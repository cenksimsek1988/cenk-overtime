# Out-of-Hours Work Evidence: A Practical Method

The method behind the `cenk-overtime` plugin, written for people. The plugin runs these steps with Claude: install it as the [README](../README.md) describes and type `/cenk-overtime:start`.

## Who this guide is for

An employee's own digital traces — sent emails, chat messages, calls, code commits — can show, hour by hour, when they worked outside their contract hours. This guide turns those traces into a package a lawyer can file and a court expert can check. It was first worked out on a real claim and is written to work for any employer and any job.

**Who can use it**

- **Employees** preparing a claim for unpaid overtime, or simply documenting their workload before they leave a job.
- **Lawyers and court experts** who receive such a package and need to know how it was built, what it proves and where it is weak.
- **Anyone helping**, including an AI assistant, who does the collection and analysis for the employee.

**What it produces**

- A short summary report (about 4 pages) and a full report with charts.
- A spreadsheet whose totals are live formulas, and a database with ready-made queries.
- The underlying records, with passwords and private matters masked.
- A small tool that rebuilds every table from those records, and a list of file fingerprints (SHA-256 hashes) that shows nothing was changed later.

**What it does not do**

- It is not legal advice. Rules on what evidence you may collect, and how overtime is proven and paid, differ by country and contract. Talk to a lawyer before you export anything from employer systems.
- It does not calculate pay. It gives a low and a high estimate of hours; the lawyer applies the law.
- It cannot show work that left no trace. Reading code, thinking, or a call on a personal phone leaves nothing behind unless it is logged somewhere.

The method has seven steps: 1 Collect → 2 Normalize → 3 Count → 4 Estimate time → 5 Correlate → 6 Mask → 7 Package, followed by verification by the lawyer and the court expert against the employer's own systems. Steps 1 to 4 produce the numbers, steps 5 and 6 make them convincing and safe to share, and step 7 makes them checkable.

## Core principles

1. **Collect before access ends.** Work accounts are usually closed on the last day, and the records cannot be collected again. Export everything you may need while you still can, even before you decide to make a claim.
2. **Keep the originals untouched.** Work on copies only. On the day of collection, compute a SHA-256 fingerprint of each original file and email it to yourself or a third party, so the date is on record.
3. **Count conservatively.** When two timestamps of the same message disagree, count it only if both fall outside working hours. Keep doubtful items in a separate category instead of counting them. Always give a low and a high estimate side by side.
4. **Make every number traceable.** Every figure must lead back to concrete message IDs or commit hashes that the employer can look up in its own systems. A number nobody can check is worth little.
5. **Apply one rule to everything.** Rules are written down before counting and applied to all records the same way. Any decision made by hand ("this message is not a release") is logged with its reason.
6. **Protect privacy by default.** Passwords, other people's private lives and the employee's own unrelated private matters are masked. Masked messages still count by their time; only the text is hidden.
7. **Describe, don't claim causes.** The data may show that late nights cluster around releases; it does not prove what caused them. Say plainly what the data cannot show.

## Step 1 — Preserve and collect

Collect what **you sent or did**, not what you received: a received email proves nothing about your work, a sent one does.

| Source | How to get it | What it shows | Watch out for |
| --- | --- | --- | --- |
| Work chat (Teams, Slack, Google Chat) | Search by sender = you, per time window, through the platform's search or API; or a workspace export | When you wrote, in which chat, about what | Search results are capped, so one big query silently misses messages |
| Email | Export the Sent folder (PST, MBOX or EML) or search it through the mail API | Send times, recipients such as customers or managers | Use the Date header and message ID; mind the time zone in the header |
| Calendar and meetings | Calendar export (ICS); meeting chats; join logs if available | Meetings held outside working hours | An invitation is not attendance; join logs are stronger |
| Calls | Teams or Slack call history; phone call log export; carrier bill | Start time and duration, so worked time directly | A personal phone log shows numbers only; map them to colleagues |
| WhatsApp, Telegram, Signal | Per chat: Export chat, without media (a text file) | Work groups kept on a personal phone | The line format depends on phone language and OS; times are the phone's local time; private talk is mixed in |
| Git and code review | Read-only git commands on your local copies: author date, hash, subject line, files and lines changed, tags, release branches | When code was written, independent of any chat | Find all your author addresses; never copy source code; local copies may miss branches |
| Issue tracker (Jira and similar) | Issue history and changelog export | Status changes and comments at night | Usually only the employer can export it |
| Build, deployment and release systems | Pipeline runs, image pushes, release records | Exact release moments | Employer-held; request them |
| VPN, single sign-on, badge, server and audit logs | Request through the lawyer | Being online or on site | Employer-held; ask early, logs are deleted after a while |
| Your own notes, photos, screenshots | Keep the originals with their file dates | Context that no system recorded | Weaker on their own; they support the rest |

