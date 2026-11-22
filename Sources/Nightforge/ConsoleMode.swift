import Foundation

/// Console mode (0.4 "like a console", the user's choice of 22.11.2026: variant A, the glass question): one switch for
/// playing with the controller. Nightforge fills the screen on whatever screen it is on, and the Dock stays out of
/// sight while games are played (DockAutoHide). It's asked for once, as soon as a controller is connected, in place of
/// the old "Full screen for the controller?"; draft docs/ENTWURF-KONSOLENMODUS.md.
///
/// The rules here; the switching itself is LibraryModel.setConsoleMode, the request LibraryView's sheet.
enum ConsoleMode {
    /// On: kept across Nightforge's and the Mac's restarts.
    static let onKey = "console.modeOn"
    /// The request came once, answered either way: Nightforge doesn't ask again by itself.
    static let askedKey = "console.modeAsked"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: onKey) }
    static func asked(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: askedKey) }

    /// Whether the request comes now: never asked before, the mode off, a controller connected, Nightforge in front, the
    /// first start's setup over, no game, nothing open (a sheet, a menu, the keyboard). Any screen counts, a TV too –
    /// the old request came only on the MacBook's own. Someone who chose full screen before is asked once as well.
    static func offers(asked: Bool, on: Bool, padConnected: Bool, inFront: Bool, firstStart: Bool, gameOn: Bool,
                       somethingOpen: Bool) -> Bool {
        !asked && !on && padConnected && inFront && !firstStart && !gameOn && !somethingOpen
    }

    /// Esc at the top of the keyboard, with nothing to go back from: it leaves Nightforge's full screen, but never
    /// console mode – a keyboard on the sofa, a press by mistake. ⌃⌘F, View › Full Screen and the small menu do.
    static func escLeavesFullScreen(consoleMode: Bool) -> Bool { !consoleMode }

    /// A TV unplugged: Nightforge leaves a full screen it made there (GameDisplay.leavesFullScreen) – not in console
    /// mode, where it stays full screen on the Mac's screen.
    static func leavesFullScreenOffTV(consoleMode: Bool, wouldLeave: Bool) -> Bool { !consoleMode && wouldLeave }

    /// At the start, and after the window moved to another screen: full screen, whichever screen it is.
    static func wantsFullScreen(consoleMode: Bool, fullScreen: Bool) -> Bool { consoleMode && !fullScreen }

    /// The full-screen switch of a player at the keyboard (⌃⌘F, View › Full Screen, the green button) in console mode
    /// ends console mode, not only the full screen: it stays one switch, with no full screen of its own beneath.
    static func toggleEndsConsoleMode(consoleMode: Bool) -> Bool { consoleMode }
}
