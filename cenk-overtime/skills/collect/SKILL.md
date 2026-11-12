---
name: "collect"
description: "Finds and collects your own work traces (sent email, work chat, WhatsApp, calls, calendar, git, trackers) and turns them into one table that shows when you worked outside your contract hours. Use for: collect evidence of my overtime, export my work messages as evidence, which records prove my working hours, fazla mesai delili topla, mesai dışı mesajlarımı delil olarak topla, raccogliere le prove degli straordinari, Beweise für Überstunden sammeln, Arbeitszeit nachweisen, reunir pruebas de horas extra, rassembler des preuves d'heures supplémentaires."
user-invocable: false
---

# Work activity evidence: collection and normalization

Use this when a person wants to document when they worked outside contract hours (usually for an overtime or unpaid-hours claim, sometimes just before leaving a job). This skill covers getting the raw traces and turning them into one clean table. Analysis is in `cenk-overtime:analyse`; masking, reports and the court package are in `cenk-overtime:court-package`. When the case was started with `cenk-overtime:start`, its intake, case folder, database and git sections replace sections 0 and 4 here.

Not legal advice. Before exporting anything from employer systems, tell the person that rules on evidence collection differ by country and contract, and that a lawyer should confirm what may be used.

## 0. Scope questions to settle first (ask once, in one message)

- Contract working hours and days, and the contract's time zone (employer's location). Where the person actually lived and worked (local time can differ by 1-2 h).
- Exact employment window to count. Earlier periods at the same company via a contractor or another employer may not count; cut every source to the agreed window.
- Which sources exist and are still reachable (accounts are usually closed on the last day: collect immediately).
- Which conversations are clearly work ("core": team groups, release channels, manager 1:1) vs everything else.
- Every identity the person used: work emails (old and new domains), personal email, names with/without diacritics, machine-default git identities.

## 1. Principles

- Collect what the person **sent or did**, not what they received.
- Keep originals untouched; work on copies. Hash originals (SHA-256) the day they are collected and tell the person to email the hashes to themselves.
- Save raw results per query/window before any processing, so collection can be audited.
- In a case folder from `cenk-overtime:start`: evidence as received (exports, each window's raw result) goes into `4_Raw_Data/<source>/` of the case's evidence folder through its section 5, with hashes. Everything derived (window lists, merges, collection notes, the normalized table) goes into `work/` or `master.sqlite`, which are never shared.
- Never print secrets found in data back to the user; never copy source code anywhere.

## 2. Sources and how to get them

| Source | Method | Key fields | Pitfalls |
|---|---|---|---|
| Teams / M365 chat | Connector search (e.g. chat message search) with sender = person, one query per out-of-hours window; or eDiscovery/Purview export by the employer | message id, chatId, createdDateTime, text/summary, webUrl | Search results are capped -> windows. Teams message id = send time in epoch ms (second clock). Search `summary` may be truncated with "...". |
| Slack | Workspace or DM export (JSON per channel per day) | ts (epoch s), user, channel, text | Filter by user id, not display name |
| Email | Sent folder: Graph/Gmail connector search per window, or export PST/MBOX/EML (PST -> `readpst` -> mbox; read with Python `mailbox`) | Message-ID, Date header (with offset), To/Cc, Subject | Use sent items only; a received mail proves nothing |
| Calendar | ICS export; meeting chats; join/attendance logs | start, end, organizer, response | An invite is not attendance |
| Calls | Teams/Slack call history; Android call-log backup XML (e.g. SMS Backup & Restore: number, duration, date ms, type); iOS backup tools; carrier statements | start, duration | Map phone numbers to colleagues; personal phone = device local time |
| WhatsApp / Telegram / Signal | Per chat "Export chat -> without media" (txt) | date, time, sender, text | Format depends on OS and phone language (see below); device local time incl. DST |
| Git | Read-only git on local clones (section 4) | hash, author email/name, author date, committer date, subject, numstat, tags, release branches | Multiple identities; clones; never copy code |
| Issue tracker, CI/CD, registry, VPN, SSO, badge, server/audit logs | Usually employer-held: list them for the lawyer to request | | Retention is often months: request early |

## 3. Chat/email collection by time windows

1. Generate windows covering every out-of-hours span in the employment window: each weekday evening from shift end to next shift start + 1 min (e.g. 18:00 -> 09:01) and each weekend from Friday shift end to Monday 09:01. Store them (`windows.json`).
2. One search per window, filtered to the person as sender. Run windows in parallel batches: subagents can each take a block of windows, with model `haiku` and effort `low`, because each window is one fixed search with nothing to judge, and steps 3 and 4 catch their slips. Save each window's raw result to its own file named by window, an empty result too.
3. Check that every window in `windows.json` has its file. Log windows that returned nothing. After collection, re-query a random sample of empty windows and record the result ("6/6 still empty").
4. Merge: dedupe by message id. Detect cross-contaminated copies: the same id saved in a file of another window, sometimes with a different chatId. Keep the copy from the window that contains its timestamp; log the dropped ones (`foreign_copies.json`).
5. Keep the collection notes: who ran the queries, the tool used, dates, window count, empty count, re-check results.

## 4. Git (local repositories)

If the person's computer is linked to the session, request access to the smallest folder that holds the repos, say exactly what will be read, and do not open vaults, credential folders or personal projects. Work read-only: no fetch, pull, checkout, commit or stash (also: the person's company accounts may be closed; never contact remotes).

