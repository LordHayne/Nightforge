import AppKit
import SwiftUI

/// The controller's way out of a game, from the sofa. Both sticks pressed and held for two seconds
/// in a game bring a calm panel over it: Continue Playing, Quit Game (one that hangs as well) and
/// Go to Nightforge. Not the PS/Xbox button: since macOS 26 it opens Apple's Game Overlay (and
/// Nightforge can't take it from the game in front), and Create/Share carries macOS's screenshot
/// and recording gestures (System Settings › Game Controllers, macOS 27); the stick buttons carry
/// none. A pad without them uses ☰ and ⧉ (`OverlayHold.chord`).
///
/// The pad reaches Nightforge in the background (InputRouter); the game gets the same presses,
/// which macOS can't take from it. So a Windows game is paused while the panel is up (SIGSTOP):
/// Wine's pad driver runs in winedevice.exe, not in the game, and XInput hands the game the pad's
/// state when it runs on, not the presses made meanwhile; its sound pauses with it. A Mac game reads
/// the pad through GameController's events, which would all arrive at once afterwards – it keeps
/// running and may react to the presses.
@MainActor
enum GameOverlay {
    final class State: ObservableObject {
        @Published var step = OverlayStep.menu
        @Published var game = ""
        @Published var paused = false
        @Published var symbols = PadSymbols()
        /// The output the game still plays to after the default changed (GameAudio.gameStillOn).
        @Published var soundStaysOn: String?
    }

    /// What the model does for the choices.
    struct Actions {
        /// Ends the game's processes (`GameProcesses.end`), off the main thread.
        var quit: () async -> Void
        /// Nightforge in front, the game left running behind it; done once it's there or can't be.
        var nightforge: () async -> Void
    }

    private static let state = State()
    private static var panel: NSPanel?
    private static var actions: Actions?
    /// On the way to Nightforge: the panel stays until it's there, and takes no more presses.
    private static var leaving = false
    private static var pausedKey: String { "overlayPaused" }

    static var isOpen: Bool { panel?.isVisible == true }
    /// Open with "Not starting?" (or the question it led to).
    static var asksAboutStart: Bool { isOpen && state.step == .notStarting }
    /// The panel, while it's up: the pad's input goes there (InputRouter).
    static var window: NSWindow? { isOpen ? panel : nil }

    /// Over `game` on `screen`. `pause`: its processes, stopped until the panel goes. `step`:
    /// `.notStarting` for a game that runs but shows nothing (LibraryModel's curtain).
    /// `soundStaysOn`: the device a Windows game still plays to after the default output changed.
    static func open(_ game: String, pause: [pid_t], on screen: NSScreen?, symbols: PadSymbols,
                     step: OverlayStep = .menu, soundStaysOn: String? = nil, actions: Actions) {
        guard !isOpen, let screen = screen ?? NSScreen.main else { return }
        self.actions = actions
        state.game = game
        state.soundStaysOn = soundStaysOn
        state.symbols = symbols
        state.step = step
        stop(pause)
        state.paused = !pause.isEmpty
        let panel = self.panel ?? make()
        self.panel = panel
        panel.setFrame(screen.frame, display: false)
        // A game that took the screen for itself (a real display-mode change) has a shield above
        // every window: Nightforge comes to the front instead, with the same choice.
        if GameProcesses.screenCaptured() { comeForward() }
        panel.orderFrontRegardless()
        panel.makeKey()
        focusDefault()
        heard = false
        GameLog.note("Overlay up (\(step)) for \(game): \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nobody") in front")
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
    static func toNightforge() { handle(.nightforge) }

    private static func handle(_ event: OverlayEvent) {
        guard !leaving else { return }
        // In wine.log: which presses arrive (the pad on "Not starting?", 1.11.), and who's in front.
        GameLog.note("Overlay: \(event) on \(state.step), \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nobody") in front"
                     + (panel?.isKeyWindow == true ? "" : ", the panel without the keys"))
        let (step, effect) = transition(state.step, event)
        if step != state.step { show(step) }
        switch effect {
        case .none:
            break
        case .close:
            InputRouter.hidePointerForGame()  // while the panel still has the keys
            close()
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
            cont()
            leaving = true
            Task {
                await actions.nightforge()
                leaving = false
                close()
            }
        }
    }

