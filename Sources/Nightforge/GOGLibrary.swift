import Foundation

/// A GOG game as Nightforge keeps it between starts (GOG/library.json): what the library looked like
/// last time, so it shows – and plays – at once and offline.
struct GOGGame: Codable, Equatable {
    /// GOG's product ID ("1207658924").
    let id: String
    let title: String
    /// Portrait cover and wide background (GamesDB's vertical_cover and background). GamesDB has no
    /// logo on its own – its "logo" is the store's tile with the title on it.
    var cover: URL?
    var hero: URL?
    /// GOG has a macOS version of it, which Nightforge takes first.
    var mac = false
    /// Add-ons the player owns for it: they download and update with the game.
    var dlcs: [GOGDLC] = []
}

struct GOGDLC: Codable, Equatable {
    let id: String
    let title: String
}

/// What Nightforge knows about the GOG library between starts.
struct GOGLibrary: Codable, Equatable {
    var games: [GOGGame] = []
    /// When GOG was last asked successfully.
    var loaded: Date?

    /// The games among the products the player owns, each with the add-ons they own for it. What
    /// isn't a game of its own (add-ons, GamesDB's "spam", products hidden from the library) stays out.
    static func games(from releases: [GOGRelease]) -> [GOGGame] {
        let owned = Dictionary(releases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return releases.filter { ["game", "mod"].contains($0.type) && $0.visible }.map { release in
            GOGGame(id: release.id, title: release.title, cover: release.cover, hero: release.hero, mac: release.mac,
                    dlcs: release.dlcs.compactMap { owned[$0] }.filter { $0.type == "dlc" }.map { GOGDLC(id: $0.id, title: $0.title) })
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// What GamesDB said about the products the player owns (GOG/releases.json), and when all of them
/// were last asked.
struct GOGReleases: Codable, Equatable {
    var items: [String: GOGRelease] = [:]
    var checked: Date?
}

/// One page of the products the player owns (`galaxy-library.gog.com/users/<id>/releases`, what GOG
/// Galaxy reads): GOG's own products by ID – the library also lists games from other platforms
/// linked to the account, which Nightforge leaves to their own store.
enum GOGOwned {
    static func page(fromJSON json: Data) -> (ids: [String], next: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return nil }
        let ids = items.compactMap { item -> String? in
            guard item["platform_id"] as? String == "gog", item["owned"] as? Bool != false else { return nil }
            let id = (item["external_id"] as? String) ?? (item["external_id"] as? NSNumber)?.stringValue
            return id.flatMap { GOGRelease.isProductID($0) ? $0 : nil }
        }
        let next = (object["next_page_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (ids, next)
    }
}

/// A product as GOG's GamesDB describes it (`gamesdb.gog.com/platforms/gog/external_releases/<id>`,
/// as Heroic reads it): a game or an add-on, its title, the systems it runs on and its art.
struct GOGRelease: Codable, Equatable {
    let id: String
    let title: String
    /// "game", "dlc", "mod" – or "spam" and others that aren't games.
    var type = "game"
    /// GOG lists it in the library (some owned products are only parts of others).
    var visible = true
    var mac = false
    var cover: URL?
    var hero: URL?
    /// Product IDs of its add-ons (whether owned or not).
    var dlcs: [String] = []

    static func from(gamesDB json: Data) -> GOGRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let game = object["game"] as? [String: Any] ?? [:]
        let id = (object["external_id"] as? String) ?? (object["external_id"] as? NSNumber)?.stringValue
        func text(_ value: Any?) -> String? {
            guard let names = value as? [String: Any] else { return nil }
            let name = (names["*"] as? String) ?? (names["en-US"] as? String)
            return name?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let id, isProductID(id), let title = text(object["title"]) ?? text(game["title"]), !title.isEmpty else { return nil }
        var release = GOGRelease(id: id, title: title)
        release.type = object["type"] as? String ?? "game"
        release.visible = game["visible_in_library"] as? Bool ?? true
        let systems = (object["supported_operating_systems"] as? [[String: Any]] ?? []).compactMap { $0["slug"] as? String }
        release.mac = systems.contains("osx")
        release.cover = image(game["vertical_cover"])
        // The store's tile when there's no background: wide, but with the title on it.
        release.hero = image(game["background"]) ?? image(game["horizontal_artwork"]) ?? image(game["logo"]) ?? image(object["logo"])
        release.dlcs = (object["dlcs"] as? [[String: Any]] ?? []).compactMap { dlc in
            guard dlc["platform_id"] as? String ?? "gog" == "gog" else { return nil }
            let id = (dlc["external_id"] as? String) ?? (dlc["external_id"] as? NSNumber)?.stringValue
            return id.flatMap { isProductID($0) ? $0 : nil }
        }
        return release
    }

    /// GamesDB's images come as "https://images.gog.com/<hash>{formatter}.{ext}": the full picture
    /// as a JPEG, only from https.
    static func image(_ value: Any?) -> URL? {
        guard let format = (value as? [String: Any])?["url_format"] as? String else { return nil }
        let url = URL(string: format.replacingOccurrences(of: "{formatter}", with: "").replacingOccurrences(of: "{ext}", with: "jpg"))
        return url?.scheme == "https" ? url : nil
    }

    /// GOG's product IDs are numbers – and become file names and keys (GameID).
    static func isProductID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 20 && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber)
    }
}

/// What `gogdl auth` hands over: the account's token for GOG's API, refreshed by gogdl when it ran
/// out – or nothing, when GOG turned the refresh down (signed out) or couldn't be reached.
enum GOGAuth: Equatable {
    case signedIn(token: String, user: String)
    case signedOut
    case offline
    /// gogdl itself didn't run: no answer at all, and an error code.
    case helperFailed

    /// `output`: gogdl's stdout (the credentials as JSON, or "null"); `log` its stderr, which says
    /// "Failed to refresh credentials" only when GOG didn't answer at all; `status` its exit code.
    static func from(output: Data, log: String, status: Int32 = 0) -> GOGAuth {
        if let object = try? JSONSerialization.jsonObject(with: output, options: .fragmentsAllowed) as? [String: Any],
           let token = object["access_token"] as? String, !token.isEmpty {
            let user = (object["user_id"] as? String) ?? (object["user_id"] as? NSNumber)?.stringValue ?? ""
            return .signedIn(token: token, user: user)
        }
        if log.contains("Failed to refresh credentials") || log.contains("Failed to reach GOG") { return .offline }
        if status != 0, !GOGDL.answered(Legendary.Output(status: status, output: output, log: log)) { return .helperFailed }
        return .signedOut
    }

    /// The tokens gogdl keeps (its auth.json, by client ID), while they're good: what `gogdl auth`
    /// would hand out without asking GOG – without its ~3 s start. nil once they run out (with a
    /// few minutes to spare): then gogdl refreshes them.
    static func stored(_ json: Data, now: Date = Date()) -> GOGAuth? {
        guard let all = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let credentials = all[GOGSignIn.clientID] as? [String: Any],
              let token = credentials["access_token"] as? String, !token.isEmpty,
              let loginTime = (credentials["loginTime"] as? NSNumber)?.doubleValue,
              let lifetime = (credentials["expires_in"] as? NSNumber)?.doubleValue,
              now.timeIntervalSince1970 < loginTime + lifetime - 300
        else { return nil }
        let user = (credentials["user_id"] as? String) ?? (credentials["user_id"] as? NSNumber)?.stringValue ?? ""
        return user.isEmpty ? nil : .signedIn(token: token, user: user)
    }
}

/// What a game comes to before it's downloaded, from `gogdl info --json` (gogdl reads the build's
/// manifest from GOG): kept per build in sizes.json, so the game page and the space check know it.
struct GOGSize: Codable, Equatable {
    /// The build it was read for: a newer one is asked again.
    var build: String
    /// What gogdl downloads (compressed) and what the game takes on disk – with the add-ons the
    /// player owns, in `language`.
    var download: Int64
    var install: Int64
    /// The language it downloads in: the Mac's, when GOG has the game in it.
    var language: String
    /// The folder it installs into (GOG's installDirectory).
    var folder: String
    var dlcs: [GOGDLC] = []

    static func from(info json: Data, preferred: [String] = Locale.preferredLanguages) -> GOGSize? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sizes = object["size"] as? [String: Any] else { return nil }
        let languages = (object["languages"] as? [Any] ?? []).compactMap { $0 as? String }
        let language = Self.language(available: languages, preferred: preferred)
        func amount(_ sizes: [String: Any]?, _ key: String) -> (download: Int64, install: Int64) {
            var total: (Int64, Int64) = (0, 0)
            for part in ["*", key] {
                guard let size = sizes?[part] as? [String: Any] else { continue }
                total.0 += (size["download_size"] as? NSNumber)?.int64Value ?? 0
                total.1 += (size["disk_size"] as? NSNumber)?.int64Value ?? 0
            }
            return total
        }
        var (download, install) = amount(sizes, language)
        var dlcs: [GOGDLC] = []
        for dlc in object["dlcs"] as? [[String: Any]] ?? [] {
            let id = (dlc["id"] as? String) ?? (dlc["id"] as? NSNumber)?.stringValue ?? ""
            guard GOGRelease.isProductID(id) else { continue }
            dlcs.append(GOGDLC(id: id, title: dlc["title"] as? String ?? id))
            let size = amount(dlc["size"] as? [String: Any], language)
            download += size.download
            install += size.install
        }
        let folder = object["folder_name"] as? String ?? ""
        let build = (object["buildId"] as? String) ?? (object["buildId"] as? NSNumber)?.stringValue ?? ""
        guard install > 0 || download > 0 else { return nil }
        return GOGSize(build: build, download: download, install: install, language: language,
                       folder: EpicLibrary.isFolderName(folder) ? folder : "", dlcs: dlcs)
    }

    /// The first of the Mac's languages GOG has the game in ("de-DE" for "de"), else English, else
    /// the first GOG has.
    static func language(available: [String], preferred: [String]) -> String {
        for wanted in preferred {
            let code = Locale(identifier: wanted).language.languageCode?.identifier ?? wanted
            if let match = available.first(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame })
                ?? available.first(where: { $0.lowercased().hasPrefix(code.lowercased() + "-") || $0.lowercased() == code.lowercased() }) {
                return match
            }
        }
        return available.first { $0.lowercased().hasPrefix("en") } ?? available.first ?? "en-US"
    }
}

/// The newest build GOG offers of a game (`content-system.gog.com/products/<id>/os/<os>/builds`):
/// the one without a branch (betas have one). Older games (generation 1) also carry a legacy ID.
struct GOGBuild: Codable, Equatable {
    var id: String
    var legacy: String?
    /// GOG's name for it ("update5A"), which the install script is given.
    var version: String?

