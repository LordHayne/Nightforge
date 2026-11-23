// Checks the Dock's setting in console mode (DockAutoHide): tests/DockAutoHideTest/run.sh
// Only a stand-in for the Mac's setting and a defaults suite of its own: nothing on this Mac changes.
import Foundation

@main
struct DockAutoHideTest {
    /// The Mac's setting as the stand-in has it, and what was done to it.
    final class Mac {
        var autohide: Bool?
        var writes: [Bool] = []
        var restarts = 0
        init(_ autohide: Bool?) { self.autohide = autohide }
        var system: DockAutoHide.System {
            DockAutoHide.System(read: { self.autohide },
                                write: { self.autohide = $0; self.writes.append($0) },
                                restartDock: { self.restarts += 1 })
        }
    }

    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        // In the test's own folder, which run.sh removes: a named domain stays in ~/Library/Preferences for good (23.11.2026).
        let defaults = TestDefaults.suite("dock")

        // Shown (never set, or set to shown): switched on, the value before kept first, put back afterwards.
        for before in [nil, false] as [Bool?] {
            let mac = Mac(before)
            check(DockAutoHide.engage(mac.system, defaults: defaults) == .set && mac.autohide == true && mac.restarts == 1,
                  "shown (\(String(describing: before))): hides itself from the first game on, the Dock restarted to read it")
            check(defaults.object(forKey: DockAutoHide.restoreKey) as? Bool == false, "what to put back is kept")
            check(DockAutoHide.engage(mac.system, defaults: defaults) == .oursAlready && mac.writes == [true] && mac.restarts == 1,
                  "the next game: nothing again, no second restart of the Dock")
            check(DockAutoHide.restore(mac.system, defaults: defaults) == .putBack && mac.autohide == false && mac.restarts == 2,
                  "console mode over: shown again")
            check(defaults.object(forKey: DockAutoHide.restoreKey) == nil, "nothing left to put back")
            check(DockAutoHide.restore(mac.system, defaults: defaults) == .nothing && mac.writes == [true, false] && mac.restarts == 2,
                  "a second restore does nothing")
        }

        // The player's own setting: never touched, never put back.
        let players = Mac(true)
        check(DockAutoHide.engage(players.system, defaults: defaults) == .playersAlready && players.writes.isEmpty && players.restarts == 0,
              "hides itself already: left alone")
        check(defaults.object(forKey: DockAutoHide.restoreKey) == nil
              && DockAutoHide.restore(players.system, defaults: defaults) == .nothing && players.autohide == true,
              "and not switched off afterwards")

        // A crash: the next start finds what to put back (App.applicationDidFinishLaunching).
        let crashed = Mac(false)
        _ = DockAutoHide.engage(crashed.system, defaults: defaults)
        let nextStart = Mac(crashed.autohide)  // the same Mac, Nightforge started anew
        check(DockAutoHide.restore(nextStart.system, defaults: defaults) == .putBack && nextStart.autohide == false,
              "after a crash: put back at the next start")

        // Written before the change: a crash between the two still knows what to put back.
        let midway = Mac(false)
        var keptBeforeWrite = false
        let watching = DockAutoHide.System(read: { midway.autohide },
                                           write: { _ in keptBeforeWrite = defaults.object(forKey: DockAutoHide.restoreKey) != nil },
                                           restartDock: {})
        _ = DockAutoHide.engage(watching, defaults: defaults)
        check(keptBeforeWrite, "what to put back is kept before the setting changes")
        defaults.removeObject(forKey: DockAutoHide.restoreKey)

        // The player switched it off meanwhile: nothing to put back, the note goes.
        let changed = Mac(false)
        _ = DockAutoHide.engage(changed.system, defaults: defaults)
        changed.autohide = false
        check(DockAutoHide.restore(changed.system, defaults: defaults) == .playerChanged && changed.writes == [true] && changed.restarts == 1
              && defaults.object(forKey: DockAutoHide.restoreKey) == nil, "the player's change meanwhile wins")

        // The Dock restarts only where the value changed, each time with its line in the log.
        for mac in [players, crashed, nextStart, changed] {
            check(mac.restarts == mac.writes.count, "a restart of the Dock only with a change of the setting")
        }
        check(DockAutoHide.Outcome.set.logLine?.contains("killall Dock") == true && DockAutoHide.Outcome.putBack.logLine?.contains("killall Dock") == true
              && DockAutoHide.Outcome.playersAlready.logLine?.contains("killall") == false
              && DockAutoHide.Outcome.playerChanged.logLine?.contains("killall") == false, "each restart of the Dock in the log, no other")
        // A line in the log when something happens, none when nothing does.
        check(DockAutoHide.Outcome.set.logLine != nil && DockAutoHide.Outcome.putBack.logLine != nil
              && DockAutoHide.Outcome.playersAlready.logLine != nil && DockAutoHide.Outcome.playerChanged.logLine != nil
              && DockAutoHide.Outcome.nothing.logLine == nil && DockAutoHide.Outcome.oursAlready.logLine == nil, "the log lines")

        print(failures == 0 ? "✓ DockAutoHide" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
