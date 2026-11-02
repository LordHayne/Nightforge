"""scripts/import-game-test.py copies a game test's report into docs/spieletest only when it names
neither the home folder nor the account, and never over an earlier run of the same day."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("import_game_test", ROOT / "scripts/import-game-test.py")
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)

HOME = "/Users/jdoe"
USER = "jdoe"


def run_folder(base, name="2026-11-03-0112", text="Overwatch hängt", finished=True, version=1):
    run = base / "GameTests" / name
    run.mkdir(parents=True)
    report = {"formatVersion": version, "games": [{"game": "Overwatch", "notes": [text]}]}
    if finished:
        report["finished"] = "2026-11-03T03:40:00Z"
    (run / "report.json").write_text(json.dumps(report))
    (run / "report.md").write_text(f"# Spieletest vom 3.11.2026\n\n{text}\n")
    (run / "steam.2357570.log").write_text(f"{HOME}/Library/wine.log")  # stays behind
    return run


class ImportGameTestTests(unittest.TestCase):
    def test_copies_report_and_summary_under_the_runs_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            run = run_folder(base)
            docs = base / "docs/spieletest"
            stem = importer.take(run, docs, HOME, USER)
            self.assertEqual(stem, docs / "2026-11-03")
            self.assertEqual(sorted(p.name for p in docs.iterdir()), ["2026-11-03.json", "2026-11-03.md"])

    def test_a_second_run_that_day_gets_its_own_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            docs = base / "docs/spieletest"
            importer.take(run_folder(base), docs, HOME, USER)
            stem = importer.take(run_folder(base, "2026-11-03-2210"), docs, HOME, USER)
            self.assertEqual(stem.name, "2026-11-03-2")

    def test_refuses_a_report_with_the_home_folder_or_account(self):
        for text in (f"log in {HOME}/Desktop", "C:\\\\users\\\\jdoe\\\\AppData", "Z:/Users/JDOE/x"):
            with tempfile.TemporaryDirectory() as tmp:
                base = pathlib.Path(tmp)
                docs = base / "docs/spieletest"
                with self.assertRaises(SystemExit):
                    importer.take(run_folder(base, text=text), docs, HOME, USER)
                self.assertFalse(docs.exists(), text)

    def test_a_name_like_the_account_is_no_leak(self):
        self.assertFalse(importer.leaks("users/jdoey · Thomas Was Alone · ~/Desktop", HOME, USER))

    def test_refuses_another_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            with self.assertRaises(SystemExit):
                importer.take(run_folder(base, version=2), base / "docs", HOME, USER)

    def test_newest_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            run_folder(base, "2026-11-02-2300")
            newest = run_folder(base, "2026-11-03-0112")
            (base / "GameTests/2026-11-04-0000").mkdir()  # no report yet
            self.assertEqual(importer.newest(base / "GameTests"), newest)
            self.assertIsNone(importer.newest(base / "nothing"))


if __name__ == "__main__":
    unittest.main()
