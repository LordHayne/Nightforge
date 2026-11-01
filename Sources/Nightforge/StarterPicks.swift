import Foundation

/// What decides how good a first game is, from what Nightforge already knows before it was played.
struct StarterFacts: Equatable {
    var installed: Bool
    var level: Compatibility.Level
    /// nil: not known – only Steam says (a game only from Epic or GOG).
    var controller: ControllerSupport?
    /// Nightforge would run its Mac version (it has one that runs on current Macs, or uses it already).
    var mac: Bool
    var metascore: Int?
    /// What it takes on the Mac (or the download), 0 when not known.
    var size: Int64
}

/// "To start with": a library's best starts, shown on Home's stage after "Continue playing" until
/// three games have been played (HomeRail.stage). The first one is "Recommended to start".
enum StarterPicks {
    static let count = 10

    /// Indices into `games`, best first: installed, runs great, full controller support, the Mac
    /// version, the Metascore, a smaller download. Only games of the library that can run here.
    static func order(_ games: [Game], facts: (Game) -> StarterFacts) -> [Int] {
        let candidates: [(index: Int, facts: StarterFacts)] = games.indices.compactMap { index in
            let game = games[index]
            guard game.inLibrary, !game.isVROnly else { return nil }
            let f = facts(game)
            return f.level.stopsGame ? nil : (index, f)
        }
        return candidates.sorted { a, b in
            let (x, y) = (rank(a.facts), rank(b.facts))
            return x != y ? x.lexicographicallyPrecedes(y) : games[a.index].name.localizedStandardCompare(games[b.index].name) == .orderedAscending
        }.map(\.index)
    }

    /// Smaller is better, place by place.
    static func rank(_ f: StarterFacts) -> [Int64] {
        let level: Int64 = f.level == .great ? 0 : f.level == .tweaks ? 1 : 2
        // Not known sits with "most of it": better than a game that says it has none.
        let controller: Int64 = f.controller == .full ? 0 : f.controller == ControllerSupport.none ? 2 : 1
        return [f.installed ? 0 : 1, level, controller, f.mac ? 0 : 1, -Int64(f.metascore ?? 0), f.size > 0 ? f.size : .max]
    }

    /// One plain sentence on why this game is a good start.
    static func reason(_ f: StarterFacts) -> String {
        let runs = f.mac ? L10n.t("The Mac version runs without any Windows translation")
            : f.level == .great ? L10n.t("Runs great on this Mac")
            : f.level == .tweaks ? L10n.t("Runs on this Mac with tweaks Nightforge applies by itself")
            : L10n.t("Not tested yet – most games like it run anyway")
        let sentence: String
        switch f.controller {
        case .full: sentence = L10n.t("%@, and you play it fully with a controller.", runs)
        case .partial: sentence = L10n.t("%@. A controller does most of it; some menus want a mouse or keyboard.", runs)
        case .some(.none): sentence = L10n.t("%@. It's played with mouse and keyboard.", runs)
        case nil: sentence = runs + "."  // nothing claimed that isn't known
        }
        return f.installed ? L10n.t("Already on your Mac. %@", sentence) : sentence
    }
}

extension HomeRail {
    /// What Home's stage shows: "Continue playing" (`pick` without filling up), and while that has
    /// fewer than `minimum` games, the best starts after it ("To start with"), the rest of the way
    /// to `limit`. `startersFrom`: where the starts begin, nil without any. `starters` is only asked
    /// for when they're needed.
    static func stage(_ games: [Game], pinned: Set<GameID> = [], now: Date = Date(),
                      starters: () -> [Int]) -> (rail: [Int], startersFrom: Int?) {
        let played = pick(games, pinned: pinned, now: now, fill: false)
        guard played.count < minimum else { return (played, nil) }
        let picks = starters().filter { !played.contains($0) }.prefix(min(StarterPicks.count, limit - played.count))
        guard !picks.isEmpty else { return (pick(games, pinned: pinned, now: now), nil) }
        return (played + picks, played.count)
    }

    /// What place `place` of a stage with `count` games is (`startersFrom` from `stage`).
    static func role(place: Int, startersFrom: Int?, count: Int) -> LibraryModel.HomeRole {
        guard let from = startersFrom, place < count else { return .next }
        if place < from { return .played }
        if from > 0 { return .upNext }
        return place == 0 ? .recommended : .starter
    }
}
