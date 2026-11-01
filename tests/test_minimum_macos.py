"""The macOS Nightforge needs is said in one place per file, and they agree: the app's Info.plist
(macOS then won't open it on an older one), the install line, and the release text."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class MinimumMacOSTests(unittest.TestCase):
    def test_every_place_names_the_same_macos(self):
        minimum = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["LSMinimumSystemVersion"]
        major = minimum.split(".")[0]
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertRegex(install, rf'\[ "\$major" -ge {major} \]')
        self.assertIn(f"Nightforge needs macOS {major} ", install)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn(f"(macOS {major} ", release)

    def test_no_older_macos_is_still_named_as_the_minimum(self):
        for path in ("scripts/install.sh", ".github/workflows/release.yml", "Resources/Info.plist"):
            self.assertIsNone(re.search(r"macOS 1[0-5]\b(?! or older)", (ROOT / path).read_text()), path)


if __name__ == "__main__":
    unittest.main()
