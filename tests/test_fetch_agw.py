"""Tests for scripts/fetch-agw.py. Run: python3 -m unittest tests/test_fetch_agw.py

The pages here are made up in AppleGamingWiki's format, not copied from it."""

import copy
import datetime
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "fetch-agw.py"
spec = importlib.util.spec_from_file_location("fetch_agw", SCRIPT)
agw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agw)


def page(crossover="unknown", crossover_notes="", wine="unknown", wine_notes="", native="na", native_notes="",
         infobox="|steam appid  = 100\n|gogcom id    = 200\n|codeweavers  = Example Game\n"):
    box = "{{Infobox game\n|cover = Example.jpg\n" + infobox + "}}\n\n" if infobox is not None else ""
    return box + f"""{{{{Compatibility/macOS
|native               = {native}
|native notes         = {native_notes}
|rosetta 2            = na
|rosetta 2 notes      =
|crossover            = {crossover}
|crossover notes      = {crossover_notes}
|wine                 = {wine}
|wine notes           = {wine_notes}
|parallels            = playable
|parallels notes      = Runs in a virtual machine.
}}}}

[[Category:Games]]"""


def ref(**fields):
    return "<ref>{{Refdevice|" + "|".join(f"{k}={v}" for k, v in fields.items()) + "}}</ref>"


def parse(text, title="Example Game", edited="2025-01-02T03:04:05Z"):
    return agw.parse_page(title, text, edited)


class ParseTests(unittest.TestCase):
    def test_ratings_ids_and_evidence(self):
        result = parse(page(crossover="perfect",
                            crossover_notes="Smooth on [[CrossOver]] 23.5.''Bold''" + ref(user="someone", date="2023-10-13",
                                device="MacBook Pro M1 Pro 16 GB", method="CrossOver 23.5 with D3DMetal on and DX12"),
                            wine="playable", wine_notes="[[Game Porting Toolkit]] 2 works.",
                            native="perfect", native_notes="Native build."))
        self.assertEqual(result["steam"], ["100"])
        self.assertEqual(result["gog"], ["200"])
        self.assertEqual(result["codeweavers"], "Example Game")
        self.assertEqual(result["edited"], "2025-01-02")
        crossover = result["paths"]["crossover"]
        self.assertEqual(crossover["rating"], "perfect")
        self.assertEqual(crossover["note"], "Smooth on CrossOver 23.5.Bold")
        self.assertEqual(crossover["versions"], ["CrossOver 23.5"])
        self.assertEqual(crossover["graphics"], ["d3dmetal"])
        self.assertEqual(crossover["directX"], ["12"])
        self.assertEqual(crossover["chips"], ["M1 Pro"])
        self.assertEqual(crossover["date"], "2023-10-13")
        self.assertEqual(result["paths"]["wine"]["versions"], ["GPTK 2"])
        self.assertEqual(result["paths"]["native"], {"rating": "perfect", "note": "Native build."})
        self.assertNotIn("parallels", result["paths"])

    def test_reporters_names_never_land_in_the_result(self):
        result = parse(page(crossover="perfect", crossover_notes="Fine." + ref(user="SecretUser42", date="2024-01-01")))
        self.assertNotIn("SecretUser42", json.dumps(result))

    def test_unknown_na_and_free_text_ratings_are_left_out(self):
        result = parse(page(crossover="unknown", wine="works great", native="perfect"))
        self.assertEqual(list(result["paths"]), ["native"])
        self.assertIsNone(parse(page(crossover="unknown", wine="na", native="na")))
        self.assertIsNone(agw.parse_page("No table", "Just text."))

    def test_long_notes_are_shortened_at_a_word(self):
        result = parse(page(crossover="playable", crossover_notes="word " * 200))
        note = result["paths"]["crossover"]["note"]
        self.assertLessEqual(len(note), agw.NOTE_LENGTH + 2)
        self.assertTrue(note.endswith(" …"))

    def test_pipes_inside_links_templates_and_refs_stay_in_their_argument(self):
        args = agw.template_args("\n|a = [[Page|label]] {{T|x=1}}<ref name=\"r\">{{Refdevice|user=u|date=1}}</ref>\n|b = 2<ref name=\"r\"/>\n")
        self.assertEqual(set(args), {"a", "b"})
        self.assertEqual(agw.clean(args["a"]), "label")
        self.assertEqual(agw.clean(args["b"]), "2")

    def test_several_ids_but_not_side_ids(self):
        # Pages often keep the sample article's "steam appid side = 10": Counter-Strike's ID.
        result = parse(page(crossover="perfect", infobox="|steam appid = 300, 301\n|steam appid side = 10\n|gogcom id = \n"))
        self.assertEqual(result["steam"], ["300", "301"])
        self.assertEqual(result["gog"], [])

    def test_dates_in_the_ways_editors_write_them(self):
        self.assertEqual(agw.parse_date("27-03-2025"), "2025-03-27")
        self.assertEqual(agw.parse_date("2023-10-13"), "2023-10-13")
        self.assertEqual(agw.parse_date("10/25/2024"), "2024-10-25")
        self.assertEqual(agw.parse_date("October 2023"), "2023-10-01")
        self.assertIsNone(agw.parse_date("sometime"))


