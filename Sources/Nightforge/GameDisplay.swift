import AppKit
import ColorSync
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
    /// The external screens seen last, for the sound: a TV that's new, not the Mac's own screen as
    /// the lid opens or a TV back after a moment (GameAudio.plugged).
    private static var externals: Set<String> = []
    private static var externalsGone: [String: Date] = [:]
    private static var lastScreen: CGDirectDisplayID?
    private static var placing = false
    /// The screens are being rearranged (makeMain): the window's moves meanwhile say nothing.
    private static var rearranging = false
    /// Nightforge put the window in full screen for a TV (so it leaves it when the TV goes).
    private static var madeFullScreen = false

    // MARK: - The launcher

    /// Puts the window on the screen to play on now and whenever one is connected.
    static func follow() {
        restoreLeftover()
        known = Set(candidates().map(\.id))
        externals = Set(candidates().filter { !$0.builtIn }.map { String($0.id) })
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
                let all = candidates()
                let now = Set(all.map(\.id))
                let connected = !now.subtracting(known).isEmpty
                known = now
                let screens = Set(all.filter { !$0.builtIn }.map { String($0.id) })
                let plugged = GameAudio.plugged(screens, before: externals, gone: &externalsGone, at: Date())
                externals = screens
                // For the live test: the curtain coming and going after a TV was plugged in again.
                if GameBackdrop.isRaised {
                    GameLog.note("Screens changed under the curtain\(connected ? ", one connected" : "")\(plugged ? ", a new TV" : "")")
                }
                followSound(plugged ? .plugged : nil)  // also when a TV goes, or mirroring starts or ends
                Task { await leaveFullScreenOffTV() }
                guard connected else { return }
                UserDefaults.standard.removeObject(forKey: Keys.declined)  // plugged in again: try it
                Task {
                    await place()
                    followSound(plugged ? .plugged : nil)
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
            // Not while Nightforge itself moves it (full screen, rearranging): only where it lands.
            if !placing, !rearranging { followSound() }
        }
        // Away from the screen a game made main: the main display goes back now (leaveGame).
        if !running, !placing, !rearranging, !onMain { restoreLeftover() }
        guard !placing, !rearranging, let before = lastScreen, before != now,
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
            // The TV becomes the main display first, where games open: changed later, under the
            // full-screen window, the screens shift and macOS takes the window to the Mac's screen.
            if becomeMain(picked.id) { try? await Task.sleep(for: .milliseconds(500)) }
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

    /// Before a game starts: the game screen becomes the main display (on a TV it is already).
    static func enterGame() {
        running = true
        followSound(.gameStarts)  // before the game: Wine takes the output when it starts
        guard let game = screen.flatMap(id) else { return }
        becomeMain(game)
    }

    /// The screen games open on: the main display (a mirror set's master), which `enterGame` made
    /// the one Nightforge's window is on. Nightforge's pages around a game go there.
    static var gameScreen: NSScreen? {
        let main = CGDisplayPrimaryDisplay(CGMainDisplayID())
        return NSScreen.screens.first { id($0) == main } ?? screen
    }

    /// Makes `display` the main one, remembering the one before for later. True when it's main now.
    @discardableResult
    private static func becomeMain(_ display: CGDirectDisplayID) -> Bool {
        let main = CGMainDisplayID()
        guard let wanted = newMain(for: display, main: main, primary: CGDisplayPrimaryDisplay) else { return true }
        guard makeMain(wanted) else { return false }
        if UserDefaults.standard.object(forKey: Keys.restoreMain) == nil {
            UserDefaults.standard.set(Int(main), forKey: Keys.restoreMain)
        }
        return true
    }

    /// After the game. Its screen stays the main one for as long as Nightforge's window is there:
    /// switching back reconfigures the screens – on a TV the picture can go dark for a moment –
    /// right as Nightforge comes back, and the next game would switch again. The main display goes
    /// back when the window leaves that screen (windowMoved) or Nightforge quits.
    static func leaveGame() {
        running = false
        GameAudio.gameEnded()
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
    /// For this login session only, so a restart puts things back anyway. Windows keep their place
    /// in the shared coordinates, so Nightforge's would land on another screen: it's put back on
    /// its own (`keepWindow`).
    private static func makeMain(_ display: CGDirectDisplayID) -> Bool {
        let kept = window.flatMap { window in
            window.screen.flatMap { screen in id(screen).map { ($0, window.frame.origin - screen.frame.origin) } }
        }
        rearranging = true
        GameLog.note("Main display: \(NSScreen.screens.first { id($0) == display }?.localizedName ?? String(display))")
        guard reconfigureMain(display) else {
            rearranging = false
            return false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))  // AppKit's screens follow a moment later
            if let kept { await keepWindow(on: kept.0, at: kept.1) }
            rearranging = false
        }
        return true
    }

    /// Puts Nightforge's window back on `display`, at `offset` from its corner. A full-screen
    /// window can't simply move: out of full screen, over, back in.
    private static func keepWindow(on display: CGDirectDisplayID, at offset: CGPoint) async {
        guard let window, let screen = NSScreen.screens.first(where: { id($0) == display }),
              window.screen.flatMap(id) != display || !window.styleMask.contains(.fullScreen)
        else { return }
        guard window.styleMask.contains(.fullScreen) else {
            window.setFrameOrigin(screen.frame.origin + offset)
            return
        }
        window.toggleFullScreen(nil)
        for _ in 0..<30 where window.styleMask.contains(.fullScreen) { try? await Task.sleep(for: .milliseconds(100)) }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        window.setFrame(frame, display: true)
        try? await Task.sleep(for: .milliseconds(300))
        window.toggleFullScreen(nil)
    }

    private static func reconfigureMain(_ display: CGDirectDisplayID) -> Bool {
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

    // MARK: - Wine's view of the screens

    /// A screen as Wine takes it when its session starts: the displays that mirror nothing (a
    /// mirror set is one), which is main, their size in points and pixels. winecx's mac driver
    /// lists the online displays and skips those mirroring another (macdrv_get_adapters), so a fresh
    /// session sees a mirrored TV alone. But it keeps what it saw for the session: on 31.10. one
    /// begun before the TV was mirrored still had the MacBook as a primary screen of its own (two
    /// sources, both flagged primary), so Overcooked 2 opened at 1512×982 with Retina scale in the
    /// corner of the 1920×1080 TV, and Mafia II chose 3024×1964.
    struct WineScreen: Equatable {
        var id: CGDirectDisplayID
        var main: Bool
        var points: CGSize
        var pixels: CGSize
    }

    nonisolated static func wineSignature(_ screens: [WineScreen]) -> String {
        screens.sorted { $0.id < $1.id }.map { screen in
            "\(screen.id)\(screen.main ? "*" : ""):\(Int(screen.points.width))x\(Int(screen.points.height))"
                + "@\(Int(screen.pixels.width))x\(Int(screen.pixels.height))"
        }.joined(separator: ",")
    }

    /// The screens a Wine session (its wineserver) began with.
    struct WineSession: Codable, Equatable {
        var server: Int32
        var screens: String
    }

    /// Whether the session `server` saw other screens than `now`. A session seen for the first
    /// time is taken to have begun with what's there now – it's looked at every few seconds
    /// (`observeWineSession`), so before the screens change – unless it began before Nightforge
    /// did (`beganBefore`): what it saw then is unknown, and it counts as stale until replaced.
    nonisolated static func wineSessionCheck(stored: WineSession?, server: pid_t?, beganBefore: Bool = false,
                                             now: String) -> (stale: Bool, store: WineSession?) {
        guard let server else { return (false, nil) }  // no session: the next one starts fresh
        guard let stored, stored.server == server else {
            let seen = WineSession(server: server, screens: beganBefore ? unknownScreens : now)
            return (seen.screens != now, seen)
        }
        return (stored.screens != now, stored)
    }

    nonisolated static let unknownScreens = "unknown"

    private nonisolated static let wineSessionKey = "wineSessionScreens"

    /// With the running-games check (LibraryModel), so a session is known before the screens change.
    nonisolated static func observeWineSession() { _ = wineSessionStale() }

    /// True when the running Wine session began with other screens: a fresh one opens games right.
    nonisolated static func wineSessionStale() -> Bool {
        let defaults = UserDefaults.standard
        let stored = defaults.data(forKey: wineSessionKey).flatMap { try? JSONDecoder().decode(WineSession.self, from: $0) }
        let server = wineserver()
        let (stale, store) = wineSessionCheck(stored: stored, server: server, beganBefore: server.map(beganBeforeNightforge) ?? false,
                                              now: wineSignature(currentWineScreens()))
        if store != stored {
            if let store, let data = try? JSONEncoder().encode(store) { defaults.set(data, forKey: wineSessionKey) }
            else { defaults.removeObject(forKey: wineSessionKey) }
        }
        return stale
    }

    private nonisolated static func currentWineScreens() -> [WineScreen] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }.compactMap { display in
            guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
            return WineScreen(id: display, main: CGDisplayIsMain(display) != 0,
                              points: CGSize(width: mode.width, height: mode.height),
                              pixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight))
        }
    }

    /// The process started before this Nightforge did.
    private nonisolated static func beganBeforeNightforge(_ pid: pid_t) -> Bool {
        func started(_ pid: pid_t) -> Double? {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        }
        guard let session = started(pid), let us = started(getpid()) else { return false }
        return session < us
    }

    /// The wineserver of Nightforge's engine, found without running ps.
    private nonisolated static func wineserver() -> pid_t? {
        let root = Engine.supportDir.resolvingSymlinksInPath().path + "/"
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let executable = String(cString: path)
            if executable.hasSuffix("/bin/wineserver"), executable.hasPrefix(root) { return pid }
        }
        return nil
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

    /// `moment`: why (GameAudio.Moment); by default the window leaving a TV, or just a look.
    private static func followSound(_ moment: GameAudio.Moment? = nil) {
        guard let display = window?.screen.flatMap(id) else { return }
        let set = CGDisplayPrimaryDisplay(display)
        let others = activeDisplays().filter { $0 != display && CGDisplayPrimaryDisplay($0) == set }
        let tv = soundScreen(candidates().first { $0.id == display }, mirroredWith: others.map { CGDisplayIsBuiltin($0) != 0 })
        // The TV itself: the window's screen, or the external one mirroring the Mac's.
        let tvDisplay = tv == nil ? nil : ([display] + others).first { CGDisplayIsBuiltin($0) == 0 }
        GameAudio.follow(moment ?? (tv == nil ? .left : .look), tv: tv,
                         tvKey: tvDisplay.flatMap(tvKey) ?? tv.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// A screen's own ID, the same after unplugging and a restart (ColorSync's UUID from its EDID).
    private static func tvKey(_ display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
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

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}
