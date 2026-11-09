import AppKit
import SwiftUI

/// Nightforge's page around a game, on the screen it plays on, as with a console.
///
/// - As a curtain (`raise`), over everything but the overlay, in every Space: from the moment
///   the game is handed to its store until it shows its window in front ("Starting …"), and again
///   the moment it ends ("Back to Nightforge …") until Nightforge is in front. Spaces changing
///   underneath, Steam for Mac's window coming up and the desktop stay out of sight.
/// - Behind the game (`show`, `lower`): in every desktop Space, right over Nightforge's window
///   while another app has the front – a game whose window goes before its process ends shows the
///   page then, not Nightforge's (Mafia II on 2.11.) – and below every normal window once
///   Nightforge is in front. It never covers the game; around a game in a window it's the page
///   instead of the desktop.
///
/// It never takes a click, a key or the pad. A loading screen of its own, like the README's banner:
/// the N in brushed metal with its blue light seam (BrandArt, drawn once per size and scale), the
/// game's name under NIGHTFORGE and what's happening, on the night. While it's a curtain a light
/// runs along the seam – a small picture moved, nothing that redraws the screen or costs the game
/// frames; with "Reduce motion" the seam only breathes.
@MainActor
enum GameBackdrop {
    final class State: ObservableObject {
        @Published var game = ""
        @Published var stage = Stage.behind
        /// The step a start is at ("Starting Steam …"), from the first moment on.
        @Published var step: String?
        /// Why it takes a while, once a start takes its time ("Steam runs invisibly in the background …").
        @Published var detail: String?
        /// A tip for new players under it, on their first starts (LaunchTip).
        @Published var tip: LaunchTip?
        /// The way out of a curtain with no game under it yet (CurtainEscape), in the tip's place.
        @Published var wayOut: LaunchTip?
        /// How far an update is, 0 to 1 (the thin bar under the step); nil without one.
        @Published var progress: Double?
        /// Steam's window stands on the curtain: the mark gives way, a bar at the bottom says what to do.
        @Published var steamAsks = false
        /// That question is its licence: said so at the top, with a seam round its window (`seam`) and the way to answer.
        @Published var licence: LicenceLook?
        /// Steam's window on the curtain, in the curtain's coordinates, once it's there.
        @Published var seam: CGRect?
        /// Steam will show the licence at this start, as far as can be told beforehand.
        @Published var licenceAnnounced = false
    }

    /// What the bar under Steam's licence says.
    struct LicenceLook: Equatable {
        var answering: SteamLicence.Answering
        /// R2 or RT, for a pad without a touchpad.
        var click: String
    }

    enum Stage: Equatable {
        case starting, behind, returning

        var raised: Bool { self != .behind }
    }

    private static let state = State()
    private static var window: NSWindow?
    private static var hiding: Task<Void, Never>?
    private static var observer: NSObjectProtocol?
    private static var spaceObserver: NSObjectProtocol?
    private static var frontObserver: NSObjectProtocol?
    private static var gameOn: @MainActor () -> Bool = { false }
    /// Whether the game being played still shows its window (LibraryModel sets it): with the page
    /// over Nightforge's window, Nightforge coming to the front decides by it where the page goes.
    static var gameShowsWindow: @MainActor () -> Bool = { true }
    /// Another app came to the front with the page behind the game (LibraryModel looks whether its picture went).
    static var frontMoved: @MainActor (pid_t) -> Void = { _ in }
    private static var settling: Task<Void, Never>?
    /// The player quit the game: the curtain stays up, whatever its processes do, until Nightforge
    /// is in front (`hide(once:)`).
    private static var held = false
    private static var raisedAt = Date.distantPast
    /// How long a start shows only its step before saying why.
    static let detailAfter: TimeInterval = 3

    /// Nightforge has the front only to give it back to a game whose window it fetches
    /// (LibraryModel.handFocus): the page stays where it is, or Nightforge's window would flash.
    static var handingOver = false

    private static var spaceChanged = Date.distantPast
    /// The Space shown changed a moment ago: a swipe of the player's, or a game's full screen.
    static var spaceJustChanged: Bool { Date().timeIntervalSince(spaceChanged) < 1.5 }

