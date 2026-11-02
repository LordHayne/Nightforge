"""Tests for scripts/test-basket.py and the grouping in scripts/mac-coverage.py, offline: the cache holds
made-up store answers. Run: python3 -m unittest tests/test_test_basket.py"""

import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


basket = load("test_basket", "test-basket.py")
coverage = load("mac_coverage", "mac-coverage.py")


def store(appid, name, kind="game", free=False, minimum="", demos=None):
    data = {"type": kind, "name": name, "is_free": free, "pc_requirements": {"minimum": minimum}}
    if demos:
        data["demos"] = [{"appid": d} for d in demos]
    return {str(appid): {"success": True, "data": data}}


class RequirementTests(unittest.TestCase):
    def test_directx_vulkan_and_storage(self):
        details = {"pc_requirements": {"minimum": "<strong>DirectX:</strong> Version 11<br><strong>Storage:</strong> 75 GB available space",
                                       "recommended": "<strong>DirectX:</strong> Version 12, Vulkan"}}
        self.assertEqual(basket.apis(details), ["dx11", "dx12", "vulkan"])
        self.assertEqual(basket.storage_gb(details), 75.0)
        self.assertEqual(basket.storage_gb({"pc_requirements": {"minimum": "Hard Drive: 900 MB"}}), 0.9)
        self.assertEqual(basket.apis({"pc_requirements": []}), [])
        self.assertIsNone(basket.storage_gb({}))

    def test_installed_steam_apps_from_libraryfolders(self):
        with tempfile.TemporaryDirectory() as folder:
            steam = pathlib.Path(folder)
            (steam / "steamapps").mkdir()
            (steam / "steamapps" / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "0"\n {\n  "path" "C:\\\\Steam"\n  "apps"\n  {\n   "550" "149"\n  }\n }\n'
                ' "1"\n {\n  "apps"\n  {\n   "2357570" "830"\n  }\n }\n}\n')
            self.assertEqual(basket.installed_steam(steam), {550: 149, 2357570: 830})
            self.assertEqual(basket.installed_steam(steam / "missing"), {})


class CoverageTests(unittest.TestCase):
    def test_groups_in_order(self):
        profiles = {"games": {"1": {"antiCheat": ["EAC"]}, "2": {"antiCheatOnline": ["BattlEye"]}}}
        mac = {"games": {"3": {"graphics": "dxmt"}}}
        agw = {"games": {"5": {"page": "Five", "paths": {"crossover": {"rating": "perfect"}}, "hint": {"graphics": "d3dmetal"}},
                         "6": {"page": "Six", "paths": {"wine": {"rating": "unplayable"}}}},
               "aliases": {"steam": {"7": "5"}}}
        group = lambda appid, mac_flag=False: coverage.classify({"appid": appid, "name": "", "mac": mac_flag}, profiles, mac, agw)["group"]
        self.assertEqual([group(1, True), group(2), group(3), group(4, True), group(5), group(6), group(8)],
                         ["anticheat", "anticheat", "tested", "mac", "agw-good", "agw-bad", "gap"])
        self.assertEqual(coverage.classify({"appid": 7, "name": "", "mac": False}, profiles, mac, agw)["hint"], "d3dmetal")


class BasketTests(unittest.TestCase):
    def test_categories_proxies_and_order(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = pathlib.Path(folder)
            answers = [
                store(100, "Big Top Game", minimum="DirectX: Version 12 Storage: 100 GB", demos=[101]),
                store(101, "Big Top Game Demo", kind="demo", minimum="DirectX: Version 12 Storage: 10 GB"),
                store(200, "Free Shooter", free=True, minimum="DirectX: Version 11 Storage: 30 GB"),
                store(300, "Blocked Free Game", free=True),
                store(400, "Unowned UE5 Game", minimum="DirectX: Version 12 Storage: 80 GB"),
                store(500, "Owned UE5 Game", minimum="DirectX: Version 12 Storage: 40 GB"),
                store(600, "Mac Top Game"),
            ]
            for answer in answers:
                appid = next(iter(answer))
                (cache / f"appdetails-full-{appid}.json").write_text(json.dumps(answer))
            for appid in basket.BENCHMARKS:
                (cache / f"appdetails-full-{appid}.json").write_text(json.dumps({str(appid): {"success": False}}))
            engines = [("400", "Unreal Engine 5"), ("500", "Unreal Engine 5"), ("100", "RE Engine"), ("101", "RE Engine")]
            (cache / "wikidata-engines.json").write_text(json.dumps({"results": {"bindings": [
                {"steam": {"value": s}, "engineLabel": {"value": e}} for s, e in engines]}}))
            top = [{"rank": 1, "appid": 100, "name": "Big Top Game", "mac": False},
                   {"rank": 2, "appid": 200, "name": "Free Shooter", "mac": False},
                   {"rank": 3, "appid": 300, "name": "Blocked Free Game", "mac": False},
                   {"rank": 4, "appid": 400, "name": "Unowned UE5 Game", "mac": False},
                   {"rank": 5, "appid": 600, "name": "Mac Top Game", "mac": True}]
            owned = [{"key": "steam.500", "name": "Owned UE5 Game", "store": "steam", "steam": 500, "sizeGB": 40.0,
                      "installed": True, "mac": False, "vrOnly": False},
                     {"key": "epic.Mac", "name": "A Mac Game", "store": "epic", "steam": None, "sizeGB": 1.0,
                      "installed": False, "mac": True, "vrOnly": False}]
            profiles = {"games": {"300": {"antiCheat": ["EAC"]}}}
            result = basket.build(top, owned, profiles, {"games": {}}, {"games": {}}, cache)
            by_key = {e["key"]: e for e in result}
            self.assertEqual(by_key["steam.500"]["category"], "proxy", "the owned UE5 DX12 game stands in for the unowned one")
            self.assertEqual(by_key["steam.500"]["standsFor"], ["steam.400"])
            self.assertEqual(by_key["steam.101"]["kind"], "demo")
            self.assertEqual(by_key["steam.101"]["demoOf"], "steam.100")
            self.assertEqual(by_key["steam.200"]["kind"], "f2p")
            self.assertNotIn("steam.300", by_key, "a free game its anti-cheat blocks isn't testable")
            self.assertNotIn("epic.Mac", by_key, "a Mac version needs no Wine test")
            self.assertNotIn("steam.600", by_key)
            self.assertEqual(by_key["steam.400"]["category"], "untestable")
            self.assertEqual(by_key["steam.400"]["coveredBy"], "steam.500")
            self.assertNotIn("steam.100", by_key, "a top game with a demo is tested through its demo")
            self.assertEqual(result[0]["key"], "steam.500", "installed and covering a top game: first")
            self.assertTrue(all(result[i]["score"] >= result[i + 1]["score"] for i in range(len(result) - 1)))


if __name__ == "__main__":
    unittest.main()
