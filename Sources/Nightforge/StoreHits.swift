import Foundation

/// One game a store sells, whichever store: what the library's search shows of it.
struct StoreHit: Hashable {
    let gameID: GameID
    let name: String
    /// Its page, in a store other than Steam.
    var page: URL?
    /// As the store shows it.
    var price: String?
    /// Steam adds its licence when asked to install it (`Game.storeFree`).
    var free = false
    var macNative: Bool?
    var metascore: Int?
    var controller: ControllerSupport?
    /// Where its store keeps its art; Steam's comes from `GameInfoStore`.
    var art: StoreArt?

    init(gameID: GameID, name: String, page: URL? = nil) {
        self.gameID = gameID
        self.name = name
        self.page = page
    }

    init(_ hit: StoreSearch.Hit) {
        self.init(gameID: .steam(hit.appID), name: hit.name)
        price = hit.price
        free = hit.free
        macNative = hit.macNative
        metascore = hit.metascore
        controller = hit.controller
    }
}

/// The library's search across the stores: each store's hits on their own, then one list.
enum StoreHits {
    /// A search to run: its store, and what it asks.
    typealias Query = (provider: Provider, run: @Sendable () async -> [StoreHit])

    /// Asks every store at once; `found` gets each store's hits as they come, so one that's slow or
    /// fails holds up nothing and takes nothing away from the others. Cancelling stops all of them.
    static func gather(_ searches: [Query], found: @MainActor (Provider, [StoreHit]) -> Void) async {
        await withTaskGroup(of: (Provider, [StoreHit]).self) { group in
            for search in searches {
                group.addTask { (search.provider, await search.run()) }
            }
            for await (provider, hits) in group { await found(provider, hits) }
        }
    }

    /// A hit as the library shows it. `blocks`: anti-cheat by Steam app ID, which only Steam's hits have.
    static func game(_ hit: StoreHit, info: GameInfo?, blocks: [Int: AntiCheatBlock]) -> Game {
        var game = Game(
            gameID: hit.gameID, name: hit.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
            steamExeWindowsPath: Engine.steamExeWindowsPath,
            installDir: Engine.steamRoot.appendingPathComponent("steamapps/common", isDirectory: true),
            sizeOnDisk: 0
        )
        game.install = .inStore
        game.macNative = hit.macNative ?? false
        game.controller = hit.controller ?? info?.controller ?? .none
        game.controllerKnown = hit.gameID.provider == .steam
        game.playModes = info?.modes ?? []
        game.art = info.map(StoreArt.init) ?? hit.art
        game.storePrice = hit.price
        game.storeFree = hit.free && hit.gameID.provider == .steam
        game.storePage = hit.page
        game.metascore = hit.metascore
        // Store hits don't say whether there's single player, so only blocks that always hold.
        if hit.macNative != true, let appID = hit.gameID.steamAppID, let block = blocks[appID], !block.onlineOnly {
            game.antiCheatBlock = block
        }
        return game
    }

    /// All stores' hits as one list: by how well they fit `term`, then each store's own order, so
    /// the stores take turns. A game two stores sell is one card (`DuplicateGames.card`), with what
    /// the second store asks on its page; a title one store has twice stays two.
    static func cards(_ found: [Provider: [Game]], term: String) -> [Game] {
        let ranked = Provider.allCases.enumerated().flatMap { store, provider in
            (found[provider] ?? []).enumerated().map { position, game in
                (game: game, order: [StoreSearch.fit(game.name, term), position, store])
            }
        }.sorted { $0.order.lexicographicallyPrecedes($1.order) }.map(\.game)

        var groups: [[Game]] = []
        var byTitle: [String: Int] = [:]
        for game in ranked {
            let keys = game.titleKeys
            if let group = keys.lazy.compactMap({ byTitle[$0] }).first(where: { group in !groups[group].contains { $0.provider == game.provider } }) {
                groups[group].append(game)
                for key in keys where byTitle[key] == nil { byTitle[key] = group }
            } else {
                groups.append([game])
                for key in keys where byTitle[key] == nil { byTitle[key] = groups.count - 1 }
            }
        }
        return groups.map { group in
            guard group.count > 1 else { return group[0] }
            var card = DuplicateGames.card(group, chosen: nil)
            card.metascore = group.lazy.compactMap(\.metascore).first
            return card
        }
    }

    /// Epic's store can't be asked from outside (`store.epicgames.com/graphql` turns honest clients
    /// away at the door), and Nightforge doesn't pose as a browser or launcher: the player's own
    /// browser opens Epic's search instead.
    static func epicSearch(_ term: String) -> URL? {
        var components = URLComponents(string: "https://store.epicgames.com/browse")!
        components.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "sortBy", value: "relevancy"),
            URLQueryItem(name: "sortDir", value: "DESC"),
            URLQueryItem(name: "count", value: "40"),
        ]
        return withPlusEscaped(components).url
    }

    /// URLComponents leaves "+" as it is, which a server reads as a space ("Rise+" would lose it).
    static func withPlusEscaped(_ components: URLComponents) -> URLComponents {
        var escaped = components
        escaped.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return escaped
    }
}

/// What the player has, to tell a store's hit from their own game: by the store's ID, by the same
/// game on Steam, by title – GOG's packs (`GOGSearch`) and another store's copy have other IDs.
/// Kept while the library doesn't change: titles take a moment over thousands of games.
struct OwnedGames {
    private var ids: Set<GameID> = []
    private var onSteam: [Int: GameID] = [:]
    private var titles: [String: GameID] = [:]

    init(_ games: [Game]) {
        for game in games {
            ids.insert(game.gameID)
            if let appID = game.steamAppID { onSteam[appID] = game.gameID }
            guard game.inLibrary else { continue }
            for key in game.titleKeys { titles[key] = game.gameID }
        }
    }

    /// The player's entry of the game `hit` shows, in any of `hit`'s stores.
    func game(of hit: Game) -> GameID? {
        hit.entries.lazy.compactMap { entry in
            if ids.contains(entry.gameID) { return entry.gameID }
            if let appID = entry.gameID.steamAppID, let own = onSteam[appID] { return own }
            return entry.titleKeys.lazy.compactMap { titles[$0] }.first
        }.first
    }
}

extension Game {
    /// Where the game is sold; Steam's demos by the game they're the demo of.
    var storePageURL: URL? {
        provider == .steam ? URL(string: "https://store.steampowered.com/app/\(demoOf ?? appID)") : storePage
    }

    /// Its title for comparing across stores, and what its page's address calls it: GOG renames
    /// ("The Witcher 3: Wild Hunt — Remastered" under `the_witcher_3_wild_hunt_game_of_the_year_edition`).
    fileprivate var titleKeys: [String] {
        [name, storePage?.lastPathComponent].compactMap { $0.map(DuplicateGames.titleKey) }.filter { !$0.isEmpty }
    }
}

extension Provider {
    /// "In the GOG Store": the heading over its hits, and what a screen reader says of one.
    var inStore: String { L10n.t("In the %@ Store", label) }
    /// The button that leads to a hit's page.
    var viewInStore: String { L10n.t("View in %@ Store", label) }
}