    /// The page's window while it lies behind the game, for GameStage's look.
    static var pageNumber: Int? { window?.isVisible == true && !state.stage.raised ? window?.windowNumber : nil }

    static var isRaised: Bool { window?.isVisible == true && state.stage.raised }
    private static var upSince = Date.distantFuture
    /// How long the curtain has stood as it is now.
    static var upFor: TimeInterval { Date().timeIntervalSince(upSince) }
    /// Up for the game's end: Nightforge's way back has it now.
    static var isReturning: Bool { isRaised && state.stage == .returning }

    /// Behind `game`, on the screen it plays on – unless the curtain is up, which stays.
    /// `gameOn`: whether it still runs – when Nightforge comes to the front without it (a game
    /// whose end went unseen), the page goes.
    static func show(_ game: String, on screen: NSScreen?, gameOn: @escaping @MainActor () -> Bool) {
        if isRaised, state.game == game { return }
        put(game, on: screen, stage: .behind, gameOn: gameOn)
    }

    /// The curtain over the screen while `game` starts; `tip` for a curtain that comes up for it.
    static func raise(_ game: String, on screen: NSScreen?, tip: LaunchTip? = nil, gameOn: @escaping @MainActor () -> Bool) {
        put(game, on: screen, stage: .starting, tip: tip, gameOn: gameOn)
    }

    /// What's happening: the step at once, the why once the curtain has been up a few seconds, so
    /// a quick start stays calm and a long one doesn't look stuck.
    static func setStatus(_ step: String?, detail: String?, progress: Double? = nil) {
        guard state.stage == .starting else { return }
        if state.step != step { state.step = step }
        if state.progress != progress { state.progress = progress }
        let shown = Date().timeIntervalSince(raisedAt) >= detailAfter ? detail : nil
        if state.detail != shown { state.detail = shown }
    }

    static func setSteamAsks(_ asks: Bool, licence: LicenceLook? = nil) {
        if state.steamAsks != asks { state.steamAsks = asks }
        if state.licence != licence { state.licence = licence }
        if state.seam != nil { state.seam = nil }
        if state.licenceAnnounced { state.licenceAnnounced = false }  // said, or answered
    }

    /// Steam's window under the licence's frame (screen coordinates, y down); nil while it isn't there.
    static func frameSteamWindow(_ frame: CGRect?) {
        guard let window, state.licence != nil else { return }
        let curtain = appKitFrame(bounds: window.frame, mainHeight: CGDisplayBounds(CGMainDisplayID()).height)
        let seam = frame.flatMap { SteamLicence.seam(window: $0, curtain: curtain) }
        if state.seam != seam { state.seam = seam }
    }

    /// A question already on the curtain turned out to be the licence (SteamLicence.framesLate).
    static var licenceStillToSay: Bool { SteamLicence.framesLate(steamAsks: state.steamAsks, framed: state.licence != nil) }

    static func sayLicence(_ look: LicenceLook) { state.licence = look }

    static func announceLicence(for game: String) {
        guard isRaised, state.game == game, !state.steamAsks else { return }
        state.licenceAnnounced = true
    }

    static func setWayOut(_ tip: LaunchTip?) {
        if state.wayOut != tip { state.wayOut = tip }
    }

    /// The curtain's level: just under the overlay – or, `overShield`, above a captured display's shield
    /// and the game over it (L…628, the game L…629 or L…630). Under it, each change of the display mode
    /// turned the curtain black and back (Overwatch's start and end, 8.11.). Not for good: up there it
    /// would cover ⌘-Tab and macOS's own alerts.
    nonisolated static func curtainLevel(overShield: Bool) -> Int {
        overShield ? Int(CGShieldingWindowLevel()) + 3 : NSWindow.Level.screenSaver.rawValue - 1
    }

    /// The curtain's level while it's up, for the overlay to go above it.
    static var raisedLevel: Int? { isRaised ? window?.level.rawValue : nil }

    /// The curtain lies under a question: not moved over anything until that's over.
    private static var underQuestion = false

    /// A Windows game runs: Wine may take the display at any moment, and a curtain that only follows the
    /// shield goes black for as long as it takes to see it. So over it beforehand, from the game's first
    /// process to its end. A Mac game that takes the display is noticed at the next look.
    static var mayCapture = false

