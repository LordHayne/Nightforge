import AppKit
import SwiftUI

/// What lies behind a running game on its screen: a calm Nightforge page ("Mafia II is running …")
/// instead of the Mac's desktop. When the game ends it's what shows – "Back to Nightforge …" –
/// until Nightforge is in front again, as with a console. Nightforge used to hide itself during a
/// game, so the desktop was all that was left behind it.
///
/// It sits below every normal window and in every desktop Space of the game's screen: wherever
/// macOS puts the game's window (on a TV, Nightforge's full screen is a Space of its own, and the
/// game opens on the desktop Space), the page is right behind it and can never cover the game or
/// another app. It never takes a click, a key or the pad. Static, so it costs nothing while the
/// game covers it.
@MainActor
enum GameBackdrop {
    final class State: ObservableObject {
        @Published var game = ""
        @Published var returning = false
    }

    private static let state = State()
    private static var window: NSWindow?
    private static var hiding: Task<Void, Never>?
    private static var observer: NSObjectProtocol?

    /// Behind `game`, on the screen it plays on. `gameOn`: whether it still runs – when Nightforge
    /// comes to the front without it (a game whose end went unseen), the page goes.
    static func show(_ game: String, on screen: NSScreen?, gameOn: @escaping @MainActor () -> Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        hiding?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if !gameOn() { hide() } }
        }
        state.game = game
        state.returning = false
        let window = self.window ?? make()
        self.window = window
        window.alphaValue = 1
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()  // within its level, under every normal window
    }

    /// The game's processes are gone: Nightforge is on its way.
    static func returning() {
        guard window?.isVisible == true else { return }
        state.returning = true
    }

    /// They came back (a launcher handed over to the game): the game runs on.
    static func playing() {
        state.returning = false
    }

    /// Once Nightforge is in front: a moment later, so a switch of Spaces has finished by then.
    static func hide(after delay: Duration = .milliseconds(900)) {
        guard let window, window.isVisible else { return }
        hiding?.cancel()
        hiding = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
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

    private static func make() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        // Above the desktop's icons, below everything else.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = NSColor(Theme.night)
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: BackdropView(state: state))
        return window
    }
}

private struct BackdropView: View {
    @ObservedObject var state: GameBackdrop.State

    var body: some View {
        ZStack {
            Theme.night
            VStack(spacing: 10) {
                Text(state.returning ? L10n.t("Back to Nightforge …") : L10n.t("%@ is running …", state.game))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.ink)
                if !state.returning {
                    Text(L10n.t("Nightforge waits here until you're done."))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Theme.gutter)
        }
        .ignoresSafeArea()
    }
}
