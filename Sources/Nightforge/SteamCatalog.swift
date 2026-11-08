import Foundation

/// A game the signed-in Steam account owns, installed or not – or, from `SteamCatalog.unownedGames`,
/// one it doesn't.
struct CatalogApp: Hashable {
    let appID: Int
    let name: String
    let installDir: String
    /// The account holds a licence for it.
    var owned = true
    /// A demo: the game it's the demo of.
    var demoOf: Int?
    /// Windows download size of the default (English) depots, 0 if Steam doesn't say.
    let size: Int64
    /// Steam marks it as playable only with a VR headset.
    var vrOnly = false
    /// Steam also has a macOS version of it.
    var macNative = false
    /// That Mac version is 64-bit, so it still runs: macOS dropped 32-bit apps with Catalina.
    var mac64 = false
    /// It's built for Apple silicon, not only for Intel Macs (which Rosetta stands in for).
    var macAppleSilicon = false
    /// Download size of the Mac version, 0 if Steam doesn't say.
    var macSize: Int64 = 0
    /// Steam has a Windows version (nearly always; a few games are Mac or Linux only).
    var windows = true
    var controller = ControllerSupport.none
    /// Steam lists a single-player mode (or says nothing about it); false: online only.
    var singlePlayer = true
    /// How it's played, from its store categories (local co-op, split screen …).
    var modes: Set<PlayMode> = []
    /// Its store tags, genres, release and Metacritic score.
    var store = StoreFacts()
}

/// What the Steam store says about playing a game with a controller.
enum ControllerSupport: String {
    /// Everything works with a controller: playable from the couch.
    case full
    /// Some parts (menus, typing) want a mouse or keyboard.
    case partial
    /// Not declared: made for mouse and keyboard.
    case none
}

/// One Steam Cloud save location of a game: a folder under a Windows root ("WinAppDataRoaming",
/// "gameinstall", …) holding files that match `pattern`, and where Steam puts it on macOS.
struct SaveRule: Equatable {
    let root: String
    /// May hold Steam's placeholders, e.g. "HelloGames/NMS/st_{64BitSteamID}/".
    let path: String
    let pattern: String
    let recursive: Bool
    /// The macOS root ("MacAppSupport", …) and what goes in front of `path` there; nil: no Mac folder.
    let macRoot: String?
    let macAddPath: String
}

/// Reads the owned-games list from the caches Steam keeps after sign-in: the account's licence
/// list (`userdata/<account>/config/licensecache`, which packages it holds), `appcache/packageinfo.vdf`
/// (packages → app IDs) and `appcache/appinfo.vdf` (name, type, depots). No API key, no network,
/// nothing sent anywhere: Steam has already downloaded all of it for its own library view.
enum SteamCatalog {
    private struct Catalog {
        var owned: [CatalogApp] = []
        var unowned: [CatalogApp] = []
        /// Every app the account holds a valid licence for; nil without a readable licence list.
        var licensed: Set<Int>?
    }

    /// Per Steam install, keyed by when its catalog files last changed.
    private static var cache: [String: (modified: Date, catalog: Catalog)] = [:]
    private static let lock = NSLock()
    /// The store facts of the last read, per Steam install and app ID. A lock of their own: they're
    /// asked while drawing, which mustn't wait for a scan reading the catalog.
    private static var facts: [String: [Int: StoreFacts]] = [:]
    private static let factsLock = NSLock()

    static func ownedGames(steamRoot: URL) -> [CatalogApp] {
        catalog(steamRoot: steamRoot).owned
    }

    /// Games Steam's caches know but the account doesn't own – an expired free weekend, a store
    /// page looked at in Steam: each as its demo where Steam has one (`demoOf` set, `owned` says
    /// whether the account has the demo's free licence yet), else as the game (`owned` false).
    /// Empty without a readable licence list: then every cached package counts as owned.
    static func unownedGames(steamRoot: URL) -> [CatalogApp] {
        catalog(steamRoot: steamRoot).unowned
    }

