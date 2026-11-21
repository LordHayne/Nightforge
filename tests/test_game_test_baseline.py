"""The game tests kept as the baseline for a later engine without Rosetta (docs/spieletest): each says what it ran on,
holds at least one measured game, and gives away nobody's Mac."""
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("import_game_test", ROOT / "scripts/import-game-test.py")
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class BaselineTests(unittest.TestCase):
    def reports(self):
        files = sorted((ROOT / "docs/spieletest").glob("*.json"))
        self.assertTrue(files, "no baseline kept")
        return [(path, json.loads(path.read_text())) for path in files]

    def test_each_says_what_it_ran_on(self):
        for path, report in self.reports():
            self.assertTrue(report.get("engine"), path.name)
            self.assertIn("macOS", report.get("mac", ""), path.name)
            # Reports from before the field all ran under Rosetta.
            self.assertEqual(report.get("runsOn", "x86_64 under Rosetta"), "x86_64 under Rosetta", path.name)

    def test_each_has_a_measured_game(self):
        for path, report in self.reports():
            self.assertTrue(any(game.get("frames") for game in report["games"]), path.name)

    def test_none_gives_a_mac_away(self):
        for path in (ROOT / "docs/spieletest").iterdir():
            self.assertFalse(importer.leaks(path.read_text(), str(pathlib.Path.home()), pathlib.Path.home().name), path.name)


if __name__ == "__main__":
    unittest.main()