    static func latest(fromJSON json: Data) -> GOGBuild? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let items = object["items"] as? [[String: Any]], !items.isEmpty else { return nil }
        let item = items.first { $0["branch"] == nil || $0["branch"] is NSNull } ?? items[0]
        guard let id = (item["build_id"] as? String) ?? (item["build_id"] as? NSNumber)?.stringValue else { return nil }
        return GOGBuild(id: id, legacy: (item["legacy_build_id"] as? String) ?? (item["legacy_build_id"] as? NSNumber)?.stringValue,
                        version: item["version_name"] as? String)
    }

    /// An installed build is this one.
    func matches(_ installed: String) -> Bool { installed == id || installed == legacy }
}

/// A game on the Mac, as Nightforge recorded it when its download finished (GOG/installed.json):
/// gogdl keeps no list of its own.
struct GOGInstall: Codable, Equatable {
    let id: String
    var path: URL
    /// The Mac version (an app) or the Windows one (through Wine).
    var platform: Platform
    var build: String
    var language: String
    var size: Int64
    /// The add-ons that came with it.
    var dlcs: [String] = []
}

/// What a game's own goggame-<id>.info says (written by the game's files): how it starts, and the
/// IDs its cloud saves go by.
struct GOGGameInfo: Equatable {
    var name = ""
    var build: String?
    var clientID: String?
    /// The primary play task: the program, relative to the game folder, its arguments and folder.
    var path: String
    var arguments: [String] = []
    var workingDir: String?

