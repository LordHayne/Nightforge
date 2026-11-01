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
/// It never takes a click, a key or the pad. A loading screen of its own: the Nightforge N with its
/// light seam, the game's name and what's happening, on the app's night with the game's backdrop
/// from Home's stage (already blurred) faint behind. While it's a curtain only the seam pulses,
/// gently, as a layer of its own – nothing that redraws the whole screen or costs the game frames.
@MainActor
enum GameBackdrop {
    final class State: ObservableObject {
        @Published var game = ""
        @Published var art: NSImage?
        @Published var stage = Stage.behind
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
    private static var gameOn: @MainActor () -> Bool = { false }
    /// The player quit the game: the curtain stays up, whatever its processes do, until Nightforge
    /// is in front (`hide(once:)`).
    private static var held = false

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

    static func setArt(_ image: NSImage?, for game: String) {
        guard state.game == game else { return }
        state.art = image
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
    static func hide(once ready: @escaping @MainActor () -> Bool) {
        hide(after: .milliseconds(350), waitingFor: ready)
    }

    static func hide(after delay: Duration = .milliseconds(900), waitingFor ready: (@MainActor () -> Bool)? = nil) {
        guard let window, window.isVisible else { return }
        hiding?.cancel()
        hiding = Task {
            if let ready {
                for _ in 0..<60 where !ready() { try? await Task.sleep(for: .milliseconds(50)) }  // up to 3 s
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
        }
    }

    private static func put(_ game: String, on screen: NSScreen?, stage: Stage, gameOn: @escaping @MainActor () -> Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        hiding?.cancel()
        if state.game != game { state.art = nil }
        state.game = game
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
                MainActor.assumeIsolated { if GameBackdrop.isRaised { GameBackdrop.window?.orderFrontRegardless() } }
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

    /// The curtain above the other windows and over full-screen Spaces too; behind, above the
    /// desktop's icons only.
    private static func arrange(_ window: NSWindow) {
        if state.stage.raised {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)  // the overlay above it
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        }
        window.orderFrontRegardless()
    }

    private static func make(_ frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
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

private struct BackdropView: View {
    @ObservedObject var state: GameBackdrop.State

    var body: some View {
        ZStack {
            Theme.night
            if let art = state.art {
                // Filling the whole screen whatever the picture's shape.
                Color.clear
                    .overlay { Image(nsImage: art).resizable().scaledToFill() }
                    .clipped()
                    .opacity(0.16)
            }
            // The app's night, a little lighter round the mark like under its lamp.
            RadialGradient(colors: [Theme.slate.opacity(0.9), Theme.night.opacity(0)], center: .center, startRadius: 0, endRadius: 620)
            VStack(spacing: 0) {
                if state.stage.raised {
                    PulsingMark()
                } else {
                    NightforgeMark(seamWidth: 4, seamGlow: 14).frame(height: 150)
                }
                Text(state.game)
                    .font(size: 32, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .padding(.top, 44)
                Text(status)
                    .font(size: 18, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .padding(Theme.gutter)
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var status: String {
        switch state.stage {
        case .starting: return L10n.t("Starting …")
        case .behind: return L10n.t("Nightforge waits here until you're done.")
        case .returning: return L10n.t("Back to Nightforge …")
        }
    }
}

/// The N while something happens: its light seam breathes, slowly. Still with "Reduce motion".
private struct PulsingMark: View {
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        // Only the seam's light is animated – not the page, which would move with it.
        NightforgeMark(seamWidth: 4, seamGlow: 14, seamOpacity: reduceMotion || bright ? 1 : 0.4,
                       seamAnimation: reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true))
            .frame(height: 150)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(300))  // once the page has its size
                bright = true
            }
    }
}
