import AppKit
import SwiftUI

/// The controller's way out of a game, from the sofa. Both sticks pressed and held for two seconds
/// in a game bring a side bar over it (OverlayView, its blocks in OverlayTiles): the game's name, the
/// time, the controllers, and Continue Playing, Quit Game (one that hangs as well) and Go to
/// Nightforge. Not the PS/Xbox button: since macOS 26 it opens Apple's Game Overlay (and
/// Nightforge can't take it from the game in front), and Create/Share carries macOS's screenshot
/// and recording gestures (System Settings › Game Controllers, macOS 27); the stick buttons carry
/// none. A pad without them uses ☰ and ⧉ (`OverlayHold.chord`).
///
/// The pad reaches Nightforge in the background (InputRouter); the game gets the same presses,
/// which macOS can't take from it, and the rule is that it gets none while the overlay is up. A
/// Windows game's pad comes through our own Wine driver, which keeps silent for as long as the overlay
/// asks (PadSilence). And the game is stopped, once the panel shows (SIGSTOP), and runs on when nothing is held any more:
/// the button that closed the overlay is the player's last word to it, not the game's (mayRunOn).
/// Wine's pad driver runs in winedevice.exe, not in the game, and XInput hands the game the pad's
/// state when it runs on, after what's queued meanwhile; its sound pauses with it. Whether a Mac
/// game gets a backlog from GameController on running on hasn't been seen yet. A Mac game that only
/// runs online isn't stopped: it keeps hearing the pad, and the overlay says so (OverlayStillness).
/// A Windows game that only runs online isn't stopped either, if the driver answers; it can't hear the pad.
@MainActor
enum GameOverlay {
    final class State: ObservableObject {
        @Published var step = OverlayStep.menu
        @Published var game = ""
        @Published var paused = false
        /// What the blocks are given, as it was when the overlay opened.
        @Published var context = OverlayContext()
        /// A question about a start, with no picture to keep: in the middle of the screen, for as long
        /// as the overlay is up.
        @Published var centered = false
        /// A TV or a desk: what the side bar's sizes are for.
        @Published var seat = OverlaySeat.desk
        @Published var symbols = PadSymbols()
        /// The output the game still plays to after the default changed (GameAudio.gameStillOn).
        @Published var soundStaysOn: String?
        /// What's said about a start on the curtain that looks stuck (`.stuck`).
        @Published var stuck: CurtainEscape.Words?
        /// A controller came after the game started without one (LibraryModel.padArrivedLate):
        /// the menu offers a restart first, once.
        @Published var lateController = false
    }

    /// What the model does for the choices.
    struct Actions {
        /// Ends the game's processes (`GameProcesses.end`), off the main thread.
        var quit: () async -> Void
        /// Nightforge in front, the game left running behind it; done once it's there or can't be.
        var nightforge: () async -> Void
        /// Ends the game and starts it again; nil where the overlay offers no restart.
        var restart: (() async -> Void)? = nil
    }

    private static let state = State()
    private static var panel: NSPanel?
    private static var actions: Actions?
    /// On the way to Nightforge: the panel stays until it's there, and takes no more presses.
    private static var leaving = false
    /// What the overlay was opened for: only that decides about the keys.
    private static var openedFor = OverlayStep.menu
    /// A closed overlay's game, stopped until the fingers are off the pad.
    private static var runningOn: Task<Void, Never>?
    private static var pausedKey: String { "overlayPaused" }

    static var isOpen: Bool { panel?.isVisible == true }
    /// Set when a controller came late; the next overlay asks, then it's cleared (close).
    static var lateController: Bool {
        get { state.lateController }
        set { state.lateController = newValue }
    }
    /// A game ended: what the overlay was to ask about it isn't for the next one.
    static func gameEnded() { state.lateController = false }
    /// The player went back to the game from here (LibraryModel, GameStage).
    static var resumed: (@MainActor () -> Void)?
    /// Whether nothing is held on any pad (InputRouter).
    static var padIdle: (@MainActor () -> Bool)?
    /// The panel may take the keys at all (OverlayPanel).
    static var mayTakeKeys: Bool { takesKeys(openedFor) }
    /// Open with "Not starting?" (or the question it led to).
    static var asksAboutStart: Bool { isOpen && (state.step == .notStarting || state.step == .stuck) }
    /// Open with the way out of a curtain with no game under it (CurtainEscape).
    static var asksWayOut: Bool { isOpen && state.step == .stuck }
    /// The panel, while it's up: the pad's input goes there (InputRouter).
    static var window: NSWindow? { isOpen ? panel : nil }

