import Foundation

/// What the library grid shows and in which order. Kept while you open a game's page and come
/// back, and while you're on Home; only the library applies it, and a search leaves it resting.
struct LibraryFilters: Equatable {
    enum Sort: CaseIterable {
        case recent, name, size

        var label: String {
            switch self {
            case .recent: return L10n.t("Recently played")
            case .name: return L10n.t("Name")
            case .size: return L10n.t("Disk space")
            }
        }

        /// What A on the pad (a click on the chip opens the list) picks next.
        var next: Sort { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    }

    /// One switch in the filter panel.
    enum Filter: CaseIterable {
        case great, controller, couch, mac, onMac

        var label: String {
            switch self {
            case .great: return Compatibility.Level.great.label
            case .controller: return L10n.t("Plays with a controller")
            case .couch: return L10n.t("Two on one Mac")
            case .mac: return L10n.t("Mac version")
            case .onMac: return L10n.t("Only on this Mac")
            }
        }

        var note: String? {
            switch self {
            case .controller: return L10n.t("Full support")
            case .couch: return L10n.t("Local co-op or split screen")
            case .onMac: return L10n.t("Installed or downloading")
            case .great, .mac: return nil
            }
        }

        var symbol: String {
            switch self {
            case .great: return Compatibility.Level.great.symbol
            case .controller: return "gamecontroller.fill"
            case .couch: return "sofa.fill"
            case .mac: return "apple.logo"
            case .onMac: return "internaldrive"
            }
        }
    }

    /// One store's games (a game from several counts in each); nil: all of them.
    var store: Provider?
    /// The panel's switches that are on.
    var on: Set<Filter> = []
    var sort = Sort.recent
    /// Only the games on the player's Play Later list: the chip of its own in the library's row.
    var later = false

    /// Something leaves games out.
    var narrows: Bool { store != nil || !on.isEmpty || later }

    /// Without what leaves games out (the order stays).
    var cleared: LibraryFilters { LibraryFilters(sort: sort) }

    /// The row's "Clear filters" shows while something leaves games out or a search runs; it clears
    /// both (`cleared`, and the search).
    static func clearable(_ filters: LibraryFilters, search: String) -> Bool {
        filters.narrows || !Search.key(search).isEmpty
    }

    /// The panel's "All filters off": the store and the list, which aren't in the panel, stay.
    var switchesOff: LibraryFilters { LibraryFilters(store: store, sort: sort, later: later) }

    func has(_ filter: Filter) -> Bool { on.contains(filter) }

    mutating func toggle(_ filter: Filter) {
        if on.remove(filter) == nil { on.insert(filter) }
    }

    /// A game from several stores goes by what its card shows (`Game.shown`) and is in each of its
    /// stores. `laterGames`: the player's list (GameMarks).
    func admits(_ game: Game, laterGames: Set<GameID> = [], level: (Game) -> Compatibility.Level) -> Bool {
        if let store, !game.providers.contains(store) { return false }
        if later, !game.isMarked(in: laterGames) { return false }
        for filter in on {
            switch filter {
            case .great where level(game) != .great: return false
            case .controller where game.controller != .full: return false
            case .couch where game.playModes.isDisjoint(with: PlayMode.couch): return false
            case .mac where game.platform != .mac: return false
            case .onMac:
                switch game.shown.shelfState {
                case .installed, .downloading: break
                case .notInstalled, .inStore: return false
                }
            default: break
            }
        }
        return true
    }

    /// Owned games in the order `sort` asks for; the library's own order is "recently played".
    func sorted(_ games: [Game]) -> [Game] {
        switch sort {
        case .recent:
            return games
        case .name:
            return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return games.sorted { $0.sizeOnDisk != $1.sizeOnDisk ? $0.sizeOnDisk > $1.sizeOnDisk
                                                                : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

/// One titled group of the grid; each starts a row of its own.
struct LibrarySection: Equatable {
    let id: String
    let title: String
    /// Indices into the games, in the order shown.
    let items: [Int]

    /// The grid's sections for `games` (already filtered and sorted): a search's hits in one list,
    /// best first; the hidden games by name; "recently played" grouped into installed /
    /// downloading / the rest; by name or size one list. Store hits always come last.
    static func make(_ games: [Game], sort: LibraryFilters.Sort, searching: Bool, hidden: Bool) -> [LibrarySection] {
        let owned = games.indices.filter { games[$0].install != .inStore }
        let store = games.indices.filter { games[$0].install == .inStore }
        var sections: [LibrarySection]
        if searching {
            sections = [LibrarySection(id: "results", title: L10n.t("Your games"), items: owned)]
        } else if hidden {
            sections = [LibrarySection(id: "hidden", title: L10n.t("Hidden games"), items: owned)]
        } else if sort == .recent {
            sections = GridGroup.allCases.filter { $0 != .store }.map { group in
                LibrarySection(id: "\(group)", title: group.title, items: owned.filter { group.contains(games[$0].shown.shelfState) })
            }
        } else {
            sections = [LibrarySection(id: "all", title: sort == .name ? L10n.t("A – Z") : L10n.t("Largest first"), items: owned)]
        }
        sections.append(LibrarySection(id: "store", title: GridGroup.store.title, items: store))
        return sections.filter { !$0.items.isEmpty }
    }
}
