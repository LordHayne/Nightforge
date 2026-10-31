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

    /// Its info: the same game's on Steam where there is one, filled in from its own store's (GOG's
    /// German description and screenshots); else its own store's.
    nonisolated static func info(for game: Game, in known: Known) -> GameInfo? {
        let key = source(of: game, in: known)
        guard key != game.gameID.key else { return known.infos[key] }
        let own = known.infos[game.gameID.key]
        guard let steam = known.infos[key] else { return own }
        return steam.filled(from: own)
    }

    /// A GOG game whose Steam twin's info lacks a description in the Mac's language or screenshots.
    static func wantsOwn(_ game: Game, in known: Known, language: String) -> Bool {
        guard game.provider == .gog, let appID = twin(of: game, in: known), let steam = known.infos[GameID.steam(appID).key] else { return false }
        return steam.summaryLanguage != GameInfo.code(language) || steam.screenshots.isEmpty
    }

    static func needsAsking(_ info: GameInfo?, language: String, now: Date = Date()) -> Bool {
        guard let info else { return true }
        return info.language != language || info.format != GameInfo.format || now.timeIntervalSince(info.asked) > askAgainAfter
    }

    static func needsAsking(_ twin: Twin?, now: Date = Date()) -> Bool {
        guard let twin else { return true }
        return twin.appID == nil && now.timeIntervalSince(twin.asked) > askAgainAfter
    }

    // MARK: - Filling in

    /// How many GamesDB lookups run at once, and after how many twins found their Steam info is asked
    /// and shown: the first ones show within seconds, not after the whole library.
    static let parallelLookups = 4
    static let twinsPerRound = 20

    /// The order games are filled in: GOG's (few, their twins mostly named already), then what's on
    /// the Mac, then what was played last – what the player looks at first.
    static func order(_ games: [Game]) -> [Game] {
        func rank(_ game: Game) -> Int { game.provider == .gog ? 0 : game.isInstalled ? 1 : 2 }
        return games.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra < rb }
            let (la, lb) = (a.element.lastPlayed ?? .distantPast, b.element.lastPlayed ?? .distantPast)
            return la != lb ? la > lb : a.offset < b.offset
        }.map(\.element)
    }

    /// Asks for what isn't known yet about these entries (or is a month old) and hands each step's
    /// result to `progress` as it comes: Steam's info for every game whose Steam app ID is known
    /// (its own, or the twin GOG's library names), then the twins of the other Epic and GOG games,
    /// a few at a time, each round with its Steam info, then the own store's info for those without one.
    /// Entries handed in while a fill runs are filled in right after it.
    func fill(_ games: [Game], progress: @escaping @MainActor @Sendable (Known) -> Void) async {
        guard !filling else {
            waiting = games
            return
        }
        filling = true
        var next: [Game]? = games
        while let batch = next {
            waiting = nil
            await fillOnce(batch, progress: progress)
            next = waiting
        }
        filling = false
    }

    private var waiting: [Game]?

    private func fillOnce(_ games: [Game], progress: @escaping @MainActor @Sendable (Known) -> Void) async {
        guard Date() >= pausedUntil else { return }
        let language = Self.language
        let entries = Self.order(games.filter(\.inLibrary))
        var shown = known
        func publish() async {
            guard known != shown else { return }
            save()
            shown = known
            await progress(known)
        }

        // 1. The twins GOG's library names, and Steam's info for everything that has an app ID now.
        for game in entries where game.provider != .steam {
            if let appID = game.steamTwin, known.twins[game.gameID.key]?.appID != appID {
                known.twins[game.gameID.key] = Twin(appID: appID, asked: Date())
            }
        }
        guard await askSteam(for: entries, language: language, publish: publish) else { return }

        // 2. The other twins, a few lookups at a time; each round's Steam info right after it.
        let unknown = entries.filter { $0.provider != .steam && $0.steamTwin == nil && Self.needsAsking(known.twins[$0.gameID.key]) }
        var offline = false
        for round in stride(from: 0, to: unknown.count, by: Self.twinsPerRound) where !offline {
            let games = unknown[round..<min(round + Self.twinsPerRound, unknown.count)]
            for start in stride(from: games.startIndex, to: games.endIndex, by: Self.parallelLookups) where !offline {
                let group = Array(games[start..<min(start + Self.parallelLookups, games.endIndex)])
                let found = await withTaskGroup(of: (String, Int??).self) { tasks in
                    for game in group { tasks.addTask { (game.gameID.key, await self.lookUpTwin(game)) } }
                    return await tasks.reduce(into: [(String, Int??)]()) { $0.append($1) }
                }
                for (key, answer) in found {
                    guard let appID = answer else { offline = true; continue }  // GamesDB didn't answer: later
                    known.twins[key] = Twin(appID: appID, asked: Date())
                }
            }
            guard await askSteam(for: Array(games), language: language, publish: publish) else { return }
        }

        // 3. Without a Steam twin: GOG's own page; Epic's catalog data that legendary keeps. GOG's page
        //    also for a game whose Steam info lacks what GOG has: a description in the Mac's language,
        //    screenshots (Steam shows some games' only to adults).
        for game in entries where game.provider != .steam && (Self.twin(of: game, in: known) == nil || Self.wantsOwn(game, in: known, language: language)) {
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
        await publish()
    }

    /// Steam's info for these games and their twins, 50 apps per request, each shown as it comes.
    /// False when Steam couldn't be asked (offline, turned down).
    private func askSteam(for games: [Game], language: String, publish: () async -> Void) async -> Bool {
        var wanted: [Int] = []
        var seen = Set<Int>()
        for game in games {
            guard let appID = game.gameID.steamAppID ?? Self.twin(of: game, in: known), seen.insert(appID).inserted,
                  Self.needsAsking(known.infos[GameID.steam(appID).key], language: language) else { continue }
            wanted.append(appID)
        }
        for start in stride(from: 0, to: wanted.count, by: Self.batchSize) {
            let batch = Array(wanted[start..<min(start + Self.batchSize, wanted.count)])
            guard let found = await steamInfos(batch, language: language) else { return false }
            let now = Date()
            for appID in batch {
                // One Steam doesn't know (delisted, region-locked) is noted too, so it isn't asked every start.
                known.infos[GameID.steam(appID).key] = found[appID]
                    ?? GameInfo(language: language, source: GameID.steam(appID).key, asked: now)
            }
            await publish()
        }
        return true
    }

    /// The same game on Steam: GamesDB's, else a store hit with exactly the same title. .some(nil):
    /// none; nil: GamesDB couldn't be asked.
    private func lookUpTwin(_ game: Game) async -> Int?? {
        guard let answer = await twinFromGamesDB(game) else { return nil }
        if let appID = answer { return appID }
        return .some(await twinByTitle(game.name))
    }

    /// One game's Steam info now, when its page opens before the fill came to it (a store hit, a game
    /// just added) or it's a month old. What's known afterwards, or nil when nothing was asked.
    func ask(_ game: Game) async -> Known? {
        let language = Self.language
        guard Date() >= pausedUntil, let appID = game.gameID.steamAppID ?? Self.twin(of: game, in: known),
              Self.needsAsking(known.infos[GameID.steam(appID).key], language: language),
              let found = await steamInfos([appID], language: language) else { return nil }
        known.infos[GameID.steam(appID).key] = found[appID] ?? GameInfo(language: language, source: GameID.steam(appID).key, asked: Date())
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
