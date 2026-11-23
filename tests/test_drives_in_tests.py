"""No test depends on what is mounted on the Mac it runs on: the drives a test sees are its own (ExternalDrive.source,
tests/Shared/TestDrives.swift). Before, whether the drive "Games" was plugged in – or a disk image another series had
mounted meanwhile – changed which ways DriveTakeoverTest and the model's moves took, and their coverage moved by 4–5 points
(23.11.2026). Run: python3 -m pytest tests/test_drives_in_tests.py"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEST_SOURCES = sorted((ROOT / "tests").glob("*/main.swift")) + sorted((ROOT / "tests" / "Shared").glob("*.swift"))
# What lists the drives plugged in, through Nightforge's own code.
LISTS_DRIVES = re.compile(r"ExternalDrive\.connected\(\)|DriveTakeover\.drives\(|\.moveTargets\(|\.driveChoices\(")


def code(text):
    """The text without its // comments."""
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


class DrivesInTestsTests(unittest.TestCase):
    def test_no_test_asks_macos_what_is_mounted(self):
        for path in TEST_SOURCES:
            self.assertNotIn("mountedVolumeURLs", code(path.read_text()), path.relative_to(ROOT))

    def test_a_test_that_lists_drives_brings_its_own(self):
        for path in TEST_SOURCES:
            text = code(path.read_text())
            if not LISTS_DRIVES.search(text):
                continue
            own = "TestDrives." in text or "ExternalDrive.source" in text or "ModelWorld.begin()" in text
            self.assertTrue(own, f"{path.relative_to(ROOT)} lists drives without bringing its own (TestDrives)")

    def test_the_model_world_starts_without_a_drive(self):
        text = (ROOT / "tests" / "Shared" / "ModelWorld.swift").read_text()
        begin = text[text.index("static func begin()"):]
        self.assertIn("TestDrives.none()", begin[:begin.index("\n    }\n")])

    def test_every_series_that_uses_the_helper_compiles_it(self):
        for run in sorted((ROOT / "tests").glob("*/run.sh")):
            main = run.parent / "main.swift"
            script = run.read_text()
            uses = (main.exists() and "TestDrives." in main.read_text()) or "ModelWorld.swift" in script
            if uses:
                self.assertIn("tests/Shared/TestDrives.swift", script, run.relative_to(ROOT))

    def test_nightforge_never_sets_the_source(self):
        for path in sorted((ROOT / "Sources" / "Nightforge").glob("*.swift")):
            self.assertNotRegex(code(path.read_text()), r"ExternalDrive\.source\s*=(?!=)", path.relative_to(ROOT))

    def test_the_source_decides_where_drives_are_listed(self):
        drives = code((ROOT / "Sources" / "Nightforge" / "ExternalDrives.swift").read_text())
        takeover = code((ROOT / "Sources" / "Nightforge" / "DriveTakeover.swift").read_text())
        connected = drives[drives.index("static func connected()"):]
        self.assertLess(connected.index("if let source"), connected.index("mountedVolumeURLs"))
        at = drives[drives.index("static func at(_ url: URL"):]
        self.assertLess(at.index("if let source"), at.index("statfs("))
        listed = takeover[takeover.index("static func drives(testHome"):]
        self.assertLess(listed.index("ExternalDrive.source != nil"), listed.index("mountedVolumeURLs"))


if __name__ == "__main__":
    unittest.main()
