# Changelog

## 0.8.1 - 2026-11-10

Gaps the commit review of 0.8.0 found.

- `court-package`, section 3: the other git fields of client repositories follow the commit subjects. The repository ships as its label in every output, branch names, tag names and messages and file paths as hashes or not at all, and addresses and local paths stay out. Those repositories' rows are scanned for the customer list and ticket prefixes. The pattern that found the author's commits stays out.
- `court-package`, section 2: a mask decision ships with its id and group only, in the packaged tables and the report's annex; its reason stays in `master.sqlite`. A masked mail's subject is masked too, unless the review passed it.

## 0.8.0 - 2026-11-10

Method gaps found by an independent audit of an evidence package.

- `court-package`, section 2: group B also covers get-well and condolence wishes, job candidates (names, CV file names, contact cards, pay expectations), and colleagues' pay, job search, resignation and character judgments. Team-management content stays as work content and is recorded as a decision. The person's own pay, raises, shares, job offers and own lawyer's advice are group A unless they decide otherwise: ask, or mask by default and tell them and the lawyer.
- `court-package`, section 2: the safety-net sweep also searches get-well phrases, attachment lines whose file name is a person's name, and login names of customer systems. Mask probes use several windows per message and skip mail subject lines that other mails share. The reason for a day off never ships, and every output is scanned for reason words. The customer-name scan includes the main client and client-project repository names.
- `court-package`, section 3: commit subjects of client repositories ship only as SHA-256 hashes, except a quoted subject checked by its hash, and git authors ship as generic labels.
- `court-package`, section 4: Saturday, Sunday and public-holiday hours are separate rows. The reports say what an evening past midnight is, that commit times come from the author's own clock and are unverified without the server's records, and the integrity date. Merge commits and bursts of identical commits are reported apart. A non-core tier that is only non-work mail is not shown as an all-chats figure on the tiles. A phase name stays neutral.
- `court-package`, section 6: a rerun of the models starts with a copy of the database outside the package, because `models.py` writes to the database it is given. The `rerun` line in each `model-*.json` and the `--db` help of `models.py` say so.
- `court-package`, section 7: after the audit and the fixes, a fresh subagent on `opus` at `high` checks each fixed finding before delivery.
- `analyse` and `schema.sql`: `days.off` holds `off` or `holiday`, never the reason, and phases get neutral names, because `days` and the model files ship. A case database made earlier keeps its values until they are changed and the models run again.
- Tests: the `rerun` line asks for a copy.

## 0.7.0 - 2026-11-10

Method gaps found by an independent check of an analysis.

- `models.py`, event-days model: when the days of an event term had no out-of-hours trace at all, the fit separated completely and reported a rate ratio of 0.00 with a 95% CI of 0.00 to 0.00 and p < 0.001. The script now tests for this before fitting and gives counts only, with the reading "a ratio cannot be estimated with a zero". Those days stay among the other days for the remaining terms, as the days of a term with too few days do.
- `models.py`, event-days model: the script stopped with a `LinAlgError` when every trace fell on the terms' days and none elsewhere, or when a term fell on exactly the days of a weekday, month, year or another term. The first now gives counts only with the same reading. The second gives counts only for that term, and the other terms are still estimated.
- `models.py`, trend model: a phase with no traces read 0.00 with an interval of 0.00 to 0.00, a first phase with no traces gave a ratio in the billions, and a window with no traces stopped the script. Each now gives counts only. The weeks of a later phase without traces leave the fit and the output says so, and the other phases are still compared with the first.
- `analyse`, section 4: first and last trace hours on the activity-day clock, with seconds. The observed span is shown as the middle measure beside the conservative and continuous ones. In the person's statement scenario, a weekend period whose first trace comes after midnight counts from that trace and stays out of the average first hour. The report sizes the continuous estimate. Weekly hours against a legal limit are the contract hours due that week plus the out-of-hours estimate, summed unrounded, with a note on what the due hours rest on.
- `analyse`, section 8: when sources cover the window unevenly, or a few days hold most of the traces on event days, the models run again on copies of the database. A full-window trend that does not survive is reported as following the sources.
- `analyse`, section 2: a mail review also reads mails sent to the person's own addresses.
- Tests: event days with no trace or with traces on a single day, all traces on event days, event days on exactly the days of a weekday, phases with no trace, and a window with no trace.

