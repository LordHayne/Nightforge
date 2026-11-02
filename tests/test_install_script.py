"""scripts/install.sh updates Nightforge where it already is, in /Applications or ~/Applications, and a fresh Mac
gets it where it always did. Run against folders of its own: a stand-in for /Applications, a home, a local zip, and
an mdls that reads the "Last opened" date from a file in the app. A running Nightforge is never quit."""
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "install.sh"

MDLS = """#!/bin/bash
for last; do :; done
cat "$last/Contents/last-used" 2>/dev/null || printf '(null)'
"""


def app(folder, name="Nightforge.app", version="0.1", last_used=None):
    contents = folder / name / "Contents"
    contents.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))
    if last_used:
        (contents / "last-used").write_text(last_used)


def version(folder, name="Nightforge.app"):
    path = folder / name / "Contents" / "Info.plist"
    return plistlib.loads(path.read_bytes())["CFBundleShortVersionString"] if path.exists() else None


class InstallTargetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.applications = root / "Applications"
        self.applications.mkdir()
        self.home = root / "home"
        self.user_apps = self.home / "Applications"
        self.home.mkdir()
        self.bin = root / "bin"
        self.bin.mkdir()
        (self.bin / "mdls").write_text(MDLS)
        (self.bin / "mdls").chmod(0o755)
        release = root / "release"
        app(release, version="9.9")
        self.zip = root / "Nightforge.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(release / "Nightforge.app"), str(self.zip)], check=True)
        self.addCleanup(self.applications.chmod, 0o755)

    def install(self, **extra):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home), "TMPDIR": self.temp.name,
               "NIGHTFORGE_APPLICATIONS": str(self.applications), "NIGHTFORGE_ZIP": str(self.zip),
               "NIGHTFORGE_NO_QUIT": "1", "NIGHTFORGE_NO_OPEN": "1", **extra}
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_a_fresh_mac_gets_it_in_applications(self):
        self.install()
        self.assertEqual(version(self.applications), "9.9")
        self.assertFalse(self.user_apps.exists())

    def test_a_fresh_mac_without_write_access_to_applications_gets_it_in_the_home_folder(self):
        self.applications.chmod(0o555)
        self.install()
        self.assertEqual(version(self.user_apps), "9.9")

    def test_a_copy_in_the_home_folder_is_updated_there(self):
        app(self.user_apps)
        self.install()
        self.assertEqual(version(self.user_apps), "9.9")
        self.assertEqual(list(self.applications.iterdir()), [], "no second copy in /Applications")

    def test_a_copy_in_applications_is_updated_there(self):
        app(self.applications)
        self.install()
        self.assertEqual(version(self.applications), "9.9")
        self.assertFalse(self.user_apps.exists(), "no second copy in ~/Applications")

    def test_a_copy_in_applications_that_cant_be_replaced_doesnt_count(self):
        app(self.applications)
        self.applications.chmod(0o555)
        self.install()
        self.assertEqual(version(self.user_apps), "9.9")
        self.assertEqual(version(self.applications), "0.1")

    def test_with_two_copies_the_one_opened_last_is_updated(self):
        app(self.applications, last_used="2026-10-20 18:00:00 +0000")
        app(self.user_apps, last_used="2026-11-02 21:15:04 +0000")
        out = self.install()
        self.assertEqual(version(self.user_apps), "9.9")
        self.assertEqual(version(self.applications), "0.1", "the other copy stays as it was")
        self.assertIn(f"An older copy is still in {self.applications}", out)

    def test_with_two_copies_only_one_opened_that_one_is_updated(self):
        app(self.applications)
        app(self.user_apps, last_used="2026-10-20 18:00:00 +0000")
        self.install()
        self.assertEqual(version(self.user_apps), "9.9")
        self.assertEqual(version(self.applications), "0.1")

    def test_with_two_copies_never_opened_applications_wins(self):
        app(self.applications)
        app(self.user_apps)
        out = self.install()
        self.assertEqual(version(self.applications), "9.9")
        self.assertEqual(version(self.user_apps), "0.1")
        self.assertIn(f"An older copy is still in {self.user_apps}", out)

    def test_nachtschicht_in_the_home_folder_is_replaced_there(self):
        app(self.user_apps, name="Nachtschicht.app")
        self.install()
        self.assertEqual(version(self.user_apps), "9.9")
        self.assertFalse((self.user_apps / "Nachtschicht.app").exists(), "the old name goes")
        self.assertEqual(list(self.applications.iterdir()), [])

    def test_the_install_folder_set_for_testing_still_wins(self):
        app(self.user_apps)
        elsewhere = pathlib.Path(self.temp.name) / "elsewhere"
        self.install(NIGHTFORGE_INSTALL_DIR=str(elsewhere))
        self.assertEqual(version(elsewhere), "9.9")
        self.assertEqual(version(self.user_apps), "0.1")


if __name__ == "__main__":
    unittest.main()
