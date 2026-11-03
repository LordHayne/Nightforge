import Foundation

/// Which program starts one of Nightforge's Steam games: the same choice as for Epic and GOG
/// (GameProgram – the options' pick, a profile's, D3DMetal's DirectX 12 program), made through
/// Steam, which starts what appinfo names. Two ways to another program (Windows Steam, Nov 2026):
/// - One of the game's own launch options goes by its type. steam://launch/<id>/Option1 starts the
///   option of that type straight away, without Steam asking which one (SteamUI.dll looks the name
///   up in its table of ELaunchOptionType). Rocket League's without anti-cheat is type option1 and
///   starts RocketLeague.exe instead of RocketLeague_EAC.exe. Steam passes no arguments this way.
/// - Any other program goes into the game's LaunchOptions: "\"C:\…\Control_DX12.exe\" %command%".
///   steamclient64.dll finds %command% (V_stristr), puts its own command line there and starts the
///   first word of the result (V_ParseShellCommandLine), in the launch option's working folder.
///   Steam's program follows as an argument, which games ignore (as with script extender loaders).
///   Steam reads LaunchOptions from userdata/<id>/config/localconfig.vdf when it starts and writes
///   its copy back when it quits, so they're written only while it's down (apply).
enum SteamProgram {
    enum Route: Equatable {
        /// Steam's default launch option (-applaunch), with Nightforge's arguments after it.
        case standard
        /// A launch option of the game's own, by its type in Steam's spelling ("Option1").
        case option(type: String, executable: String)
        /// Another program, relative to the game folder ("Control_DX12.exe"), in the LaunchOptions.
        case program(String)
    }

    /// The launch option types steam://launch takes, in Steam's spelling. Not "default" and "none",
    /// which games give several options, nor the VR ones.
    static let types = ["safemode": "SafeMode", "multiplayer": "Multiplayer", "config": "Config", "server": "Server",
                        "editor": "Editor", "manual": "Manual", "benchmark": "Benchmark",
                        "option1": "Option1", "option2": "Option2", "option3": "Option3"]

    /// The program Nightforge counts as the store's: the launch option without anti-cheat when the
    /// game has one (Rocket League), else Steam's default. Relative to the game folder.
    static func storeProgram(_ entries: [SteamCatalog.LaunchEntry]) -> String? {
        (SteamCatalog.antiCheatOff(entries) ?? entries.first)?.executable
    }

    /// How a start of `game` reaches the program GameProgram picks, `layer` being the one it draws with.
    static func route(_ game: Game, layer: GraphicsLayer, options: GameOptions, profile: GameProfile?) -> Route {
        route(entries: SteamCatalog.launchEntries(appID: game.appID, steamRoot: game.steamRoot), installDir: game.installDir,
              layer: layer, chosen: options.program, profile: profile?.executable)
    }

    static func route(entries: [SteamCatalog.LaunchEntry], installDir: URL, layer: GraphicsLayer, chosen: String,
                      profile: String?) -> Route {
        guard let standard = entries.first, let store = storeProgram(entries) else { return .standard }
        let program = GameProgram.resolve(store: file(store, in: installDir), installDir: installDir, layer: layer,
                                          chosen: chosen, profile: profile)
        let base = installDir.standardizedFileURL.path + "/"
        guard program.path.hasPrefix(base) else { return .standard }
        let relative = String(program.path.dropFirst(base.count))
        if standard.starts(relative) { return .standard }
        // One of Steam's own, if no other option shares its type (Steam would take the first).
        let ofType = { (type: String) in entries.filter { $0.type.lowercased() == type.lowercased() } }
        if let option = entries.first(where: { $0.starts(relative) && $0.betaKey.isEmpty }),
           let type = types[option.type.lowercased()], ofType(option.type).count == 1 {
            return .option(type: type, executable: option.executable)
        }
        guard FileManager.default.fileExists(atPath: program.path) else { return .standard }
        return .program(relative)
    }

    /// steam://launch/<id>/<type>, for Steam's command line.
    static func url(appID: Int, type: String) -> String { "steam://launch/\(appID)/\(type)" }

    /// What the game's LaunchOptions say for `route`: the program before Steam's command, or nil.
    static func launchOptions(_ route: Route, installDir: URL) -> String? {
        guard case .program(let relative) = route else { return nil }
        return "\"" + Engine.windowsPath(of: file(relative, in: installDir)) + "\" %command%"
    }

    /// LaunchOptions as Nightforge writes them. Anything else there is the player's and stays.
    static func isOurs(_ value: String) -> Bool {
        value.hasPrefix("\"") && value.lowercased().hasSuffix(".exe\" %command%")
            && value.filter { $0 == "\"" }.count == 2
    }

