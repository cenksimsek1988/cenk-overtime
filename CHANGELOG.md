# Changelog

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
