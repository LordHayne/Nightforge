import Foundation

/// Games the player hid from the library or pinned to Home. Kept by store and ID (`GameID.key`),
/// so a game keeps its mark when it changes between its Mac and Windows versions.
enum GameMarks {
    enum Kind: String {
        case hidden, pinned
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
}
