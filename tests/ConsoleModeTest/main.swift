// Checks console mode's rules (ConsoleMode): tests/ConsoleModeTest/run.sh
import Foundation

@main
struct ConsoleModeTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        func offers(asked: Bool = false, on: Bool = false, pad: Bool = true, inFront: Bool = true, firstStart: Bool = false,
                    gameOn: Bool = false, open: Bool = false) -> Bool {
            ConsoleMode.offers(asked: asked, on: on, padConnected: pad, inFront: inFront, firstStart: firstStart, gameOn: gameOn,
                               somethingOpen: open)
        }
        // When the request comes: once overall, as soon as a controller is connected.
        check(offers(), "a controller connected, Nightforge in front: the request")
        check(!offers(asked: true), "asked once, answered either way: never again by itself")
        check(!offers(on: true), "console mode on already: nothing to ask")
        check(!offers(pad: false), "without a controller: no request, mouse and keyboard see nothing of it")
        check(!offers(inFront: false), "not from the background")
        check(!offers(firstStart: true), "not in the middle of the first start's setup, right after it")
        check(!offers(gameOn: true), "not with a game on")
        check(!offers(open: true), "not over a sheet, a menu or the keyboard")

        // The ways out.
        check(!ConsoleMode.escLeavesFullScreen(consoleMode: true) && ConsoleMode.escLeavesFullScreen(consoleMode: false),
              "Esc at the top never ends console mode; outside it, it leaves full screen as before")
        check(ConsoleMode.toggleEndsConsoleMode(consoleMode: true) && !ConsoleMode.toggleEndsConsoleMode(consoleMode: false),
              "⌃⌘F in console mode ends console mode, outside it only switches full screen")

        // Screens.
        check(!ConsoleMode.leavesFullScreenOffTV(consoleMode: true, wouldLeave: true),
              "a TV unplugged in console mode: full screen stays, on the Mac's screen")
        check(ConsoleMode.leavesFullScreenOffTV(consoleMode: false, wouldLeave: true)
              && !ConsoleMode.leavesFullScreenOffTV(consoleMode: false, wouldLeave: false), "outside it: today's rule")
        check(ConsoleMode.wantsFullScreen(consoleMode: true, fullScreen: false), "console mode, in a window: full screen")
        check(!ConsoleMode.wantsFullScreen(consoleMode: true, fullScreen: true) && !ConsoleMode.wantsFullScreen(consoleMode: false, fullScreen: false),
              "full screen already, or no console mode: nothing to do")

        // The highlight at once in console mode, where it's the pad's only mark (23.11.2026).
        func place(on: Bool = true, focused: Bool = false, dialog: Bool = false, panel: Bool = false, gameOn: Bool = false) -> ConsoleMode.FocusPlace {
            ConsoleMode.focusPlace(consoleMode: on, focused: focused, dialogInFront: dialog, panelOpen: panel, gameOn: gameOn)
        }
        check(place(dialog: true) == .dialog, "a dialog or sheet in front: its highlight stands before any press")
        check(place(panel: true) == .panel, "the small menu, the quick menu, a game's options: theirs too")
        check(place(dialog: true, panel: true) == .dialog, "a dialog over an open panel: the dialog, which has the keys")
        check(place() == .none, "the library and Home: the selected game is the pad's mark, no ring on a button")
        check(place(on: false, dialog: true) == .none && place(on: false, panel: true) == .none,
              "outside console mode: as before, once the pad moved")
        check(place(focused: true, dialog: true) == .none, "one stands already: left where the player put it")
        check(place(dialog: true, gameOn: true) == .none, "a game on: the pad is the game's")
        check(ConsoleMode.focusLook <= 0.5, "a dialog shows its highlight within half a second")
        // The look's beat only where it's needed (E1).
        check(ConsoleMode.focusWatchRuns(consoleMode: true, inFront: true, gameOn: false), "console mode, Nightforge in front: the beat runs")
        check(!ConsoleMode.focusWatchRuns(consoleMode: true, inFront: true, gameOn: true), "a game on: no beat")
        check(!ConsoleMode.focusWatchRuns(consoleMode: true, inFront: false, gameOn: false), "another app in front: no beat")
        check(!ConsoleMode.focusWatchRuns(consoleMode: false, inFront: true, gameOn: false), "outside console mode: none at all")

        // Kept in the defaults: on across restarts, asked once.
        // In the test's own folder, which run.sh removes: a named domain stays in ~/Library/Preferences for good (23.11.2026).
        let defaults = TestDefaults.suite("console-mode")
        check(!ConsoleMode.isOn(defaults) && !ConsoleMode.asked(defaults), "a new Mac: off, never asked")
        defaults.set(true, forKey: ConsoleMode.onKey)
        defaults.set(true, forKey: ConsoleMode.askedKey)
        check(ConsoleMode.isOn(defaults) && ConsoleMode.asked(defaults), "on and asked, as kept")
        check(ConsoleMode.askedKey != ConsoleMode.onKey, "two keys of their own")

        print(failures == 0 ? "✓ ConsoleMode" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
