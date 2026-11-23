// A test program with the Mac's real home finds and reaches none of the player's Wine session (TestGuard). It only
// reads, and builds a Wine process without starting it; stopAll and the quit script are checked by their condition,
// never called: tests/TestGuardTest/run.sh
import Foundation

@main
struct TestGuardTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()  // settings in the test's folder; the home stays the real one on purpose
        // The rule.
        check(TestGuard.isTestWithRealHome(bundleID: nil, home: "/Users/jane", account: "/Users/jane"), "a test with the real home: guarded")
        check(TestGuard.isTestWithRealHome(bundleID: nil, home: "/Users/jane/", account: "/Users/jane"), "…a slash more or less")
        check(!TestGuard.isTestWithRealHome(bundleID: "io.github.lordhayne.nightforge", home: "/Users/jane", account: "/Users/jane"),
              "Nightforge itself: never")
        check(!TestGuard.isTestWithRealHome(bundleID: nil, home: "/private/var/folders/x/T/tmp.1/home", account: "/Users/jane"),
              "a test with a home of its own: its own data folder, nothing to guard")
        check(!TestGuard.isTestWithRealHome(bundleID: nil, home: "/Users/jane", account: ""), "no account home known: not guessed")
        check(TestGuard.lies("/a/b/Nightforge/Components/x", in: "/a/b/Nightforge") && TestGuard.lies("/a/b/Nightforge", in: "/a/b/Nightforge/")
              && !TestGuard.lies("/a/b/Nightforge Games/x", in: "/a/b/Nightforge"), "inside the data folder, not a sibling of the same start")

        // This program: no bundle, the real home.
        check(TestGuard.realHome, "this test runs with the real home, as most series do")
        let support = Engine.supportDir
        check(TestGuard.keepsOut(support.appendingPathComponent("Components/winecx/4.7.3/Libraries/Wine/bin/wine").path),
              "the data folder's Wine is kept out")
        check(!TestGuard.keepsOut("/nonexistent/bin/wine") && !TestGuard.keepsOut(FileManager.default.temporaryDirectory.path),
              "a stand-in's path isn't")

        // The player's session, whether or not it runs right now: not found.
        check(Engine.ownProcesses().isEmpty, "Nightforge's own processes: none")
        check(Engine.ownProcessesKnown()?.isEmpty != false, "…none known either")
        check(Engine.sessionWine() == nil, "no session's Wine")
        check(Engine.steamRunningKnown != true && Engine.windowsGameRunningKnown != true, "no Steam, no game of the player's")

        // No Wine program from the data folder starts: refused before anything is built to run.
        let wine = support.appendingPathComponent("Components/winecx/4.7.3/Libraries/Wine/bin/wine")
        do {
            _ = try WineSandbox.process(wine, ["regedit", "/S", "nothing.reg"])
            check(false, "a Wine program from the data folder was built to run")
        } catch is TestGuard.KeptOut {
        } catch {
            check(false, "refused, but not by TestGuard: \(error)")
        }

        // stopAll and the quit script: by their condition only (never called here).
        check(TestGuard.keepsOut(wine.path), "stopAll with the data folder's Wine returns before `wineserver -k`")
        check(TestGuard.keepsOut(support.path), "scheduleSteamShutdown hands no script over")
        check(TestGuard.keepsOut(DetachedProcess.home.path), "the data folder's helper app isn't used")

        print(failures == 0 ? "✓ TestGuard" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
