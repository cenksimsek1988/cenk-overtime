#!/usr/bin/env python3
"""mail-index.py: a full-text index (SQLite FTS5) of mail archives, and its search.

    python mail-index.py measure SOURCE...
    python mail-index.py build --index INDEX [--codepage CP] SOURCE...
    python mail-index.py search --index INDEX QUERY [--folder NAME] [--sender TEXT]
                                [--since YYYY-MM-DD] [--until YYYY-MM-DD]
                                [--zone IANA] [--limit N] [--snippet]
    python mail-index.py folders --index INDEX [--zone IANA]
    python mail-index.py secrets --index INDEX [--limit N]

SOURCE is an Outlook backup (.pst), an mbox file, an .eml file or a folder of
.eml files. Sources are opened read-only and never changed.

measure  says whether the sources are worth an index: every .pst, and mbox
         or .eml sources whose message text is over 10 MB together.
build    writes a new index of all the sources: folder, times (UTC), people,
         subject, body text, attachment names and links of every message.
         Attachment contents are not indexed. INDEX must be outside the
         evidence folder: it holds other people's mail, unmasked.
search   QUERY is FTS5 syntax over the columns subject, people, body,
         attachments and links. It prints header lines only; --snippet adds
         the matching words in context, with secret-like values hidden.
folders  messages, first and last day, and attachments per folder.
secrets  the messages that hold secret-like words (password, token...):
         header lines and the word, never the value.

Standard library only, except for .pst: that needs the libpff-python package.
Exit code 0, or 1 with a message on stderr.
"""

import argparse
import datetime
import email
import email.policy
import email.utils
import hashlib
import mailbox
import os
import pathlib
import re
import shutil
import sqlite3
import sys
import tempfile
import time
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlsplit

THRESHOLD_MB = 10.0

# FTS5's unicode61 folds accents and cedillas, but not the dotless i and the
# dotted capital I of Turkish and Azerbaijani: both become plain i, in the
# index and in every query.
FOLD = {0x131: "i", 0x130: "I"}

URL = re.compile(r"https?://[^\s<>\"')\]]+", re.I)
RTF_HEX = re.compile(r"\\'([0-9a-fA-F]{2})")

# Words that announce a secret, in the plugin's six languages.
SECRET_WORD = re.compile(
    r"(?<![^\W\d_])(passwords?|passwd|pwd|passphrase|tokens?|secrets?|api[ _-]?keys?|access[ _-]?keys?|"
    r"private[ _-]?keys?|credentials?|2fa|otp|pin|parola\w*|[sş]ifre\w*|kennwort\w*|passwort\w*|"
    r"contrase[nñ]a\w*|clave\w*|mot de passe|chiave\w*)(?![^\W\d_])", re.I)
# A long run with letters and digits mixed is a key, a token or a hash. The
# mix is tested in Python: lookaheads in the pattern take hours on hostile text.
LONG_RUN = re.compile(r"[A-Za-z0-9_+/=.\-]{20,}")
URL_LOGIN = re.compile(r"(://)[^/\s:@]+:[^/\s@]+@")
HIDDEN = "[hidden]"
# Control characters and direction overrides: mail text could forge output lines with them.
UNPRINTABLE = re.compile("[\x00-\x1f\x7f-\x9f‎‏‪-‮⁦-⁩  ]")


def key_like(run):
    return any(c.isalpha() for c in run) and any(c.isdigit() for c in run)


def has_long_value(text):
    return any(key_like(match.group(0)) for match in LONG_RUN.finditer(text))


def printable(text):
    return UNPRINTABLE.sub(" ", text or "")

SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE sources(
  id INTEGER PRIMARY KEY, path TEXT NOT NULL, kind TEXT NOT NULL, bytes INTEGER, sha256 TEXT,
  messages INTEGER NOT NULL DEFAULT 0, no_text INTEGER NOT NULL DEFAULT 0, errors INTEGER NOT NULL DEFAULT 0);
