---
name: "start"
description: "Starts an unpaid overtime or extra-shift claim, or picks up one you started before, and guides it to an evidence report for your lawyer: asks about your job, contract hours and the evidence you already have, creates a case folder in your own Google Drive, with one folder in it to share with your lawyer, brings your evidence in with hashes, reads your git history, then runs cenk-overtime:collect, :analyse and :court-package in order. Use for: I worked unpaid overtime, my extra shifts were never paid, claim overtime from my employer, prepare my overtime case for my lawyer, fazla mesai hesapla, fazla mesai davası açacağım, fazla mesai alacağımı nasıl kanıtlarım, işçi alacağı davası, straordinari non pagati, causa di lavoro per gli straordinari, unbezahlte Überstunden, Überstunden nachweisen, Überstundenvergütung einklagen, horas extra no pagadas, reclamar horas extra, heures supplémentaires non payées, prouver mes heures supplémentaires."
---

# Overtime evidence: start here

The single entry point for an overtime case. This skill owns the choice of case, the intake, the case folder, sharing its `for-lawyer/` folder with the lawyers, the master database and git history. The detail of each later stage lives in three skills of this plugin, used in this order:

1. `cenk-overtime:collect`: getting the remaining traces and normalizing them.
2. `cenk-overtime:analyse`: definitions, counts, hour estimates, release and incident relation.
3. `cenk-overtime:court-package`: masking, reports, spreadsheet, hashes, audit.

Where this skill and one of them differ, this skill wins: case folder, sharing, master database, evidence import, and git (section 6 replaces section 4 of `cenk-overtime:collect`).

In the first message, say that this is not legal advice: rules on what evidence may be collected and used differ by country and contract, and a lawyer should confirm them, especially access to employer systems after the job has ended. Also say that what this plugin builds is prepared with the help of AI and is for a lawyer to check before anything is filed or sent.

This plugin works on the person's own computer: their files, Google Drive for desktop, git and a shell. If this session cannot reach the person's files (for example claude.ai chat, whose sandbox is not their computer), say so in the first message, point to Claude Code, and stop.

## 0. Which case

Before the intake, find the cases the person already has: the folders in `My Drive/overtime-cases/` of every Google Drive account on the computer (section 3 says where each account appears). For each case, read only its `README.md` and, if `master.sqlite` exists, its `case_info` table. Do not open `for-lawyer/`, `git/` or `work/` yet, nor `originals/` and `outputs/` in a case in the old layout.

In the first message, list the cases found (name, account, last change) and ask whether to continue one of them or start a new one. If none is found, say so and go on to the intake.

- **New case:** sections 1 to 7 in order.
- **Existing case:** show what `case_info` and `README.md` already answer, ask the intake questions that are still open (in one message, as in section 1), and save the answers in `case_info`. Then go on from the first of sections 3 to 7 that is not done, for example section 4 when there is no `master.sqlite` yet. Files from earlier work that do not fit the layout in section 3 stay where they are: ask before moving or redoing any of them.
- **Case in the old layout** (`originals/` or `outputs/`, no `for-lawyer/`; made before version 0.5.0): before anything else, offer to move it to the layout in section 3. List what moves where, and wait for the yes:
  1. `originals/<source>/...` goes to `for-lawyer/raw/<source>/...`, with the same subfolders. `outputs/<name>.sql` goes to `work/queries/<name>.sql`. The other files in `outputs/` go to `for-lawyer/`, except those the person keeps in `work/`: drafts, earlier versions, anything unmasked.
  2. Move, do not copy. Hash each file before and after the move: the two must match, and match `evidence_files.sha256` where the file has a row.
  3. In `evidence_files`, set `case_path` to the new path and add the earlier one to `note`, after what `note` already holds (`case_path was originals/email/sent.mbox until 2026-11-06`). Without `master.sqlite`: create it (section 4), then record each moved file as in section 5, step 4, from what the case `README.md` says about it, with the earlier path in `note`; ask what the README does not say.
  4. Write `for-lawyer/raw/hashes.txt` (section 5, step 5) and `for-lawyer/README.md` (section 3), update the case `README.md`, record the move in `decisions`, and remove `originals/` and `outputs/` once they are empty.
  5. If the case folder was shared before (its `README.md` or `decisions` say so), the lawyers still see everything in it, database included. Tell the person; section 7, step 4 removes that access, and `for-lawyer/` is shared with the same lawyers instead.

## 1. Intake (one message)

For a new case, ask everything at once, in the person's language, and wait for the answers:

