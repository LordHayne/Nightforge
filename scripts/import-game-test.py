#!/usr/bin/env python3
"""Takes a game test's report into the repository: docs/spieletest/<date>.json and <date>.md.

Nightforge writes each run (GameTestRun, `defaults write io.github.lordhayne.nightforge gameTest
-bool true`) to ~/Library/Application Support/Nightforge/GameTests/<yyyy-MM-dd-HHmm>/: report.json,
report.md, and per game the log since its start and a sample of a hang. Only the first two go into
the repository, and only when neither gives away whose Mac it ran on – no home folder, no account
name in a path, no drive or computer name. Nightforge leaves them out already; this checks again
before anything is copied.

Usage: import-game-test.py [run folder]   (default: the newest run)
"""

import argparse
import getpass
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNS = pathlib.Path.home() / "Library/Application Support/Nightforge/GameTests"
FORMAT_VERSION = 1


def machine_names():
    """The Mac's computer name, host name (with and without ".local") and Wine's NetBIOS name for it
    (upper case, 15 characters), each at least 3 characters – as GameLog.machineNames has them, read now."""
    names = []
    try:
        names.append(subprocess.run(["scutil", "--get", "ComputerName"], capture_output=True, text=True, timeout=5).stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    host = socket.gethostname()
    short = host.split(".")[0]
    names += [host, short, short[:15]]
    seen, result = set(), []
    for name in names:
        if len(name) >= 3 and name.lower() not in seen:
            seen.add(name.lower())
            result.append(name)
    return result


# What GameLog.redacted takes out and leaves a placeholder for ("<hidden>", "<email>", …): any of these
# that is still there in its plain form gives the player away. The same patterns as redacted's.
_EPIC = r"(?:AUTH_PASSWORD|AUTH_LOGIN|epicusername|epicuserid)"
_SECRET_WORDS = (r"access_token|refresh_token|id_token|session_id|sessionid|exchange_code|exchangecode|authorization_code|auth_code"
                 r"|client_secret|api_key|apikey|password|passwd|secret|token")
_SECRETS = [
    re.compile(r"(?i)-{1,2}" + _EPIC + r'\s*=\s*"?(?!<hidden>)[^\s"]+'),
    re.compile(r"(?i)(?<![A-Za-z0-9])(?:" + _SECRET_WORDS + r")[\"']?\s*[:=]\s*[\"']?(?!<hidden>)[^\"'\s,&}]+"),
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"),
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"),
    re.compile(r"\[U:1:\d+\]"),
    re.compile(r"\b7656119\d{10}\b"),
    re.compile(r"(?i)\buserdata(?:\\{1,2}|/)\d{3,}"),
    re.compile(r"(?i)\busers/\d{6,}"),
    re.compile(r"(?i)(?<![A-Za-z0-9])(?:galaxy_?)?user_?id[\"']?\s*[:=]\s*[\"']?\d{6,}"),
    re.compile(r"/(?:private/)?var/folders/(?!<id>)[^/\s\"']+/"),
]


def leaks(text, home, user, machine=None):
    """Whatever GameLog.redacted still takes out of `text`: the home folder, the account name in a path
    (/Users/<name>, C:\\users\\<name>) or as a word, an external drive's name (/Volumes/<name>,
    Z:\\Volumes\\<name>), the Mac's names as words (a Mac called "Mini" doesn't stop every import), the temp
    folder, e-mail addresses, tokens and sign-in arguments, Steam and GOG ids. Nightforge leaves "<drive>",
    "<computer>", "<user>", "<hidden>" … in their place."""
    if home and home in text:
        return True
    if re.search(r"(?<!System)(/|\\{1,2})Volumes(/|\\{1,2})(?!<drive>)", text):
        return True
    for name in machine_names() if machine is None else machine:
        if re.search(r"(?i)(?<![\w])" + re.escape(name) + r"(?![\w])", text):
            return True
    if any(pattern.search(text) for pattern in _SECRETS):
        return True
    if not user:
        return False
    if re.search(r"(?i)users(\\{1,2}|/)" + re.escape(user) + r"(?![\w])", text):
        return True
    return len(user) >= 3 and re.search(r"(?i)(?<![\w<])" + re.escape(user) + r"(?![\w>])", text) is not None


def newest(runs):
    folders = sorted(p for p in runs.iterdir() if (p / "report.json").is_file()) if runs.is_dir() else []
    return folders[-1] if folders else None


def target(docs, name):
    """docs/spieletest/<date>, with -2, -3 … when a run of that day is there already."""
    base = name[:10]
    stem, number = base, 1
    while (docs / f"{stem}.json").exists() or (docs / f"{stem}.md").exists():
        number += 1
        stem = f"{base}-{number}"
    return docs / stem


def take(run, docs, home, user):
    report = run / "report.json"
    summary = run / "report.md"
    if not report.is_file() or not summary.is_file():
        raise SystemExit(f"✗ {run.name}: report.json or report.md missing")
    data = json.loads(report.read_text())
    if data.get("formatVersion") != FORMAT_VERSION:
        raise SystemExit(f"✗ {run.name}: report format {data.get('formatVersion')}, this script knows {FORMAT_VERSION}")
    if not data.get("finished"):
        print(f"! {run.name}: the run hasn't finished (yet) – taking what it has")
    for path in (report, summary):
        if leaks(path.read_text(), home, user):
            raise SystemExit(f"✗ {path.name} names the home folder or the account: not copied")
    docs.mkdir(parents=True, exist_ok=True)
    stem = target(docs, run.name)
    shutil.copyfile(report, stem.with_suffix(".json"))
    shutil.copyfile(summary, stem.with_suffix(".md"))
    return stem


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("run", nargs="?", type=pathlib.Path, help="the run's folder (default: the newest)")
    parser.add_argument("--docs", type=pathlib.Path, default=ROOT / "docs/spieletest")
    args = parser.parse_args(argv)
    run = args.run or newest(RUNS)
    if run is None:
        raise SystemExit(f"✗ no game test in {RUNS}")
    stem = take(run, args.docs, str(pathlib.Path.home()), os.environ.get("USER") or getpass.getuser())
    print(f"✓ {stem.with_suffix('.md').relative_to(ROOT) if stem.is_relative_to(ROOT) else stem.with_suffix('.md')} and .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
