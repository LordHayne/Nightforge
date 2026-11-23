import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// A picture of the running game for the big overlay (docs/ENTWURF-OVERLAY-FUNKTIONEN.md, „Bildschirmfoto“): only the
/// game's own window, through ScreenCaptureKit, also in the game's own full screen. Nothing in the game's process – the
/// picture comes from the window server, so games with anti-cheat are no different. It needs Screen Recording, a macOS
/// permission given only with a mouse or trackpad: Nightforge only looks whether it is there (`CGPreflightScreenCaptureAccess`)
/// and never asks for it itself; without it the answer is `.needsPermission`, and the overlay says so in a sentence.
/// It is asked for beforehand, where the player has a mouse (first setup or the console-mode question), not here.
/// Saved where macOS saves screenshots (`com.apple.screencapture location`, else the Desktop), as „<game> <date time>.png“.
/// Not hooked into the overlay yet: that comes with its variant.
enum GameScreenshot {
    enum Outcome: Equatable {
        case saved(URL)
        /// Screen Recording isn't given.
        case needsPermission
        /// No window of the game's on screen (it may be starting, or behind).
        case noWindow
        /// ScreenCaptureKit gave no picture, or it couldn't be written.
        case failed
    }

    /// The Mac's part: so the tests run on stand-ins, never take a real picture and leave nothing on disk.
    struct System {
        var permitted: () -> Bool
        /// CGWindowList's on-screen entries, front to back.
        var windows: () -> [[String: Any]]
        var capture: (_ window: Int) async -> CGImage?
        /// `com.apple.screencapture location` as set, if at all.
        var location: () -> String?
        var home: URL
        var exists: (URL) -> Bool
        var write: (CGImage, URL) -> Bool
        var now: () -> Date
    }

    static func take(game: String, pids: Set<pid_t>, _ system: System = .live) async -> Outcome {
        guard system.permitted() else { return .needsPermission }
        guard let window = window(in: system.windows(), pids: pids) else { return .noWindow }
        guard let image = await system.capture(window) else { return .failed }
        let folder = folder(location: system.location(), home: system.home, exists: system.exists)
        let file = folder.appendingPathComponent(fileName(game: game, at: system.now(), taken: { system.exists(folder.appendingPathComponent($0)) }))
        return system.write(image, file) ? .saved(file) : .failed
    }

    /// The game's picture window: the frontmost of `pids`' windows of a game's size on screen, as the curtain counts them
    /// (`GameProcesses.showsWindow`: not a splash, not a captured display's black shield).
    static func window(in windows: [[String: Any]], pids: Set<pid_t>) -> Int? {
        windows.first { GameProcesses.showsWindow([$0], pids: pids) }
            .flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }

    /// Where macOS puts screenshots: its own setting when that folder is there (a `~` in it is the home), else the Desktop.
    static func folder(location: String?, home: URL, exists: (URL) -> Bool) -> URL {
        if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            let expanded = location == "~" ? home.path
                : location.hasPrefix("~/") ? home.path + location.dropFirst(1) : location
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            if expanded.hasPrefix("/"), exists(url) { return url }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// „<game> 2026-11-23 13.55.01.png“ – macOS' own pattern for its screenshots, with the game's name in front; a second
    /// one in the same second gets „ 2“. Slashes and colons, which Finder can't show, become dashes.
    static func fileName(game: String, at date: Date, taken: (String) -> Bool) -> String {
        var name = game.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(".") { name = String(name.drop { $0 == "." }) }
        if name.isEmpty { name = "Nightforge" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = name + " " + formatter.string(from: date)
        var candidate = stem + ".png"
        var number = 2
        while taken(candidate) {
            candidate = "\(stem) \(number).png"
            number += 1
        }
        return candidate
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

extension GameScreenshot.System {
    /// The Mac's own. A test program takes no picture (`TestGuard.testProgram`): the screen isn't a test's.
    static var live: GameScreenshot.System {
        GameScreenshot.System(
            permitted: { CGPreflightScreenCaptureAccess() },
            windows: { CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [] },
            capture: { number in
                guard !TestGuard.testProgram,
                      let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                      let window = content.windows.first(where: { Int($0.windowID) == number })
                else { return nil }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                configuration.showsCursor = false
                return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            },
            location: { CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String },
            home: FileManager.default.homeDirectoryForCurrentUser,
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            write: { image, url in !TestGuard.testProgram && GameScreenshot.writePNG(image, to: url) },
            now: { Date() })
    }
}