    /// Whether the account holds a licence for an app; nil when the licence list can't be read.
    static func owns(_ appID: Int, steamRoot: URL) -> Bool? {
        catalog(steamRoot: steamRoot).licensed?.contains(appID)
    }

    private static func catalog(steamRoot: URL) -> Catalog {
        let appinfo = steamRoot.appendingPathComponent("appcache/appinfo.vdf")
        let packageinfo = steamRoot.appendingPathComponent("appcache/packageinfo.vdf")
        let licenses = licenseFile(steamRoot: steamRoot)
        let modified = ([appinfo, packageinfo].compactMap(modificationDate) + [licenses?.modified].compactMap { $0 })
            .max() ?? .distantPast

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[steamRoot.path], cached.modified == modified { return cached.catalog }

        guard let apps = try? Data(contentsOf: appinfo), let packages = try? Data(contentsOf: packageinfo) else { return Catalog() }
        let packageApps = appIDsByPackage(Array(packages))
        let licensedPackages = licenses.flatMap { file in
            (try? Data(contentsOf: file.url)).flatMap { Self.licenses(Array($0), accountID: file.accountID) }
        }
        var result = Catalog()
        result.licensed = licensedPackages.map { packages in
            Set(packages.filter { $0.value & unusableLicense == 0 }.keys.flatMap { packageApps[$0] ?? [] })
        }
        let cached = Set(packageApps.values.joined())
        let entries = appEntries(Array(apps))
        let games = entries.filter { $0.demoOf == nil }
        var demos: [Int: CatalogApp] = [:]
        for demo in entries where demo.demoOf != nil && (demos[demo.demoOf!]?.appID ?? .max) > demo.appID {
            demos[demo.demoOf!] = demo
        }
        let byName = { (a: CatalogApp, b: CatalogApp) in a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        result.owned = games.filter { (result.licensed ?? cached).contains($0.appID) }.sorted(by: byName)
        if let licensed = result.licensed {
            result.unowned = games.filter { cached.contains($0.appID) && !licensed.contains($0.appID) }.map { game in
                var entry = demos[game.appID] ?? game
                entry.owned = entry.demoOf != nil && licensed.contains(entry.appID)
                return entry
            }.sorted(by: byName)
        }
        cache[steamRoot.path] = (modified, result)
        factsLock.lock()
        facts[steamRoot.path] = Dictionary((result.owned + result.unowned).map { ($0.appID, $0.store) },
                                           uniquingKeysWith: { first, _ in first })
        factsLock.unlock()
        return result
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Genre, release and Metacritic score of an owned game, as the last scan read them – without
    /// touching the disk, so a view can ask while drawing. Another Steam install (Steam for Mac
    /// beside Nightforge's own) stands in when the game's own doesn't know it. nil before a scan.
    static func storeFacts(appID: Int, steamRoot: URL) -> StoreFacts? {
        factsLock.lock()
        defer { factsLock.unlock() }
        return facts[steamRoot.path]?[appID] ?? facts.values.lazy.compactMap { $0[appID] }.first
    }

    // MARK: - Launch options

    /// One of a game's launch options in appinfo (config/launch): the program relative to the game
    /// folder, what it adds, its type ("default", "option1", "none"), the name Steam's question shows,
    /// and the beta branch it's only for.
    struct LaunchEntry: Equatable {
        var executable: String
        var arguments = ""
        var type = ""
        var description = ""
        var betaKey = ""

        /// The same program as `other` ("Binaries/Win64/Game.exe" is "binaries\win64\game.exe").
        func starts(_ other: String) -> Bool {
            func plain(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/").lowercased() }
            return plain(executable) == plain(other)
        }
    }

    /// The game's Windows launch options in Steam's order; the first is the one -applaunch starts.
    static func launchEntries(appID: Int, steamRoot: URL) -> [LaunchEntry] {
        windowsLaunchOptions(appID: appID, steamRoot: steamRoot).map { option in
            LaunchEntry(executable: option["executable"]?.string ?? "", arguments: option["arguments"]?.string ?? "",
                        type: option["type"]?.string ?? "", description: option["description"]?.string ?? "",
                        betaKey: option["config"]?.object?["betakey"]?.string ?? "")
        }
    }

    /// Easy Anti-Cheat and BattlEye don't run under Wine on a Mac, so a game that offers a Windows
    /// launch option without them (7 Days to Die: "Launch game without EAC") should use it. Returns
    /// what that option adds to the default one; Steam appends extra -applaunch arguments to the
    /// default option, which gives the same command line. Empty when there's no such option, or when
    /// it starts another program (Rocket League's RocketLeague.exe: SteamProgram).
    static func antiCheatOffArguments(appID: Int, steamRoot: URL) -> [String] {
        antiCheatOffArguments(launchEntries(appID: appID, steamRoot: steamRoot))
    }

    static func antiCheatOffArguments(_ entries: [LaunchEntry]) -> [String] {
        guard let standard = entries.first, let candidate = antiCheatOff(entries), candidate.starts(standard.executable)
        else { return [] }
        let base = standard.arguments.split(separator: " ").map(String.init)
        let extra = candidate.arguments.split(separator: " ").map(String.init)
        guard extra.starts(with: base) else {
            return extra.filter { !base.contains($0) }
        }
        return Array(extra.dropFirst(base.count))
    }

    /// The game's launch option without anti-cheat, if it has one besides the default.
    static func antiCheatOff(_ entries: [LaunchEntry]) -> LaunchEntry? {
        let markers = ["-noeac", "-forceeac off", "-nobattleye", "-noanticheat", "-no-anticheat"]
        return entries.dropFirst().first { option in
            let arguments = option.arguments.lowercased()
            let description = option.description.lowercased()
            let mentionsAntiCheat = ["eac", "anti-cheat", "anticheat", "battleye"].contains { description.contains($0) }
            let saysWithout = ["without", "no eac", "no anti", "no battleye", "disable", "ohne"].contains { description.contains($0) }
            return markers.contains { arguments.contains($0) } || (mentionsAntiCheat && saysWithout)
        }
    }

    /// The program Steam starts with the game's default Windows launch option, relative to the
    /// game folder ("Binaries\NMS.exe"); nil when Steam doesn't say.
    static func launchExecutable(appID: Int, steamRoot: URL) -> String? {
        windowsLaunchOptions(appID: appID, steamRoot: steamRoot).first?["executable"]?.string
    }

    /// Where Steam Cloud finds a game's saves (appinfo ufs/savefiles), with the macOS folder each
    /// Windows one maps to (ufs/rootoverrides). Rules only for other systems are left out.
    static func saveRules(appID: Int, steamRoot: URL) -> [SaveRule] {
        guard let ufs = cachedAppInfo(appID: appID, steamRoot: steamRoot)?["ufs"]?.object else { return [] }
        let overrides = (ufs["rootoverrides"]?.object ?? [:]).values.compactMap(\.object)
            .filter { ($0["os"]?.string ?? "").lowercased() == "macos" && $0["pathtransforms"] == nil }
        return (ufs["savefiles"]?.object ?? [:]).sorted { $0.key < $1.key }.compactMap { _, value in
            guard let rule = value.object, let root = rule["root"]?.string else { return nil }
            let platforms = (rule["platforms"]?.object ?? [:]).values.compactMap { $0.string?.lowercased() }
            if !platforms.isEmpty && !platforms.contains("all") && !(platforms.contains("windows") && platforms.contains("macos")) {
                return nil
            }
            let mac = overrides.first { $0["root"]?.string?.lowercased() == root.lowercased() }
            return SaveRule(root: root, path: rule["path"]?.string ?? "", pattern: rule["pattern"]?.string ?? "*",
                            recursive: rule["recursive"]?.int == 1,
                            macRoot: mac?["useinstead"]?.string ?? (root.lowercased() == "gameinstall" ? root : nil),
                            macAddPath: mac?["addpath"]?.string ?? "")
        }
    }

    /// The game's macOS launch options in Steam's order, from Steam for Mac's appinfo (SteamProgram.macLaunchType).
    static func macLaunchEntries(appID: Int, steamRoot: URL) -> [LaunchEntry] {
        launchOptions(appID: appID, steamRoot: steamRoot, os: "macos").map { option in
            LaunchEntry(executable: option["executable"]?.string ?? "", arguments: option["arguments"]?.string ?? "",
                        type: option["type"]?.string ?? "", description: option["description"]?.string ?? "",
                        betaKey: option["config"]?.object?["betakey"]?.string ?? "")
        }
    }

    /// The game's launch options that apply to Windows, in Steam's order.
    private static func windowsLaunchOptions(appID: Int, steamRoot: URL) -> [[String: BinaryKV]] {
        launchOptions(appID: appID, steamRoot: steamRoot, os: "windows")
    }

    /// The game's launch options that apply to `os` ("windows", "macos"), in Steam's order.
    private static func launchOptions(appID: Int, steamRoot: URL, os target: String) -> [[String: BinaryKV]] {
        guard let launch = cachedAppInfo(appID: appID, steamRoot: steamRoot)?["config"]?.object?["launch"]?.object
        else { return [] }
        return launch
            .compactMap { key, value -> (index: Int, option: [String: BinaryKV])? in
                guard let index = Int(key), let option = value.object else { return nil }
                let os = option["config"]?.object?["oslist"]?.string ?? ""
                return os.isEmpty || os.contains(target) ? (index, option) : nil
            }
            .sorted { $0.index < $1.index }
            .map(\.option)
    }

    /// One app's appinfo, read once per change of appinfo.vdf: the file is megabytes with a big
    /// library, and every start and every selection asks for launch options or save rules.
    private static var appInfoCache: [String: (modified: Date, info: [String: BinaryKV]?)] = [:]
    private static let appInfoLock = NSLock()

    private static func cachedAppInfo(appID: Int, steamRoot: URL) -> [String: BinaryKV]? {
        let file = steamRoot.appendingPathComponent("appcache/appinfo.vdf")
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let key = "\(steamRoot.path)#\(appID)"
        appInfoLock.lock()
        defer { appInfoLock.unlock() }
        if let cached = appInfoCache[key], cached.modified == modified { return cached.info }
        // The file itself is read once per change too, not again for each other game (release review C4).
        let bytes: [UInt8]
        if let file = appInfoFile[steamRoot.path], file.modified == modified {
            bytes = file.bytes
        } else {
            guard let data = try? Data(contentsOf: file) else { return nil }
            bytes = Array(data)
            // Kept only up to 64 MB, so a huge library doesn't hold its whole appinfo in memory for good.
            appInfoFile[steamRoot.path] = bytes.count <= 64 << 20 ? (modified, bytes) : nil
        }
        let info = appInfo(bytes, appID: appID)
        appInfoCache[key] = (modified, info)
        return info
    }
    private static var appInfoFile: [String: (modified: Date, bytes: [UInt8])] = [:]

    /// The "appinfo" section of one app in appinfo.vdf.
    private static func appInfo(_ bytes: [UInt8], appID wanted: Int) -> [String: BinaryKV]? {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return nil }
        var strings: [String]?
        if magic == 0x0756_4429 {
            guard let tableOffset = reader.i64(), tableOffset > 0, Int(tableOffset) < bytes.count else { return nil }
            var table = ByteReader(bytes, at: Int(tableOffset))
            let count = table.u32() ?? 0
            strings = (0..<count).compactMap { _ in table.cString() }
        } else if magic != 0x0756_4428 && magic != 0x0756_4427 {
            return nil
        }
        let headerSkip = 4 + 4 + 8 + 20 + 4 + (magic >= 0x0756_4428 ? 20 : 0)
        while let appID = reader.u32(), appID != 0, let size = reader.u32() {
            let end = reader.position + Int(size)
            if appID == wanted {
                reader.skip(headerSkip)
                return BinaryKV.parse(&reader, strings: strings)?["appinfo"]?.object
            }
            reader.position = end
        }
        return nil
    }

    // MARK: - licensecache

    /// ELicenseFlags of a licence that gives nothing to play: pending (4), expired (8, a free
    /// weekend that ended), cancelled by the player (16) or by Steam (32, a refund), or locked
    /// for fraud (1024).
    private static let unusableLicense = 4 | 8 | 16 | 32 | 1024

    /// The licence list of the account that signed in last: Steam keeps one per account, in
    /// userdata/<account ID>/config/licensecache.
    private static func licenseFile(steamRoot: URL) -> (url: URL, accountID: UInt32, modified: Date)? {
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        let users = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        return users.compactMap { user -> (url: URL, accountID: UInt32, modified: Date)? in
            guard let accountID = UInt32(user.lastPathComponent), accountID != 0 else { return nil }
            let file = user.appendingPathComponent("config/licensecache")
            return modificationDate(file).map { (file, accountID, $0) }
        }.max { $0.modified < $1.modified }
    }

    /// The packages in an account's licence list, with their ELicenseFlags. licensecache holds the
    /// list the Steam servers send at sign-in (CMsgClientLicenseList, protobuf) plus its CRC32,
    /// XORed with `licenseCipher`. nil when it doesn't check out.
    static func licenses(_ bytes: [UInt8], accountID: UInt32) -> [Int: Int]? {
        guard bytes.count > 4 else { return nil }
        let plain = licenseCipher(bytes, accountID: accountID)
        let body = Array(plain.dropLast(4))
        let stored = plain.suffix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard crc32(body) == stored, let list = protobufFields(body[...]) else { return nil }
        var packages: [Int: Int] = [:]
        for field in list where field.number == 2 {  // repeated License licenses = 2
            guard let bytes = field.bytes, let license = protobufFields(bytes) else { return nil }
            let packageID = Int(license.first { $0.number == 1 }?.value ?? 0)  // package_id = 1
            let flags = Int(license.first { $0.number == 7 }?.value ?? 0)      // flags = 7
            // Two licences for one package: one that's still good is enough.
            if let held = packages[packageID], held & unusableLicense == 0 { continue }
            packages[packageID] = flags
        }
        return packages
    }

    /// Steam's own scrambling of licensecache: each byte XORed with RandomInt(32, 126) from Valve's
    /// uniform random stream (vstdlib, Numerical Recipes' ran1) seeded with the account ID. The
    /// same both ways.
    static func licenseCipher(_ bytes: [UInt8], accountID: UInt32) -> [UInt8] {
        var stream = UniformRandomStream(seed: Int32(bitPattern: accountID))
        return bytes.map { $0 ^ UInt8(stream.randomInt(32, 126)) }
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 != 0 ? crc >> 1 ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// The fields of a protobuf message: varints and fixed-size numbers as `value`, length-delimited
    /// ones as `bytes`. nil when it's cut off or has a wire type protobuf doesn't use any more.
    private static func protobufFields(_ bytes: ArraySlice<UInt8>) -> [(number: Int, value: UInt64, bytes: ArraySlice<UInt8>?)]? {
        var position = bytes.startIndex
        func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard position < bytes.endIndex else { return nil }
                let byte = bytes[position]
                position += 1
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte < 0x80 { return value }
            }
            return nil
        }
        func fixed(_ size: Int) -> UInt64? {
            guard bytes.endIndex - position >= size else { return nil }
            defer { position += size }
            return (0..<size).reduce(UInt64(0)) { $0 | UInt64(bytes[position + $1]) << UInt64(8 * $1) }
        }
        var fields: [(number: Int, value: UInt64, bytes: ArraySlice<UInt8>?)] = []
        while position < bytes.endIndex {
            guard let key = varint() else { return nil }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0: guard let value = varint() else { return nil }; fields.append((number, value, nil))
            case 1: guard let value = fixed(8) else { return nil }; fields.append((number, value, nil))
            case 5: guard let value = fixed(4) else { return nil }; fields.append((number, value, nil))
            case 2:
                guard let length = varint(), length <= UInt64(bytes.endIndex - position) else { return nil }
                fields.append((number, 0, bytes[position..<position + Int(length)]))
                position += Int(length)
            default: return nil
            }
        }
        return fields
    }

