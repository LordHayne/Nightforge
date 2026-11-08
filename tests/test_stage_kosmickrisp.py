"""tests/kosmickrisp/stage-live-test.sh, on a stand-in app and in a home of its own: since the component lists are signed
it has to name KosmicKrisp in the test build's own list, with a stamp newer than the list kept on the Mac, and keep that
build from asking online. --undo puts everything back."""
import calendar
import hashlib
import json
import os
import pathlib
import plistlib
import stat
import subprocess
import tarfile
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tests/kosmickrisp/stage-live-test.sh"
URL = "https://example.invalid/manifest.json"
VERSION = "27.0.0-test"


class StageLiveTestTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name).resolve()
        self.home = self.root / "home"
        self.components = self.home / "Library/Application Support/Nightforge/Components"
        self.components.mkdir(parents=True)
        self.app = self.make_app(self.root / "build/Nightforge.app")
        self.archive = self.root / f"nightforge-kosmickrisp-{VERSION}.tar.gz"
        driver = self.root / f"nightforge-kosmickrisp-{VERSION}/libvulkan.1.dylib"
        driver.parent.mkdir()
        driver.write_bytes(b"loader")
        with tarfile.open(self.archive, "w:gz") as archive:
            archive.add(driver.parent, arcname=driver.parent.name)
        # codesign is the one tool the stand-in app can't go through.
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.signed = self.root / "signed.txt"
        codesign = self.tools / "codesign"
        codesign.write_text(f'#!/bin/sh\necho "$@" >> "{self.signed}"\n')
        codesign.chmod(codesign.stat().st_mode | stat.S_IEXEC)

    def make_app(self, app):
        (app / "Contents/Resources").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"NightforgeManifestURL": URL}))
        (app / "Contents/Resources/manifest.json").write_text(json.dumps({
            "generated": "2026-11-05T21:26:18Z",
            "components": [{"id": "winecx", "version": "4.7.3"}, {"id": "dxvk", "version": "3.1.1"}],
        }))
        return app

    def run_script(self, *arguments):
        env = dict(os.environ, HOME=str(self.home), NIGHTFORGE_AD_HOC="1", PATH=f"{self.tools}:{os.environ['PATH']}")
        return subprocess.run(["bash", str(SCRIPT), *arguments], env=env, capture_output=True, text=True)

    def stage(self):
        result = self.run_script(str(self.archive), str(self.app))
        self.assertEqual(result.returncode, 0, result.stderr)

    def manifest(self):
        return json.loads((self.app / "Contents/Resources/manifest.json").read_text())

    def manifest_url(self):
        return plistlib.loads((self.app / "Contents/Info.plist").read_bytes())["NightforgeManifestURL"]

    def test_the_build_is_in_place_as_if_downloaded(self):
        self.stage()
        folder = self.components / f"kosmickrisp/{VERSION}"
        self.assertTrue((folder / f"nightforge-kosmickrisp-{VERSION}/libvulkan.1.dylib").is_file())
        self.assertEqual((folder / ".sha256").read_text(), hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                         "without a line break, as ComponentStore.installedPath compares it")

    def test_the_test_builds_own_list_names_it(self):
        self.stage()
        manifest = self.manifest()
        entry = next(c for c in manifest["components"] if c["id"] == "kosmickrisp")
        self.assertEqual(entry["version"], VERSION)
        self.assertEqual(entry["sha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        self.assertEqual(entry["size"], self.archive.stat().st_size)
        self.assertEqual([c["id"] for c in manifest["components"]], ["winecx", "dxvk", "kosmickrisp"])

    def test_its_stamp_beats_the_signed_list_kept_on_the_mac(self):
        before = time.time() - 2
        self.stage()
        stamp = calendar.timegm(time.strptime(self.manifest()["generated"], "%Y-%m-%dT%H:%M:%SZ"))
        self.assertGreaterEqual(stamp, before)
        self.assertLessEqual(stamp, time.time() + 2, "no stamp from the future: SignedLists ignores those")

    def test_the_build_doesnt_ask_online_and_is_signed_again(self):
        self.stage()
        self.assertEqual(self.manifest_url(), "")
        self.assertIn(str(self.app), self.signed.read_text())

    def test_upstream_dxvk_is_added_when_the_list_lacks_it(self):
        path = self.app / "Contents/Resources/manifest.json"
        manifest = json.loads(path.read_text())
        manifest["components"] = [c for c in manifest["components"] if c["id"] != "dxvk"]
        path.write_text(json.dumps(manifest))
        self.stage()
        self.assertIn("dxvk", [c["id"] for c in self.manifest()["components"]])

    def test_undo_puts_everything_back(self):
        original = (self.app / "Contents/Resources/manifest.json").read_bytes()
        self.stage()
        self.stage()  # staged twice: the backup stays the original
        result = self.run_script("--undo", str(self.app))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.components / "kosmickrisp").exists())
        self.assertEqual((self.app / "Contents/Resources/manifest.json").read_bytes(), original)
        self.assertEqual(self.manifest_url(), URL)
        self.assertFalse(pathlib.Path(f"{self.app}.before-kosmickrisp").exists())

    def test_undo_without_the_test_build_still_removes_kosmickrisp(self):
        self.stage()
        result = self.run_script("--undo", str(self.root / "gone/Nightforge.app"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.components / "kosmickrisp").exists())

    def test_an_installed_nightforge_is_refused(self):
        app = self.make_app(self.home / "Applications/Nightforge.app")
        before = (app / "Contents/Resources/manifest.json").read_bytes()
        result = self.run_script(str(self.archive), str(app))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("installed Nightforge", result.stderr)
        self.assertEqual((app / "Contents/Resources/manifest.json").read_bytes(), before)
        self.assertFalse((self.components / "kosmickrisp").exists())

    def test_another_archive_is_refused(self):
        other = self.root / "something-else.tar.gz"
        other.write_bytes(self.archive.read_bytes())
        result = self.run_script(str(other), str(self.app))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.components / "kosmickrisp").exists())


if __name__ == "__main__":
    unittest.main()
