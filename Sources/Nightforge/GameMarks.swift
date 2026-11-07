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
