import Foundation

/// Fixes for one game from profiles/profiles.json, built nightly from umu-protonfixes plus
/// Nightforge's own Mac profiles (scripts/build-profiles.py). Applied silently at launch.
struct GameProfile: Decodable, Equatable {
    var name: String?
    /// Where it comes from: "mac" (Nightforge's own, tested on Macs), "umu", "anticheat", or a
    /// mix like "umu+mac".
    var source: String?
    /// What testing found, for Nightforge's own profiles ("Tested 2026-10-26 on M5: …").
    var note: String?
    /// Graphics layer for games left on "Automatic".
    var graphics: GraphicsLayer?
    /// Appended to the game's command line.
    var arguments: [String]?
    /// DLL → load order as Wine writes it ("native,builtin", "" = disabled), for the game's programs.
    var dllOverrides: [String: String]?
    var registry: [RegistryEntry]?
    /// Windows version the game's programs see ("win7", …); the rest of the prefix keeps its own.
    var windowsVersion: String?
    /// winetricks verbs installed into the prefix before the first start.
    var winetricks: [String]?
    /// false: MetalFX upscaling misbehaves in this game, so "Automatic" leaves it off.
    var metalFX: Bool?
    /// Frame limit "Automatic" uses for this game instead of the display-based one.
    var frameLimit: Int?
    /// Vulkan games: samplers per shader stage reported to the game. MoltenVK says 16, which
    /// stops some games at start; Metal's argument buffers hold more.
    var vulkanSamplers: Int?
    /// The game's Windows version runs better than its Mac one (old OpenGL ports, say), so
    /// "Automatic" keeps to Windows even though Steam has a 64-bit Mac version.
    var preferWindows: Bool?
    /// Save folders for games Steam Cloud doesn't know the folders of (SaveTransfer).
    var saves: [SaveRule]?
    /// Anti-cheat that stops the game's Windows version on a Mac ("BattlEye", …), from
    /// AreWeAntiCheatYet; an empty list (a Mac profile) means it runs after all.
    var antiCheat: [String]?
    /// Anti-cheat that only stops online play on a Mac (Easy Anti-Cheat, BattlEye: Proton runs them
    /// through their Linux module): it blocks games that have nothing else.
    var antiCheatOnline: [String]?
    /// Its game id on GeForce Now, NVIDIA's cloud gaming, where such a game can be streamed instead.
    var geforceNow: String?
    /// Why the game doesn't start on a Mac yet, in plain English (the German is in Strings.swift);
    /// Nightforge is working on it. Unlike anti-cheat it doesn't rule the game out for good, so
    /// loading and starting it stay possible, only not as the big button.
    var notYet: String?
    /// false: the game crashes when Rosetta advertises AVX/AVX2, so it starts without.
    var avx: Bool?
    /// Changes to the game's own settings files before it starts, for settings that crash it on a
    /// Mac: in `path` (relative to the game folder) `find` becomes `replace`.
    var fileEdits: [FileEdit]?
    /// Values for the game's own .ini files, set before every start (Unreal deletes a user
    /// Engine.ini it didn't write itself when it quits).
    var iniSettings: [IniSetting]?
    /// true: the game sees the screen's full Retina resolution instead of half of it. Wine sets that
    /// for a whole session, so Steam starts afresh when it changes from one game to the next.
    var retina: Bool?
    /// Where the game keeps the resolution it starts in, so it's fitted to the screen it plays on
    /// (GameResolution), as Unity's and Unreal's are without a profile.
    var resolution: SavedResolution?

    /// {"root": "WinAppDataLocal", "path": "2K Games/Mafia II/Saves/videoconfig.cfg",
    ///  "fields": {"width": 2, "height": 3, "fullscreen": 4}} – a line of values separated by spaces,
    /// counted from 0; or for an .ini file {"section": "Video", "keys": {"width": "ResX", …}}.
    struct SavedResolution: Decodable, Equatable {
        /// A Windows root as in `saves`; nil, the game folder.
        var root: String?
        let path: String
        var fields: Fields?
        var section: String?
        var keys: Keys?
        /// The full-screen value's settings that mean "on"; "1" when not given. Without a
        /// full-screen value the game counts as full screen.
        var fullscreenOn: [String]?

