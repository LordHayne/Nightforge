import AppKit
import CoreGraphics

/// The screen games are played on: the one Nightforge's window is on. When a TV or another
/// external screen is connected, the window moves there by itself (full screen on a TV), and from
/// a game's start until the window leaves it that screen is the main one – Wine and Mac games open
/// their full screen on the main display, and the menu bar would otherwise keep it on a MacBook's
/// own screen.
/// Moving the window back to the Mac's screen is the way to play there; Nightforge remembers it.
/// Mirrored screens are one screen: nothing moves, and games open in the mirror set's mode.
@MainActor
enum GameDisplay {
    struct Candidate: Equatable {
        let id: CGDirectDisplayID
        let name: String
        let builtIn: Bool
        let pixels: Int
        /// Shows another screen's picture (mirroring): no place of its own to move to.
        var mirrors = false
    }

    /// The external screen to play on: a TV before a monitor, then the biggest. None without one.
    nonisolated static func pick(_ displays: [Candidate]) -> CGDirectDisplayID? {
        displays.filter { !$0.builtIn && !$0.mirrors }
            .max { ($0.isTV ? 1 : 0, $0.pixels) < ($1.isTV ? 1 : 0, $1.pixels) }?.id
    }

    /// The display to make main for a game on `display`, nil when that one is main already. Mirrored
    /// screens are one screen: `primary` (CGDisplayPrimaryDisplay) gives a mirror set's master, which
    /// is the one that is main – so a game on a mirrored TV needs no change at all.
    nonisolated static func newMain(for display: CGDirectDisplayID, main: CGDirectDisplayID,
                                    primary: (CGDirectDisplayID) -> CGDirectDisplayID) -> CGDirectDisplayID? {
        let wanted = primary(display)
        return wanted == primary(main) ? nil : wanted
    }

    /// The screen a game will open on.
    static var screen: NSScreen? { window?.screen ?? NSScreen.main }

    private static var window: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    private enum Keys {
        /// The main display before a game made another one main, while that lasts.
        static let restoreMain = "gameDisplayRestoreMain"
        /// An external screen the player moved Nightforge's window away from.
        static let declined = "gameDisplayDeclined"
    }

    private static var known: Set<CGDirectDisplayID> = []
    private static var lastScreen: CGDirectDisplayID?
    private static var placing = false
    /// Nightforge put the window in full screen for a TV (so it leaves it when the TV goes).
    private static var madeFullScreen = false

    // MARK: - The launcher

