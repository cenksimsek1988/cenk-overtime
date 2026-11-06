---
name: "start"
description: "Starts an unpaid overtime or extra-shift claim, or picks up one you started before, and guides it to a court-ready report: asks about your job, contract hours and the evidence you already have, creates a case folder in your own Google Drive to share with your lawyer, brings your evidence in with hashes, reads your git history, then runs cenk-overtime:collect, :analyse and :court-package in order. Use for: I worked unpaid overtime, my extra shifts were never paid, claim overtime from my employer, prepare my overtime case for my lawyer, fazla mesai hesapla, fazla mesai davası açacağım, fazla mesai alacağımı nasıl kanıtlarım, işçi alacağı davası, straordinari non pagati, causa di lavoro per gli straordinari, unbezahlte Überstunden, Überstunden nachweisen, Überstundenvergütung einklagen, horas extra no pagadas, reclamar horas extra, heures supplémentaires non payées, prouver mes heures supplémentaires."
---

# Overtime evidence: start here

The single entry point for an overtime case. This skill owns the choice of case, the intake, the case folder, sharing it with the lawyers, the master database and git history. The detail of each later stage lives in three skills of this plugin, used in this order:

1. `cenk-overtime:collect`: getting the remaining traces and normalizing them.
2. `cenk-overtime:analyse`: definitions, counts, hour estimates, release and incident relation.
3. `cenk-overtime:court-package`: masking, reports, spreadsheet, hashes, audit.

Where this skill and one of them differ, this skill wins: case folder, sharing, master database, evidence import, and git (section 6 replaces section 4 of `cenk-overtime:collect`).

In the first message, say that this is not legal advice: rules on what evidence may be collected and used differ by country and contract, and a lawyer should confirm them, especially access to employer systems after the job has ended.

## 0. Which case

Before the intake, find the cases the person already has: the folders in `My Drive/overtime-cases/` of every Google Drive account on the computer (section 3 says where each account appears). For each case, read only its `README.md` and, if `master.sqlite` exists, its `case_info` table. Do not open `originals/`, `git/` or `work/` yet.

In the first message, list the cases found (name, account, last change) and ask whether to continue one of them or start a new one. If none is found, say so and go on to the intake.

- **New case:** sections 1 to 7 in order.
- **Existing case:** show what `case_info` and `README.md` already answer, ask the intake questions that are still open (in one message, as in section 1), and save the answers in `case_info`. Then go on from the first of sections 3 to 7 that is not done, for example section 4 when there is no `master.sqlite` yet. Files from earlier work that do not fit the layout in section 3 stay where they are: ask before moving or redoing any of them.

## 1. Intake (one message)

For a new case, ask everything at once, in the person's language, and wait for the answers:

1. **Job:** role and what a working day looked like (code, support, sales, shifts...). This picks the sources in section 2.
2. **Contract:** working hours and days, and the contract's time zone. Where they actually lived and worked.
3. **Window:** first and last day to count. Earlier periods at the same company through a contractor or another employer may not count.
4. **Identities:** every work and personal email, name spellings (with and without diacritics), chat display names, git names.
5. **Evidence:** do they already have all of it, some of it, or none and want help finding it?
6. **Existing evidence:** where it is now (folders, drives, email attachments, phone exports).
7. **Git:** did they write code or configuration? Local clones on their computer (paths) and repository URLs. For each URL: are they still allowed to access it (still employed, or written permission)?
8. **Case folder:** which Google account to keep it in, and a short name for the case [`<employer>-<year the job ended>`]. It must be the person's own account, never the employer's Google Workspace or a Drive the employer manages: the folder will be shared with their lawyers.

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

Each case gets its own folder: `My Drive/overtime-cases/<case>/` in the person's Google Drive. Cases stay apart from each other and from this skill's files, so sharing one case shares nothing else.

Find it on the computer through Google Drive for desktop, which shows each signed-in account:
- Windows: as a drive letter, `X:\My Drive`. The drive's label is the account's email (Explorer, or `Get-PSDrive` in PowerShell).
- macOS: `~/Library/CloudStorage/GoogleDrive-<email>/My Drive`.

If several accounts appear, ask which one. If Google Drive for desktop is not installed, ask the person to install it and sign in with their own account; if they would rather not, create the folder on the computer and tell them to upload it before sharing. Paths here contain spaces (`My Drive`): quote them in every command.

Create this layout and write `README.md` in it: what each folder holds, where each piece of evidence came from, and who the folder is shared with since when. Update it whenever something is added.