        struct Fields: Decodable, Equatable {
            let width: Int
            let height: Int
            var fullscreen: Int?
        }

        struct Keys: Decodable, Equatable {
            let width: String
            let height: String
            var fullscreen: String?
        }
    }

    struct FileEdit: Decodable, Equatable {
        let path: String
        let find: String
        let replace: String
        /// Where `path` starts: a Windows root as in `saves` ("WinAppDataLocal", …); nil, the game folder.
        var root: String?
        /// A starting value: applied a single time, so what the player picks in the game afterwards stays.
        var once: Bool?
    }

    /// {"root": "WinAppDataLocal", "path": "Voyage/Saved/Config/Windows/Engine.ini",
    ///  "section": "SystemSettings", "values": {"r.Nanite": "0"}}
    struct IniSetting: Decodable, Equatable {
        let root: String
        let path: String
        let section: String
        let values: [String: String]
    }

    struct RegistryEntry: Decodable, Equatable {
        let key: String
        let name: String?
        let type: String?
        let value: String?
    }

    private enum CodingKeys: String, CodingKey {
        case source, note
        case name, graphics, arguments, dllOverrides, registry, windowsVersion, winetricks, metalFX, frameLimit
        case vulkanSamplers, preferWindows, saves, antiCheat, antiCheatOnline, geforceNow, notYet, avx, fileEdits
        case iniSettings, retina, resolution
    }

    /// {"root": "WinAppDataRoaming", "path": "7DaysToDie/Saves", "pattern": "*", "recursive": true, "mac": "MacAppSupport"}
    private struct SaveFolder: Decodable {
        let root: String
        let path: String
        var pattern: String?
        var recursive: Bool?
        let mac: String
        var macPath: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        // An unknown layer from a newer list just means "no preference" here.
        graphics = (try? container.decodeIfPresent(String.self, forKey: .graphics)).flatMap { $0.flatMap(GraphicsLayer.init(rawValue:)) }
        arguments = try? container.decodeIfPresent([String].self, forKey: .arguments)
        dllOverrides = try? container.decodeIfPresent([String: String].self, forKey: .dllOverrides)
        registry = try? container.decodeIfPresent([RegistryEntry].self, forKey: .registry)
        windowsVersion = try? container.decodeIfPresent(String.self, forKey: .windowsVersion)
        winetricks = try? container.decodeIfPresent([String].self, forKey: .winetricks)
        metalFX = try? container.decodeIfPresent(Bool.self, forKey: .metalFX)
        frameLimit = try? container.decodeIfPresent(Int.self, forKey: .frameLimit)
        vulkanSamplers = try? container.decodeIfPresent(Int.self, forKey: .vulkanSamplers)
        preferWindows = try? container.decodeIfPresent(Bool.self, forKey: .preferWindows)
        saves = (try? container.decodeIfPresent([SaveFolder].self, forKey: .saves))?.map {
            SaveRule(root: $0.root, path: $0.path, pattern: $0.pattern ?? "*", recursive: $0.recursive ?? true,
                     macRoot: $0.mac, macAddPath: $0.macPath ?? "")
        }
        antiCheat = try? container.decodeIfPresent([String].self, forKey: .antiCheat)
        antiCheatOnline = try? container.decodeIfPresent([String].self, forKey: .antiCheatOnline)
        geforceNow = try? container.decodeIfPresent(String.self, forKey: .geforceNow)
        // An empty reason is none.
        notYet = (try? container.decodeIfPresent(String.self, forKey: .notYet)).flatMap { $0.isEmpty ? nil : $0 }
        avx = try? container.decodeIfPresent(Bool.self, forKey: .avx)
        fileEdits = try? container.decodeIfPresent([FileEdit].self, forKey: .fileEdits)
        iniSettings = try? container.decodeIfPresent([IniSetting].self, forKey: .iniSettings)
        retina = try? container.decodeIfPresent(Bool.self, forKey: .retina)
        resolution = try? container.decodeIfPresent(SavedResolution.self, forKey: .resolution)
    }
}

