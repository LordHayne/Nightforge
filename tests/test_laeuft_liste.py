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
                                               "nightforge": None, "built": None, "parts": None, "starts": 1, "ways": 1, "failedSince": 0})
        self.assertEqual((batman["name"], batman["nameFrom"]), ("Batman: Arkham Asylum GOTY Edition", "names"))
        self.assertIsNone(batman["measured"])
        self.assertIsNone(batman["antiCheat"])  # no record says
        self.assertEqual(document["dataUntil"], "2026-11-14T12:11:13Z")

    def test_a_start_that_names_its_build_and_its_game_brings_both(self):
        parts = ["winecx@4.7.3", "graphics@11.18-dxmt0.80-17"]
        said = started("steam.35140", "wined3d", "2026-11-14T16:08:12Z", name="Batman: Arkham Asylum GOTY Edition",
                       nightforge="0.3.2", built="2026-11-14T14:02:11Z", parts=parts)
        document = liste.build([[said, event("steam.35140", "worked", "wined3d", "2026-11-14T16:11:13Z")]], [], {"steam.35140": "Another name"})
        batman = entry(document, "steam.35140")
        self.assertEqual((batman["name"], batman["nameFrom"]), ("Batman: Arkham Asylum GOTY Edition", "evidence"))
        self.assertEqual((batman["confirmed"]["nightforge"], batman["confirmed"]["built"], batman["confirmed"]["parts"]),
                         ("0.3.2", "2026-11-14T14:02:11Z", parts))
        self.assertIn("bestätigt 14.11.2026, 1. Start · Nightforge 0.3.2 (gebaut 14.11.2026 14:02 UTC) · winecx@4.7.3", liste.markdown(document))
        self.assertNotIn("Ohne Namen", liste.markdown(document))
        # A report's name still comes first, and a line without these reads as before.
        named = liste.build([[said]], [report("2026-11-14T17:00:00Z", [played("Batman GOTY", "steam.35140", way="wined3d")])])
        self.assertEqual((entry(named, "steam.35140")["name"], entry(named, "steam.35140")["nameFrom"]), ("Batman GOTY", "report"))
        self.assertIsNone(liste.stated(started("steam.1", "dxmt", "2026-11-09T22:45:04Z")))
        self.assertIsNone(liste.stated(started("steam.1", "dxmt", "2026-11-09T22:45:04Z", nightforge="0.3.2")))  # no parts: not a build
        self.assertEqual(liste.stated(said), ("0.3.2", "2026-11-14T14:02:11Z", tuple(parts)))

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
        self.assertEqual(m["fps"], {"average": 54.8, "low": 42.3, "periods": 6, "seconds": None, "slowestFrame": None, "slowestTypical": None,
                                    "source": None, "onePercentLow": None, "gpuTime": None})
        # Without its limit on record the number is neither "holds 60" nor a free one, and not one for a public list.
        self.assertEqual((m["kind"], m["holds"], m["public"]), (None, None, False))
        self.assertEqual(m["notPublic"], ["limitUnknown", "sizeUnknown", "durationUnknown"])
        # A format 1 report measured neither a slowest frame, a size nor the limit: said, not guessed.
        self.assertEqual([m[name] for name in ("frameLimit", "window", "swapchain", "displayMode", "noFrames")], [None] * 5)
        row = next(line for line in liste.markdown(document).splitlines() if line.startswith("| ABZU"))
        self.assertEqual(row, "| ABZU | Epic Games | Windows | dxmt -dx11 | Bild im Spieletest 10.11.2026 | Bild in 1 von 1 | 12 s | nicht gemessen "
                              "| Ø 55, tiefste Periode 42 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen "
                              "| 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | Bild 10.11.2026 (Spieletest) "
                              "| FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |")

    def test_a_value_keeps_the_build_it_was_measured_on_when_a_newer_one_runs(self):
        """What the public list shows doesn't go with a new build: the value stands with its build, and what the
        current build has seen of the game is said beside it."""
        low = {"average": 2, "cores": 10, "low": True}
        good = played("MGS V", "steam.287700", frames={"average": 59.3, "low": 56.7, "periods": 12, "seconds": 190}, load=low,
                      measure={"window": "1512×982", "frameLimit": 60, "refreshRate": 120})
        first = report("2026-11-15T20:00:00Z", [good], version=2, built="2026-11-15T18:00:00Z", playSeconds=200)
        newer = "2026-11-17T09:00:00Z"

        def listed(*later):
            document = liste.build([], [first] + list(later))
            return document, entry(document, "steam.287700")

        # A newer build that ran another game only: the value stays, and the current build has seen nothing of this one.
        document, mgs = listed(report("2026-11-17T10:00:00Z", [played("ABZU", "epic.Curry")], version=2, built=newer))
        self.assertEqual((mgs["measured"]["fps"]["average"], mgs["measured"]["built"], mgs["measured"]["public"], mgs["onCurrentBuild"]),
                         (59.3, "2026-11-15T18:00:00Z", True, None))
        self.assertEqual((document["currentBuilds"][MAC]["built"], document["currentBuilds"][MAC]["since"]), (newer, "2026-11-17T10:00:00Z"))
        table = liste.markdown(document)
        self.assertIn("Aktueller Build: Nightforge 0.3.2 (gebaut 17.11.2026 09:00 UTC)", table)
        self.assertIn("15.11.2026 · Nightforge 0.3.2 (gebaut 15.11.2026 18:00 UTC) · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 200 s | noch nichts |", table)
        # A newer run with a picture and no frame rate, or one measured on battery, doesn't take the value's place.
        silent = played("MGS V", "steam.287700", load=low, measure={"frameLimit": 60, "noFrames": "noneInLog"})
        _, mgs = listed(report("2026-11-17T10:00:00Z", [silent], version=2, built=newer))
        self.assertEqual((mgs["measured"]["at"], mgs["measured"]["fps"]["average"]), ("2026-11-15T20:00:00Z", 59.3))
        self.assertEqual(mgs["onCurrentBuild"], {"at": "2026-11-17T10:00:00Z", "picture": True, "by": "gameTest"})
        battery = dict(good, frames={"average": 29.8, "low": 28.0, "periods": 12, "seconds": 190})
        _, mgs = listed(report("2026-11-17T10:00:00Z", [battery], version=2, built=newer, onBattery=True))
        self.assertEqual((mgs["measured"]["fps"]["average"], mgs["measured"]["built"]), (59.3, "2026-11-15T18:00:00Z"))
        # A newer value that can stand in public takes it, with its own build.
        better = dict(good, frames={"average": 60.0, "low": 58.9, "periods": 12, "seconds": 190})
        _, mgs = listed(report("2026-11-17T10:00:00Z", [better], version=2, built=newer))
        self.assertEqual((mgs["measured"]["fps"]["average"], mgs["measured"]["built"]), (60.0, newer))
        # No picture on the current build is said too – from a game test or from a start's own line.
        document, mgs = listed(report("2026-11-17T10:00:00Z", [played("MGS V", "steam.287700", outcome="noPicture")], version=2, built=newer))
        self.assertEqual(mgs["onCurrentBuild"], {"at": "2026-11-17T10:00:00Z", "picture": False, "by": "gameTest"})
        self.assertIn("| kein Bild 17.11.2026 (Spieletest) |", liste.markdown(document))
        parts = ["winecx@4.7.3", "d3dmetal@apple-3.0", "graphics@11.18-dxmt0.80-17"]
        begun = started("steam.287700", "dxmt", "2026-11-18T12:00:00Z", nightforge="0.3.2", built="2026-11-18T09:00:00Z", parts=parts)
        document = liste.build([[begun, event("steam.287700", "worked", "dxmt", "2026-11-18T12:03:10Z")]], [first])
        self.assertEqual(entry(document, "steam.287700")["onCurrentBuild"], {"at": "2026-11-18T12:00:00Z", "picture": True, "by": "evidence"})
        self.assertEqual(entry(document, "steam.287700")["measured"]["built"], "2026-11-15T18:00:00Z")

    def test_a_format_2_report_brings_the_slowest_frames_the_size_and_the_limit(self):
        frames = {"average": 59.3, "low": 56.7, "periods": 11, "seconds": 110, "slowestFrame": 310, "slowestTypical": 24, "source": "dxmt"}
        measure = {"window": "1512×982", "screen": "1512×982", "displayMode": "1512×982@120", "frameLimit": 60, "refreshRate": 120, "metalFX": True}
        low = {"average": 2, "cores": 10, "low": True}
        document = liste.build([], [report("2026-11-15T20:00:00Z", [played("MGS V", "steam.287700", frames=frames, measure=measure, load=low)],
                                           version=2, built="2026-11-15T18:00:00Z")])
        row = next(line for line in liste.markdown(document).splitlines() if line.startswith("| MGS V"))
        self.assertIn("| 60 FPS | hält das Limit: Ø 59, tiefste Periode 57, über 110 s | üblich 24 ms, schlimmster 310 ms | 1512×982@120 (Modus des Spiels) |", row)
        self.assertIn("Nightforge 0.3.2 (gebaut 15.11.2026 18:00 UTC)", row)
        self.assertTrue(row.endswith("| – |"))  # every condition on record: nothing against showing it
        m = entry(document, "steam.287700")["measured"]
        self.assertEqual((m["fps"]["source"], m["kind"], m["holds"], m["public"], m["notPublic"]), ("dxmt", "holdsLimit", True, True, []))

    def test_a_number_under_a_limit_is_not_a_free_number_and_a_throttled_one_is_not_public(self):
        low = {"average": 2, "cores": 10, "low": True}

        def one(frames, **measure):
            measure = dict({"window": "1512×982", "frameLimit": 60}, **measure)
            run = report("2026-11-15T20:00:00Z", [played("Game", "steam.1", frames=dict(frames, periods=12, seconds=120), measure=measure, load=low)], version=2)
            document = liste.build([], [run])
            return entry(document, "steam.1")["measured"], liste.markdown(document)

        m, table = one({"average": 47.0, "low": 12.0})
        self.assertEqual((m["kind"], m["holds"]), ("holdsLimit", False))
        self.assertIn("hält das Limit nicht: Ø 47, tiefste Periode 12, über 120 s", table)
        m, table = one({"average": 87.4, "low": 61.0, "onePercentLow": 55.5, "gpuTime": 9.9, "source": "metal-hud"}, frameLimit=0)
        self.assertEqual((m["kind"], m["holds"], m["public"], m["fps"]["gpuTime"]), ("free", None, True, 9.9))
        self.assertIn("| keins | frei: Ø 87, tiefste Periode 61, 1-%-Tief 56, über 120 s |", table)
        m, table = one({"average": 30.0, "low": 29.0}, frameLimit=30, throttled="battery")
        self.assertEqual((m["public"], m["notPublic"], m["throttled"]), (False, ["throttled"], "battery"))
        self.assertIn("FPS nicht für die öffentliche Liste: Limit gedrosselt", table)
        battery = report("2026-11-15T20:00:00Z", [played("Game", "steam.1", frames={"average": 59, "low": 57, "periods": 12, "seconds": 120},
                                                        measure={"window": "1512×982", "frameLimit": 60}, load={"average": 9, "cores": 10, "low": False})],
                         version=2, onBattery=True, lowPower=True)
        self.assertEqual(entry(liste.build([], [battery]), "steam.1")["measured"]["notPublic"], ["onBattery", "lowPower", "loadHigh"])

    def test_ways_that_report_no_frames_say_which(self):
        games = [played("Control", "epic.Calluna", way="d3dmetal"), played("Mafia II", "gog.1", way="wined3d"),
                 played("Valheim", "steam.892970", way="mac", platform="mac"), played("OxyRail", "steam.3907790", way="dxvk"),
                 played("Sized", "steam.5", way="d3dmetal", measure={"window": "1512×982", "frameLimit": 0, "noFrames": "wayReportsNone"})]
        document = liste.build([], [report("2026-11-10T00:00:00Z", games)])
        table = liste.markdown(document)
        for text in ("nicht gemessen (D3DMetal meldet keine)", "nicht gemessen (WineD3D meldet keine ohne Wines fps-Kanal)", "nicht gemessen (Mac-Fassung meldet keine)",
                     "nicht gemessen (keine im Log)", "| keins | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | Fenster 1512×982 Punkte |"):
            self.assertIn(text, table)
        self.assertEqual(entry(document, "epic.Calluna")["measured"]["noFrames"], "wayReportsNone")
        self.assertEqual(entry(document, "steam.3907790")["measured"]["noFrames"], "noneInLog")
        # A Mac version is its own entry, never confirmed, and its measurement names no engine.
        valheim = entry(document, "steam.892970", "mac")
        self.assertEqual((valheim["level"], valheim["confirmed"]), ("startet", None))
        self.assertIn("| 10.11.2026 · Nightforge 0.3.2 · 60 s |", next(line for line in table.splitlines() if line.startswith("| Valheim")))
        self.assertIn("d3dmetal@apple-3.0", next(line for line in table.splitlines() if line.startswith("| Control")))

    def test_with_the_huds_frame_log_only_opengl_and_mac_versions_report_none(self):
        def why(way, platform="windows", **more):
            runs = [report("2026-11-15T20:00:00Z", [played("X", "steam.1", way=way, platform=platform)], version=2, **more)]
            return entry(liste.build([], runs), "steam.1", platform)["measured"]["noFrames"]

        self.assertEqual((why("d3dmetal"), why("dxvk"), why("wined3d"), why("mac", "mac")), ("wayReportsNone", "noneInLog", "wayReportsNone", "wayReportsNone"))
        self.assertEqual((why("d3dmetal", frameLog=True), why("dxvk", frameLog=True), why("wined3d", frameLog=True), why("mac", "mac", frameLog=True)),
                         ("noneInLog", "noneInLog", "wayReportsNone", "wayReportsNone"))
        logged = report("2026-11-15T20:00:00Z", [played("X", "steam.1", way="d3dmetal", measure={"noFrames": "noneInLog"})], version=2, frameLog=True)
        document = liste.build([], [logged])
        self.assertTrue(entry(document, "steam.1")["measured"]["frameLog"])
        self.assertIn("nicht gemessen (keine im Log)", liste.markdown(document))

    def test_wines_own_direct3d_brings_a_rate_through_wines_fps_channel(self):
        low = {"average": 2, "cores": 10, "low": True}
        rate = {"average": 55.0, "low": 48.6, "periods": 2, "seconds": 24.0, "source": "wine-fps"}
        batman = played("Batman", "steam.35140", way="wined3d", frames=rate, load=low, check={"start": "ok", "fps": "ok"},
                        measure={"window": "1512×982", "frameLimit": 0, "refreshRate": 120, "metalFX": False})
        run = report("2026-11-15T20:00:00Z", [batman], version=2, built="2026-11-15T18:00:00Z", playSeconds=190, frameLog=True, wineFps=True)
        document = liste.build([], [run])
        m = entry(document, "steam.35140")["measured"]
        # A rate without a limit is a free number; what the channel doesn't give stays null and is said in words.
        self.assertEqual((m["fps"]["source"], m["kind"], m["public"], m["wineFps"]), ("wine-fps", "free", True, True))
        self.assertEqual((m["fps"]["onePercentLow"], m["fps"]["slowestFrame"], m["fps"]["slowestTypical"]), (None, None, None))
        row = next(line for line in liste.markdown(document).splitlines() if line.startswith("| Batman"))
        self.assertIn("| keins | frei: Ø 55, tiefste Periode 49 (Wines fps-Kanal), über 24 s | gibt Wines fps-Kanal nicht her |", row)
        # With the channel on and no line of the game's: the log held none. Without it, WineD3D reports none – a Mac version never does.
        def why(way, platform="windows", **more):
            runs = [report("2026-11-15T20:00:00Z", [played("X", "steam.1", way=way, platform=platform)], version=2, **more)]
            return entry(liste.build([], runs), "steam.1", platform)["measured"]["noFrames"]

        self.assertEqual((why("wined3d", wineFps=True), why("wined3d", frameLog=True), why("mac", "mac", wineFps=True), why("d3dmetal", wineFps=True)),
                         ("noneInLog", "wayReportsNone", "wayReportsNone", "wayReportsNone"))
        # On the checklist it's a frame rate like any other: with a clean start on the same build, done.
        stock = [{"key": "steam.35140", "platform": "windows", "name": "Batman", "sizeBytes": 8471095333, "location": "extern"}]
        game = liste.checklist(stock, [], [run])["games"][0]
        self.assertEqual((game["status"], game["fps"]["kind"], game["fps"]["average"]), ("fertig", "free", 55.0))
        self.assertIn("ja: frei gemessen, Ø 55, 15.11.2026, wined3d", liste.checklist_markdown(liste.checklist(stock, [], [run])))

    def test_a_picture_stays_one_and_a_run_without_it_is_said_beside_it(self):
        tests = [report("2026-11-09T20:00:00Z", [played("Wukong", "steam.3132990", way="d3dmetal", secondsToPicture=87.1)]),
                 report("2026-11-10T20:00:00Z", [played("Wukong", "steam.3132990", outcome="hang", way="d3dmetal")]),
                 report("2026-11-11T20:00:00Z", [played("Wukong", "steam.3132990", outcome="needsPlayer", way="d3dmetal", skip="steamAsks")])]
        wukong = entry(liste.build([], tests), "steam.3132990")
        self.assertEqual((wukong["level"], wukong["gameTest"]["runs"], wukong["gameTest"]["pictures"]), ("startet", 2, 1))
        self.assertEqual((wukong["seen"], wukong["noPictureSince"]), ({"at": "2026-11-09T20:00:00Z", "by": "gameTest"},
                                                                      {"at": "2026-11-10T20:00:00Z", "by": "gameTest", "count": 1}))
        self.assertEqual((wukong["measured"]["secondsToPicture"], wukong["onCurrentBuild"]), (87.1, {"at": "2026-11-10T20:00:00Z", "picture": False, "by": "gameTest"}))
        table = liste.markdown(liste.build([], tests))
        self.assertIn("Bild im Spieletest 9.11.2026 | Bild in 1 von 2 | 87 s |", table)
        self.assertIn("| kein Bild 10.11.2026 (Spieletest) | danach ein Start ohne Bild, zuletzt 10.11.2026 (Spieletest) |", table)
        # Never a picture: tried, and not on the list proper.
        never = liste.build([], tests[1:])
        self.assertEqual(entry(never, "steam.3132990")["level"], "kein-bild")
        self.assertIn("Spieletest 10.11.2026: hängt ohne Bild", liste.markdown(never))
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