    /// Puts the window on the screen to play on now and whenever one is connected.
    static func follow() {
        restoreLeftover()
        known = Set(candidates().map(\.id))
        Task {
            // The window shows up a moment after the app finished launching.
            for _ in 0..<50 where window == nil { try? await Task.sleep(for: .milliseconds(100)) }
            lastScreen = window?.screen.flatMap(id)
            await place()
            followSound()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let now = Set(candidates().map(\.id))
                let connected = !now.subtracting(known).isEmpty
                known = now
                followSound()  // also when a TV goes, or mirroring starts or ends
                Task { await leaveFullScreenOffTV() }
                guard connected else { return }
                UserDefaults.standard.removeObject(forKey: Keys.declined)  // plugged in again: try it
                Task {
                    await place()
                    followSound()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                                               object: nil, queue: .main) { note in
            MainActor.assumeIsolated { windowMoved(note.object as? NSWindow) }
        }
    }

    /// The player moved the window: away from the picked screen means "not there", onto it "yes".
    /// A screen that went away taking the window along says nothing.
    private static func windowMoved(_ moved: NSWindow?) {
        guard let moved, moved === window, let now = moved.screen.flatMap(id) else { return }
        defer {
            lastScreen = now
            followSound()
        }
        // Away from the screen a game made main: the main display goes back now (leaveGame).
        if !running, !placing, !onMain { restoreLeftover() }
        guard !placing, let before = lastScreen, before != now,
              NSScreen.screens.contains(where: { id($0) == before }),
              let picked = pick(candidates())
        else { return }
        if before == picked {
            UserDefaults.standard.set(Int(picked), forKey: Keys.declined)
        } else if now == picked {
            UserDefaults.standard.removeObject(forKey: Keys.declined)
        }
    }

    /// What `place` does with the window: move it to the picked screen, and on a TV go full screen –
    /// also when it's there already, as on a mirrored TV (one screen, nothing to move). Nothing on a
    /// screen the player moved it away from (`declined`).
    struct Placement: Equatable {
        var move: Bool
        var fullScreen: Bool
    }

    nonisolated static func placement(picked: Candidate?, windowOn: CGDirectDisplayID?, declined: CGDirectDisplayID?,
                                      fullScreen: Bool) -> Placement? {
        guard let picked, declined != picked.id else { return nil }
        let move = windowOn != picked.id
        let full = picked.isTV && (move || !fullScreen)
        return move || full ? Placement(move: move, fullScreen: full) : nil
    }

    /// Full screen that Nightforge chose for a TV ends when the window is on no TV any more (TV
    /// unplugged, mirroring off). Full screen the player chose stays.
    nonisolated static func leavesFullScreen(madeFullScreen: Bool, fullScreen: Bool, windowOn: Candidate?) -> Bool {
        madeFullScreen && fullScreen && windowOn?.isTV != true
    }

    private static func place() async {
        let screens = candidates()
        let declined = (UserDefaults.standard.object(forKey: Keys.declined) as? Int).map { CGDirectDisplayID(truncatingIfNeeded: $0) }
        guard let window, !running,
              let picked = pick(screens).flatMap({ display in screens.first { $0.id == display } }),
              let plan = placement(picked: picked, windowOn: window.screen.flatMap(id), declined: declined,
                                   fullScreen: window.styleMask.contains(.fullScreen)),
              let target = NSScreen.screens.first(where: { id($0) == picked.id })
        else { return }
        placing = true
        defer { placing = false }
        if plan.move {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                for _ in 0..<30 where window.styleMask.contains(.fullScreen) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let area = target.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, area.width)
            frame.size.height = min(frame.height, area.height)
            frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
            window.setFrame(frame, display: true)
            lastScreen = picked.id
            try? await Task.sleep(for: .milliseconds(300))  // let the move land first
        }
        if plan.fullScreen, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            madeFullScreen = true
        }
        window.makeKeyAndOrderFront(nil)
    }

    private static func leaveFullScreenOffTV() async {
        guard let window, !running,
              leavesFullScreen(madeFullScreen: madeFullScreen, fullScreen: window.styleMask.contains(.fullScreen),
                               windowOn: candidates().first { $0.id == window.screen.flatMap(id) })
        else { return }
        madeFullScreen = false
        placing = true
        defer { placing = false }
        window.toggleFullScreen(nil)
        for _ in 0..<30 where window.styleMask.contains(.fullScreen) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - While a game runs

    private static var running = false

    /// Before a game starts: the game screen becomes the main display.
    static func enterGame() {
        running = true
        followSound()  // before the game: Wine takes the output when it starts
        guard let game = screen.flatMap(id) else { return }
        let main = CGMainDisplayID()
        guard let wanted = newMain(for: game, main: main, primary: CGDisplayPrimaryDisplay), makeMain(wanted) else { return }
        if UserDefaults.standard.object(forKey: Keys.restoreMain) == nil {
            UserDefaults.standard.set(Int(main), forKey: Keys.restoreMain)
        }
    }

    /// After the game. Its screen stays the main one for as long as Nightforge's window is there:
    /// switching back reconfigures the screens – on a TV the picture can go dark for a moment –
    /// right as Nightforge comes back, and the next game would switch again. The main display goes
    /// back when the window leaves that screen (windowMoved) or Nightforge quits.
    static func leaveGame() {
        running = false
        if !onMain { restoreLeftover() }
    }

    /// Nightforge is in front again after a game: its window comes forward first – on a TV from
    /// the page behind the game into its own full-screen Space (GameBackdrop) – then the rest.
    static func backFromGame() {
        window?.makeKeyAndOrderFront(nil)
        leaveGame()
    }

    /// Nightforge's window is on the main display (or in its mirror set).
    private static var onMain: Bool {
        guard let display = window?.screen.flatMap(id) else { return true }
        return newMain(for: display, main: CGMainDisplayID(), primary: CGDisplayPrimaryDisplay) == nil
    }

    /// When Nightforge quits with no game running.
    static func quitting() {
        if !running { restoreLeftover() }
    }

    /// Also at start, after Nightforge quit while a game ran.
    private static func restoreLeftover() {
        guard let stored = UserDefaults.standard.object(forKey: Keys.restoreMain) as? Int else { return }
        UserDefaults.standard.removeObject(forKey: Keys.restoreMain)
        let main = CGDirectDisplayID(stored)
        if CGDisplayIsActive(main) != 0,
           let wanted = newMain(for: main, main: CGMainDisplayID(), primary: CGDisplayPrimaryDisplay) {
            _ = makeMain(wanted)
        }
    }

    /// The main display is the one at the origin: shift every screen so `display` lands there.
    /// For this login session only, so a restart puts things back anyway.
    private static func makeMain(_ display: CGDirectDisplayID) -> Bool {
        let shift = CGDisplayBounds(display).origin
        let displays = activeDisplays()
        guard !displays.isEmpty else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        // A mirrored screen follows the one it mirrors.
        for other in displays where CGDisplayMirrorsDisplay(other) == kCGNullDirectDisplay {
            let origin = CGDisplayBounds(other).origin
            CGConfigureDisplayOrigin(config, other, Int32(origin.x - shift.x), Int32(origin.y - shift.y))
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }

    // MARK: - Screens

    private static func id(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func candidates() -> [Candidate] {
        NSScreen.screens.compactMap { screen in
            guard let display = id(screen) else { return nil }
            return Candidate(id: display, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(display) != 0,
                             pixels: CGDisplayPixelsWide(display) * CGDisplayPixelsHigh(display),
                             mirrors: CGDisplayMirrorsDisplay(display) != kCGNullDirectDisplay)
        }
    }

    /// Every display that shows a picture, mirrors included (they aren't NSScreens of their own).
    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    // MARK: - Sound

    /// The TV that shows Nightforge, for its sound (GameAudio): the window's screen when it's a TV,
    /// or a screen mirrored with an external one – mirroring puts the picture on the big screen.
    /// `mirroredWith`: the other displays of its mirror set, true for the Mac's own. A mirror has no
    /// name of its own here (""). Nil when no TV shows Nightforge.
    nonisolated static func soundScreen(_ screen: Candidate?, mirroredWith: [Bool]) -> String? {
        guard let screen else { return nil }
        if screen.isTV { return screen.name }
        guard !mirroredWith.isEmpty, !screen.builtIn || mirroredWith.contains(false) else { return nil }
        return screen.builtIn ? "" : screen.name
    }

    private static func followSound() {
        guard let display = window?.screen.flatMap(id) else { return }
        let set = CGDisplayPrimaryDisplay(display)
        let mirroredWith = activeDisplays().filter { $0 != display && CGDisplayPrimaryDisplay($0) == set }
            .map { CGDisplayIsBuiltin($0) != 0 }
        GameAudio.follow(tv: soundScreen(candidates().first { $0.id == display }, mirroredWith: mirroredWith))
    }
}

extension GameDisplay.Candidate {
    /// TVs name themselves so over HDMI ("LG TV SSCR2", "SAMSUNG", "SONY TV  *00"), and so does an
    /// AV receiver in front of one ("DENON-AVR").
    var isTV: Bool {
        let words = name.uppercased().split { !$0.isLetter && !$0.isNumber }
        let brands: Set<Substring> = ["TV", "SAMSUNG", "SONY", "VIZIO", "HISENSE", "TCL", "PANASONIC", "BRAVIA",
                                      "AVR", "DENON", "MARANTZ", "ONKYO"]
        return words.contains { brands.contains($0) }
    }
}
