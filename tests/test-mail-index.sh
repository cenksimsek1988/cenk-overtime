#!/bin/sh
# Tests mail-index.py on a made-up mailbox: an mbox, a folder of .eml files and
# an Outlook backup read through a stub of the libpff-python package. Not part
# of the skill.
#
#   sh tests/test-mail-index.sh [SKILL_DIR]
#
# SKILL_DIR defaults to ../cenk-overtime/skills/collect. Everything goes to a
# new folder in the system temp folder, deleted when every check passes.
set -eu

T=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(cd "${1:-$T/../cenk-overtime/skills/collect}/scripts" && pwd)/mail-index.py
W=$(mktemp -d "${TMPDIR:-/tmp}/test-mail-index.XXXXXX")

PY=''
for p in python3 python py; do
	# Windows has a python3 stub that only opens the Store: try each one.
	if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys' >/dev/null 2>&1; then
		PY=$(command -v "$p")
		break
	fi
done
[ -n "$PY" ] || { echo 'no Python 3 found' >&2; exit 1; }

case $(uname -s) in
	MINGW* | MSYS* | CYGWIN*) WIN=1 ;;
	*) WIN=0 ;;
esac
# Native Windows programs need Windows paths in variables and arguments.
native() { if [ "$WIN" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# Made-up secret values: the tests check that no output ever shows them.
PW='correct-horse-42'
TOKEN=$(printf 'A1b2C3d4%.0s' 1 2 3 4)

mkdir -p "$W/src/eml/team" "$W/stub" "$W/case/work" "$W/case/acme-2024-evidence/4_Raw_Data"

"$PY" - "$(native "$W/src")" "$PW" "$TOKEN" <<'EOF'
import mailbox, sys
from email.message import EmailMessage
from email.generator import BytesGenerator

src, pw, token = sys.argv[1:4]
ADA, GRACE = "Ada Lovelace <ada@example.com>", "Grace Hopper <grace@example.com>"


def mail(sender, to, subject, date, label, text=None, html=None, attachment=None):
    m = EmailMessage()
    m["From"], m["To"], m["Subject"], m["Date"] = sender, to, subject, date
    m["Message-ID"] = "<%s@example.com>" % date[5:25].replace(" ", "-").replace(":", "")
    m["X-Gmail-Labels"] = label
    if text is not None:
        m.set_content(text)
    if html is not None:
        m.set_content(html, subtype="html")
    if attachment:
        m.add_attachment(b"made-up bytes", maintype="application", subtype="octet-stream", filename=attachment)
    return m


SAFELINK = ("https://eur01.safelinks.protection.outlook.com/"
            "?url=https%3A%2F%2Ffiles.example.org%2Fforms%2Fclaim.xlsx&amp;data=05")
box = mailbox.mbox(src + "/sent.mbox")
for m in [
    mail(ADA, GRACE, "Release notes", "Tue, 05 Mar 2024 22:30:00 +0300", "Sent",
         text="The ışık report is ready. Toplantı yarın.\n"),
    mail(ADA, GRACE, "Weekly sync", "Wed, 06 Mar 2024 00:30:00 +0300", "Sent",
         text="Please check the reimbursement for the tools I paid for.\n", attachment="expenses-march.xlsx"),
    mail(GRACE, ADA, "Form", "Thu, 07 Mar 2024 10:00:00 +0300", "Inbox",
         html='<html><head><style>p{color:red}</style></head><body><p>Please open the <a href="%s">form</a>.</p>'
              '<img src="x.png" alt="Maintenance window notice"></body></html>' % SAFELINK),
    mail(GRACE, ADA, "Empty", "Fri, 08 Mar 2024 10:00:00 +0300", "Inbox", text=""),
    mail(GRACE, ADA, "Access", "Sat, 09 Mar 2024 10:00:00 +0300", "Inbox",
         text="The staging pass" + "word is: %s and the token %s works.\n" % (pw, token)),
]:
    box.add(m)
box.close()

with open(src + "/eml/team/move.eml", "wb") as handle:
    BytesGenerator(handle).flatten(mail(
        ADA, GRACE, "İstanbul office move", "Mon, 11 Mar 2024 09:15:00 +0300", "",
        text="Çağrı merkezi taşınıyor.\n"))
# A sender controls this text: an escape sequence in the subject, and a long run that a slow pattern chokes on.
with open(src + "/hostile.eml", "wb") as handle:
    handle.write(b"From: Grace Hopper <grace@example.com>\r\nTo: ada@example.com\r\n"
                 b"Subject: =?utf-8?q?Reset=1B[2J_now?=\r\nDate: Thu, 14 Mar 2024 09:00:00 +0000\r\n"
                 b"Content-Type: text/plain; charset=utf-8\r\n\r\n" + b"a" * 50000 + b" zebra\r\n")
with open(src + "/backup.pst", "wb") as handle:
    handle.write(b"not a real backup: the stub reader ignores it\n")
EOF

# A stand-in for libpff-python with the calls mail-index.py makes.
cat >"$W/stub/pypff.py" <<'EOF'
import datetime


class Entry:
    def __init__(self, kind, value):
        self.entry_type = kind
        self.data_as_string = value if isinstance(value, str) else None
        self.data_as_integer = value if isinstance(value, int) else None


class RecordSet:
    def __init__(self, values):
        self.entries = [Entry(k, v) for k, v in values.items()]
        self.number_of_entries = len(self.entries)

    def get_entry(self, i):
        return self.entries[i]


class Item:
    size = 13

    def __init__(self, *sets):
        self.sets = [RecordSet(s) for s in sets]
        self.number_of_record_sets = len(self.sets)

    def get_record_set(self, i):
        return self.sets[i]


class Message(Item):
    def __init__(self, subject, sent, plain, recipients=(), attachments=()):
        super().__init__({0x0C1A: "Ada Lovelace", 0x5D01: "ada@example.com", 0x1035: "<%s@example.com>" % subject})
        self.subject, self.client_submit_time, self.delivery_time, self.plain = subject, sent, None, plain
        self.recipients = Item(*recipients)
        self.attached = [Item({0x3707: name}) for name in attachments]
        self.number_of_attachments = len(self.attached)

    def get_attachment(self, i):
        return self.attached[i]

    @property
    def plain_text_body(self):
        if self.plain is None:
            raise OSError("pypff_message_get_plain_text_body: unable to retrieve plain text body: missing value data.")
        return self.plain

    @property
    def html_body(self):
        raise OSError("missing value data.")

    rtf_body = html_body


class Folder:
    def __init__(self, name, messages=(), folders=()):
        self.name, self.messages, self.folders = name, list(messages), list(folders)
        self.number_of_sub_messages, self.number_of_sub_folders = len(self.messages), len(self.folders)

    def get_sub_message(self, i):
        return self.messages[i]

    def get_sub_folder(self, i):
        return self.folders[i]


class file:
    def open(self, path):
        raise OSError("unable to open file.")

    def open_file_object(self, handle):
        handle.read(1)
        sent = Folder("Sent Items", [
            Message("Deploy tonight", datetime.datetime(2024, 3, 12, 20, 5, 0),
                    "Deploying the billing service now.".encode("utf-8"),
                    recipients=[{0x3001: "Grace Hopper", 0x39FE: "grace@example.com", 0x0C15: 1},
                                {0x3001: "Alan Turing", 0x39FE: "alan@example.com", 0x0C15: 2}],
                    attachments=["runbook.pdf"]),
            Message("Picture only", datetime.datetime(2024, 3, 13, 8, 0, 0), None),
        ])
        self.root_folder = Folder(None, folders=[Folder("Top", folders=[sent])])

    def close(self):
        pass
EOF

INDEX="$W/case/work/mail-index/mail.sqlite"
# run ARGS: the script with the stub reader; output in $W/out.txt, errors in $W/err.txt.
run() {
	set +e
	env PYTHONPATH="$(native "$W/stub")" "$PY" "$SCRIPT" "$@" >"$W/out.txt" 2>"$W/err.txt"
	code=$?
	set -e
}
s() { run search --index "$(native "$INDEX")" "$@"; }
# ids: the message subjects of the last search, in order.
subjects() { grep '^#' "$W/out.txt" | awk -F ' [|] ' '{print $5}' | tr '\n' ',' | sed 's/,$//'; }
count() { grep -c -- "$1" "$W/out.txt" || true; }
# q SQL: one value from the index.
q() {
	"$PY" -c 'import sqlite3, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])' "$(native "$INDEX")" "$1"
}
hash_of() {
	"$PY" -c 'import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$(native "$1")"
}

fails=0
check() {
	if [ "$2" = "$3" ]; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
		fails=$((fails + 1))
	fi
}

MBOX=$(native "$W/src/sent.mbox")
EML=$(native "$W/src/eml")
PST=$(native "$W/src/backup.pst")

echo '--- measure'
run measure "$MBOX" "$EML"
check 'measure: exit code' 0 "$code"
check 'measure: small sources need no index' 1 "$(count '^index: no')"
check 'measure: message counts' 'mbox:5,eml:1' "$(awk '$2 == "messages" {printf "%s%s:%s", sep, $1, $3; sep = ","}' "$W/out.txt")"
run measure --threshold-mb 0.0001 "$MBOX" "$EML"
check 'measure: over the threshold' 1 "$(count '^index: yes')"
run measure "$PST"
check 'measure: an Outlook backup is always indexed' 1 "$(count '^index: yes (an Outlook backup)')"
run measure "$(native "$W/src/missing.mbox")"
check 'measure: a missing source stops' '1|1' "$code|$(grep -c '^mail-index: not found' "$W/err.txt")"

echo '--- build'
before=$(hash_of "$W/src/sent.mbox")
run build --index "$(native "$W/case/acme-2024-evidence/4_Raw_Data/mail.sqlite")" "$MBOX"
check 'build: refuses the evidence folder' '1|1' "$code|$(grep -c 'must not be in the evidence folder' "$W/err.txt")"
check 'build: nothing written there' 0 "$(find "$W/case/acme-2024-evidence" -type f | wc -l | tr -d ' ')"
run build --index "$(native "$INDEX")" "$MBOX" "$EML" "$PST"
check 'build: exit code' 0 "$code"
check 'build: no errors printed' 0 "$(wc -c <"$W/err.txt" | tr -d ' ')"
check 'build: summary line' 1 "$(count '8 messages, 2 without text, 0 read errors; attachment contents are not indexed')"
check 'build: sources' 'mbox:5:1,eml:1:0,pst:2:1' "$(q "SELECT group_concat(kind || ':' || messages || ':' || no_text) FROM sources")"
check 'build: source hash recorded' "$before" "$(q "SELECT sha256 FROM sources WHERE kind = 'mbox'")"
check 'build: source unchanged' "$before" "$(hash_of "$W/src/sent.mbox")"
check 'build: times in UTC' '2024-03-05T19:30:00' "$(q "SELECT sent_utc FROM messages WHERE subject = 'Release notes'")"
check 'build: nothing left beside the index' 'mail.sqlite' "$(ls "$W/case/work/mail-index" | tr '\n' ' ' | sed 's/ $//')"
check 'build: no secret in what it printed' 0 "$(count "$PW")"

echo '--- search'
s 'reimbursement'
check 'a word only in the body' 'Weekly sync' "$(subjects)"
check 'header lines only by default' 0 "$(count 'paid for')"
check 'attachment names on the line' 1 "$(count 'expenses-march.xlsx')"
check 'the limits line' 1 "$(count '^Searched: .* of 8 messages. Not searched: attachment contents; 2 messages have no text.')"
s 'isik'
check 'dotless i found by plain i' 'Release notes' "$(subjects)"
s "$(printf '\304\261\305\237\304\261k')"
check 'dotless i in the query' 'Release notes' "$(subjects)"
s 'istanbul AND cagri'
check 'dotted capital I and other Turkish letters' "$(printf '\304\260stanbul office move')" "$(subjects)"
s 'attachments: xlsx'
check 'attachment name column' 'Weekly sync' "$(subjects)"
s 'links: "files.example.org"'
check 'a wrapped link is indexed by its target' 'Form' "$(subjects)"
check 'the wrapper is gone' 0 "$(q "SELECT count(*) FROM links WHERE url LIKE '%safelinks%'")"
s 'maintenance'
check 'image description of an HTML-only mail' 'Form' "$(subjects)"
s 'color'
check 'style text is not indexed' '0' "$(sed -n 's/^\([0-9]*\) messages match.*/\1/p' "$W/out.txt")"
s 'people: hopper' --folder Sent
check 'people column and --folder' 'Release notes,Weekly sync' "$(subjects)"
s 'people: lovelace' --sender grace
check '--sender' 'Form,Empty,Access' "$(subjects)"
s 'people: ada' --since 2024-03-06 --until 2024-03-06 --zone Europe/Istanbul
check 'days in the contract zone' 'Weekly sync' "$(subjects)"
check 'times in the contract zone' 1 "$(count '| 2024-03-06 00:30 |')"
s 'people: ada' --since 2024-03-06 --until 2024-03-06
check 'days in UTC without --zone' '' "$(subjects)"
s 'people: ada' --limit 2
check '--limit' '8|2' "$(sed -n 's/^\([0-9]*\) messages match; showing \([0-9]*\).*/\1|\2/p' "$W/out.txt")"
s 'AND AND'
check 'a broken query stops' '1|1' "$code|$(grep -c '^mail-index: the query is not valid' "$W/err.txt")"

echo '--- secrets'
s 'staging' --snippet
check 'snippet shows the match' 1 "$(count '>> staging <<')"
check 'snippet hides the values' '1|0|0' "$(count '\[hidden\]')|$(count "$PW")|$(count "$TOKEN")"
s 'reimbursement' --snippet
check 'snippet without secrets is whole' 1 "$(count 'the >> reimbursement << for the tools')"
run secrets --index "$(native "$INDEX")"
check 'secrets: the mail is listed' 'Access' "$(subjects)"
check 'secrets: the words, not the values' '1|0|0' "$(count 'secret-like: .*password')|$(count "$PW")|$(count "$TOKEN")"
check 'secrets: count line' 1 "$(count '^1 messages hold secret-like')"

echo '--- Outlook backup'
s 'billing'
check 'pst: body text' 'Deploy tonight' "$(subjects)"
check 'pst: folder and recipients' 1 "$(count '| Sent Items | Ada Lovelace -> Grace Hopper <grace@example.com> |')"
check 'pst: cc recipients' 'Alan Turing <alan@example.com>' "$(q "SELECT cc_list FROM messages WHERE subject = 'Deploy tonight'")"
check 'pst: attachment name' 'runbook.pdf' "$(q "SELECT name FROM attachments a JOIN messages m ON m.id = a.message_id WHERE m.subject = 'Deploy tonight'")"
check 'pst: a message without a body is no error' '|0' "$(q "SELECT body || '|' || (SELECT count(*) FROM errors) FROM messages WHERE subject = 'Picture only'")"
check 'pst: folder path' '/Top/Sent Items' "$(q "SELECT DISTINCT folder FROM messages WHERE source_id = 3")"
set +e
"$PY" -S "$SCRIPT" build --index "$(native "$W/case/work/other.sqlite")" "$PST" >"$W/out.txt" 2>"$W/err.txt"
code=$?
set -e
check 'pst: without the reader package it says what to do' '1|1' "$code|$(grep -c 'run the tools check with --pst' "$W/err.txt")"

echo '--- hostile text'
HOSTILE="$W/case/work/mail-index/hostile #1.sqlite"
run build --index "$(native "$HOSTILE")" "$(native "$W/src/hostile.eml")"
check 'hostile: build' 0 "$code"
run search --index "$(native "$HOSTILE")" zebra --snippet
check 'hostile: found, index path with # and a space' '0|1' "$code|$(count '^1 messages match')"
check 'hostile: no escape character printed' 0 "$(tr -cd '\033' <"$W/out.txt" | wc -c | tr -d ' ')"
run secrets --index "$(native "$HOSTILE")"
check 'hostile: a long run of one letter is quick and no secret' '0|1' "$code|$(count '^0 messages hold')"
s 'people: ada' --sender 'gr_ce'
check '--sender takes an underscore as itself' '' "$(subjects)"

echo '--- folders'
run folders --index "$(native "$INDEX")" --zone Europe/Istanbul
check 'folders: one line per folder' 4 "$(grep -c ' messages  *[0-9]' "$W/out.txt")"
check 'folders: counts and days' 1 "$(grep -c '^Sent  *messages  *2  2024-03-05 .. 2024-03-06  with attachments  *1 ' "$W/out.txt")"
run folders --index "$(native "$W/case/work/none.sqlite")"
check 'folders: no index yet' '1|1' "$code|$(grep -c '^mail-index: no index at' "$W/err.txt")"

echo
if [ "$fails" != 0 ]; then
	echo "$fails failed; the test files are in $W"
	exit 1
fi
rm -rf "$W"
echo 'all passed'
