#!/usr/bin/env bash
# Tests git-history.sh on throwaway repositories. Not part of the skill.
#
#   test-git-history.sh [SKILL_DIR]
#
# SKILL_DIR defaults to ../cenk-overtime/skills/start. The repositories, clones
# and temporary files go to a new folder in the system temp folder, deleted when
# every check passes. Set CASE_DIR to a folder that does not exist yet to put
# the case folder somewhere else, such as Google Drive; delete it afterwards.
set -euo pipefail

T=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(cd "${1:-$T/../cenk-overtime/skills/start}/scripts" && pwd)/git-history.sh
W=$(mktemp -d "${TMPDIR:-/tmp}/test-git-history.XXXXXX")
mkdir -p "$W/home" "$W/tmp"
C=${CASE_DIR:-$W/case}
[ ! -e "$C" ] || { echo "CASE_DIR exists already: $C" >&2; exit 1; }
mkdir -p "$C"
: >"$W/empty.gitconfig"

# The script under test, with its own home (default clones folder) and temp folder.
gh_() { HOME=$W/home TMPDIR=$W/tmp bash "$SCRIPT" "$@"; }

# Setup git: no global config (no fsmonitor, no global identity).
s() { GIT_CONFIG_GLOBAL="$W/empty.gitconfig" GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false "$@"; }
# commit <repo> <name> <email> <author date> <committer date> <message> [git commit options]
commit() {
	local r=$1 n=$2 e=$3 ad=$4 cd=$5 m=$6
	shift 6
	GIT_AUTHOR_NAME=$n GIT_AUTHOR_EMAIL=$e GIT_AUTHOR_DATE=$ad \
		GIT_COMMITTER_NAME=$n GIT_COMMITTER_EMAIL=$e GIT_COMMITTER_DATE=$cd \
		s -C "$r" commit -q -m "$m" "$@"
}
q() { python -I -c 'import sqlite3, sys
sys.stdout.reconfigure(newline="\n")
for r in sqlite3.connect(sys.argv[1]).execute(sys.argv[2]): print("|".join("" if v is None else str(v) for v in r))' "$C/master.sqlite" "$1"; }

fails=0
check() {
	if [ "$2" = "$3" ]; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
		fails=$((fails + 1))
	fi
}

R=$W/repo
ME='Cenk Test'
s init -q -b main "$R"
s -C "$R" config user.name "$ME"
s -C "$R" config user.email cenk@work.example
s -C "$R" remote add origin 'https://cenk:notarealtoken@git.employer.example/team/backend.git'  # secret-scan: allow (fake credentials the script must refuse)

printf '1\n2\n3\n' >"$R/a.txt"
printf 'x\ny\n' >"$R/dosya ş.txt"
s -C "$R" add -A
commit "$R" "$ME" cenk@work.example 2024-03-05T21:30:00+03:00 2024-03-05T21:30:00+03:00 "Add files, it's \"quoted\""
c1=$(s -C "$R" rev-parse HEAD)

printf '4\n' >>"$R/a.txt"
s -C "$R" add -A
commit "$R" 'Bob Colleague' bob@work.example 2024-03-06T10:00:00+03:00 2024-03-06T10:00:00+03:00 'Colleague change'

printf '\000\001\002binary' >"$R/bin.dat"
printf '1\n2\nthree\n4\n' >"$R/a.txt"
s -C "$R" add -A
commit "$R" "$ME" cenk@10.1.2.3 2024-03-06T23:10:00+03:00 2024-03-07T01:10:00+03:00 $'Sürüm\tçıktı'
c3=$(s -C "$R" rev-parse HEAD)

s -C "$R" checkout -q -b release/1.2.0
s -C "$R" mv a.txt b.txt
commit "$R" "$ME" cenk@DESKTOP-ABC 2024-03-09T11:00:00+03:00 2024-03-09T11:00:00+03:00 'Rename on weekend'
c4=$(s -C "$R" rev-parse HEAD)

s -C "$R" checkout -q main
printf 'z\n' >>"$R/dosya ş.txt"
s -C "$R" add -A
commit "$R" 'Bob Colleague' bob@work.example 2024-03-10T09:30:00+03:00 2024-03-10T09:30:00+03:00 'Colleague two'
GIT_AUTHOR_DATE=2024-03-10T20:00:00+03:00 GIT_COMMITTER_DATE=2024-03-10T20:00:00+03:00 \
	s -C "$R" merge -q --no-ff -m 'Merge release/1.2.0' release/1.2.0
cm=$(s -C "$R" rev-parse HEAD)
commit "$R" "$ME" cenk@work.example 2024-03-11T19:00:00+03:00 2024-03-11T19:00:00+03:00 'Empty' --allow-empty
ce=$(s -C "$R" rev-parse HEAD)

GIT_COMMITTER_DATE=2024-03-11T19:05:00+03:00 s -C "$R" tag -a v1.2.0 -m 'Release 1.2.0' "$c4"
GIT_COMMITTER_NAME='Bob Colleague' GIT_COMMITTER_EMAIL=bob@work.example s -C "$R" -c user.name='Bob Colleague' -c user.email=bob@work.example tag -a v1.2.1 -m 'Bob release' "$ce"
s -C "$R" tag lt-1 "$c1"
s -C "$R" notes add -m 'a note' "$c1"
printf 'wip\n' >>"$R/b.txt" 2>/dev/null || printf 'wip\n' >>"$R/dosya ş.txt"
s -C "$R" stash -q

echo '--- extract (local)'
gh_ extract --case "$C" --author 'cenk' "$R"
DB=$C/master.sqlite

check 'own commits' 5 "$(q "select count(*) from commits where repo='team/backend'")"
check 'repos row' 'team/backend|local|https://git.employer.example/team/backend.git|git.employer.example|7|5|2' \
	"$(q "select repo, kind, remote_url, remote_host, commits_all, commits_own, commits_others from repos")"

# Files and lines per commit against git's own --shortstat.
for h in "$c1" "$c3" "$c4" "$cm" "$ce"; do
	expected=$(s -C "$R" log -1 --no-renames --shortstat --format= "$h" | awk '
		{ for (i = 1; i <= NF; i++) { if ($(i+1) ~ /^files?$/) f = $i; if ($(i+1) ~ /^insertion/) a = $i; if ($(i+1) ~ /^deletion/) d = $i } }
		END { print (f ? f : 0) "|" (a ? a : 0) "|" (d ? d : 0) }')
	check "shortstat ${h:0:7}" "$expected" "$(q "select files_changed, lines_added, lines_deleted from commits where hash='$h'")"
done

check 'binary file' '2|1' "$(q "select files_changed, binary_files from commits where hash='$c3'")"
check 'binary row' 'bin.dat|||1' "$(q "select path, lines_added, lines_deleted, is_binary from commit_files where hash='$c3' and is_binary=1")"
check 'merge flag' '1|0' "$(q "select is_merge, files_changed from commits where hash='$cm'")"
check 'utf-8 path' 'dosya ş.txt|2|0' "$(q "select path, lines_added, lines_deleted from commit_files where hash='$c1' and path like 'dosya%'")"
check 'quote in subject' "Add files, it's \"quoted\"" "$(q "select subject from commits where hash='$c1'")"
check 'tab in subject' 'Sürüm çıktı' "$(q "select subject from commits where hash='$c3'")"
check 'author utc' '2024-03-05T21:30:00+03:00|2024-03-05 18:30:00|0' "$(q "select author_date, author_utc, dates_differ from commits where hash='$c1'")"
check 'dates differ' '1' "$(q "select dates_differ from commits where hash='$c3'")"
check 'identities' 'Cenk Test|cenk@local-machine|2;Cenk Test|cenk@work.example|3' \
	"$(q "select author_name, author_email, commits from git_identities order by author_email" | paste -sd';')"
check 'tags' 'lt-1|lightweight|0|'"$c1"';v1.2.0|annotated|1|'"$c4"';v1.2.1|annotated|0|'"$ce" \
	"$(q "select tag, type, tagger_is_person, commit_hash from tags order by tag" | paste -sd';')"
check 'branches' 'refs/heads/main|main;refs/heads/release/1.2.0|release/1.2.0' \
	"$(q "select ref, branch from branches order by ref" | paste -sd';')"
check 'no stash or notes' 0 "$(q "select count(*) from commits where subject like 'WIP on%' or subject like 'index on%' or subject like 'Notes%'")"

for leak in bob@ 10.1.2.3 DESKTOP-ABC notarealtoken; do
	n=$({ grep -rlaF -- "$leak" "$C" || true; } | wc -l)
	check "nothing stores $leak" 0 "$n"
done

printf "insert into case_info values ('window_from', '2024-03-06', null), ('window_to', '2024-03-10', null);" >"$W/w.sql"
python -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(open(sys.argv[2]).read()); c.close()' "$DB" "$W/w.sql"
check 'window view' 3 "$(q "select count(*) from v_commits_in_window")"
check 'repo summary' 'team/backend|5|1' "$(q "select repo, own_commits, merges from v_repo_summary")"
check 'by day view' '2024-03-05|1' "$(q "select day, commits from v_commits_by_day order by day limit 1")"

echo '--- rerun, then a narrower pattern'
gh_ extract --case "$C" --author 'cenk' "$R" 2>/dev/null
check 'rerun keeps counts' '5|1' "$(q "select (select count(*) from commits), (select count(*) from repos)")"
gh_ extract --case "$C" --author 'cenk@work\.example' "$R" 2>/dev/null
check 'narrower pattern drops stale rows' 3 "$(q "select count(*) from commits")"

echo '--- two clones of one remote in one run'
R2=$W/repo-second-clone
s clone -q "$R" "$R2"
s -C "$R2" remote set-url origin 'https://git.employer.example/team/backend.git'
printf 'more\n' >"$R2/c.txt"
s -C "$R2" add -A
commit "$R2" "$ME" cenk@work.example 2024-03-12T22:00:00+03:00 2024-03-12T22:00:00+03:00 'Only in second clone'
gh_ extract --case "$C" --author 'cenk' "$R" "$R2"
check 'clones merge by hash' 6 "$(q "select count(*) from commits where repo='team/backend'")"
check 'one repos row per source' 2 "$(q "select count(*) from repos where repo='team/backend'")"
check 'one folder per source' 'git/team_backend;git/team_backend-2' "$(q "select tsv_dir from repos order by tsv_dir" | paste -sd';')"

echo '--- URL clone'
# The script names a URL clone after its last two path parts: work/remote.
s clone -q --bare "$R" "$W/work/remote.git"
URL="file:///$(cd "$W/work" && pwd -W)/remote.git"
DEFAULT_CLONES=$W/home/overtime-clones/$(basename "$C")
gh_ identities --case "$C" --author 'cenk|bob' "$URL"
check 'identities keeps the clone' yes "$([ -d "$DEFAULT_CLONES/work_remote.git" ] && echo yes || echo no)"
gh_ extract --case "$C" --author 'cenk' "$URL"
check 'clone commits' 5 "$(q "select count(*) from commits where repo='work/remote'")"
check 'clone row' "clone|$URL|" "$(q "select kind, source, remote_host from repos where repo='work/remote'")"
check 'clone deleted' no "$([ -d "$DEFAULT_CLONES/work_remote.git" ] && echo yes || echo no)"
check 'empty clones folder removed' no "$([ -d "$DEFAULT_CLONES" ] && echo yes || echo no)"
gh_ extract --case "$C" --clones "$W/clones" --author 'cenk' --keep-clone "$URL" 2>/dev/null
check 'keep-clone keeps it in --clones' yes "$([ -d "$W/clones/work_remote.git" ] && echo yes || echo no)"
gh_ identities --clones "$W/clones" --author 'cenk' "$URL" >/dev/null 2>&1
check 'identities without --case reuses --clones' 0 $?
check 'no clone in the case folder' 0 "$(find "$C" -name '*.git' | wc -l)"

echo '--- refusals'
set +e
out=$(gh_ extract --case "$C" --author cenk 'https://someone:notarealpass@git.employer.example/x.git' 2>&1)  # secret-scan: allow (fake credentials the script must refuse)
code=$?
check 'credential URL refused' 1 "$code"
check 'password not echoed' 0 "$(printf '%s' "$out" | grep -c notarealpass)"
gh_ extract --case "$C" --author cenk 'https://ghp_notreal@github.com/x/y.git' >/dev/null 2>&1
check 'token as user name refused' 1 $?
gh_ extract --case "$C" "$R" >/dev/null 2>&1
check 'author required' 1 $?
gh_ extract --case "$W/nope" --author cenk "$R" >/dev/null 2>&1
check 'case folder must exist' 1 $?
gh_ extract --case "$C" --author cenk "$W" >/dev/null 2>&1
check 'not a repository' 1 $?
gh_ extract --case "$C" --clones "$C/git/clones" --author cenk "$URL" >/dev/null 2>&1
check 'clones inside the case refused' 1 $?
check 'refused clones folder not left' no "$([ -d "$C/git/clones" ] && echo yes || echo no)"
gh_ identities --author cenk "$URL" >/dev/null 2>&1
check 'URL without --case or --clones refused' 1 $?
gh_ frobnicate >/dev/null 2>&1
check 'unknown command' 2 $?
gh_ --help >/dev/null 2>&1
check 'help' 0 $?
check 'help shows --clones' 1 "$(gh_ --help | grep -c 'extract --case DIR \[--clones DIR\]')"
set -e

check 'no temp folders left' 0 "$(find "$W/tmp" -mindepth 1 | wc -l)"
check 'no temp files in the case' 0 "$(find "$C" -name '.tmp.*' -o -name 'load.sql' | wc -l)"
check 'local repo untouched' '' "$(s -C "$R" status --porcelain)"

echo
if [ "$fails" != 0 ]; then
	echo "$fails failed; the test files are in $W"
	exit 1
fi
rm -rf "$W"
echo 'all passed'