    // MARK: - packageinfo.vdf

    /// Each cached package's app IDs. Steam caches packages it doesn't hold a licence for too
    /// (expired free weekends, games whose store page was opened), so this alone isn't ownership.
    private static func appIDsByPackage(_ bytes: [UInt8]) -> [Int: [Int]] {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return [:] }
        let hasToken = magic >= 0x0656_5528
        var packages: [Int: [Int]] = [:]

        while let packageID = reader.u32(), packageID != 0xFFFF_FFFF {
            reader.skip(20 + 4 + (hasToken ? 8 : 0))  // sha1, change number, PICS token
            guard case .object(let root)? = BinaryKV.parse(&reader, strings: nil) else { break }
            for case .object(let package) in root.values {
                guard case .object(let appIDs)? = package["appids"] else { continue }
                packages[Int(packageID), default: []] += appIDs.values.compactMap(\.int)
            }
        }
        return packages
    }

    // MARK: - appinfo.vdf

    /// Games, and demos that name the game they're for.
    private static func appEntries(_ bytes: [UInt8]) -> [CatalogApp] {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return [] }
        // v29 keeps key names in a string table at the end of the file.
        var strings: [String]?
        if magic == 0x0756_4429 {
            guard let tableOffset = reader.i64(), tableOffset > 0, Int(tableOffset) < bytes.count else { return [] }
            var table = ByteReader(bytes, at: Int(tableOffset))
            let count = table.u32() ?? 0
            strings = (0..<count).compactMap { _ in table.cString() }
        } else if magic != 0x0756_4428 && magic != 0x0756_4427 {
            return []
        }
        let headerSkip = 4 + 4 + 8 + 20 + 4 + (magic >= 0x0756_4428 ? 20 : 0)

        var games: [CatalogApp] = []
        while let appID = reader.u32(), appID != 0, let size = reader.u32() {
            let end = reader.position + Int(size)
            reader.skip(headerSkip)
            if case .object(let root)? = BinaryKV.parse(&reader, strings: strings),
               let info = root["appinfo"]?.object,
               let common = info["common"]?.object,
               let type = common["type"]?.string?.lowercased(),
               type == "game" || (type == "demo" && common["parent"]?.int != nil),
               let name = common["name"]?.string?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                let installDir = info["config"]?.object?["installdir"]?.string ?? name
                let oslist = common["oslist"]?.string ?? ""
                let depots = info["depots"]?.object
                var game = CatalogApp(appID: Int(appID), name: name, installDir: installDir,
                                      demoOf: type == "demo" ? common["parent"]?.int : nil,
                                      size: downloadSize(depots, os: "windows"),
                                      vrOnly: common["onlyvrsupport"]?.int == 1,
                                      macNative: oslist.contains("macos"),
                                      windows: oslist.isEmpty || oslist.contains("windows"))
                game.controller = controllerSupport(common)
                game.store = storeFacts(common)
                // Store category 2 is "Single-player"; a game with categories but not that one is online only.
                if let categories = common["category"]?.object, !categories.isEmpty {
                    game.singlePlayer = categories["category_2"] != nil
                    game.modes = PlayMode.steam(Set(categories.keys.compactMap { Int($0.dropFirst("category_".count)) }))
                }
                if game.macNative {
                    (game.mac64, game.macAppleSilicon) = macBuild(common: common, depots: depots,
                                                                  launch: info["config"]?.object?["launch"]?.object)
                    game.macSize = downloadSize(depots, os: "macos")
                }
                games.append(game)
            }
            reader.position = end
        }
        return games
    }

    /// Store tags (most voted first), genres, release dates and Metacritic score from common.
    private static func storeFacts(_ common: [String: BinaryKV]) -> StoreFacts {
        func ids(_ key: String) -> [Int] {
            (common[key]?.object ?? [:])
                .compactMap { key, value in Int(key).flatMap { place in value.int.map { (place, $0) } } }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
        // A game out elsewhere (or in Early Access) before Steam's release date came out then.
        let released = ["steam_release_date", "original_release_date"]
            .compactMap { common[$0]?.int }.filter { $0 > 0 }.min()
        return StoreFacts(tags: ids("store_tags"), genres: ids("genres"), primaryGenre: common["primary_genre"]?.int,
                          released: released.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                          metascore: common["metacritic_score"]?.int.flatMap { $0 > 0 ? $0 : nil })
    }

    /// common/controller_support ("full", "partial"), or the store categories that say the same:
    /// 28 "Full controller support", 18 "Partial Controller Support".
    private static func controllerSupport(_ common: [String: BinaryKV]) -> ControllerSupport {
        if let declared = common["controller_support"]?.string.flatMap({ ControllerSupport(rawValue: $0.lowercased()) }) {
            return declared
        }
        let categories = common["category"]?.object ?? [:]
        if categories["category_28"] != nil { return .full }
        if categories["category_18"] != nil { return .partial }
        return .none
    }

    /// Whether the Mac version still runs on current macOS. Valve marks 64-bit Mac builds with
    /// "macos64" in common/osextended (Apple silicon ones also with "macosapplesilicon"); some
    /// entries only say it per depot or launch option (osarch 64). Unknown counts as 32-bit.
    private static func macBuild(common: [String: BinaryKV], depots: [String: BinaryKV]?,
                                 launch: [String: BinaryKV]?) -> (is64: Bool, appleSilicon: Bool) {
        let extended = (common["osextended"]?.string ?? "").lowercased()
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let appleSilicon = extended.contains("macosapplesilicon")
        if appleSilicon || extended.contains("macos64") { return (true, appleSilicon) }
        let configs = (depots ?? [:]).values.compactMap { $0.object?["config"]?.object }
            + (launch ?? [:]).values.compactMap { $0.object?["config"]?.object }
        let declares64 = configs.contains { ($0["oslist"]?.string ?? "").contains("macos") && $0["osarch"]?.string == "64" }
        return (declares64, false)
    }

    /// Download size of the default (English) depots for one OS ("windows", "macos").
    private static func downloadSize(_ depots: [String: BinaryKV]?, os: String) -> Int64 {
        var total: Int64 = 0
        for (key, value) in depots ?? [:] where Int(key) != nil {
            guard let depot = value.object else { continue }
            // DLC content, shared redistributables and optional extras aren't part of the base download.
            if depot["dlcappid"] != nil || depot["sharedinstall"] != nil || depot["depotfromapp"] != nil { continue }
            let config = depot["config"]?.object
            if config?["optionaldlc"] != nil || config?["lowviolence"]?.int == 1 { continue }
            if let arch = config?["osarch"]?.string, arch == "32", depots?.values.contains(where: {
                $0.object?["config"]?.object?["osarch"]?.string == "64"
            }) == true { continue }
            if let list = config?["oslist"]?.string, !list.isEmpty, !list.contains(os) { continue }
            if let language = config?["language"]?.string, !language.isEmpty, language != "english" { continue }
            let manifest = depot["manifests"]?.object?["public"]
            let size = manifest?.object?["size"]?.string.flatMap { Int64($0) } ?? manifest?.object?["size"]?.int.map(Int64.init)
            total += size ?? 0
        }
        return total
    }
}

