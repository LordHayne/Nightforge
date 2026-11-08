#!/usr/bin/python3 -I
"""Which test series a change touches: a quick check while working, never instead of the full run before a merge.

    scripts/testbuild/affected.py [base]    one tests/…Test per line; base is origin/main unless given

Compares this checkout, uncommitted work included, with where it left base. A series counts when its own folder changed, when
a tests/Shared file it uses changed, or when it names the changed app file or something that file declares. Series that read the
app's folder as text always count for an app change. It's a good guess, not a proof: a series that only reaches a changed file
through another one is missed, and that's what the full run is for. Anything but app, test and documentation files means every series.
"""
import glob
import os
import re
import subprocess
import sys

APP = "Sources/Nightforge/"
NOT_CODE = ("docs/", "site/")
DECLARED = re.compile(
    r"^(?:@\w+(?:\([^)\n]*\))?\s+)*((?:(?:public|internal|fileprivate|private|final|nonisolated|indirect|open)\s+)*)"
    r"(?:struct|class|enum|protocol|actor|typealias|extension|func|let|var)\s+([A-Za-z_]\w*)", re.MULTILINE)
# How a series names the whole folder rather than one file in it.
READS_FOLDER = re.compile(r'Sources/Nightforge(?:/\*|/\\\(|/?["\')])')
TEXT = ("*.swift", "*.py", "*.sh")


def git(*words):
    return subprocess.run(["git", *words], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout


def changed(base):
    start = git("merge-base", "HEAD", base).strip()
    names = git("diff", "--name-only", start).splitlines() + git("ls-files", "--others", "--exclude-standard").splitlines()
    return sorted(set(names))


def read(path):
    with open(path, errors="replace") as handle:
        return handle.read()


def series_text(folder):
    parts = [read(path) for pattern in TEXT for path in glob.glob(os.path.join(folder, pattern))]
    return "\n".join(line for part in parts for line in part.splitlines() if "SOURCES=" not in line)


def declared_names(source):
    return {name for modifiers, name in DECLARED.findall(source) if "private" not in modifiers}


def mentions(names):
    return re.compile(r"\b(?:" + "|".join(sorted(map(re.escape, names))) + r")\b") if names else None


def pick(paths):
    """The series these changes touch, in order, or None for all of them."""
    every = sorted(glob.glob("tests/*Test"))
    texts = {folder: series_text(folder) for folder in every}
    chosen = set()
    for path in paths:
        if path.endswith(".md") or path.startswith(NOT_CODE):
            continue
        if path.startswith("tests/"):
            parts = path.split("/")
            if len(parts) > 2 and parts[1].endswith("Test"):
                if os.path.isdir(os.path.join("tests", parts[1])):
                    chosen.add(os.path.join("tests", parts[1]))
            elif len(parts) > 2 and parts[1] == "Shared":
                chosen.update(folder for folder, text in texts.items() if parts[2] in text)
            continue
        if not path.startswith(APP) or not path.endswith(".swift"):
            print(f"{path} isn't app, test or documentation: every series", file=sys.stderr)
            return None
        stem = os.path.basename(path)[:-len(".swift")]
        own = {stem} | (declared_names(read(path)) if os.path.isfile(path) else set())
        word = mentions(own)
        chosen.update(folder for folder, text in texts.items()
                      if f"{stem}.swift" in text or READS_FOLDER.search(text) or word.search(text))
    return sorted(chosen)


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    try:
        paths = changed(base)
    except subprocess.CalledProcessError:
        print(f"Can't compare with {base}: every series", file=sys.stderr)
        paths = None
    series = sorted(glob.glob("tests/*Test")) if paths is None else pick(paths)
    if series is None:
        series = sorted(glob.glob("tests/*Test"))
    print("\n".join(series))
    return 0


if __name__ == "__main__":
    sys.exit(main())
