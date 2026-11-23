"""scripts/release-check.sh: the release notes' rules, which decide what release.yml publishes word for word, and that the
switch check reads the same keys as release.yml. Run: python3 -m pytest tests/test_release_check.py"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "release-check.sh"

GOOD = "## Deutsch\n\nNightforge 0.3.5 …\n\n---\n\n## English\n\nNightforge 0.3.5 …\n"


class ReleaseCheckTests(unittest.TestCase):
    def notes(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(text)
        self.addCleanup(pathlib.Path(handle.name).unlink)
        result = subprocess.run(["/bin/bash", str(SCRIPT), "--notes", handle.name], capture_output=True, text=True)
        return result.returncode, result.stdout

    def test_clean_notes_pass(self):
        code, out = self.notes(GOOD)
        self.assertEqual(code, 0, out)
        self.assertNotIn("✗", out)

    def test_an_open_place_stops_it(self):
        code, out = self.notes(GOOD.replace("…\n\n---", "… [offen: live]\n\n---").replace("0.3.5 …\n", "0.3.5 … [offen: x]\n", 1))
        self.assertEqual(code, 1)
        self.assertIn("✗ notes: 2 places still [offen]", out)

    def test_a_working_comment_stops_it(self):
        code, out = self.notes("<!-- ENTWURF -->\n" + GOOD)
        self.assertEqual(code, 1)
        self.assertIn("working comment", out)

    def test_both_languages_are_needed(self):
        code, out = self.notes(GOOD.split("---")[0])
        self.assertEqual(code, 1)
        self.assertIn("a section is missing", out)

    def test_the_users_word_rule(self):
        code, out = self.notes(GOOD.replace("Nightforge 0.3.5 …", "Ganz ehrlich: Nightforge 0.3.5 …", 1))
        self.assertEqual(code, 1)

    def test_no_notes_at_all(self):
        result = subprocess.run(["/bin/bash", str(SCRIPT), "--notes", "/nonexistent/v9.9.9.md"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no release notes", result.stdout)

    def test_the_switch_check_reads_release_yml(self):
        # One list of test switches: release.yml's, which tests/test_release_switches.py holds against the code.
        text = SCRIPT.read_text()
        self.assertIn("for key in \\([^;]*\\); do", text)
        self.assertIn(".github/workflows/release.yml", text)
        self.assertNotIn("gameTest.startPhases", text)


if __name__ == "__main__":
    unittest.main()