## 0.6.1 - 2026-11-06

Fixes found while reading a real case's git history.

- `git_identities` counted wrong for a repository read from several clones in one run: the last clone's count replaced the others. It is now rebuilt from the merged commits after each clone, so every commit counts once.
- `git-history.sh` refuses an `--author` pattern with a letter outside ASCII inside `[...]`: git compares such letters byte by byte, so the bracket matched no commit, and `-i` folds only ASCII letters. `start` says to write such letters as alternatives with both cases, such as `(ç|Ç)el(i|ı|İ)k`.
- The git views used the offset the author's computer had (`Z` from a UTC container), so a commit near midnight could land on the wrong day, and the window could gain or lose commits at its edges. The new `scripts/contract-offset.py` writes the contract zone's fixed UTC offset over the window into `case_info` (`contract_offset_minutes`), or NULL when daylight saving changes it inside the window. `v_commits_in_window` and `v_commits_by_day` take their day from `author_utc` with that offset. `v_repo_summary` gives first and last as `first_commit_utc` and `last_commit_utc` (it compared mixed offsets as text), and in the contract zone. `schema.sql` now recreates the views, so older case databases get the new ones.
- `analyse` counts git work as events (author minute and subject, after giving reworded copies the first subject), reports merges apart, and never turns commit counts into hours.
- On Windows the tools check lists `tzdata`, which Python's time zones need there.
- Tests: two clones that each hold their own commit, a name with Turkish letters, commits from a UTC container near midnight and at the window's edge, a zone with daylight saving.

## 0.6.0 - 2026-11-06

- `start` runs `scripts/check-tools.py` at the start of every session. It lists the programs and Python packages this computer lacks and prints the install command for winget, Homebrew or apt, and pip: ffmpeg, Tesseract with the documents' language, sqlite3, PyMuPDF, pdfplumber, openpyxl, python-docx, Pillow, pandas, statsmodels, scipy; git and Git Bash for git history; LibreOffice and Playwright for the package. The plugin decides what the case needs, tells the person in plain words that it will install some free programs, and asks one yes. A language pack comes only when a document in that language turns up or the person writes in it. Details per system: `start/references/tools.md`.
- `collect` has a "Reading files" section: which library or program reads each kind of file (PDF text and tables, scans, .docx, .xlsx, old Office files, CSV, mail archives, images, screen recordings, SQLite backups), instead of hand-written zip, XML or PDF parsing. WhatsApp, normalizing and the hand-off checklist are now sections 7 to 9.
- Every subagent role has a model and an effort: window searches on `haiku` at low; readers and gap readers on `sonnet` at medium; checkers and privacy reviewers on `opus` at high; the merge and the completeness critic on `fable` at high; the audit on `fable` at xhigh (`opus` where Fable is not available). A large reading follows `collect/references/readers-and-checkers.md`, after the person's yes: each checker starts as soon as its reader finishes, and recounts and samples instead of reading everything a second time.
- `analyse` runs regression checks with `scripts/models.py` on the new `days` table, one row per day of the window. Event days: Poisson or negative binomial, weekday, month and year controls, errors clustered by week, on all days and on days with activity. Weekend work near releases: risk ratio and Fisher's exact test. Agreement of the commit, chat and mail clocks: Spearman. The load over the window and its phases: weekly, Newey-West. Each model's query, input rows, output and a copy of the script go to `work/queries/`, and every result with a plain reading goes to `model_results`. The skill explains each result in plain words: effect size, interval, p-value, and what it does not show.
- `court-package` puts the model results in the report with what they do not show, ships `models.py` and its files in `6_Method_and_Tool/models/` with `days` and `model_results` in the database, and checks that a rerun gives the same results.
- New tests: `tests/test-check-tools.sh` and `tests/test-models.sh`.

## 0.5.0 - 2026-11-06

