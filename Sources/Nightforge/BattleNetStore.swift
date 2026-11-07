import Foundation

/// Battle.net: Blizzard's own client, on the Mac and in a Wine prefix of its own (BattleNetLibrary).
/// Unlike Epic's and GOG's games, these stay the client's to download, update and start; Nightforge
/// shows what the Agent lists and will ask the client to start it, and never holds a Blizzard
/// password or changes the client's files.
///
/// So far the library only: the cards show, nothing starts from them (LibraryModel.launch). Until
/// the start is there they stay behind a hidden switch:
/// `defaults write io.github.lordhayne.nightforge battleNetStore -bool true`
@MainActor
final class BattleNetStore: StoreProvider {
    static let switchKey = "battleNetStore"

    let provider = Provider.battlenet
    private(set) var sync = StoreSync()

    private var clients: [BattleNetLibrary.Client] { [.mac, .windows(prefix: BattleNetLibrary.prefix)] }

    /// Switched on, and a client has left its list on this Mac. No sign-in of Nightforge's own: that's the client's.
    var isConnected: Bool {
        UserDefaults.standard.bool(forKey: Self.switchKey)
            && clients.contains { FileManager.default.fileExists(atPath: $0.database.path) }
    }

    func library() async -> [Game] {
        guard isConnected else { return [] }
        let prefix = BattleNetLibrary.prefix
        return await Engine.offMain {
            func games(_ client: BattleNetLibrary.Client) -> [Game] {
                BattleNetLibrary.read(client.database).map { BattleNetLibrary.games($0, client: client) } ?? []
            }
            return BattleNetLibrary.merged(mac: games(.mac), windows: games(.windows(prefix: prefix)))
        }
    }

    func install(_ game: Game, context: StoreContext) async throws {
        throw ClientsOwn()
    }

    func uninstall(_ game: Game) async throws {
        throw ClientsOwn()
    }

    /// Downloads and removals stay Battle.net's own.
    struct ClientsOwn: LocalizedError {
        var errorDescription: String? { L10n.t("Battle.net installs and removes its games itself: do that in Battle.net.") }
    }
}