    static func from(json: Data) -> GOGGameInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let tasks = (object["playTasks"] as? [[String: Any]] ?? []).filter { ($0["type"] as? String ?? "FileTask") == "FileTask" && $0["path"] is String }
        guard let task = tasks.first(where: { $0["isPrimary"] as? Bool == true }) ?? tasks.first,
              let path = (task["path"] as? String).map(relative), isInside(path)
        else { return nil }
        var info = GOGGameInfo(path: path)
        info.name = object["name"] as? String ?? ""
        info.build = (object["buildId"] as? String) ?? (object["buildId"] as? NSNumber)?.stringValue
        info.clientID = object["clientId"] as? String
        if let arguments = task["arguments"] as? String {
            info.arguments = Launcher.splitArguments(arguments)
        } else if let arguments = task["arguments"] as? [String] {
            info.arguments = arguments
        }
        if let dir = (task["workingDir"] as? String).map(relative), !dir.isEmpty, isInside(dir) { info.workingDir = dir }
        return info
    }

    /// Where the file is: in the game folder, or in an app's Resources (GOG's Mac versions).
    static func file(id: String, in folder: URL) -> URL? {
        let name = "goggame-\(id).info"
        return [folder.appendingPathComponent(name), folder.appendingPathComponent("Contents/Resources/\(name)")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func read(id: String, in folder: URL) -> GOGGameInfo? {
        guard let file = file(id: id, in: folder), let data = try? Data(contentsOf: file) else { return nil }
        return from(json: data)
    }

    /// The Windows way of writing a path ("bin\Game.exe") the Mac way.
    private static func relative(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private static func isInside(_ path: String) -> Bool {
        !path.isEmpty && !path.split(separator: "/").contains("..") && !path.contains(":")
    }

    /// How the Windows version starts under Wine: the program, its folder (the game folder unless
    /// the task names one, as gogdl does) and arguments.
    func command(in folder: URL) -> StoreLaunchCommand {
        let executable = folder.appendingPathComponent(path)
        return StoreLaunchCommand(executable: executable,
                                  workingDirectory: workingDir.map { folder.appendingPathComponent($0, isDirectory: true) } ?? folder,
                                  arguments: arguments, environment: [:])
    }
}

/// GOG's cloud saves: where a game keeps its saves on the Mac (GOG's remote config names folders
/// like <?SAVED_GAMES?>/Studio/Game), each synced with gogdl under its name.
enum GOGSaves {
    struct Location: Equatable {
        let name: String
        let folder: URL
    }

    /// `json`: `remote-config.gog.com/components/galaxy_client/clients/<clientId>`. nil when the
    /// game keeps no saves with GOG; without named folders it uses GOG Galaxy's default one.
    static func locations(fromConfig json: Data, platform: Platform, clientID: String, installDir: URL,
                          windowsUser: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Location]? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let content = object["content"] as? [String: Any],
              let system = content[platform == .mac ? "MacOS" : "Windows"] as? [String: Any],
              let storage = system["cloudStorage"] as? [String: Any], storage["enabled"] as? Bool == true
        else { return nil }
        var named = (storage["locations"] as? [[String: Any]] ?? []).compactMap { location -> (String, String)? in
            guard let name = location["name"] as? String, let path = location["location"] as? String else { return nil }
            return (name, path)
        }
        if named.isEmpty {
            let base = platform == .mac ? "<?APPLICATION_SUPPORT?>" : "<?APPLICATION_DATA_LOCAL?>"
            named = [("__default", "\(base)/GOG.com/Galaxy/Applications/\(clientID)/Storage/Shared/Files")]
        }
        let found = named.compactMap { name, path in
            resolve(path, platform: platform, installDir: installDir, windowsUser: windowsUser, home: home).map { Location(name: name, folder: $0) }
        }
        return found.isEmpty ? nil : found
    }

    /// "<?SAVED_GAMES?>/Studio/Game" → the folder on the Mac: in the Windows user's folder of the
    /// Windows environment, or the Mac's own for Mac versions. Unknown variables and paths that
    /// climb out give nothing.
    static func resolve(_ template: String, platform: Platform, installDir: URL, windowsUser: URL, home: URL) -> URL? {
        let path = template.replacingOccurrences(of: "\\", with: "/")
        guard path.hasPrefix("<?"), let end = path.range(of: "?>") else { return nil }
        let variable = String(path[path.index(path.startIndex, offsetBy: 2)..<end.lowerBound])
        let rest = path[end.upperBound...].split(separator: "/").map(String.init)
        guard !rest.contains(".."), !rest.contains(where: { $0.contains(":") }) else { return nil }
        let base: URL?
        switch (variable, platform) {
        case ("INSTALL", _): base = installDir
        case ("DOCUMENTS", .windows): base = windowsUser.appendingPathComponent("Documents")
        case ("SAVED_GAMES", .windows): base = windowsUser.appendingPathComponent("Saved Games")
        case ("APPLICATION_DATA_LOCAL", .windows): base = windowsUser.appendingPathComponent("AppData/Local")
        case ("APPLICATION_DATA_LOCAL_LOW", .windows): base = windowsUser.appendingPathComponent("AppData/LocalLow")
        case ("APPLICATION_DATA_ROAMING", .windows): base = windowsUser.appendingPathComponent("AppData/Roaming")
        case ("DOCUMENTS", .mac): base = home.appendingPathComponent("Documents")
        case ("APPLICATION_SUPPORT", .mac): base = home.appendingPathComponent("Library/Application Support")
        default: base = nil
        }
        return base.map { rest.reduce($0) { $0.appendingPathComponent($1, isDirectory: true) } }
    }
}

/// Whether a Mac program runs on this Mac: GOG still has Mac versions from the 32-bit days, which
/// macOS no longer starts. A Mac version whose program is 32-bit only gives way to the Windows one.
enum MachO {
    static let x86_64: UInt32 = 0x0100_0007
    static let arm64: UInt32 = 0x0100_000C

    /// From the program's first bytes: true for 64-bit Intel or Apple silicon, false for 32-bit
    /// only, nil when it isn't a Mac program (a script, say – it runs as it is).
    static func runsHere(_ header: Data) -> Bool? {
        guard header.count >= 8 else { return nil }
        let bytes = [UInt8](header.prefix(4096))
        func uint32(_ at: Int, bigEndian: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            let value = bytes[at..<at + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return bigEndian ? value : value.byteSwapped
        }
        switch uint32(0, bigEndian: true) {
        case 0xCFFA_EDFE: return true   // thin, 64-bit
        case 0xCEFA_EDFE: return false  // thin, 32-bit
        case 0xCAFE_BABE, 0xCAFE_BABF:  // universal: does it hold a 64-bit slice?
            let count = Int(uint32(4, bigEndian: true))
            let stride = uint32(0, bigEndian: true) == 0xCAFE_BABF ? 32 : 20
            guard count > 0, count < 32 else { return nil }  // Java class files share the magic
            return (0..<count).contains { [x86_64, arm64].contains(uint32(8 + $0 * stride, bigEndian: true)) }
        default: return nil
        }
    }

    /// The program an app or a play task starts: an app's own (Info.plist), or the file itself.
    static func program(_ url: URL) -> URL {
        guard url.pathExtension == "app",
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let name = info["CFBundleExecutable"] as? String, !name.contains("/") else { return url }
        return url.appendingPathComponent("Contents/MacOS/\(name)")
    }

    static func runsHere(file: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: program(file)) else { return nil }
        defer { try? handle.close() }
        return runsHere((try? handle.read(upToCount: 4096)) ?? Data())
    }
}
