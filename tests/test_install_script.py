"""scripts/install.sh updates Nightforge where it already is, in /Applications or ~/Applications, and a fresh Mac
gets it where it always did, and it quits a running copy first. Run against folders of its own: a stand-in for
/Applications, a home, a local zip, an mdls that reads the "Last opened" date from a file in the app, and an osascript
whose running apps are files. A real Nightforge is never asked or quit."""
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

# osascript for `application id "…" is running` and `tell application id "…" to quit`, logged in $STATE/log. An app
# runs while $STATE/<id> exists. Told to quit, it ends at once, or after the number of looks in $STATE/<id>.looks,
# or never with $STATE/<id>.stays.
OSASCRIPT = """#!/bin/bash
script="$2"
id="$(printf '%s' "$script" | sed -n 's/.*application id "\\([^"]*\\)".*/\\1/p')"
app="$STATE/$id"
case "$script" in
  *"is running"*)
    echo "running? $id" >> "$STATE/log"
    if [ -f "$app.countdown" ]; then
      left=$(( $(cat "$app.countdown") - 1 ))
      if [ "$left" -le 0 ]; then rm -f "$app" "$app.countdown"; else echo "$left" > "$app.countdown"; fi
    fi
    if [ -f "$app" ]; then echo true; else echo false; fi ;;
  *"to quit"*)
    echo "quit $id" >> "$STATE/log"
    if [ -f "$app.stays" ]; then :; elif [ -f "$app.looks" ]; then cp "$app.looks" "$app.countdown"; else rm -f "$app"; fi ;;
esac
"""

# What the review found: a tail, grep or debugger with the app's path in its arguments matches pgrep -f.
PGREP = """#!/bin/bash
echo "pgrep $*" >> "$STATE/log"
exit 0
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


class Folders(unittest.TestCase):
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
        self.state = root / "state"
        self.state.mkdir()
        for name, body in (("mdls", MDLS), ("osascript", OSASCRIPT), ("pgrep", PGREP)):
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)
        release = root / "release"
        app(release, version="9.9")
        self.zip = root / "Nightforge.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(release / "Nightforge.app"), str(self.zip)], check=True)
        self.addCleanup(self.applications.chmod, 0o755)

    def run_install(self, quit=False, **extra):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home), "TMPDIR": self.temp.name,
               "NIGHTFORGE_APPLICATIONS": str(self.applications), "NIGHTFORGE_ZIP": str(self.zip),
               "NIGHTFORGE_NO_OPEN": "1", "STATE": str(self.state), **extra}
        if not quit:
            env["NIGHTFORGE_NO_QUIT"] = "1"
        return subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)

    def install(self, **extra):
        result = self.run_install(**extra)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def log(self):
        path = self.state / "log"
        return path.read_text().splitlines() if path.exists() else []


class InstallTargetTests(Folders):
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


class QuitTests(Folders):
    """A running copy is quit before its bundle is replaced, and only one that really runs."""

    NIGHTFORGE = "io.github.lordhayne.nightforge"

    def running(self, bundle_id, looks=None, stays=False):
        (self.state / bundle_id).touch()
        if looks:
            (self.state / f"{bundle_id}.looks").write_text(str(looks))
        if stays:
            (self.state / f"{bundle_id}.stays").touch()

    def test_a_path_in_another_programs_arguments_isnt_the_app(self):
        app(self.applications)
        self.install(quit=True)
        self.assertEqual(version(self.applications), "9.9")
        self.assertFalse([line for line in self.log() if line.startswith(("quit", "pgrep"))],
                         "nothing is told to quit (AppleScript would start it), and pgrep isn't asked")

    def test_a_running_nightforge_is_quit_and_waited_for(self):
        app(self.applications)
        self.running(self.NIGHTFORGE, looks=3)
        self.install(quit=True)
        self.assertEqual(version(self.applications), "9.9")
        log = self.log()
        self.assertEqual(log.count(f"quit {self.NIGHTFORGE}"), 1)
        after = log[log.index(f"quit {self.NIGHTFORGE}") + 1:]
        self.assertGreaterEqual(after.count(f"running? {self.NIGHTFORGE}"), 3, "it waits until the app has ended")
        self.assertFalse((self.state / self.NIGHTFORGE).exists())

    def test_one_that_doesnt_quit_stops_the_install_with_nothing_replaced(self):
        app(self.applications)
        self.running(self.NIGHTFORGE, stays=True)
        result = self.run_install(quit=True, NIGHTFORGE_QUIT_WAIT="2")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Nightforge didn't quit", result.stderr)
        self.assertEqual(version(self.applications), "0.1", "the running copy is still there, as it was")

    def test_a_running_nachtschicht_is_quit_too_and_replaced(self):
        app(self.user_apps, name="Nachtschicht.app")
        self.running("local.thomas.nachtschicht")
        self.install(quit=True)
        self.assertIn("quit local.thomas.nachtschicht", self.log())
        self.assertNotIn(f"quit {self.NIGHTFORGE}", self.log(), "Nightforge didn't run")
        self.assertFalse((self.user_apps / "Nachtschicht.app").exists())
        self.assertEqual(version(self.user_apps), "9.9")