    /// Over `game` on `screen`. `pids`: its processes, whose windows the panel goes above;
    /// `pause`: whether they're stopped while it's up – once it shows (`checkShown`). `step`:
    /// `.notStarting` for a game that runs but shows nothing (LibraryModel's curtain).
    /// `soundStaysOn`: the device a Windows game still plays to after the default output changed.
    /// `context`: what the side bar's blocks show.
    static func open(_ game: String, pids: [pid_t], pause: Bool, on screen: NSScreen?, symbols: PadSymbols,
                     step: OverlayStep = .menu, soundStaysOn: String? = nil, stuck: CurtainEscape.Words? = nil,
                     context: OverlayContext = OverlayContext(), actions: Actions) {
        guard !isOpen, let screen = screen ?? NSScreen.main else { return }
        runningOn?.cancel()  // opened again before the fingers were off: the game simply stays stopped
        runningOn = nil
        self.actions = actions
        openedFor = step
        state.centered = takesKeys(step)
        state.context = context
        state.stuck = stuck
        if step == .menu, context.silencesPad { PadSilence.begin() }  // at once: it costs a game nothing
        state.game = game
        state.soundStaysOn = soundStaysOn
        state.symbols = symbols
        state.step = step
        state.paused = pause && !pids.isEmpty  // said at once, done once the panel shows
        let panel = self.panel ?? make()
        self.panel = panel
        // The display the game's window is on, as it is now: ABZU switched the MacBook to 1920×1200
        // after its start (4.11.), and the overlay laid out for 1512×982 covered a corner of it.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        display = GameProcesses.display(of: windows, pids: Set(pids)) ?? screenNumber(screen)
        let frame = display.map(Self.frame(of:)) ?? screen.frame
        let shownOn = NSScreen.screens.first { GameDisplay.id($0) == display } ?? screen
        state.seat = GameDisplay.isTV(shownOn) ? .sofa : .desk
        panel.setFrame(frame, display: false)
        // Above whatever covers the screen – the game's window, whatever level it gives it, or a
        // captured display's shield (windows above its level show over it).
        let coverLevel = GameProcesses.coverLevel(windows, screen: GameProcesses.cgRect(frame), except: getpid())
        // The curtain may lie above a captured display's shield: the panel over that too.
        panel.level = NSWindow.Level(rawValue: panelLevel(coverLevel: [coverLevel, GameBackdrop.raisedLevel].compactMap { $0 }.max()))
        panel.orderFrontRegardless()
        if Self.takesKeys(step) { panel.makeKey() }
        focusDefault()
        heard = false
        opened += 1
        let look = opened
        GameLog.note("Overlay up (\(step)) for \(game): \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nobody") in front, "
                     + "its windows \(GameProcesses.windowList(Set(pids))), the panel L\(panel.level.rawValue) on \(Int(frame.width))×\(Int(frame.height))"
                     + (panel.isOnActiveSpace ? "" : " not on the Space shown"))
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            checkShown(look, pids: pids, pause: pause)
        }
    }

    /// The panel's opening, so a look 300 ms on knows it's still the same one.
    private static var opened = 0
    /// The display the panel is over while it's up.
    private static var display: CGDirectDisplayID?

    /// A display's frame as it is now, in AppKit's terms – from the display itself, not a screen
    /// remembered from before a game changed its mode.
    static func frame(of display: CGDirectDisplayID) -> NSRect {
        appKitFrame(CGDisplayBounds(display), primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
    }

    /// CGDisplayBounds' frame (from the main display's top left) in AppKit's (from its bottom left).
    nonisolated static func appKitFrame(_ bounds: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    private static func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The display changed while the panel is up (a game switching its mode): the panel follows it.
    private static func followDisplay() {
        guard isOpen, let panel, let display else { return }
        let frame = Self.frame(of: display)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        GameLog.note("Overlay follows the display: \(Int(frame.width))×\(Int(frame.height))")
    }

    /// 300 ms after the panel opened: it shows – then the game pauses – or it's raised above what
    /// lies in front of it and looked at once more, and failing that the game runs on in front
    /// without it. ABZU (DXMT, macOS's Game Mode on, 3.11.) froze under a panel the player never
    /// saw, behind the game's window: the pause came at once. So the pause waits for the panel.
    private static func checkShown(_ look: Int, pids: [pid_t], pause: Bool, again: Bool = false) {
        guard look == opened, isOpen, let panel, !leaving else { return }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let covering = GameProcesses.covering(windows, window: panel.windowNumber)
        let visible = panel.occlusionState.contains(.visible)
        let seen = "\(covering.map { $0.isEmpty ? "nothing in front of it" : "in front of it " + GameProcesses.describe($0) } ?? "not on the Space shown"), "
            + "\(visible ? "visible" : "hidden") to macOS, the panel L\(panel.level.rawValue), the game's windows \(GameProcesses.windowList(Set(pids)))"
        if shows(inFront: covering?.isEmpty == true, occlusionVisible: visible) {
            if again { GameLog.note("Overlay seen for \(state.game) once raised (\(seen))") }
            if pause, !runsOnSilenced() { stop(pids) }
            return
        }
        if !again {
            panel.level = NSWindow.Level(rawValue: raisedLevel(panel.level.rawValue, covering: covering ?? []))
            panel.orderFrontRegardless()
            if Self.takesKeys(state.step) { panel.makeKey() }
            GameLog.note("Overlay not seen for \(state.game) after 300 ms (\(seen)): raised to L\(panel.level.rawValue), brought to the front")
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                checkShown(look, pids: pids, pause: pause, again: true)
            }
            return
        }
        GameLog.note("Overlay still not seen for \(state.game) (\(seen)): it goes, the game runs on in front")
        InputRouter.hidePointerForGame()
        close()
    }

    /// A Windows game that only runs online isn't stopped when our Wine driver has answered that it
    /// keeps the pad from it; if not, it's stopped like any other.
    private static func runsOnSilenced() -> Bool {
        guard state.context.runsOnIfSilent else { return false }
        let heard = PadSilence.heard
        state.context.stillness = heard ? .silenced : .paused
        state.paused = !heard
        GameLog.note("Overlay: \(state.game) only runs online, " + (heard ? "the pad driver answered: it runs on" : "no answer from the pad driver: it stops"))
        return heard
    }

    /// Whether the panel shows: nothing in front of it on the Space shown, and macOS counts it as
    /// visible.
    nonisolated static func shows(inFront: Bool, occlusionVisible: Bool) -> Bool { inFront && occlusionVisible }

    /// Whether the panel takes the keys. Not over a game that shows a picture: losing them, The Forest
    /// lay down in the Dock the moment the panel opened (8.11. 15:5x: `picture here`, next look
    /// `picture elsewhere`), as Unity and Unreal games do (GameStage), and nothing came back of it for
    /// the player but a game out of its full screen. The pad reaches Nightforge without them and the
    /// mouse works through a panel that doesn't need them; the keyboard answers only "Not starting?",
    /// where no picture is lost. The overlay opens only with the pad, so there's one in the hand.
    nonisolated static func takesKeys(_ step: OverlayStep) -> Bool { step == .notStarting || step == .stuck }

    /// The panel's level: the screen saver's (the curtain lies just under it), or above what covers
    /// the screen should that lie higher.
    nonisolated static func panelLevel(coverLevel: Int?) -> Int {
        min(max(Int(CGWindowLevelForKey(.screenSaverWindow)), (coverLevel ?? 0) + 1), highestLevel)
    }

    /// No window goes higher; one at the top already gets the panel at its level, ordered in front.
    nonisolated static var highestLevel: Int { Int(CGWindowLevelForKey(.maximumWindow)) }

    /// The panel's level for a second try: above every window found in front of it.
    nonisolated static func raisedLevel(_ level: Int, covering: [[String: Any]]) -> Int {
        min(max(level, (covering.compactMap { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue }.max() ?? level - 1) + 1), highestLevel)
    }

    /// The pad heard while the panel is up, once (InputRouter): "Not starting?" took no presses on
    /// 1.11. (Black Myth: Wukong), and wine.log tells whether they reached Nightforge at all.
    static func padHeard() {
        guard isOpen, !heard else { return }
        heard = true
        GameLog.note("Overlay: the pad reaches Nightforge (\(state.step))")
    }

    private static var heard = false

    /// B: from the question back to the choice, from the choice back to the game.
    static func back() { handle(.back) }
    /// Continue Playing, or the sticks held again: the panel goes, the game runs on.
    static func resume() { handle(.resume) }
    static func askQuit() { handle(.askQuit) }
    static func quit() { handle(.quit) }
    static func restart() { handle(.restart) }
    static func toNightforge() { handle(.nightforge) }

    private static func handle(_ event: OverlayEvent) {
        guard !leaving else { return }
        // In wine.log: which presses arrive (the pad on "Not starting?", 1.11.), and who's in front.
        GameLog.note("Overlay: \(event) on \(state.step), \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nobody") in front"
                     + (Self.takesKeys(state.step) && panel?.isKeyWindow != true ? ", the panel without the keys" : ""))
        let (step, effect) = transition(state.step, event)
        if step != state.step { show(step) }
        switch effect {
        case .none:
            break
        case .close:
            InputRouter.hidePointerForGame()  // while the panel still has the keys
            closeForGame()
        case .restart:
            guard let actions else { return }
            GameBackdrop.returning(held: true)
            close()
            Task { await (actions.restart ?? actions.quit)() }
        case .quit:
            // One curtain from here until Nightforge is in front: the panel goes at once, the
            // curtain holds whatever the game's processes do while they end.
            guard let actions else { return }
            GameBackdrop.returning(held: true)
            close()
            Task { await actions.quit() }
        case .nightforge:
            // The game runs again first: stopped, Wine can neither hand over the front nor hide.
            // Then Nightforge in front (LibraryModel.leaveGame), then the panel goes: the game
            // doesn't show in between.
            guard let actions else { return }
            leaving = true
            Task {
                await padReleased()
                cont()
                PadSilence.end()
                await actions.nightforge()
                leaving = false
                close()
            }
        }
    }

    enum Effect: Equatable { case none, close, quit, nightforge, restart }

    /// The overlay's steps: B steps back, the sticks held again go back to the game from anywhere
    /// but the quitting, and a game is only quit from the question.
    nonisolated static func transition(_ step: OverlayStep, _ event: OverlayEvent) -> (OverlayStep, Effect) {
        switch (step, event) {
        case (.quitting, _): return (.quitting, .none)
        case (.menu, .back), (.notStarting, .back), (.stuck, .back), (_, .resume): return (step, .close)
        case (.menu, .askQuit), (.notStarting, .askQuit): return (.confirmQuit, .none)
        case (.menu, .nightforge), (.notStarting, .nightforge), (.stuck, .nightforge): return (step, .nightforge)
        case (.confirmQuit, .back): return (.menu, .none)
        case (.confirmQuit, .quit): return (.quitting, .quit)
        case (.menu, .restart): return (.quitting, .restart)
        default: return (step, .none)
        }
    }

    /// Also when Nightforge quits: a paused game never stays paused.
    static func close() {
        cont()
        PadSilence.end()
        state.lateController = false
        panel?.orderOut(nil)
        PadFocus.shared.clear()
        actions = nil
    }

    /// Continue Playing: the panel goes at once, a stopped game runs on when the fingers are off the
    /// pad (the press that closed it is not for the game), and only then is it handed the front:
    /// stopped, Wine can't take it.
    private static func closeForGame() {
        let holdsIt = state.paused || PadSilence.isOn
        state.lateController = false
        panel?.orderOut(nil)
        PadFocus.shared.clear()
        actions = nil
        guard holdsIt else {
            cont()
            resumed?()
            return
        }
        runningOn = Task {
            await padReleased()
            guard !Task.isCancelled else { return }
            cont()
            PadSilence.end()
            runningOn = nil
            resumed?()
        }
    }

    /// Back when nothing is held any more on any pad, or after a second.
    private static func padReleased() async {
        guard let idle = padIdle else { return }
        let start = ProcessInfo.processInfo.systemUptime
        var waited: TimeInterval = 0
        while !OverlayRules.mayRunOn(padIdle: idle(), waited: waited), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
            waited = ProcessInfo.processInfo.systemUptime - start
        }
        if waited > 0 { GameLog.note("Overlay: the fingers off the pad after \(Int(waited * 1000)) ms") }
    }

    /// At start: a game Nightforge paused before it quit or crashed runs on.
    static func resumeLeftovers() { cont() }

    private static func show(_ step: OverlayStep) {
        state.step = step
        focusDefault()
    }

    /// The highlight on the step's default button at once: the panel is opened with the pad. By its
    /// id, not looked up on the screen: right after the panel opens – the first time it's made, as
    /// "Not starting?" often is – or changes its step, the buttons aren't laid out yet, nothing was
    /// highlighted, and the first press only showed where you were.
    private static func focusDefault() {
        PadFocus.shared.clear()
        if state.step == .menu && state.lateController {
            PadFocus.shared.focus("overlay.restart")
        } else if let id = defaultButton(state.step) {
            PadFocus.shared.focus(id)
        }
    }

    /// The button a step's highlight starts on (its `padFocus` id): the safe answer.
    nonisolated static func defaultButton(_ step: OverlayStep) -> String? {
        switch step {
        case .menu: return "overlay.continue"
        case .notStarting, .stuck: return "overlay.wait"
        case .confirmQuit: return "overlay.cancel"
        case .quitting: return nil
        }
    }

    private static func stop(_ pids: [pid_t]) {
        guard !pids.isEmpty else { return }
        UserDefaults.standard.set(pids.map(Int.init), forKey: pausedKey)
        for pid in pids { kill(pid, SIGSTOP) }
    }

    private static func cont() {
        let pids = (UserDefaults.standard.array(forKey: pausedKey) as? [Int]) ?? []
        for pid in pids { kill(pid_t(pid), SIGCONT) }
        UserDefaults.standard.removeObject(forKey: pausedKey)
        state.paused = false
    }

    private static func make() -> NSPanel {
        let panel = OverlayPanel(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        // Over the game's full screen, in its Space as in every other.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.becomesKeyOnlyIfNeeded = true  // a click on a button leaves the game its keys too
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { followDisplay() }
        }
        let host = NSHostingView(rootView: OverlayView(state: state).modifier(AccessibilityFromSettings()))
        host.sizingOptions = []  // the screen's size, not the content's
        panel.contentView = host
        return panel
    }
}