def vdf(libraries):
    """A libraryfolders.vdf: [(path as Steam writes it, {app: size})]."""
    blocks = []
    for index, (path, apps) in enumerate(libraries):
        listed = "".join(f'\t\t\t"{app}"\t\t"{size}"\n' for app, size in apps.items())
        blocks.append(f'\t"{index}"\n\t{{\n\t\t"path"\t\t"{path}"\n\t\t"label"\t\t""\n\t\t"apps"\n\t\t{{\n{listed}\t\t}}\n\t}}\n')
    return '"libraryfolders"\n{\n' + "".join(blocks) + "}\n"


def manifest(folder, app, name, size):
    (folder / "steamapps").mkdir(parents=True, exist_ok=True)
    (folder / f"steamapps/appmanifest_{app}.acf").write_text(
        f'"AppState"\n{{\n\t"appid"\t\t"{app}"\n\t"name"\t\t"{name}"\n\t"StateFlags"\t\t"4"\n\t"SizeOnDisk"\t\t"{size}"\n}}\n')


def stores(base):
    """Nightforge's folder with a Windows Steam of two libraries, Epic with an add-on, GOG – and Steam for Mac."""
    support, drive, mac = base / "Nightforge", base / "drive/Nightforge Games", base / "Steam"
    steam = support / "Prefix/drive_c/Program Files (x86)/Steam"
    manifest(steam, "228980", "Steamworks Common Redistributables", 255505002)
    manifest(drive, "35140", "Batman: Arkham Asylum GOTY Edition", 8471095333)
    manifest(drive, "550", "Left 4 Dead 2", 0)  # its size only in the list
    windows = "Z:" + str(drive).replace("/", "\\\\")
    (steam / "steamapps/libraryfolders.vdf").write_text(vdf([
        ("C:\\\\Program Files (x86)\\\\Steam", {"228980": 255505002}), (windows, {"35140": 1, "550": 14964354280, "999": 0}),
        ("D:\\\\Elsewhere", {"1": 5})]))
    manifest(mac, "892970", "Valheim", 4586639854)
    (mac / "steamapps/libraryfolders.vdf").write_text(vdf([(str(mac), {"892970": 4586639854})]))
    (support / "Epic/legendary").mkdir(parents=True)
    (support / "Epic/legendary/installed.json").write_text(json.dumps({
        "Calluna": {"app_name": "Calluna", "title": "Control", "install_size": 45000000000, "platform": "Windows", "is_dlc": False,
                    "install_path": str(drive / "Epic Games/Control")},
        "CallunaDLC": {"app_name": "CallunaDLC", "title": "Control: AWE", "install_size": 1000000000, "platform": "Windows", "is_dlc": True,
                       "install_path": str(drive / "Epic Games/Control")}}))
    (support / "GOG").mkdir()
    (support / "GOG/installed.json").write_text(json.dumps({"1816059595": {
        "id": "1816059595", "platform": "windows", "size": 8441968765, "path": "file://" + str(drive).replace(" ", "%20") + "/GOG%20Games/Mafia%20II/"}}))
    (support / "GOG/library.json").write_text(json.dumps({"games": [{"id": "1816059595", "title": "Mafia II (Classic)"}]}))
    return support, mac


