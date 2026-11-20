---
name: "coordinate"
description: "The main session for your overtime cases: keeps the list of your cases and their folders, and starts one session per case in that case's own folder. Not legal advice. Use for: coordinate my overtime cases, list my overtime cases, open a session for my case, fazla mesai davalarımı yönet, davam için oturum aç, gestire le mie cause per straordinari, meine Überstundenfälle verwalten, gestionar mis casos de horas extra, gérer mes dossiers d'heures supplémentaires."
---

# Coordinate: the cases session

The coordinator keeps the case list and one session per case; the case work itself is `/cenk-overtime:start` in the case's session, never here.

## First

1. Check cenk-base (Bash tool): `CENK_BASE` set and `"$CENK_BASE/references/coordinator.md"` a file. `CENK_BASE` unset: tell the person a part this plugin needs is missing and give `claude plugin install cenk-overtime@<marketplace>`, then a new session. The file missing (cenk-base older than 0.2.0): `claude plugin update cenk-base@cenk`, then a new session. Stop until it is there.
2. Read the shared coordinator rules, `$CENK_BASE/references/coordinator.md`: one coordinator, titles, briefs, questions, messages, hand-off files, archiving. This skill adds only the cases.
3. Find this session's plugin entry: `claude plugin list --json`, the `cenk-overtime@<marketplace>` entry whose `projectPath` is this folder, else the one at user scope. Take the title (the app's session-title tool) by it: with `readFromFolder` (loaded from a source folder: the plugin's developer) "Coordinator · cenk-overtime", else "Overtime coordinator".
4. The folder: any folder the person picks, never a case folder or the folder that holds the cases. Example: a folder in Documents, or the plugin's own repository for its developer.
5. Run `python -I "$CENK_BASE/lib/profile.py" home` for the cenk folder; nothing usable: send the person to `/cenk-overtime:start`, which creates the profile, and stop.

## The case list

- `<cenk folder>/cenk-overtime/cases.md`, one table row per case: `| case | folder | account | session | state | updated |`. Example: `| acme-2024 | G:/My Drive/Legal cases/acme-2024 | own Google account | local_ab12 | Ready | 2026-11-20 |`.
- `folder` is the absolute path on this computer; `session` the case session's `local_...` id, empty when none; `state` one of `new`, `You`, `Ready`, `Done`, `missing`, `closed`.
- The coordinator is its only writer: the file syncs through Google Drive, and two writers lose each other's rows.
- It holds case names, folders and states only: never evidence, figures or the person's facts. It never goes into a repository or a case folder.

## Building the list

- No list yet, or the person asks: find the cases as `/cenk-overtime:start` section 0 does: folders two levels below `My Drive` in every Google Drive account on the computer, holding `master.sqlite`, `<case>-evidence/`, `for-lawyer/`, `originals/` or `outputs/`. Folder names only: nothing inside a case is opened here.
- Show each found case (name, folder, account) and write a row only after the person confirms it.
- A row whose folder is gone: state `missing`, and ask the person where the case is now. Never guess a folder from a similar name.
- A new case: the person names the folder that holds their legal cases and a short case name [`<employer>-<year the job ended>`]; after their yes, create the empty folder `<cases folder>/<case>/`, state `new`. `start` creates everything inside it.

## A session per case

Started only on a turn the person's own message started; otherwise proposed as a card (shared rules).

1. The folder exists and is the row's case (as in "Building the list", or empty for a `new` case).
2. The marketplace: from this session's plugin entry (First, step 3). Example: `cenk` for a catalog install.
3. In the case folder, enable the plugin there only: `cd "<case folder>" && claude plugin install cenk-overtime@<marketplace> --scope local`. Never `--scope user` or `--scope project`: local scope keeps it off in every other folder and out of what syncs to the lawyers. It writes `<case folder>/.claude/settings.local.json`, outside the evidence folder.
4. Check: `claude plugin list --json` shows `cenk-overtime@<marketplace>` with `scope` `local`, `projectPath` the case folder and `enabled` true. Not there: stop and tell the person the line that failed.
5. `start_session`: `cwd` the case folder, context fresh, title `<state> · <case>`, name `case-<case>`. The app may ask the person to trust the folder.
6. Record the session id and state in the row.

The brief names the case and its folder and says:
- Work only in this folder; never open another case or anything above this folder.
- Run `/cenk-overtime:start`; this folder is the case: skip the case list.
- Each milestone in one line to the coordinator (its `local_...` id): plan agreed, a stage done, waiting on the person (on what).
- Questions for the person go to the coordinator, unless the person answers here.
- At the end, the hand-off below, then one line to the coordinator, and stop.

A case that already has an open session is reached by message to its id, never a second session.

## The hand-off a case session ends with

`<case folder>/work/handoff.md` (`work/` is never shared): the stage reached (`start` sections done, collect, analyse, court-package), what waits on the person, the next step, and lessons for the plugin. Facts only: no evidence content, figures, names or the person's facts; the case's records hold those.

The coordinator reads it, sets the row's state, passes the lessons on, deletes the file and archives the session (shared rules).

## Rules

- Never does case work, opens evidence, reads `master.sqlite` or shares anything: that is the case session's, under `start`.
- Never changes the plugin and never starts a session in its repository for a case. A lesson goes in one message to the session titled "Coordinator · workbench" when one is open, else into the report for the person, with the plugin's issues page.
- Its own hand-off, at the end of each session: `<cenk folder>/cenk-overtime/handoffs/coordinator.md`, listing each open case session (id, state, waits on). The next coordinator reads and deletes it first.
- Each turn ends with the case list's rows that changed and what waits on the person.
