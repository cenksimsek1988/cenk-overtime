#!/bin/sh
# Tests models.py on a made-up case with known effects. Not part of the skill.
#
#   sh tests/test-models.sh [PLUGIN_DIR]
#
# PLUGIN_DIR defaults to ../cenk-overtime. Needs a Python with pandas, numpy,
# statsmodels and scipy. The database and the model files go to a new folder
# in the system temp folder, deleted when every check passes.
set -eu

T=$(cd "$(dirname "$0")" && pwd)
P=$(cd "${1:-$T/../cenk-overtime}" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/test-models.XXXXXX")

PY=''
for p in python3 python py; do
	# Windows has a python3 stub that only opens the Store: try each one.
	if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import pandas, statsmodels, scipy' >/dev/null 2>&1; then
		PY=$(command -v "$p")
		break
	fi
done
[ -n "$PY" ] || { echo 'no Python with pandas, statsmodels and scipy: run check-tools.py of the start skill' >&2; exit 1; }

case $(uname -s) in
	MINGW* | MSYS* | CYGWIN*) WIN=1 ;;
	*) WIN=0 ;;
esac
native() { if [ "$WIN" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

MODELS=$(native "$P/skills/analyse/scripts/models.py")
SCHEMA=$(native "$P/skills/start/scripts/schema.sql")
DB=$W/case/master.sqlite
mkdir -p "$W/case"

# Two years of days: weekday and weekend rates, a 30% higher year, a later
# phase 25% higher, releases every 3 weeks with 3 times the traces, 1.5 times
# in the week before (2.5 times on those weekends), patches twice, 3
# incidents (too few to test), leave, extra variation (negative binomial),
# chat and commit clocks that agree and a mail clock that does not.
cat >"$W/make.py" <<'EOF'
import datetime as dt, math, random, sqlite3, sys
db, schema = sys.argv[1], sys.argv[2]
rng = random.Random(7)
con = sqlite3.connect(db)
con.executescript(open(schema, encoding="utf-8").read())
con.executemany("INSERT INTO case_info VALUES (?, ?, NULL)", [("window_from", "2023-01-02"), ("window_to", "2024-12-29")])
days = [dt.date(2023, 1, 2) + dt.timedelta(n) for n in range(728)]
releases = {d for d in (dt.date(2023, 1, 18) + dt.timedelta(21 * k) for k in range(40)) if d <= days[-1]}
weekdays = [d for d in days if d.weekday() < 5 and d not in releases]
patches = set(rng.sample(weekdays, 14))
incidents = set(rng.sample([d for d in weekdays if d not in patches], 3))
leave = set(rng.sample([d for d in weekdays if d not in patches | incidents], 25))

def poisson(lam):
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1

rows = []
for d in days:
    weekend = d.weekday() >= 5
    lam = 0.45 if weekend else 1.2
    lam *= 1.3 if d.year == 2024 else 1.0
    lam *= 1.25 if d >= dt.date(2024, 3, 1) else 1.0
    pre = d not in releases | patches | incidents and any(d + dt.timedelta(k) in releases for k in range(1, 8))
    if d in releases:
        lam *= 3.0
    elif pre:
        lam *= 2.5 if weekend else 1.5
    if d in patches:
        lam *= 2.0
    if d in incidents:
        lam *= 2.5
    n = 0 if d in leave else poisson(lam * rng.gammavariate(1.5, 1 / 1.5))
    kinds = [rng.choices(["chat", "mail", "commit"], [0.5, 0.2, 0.3])[0] for _ in range(n)]
    chat, mail, commit = (kinds.count(k) for k in ("chat", "mail", "commit"))
    end = 19 + rng.expovariate(0.5)
    last_chat = min(end, 29.5) if chat else None
    last_commit = (min(end + rng.gauss(0, 0.3), 29.5) if chat else 19 + rng.expovariate(0.5)) if commit else None
    last_mail = rng.uniform(18.5, 23.5) if mail else None
    rows.append((d.isoformat(), "leave" if d in leave else None, "second" if d >= dt.date(2024, 3, 1) else "first",
                 n, chat, mail, commit, last_chat, last_mail, last_commit,
                 int(d in releases), int(d in patches), int(d in incidents),
                 "git" if d in releases else ("message" if d in patches | incidents else None)))
con.executemany("INSERT INTO days VALUES (%s)" % ", ".join("?" * 14), rows)
con.commit()
EOF
"$PY" -I "$W/make.py" "$(native "$DB")" "$SCHEMA"

fails=0
check() {
	if [ "$2" = "$3" ]; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
		fails=$((fails + 1))
	fi
}

# j MODEL EXPR [DIR]: a Python expression on model-MODEL.json; r is the
# result row of a "sample/term" key: r["all-days/release"].
j() {
	"$PY" -I -c 'import json, sys
sys.stdout.reconfigure(newline="\n")
m = json.load(open(sys.argv[1], encoding="utf-8"))
r = {x["sample"] + "/" + x["term"]: x for x in m["results"]}
print(eval(sys.argv[2]))' "$(native "${3:-$W/out}/model-$1.json")" "$2"
}
# q SQL: rows of the case database.
q() {
	"$PY" -I -c 'import sqlite3, sys
sys.stdout.reconfigure(newline="\n")
for row in sqlite3.connect(sys.argv[1]).execute(sys.argv[2]): print("|".join("" if v is None else str(v) for v in row))' "$(native "${2:-$DB}")" "$1"
}
run() {
	set +e
	"$PY" -I "$@" >"$W/stdout.txt" 2>"$W/stderr.txt"
	code=$?
	set -e
}

echo '--- all models'
run "$MODELS" --db "$(native "$DB")" --out "$(native "$W/out")"
check 'exit code' 0 "$code"
files=0
for m in event-days weekends clocks trend; do
	for e in sql csv txt json; do [ -s "$W/out/model-$m.$e" ] && files=$((files + 1)); done
done
check 'four files per model' 16 "$files"
check 'copy of the script' same "$(cmp -s "$P/skills/analyse/scripts/models.py" "$W/out/models.py" && echo same || echo different)"
check 'input rows' '728|2023-01-02|2024-12-29' "$(j event-days "'%d|%s|%s' % (m['input']['rows'], m['input']['from'], m['input']['to'])")"

echo '--- event days'
check 'negative binomial for varied counts' True "$(j event-days "r['all-days/release']['method'].startswith('negative binomial')")"
check 'release ratio near 3' True "$(j event-days "2 < r['all-days/release']['estimate'] < 4.5 and r['all-days/release']['ci_low'] < 3 < r['all-days/release']['ci_high']")"
check 'release days counted' 34 "$(j event-days "r['all-days/release']['n_event']")"
check 'leave days left out' 703 "$(j event-days "r['all-days/release']['n']")"
check 'week before a release' True "$(j event-days "1.2 < r['all-days/pre_release']['estimate'] < 2.5 and r['all-days/pre_release']['p_value'] < 0.05")"
check 'patch ratio near 2' True "$(j event-days "r['all-days/patch']['ci_low'] < 2 < r['all-days/patch']['ci_high']")"
check 'three incidents not tested' 'None|Only 3 incident days: too few to test.' \
	"$(j event-days "str(r['all-days/incident']['estimate']) + '|' + r['all-days/incident']['reading'].split(' They')[0]")"
check 'incidents reported once' 0 "$(j event-days "sum(1 for k in r if k == 'active-days/incident')")"
check 'active days sample' True "$(j event-days "r['active-days/release']['n'] < r['all-days/release']['n'] and r['active-days/release']['estimate'] > 1")"
check 'reading names the controls' True "$(j event-days "'same weekday, month and year' in r['all-days/release']['reading']")"
check 'Ljung-Box reported' True "$(j event-days "0 <= m['diagnostics']['all-days']['ljung_box_p_14d'] <= 1")"

echo '--- weekends'
check 'weekends near a release' True "$(j weekends "r['weekend-days/near_release']['estimate'] > 1.2 and r['weekend-days/near_release']['p_value'] < 0.05")"
check 'weekend days' 208 "$(j weekends "r['weekend-days/near_release']['n']")"
check 'Fisher p stored' True "$(j weekends "'Fisher' in r['weekend-days/near_release']['reading'] and r['weekend-days/near_release']['p_value_wald'] is not None")"

echo '--- clocks'
check 'chat and commit agree' True "$(j clocks "r['chat-vs-commit/rho']['estimate'] > 0.8 and r['chat-vs-commit/rho']['median_gap_min'] < 20")"
check 'mail and commit do not' True "$(j clocks "abs(r['mail-vs-commit/rho']['estimate']) < 0.3 and r['mail-vs-commit/rho']['ci_low'] < 0 < r['mail-vs-commit/rho']['ci_high']")"
check 'no-link reading' True "$(j clocks "'no clear link' in r['mail-vs-commit/rho']['reading']")"

echo '--- trend and phases'
check 'rising trend' True "$(j trend "r['weeks/per_year']['ci_low'] > 1 and 'rose by' in r['weeks/per_year']['reading']")"
check 'weeks' 104 "$(j trend "r['weeks/per_year']['n']")"
check 'later phase higher' True "$(j trend "r['weeks/phase:second']['ci_low'] > 1")"

echo '--- model_results'
check 'one row per result' "$(j event-days "len(m['results'])")" "$(q "select count(*) from model_results where model = 'event-days'")"
check 'all four models' 'clocks;event-days;trend;weekends' "$(q 'select distinct model from model_results order by model' | paste -sd';' -)"
check 'every row has a reading' 0 "$(q "select count(*) from model_results where reading is null or reading = ''")"

echo '--- reruns'
run "$MODELS" --db "$(native "$DB")" --out "$(native "$W/again")"
same=0
for m in event-days weekends clocks trend; do
	cmp -s "$W/out/model-$m.json" "$W/again/model-$m.json" && cmp -s "$W/out/model-$m.csv" "$W/again/model-$m.csv" && same=$((same + 1))
done
check 'same files on a rerun' 4 "$same"
run "$(native "$W/out/models.py")" --db "$(native "$DB")" --out "$(native "$W/expert")" --model clocks
check 'the copy reruns' same "$(cmp -s "$W/out/model-clocks.json" "$W/expert/model-clocks.json" && echo same || echo different)"
check 'one model only' 'model-clocks.csv model-clocks.json model-clocks.sql model-clocks.txt models.py' "$(ls "$W/expert" | sort | tr '\n' ' ' | sed 's/ $//')"
check 'rerun keeps one row per result' "$(j event-days "len(m['results'])")" "$(q "select count(*) from model_results where model = 'event-days'")"
check 'the rerun line asks for a copy of the database' True "$(j event-days "'--db <copy of the database> ' in m['rerun']")"

# edit SQL COPY: COPY is the case database with SQL applied to it.
edit() {
	cp "$DB" "$2"
	"$PY" -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(sys.argv[2]); c.close()' "$(native "$2")" "$1"
}
# unestimated LABEL MODEL KEY DIR: the result KEY has counts only.
unestimated() {
	check "$1" 'None|None|None|None|not estimated' \
		"$(j "$2" "'|'.join(str(r['$3'][k]) for k in ('estimate', 'ci_low', 'ci_high', 'p_value', 'method'))" "$4")"
}

echo '--- event days without any trace'
QUIET='ooh_traces = 0, ooh_chat = 0, ooh_mail = 0, ooh_commits = 0, last_chat_h = null, last_mail_h = null, last_commit_h = null'
edit "update days set $QUIET where patch = 1;" "$W/zero.sqlite"
run "$MODELS" --db "$(native "$W/zero.sqlite")" --out "$(native "$W/zero")" --model event-days
check 'runs' 0 "$code"
unestimated 'no ratio, interval or p-value' event-days all-days/patch "$W/zero"
check 'days counted' '703|14' "$(j event-days "'%d|%d' % (r['all-days/patch']['n'], r['all-days/patch']['n_event'])" "$W/zero")"
check 'reading gives the counts' \
	"The 14 patch days had no out-of-hours traces, against $(q "select sum(ooh_traces) || ' on the ' || count(*) from days where off is null and patch = 0" "$W/zero.sqlite") other days; a ratio cannot be estimated with a zero." \
	"$(j event-days "r['all-days/patch']['reading']" "$W/zero")"
check 'reported once, not for the active days' 0 "$(j event-days "sum(1 for k in r if k == 'active-days/patch')" "$W/zero")"
check 'other terms still estimated' True "$(j event-days "r['all-days/release']['estimate'] > 1 and r['active-days/release']['estimate'] > 1" "$W/zero")"
check 'empty in model_results' 1 \
	"$(q "select count(*) from model_results where model = 'event-days' and sample = 'all-days' and term = 'patch' and estimate is null and ci_low is null and ci_high is null and p_value is null" "$W/zero.sqlite")"
edit "update days set $QUIET where patch = 1; update days set ooh_traces = 2 where day = (select min(day) from days where patch = 1);" "$W/one.sqlite"
run "$MODELS" --db "$(native "$W/one.sqlite")" --out "$(native "$W/one")" --model event-days
check 'traces on one of those days: estimated' True "$(j event-days "r['all-days/patch']['estimate'] is not None" "$W/one")"

echo '--- all traces on event days'
edit 'update days set ooh_traces = 0 where release = 0; update days set ooh_traces = 2 where release = 1;' "$W/only.sqlite"
run "$MODELS" --db "$(native "$W/only.sqlite")" --out "$(native "$W/only")" --model event-days
check 'one term: runs' 0 "$code"
unestimated 'one term: no ratio, interval or p-value' event-days all-days/release "$W/only"
check 'one term: reading gives the counts' \
	'The 34 release days had 68 out-of-hours traces, against none on the 669 days that were not release days; a ratio cannot be estimated with a zero.' \
	"$(j event-days "r['all-days/release']['reading']" "$W/only")"
check 'one term: nothing again for the active days' 0 "$(j event-days "sum(1 for k in r if k.startswith('active-days/'))" "$W/only")"
edit 'update days set ooh_traces = 0 where release = 0 and patch = 0;' "$W/both.sqlite"
run "$MODELS" --db "$(native "$W/both.sqlite")" --out "$(native "$W/both")" --model event-days
check 'two terms: runs' 0 "$code"
check 'two terms: reading names both' \
	"The 14 patch days had $(q 'select sum(ooh_traces) from days where patch = 1 and off is null' "$W/both.sqlite") out-of-hours traces, against none on the 655 days that were not release days or patch days; a ratio cannot be estimated with a zero." \
	"$(j event-days "r['all-days/patch']['reading']" "$W/both")"

echo '--- event days on exactly the days of a weekday'
edit "update days set release = (strftime('%w', day) = '3'), patch = 0;" "$W/wed.sqlite"
run "$MODELS" --db "$(native "$W/wed.sqlite")" --out "$(native "$W/wed")" --model event-days
check 'runs' 0 "$code"
unestimated 'no ratio, interval or p-value' event-days all-days/release "$W/wed"
check 'reading gives the counts' \
	"The $(q 'select count(*) from days where off is null and release = 1' "$W/wed.sqlite") release days fall on exactly the days of a weekday, month or year, or of another event: their effect cannot be told apart from it. They had $(q 'select sum(ooh_traces) from days where off is null and release = 1' "$W/wed.sqlite") out-of-hours traces, the $(q 'select count(*) from days where off is null and release = 0' "$W/wed.sqlite") other days $(q 'select sum(ooh_traces) from days where off is null and release = 0' "$W/wed.sqlite")." \
	"$(j event-days "r['all-days/release']['reading']" "$W/wed")"

echo '--- phases without any trace'
edit "update days set ooh_traces = 0 where phase = 'second';" "$W/phase.sqlite"
run "$MODELS" --db "$(native "$W/phase.sqlite")" --out "$(native "$W/phase")" --model trend
check 'later phase: runs' 0 "$code"
unestimated 'later phase: no ratio, interval or p-value' trend weeks/phase:second "$W/phase"
check 'later phase: reading gives the counts' \
	"The phase 'second' had 0 out-of-hours traces in 43 weeks, against $(q 'select sum(ooh_traces) from days where off is null' "$W/phase.sqlite") in the 61 weeks of 'first'; a ratio cannot be estimated with a zero." \
	"$(j trend "r['weeks/phase:second']['reading']" "$W/phase")"
edit "update days set ooh_traces = 0 where day < '2024-03-04';" "$W/first.sqlite"
run "$MODELS" --db "$(native "$W/first.sqlite")" --out "$(native "$W/first")" --model trend
check 'first phase: runs' 0 "$code"
unestimated 'first phase: no ratio, interval or p-value' trend weeks/phase:second "$W/first"
check 'first phase: reading gives the counts' \
	"The phase 'second' had $(q 'select sum(ooh_traces) from days where off is null' "$W/first.sqlite") out-of-hours traces in 43 weeks, against 0 in the 61 weeks of 'first'; a ratio cannot be estimated with a zero." \
	"$(j trend "r['weeks/phase:second']['reading']" "$W/first")"
edit "update days set phase = case when day < '2023-09-04' then 'first' when day < '2024-03-04' then 'middle' else 'last' end; update days set ooh_traces = 0 where phase = 'middle';" "$W/middle.sqlite"
run "$MODELS" --db "$(native "$W/middle.sqlite")" --out "$(native "$W/middle")" --model trend
check 'middle phase: runs' 0 "$code"
unestimated 'middle phase: no ratio, interval or p-value' trend weeks/phase:middle "$W/middle"
check 'middle phase: the others are compared' True "$(j trend "r['weeks/phase:last']['estimate'] is not None" "$W/middle")"
check 'middle phase: its weeks leave the fit' '78|1' \
	"$(j trend "r['weeks/phase:last']['n']" "$W/middle")|$(grep -c 'No. Observations: *78' "$W/middle/model-trend.txt")"
check 'middle phase: named in the samples and the method' True \
	"$(j trend "any('middle' in s for s in m['samples']) and 'middle' in r['weeks/phase:last']['method']" "$W/middle")"

echo '--- no trace in the whole window'
edit 'update days set ooh_traces = 0;' "$W/silent.sqlite"
run "$MODELS" --db "$(native "$W/silent.sqlite")" --out "$(native "$W/silent")"
check 'runs' 0 "$code"
check 'no trend' 'None|No out-of-hours traces in any of the 104 weeks: no trend to estimate.' \
	"$(j trend "str(r['weeks/per_year']['estimate']) + '|' + r['weeks/per_year']['reading']" "$W/silent")"

echo '--- refusals'
bad() {
	edit "$1" "$W/bad.sqlite"
	run "$MODELS" --db "$(native "$W/bad.sqlite")" --out "$(native "$W/bad")"
}
bad "delete from days where day = '2024-02-29';"
check 'missing day refused' '1|1' "$code|$(grep -c '1 missing, first 2024-02-29' "$W/stderr.txt")"
bad "update case_info set value = '2025-01-05' where key = 'window_to';"
check 'window mismatch refused' '1|1' "$code|$(grep -c 'case_info has the window' "$W/stderr.txt")"
bad "update days set release = 2 where day = '2023-01-18';"
check 'flag other than 0 or 1 refused' '1|1' "$code|$(grep -c 'release must be 0 or 1' "$W/stderr.txt")"
bad "delete from days;"
check 'empty days refused' '1|1' "$code|$(grep -c 'days is empty' "$W/stderr.txt")"
"$PY" -I -c 'import sqlite3, sys; sqlite3.connect(sys.argv[1]).close()' "$(native "$W/none.sqlite")"
run "$MODELS" --db "$(native "$W/none.sqlite")" --out "$(native "$W/bad")"
check 'no days table refused' '1|1' "$code|$(grep -c 'has no table days' "$W/stderr.txt")"
check 'nothing written on refusal' no "$([ -e "$W/bad" ] && echo yes || echo no)"

echo
if [ "$fails" != 0 ]; then
	echo "$fails failed; the test files are in $W"
	exit 1
fi
rm -rf "$W"
echo 'all passed'