enum OverlayStep: Equatable { case menu, notStarting, stuck, confirmQuit, quitting }

enum OverlayEvent { case back, resume, askQuit, quit, nightforge, restart }

/// Can take keys without making Nightforge the active app, so the game's Space stays where it is –
/// and only for what the overlay was opened for (`takesKeys`): never over a game showing its picture.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { GameOverlay.mayTakeKeys }
    override func cancelOperation(_ sender: Any?) { GameOverlay.back() }  // Esc
}

/// The buttons that open the overlay, as the pad shows them: both sticks pressed ("L3 + R3").
struct OverlayChord: View {
    let symbols: PadSymbols

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbols.overlayChord[0])
            Text("+")
            Image(systemName: symbols.overlayChord[1])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Both sticks pressed"))
    }
}

/// The overlay's buttons held for two seconds, from the pad's state as it changes.
struct OverlayHold {
    static let seconds: TimeInterval = 2

    /// Whether the overlay's buttons are down: both sticks pressed – or, on a pad without stick
    /// buttons (nil), ☰ and ⧉ together.
    static func chord(leftStick: Bool?, rightStick: Bool?, menu: Bool, view: Bool) -> Bool {
        if let leftStick, let rightStick { return leftStick && rightStick }
        return menu && view
    }

    /// Whether the buttons are still down, at an event from any pad. Each pad reports by itself, and a second
    /// player's moving stick counted as the first one letting go: in a game for two the hold never got
    /// to its two seconds. The other pads are looked at only while a hold is under way, not at every event.
    static func stillHeld(thisPad: Bool, holdUnderWay: Bool, anyPad: @autoclosure () -> Bool) -> Bool {
        thisPad || (holdUnderWay && anyPad())
    }