/// A game that doesn't start on a Mac because its anti-cheat needs Windows itself: Wine can't
/// run it, and getting around it would get the player banned.
struct AntiCheatBlock: Hashable {
    let antiCheat: [String]
    /// Its GeForce Now game id, when it can be streamed there instead.
    let geforceNow: String?
    /// The anti-cheat only stops online play, so this blocks only games that are online only.
    var onlineOnly = false
    /// Not for good: why it doesn't start on a Mac yet (`GameProfile.notYet`; `antiCheat` is empty then).
    /// Downloading and starting stay possible, GeForce Now is what the big button offers.
    var notYet: String?

    /// GeForce Now's deep link to the game's page, where it can be played
    /// (NVIDIA GeForce NOW SDK, doc/GfnSdk-Deep-Linking.md).
    var geforceNowURL: URL? {
        guard let geforceNow else { return nil }
        var link = URLComponents(string: "https://play.geforcenow.com/games")
        link?.queryItems = [
            URLQueryItem(name: "game-id", value: geforceNow),
            URLQueryItem(name: "utm_source", value: "nightforge"),
            URLQueryItem(name: "utm_campaign", value: "library"),
        ]
        return link?.url
    }
}

private struct ProfileDocument: Decodable {
    let formatVersion: Int
    let games: [String: Lenient]

    /// One odd entry shouldn't cost every other game its profile.
    struct Lenient: Decodable {
        let profile: GameProfile?
        init(from decoder: Decoder) throws { profile = try? GameProfile(from: decoder) }
    }
}