class HintTests(unittest.TestCase):
    def hint(self, text, own=None):
        return agw.derive_hint(parse(text), own)

    def test_the_one_layer_good_ways_name(self):
        hint = self.hint(page(crossover="perfect", crossover_notes="Works with D3DMetal and DX12.",
                              wine="perfect", wine_notes="Game Porting Toolkit: rename the exe."))
        self.assertEqual(hint, {"graphics": "d3dmetal", "directX": "12", "from": ["crossover", "wine"], "source": "agw"})
        self.assertEqual(self.hint(page(crossover="playable", crossover_notes="Use DXMT on CrossOver 25.1.")),
                         {"graphics": "dxmt", "from": ["crossover"], "source": "agw"})

    def test_nothing_named_no_hint(self):
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Runs great.")))

    def test_two_layers_is_no_clear_hint(self):
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="DXVK crashes, D3DMetal works.")))
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Use D3DMetal on CrossOver 25.",
                                         wine="playable", wine_notes="Fine with DXMT on CrossOver 25.")))

    def test_a_layer_named_in_a_bad_light_is_no_hint(self):
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Crashes with D3DMetal.")))
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Turn D3DMetal off.")))
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Works with D3DMetal.",
                                         wine="unplayable", wine_notes="GPTK shows a black window.")))

    def test_a_far_away_negative_word_doesnt_count(self):
        hint = self.hint(page(wine="perfect", wine_notes="Game Porting Toolkit - run it from the game's folder, as the game "
                                                         "would otherwise complain about a missing Data folder."))
        self.assertEqual(hint["graphics"], "d3dmetal")

    def test_ways_that_dont_run_well_dont_hint(self):
        self.assertIsNone(self.hint(page(crossover="runs", crossover_notes="Menus with D3DMetal.")))

    def test_dxvk_only_counts_from_crossover_with_dxmt(self):
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Enable DXVK. Tested on CrossOver 23.")))
        self.assertEqual(self.hint(page(crossover="perfect", crossover_notes="Enable DXVK. Tested on CrossOver 25.1."))["graphics"], "dxvk")
        # An old DXVK recommendation still makes another layer unclear.
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Use DXVK on CrossOver 22.",
                                         wine="perfect", wine_notes="GPTK works.")))

    def test_nightforges_own_profile_wins(self):
        self.assertIsNone(self.hint(page(crossover="perfect", crossover_notes="Works with D3DMetal."), own="dxmt"))


