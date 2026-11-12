---
name: "court-package"
description: "Builds an evidence package from the analysis, for your lawyer to check before anything goes to court: passwords and private life masked, delivered as plain folders with no zip: a summary anyone can follow with plus, minus, times and divide, a full report, the processed data, a whitepaper-style method document and a rebuild tool for the court expert, SHA-256 hashes and an independent audit. Use for: evidence package for my lawyer, prepare my overtime evidence for court, report for the labour court, mahkemeye sunulacak delil paketi, avukatım için fazla mesai raporu, bilirkişi için rapor, pacchetto di prove per l'avvocato, prove per la causa di lavoro, Beweismappe für das Arbeitsgericht, Unterlagen für die Überstundenklage, pruebas para el juicio laboral, informe para mi abogado, dossier de preuves pour les prud'hommes, rapport pour mon avocat."
user-invocable: false
---

# Evidence package for the lawyer and the court

Use after `cenk-overtime:collect` and `cenk-overtime:analyse`. Readers: the lawyer (summary), the court expert (full report, data, method document, tool), the judge (summary). Every number must be traceable to record ids the employer can verify, and the whole package must be rebuildable from its own masked records.

## 1. Credentials and system details (before anything is shared)

Mask in every text field:
- keyword=value or keyword: value (password, sifre/sifre-like local words, parola, pwd, token, secret, api key; also inside property names like `x.apiKey=`)
- user/password pairs (`admin/xyz`, service users)
- a message that is only `user / password-with-digit`
- an email followed by a random-looking token (letters + digits + symbol, >= 8)
- a whole message that is one random-looking token (>= 12 chars, >= 3 character classes, >= 3 letter/digit switches, not an identifier/path/version)
- JWTs, PEM private keys, share links to private pages
- internal IPv4 (not 127.x, not version numbers) with port/SID, database endpoints (host:1433/1521/3306/5432/27017... or host:SID)
- literal passwords found by review: kept in `secrets.json` on the computer, next to the git clones (`~/overtime-clones/<case>/`), never in the case folder, which syncs to Google Drive; used only at build time, never copied into the package or the tool; deleted when the package is final (section 7)
- a message containing a login (user + password) is masked whole by id with a stated reason

Rescan after every scope change (new chats, git) and scan every output format, not just inputs: PDF text (pdftotext), xlsx cells, every SQLite table, CSV, JSONL, git metadata. Also run a shape scan for password-like tokens (upper+lower+digit+symbol) and a context scan (password-like tokens within 10 min of a password discussion). Print shapes, never the secrets.

## 2. Private life

1. Agree the policy with the person first. Default: group A = their own non-work private matters (masked on request); group B = anyone else's private information (health, family, relationships, bereavement, legal matters, finances, gossip) = always masked. The person may choose to keep their own items that support the claim (e.g. own illness or therapy showing strain).
   - Group B also covers get-well and condolence wishes. Example: `Get well soon, Ada`.
   - Group B also covers job candidates: names, CV file names, contact cards, pay expectations. Example: `Ada_Lovelace_CV.pdf`, `asks for 4000 a month`.
   - Group B also covers colleagues' pay, job search, resignation and character judgments. Example: `Bob has resigned`, `Bob is useless`.
   - Team-management content stays as work content: who does what, a hiring plan, a leave plan. Record that as a decision. Example: `Ada takes billing`, `two testers by June`, `Bob is off next week`.
   - The person's own pay, raises, shares, job offers and own lawyer's advice are group A unless they decide otherwise. Ask, or mask by default and tell them and the lawyer; the originals stay in `4_Raw_Data/` of the evidence folder. Example: `my raise came through`, `my lawyer says wait`.
