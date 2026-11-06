# cenk-overtime

Help for employees who worked unpaid overtime or extra shifts and want to claim it from their employer.

Not legal advice. The plugin organises your own records and counts hours. It does not tell you whether you have a claim or what you are owed. What you may collect and use depends on your country and contract: ask a lawyer, especially before you access employer systems after your job has ended.

## Who it is for

- Employees and former employees with unpaid overtime or extra shifts.
- Their lawyers and court experts, who receive the report and can check every number in it.

## What it does

- Asks about your job, contract hours, the period to count and the evidence you already have.
- Creates a case folder in your own Google Drive, never your employer's. You share one folder of it with your lawyer, `for-lawyer`: your evidence as received and the reports.
- Copies your evidence into `for-lawyer/raw/` unchanged, with its subfolders, and lists a SHA-256 hash of each file in `hashes.txt`.
- Reads the git history of the employer repositories you name, and keeps only your own commits.
- Collects what you sent or did: sent email, work chat, WhatsApp exports, calls, calendar.
- Counts your evenings, nights, mornings and weekends, and gives a low and a high estimate of the hours, weekday and weekend apart.
- Builds a package for your lawyer: a short summary, a full report, a spreadsheet, the data, and a tool that rebuilds every number. Passwords and private life are masked first.
- Marks the package as prepared with the help of AI, for your lawyer to check before anything is filed.

## What it does not do

- It gives no legal advice and does not calculate pay.
- It never asks for passwords or tokens, and refuses repository addresses that contain one.
- It asks whether you may still access each employer repository, and clones it only after you confirm.
- Before any export from employer systems, it tells you to check with a lawyer what you may use.
- It never puts your employer's source code in the case folder or the package.
- It shares only the `for-lawyer` folder, and only after your yes for each email address. The case database, git tables and working files are not shared.
- It sends nothing to its author: no servers, no hooks, no tracking.
- It does not work in claude.ai chat: it needs your files, git and a shell.

## Try it

- "I worked unpaid overtime for two years. Help me prepare my claim for my lawyer."
- "Continue my overtime case."
- "How many hours did I work on weekends, going by my sent emails and git commits?"
- "Build the evidence package for my lawyer, with passwords and private messages masked."

Or type `/cenk-overtime:start`. It runs `collect`, `analyse` and `court-package` in order. The skills also answer to Turkish, Italian, German, Spanish and French.

## What you need

- Claude Code: the terminal, an IDE extension, or the Code tab of the Claude desktop app. Not tested in Cowork.
- Google Drive for desktop, signed in with your own Google account.
- For git history: git, bash (Git Bash on Windows), and Python 3 or `sqlite3`.
- For the package: Python 3; optional openpyxl, Playwright with Chromium, LibreOffice and pdftotext.

## What it runs, reads and sends

- Runs `skills/start/scripts/git-history.sh` with bash to read git history, and Python or `sqlite3` for the case database.
- For the package, Claude writes a small Python tool that rebuilds every number, runs it on your computer, and puts it in the package.
- Reads only the files and folders you agree to. It never opens password managers, vaults or key folders.
- Network: `git clone` of the employer repositories you name, with your own git login, into `~/overtime-clones/` on your computer. Each clone is deleted after reading, unless you ask to keep it.
- Your case folder syncs to your Google Drive through Google Drive for desktop.
- If you have Microsoft 365, Gmail or Google Drive connected, Claude uses them with your sign-in: to search your sent messages, or to share the `for-lawyer` folder after your yes.
- Passwords found in your messages are listed in a file on your computer, outside the case folder, used only to mask them, and deleted when you say the package is final.
- Claude processes what it reads in your session, as with any other work. Details: https://github.com/cenksimsek1988/cenk-overtime/blob/main/PRIVACY.md

## Help

- The method in plain prose: https://github.com/cenksimsek1988/cenk-overtime/blob/main/docs/guide.md
- Questions and bugs: https://github.com/cenksimsek1988/cenk-overtime/issues
- Security problems: https://github.com/cenksimsek1988/cenk-overtime/blob/main/SECURITY.md
- Clone fails with a host key error: install from the `https://` address, not the `owner/repo` short form.
- "python3" opens the Microsoft Store on Windows: the script also tries `python` and `py`.
- No Google Drive for desktop: keep the case folder on your computer and upload its `for-lawyer` folder before you share it.

## License

MIT, see LICENSE in this folder: https://github.com/cenksimsek1988/cenk-overtime/blob/main/cenk-overtime/LICENSE
