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

    /// A game's own app adds `key`: nightforge://play/570?key=….
    static func url(play game: GameID, key: String? = nil) -> URL {
        URL(string: "nightforge://play/\(linkID(game))" + (key.map { "?key=\($0)" } ?? ""))!
    }

    /// nightforge://play/570, nightforge://show/570 or nightforge://play/epic.Fortnite. Any web page can
    /// open such a link, so one that plays only does so with `key`, which only the game apps Nightforge
    /// wrote carry; without it Nightforge shows the game's page, and Play is the player's click.
    static func action(from url: URL, key: String) -> Action? {
        guard url.scheme == "nightforge", let game = GameID(key: url.lastPathComponent) else { return nil }
        switch url.host {
        case "play":
            let given = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value
            return given == key && !key.isEmpty ? .play(game) : .show(game)
        case "show": return .show(game)
        default: return nil
        }
    }

    /// The key in the game apps' links: made once per Mac and kept with Nightforge's files, where no web
    /// page can read it. Without a file to keep it in, a key of the moment: plain links then show the page.
    static func key(in folder: URL = Engine.supportDir) -> String {
        let file = folder.appendingPathComponent("shortcut-key")
        func kept() -> String? {
            guard let text = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count == 32, text.allSatisfy(\.isHexDigit) else { return nil }
            return text
        }
        if let key = kept() { return key }
        var bytes = [UInt8](repeating: 0, count: 16)
        arc4random_buf(&bytes, bytes.count)
        let key = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            try? Data(key.utf8).write(to: file, options: .atomic)  // there, but no key (cut short): replaced
        } else if (try? Data(key.utf8).write(to: file, options: .withoutOverwriting)) == nil {
            return kept() ?? key  // written meanwhile (the start's addKey and a link at once): that one counts
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return key
    }

    /// What a game's app runs: open its link, with the key.
    static func script(_ game: GameID, key: String) -> String {
        "#!/bin/sh\nexec /usr/bin/open \"\(url(play: game, key: key).absoluteString)\"\n"
    }

    /// Apps an older Nightforge wrote open their link without the key (or with another one): their
    /// script gets this one, so they go on starting their game directly. Only scripts exactly as
    /// Nightforge writes them are touched. Run at start: a click on such an app that starts Nightforge
    /// itself still sends its link without the key and shows the game's page, once.
    static func addKey(_ key: String, in folder: URL = folder) {
        let fm = FileManager.default
        let head = "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/"
        for app in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where app.pathExtension == "app" {
            let file = app.appendingPathComponent("Contents/MacOS/play")
            guard let text = try? String(contentsOf: file, encoding: .utf8), text.hasPrefix(head), text.hasSuffix("\"\n"),
                  let id = text.dropFirst(head.count).dropLast(2).split(separator: "?", maxSplits: 1).first,
                  let game = GameID(key: String(id)), linkID(game) == id
            else { continue }
            let wanted = script(game, key: key)
            guard wanted != text, (try? wanted.write(to: file, atomically: true, encoding: .utf8)) != nil else { continue }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
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

    /// Writes the little app: a script that opens the game's link with the key, with the cover as its icon.
    @discardableResult
    static func create(for game: Game, icon: NSImage?, in folder: URL = folder, key: String = GameShortcut.key()) throws -> URL {
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
        try Self.script(game.gameID, key: key).write(to: script, atomically: true, encoding: .utf8)
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