2. Read every non-empty message, not keyword hits. Split into chunks of ~800 messages; brief parallel reviewers (subagents) with one written brief: categories, what not to flag (work content, team-management content, complaints about workload, idioms, small talk), output `{id, group, topic}` only, never quoted text, plus up to 10 unsure ids. Reviewers: model `opus`, effort `high`. Telling private matters from work is legally sensitive judgment, often in more than one language, and a miss puts someone's private life in front of the employer and the court.
3. Merge, then decide borderline cases yourself with context: keep items that help the claim per the person's policy; mask items that could be used against them (job search, side-business plans for evenings/weekends, alcohol/drugs, immigration status, address/finances) and tell the person these exist so the lawyer can decide.
4. Run keyword safety-net sweeps after the review (immigration/visa/citizenship, legal/court, health of others, politics/religion, money, job offers, get-well phrases) and check hits in context. Also sweep attachment lines whose file name is a person's name (.vcf, .pdf, .docx) and login names of customer systems. Example: `get well soon`, `Attachment: Ada_Lovelace.vcf`, `acme_admin`.
5. Check messages excluded from review (empty or already masked) and old placeholders from earlier policies.
6. Replace masked text with a fixed placeholder; keep time, ids, chat; the message still counts. A masked mail's subject is masked too, unless the review passed it. Store `[{id, group}]` in the tool folder so the tool reproduces the masks; reasons go to the decisions table of `master.sqlite`. A mask decision ships with its id and group only, in the packaged tables and the report's annex. Example: `traces:4711 | masked | group B`, never `colleague's surgery`.
7. Never publish counts by private topic; report only the total and the A/B split. Do not mask unflattering work content (it looks like cherry-picking); flag it to the person instead.
8. Verify: for every masked id, probe the original's own text and quoted text in every output, with several windows per message; zero hits required. Skip a mail subject line only when a kept mail shares it and the review passed that subject. Example: 40 chars from the start, the middle and the end of each message; a hit on `Re: Release plan`, which a kept mail also carries, is no leak.
9. The reason for a day off never ships: not in a table value, key, comment or identifier. Scan every output for reason words in the case's languages: the formats of section 1, plus sheet names, column names, JSON keys, file names, scripts and `sqlite_master`, which keeps SQL comments (a hit there: take the word out of the tool's `CREATE TABLE`). Check hits in context; a reason in a message the person chose to keep (step 1) stays. Example: `days.off` holds `off` or `holiday`, never `sick`; no column `sick_days`; scan words `sick`, `doctor`, `funeral`.

Customer names stay out of the narrative PDFs: scan for the known list, which includes the main client and the client-project repository names. Example: `Acme` is never named, and `acme-portal` appears as `client-repo-1`. The package is marked confidential (lawyer, court, expert).

## 3. Package layout

The package goes into the case's evidence folder, `<case>-evidence/` (`cenk-overtime:start`, section 3), as plain folders that open without unpacking: no zip. Folder and file names are in English and the same in every case; the folder's `README.md` explains them in the court's language.

```
README.md                  start here (cenk-overtime:start, section 3); section 7 adds the package
1_Summary/Summary.pdf      3-4 pages, for a reader who knows only + - x / (section 4)
2_Report/Report.pdf        full report with annexes
3_Processed_Data/
  Data_Tables.xlsx         one sheet per table; summary sheet with live formulas
  database/                db.sqlite (days and model_results too), csv/, sample_queries.sql
  masked_records/          masked records (jsonl), collection_notes.json, git_metadata.json
4_Raw_Data/                evidence as received, with hashes.txt (cenk-overtime:start, section 5); never changed here
5_Calculation/
  Method.pdf               how every number was calculated, like a whitepaper (section 4)
  tool/                    scripts + mask list
  models/                  models.py, model-* files
  HOW_TO_USE.txt
6_From_Lawyer/             the lawyers' own documents: never written, moved, deleted or hashed
HASHES_SHA256.txt          SHA-256 of every file above, except README.md, 4_Raw_Data/hashes.txt and 6_From_Lawyer/
```

`README.md` and `4_Raw_Data/hashes.txt` change whenever evidence comes in, so `HASHES_SHA256.txt` leaves them out and lists each raw file itself: evidence added later does not break the check. Example: `4_Raw_Data/email/sent.mbox` has its own line.

Git data in the package:
- Commit subjects of client repositories ship only as SHA-256 hashes: they name client tickets and security bugs. The tool counts events on the hash; a tag derived from a subject ships as its own field. A report may quote a subject when code checks the quote against its hash. Example: `ACME-12 fix login bypass` ships as `sha256:ab12...` in `git_metadata.json` and every table.
- The other git fields of client repositories follow: the repository ships as its label in every output; branch names, tag names and messages and file paths ship as hashes or not at all; addresses and local paths stay out. Scan those repositories' rows for the known customer list and ticket prefixes: zero hits. Example: `acme-portal` is `client-repo-1` in `db.sqlite` too, `feature/ACME-12-fix-login` ships as `sha256:cd34...`, and `https://git.acme.example/portal.git` stays out.
- Git author identities are generic labels, and the pattern that found them (`repos.author_regex`) stays out. Example: `author-1`, never a name or an email address.

Build each version in `work/package/v<N>/` of the case folder, never in the evidence folder, which the lawyers see as soon as a file lands there. Section 7 delivers the finished version.

## 4. Reports (HTML -> PDF with Playwright/Chromium)

AI notice, in the report's language, under the title of `Summary.pdf`, `Report.pdf` and `Method.pdf` and at the top of the evidence folder's `README.md`: "Prepared with the help of AI from the employee's own records. To be checked by a lawyer before it is filed or relied on." Keep it in every version delivered to the person and the lawyer.