    static func expectCapture() {
        mayCapture = true
        keepOverShield()
    }

    /// A game took the display or let it go: the curtain stays over it, the same window, not redrawn.
    static func keepOverShield() {
        guard let window, isRaised, !underQuestion else { return }
        let level = curtainLevel(overShield: mayCapture || GameProcesses.screenCaptured())
        guard window.level.rawValue != level else { return }
        window.level = NSWindow.Level(rawValue: level)
        toFront(window)
        GameLog.note("The curtain goes \(level > NSWindow.Level.screenSaver.rawValue ? "over" : "back under") a captured display's shield")
    }

    /// The screens changed while the page is up (a game setting its display mode, 1920×1200 on a
    /// 1512×982 Mac; the mode restored as it ends): the page keeps to the screen, or it covers only
    /// a corner of it, as the overlay did on 4.11. before it followed.
    static func followScreen() {
        guard let window, let screen = GameDisplay.gameScreen ?? NSScreen.main else { return }
        let frame = currentFrame(of: screen)
        guard shouldFollow(visible: window.isVisible, frame: window.frame, screen: frame) else { return }
        GameLog.note("The page follows the screen: \(Int(frame.width))×\(Int(frame.height))")
        window.setFrame(frame, display: true)
    }

    nonisolated static func shouldFollow(visible: Bool, frame: CGRect, screen: CGRect) -> Bool {
        visible && frame != screen
    }

