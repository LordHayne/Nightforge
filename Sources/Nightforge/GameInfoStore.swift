import Foundation

/// What each game is (GameInfo), kept on the Mac so the library's filters and a game's page work
/// offline and nothing is asked on every start. Steam's games come from Steam's store-browse API, 50
/// at a time. Epic's and GOG's stores say little without a sign-in, so their games take the same
/// game on Steam: GOG's GamesDB names it by ID (Epic's AppName, GOG's product ID), else a Steam store
/// hit with exactly the same title. GOG's games without one take GOG's own page; Epic's, what
/// legendary already has.
actor GameInfoStore {
    static let shared = GameInfoStore()

    struct Known: Codable, Equatable {
        /// By the key of where it came from ("steam.728880", "gog.1207664643").
        var infos: [String: GameInfo] = [:]
        /// Epic's and GOG's games (by GameID key) → the same game on Steam.
        var twins: [String: Twin] = [:]
    }

    struct Twin: Codable, Equatable {
        /// nil: none found.
        var appID: Int?
        var asked: Date
    }

    /// Asked again after a month: a description changes rarely, a game Steam didn't have may come.
    static let askAgainAfter: TimeInterval = 30 * 24 * 3600
    /// Steam's store-browse API takes this many apps per request.
    static let batchSize = 50

    static var file: URL {
        Engine.supportDir.appendingPathComponent("GameInfo/known.json")
    }

    private var known: Known
    private var filling = false
    /// Steam or GamesDB turned requests down (429/403): nothing is asked until then.
    private var pausedUntil = Date.distantPast

    init() {
        known = Self.load()
    }

    nonisolated static func load() -> Known {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Known.self, from: $0) } ?? Known()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(known) { try? data.write(to: Self.file, options: .atomic) }
    }

    /// The language texts are asked in: the app's.
    nonisolated static var language: String { AppLanguage.current.resolved == .german ? "german" : "english" }

    // MARK: - Looking up

    /// The same game on Steam for an Epic or GOG entry.
    nonisolated static func twin(of game: Game, in known: Known) -> Int? {
        game.provider == .steam ? nil : game.steamTwin ?? known.twins[game.gameID.key]?.appID
    }

    /// Where a game's info comes from: Steam (its own or the same game there), else its own store.
    nonisolated static func source(of game: Game, in known: Known) -> String {
        if let appID = game.gameID.steamAppID ?? twin(of: game, in: known) { return GameID.steam(appID).key }
        return game.gameID.key
    }

    nonisolated static func info(for game: Game, in known: Known) -> GameInfo? {
        known.infos[source(of: game, in: known)]
    }

    static func needsAsking(_ info: GameInfo?, language: String, now: Date = Date()) -> Bool {
        guard let info else { return true }
        return info.language != language || now.timeIntervalSince(info.asked) > askAgainAfter
    }

    static func needsAsking(_ twin: Twin?, now: Date = Date()) -> Bool {
        guard let twin else { return true }
        return twin.appID == nil && now.timeIntervalSince(twin.asked) > askAgainAfter
    }

    // MARK: - Filling in

    /// Asks for what isn't known yet about these entries (or is a month old): first the Steam twins of
    /// Epic's and GOG's games, then Steam's info for all of them, then GOG's own for those without one.
    /// What's known afterwards, or nil when nothing changed (offline, all known, another fill running).
    func fill(_ games: [Game]) async -> Known? {
        guard !filling, Date() >= pausedUntil else { return nil }
        filling = true
        defer { filling = false }
        let before = known
        let language = Self.language
        let entries = games.filter { $0.inLibrary }

        // 1. The same game on Steam.
        for game in entries where game.provider != .steam {
            let key = game.gameID.key
            if let appID = game.steamTwin {
                if known.twins[key]?.appID != appID { known.twins[key] = Twin(appID: appID, asked: Date()) }
                continue
            }
            guard Self.needsAsking(known.twins[key]) else { continue }
            guard let answer = await twinFromGamesDB(game) else { break }  // offline or turned down: later
            var appID = answer
            if appID == nil { appID = await twinByTitle(game.name) }
            known.twins[key] = Twin(appID: appID, asked: Date())
        }

        // 2. Steam's info, 50 apps per request.
        var wanted: [Int] = []
        var seen = Set<Int>()
        for game in entries {
            guard let appID = game.gameID.steamAppID ?? Self.twin(of: game, in: known), seen.insert(appID).inserted,
                  Self.needsAsking(known.infos[GameID.steam(appID).key], language: language) else { continue }
            wanted.append(appID)
        }
        for start in stride(from: 0, to: wanted.count, by: Self.batchSize) {
            let batch = Array(wanted[start..<min(start + Self.batchSize, wanted.count)])
            guard let found = await steamInfos(batch, language: language) else { break }
            let now = Date()
            for appID in batch {
                // One Steam doesn't know (delisted, region-locked) is noted too, so it isn't asked every start.
                known.infos[GameID.steam(appID).key] = found[appID]
                    ?? GameInfo(language: language, source: GameID.steam(appID).key, asked: now)
            }
            save()
        }

        // 3. Without a Steam twin: GOG's own page; Epic's catalog data that legendary keeps.
        for game in entries where game.provider != .steam && Self.twin(of: game, in: known) == nil {
            let key = game.gameID.key
            guard Self.needsAsking(known.infos[key], language: language) else { continue }
            switch game.provider {
            case .gog:
                guard let info = await gogInfo(game.gameID.id, language: language) else { continue }
                known.infos[key] = info
            case .epic:
                let file = Legendary.configDir.appendingPathComponent("metadata/\(game.gameID.id).json")
                known.infos[key] = (try? Data(contentsOf: file)).flatMap { GameInfo.epic(fromMetadata: $0, appName: game.gameID.id, language: language) }
                    ?? GameInfo(language: language, source: key, asked: Date())
            case .steam:
                break
            }
        }

        guard known != before else { return nil }
        save()
        return known
    }

    /// Steam's info for store hits (games not in the library): their covers and controller support,
    /// not kept on the Mac.
    func storeInfos(_ appIDs: [Int]) async -> [Int: GameInfo] {
        guard !appIDs.isEmpty, Date() >= pausedUntil else { return [:] }
        return await steamInfos(Array(appIDs.prefix(Self.batchSize)), language: Self.language) ?? [:]
    }

    // MARK: - Requests

    private func steamInfos(_ appIDs: [Int], language: String) async -> [Int: GameInfo]? {
        let request: [String: Any] = [
            "ids": appIDs.map { ["appid": $0] },
            "context": ["language": language, "country_code": Locale.current.region?.identifier ?? "US"],
            "data_request": ["include_assets": true, "include_basic_info": true, "include_tag_count": 20,
                             "include_release": true, "include_ratings": true, "include_screenshots": true,
                             "include_supported_languages": true],
        ]
        guard let input = try? JSONSerialization.data(withJSONObject: request),
              var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "input_json", value: String(decoding: input, as: UTF8.self))]
        guard let data = await get(components.url) else { return nil }
        return GameInfo.steam(fromItems: data, language: language)
    }

    /// The Steam app ID GamesDB knows for an Epic or GOG game: .some(nil) when it knows none, nil
    /// when it couldn't be asked.
    private func twinFromGamesDB(_ game: Game) async -> Int?? {
        let platform = game.provider == .epic ? "epic" : "gog"
        guard let id = game.gameID.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://gamesdb.gog.com/platforms/\(platform)/external_releases/\(id)") else { return .some(nil) }
        try? await Task.sleep(for: .milliseconds(250))
        switch await fetch(url) {
        case .found(let data): return .some(GameInfo.steamTwin(fromGamesDB: data))
        case .missing: return .some(nil)
        case .failed: return nil
        }
    }

    /// A Steam store hit with exactly the same title (the way DuplicateGames compares them).
    private func twinByTitle(_ name: String) async -> Int? {
        let key = DuplicateGames.titleKey(name)
        guard !key.isEmpty else { return nil }
        return await StoreSearch.shared.search(name).first { DuplicateGames.titleKey($0.name) == key }?.appID
    }

    private func gogInfo(_ id: String, language: String) async -> GameInfo? {
        let locale = language == "german" ? "de-DE" : "en-US"
        guard GOGRelease.isProductID(id), let url = URL(string: "https://api.gog.com/v2/games/\(id)?locale=\(locale)"),
              let data = await get(url) else { return nil }
        return GameInfo.gog(fromJSON: data, id: id, language: language)
    }

    private enum Answer {
        case found(Data)
        case missing
        case failed
    }

    private func fetch(_ url: URL) async -> Answer {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        switch status {
        case 200: return .found(data)
        case 404: return .missing
        case 403, 429:
            pausedUntil = Date().addingTimeInterval(600)
            return .failed
        default: return .failed
        }
    }

    private func get(_ url: URL?) async -> Data? {
        guard let url, case .found(let data) = await fetch(url) else { return nil }
        return data
    }
}