    /// When the hold began; nil while nothing is held.
    private(set) var since: TimeInterval?
    private var fired = false

    /// When the current hold reaches two seconds, while it hasn't yet.
    var due: TimeInterval? { fired ? nil : since.map { $0 + Self.seconds } }

    /// True once a hold reaches two seconds, then not again until it's let go.
    mutating func update(pressed: Bool, now: TimeInterval) -> Bool {
        guard pressed else {
            since = nil
            fired = false
            return false
        }
        let start = since ?? now
        since = start
        guard !fired, now - start >= Self.seconds else { return false }
        fired = true
        return true
    }
}

/// A game's processes, to pause or end it.
enum GameProcesses {
    struct Entry: Equatable {
        var pid: pid_t
        var parent: pid_t
        var command: String
        /// Its working folder, for a Windows program (`table`).
        var cwd: String? = nil
    }

    /// Every process with its parent and command line, as ps shows them – a Windows program with
    /// its working folder too (`runsFrom`) – or why there is no list (`ProcessList`: `ps` has been seen not
    /// answering for good). `.fresh` and empty means "no process"; `.unavailable` means "not known", and
    /// whoever would conclude from an empty list that a game is gone must not. `allowOld`: the last good
    /// list in its place while `ps` is down.
    nonisolated static func lookup(allowOld: Bool = false) -> ProcessListing<[Entry]> {
        ProcessList.listing("pid=,ppid=,command=", allowOld: allowOld).map(entries(from:))
    }

