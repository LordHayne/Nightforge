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

        // Kept in the defaults: on across restarts, asked once.
        let suite = "ConsoleModeTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return print("✗ no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        check(!ConsoleMode.isOn(defaults) && !ConsoleMode.asked(defaults), "a new Mac: off, never asked")
        defaults.set(true, forKey: ConsoleMode.onKey)
        defaults.set(true, forKey: ConsoleMode.askedKey)
        check(ConsoleMode.isOn(defaults) && ConsoleMode.asked(defaults), "on and asked, as kept")
        check(ConsoleMode.askedKey != ConsoleMode.onKey, "two keys of their own")

        print(failures == 0 ? "✓ ConsoleMode" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
