"""Tests for scripts/fetch-geforce-now.py and for the night without its catalog in
scripts/build-profiles.py. Run: python3 -m unittest tests/test_fetch_geforce_now.py

No request leaves the machine: the answers are made up in the catalog's format."""

import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parent.parent
FETCH = ROOT / "scripts" / "fetch-geforce-now.py"
BUILD = ROOT / "scripts" / "build-profiles.py"
spec = importlib.util.spec_from_file_location("fetch_geforce_now", FETCH)
gfn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gfn)


def answer(body):
    """An urlopen stand-in that answers every request with `body` (an object, or an exception to raise)."""
    def urlopen(request, timeout=None):
        if isinstance(body, Exception):
            raise body
        return contextlib.closing(io.BytesIO(json.dumps(body).encode()))
    return urlopen


def catalog_page(count, more=False, cursor="next"):
    items = [{"id": f"g{n}", "title": f"Game {n}", "variants": [{"appStore": "STEAM", "storeId": str(1000 + n)}]}
             for n in range(count)]
    return {"data": {"apps": {"pageInfo": {"hasNextPage": more, "endCursor": cursor}, "items": items}}}


FORBIDDEN = {"errors": [{"message": "Forbidden", "path": ["apps"], "extensions": {"code": "FORBIDDEN"}}],
             "data": {"apps": None}}


class FetchTests(unittest.TestCase):
    def run_main(self, urlopen, github=False):
        with tempfile.TemporaryDirectory() as folder:
            out = pathlib.Path(folder) / "gfn.json"
            stderr = io.StringIO()
            env = {k: v for k, v in os.environ.items() if k != "GITHUB_ACTIONS"} | ({"GITHUB_ACTIONS": "true"} if github else {})
            with unittest.mock.patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = gfn.main([str(out)], urlopen)
            return code, (json.loads(out.read_text()) if out.exists() else None), stderr.getvalue()

    def test_a_whole_catalog_is_written(self):
        code, games, _ = self.run_main(answer(catalog_page(150)))
        self.assertEqual(code, 0)
        self.assertEqual(len(games), 150)

    def test_pages_are_followed(self):
        pages = iter([catalog_page(80, more=True), catalog_page(80)])
        seen = []

        def urlopen(request, timeout=None):
            seen.append(json.loads(request.data)["variables"]["after"])
            return contextlib.closing(io.BytesIO(json.dumps(next(pages)).encode()))
        self.assertEqual(len(gfn.fetch("NP-AMS-08", urlopen)), 160)
        self.assertEqual(seen, [None, "next"])

    def test_the_403_of_november_2026_skips_the_source(self):
        # The catalog's answer since 20.11.2026: HTTP 403 with a GraphQL "FORBIDDEN" on apps.
        error = urllib.error.HTTPError(gfn.URL, 403, "Forbidden", {}, io.BytesIO(json.dumps(FORBIDDEN).encode()))
        code, games, stderr = self.run_main(answer(error), github=True)
        self.assertEqual(code, 0)
        self.assertIsNone(games)
        self.assertIn("::warning title=GeForce Now catalog::Not fetched (HTTP 403 Forbidden)", stderr)

    def test_other_failures_skip_it_too(self):
        for body in (FORBIDDEN, urllib.error.URLError("no route"), TimeoutError("timed out"), ["not", "an", "object"],
                     {"data": {"apps": None}}, {"data": {}}, catalog_page(3)):
            with self.subTest(body=str(body)[:60]):
                code, games, stderr = self.run_main(answer(body))
                self.assertEqual(code, 0)
                self.assertIsNone(games)
                self.assertIn("Not fetched", stderr)

    def test_broken_json_skips_it(self):
        def urlopen(request, timeout=None):
            return contextlib.closing(io.BytesIO(b"<html>blocked</html>"))
        with self.assertRaises(gfn.Unavailable):
            gfn.fetch("NP-AMS-08", urlopen)


