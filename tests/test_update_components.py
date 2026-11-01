"""An optional component (D3DMetal, pinned to a release that may not exist yet) stays out of the
list instead of stopping the nightly run for every other component."""
import importlib.util
import io
import json
import pathlib
import re
import tempfile
import unittest
import urllib.error
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "update-components.py"
spec = importlib.util.spec_from_file_location("update_components", SCRIPT)
update_components = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update_components)

SOURCE = {"id": "d3dmetal", "kind": "graphics", "repo": "LordHayne/Nightforge", "tagPrefix": "d3dmetal-", "tag": "d3dmetal-3.0",
          "asset": r"^nightforge-d3dmetal-.*\.tar\.gz$", "license": "LicenseRef-Apple-Game-Porting-Toolkit"}
RELEASE = {"tag_name": "d3dmetal-3.0", "draft": False, "prerelease": False,
           "assets": [{"name": "nightforge-d3dmetal-3.0.tar.gz", "size": 1234, "digest": "sha256:" + "ab" * 32,
                       "browser_download_url": "https://example.test/nightforge-d3dmetal-3.0.tar.gz"}]}


def not_found(url):
    raise urllib.error.HTTPError(url, 404, "Not Found", {}, io.BytesIO())


class OptionalComponentTests(unittest.TestCase):
    def test_a_release_that_exists_is_pinned_by_its_tag(self):
        requested = []

        def get_json(url):
            requested.append(url)
            return RELEASE

        with mock.patch.object(update_components, "get_json", get_json):
            component = update_components.build({**SOURCE, "optional": True})
        self.assertEqual((component["id"], component["version"], component["sha256"]), ("d3dmetal", "3.0", "ab" * 32))
        self.assertTrue(requested[0].endswith("/releases/tags/d3dmetal-3.0"), requested)

    def test_an_optional_one_without_its_release_is_left_out(self):
        with mock.patch.object(update_components, "get_json", not_found):
            self.assertIsNone(update_components.build({**SOURCE, "optional": True}))

    def test_without_optional_a_missing_release_still_stops_the_run(self):
        with mock.patch.object(update_components, "get_json", not_found):
            with self.assertRaises(urllib.error.HTTPError):
                update_components.build(SOURCE)

    def test_an_optional_one_with_no_stable_release_by_prefix_is_left_out(self):
        unpinned = {key: value for key, value in SOURCE.items() if key != "tag"}
        with mock.patch.object(update_components, "get_json", lambda url: []):
            self.assertIsNone(update_components.build({**unpinned, "optional": True}))
            with self.assertRaises(SystemExit):
                update_components.build(unpinned)

    def test_the_shipped_sources_pin_the_final_toolkit_and_the_manifest_holds_no_beta(self):
        import json
        root = SCRIPT.parent.parent / "components"
        d3dmetal = next(s for s in json.loads((root / "sources.json").read_text())["sources"] if s["id"] == "d3dmetal")
        self.assertEqual((d3dmetal.get("tag"), d3dmetal.get("optional")), ("d3dmetal-3.0", True))
        for component in json.loads((root / "manifest.json").read_text())["components"]:
            if component["id"] == "d3dmetal":
                self.assertEqual(component["version"], "3.0")


ROOT = SCRIPT.parent.parent


def release(tag, prerelease=False, draft=False, published="2026-01-01T00:00:00Z"):
    return {"tag_name": tag, "prerelease": prerelease, "draft": draft, "published_at": published, "assets": []}


class PinTests(unittest.TestCase):
    """winetricks (a script run as the player) and DXMT (DLLs under Wine) no longer follow their upstream's
    newest release: a stranger's release reaches the app only through a pull request a person reads."""

    def test_every_third_party_source_is_pinned(self):
        sources = json.loads((ROOT / "components/sources.json").read_text())["sources"]
        for source in sources:
            if not source["repo"].startswith("LordHayne/"):
                self.assertIn("tag", source, f"{source['id']} follows the newest release of {source['repo']}")

    def test_the_manifest_holds_what_the_pins_say(self):
        sources = {s["id"]: s for s in json.loads((ROOT / "components/sources.json").read_text())["sources"]}
        manifest = {c["id"]: c for c in json.loads((ROOT / "components/manifest.json").read_text())["components"]}
        self.assertEqual(manifest["dxmt"]["version"], sources["dxmt"]["tag"].lstrip("v"))
        self.assertEqual(manifest["winetricks"]["version"], sources["winetricks"]["tag"])
        self.assertTrue(sources["dxmt"].get("propose") and sources["winetricks"].get("propose"))

    def test_a_pinned_source_ignores_a_newer_release(self):
        requested = []

        def get_json(url):
            requested.append(url)
            return {**release("v0.80"), "assets": [{"name": "dxmt-v0.80-builtin.tar.gz", "size": 5,
                                                    "digest": "sha256:" + "cd" * 32, "browser_download_url": "https://example.test/dxmt.tar.gz"}]}

        source = {"id": "dxmt", "kind": "graphics", "repo": "3Shain/dxmt", "tag": "v0.80", "propose": True,
                  "asset": r"^dxmt-v[0-9.]+-builtin\.tar\.gz$", "license": "LGPL-2.1-or-later"}
        with mock.patch.object(update_components, "get_json", get_json):
            component = update_components.build(source)
        self.assertEqual(component["version"], "0.80")
        self.assertTrue(any(url.endswith("/releases/tags/v0.80") for url in requested), requested)
        self.assertFalse(any("/releases?" in url for url in requested), "the list of releases isn't asked for")


