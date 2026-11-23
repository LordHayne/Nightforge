"""No test series reaches the player's Wine session (23.11.2026). Most series run with the Mac's real home, where
Nightforge's data folder is the real one; Steam and its session run there. Two layers keep them out:

- TestGuard in the app's code: a program without a bundle (every test) with the real home finds no processes of
  Nightforge's, starts no Wine program from the data folder, ends no session, hands no quit script over. Checked here
  that each place still asks it.
- Here: a series without a home of its own (no HOME= in its run.sh) calls none of Engine's steps that act on a session,
  and the stoppers only with a stand-in for each part they'd otherwise ask the real Mac.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources/Nightforge"
# Steps that act on a session or start a Wine program, whatever they're handed.
ACTING = ["Engine.stopAll(", "Engine.startSteam(", "startSteamOffMain(", "restartSteamInBackground(", "ensureSteamRunning(",
          "Engine.run(", "installWinetricks(", "scheduleSteamShutdown(", "killLeftovers(", "DockHider.restartSteam(",
          "applySessionSettings(", "applyMsyncMode(", "applyRetinaMode(", "Engine.importRegistry(", "restartHungSteam("]
# Steps that are safe only with their stand-in handed in: (call, the parameter that must be there).
NEEDS_STAND_IN = [("Engine.stopSteam(", "running:"), ("hardStopSteam(", "stop:"), ("waitForSteamToEnd(", "leftovers:"),
                  ("applyLibraryVersion(", "session:")]


def code(text):
    """Swift without comments and without string literals: a test that reads the sources as text names steps it never calls."""
    text = re.sub(r'#"(?:[^"]|"(?!#))*"#', '""', text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return "\n".join(line.split("//", 1)[0] for line in text.split("\n"))


def call(text, start):
    """The call from `start` to its closing parenthesis."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    return text[start:]


class TestsReachNoSessionTests(unittest.TestCase):
    def test_the_guard_is_asked_where_a_session_is_reached(self):
        engine = code((SOURCES / "Engine.swift").read_text())
        self.assertRegex(engine, r"func own\(in table[^{]*\{\s*[^}]*TestGuard\.keepsOut\(folder\.path\)")
        self.assertRegex(engine, r"static func stopAll\([^{]*\{[^}]*TestGuard\.keepsOut\(wine\.path\)")
        self.assertRegex(engine, r"static func scheduleSteamShutdown\([^{]*\{\s*guard !TestGuard\.keepsOut\(supportDir\.path\)")
        sandbox = code((SOURCES / "WineSandbox.swift").read_text())
        self.assertRegex(sandbox, r"static func process\(_ executable[^{]*\{\s*[^}]*TestGuard\.keepsOut\(executable\.path\)")
        detached = code((SOURCES / "Detached.swift").read_text())
        self.assertRegex(detached, r"static func helperApp\(\)[^{]*\{\s*[^}]*TestGuard\.keepsOut\(home\.path\)")
        guard = code((SOURCES / "TestGuard.swift").read_text())
        self.assertIn("bundleID == nil", guard)

    def test_series_with_the_real_home_act_on_no_session(self):
        wrong = []
        for series in sorted((ROOT / "tests").glob("*Test")):
            run, main = series / "run.sh", series / "main.swift"
            if not run.exists() or not main.exists() or re.search(r"\bHOME=", run.read_text()):
                continue
            text = code(main.read_text())
            for step in ACTING:
                if step in text:
                    wrong.append(f"{series.name}: {step}")
            for step, stand_in in NEEDS_STAND_IN:
                for found in re.finditer(re.escape(step), text):
                    if stand_in not in call(text, found.start()):
                        wrong.append(f"{series.name}: {step} without {stand_in}")
        self.assertEqual(wrong, [], "give the series a home of its own (HOME= in run.sh), or hand in a stand-in")

    def test_the_guard_series_keeps_the_real_home(self):
        run = (ROOT / "tests/TestGuardTest/run.sh").read_text()
        self.assertNotRegex(run, r"\bHOME=", "TestGuardTest checks the real-home case: it must run in it")


if __name__ == "__main__":
    unittest.main()
