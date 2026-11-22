"""The built app lies in a folder Spotlight leaves out, so a test build never shows in Spotlight or Launchpad
and `open -b` doesn't pick it (22.11.2026: three Nightforges to choose from). Everything that takes the built
app from build.sh looks for it there."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = "build/Nightforge.noindex/Nightforge.app"


class BuildHiddenTests(unittest.TestCase):
    def test_build_sh_builds_into_a_noindex_folder(self):
        text = (ROOT / "build.sh").read_text()
        out = re.search(r'^OUT="([^"]+)"', text, re.M).group(1)
        self.assertEqual(out, "build/Nightforge.noindex/$APP.app")
        self.assertTrue(pathlib.PurePosixPath(out).parent.name.endswith(".noindex"))

    def test_build_sh_forgets_the_build_at_launchservices(self):
        text = (ROOT / "build.sh").read_text()
        self.assertIn('"$LSREGISTER" -u "$PWD/$OUT"', text)
        self.assertIn('"$LSREGISTER" -u "$PWD/build/$APP.app"', text, "the old place is forgotten, not deleted")
        self.assertNotIn('rm -rf "build/$APP.app"', text)

    def test_install_copies_from_there(self):
        text = (ROOT / "build.sh").read_text()
        self.assertIn('cp -R "$OUT" "$HOME/Applications/"', text)

    def test_release_and_dmg_take_it_from_there(self):
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn(f"app={APP}", release)
        self.assertIn(f"strings -a {APP}/Contents/MacOS/Nightforge", release)
        dmg = (ROOT / "scripts/dmg-settings.py").read_text()
        self.assertIn(f'defines.get("app", "{APP}")', dmg)

    def test_no_script_looks_in_the_old_place(self):
        old = re.compile(r"build/Nightforge\.app")
        places = [ROOT / "build.sh", *(ROOT / "scripts").rglob("*.sh"), *(ROOT / "scripts").rglob("*.py"),
                  *(ROOT / ".github/workflows").glob("*.yml"), *(ROOT / "tests").glob("*/run.sh"),
                  ROOT / "tests/kosmickrisp/stage-live-test.sh"]
        stale = [str(p.relative_to(ROOT)) for p in places if p.is_file() and old.search(p.read_text(errors="ignore"))]
        self.assertEqual(stale, [])

    def test_the_detached_test_makes_its_helper_app_out_of_sight(self):
        text = (ROOT / "tests/DetachedProcessTest/main.swift").read_text()
        self.assertIn('"build/tests.noindex/detached-test-', text)
        self.assertIn('forget.arguments = ["-u", app.path]', text)


if __name__ == "__main__":
    unittest.main()
