#!/usr/bin/env python3
"""Deliver a finished package version into a case's evidence folder.

    python deliver.py --evidence <case>/<case>-evidence \
        --package <case>/work/package/v3 --version 3 [--dry-run]

Steps, in this order; the first failure stops the run:
  1. check the package folder and the evidence folder
  2. check 4_Raw_Data/hashes.txt: the evidence is unchanged since it came in;
     work out the hash list and the new README text, so that from here on
     only moving, copying and writing can fail
  3. move the earlier package out of the evidence folder, to
     <package's parent>/delivered-v<previous>/
  4. copy folders 1, 2, 3 and 5 and NOTE_FOR_LAWYER.md in
  5. write HASHES_SHA256.txt (folders 1 to 5; not hashes.txt, the README,
     the note or 6_From_Lawyer/)
  6. read every listed file again and compare
  7. put README-package.md into the evidence folder's README.md
  8. print the SHA-256 of HASHES_SHA256.txt, for the deposit

Nothing in 4_Raw_Data/ or 6_From_Lawyer/ is written, moved or deleted, and
nothing anywhere is deleted. After a stop past step 3, run again with
--previous <label>-retry: the half-delivered files are set aside.
Standard library only.
"""
import argparse
import datetime
import hashlib
import os
import re
import shutil
import sys

PACKAGE_DIRS = ["1_Summary", "2_Report", "3_Processed_Data", "5_Calculation"]
RAW = "4_Raw_Data"
FROM_LAWYER = "6_From_Lawyer"
NOTE = "NOTE_FOR_LAWYER.md"
README = "README.md"
README_PART = "README-package.md"
HASHES = "HASHES_SHA256.txt"
RAW_HASHES = "hashes.txt"
# Files the system or Google Drive for desktop adds on its own.
JUNK = {"desktop.ini", ".DS_Store", "Thumbs.db"}
START = "<!-- package:start -->"
END = "<!-- package:end -->"
HASH_LINE = re.compile(r"^([0-9a-fA-F]{64}) [ *](.+)$")


class Stop(Exception):
    pass


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def files_under(root, top):
    """Relative paths, with '/', of every file below root/top, sorted."""
    out = []
    for folder, dirs, names in os.walk(os.path.join(root, top)):
        dirs.sort()
        for name in names:
            if name in JUNK:
                continue
            full = os.path.join(folder, name)
            out.append(os.path.relpath(full, root).replace(os.sep, "/"))
    return sorted(out)


def is_link(path):
    """A symbolic link or a Windows junction: both lead out of the folder."""
    junction = getattr(os.path, "isjunction", lambda p: False)
    return os.path.islink(path) or junction(path)


def check_names(root, top):
    """Stop on links, and on names a hash list cannot carry, below root/top."""
    start = os.path.join(root, top)
    if is_link(start):
        raise Stop("a link, not a real folder: %s" % top)
    for folder, dirs, names in os.walk(start):
        for name in dirs + names:
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            shown = rel.encode("ascii", "backslashreplace").decode("ascii")
            shown = shown.replace("\n", "?").replace("\r", "?")
            if is_link(full):
                # copytree would copy what the link points to, from outside
                # the package, into the folder the lawyers read.
                raise Stop("a link, not a real folder or file: %s" % shown)
            if "\n" in name or "\r" in name:
                raise Stop("line break in a name: %s" % shown)
            try:
                name.encode("utf-8")
            except UnicodeError:
                raise Stop("a name that is not valid UTF-8: %s" % shown)


def inside(path, parent):
    path, parent = os.path.realpath(path), os.path.realpath(parent)
    try:
        return os.path.commonpath([path, parent]) == parent
    except ValueError:  # another drive
        return False


def check_package(package):
    if not os.path.isdir(package):
        raise Stop("no package folder: %s" % package)
    wanted = set(PACKAGE_DIRS) | {NOTE, README_PART}
    have = {n for n in os.listdir(package) if n not in JUNK}
    missing = sorted(wanted - have)
    extra = sorted(have - wanted)
    if missing:
        raise Stop("the package folder lacks: %s" % ", ".join(missing))
    if extra:
        raise Stop("the package folder holds entries that are not part of a "
                   "package (move them out first): %s" % ", ".join(extra))
    for name in (NOTE, README_PART):
        full = os.path.join(package, name)
        if is_link(full) or not os.path.isfile(full):
            raise Stop("not a plain file: %s" % name)
    for d in PACKAGE_DIRS:
        if not os.path.isdir(os.path.join(package, d)):
            raise Stop("not a folder: %s" % d)
        check_names(package, d)
        files = files_under(package, d)
        if not files:
            raise Stop("empty package folder: %s" % d)
        for rel in files:
            if "__pycache__" in rel.split("/") or rel.endswith(".pyc"):
                raise Stop("compiled Python file in the package, delete it "
                           "first: %s" % rel)


