"""Swift test series leave nothing in the Mac's preferences. cfprefsd keeps every named domain in the real
~/Library/Preferences, whatever HOME says, and a domain removed there still leaves its file; a defer before the
test's exit() never runs. On 23.11.2026 that had piled up hundreds of files (GameResolutionTest.<UUID>,
first-start-rosetta-<UUID>, DockAutoHideTest.<UUID>, ConsoleModeTest.<UUID>, nightforge.test.unity-screen.<UUID>,
nightforge-test-launch-memory-<pid>, d3dmetal-test, drive-takeover-test).

The way out is tests/Shared/TestDefaults.swift: domains named by a path in the test's folder, which run.sh removes,
and `useWorkFolder()` for UserDefaults.standard. Read from the sources, so a new test is held to it too.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = sorted(p for p in (ROOT / "tests").glob("*/*.swift"))
SUITE = re.compile(r"UserDefaults\(suiteName:\s*")
CF_WRITE = re.compile(r"CFPreferencesSetAppValue\([^,]+,[^,]+,\s*([^)]+?)\s*(?:as CFString)?\)")


def code(text):
    return "\n".join(line.split("//", 1)[0] for line in text.split("\n"))


def argument(text, start):
    """The expression from `start` up to the parenthesis that closes the call it stands in."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            if depth == 0:
                return text[start:index].strip()
            depth -= 1
    return text[start:].strip()


def from_test_folder(name, text):
    """Whether `name` (an expression or a variable) is a domain in the test's folder."""
    if "TestDefaults." in name or name.endswith(".path"):
        return True
    if "." in name:  # a member of a tuple or a struct: (player: TestDefaults.domain("…"))
        member = name.rsplit(".", 1)[1]
        if re.search(r"\b" + re.escape(member) + r":\s*TestDefaults\.", text):
            return True
    assigned = re.findall(r"(?<![\w.])" + re.escape(name) + r"\s*(?::[^=\n]+)?=\s*([^\n]+)", text)
    return bool(assigned) and all("TestDefaults." in value or ".path" in value for value in assigned)


class TestsLeaveNothingTests(unittest.TestCase):
    def test_named_suites_live_in_the_test_folder(self):
        wrong = []
        for source in TESTS:
            if source.name == "TestDefaults.swift":
                continue
            text = code(source.read_text())
            for match in SUITE.finditer(text):
                name = argument(text, match.end())
                if from_test_folder(name, text):
                    continue
                # Registered values stay in memory; only allowed where nothing is set on that suite.
                variable = re.search(r"let (\w+) = UserDefaults\(suiteName:\s*" + re.escape(name), text)
                if variable and f"{variable.group(1)}.register(" in text and f"{variable.group(1)}.set(" not in text:
                    continue
                wrong.append(f"{source.parent.name}: UserDefaults(suiteName: {name})")
        self.assertEqual(wrong, [], "use TestDefaults.suite/domain, or register(defaults:) without set")

    def test_cfpreferences_writes_go_to_the_test_folder(self):
        wrong = []
        for source in TESTS:
            text = code(source.read_text())
            for match in CF_WRITE.finditer(text):
                if not from_test_folder(match.group(1), text):
                    wrong.append(f"{source.parent.name}: {match.group(0)}")
        self.assertEqual(wrong, [], "CFPreferences writes to a domain outside the test's folder")

    def test_run_scripts_compile_test_defaults_where_used(self):
        for source in TESTS:
            if source.name != "main.swift" or "TestDefaults." not in code(source.read_text()):
                continue
            run = source.parent / "run.sh"
            if run.exists():
                self.assertIn("tests/Shared/TestDefaults.swift", run.read_text(), f"{source.parent.name}/run.sh")

    def test_the_series_found_on_23_11_are_fixed(self):
        for name in ["D3DMetalTest", "DriveTakeoverTest"]:
            self.assertIn("TestDefaults.useWorkFolder()", (ROOT / "tests" / name / "main.swift").read_text(), name)
        unity = code((ROOT / "tests/MacUnityScreenTest/main.swift").read_text())
        self.assertNotIn("CFPreferencesSetAppValue", unity)


if __name__ == "__main__":
    unittest.main()
