import AppKit

/// Games outside Nightforge: `nightforge://play/<id>` (and `show`), and a small app per game in
/// ~/Applications/Nightforge Games that opens it – so Spotlight and Launchpad find the game.
enum GameShortcut {
    enum Action: Equatable {
        case play(GameID)
        case show(GameID)
    }

    /// A Steam game's link carries its bare app ID, as before there were other stores – the apps
    /// already in Applications keep working; other stores' games their key ("epic.Fortnite").
    static func linkID(_ game: GameID) -> String { game.steamAppID.map(String.init) ?? game.key }

    static func url(play game: GameID) -> URL { URL(string: "nightforge://play/\(linkID(game))")! }

    /// nightforge://play/570, nightforge://show/570 or nightforge://play/epic.Fortnite.
    static func action(from url: URL) -> Action? {
        guard url.scheme == "nightforge", let game = GameID(key: url.lastPathComponent) else { return nil }
        switch url.host {
        case "play": return .play(game)
        case "show": return .show(game)
        default: return nil
        }
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Nightforge Games", isDirectory: true)
    }

    /// "Baldur's Gate 3.app" – without the characters a file name can't have.
    static func appURL(for game: Game, in folder: URL = folder) -> URL {
        let name = game.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " –")
            .trimmingCharacters(in: .whitespaces)
        return folder.appendingPathComponent(name.isEmpty ? "Game \(linkID(game.gameID))" : name).appendingPathExtension("app")
    }

    static func exists(for game: Game) -> Bool {
        FileManager.default.fileExists(atPath: appURL(for: game).path)
    }

    /// Writes the little app: a script that opens the game's link, with the cover as its icon.
    @discardableResult
    static func create(for game: Game, icon: NSImage?, in folder: URL = folder) throws -> URL {
        let app = appURL(for: game, in: folder)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleExecutable": "play",
            "CFBundleIdentifier": "io.github.lordhayne.nightforge.game.\(linkID(game.gameID))",
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "LSApplicationCategoryType": "public.app-category.games",
            // No Dock icon for the moment it runs: it only hands over to Nightforge.
            "LSUIElement": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let script = macOS.appendingPathComponent("play")
        try "#!/bin/sh\nexec /usr/bin/open \"\(url(play: game.gameID).absoluteString)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        if let icon { NSWorkspace.shared.setIcon(square(icon), forFile: app.path, options: []) }
        return app
    }

    /// A cover is 2:3; an app icon is square: the cover centred on a dark rounded tile.
    private static func square(_ cover: NSImage) -> NSImage {
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 90, yRadius: 90)
            NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
            tile.fill()
            tile.addClip()
            let height = rect.height - 80
            let width = height * cover.size.width / max(cover.size.height, 1)
            cover.draw(in: NSRect(x: rect.midX - width / 2, y: 40, width: width, height: height))
            return true
        }
    }
}
