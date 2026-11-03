"""Every shell script of the repository a workflow runs as a command is executable in git.

enginefix.yml called scripts/build-enginefix.sh directly while it was committed as 100644: its one run
stopped at "Permission denied" and the package was never built (2.11.2026). A script that is sourced
(". scripts/signing-lib.sh"), handed to bash, copied or only named in a text doesn't need the bit.
python3 -m unittest tests/test_workflow_scripts.py
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"

# Quoted text is no command (echo "…, then scripts/build-enginefix.sh …"); an assignment keeps its name.
QUOTED = re.compile(r""""(?:[^"\\]|\\.)*"|'[^']*'""")
# Where a command begins on a line of a run block: after these, the next word is the program.
SEPARATORS = re.compile(r"&&|\|\||;|\||\$\(|(?:^|(?<=\s))(?:then|do|else|if|while|until|!)(?=\s)")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+")
SCRIPT = re.compile(r"^((?:\./)?[A-Za-z0-9_./-]+\.sh)(?=\s|$|\))")


def called_scripts(line: str) -> list[str]:
    """The .sh paths a line of a workflow runs as commands, as written."""
    text = line.strip()
    if text.startswith("#"):
        return []
    text = QUOTED.sub("Q", re.sub(r"^-?\s*run:\s*", "", text))
    found = []
    for segment in SEPARATORS.split(text):
        segment = segment.strip()
        while (assignment := ASSIGNMENT.match(segment)):  # JOBS="…" scripts/x.sh
            segment = segment[assignment.end():]
        if (match := SCRIPT.match(segment)):
            found.append(match.group(1))
    return found


def in_repository(path: str) -> str | None:
    """The repository file a path in a workflow names: as it stands, or below a checkout folder
    ("nightforge/scripts/build-enginefix.sh", checked out with `path: nightforge`)."""
    parts = pathlib.PurePosixPath(path.removeprefix("./")).parts
    for start in range(len(parts)):
        relative = pathlib.PurePosixPath(*parts[start:])
        if (ROOT / relative).is_file():
            return str(relative)
    return None


def is_executable(relative: str) -> bool:
    """As git has it (what a checkout gives the runner); the file's own mode when git has none."""
    listed = subprocess.run(["git", "ls-files", "-s", "--", relative], cwd=ROOT, capture_output=True, text=True)
    if listed.returncode == 0 and listed.stdout.strip():
        return listed.stdout.split()[0] == "100755"
    return os.access(ROOT / relative, os.X_OK)


class WorkflowScripts(unittest.TestCase):
    def test_lines(self):
        self.assertEqual(called_scripts("        run: scripts/run-tests.sh"), ["scripts/run-tests.sh"])
        self.assertEqual(called_scripts('JOBS="$(sysctl -n hw.ncpu)" scripts/build-kosmickrisp.sh "$A" "$B"'),
                         ["scripts/build-kosmickrisp.sh"])
        self.assertEqual(called_scripts('nightforge/scripts/build-enginefix.sh winecx work "$originals"'),
                         ["nightforge/scripts/build-enginefix.sh"])
        self.assertEqual(called_scripts("set -e && ./build.sh"), ["./build.sh"])
        self.assertEqual(called_scripts("out=$(scripts/check-signatures.sh)"), ["scripts/check-signatures.sh"])
        self.assertEqual(called_scripts("if ! scripts/check-signatures.sh pull-request; then exit 1; fi"),
                         ["scripts/check-signatures.sh"])
        for line in ['. scripts/signing-lib.sh', 'bash scripts/x.sh', 'cp nightforge/scripts/build-enginefix.sh "$s/"',
                     'echo "Then, on the maintainer\'s Mac: \\`scripts/sign-lists.sh $branch\\`"', '# scripts/build-enginefix.sh does',
                     '      - "scripts/build-kosmickrisp.sh"', 'curl -fsSL https://x/main/scripts/install.sh | bash',
                     '"To rebuild: unpack it, then scripts/build-enginefix.sh <that folder> <work folder>" \\']:
            self.assertEqual(called_scripts(line), [], line)

    def test_every_called_script_is_executable(self):
        called = {}
        for workflow in sorted(WORKFLOWS.glob("*.yml")):
            for number, line in enumerate(workflow.read_text(encoding="utf-8").splitlines(), 1):
                for path in called_scripts(line):
                    if (relative := in_repository(path)):
                        called.setdefault(relative, f"{workflow.name}:{number}")
        self.assertIn("scripts/run-tests.sh", called, "the workflows' commands are found at all")
        missing = {path: where for path, where in called.items() if not is_executable(path)}
        self.assertEqual(missing, {}, "run as a command, but not executable in git (git update-index --chmod=+x …)")


if __name__ == "__main__":
    unittest.main()
