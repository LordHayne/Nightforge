import AppKit
import ObjectiveC

/// Nightforge's full screen, without a Space of its own: the window over the whole screen, the
/// menu bar and the Dock hidden while Nightforge is in front – the menu bar comes with the pointer
/// at the top edge, as in macOS's full screen, and with another app in front. In the desktop's
/// Space, with the curtain and the game: starting or ending a game slides nothing. macOS's own full
/// screen has a Space of its own, and every switch to the game and back slid across the screen,
/// curtain and all (Overcooked 2 on 1.11.).
///
/// Without its title bar meanwhile: with one, macOS kept the window below the menu bar's strip
/// and gave it round corners, the desktop showing above and in them (1.11.). On a MacBook the
/// content stays below the notch, the strip beside it is the page's night.
///
/// The green button, ⌃⌘F (View › Full Screen) and Esc with nothing to go back from switch it;
/// GameDisplay switches it for a TV and keeps what the player chose for each screen.
@MainActor
enum FullScreen {
    /// The window's frame before full screen, to go back to; nil while it's in a window.
    private static var windowed: NSRect?
    private static var observers: [NSObjectProtocol] = []
    /// Mouse moves seen while in full screen: the menu bar follows the pointer.
    private static var pointerWatch: Any?
    private static var movesBefore = false
    private static var menuBarShown = false
    private static var menuOpen = false

    static var isOn: Bool { windowed != nil }

    private static var window: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    /// The green button and ⌃⌘F switch this full screen from now on, not macOS's.
    static func adopt() {
        guard let window, observers.isEmpty else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }  // macOS brought it back so
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        keyWithoutTitleBar(window)
        retarget(window)
        let center = NotificationCenter.default
        observers = [
            // A screen plugged in, unplugged or the lid closed: the window takes the new size.
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { refit() }
            },
            // Back in front (⌘-Tab): the menu bar as the pointer has it, hidden in the middle.
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { followPointer() }
            },
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { menuOpen = true }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    menuOpen = false
                    followPointer()
                }
            },
        ]
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
            window.styleMask.remove(.titled)
            window.isMovable = false
            menuOpen = false
            showMenuBar(false)
            fit(window, to: screen)
            movesBefore = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
            pointerWatch = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated { followPointer() }
                return event
            }
        } else {
            let saved = windowed ?? defaultFrame(in: screen.visibleFrame)
            windowed = nil
            if let pointerWatch { NSEvent.removeMonitor(pointerWatch) }
            pointerWatch = nil
            window.acceptsMouseMovedEvents = movesBefore
            NSApp.presentationOptions = []
            window.contentView?.additionalSafeAreaInsets = NSEdgeInsets()
            window.styleMask.insert(.titled)
            window.isMovable = true
            retarget(window)  // the title bar's buttons are new ones
            window.setFrame(windowedFrame(saved, in: screen.visibleFrame), display: true)
        }
    }

    /// Over `screen`'s whole area, in full screen (GameDisplay moving it, a screen changed).
    static func fit(_ window: NSWindow, to screen: NSScreen) {
        guard isOn else { return }
        window.setFrame(screen.frame, display: true)
        // Below a MacBook's notch, as in macOS's full screen.
        window.contentView?.additionalSafeAreaInsets = NSEdgeInsets(top: screen.safeAreaInsets.top, left: 0, bottom: 0, right: 0)
    }

    private static func refit() {
        guard isOn, let window, let screen = window.screen ?? NSScreen.main else { return }
        fit(window, to: screen)
    }

    /// Hidden, and shown while the pointer is at the screen's top edge or on the bar. macOS's own
    /// hiding (autoHideMenuBar) left the bar on screen on this MacBook, the pointer still or moved
    /// (probe on 1.11.); hidden outright it doesn't come with the pointer – so Nightforge switches.
    private static func followPointer() {
        guard isOn, let screen = window?.screen else { return }
        showMenuBar(menuOpen || menuBarShown(pointer: NSEvent.mouseLocation, on: screen.frame,
                                             bar: max(screen.safeAreaInsets.top, 24), shown: menuBarShown))
    }

    private static func showMenuBar(_ shown: Bool) {
        menuBarShown = shown
        // The Dock comes along at the bottom edge while the bar is there.
        let options: NSApplication.PresentationOptions = shown ? [.autoHideDock] : [.hideDock, .hideMenuBar]
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
    }

    /// Whether the menu bar shows: the pointer at the top edge of the screen brings it, and it
    /// stays while the pointer is on it (`bar` high) or just below.
    nonisolated static func menuBarShown(pointer: CGPoint, on screen: CGRect, bar: CGFloat, shown: Bool) -> Bool {
        guard screen.minX <= pointer.x, pointer.x < screen.maxX, pointer.y <= screen.maxY else { return false }
        if pointer.y >= screen.maxY - 1 { return true }
        return shown && pointer.y >= screen.maxY - bar - 12
    }

    /// The green button switches this full screen, not macOS's.
    private static func retarget(_ window: NSWindow) {
        guard let zoom = window.standardWindowButton(.zoomButton) else { return }
        zoom.target = Switch.shared
        zoom.action = #selector(Switch.toggle(_:))
    }

    /// SwiftUI's window says it can't be key or main without its title bar, and the keys (Esc, the
    /// search) would reach nothing. Its class's two answers widened for Nightforge's window, once:
    /// a subclass of its own swapped in broke SwiftUI's observers of the window (probe on 1.11.).
    private static func keyWithoutTitleBar(_ window: NSWindow) {
        typealias Answer = @convention(c) (AnyObject, Selector) -> Bool
        let type: AnyClass = type(of: window)
        for selector in [#selector(getter: NSWindow.canBecomeKey), #selector(getter: NSWindow.canBecomeMain)] {
            guard let method = class_getInstanceMethod(type, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Answer.self)
            let answer: @convention(block) (AnyObject) -> Bool = { [weak window] asked in
                original(asked, selector) || asked === window
            }
            let implementation = imp_implementationWithBlock(answer)
            // Its own answer replaced; the inherited one (NSWindow's) left as it is for every other window.
            if !class_addMethod(type, selector, implementation, method_getTypeEncoding(method)) {
                method_setImplementation(method, implementation)
            }
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