**How to search a chat platform without missing messages**

- Split the whole period into out-of-hours windows: each weekday evening from end of work to the next morning's start (for example 18:00 to 09:01), and each weekend from Friday evening to Monday morning. Keep the list of windows, so anyone can check that none is missing.
- Run one search per window, filtered to messages sent by the employee. Save each window's raw result as its own file.
- Record which windows returned nothing, and later re-run a sample of those to show the emptiness is real.
- Merge everything, remove duplicates by message ID, and check for copies that landed in the wrong window's file.
- If an AI assistant runs the searches through a connector to the work account, the same rules apply: one window per query, raw results saved, empty windows logged.

## Step 2 — Normalize

Put every trace from every source into one table of records with the same columns, in one time zone.

- **Time zone: use the contract's.** Convert every timestamp to the employer's time zone with its real offset. If the employee lived elsewhere, say so.
- **Use two timestamps when the source has them.** Teams message IDs contain the send time in milliseconds. Count a message only when both clocks say "outside working hours", and list the few where they disagree.
- **Separate scheduled sends.** Messages sent exactly at the start of the working day (say 09:00:00–09:00:59) may have been scheduled. Keep them in their own category, outside the overtime count.
- **Remove duplicates by ID**, and log the copies you removed.
- **Collect every identity the person used**: work email, personal email, an old employer's address, a computer's default git identity ("name@machine" or "name@10.x.x.x").
- **Name the conversations.** In a one-to-one chat, every quoted author who is not the employee is the other person, so quotes reveal the chat's name.
- **Leave out what is not communication**: "notes to self" chats, drafts, bots.
- **Restrict to the employment period** agreed with the lawyer, and cut every source to that window.

## Step 3 — Count out-of-hours activity