    /// The list asked for just now, [] without one: for what acts on pids (pausing a game, ending it), which
    /// has nothing to act on then.
    nonisolated static func table() -> [Entry] { lookup().value ?? [] }

    nonisolated private static func entries(from output: String) -> [Entry] {
        parse(output).map { entry in
            var entry = entry
            if entry.command.lowercased().contains(".exe") { entry.cwd = cwd(of: entry.pid) }
            return entry
        }
    }

    /// The games of `folders` (`running`) that run now, nil when no list is to be had at all: the last good
    /// one stands in while `ps` is down, and a game running when it went down is still running then, as far
    /// as anyone can tell. Nil means "not known" – not "no game".
    nonisolated static func runningNow(_ folders: [String: String]) -> [String: pid_t]? {
        guard !folders.isEmpty else { return [:] }
        return lookup(allowOld: true).value.map { running(folders, in: $0) }
    }

    /// Where one game stands by the list at hand. Only a list asked for just now says it is `gone`: an
    /// old one (`ps` is down) says `running` for a game that was in it – it ran when the list was made –
    /// and `unknown` for one that wasn't, which may have started since. `unknown` decides nothing.
    enum Presence: Equatable {
        case running(pid_t)
        case gone
        case unknown

        /// A game that may be running: it was seen, or can't be told apart from one that is.
        var mayBeRunning: Bool { self != .gone }
    }

    /// `id`'s standing by `listing`; `folders` as for `running` (marker → id).
    nonisolated static func presence(of id: String, folders: [String: String], in listing: ProcessListing<[Entry]>) -> Presence {
        switch listing {
        case .fresh(let table): return running(folders, in: table)[id].map(Presence.running) ?? .gone
        case .old(let table): return running(folders, in: table)[id].map(Presence.running) ?? .unknown
        case .unavailable: return .unknown
        }
    }

    /// The same for the list asked for now (the last good one stands in while `ps` is down).
    nonisolated static func presence(of id: String, folders: [String: String]) -> Presence {
        presence(of: id, folders: folders, in: lookup(allowOld: true))
    }

    /// What the curtain's look at the start needs from the list: the game's processes, whether the app in
    /// front is a Windows program of the game's, and macOS's own askers – all from the one list, so that a
    /// look is one `ps` (and one scan of the programs' folders). Nil when nothing can be decided at that look:
    /// no list, or an old one that doesn't show the game (it may have started since; an old list only says "there").
    struct CurtainLook: Equatable {
        var pids: Set<pid_t>
        var companion: Bool
        var askers: Set<pid_t>
    }

    nonisolated static func curtainLook(marker: String?, folder: String?, front: pid_t?) -> CurtainLook? {
        curtainLook(marker: marker, folder: folder, front: front, in: lookup(allowOld: true))
    }

    nonisolated static func curtainLook(marker: String?, folder: String?, front: pid_t?,
                                        in listing: ProcessListing<[Entry]>) -> CurtainLook? {
        guard let table = listing.value else { return nil }
        let pids = Set(targets(windows: marker, mac: folder, in: table))
        if case .old = listing, pids.isEmpty { return nil }
        return CurtainLook(pids: pids, companion: marker != nil && front.map { windowsCompanion($0, in: table) } == true,
                           askers: macOSAskers(in: table))
    }

    /// A process's working folder (another user's, or one gone meanwhile: nil).
    nonisolated static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    /// The Windows game folders processes show (`Game.windowsFolderMarker`): Steam's, Epic's, GOG's.
    nonisolated static let gameFolders = [#"\steamapps\common\"#, #"\Epic Games\"#, #"\GOG Games\"#]

    /// Whether a Windows program runs from one of `folders` (`Game.windowsFolderMarker`, or any
    /// game's: `gameFolders`). Wine names a program by its Windows path, which shows the folder – or,
    /// started by a launcher with its bare name, only by that: Control's launcher starts
    /// "Control_DX11.exe -AUTH_LOGIN=…" (2.11.), and the game counted as ended with the launcher.
    /// Then its working folder tells: Wine gives a program its Windows working folder as its own
    /// (winecx, spawn_process), and on the Mac the game folder is the same folders by name (in the
    /// Windows environment, or Z:\Volumes\…\Nightforge Games on a drive). Not Windows' own programs,
    /// nor Steam's, whose working folder may be a game's.
    nonisolated static func runsFrom(_ folders: [String], command: String, cwd: String?) -> Bool {
        let command = command.lowercased()
        guard command.contains(".exe") else { return false }
        let folders = folders.map { $0.lowercased() }
        if folders.contains(where: command.contains) { return true }
        guard let cwd, !command.contains(#"c:\windows\"#), !command.contains("steamwebhelper"),
              !(command.contains(#"\steam\"#) && !command.contains(#"\steamapps\"#))
        else { return false }
        let path = cwd.lowercased() + "/"
        return folders.contains { path.contains($0.replacingOccurrences(of: "\\", with: "/")) }
    }

    /// The first process of each game (`folders`: a Windows game's `windowsFolderMarker`, a Mac
    /// game's folder with a trailing slash → its id), in the order ps lists them. Steam's crash
    /// handler and similar helpers live in the same folder; the game's own process is the first
    /// program there that isn't one of those. A Mac version's program itself runs from the folder
    /// ("/…/steamapps/common/Game/Game.app/Contents/MacOS/Game"); a script that merely names the
    /// folder doesn't count.
    nonisolated static func running(_ folders: [String: String], in table: [Entry]) -> [String: pid_t] {
        var result: [String: pid_t] = [:]
        for entry in table {
            let command = entry.command.lowercased()
            guard !command.contains("crashhandler"), !command.contains("unitycrash") else { continue }
            for (folder, id) in folders where result[id] == nil {
                let matches = folder.hasPrefix("/") ? command.hasPrefix(folder.lowercased())
                                                    : runsFrom([folder], command: command, cwd: entry.cwd)
                if matches { result[id] = entry.pid }
            }
        }
        return result
    }

    /// ps's `pid ppid command` lines.
    nonisolated static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]), let parent = pid_t(fields[1]) else { return nil }
            return Entry(pid: pid, parent: parent, command: String(fields[2]))
        }
    }

