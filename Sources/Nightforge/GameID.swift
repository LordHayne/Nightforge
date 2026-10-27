import Foundation

/// The stores Nightforge brings games in from.
enum Provider: String, CaseIterable, Identifiable {
    case steam, epic

    var id: String { rawValue }

    /// The store's own name (not translated).
    var label: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic Games"
        }
    }
}

/// Which store a game comes from and its ID there – Steam's app ID, Epic's app name. Everything
/// Nightforge keeps per game (options, what a start taught it, marks, ratings, art) is filed under
/// `key`, so a game from another store never mixes with a Steam game that happens to share its ID.
struct GameID: Hashable, CustomStringConvertible {
    let provider: Provider
    let id: String

    static func steam(_ appID: Int) -> GameID { GameID(provider: .steam, id: String(appID)) }
    static func epic(_ appName: String) -> GameID { GameID(provider: .epic, id: appName) }

    /// Steam's app ID, for what only Steam knows (its manifests, store pages, the profile list).
    var steamAppID: Int? { provider == .steam ? Int(id) : nil }

    /// "steam.570", "epic.Fortnite": the name settings are kept under, and what links carry.
    var key: String { "\(provider.rawValue).\(id)" }

    var description: String { key }

    /// From `key` – or from a bare number, which is a Steam app ID: that's how Nightforge wrote
    /// them before there were other stores (the links of games added to Applications, say).
    /// IDs become file and bundle names, so only letters, digits, "-" and "_" pass.
    init?(key: String) {
        if let appID = Int(key) {
            guard appID > 0 else { return nil }
            self = .steam(appID)
            return
        }
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = Provider(rawValue: parts[0]), Self.isPlain(parts[1]) else { return nil }
        if provider == .steam && (Int(parts[1]) ?? 0) <= 0 { return nil }
        self.init(provider: provider, id: parts[1])
    }

    init(provider: Provider, id: String) {
        self.provider = provider
        self.id = id
    }

    static func isPlain(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
    }
}