def check_raw(evidence):
    """Verify 4_Raw_Data/hashes.txt; return {relative path: sha256}."""
    raw = os.path.join(evidence, RAW)
    listing = os.path.join(raw, RAW_HASHES)
    if not os.path.isfile(listing):
        raise Stop("no %s/%s in the evidence folder" % (RAW, RAW_HASHES))
    on_disk = {p[len(RAW) + 1:] for p in files_under(evidence, RAW)}
    on_disk.discard(RAW_HASHES)
    listed = {}
    # utf-8-sig: a hash list saved by a Windows editor may start with a BOM.
    with open(listing, encoding="utf-8-sig") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line:
                continue
            m = HASH_LINE.match(line)
            if not m:
                raise Stop("%s line %d is not '<sha256>  <path>'"
                           % (RAW_HASHES, number))
            listed[m.group(2)] = m.group(1).lower()
    bad = []
    for rel, digest in sorted(listed.items()):
        # Only a file found below 4_Raw_Data counts: a listed path such as
        # ../x or D:/x would otherwise be read from outside the folder.
        if rel not in on_disk:
            bad.append("missing: %s" % rel)
        elif sha256(os.path.join(raw, *rel.split("/"))) != digest:
            bad.append("changed: %s" % rel)
    for rel in sorted(on_disk - set(listed)):
        bad.append("not in %s: %s" % (RAW_HASHES, rel))
    if bad:
        raise Stop("%s does not match the evidence:\n  %s"
                   % (RAW_HASHES, "\n  ".join(bad)))
    return listed