CREATE TABLE messages(
  id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL,
  folder TEXT NOT NULL, position TEXT NOT NULL,       -- where to find it again in the source
  sent_utc TEXT, delivered_utc TEXT,
  sender_name TEXT, sender_email TEXT, to_list TEXT, cc_list TEXT, bcc_list TEXT,
  subject TEXT, internet_id TEXT, attachment_count INTEGER NOT NULL, body_source TEXT, body TEXT);
CREATE TABLE attachments(message_id INTEGER NOT NULL, position INTEGER NOT NULL, name TEXT, size INTEGER, mime TEXT);
CREATE TABLE links(message_id INTEGER NOT NULL, url TEXT NOT NULL);
CREATE TABLE errors(source_id INTEGER NOT NULL, folder TEXT, position TEXT, error TEXT);
CREATE VIRTUAL TABLE fts USING fts5(subject, people, body, attachments, links, tokenize = "unicode61 remove_diacritics 2");
CREATE INDEX messages_time ON messages(sent_utc);
CREATE INDEX messages_folder ON messages(folder);
CREATE INDEX attachments_message ON attachments(message_id);
CREATE INDEX links_message ON links(message_id);
"""


class Stop(Exception):
    """An error for the person: printed without a traceback."""


def fold(text):
    return (text or "").translate(FOLD)


def tidy(text):
    text = re.sub(r"[ \t\r\f\v\u00a0]+", " ", text or "")
    text = re.sub(r" ?\n ?", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


class HtmlText(HTMLParser):
    BREAK = {"p", "div", "br", "tr", "li", "table", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "hr"}
    SKIP = {"script", "style", "head", "title"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.links, self.skip = [], [], 0

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            self.skip = 0  # an unclosed <head> must not hide the body
        elif tag in self.SKIP:
            self.skip += 1
        elif tag == "a":
            for name, value in attrs:
                if name == "href" and value and value.lower().startswith(("http://", "https://")):
                    self.links.append(value)
        elif tag == "img" and not self.skip:
            # Some notices are one picture: its description is the only text.
            self.parts.extend(" %s " % value for name, value in attrs if name == "alt" and value)
        if tag in self.BREAK:
            self.parts.append("\n")
        elif tag in ("td", "th"):
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag in self.BREAK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def html_text(html):
    """(text, links) of an HTML body."""
    parser = HtmlText()
    try:
        parser.feed(html)
        parser.close()
    except Exception:  # broken markup: keep what was read
        pass
    return tidy("".join(parser.parts)), parser.links


def unwrap(url):
    """Outlook rewrites links as safelinks.protection.outlook.com/?url=<the real link>."""
    parts = urlsplit(url)
    if parts.netloc.lower().endswith("safelinks.protection.outlook.com"):
        real = parse_qs(parts.query).get("url")
        if real:
            return real[0]
    return url


def clean_links(links):
    seen, unique = set(), []
    for url in links:
        try:
            url = unwrap(url.rstrip(".,;"))
        except ValueError:
            pass
        url = url[:2000]
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def choose_body(plain, html):
    """(body_source, text, links): plain text first, else the text of the HTML."""
    plain = tidy(plain)
    text, links = html_text(html) if html else ("", [])
    links = links + URL.findall(plain)
    if plain:
        return "plain", plain, clean_links(links)
    if text:
        return "html", text, clean_links(links)
    return None, "", clean_links(links)


def label(name, address):
    name, address = (name or "").strip(), (address or "").strip()
    return "%s <%s>" % (name, address) if name and address and name != address else (name or address)


def iso(moment):
    """A datetime as UTC text; a naive one is taken as UTC."""
    if not moment:
        return None
    if moment.tzinfo is not None:
        moment = moment.astimezone(datetime.timezone.utc).replace(tzinfo=None)
    return moment.isoformat(timespec="seconds")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 22), b""):
            digest.update(block)
    return digest.hexdigest()


# --- sources: each reader yields ("message", dict) or ("error", folder, position, text)

def kind_of(path):
    if os.path.isdir(path):
        return "eml"
    if not os.path.isfile(path):
        raise Stop("not found: %s" % path)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".pst", ".ost"):
        return "pst"
    if ext == ".eml":
        return "eml"
    return "mbox"


def header_date(message):
    value = message.get("Date")
    try:
        return iso(email.utils.parsedate_to_datetime(str(value))) if value else None
    except (TypeError, ValueError):
        return None


def addresses(message, header):
    pairs = email.utils.getaddresses([str(v) for v in message.get_all(header, [])])
    return [label(name, address) for name, address in pairs if name or address]


def from_email(message, folder, position):
    """One message dict from an email.message.EmailMessage."""
    plain, html, attachments = [], [], []
    for part in message.walk():
        if part.is_multipart():
            continue
        name = part.get_filename()
        if name or part.get_content_disposition() == "attachment":
            payload = part.get_payload(decode=True) or b""
            attachments.append((name, len(payload), part.get_content_type()))
        elif part.get_content_type() in ("text/plain", "text/html"):
            try:
                content = part.get_content()
            except (LookupError, UnicodeError, ValueError):
                content = (part.get_payload(decode=True) or b"").decode("utf-8", "replace")
            (plain if part.get_content_type() == "text/plain" else html).append(content)
    source, body, links = choose_body("\n".join(plain), "\n".join(html))
    sender = addresses(message, "From")
    name, address = email.utils.parseaddr(str(message.get("From", "")))
    return {
        "folder": folder, "position": position, "sent_utc": header_date(message), "delivered_utc": None,
        "sender_name": name or (sender[0] if sender else ""), "sender_email": address,
        "to": addresses(message, "To"), "cc": addresses(message, "Cc"), "bcc": addresses(message, "Bcc"),
        "subject": str(message.get("Subject", "") or ""), "internet_id": str(message.get("Message-ID", "") or "").strip(),
        "body_source": source, "body": body, "links": links, "attachments": attachments,
    }


def read_mbox(path, codepage):
    box = mailbox.mbox(path, create=False)
    try:
        for key in box.iterkeys():
            try:
                message = email.message_from_bytes(box.get_bytes(key), policy=email.policy.default)
                # Google Takeout keeps the labels of each message in this header.
                yield "message", from_email(message, str(message.get("X-Gmail-Labels", "") or ""), str(key))
            except Exception as error:
                yield "error", "", str(key), repr(error)
    finally:
        box.close()


def read_eml(path, codepage):
    if os.path.isfile(path):
        files = [(path, os.path.basename(path))]
    else:
        files = []
        for root, dirs, names in os.walk(path):
            dirs.sort()
            for name in sorted(names):
                if name.lower().endswith(".eml"):
                    full = os.path.join(root, name)
                    files.append((full, os.path.relpath(full, path).replace(os.sep, "/")))
    for full, relative in files:
        folder = relative.rsplit("/", 1)[0] if "/" in relative else ""
        try:
            with open(full, "rb") as handle:
                message = email.message_from_binary_file(handle, policy=email.policy.default)
            yield "message", from_email(message, folder, relative)
        except Exception as error:
            yield "error", folder, relative, repr(error)


# MAPI property ids, as libpff names them in entry_type.
PST_SENDER_NAME = (0x0C1A, 0x0042)                    # sender name, sent-representing name
PST_SENDER_EMAIL = (0x5D01, 0x5D02, 0x0C1F, 0x0065)   # SMTP addresses first, then the address fields
PST_INTERNET_ID = 0x1035
PST_DISPLAY_NAME, PST_SMTP, PST_EMAIL, PST_RECIPIENT_TYPE = 0x3001, 0x39FE, 0x3003, 0x0C15
PST_LONG_NAME, PST_SHORT_NAME, PST_MIME = 0x3707, 0x3704, 0x370E


def decode(data, codepage):
    if data is None:
        return ""
    if isinstance(data, str):
        return data.replace("\x00", "")
    for encoding in ("utf-8", codepage):
        try:
            return data.decode(encoding).replace("\x00", "")
        except (UnicodeDecodeError, LookupError):
            pass
    return data.decode("utf-8", "replace").replace("\x00", "")


def rtf_text(data, codepage):
    text = decode(data, codepage)
    text = RTF_HEX.sub(lambda m: bytes([int(m.group(1), 16)]).decode(codepage, "replace"), text)
    text = re.sub(r"\\par[d]?\b", "\n", text)
    text = re.sub(r"\\[a-zA-Z]+-?\d* ?", "", text)
    return tidy(text.replace("{", "").replace("}", "").replace("\\", ""))


def record_set_values(record_set, strings, integers=()):
    out = {}
    for e in range(record_set.number_of_entries):
        entry = record_set.get_entry(e)
        kind = entry.entry_type
        try:
            if kind in strings:
                value = entry.data_as_string
                if value:
                    out.setdefault(kind, value)
            elif kind in integers:
                out.setdefault(kind, entry.data_as_integer)
        except Exception:  # an entry without data: skip it
            pass
    return out


def item_values(item, strings):
    out = {}
    for s in range(item.number_of_record_sets):
        for kind, value in record_set_values(item.get_record_set(s), strings).items():
            out.setdefault(kind, value)
    return out


def pst_part(message, name):
    # A message without this body raises "missing value data": no body, not a read error.
    try:
        return getattr(message, name)
    except Exception:
        return None


def pst_recipients(message):
    lists = {1: [], 2: [], 3: []}  # to, cc, bcc
    try:
        table = message.recipients
        count = table.number_of_record_sets if table else 0
    except Exception:
        return lists
    for i in range(count):  # one record set per recipient
        try:
            p = record_set_values(table.get_record_set(i), {PST_DISPLAY_NAME, PST_SMTP, PST_EMAIL},
                                  {PST_RECIPIENT_TYPE})
        except Exception:
            continue
        who = label(p.get(PST_DISPLAY_NAME), p.get(PST_SMTP) or p.get(PST_EMAIL))
        if who:
            lists.get(p.get(PST_RECIPIENT_TYPE), lists[1]).append(who)
    return lists


def from_pst(message, folder, position, codepage):
    p = item_values(message, set(PST_SENDER_NAME + PST_SENDER_EMAIL) | {PST_INTERNET_ID})
    source, body, links = choose_body(decode(pst_part(message, "plain_text_body"), codepage),
                                      decode(pst_part(message, "html_body"), codepage))
    if not body:
        rtf = pst_part(message, "rtf_body")
        if rtf:
            source, body = "rtf", rtf_text(rtf, codepage)
            source = source if body else None
    attachments, problems = [], []
    count = message.number_of_attachments
    for a in range(count):
        try:
            attachment = message.get_attachment(a)
            ap = item_values(attachment, {PST_LONG_NAME, PST_SHORT_NAME, PST_MIME})
            attachments.append((ap.get(PST_LONG_NAME) or ap.get(PST_SHORT_NAME), attachment.size, ap.get(PST_MIME)))
        except Exception as error:
            attachments.append((None, None, None))
            problems.append("attachment %d: %r" % (a, error))
    people = pst_recipients(message)
    first = lambda ids: next((p[i] for i in ids if p.get(i)), "")
    return {
        "folder": folder, "position": str(position),
        "sent_utc": iso(message.client_submit_time), "delivered_utc": iso(message.delivery_time),
        "sender_name": first(PST_SENDER_NAME), "sender_email": first(PST_SENDER_EMAIL),
        "to": people[1], "cc": people[2], "bcc": people[3],
        "subject": message.subject or "", "internet_id": p.get(PST_INTERNET_ID, ""),
        "body_source": source, "body": body, "links": links, "attachments": attachments, "problems": problems,
    }


def read_pst(path, codepage):
    try:
        import pypff
    except ImportError:
        raise Stop("an Outlook backup needs the libpff-python package: run the tools check with --pst")
    handle = open(path, "rb")
    backup = pypff.file()
    try:
        # Opened from a file object: the path-based open fails on Windows.
        backup.open_file_object(handle)
    except Exception as error:
        handle.close()
        raise Stop("cannot read %s as an Outlook backup (%s)" % (path, error))
    try:
        stack = [(backup.root_folder, "")]
        while stack:
            folder, name = stack.pop()
            for position in range(folder.number_of_sub_messages):
                try:
                    yield "message", from_pst(folder.get_sub_message(position), name, position, codepage)
                except Exception as error:
                    yield "error", name, str(position), repr(error)
            subs = [folder.get_sub_folder(i) for i in range(folder.number_of_sub_folders)]
            stack.extend((sub, "%s/%s" % (name, sub.name or "?")) for sub in reversed(subs))
    finally:
        backup.close()
        handle.close()


READERS = {"pst": read_pst, "mbox": read_mbox, "eml": read_eml}


def source_bytes(path):
    if os.path.isfile(path):
        return os.path.getsize(path)
    return sum(os.path.getsize(os.path.join(root, name)) for root, _, names in os.walk(path) for name in names)


# --- measure

def measure(args):
    rows, text_bytes, pst = [], 0, False
    for path in args.sources:
        kind = kind_of(path)
        if kind == "pst":
            # Its text cannot be measured without reading all of it, which costs as much as the build.
            pst = True
            rows.append((kind, None, None, path))
            continue
        messages = size = 0
        for item in READERS[kind](path, args.codepage):
            if item[0] == "message":
                messages += 1
                size += len((item[1]["subject"] + item[1]["body"]).encode("utf-8"))
        text_bytes += size
        rows.append((kind, messages, size, path))
    for kind, messages, size, path in rows:
        if kind == "pst":
            print("pst   messages ?        text ?           %s" % path)
        else:
            print("%-5s messages %-8d text %8.1f MB  %s" % (kind, messages, size / 1e6, path))
    wanted = pst or text_bytes > args.threshold_mb * 1e6
    reason = "an Outlook backup" if pst else "%.1f MB of text, threshold %g MB" % (text_bytes / 1e6, args.threshold_mb)
    print("index: %s (%s)" % ("yes" if wanted else "no", reason))
    return 0


# --- build

def refuse_shared(target):
    """The index holds unmasked mail: it never goes where the lawyers read."""
    # realpath: a link or junction under work/ must not lead into the evidence folder.
    for part in os.path.realpath(target).replace("\\", "/").split("/")[:-1]:
        if part.lower().endswith("-evidence") or part.lower() in ("for-lawyer", "4_raw_data"):
            raise Stop("the index must not be in the evidence folder (%s): put it in the case's work folder" % part)


def store(db, source_id, m):
    people = [m["to"], m["cc"], m["bcc"]]
    to_list, cc_list, bcc_list = ("; ".join(p) for p in people)
    row = db.execute(
        "INSERT INTO messages(source_id, folder, position, sent_utc, delivered_utc, sender_name, sender_email,"
        " to_list, cc_list, bcc_list, subject, internet_id, attachment_count, body_source, body)"
        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (source_id, m["folder"], m["position"], m["sent_utc"], m["delivered_utc"], m["sender_name"],
         m["sender_email"], to_list, cc_list, bcc_list, m["subject"], m["internet_id"], len(m["attachments"]),
         m["body_source"], m["body"])).lastrowid
    db.executemany("INSERT INTO attachments VALUES (?,?,?,?,?)",
                   [(row, i, name, size, mime) for i, (name, size, mime) in enumerate(m["attachments"])])
    db.executemany("INSERT INTO links VALUES (?,?)", [(row, url) for url in m["links"]])
    db.execute("INSERT INTO fts(rowid, subject, people, body, attachments, links) VALUES (?,?,?,?,?,?)",
               (row, fold(m["subject"]),
                fold(" ".join([m["sender_name"], m["sender_email"], to_list, cc_list, bcc_list])),
                fold(m["body"]), fold(" ".join(name or "" for name, _, _ in m["attachments"])), " ".join(m["links"])))
    for problem in m.get("problems", ()):
        db.execute("INSERT INTO errors VALUES (?,?,?,?)", (source_id, m["folder"], m["position"], problem))


def build(args):
    target = os.path.abspath(args.index)
    refuse_shared(target)
    kinds = [(path, kind_of(path)) for path in args.sources]
    os.makedirs(os.path.dirname(target), exist_ok=True)
    # Built in the system temp folder: a synced folder would upload the half-written file.
    scratch = tempfile.mkdtemp(prefix="mail-index.")
    building = os.path.join(scratch, "index.sqlite")
    started = time.time()
    db = None
    try:
        db = sqlite3.connect(building)
        try:
            db.executescript(SCHEMA)
        except sqlite3.OperationalError as error:
            raise Stop("this Python's SQLite has no FTS5 (%s): search the archive without an index" % error)
        for path, kind in kinds:
            source_id = db.execute("INSERT INTO sources(path, kind) VALUES (?,?)",
                                   (os.path.abspath(path), kind)).lastrowid
            messages = no_text = errors = 0
            for item in READERS[kind](path, args.codepage):
                if item[0] == "error":
                    errors += 1
                    db.execute("INSERT INTO errors VALUES (?,?,?,?)", (source_id,) + item[1:])
                    continue
                store(db, source_id, item[1])
                messages += 1
                no_text += not item[1]["body"]
                if messages % 2000 == 0:
                    db.commit()
                    print("%s: %d messages" % (os.path.basename(path), messages), flush=True)
            errors += db.execute("SELECT count(*) FROM errors WHERE source_id = ? AND error LIKE 'attachment %'",
                                 (source_id,)).fetchone()[0]
            digest = sha256(path) if os.path.isfile(path) else None
            db.execute("UPDATE sources SET bytes = ?, sha256 = ?, messages = ?, no_text = ?, errors = ? WHERE id = ?",
                       (source_bytes(path), digest, messages, no_text, errors, source_id))
            db.commit()
        db.execute("INSERT INTO fts(fts) VALUES ('optimize')")
        totals = db.execute("SELECT coalesce(sum(messages), 0), coalesce(sum(no_text), 0), coalesce(sum(errors), 0)"
                            " FROM sources").fetchone()
        meta = {"built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "sqlite": sqlite3.sqlite_version,
                "times": "UTC", "attachment_text": "not indexed", "codepage": args.codepage}
        db.executemany("INSERT INTO meta VALUES (?,?)", list(meta.items()))
        db.execute("ANALYZE")
        db.commit()
        rows = db.execute("SELECT kind, messages, no_text, errors, sha256, path FROM sources ORDER BY id").fetchall()
        db.close()
        db = None
        shutil.move(building, target)
    finally:
        # Closed first: Windows cannot delete an open file, and a half-built index holds unmasked mail.
        if db is not None:
            db.close()
        shutil.rmtree(scratch, ignore_errors=True)
        if os.path.exists(scratch):
            print("mail-index: could not delete %s: delete it by hand, it holds mail text" % scratch, file=sys.stderr)
    for kind, messages, no_text, errors, digest, path in rows:
        print("%-5s messages %d, without text %d, read errors %d, sha256 %s  %s"
              % (kind, messages, no_text, errors, digest or "-", path))
    print("built in %.0f s: %d messages, %d without text, %d read errors; attachment contents are not indexed"
          % ((time.time() - started,) + tuple(totals)))
    return 0


# --- search, folders, secrets

def open_index(path):
    if not os.path.isfile(path):
        raise Stop("no index at %s: run build first" % path)
    # as_uri escapes ? and #, which would cut the address short and drop the read-only mode.
    return sqlite3.connect(pathlib.Path(os.path.abspath(path)).as_uri() + "?mode=ro", uri=True)


def zone_of(name):
    if not name:
        return datetime.timezone.utc
    import zoneinfo
    try:
        return zoneinfo.ZoneInfo(name)
    except (zoneinfo.ZoneInfoNotFoundError, ValueError):
        raise Stop("unknown time zone %s (on Windows the tzdata package holds the zones)" % name)


def local_time(utc_text, zone):
    if not utc_text:
        return ""
    moment = datetime.datetime.fromisoformat(utc_text).replace(tzinfo=datetime.timezone.utc)
    return moment.astimezone(zone).strftime("%Y-%m-%d %H:%M")


def day_start_utc(day, zone, add_days=0):
    try:
        moment = datetime.datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=zone) + datetime.timedelta(days=add_days)
    except ValueError:
        raise Stop("not a date (YYYY-MM-DD): %s" % day)
    return iso(moment)


def hide_secrets(text):
    """A snippet with the values that look like secrets replaced."""
    text = URL_LOGIN.sub(r"\1" + HIDDEN + "@", text)
    text = LONG_RUN.sub(lambda match: HIDDEN if key_like(match.group(0)) else match.group(0), text)
    out, hide = [], 0
    for word in text.split():
        if hide and word not in (">>", "<<"):
            hide -= 1
            if not SECRET_WORD.search(word):
                word = HIDDEN
        if SECRET_WORD.search(word):
            hide = 4  # "password is: <value>", "token = <value>"
        out.append(word)
    line = " ".join(out)
    return re.sub(r"(%s ?)+" % re.escape(HIDDEN), HIDDEN + " ", line).strip()


def limits_line(db):
    messages, no_text = db.execute("SELECT coalesce(sum(messages), 0), coalesce(sum(no_text), 0) FROM sources").fetchone()
    return ("Searched: subject, people, body text, attachment names and links of %d messages."
            " Not searched: attachment contents; %d messages have no text." % (messages, no_text))


def header_line(row_id, when, folder, sender, to, subject, attachments):
    # A subject can carry a secret too ("your code is ..."): it is hidden like a snippet.
    return printable("#%d | %s | %s | %s -> %s | %s | %s" % (
        row_id, when, (folder or "").rsplit("/", 1)[-1], sender or "", (to or "")[:60],
        hide_secrets(printable(subject)[:80]), (attachments or "")[:120]))


ATTACHMENT_NAMES = "(SELECT group_concat(name, '; ') FROM attachments a WHERE a.message_id = m.id)"
WHEN = "coalesce(m.sent_utc, m.delivered_utc)"


def search(args):
    zone = zone_of(args.zone)
    where, values = ["fts MATCH ?"], [fold(args.query)]
    if args.folder:
        # No LIKE: an underscore or a percent sign in a name must match only itself.
        where.append("(m.folder = ? OR substr(m.folder, -length(?)) = ?)")
        values += [args.folder, "/" + args.folder, "/" + args.folder]
    if args.sender:
        where.append("(instr(lower(m.sender_name), lower(?)) OR instr(lower(m.sender_email), lower(?)))")
        values += [args.sender] * 2
    if args.since:
        where.append(WHEN + " >= ?")
        values.append(day_start_utc(args.since, zone))
    if args.until:
        where.append(WHEN + " < ?")
        values.append(day_start_utc(args.until, zone, 1))
    joined = "FROM fts JOIN messages m ON m.id = fts.rowid WHERE " + " AND ".join(where)
    db = open_index(args.index)
    try:
        total = db.execute("SELECT count(*) " + joined, values).fetchone()[0]
        rows = db.execute(
            "SELECT m.id, %s, m.folder, m.sender_name, m.to_list, m.subject, %s,"
            " snippet(fts, 2, '>> ', ' <<', ' ... ', 16) %s ORDER BY %s LIMIT ?" % (WHEN, ATTACHMENT_NAMES, joined, WHEN),
            values + [args.limit]).fetchall()
    except sqlite3.OperationalError as error:
        raise Stop("the query is not valid FTS5 (%s)" % error)
    print("%d messages match; showing %d; times in %s" % (total, len(rows), args.zone or "UTC"))
    for row in rows:
        print(header_line(row[0], local_time(row[1], zone), *row[2:7]))
        if args.snippet:
            print("    " + hide_secrets(" ".join(printable(row[7]).split())))
    print(limits_line(db))
    return 0


def folders(args):
    zone = zone_of(args.zone)
    db = open_index(args.index)
    rows = db.execute(
        "SELECT m.folder, count(*), min(%s), max(%s), sum(m.attachment_count > 0), sum(m.attachment_count),"
        " sum(m.body = '') FROM messages m GROUP BY m.folder ORDER BY m.folder" % (WHEN, WHEN)).fetchall()
    for folder, count, first, last, with_attachments, attachments, no_text in rows:
        print("%-50s messages %6d  %s .. %s  with attachments %5d  attachments %6d  without text %5d"
              % (printable(folder) or "(none)", count, local_time(first, zone)[:10], local_time(last, zone)[:10],
                 with_attachments, attachments, no_text))
    print(limits_line(db))
    return 0


def secrets(args):
    db = open_index(args.index)
    found = 0
    rows = db.execute("SELECT m.id, %s, m.folder, m.sender_name, m.to_list, m.subject, %s, m.body FROM messages m"
                      " ORDER BY %s" % (WHEN, ATTACHMENT_NAMES, WHEN))
    for row in rows:
        text = (row[5] or "") + "\n" + (row[7] or "")
        words = sorted({match.group(1).lower() for match in SECRET_WORD.finditer(text)})
        # Links written out in the text carry long ids: only a long value outside a link counts.
        if has_long_value(URL.sub(" ", row[7] or "")):
            words.append("long key-like value")
        if URL_LOGIN.search(text):
            words.append("login in a link")
        if not words:
            continue
        found += 1
        if found <= args.limit:
            print(header_line(row[0], local_time(row[1], datetime.timezone.utc), *row[2:7]))
            print("    secret-like: " + ", ".join(words))
    print("%d messages hold secret-like words or values; showing %d. Values are never printed."
          % (found, min(found, args.limit)))
    return 0


def main():
    parser = argparse.ArgumentParser(description="A full-text index of mail archives, and its search.")
    sub = parser.add_subparsers(dest="command", required=True)

    def command(name, function, index=True):
        p = sub.add_parser(name)
        p.set_defaults(function=function)
        if index:
            p.add_argument("--index", required=True, help="the index file, outside the evidence folder")
        return p

    def sources(p):
        p.add_argument("--codepage", default="cp1252",
                       help="Windows code page of old messages without Unicode text, such as cp1254 for Turkish")
        p.add_argument("sources", nargs="+", metavar="SOURCE", help=".pst, mbox, .eml or a folder of .eml files")

    p = command("measure", measure, index=False)
    p.add_argument("--threshold-mb", type=float, default=THRESHOLD_MB, help="index above this much message text")
    sources(p)
    sources(command("build", build))
    p = command("search", search)
    p.add_argument("query", help="FTS5 query")
    p.add_argument("--folder", help="folder name, or the last part of its path")
    p.add_argument("--sender", help="part of the sender's name or address")
    p.add_argument("--since", help="first day, YYYY-MM-DD, in --zone")
    p.add_argument("--until", help="last day, YYYY-MM-DD, in --zone")
    p.add_argument("--zone", help="IANA time zone for the times shown and the days given (default: UTC)")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--snippet", action="store_true", help="add the matching words in context, secrets hidden")
    command("folders", folders).add_argument("--zone", help="IANA time zone for the days shown (default: UTC)")
    command("secrets", secrets).add_argument("--limit", type=int, default=200)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    try:
        return args.function(args)
    except Stop as error:
        print("mail-index: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
