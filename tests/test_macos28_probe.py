"""tests/arm64/macos28-probe.sh, against stand-ins for macOS's tools: reports what it finds, stops before macOS 28, and
never calls `game-test-tool` (its "enable" switches Rosetta off)."""
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tests/arm64/macos28-probe.sh"


class ProbeTests(unittest.TestCase):
    def run_probe(self, version="28.0", translates=True, wine=None):
        with tempfile.TemporaryDirectory() as folder:
            tools = pathlib.Path(folder) / "tools"
            tools.mkdir()
            calls = pathlib.Path(folder) / "calls"

            def tool(name, body):
                path = tools / name
                path.write_text("#!/bin/bash\n" + body + "\n")
                path.chmod(path.stat().st_mode | stat.S_IXUSR)

            tool("sw_vers", f'[ "$1" = -productVersion ] && echo {version} || echo 28A1')
            tool("lipo", "echo arm64e")
            tool("game-test-tool", f'echo "$@" >> "{calls}"')
            tool("arch", ('shift; exec "$@"' if translates else "exit 1"))
            arguments = []
            if wine is not None:
                tool("wine", wine)
                arguments = [str(tools / "wine")]
            done = subprocess.run(["bash", str(SCRIPT), *arguments], capture_output=True, text=True,
                                  env={"PATH": f"{tools}:/usr/bin:/bin", "HOME": folder})
            return done, (calls.read_text() if calls.exists() else "")

    def test_it_stops_before_macos_28(self):
        done, _ = self.run_probe(version="27.0.1")
        self.assertEqual(done.returncode, 2)
        self.assertEqual(done.stdout, "")

    def test_it_says_whether_x86_64_runs(self):
        self.assertIn("runs", self.run_probe()[0].stdout.splitlines()[1])
        self.assertIn("does not run", self.run_probe(translates=False)[0].stdout)

    def test_it_shows_what_true_is_built_for(self):
        self.assertIn("/usr/bin/true is built for: arm64e", self.run_probe()[0].stdout)

    def test_wine_gets_an_empty_prefix_and_only_prints_its_version(self):
        done, _ = self.run_probe(wine='[ -d "$WINEPREFIX" ] && [ -z "$(ls -A "$WINEPREFIX")" ] && echo "wine-1 $1"')
        self.assertIn("wine: wine-1 --version", done.stdout)

    def test_wine_that_fails_is_reported(self):
        self.assertIn("wine: does not start: Bad CPU", self.run_probe(wine="echo Bad CPU; exit 86")[0].stdout)

    def test_game_test_tool_is_never_run(self):
        done, calls = self.run_probe()
        self.assertIn("game-test-tool: ", done.stdout)
        self.assertEqual(calls, "")


if __name__ == "__main__":
    unittest.main()