/// Valve's binary KeyValues as used in appinfo/packageinfo.
private indirect enum BinaryKV {
    case object([String: BinaryKV])
    case string(String)
    case number(Int64)

    var object: [String: BinaryKV]? { if case .object(let o) = self { return o } else { return nil } }
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .object: return nil
        }
    }
    var int: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        case .object: return nil
        }
    }

    subscript(key: String) -> BinaryKV? { object?[key] }

    /// How deep objects may nest: Steam's files go to about eight levels. The file lies in the prefix, which
    /// Windows programs can write to – thousands of nested objects (two bytes each) would overflow the stack
    /// here and crash Nightforge at every scan.
    static let maxDepth = 64

    /// Parses one object body (until its 0x08 terminator). Keys are lowercased. nil past `maxDepth`.
    static func parse(_ reader: inout ByteReader, strings: [String]?, depth: Int = 0) -> BinaryKV? {
        guard depth <= maxDepth else { return nil }
        var dict: [String: BinaryKV] = [:]
        while let type = reader.u8() {
            if type == 0x08 { return .object(dict) }
            let key: String?
            if let strings {
                key = reader.u32().flatMap { Int($0) < strings.count ? strings[Int($0)] : nil }
            } else {
                key = reader.cString()
            }
            guard let name = key?.lowercased() else { return nil }

            switch type {
            case 0x00: guard let child = parse(&reader, strings: strings, depth: depth + 1) else { return nil }; dict[name] = child
            case 0x01: guard let s = reader.cString() else { return nil }; dict[name] = .string(s)
            case 0x02: guard let v = reader.u32() else { return nil }; dict[name] = .number(Int64(Int32(bitPattern: v)))
            case 0x03: reader.skip(4)  // float, not needed
            case 0x07: guard let v = reader.i64() else { return nil }; dict[name] = .number(v)
            case 0x0A: guard let v = reader.i64() else { return nil }; dict[name] = .number(v)
            default: return nil
            }
        }
        return nil
    }
}