    enum Effect: Equatable { case none, close, quit, nightforge }

    /// The overlay's steps: B steps back, the sticks held again go back to the game from anywhere
    /// but the quitting, and a game is only quit from the question.
    nonisolated static func transition(_ step: OverlayStep, _ event: OverlayEvent) -> (OverlayStep, Effect) {
        switch (step, event) {
        case (.quitting, _): return (.quitting, .none)
        case (.menu, .back), (.notStarting, .back), (_, .resume): return (step, .close)
        case (.menu, .askQuit), (.notStarting, .askQuit): return (.confirmQuit, .none)
        case (.menu, .nightforge), (.notStarting, .nightforge): return (step, .nightforge)
        case (.confirmQuit, .back): return (.menu, .none)
        case (.confirmQuit, .quit): return (.quitting, .quit)
        default: return (step, .none)
        }
    }

    /// Also when Nightforge quits: a paused game never stays paused.
    static func close() {
        cont()
        panel?.orderOut(nil)
        PadFocus.shared.clear()
        actions = nil
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
        if let id = defaultButton(state.step) { PadFocus.shared.focus(id) }
    }

    /// The button a step's highlight starts on (its `padFocus` id): the safe answer.
    nonisolated static func defaultButton(_ step: OverlayStep) -> String? {
        switch step {
        case .menu: return "overlay.continue"
        case .notStarting: return "overlay.wait"
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

    private static func comeForward() { NSApp.comeToFront() }

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
        let host = NSHostingView(rootView: OverlayView(state: state).modifier(AccessibilityFromSettings()))
        host.sizingOptions = []  // the screen's size, not the content's
        panel.contentView = host
        return panel
    }
}

enum OverlayStep: Equatable { case menu, notStarting, confirmQuit, quitting }

enum OverlayEvent { case back, resume, askQuit, quit, nightforge }

/// Takes keys without making Nightforge the active app, so the game's Space stays where it is.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { GameOverlay.back() }  // Esc
}

private struct OverlayView: View {
    @ObservedObject var state: GameOverlay.State

