---
name: "analyse"
description: "Counts your out-of-hours work from the collected traces (evenings, nights, mornings and weekends) and estimates the hours, conservatively and continuously, with weekday and weekend apart, and shows how the overtime clusters around releases, patches and incidents, with regression checks explained in plain words. Use for: how many overtime hours did I work, calculate my unpaid overtime hours, count my weekend work, fazla mesai saatlerimi hesapla, kaç saat fazla mesai yaptım, calcolare le ore di straordinario, quante ore di straordinario ho fatto, Überstunden berechnen, wie viele Überstunden habe ich gemacht, calcular mis horas extra, cuántas horas extra hice, calculer mes heures supplémentaires, combien d'heures supplémentaires ai-je faites."
user-invocable: false
---

# Overtime evidence: analysis

Input: the normalized trace table from `cenk-overtime:collect`. Output: tables, charts and plain-language findings that a lawyer and a court expert can check. Package building and masking are in `cenk-overtime:court-package`.

Rules: write definitions before counting; apply them to every record; log every manual decision with its reason; be conservative when in doubt; describe, never claim causes.

## 1. Definitions (adapt hours to the contract)

| Category | Time (contract zone) | Activity period |
|---|---|---|
| evening | weekday 18:00-23:59 | that day's evening |
| night | weekday 00:00-05:59 | previous day's evening (ran past midnight) |
| morning | weekday 06:00-08:59 | that day's morning |
| weekend | Sat/Sun all day | that day, 06:00 -> next day 06:00 |
| scheduled | weekday 09:00:00-09:00:59 | not counted |
| in hours | weekday 09:01-17:59 | not counted |

Public holidays: ask whether to treat them as weekend days.
A trace counts only if both clocks (when two exist) are out of hours.

## 2. Tiers

- **Core**: clearly-work conversations + commits. Main analysis.
- **All chats**: everything, shown beside core as supporting evidence. Give a work-content lower bound: share of messages matching a work-term regex (release, branch, commit, merge, deploy, ticket key, sql, bug, test, server, customer...). Short replies ("ok") never match, so say it is a lower bound. Also: periods with activity only in non-core chats and how many contain a work term.

## 3. Counts to report

- Messages per category; periods per type; weekly bars (core dark, other chats light, stacked).
- Last-activity time per evening: median; evenings ending after 20:00, 22:00, midnight. Day x hour heat map.
- Sensitivity: recount with shift end 18:15 / 18:30 (late evenings unchanged).
- With git: periods with commits, periods with both, git-only periods; out-of-hours commits; median files and +/- lines per commit next to totals (a few huge commits inflate totals: report the top-5 share).
- Count git work as events, not hashes: a rebased, cherry-picked or amended copy carries the same author time. First give every copy reworded in the same author second the subject of the row committed first (`committer_utc`), then count one event per author time in UTC to the minute and subject. Report merges apart from the other commits.
- Times come from `author_utc` in the contract zone, never from the offset the author's computer had.

## 4. Working-time estimates

```python
def session_minutes(times, gap=60):
    """Conservative: sum first-to-last of sessions; gaps > gap min and single traces count 0."""
    ts = sorted(times); total = 0; start = prev = ts[0]
    for t in ts[1:]:
        if (t - prev).total_seconds() / 60 > gap:
            total += (prev - start).total_seconds() / 60; start = t
        prev = t
    return total + (prev - start).total_seconds() / 60

def upper_minutes(kind, day, first, last):
    """Continuous: evening = shift end -> last trace; morning = first trace -> shift start; weekend = first -> last."""
```

Also keep observed span (first -> last trace). Hours come from these sessions and days; a count of commits never becomes hours.

Present separately for **weekday (evenings + mornings), weekend, total**:
- per worked day (average over periods with a trace),
- weekly average = total / all weeks in the window (state that quiet weeks, holidays and leave are in the denominator),
- total hours over the whole window.

Explain the trace limit in plain words: a day without any message or commit counts as zero; hours before the first trace are invisible (report the median first-trace time on weekends). If the person states habits ("on worked weekends I started ~11:00, 1-2 h breaks"), compute that as a separate scenario labelled as the person's statement, with a range, and also restricted to clearly-worked days (> 3 traces), never mixed into the data-based figures.

When the person asks for numbers, answer with a small table (weekday / weekend / total x conservative / continuous) and two sentences on what each assumes. Clarify what git alone shows (fewer days but later ends) vs chat + git (most complete).

## 5. Release, patch and incident events from the person's words

1. Write explicit regex rules for real phrasing in the data (look at samples first; include typos and the local language): "released X", "X is out", "branch is ready", "images pushed", "patch shipped", "re-released/updated X".
2. Tense per match: done, in progress, retrospective ("when I released it"), intent ("I'll release"). Date events only from done/in-progress. Retrospective and intent-only events are listed but excluded from analysis.
3. Version completion for abbreviations ("a7"): same period full name -> same full name mentioned within -30/+7 days -> bracketing versions within 45 days. Record the rule used per event.
4. Mark updates/re-releases of a version separately from first releases. Merge multiple messages of one event; keep all as evidence ids.
5. Manual include/exclude/version fixes go into a decisions table with reasons. Quoted text is never evidence of the person's own action.
6. Prod incidents / patches / customer work: tag messages (prod bug, hotfix, patch, customer name list). Use message tags only when grouping periods; commit subjects with "fix" do not make an incident.