    /// A display's place in AppKit's coordinates from its bounds in Core Graphics' (y down, the main
    /// display's height the turning point).
    nonisolated static func appKitFrame(bounds: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    /// The screen as it is this moment. NSScreen only learns of a new mode with its notification, a while
    /// after the display has it: until then a page sized by NSScreen covered a corner, the desktop beside it.
    private static func currentFrame(of screen: NSScreen) -> CGRect {
        guard let display = GameDisplay.id(screen) else { return screen.frame }
        return appKitFrame(bounds: CGDisplayBounds(display), mainHeight: CGDisplayBounds(CGMainDisplayID()).height)
    }

    /// Told of a new display mode right as it's set, before NSScreen's notification.
    private static func listenToDisplays() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { GameBackdrop.followScreen() } }
        }, nil)
    }

    /// The page was found over the game's picture (GameProcesses.pageCovers): behind every window.
    /// A Mac game's window lies at the level of the page, and not always above it.
    static func stepAside() {
        guard let window, window.isVisible, !state.stage.raised else { return }
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.orderFrontRegardless()
    }

    /// The page's level right under a game that covers the screen in front (`level`: the game's), when
    /// it's above every normal window. There the page hides what the player shouldn't see as the game's
    /// window closes: Steam's windows, the browser, the desktop. Nil for a game at the normal level, which
    /// the page mustn't get in front of.
    nonisolated static func pageLevel(underGameAt level: Int?) -> Int? {
        let highestUnder = NSWindow.Level.statusBar.rawValue
        guard let level, level > highestUnder else { return nil }
        return highestUnder
    }

    /// The stage watch at each look, while the game has the front with its picture.
    static func keepUnderGame(at level: Int?) {
        guard let window, window.isVisible, !state.stage.raised, let wanted = pageLevel(underGameAt: level),
              window.level.rawValue != wanted
        else { return }
        window.level = NSWindow.Level(rawValue: wanted)
        window.orderFrontRegardless()
    }

    /// The game is in front: the curtain fades and stays behind it.
    static func lower() {
        guard let window, window.isVisible, state.stage.raised else { return }
        hiding?.cancel()
        hiding = Task {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            state.stage = .behind
            arrange(window)
            window.alphaValue = 1
        }
    }

    /// A window of the game's asks something (GameProcesses.question), or one of macOS's
    /// (`macOSQuestions`, the backmost: they all show): the curtain stays, right under it – the game
    /// or macOS has the front – and over everything else, so the question shows on the curtain as on a console. A click beside it lands on the curtain, not on Nightforge's page,
    /// which would come to the front over the question. Back over everything with `raise`; the
    /// game's window coming over it in front lowers it as ever.
    static func makeWay(under question: Int) {
        guard let window, isRaised else { return }
        underQuestion = true
        window.level = .normal
        window.ignoresMouseEvents = false
        window.order(.below, relativeTo: question)
    }

    /// The game's processes are gone, or the player quit it (`held`): the curtain at once,
    /// "Back to Nightforge …".
    static func returning(held: Bool = false) {
        guard !state.game.isEmpty else { return }
        if held {
            self.held = true
            // Never stuck: should the way back not come (a game that never counted as running).
            Task {
                try? await Task.sleep(for: .seconds(20))
                if self.held, isReturning { hide(after: .zero) }
            }
        }
        put(state.game, on: GameDisplay.gameScreen, stage: .returning, gameOn: gameOn)
    }

    /// They came back (a launcher handed over to the game): the game runs on – not after Quit Game,
    /// where a process lingering a moment mustn't drop the curtain halfway.
    static func playing() {
        guard state.stage == .returning, !held else { return }
        state.stage = .behind
        if let window { arrange(window) }
    }

    /// Gone, once Nightforge is in front – `ready` says so (its window on the Space shown) – and a
    /// moment later, so the switch of Spaces has settled.
    /// `then`: what may only show once the curtain is gone ("Welcome back").
    static func hide(once ready: @escaping @MainActor () -> Bool, then: (@MainActor () -> Void)? = nil) {
        hide(after: .milliseconds(350), waitingFor: ready, then: then)
    }

    static func hide(after delay: Duration = .milliseconds(900), waitingFor ready: (@MainActor () -> Bool)? = nil,
                     then: (@MainActor () -> Void)? = nil) {
        guard let window, window.isVisible else {
            then?()
            return
        }
        hiding?.cancel()
        hiding = Task {
            if let ready {
                // While Spaces change underneath, the curtain is put in front again and again: the
                // one shown next has it from its first frame on.
                for look in 0..<60 where !ready() {
                    if isRaised { window.orderFrontRegardless() }
                    if asksFrontAgain(look: look), !NSApp.isActive { NSApp.comeToFront() }
                    try? await Task.sleep(for: .milliseconds(50))
                }  // up to 3 s
                if isRaised { window.orderFrontRegardless() }
            }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Steam Helper took the front back in that moment (Valheim's end, 16:09 on 8.11.): the curtain
            // would go over Steam's window.
            if let ready, !ready() {
                NSApp.comeToFront()
                for _ in 0..<20 where !ready() { try? await Task.sleep(for: .milliseconds(50)) }
                guard !Task.isCancelled else { return }
            }
            held = false
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            then?()
        }
    }

    /// On the way back Nightforge asks for the front once, and macOS may give it to Steam Helper as a
    /// game ends: asked again after half a second and after one and a half, not at every look.
    nonisolated static func asksFrontAgain(look: Int) -> Bool { look == 10 || look == 30 }

    private static func put(_ game: String, on screen: NSScreen?, stage: Stage, tip: LaunchTip? = nil,
                            gameOn: @escaping @MainActor () -> Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        hiding?.cancel()
        state.game = game
        if stage == .starting, state.stage != .starting || !isRaised {
            raisedAt = Date()
            state.step = nil
            state.detail = nil
            state.tip = tip
            state.wayOut = nil
            state.progress = nil
            state.steamAsks = false
            state.licence = nil
            state.seam = nil
            state.licenceAnnounced = false
        }
        if stage.raised, stage != state.stage || !isRaised { upSince = Date() }
        state.stage = stage
        self.gameOn = gameOn
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GameBackdrop.nightforgeInFront() }
        }
        if self.window == nil { listenToDisplays() }
        let window = self.window ?? make(screen.frame)
        self.window = window
        // A curtain is ordered into the Space shown; after a switch of Spaces (Nightforge's full
        // screen, the game's) it's put in front there at once.
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                              object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    GameBackdrop.spaceChanged = Date()
                    guard GameBackdrop.isRaised else { return }
                    GameBackdrop.holdInFront(for: afterSpaceChange)
                    GameLog.note("Space changed under the curtain")
                }
            }
        }
        // Who comes forward under it, in wine.log: what's seen of a flicker has a name then.
        if frontObserver == nil {
            frontObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                              object: nil, queue: .main) { note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // With its process: Steam's Wine and the game's are both "Nightforge Game".
                let app = "\(running?.localizedName ?? "?") (\(running.map { String($0.processIdentifier) } ?? "-"))"
                let other = running?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                MainActor.assumeIsolated {
                    // Behind the game, another app in front (the game again): over Nightforge's window.
                    if other, !GameBackdrop.isRaised {
                        // After the curtain too, in wine.log: who takes the front from a game.
                        if GameBackdrop.window?.isVisible == true, GameBackdrop.gameOn() { GameLog.note("In front over the page: \(app)") }
                        GameBackdrop.otherAppInFront()
                        if let front = running?.processIdentifier { GameBackdrop.frontMoved(front) }
                        return
                    }
                    guard GameBackdrop.isRaised else { return }
                    GameLog.note("In front under the curtain: \(app)")
                    if other { GameBackdrop.holdInFront(for: afterActivation) }
                    // On the way back each app coming forward brought the pointer back. The start
                    // hides it once the game has had the front a moment (LibraryModel.watchCurtain).
                    if GameBackdrop.isReturning { InputRouter.hidePointerSoon() }
                }
            }
        }
        let appearing = !window.isVisible
        window.setFrame(currentFrame(of: screen), display: true)
        window.alphaValue = appearing ? 0 : 1
        arrange(window)
        // Faded in where it wasn't up; from behind the game it's there at once, as it covers its end.
        if appearing {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 1
            }
        }
    }

    /// How long the curtain is put in front again and again after another app comes forward under it, and
    /// after the Space changes. Valheim's own full-screen Space (8.11.) came about a second after its
    /// activation, with the desktop showing until the curtain was ordered into it (`Space changed …`).
    nonisolated static let afterActivation: TimeInterval = 4
    nonisolated static let afterSpaceChange: TimeInterval = 1
    private static var holding: Task<Void, Never>?

    /// Never over a question it lies under (`makeWay`), where the player has to see the question.
    nonisolated static func holdsInFront(raised: Bool, underQuestion: Bool) -> Bool { raised && !underQuestion }

    private static func holdInFront(for seconds: TimeInterval) {
        holding?.cancel()
        let until = Date().addingTimeInterval(seconds)
        holding = Task {
            while !Task.isCancelled, Date() < until, holdsInFront(raised: isRaised, underQuestion: underQuestion), let window {
                toFront(window)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// With the curtain at the top level the overlay shares it: the panel is ordered back above it.
    private static func toFront(_ window: NSWindow) {
        window.orderFrontRegardless()
        if GameOverlay.isOpen { GameOverlay.window?.orderFrontRegardless() }
    }

    /// Nightforge came to the front with the page behind a game. The game gone: the page goes. The
    /// player came over (⌘-Tab, Go to Nightforge): it goes behind Nightforge's window. Without the
    /// game's window macOS handed Nightforge the front as the game ended: the page stays over
    /// Nightforge's window until the end's curtain comes (watchForGameEnd), three seconds at most.
    private static func nightforgeInFront() {
        guard let window, window.isVisible, !isRaised, !handingOver else { return }
        guard gameOn() else { return hide() }
        settling?.cancel()
        guard !gameShowsWindow() else { return arrange(window, nightforgeFront: true) }
        settling = Task {
            for _ in 0..<30 where !isRaised && gameOn() {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, window.isVisible, !isRaised else { return }
            if gameOn() { arrange(window) } else { hide() }
        }
    }

    /// Another app came to the front – the game, given the front again: the page over Nightforge's
    /// window again.
    private static func otherAppInFront() {
        guard let window, window.isVisible, !isRaised else { return }
        settling?.cancel()
        arrange(window, nightforgeFront: false)
    }

    /// The curtain above the other windows and over full-screen Spaces too – other apps' as well
    /// (the game's, Steam's), so it stays where it is while macOS slides from one Space to the
    /// next: without, it slid out with the Space it was in and Nightforge's page slid in (the
    /// monitor test on 1.11.). Behind, right over Nightforge's window while another app has the
    /// front – the game's window going before its process ended showed Nightforge's page for a
    /// moment before the curtain (Mafia II, 2.11.) – and above the desktop's icons only once
    /// Nightforge is in front.
    private static func arrange(_ window: NSWindow, nightforgeFront: Bool? = nil) {
        window.ignoresMouseEvents = true  // taken under a question (makeWay)
        underQuestion = false
        if state.stage.raised {
            window.level = NSWindow.Level(rawValue: curtainLevel(overShield: mayCapture || GameProcesses.screenCaptured()))  // the overlay above it
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            // Only in the Space of Nightforge's window: in a Space of the game's own (a Mac version in
            // macOS's full screen) there's no window to lie over, only the game (Valheim, 7.11.).
            if !(nightforgeFront ?? NSApp.isFrontmost), let main = NSApp.windows.first(where: { $0.title == "Nightforge" }), main.isVisible,
               main.isOnActiveSpace {
                window.level = .normal
                window.order(.above, relativeTo: main.windowNumber)
                return
            }
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
        toFront(window)
    }

    /// The brand's pictures (BrandArt), drawn once per size and scale: sharp on a 4K TV as on the
    /// MacBook, and nothing to draw again after that.
    private static var pictures: [String: CGImage] = [:]

    static func picture(_ name: String, size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let key = "\(name) \(Int(size.width))×\(Int(size.height)) @\(scale)"
        if let picture = pictures[key] { return picture }
        let picture = BrandArt.image(size: size, scale: scale, draw: draw)
        pictures[key] = picture
        return picture
    }

    private static func make(_ frame: CGRect) -> NSWindow {
        // A panel that never activates Nightforge: only such a window may join other apps' full-screen Spaces.
        let window = CurtainPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = NSColor(Theme.night)
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        let host = NSHostingView(rootView: BackdropView(state: state).modifier(AccessibilityFromSettings()))
        host.sizingOptions = []  // the screen's size, not the content's
        window.contentView = host
        return window
    }
}

/// Never key or main: keys and the pad stay with the game, or with Nightforge's window.
private final class CurtainPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct BackdropView: View {
    @ObservedObject var state: GameBackdrop.State

    var body: some View {
        ZStack {
            BrandNight()
            // One fade each way, between two pages that stand still.
            if state.stage == .starting && state.steamAsks {
                SteamQuestionFrame(game: state.game, wayOut: state.wayOut, licence: state.licence, seam: state.seam)
                    .transition(.opacity)
            } else {
                page.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.steamAsks)
        .clipped()
        .ignoresSafeArea()
    }

    private var page: some View {
            VStack(spacing: 0) {
                BrandMark(moving: state.stage.raised)
                // The banner's wordmark, and under it the game in the blue of its tagline.
                Spaced(text: "NIGHTFORGE", kern: 15)
                    .fontWidth(.expanded)
                    .font(size: 50, weight: .light)
                    .foregroundStyle(Color(nsColor: BrandArt.wordmark))
                    .padding(.top, 40)
                Spaced(text: state.game.uppercased(with: L10n.locale), kern: 8)
                    .fontWidth(.expanded)
                    .font(size: 22)
                    .foregroundStyle(Color(nsColor: BrandArt.tagline))
                    .lineLimit(2)
                    .padding(.top, 18)
                // What's happening; each step fades over the last.
                ZStack {
                    Text(status).id(status).transition(.opacity)
                }
                .font(size: 18, weight: .medium)
                .foregroundStyle(Theme.muted)
                .animation(.easeInOut(duration: 0.4), value: status)
                .padding(.top, 34)
                // In the gap above the second line, which is there anyway: nothing moves when it comes.
                UpdateBar(fraction: state.stage == .starting ? state.progress : nil)
                // Its own fade only, nothing else on the page moves with it.
                Text(state.stage == .starting ? state.detail ?? " " : " ")
                    .font(size: 14)
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: 560)
                    .opacity(state.stage == .starting && state.detail != nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: state.detail)
                // Steam's licence, said beforehand in the place of the tip.
                if state.stage == .starting, state.wayOut == nil, state.licenceAnnounced {
                    Text(L10n.t("Steam will show the licence once. After that, never again."))
                        .font(size: 15)
                        .foregroundStyle(Color(nsColor: BrandArt.tagline).opacity(0.85))
                        .padding(.top, 26)
                } else if state.stage == .starting, let tip = state.wayOut ?? state.tip {
                    // A tip for new players, quiet, in the banner's blue.
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            ForEach(Array(tip.symbols.enumerated()), id: \.offset) { index, symbol in
                                if index > 0 { Text(verbatim: "+") }
                                PadGlyph(symbol, size: 17)
                            }
                        }
                        Text(tip.text)
                    }
                    .font(size: 15)
                    .foregroundStyle(Color(nsColor: BrandArt.tagline).opacity(0.85))
                    .padding(.top, 26)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Theme.gutter)
    }

    private var status: String {
        switch state.stage {
        case .starting: return state.step ?? L10n.t("Starting …")
        case .behind: return L10n.t("Nightforge waits here until you're done.")
        case .returning: return L10n.t("Back to Nightforge …")
        }
    }
}

/// How far an update is: a thin line in the seam's blue, in a gap that's there with or without it.
private struct UpdateBar: View {
    let fraction: Double?
    static let width: CGFloat = 420
    static let height: CGFloat = 4

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule().fill(Color(nsColor: BrandArt.seamBlue))
                .frame(width: Self.width * (fraction ?? 0))
        }
        .frame(width: Self.width, height: Self.height)
        .opacity(fraction == nil ? 0 : 1)
        .animation(.linear(duration: 0.4), value: fraction)
        .frame(height: 14)
    }
}

/// Steam's question on the curtain: its window stands where Steam puts it, so the mark gives way, the
/// game's name goes to the top, and a bar at the bottom says how to answer and how to leave.
private struct SteamQuestionFrame: View {
    let game: String
    let wayOut: LaunchTip?
    /// Steam's licence: said so at the top, with `seam` round its window once that's there.
    var licence: GameBackdrop.LicenceLook?
    var seam: CGRect?
    @ObservedObject private var tv = TVLayout.shared

    var body: some View {
        ZStack {
            if let seam {
                // Drawn once where the window stands, on the curtain under it; the window itself is left as it is.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: BrandArt.seamBlue), lineWidth: 2)
                    .shadow(color: Color(nsColor: BrandArt.seamBlue).opacity(0.6), radius: 18)
                    .frame(width: seam.width + 24, height: seam.height + 24)
                    .position(x: seam.midX, y: seam.midY)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                Spaced(text: game.uppercased(with: L10n.locale) + " · " + (licence == nil ? L10n.t("Steam is asking something") : L10n.t("The licence, just once")).uppercased(with: L10n.locale), kern: 6)
                    .fontWidth(.expanded)
                    .font(size: 18)
                    .foregroundStyle(Color(nsColor: BrandArt.tagline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, max(48, Theme.margins.top))
                    .padding(.horizontal, Theme.margins.side)
                if licence != nil {
                    Text(L10n.t("Steam only asks this at the first start."))
                        .font(size: 15)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
                }
                Spacer()
                HStack(spacing: 48) {
                    answers
                    // Without a controller there's no B to name, and Esc goes to Steam's window.
                    if let wayOut, !wayOut.symbols.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(Array(wayOut.symbols.enumerated()), id: \.offset) { _, symbol in PadGlyph(symbol, size: 20) }
                            Text(licence == nil ? wayOut.text : L10n.t("Cancel"))
                        }
                    }
                }
                .font(size: 17)
                .foregroundStyle(Color(nsColor: BrandArt.tagline))
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .padding(.bottom, tv.isOn ? Theme.margins.bottom : 0)  // what a TV may cut off stays empty
                .background(Color(red: 6 / 255, green: 8 / 255, blue: 11 / 255).opacity(0.72))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: seam == nil)
    }

    @ViewBuilder private var answers: some View {
        switch licence?.answering ?? .mouse {
        case .mouse:
            Text(L10n.t("Answer with the mouse or trackpad"))
        case .touchpad:
            HStack(spacing: 10) {
                TouchpadMark()
                Text(L10n.t("Touchpad moves the pointer"))
            }
            Text(L10n.t("Press to click"))
            Text(L10n.t("Two fingers scroll"))
        case .stick:
            HStack(spacing: 10) {
                PadGlyph("r.joystick.fill", size: 20)
                Text(L10n.t("Right stick moves the pointer"))
            }
            Text(L10n.t("%@ clicks", licence?.click ?? "R2"))
        }
    }
}

/// The pad's touchpad, as small as the button marks beside it.
private struct TouchpadMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(lineWidth: 1.8)
            .frame(width: 30, height: 20)
            .overlay(Circle().frame(width: 5, height: 5))
    }
}