def readme_text(evidence, package, values):
    """The evidence folder's README with the package part put in. Reads only."""
    with open(os.path.join(package, README_PART), encoding="utf-8") as f:
        part = f.read()
    for key, value in values.items():
        part = part.replace("{%s}" % key, value)
    block = "%s\n%s\n%s" % (START, part.strip("\n"), END)
    path = os.path.join(evidence, README)
    text = ""
    if os.path.isfile(path):
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
    starts, ends = text.count(START), text.count(END)
    if starts == 0 and ends == 0:
        return text.rstrip("\n") + ("\n\n" if text.strip() else "") + block + "\n"
    if starts == 1 and ends == 1 and text.index(START) < text.index(END):
        return text[:text.index(START)] + block + text[text.index(END) + len(END):]
    # A lone or doubled marker would make this run or the next one cut text.
    raise Stop("%s must hold the package markers once each, start first, or "
               "not at all: found %d start, %d end" % (README, starts, ends))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--evidence", required=True, help="the case's evidence folder")
    ap.add_argument("--package", required=True, help="work/package/v<N> of the case")
    ap.add_argument("--version", required=True, type=int, help="N, a whole number from 1")
    ap.add_argument("--previous", help="label of the earlier version (default: N-1)")
    ap.add_argument("--date", default=datetime.date.today().isoformat(),
                    help="delivery date for the README (default: today)")
    ap.add_argument("--dry-run", action="store_true",
                    help="check and list everything, change nothing")
    a = ap.parse_args()
    done = []
    previous = a.previous if a.previous is not None else str(a.version - 1)

    try:
        if a.version < 1:
            raise Stop("--version starts at 1")
        if not re.fullmatch(r"[A-Za-z0-9._-]+", previous):
            raise Stop("--previous takes letters, digits, '.', '_' and '-'")
        evidence, package = os.path.abspath(a.evidence), os.path.abspath(a.package)
        if not os.path.isdir(os.path.join(evidence, RAW)):
            raise Stop("not an evidence folder (no %s/): %s" % (RAW, evidence))
        if inside(package, evidence):
            raise Stop("the package folder is inside the evidence folder, "
                       "which the lawyers see: build in work/package/")
        set_aside = os.path.join(os.path.dirname(package), "delivered-v" + previous)
        if inside(set_aside, evidence):
            raise Stop("the earlier version would stay inside the evidence folder")

        # 1 and 2: every check and every read, before anything changes.
        check_package(package)
        raw_listed = check_raw(evidence)
        print("ok   %s/%s: %d files unchanged" % (RAW, RAW_HASHES, len(raw_listed)))
        source = {}
        for d in PACKAGE_DIRS:
            for rel in files_under(package, d):
                source[rel] = sha256(os.path.join(package, *rel.split("/")))
        lines = dict(source)
        for rel, digest in raw_listed.items():
            lines["%s/%s" % (RAW, rel)] = digest
        hash_list = "".join("%s  %s\n" % (lines[rel], rel)
                            for rel in sorted(lines)).encode("utf-8")
        deposit = hashlib.sha256(hash_list).hexdigest()
        new_readme = readme_text(evidence, package, {
            "version": str(a.version), "date": a.date, "hashes_sha256": deposit})

        keep = {README, RAW, FROM_LAWYER} | JUNK
        earlier = sorted(n for n in os.listdir(evidence) if n not in keep)
        if earlier and os.path.exists(set_aside):
            raise Stop("%s exists already: give the earlier version's "
                       "label with --previous" % set_aside)

        if a.dry_run:
            for name in earlier:
                print("would move %s -> %s" % (name, set_aside))
            if not earlier:
                print("no earlier package in the evidence folder")
            print("would copy %d files in %s, and %s"
                  % (len(source), ", ".join(PACKAGE_DIRS), NOTE))
            print("would write %s with %d lines" % (HASHES, len(lines)))
            print("would put %s into %s" % (README_PART, README))
            print("deposit would be: SHA-256 of %s = %s" % (HASHES, deposit))
            print("dry run: nothing changed")
            return 0

        # 3: the earlier package leaves the evidence folder.
        if earlier:
            os.makedirs(set_aside)
            for name in earlier:
                shutil.move(os.path.join(evidence, name),
                            os.path.join(set_aside, name))
                done.append("moved out: %s" % name)
                print("moved %s -> %s" % (name, set_aside))
        else:
            print("no earlier package in the evidence folder")

        # 4: copy the new version in, and compare each copy with its source.
        for d in PACKAGE_DIRS:
            shutil.copytree(os.path.join(package, d), os.path.join(evidence, d),
                            ignore=shutil.ignore_patterns(*JUNK))
            done.append("copied: %s" % d)
        shutil.copy2(os.path.join(package, NOTE), os.path.join(evidence, NOTE))
        done.append("copied: %s" % NOTE)
        for rel, digest in source.items():
            if sha256(os.path.join(evidence, *rel.split("/"))) != digest:
                raise Stop("the copy differs from its source: %s" % rel)
        print("copied %d files, each equal to its source" % len(source))

        # 5: the hash list, raw files included, sorted by path.
        hashes_path = os.path.join(evidence, HASHES)
        with open(hashes_path, "wb") as f:
            f.write(hash_list)
        done.append("wrote: %s" % HASHES)

        # 6: read everything again from the evidence folder.
        on_disk = []
        for d in PACKAGE_DIRS + [RAW]:
            on_disk += files_under(evidence, d)
        on_disk = set(on_disk) - {"%s/%s" % (RAW, RAW_HASHES)}
        if on_disk != set(lines):
            odd = sorted(on_disk ^ set(lines))
            raise Stop("%s and the folders differ: %s" % (HASHES, ", ".join(odd)))
        for rel in sorted(lines):
            if sha256(os.path.join(evidence, *rel.split("/"))) != lines[rel]:
                raise Stop("changed while delivering: %s" % rel)
        print("ok   %s: %d files" % (HASHES, len(lines)))

        # 7 and 8: the README's package part, and the deposit hash.
        with open(os.path.join(evidence, README), "w", encoding="utf-8", newline="") as f:
            f.write(new_readme)
        print("ok   %s: package part for version %d" % (README, a.version))
        print("deposit: SHA-256 of %s = %s" % (HASHES, deposit))
        return 0
    except (Stop, OSError, UnicodeError) as e:
        print("stopped: %s" % e, file=sys.stderr)
        if done:
            print("already done:\n  %s" % "\n  ".join(done), file=sys.stderr)
            print("the evidence folder is half delivered. Repair nothing by "
                  "hand: fix the cause, then run again with --previous "
                  "%s-retry, which sets these files aside and delivers "
                  "afresh." % previous, file=sys.stderr)
        else:
            print("nothing was changed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