## 6. Fair comparisons

- Event days are found from out-of-hours messages, so they always have some. Compare them with **other days that have out-of-hours activity**, and separately with all days; never only with all days.
- Event study: average daily out-of-hours messages for offsets -7..+3 around each event day, excluding at non-zero offsets any day that is itself an event day; reference line = average of all non-event days.
- Year-stratified: 7-day pre-event windows vs other days per year, event days removed from both.
- Period groups: release periods / incident-or-patch periods / other: count, mean messages, mean commits, conservative and continuous time, % evenings past midnight.
- Phrase all of it as descriptive ("clusters around"), never causal.
- Section 8 tests the same comparisons with regression models.

## 7. Git as an independent clock

- Release anchors only from the employer's product repos the person released.
- Keep tags matching product version names (e.g. `^(?:(?:release|patch)/)?(?:prefix-)?\d+\.\d+\.\d+(?:\.\d+)?(?:-a\d+|-patch\d+)?$`) and `release/` or `patch/` branches with such versions. Drop ticket, customer, build-timestamp and other-component tags; drop tags created in bulk on one day (repository migration) and say how many were dropped and why.
- Lightweight tag date = tagged commit's date; release branch date = last commit on it. State both in limitations.
- Do not use other teams' repos' tags as anchors; their commits by the person still count as work.
- Keyword tags on commit subjects: avoid ambiguous words (e.g. "agent" meaning a product component, not AI).

## 8. Regression checks

After sections 3 to 7, test the patterns with `scripts/models.py` in this skill's base directory. It needs pandas, numpy, statsmodels and scipy; the Tools section of `cenk-overtime:start` installs them.

1. Run `scripts/schema.sql` of `cenk-overtime:start` on `master.sqlite` again: it adds the table `days` to an older database.
2. Ask once whether the employer, role or team changed inside the window, and since when. Each period is a `phase`.
3. Fill `days` with one row per calendar day of the window, from `traces`, `commits` and the events of sections 5 and 7, by the definitions of section 1: the activity day, counted traces only (out of hours on every clock, no scheduled sends), core tier, and commits counted as events (section 3). Leave, sick days and public holidays get `off`. Save the query as `work/queries/days.sql`.
4. Run `python models.py --db "<case>/master.sqlite" --out "<case>/work/queries"`. Per model it writes `model-<name>.sql` (the query it read), `.csv` (the rows it used), `.txt` (the full output) and `.json` (estimates and readings), copies itself there, and fills `model_results`.

| Model | Question | Method |
|---|---|---|
| `event-days` | More out-of-hours work on release, patch and incident days, and in the week before a release? | Daily counts; Poisson, or negative binomial when they vary more; weekday, month and year controls; errors clustered by week; all days, then days with any out-of-hours trace |
| `weekends` | More weekend work near a release or a fix? | Risk ratio, and Fisher's exact test for small counts |
| `clocks` | Do commits, chat and mail show the same end of the evening? | Spearman correlation of the last times on days with both; the median gap in minutes |
| `trend` | Did the load change over the employment, or between its phases? | Weekly counts, working days as exposure, Newey-West errors over 4 weeks |

Reading the results, in the report's language, with the script's numbers unchanged:
- Start from each result's `reading` line.
- Effect size: a rate ratio of 1.8 means 80% more out-of-hours traces than on comparable days; a risk ratio of 2.0, twice as often; a Spearman correlation of 0.7, that the two clocks rise and fall closely together (1 always together, 0 no link).
- 95% CI: the range of values the data allow. When it includes 1 (0 for a correlation), say that the data cannot tell the difference from none.
- p-value: how often a difference this large would come up by chance if there were none. It is not the chance that the finding is true; below 0.05 is the usual line.
- With every result, say what it does not show:
  - Association, not cause: releases come with other things (deadlines, staffing, a customer).
  - Days without traces count as zero; work that left no trace stays out.
  - Under 10 event days the reading says "indicative"; under 5 the script gives counts only.
  - Busy days come in runs. The errors allow for days of the same week being alike; a Ljung-Box p below 0.05 (in `diagnostics`) means the runs last longer, and the intervals may be too narrow.
  - Several tests at once: give their number (`tests` in each JSON file); about one in twenty passes 0.05 by chance.
  - Event days found from out-of-hours messages always have some activity: lead with the active-days results and with events dated from git (`events_from`).
  - The clocks model supports the timestamps, not the hours between them.
- Never "caused", "because of" or "proves"; write "went with", "was higher on".

## 9. Outputs for the package

SQLite tables: messages (with tier flags, categories, period ids, tags, versions, tickets, masked flag), periods (core) and periods_all (all chats) with counts, first/last activity, session/observed/upper minutes, events, event evidence, commits, tags, release branches, repo summary, `days` and `model_results` (section 8), manual decisions, dropped copies, validation checks, metadata. Views: monthly summary, event pre/post windows, prod/patch messages, chat summary, AI/tool records (Teams and commits kept apart). Keep every number in the reports computable from these tables.

In a case folder from `cenk-overtime:start`: tables go into `master.sqlite`, charts and drafts into `work/`, each artifact's query into `work/queries/<artifact>.sql`, and each model's files next to them (section 8). Nothing goes into `for-lawyer/`: these outputs are not masked yet, and the lawyers see that folder at once. `cenk-overtime:court-package` delivers there.