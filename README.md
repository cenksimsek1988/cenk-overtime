# cenk-overtime

For employees who worked unpaid overtime or extra shifts and want to claim it from their employer.

What you get: a case folder in your own Google Drive to share with your lawyer, your overtime hours counted from your own work traces (sent email, work chat, phone, calendar, git), weekday and weekend apart, and an evidence report for your lawyer to check before anything is filed. The report says that it was prepared with the help of AI.

Not legal advice. What you may collect and use depends on your country and contract, so ask a lawyer, especially before accessing employer systems after your job has ended.

The method itself, in plain prose for employees, lawyers and court experts, is in [docs/guide.md](docs/guide.md).

## Skills

Start with `/cenk-overtime:start`, or just say "I want to claim my unpaid overtime". It runs the other three when their turn comes, so only `start` appears in the `/` menu. More example prompts are in [cenk-overtime/README.md](cenk-overtime/README.md).

| Skill | What it does |
|---|---|
| `cenk-overtime:start` | Picks up a case you started before or starts a new one; asks about your job, contract hours and the evidence you already have, creates the case folder in your Google Drive, sets up the database, brings your evidence in with hashes, and reads your git history |
| `cenk-overtime:collect` | Finds and collects your remaining work traces and puts them in one table |
| `cenk-overtime:analyse` | Counts your out-of-hours work and estimates the hours, conservatively and continuously, weekday and weekend apart |
| `cenk-overtime:court-package` | Masks passwords and private life, and builds the reports, spreadsheet and hashes for your lawyer and the court |

## What you need

- Claude Code: the terminal, an IDE extension, or the Code tab of the Claude desktop app. It does not work in claude.ai chat: it needs your files, git and a shell on your computer. Not tested in Cowork.
- Google Drive for desktop, signed in with your own Google account, never your employer's.
- For git history: git, bash (Git Bash on Windows), and Python 3 or the `sqlite3` tool.

## Install in Claude Code

```bash
claude plugin marketplace add https://github.com/cenksimsek1988/cenk-overtime.git
```
```bash
claude plugin install cenk-overtime@cenk-overtime
```

Use the `https://` address as written: the short form `cenksimsek1988/cenk-overtime` makes Claude Code clone over SSH, which fails on computers that have never connected to GitHub that way. Then start a new Claude Code session and type `/cenk-overtime:start`.

To get a newer version later:
```bash
claude plugin marketplace update cenk-overtime
```
```bash
claude plugin update cenk-overtime@cenk-overtime
```

## Install in claude.ai or the Claude desktop app

Each [GitHub release](https://github.com/cenksimsek1988/cenk-overtime/releases) has `cenk-overtime.plugin`: the same plugin packed as one file, for where plugins are added from a file instead of a command. Download it from the latest release and add it as a plugin. This route has not been tested with this version; the Claude Code route above has.

## Your data

The plugin has no hooks, servers or tracking, and sends nothing to its author. Your case folder stays in your own Google Drive and on your computer; Claude reads what you work on with it, as with anything else.

- Network: it clones the employer repositories you name, with your own git login, into `overtime-clones` in your home folder, and deletes each clone after the git history is read.
- Your case folder syncs to Google Drive through Google Drive for desktop.
- Connectors you already have (Microsoft 365, Gmail, Google Drive) are used with your sign-in, to search your sent messages or to share the case folder.
- Nothing is shared without your yes for each email address.

The full list of what it runs, reads and sends is in [cenk-overtime/README.md](cenk-overtime/README.md); [PRIVACY.md](PRIVACY.md) says who sees your data and how to delete it. Report security problems privately as [SECURITY.md](SECURITY.md) says.

## Files here

```
README.md                          this file
CHANGELOG.md                       what changed in each version
LICENSE                            MIT
PRIVACY.md                         what data the plugin reads, stores and shares
SECURITY.md                        how to report a vulnerability
CLAUDE.md                          notes for Claude when working on this repository
docs/guide.md                      the method in plain prose
.claude-plugin/marketplace.json    lets Claude Code install from this repository
cenk-overtime/                     the plugin
cenk-overtime/README.md            the plugin's own description, example prompts, what it runs and sends
cenk-overtime/LICENSE              the same MIT license, so it travels with every install
tests/test-git-history.sh          checks for the git history script (bash tests/test-git-history.sh)
```

## License

MIT, see [LICENSE](LICENSE). Others can read, install and fork it; only the author changes this repository.