class BuildWithoutCatalogTests(unittest.TestCase):
    """build-profiles.py on a night the fetch wrote no catalog: the last list's ids stay."""

    ANTICHEAT = [
        {"name": "ARC Raiders", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1808500"}},
        # No Steam ID of its own: the catalog's titles gave it one, the kept list must too.
        {"name": "Nameless Shooter", "status": "Denied", "anticheats": ["BattlEye"], "storeIds": {}},
        {"name": "Epic Only", "status": "Denied", "anticheats": ["Easy Anti-Cheat"],
         "storeIds": {"epic": {"namespace": "ns1"}}},
    ]
    CATALOG = [
        {"id": "gArc", "title": "ARC Raiders", "variants": [{"appStore": "STEAM", "storeId": "1808500"}]},
        {"id": "gNameless", "title": "Nameless Shooter", "variants": [{"appStore": "STEAM", "storeId": "4242"}]},
        {"id": "gOw", "title": "Overwatch", "variants": [{"appStore": "STEAM", "storeId": "2357570"}]},
    ]
    MAC = {"games": {"2357570": {"name": "Overwatch", "notYet": "Hangs under Rosetta."}}}

    def build(self, root, catalog):
        if catalog is not None:
            (root / "gfn.json").write_text(json.dumps(catalog) if not isinstance(catalog, str) else catalog)
        elif (root / "gfn.json").exists():
            (root / "gfn.json").unlink()
        return subprocess.run([sys.executable, "-I", str(BUILD), str(root / "umu"), "--anticheat", str(root / "anticheat.json"),
                               "--geforcenow", str(root / "gfn.json"), "--mac", str(root / "mac.json"),
                               "--out", str(root / "out.json")], check=True, capture_output=True, text=True)

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.folder.name)
        (self.root / "umu" / "gamefixes-steam").mkdir(parents=True)
        (self.root / "anticheat.json").write_text(json.dumps(self.ANTICHEAT))
        (self.root / "mac.json").write_text(json.dumps(self.MAC))

    def tearDown(self):
        self.folder.cleanup()

    def doc(self):
        return json.loads((self.root / "out.json").read_text())

    def test_a_night_without_the_catalog_keeps_the_ids_and_says_since_when(self):
        self.build(self.root, self.CATALOG)
        before = self.doc()
        # The Epic game shares no Steam twin; give the last list an id for it, as a hand edit could.
        before["games"]["epic.ns1"]["geforceNow"] = "gEpic"
        (self.root / "out.json").write_text(json.dumps(before))
        self.assertEqual(before["games"]["4242"]["geforceNow"], "gNameless")

        result = self.build(self.root, None)
        self.assertIn("kept 4 ids", result.stderr)
        after = self.doc()
        for key in ("1808500", "4242", "2357570", "epic.ns1"):
            self.assertEqual(after["games"][key].get("geforceNow"), before["games"][key]["geforceNow"], key)
        self.assertEqual(after["games"]["4242"]["name"], "Nameless Shooter")
        self.assertEqual(after["sources"]["geforce-now"]["kept"], before["generated"])

    def test_the_kept_date_stays_so_the_night_commits_no_noise(self):
        self.build(self.root, self.CATALOG)
        self.build(self.root, None)
        first = self.doc()
        self.build(self.root, None)
        self.assertEqual(self.doc(), first)

    def test_an_unreadable_catalog_counts_as_none(self):
        self.build(self.root, self.CATALOG)
        for broken in ("", "{not json", json.dumps({"errors": ["x"]})):
            with self.subTest(broken=broken):
                self.build(self.root, broken)
                self.assertEqual(self.doc()["games"]["1808500"]["geforceNow"], "gArc")

    def test_the_catalog_back_drops_the_mark(self):
        self.build(self.root, self.CATALOG)
        self.build(self.root, None)
        self.build(self.root, self.CATALOG)
        self.assertEqual(self.doc()["sources"]["geforce-now"], {"url": "https://play.geforcenow.com"})

    def test_without_a_last_list_there_is_nothing_to_keep(self):
        self.build(self.root, None)
        doc = self.doc()
        self.assertNotIn("geforce-now", doc["sources"])
        self.assertNotIn("geforceNow", doc["games"]["1808500"])


if __name__ == "__main__":
    unittest.main()
