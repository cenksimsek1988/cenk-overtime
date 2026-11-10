# cenk-overtime

Help for employees who worked unpaid overtime or extra shifts and want to claim it from their employer.

Not legal advice. The plugin organises your own records and counts hours. It does not tell you whether you have a claim or what you are owed. What you may collect and use depends on your country and contract: ask a lawyer, especially before you access employer systems after your job has ended.

## Who it is for

- Employees and former employees with unpaid overtime or extra shifts.
- Their lawyers and court experts, who receive the report and can check every number in it.

## What it does

- Asks about your job, contract hours, the period to count and the evidence you already have.
- Works out which free programs it needs to read your documents and calculate, and installs them from their official sources after your yes.
- Creates a case folder in your own Google Drive, never your employer's. You share one folder of it with your lawyer, `for-lawyer`: your evidence as received and the reports.
- Copies your evidence into `for-lawyer/raw/` unchanged, with its subfolders, and lists a SHA-256 hash of each file in `hashes.txt`.
- Reads the git history of the employer repositories you name, and keeps only your own commits.
- Collects what you sent or did: sent email, work chat, WhatsApp exports, calls, calendar.
- Counts your evenings, nights, mornings and weekends, and gives a low and a high estimate of the hours, weekday and weekend apart.
- Tests the patterns with standard regression models (more out-of-hours work on release days, weekend work near releases, the load over the years), and explains each result in plain words, with what it does not show.
- Builds a package for your lawyer: a short summary, a full report, a spreadsheet, the data, and a tool that rebuilds every number. Passwords and private life are masked first.
- Marks the package as prepared with the help of AI, for your lawyer to check before anything is filed.

## What it does not do

- It gives no legal advice and does not calculate pay.
- It never asks for passwords or tokens, and refuses repository addresses that contain one.
- It installs nothing without your yes.
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
- Python 3. The plugin offers to install the rest when your case needs it: ffmpeg, Tesseract OCR with your documents' language, sqlite3, Python packages (PyMuPDF, pdfplumber, openpyxl, python-docx, Pillow, pandas, statsmodels, scipy; tzdata on Windows), and for the package LibreOffice and Playwright with Chromium.
- For git history: git and bash (Git Bash on Windows).

## What it runs, reads and sends

- Runs `skills/start/scripts/check-tools.py` to see which programs are missing; it installs nothing itself.
- After your yes, installs what is missing with winget (Windows), Homebrew (macOS) or apt (Debian, Ubuntu), Python packages with pip from PyPI, and text-recognition language data from the Tesseract project on GitHub.
- Runs `skills/start/scripts/git-history.sh` with bash to read git history, and Python or `sqlite3` for the case database; `skills/start/scripts/contract-offset.py` records the contract zone's UTC offset for the day views.
- Runs `skills/analyse/scripts/models.py` (pandas, statsmodels, scipy) on the case database for the regression checks.
- For a large set of files, the privacy review, the final audit and the check of its fixes, Claude hands parts of the work to subagents, each on a named Claude model.
- For the package, Claude writes a small Python tool that rebuilds every number, runs it on your computer, and puts it in the package.
- Reads only the files and folders you agree to. It never opens password managers, vaults or key folders.
- Network: `git clone` of the employer repositories you name, with your own git login, into `~/overtime-clones/` on your computer. Each clone is deleted after reading, unless you ask to keep it. Program and package downloads after your yes; no case data goes with them.
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
- A program was installed but is not found: start a new Claude Code session, or use the path the tools check prints.
- Scanned documents come out garbled: their language pack is missing; the plugin offers to download it.
- No Google Drive for desktop: keep the case folder on your computer and upload its `for-lawyer` folder before you share it.

## License

MIT, see LICENSE in this folder: https://github.com/cenksimsek1988/cenk-overtime/blob/main/cenk-overtime/LICENSE