| Category | Time (employer's time zone) | Belongs to the activity period of |
| --- | --- | --- |
| Evening | Weekday 18:00–23:59 | That day's evening |
| Night | Weekday 00:00–05:59 | The previous day's evening (work that ran past midnight) |
| Early morning | Weekday 06:00–08:59 | That day's morning |
| Weekend | Saturday and Sunday, all day | That day, from 06:00 to 06:00 the next morning |
| Scheduled send | Weekday 09:00:00–09:00:59 | Not counted (shown separately) |
| Working hours | Weekday 09:01–17:59 | Not counted |

Adapt the hours to the contract. An **activity period** is one evening, one early morning or one weekend day with at least one trace.

**Measures worth reporting:** out-of-hours messages by category and periods by type; the time of the last trace in each evening (median; evenings ending after 20:00, 22:00, midnight); a weekly bar chart and a day-by-hour heat map; a sensitivity check with the working day ending at 18:15 or 18:30.

**Two tiers of conversations:** core (clearly work: team groups, release channels, the manager one-to-one) for the main analysis; all chats as supporting evidence, with a lower bound of work content (the share of messages with technical or work terms; short replies such as "ok" never match, so it is a lower bound).

## Step 4 — Estimate working time

| Estimate | Rule | What it assumes |
| --- | --- | --- |
| Conservative (sessions) | Traces less than 60 minutes apart form one session; sessions are summed from first to last trace. Gaps over 60 minutes and single-message sessions count as zero. | You worked only while traces were close together |
| Observed span | First to last trace of the period | Continuous work between the first and the last trace |
| Continuous | Weekday evening: end of the working day to the last trace. Early morning: first trace to the start of work. Weekend: first to last trace. | You worked without a break from the end of the shift |

Report weekdays, weekends and the total separately, per worked day and per week. Weekly averages divide by all weeks in the period, including quiet weeks, holidays and leave; say so next to the figure. A results table can look like this:

| Per week, on average | Conservative | Continuous |
| --- | --- | --- |
| Weekday evenings and mornings | … h … min | … h … min |
| Weekends | … h … min | … h … min |
| **Total** | **… h … min** | **… h … min** |
| Total over the whole period | … hours | … hours |

Showing both estimates lets the reader see a range instead of a single number that is easy to attack.

**The "trace" limit.** A day with no message or commit counts as zero, and hours before the first trace are invisible. Report how many weekend days had any trace at all, and the median time of the first weekend trace, so readers see how much the data cannot show.

**The employee's own account** (for example "on the weekends I worked, I usually started late in the morning and took a couple of hours of breaks") is computed as a separate, labelled scenario, with a range. It can change the totals a lot, so it is never mixed into the data-based figures: it is testimony, not data.

**Git adds what chat misses:** evenings with commits but no messages, and later end times on evenings that had both.

## Step 5 — Correlate with releases, patches and incidents

- Find events in the employee's own words with explicit patterns; classify tense (done, in progress, told afterwards, intent); date events only from done or in-progress messages; complete abbreviated version names ("rc1") from context and log how; mark re-releases separately; log manual decisions.
- Compare event days with other days that also had out-of-hours activity (not with all calendar days); look at seven days before to three after, excluding other event days; split by year.
- Group the activity periods and compare the groups:

| Period group | Periods | Estimated time per period | Ran past midnight |
| --- | --- | --- | --- |
| A release was done that evening | count | conservative – continuous | share |
| Production bug or patch discussed | count | conservative – continuous | share |
| Other periods | count | conservative – continuous | share |

**Git as an independent clock:** keep only product version tags and release/patch branches; drop ticket, customer, build and bulk-migration tags; a lightweight tag carries the tagged commit's date, a release branch its last commit's date.

**Test the patterns with standard models.** Counting shows a pattern; a regression model checks it against comparable days and says how sure the data can be. Four basic checks run on one row per day of the employment:

| Check | Question | A result reads like (made up) |
| --- | --- | --- |
| Event days | More out-of-hours work on release, patch and incident days than on other days with the same weekday, month and year? | "Release days had 2.1 times as many out-of-hours traces (95% interval 1.6 to 2.8)" |
| Weekends | More weekend work near a release? | "Weekend days before a release had work twice as often" |
| Two clocks | Do commits and chat show the same end of the evening? | "Last commit and last message a median 20 minutes apart" |
| Trend | Did the load grow over the employment, or after a change of employer or role? | "Out-of-hours traces per working day rose by 15% a year" |

How to read them: the ratio is the size of the effect; the 95% interval is the range the data allow, and when it includes 1 the data cannot tell the difference from none; the p-value is how often a difference this large would appear by chance if there were none. They do not show a cause (releases come with deadlines and staffing changes), work that left no trace, or anything firm from a handful of event days. Busy days come in runs, so the intervals allow for days of the same week being alike. Several checks at once mean about one in twenty can pass by chance, so the report says how many were run. Event days found from out-of-hours messages always have some activity: the fairest figure compares them only with other days that had out-of-hours activity, and events dated from git, independent of the messages, weigh more. The code, its input rows and its output stay with the package, so the court expert can run it again and get the same numbers.

## Step 6 — Privacy, credentials and confidentiality

- Scan every text for passwords, keys, tokens, internal IPs, database addresses and share links; keep literal passwords in a local file used only for masking, outside the case folder and never in the package, and delete it when the package is final; mask whole messages that contain a login; rescan every output and after every scope change.
- Read every message for private matters (parallel reviewers from one written brief). Group A: the employee's own unrelated private life, masked on request. Group B: anyone else's private information, always masked. The employee chooses what of their own to keep (e.g. health that supports a claim of strain).
- Masked messages keep their time and still count. Never publish counts by private topic.
- Do not mask unflattering work content; tell the lawyer about private messages that could be used against the employee (job hunting, side business, errands during hours).
- Keep customer names out of narrative reports; mark the package confidential.

## Step 7 — Build the evidence package

| File or folder | Contents | Main reader |
| --- | --- | --- |
| 1_Summary.pdf | 3–4 pages: key numbers, findings with one example each, weekly chart, what the report does not show | Lawyer, judge |
| 2_Report.pdf | Method, distributions, time estimates, release analysis, git, validation and limitations; annexes with every period, event evidence, manual decisions, data dictionary | Court expert |
| 3_Data_Tables.xlsx | One sheet per table; live formulas checked against the database | Anyone |
| 4_Database/ | SQLite, CSV per table, ready-made queries | Court expert, analyst |
| 5_Raw_Data/ | Masked records, collection notes, git metadata | Court expert |
| 6_Method_and_Tool/ | Script that rebuilds everything from 5_Raw_Data, and a how-to | Court expert |
| HASHES_SHA256.txt, README | Fingerprints; how it was made (with AI help); contents, confidentiality, verification | Everyone |

Make it reproducible (the packaged tool rebuilds identical tables), remove cache files before hashing, deposit the zip's SHA-256 the same day, and have an independent audit before hand-over. When an AI assistant built the package, say so on the summary, the report and the README. The package is a draft until the lawyer has checked it: nothing is filed or sent to the employer before that.

## For lawyers

| Evidence | Proves | How to verify |
| --- | --- | --- |
| Work chat messages | A work message sent at that minute | Message ID in the employer's Microsoft 365 or Slack records (eDiscovery) |
| Sent emails | A sent email at that minute, to that recipient | Message ID and headers on the employer's mail server |
| Commits | Code authored at that minute | Commit hash on the employer's Git server; push logs |
| Release tags and branches | A release at roughly that moment | Git server, build and release records |
| Calls | Duration of a work call | Platform or carrier records |
| Employee's statement | Work that left no trace | Witnesses, consistency with the traces |

| Objection | Answer |
| --- | --- |
| "Messages are not work." | Main analysis uses work chats only; examples quoted; peaks around releases and incidents |
| "It was social chatting." | All-chats figures shown separately, with a lower bound of work content |
| "Timestamps can be edited." | Every record has an ID the employer can check; two independent chat clocks; commits on the employer's server |
| "Messages were scheduled." | Start-of-day sends excluded |
| "The employee lived in another time zone." | All times in the contract's time zone; local time stated |
| "The employee made up for it during the day." | In-hours activity not collected; the employer's attendance and leave records answer this |
| "Commit dates were rewritten." | Author date used; differing commit dates flagged |
| "The line counts are inflated." | Medians per commit given next to totals |
| "It is a coincidence." | Regression checks against comparable days, with intervals, p-values and the number of checks run |

Records worth requesting from the employer: Microsoft 365 or Slack audit logs and eDiscovery exports; VPN, single sign-on and remote-desktop logs; Git server push events, build and deployment logs, release calendar; issue tracker histories; on-call schedules, overtime approvals, leave and attendance records. Ask early: many logs are kept only for months.

## Pitfalls and lessons learned

| Pitfall | Fix |
| --- | --- |
| One big search returned a capped result | One query per out-of-hours window; log and re-check empty windows |
| Records saved into the wrong window's file with a wrong chat ID | Dedupe by message ID; keep the copy from its own window |
| Keyword rules fired on quoted text | Classify only the employee's own words |
| A release told afterwards was dated to the evening it was mentioned | Classify tense; date only from done or in-progress messages |
| Release days compared with all calendar days | Compare with other days that had out-of-hours activity |
| Years before the direct employment crept in | Cut every source to the agreed employment window |
| Commits under other identities were missed | List all identities first; mask IPs inside author emails |
| Several local clones multiplied the commits | Dedupe by hash; merge by remote |
| An ambiguous keyword (a product component called "agent") was counted as AI work | Avoid ambiguous keywords |
| A few huge commits inflated line totals | Report medians per commit |
| Weekly averages looked low | Also show per-worked-day figures; explain the denominator |
| Passwords surfaced late when scope grew | Rescan everything, including outputs, on every scope change |
| Early drafts with unmasked passwords were shared | Version every package; tell the recipient not to share old ones |
| Cache files broke the hash list | Prevent caches; remove before hashing |
| Git over a slow network drive timed out | Batch and parallelize; never copy the repository |

## Appendix: record schema and glossary

The example values are made up.

| Column | Example | Note |
| --- | --- | --- |
| record_id | 1700000000000 / a1b2c3d4… | Message ID, email Message-ID, commit hash, call ID |
| source | teams, email, whatsapp, call, git | One value per system |
| channel | release channel; manager one-to-one; repository | Decides core vs all-chats tier |
| time_utc | 2025-03-14T19:46:30Z | As stored |
| time_contract | 2025-03-14 22:46:30 | Contract time zone |
| time_second_source | from the message ID | Only when a second clock exists |
| category | evening, night, early morning, weekend, scheduled, working hours | From time_contract |
| period_id | 2025-03-14_evening | Activity period |
| own_text | "2.4 is out, images pushed" | Employee's own words; masked when required |
| quoted_author | colleague's name | Empty when not a reply |
| tags | release, patch, prod_bug, customer, ai_tool | From written rules |
| versions, tickets | 2.4.0-rc1; PROJ-123 | From own_text |
| lines_added, lines_deleted, files | 120, 30, 5 | Commits only |
| masked, mask_reason | 1, "another person's private life" | Decisions table |

- **Trace:** any timestamped record the employee created.
- **Activity period:** one evening, early morning or weekend day with at least one trace.
- **Conservative estimate:** time between traces less than 60 minutes apart, summed.
- **Continuous estimate:** work assumed without a break from the end of the shift to the last trace.
- **Event:** a release, re-release, patch or deployment, dated from the employee's message or from git.
- **Core chats:** conversations clearly about work.
- **Author date:** when a commit was written; survives rebasing.
- **SHA-256 hash:** a file fingerprint; any change alters it.
