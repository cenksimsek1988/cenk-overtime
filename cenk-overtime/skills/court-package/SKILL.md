---
name: "court-package"
description: "Builds a court-ready evidence package from the analysis: passwords and private life masked, a short summary PDF for your lawyer, a full report, data and a rebuild tool for the court expert, a spreadsheet with live formulas, SHA-256 hashes and an independent audit. Use for: evidence package for my lawyer, prepare my overtime evidence for court, report for the labour court, mahkemeye sunulacak delil paketi, avukatım için fazla mesai raporu, bilirkişi için rapor, pacchetto di prove per l'avvocato, prove per la causa di lavoro, Beweismappe für das Arbeitsgericht, Unterlagen für die Überstundenklage, pruebas para el juicio laboral, informe para mi abogado, dossier de preuves pour les prud'hommes, rapport pour mon avocat."
user-invocable: false
---

# Court-ready evidence package

Use after `cenk-overtime:collect` and `cenk-overtime:analyse`. Readers: the lawyer (summary), the court expert (full report, data, tool), the judge (summary). Every number must be traceable to record ids the employer can verify, and the whole package must be rebuildable from its own raw data.

## 1. Credentials and system details (before anything is shared)

Mask in every text field:
- keyword=value or keyword: value (password, sifre/sifre-like local words, parola, pwd, token, secret, api key; also inside property names like `x.apiKey=`)
- user/password pairs (`admin/xyz`, service users)
- a message that is only `user / password-with-digit`
- an email followed by a random-looking token (letters + digits + symbol, >= 8)
- a whole message that is one random-looking token (>= 12 chars, >= 3 character classes, >= 3 letter/digit switches, not an identifier/path/version)
- JWTs, PEM private keys, share links to private pages
- internal IPv4 (not 127.x, not version numbers) with port/SID, database endpoints (host:1433/1521/3306/5432/27017... or host:SID)
- literal passwords found by review: kept in a local `secrets.json` used only at build time, never copied into the package or the tool
- a message containing a login (user + password) is masked whole by id with a stated reason

Rescan after every scope change (new chats, git) and scan every output format, not just inputs: PDF text (pdftotext), xlsx cells, every SQLite table, CSV, JSONL, git metadata. Also run a shape scan for password-like tokens (upper+lower+digit+symbol) and a context scan (password-like tokens within 10 min of a password discussion). Print shapes, never the secrets.

## 2. Private life

1. Agree the policy with the person first. Default: group A = their own non-work private matters (masked on request); group B = anyone else's private information (health, family, relationships, bereavement, legal matters, finances, gossip) = always masked. The person may choose to keep their own items that support the claim (e.g. own illness or therapy showing strain).
2. Read every non-empty message, not keyword hits. Split into chunks of ~800 messages; brief parallel reviewers (subagents) with one written brief: categories, what not to flag (work content, complaints about workload, idioms, small talk), output `{id, group, topic}` only, never quoted text, plus up to 10 unsure ids.
3. Merge, then decide borderline cases yourself with context: keep items that help the claim per the person's policy; mask items that could be used against them (job search, side-business plans for evenings/weekends, alcohol/drugs, immigration status, address/finances) and tell the person these exist so the lawyer can decide.
4. Run keyword safety-net sweeps after the review (immigration/visa/citizenship, legal/court, health of others, politics/religion, money, job offers) and check hits in context.
5. Check messages excluded from review (empty or already masked) and old placeholders from earlier policies.
6. Replace masked text with a fixed placeholder; keep time, ids, chat; the message still counts. Store `[{id, group}]` in the tool folder so the tool reproduces the masks; reasons go to the decisions table.
7. Never publish counts by private topic; report only the total and the A/B split. Do not mask unflattering work content (it looks like cherry-picking); flag it to the person instead.
8. Verify: for every masked id, probe the original's own text and quoted text (first 40 chars) in every output; zero hits required.

Customer names stay out of the narrative PDFs (scan for the known list); the package is marked confidential (lawyer, court, expert).

## 3. Package layout

```
1_Summary.pdf            3-4 pages
2_Report.pdf             full report with annexes
3_Data_Tables.xlsx       one sheet per table; summary sheet with live formulas
4_Database/              db.sqlite, csv/, sample_queries.sql
5_Raw_Data/              masked records (jsonl), collection_notes.json, git_metadata.json
6_Method_and_Tool/       tool/ (scripts + mask list), HOW_TO_USE.txt
HASHES_SHA256.txt
README.txt               contents, confidentiality, verification, hash deposit
```

## 4. Reports (HTML -> PDF with Playwright/Chromium)

Summary: title with period and person; data source and collection date; raw-data hash; 6 key-number tiles (each with the all-chats figure in brackets); findings bullets, each with one quoted example and its date/time and a reference to the report section; a box "What this report does not show" (no pay calculation, estimates only, traceless work invisible, content not judged message by message); weekly chart; core vs all-chats table; time-estimate table (weekday/weekend/total); event-day chart and table; period-group table.

Full report: 1 summary, 2 data/definitions/method (collection, windows, two clocks, tense model, version completion, masking), 3 distribution (bands, heat map, end-time histogram, sensitivity, all chats, time estimates), 4 release/patch relation (event study, year table, release list with evidence ids, cycles, prod/patch), 5 git (tiles, weekly commits with anchors, independent comparison, repos table, excluded tags), 6 tool/AI work if relevant, 7 validation table and limitations, annexes: every period, evidence for every event, manual decisions, data dictionary.

Writing: Turkish or the court's language; sentences < 25 words; numbers with units; suffixes/grammar generated correctly for numbers; quotes must match the stored text exactly (assert it in code). Wording must follow the data: when git is present say "messages and commits", "last activity (message or commit)"; when an all-chats figure includes private masked messages, say so.

Charts: hand-drawn SVG; grey data with one accent; values on bars; reference line labelled on the chart; no overlapping labels (render and look at every page before delivery).

## 5. Spreadsheet

Write with openpyxl; the summary sheet uses formulas (COUNTIF/COUNTIFS on the data sheets, never hardcoded results); recalculate with LibreOffice; require zero formula errors; then compare every summary value with the same query on SQLite and fail the build on any mismatch. Keep Teams-based and commit-based counts in separate rows.

## 6. Reproducibility and integrity

- The packaged tool rebuilds every table and report from 5_Raw_Data (+ git metadata) into a new folder next to the package; it never writes into the package. Build the delivered outputs by running the packaged tool itself on the packaged raw data.
- Standard library only for the core; openpyxl and Playwright optional. Set `sys.dont_write_bytecode = True` and run with `-I -B`; delete `__pycache__` before hashing.
- Reproduction check before delivery: copy the package, run the tool, compare every SQLite table (ignore the generation timestamp).
- `sha256sum -c HASHES_SHA256.txt` must pass; compute the zip's SHA-256 and tell the person to deposit it the same day (email to self and lawyer, notary or timestamp service).
- Sample queries: run every query in sample_queries.sql against the final DB; examples must return rows.

## 7. Audit and delivery

- Before delivery, have an independent reviewer (fresh subagent) audit: credentials, quotes vs data, numbers vs DB, wording/overclaims, event dating, comparisons, labels, limitations. Fix everything found and rebuild.
- Deliver the zip and the summary PDF; give the zip hash. Number versions; state that the new package replaces earlier ones; if earlier deliverables contained unmasked data, tell the person not to share them.
- Clean the workspace of scratch copies with unmasked data (review chunks, scan outputs, old builds); keep only what is needed to rebuild.
- Final message to the person: what changed, key numbers in a small table, judgment calls they should know about (masked borderline items), and one next step.