1. **Job:** role and what a working day looked like (code, support, sales, shifts...). This picks the sources in section 2.
2. **Contract:** working hours and days, and the contract's time zone. Where they actually lived and worked.
3. **Window:** first and last day to count. Earlier periods at the same company through a contractor or another employer may not count.
4. **Identities:** every work and personal email, name spellings (with and without diacritics), chat display names, git names.
5. **Evidence:** do they already have all of it, some of it, or none and want help finding it?
6. **Existing evidence:** where it is now (folders, drives, email attachments, phone exports).
7. **Git:** did they write code or configuration? Local clones on their computer (paths) and repository URLs. For each URL: are they still allowed to access it (still employed, or written permission)?
8. **Case folder:** which Google account to keep it in, and a short name for the case [`<employer>-<year the job ended>`]. It must be the person's own account, never the employer's Google Workspace or a Drive the employer manages: the folder holds their evidence, and its `for-lawyer/` folder will be shared with their lawyers.

These answers also cover section 0 of `cenk-overtime:collect`: do not ask them again there. Save them in `case_info` (section 4), including `drive_account` and `case_folder`.

## 2. Likely sources by job

| Job | Look for |
|---|---|
| Software, DevOps, data | git commits, tags, release branches; code review; CI/CD runs; issue tracker; work chat; on-call pages; cloud console and VPN logs |
| Support, operations, IT | ticket history; call logs; work chat; email; remote-access and monitoring logs |
| Sales, account management | sent email; CRM activity; calendar; calls; travel and expense records |
| Consulting, projects | timesheets next to chat and email; calendar; document version history |
| Office, finance, HR | sent email; document version history; ERP or payroll audit logs; VPN |
| Shifts, field, healthcare, retail | rota; time clock or badge records; handover notes; work phone; travel |
| Teaching, research | learning platform activity; email; grading timestamps |

For every job: the personal phone (WhatsApp, Telegram, Signal, call history) and any personal email the work mail was forwarded to. Records only the employer holds (VPN, SSO, badge, server and audit logs, push logs) go on a list for the lawyer to request.

If the person has some or none of the evidence, go through the table for their job, then the source table of `cenk-overtime:collect`, and agree which sources to get. Collect what the person sent or did, not what they received.

## 3. Case folder in Google Drive

Each case gets its own folder: `My Drive/overtime-cases/<case>/` in the person's Google Drive. Cases stay apart from each other and from this skill's files, and only a case's `for-lawyer/` folder is ever shared, so sharing one case shares nothing else.

Find it on the computer through Google Drive for desktop, which shows each signed-in account:
- Windows: as a drive letter, `X:\My Drive`. The drive's label is the account's email (Explorer, or `Get-PSDrive` in PowerShell).
- macOS: `~/Library/CloudStorage/GoogleDrive-<email>/My Drive`.

If several accounts appear, ask which one. If Google Drive for desktop is not installed, ask the person to install it and sign in with their own account; if they would rather not, create the folder on the computer and tell them to upload `for-lawyer/` to their Drive before sharing it. Paths here contain spaces (`My Drive`): quote them in every command.

Create this layout:

```
<case>/
  README.md          the plugin's record: layout, sources, decisions, shares (not shared)
  master.sqlite      master database, section 4 (not shared)
  git/<repo>/        git history tables written by the script, section 6 (not shared)
  work/              normalized tables, scripts, scratch work (not shared)
    queries/         <artifact>.sql: the query that built each artifact (section 4)
  for-lawyer/        the only folder shared with the lawyers, as Viewer (section 7)
    README.md        plain description for the lawyer
    <artifacts>      summary, full report, spreadsheet, package (cenk-overtime:court-package)
    raw/<source>/    evidence as received, with its own subfolders: never edited (section 5)
    raw/hashes.txt   SHA-256 of every file in raw/, paths relative to raw/
```

`<source>` is one of `email`, `teams`, `slack`, `whatsapp`, `calls`, `calendar`, `tracker`, `other`.

Write both READMEs when the folder is created, and update them whenever something is added:
- `README.md`: what each folder holds, where each piece of evidence came from, the decisions, and who `for-lawyer/` is shared with since when.
- `for-lawyer/README.md`, in plain words and in the court's language: what each file and folder is; the sources in `raw/` with their file counts; that `raw/` holds the evidence unmasked and is confidential, and that the masked records built from it are in the package's `5_Raw_Data/`; how to check `hashes.txt` (macOS and Linux: `shasum -a 256 -c hashes.txt` in `raw/`; Windows PowerShell: `Get-FileHash -Algorithm SHA256 <file>`, compared with its line); the records only the employer holds, for the lawyer to request (section 2); the AI notice of `cenk-overtime:court-package`, section 4.

