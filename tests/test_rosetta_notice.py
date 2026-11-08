"""What Nightforge says on a macOS without Rosetta promises nothing about later, in either language."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROMISES = ("yet", "soon", "later", "will ", "future", "noch", "bald", "später", "wird ", "künftig", "update", "macos 28")


class RosettaNoticeTests(unittest.TestCase):
    def test_the_notice_promises_nothing(self):
        english = re.search(r'L10n\.t\("(Windows games can.t run on this version[^"]+)"\)',
                            (ROOT / "Sources/Nightforge/RosettaSupport.swift").read_text()).group(1)
        strings = (ROOT / "Sources/Nightforge/Strings.swift").read_text()
        german = re.search(re.escape(f'"{english}": "') + r'([^"]+)"', strings).group(1)
        for text in (english, german):
            for word in PROMISES:
                self.assertNotIn(word, text.lower(), text)


if __name__ == "__main__":
    unittest.main()