/// Keeps the profile list current: the online copy (`NightforgeProfilesURL`) once per app run,
/// else the last one fetched, else the copy bundled with the app. The bundled copy wins over the
/// other two when it was built later ("generated"): a local build or an update can bring profiles
/// the online list doesn't have yet.
actor ProfileStore {
    static let shared = ProfileStore()
    static let supportedFormat = 1

    private let remoteURL = (Bundle.main.object(forInfoDictionaryKey: "NightforgeProfilesURL") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    private var cachedURL: URL { Engine.supportDir.appendingPathComponent("profiles.json") }
    private let bundledURL: URL?
    private var profiles: [Int: GameProfile]?
    /// Epic games' entries ("epic.<namespace>" in the list), by catalog namespace.
    private var epicProfiles: [String: GameProfile] = [:]
    /// GOG games' entries ("gog.<product ID>" in the list), by product ID.
    private var gogProfiles: [String: GameProfile] = [:]
    private var refreshed = false

    /// `bundledURL`: the copy that comes with the app; a test hands in its own.
    init(bundledURL: URL? = Bundle.main.url(forResource: "profiles", withExtension: "json")) {
        self.bundledURL = bundledURL
    }

    func profile(for appID: Int) async -> GameProfile? {
        if !refreshed { await refresh() }
        loadLocalIfNeeded()
        return profiles?[appID]
    }

    /// The profile a game starts with, from any store: Steam's by app ID, GOG's by product ID (the
    /// Steam version's profile, for the GOG versions profiles/mac.json names). Epic's entries only
    /// say what blocks a game (`epicAntiCheatBlocks`), so an Epic game starts without.
    func profile(for game: GameID) async -> GameProfile? {
        if let appID = game.steamAppID { return await profile(for: appID) }
        guard game.provider == .gog else { return nil }
        if !refreshed { await refresh() }
        loadLocalIfNeeded()
        return gogProfiles[game.id]
    }

    /// Every game's profile from the list at hand, without waiting for the online copy (like
    /// `preferWindows`): for working out how well games run.
    func knownProfiles() -> [Int: GameProfile] {
        loadLocalIfNeeded()
        return profiles ?? [:]
    }

    /// Games whose profile keeps them on the Windows version, from the list at hand: the library
    /// scan doesn't wait for the online copy, the next scan picks it up.
    func preferWindows() -> Set<Int> {
        loadLocalIfNeeded()
        return Set((profiles ?? [:]).filter { $0.value.preferWindows == true }.keys)
    }

    /// Games whose anti-cheat stops them on a Mac, from the list at hand (like `preferWindows`).
    func antiCheatBlocks() -> [Int: AntiCheatBlock] {
        loadLocalIfNeeded()
        return (profiles ?? [:]).compactMapValues(Self.block(of:))
    }

    /// Epic games whose anti-cheat stops them on a Mac, by catalog namespace (like `antiCheatBlocks`).
    func epicAntiCheatBlocks() -> [String: AntiCheatBlock] {
        loadLocalIfNeeded()
        return epicProfiles.compactMapValues(Self.block(of:))
    }

    /// What stops a game on a Mac, as its profile says. "notYet" is the profile's own word about the
    /// game (a Mac profile, tested), so it comes before what AreWeAntiCheatYet lists.
    static func block(of profile: GameProfile) -> AntiCheatBlock? {
        if let reason = profile.notYet {
            return AntiCheatBlock(antiCheat: [], geforceNow: profile.geforceNow, notYet: reason)
        }
        if let antiCheat = profile.antiCheat, !antiCheat.isEmpty {
            return AntiCheatBlock(antiCheat: antiCheat, geforceNow: profile.geforceNow)
        }
        if let antiCheat = profile.antiCheatOnline, !antiCheat.isEmpty {
            return AntiCheatBlock(antiCheat: antiCheat, geforceNow: profile.geforceNow, onlineOnly: true)
        }
        return nil
    }

    private func loadLocalIfNeeded() {
        guard profiles == nil else { return }
        let cached = try? Data(contentsOf: cachedURL)
        let bundled = bundledURL.flatMap { try? Data(contentsOf: $0) }
        // The newer one first; the other still serves when it can't be read.
        let lists = cached.map { Self.isOlder($0, than: bundled) } == true ? [bundled, cached] : [cached, bundled]
        for data in lists.compactMap({ $0 }) where use(data) { return }
    }

    /// Makes `data` the list at hand; false when it isn't one this Nightforge reads.
    private func use(_ data: Data) -> Bool {
        guard let decoded = decode(data) else { return false }
        profiles = decoded
        epicProfiles = Self.decodeEpic(data)
        gogProfiles = Self.decodeGOG(data)
        return true
    }

    /// Whether `list` was built before `other` (their "generated"); a list without that date counts
    /// as older than one with it.
    static func isOlder(_ list: Data, than other: Data?) -> Bool {
        guard let theirs = other.flatMap(generated) else { return false }
        guard let ours = generated(list) else { return true }
        return ours < theirs
    }

    private static func generated(_ data: Data) -> Date? {
        struct Stamp: Decodable { let generated: String? }
        return (try? JSONDecoder().decode(Stamp.self, from: data))?.generated.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Fetches the online list; keeps what's there when offline, when the list is too new for this
    /// Nightforge, or when it's older than the bundled one.
    func refresh() async {
        refreshed = true
        guard let remoteURL else { return }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !Self.isOlder(data, than: bundledURL.flatMap { try? Data(contentsOf: $0) }),
              use(data)
        else { return }
        try? FileManager.default.createDirectory(at: Engine.supportDir, withIntermediateDirectories: true)
        try? data.write(to: cachedURL, options: .atomic)
    }

    /// The entries keyed "epic.<namespace>" (older Nightforge versions skip them: not a number).
    static func decodeEpic(_ data: Data) -> [String: GameProfile] { decodeStore(data, prefix: "epic.") }

    /// The entries keyed "gog.<product ID>", by product ID.
    static func decodeGOG(_ data: Data) -> [String: GameProfile] { decodeStore(data, prefix: "gog.") }

    private static func decodeStore(_ data: Data, prefix: String) -> [String: GameProfile] {
        guard let document = try? JSONDecoder().decode(ProfileDocument.self, from: data),
              document.formatVersion <= supportedFormat
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: document.games.compactMap { key, value in
            guard key.hasPrefix(prefix), let profile = value.profile else { return nil }
            return (String(key.dropFirst(prefix.count)), profile)
        })
    }

    private func decode(_ data: Data) -> [Int: GameProfile]? {
        guard let document = try? JSONDecoder().decode(ProfileDocument.self, from: data),
              document.formatVersion <= Self.supportedFormat
        else { return nil }
        return Dictionary(uniqueKeysWithValues: document.games.compactMap { key, value in
            guard let appID = Int(key), let profile = value.profile else { return nil }
            return (appID, profile)
        })
    }
}
