# Tools: install facts

Read when `scripts/check-tools.py` reports something missing. The script prints the commands; these are the facts behind them. Install only from these sources.

| Tool | Windows (winget) | macOS (Homebrew) | Debian, Ubuntu (apt) |
|---|---|---|---|
| ffmpeg, ffprobe | `Gyan.FFmpeg`: the gyan.dev build that ffmpeg.org links to | `ffmpeg` | `ffmpeg` |
| Tesseract OCR | `UB-Mannheim.TesseractOCR`: the Mannheim University Library build that the Tesseract docs link to | `tesseract`; `tesseract-lang` for other languages | `tesseract-ocr`; `tesseract-ocr-<lang>` |
| pdftotext, pdfinfo, pdftoppm | not needed: PyMuPDF does this | `poppler` | `poppler-utils` |
| sqlite3 | `SQLite.SQLite`, from sqlite.org | `sqlite` (macOS has one) | `sqlite3` |
| git, Git Bash | `Git.Git` | `git` | `git` |
| LibreOffice | `TheDocumentFoundation.LibreOffice` | `--cask libreoffice` | `libreoffice` |
| Python packages | pip, from PyPI | pip, from PyPI | pip, from PyPI |
| Tesseract language data | `<lang>.traineddata` from github.com/tesseract-ocr/tessdata | in `tesseract-lang` | `tesseract-ocr-<lang>` |

Tesseract codes: `tur` Turkish, `eng` English, `ita` Italian, `deu` German, `spa` Spanish, `fra` French.

## Windows

- winget puts portable programs (ffmpeg, ffprobe, sqlite3) in `%LOCALAPPDATA%\Microsoft\WinGet\Links`, which new sessions find on PATH.
- The Tesseract installer asks for administrator rights: a Windows prompt the person approves. It installs into `%ProgramFiles%\Tesseract-OCR`, off PATH: call `tesseract.exe` by the path the check prints.
- That installer brings English only (seen: 5.4.0, Nov 2026). Its `tessdata` folder is writable only by administrators:
  1. Download `<lang>.traineddata` into a new temp folder: `curl.exe -L -o <temp>\tur.traineddata https://github.com/tesseract-ocr/tessdata/raw/main/tur.traineddata` (18.8 MB).
  2. Compare `git hash-object <file>` with the `sha` of `https://api.github.com/repos/tesseract-ocr/tessdata/contents/tur.traineddata`.
  3. Copy it in with an administrator prompt: `Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command',"Copy-Item -LiteralPath '<temp>\tur.traineddata' -Destination '<tessdata>\tur.traineddata'"`.
  4. `tesseract --list-langs` must now list the language.
- Windows has no time zone database of its own: Python's `zoneinfo` (contract-offset.py, the analysis) reads it from the `tzdata` package, which the check lists there.
- In PowerShell, `python` can be a Microsoft Store alias that fails ("The system cannot find the path specified"): use `py`, or the path the check prints.
- `bash` on PATH can be the WSL launcher in `System32`. git-history.sh needs Git Bash: the check prints its path.

## macOS and Linux

- Homebrew's Python and the Python of Debian 12 and Ubuntu 23.04 or later refuse `pip install` outside a virtual environment (PEP 668). The check then prints commands for `~/.cenk-overtime/venv`: run the plugin's Python scripts with that folder's `bin/python`.
- `apt` needs `sudo`: the person types their password in their own terminal; never ask for it.

## Packages

- PyMuPDF 2.x also installs pymupdf-layout, pymupdf4llm and onnxruntime; statsmodels 0.15 installs formulaic (seen: Python 3.14, Nov 2026; the eight packages came to 183 MB of downloads).
- Playwright needs its own Chromium: `python -m playwright install chromium` downloads it from Microsoft's servers.
