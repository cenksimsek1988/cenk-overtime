#!/bin/sh
# Tests deliver.py on a made-up case folder. Not part of the skill.
#
#   sh tests/test-deliver.sh [SKILL_DIR]
#
# SKILL_DIR defaults to ../cenk-overtime/skills/court-package. Everything goes
# to a new folder in the system temp folder, deleted when every check passes.
set -eu

T=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(cd "${1:-$T/../cenk-overtime/skills/court-package}/scripts" && pwd)/deliver.py
W=$(mktemp -d "${TMPDIR:-/tmp}/test-deliver.XXXXXX")

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
# Native Windows programs need Windows paths in arguments.
native() { if [ "$WIN" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

if command -v sha256sum >/dev/null 2>&1; then
	sum() { sha256sum "$@"; }
else
	sum() { shasum -a 256 "$@"; }
fi

fails=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
no() { n=$((n + 1)); fails=$((fails + 1)); echo "FAIL $n $1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

C="$W/case one"
E="$C/acme-2024-evidence"
P="$C/work/package"
SCRIPT_N=$(native "$SCRIPT")

deliver() { "$PY" -I -B "$SCRIPT_N" --evidence "$(native "$E")" "$@" >"$W/out" 2>"$W/err"; }

# A made-up version of the package in work/package/v<N>.
make_package() {
	d="$P/v$1"
	mkdir -p "$d/1_Summary" "$d/2_Report" "$d/3_Processed_Data/database/csv" "$d/5_Calculation/tool"
	echo "summary $1" >"$d/1_Summary/Summary.pdf"
	echo "report $1" >"$d/2_Report/Report.pdf"
	echo "annex $1" >"$d/2_Report/Annex A.pdf"
	echo "day,count" >"$d/3_Processed_Data/database/csv/days.csv"
	echo "tool $1" >"$d/5_Calculation/tool/build.py"
	echo "For the lawyer only. v$1" >"$d/NOTE_FOR_LAWYER.md"
	printf 'Package version {version}, {date}.\nSHA-256 of HASHES_SHA256.txt: {hashes_sha256}\n' >"$d/README-package.md"
}

mkdir -p "$E/4_Raw_Data/email" "$E/4_Raw_Data/slack/general" "$E/6_From_Lawyer"
echo 'made-up mail' >"$E/4_Raw_Data/email/sent.mbox"
echo '{"text": "made up"}' >"$E/4_Raw_Data/slack/general/2024-03-05.json"
echo '[.ShellClassInfo]' >"$E/4_Raw_Data/desktop.ini"
(cd "$E/4_Raw_Data" && sum email/sent.mbox slack/general/2024-03-05.json >hashes.txt)
echo 'from the lawyer' >"$E/6_From_Lawyer/letter.txt"
printf '# Start here\n\nWhat each folder holds.\n' >"$E/README.md"
# A package from an early plugin version, at the folder's top.
echo 'old summary' >"$E/Summary.pdf"
echo 'old zip' >"$E/package.zip"
make_package 1
lawyer_before=$(sum "$E/6_From_Lawyer/letter.txt" | cut -c1-64)

# --- refusals, each leaving the evidence folder as it was
if deliver --package "$(native "$P/v1")" --version 0; then no 'version 0 refused'; else ok 'version 0 refused'; fi
if deliver --package "$(native "$P/nope")" --version 1; then no 'missing package folder refused'; else ok 'missing package folder refused'; fi

mkdir -p "$E/build"; cp -r "$P/v1" "$E/build/v1"
if deliver --package "$(native "$E/build/v1")" --version 1; then no 'package inside the evidence folder refused'; else ok 'package inside the evidence folder refused'; fi
rm -rf "$E/build"

echo scratch >"$P/v1/unmasked.jsonl"
if deliver --package "$(native "$P/v1")" --version 1; then no 'extra entry refused'; else ok 'extra entry refused'; fi
check 'extra entry named' "grep -q 'unmasked.jsonl' '$W/err'"
rm "$P/v1/unmasked.jsonl"

mv "$P/v1/NOTE_FOR_LAWYER.md" "$W/note"
if deliver --package "$(native "$P/v1")" --version 1; then no 'missing note refused'; else ok 'missing note refused'; fi
check 'missing note named' "grep -q 'NOTE_FOR_LAWYER.md' '$W/err'"
mv "$W/note" "$P/v1/NOTE_FOR_LAWYER.md"

mkdir "$P/v1/5_Calculation/tool/__pycache__"; echo x >"$P/v1/5_Calculation/tool/__pycache__/build.pyc"
if deliver --package "$(native "$P/v1")" --version 1; then no 'compiled Python file refused'; else ok 'compiled Python file refused'; fi
rm -rf "$P/v1/5_Calculation/tool/__pycache__"

echo 'changed' >>"$E/4_Raw_Data/email/sent.mbox"
if deliver --package "$(native "$P/v1")" --version 1; then no 'changed raw file refused'; else ok 'changed raw file refused'; fi
check 'changed raw file named' "grep -q 'changed: email/sent.mbox' '$W/err'"
check 'says nothing was changed' "grep -q 'nothing was changed' '$W/err'"
echo 'made-up mail' >"$E/4_Raw_Data/email/sent.mbox"

echo 'late' >"$E/4_Raw_Data/email/late.eml"
if deliver --package "$(native "$P/v1")" --version 1; then no 'unlisted raw file refused'; else ok 'unlisted raw file refused'; fi
check 'unlisted raw file named' "grep -q 'not in hashes.txt: email/late.eml' '$W/err'"
rm "$E/4_Raw_Data/email/late.eml"

# A linked folder would bring files from outside the package into the shared folder.
mkdir "$W/outside"; echo 'not for the lawyers' >"$W/outside/private.txt"
if "$PY" -I -B "$(native "$T/make-link.py")" "$(native "$W/outside")" "$(native "$P/v1/2_Report/linked")" 2>/dev/null; then
	if deliver --package "$(native "$P/v1")" --version 1; then no 'linked folder refused'; else ok 'linked folder refused'; fi
	check 'linked folder named' "grep -q 'a link, not a real folder or file: 2_Report/linked' '$W/err'"
	"$PY" -I -B "$(native "$T/make-link.py")" --remove "$(native "$P/v1/2_Report/linked")"
else
	ok 'linked folder refused (skipped: this system makes no links)'
	ok 'linked folder named (skipped)'
fi
check 'the link is gone, its target stays' "[ ! -e '$P/v1/2_Report/linked' ] && [ -f '$W/outside/private.txt' ]"

cp "$E/4_Raw_Data/hashes.txt" "$W/hashes.keep"
printf '%s  ../README.md\n' "$(sum "$E/README.md" | cut -c1-64)" >>"$E/4_Raw_Data/hashes.txt"
if deliver --package "$(native "$P/v1")" --version 1; then no 'listed path outside the raw folder refused'; else ok 'listed path outside the raw folder refused'; fi
check 'outside path named as missing' "grep -q 'missing: ../README.md' '$W/err'"
printf '\357\273\277' >"$E/4_Raw_Data/hashes.txt"; cat "$W/hashes.keep" >>"$E/4_Raw_Data/hashes.txt"
if deliver --package "$(native "$P/v1")" --version 1 --dry-run; then ok 'hash list with a BOM accepted'; else no 'hash list with a BOM accepted'; cat "$W/err"; fi
cp "$W/hashes.keep" "$E/4_Raw_Data/hashes.txt"

cp "$E/README.md" "$W/readme.keep"
echo '<!-- package:start -->' >>"$E/README.md"
if deliver --package "$(native "$P/v1")" --version 1; then no 'lone README marker refused'; else ok 'lone README marker refused'; fi
check 'marker count named' "grep -q 'found 1 start, 0 end' '$W/err'"
cp "$W/readme.keep" "$E/README.md"

cp "$P/v1/README-package.md" "$W/part.keep"
printf 'Version {version} \377\376\n' >"$P/v1/README-package.md"
if deliver --package "$(native "$P/v1")" --version 1; then no 'README part that is not UTF-8 refused'; else ok 'README part that is not UTF-8 refused'; fi
check 'refused before anything changed' "grep -q 'nothing was changed' '$W/err'"
cp "$W/part.keep" "$P/v1/README-package.md"

check 'refusals moved nothing' "[ -f '$E/Summary.pdf' ] && [ -f '$E/package.zip' ] && [ ! -e '$E/1_Summary' ] && [ ! -e '$E/HASHES_SHA256.txt' ]"

# --- dry run
if deliver --package "$(native "$P/v1")" --version 1 --dry-run; then ok 'dry run exits 0'; else no 'dry run exits 0'; fi
check 'dry run lists the move' "grep -q 'would move Summary.pdf' '$W/out'"
check 'dry run shows the deposit hash' "grep -Eq 'deposit would be: .* = [0-9a-f]{64}' '$W/out'"
check 'dry run changes nothing' "[ -f '$E/Summary.pdf' ] && [ ! -e '$E/1_Summary' ] && [ ! -e '$P/delivered-v0' ] && ! grep -q 'package:start' '$E/README.md'"

# --- first delivery: the early package moves out
if deliver --package "$(native "$P/v1")" --version 1 --date 2030-01-02; then ok 'version 1 delivered'; else no 'version 1 delivered'; cat "$W/err"; fi
check 'early package moved to delivered-v0' "[ -f '$P/delivered-v0/Summary.pdf' ] && [ -f '$P/delivered-v0/package.zip' ] && [ ! -e '$E/Summary.pdf' ] && [ ! -e '$E/package.zip' ]"
check 'four folders and the note copied' "[ -f '$E/1_Summary/Summary.pdf' ] && [ -f '$E/2_Report/Report.pdf' ] && [ -f '$E/3_Processed_Data/database/csv/days.csv' ] && [ -f '$E/5_Calculation/tool/build.py' ] && [ -f '$E/NOTE_FOR_LAWYER.md' ]"
check 'README-package.md not copied' "[ ! -e '$E/README-package.md' ]"
check 'the package in work/ stays' "[ -f '$P/v1/1_Summary/Summary.pdf' ]"
check 'sha256sum -c passes' "(cd '$E' && sum -c HASHES_SHA256.txt >/dev/null 2>&1)"
check 'hash list has 7 lines' "[ \$(grep -c . '$E/HASHES_SHA256.txt') = 7 ]"
check 'a name with a space is listed' "grep -q '  2_Report/Annex A.pdf\$' '$E/HASHES_SHA256.txt'"
check 'raw files listed one by one' "grep -q '  4_Raw_Data/slack/general/2024-03-05.json\$' '$E/HASHES_SHA256.txt'"
check 'hashes.txt, README, note, lawyer folder, desktop.ini not listed' "! grep -Eq 'hashes\.txt|README|NOTE_FOR_LAWYER|6_From_Lawyer|desktop\.ini' '$E/HASHES_SHA256.txt'"
check 'hash list sorted by path' "cut -c67- '$E/HASHES_SHA256.txt' | LC_ALL=C sort -c"
check 'hash list has no CR' "[ \$(tr -cd '\r' <'$E/HASHES_SHA256.txt' | wc -c) = 0 ]"
dep=$(sum "$E/HASHES_SHA256.txt" | cut -c1-64)
check 'deposit hash printed' "grep -q '$dep' '$W/out'"
check 'README keeps its own text' "grep -q 'What each folder holds' '$E/README.md'"
check 'README has version, date and deposit hash' "grep -q 'Package version 1, 2030-01-02' '$E/README.md' && grep -q '$dep' '$E/README.md'"
check 'README has no placeholder left' "! grep -q '{' '$E/README.md'"
check 'lawyer folder untouched' "[ \"\$(sum '$E/6_From_Lawyer/letter.txt' | cut -c1-64)\" = '$lawyer_before' ] && [ \$(ls '$E/6_From_Lawyer' | wc -l) = 1 ]"
check 'raw folder untouched' "(cd '$E/4_Raw_Data' && sum -c hashes.txt >/dev/null 2>&1) && [ -f '$E/4_Raw_Data/desktop.ini' ]"

# --- second delivery: version 1 moves out, the README part is replaced
make_package 2
if deliver --package "$(native "$P/v2")" --version 2 --date 2030-02-03; then ok 'version 2 delivered'; else no 'version 2 delivered'; cat "$W/err"; fi
check 'version 1 moved to delivered-v1, note and hash list too' "[ -f '$P/delivered-v1/1_Summary/Summary.pdf' ] && [ -f '$P/delivered-v1/NOTE_FOR_LAWYER.md' ] && [ -f '$P/delivered-v1/HASHES_SHA256.txt' ]"
check 'version 2 in the evidence folder' "grep -q 'summary 2' '$E/1_Summary/Summary.pdf' && grep -q 'v2' '$E/NOTE_FOR_LAWYER.md'"
check 'sha256sum -c passes again' "(cd '$E' && sum -c HASHES_SHA256.txt >/dev/null 2>&1)"
check 'README part replaced, not added twice' "[ \$(grep -c 'package:start' '$E/README.md') = 1 ] && grep -q 'Package version 2, 2030-02-03' '$E/README.md' && ! grep -q 'Package version 1' '$E/README.md'"
check 'README still keeps its own text' "grep -q 'What each folder holds' '$E/README.md'"

# --- the set-aside folder is never overwritten
make_package 3
mkdir "$P/delivered-v2"
if deliver --package "$(native "$P/v3")" --version 3; then no 'existing delivered-v2 refused'; else ok 'existing delivered-v2 refused'; fi
check 'version 2 still in place' "grep -q 'summary 2' '$E/1_Summary/Summary.pdf'"
if deliver --package "$(native "$P/v3")" --version 3 --previous 2b; then ok '--previous picks another label'; else no '--previous picks another label'; cat "$W/err"; fi
check 'version 2 moved to delivered-v2b' "[ -f '$P/delivered-v2b/2_Report/Report.pdf' ] && grep -q 'summary 3' '$E/1_Summary/Summary.pdf'"

# --- a half-delivered folder: a run again with a new label sets it aside
make_package 4
rm "$E/HASHES_SHA256.txt"; rm -r "$E/5_Calculation"
if deliver --package "$(native "$P/v4")" --version 4; then ok 'half-delivered folder: delivered again'; else no 'half-delivered folder: delivered again'; cat "$W/err"; fi
check 'half-delivered files set aside' "[ -f '$P/delivered-v3/1_Summary/Summary.pdf' ] && [ ! -e '$P/delivered-v3/5_Calculation' ]"
check 'version 4 complete' "grep -q 'summary 4' '$E/1_Summary/Summary.pdf' && (cd '$E' && sum -c HASHES_SHA256.txt >/dev/null 2>&1)"
check 'lawyer folder untouched at the end' "[ \"\$(sum '$E/6_From_Lawyer/letter.txt' | cut -c1-64)\" = '$lawyer_before' ]"

echo
if [ "$fails" != 0 ]; then
	echo "$fails failed; the test files are in $W"
	exit 1
fi
rm -rf "$W"
echo 'all passed'