```bash
# which folders are repos, and which belong to the employer (classify by remote host)
git -c safe.directory='*' -C REPO remote get-url origin   # strip any user:token@ before printing
# all identities that look like the person
git -c safe.directory='*' -C REPO log --all --format='%ae|%an' | grep -iE 'firstname|lastname' | sort | uniq -c | sort -rn
# own commits with stats (author regex covers every identity)
git -c safe.directory='*' -C REPO log --all --numstat --no-renames -E \
  --author='name\.surname@|personal@' --format=$'\x1e%H\x1f%P\x1f%ae\x1f%an\x1f%aI\x1f%cI\x1f%s'
# release markers
git -C REPO for-each-ref refs/tags --format='%(refname:strip=2)%1f%(objecttype)%1f%(creatordate:iso-strict)%1f%(taggeremail)%1f%(objectname)%1f%(*objectname)%1f%(subject)'
git -C REPO for-each-ref refs/heads refs/remotes --format='%(refname)%1f%(refname:short)%1f%(committerdate:iso-strict)%1f%(authordate:iso-strict)%1f%(objectname)'
```

- Include only employer repos (remote host = employer's git server). Exclude open-source clones and personal projects even if they contain commits with the work email.
- Identities found in practice: work email (sometimes two company domains), personal email, a previous employer's address, `user@HOSTNAME` and `user@10.x.x.x` machine defaults. Normalize machine-default ones to `user@local-machine` (they contain internal IPs).
- Use author date (`%aI`) as the time of work; flag commits whose committer date differs by > 5 min (rebase/amend/cherry-pick).
- Several clones of one remote: dedupe by hash, merge into one repo entry named after the remote; total commits = max over clones.
- Restrict commits, tags and branches to the employment window.
- `--numstat` can be very slow on network/virtual mounts: first list commits without stats, then compute stats in batches (`git log --no-walk=unsorted --numstat <20 hashes>`) with several parallel workers per call; background processes may be killed between tool calls.
- Do not export colleagues' emails: keep only the person's identities plus an aggregate count of others; blank tagger emails that are not the person's.
- Output folder on the person's machine: tell them its path; you may not be able to delete it.

## 5. Reading files

Evidence in `4_Raw_Data/` is read, never changed: every derived file goes to `work/`. Use the programs and libraries from the Tools section of `cenk-overtime:start`, never a hand-written unzip and XML parse of .docx or .xlsx, or a PDF parser of your own. Run Python with the interpreter the tools check named.

- PDF text: PyMuPDF, `doc = pymupdf.open(path)`, then `page.get_text()` per page; `doc.page_count`; `doc.metadata` has the creation and change dates, by the producer's clock.
- PDF tables (payslips, timesheets): pdfplumber, `page.extract_tables()`; check the totals against the page text.
- Scanned PDF, a page whose `get_text()` is empty: `page.get_pixmap(dpi=300).save("work/ocr/p001.png")`, then `tesseract work/ocr/p001.png work/ocr/p001 -l tur+eng`. OCR text can be wrong: check every quote against the page image. Record which pages were read by OCR.
- .docx: python-docx, `Document(path)`: `.paragraphs`, `.tables`, `.core_properties` (author, created, modified). Headers, footers and text boxes are separate parts.
- .xlsx: openpyxl, `load_workbook(path, read_only=True, data_only=True)` for the values as last saved; load again without `data_only` for the formulas. A file saved by a program that does not calculate has no values (`None`): read the formulas. pandas `read_excel` for plain tables.
- Old .doc and .xls: convert a copy with LibreOffice, `soffice --headless --convert-to docx --outdir work/convert <file>` (`xlsx` for .xls).
- CSV: pandas `read_csv(path, dtype=str)`; encoding `utf-8-sig`, else the exporting system's (`cp1254` for Turkish Windows); `sep=None, engine="python"` when the separator is `;`.
- Mail: MBOX (also Google Takeout) with Python's `mailbox.mbox(path)`, headers only: `Date`, `From`, `To`, `Message-ID`, `X-Gmail-Labels` (Takeout marks sent mail with `Sent`). EML with `email.message_from_binary_file(f, policy=email.policy.default)`.
- Images and screenshots: Pillow, `Image.open(path).getexif().get(36867)`, the time taken; chat apps often strip it. Text: Tesseract, as for scans.
- Screen recordings and videos: `ffprobe -v error -show_entries format=duration:format_tags=creation_time -of json <file>`. Frames every 5 s: `ffmpeg -i <file> -vf fps=1/5 work/frames/%05d.png`; at scene changes: `ffmpeg -i <file> -vf "select='gt(scene,0.3)'" -fps_mode vfr work/frames/%05d.png`. Then Tesseract, or look at the frames. A frame's clock time is creation_time plus its offset only when the file has a creation_time: say which.
- SQLite files (app backups): open a copy in `work/`, never the file in `4_Raw_Data/`: opening one can write `-wal` and `-shm` files beside it.
- WhatsApp and other chat exports: section 7.

## 6. Many files at once

With more than about 10 evidence files or 100 MB, or many formats at once (mail archive, chats, PDFs, office files, recordings), read `references/readers-and-checkers.md` before reading anything: it splits the work over subagents, with a model and an effort for each role, after the person's yes.

## 7. WhatsApp exports

Line formats vary; detect per file:

```python
import re
LINE = re.compile(r'^\[?(\d{1,2})[./-](\d{1,2})[./-](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp]\.?\s?[Mm]\.?)?\]?\s*(?:-\s)?([^:]{1,80}): (.*)$')
# Android EN: 12/31/23, 9:41 PM - Name: text   | Android TR/EU: 31.12.2023 21:41 - Name: text
# iOS: [31.12.23, 21:41:05] Name: text
```

- Lines that do not match continue the previous message (multi-line). Lines without `Name:` are system notices: skip.
- Day/month order: decide per file from values > 12; if still ambiguous, ask the person which phone language was set.
- Times are the phone's local time: convert with the real time zone of that date (DST), then to the contract zone.
- Keep only the person's own messages (their display name as it appears in that export, which can differ per chat).

## 8. Normalize into one table

One record per trace:

`record_id, source, channel_id, channel_name, time_utc, time_contract, time_second_source, author, own_text, quoted_author, raw_text, url, extra(json)`

- Convert to the contract time zone with real offsets; state where the person lived.
- Second clock: for Teams, time from the message id; count as out-of-hours only when both clocks agree (conservative). List disagreements.
- Scheduled sends: messages at exactly shift start (e.g. 09:00:00-09:00:59) get their own category and are not counted.
- Replies: split `Author  quoted text  own text` and classify only the person's own words. If the split fails, flag it.
- 1:1 chats without names: in a 1:1, every quoted author who is not the person is the other participant -> infer the name, mark it as inferred.
- Exclude self-notes chats (e.g. Teams `48:notes`), bots and drafts; list them as excluded.
- Keep the full unmasked table only in the private workspace (`master.sqlite` and `work/` of the case folder), never in the evidence folder; masking happens before anything is shared (see `cenk-overtime:court-package`).

## 9. Hand-off checklist

- [ ] Raw results per window/source saved, originals hashed
- [ ] Collection notes: windows, empty windows, re-checks, dropped copies, tools, dates
- [ ] Identity list and employment window confirmed with the person
- [ ] Normalized table with both clocks, categories ready for analysis
- [ ] List of employer-held records for the lawyer to request (VPN/SSO, git server push logs, CI/CD, tracker histories, audit logs, attendance/leave)