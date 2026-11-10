# cenk-overtime

Cenk's Claude Code plugin for employees who claim unpaid overtime. Public: github.com/cenksimsek1988/cenk-overtime (MIT). README.md is for people; this file is for the assistant.

## What belongs here

- Generic material only: the plugin, its tests and docs. Case data (documents, figures, git exports, connections) lives in each person's own Drive case folder, never here.
- Before publishing any text, check it for figures and examples from a real case, not only for names and emails.
- Case folders: only `for-lawyer/` is shared (evidence as received in `raw/`, `raw/hashes.txt`, the artifacts). The case README, `master.sqlite`, `git/` and `work/` stay unshared: lawyers cannot use the normalized data (Cenk's decision, 6 Nov 2026, from 0.5.0).

## Layout

- `.claude-plugin/marketplace.json`: one-plugin marketplace, source `./cenk-overtime`, for a clone and Cenk's own install. Users install from the public catalog `cenk` (repository `cenksimsek1988/claude-plugins`) as `cenk-overtime@cenk`; its entry has no version, so a release needs no change there (6 Nov 2026).
- `cenk-overtime/skills/`: `start` (tools check, intake, case folder, database, git script), `collect`, `analyse`, `court-package`. The last three have `user-invocable: false`; `start` runs them. Cross-references use `cenk-overtime:<skill>`.
- Scripts: `start/scripts/check-tools.py` (standard library; lists missing programs and prints install commands, installs nothing), `start/scripts/git-history.sh`, `start/scripts/schema.sql`, `start/scripts/contract-offset.py` (standard library; tzdata on Windows), `analyse/scripts/models.py` (pandas, numpy, statsmodels, scipy).
- The git views take days from `author_utc` with the fixed `contract_offset_minutes`; zones with daylight saving inside the window get NULL there, and the analysis converts in Python. Never base a day on `author_date`: its offset is the author's machine's. References read on demand: `start/references/tools.md`, `collect/references/readers-and-checkers.md`.
- Tools, Cenk's decision (6 Nov 2026): the plugin decides which programs a case needs; it tells the person in plain words that it will install some free programs to read their documents and calculate, without naming libraries, and asks one yes per round. A language pack only when a document in that language turns up or the person writes in it.
- Subagent models are Claude Code aliases (`haiku`, `sonnet`, `opus`, `fable`). When Anthropic's lineup changes, update the alias line in `collect/references/readers-and-checkers.md` and check the roles in `collect` section 3 and `court-package` sections 2 and 7.
- Skill descriptions: one sentence, then "Use for:" with trigger phrases in English, Turkish, Italian, German, Spanish and French; quoted; at most 1024 characters, no angle brackets (claude.ai's limits).
- `cenk-overtime/README.md`: the plugin's own README, which Anthropic's directory shows as the listing's description. It lists what the plugin runs, reads and sends: update it with every skill change that touches those.
- `PRIVACY.md` and `SECURITY.md` at the root: the directory's privacy policy link and the route for vulnerability reports.
- `LICENSE` is at the root and in `cenk-overtime/`, because installs and the `.plugin` file get only the plugin folder: keep the two copies identical (`cmp LICENSE cenk-overtime/LICENSE`).

## Directory

- Not submitted yet. Route: claude.ai/directory/manage > Submit new > Plugin bundle; repository `cenksimsek1988/cenk-overtime`, plugin path `cenk-overtime`.
- Validation blocks a plugin folder without a README of 40 or more words outside code blocks.
- Legal is a high-risk area in Anthropic's usage policy: keep the AI notice and the lawyer's check in `court-package`, and "Not legal advice" in the descriptions.
- `SECURITY.md` links GitHub's private vulnerability reporting, which must be turned on in the repository settings.

## Check

- `bash tests/test-git-history.sh`: 70 checks on throwaway repositories in the temp folder (also contract-offset.py); `CASE_DIR=<new folder>` puts the case folder elsewhere, such as Google Drive. It loads through `sqlite3` when that is on PATH, else through Python: run it once with each.
- `sh tests/test-check-tools.sh`: 30 checks with stub programs and stub Python packages; the real ones stay out of sight. In Git Bash it needs a POSIX `TMPDIR` (`/c/Users/...`): the colon in `C:/...` breaks `cygpath -wp`, and 12 checks fail.
- `sh tests/test-models.sh`: 68 checks of `models.py` on a made-up two-year case with known effects; needs pandas, numpy, statsmodels and scipy; about a minute.
- `claude plugin validate --strict` on `cenk-overtime`, `cenk-overtime/skills` and the repository root.

## Release

1. Raise `version` in `cenk-overtime/.claude-plugin/plugin.json`; add a CHANGELOG entry.
2. Run the checks, commit with `/cenk-workbench:commit`, push.
3. Pack the release commit's `cenk-overtime/` (`.claude-plugin/plugin.json` at the zip root) with `git -c core.autocrlf=false archive --format=zip -o cenk-overtime.plugin <commit>:cenk-overtime`, check that no file in the zip contains a CR, then `gh release create vX.Y.Z cenk-overtime.plugin --target <full commit hash> --title "cenk-overtime X.Y.Z" --notes-file <notes> --latest`. The notes keep the previous release's opening and install text (`gh release view <tag>`), then list the changes in plain words.
4. `claude plugin marketplace update cenk-overtime`, then `claude plugin update cenk-overtime@cenk-overtime` (Cenk's install uses this folder as a directory marketplace).

## Quirks

- Install from the HTTPS address; the `owner/repo` form clones over SSH and fails without a GitHub host key.
- `user-invocable` is not among the Agent Skills front-matter keys: a single-skill upload on claude.ai (Customize > Skills) fails on it. The directory does not check it, and plugins listed in claude-plugins-official (project-artifact, telegram, discord) carry it.
- Google Drive for desktop ignores the read-only flag; the skills rely on SHA-256 hashes.
- `sha256sum` on Windows writes ` *` before each path.
- Archiving only the `cenk-overtime/` subtree leaves the root `.gitattributes` behind, so with `core.autocrlf=true` (as on Cenk's machine) every file in the zip comes out CRLF and `git-history.sh` breaks under bash. Hence `core.autocrlf=false` in release step 3.
- The repository's git identity is set locally; the machine's global identity belongs to a former employer and must not be used.
- The test's two fake credential URLs carry `secret-scan: allow`.

## Open

- The `.plugin` upload to claude.ai is untested since 0.2.0; Cowork is untested.
- Not tested: macOS and Linux `awk`; `check-tools.py` on macOS and Linux, including the PEP 668 venv commands; the Tools step in a live session.
- Workbench 0.19.3's `scripts/check-plugin.sh` gives this plugin one FAIL, the description budget (350 against the 1024-character rule under Layout), and one WARN, no `tests/run.sh` (the three test scripts under Check run one by one).