/// Valve's CUniformRandomStream (vstdlib/random.cpp): Numerical Recipes' ran1, a Park–Miller
/// generator behind a 32-entry shuffle table. 32-bit arithmetic in C; no step leaves that range.
private struct UniformRandomStream {
    private var idum: Int
    private var iy = 0
    private var table = [Int](repeating: 0, count: 32)

    init(seed: Int32) {
        idum = seed < 0 ? Int(seed) : -Int(seed)
    }

    private mutating func step() {
        let k = idum / 127_773
        idum = 16_807 * (idum - k * 127_773) - 2_836 * k
        if idum < 0 { idum += 2_147_483_647 }
    }

    private mutating func next() -> Int {
        if idum <= 0 || iy == 0 {
            idum = -idum < 1 ? 1 : -idum
            for j in stride(from: 39, through: 0, by: -1) {
                step()
                if j < 32 { table[j] = idum }
            }
            iy = table[0]
        }
        step()
        let j = iy / 67_108_864  // 1 + (2^31 - 2) / 32
        iy = table[j]
        table[j] = idum
        return iy
    }

    /// Uniform in low...high, re-drawing the few numbers that would favour the low end.
    mutating func randomInt(_ low: Int, _ high: Int) -> Int {
        let range = high - low + 1
        let maxAcceptable = 0x7FFF_FFFF - 0x8000_0000 % range
        var n = next()
        while n > maxAcceptable { n = next() }
        return low + n % range
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var position: Int

    init(_ bytes: [UInt8], at position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    mutating func skip(_ count: Int) { position += count }

    mutating func u8() -> UInt8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u32() -> UInt32? {
        guard position + 4 <= bytes.count else { return nil }
        defer { position += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[position + $1]) << (8 * $1) }
    }

    mutating func i64() -> Int64? {
        guard position + 8 <= bytes.count else { return nil }
        defer { position += 8 }
        let raw = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[position + $1]) << (8 * UInt64($1)) }
        return Int64(bitPattern: raw)
    }

    mutating func cString() -> String? {
        guard let end = bytes[position...].firstIndex(of: 0) else { return nil }
        defer { position = end + 1 }
        return String(decoding: bytes[position..<end], as: UTF8.self)
    }
}
