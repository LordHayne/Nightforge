"""An optional component (D3DMetal, pinned to a release that may not exist yet) stays out of the
list instead of stopping the nightly run for every other component."""
import importlib.util
import io
import pathlib
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


if __name__ == "__main__":
    unittest.main()
