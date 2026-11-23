"""Nothing in Nightforge waits for an AppKit animation to end. AppKit drives them by the screen's display link: with the
display asleep or the Mac locked they never end, and whatever came after never happened. On 23.11.2026 the curtain stood
unseen as an orphan from 11:35 to 12:08 and Nightforge's way back started over every 19 s (GameBackdrop.fade)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class NoAwaitedAnimationsTests(unittest.TestCase):
    def test_no_await_on_run_animation_group(self):
        found = []
        for source in sorted((ROOT / "Sources/Nightforge").glob("*.swift")):
            for number, line in enumerate(source.read_text().split("\n"), 1):
                if re.search(r"await\s+NSAnimationContext\.runAnimationGroup", line.split("//", 1)[0]):
                    found.append(f"{source.name}:{number}")
        self.assertEqual(found, [], "use GameBackdrop.fade: it goes on after its time")


if __name__ == "__main__":
    unittest.main()
