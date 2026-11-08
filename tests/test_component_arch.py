"""The optional "arch" of a component: scripts/update-components.py passes it on, scripts/validate-manifest.py
keeps an arm64 build away from older apps, which ignore the field and would take the build for theirs."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate = load("validate_manifest", "validate-manifest.py")
update = load("update_components", "update-components.py")

ENTRY = {"id": "wine", "kind": "engine", "version": "1", "url": "https://example.test/a.tar.gz", "sha256": "ab" * 32, "size": 1,
         "license": "MIT", "source": "https://example.test"}
SOURCE = {"id": "wine", "kind": "engine", "repo": "o/r", "tag": "v1", "asset": r"^a\.tar\.gz$", "license": "MIT"}
RELEASE = {"tag_name": "v1", "draft": False, "prerelease": False,
           "assets": [{"name": "a.tar.gz", "size": 1, "digest": "sha256:" + "ab" * 32, "browser_download_url": "https://example.test/a.tar.gz"}]}


class ValidateTests(unittest.TestCase):
    def check(self, *components):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "manifest.json"
            path.write_text(json.dumps({"schemaVersion": 1, "components": list(components)}))
            with mock.patch.object(validate, "MANIFEST", path):
                validate.main()

    def test_no_field_x86_and_universal_pass(self):
        self.check(ENTRY, {**ENTRY, "id": "a", "arch": "x86_64"}, {**ENTRY, "id": "b", "arch": "universal"})

    def test_an_arm64_build_under_its_own_id_passes(self):
        self.check(ENTRY, {**ENTRY, "id": "wine-arm64", "arch": "arm64"})

    def test_an_arm64_build_under_an_id_older_apps_know_is_refused(self):
        with self.assertRaises(SystemExit) as stop:
            self.check({**ENTRY, "arch": "arm64"})
        self.assertIn("-arm64", str(stop.exception))

    def test_an_unknown_processor_is_refused(self):
        with self.assertRaises(SystemExit):
            self.check({**ENTRY, "arch": "riscv"})

    def test_the_shipped_list_names_no_arch_yet(self):
        components = json.loads((ROOT / "components/manifest.json").read_text())["components"]
        self.assertEqual([c["id"] for c in components if "arch" in c], [])


class UpdateTests(unittest.TestCase):
    def test_arch_goes_from_the_source_to_the_component(self):
        with mock.patch.object(update, "get_json", lambda url: RELEASE):
            self.assertEqual(update.build({**SOURCE, "arch": "universal"})["arch"], "universal")

    def test_no_arch_in_the_source_means_none_in_the_component(self):
        with mock.patch.object(update, "get_json", lambda url: RELEASE):
            self.assertNotIn("arch", update.build(SOURCE))


if __name__ == "__main__":
    unittest.main()
