#!/usr/bin/env python3
"""check-tools.py: the programs and Python packages an overtime case uses,
which of them this computer lacks, and the command that installs each one.

    python check-tools.py [--os windows|macos|linux] [--ocr-lang CODES] [--json]

--os       the system to print install commands for (default: this one)
--ocr-lang Tesseract language codes the evidence needs, such as tur,eng
           (default: eng)
--json     machine-readable output

Programs are looked for on PATH, then in the usual install folders of the
system, which a new install may not have added to this session's PATH yet.
CENK_OVERTIME_TOOL_DIRS (folders separated by the system's path separator)
replaces those install folders.

It only looks and prints: it installs nothing. Standard library only.
Exit code 0 when nothing is missing, 1 when something is.
"""

import argparse
import glob
import importlib.metadata
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import sysconfig

TESSDATA_URL = "https://github.com/tesseract-ocr/tessdata/raw/main/{lang}.traineddata"
VENV = "~/.cenk-overtime/venv"

# install: per OS, "winget:<id>", "brew:<formula>", "cask:<name>" or "apt:<package>".
# covered_by: a Python module that does the same work, so the program is not needed.
PROGRAMS = [
    {"name": "git", "stage": "git", "use": "git history", "args": ["--version"],
     "install": {"windows": "winget:Git.Git", "macos": "brew:git", "linux": "apt:git"}},
    {"name": "bash", "stage": "git", "use": "runs git-history.sh (Git Bash on Windows)", "args": ["--version"],
     "install": {"windows": "winget:Git.Git"}},
    {"name": "ffmpeg", "stage": "reading", "use": "frames and sound from screen recordings and videos", "args": ["-version"],
     "install": {"windows": "winget:Gyan.FFmpeg", "macos": "brew:ffmpeg", "linux": "apt:ffmpeg"}},
    {"name": "ffprobe", "stage": "reading", "use": "length and recording time of videos", "args": ["-version"],
     "install": {"windows": "winget:Gyan.FFmpeg", "macos": "brew:ffmpeg", "linux": "apt:ffmpeg"}},
    {"name": "tesseract", "stage": "reading", "use": "text from scans, screenshots and video frames", "args": ["--version"],
     "install": {"windows": "winget:UB-Mannheim.TesseractOCR", "macos": "brew:tesseract", "linux": "apt:tesseract-ocr"}},
    {"name": "pdftotext", "stage": "reading", "use": "PDF text", "args": ["-v"], "covered_by": "pymupdf",
     "install": {"macos": "brew:poppler", "linux": "apt:poppler-utils"}},
    {"name": "pdfinfo", "stage": "reading", "use": "PDF page counts and dates", "args": ["-v"], "covered_by": "pymupdf",
     "install": {"macos": "brew:poppler", "linux": "apt:poppler-utils"}},
    {"name": "pdftoppm", "stage": "reading", "use": "PDF pages as images", "args": ["-v"], "covered_by": "pymupdf",
     "install": {"macos": "brew:poppler", "linux": "apt:poppler-utils"}},
    {"name": "sqlite3", "stage": "database", "use": "master.sqlite from the shell", "args": ["--version"], "covered_by": "sqlite3",
     "install": {"windows": "winget:SQLite.SQLite", "macos": "brew:sqlite", "linux": "apt:sqlite3"}},
    # soffice is a GUI program on Windows and starts slowly: found is enough.
    {"name": "soffice", "stage": "package", "use": "recalculates the spreadsheet's formulas; opens old .doc and .xls", "args": None,
     "install": {"windows": "winget:TheDocumentFoundation.LibreOffice", "macos": "cask:libreoffice", "linux": "apt:libreoffice"}},
]

# import name, pip name, stage, use
MODULES = [
    ("pymupdf", "pymupdf", "reading", "PDF text, page images and page counts"),
    ("pdfplumber", "pdfplumber", "reading", "tables in PDFs"),
    ("openpyxl", "openpyxl", "reading", ".xlsx files; the package spreadsheet"),
    ("docx", "python-docx", "reading", ".docx files"),
    ("PIL", "pillow", "reading", "images and their dates"),
    ("pandas", "pandas", "analysis", "tables for the models"),
    ("statsmodels", "statsmodels", "analysis", "regression checks"),
    ("scipy", "scipy", "analysis", "correlations and exact tests"),
    ("playwright", "playwright", "package", "report HTML to PDF"),
]


def this_os():
    return {"Windows": "windows", "Darwin": "macos"}.get(platform.system(), "linux")