    var body: some View {
        ZStack {
            // Dimmed, not blurred: a live blur over the whole picture would cost the game frames.
            Color.black.opacity(0.62)
            VStack(spacing: 14) {
                switch state.step {
                case .menu: menu
                case .notStarting: notStarting
                case .confirmQuit: question
                case .quitting:
                    Text(L10n.t("Quitting %@ …", state.game))
                        .font(size: 20, weight: .semibold)
                }
            }
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(36)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14)))
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var menu: some View {
        Text(state.game)
            .font(size: 24, weight: .semibold)
            .lineLimit(2)
        if state.paused {
            Text(L10n.t("Paused"))
                .font(size: 14)
                .foregroundStyle(Theme.muted)
        }
        // Wine keeps the device it opened: a change in the menu bar reaches the game's next start.
        if let device = state.soundStaysOn {
            Text(L10n.t("The game plays its sound on %@ until it starts again.", device))
                .font(size: 13)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        VStack(spacing: 12) {
            choice("overlay.continue", L10n.t("Continue Playing"), tint: Theme.sodium, preferred: true) { GameOverlay.resume() }
            choice("overlay.quit", L10n.t("Quit Game")) { GameOverlay.askQuit() }
            choice("overlay.nightforge", L10n.t("Go to Nightforge")) { GameOverlay.toNightforge() }
        }
        .padding(.top, 10)
        // How it closes, and how it opens next time.
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: state.symbols.back)
                Text(L10n.t("Continue Playing"))
            }
            HStack(spacing: 6) {
                OverlayChord(symbols: state.symbols)
                Text(L10n.t("Hold: this menu"))
            }
        }
        .font(size: 12, weight: .medium)
        .foregroundStyle(Theme.muted)
        .padding(.top, 8)
    }

    /// The game runs but has shown nothing for a minute (LibraryModel's curtain).
    @ViewBuilder private var notStarting: some View {
        Text(L10n.t("%@ isn't starting?", state.game))
            .font(size: 22, weight: .semibold)
        Text(L10n.t("It runs, but hasn't shown a picture yet. Some games take long the first time."))
            .font(size: 14)
            .foregroundStyle(Theme.muted)
        VStack(spacing: 12) {
            choice("overlay.wait", L10n.t("Keep Waiting"), tint: Theme.sodium, preferred: true) { GameOverlay.resume() }
            choice("overlay.nightforge", L10n.t("Go to Nightforge")) { GameOverlay.toNightforge() }
            choice("overlay.quit", L10n.t("Quit Game")) { GameOverlay.askQuit() }
        }
        .padding(.top, 10)
    }

    @ViewBuilder private var question: some View {
        Text(L10n.t("Quit %@?", state.game))
            .font(size: 22, weight: .semibold)
        Text(L10n.t("What wasn't saved is lost. A game that no longer responds ends as well."))
            .font(size: 14)
            .foregroundStyle(Theme.muted)
        HStack(spacing: 12) {
            choice("overlay.cancel", L10n.t("Cancel"), preferred: true) { GameOverlay.back() }
            choice("overlay.confirmQuit", L10n.t("Quit Game"), tint: Theme.danger) { GameOverlay.quit() }
        }
        .padding(.top, 10)
    }

    private func choice(_ id: String, _ title: String, tint: Color? = nil, preferred: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(OverlayButtonStyle(tint: tint))
            .padFocus(id, cornerRadius: 24, preferred: preferred, activate: action)
    }
}

/// Solid, without the glass's frosted backdrop, which would blur the game behind live.
private struct OverlayButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size: 16, weight: .semibold)
            .foregroundStyle(tint != nil ? Theme.night : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(tint ?? .white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(.white.opacity(tint != nil ? 0.3 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
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
    /// its working folder too (`runsFrom`).
    nonisolated static func table() -> [Entry] {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return parse(output).map { entry in
            var entry = entry
            if entry.command.lowercased().contains(".exe") { entry.cwd = cwd(of: entry.pid) }
            return entry
        }
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

    /// Stopped by SIGSTOP.
    nonisolated static func stopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status == UInt32(SSTOP)
    }

    /// Whether one of `pids` shows a window of a game's size on screen (CGWindowList's entries):
    /// what the curtain waits for. Small ones – a splash, a launcher's dialog – don't count.
    nonisolated static func showsWindow(_ windows: [[String: Any]], pids: Set<pid_t>) -> Bool {
        windows.contains { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 >= 0,
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
        let asking = windows.first { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  (0...Int(CGWindowLevelForKey(.modalPanelWindow))).contains((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return width >= 200 && height >= 100 && !(width >= 640 && height >= 360)
        }
        return asking.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }

    nonisolated static func question(_ pids: Set<pid_t>) -> Int? {
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return question(windows, pids: pids)
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

    /// A window of theirs on the Space shown – they show one only while they ask, none of a picture's
    /// size: its number, the frontmost first. At any level from the windows' up, an alert may lie
    /// high; more than a sliver.
    nonisolated static func macOSQuestion(_ windows: [[String: Any]], askers: Set<pid_t>) -> Int? {
        let asking = windows.first { window in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, askers.contains(owner),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 >= 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue, let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return width >= 150 && height >= 60
        }
        return asking.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }

    nonisolated static func macOSQuestion(askers: Set<pid_t>) -> Int? {
        guard !askers.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return macOSQuestion(windows, askers: askers)
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
        let shield = Int(CGShieldingWindowLevel())
        return windows.contains { ($0[kCGWindowLayer as String] as? Int ?? 0) >= shield }
    }
}