Summary (`1_Summary/Summary.pdf`), for a reader who knows only addition, subtraction, multiplication and division:
- Every number is a count, a sum, a difference, an average (a total divided by a named count of days or weeks) or "N times as many" next to both counts. A share is "N of M", never a percent. Example: `412 of the 520 weekdays`, `1 h 50 min per worked evening on average (755 h ÷ 412 evenings)`.
- Each number has one line on how it was counted and one real day as an example. Example: `Evenings with work after 18:00: 412. Counted: a weekday with at least one own message or commit after 18:00. Example: Tuesday 14 March 2023, last message 22:41.`
- Each hour estimate gives its rule with a worked example. Example: `Conservative: only the time between own traces less than 1 hour apart. Messages at 19:00, 19:40 and 21:30 give 40 minutes.`
- No statistical words: median, mean, percentile, interval, p-value, significance, correlation, regression, model, standard deviation. Example: `half of the evenings ended before 21:40`, not `median end 21:40`.
- No model results: one line points to the report's section and to `Method.pdf`.
- Contents: title with period and person; data source and collection date; the raw-data fingerprint (SHA-256 of `4_Raw_Data/hashes.txt`) and the integrity date; 6 key-number tiles (each with the all-chats figure in brackets; exception below); findings bullets, each with one quoted example and its date/time and a reference to the report section; a box "What this report does not show" (no pay calculation, estimates only, traceless work invisible, content not judged message by message, commit times unverified without the server's records); weekly chart; core vs all-chats table; time-estimate table (weekday, Saturday, Sunday, public holiday, total); event-day chart and table; period-group table.

Method document (`5_Calculation/Method.pdf`), like a whitepaper: the one place the method is written; the report points to its sections instead of repeating them. Sections: 1 question and data (sources, window, identities, collection, windows); 2 definitions (contract hours, categories, activity day, tiers, two clocks, scheduled sends); 3 each counting step with a worked example on one real day, masked as in the package; 4 the hour estimates (conservative, observed, continuous, the person's statement), each with its rule and a worked example; 5 events and comparisons (tense model, version completion, event study, period groups); 6 the regression checks: the question, the method in one line, how to read the numbers, what each does not show; 7 masking (rules and checks, never the masked content); 8 integrity and rebuild (hashes, the tool's steps, which script does each); 9 limitations. Example: `3.2 Evening end: the last own trace of the activity day. Tuesday 14 March 2023: messages at 19:05 and 22:41, a commit at 21:10, so the evening ends at 22:41.`

Full report: 1 summary, 2 data and definitions in short, each pointing to its section of `Method.pdf`, 3 distribution (bands, heat map, end-time histogram, sensitivity, all chats, time estimates, workload trend and phases), 4 release/patch relation (event study, year table, regression checks on event days and weekends, release list with evidence ids, cycles, prod/patch), 5 git (tiles, weekly commits with anchors, independent comparison, agreement of the clocks, repos table, excluded tags), 6 tool/AI work if relevant, 7 validation table and limitations, annexes: every period, evidence for every event, manual decisions, data dictionary.

Both reports, wherever the item appears:
- Saturday, Sunday and public-holiday hours are separate rows, split at report build by the day of each period (`days.off` = `holiday` marks public holidays), and each hour is in one row. Example: weekday 120 h, Saturday 30 h, Sunday 12 h, public holiday 6 h, total 168 h; a public holiday on a Saturday goes in the public-holiday row.
- Say what an evening past midnight is: traces after midnight count to the evening before, and with a first trace after midnight it may be an early start. Example: "First trace 02:10, last 03:05: counted as Monday's evening; it may be an early start on Tuesday."
- A non-core tier that is only non-work mail is not shown as an all-chats figure on the tiles. Example: the only traces outside core are mails to a private address: the tile says `120 evenings`, not `120 evenings (all chats: 150)`.
- Merge commits and bursts of identical commits are reported apart from the other commits. Example: 200 commits = 170 others + 20 merges + 10 in 2 bursts (`sync`, 5 times in 2 minutes).
- Commit times come from the author's own clock and are unverified without the server's records. Example: "Commit times come from the employee's computer; the employer's server push logs would confirm them."
- State the integrity date, the day the last raw file was hashed (the latest `evidence_files.received_at`): a hash taken long after collection proves nothing about the time before. Example: "Collected in week 1, hashed in week 12: the hashes show no change since week 12 and say nothing about weeks 1 to 12."
- A phase name stays neutral, here and in `days.phase`, which the model readings quote: a role label such as a manager title can serve as the other side's argument. Example: `Phase 2`, not `Shift supervisor period`.

Model results (`model_results`, from `cenk-overtime:analyse`, section 8): in the report, each with its reading in the report's language and the same numbers, the method in one line, and what it does not show; never in the summary.

Writing: the court's language; sentences < 25 words; numbers with units; suffixes/grammar generated correctly for numbers; quotes must match the stored text exactly (assert it in code). Wording must follow the data: when git is present say "messages and commits", "last activity (message or commit)"; when an all-chats figure includes private masked messages, say so.

Charts: hand-drawn SVG; grey data with one accent; values on bars; reference line labelled on the chart; no overlapping labels (render and look at every page before delivery).

## 5. Spreadsheet

Write with openpyxl; the summary sheet uses formulas (COUNTIF/COUNTIFS on the data sheets, never hardcoded results); recalculate with LibreOffice; require zero formula errors; then compare every summary value with the same query on SQLite and fail the build on any mismatch. Keep Teams-based and commit-based counts in separate rows.

## 6. Reproducibility and integrity

- Before the build, run `sha256sum -c hashes.txt` (`shasum -a 256 -c` on macOS) in `4_Raw_Data/` of the evidence folder: every line must say OK, so the evidence is unchanged since it came in.
- The packaged tool rebuilds every table and report from `3_Processed_Data/masked_records/` (+ git metadata) into a new folder outside the package; it never writes into the package. Build the delivered outputs by running the packaged tool itself on the packaged masked records.
- Standard library only for the core; openpyxl and Playwright optional. Set `sys.dont_write_bytecode = True` and run with `-I -B`; delete `__pycache__` before hashing.
- Reproduction check before delivery: copy the package, run the tool, compare every SQLite table (ignore the generation timestamp).
- The tool also rebuilds `days`. `5_Calculation/models/` holds `models.py` and its `model-*` files from `work/queries/`. `models.py` writes `model_results` into the database it is given, so a rerun starts with a copy outside the package. Example: copy `3_Processed_Data/database/db.sqlite` to a new folder `../rerun/`; then `python 5_Calculation/models/models.py --db ../rerun/db.sqlite --out ../rerun/models` must give the same `model-*.json`, and `HASHES_SHA256.txt` still passes. HOW_TO_USE.txt gives these commands and the library versions in the JSON files (pandas, numpy, statsmodels, scipy); the core tool stays standard library only.
- `sha256sum -c HASHES_SHA256.txt` in the evidence folder must pass. Compute the SHA-256 of `HASHES_SHA256.txt` itself and tell the person to deposit it the same day (email to self and lawyer, notary or timestamp service): it pins every file of the package, raw files included.
- Sample queries: run every query in sample_queries.sql against the final DB; examples must return rows.

## 7. Audit and delivery

- Before delivery, have an independent reviewer (fresh subagent) audit: credentials, quotes vs data, numbers vs DB, wording/overclaims, event dating, comparisons, model readings (no causal words, intervals and limits stated), labels, limitations, the summary rules of section 4 (only the four operations, no statistical word, each number with its counting line and example day, no model result), and `Method.pdf` against what the tool does. Fix everything found and rebuild. Auditor: model `fable` (`opus` where Fable is not available), effort `xhigh`: it runs once, and it is the only check of the whole package before the lawyer.
- After the audit and the fixes, one more pass before delivery: a fresh subagent checks each fixed finding in the rebuilt package. A finding that is not fixed goes back to fix, rebuild and check. Verifier: model `opus`, effort `high`: it checks the audit's findings only. Example: finding 7, "quote differs from the database": it compares the quote in the rebuilt PDF with the stored text and writes `fixed` or `not fixed`.
- The package is a draft for the person's lawyer. Tell the person not to file it, or send it to the employer or the court, before the lawyer has checked it.
- Deliver into the evidence folder: copy `1_Summary/`, `2_Report/`, `3_Processed_Data/`, `5_Calculation/` and `HASHES_SHA256.txt` from `work/package/v<N>/`, then run the check of section 6 there. Update the folder's `README.md`: the package version and date, what each folder holds, how to check `HASHES_SHA256.txt`, and its SHA-256 for the deposit. Never write, move or delete anything in `6_From_Lawyer/`.
- Number versions, on each title page and in the README; state that the new package replaces earlier ones. Before delivering, move the earlier version's files from the evidence folder to `work/package/` unless the person wants them kept there; a package from before version 0.9.0 sits at the folder's top (summary, report, spreadsheet, zip). An earlier version with unmasked data leaves the evidence folder at once: tell the person that the lawyers may have downloaded it already and must not file or pass it on, and not to share copies of it themselves.
- Clean `work/` of scratch copies with unmasked data (review chunks, scan outputs, old builds); keep only what is needed to rebuild.
- When the person says the package is final, delete `secrets.json` (section 1) and say so; a later rebuild needs the password review again.
- Final message to the person: what changed, key numbers in a small table, judgment calls they should know about (masked borderline items), and one next step.