#!/bin/sh
# Tests cenk-overtime's use of the shared profile: the dependency on cenk-base in
# both manifests, and cenk-base's lib/profile.py with the keys this plugin keeps,
# on made-up profiles. Not part of the skill.
#
#   sh tests/test-profile.sh
#   CENK_BASE_DIR=<cenk-base folder> sh tests/test-profile.sh
#
# CENK_BASE_DIR defaults to ../cenk-base beside this repository; without it the
# checks that need cenk-base are skipped, and the test says so. Everything goes
# to a new folder in the system temp folder, deleted when every check passes.
# The real profile stays out of sight: CENK_HOME, CENK_PROFILE and CENK_BASE,
# which a session may carry to the person's real files, are unset first; then
# CENK_HOME and the Claude config folder point into the temp folder.
set -eu
unset CENK_HOME CENK_PROFILE CENK_BASE CLAUDE_PLUGIN_OPTION_PROFILE_PATH 2>/dev/null || true

T=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$T/.." && pwd)
PLUGIN="$ROOT/cenk-overtime"
BASE_DIR=${CENK_BASE_DIR:-$ROOT/../cenk-base}
W=$(mktemp -d "${TMPDIR:-/tmp}/test-profile.XXXXXX")

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

fails=0
n=0
ok() { n=$((n + 1)); echo "ok   $n $1"; }
no() { n=$((n + 1)); fails=$((fails + 1)); echo "FAIL $n $1"; }
# check <name> <expected exit> <command...>: runs it, keeps stdout and stderr in $W/out.
check() {
	name=$1 want=$2
	shift 2
	set +e
	"$@" >"$W/out" 2>&1
	got=$?
	set -e
	if [ "$got" = "$want" ]; then ok "$name"; else no "$name (exit $got, wanted $want)"; sed 's/^/     /' "$W/out"; fi
}
has() { if grep -q -- "$2" "$3"; then ok "$1"; else no "$1"; sed 's/^/     /' "$3"; fi; }
# json <name> <file> <python expression on d>: the file's JSON, checked.
json() {
	if "$PY" -I -B -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8")); sys.exit(0 if eval(sys.argv[2]) else 1)' \
		"$(native "$2")" "$3" >"$W/out" 2>&1; then ok "$1"; else no "$1"; sed 's/^/     /' "$W/out"; fi
}
finish() {
	if [ "$fails" = 0 ]; then
		rm -rf "$W"
		echo "all $n checks passed$1"
	else
		echo "$fails of $n checks failed; files kept in $W"
		exit 1
	fi
}

# --- the dependency, in both manifests ---
json 'plugin.json needs cenk-base from the cenk catalog' "$PLUGIN/.claude-plugin/plugin.json" \
	'{"name": "cenk-base", "marketplace": "cenk"} in d.get("dependencies", [])'
json 'the repository catalog allows dependencies from cenk' "$ROOT/.claude-plugin/marketplace.json" \
	'"cenk" in d.get("allowCrossMarketplaceDependenciesOn", [])'
[ ! -e "$PLUGIN/skills/start/scripts/profilelib.py" ] && ok 'no own copy of the profile code' || no 'no own copy of the profile code'
if grep -rn -e 'import profile' -e 'profilelib' "$PLUGIN" >"$W/out" 2>&1; then
	no 'no skill imports profile or names profilelib'
	sed 's/^/     /' "$W/out"
else
	ok 'no skill imports profile or names profilelib'
fi
has 'start calls the base by CENK_BASE' '"$CENK_BASE/lib/profile.py"' "$PLUGIN/skills/start/SKILL.md"
has 'start gives the install command that brings the base' 'claude plugin install cenk-overtime@cenk' "$PLUGIN/skills/start/SKILL.md"

# --- the set-up check of start: CENK_BASE set and lib/profile.py there ---
base_ready() { [ -n "${CENK_BASE:-}" ] && [ -f "$CENK_BASE/lib/profile.py" ]; }
if base_ready; then no 'set-up check: CENK_BASE unset is missing'; else ok 'set-up check: CENK_BASE unset is missing'; fi
mkdir -p "$W/fake-base"
CENK_BASE="$W/fake-base"
if base_ready; then no 'set-up check: a folder without lib/profile.py is missing'; else ok 'set-up check: a folder without lib/profile.py is missing'; fi
unset CENK_BASE

if [ ! -f "$BASE_DIR/lib/profile.py" ]; then
	echo "SKIP the checks of cenk-base itself: no lib/profile.py in $BASE_DIR (set CENK_BASE_DIR)"
	finish '; the cenk-base checks were skipped'
	exit 0
fi
CENK_BASE=$(cd "$BASE_DIR" && pwd)
export CENK_BASE
if base_ready; then ok 'set-up check: the cenk-base folder is there'; else no 'set-up check: the cenk-base folder is there'; fi

CLAUDE_CONFIG_DIR=$(native "$W/claude-config")
export CLAUDE_CONFIG_DIR
mkdir -p "$W/claude-config" "$W/drive/My Drive"
H="$W/drive/My Drive/cenk"
CENK_HOME=$(native "$H")
export CENK_HOME
P="$H/profile.json"
pl() { "$PY" -I -B "$(native "$CENK_BASE/lib/profile.py")" "$@"; }
# plh <cenk folder> <command...>: profile.py with CENK_HOME set for that one program only. A prefix
# assignment on a shell function may outlive the call in some shells; on a program it never does.
plh() { h=$1; shift; CENK_HOME=$(native "$h") "$PY" -I -B "$(native "$CENK_BASE/lib/profile.py")" "$@"; }