```
<case>/
  README.md            what is where, and who it is shared with
  master.sqlite        master database (section 4)
  originals/<source>/  evidence as received: never edited, hashed on arrival
  git/<repo>/          git history tables written by the script (section 6)
  work/                derived files: normalized tables, scratch work
  outputs/             charts, reports, packages, each with the query that built it
```

`<source>` is one of `email`, `teams`, `slack`, `whatsapp`, `calls`, `calendar`, `tracker`, `other`.

Everything in this folder goes to Google's servers and to the lawyers. These stay on the computer only:
- git clones, in `~/overtime-clones/<case>/` (section 6): they hold the employer's source code;
- the git script's temporary files, in the system temp folder.

Because the folder syncs:
- Write to `master.sqlite` from one computer at a time, and let Drive finish syncing before opening it on another.
- Google Drive for desktop ignores the read-only flag, so copies in `originals/` cannot be locked. Their SHA-256 hashes (section 5) show that they were not changed; check them again before the package is built.

## 4. Master database

Create `master.sqlite` from `scripts/schema.sql` in this skill's base directory, with `sqlite3 master.sqlite < schema.sql` or Python's built-in `sqlite3` module (`executescript`). The schema only adds what is missing, so running it again is safe.

| Table | One row per |
|---|---|
| `case_info` | intake answer: `key`, `value`, `note` (`job`, `contract_hours`, `contract_days`, `contract_zone`, `lived_zone`, `window_from`, `window_to` as `YYYY-MM-DD`, `drive_account`, `case_folder`...) |
| `evidence_files` | file in `originals/`: source, original path, case path, SHA-256, size, original modification time, date received, method |
| `traces` | normalized record (`cenk-overtime:collect`, section 6), with `file_id` pointing to the evidence file it came from |
| `repos` | repository source the script read: kind, remote host, commit counts (own and others) |
| `commits` | own commit: hash, author, author time (with its offset, and in UTC), committer time, subject, files changed, lines added and deleted, binary files, merge flag |
| `commit_files` | file changed in an own commit, with its lines added and deleted |
| `tags`, `branches` | tag or branch with its date and commit |
| `git_identities` | identity of the person found in a repository, with its commit count |
| `decisions` | manual decision: what, why, who (sharing too, section 7) |

Views: `v_repo_summary`, `v_commits_by_day`, `v_commits_in_window` (uses `window_from` and `window_to` from `case_info`), `v_evidence_by_source`.

Rules:
- Every new artifact (table, chart, report figure) is a query on `master.sqlite`. Save the query next to the artifact (`outputs/<name>.sql`) so it can be rebuilt and checked.
- `cenk-overtime:analyse` and `cenk-overtime:court-package` read git data from these tables instead of extracting it again. Tables they add (periods, events, categories) go into the same database.
- Every manual include, exclude or correction goes into `decisions` with its reason.
- Only the person's own commits and identities are stored. Other authors appear only as a count per repository.

## 5. Bringing existing evidence in

1. For each place the person named: list file names, sizes and dates; do not open contents yet. Never open password managers, vaults, key or credential folders.
2. Agree with the person which files belong to the case.
3. Copy each file into `originals/<source>/`, keeping its name. Leave the original where it is. Move only if the person asks for it; moving out of a synced folder (OneDrive, Google Drive, iCloud) also deletes it there, so say so first.
4. Hash the original and the copy (`sha256sum`, or `shasum -a 256` on macOS); they must match. Record one `evidence_files` row per file, with `method` = `copied` or `moved`.
5. Tell the person to email the list of hashes to themselves the same day: the dated email shows the copies have not changed since.
6. Report how many files came in per source (`v_evidence_by_source`).

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

Sharing is the person's decision: never share without their yes for each email address.

1. Offer it once sections 3 to 6 are done, or whenever the person asks.
2. First say what the lawyers will see: everything in the case folder, now and later, unmasked. Original files may contain passwords, tokens or keys that colleagues posted, and colleagues' private messages; masked versions come from `cenk-overtime:court-package`. Git clones are not in the folder.
3. Ask for each lawyer's email address. Access is Viewer; Editor only if the person asks for it, after saying that editors can change or delete evidence.
4. Share the case folder itself, never `overtime-cases` or anything above it. With a Google Drive connector, share through it only if it finds the case folder; if it does not, it is signed in to another account. Otherwise tell the person how: on drive.google.com, right-click the case folder, Share, enter the email, choose Viewer, Send.
5. Record each share in `decisions` (who, access, date) and in `README.md`.

## 8. Then

1. `cenk-overtime:collect`: the remaining sources, normalized into `traces`.
2. `cenk-overtime:analyse`: on `traces` and the git tables.
3. `cenk-overtime:court-package`: masking, reports, spreadsheet, hashes.

Before each stage, tell the person what is done, what is next, and what you need from them.