/// Widely spaced capitals, as on the banner – still centred: the space after the last letter is
/// made up for on the left.
private struct Spaced: View {
    let text: String
    let kern: CGFloat

    var body: some View {
        Text(verbatim: text).kerning(kern).padding(.leading, kern)
    }
}

/// The banner's night with its blue haze, drawn at a quarter of the screen's size – there's nothing
/// finer in it – and stretched.
private struct BrandNight: View {
    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(width: (geometry.size.width / 4).rounded(), height: (geometry.size.height / 4).rounded())
            if let night = GameBackdrop.picture("night", size: size, scale: 1, draw: {
                BrandArt.nightBackground($0, in: CGRect(origin: .zero, size: size))
            }) {
                Image(decorative: night, scale: 1).resizable().interpolation(.high)
            }
        }
    }
}

/// The N in brushed metal, its seam a picture of its own on top. The layout counts the N alone;
/// its shadow and the seam's glow reach beyond.
private struct BrandMark: View {
    /// The curtain is up: a light runs along the seam (with "Reduce motion" it breathes).
    let moving: Bool
    @Environment(\.displayScale) private var scale
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var on = false
    private static let height: CGFloat = 230

    var body: some View {
        let unit = Self.height / BrandArt.glyphSize.height
        let reach = BrandArt.reach * unit
        let size = CGSize(width: BrandArt.glyphSize.width * unit + 2 * reach, height: Self.height + 2 * reach)
        let origin = CGPoint(x: reach, y: reach)
        // Shadow and light in proportion to the N, as on the banner (0.78 × the design there).
        let glow = unit / 0.78 * scale
        let metal = GameBackdrop.picture("mark", size: size, scale: scale) {
            BrandArt.drawMark($0, origin: origin, scale: unit, seam: false, glow: glow)
        }
        let seam = GameBackdrop.picture("seam", size: size, scale: scale) {
            BrandArt.drawSeam($0, origin: origin, scale: unit, glow: glow)
        }
        let runs = moving && !reduceMotion
        ZStack {
            if let metal { Image(decorative: metal, scale: scale) }
            if let seam {
                Image(decorative: seam, scale: scale)
                    .opacity(moving && reduceMotion ? (on ? 1 : 0.45) : runs ? 0.8 : 1)
                if runs {
                    // A light along the seam, in it only (the seam's own picture as the mask), and
                    // a pause off its ends before the next run.
                    let from = CGPoint(x: origin.x + BrandArt.seam.0.x * unit, y: origin.y + BrandArt.seam.0.y * unit)
                    let to = CGPoint(x: origin.x + BrandArt.seam.1.x * unit, y: origin.y + BrandArt.seam.1.y * unit)
                    let along: CGFloat = on ? 1.3 : -0.3
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0.85, green: 0.93, blue: 1), Color(nsColor: BrandArt.seamBlue).opacity(0.5), .clear],
                                             center: .center, startRadius: 0, endRadius: 45))
                        .frame(width: 90, height: 90)
                        .offset(x: from.x + (to.x - from.x) * along - size.width / 2,
                                y: from.y + (to.y - from.y) * along - size.height / 2)
                        .frame(width: size.width, height: size.height)
                        .mask { Image(decorative: seam, scale: scale) }
                        .blendMode(.plusLighter)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(moving ? (reduceMotion ? Animation.easeInOut(duration: 1.8) : .linear(duration: 2.6)).repeatForever(autoreverses: reduceMotion)
                          : nil, value: on)
        .padding(-reach)
        .task(id: moving) {
            on = false
            guard moving else { return }
            try? await Task.sleep(for: .milliseconds(300))  // once the page has its size
            on = true
        }
    }
}
