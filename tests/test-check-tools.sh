#!/bin/sh
# Tests check-tools.py with stub programs and stub Python packages. Not part of the skill.
#
#   sh tests/test-check-tools.sh [SKILL_DIR]
#
# SKILL_DIR defaults to ../cenk-overtime/skills/start. The stubs go to a new
# folder in the system temp folder, deleted when every check passes. The real
# programs and packages of this computer stay out of sight: PATH, the install
# folders and Python's site-packages all point at the stubs.
set -eu

T=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(cd "${1:-$T/../cenk-overtime/skills/start}/scripts" && pwd)/check-tools.py
W=$(mktemp -d "${TMPDIR:-/tmp}/test-check-tools.XXXXXX")

PY=''
for p in python3 python py; do
	# Windows has a python3 stub that only opens the Store: try each one.
	if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys' >/dev/null 2>&1; then
		PY=$(command -v "$p")
		break
	fi
done
[ -n "$PY" ] || { echo 'no Python 3 found' >&2; exit 1; }

case $(uname -s) in
	MINGW* | MSYS* | CYGWIN*) WIN=1 ;;
	*) WIN=0 ;;
esac
# Native Windows programs need Windows paths in variables and arguments.
native() { if [ "$WIN" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
native_list() { if [ "$WIN" = 1 ]; then cygpath -wp "$1"; else printf '%s' "$1"; fi; }

# stub DIR NAME FIRST_LINE: a program that prints FIRST_LINE; tesseract also lists languages.
stub() {
	mkdir -p "$1"
	if [ "$WIN" = 1 ]; then
		{
			echo '@echo off'
			if [ "$2" = tesseract ]; then
				echo 'if "%~1"=="--list-langs" goto langs'
				echo "echo $3"
				echo 'goto :eof'
				echo ':langs'
				echo "echo List of available languages in \"$(native "$W/tessdata")\" 2:"
				for l in $LANGS; do echo "echo $l"; done
			else
				echo "echo $3"
			fi
		} >"$1/$2.cmd"
	else
		{
			echo '#!/bin/sh'
			if [ "$2" = tesseract ]; then
				echo "if [ \"\${1:-}\" = --list-langs ]; then echo 'List of available languages in \"$W/tessdata\" 2:'; for l in $LANGS; do echo \"\$l\"; done; exit 0; fi"
			fi
			echo "echo '$3'"
		} >"$1/$2"
		chmod +x "$1/$2"
	fi
}

# module NAME DIST: an importable stub package with version 9.9.
module() {
	mkdir -p "$W/py/$1" "$W/py/$2-9.9.dist-info"
	: >"$W/py/$1/__init__.py"
	printf 'Metadata-Version: 2.1\nName: %s\nVersion: 9.9\n' "$2" >"$W/py/$2-9.9.dist-info/METADATA"
}

# run [ARGS]: the script under test in a world of stubs; JSON goes to $W/out.json.
run() {
	set +e
	env PATH="$(native_list "$W/bin:$W/pf/Git/cmd")" \
		LOCALAPPDATA="$(native "$W/local")" ProgramFiles="$(native "$W/pf")" \
		CENK_OVERTIME_TOOL_DIRS="$(native "$W/extra")" PYTHONPATH="$(native "$W/py")" \
		PLAYWRIGHT_BROWSERS_PATH="$(native "$W/browsers")" \
		"$PY" -S "$SCRIPT" "$@" >"$W/out.txt" 2>"$W/err.txt"
	code=$?
	set -e
}

# j EXPR: a Python expression on the last JSON result r.
j() {
	"$PY" -c 'import json, sys
sys.stdout.reconfigure(newline="\n")
r = json.load(open(sys.argv[1], encoding="utf-8"))
item = {i["name"]: i for i in r["items"]}
print(eval(sys.argv[2]))' "$W/out.txt" "$1"
}

fails=0
check() {
	if [ "$2" = "$3" ]; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
		fails=$((fails + 1))
	fi
}

echo '--- some tools missing'
LANGS='eng osd'
stub "$W/bin" ffmpeg 'ffmpeg version 9.9.1-stub'
stub "$W/bin" tesseract 'tesseract v5.9.9'
stub "$W/extra" sqlite3 '3.99.0 2026-01-01'
stub "$W/pf/Git/cmd" git 'git version 2.99.0'
stub "$W/pf/Git/bin" bash 'GNU bash, version 5.9.9(1)-release'
# The WSL launcher that Windows has on PATH as bash must not count as Git Bash.
stub "$W/bin" bash 'wsl bash'
module pymupdf pymupdf
module pandas pandas
module playwright playwright
mkdir -p "$W/tessdata" "$W/browsers"

run --os windows --ocr-lang tur,eng --json
check 'exit code with missing tools' 1 "$code"
check 'program on PATH' 'found|9.9.1|True' "$(j "'|'.join(str(item['ffmpeg'][k]) for k in ('status', 'version', 'on_path'))")"
check 'program in an install folder' 'found|3.99.0|False' "$(j "'|'.join(str(item['sqlite3'][k]) for k in ('status', 'version', 'on_path'))")"
check 'Git Bash, not the bash on PATH' "$(native "$W/pf/Git/bin")" "$(j "__import__('os').path.dirname(item['bash']['path'])")"
check 'missing program' missing "$(j "item['ffprobe']['status']")"
check 'poppler covered by PyMuPDF' 'covered by pymupdf' "$(j "item['pdfinfo']['status']")"
check 'module version' 'found|9.9' "$(j "item['pandas']['status'] + '|' + item['pandas']['version']")"
check 'missing module' missing "$(j "item['statsmodels']['status']")"
check 'ocr languages' 'tur' "$(j "','.join(r['ocr']['missing'])")"
check 'missing list' 'ffprobe,soffice,pdfplumber,openpyxl,python-docx,pillow,statsmodels,scipy,tzdata,chromium,ocr:tur' \
	"$(j "','.join(r['missing'])")"
check 'winget once per package' 'winget install --id Gyan.FFmpeg --exact --source winget;winget install --id TheDocumentFoundation.LibreOffice --exact --source winget' \
	"$(j "';'.join(c for c in r['install'] if c.startswith('winget'))")"
check 'tessdata download' "curl.exe -L -o \"$(native "$W/tessdata")$(if [ "$WIN" = 1 ]; then echo '\'; else echo /; fi)tur.traineddata\" https://github.com/tesseract-ocr/tessdata/raw/main/tur.traineddata" \
	"$(j "next(c for c in r['install'] if c.startswith('curl'))")"
check 'pip for the missing modules' 'pip install pdfplumber openpyxl python-docx pillow statsmodels scipy tzdata' \
	"$(j "next(c for c in r['install'] if ' -m pip ' in c).split(' -m ', 1)[1]")"
check 'chromium for playwright' 'playwright install chromium' \
	"$(j "next(c for c in r['install'] if 'playwright install' in c).split(' -m ', 1)[1]")"

run --os macos --ocr-lang tur,eng --json
check 'brew formulae' 'brew install ffmpeg' "$(j "next(c for c in r['install'] if c.startswith('brew install ') and '--cask' not in c)")"
check 'brew cask' 'brew install --cask libreoffice' "$(j "next(c for c in r['install'] if '--cask' in c)")"
check 'brew languages' 'brew install tesseract-lang' "$(j "next(c for c in r['install'] if 'tesseract-lang' in c)")"

run --os linux --ocr-lang tur,deu --json
check 'apt packages' 'sudo apt install ffmpeg libreoffice' "$(j "r['install'][0]")"
check 'apt languages' 'sudo apt install tesseract-ocr-tur tesseract-ocr-deu' "$(j "r['install'][1]")"

run --os linux --json
check 'default language eng' 'eng|' "$(j "','.join(r['ocr']['requested']) + '|' + ','.join(r['ocr']['missing'])")"
check 'tzdata only on Windows' False "$(j "'tzdata' in item")"

echo '--- text output'
run --os windows --ocr-lang tur
check 'text: install heading' 1 "$(grep -c '^Install commands for windows:' "$W/out.txt")"
check 'text: run as for a program off PATH' 1 "$(grep -c 'sqlite3 .*run as: ' "$W/out.txt")"
check 'text: ocr line' 1 "$(grep -c 'missing   ocr:tur' "$W/out.txt")"

echo '--- no PyMuPDF: poppler programs are missing'
rm -rf "$W/py/pymupdf" "$W/py/pymupdf-9.9.dist-info"
run --os linux --json
check 'pdftotext without PyMuPDF' missing "$(j "item['pdftotext']['status']")"
check 'apt adds poppler once' 'sudo apt install ffmpeg poppler-utils libreoffice' "$(j "r['install'][0]")"

echo '--- nothing missing'
LANGS='eng osd tur'
for p in ffprobe pdftotext pdfinfo pdftoppm soffice; do stub "$W/bin" "$p" "$p version 1.2.3"; done
stub "$W/bin" tesseract 'tesseract v5.9.9'
module pymupdf pymupdf
module pdfplumber pdfplumber
module openpyxl openpyxl
module docx python-docx
module PIL pillow
module statsmodels statsmodels
module scipy scipy
module tzdata tzdata
mkdir -p "$W/browsers/chromium-1234"
run --os windows --ocr-lang tur,eng --json
check 'exit code when complete' 0 "$code"
check 'nothing missing' '0|0' "$(j "str(len(r['missing'])) + '|' + str(len(r['install']))")"
run --os windows --ocr-lang tur,eng
check 'text: nothing is missing' 'Nothing is missing.' "$(tail -n 1 "$W/out.txt")"
check 'no errors printed' 0 "$(wc -c <"$W/err.txt" | tr -d ' ')"

echo
if [ "$fails" != 0 ]; then
	echo "$fails failed; the test files are in $W"
	exit 1
fi
rm -rf "$W"
echo 'all passed'
