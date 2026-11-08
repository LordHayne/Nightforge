"""The monthly watch list in docs/ENTWURF-ARM64.md: each row says where to look and what was there last, and none of
the things the plan hangs on has dropped off."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOPICS = ("Wine", "CrossOver", "FEX", "DXMT", "D3DMetal", "Altspiele")


def rows():
    text = (ROOT / "docs/ENTWURF-ARM64.md").read_text()
    section = re.search(r"^## 8\. Beobachtungsliste\n(.*?)^## ", text, re.M | re.S).group(1)
    lines = [line for line in section.splitlines() if line.startswith("|")]
    return [[cell.strip() for cell in line.strip("|").split("|")] for line in lines[2:]]


class WatchListTests(unittest.TestCase):
    def test_each_row_is_complete(self):
        self.assertTrue(rows())
        for row in rows():
            self.assertEqual(len(row), 4, row)
            self.assertTrue(row[1].startswith("https://"), row)
            self.assertTrue(all(row), row)

    def test_every_topic_is_watched(self):
        names = " ".join(row[0] for row in rows())
        for topic in TOPICS:
            self.assertIn(topic, names)


if __name__ == "__main__":
    unittest.main()
