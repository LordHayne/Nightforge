import Foundation

/// Games the player hid from the library, pinned to Home or marked to play later. Kept by store and
/// ID (`GameID.key`), so a game keeps its mark when it changes between its Mac and Windows versions,
/// and when it leaves the library for a while.
enum GameMarks {
    enum Kind: String {
        case hidden, pinned, later
    }

    /// Up to Epic Games these were Steam app IDs under "library.hidden" / "library.pinned"
    /// (GameIDMigration brings them over).
    static func key(_ kind: Kind) -> String { "marks.\(kind.rawValue)" }
    static func legacyKey(_ kind: Kind) -> String { "library.\(kind.rawValue)" }

    static func load(_ kind: Kind, from defaults: UserDefaults = .standard) -> Set<GameID> {
        Set(((defaults.array(forKey: key(kind)) as? [String]) ?? []).compactMap(GameID.init(key:)))
    }

    static func save(_ ids: Set<GameID>, _ kind: Kind, to defaults: UserDefaults = .standard) {
        defaults.set(ids.map(\.key).sorted(), forKey: key(kind))
    }

    /// A game into `marks` or out of it, under all its stores at once (`Game.gameIDs`), so it's
    /// marked or not wherever it's looked up.
    static func set(_ games: [GameID], _ on: Bool, in marks: inout Set<GameID>) {
        if on { marks.formUnion(games) } else { marks.subtract(games) }
    }
}

/// Games taken off Home ("Remove from Home", the user's wish 8.11.), with when: one comes back once it's
/// played after that, or pinned. The library keeps it all along.
enum HomeRemovals {
    static let key = "marks.offHome"

    static func load(from defaults: UserDefaults = .standard) -> [GameID: Date] {
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        return Dictionary(stored.compactMap { key, time in GameID(key: key).map { ($0, Date(timeIntervalSince1970: time)) } },
                          uniquingKeysWith: max)
    }

    static func save(_ removals: [GameID: Date], to defaults: UserDefaults = .standard) {
        defaults.set(Dictionary(uniqueKeysWithValues: removals.map { ($0.key.key, $0.value.timeIntervalSince1970) }), forKey: key)
    }

    /// Off Home: taken off in any of its stores, and not played since.
    static func isOff(_ game: Game, in removals: [GameID: Date]) -> Bool {
        guard !removals.isEmpty, let removed = game.gameIDs.compactMap({ removals[$0] }).max() else { return false }
        return (game.lastPlayed ?? .distantPast) <= removed
    }
}
