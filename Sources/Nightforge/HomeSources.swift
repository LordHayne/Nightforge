import Foundation

/// What Home's stage is made of (Settings › Home): each source on or off. Pinned games, downloads,
/// what was played lately and the suggestions are on until the player says otherwise; Play Later is
/// off. Taking one game off Home stays its quick menu's (HomeRemovals).
struct HomeSources: Equatable {
    enum Source: String, CaseIterable, Identifiable {
        case pinned, downloads, recent, later, starters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pinned: return L10n.t("Pinned games")
            case .downloads: return L10n.t("Downloads in progress")
            case .recent: return L10n.t("Recently played")
            case .later: return L10n.t("Play Later")
            case .starters: return L10n.t("Suggestions to start with")
            }
        }

        /// A word on what it means, where its name doesn't say.
        var note: String? {
            switch self {
            case .recent: return L10n.t("the last %ld days", HomeRail.recentDays)
            case .starters: return L10n.t("fills up a short Home")
            case .pinned, .downloads, .later: return nil
            }
        }

        fileprivate var byDefault: Bool { self != .later }
        static func key(_ source: Source) -> String { "home.source.\(source.rawValue)" }
    }

    private var off: Set<Source> = [.later]

    func isOn(_ source: Source) -> Bool { !off.contains(source) }

    mutating func set(_ source: Source, _ on: Bool) {
        if on { off.remove(source) } else { off.insert(source) }
    }

    /// Each by a key of its own: a source added later starts with its own default.
    static func load(from defaults: UserDefaults = .standard) -> HomeSources {
        var sources = HomeSources()
        for source in Source.allCases {
            sources.set(source, defaults.object(forKey: Source.key(source)) as? Bool ?? source.byDefault)
        }
        return sources
    }

    func save(to defaults: UserDefaults = .standard) {
        for source in Source.allCases { defaults.set(isOn(source), forKey: Source.key(source)) }
    }
}

/// The player's order of the pinned games (Settings › Home), as `GameID`s. A game pinned after that
/// comes behind them, by name, until it's moved.
enum HomePinOrder {
    static let key = "home.pinOrder"

    static func load(from defaults: UserDefaults = .standard) -> [GameID] {
        ((defaults.array(forKey: key) as? [String]) ?? []).compactMap(GameID.init(key:))
    }

    static func save(_ order: [GameID], to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.key), forKey: key)
    }

    /// `indices` of `games` in that order: a game from several stores goes by the first of its IDs in it.
    static func sorted(_ indices: [Int], in games: [Game], order: [GameID]) -> [Int] {
        let places = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        func place(_ index: Int) -> Int? { games[index].gameIDs.compactMap { places[$0] }.min() }
        return indices.sorted { a, b in
            switch (place(a), place(b)) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return games[a].name.localizedStandardCompare(games[b].name) == .orderedAscending
            }
        }
    }

    /// The order with `pinned[index]` moved `delta` places; nil past either end. IDs of pinned games
    /// that aren't in the library right now keep their place behind the others.
    static func moved(_ pinned: [Game], index: Int, by delta: Int, order: [GameID]) -> [GameID]? {
        guard pinned.indices.contains(index), pinned.indices.contains(index + delta), delta != 0 else { return nil }
        var games = pinned
        games.remove(at: index)
        games.insert(pinned[index], at: index + delta)
        let listed = games.flatMap(\.gameIDs)
        let known = Set(listed)
        return listed + order.filter { !known.contains($0) }
    }
}
