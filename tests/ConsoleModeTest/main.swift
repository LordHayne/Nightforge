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
        // Audit K1: a beat without a key window (going into full screen) only skips that beat; the watch ends only when the
        // mode is off, a game runs or Nightforge is behind.
        check(ConsoleMode.focusLook(consoleMode: true, inFront: true, gameOn: false, keyWindow: true) == .look, "a key window: the look")
        check(ConsoleMode.focusLook(consoleMode: true, inFront: true, gameOn: false, keyWindow: false) == .skip,
              "no key window for a moment: this look skipped, the watch goes on")
        check(ConsoleMode.focusLook(consoleMode: false, inFront: true, gameOn: false, keyWindow: true) == .end, "the mode off: the watch ends")
        check(ConsoleMode.focusLook(consoleMode: true, inFront: true, gameOn: true, keyWindow: true) == .end, "a game on: it ends")
        check(ConsoleMode.focusLook(consoleMode: true, inFront: false, gameOn: false, keyWindow: false) == .end, "Nightforge behind: it ends")
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(model.contains("case .skip: continue") && model.contains("guard let key = NSApp.keyWindow else { continue }")
              && !model.contains("let key = NSApp.keyWindow else { return }"), "the watch skips a look, it doesn't end on it")
        // The request is noted as asked once it's answered, not when it shows: closed by a quit, it comes again.
        if let offer = model.range(of: "private func offerConsoleModeIfDue() {"),
           let next = model.range(of: "func askForHomeButton()", range: offer.upperBound..<model.endIndex) {
            check(!model[offer.upperBound..<next.lowerBound].contains("ConsoleMode.askedKey"), "showing the request notes nothing")
        } else {
            check(false, "offerConsoleModeIfDue is found")
        }
        if let decline = model.range(of: "func declineConsoleMode() {"),
           let end = model.range(of: "GameLog.note(\"Console mode: not now\")", range: decline.upperBound..<model.endIndex) {
            check(model[decline.upperBound..<end.lowerBound].contains("ConsoleMode.askedKey"), "Not Now notes it")
        } else {
            check(false, "declineConsoleMode is found")
        }
        if let set = model.range(of: "func setConsoleMode(_ on: Bool, by: String) {"),
           let after = model.range(of: "ConsoleMode.askedKey", range: set.upperBound..<model.endIndex) {
            check(model.distance(from: set.upperBound, to: after.lowerBound) < 400, "switching the mode (the request's yes) notes it")
        } else {
            check(false, "setConsoleMode notes it")
        }

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