class BuildTests(unittest.TestCase):
    def test_keys_aliases_and_mac_profiles(self):
        pages = [
            parse(page(crossover="perfect", crossover_notes="Works with D3DMetal.",
                       infobox="|steam appid = 500, 501\n|gogcom id = 900\n"), title="B Game"),
            parse(page(crossover="perfect", crossover_notes="Works with D3DMetal.",
                       infobox="|steam appid = \n|gogcom id = 901\n"), title="GOG Only"),
            parse(page(crossover="perfect", infobox=None), title="Short Page"),
            parse(page(crossover="perfect", crossover_notes="Works with D3DMetal.",
                       infobox="|steam appid = 600\n"), title="Tested"),
        ]
        agw.fill_ids(pages, agw.wikidata_ids([{"pcgw": {"value": "Short_Page"}, "steam": {"value": "700"}}]))
        mac = {"games": {"600": {"graphics": "dxmt"}}}
        games, aliases, stats = agw.build(pages, mac)
        self.assertEqual(set(games), {"500", "gog.901", "700", "600"})
        self.assertEqual(aliases, {"steam": {"501": "500"}, "gog": {"900": "500"}})
        self.assertEqual(games["700"]["ids"], "wikidata")
        self.assertNotIn("hint", games["600"])
        self.assertEqual(stats["overruled"], 1)
        self.assertEqual(games["500"]["hint"]["graphics"], "d3dmetal")
        self.assertNotIn("_mentions", games["500"])

    def test_wikidata_titles_differing_in_case_match_when_unique(self):
        pages = [parse(page(crossover="perfect", infobox=None), title="Cruelty squad"),
                 parse(page(crossover="perfect", infobox=None), title="Two Ways")]
        bindings = [{"pcgw": {"value": "Cruelty_Squad"}, "steam": {"value": "800"}},
                    {"pcgw": {"value": "Two_ways"}, "steam": {"value": "801"}},
                    {"pcgw": {"value": "Two_WAYS"}, "steam": {"value": "802"}}]
        agw.fill_ids(pages, agw.wikidata_ids(bindings))
        self.assertEqual((pages[0]["steam"], pages[0]["ids"]), (["800"], "name"))
        self.assertEqual(pages[1]["steam"], [])

    def test_an_infobox_beats_wikidata_for_the_same_id(self):
        pages = [parse(page(crossover="perfect", infobox=None), title="A Remaster"),
                 parse(page(crossover="playable", infobox="|steam appid = 900\n"), title="Z Original")]
        agw.fill_ids(pages, agw.wikidata_ids([{"pcgw": {"value": "A_Remaster"}, "steam": {"value": "900"}}]))
        games, _, _ = agw.build(pages, {})
        self.assertEqual(games["900"]["page"], "Z Original")

    def test_generated_only_changes_with_the_content(self):
        games = {"1": {"page": "X", "paths": {"crossover": {"rating": "perfect"}}}}
        aliases = {"steam": {}, "gog": {}}
        first = agw.document(games, aliases, now=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
        same = agw.document(games, aliases, previous=first, now=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc))
        self.assertEqual(same["generated"], "2026-01-01T00:00:00Z")
        games = copy.deepcopy(games)
        games["1"]["paths"]["crossover"]["rating"] = "runs"
        changed = agw.document(games, aliases, previous=first, now=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc))
        self.assertEqual(changed["generated"], "2026-02-01T00:00:00Z")
        self.assertEqual(changed["license"], "CC BY-NC-SA 3.0")

    def test_validation_keeps_the_old_file_when_the_format_changed(self):
        games = {str(i): {"page": "X", "paths": {"crossover": {"rating": "perfect"}}} for i in range(1, 30)}
        agw.validate(agw.document(games, {"steam": {}, "gog": {}}), minimum=20)
        with self.assertRaises(ValueError):
            agw.validate(agw.document(games, {"steam": {}, "gog": {}}), minimum=100)
        games["5"]["paths"]["crossover"]["rating"] = "great"
        with self.assertRaises(ValueError):
            agw.validate(agw.document(games, {"steam": {}, "gog": {}}), minimum=20)


class CommandLineTests(unittest.TestCase):
    def test_offline_run_writes_the_file_and_a_failed_one_leaves_it(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            raw = [{"title": f"Game {i}", "wikitext": page(crossover="perfect", infobox=f"|steam appid = {i}\n"),
                    "edited": "2025-05-05T00:00:00Z"} for i in range(1, 6)]
            (folder / "pages.json").write_text(json.dumps(raw))
            (folder / "wikidata.json").write_text("[]")
            (folder / "mac.json").write_text('{"games": {}}')
            out = folder / "agw.json"
            command = [sys.executable, "-I", str(SCRIPT), "--pages", str(folder / "pages.json"),
                       "--wikidata", str(folder / "wikidata.json"), "--mac", str(folder / "mac.json"), "--out", str(out)]
            run = subprocess.run(command + ["--minimum", "3"], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            written = json.loads(out.read_text())
            self.assertEqual(sorted(written["games"], key=int), ["1", "2", "3", "4", "5"])
            before = out.read_text()
            run = subprocess.run(command + ["--minimum", "50"], capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(out.read_text(), before)


if __name__ == "__main__":
    unittest.main()
