import Foundation

/// A game the player owns in several stores (ARC Raiders on Steam and on Epic Games, The Witcher 3
/// on Steam and on GOG) shows as one card. Each store keeps its own entry – its options, what a
/// start taught Nightforge, its saves and files differ – and the card starts, downloads and
/// uninstalls through one of them (`Game.others` holds the rest).
///
/// Which entries are the same game: their titles, the way both stores write them (case, ™, accents,
/// punctuation, a generic "Game of the Year Edition"). Neither store's data on the Mac names the
/// game in the other one, so there is no ID to go by. One card too many is better than two games
/// on one card: everything else that tells titles apart – a number, "Remastered", "Demo", "Test
/// Server", a subtitle – keeps them apart, and a title one store has twice merges with nothing.
enum DuplicateGames {
    /// Edition names that leave the game the same, as words at the end of a title. Not
    /// "Definitive", "Enhanced", "Special", "Anniversary", "Remastered" or "Director's Cut": those
    /// are often a reworked game of their own (Age of Empires II: Definitive Edition, Skyrim
    /// Special Edition).
    static let editions: [[String]] = [
        "digital deluxe edition", "game of the year edition", "game of the year", "goty edition", "goty",
        "complete edition", "deluxe edition", "standard edition", "gold edition", "ultimate edition", "premium edition",
    ].map { $0.split(separator: " ").map(String.init) }.sorted { $0.count > $1.count }

    /// "Sid Meier’s Civilization® VI" → "sid meiers civilization vi", "Batman: Arkham Asylum GOTY
    /// Edition" → "batman arkham asylum". Empty when nothing's left.
    static func titleKey(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        // Apostrophes and dots join ("Baldur's" → "baldurs", "S.T.A.L.K.E.R." → "stalker"); any
        // other mark splits.
        let joined = folded.filter { !"'’‘`´.".contains($0) }
        var words = joined.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if let edition = editions.first(where: { words.count > $0.count && Array(words.suffix($0.count)) == $0 }) {
            words.removeLast(edition.count)
        }
        return words.joined(separator: " ")
    }

    /// One card per game: entries of different stores with the same title become one card, the
    /// store it starts through first (`order`); everything else stays as it is. Store hits and demos
    /// aren't the player's games and merge with nothing. `chosen`: the store picked on the card's
    /// page, by the card's entries.
    static func merge(_ entries: [Game], chosen: ([GameID]) -> Provider? = StoreChoice.load) -> [Game] {
        var groups: [String: [Int]] = [:]
        for (index, game) in entries.enumerated() where game.inLibrary {
            let key = titleKey(game.name)
            if !key.isEmpty { groups[key, default: []].append(index) }
        }
        var cards: [Int: Game] = [:]
        var merged = Set<Int>()
        for indices in groups.values where indices.count > 1 {
            let providers = indices.map { entries[$0].provider }
            // A title one store has twice (two Steam bottles, two apps of that name): which is which isn't clear.
            guard Set(providers).count == providers.count else { continue }
            let group = indices.map { entries[$0] }
            cards[indices[0]] = card(group, chosen: chosen(group.map(\.gameID)))
            merged.formUnion(indices.dropFirst())
        }
        return entries.indices.compactMap { index in
            merged.contains(index) ? nil : cards[index] ?? entries[index]
        }
    }

    /// The card for one game's entries: the first store it starts through, the others behind it.
    /// Last played and play time are the game's across its stores; what a store doesn't know about
    /// the game (Epic: controller support, VR) comes from one that does.
    static func card(_ entries: [Game], chosen: Provider?) -> Game {
        let ordered = order(entries, chosen: chosen)
        var card = ordered[0]
        card.others = Array(ordered.dropFirst())
        card.lastPlayed = ordered.compactMap(\.lastPlayed).max()
        let minutes = ordered.compactMap(\.playtimeMinutes)
        card.playtimeMinutes = minutes.isEmpty ? nil : minutes.reduce(0, +)
        if let known = ordered.compactMap(\.knownController).min(by: { rank($0) < rank($1) }) {
            card.controller = known
            card.controllerKnown = true
        }
        card.playModes = ordered.reduce(into: Set<PlayMode>()) { $0.formUnion($1.playModes) }
        if card.provider != .steam { card.steamTwin = card.steamTwin ?? ordered.lazy.compactMap(\.steamAppID).first }
        card.isVROnly = ordered.contains(where: \.isVROnly)
        return card
    }

    /// The store a game starts through: the one picked on its page; else the one it's installed
    /// in (or downloading in) – of several, the one played last; else a store that has its Mac
    /// version (Mac first, Windows only as the fallback); else Steam, then the other stores in
    /// their order.
    static func order(_ entries: [Game], chosen: Provider?) -> [Game] {
        func onMac(_ game: Game) -> Int {
            switch game.install {
            case .installed: return 0
            case .downloading: return 1
            case .notInstalled, .inStore: return 2
            }
        }
        func storeRank(_ game: Game) -> Int { Provider.allCases.firstIndex(of: game.provider) ?? Provider.allCases.count }
        return entries.sorted { a, b in
            if let chosen, (a.provider == chosen) != (b.provider == chosen) { return a.provider == chosen }
            if onMac(a) != onMac(b) { return onMac(a) < onMac(b) }
            if onMac(a) < 2, a.lastPlayed != b.lastPlayed { return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast) }
            if onMac(a) == 2, (a.platform == .mac) != (b.platform == .mac) { return a.platform == .mac }
            return storeRank(a) < storeRank(b)
        }
    }

    /// The player's games among `cards`, each once, without the hidden ones – of one store: a game
    /// from several stores counts in each. `list`: only those on it (Play Later).
    static func count(_ cards: [Game], hidden: Set<GameID>, in provider: Provider? = nil, on list: Set<GameID>? = nil) -> Int {
        cards.lazy.filter { card in
            card.counted && !card.isMarked(in: hidden) && provider.map(card.providers.contains) ?? true
                && list.map(card.isMarked) ?? true
        }.count
    }

    private static func rank(_ support: ControllerSupport) -> Int {
        switch support {
        case .full: return 0
        case .partial: return 1
        case .none: return 2
        }
    }
}

extension Game {
    /// Marked (hidden, pinned, to play later) in one of its stores: a game from several stores
    /// shares its marks.
    func isMarked(in marks: Set<GameID>) -> Bool { gameIDs.contains(where: marks.contains) }
}

/// The store a game the player owns in several stores starts through, as picked on its page. Kept
/// under each of its entries (`GameID.key`), so it holds whichever store's entry is looked up – and
/// when a store's library briefly lacks the game.
enum StoreChoice {
    static func key(_ game: GameID) -> String { "startsThrough.\(game.key)" }

    static func load(_ games: [GameID]) -> Provider? { load(games, from: .standard) }

    static func load(_ games: [GameID], from defaults: UserDefaults) -> Provider? {
        games.lazy.compactMap { defaults.string(forKey: key($0)).flatMap(Provider.init(rawValue:)) }.first
    }

    static func save(_ provider: Provider, for games: [GameID], to defaults: UserDefaults = .standard) {
        for game in games { defaults.set(provider.rawValue, forKey: key(game)) }
    }

    /// Back to the store it's installed in (after its copy in the picked store was uninstalled).
    static func forget(_ games: [GameID], in defaults: UserDefaults = .standard) {
        for game in games { defaults.removeObject(forKey: key(game)) }
    }
}
