import Foundation

/// Battle.net: Blizzard's own client, on the Mac and in a Wine prefix of its own (BattleNetLibrary).
/// Unlike Epic's and GOG's games, these stay the client's to download, update and start; Nightforge
/// shows what the Agent lists and asks the client to start it (BattleNetStart, the Mac client's games
/// only), and never holds a Blizzard password or changes the client's or a game's files.
///
/// The cards show once Battle.net is linked: on its launcher card, or by itself once the client is
/// signed in on this Mac – until the player disconnects it (`links`).
@MainActor
final class BattleNetStore: StoreProvider {
    static let switchKey = "battleNetStore"

    let provider = Provider.battlenet
    private(set) var sync = StoreSync()

    private var clients: [BattleNetLibrary.Client] { [.mac, .windows(prefix: BattleNetLibrary.prefix)] }

    /// Linked: its games are in the library.
    var isLinked: Bool { UserDefaults.standard.bool(forKey: Self.switchKey) }
    /// The player chose "Disconnect": a signed-in client doesn't bring the games back by itself.
    var wasUnlinked: Bool { UserDefaults.standard.object(forKey: Self.switchKey) as? Bool == false }

    /// Whether Battle.net belongs in the library: linked, or signed in on this Mac and never disconnected
    /// – as Steam's games show once Steam is signed in. Blizzard's client has no sign-in of Nightforge's.
    nonisolated static func links(linked: Bool, unlinked: Bool, clientSignedIn: Bool) -> Bool {
        linked || (!unlinked && clientSignedIn)
    }

    func link() { UserDefaults.standard.set(true, forKey: Self.switchKey) }
    func unlink() { UserDefaults.standard.set(false, forKey: Self.switchKey) }

    /// Linked, and a client has left its list on this Mac. No sign-in of Nightforge's own: that's the client's.
    var isConnected: Bool {
        isLinked && clients.contains { FileManager.default.fileExists(atPath: $0.database.path) }
    }

    func library() async -> [Game] {
        guard isConnected else { return [] }
        let prefix = BattleNetLibrary.prefix
        let found: [Game] = await Engine.offMain {
            func games(_ client: BattleNetLibrary.Client) -> [Game] {
                BattleNetLibrary.read(client.database).map { BattleNetLibrary.games($0, client: client) } ?? []
            }
            return BattleNetLibrary.merged(mac: games(.mac), windows: games(.windows(prefix: prefix)))
        }
        return Self.withPlayTimes(found, loadPlayTimes())
    }

    // MARK: Play time

    /// What Nightforge has seen of its own starts: the client keeps none it lets anyone read.
    nonisolated static var playTimeFile: URL { Engine.supportDir.appendingPathComponent("BattleNet/playtime.json") }

    private func loadPlayTimes() -> [String: EpicPlayTime] {
        (try? Data(contentsOf: Self.playTimeFile)).flatMap { try? JSONDecoder().decode([String: EpicPlayTime].self, from: $0) } ?? [:]
    }

    private func save(_ times: [String: EpicPlayTime]) {
        try? FileManager.default.createDirectory(at: Self.playTimeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(times) { try? data.write(to: Self.playTimeFile, options: .atomic) }
    }

    nonisolated static func withPlayTimes(_ games: [Game], _ times: [String: EpicPlayTime]) -> [Game] {
        games.map { game in
            guard let time = times[game.gameID.id] else { return game }
            var game = game
            game.lastPlayed = time.lastPlayed
            game.playtimeMinutes = time.minutes
            return game
        }
    }

    /// `time` after a start (no minutes yet) or a session that ended.
    nonisolated static func played(_ time: EpicPlayTime?, minutes: Int = 0, at date: Date) -> EpicPlayTime {
        var time = time ?? EpicPlayTime()
        time.lastPlayed = date
        time.minutes += max(minutes, 0)
        return time
    }

    func recordStart(_ game: Game, at date: Date = Date()) {
        var times = loadPlayTimes()
        times[game.gameID.id] = Self.played(times[game.gameID.id], at: date)
        save(times)
    }

    /// A session that ended: for "Continue playing" and the play time.
    func recordSession(_ game: Game, minutes: Int, endedAt: Date = Date()) {
        var times = loadPlayTimes()
        times[game.gameID.id] = Self.played(times[game.gameID.id], minutes: minutes, at: endedAt)
        save(times)
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
