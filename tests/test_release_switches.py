"""The hidden switches for Nightforge's own tests don't reach a release: each lives in the #else of an
`#if NIGHTFORGE_RELEASE`, key and all, the release workflow looks for every one of them in the build, and
each key is long enough to be found there (Swift keeps text of up to 15 bytes in the code itself, where
`strings` doesn't see it). The finished build tracks nothing (the user, 15.11.2026)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = sorted((ROOT / "Sources/Nightforge").glob("*.swift"))
KEY = re.compile(r'static let \w+Key = "([^"]+)"')


def parts(text):
    """The lines of a source by where they stand: in a release build only, in every other build only, in both."""
    release, other, both = [], [], []
    target = both
    for line in text.splitlines():
        word = line.strip()
        if word.startswith("#if NIGHTFORGE_RELEASE"):
            target = release
        elif word.startswith("#else") and target is release:
            target = other
        elif word.startswith("#endif") and target is not both:
            target = both
        else:
            target.append(line)
    return release, other, both


def code(line):
    """A line without its comment."""
    return line.split("//", 1)[0]


class ReleaseSwitchTests(unittest.TestCase):
    def setUp(self):
        self.keys = {}
        for source in SOURCES:
            _, other, _ = parts(source.read_text())
            for line in other:
                for key in KEY.findall(code(line)):
                    self.keys[key] = source.name

    def test_the_six_switches_are_found(self):
        self.assertEqual(sorted(self.keys), ["gameTest.curtainPreview", "gameTest.measurePlay", "gameTest.missingRosetta", "gameTest.startPhases",
                                             "gameTest.testFinding", "testRootQuestion"])

    def test_the_workflow_looks_for_each_of_them(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        looked = re.search(r"for key in ([^;]+); do", workflow)
        self.assertIsNotNone(looked, "release.yml's step \"No test switches in a release\"")
        self.assertEqual(sorted(looked.group(1).split()), sorted(self.keys))
        self.assertIn("NIGHTFORGE_RELEASE=1 ./build.sh", workflow)

    def test_each_key_is_text_in_an_optimized_build(self):
        for key in self.keys:
            self.assertGreater(len(key.encode()), 15, key)

    def test_no_key_stands_where_a_release_is_built_from(self):
        for source in SOURCES:
            release, _, both = parts(source.read_text())
            for line in release + both:
                for key in self.keys:
                    self.assertNotIn(f'"{key}"', code(line), f"{source.name}: {line.strip()}")

    def test_a_release_answers_no(self):
        """What stands in for a switch in a release reads no settings at all."""
        for source in SOURCES:
            release, _, _ = parts(source.read_text())
            for line in release:
                self.assertNotRegex(code(line), r"defaults\.|UserDefaults\.standard", f"{source.name}: {line.strip()}")


if __name__ == "__main__":
    unittest.main()
