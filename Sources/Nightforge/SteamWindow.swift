import AppKit

/// Steam's own windows (its sign-in, a demo's install dialog) in front of Nightforge. Since macOS 14
/// an app can't push itself to the front, and Steam's sign-in opened behind Nightforge's window
/// (29.10.2026) – "Show Steam window again" didn't change that. Nightforge, while it's the active
/// app, hands activation over to the process that shows the window, like it does for games.
enum SteamWindow {
    /// The process showing Steam's window: the front one of Steam's browser processes' windows
    /// (CGWindowList lists front to back). Its tiny menu windows don't count; the sign-in is
    /// 700 × 440. Without Screen Recording, window titles aren't readable, so owner and size it is.
    static func owner(of windows: [[String: Any]], helpers: Set<pid_t>) -> pid_t? {
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init), helpers.contains(owner),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 300, height >= 200
            else { continue }
            return owner
        }
        return nil
    }

    /// Brings Steam's window to the front, trying for up to `seconds` while it appears. False when
    /// none came or Nightforge wasn't the active app (then it can't hand the front over).
    @MainActor @discardableResult
    static func bringForward(within seconds: Int = 10) async -> Bool {
        for _ in 0..<(seconds * 2) {
            let helpers = await Engine.offMain {
                Set(Engine.ownProcesses().filter { $0.command.lowercased().contains("steamwebhelper") }.map(\.pid))
            }
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            if let pid = owner(of: windows, helpers: helpers), let app = NSRunningApplication(processIdentifier: pid) {
                guard NSApp.isActive else { return false }  // the player has moved on to something else
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [.activateAllWindows])
                try? await Task.sleep(for: .milliseconds(600))
                if app.isActive { return true }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }
}