# --- no profile yet ---
check 'path without a profile' 0 pl path
[ -z "$(tr -d '\r\n' <"$W/out")" ] && ok 'path prints nothing' || no 'path prints nothing'
check 'home names the CENK_HOME folder' 0 pl home
has 'home is the cenk folder' 'cenk' "$W/out"
check 'get without a profile is refused' 1 pl get person.name

# --- create, never inside a case folder of this plugin ---
C="$W/Legal cases/acme-2024"
mkdir -p "$C/acme-2024-evidence"
: >"$C/master.sqlite"
check 'create inside a case folder is refused' 1 plh "$C/cenk" create "$(native "$C/cenk")"
has 'the refusal names the case folder' 'inside the case folder' "$W/out"
check 'create inside the evidence folder is refused' 1 plh "$C/acme-2024-evidence/cenk" create "$(native "$C/acme-2024-evidence/cenk")"
[ ! -e "$C/cenk" ] && [ ! -e "$C/acme-2024-evidence/cenk" ] && ok 'nothing made in the case' || no 'nothing made in the case'
check 'create in the cenk folder' 0 pl create "$(native "$H")"
[ -f "$P" ] && ok 'profile.json is in the cenk folder' || no 'profile.json is in the cenk folder'

# --- the keys this plugin keeps ---
check 'set the name' 0 pl set person.name '"Ayşe Example"'
check 'set the spellings' 0 pl set person.name_variants '["Ayşe Example", "Ayse Example"]'
check 'get a spelling' 0 pl get 'person.name_variants[1]'
has 'the spelling without diacritics comes back' 'Ayse Example' "$W/out"
check 'set the personal emails' 0 pl set person.emails '["ayse@private.example"]'
printf '"+00 555 000 0001"' | pl set person.phone - >"$W/out" 2>&1 && ok 'the phone from stdin' || no 'the phone from stdin'
check 'set the Google account' 0 pl set accounts.drive '"ayse@private.example"'
check 'set the job' 0 pl set employment.acme-2021 '{"employer": "Acme Example", "role": "Engineer", "start": "2021-03", "end": "2024-06", "source": "chat"}'
check 'get the job end' 0 pl get employment.acme-2021.end
has 'the job end comes back' '2024-06' "$W/out"
check 'set a lawyer' 0 pl set contacts.lawyer-jo '{"name": "Jo Example", "email": "jo@example.com", "relation": "lawyer", "source": "chat"}'
check 'get the lawyer email' 0 pl get contacts.lawyer-jo.email
has 'the lawyer email comes back' 'jo@example.com' "$W/out"
check 'another job end without --old is refused (exit 3)' 3 pl set employment.acme-2021.end '"2024-07"'
check 'the right --old changes it' 0 pl set employment.acme-2021.end '"2024-07"' --old '"2024-06"'
json 'history keeps the earlier job end' "$P" '[h["old"] for h in d["history"]] == ["2024-06"]'
check 'a cenk-overtime setting without --yes is refused' 1 pl set settings.cenk-overtime.send_mode '"confirm"'
json 'the profile holds no address' "$P" '"address" not in d.get("person", {})'

# --- moving a case: compare-and-set, as start does it ---
check 'a case value the profile already holds' 0 pl set person.emails '["ayse@private.example"]'
has 'it is reported unchanged' 'unchanged' "$W/out"
check 'a case value that differs: exit 3, nothing written' 3 pl set person.name '"Ayse Other"'
has 'the refusal shows the held value' 'Ayşe Example' "$W/out"

# --- another plugin's profile, found through CENK_HOME ---
# Another cenk-* plugin wrote this profile, in a cenk folder this plugin's own
# lookup would not reach by itself.
O="$W/elsewhere/shared cenk"
mkdir -p "$O"
cat >"$O/profile.json" <<'EOF'
{
  "person": {"name": "Ada Example", "emails": ["ada@private.example"]},
  "settings": {"cenk-jobs": {"send_mode": "confirm"}},
  "history": [{"date": "2026-11-01", "field": "person.name", "old": "Ada E.", "new": "Ada Example"}]
}
EOF
check 'path is the other plugin profile' 0 plh "$O" path
has 'path names it' 'shared cenk' "$W/out"
check 'get a value the other plugin wrote' 0 plh "$O" get 'person.emails[0]'
has 'its personal email comes back' 'ada@private.example' "$W/out"
check 'add a lawyer there' 0 plh "$O" set contacts.lawyer-jo '{"name": "Jo Example"}'
json 'its settings and history are kept' "$O/profile.json" \
	'd["settings"] == {"cenk-jobs": {"send_mode": "confirm"}} and len(d["history"]) == 1 and list(d)[-1] == "history"'
check 'CENK_HOME naming no profile: nothing else is looked at' 1 plh "$W/no-such-folder" get person.name
has 'the refusal names the CENK_HOME folder' 'no-such-folder' "$W/out"

# --- pin: CENK_HOME in the Claude settings, only after a yes ---
S="$W/claude-config/settings.json"
printf '{"model": "opus", "env": {"OTHER": "1"}}' >"$S"
check 'pin without --yes is refused' 1 pl pin "$(native "$H")"
json 'the settings are unchanged' "$S" 'd == {"model": "opus", "env": {"OTHER": "1"}}'
check 'pin with --yes' 0 pl pin "$(native "$H")" --yes
json 'pin sets CENK_HOME and keeps the rest' "$S" \
	'd["model"] == "opus" and d["env"]["OTHER"] == "1" and d["env"]["CENK_HOME"].rstrip("/").endswith("My Drive/cenk")'

finish ''