class ProposalTests(unittest.TestCase):
    def sources(self):
        return [
            {"id": "dxmt", "repo": "3Shain/dxmt", "tag": "v0.80", "propose": True},
            {"id": "winetricks", "repo": "Winetricks/winetricks", "tag": "20260125", "propose": True},
            {"id": "wine", "repo": "Gcenx/macOS_Wine_builds", "tag": "11.18"},
            {"id": "graphics", "repo": "LordHayne/Nightforge", "tagPrefix": "graphics-"},
        ]

    def test_only_proposed_sources_move_to_the_newest_stable_release(self):
        releases = {
            "3Shain/dxmt": [release("v0.81-rc1", prerelease=True, published="2026-06-03T00:00:00Z"),
                            release("v0.81", published="2026-06-02T00:00:00Z"), release("v0.80", published="2026-04-23T00:00:00Z")],
            "Winetricks/winetricks": [release("20260125", published="2026-01-25T00:00:00Z")],
            "Gcenx/macOS_Wine_builds": [release("11.19", published="2026-06-05T00:00:00Z")],
        }

        def get_json(url):
            repo = re.search(r"repos/([^/]+/[^/]+)/releases", url).group(1)
            return releases[repo]

        sources = self.sources()
        with mock.patch.object(update_components, "get_json", get_json):
            moves = update_components.propose_newer(sources)
        self.assertEqual(moves, [("dxmt", "v0.80", "v0.81")], "the draft/pre-release isn't proposed; the up-to-date one and the others stay")
        self.assertEqual([s.get("tag") for s in sources], ["v0.81", "20260125", "11.18", None])

    def test_nothing_is_proposed_without_a_stable_release(self):
        sources = self.sources()[:1]
        with mock.patch.object(update_components, "get_json", lambda url: [release("v0.81-rc1", prerelease=True), release("v0.82", draft=True)]):
            self.assertEqual(update_components.propose_newer(sources), [])
        self.assertEqual(sources[0]["tag"], "v0.80")

    def test_the_changes_in_words(self):
        before = [{"id": "dxmt", "version": "0.80", "sha256": "a"}, {"id": "winetricks", "version": "1", "sha256": "b"},
                  {"id": "old", "version": "9", "sha256": "c"}]
        after = [{"id": "dxmt", "version": "0.81", "sha256": "d"}, {"id": "winetricks", "version": "1", "sha256": "b"},
                 {"id": "d3dmetal", "version": "3.0", "sha256": "e"}]
        self.assertEqual(update_components.describe_changes(before, after),
                         ["dxmt: 0.80 -> 0.81", "d3dmetal: new, 3.0", "old: gone (was 9)"])

    def test_a_file_replaced_under_the_same_version_is_called_out(self):
        before = [{"id": "winetricks", "version": "20260125", "sha256": "a"}]
        after = [{"id": "winetricks", "version": "20260125", "sha256": "b"}]
        lines = update_components.describe_changes(before, after)
        self.assertEqual(len(lines), 1)
        self.assertIn("winetricks: 20260125 unchanged, but its file is a different one", lines[0])
        self.assertEqual(update_components.describe_changes(before, before), [])

    def test_a_proposing_run_writes_the_new_pin_and_a_plain_run_does_not(self):
        newest = release("v0.81", published="2026-06-02T00:00:00Z")
        newest["assets"] = [{"name": "dxmt-v0.81-builtin.tar.gz", "size": 7, "digest": "sha256:" + "ef" * 32,
                             "browser_download_url": "https://example.test/dxmt-v0.81-builtin.tar.gz"}]

        def get_json(url):
            if url.endswith("/releases/tags/v0.80") or url.endswith("/releases/tags/v0.81"):
                return newest if url.endswith("v0.81") else {**newest, "tag_name": "v0.80", "assets": [
                    {**newest["assets"][0], "name": "dxmt-v0.80-builtin.tar.gz", "browser_download_url": "https://example.test/dxmt-v0.80-builtin.tar.gz"}]}
            return [newest, release("v0.80")]

        with tempfile.TemporaryDirectory() as folder:
            sources, manifest = pathlib.Path(folder, "sources.json"), pathlib.Path(folder, "manifest.json")
            sources.write_text(json.dumps({"sources": [{"id": "dxmt", "kind": "graphics", "repo": "3Shain/dxmt", "tag": "v0.80", "propose": True,
                                                        "asset": r"^dxmt-v[0-9.]+-builtin\.tar\.gz$", "license": "LGPL-2.1-or-later"}]}, indent=2) + "\n")
            with mock.patch.object(update_components, "get_json", get_json), mock.patch.object(update_components, "SOURCES", sources), \
                    mock.patch.object(update_components, "MANIFEST", manifest):
                update_components.main([])
                self.assertEqual(json.loads(sources.read_text())["sources"][0]["tag"], "v0.80", "a plain run keeps the pin")
                self.assertEqual(json.loads(manifest.read_text())["components"][0]["version"], "0.80")
                update_components.main(["--propose"])
            self.assertEqual(json.loads(sources.read_text())["sources"][0]["tag"], "v0.81")
            self.assertEqual(json.loads(manifest.read_text())["components"][0]["version"], "0.81")


class WorkflowTests(unittest.TestCase):
    def test_the_nightly_run_proposes_and_never_pushes_to_main(self):
        workflow = (ROOT / ".github/workflows/components.yml").read_text()
        self.assertIn("update-components.py --propose", workflow)
        self.assertIn("gh pr create", workflow)
        self.assertIn("pull-requests: write", workflow)
        for line in workflow.splitlines():
            if re.match(r"\s*git push\b", line):
                self.assertRegex(line, r'origin "\$branch"', "a push goes to the bot's branch only: " + line)


if __name__ == "__main__":
    unittest.main()
