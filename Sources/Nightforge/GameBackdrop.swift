import AppKit
import SwiftUI

/// Nightforge's page around a game, on the screen it plays on, as with a console.
///
/// - As a curtain (`raise`), over everything but the overlay, in every Space: from the moment
///   the game is handed to its store until it shows its window in front ("Starting …"), and again
///   the moment it ends ("Back to Nightforge …") until Nightforge is in front. Spaces changing
///   underneath, Steam for Mac's window coming up and the desktop stay out of sight.
/// - Behind the game (`show`, `lower`): below every normal window and in every desktop Space, so
///   it never covers the game or another app; around a game in a window it's the page instead of
///   the desktop.
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
    /// The player quit the game: the curtain stays up, whatever its processes do, until Nightforge
    /// is in front (`hide(once:)`).
    private static var held = false
    private static var raisedAt = Date.distantPast
    /// How long a start shows only its step before saying why.
    static let detailAfter: TimeInterval = 3

    static var isRaised: Bool { window?.isVisible == true && state.stage.raised }
    /// Up for the game's end: Nightforge's way back has it now.
    static var isReturning: Bool { isRaised && state.stage == .returning }

    /// Behind `game`, on the screen it plays on – unless the curtain is up, which stays.
    /// `gameOn`: whether it still runs – when Nightforge comes to the front without it (a game
    /// whose end went unseen), the page goes.
    static func show(_ game: String, on screen: NSScreen?, gameOn: @escaping @MainActor () -> Bool) {
        if isRaised, state.game == game { return }
        put(game, on: screen, stage: .behind, gameOn: gameOn)
    }

    /// The curtain over the screen while `game` starts.
    static func raise(_ game: String, on screen: NSScreen?, gameOn: @escaping @MainActor () -> Bool) {
        put(game, on: screen, stage: .starting, gameOn: gameOn)
    }

    /// What's happening: the step at once, the why once the curtain has been up a few seconds, so
    /// a quick start stays calm and a long one doesn't look stuck.
    static func setStatus(_ step: String?, detail: String?) {
        guard state.stage == .starting else { return }
        if state.step != step { state.step = step }
        let shown = Date().timeIntervalSince(raisedAt) >= detailAfter ? detail : nil
        if state.detail != shown { state.detail = shown }
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
                for _ in 0..<60 where !ready() {
                    if isRaised { window.orderFrontRegardless() }
                    try? await Task.sleep(for: .milliseconds(50))
                }  // up to 3 s
                if isRaised { window.orderFrontRegardless() }
            }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
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

    private static func put(_ game: String, on screen: NSScreen?, stage: Stage, gameOn: @escaping @MainActor () -> Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        hiding?.cancel()
        state.game = game
        if stage == .starting, state.stage != .starting || !isRaised {
            raisedAt = Date()
            state.step = nil
            state.detail = nil
        }
        state.stage = stage
        self.gameOn = gameOn
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if !GameBackdrop.gameOn(), !GameBackdrop.isRaised { hide() } }
        }
        let window = self.window ?? make(screen.frame)
        self.window = window
        // A curtain is ordered into the Space shown; after a switch of Spaces (Nightforge's full
        // screen, the game's) it's put in front there at once.
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                              object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard GameBackdrop.isRaised else { return }
                    GameBackdrop.window?.orderFrontRegardless()
                    GameLog.note("Space changed under the curtain")
                }
            }
        }
        // Who comes forward under it, in wine.log: what's seen of a flicker has a name then.
        if frontObserver == nil {
            frontObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                              object: nil, queue: .main) { note in
                let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
                MainActor.assumeIsolated { if GameBackdrop.isRaised { GameLog.note("In front under the curtain: \(app)") } }
            }
        }
        let appearing = !window.isVisible
        window.setFrame(screen.frame, display: true)
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

    /// The curtain above the other windows and over full-screen Spaces too – other apps' as well
    /// (the game's, Steam's), so it stays where it is while macOS slides from one Space to the
    /// next: without, it slid out with the Space it was in and Nightforge's page slid in (the
    /// monitor test on 1.11.). Behind, above the desktop's icons only.
    private static func arrange(_ window: NSWindow) {
        if state.stage.raised {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)  // the overlay above it
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        }
        window.orderFrontRegardless()
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

private struct BackdropView: View {
    @ObservedObject var state: GameBackdrop.State

    var body: some View {
        ZStack {
            BrandNight()
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
                // Its own fade only, nothing else on the page moves with it.
                Text(state.stage == .starting ? state.detail ?? " " : " ")
                    .font(size: 14)
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: 560)
                    .padding(.top, 14)
                    .opacity(state.stage == .starting && state.detail != nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: state.detail)
            }
            .multilineTextAlignment(.center)
            .padding(Theme.gutter)
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var status: String {
        switch state.stage {
        case .starting: return state.step ?? L10n.t("Starting …")
        case .behind: return L10n.t("Nightforge waits here until you're done.")
        case .returning: return L10n.t("Back to Nightforge …")
        }
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
