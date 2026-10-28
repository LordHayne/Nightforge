import Foundation

/// Where the main window is: Home (what you play) → Library (every game) → one game's page.
/// Back (Esc, B) always goes one level up, to where the page was opened from.
enum Route: Equatable {
    case home, library
    case detail(gameID: String, from: Level)

    enum Level: Equatable { case home, library }

    /// The section the top bar shows: a game's page belongs to where it was opened from.
    var level: Level {
        switch self {
        case .home: return .home
        case .library: return .library
        case .detail(_, let from): return from
        }
    }

    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }

    /// The level a step back leads to; nil on Home, where there's nothing behind.
    var parent: Route? {
        switch self {
        case .home: return nil
        case .library, .detail(_, .home): return .home
        case .detail(_, .library): return .library
        }
    }
}

/// Where a step back can be retraced: two fingers the other way on the trackpad go forward again,
/// like Safari – but only right after going back. Any other step forgets it.
struct NavigationHistory: Equatable {
    enum Step { case back, forward, other }

    /// The levels gone back from, the latest last.
    private(set) var forward: [Route] = []

    /// The window went from `old` to `new`.
    mutating func moved(from old: Route, to new: Route, by step: Step) {
        switch step {
        case .back:
            forward.append(old)
        case .forward where forward.last == new:
            forward.removeLast()
        case .forward, .other:
            forward.removeAll()
        }
    }

    /// Something changed without leaving the level (back dropped the search): nothing to retrace.
    mutating func forget() { forward.removeAll() }

    /// The level forward leads to from `current`: the one last gone back from, if it lies right
    /// ahead of where the window is now.
    func next(from current: Route) -> Route? {
        guard let next = forward.last, next.parent == current else { return nil }
        return next
    }
}

/// Home's rail, "Continue playing": only what you're likely to play next, so it stays short with
/// hundreds of games. Everything else is one step away in the library (the rail's last tile).
enum HomeRail {
    static let limit = 12
    /// Played within this many days counts as "lately".
    static let recentDays = 90
    /// With fewer games than this to continue (a new library), other installed games fill up.
    static let minimum = 3

    /// Indices into `games`: pinned games first (by name), then downloads, then installed games
    /// played in the last 90 days, the latest first. Only what's on this Mac. A game from several
    /// stores goes by what its card shows (`Game.shown`) and is pinned when one of them is.
    static func pick(_ games: [Game], pinned: Set<GameID> = [], now: Date = Date()) -> [Int] {
        let onMac = games.indices.filter { index in
            switch games[index].shown.install {
            case .installed, .downloading: return true
            case .notInstalled, .inStore: return false
            }
        }
        func downloading(_ game: Game) -> Bool {
            if case .downloading = game.shown.install { return true }
            return false
        }
        let since = now.addingTimeInterval(-Double(recentDays) * 86_400)
        func recent(_ game: Game) -> Bool { game.lastPlayed.map { $0 >= since } ?? false }
        func byName(_ a: Int, _ b: Int) -> Bool { games[a].name.localizedStandardCompare(games[b].name) == .orderedAscending }
        // Latest first; never played after the rest, by name.
        func byRecency(_ a: Int, _ b: Int) -> Bool {
            switch (games[a].lastPlayed, games[b].lastPlayed) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return byName(a, b)
            }
        }

        let pins = onMac.filter { games[$0].isMarked(in: pinned) }.sorted(by: byName)
        let rest = onMac.filter { !games[$0].isMarked(in: pinned) }
        let downloads = rest.filter { downloading(games[$0]) }.sorted(by: byRecency)
        let lately = rest.filter { !downloading(games[$0]) && recent(games[$0]) }.sorted(by: byRecency)
        var rail = pins + downloads + lately
        if rail.count < minimum {
            rail += rest.filter { !rail.contains($0) }.sorted(by: byRecency).prefix(minimum - rail.count)
        }
        return Array(rail.prefix(limit))
    }
}