- Each case folder has one folder for the lawyers, `for-lawyer/`, and only that folder is ever shared, as Viewer. It holds a plain README for the lawyer in the court's language, the reports and the package, the evidence as received in `raw/<source>/` with its own subfolders (file names repeat across folders), and `raw/hashes.txt` with the SHA-256 of every raw file. The case README, `master.sqlite`, `git/` and `work/` are no longer shared: lawyers cannot use the normalized data.
- `originals/` and `outputs/` are gone: evidence goes to `for-lawyer/raw/`, finished artifacts to `for-lawyer/`, and the query behind each artifact to `work/queries/<artifact>.sql`.
- Before sharing, `start` checks that neither the case folder nor `overtime-cases` is shared with anyone.
- For a case in the old layout, `start` offers to move it: hashes are checked before and after, `evidence_files.case_path` gets the new path, and `note` keeps the earlier one. A case whose whole folder was shared gets that access removed and `for-lawyer/` shared instead.
- `court-package` builds in `work/package/v<N>/`, checks `raw/hashes.txt` before the build, and delivers the zip, summary, report and spreadsheet into `for-lawyer/`. Earlier versions move out of it. `collect` and `analyse` keep derived and unmasked files in `work/` and `master.sqlite`.

## 0.4.2 - 2026-11-06

- README: install from Cenk Simsek's plugin catalog `cenk` (`https://github.com/cenksimsek1988/claude-plugins.git`) as `cenk-overtime@cenk`. This repository's own catalog `cenk-overtime` stays, for a clone and for local work; install one way only. The skills are unchanged from 0.4.1.

## 0.4.1 - 2026-11-06

- The plugin folder carries the MIT license text, so every install and the `.plugin` file include it; before, only the repository root had it. The skills are unchanged from 0.4.0.

## 0.4.0 - 2026-11-06

- Prepared for Anthropic's plugin directory. The plugin folder has its own README.md, the listing's description: what it does and does not do, example prompts, what it runs, reads and sends. The repository has PRIVACY.md and SECURITY.md.
- `court-package` puts an AI notice on the summary, the full report and README.txt: "Prepared with the help of AI from the employee's own records. To be checked by a lawyer before it is filed or relied on." The package is a draft until the lawyer has checked it.
- The password list used for masking (`secrets.json`) stays next to the git clones, outside the synced case folder, and is deleted when the package is final.
- `court-package` writes in the court's language; Turkish is no longer named as a default.
- `start` says in its first message that what it builds is for a lawyer to check, and stops with a pointer to Claude Code when the session cannot reach the person's files, as in claude.ai chat.
- Descriptions say "an evidence report for your lawyer" instead of "court-ready report". The root README lists what the plugin runs and sends instead of "no network calls of its own".

## 0.3.0 - 2026-11-06

- `start` now begins by listing the cases already in `My Drive/overtime-cases/` of every Google Drive account on the computer and asking whether to continue one of them or start a new one. For an existing case it asks only the intake questions that the case's `case_info` and README leave open, then goes on from the first step that is not done, so a case can be picked up in a later session.

## 0.2.1 - 2026-11-05

- Added `docs/guide.md`: the method in plain prose for employees, lawyers and court experts, with made-up examples instead of figures from a real case. The skills are unchanged from 0.2.0.
- Dropped the Google Drive install route: install from GitHub. The `.plugin` file for claude.ai is attached to each GitHub release.

## 0.2.0 - 2026-11-05

- Renamed the plugin and its marketplace from `overtime-evidence` to `cenk-overtime`, and the skills to `start`, `collect`, `analyse` and `court-package`, so every skill shows which plugin it belongs to. Installs of 0.1.0 have to be removed and installed again under the new name.
- Rewrote the plugin and skill descriptions in plain words for the people the plugin is for, with trigger phrases in English, Turkish, Italian, German, Spanish and French, and added keywords in those languages.
- Hid `collect`, `analyse` and `court-package` from the `/` menu: `start` runs them in order.
- Published on GitHub as `cenksimsek1988/cenk-overtime` under the MIT license, so anyone can install it from there; the shared Google Drive folder keeps working.

## 0.1.0 - 2026-11-05

- First version, as `overtime-evidence`: an entry skill with the intake, a Google Drive case folder per case to share with lawyers, a SQLite master database and a git history script, plus the collection, analysis and court package skills.
