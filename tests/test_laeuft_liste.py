"""scripts/laeuft-liste.py builds the list of games that run from Nightforge's own records only: a way the
evidence confirmed is "laeuft", a picture without that is "startet", what no record holds stays null and
"nicht gemessen" – and the same inputs give the same files, with nothing in them that names the player."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("laeuft_liste", ROOT / "scripts/laeuft-liste.py")
liste = importlib.util.module_from_spec(spec)
spec.loader.exec_module(liste)

MAC = "Apple M5 · macOS 27.0"


def started(game, way, at, known=False, **more):
    return dict({"at": at, "game": game, "event": "started", "way": way, "engine": "winecx@4.7.3", "mac": MAC, "known": known}, **more)


def event(game, name, way, at, **more):
    return dict({"at": at, "game": game, "event": name, "way": way}, **more)


def played(name, key, outcome="picture", way="dxmt", platform="windows", **more):
    store, _, store_id = key.partition(".")
    entry = {"game": name, "store": store, "storeID": store_id, "platform": platform, "outcome": outcome, "way": way,
             "ways": [{"way": way, "outcome": outcome}], "issues": []}
    entry.update(more)
    return entry


def report(at, games, version=1, nightforge="0.3.2", **more):
    return dict({"formatVersion": version, "started": at, "nightforge": nightforge, "mac": MAC, "playSeconds": 60,
                 "engine": ["winecx@4.7.3", "d3dmetal@apple-3.0", "graphics@11.18-dxmt0.80-17"], "games": games}, **more)


def entry(document, key, platform="windows"):
    return next(e for e in document["entries"] if e["key"] == key and e["platform"] == platform)


class EvidenceTests(unittest.TestCase):
    def test_a_first_start_that_worked_runs_with_its_date_mac_and_engine(self):
        document = liste.build([[started("steam.35140", "wined3d", "2026-11-14T12:08:12Z"),
                                 event("steam.35140", "worked", "wined3d", "2026-11-14T12:11:13Z")]], [],
                               {"steam.35140": "Batman: Arkham Asylum GOTY Edition"})
        batman = entry(document, "steam.35140")
        self.assertEqual((batman["level"], batman["way"], batman["mac"]), ("laeuft", "wined3d", MAC))
        self.assertEqual(batman["confirmed"], {"way": "wined3d", "at": "2026-11-14T12:11:13Z", "basis": "worked", "engine": "winecx@4.7.3",
                                               "nightforge": None, "starts": 1, "ways": 1, "failedSince": 0})
        self.assertEqual((batman["name"], batman["nameFrom"]), ("Batman: Arkham Asylum GOTY Edition", "names"))
        self.assertIsNone(batman["measured"])
        self.assertIsNone(batman["antiCheat"])  # no record says
        self.assertEqual(document["dataUntil"], "2026-11-14T12:11:13Z")

    def test_counts_the_starts_and_ways_before_it_worked(self):
        document = liste.build([[started("steam.287700", "d3dmetal", "2026-11-11T18:25:22Z"),
                                 event("steam.287700", "failed", "d3dmetal", "2026-11-11T18:26:00Z"),
                                 started("steam.287700", "d3dmetal", "2026-11-11T18:37:50Z"),
                                 started("steam.287700", "dxmt", "2026-11-11T19:23:41Z"),
                                 event("steam.287700", "worked", "dxmt", "2026-11-11T19:24:30Z")]], [])
        confirmed = entry(document, "steam.287700")["confirmed"]
        self.assertEqual((confirmed["way"], confirmed["starts"], confirmed["ways"]), ("dxmt", 3, 2))
        self.assertIn("bestätigt 11.11.2026, 3. Start, 2 Wege · winecx@4.7.3", liste.markdown(document))
        self.assertIn("`steam.287700`", liste.markdown(document))  # no name: its key, and said so
        self.assertIn("Ohne Namen", liste.markdown(document))

    def test_a_way_confirmed_before_the_record_says_so_and_counts_no_starts(self):
        document = liste.build([[started("steam.550", "wined3d", "2026-11-09T23:43:34Z", known=True)]], [])
        confirmed = entry(document, "steam.550")["confirmed"]
        self.assertEqual((confirmed["basis"], confirmed["starts"], confirmed["ways"]), ("known", None, None))
        self.assertIn("bestätigt vor dem 9.11.2026 (vor der Aufzeichnung)", liste.markdown(document))

    def test_a_confirmation_nightforge_took_back_no_longer_runs(self):
        entries = [started("epic.Curry", "dxmt -dx11", "2026-11-09T23:50:55Z", known=True),
                   started("epic.Curry", "dxmt -dx11", "2026-11-10T00:41:45Z")]
        gone = entry(liste.build([entries], []), "epic.Curry")
        self.assertEqual((gone["level"], gone["confirmed"]), ("kein-bild", None))
        self.assertEqual(gone["withdrawn"], {"way": "dxmt -dx11", "at": "2026-11-10T00:41:45Z", "confirmedAt": "2026-11-09T23:50:55Z"})
        # With a picture in a game test it "starts"; once it worked again, it runs again.
        tests = [report("2026-11-10T00:57:00Z", [played("ABZU", "epic.Curry", way="dxmt -dx11")])]
        self.assertEqual(entry(liste.build([entries], tests), "epic.Curry")["level"], "startet")
        self.assertIn("dxmt -dx11 war bestätigt, seit 10.11.2026 nicht mehr", liste.markdown(liste.build([entries], tests)))
        again = entries + [event("epic.Curry", "worked", "dxmt -dx11", "2026-11-12T10:00:00Z")]
        back = entry(liste.build([again], tests), "epic.Curry")
        self.assertEqual((back["level"], back["withdrawn"], back["confirmed"]["at"]), ("laeuft", None, "2026-11-09T23:50:55Z"))

    def test_failures_after_the_confirmation_are_said_and_a_profile_too(self):
        document = liste.build([[started("steam.1", "dxmt", "2026-11-10T10:00:00Z", profiled=True, kind={"engine": "unreal", "engineVersion": "4.26", "antiCheat": True}),
                                 event("steam.1", "worked", "dxmt", "2026-11-10T10:03:00Z"),
                                 started("steam.1", "dxmt", "2026-11-11T10:00:00Z", known=True),
                                 event("steam.1", "failed", "dxmt", "2026-11-11T10:00:20Z", reason="a proven way ended in its first seconds again")]], [])
        game = entry(document, "steam.1")
        self.assertEqual(game["level"], "laeuft")
        self.assertEqual(game["notes"], ["antiCheatOnlineUnproven", "profiled", "failedSince"])
        self.assertEqual(game["gameEngine"], {"engine": "unreal", "version": "4.26"})
        table = liste.markdown(document)
        self.assertIn("Anti-Cheat: nur der Start ist belegt, der Online-Teil nicht; mit Profil; danach 1 Fehlstart", table)

    def test_starts_without_a_picture_stay_out_of_the_list_proper(self):
        document = liste.build([[started("steam.3240220", "d3dmetal", "2026-11-09T20:50:16Z"),
                                 event("steam.3240220", "failed", "d3dmetal", "2026-11-09T20:50:40Z"),
                                 event("steam.3240220", "gaveUp", "d3dmetal", "2026-11-09T20:50:41Z")]], [])
        self.assertEqual(entry(document, "steam.3240220")["level"], "kein-bild")
        table = liste.markdown(document)
        self.assertIn("### Versucht, bisher ohne Bild (1)", table)
        self.assertIn("1 Start aufgezeichnet, kein Bild bestätigt, aufgegeben", table)
        self.assertNotIn("### Läuft", table)

    def test_a_start_that_ended_with_a_picture_starts(self):
        document = liste.build([[started("gog.7", "dxvk", "2026-11-12T10:00:00Z"),
                                 event("gog.7", "ended", "dxvk", "2026-11-12T10:01:00Z", picture=True, seconds=60)]], [])
        game = entry(document, "gog.7")
        self.assertEqual((game["level"], game["way"], game["seen"]), ("startet", "dxvk", {"at": "2026-11-12T10:01:00Z", "by": "evidence"}))
        self.assertIn("Bild beim Start 12.11.2026 (Evidenz)", liste.markdown(document))

    def test_an_outcome_belongs_to_the_mac_of_its_start(self):
        other = "Apple M2 · macOS 26.1"
        document = liste.build([[dict(started("steam.9", "dxmt", "2026-11-12T10:00:00Z"), mac=other),
                                 event("steam.9", "worked", "dxmt", "2026-11-12T10:03:00Z")],
                                [started("steam.9", "dxmt", "2026-11-13T10:00:00Z")]], [])
        by_mac = {e["mac"]: e["level"] for e in document["entries"]}
        self.assertEqual(by_mac, {other: "laeuft", MAC: "kein-bild"})
        self.assertEqual(liste.markdown(document).count("\n## Apple"), 2)

    def test_lines_that_are_no_entries_are_left_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = pathlib.Path(tmp) / "start-evidence.jsonl"
            file.write_text(json.dumps(started("steam.9", "dxmt", "2026-11-12T10:00:00Z")) + "\nnot json\n[1]\n{\"game\": \"x\"}\n\n")
            self.assertEqual(len(liste.read_evidence(file)), 1)


class GameTestTests(unittest.TestCase):
    def test_a_picture_without_a_confirmed_way_starts_and_brings_what_it_measured(self):
        frames = {"average": 54.8, "low": 42.3, "periods": 6}
        document = liste.build([], [report("2026-11-10T00:57:00Z", [
            played("ABZU", "epic.Curry", way="dxmt -dx11", secondsToPicture=11.7, frames=frames, load={"average": 2, "cores": 10, "low": True})])])
        abzu = entry(document, "epic.Curry")
        self.assertEqual((abzu["level"], abzu["name"], abzu["nameFrom"]), ("startet", "ABZU", "report"))
        m = abzu["measured"]
        self.assertEqual((m["nightforge"], m["playSeconds"], m["secondsToPicture"], m["loadLow"], m["reportFormat"]), ("0.3.2", 60, 11.7, True, 1))
        self.assertEqual(m["fps"], {"average": 54.8, "low": 42.3, "periods": 6, "seconds": None, "slowestFrame": None, "slowestTypical": None, "source": None})
        # A format 1 report measured neither a slowest frame, a size nor the limit: said, not guessed.
        self.assertEqual([m[name] for name in ("frameLimit", "window", "swapchain", "displayMode", "noFrames")], [None] * 5)
        row = next(line for line in liste.markdown(document).splitlines() if line.startswith("| ABZU"))
        self.assertEqual(row, "| ABZU | Epic Games | Windows | dxmt -dx11 | Bild im Spieletest 10.11.2026 | Bild in 1 von 1 | 12 s | nicht gemessen "
                              "| 55 / 42 | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | – |")

    def test_a_format_2_report_brings_the_slowest_frames_the_size_and_the_limit(self):
        frames = {"average": 59.3, "low": 56.7, "periods": 11, "seconds": 110, "slowestFrame": 310, "slowestTypical": 24, "source": "dxmt"}
        measure = {"window": "1512×982", "screen": "1512×982", "displayMode": "1512×982@120", "frameLimit": 60, "refreshRate": 120, "metalFX": True}
        document = liste.build([], [report("2026-11-15T20:00:00Z", [played("MGS V", "steam.287700", frames=frames, measure=measure)], version=2)])
        row = next(line for line in liste.markdown(document).splitlines() if line.startswith("| MGS V"))
        self.assertIn("| 60 FPS | 59 / 57 über 110 s | üblich 24 ms, schlimmster 310 ms | 1512×982@120 (Modus des Spiels) |", row)
        self.assertEqual(entry(document, "steam.287700")["measured"]["fps"]["source"], "dxmt")

    def test_ways_that_report_no_frames_say_which(self):
        games = [played("Control", "epic.Calluna", way="d3dmetal"), played("Mafia II", "gog.1", way="wined3d"),
                 played("Valheim", "steam.892970", way="mac", platform="mac"), played("OxyRail", "steam.3907790", way="dxvk"),
                 played("Sized", "steam.5", way="d3dmetal", measure={"window": "1512×982", "frameLimit": 0, "noFrames": "wayReportsNone"})]
        document = liste.build([], [report("2026-11-10T00:00:00Z", games)])
        table = liste.markdown(document)
        for text in ("nicht gemessen (D3DMetal meldet keine)", "nicht gemessen (WineD3D meldet keine)", "nicht gemessen (Mac-Fassung meldet keine)",
                     "nicht gemessen (keine im Log)", "| keins | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | Fenster 1512×982 Punkte |"):
            self.assertIn(text, table)
        self.assertEqual(entry(document, "epic.Calluna")["measured"]["noFrames"], "wayReportsNone")
        self.assertEqual(entry(document, "steam.3907790")["measured"]["noFrames"], "noneInLog")
        # A Mac version is its own entry, never confirmed, and its measurement names no engine.
        valheim = entry(document, "steam.892970", "mac")
        self.assertEqual((valheim["level"], valheim["confirmed"]), ("startet", None))
        self.assertIn("| 10.11.2026 · Nightforge 0.3.2 · 60 s |", next(line for line in table.splitlines() if line.startswith("| Valheim")))
        self.assertIn("d3dmetal@apple-3.0", next(line for line in table.splitlines() if line.startswith("| Control")))

    def test_the_newest_run_decides_and_the_runs_are_counted(self):
        tests = [report("2026-11-09T20:00:00Z", [played("Wukong", "steam.3132990", way="d3dmetal", secondsToPicture=87.1)]),
                 report("2026-11-10T20:00:00Z", [played("Wukong", "steam.3132990", outcome="hang", way="d3dmetal")]),
                 report("2026-11-11T20:00:00Z", [played("Wukong", "steam.3132990", outcome="needsPlayer", way="d3dmetal", skip="steamAsks")])]
        wukong = entry(liste.build([], tests), "steam.3132990")
        self.assertEqual((wukong["level"], wukong["gameTest"]["runs"], wukong["gameTest"]["pictures"]), ("kein-bild", 2, 1))
        self.assertIn("Spieletest 10.11.2026: hängt ohne Bild (Bild in 1 von 2 Läufen)", liste.markdown(liste.build([], tests)))
        # Confirmed by the evidence, it runs all the same – and brings the picture run's numbers.
        runs = liste.build([[started("steam.3132990", "d3dmetal", "2026-11-09T19:00:00Z", known=True)]], tests)
        self.assertEqual((entry(runs, "steam.3132990")["level"], entry(runs, "steam.3132990")["measured"]["secondsToPicture"]), ("laeuft", 87.1))

    def test_the_measurement_is_the_newest_picture_on_the_listed_way(self):
        tests = [report("2026-11-09T20:00:00Z", [played("Forest", "steam.242760", way="dxvk", secondsToPicture=17.2)]),
                 report("2026-11-10T20:00:00Z", [played("Forest", "steam.242760", way="dxmt", secondsToPicture=5.0,
                                                        load={"average": 9, "cores": 10, "low": False}, issues=["crashed"])])]
        on_dxvk = liste.build([[started("steam.242760", "dxvk", "2026-11-09T19:00:00Z", known=True)]], tests)
        self.assertEqual(entry(on_dxvk, "steam.242760")["measured"]["secondsToPicture"], 17.2)
        on_d3dmetal = liste.build([[started("steam.242760", "d3dmetal", "2026-11-09T19:00:00Z", known=True)]], tests)
        other = entry(on_d3dmetal, "steam.242760")
        self.assertEqual((other["measured"]["way"], other["notes"]), ("dxmt", ["measuredOnAnotherWay", "loadHigh", "endedByItself"]))
        self.assertIn("Messung auf dxmt; Last beim Messen hoch; endete im Spielfenster von selbst", liste.markdown(on_d3dmetal))

    def test_a_note_taken_for_a_way_in_old_reports_is_no_way(self):
        note = "it ended at a question of its own – the player's choice, no other way"
        game = played("Alan Wake", "epic.Heron", outcome="noWindow", way=note)
        game["ways"] = [{"way": "d3dmetal", "outcome": "noWindow"}, {"way": note, "outcome": "noWindow"}]
        wake = entry(liste.build([], [report("2026-11-11T18:25:00Z", [game])]), "epic.Heron")
        self.assertEqual((wake["way"], wake["gameTest"]["lastWays"]), ("d3dmetal", ["d3dmetal"]))

    def test_an_anti_cheat_game_is_listed_by_what_nightforge_says_and_nothing_else(self):
        blocked = played("Shooter", "steam.77", outcome="skipped", way=None, skip="antiCheat")
        blocked["ways"] = []
        other = played("Updater", "steam.78", outcome="skipped", way=None, skip="update")
        document = liste.build([], [report("2026-11-10T00:00:00Z", [blocked, other])])
        self.assertEqual([e["key"] for e in document["entries"]], ["steam.77"])  # skipped for an update: nothing known, no entry
        shooter = entry(document, "steam.77")
        self.assertEqual((shooter["level"], shooter["antiCheat"], shooter["measured"], shooter["way"]), ("anti-cheat", True, None, None))
        table = liste.markdown(document)
        self.assertIn("### Anti-Cheat (1)", table)
        self.assertIn("- Shooter (Steam)", table)
        self.assertNotIn("| Shooter", table)

    def test_reports_of_unknown_formats_and_copies_of_a_run_count_once_or_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            run = report("2026-11-10T00:00:00Z", [played("Control", "epic.Calluna", way="d3dmetal")])
            (base / "GameTests/2026-11-10-0100").mkdir(parents=True)
            (base / "GameTests/2026-11-10-0100/report.json").write_text(json.dumps(run))
            (base / "spieletest").mkdir()
            (base / "spieletest/2026-11-10.json").write_text(json.dumps(run))  # the copy in docs/spieletest
            (base / "spieletest/2026-11-12.json").write_text(json.dumps(dict(run, started="2026-11-12T00:00:00Z", formatVersion=3)))
            (base / "spieletest/notes.json").write_text("[1, 2]")
            reports = liste.read_reports([base / "GameTests", base / "spieletest", base / "missing"])
            self.assertEqual([r["started"] for r in reports], ["2026-11-10T00:00:00Z"])
            self.assertEqual(entry(liste.build([], reports), "epic.Calluna")["gameTest"]["runs"], 1)


class OutputTests(unittest.TestCase):
    def inputs(self):
        evidence = [started("steam.35140", "wined3d", "2026-11-14T12:08:12Z"), event("steam.35140", "worked", "wined3d", "2026-11-14T12:11:13Z"),
                    started("epic.Calluna", "d3dmetal", "2026-11-09T21:56:35Z", known=True)]
        tests = [report("2026-11-10T00:00:00Z", [played("Control", "epic.Calluna", way="d3dmetal", secondsToPicture=9.5)]),
                 report("2026-11-09T00:00:00Z", [played("Control | Ultimate", "epic.Calluna", way="d3dmetal"),
                                                 played("Valheim", "steam.892970", way="mac", platform="mac")])]
        return evidence, tests

    def test_the_same_inputs_give_the_same_files_in_any_order(self):
        evidence, tests = self.inputs()
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            (base / "evidence.jsonl").write_text("\n".join(json.dumps(e) for e in evidence) + "\n")
            for index, run in enumerate(tests):
                (base / f"run{index}").mkdir()
                (base / f"run{index}/report.json").write_text(json.dumps(run))
            (base / "namen.json").write_text(json.dumps({"steam.35140": "Batman", "epic.Calluna": "not this"}))
            common = ["--evidence", str(base / "evidence.jsonl"), "--names", str(base / "namen.json")]
            liste.main(common + ["--out", str(base / "a"), str(base / "run0"), str(base / "run1")])
            liste.main(common + ["--out", str(base / "b"), str(base / "run1/report.json"), str(base / "run0/report.json")])
            for name in ("laeuft.json", "LAEUFT.md"):
                self.assertEqual((base / "a" / name).read_bytes(), (base / "b" / name).read_bytes(), name)
            document = json.loads((base / "a/laeuft.json").read_text())
            self.assertEqual((document["formatVersion"], document["sources"]), (1, {"evidenceEntries": 3, "gameTestRuns": 2}))
            self.assertEqual([e["name"] for e in document["entries"]], ["Batman", "Control", "Valheim"])  # by level, then name
            self.assertEqual(entry(document, "epic.Calluna")["nameFrom"], "report")  # the newest report's name, before the names file
            table = (base / "a/LAEUFT.md").read_text()
            self.assertIn("Stand der Daten: 14.11.2026 (Tage in UTC). Quellen: 3 Einträge der Start-Evidenz, 2 Spieletest-Läufe.", table)
            self.assertIn("### Läuft (2)", table)
            self.assertIn("### Startet (1)", table)
            self.assertNotIn(str(base), table)

    def test_every_entry_says_where_and_when(self):
        evidence, tests = self.inputs()
        for item in liste.build([evidence], tests)["entries"]:
            self.assertTrue(item["mac"])
            if item["confirmed"]:
                self.assertTrue(item["confirmed"]["at"] and item["confirmed"]["engine"])
            if item["measured"]:
                self.assertTrue(item["measured"]["at"] and item["measured"]["nightforge"] and item["measured"]["engine"])

    def test_nothing_is_written_that_names_the_player(self):
        home, user = "/Users/jdoe", "jdoe"
        for name in ("Game in /Users/jdoe/Games", "C:\\users\\jdoe\\x", "/Volumes/Jane SSD/Game", "Z:\\Users\\someone"):
            document = liste.build([], [report("2026-11-10T00:00:00Z", [played(name, "steam.1")])])
            with tempfile.TemporaryDirectory() as tmp:
                with self.assertRaises(SystemExit):
                    liste.write(document, pathlib.Path(tmp) / "out", home, user)
                self.assertFalse((pathlib.Path(tmp) / "out").exists(), name)
        self.assertFalse(liste.leaks("Thomas Was Alone · users of jdoe's · Volumes", home, user))

    def test_no_records_no_entries(self):
        document = liste.build([], [])
        self.assertEqual((document["entries"], document["dataUntil"]), ([], None))
        self.assertIn("Noch nichts aufgezeichnet.", liste.markdown(document))

    def test_the_committed_list_is_what_the_script_writes_for_its_own_json(self):
        """docs/laeuft/LAEUFT.md belongs to docs/laeuft/laeuft.json: nobody edited one without the other."""
        data = ROOT / "docs/laeuft/laeuft.json"
        if not data.is_file():
            self.skipTest("no list committed")
        document = json.loads(data.read_text(encoding="utf-8"))
        self.assertEqual(document["formatVersion"], liste.FORMAT_VERSION)
        self.assertEqual((ROOT / "docs/laeuft/LAEUFT.md").read_text(encoding="utf-8"), liste.markdown(document))
        self.assertFalse(liste.leaks(data.read_text(encoding="utf-8"), "/Users/nobody", "nobody"))


if __name__ == "__main__":
    unittest.main()