Everything in the case folder goes to Google's servers; only `for-lawyer/` goes to the lawyers. These stay on the computer only:
- git clones, in `~/overtime-clones/<case>/` (section 6): they hold the employer's source code;
- the list of passwords found in messages, `secrets.json`, next to the clones (`cenk-overtime:court-package`, section 1);
- the git script's temporary files, in the system temp folder.

Because the folder syncs:
- Write to `master.sqlite` from one computer at a time, and let Drive finish syncing before opening it on another.
- Google Drive for desktop ignores the read-only flag, so the files in `for-lawyer/raw/` cannot be locked. Their SHA-256 hashes (`hashes.txt`, section 5) show that they were not changed; check them again before the package is built.
- A file is in front of the lawyers as soon as it lands in `for-lawyer/`: only evidence as received (in `raw/`) and finished, masked artifacts go there. Drafts and unmasked outputs stay in `work/`.

## 4. Master database

Create `master.sqlite` from `scripts/schema.sql` in this skill's base directory, with `sqlite3 master.sqlite < schema.sql` or Python's built-in `sqlite3` module (`executescript`). The schema only adds what is missing, so running it again is safe.

| Table | One row per |
|---|---|
| `case_info` | intake answer: `key`, `value`, `note` (`job`, `contract_hours`, `contract_days`, `contract_zone`, `lived_zone`, `window_from`, `window_to` as `YYYY-MM-DD`, `drive_account`, `case_folder`...) |
| `evidence_files` | file in `for-lawyer/raw/`: source, original path, case path, SHA-256, size, original modification time, date received, method, note (earlier case paths too) |
| `traces` | normalized record (`cenk-overtime:collect`, section 6), with `file_id` pointing to the evidence file it came from |
| `repos` | repository source the script read: kind, remote host, commit counts (own and others) |
| `commits` | own commit: hash, author, author time (with its offset, and in UTC), committer time, subject, files changed, lines added and deleted, binary files, merge flag |
| `commit_files` | file changed in an own commit, with its lines added and deleted |
| `tags`, `branches` | tag or branch with its date and commit |
| `git_identities` | identity of the person found in a repository, with its commit count |
| `decisions` | manual decision: what, why, who (sharing too, section 7) |

Views: `v_repo_summary`, `v_commits_by_day`, `v_commits_in_window` (uses `window_from` and `window_to` from `case_info`), `v_evidence_by_source`.

Rules:
- Every new artifact (table, chart, report figure) is a query on `master.sqlite`. Save the query in `work/queries/`, named after the artifact (`work/queries/weekly-chart.sql` for `weekly-chart.svg`), so it can be rebuilt and checked. Queries stay out of `for-lawyer/`: the lawyers do not get the database.
- `cenk-overtime:analyse` and `cenk-overtime:court-package` read git data from these tables instead of extracting it again. Tables they add (periods, events, categories) go into the same database.
- Every manual include, exclude or correction goes into `decisions` with its reason.
- Only the person's own commits and identities are stored. Other authors appear only as a count per repository.

## 5. Bringing existing evidence in

1. For each place the person named: list file names, sizes and dates; do not open contents yet. Never open password managers, vaults, key or credential folders.
2. Agree with the person which files belong to the case.
3. Copy each file into `for-lawyer/raw/<source>/`, keeping its name and the subfolders it has below the place the person named: names repeat across folders (a Slack export has a `2024-03-05.json` in every channel folder). Never overwrite a file in `raw/`: if a path is taken, add a subfolder named after the place the file came from. Leave the original where it is. Move only if the person asks for it; moving out of a synced folder (OneDrive, Google Drive, iCloud) also deletes it there, so say so first.
4. Hash the original and the copy (`sha256sum`, or `shasum -a 256` on macOS); they must match. Record one `evidence_files` row per file, with `case_path` relative to the case folder (`for-lawyer/raw/slack/general/2024-03-05.json`) and `method` = `copied` or `moved`.
5. Write `for-lawyer/raw/hashes.txt` again: one line per file in `raw/` except itself, `<sha256>  <path>`, the path relative to `raw/` with `/` between folders, sorted by path. Git Bash on Windows writes ` *` instead of the two spaces; both forms check. Then run `sha256sum -c hashes.txt` (`shasum -a 256 -c` on macOS) in `raw/`: every line must say OK.
6. Tell the person to email `hashes.txt` to themselves the same day: the dated email shows the files have not changed since.
7. Update both READMEs (section 3), and report how many files came in per source (`v_evidence_by_source`).

