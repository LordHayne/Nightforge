import AppKit

/// Nightforge's full screen, without a Space of its own: the window over the whole screen, the
/// menu bar and the Dock hidden while Nightforge is in front – they come back with the mouse at
/// the top or the bottom edge, as in macOS's full screen, and with another app in front. In the
/// desktop's Space, with the curtain and the game: starting or ending a game slides nothing.
/// macOS's own full screen has a Space of its own, and every switch to the game and back slid
/// across the screen, curtain and all (Overcooked 2 on 1.11.).
///
/// The green button, ⌃⌘F (View › Full Screen) and Esc with nothing to go back from switch it;
/// GameDisplay switches it for a TV and keeps what the player chose for each screen.
@MainActor
enum FullScreen {
    /// The window's frame before full screen, to go back to; nil while it's in a window.
    private static var windowed: NSRect?
    private static var observers: [NSObjectProtocol] = []

    static var isOn: Bool { windowed != nil }

    private static var window: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    /// The green button and ⌃⌘F switch this full screen from now on, not macOS's.
    static func adopt() {
        guard let window, observers.isEmpty else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }  // macOS brought it back so
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        if let zoom = window.standardWindowButton(.zoomButton) {
            zoom.target = Switch.shared
            zoom.action = #selector(Switch.toggle(_:))
        }
        // A screen plugged in, unplugged or the lid closed: the window takes the new size.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { refit() }
        })
    }

    /// The player's switch: the green button, ⌃⌘F or Esc.
    static func toggle() {
        guard let window else { return }
        set(!isOn, window)
        GameDisplay.fullScreenChosen(isOn, window)
    }

    /// On or off, at once, on the screen the window is on.
    static func set(_ on: Bool, _ window: NSWindow) {
        guard on != isOn, let screen = window.screen ?? NSScreen.main else { return }
        if on {
            // A window that already filled the screen (the last session ended in full screen)
            // goes back to the size Nightforge opens with.
            windowed = window.frame.size == screen.frame.size ? defaultFrame(in: screen.visibleFrame) : window.frame
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
            buttons(window, hidden: true)
            window.isMovable = false
            window.setFrame(screen.frame, display: true)
        } else {
            let saved = windowed ?? defaultFrame(in: screen.visibleFrame)
            windowed = nil
            NSApp.presentationOptions = []
            buttons(window, hidden: false)
            window.isMovable = true
            window.setFrame(windowedFrame(saved, in: screen.visibleFrame), display: true)
        }
    }

    /// Over another screen's whole area, in full screen (GameDisplay moving it).
    static func fit(_ window: NSWindow, to screen: NSScreen) {
        guard isOn else { return }
        window.setFrame(screen.frame, display: true)
    }

    private static func refit() {
        guard isOn, let window, let screen = window.screen ?? NSScreen.main, window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
    }

    private static func buttons(_ window: NSWindow, hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// The window's frame back from full screen: its old size and place, within the screen it's
    /// on now (the old one may be gone, or smaller).
    nonisolated static func windowedFrame(_ saved: NSRect, in area: NSRect) -> NSRect {
        var frame = saved
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        if !area.contains(frame) {
            frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        }
        return frame
    }

    /// The size Nightforge opens with (App's defaultSize), in the middle of `area`.
    nonisolated static func defaultFrame(in area: NSRect) -> NSRect {
        windowedFrame(NSRect(x: area.midX - 720, y: area.midY - 440, width: 1440, height: 880), in: area)
    }

    /// The green button's target.
    private final class Switch: NSObject {
        static let shared = Switch()

        @objc func toggle(_ sender: Any?) {
            MainActor.assumeIsolated { FullScreen.toggle() }
        }
    }
}