class StockTests(unittest.TestCase):
    def test_reads_what_the_stores_list_as_installed(self):
        with tempfile.TemporaryDirectory() as tmp:
            support, mac = stores(pathlib.Path(tmp))
            stock = liste.read_stock(support, mac)
            self.assertEqual([(g["key"], g["platform"], g["name"], g["sizeBytes"]) for g in stock], [
                ("epic.Calluna", "windows", "Control", 46000000000),  # with its add-on
                ("gog.1816059595", "windows", "Mafia II (Classic)", 8441968765),
                ("steam.35140", "windows", "Batman: Arkham Asylum GOTY Edition", 8471095333),  # the manifest's size before the list's
                ("steam.550", "windows", "Left 4 Dead 2", 14964354280),
                ("steam.892970", "mac", "Valheim", 4586639854)])  # no tool of Steam's, nothing without a size, no unknown drive
            self.assertEqual({g["location"] for g in stock}, {"intern"})
            self.assertEqual((liste.place("/Volumes/Some Drive/Games"), liste.place("/Applications")), ("extern", "intern"))
            self.assertNotIn(str(tmp), json.dumps(stock))  # no path leaves the reader

    def test_missing_stores_are_no_games(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(liste.read_stock(pathlib.Path(tmp) / "nothing", pathlib.Path(tmp) / "none"), [])

    def test_valves_text_as_dicts(self):
        parsed = liste.parse_vdf('"a"\n{\n\t"path"\t\t"Z:\\\\Volumes\\\\X"\n\t"b"\n\t{\n\t\t"1"\t"2"\n\t}\n}\n')
        self.assertEqual(parsed, {"a": {"path": "Z:\\Volumes\\X", "b": {"1": "2"}}})
        self.assertEqual(liste.parse_vdf("not valve's"), {})


class ChecklistTests(unittest.TestCase):
    LOW = {"average": 2, "cores": 10, "low": True}
    BUILT = "2026-11-15T18:00:00Z"

    def stock(self, *games):
        return [{"key": key, "platform": platform, "name": name, "sizeBytes": size, "location": "extern"} for key, platform, name, size in games]

    def measured_run(self, at, games, **more):
        return report(at, games, version=2, built=self.BUILT, playSeconds=200, **more)

    def clean(self, name, key, way="dxmt", **more):
        game = dict({"frames": {"average": 59.3, "low": 56.7, "periods": 12, "seconds": 190}, "load": self.LOW,
                     "measure": {"window": "1512×982", "frameLimit": 60, "refreshRate": 120}, "check": {"start": "ok", "fps": "ok"}}, **more)
        return played(name, key, way=way, **game)

    def test_done_needs_a_clean_start_and_a_frame_rate_with_its_conditions(self):
        stock = self.stock(("steam.287700", "windows", "MGS V", 31106322849), ("epic.Calluna", "windows", "Control", 45000000000),
                           ("steam.239140", "mac", "Dying Light", 33640621009))
        quiet = self.clean("Control", "epic.Calluna", way="d3dmetal", frames=None, check={"start": "ok", "fps": "wayReportsNone"},
                           measure={"window": "1512×982", "frameLimit": 60, "noFrames": "wayReportsNone"})
        document = liste.checklist(stock, [], [self.measured_run("2026-11-15T20:00:00Z", [self.clean("MGS V", "steam.287700"), quiet])])
        by = {game["key"]: game for game in document["games"]}
        self.assertEqual((by["steam.287700"]["status"], by["steam.287700"]["missing"]), ("fertig", []))
        self.assertEqual((by["steam.287700"]["fps"]["kind"], by["steam.287700"]["fps"]["holds"], by["steam.287700"]["fps"]["public"]), ("holdsLimit", True, True))
        self.assertEqual((by["epic.Calluna"]["status"], by["epic.Calluna"]["missing"], by["epic.Calluna"]["fps"]["why"]), ("offen", ["fps"], "wayReportsNone"))
        self.assertEqual((by["steam.239140"]["status"], by["steam.239140"]["missing"], by["steam.239140"]["start"]["why"]), ("offen", ["start", "fps"], "never"))
        self.assertEqual(document["totals"], {"fertig": {"games": 1, "bytes": 31106322849}, "offen": {"games": 2, "bytes": 78640621009},
                                              "von-hand": {"games": 0, "bytes": 0}})
        self.assertEqual((document["build"]["nightforge"], document["build"]["built"], document["build"]["since"], document["mac"]),
                         ("0.3.2", self.BUILT, "2026-11-15T20:00:00Z", MAC))
        table = liste.checklist_markdown(document)
        self.assertIn("**Fertig: 1 Spiel, 31,1 GB. Offen: 2 Spiele, 78,6 GB. Von Hand zu prüfen: 0 Spiele, 0,0 GB.**", table)
        self.assertIn("| MGS V | Steam | Windows | 31,1 GB | ja (Spieletest 15.11.2026, dxmt) | ja: hält 60 FPS, Ø 59, 15.11.2026, dxmt | B1 (aktuell) | **fertig – darf weg** |", table)
        self.assertIn("| Control | Epic Games | Windows | 45,0 GB | ja (Spieletest 15.11.2026, d3dmetal) | fehlt: D3DMetal meldet keine (15.11.2026, d3dmetal) | B1 (aktuell) | offen |", table)
        self.assertIn("| Dying Light | Steam | Mac | 33,6 GB | fehlt: kein Start aufgezeichnet | fehlt: nie gemessen | – | offen |", table)
        self.assertIn("Aktueller Build: Nightforge 0.3.2 (gebaut 15.11.2026 18:00 UTC) · winecx@4.7.3", table)
        self.assertIn("- **B1** (aktuell): Nightforge 0.3.2 (gebaut 15.11.2026 18:00 UTC) · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17, gesehen seit 15.11.2026", table)
        self.assertEqual(by["steam.287700"]["build"], {"nightforge": "0.3.2", "built": self.BUILT, "since": "2026-11-15T20:00:00Z", "current": True,
                                                       "engine": ["winecx@4.7.3", "d3dmetal@apple-3.0", "graphics@11.18-dxmt0.80-17"]})
        self.assertIsNone(by["steam.239140"]["build"])
        self.assertIn("Deinstalliert wird von hier aus nie etwas", table)
        self.assertEqual([game["key"] for game in document["games"]], ["steam.287700", "epic.Calluna", "steam.239140"])  # done first, then by size

    def test_a_number_without_its_limit_and_an_older_build_do_not_count(self):
        stock = self.stock(("epic.Curry", "windows", "ABZU", 4800000000))
        old = report("2026-11-10T00:57:00Z", [played("ABZU", "epic.Curry", way="dxmt -dx11", frames={"average": 54.8, "low": 42.3, "periods": 6}, load=self.LOW)])
        abzu = liste.checklist(stock, [], [old])["games"][0]
        self.assertEqual((abzu["start"]["ok"], abzu["fps"]["ok"], abzu["fps"]["why"], abzu["fps"]["average"]), (True, False, "limitUnknown", 54.8))
        self.assertIn("fehlt: Wert ohne aufgezeichnetes Limit (Ø 55, 10.11.2026, dxmt -dx11)", liste.checklist_markdown(liste.checklist(stock, [], [old])))
        # A newer build's first run without the game: what the old build saw stays, under that build's name.
        newer = self.measured_run("2026-11-15T20:00:00Z", [self.clean("MGS V", "steam.287700")])
        document = liste.checklist(stock, [], [old, newer])
        abzu = document["games"][0]
        self.assertEqual((abzu["start"]["ok"], abzu["fps"]["why"], abzu["build"]["current"], abzu["build"]["built"]), (True, "limitUnknown", False, None))
        self.assertEqual(document["build"]["built"], self.BUILT)  # the current build is the newer one all the same
        table = liste.checklist_markdown(document)
        self.assertIn("- **B1**: Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17, gesehen seit 10.11.2026", table)
        self.assertIn("fehlt: Wert ohne aufgezeichnetes Limit (Ø 55, 10.11.2026, dxmt -dx11) | B1 | offen |", table)

    def test_done_once_is_done_and_names_the_build_it_was_done_on(self):
        """The player uninstalls a game once it's done: no newer build can measure it again, so none takes it back."""
        stock = self.stock(("steam.1", "windows", "Game", 1000000000))
        done = self.measured_run("2026-11-15T20:00:00Z", [self.clean("Game", "steam.1")])
        newer = dict(BUILT="2026-11-17T09:00:00Z")

        def run(at, game, built=self.BUILT):
            return report(at, [game], version=2, built=built, playSeconds=200)

        def check(*runs, evidence=()):
            document = liste.checklist(stock, [list(evidence)], [done] + list(runs))
            return document, document["games"][0]

        # A newer build that never saw the game: done stays, on the build it was done on.
        other = run("2026-11-17T10:00:00Z", self.clean("MGS V", "steam.287700"), built=newer["BUILT"])
        document, game = check(other)
        self.assertEqual((game["status"], game["missing"], game["build"]["built"], game["build"]["current"]), ("fertig", [], self.BUILT, False))
        self.assertEqual((document["build"]["built"], [one["built"] for one in document["builds"]]), (newer["BUILT"], [self.BUILT]))
        self.assertIn("| ja (Spieletest 15.11.2026, dxmt) | ja: hält 60 FPS, Ø 59, 15.11.2026, dxmt | B1 | **fertig – darf weg** |", liste.checklist_markdown(document))
        # A start that goes wrong on the newer build is said beside it and takes nothing back.
        failed = run("2026-11-17T10:00:00Z", played("Game", "steam.1", outcome="noPicture"), built=newer["BUILT"])
        document, game = check(failed)
        self.assertEqual((game["status"], game["build"]["built"]), ("fertig", self.BUILT))
        self.assertEqual(game["later"], {"count": 1, "at": "2026-11-17T10:00:00Z", "why": "noPicture", "by": "gameTest"})
        self.assertIn("ja (Spieletest 15.11.2026, dxmt); danach ein Start ging schief, zuletzt 17.11.2026: kein Bild (Spieletest)", liste.checklist_markdown(document))
        # … also on the same build, and from the evidence: two of them, the newest named.
        twice = run("2026-11-15T21:00:00Z", self.clean("Game", "steam.1", check={"start": "severalWays", "fps": "ok"}))
        begun = started("steam.1", "dxmt", "2026-11-18T12:00:00Z", nightforge="0.3.2", built=newer["BUILT"], parts=["winecx@4.7.3"])
        document, game = check(twice, evidence=[begun, event("steam.1", "failed", "dxmt", "2026-11-18T12:00:20Z")])
        self.assertEqual((game["status"], game["later"]), ("fertig", {"count": 2, "at": "2026-11-18T12:00:00Z", "why": "failed", "by": "evidence"}))
        self.assertIn("danach 2 Starts gingen schief, zuletzt 18.11.2026: Fehlstart (Evidenz)", liste.checklist_markdown(document))
        # A start that settles nothing, or one that went wrong before the clean one, is no note.
        short = run("2026-11-15T21:00:00Z", self.clean("Game", "steam.1", frames=None, check={"start": "tooShort", "fps": "noneInLog"}))
        self.assertIsNone(check(short)[1]["later"])
        early = report("2026-11-15T19:00:00Z", [played("Game", "steam.1", outcome="noPicture")], version=2, built=self.BUILT, playSeconds=200)
        self.assertEqual((check(early)[1]["status"], check(early)[1]["later"]), ("fertig", None))
        # Done again on the newer build: the entry names the newest build that had both.
        again = run("2026-11-17T10:00:00Z", self.clean("Game", "steam.1"), built=newer["BUILT"])
        document, game = check(again)
        self.assertEqual((game["status"], game["build"]["built"], game["build"]["current"], game["start"]["at"]), ("fertig", newer["BUILT"], True, "2026-11-17T10:00:00Z"))

    def test_both_have_to_be_on_the_same_build(self):
        stock = self.stock(("steam.1", "windows", "Game", 1000000000))
        quiet = self.clean("Game", "steam.1", way="d3dmetal", frames=None, check={"start": "ok", "fps": "noneInLog"}, measure={"frameLimit": 60, "noFrames": "noneInLog"})
        started_only = self.measured_run("2026-11-15T20:00:00Z", [quiet])
        measured_only = report("2026-11-17T10:00:00Z", [self.clean("Game", "steam.1", check={"start": "severalWays", "fps": "ok"})], version=2,
                               built="2026-11-17T09:00:00Z", playSeconds=200)
        document = liste.checklist(stock, [], [started_only, measured_only])
        game = document["games"][0]
        # A clean start on one build and a frame rate on another: open, and what the newest build with a record says.
        self.assertEqual((game["status"], game["missing"], game["start"]["why"], game["fps"]["ok"], game["build"]["built"]),
                         ("offen", ["start"], "severalWays", True, "2026-11-17T09:00:00Z"))
        self.assertIsNone(game["later"])  # no clean start on that build: nothing came "after" one
        # Both on the older build after all: done there.
        both = self.measured_run("2026-11-15T21:00:00Z", [self.clean("Game", "steam.1")])
        game = liste.checklist(stock, [], [started_only, both, measured_only])["games"][0]
        self.assertEqual((game["status"], game["build"]["built"], game["later"]["why"]), ("fertig", self.BUILT, "severalWays"))

    def test_a_clean_start_stays_one_on_its_build(self):
        stock = self.stock(("steam.1", "windows", "Game", 1000000000))
        quiet = {"frames": None, "check": {"start": "ok", "fps": "noneInLog"}, "measure": {"frameLimit": 60, "noFrames": "noneInLog"}}
        first = self.measured_run("2026-11-15T20:00:00Z", [self.clean("Game", "steam.1", **quiet)])

        def start(*later):
            runs = [first] + [self.measured_run(f"2026-11-15T2{index + 1}:00:00Z", [game]) for index, game in enumerate(later)]
            game = liste.checklist(stock, [], runs)["games"][0]
            return game["status"], game["start"]["ok"], game["start"]["at"], (game["later"] or {}).get("why")

        twice = self.clean("Game", "steam.1", check={"start": "severalWays", "fps": "ok"})
        short = self.clean("Game", "steam.1", frames=None, check={"start": "tooShort", "fps": "noneInLog"})
        self.assertEqual(start(), ("offen", True, "2026-11-15T20:00:00Z", None))
        # A later start that needed a second way brings the frame rate: with the clean start before it that is done, and said.
        self.assertEqual(start(twice), ("fertig", True, "2026-11-15T20:00:00Z", "severalWays"))
        self.assertEqual(start(short), ("offen", True, "2026-11-15T20:00:00Z", None))
        # Without any clean start the newest one is the answer.
        none = liste.checklist(stock, [], [self.measured_run("2026-11-15T20:00:00Z", [twice]), self.measured_run("2026-11-15T21:00:00Z", [short])])["games"][0]
        self.assertEqual((none["status"], none["start"]["ok"], none["start"]["why"], none["fps"]["ok"]), ("offen", False, "tooShort", True))

    def test_starts_by_hand_count_from_the_evidence(self):
        stock = self.stock(("steam.35140", "windows", "Batman", 8471095333))
        run = self.measured_run("2026-11-15T20:00:00Z", [self.clean("MGS V", "steam.287700")])

        def start(*events, since=None):
            game = liste.checklist(stock, [list(events)], [run], since=since)["games"][0]
            return game["start"]["ok"], game["start"]["why"], game["start"]["by"]

        begun = started("steam.35140", "wined3d", "2026-11-16T12:08:12Z")
        self.assertEqual(start(begun, event("steam.35140", "worked", "wined3d", "2026-11-16T12:11:13Z")), (True, "ok", "evidence"))
        self.assertEqual(start(begun), (False, "noOutcome", "evidence"))
        self.assertEqual(start(begun, event("steam.35140", "ended", "wined3d", "2026-11-16T12:09:00Z", picture=True, seconds=48)), (False, "tooShort", "evidence"))
        known = started("steam.35140", "wined3d", "2026-11-16T12:08:12Z", known=True)
        self.assertEqual(start(known, event("steam.35140", "ended", "wined3d", "2026-11-16T12:20:00Z", picture=True, seconds=700)), (True, "ok", "evidence"))
        self.assertEqual(start(known, event("steam.35140", "failed", "wined3d", "2026-11-16T12:08:30Z")), (False, "failed", "evidence"))
        # The ladder's next way right after a failure is the same launch: no clean start, even if that way worked.
        self.assertEqual(start(started("steam.35140", "d3dmetal", "2026-11-16T12:00:00Z"), event("steam.35140", "failed", "d3dmetal", "2026-11-16T12:00:20Z"),
                               started("steam.35140", "wined3d", "2026-11-16T12:00:21Z"), event("steam.35140", "worked", "wined3d", "2026-11-16T12:03:30Z")),
                         (False, "severalWays", "evidence"))
        # Before the build's first game test nothing counts – unless the build's date is given.
        early = [started("steam.35140", "wined3d", "2026-11-14T12:08:12Z"), event("steam.35140", "worked", "wined3d", "2026-11-14T12:11:13Z")]
        self.assertEqual(start(*early), (False, "never", None))
        self.assertEqual(start(*early, since="2026-11-11T20:00:00Z"), (True, "ok", "evidence"))
        another = dict(started("steam.35140", "wined3d", "2026-11-16T12:08:12Z"), engine="winecx@5.0")
        self.assertEqual(start(another, event("steam.35140", "worked", "wined3d", "2026-11-16T12:11:13Z")), (False, "never", None))

    def test_a_start_that_names_its_build_counts_on_that_build_only(self):
        stock = self.stock(("steam.35140", "windows", None, 8471095333))
        parts = ["winecx@4.7.3", "d3dmetal@apple-3.0", "graphics@11.18-dxmt0.80-17"]
        run = self.measured_run("2026-11-15T20:00:00Z", [self.clean("MGS V", "steam.287700")])

        def said(at, built=self.BUILT, parts=parts, **more):
            return started("steam.35140", "wined3d", at, name="Batman", nightforge="0.3.2", built=built, parts=parts, **more)

        def check(*events, runs=(run,), since=None):
            return liste.checklist(stock, [list(events)], list(runs), since=since)

        worked = event("steam.35140", "worked", "wined3d", "2026-11-16T12:11:13Z")
        # The report's build, named by the start: it counts, and the game has its name from the start.
        game = check(said("2026-11-16T12:08:12Z"), worked)["games"][0]
        self.assertEqual((game["start"]["ok"], game["start"]["by"], game["name"]), (True, "evidence", "Batman"))
        # A newer test build shares the version: its starts are the current build now, the older report isn't.
        newer = check(said("2026-11-16T12:08:12Z", built="2026-11-16T09:00:00Z"), worked)
        self.assertEqual((newer["build"]["built"], newer["build"]["since"], newer["build"]["sinceFrom"]),
                         ("2026-11-16T09:00:00Z", "2026-11-16T12:08:12Z", "firstStart"))
        self.assertEqual((newer["games"][0]["start"]["ok"], newer["games"][0]["fps"]["why"]), (True, "never"))
        self.assertIn("(erster aufgezeichneter Start auf diesem Build)", liste.checklist_markdown(newer))
        # A start on an older build, or on other engine parts, counts on that build and is named with it – whatever its date.
        older = check(said("2026-11-15T21:00:00Z", built="2026-11-10T09:00:00Z"), event("steam.35140", "worked", "wined3d", "2026-11-15T21:04:00Z"),
                      runs=[run, self.measured_run("2026-11-15T22:00:00Z", [self.clean("MGS V", "steam.287700")])])
        game = older["games"][0]
        self.assertEqual((older["build"]["built"], game["start"]["ok"], game["build"]["built"], game["build"]["current"]),
                         (self.BUILT, True, "2026-11-10T09:00:00Z", False))
        other = check(said("2026-11-15T21:00:00Z", parts=["winecx@4.7.3", "graphics@11.19"]), event("steam.35140", "worked", "wined3d", "2026-11-15T21:04:00Z"),
                      runs=[run, self.measured_run("2026-11-15T22:00:00Z", [self.clean("MGS V", "steam.287700")])])
        self.assertEqual((other["games"][0]["build"]["engine"], other["games"][0]["build"]["current"]), (["winecx@4.7.3", "graphics@11.19"], False))
        # No report at all: the starts alone name the build.
        alone = check(said("2026-11-16T12:08:12Z"), worked, runs=[])
        self.assertEqual((alone["build"]["nightforge"], alone["build"]["engine"], alone["games"][0]["start"]["ok"]), ("0.3.2", parts, True))
        self.assertIsNone(check(started("steam.35140", "wined3d", "2026-11-16T12:08:12Z"), worked, runs=[])["build"])

    def test_what_no_game_test_starts_is_for_a_person(self):
        stock = self.stock(("steam.77", "windows", None, 84000000000), ("steam.35140", "windows", "Batman", 8471095333), ("steam.5", "windows", "Updater", 1))
        guarded = played("Shooter", "steam.77", outcome="skipped", way=None, skip="antiCheat")
        other = played("Batman", "steam.35140", outcome="skipped", way=None, skip="versionSwitch")
        update = played("Updater", "steam.5", outcome="skipped", way=None, skip="update")
        run = self.measured_run("2026-11-15T20:00:00Z", [guarded, other, update])
        by = {game["key"]: game for game in liste.checklist(stock, [], [run])["games"]}
        self.assertEqual((by["steam.77"]["status"], by["steam.77"]["byHand"], by["steam.77"]["name"]), ("von-hand", "antiCheat", "Shooter"))
        self.assertEqual((by["steam.35140"]["status"], by["steam.35140"]["byHand"]), ("von-hand", "versionSwitch"))
        self.assertEqual((by["steam.5"]["status"], by["steam.5"]["skipped"]), ("offen", "update"))  # an update can be mended: open, with the reason
        table = liste.checklist_markdown(liste.checklist(stock, [], [run]))
        self.assertIn("| von Hand zu prüfen: Anti-Cheat sperrt es auf dem Mac |", table)
        self.assertIn("| offen (Spieletest ließ es aus: ein Update stünde an) |", table)
        # Once the player has made the other version's first start, the skip is history.
        since = [started("steam.35140", "wined3d", "2026-11-16T12:08:12Z"), event("steam.35140", "worked", "wined3d", "2026-11-16T12:11:13Z")]
        batman = next(game for game in liste.checklist(stock, [since], [run])["games"] if game["key"] == "steam.35140")
        self.assertEqual((batman["status"], batman["byHand"], batman["missing"]), ("offen", None, ["fps"]))
        # An anti-cheat the evidence names is by hand as well.
        flagged = [started("steam.5", "dxmt", "2026-11-16T12:08:12Z", kind={"engine": "other", "antiCheat": True})]
        self.assertEqual(next(game for game in liste.checklist(stock, [flagged], [run])["games"] if game["key"] == "steam.5")["byHand"], "antiCheat")

    def test_the_command_writes_the_checklist_from_the_stores_it_is_given(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            support, mac = stores(base)
            (base / "run").mkdir()
            (base / "run/report.json").write_text(json.dumps(self.measured_run("2026-11-15T20:00:00Z", [self.clean("Control", "epic.Calluna")])))
            arguments = ["--evidence", str(base / "none.jsonl"), "--names", str(base / "none.json"), "--stock", str(support), "--mac-steam", str(mac),
                         "--out", str(base / "out"), str(base / "run")]
            liste.main(arguments)
            first = {name: (base / "out" / name).read_bytes() for name in ("abhakliste.json", "ABHAKLISTE.md", "laeuft.json", "LAEUFT.md")}
            liste.main(arguments)
            self.assertEqual(first, {name: (base / "out" / name).read_bytes() for name in first})
            check = json.loads(first["abhakliste.json"])
            self.assertEqual((check["formatVersion"], check["totals"]["fertig"]), (1, {"games": 1, "bytes": 46000000000}))
            self.assertEqual([game["name"] for game in check["games"]], ["Control", "Left 4 Dead 2", "Batman: Arkham Asylum GOTY Edition", "Mafia II (Classic)", "Valheim"])
            for text in first.values():
                self.assertNotIn(str(base).encode(), text)

    def test_what_a_launch_says(self):
        def launch(**more):
            return dict({"starts": 1, "failed": 0, "gaveUp": False, "worked": False, "known": False, "ended": None}, **more)

        self.assertEqual(liste.launch_verdict(launch(worked=True)), ("ok", True))
        self.assertEqual(liste.launch_verdict(launch(starts=2, worked=True)), ("severalWays", True))
        self.assertEqual(liste.launch_verdict(launch(gaveUp=True)), ("failed", True))
        self.assertEqual(liste.launch_verdict(launch()), ("noOutcome", False))
        self.assertEqual(liste.launch_verdict(launch(ended={"picture": False, "seconds": 20})), ("endedEarly", False))
        self.assertEqual(liste.launch_verdict(launch(ended={"picture": True, "seconds": 600})), ("tooShort", False))  # not confirmed before: 600 s prove nothing more
        self.assertEqual(liste.launch_verdict(launch(known=True, ended={"picture": True, "seconds": 179})), ("tooShort", False))


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
            common = ["--evidence", str(base / "evidence.jsonl"), "--names", str(base / "namen.json"), "--no-stock"]
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
            self.assertFalse((base / "a/abhakliste.json").exists())  # nothing read of what is installed: no checklist

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
        check = ROOT / "docs/laeuft/abhakliste.json"
        if check.is_file():
            self.assertEqual((ROOT / "docs/laeuft/ABHAKLISTE.md").read_text(encoding="utf-8"),
                             liste.checklist_markdown(json.loads(check.read_text(encoding="utf-8"))))
            self.assertFalse(liste.leaks(check.read_text(encoding="utf-8"), "/Users/nobody", "nobody"))


if __name__ == "__main__":
    unittest.main()