New evidence collected later (`cenk-overtime:collect`) goes through the same steps.

## 6. Git history: shell script only

All git work goes through `scripts/git-history.sh` in this skill's base directory. Do not run ad-hoc git commands on the person's repositories. Run it with `bash` (Git Bash on Windows); it needs git, and `sqlite3` or Python 3.

1. **Which repositories:** only the employer's (remote host = the employer's git server). Leave out open-source clones and personal projects, even when they hold commits with the work email.
2. **URLs:** clone only after the person confirms they are still allowed to access the repository. The clone uses the person's own git login (credential manager or SSH key): never ask for a token or password, and the script refuses URLs that contain one. A clone holds the employer's source code: it goes to `~/overtime-clones/<case>/` on the computer (`--clones` picks another folder, never a synced one) and never into the case folder, which the script refuses. It is never uploaded, shared or packaged, and is deleted after extraction unless the person asks to keep it (`--keep-clone`).
3. **Local clones:** read only. The script never fetches, pulls, checks out or writes into them.
4. **Identities:** list the identities that look like the person, with a broad pattern, and agree with them which ones are theirs:
   ```bash
   bash <skill>/scripts/git-history.sh identities --case "<case>" --author 'surname|firstname' <repo-path-or-url>...
   ```
   Build the final pattern from the confirmed identities (escape dots: `name\.surname@`).
5. **Extract:** pass all clones of one repository in the same run, so they merge into one entry:
   ```bash
   bash <skill>/scripts/git-history.sh extract --case "<case>" --author '<confirmed pattern>' <repo-path-or-url>...
   ```
   It writes `git/<repo>/commits.tsv`, `commit_files.tsv`, `tags.tsv`, `branches.tsv`, `identities.tsv` and `repo.tsv`, and loads them into `master.sqlite`. Running it again for a repository replaces that repository's rows.
6. **Window:** set `window_from` and `window_to` in `case_info`; `v_commits_in_window` keeps only commits whose author date falls inside it.
7. **Report** per repository from `v_repo_summary`: own commits, first and last, files changed, lines added and deleted.

What the numbers mean, for the limitations section:
- The time of work is the author time, with the offset the author's computer had. `dates_differ` = 1 when the committer time is more than 5 minutes away (rebase, amend, cherry-pick). Conversion to the contract's time zone happens in the analysis.
- Merge commits count 0 files and 0 lines: git shows no diff for them.
- A moved or renamed file counts as deleted plus added (rename detection is off, so counts do not depend on git's guess).
- Binary files count as changed files with no lines.
- Machine-default emails (`user@HOSTNAME`, `user@10.x.x.x`) are stored as `user@local-machine`: they contain internal host names and addresses.
- Lightweight tags carry the tagged commit's date; a branch's date is its last commit.

## 7. Sharing with the lawyers

Sharing is the person's decision: never share without their yes for each email address. Only `for-lawyer/` is shared: the lawyers get the evidence and the artifacts, not the plugin's database, git tables or working files, which they cannot use.

1. Offer it once sections 3 to 6 are done, or whenever the person asks.
2. First say what the lawyers will see: everything in `for-lawyer/`, now and later. The evidence in `raw/` is unmasked: original files may contain passwords, tokens or keys that colleagues posted, and colleagues' private messages; masked versions come in the package from `cenk-overtime:court-package`. The case `README.md`, `master.sqlite`, `git/`, `work/` and the git clones are not shared.
3. Ask for each lawyer's email address. Access is Viewer; Editor only if the person asks for it, after saying that editors can change or delete evidence.
4. Share `for-lawyer/` itself, never the case folder, `overtime-cases` or anything above them: access to a folder covers everything in it. Before sharing, check that the case folder and `overtime-cases` are shared with nobody. If one is, tell the person and ask them to remove that access first: on drive.google.com, right-click the folder, Share, and choose Remove access next to each name.
5. With a Google Drive connector, share through it only if it finds this case's `for-lawyer` folder, the one inside the case folder: every case has one. If it finds none, it is signed in to another account. Otherwise tell the person how: on drive.google.com, open the case folder, right-click `for-lawyer`, Share, enter the email, choose Viewer, Send.
6. Record each share in `decisions` (who, access, date) and in the case `README.md`.

## 8. Then

1. `cenk-overtime:collect`: the remaining sources, normalized into `traces`.
2. `cenk-overtime:analyse`: on `traces` and the git tables.
3. `cenk-overtime:court-package`: masking, reports, spreadsheet, hashes.

Before each stage, tell the person what is done, what is next, and what you need from them.