    /// Whether `pid` is a Windows program other than Steam (Wine names it by its Windows path):
    /// a game's launcher, overlay or dialog in front is the game's side, not another app.
    nonisolated static func windowsCompanion(_ pid: pid_t, in table: [Entry]) -> Bool {
        guard let command = table.first(where: { $0.pid == pid })?.command.lowercased() else { return false }
        let windowsPath = command.dropFirst().hasPrefix(#":\"#) && command.first?.isLetter == true
        return windowsPath && command.contains(".exe") && !command.contains(#"\steam\steam.exe"#)
            && !command.contains("steamwebhelper")
    }

    /// The game's processes and whatever they started, however deep: a Windows game by its folder
    /// in Wine's command line (`Game.windowsFolderMarker`) or as its working folder (`runsFrom`: Wine
    /// starts a program with launchd as its parent, so what a launcher started isn't found below it),
    /// a Mac game by its folder. Never the Wine
    /// session (wineserver and Windows' own programs), Steam or Nightforge, which other games share.
    nonisolated static func targets(windows marker: String?, mac folder: String?, in table: [Entry],
                                    me: pid_t = getpid()) -> [pid_t] {
        func spared(_ entry: Entry) -> Bool {
            let command = entry.command.lowercased()
            return entry.pid == me || entry.pid <= 1 || command.contains("wineserver") || command.contains(#"c:\windows\"#)
                || command.contains(#"\steam\steam.exe"#) || command.contains("steamwebhelper") || command.contains("/steam.app/")
        }
        func belongs(_ entry: Entry) -> Bool {
            if let marker { return runsFrom([marker], command: entry.command, cwd: entry.cwd) }
            if let folder { return entry.command.lowercased().hasPrefix(folder.lowercased() + "/") }
            return false
        }
        var found = Set(table.filter { belongs($0) && !spared($0) }.map(\.pid))
        var grew = !found.isEmpty
        while grew {
            grew = false
            for entry in table where !found.contains(entry.pid) && found.contains(entry.parent) && !spared(entry) {
                found.insert(entry.pid)
                grew = true
            }
        }
        return found.sorted()
    }

    /// Ends `pids`: woken (a stopped process takes no other signal), asked to end, and after
    /// `patience` killed – a game that hangs doesn't answer. Returns when they're gone.
    nonisolated static func end(_ pids: [pid_t], patience: TimeInterval = 3) {
        for pid in pids {
            kill(pid, SIGCONT)
            kill(pid, SIGTERM)
        }
        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline, pids.contains(where: alive) { Thread.sleep(forTimeInterval: 0.1) }
        for pid in pids where alive(pid) { kill(pid, SIGKILL) }
        let killed = Date().addingTimeInterval(2)
        while Date() < killed, pids.contains(where: alive) { Thread.sleep(forTimeInterval: 0.05) }
    }

    /// Running (or stopped), not ended: a process that's gone but not yet collected by its parent
    /// (a zombie) counts as ended.
    nonisolated static func alive(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }

    /// The one of `pids` with the most memory: a game's own program, not the launcher that waits for
    /// it (for `sample` in the game test).
    nonisolated static func biggest(_ pids: [pid_t]) -> pid_t? {
        func resident(_ pid: pid_t) -> UInt64 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info.pti_resident_size : 0
        }
        return pids.max { resident($0) < resident($1) }
    }

    /// When a process started; nil for one that's gone.
    nonisolated static func started(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// Stopped by SIGSTOP.
    nonisolated static func stopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status == UInt32(SSTOP)
    }

    /// A captured display's shield: black, the size of the screen, and the game's own window lies a
    /// level or two above it (L…630 or L…629 in every run with a picture, Overwatch, ABZU, Control).
    /// Overwatch's black start on 8.11. 13:40 had only this one on screen, its real window hidden,
    /// while DXMT drew 57 FPS into nothing – and the curtain sank for it.
    nonisolated static func isShield(level: Int) -> Bool { level == Int(CGShieldingWindowLevel()) }

    /// Whether one of `pids` shows a window of a game's size on screen (CGWindowList's entries):
    /// what the curtain waits for. Small ones – a splash, a launcher's dialog – don't count, nor
    /// does a captured display's black shield (`isShield`).
    nonisolated static func showsWindow(_ windows: [[String: Any]], pids: Set<pid_t>) -> Bool {
        windows.contains { window in
            let level = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  level >= 0, !isShield(level: level),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return width >= 640 && height >= 360
        }
    }

    /// A window of the game's that waits for an answer – a driver warning, an EULA, a launcher's
    /// question (Black Myth: Wukong's driver warning, about 380 × 330, lay under the curtain on
    /// 1.11.): on the Space shown, smaller than a picture (`showsWindow`) but more than a sliver, a
    /// window up to a modal panel's level – Wine lifts a topmost one (that warning, seen over
    /// Nightforge's page) to the floating level; menus lie higher. Its number, the frontmost first.
    /// Its title, which would tell it from a splash, can't be read without Screen Recording.
    nonisolated static func question(_ windows: [[String: Any]], pids: Set<pid_t>) -> Int? {
        questionWindow(windows, pids: pids)?.number
    }

    /// The same with its size: a thin one may be a splash (`LibraryModel.takenAsQuestion`).
    nonisolated static func questionWindow(_ windows: [[String: Any]], pids: Set<pid_t>) -> (number: Int, size: CGSize)? {
        let asking = windows.first { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  questionLevel((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return width >= 200 && height >= 100 && !(width >= 640 && height >= 360)
        }
        guard let asking, let number = (asking[kCGWindowNumber as String] as? NSNumber)?.intValue, let frame = bounds(asking) else { return nil }
        return (number, frame.size)
    }

    /// Steam's windows on the Space shown, front to back, its tiny menu windows left out: what its
    /// question on the curtain is (`pids`: the processes that show them).
    nonisolated static func steamWindows(_ windows: [[String: Any]], pids: Set<pid_t>) -> [Int] {
        windows.filter { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  questionLevel((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let frame = bounds(window)
            else { return false }
            return frame.width >= 200 && frame.height >= 100
        }.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }

    nonisolated static func steamWindows(pids: Set<pid_t>) -> [Int] {
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return steamWindows(windows, pids: pids)
    }

    /// The levels a question can be at: normal up to a modal panel, and winecx's own for a topmost
    /// window – just above the Dock (cocoa_app.m, adjustWindowLevels: kCGDockWindowLevel + 1). There
    /// Black Myth: Wukong's driver warning stood in both game tests on 2.11. (286×251 L21), under the
    /// curtain, which never made way: the game never got the front and counted as hanging.
    nonisolated static func questionLevel(_ level: Int) -> Bool {
        (0...Int(CGWindowLevelForKey(.modalPanelWindow))).contains(level) || level == Int(CGWindowLevelForKey(.dockWindow)) + 1
    }

    nonisolated static func question(_ pids: Set<pid_t>) -> Int? {
        questionWindow(pids)?.number
    }

    nonisolated static func questionWindow(_ pids: Set<pid_t>) -> (number: Int, size: CGSize)? {
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return questionWindow(windows, pids: pids)
    }

    /// The programs macOS asks the player through. TCC's permissions – files on a removable or
    /// network volume, a folder, the camera, the microphone, the local network: tccd shows them
    /// through CFUserNotification, which UserNotificationCenter draws (Tomb Raider's on its drive lay
    /// under the curtain on 2.11.), or through AuthorizationPromptService – Accessibility's
    /// (universalAccessAuthWarn), location's (CoreLocationAgent), Gatekeeper's for an app from the
    /// internet (CoreServicesUIAgent), a password or Touch ID (SecurityAgent, coreautha).
    nonisolated static let macOSAskers = [
        "/System/Library/CoreServices/UserNotificationCenter.app/",
        "/System/Library/CoreServices/AuthorizationPromptService.app/",
        "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Resources/universalAccessAuthWarn.app/",
        "/System/Library/CoreServices/CoreLocationAgent.app/",
        "/System/Library/CoreServices/CoreServicesUIAgent.app/",
        "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle/",
        "/System/Library/Frameworks/LocalAuthentication.framework/Support/coreautha.bundle/",
    ]

    /// Their processes in `table`.
    nonisolated static func macOSAskers(in table: [Entry]) -> Set<pid_t> {
        Set(table.filter { entry in macOSAskers.contains { entry.command.hasPrefix($0) } }.map(\.pid))
    }

    /// Their windows on the Space shown – they show one only while they ask, none of a picture's
    /// size: their numbers, the frontmost first. At any level from the windows' up, an alert may lie
    /// high; more than a sliver.
    nonisolated static func macOSQuestions(_ windows: [[String: Any]], askers: Set<pid_t>) -> [Int] {
        windows.filter { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, askers.contains(owner),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 >= 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return width >= 150 && height >= 60
        }.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }

    /// The frontmost of them.
    nonisolated static func macOSQuestion(_ windows: [[String: Any]], askers: Set<pid_t>) -> Int? {
        macOSQuestions(windows, askers: askers).first
    }

    nonisolated static func macOSQuestions(askers: Set<pid_t>) -> [Int] {
        guard !askers.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return macOSQuestions(windows, askers: askers)
    }

    /// A window's frame in CGWindowList's terms (`kCGWindowBounds`): from the main display's top left.
    nonisolated static func bounds(_ window: [String: Any]) -> CGRect? {
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// A screen's frame (AppKit's, from the main display's bottom left) in CGWindowList's terms.
    @MainActor
    static func cgRect(_ frame: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? frame.maxY
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Whether a window covers most of `area`: a game's picture or a shield, not the menu bar, a
    /// banner or the Dock.
    nonisolated static func covers(_ window: [String: Any], _ area: CGRect) -> Bool {
        guard let frame = bounds(window), (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { return false }
        let overlap = frame.intersection(area)
        return !overlap.isNull && overlap.width * overlap.height >= area.width * area.height / 2
    }

    /// The display the largest of `pids`' windows is on (its middle); nil without one.
    nonisolated static func display(of windows: [[String: Any]], pids: Set<pid_t>) -> CGDirectDisplayID? {
        let frames = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber).map { pids.contains($0.int32Value) } ?? false }
            .compactMap(bounds)
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(CGPoint(x: largest.midX, y: largest.midY), 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    /// The highest level of a window that covers `screen`, not one of `except`'s (Nightforge's own
    /// curtain); nil without one.
    nonisolated static func coverLevel(_ windows: [[String: Any]], screen: CGRect, except: pid_t) -> Int? {
        windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != except && covers($0, screen) }
            .map { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 }.max()
    }

    /// What lies in front of `window` (`windows`: the Space shown, front to back) over most of it;
    /// nil when it isn't there at all.
    nonisolated static func covering(_ windows: [[String: Any]], window: Int) -> [[String: Any]]? {
        guard let index = windows.firstIndex(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == window }),
              let area = bounds(windows[index])
        else { return nil }
        return windows[..<index].filter { covers($0, area) }
    }

    /// Windows for wine.log: "ABZU L27 1512×982".
    nonisolated static func describe(_ windows: [[String: Any]]) -> String {
        windows.map { window in
            let size = bounds(window).map { "\(Int($0.width))×\(Int($0.height))" } ?? "?"
            return "\(window[kCGWindowOwnerName as String] as? String ?? "?") L\((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) \(size)"
        }.joined(separator: ", ")
    }

    /// The game's windows as the curtain sees them, for wine.log: "380×332 L3, 1512×982 L0, 2 hidden".
    nonisolated static func windowList(_ pids: Set<pid_t>) -> String {
        guard !pids.isEmpty,
              let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let shown = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return "none" }
        func number(_ window: [String: Any]) -> Int { (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0 }
        let onScreen = Set(shown.map(number))
        let mine = all.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber).map { pids.contains($0.int32Value) } ?? false }
        let listed = mine.filter { onScreen.contains(number($0)) }.compactMap { window -> String? in
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.intValue, let height = (bounds["Height"] as? NSNumber)?.intValue
            else { return nil }
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return "\(width)×\(height) L\((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)" + (alpha > 0 ? "" : " clear")
        }
        let hidden = mine.count - listed.count
        let parts = listed + (hidden > 0 ? ["\(hidden) hidden"] : [])
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    /// On the Space shown, or (`anySpace`) wherever it is: a game's window opens in its own Space
    /// or the desktop's while Nightforge's full screen is shown, and only the list of all windows
    /// has it then.
    nonisolated static func showsWindow(_ pids: Set<pid_t>, anySpace: Bool = false) -> Bool {
        let options: CGWindowListOption = anySpace ? [.optionAll, .excludeDesktopElements] : [.optionOnScreenOnly]
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return showsWindow(windows, pids: pids)
    }

    /// `pids` have a captured display's shield on the Space shown and no picture above it: the screen
    /// is black, whatever the game draws (`isShield`).
    nonisolated static func onlyShield(_ windows: [[String: Any]], pids: Set<pid_t>) -> Bool {
        !showsWindow(windows, pids: pids) && windows.contains { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner) else { return false }
            return isShield(level: (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
        }
    }

    nonisolated static func onlyShield(_ pids: Set<pid_t>) -> Bool {
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return onlyShield(windows, pids: pids)
    }

    /// What the stage watch needs to know of the game's windows; `page`: Nightforge's page behind it;
    /// `level`: the level of its window over the screen shown (`screen`), when it has one.
    nonisolated static func onStage(_ pids: Set<pid_t>, page: Int?, screen: CGRect?) -> (here: Bool, anywhere: Bool, pageOver: Bool, level: Int?) {
        guard !pids.isEmpty, let shown = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return (false, false, false, nil) }
        let here = showsWindow(shown, pids: pids)
        return (here, here || showsWindow(pids, anySpace: true), page.map { pageCovers(shown, page: $0, pids: pids) } ?? false,
                screen.flatMap { pictureLevel(shown, pids: pids, screen: $0) })
    }

    /// The highest level of a window of `pids` over most of `screen`, the black shield aside.
    nonisolated static func pictureLevel(_ windows: [[String: Any]], pids: Set<pid_t>, screen: CGRect) -> Int? {
        windows.filter { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber).map { pids.contains($0.int32Value) } ?? false
                && covers(window, screen) && !isShield(level: (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
        }
        .map { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 }.max()
    }

    /// Whether Nightforge's page lies over the game's picture and none of it in front (`windows`:
    /// the Space shown, front to back).
    nonisolated static func pageCovers(_ windows: [[String: Any]], page: Int, pids: Set<pid_t>) -> Bool {
        guard let index = windows.firstIndex(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == page }) else { return false }
        return !showsWindow(Array(windows[..<index]), pids: pids) && showsWindow(Array(windows[index...]), pids: pids)
    }

    /// The biggest window of `pids` on the Space shown, for wine.log ("1512×945").
    nonisolated static func windowSize(_ pids: Set<pid_t>) -> String? {
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let sizes = windows.compactMap { window -> CGSize? in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return nil }
            return CGSize(width: width, height: height)
        }
        return sizes.max { $0.width * $0.height < $1.width * $1.height }.map { "\(Int($0.width))×\(Int($0.height))" }
    }

    /// A display taken by a game for a mode change: its shield window lies above every other.
    nonisolated static func screenCaptured() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return screenCaptured(windows, me: getpid())
    }

    /// `me`'s own windows don't count: the curtain and the overlay may lie above a shield themselves.
    nonisolated static func screenCaptured(_ windows: [[String: Any]], me: pid_t) -> Bool {
        let shield = Int(CGShieldingWindowLevel())
        return windows.contains {
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 >= shield && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != me
        }
    }
}