    private static func file(_ relative: String, in installDir: URL) -> URL {
        installDir.appendingPathComponent(relative.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL
    }

    // MARK: - LaunchOptions in localconfig.vdf

    /// What the game about to start needs in its LaunchOptions until Steam next starts (apply): app ID
    /// → the value, "" for none of Nightforge's.
    private static var wanted: [Int: String] = [:]
    private static let lock = NSLock()

    /// Notes what `game`'s LaunchOptions should say for a start by `route`. True when the running Steam
    /// has to restart for it: an account's file says otherwise, and it isn't the player's own.
    @discardableResult
    static func prepare(_ game: Game, route: Route) -> Bool {
        prepare(appID: game.appID, value: launchOptions(route, installDir: game.installDir), steamRoot: game.steamRoot)
    }

    static func prepare(appID: Int, value: String?, steamRoot: URL) -> Bool {
        lock.withLock { wanted[appID] = value ?? "" }
        return configs(steamRoot: steamRoot).contains { config in
            guard let data = try? Data(contentsOf: config) else { return false }
            return edited(String(decoding: data, as: UTF8.self), appID: appID, value: value) != nil
        }
    }

    /// Writes what `prepare` noted into every account's localconfig.vdf, with Steam down (it starts next).
    static func apply(steamRoot: URL) {
        let changes = lock.withLock { wanted }.sorted { $0.key < $1.key }
        guard !changes.isEmpty else { return }
        for config in configs(steamRoot: steamRoot) {
            guard let data = try? Data(contentsOf: config) else { continue }
            let original = String(decoding: data, as: UTF8.self)
            let text = changes.reduce(original) { text, change in
                edited(text, appID: change.key, value: change.value.isEmpty ? nil : change.value) ?? text
            }
            if text != original { try? Data(text.utf8).write(to: config, options: .atomic) }
        }
    }

    private static func configs(steamRoot: URL) -> [URL] {
        let users = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("config/localconfig.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// `text` (a localconfig.vdf) with `appID`'s LaunchOptions set to `value` – nil takes Nightforge's
    /// away – and the rest exactly as Steam wrote it. nil when nothing changes: it says so already, the
    /// player put their own there, or the file isn't one (cut off, no UserLocalConfigStore).
    static func edited(_ text: String, appID: Int, value: String?) -> String? {
        let names = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", String(appID)]
        let target = names.map { $0.lowercased() }
        let chars = Array(text.unicodeScalars)
        var objects: [[String]: Int] = [:]  // where each object's brace opens, by its keys (lower-cased)
        var path: [String] = []
        var key: (text: String, start: Int)?
        var found: (keyStart: Int, valueStart: Int, valueEnd: Int, value: String)?
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                // A quoted string; Steam escapes quotes and backslashes inside.
                let start = i
                var content = String.UnicodeScalarView()
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        let next = chars[i + 1]
                        content.append(next == "n" ? "\n" : next == "t" ? "\t" : next)
                        i += 2
                    } else {
                        content.append(chars[i])
                        i += 1
                    }
                }
                guard i < chars.count else { return nil }
                i += 1
                if let pending = key {
                    if path == target, pending.text.lowercased() == "launchoptions" {
                        found = (pending.start, start, i, String(content))
                    }
                    key = nil
                } else {
                    key = (String(content), start)
                }
            } else if c == "{" {
                guard let pending = key else { return nil }
                path.append(pending.text.lowercased())
                objects[path] = i
                key = nil
                i += 1
            } else if c == "}" {
                guard key == nil, !path.isEmpty else { return nil }
                path.removeLast()
                i += 1
            } else if c == " " || c == "\t" || c == "\n" || c == "\r" {
                i += 1
            } else {
                return nil
            }
        }
        guard path.isEmpty, key == nil, objects[[target[0]]] != nil else { return nil }

        func slice(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(chars[range])) }
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        if let found {
            if let value {
                guard found.value != value, found.value.isEmpty || isOurs(found.value) else { return nil }
                return slice(0..<found.valueStart) + quoted(value) + slice(found.valueEnd..<chars.count)
            }
            guard isOurs(found.value) else { return nil }
            // The whole line goes, with the line break before it.
            var start = found.keyStart
            while start > 0, chars[start - 1] == "\t" || chars[start - 1] == " " { start -= 1 }
            if start > 0, chars[start - 1] == "\n" {
                start -= start > 1 && chars[start - 2] == "\r" ? 2 : 1
            } else {
                start = found.keyStart
            }
            return slice(0..<start) + slice(found.valueEnd..<chars.count)
        }
        guard let value else { return nil }
        // Under the deepest of the keys down to the game that's there, first thing after its brace,
        // indented as Steam does.
        let depth = (1...target.count).last { objects[Array(target.prefix($0))] != nil } ?? 1
        let open = objects[Array(target.prefix(depth))] ?? 0
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        func tabs(_ count: Int) -> String { String(repeating: "\t", count: count) }
        var lines = ""
        for level in depth..<target.count {
            lines += newline + tabs(level) + quoted(names[level]) + newline + tabs(level) + "{"
        }
        lines += newline + tabs(target.count) + quoted("LaunchOptions") + "\t\t" + quoted(value)
        for level in (depth..<target.count).reversed() {
            lines += newline + tabs(level) + "}"
        }
        return slice(0..<(open + 1)) + lines + slice((open + 1)..<chars.count)
    }
}