def extra_dirs(os_name):
    """Install folders that are often not on PATH, or not yet in this session's PATH."""
    if os.environ.get("CENK_OVERTIME_TOOL_DIRS"):
        return [d for d in os.environ["CENK_OVERTIME_TOOL_DIRS"].split(os.pathsep) if d]
    if os_name == "macos":
        return ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/LibreOffice.app/Contents/MacOS"]
    if os_name == "linux":
        return ["/usr/local/bin", "/usr/bin", "/snap/bin"]
    dirs = []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        dirs += [os.path.join(local, "Microsoft", "WinGet", "Links"), os.path.join(local, "Programs", "Tesseract-OCR")]
    for root in dict.fromkeys(filter(None, [os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")])):
        dirs += [os.path.join(root, "Tesseract-OCR"), os.path.join(root, "LibreOffice", "program"),
                 os.path.join(root, "Git", "mingw64", "bin")]
    return dirs


def git_bash():
    """Git Bash, not the WSL launcher that Windows puts on PATH as bash.exe."""
    roots = []
    git = shutil.which("git")
    if git:
        roots.append(os.path.dirname(os.path.dirname(git)))
    if os.environ.get("ProgramFiles"):
        roots.append(os.path.join(os.environ["ProgramFiles"], "Git"))
    for root in roots:
        for sub in ("bin", os.path.join("usr", "bin")):
            found = shutil.which("bash", path=os.path.join(root, sub))
            if found:
                return found
    return None


def locate(name, os_name):
    """(path, on_path) of a program, or (None, False)."""
    if name == "bash" and os_name == "windows":
        found = git_bash()
        return found, False
    found = shutil.which(name)
    if found:
        return found, True
    for folder in extra_dirs(os_name):
        found = shutil.which(name, path=folder)
        if found:
            return found, False
    return None, False


def first_line(cmd):
    try:
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=30, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return ""
    for line in (run.stdout + "\n" + run.stderr).splitlines():
        if line.strip():
            return line.strip()
    return ""


def version_of(text):
    match = re.search(r"\d+(?:\.\d+)+", text)
    return match.group(0) if match else ""


def module_found(name):
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def module_version(dist):
    try:
        return importlib.metadata.version(dist)
    except importlib.metadata.PackageNotFoundError:
        return ""


def check_programs(os_name):
    items = []
    for prog in PROGRAMS:
        path, on_path = locate(prog["name"], os_name)
        item = {"kind": "program", "name": prog["name"], "stage": prog["stage"], "use": prog["use"],
                "path": path, "on_path": on_path, "version": "", "status": "found" if path else "missing"}
        if path and prog["args"]:
            item["version"] = version_of(first_line([path] + prog["args"]))
        if not path and prog.get("covered_by") and module_found(prog["covered_by"]):
            item["status"] = "covered by " + prog["covered_by"]
        item["install"] = prog["install"].get(os_name)
        items.append(item)
    return items


def check_modules():
    items = []
    for mod, dist, stage, use in MODULES:
        found = module_found(mod)
        items.append({"kind": "module", "name": dist, "stage": stage, "use": use, "import": mod,
                      "version": module_version(dist) if found else "", "status": "found" if found else "missing"})
    return items


def browsers_dir(os_name):
    if os.environ.get("PLAYWRIGHT_BROWSERS_PATH"):
        return os.environ["PLAYWRIGHT_BROWSERS_PATH"]
    if os_name == "windows":
        return os.path.join(os.environ.get("LOCALAPPDATA", ""), "ms-playwright")
    if os_name == "macos":
        return os.path.expanduser("~/Library/Caches/ms-playwright")
    return os.path.expanduser("~/.cache/ms-playwright")


def check_chromium(os_name, modules):
    """Playwright needs its own Chromium download besides the Python package."""
    if not any(m["name"] == "playwright" and m["status"] == "found" for m in modules):
        return None
    found = glob.glob(os.path.join(browsers_dir(os_name), "chromium*"))
    return {"kind": "browser", "name": "chromium", "stage": "package", "use": "Playwright's browser",
            "version": "", "status": "found" if found else "missing"}


def check_ocr(langs, tesseract_path):
    """Language data present, from tesseract --list-langs."""
    result = {"requested": langs, "available": [], "missing": list(langs), "tessdata": None}
    if not tesseract_path:
        return result
    try:
        run = subprocess.run([tesseract_path, "--list-langs"], capture_output=True, text=True, timeout=30, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return result
    lines = (run.stdout + "\n" + run.stderr).splitlines()
    for line in lines:
        match = re.search(r'languages in "([^"]+)"', line)
        if match:
            result["tessdata"] = os.path.normpath(match.group(1))
    result["available"] = [l.strip() for l in lines if re.fullmatch(r"[A-Za-z0-9_]+", l.strip())]
    result["missing"] = [l for l in langs if l not in result["available"]]
    return result


def externally_managed():
    """PEP 668: Homebrew and Debian Pythons refuse pip installs outside a venv."""
    stdlib = sysconfig.get_path("stdlib")
    return bool(stdlib) and os.path.exists(os.path.join(stdlib, "EXTERNALLY-MANAGED"))


def quote(path):
    return '"' + path + '"' if " " in path else path


def system_commands(os_name, programs):
    wanted = [p["install"] for p in programs if p["status"] == "missing" and p["install"]]
    wanted = list(dict.fromkeys(wanted))
    if os_name == "windows":
        return ["winget install --id %s --exact --source winget" % w.split(":", 1)[1] for w in wanted]
    if os_name == "macos":
        formulae = [w.split(":", 1)[1] for w in wanted if w.startswith("brew:")]
        casks = [w.split(":", 1)[1] for w in wanted if w.startswith("cask:")]
        return (["brew install " + " ".join(formulae)] if formulae else []) + \
               (["brew install --cask " + " ".join(casks)] if casks else [])
    packages = [w.split(":", 1)[1] for w in wanted]
    return ["sudo apt install " + " ".join(packages)] if packages else []


def ocr_commands(os_name, ocr):
    missing = ocr["missing"]
    if not missing:
        return []
    if os_name == "macos":
        return ["brew install tesseract-lang"]
    if os_name == "linux":
        return ["sudo apt install " + " ".join("tesseract-ocr-" + l for l in missing)]
    folder = ocr["tessdata"] or os.path.join(os.environ.get("ProgramFiles", "C:\\Program Files"), "Tesseract-OCR", "tessdata")
    return ['curl.exe -L -o "%s" %s' % (os.path.join(folder, l + ".traineddata"), TESSDATA_URL.format(lang=l))
            for l in missing]


def python_commands(os_name, modules, chromium, managed):
    names = [m["name"] for m in modules if m["status"] == "missing"]
    python = quote(sys.executable)
    commands = []
    if managed and names:
        venv_python = VENV + ("/Scripts/python.exe" if os_name == "windows" else "/bin/python")
        commands.append("%s -m venv %s" % (python, VENV))
        python = venv_python
    if names:
        commands.append("%s -m pip install %s" % (python, " ".join(names)))
    if "playwright" in names or (chromium and chromium["status"] == "missing"):
        commands.append("%s -m playwright install chromium" % python)
    return commands


def report(args):
    os_name = args.os or this_os()
    programs = check_programs(os_name)
    modules = check_modules()
    chromium = check_chromium(os_name, modules)
    tesseract = next(p for p in programs if p["name"] == "tesseract")
    ocr = check_ocr(args.ocr_lang, tesseract["path"])
    managed = externally_managed()
    items = programs + modules + ([chromium] if chromium else [])
    commands = system_commands(os_name, programs) + ocr_commands(os_name, ocr) + \
        python_commands(os_name, modules, chromium, managed)
    missing = [i["name"] for i in items if i["status"] == "missing"] + ["ocr:" + l for l in ocr["missing"]]
    return {
        "os": os_name,
        "python": {"path": sys.executable, "version": platform.python_version(), "externally_managed": managed},
        "items": items,
        "ocr": ocr,
        "missing": missing,
        "install": commands,
        "venv": VENV if managed and any(m["status"] == "missing" for m in modules) else None,
    }


def print_text(result):
    py = result["python"]
    print("Tools for cenk-overtime on %s (Python %s, %s)" % (result["os"], py["version"], py["path"]))
    print()
    for item in result["items"]:
        where = ""
        if item.get("path") and not item.get("on_path"):
            where = "  run as: " + item["path"]
        print("  %-9s %-12s %-14s %-9s %s%s" % (item["status"].split(" ")[0], item["name"], item["version"],
                                              item["stage"], item["use"], where))
    ocr = result["ocr"]
    for lang in ocr["requested"]:
        status = "missing" if lang in ocr["missing"] else "found"
        print("  %-9s %-12s %-14s %-9s %s" % (status, "ocr:" + lang, "", "reading", "Tesseract language data"))
    print()
    if not result["missing"]:
        print("Nothing is missing.")
        return
    print("Missing: " + ", ".join(result["missing"]))
    print("Install commands for %s:" % result["os"])
    for command in result["install"]:
        print("  " + command)
    if result["venv"]:
        print("This Python is managed by the system (PEP 668): the packages go into %s;" % result["venv"])
        print("run the plugin's Python scripts with the Python in that folder.")


def main():
    parser = argparse.ArgumentParser(description="Which tools an overtime case needs and how to install the missing ones.")
    parser.add_argument("--os", choices=["windows", "macos", "linux"], help="system to print install commands for")
    parser.add_argument("--ocr-lang", default="eng", type=lambda s: [l for l in s.split(",") if l],
                        help="Tesseract language codes, such as tur,eng")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    result = report(args)
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print_text(result)
    return 1 if result["missing"] else 0


if __name__ == "__main__":
    sys.exit(main())
