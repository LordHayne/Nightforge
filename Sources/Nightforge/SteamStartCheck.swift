import Foundation

/// Whether Nightforge's Steam came up after Nightforge started it, for the engine rollback
/// (EngineRollback.afterFailedSteamStart) – told apart from a Steam that's only slow. A Steam that
/// updates itself is never judged, nor one that has had less than `patience`; it counts as failed
/// only with its process gone or its logs quiet for `quiet`. Only log lines written since that start
/// are signs of life: a start that dies early leaves the last session's "Logged On" behind.
enum SteamStartCheck {
    enum Outcome: Equatable {
        case cameUp
        case failed
        case undecided
    }

    /// How long a start gets before it can count as failed: Steam under Wine signs in within half a
    /// minute, and Nightforge waits 90 s for a restarted one (LibraryModel.restartStuckSteam).
    static let patience: TimeInterval = 90
    /// How long its logs have to be quiet then, as for a stuck Steam (Engine.steamLooksStuck).
    static let quiet: TimeInterval = 45

    struct Signs: Equatable {
        /// connection_log since the start: signed in, or signed out by Steam for Mac (so it ran).
        var signedIn = false
        var sessionReplaced = false
        /// It asks for the account: its window is up, the engine runs it.
        var askingForAccount = false
        /// console_log since the start: "System startup time".
        var startupFinished = false
        var bootstrap: SteamBootstrap = .idle
        /// Steam's main process and its wineserver run.
        var running = true
        /// Since Steam's newest log line (or the start, when it wrote none since), and since the start.
        var quietFor: TimeInterval = 0
        var sinceStart: TimeInterval = 0
    }

    static func judge(_ signs: Signs) -> Outcome {
        if signs.signedIn || signs.sessionReplaced || signs.askingForAccount || signs.startupFinished { return .cameUp }
        // An update coming down or going in takes as long as it takes (SteamBootstrap).
        guard signs.bootstrap == .idle, signs.sinceStart >= patience else { return .undecided }
        return !signs.running || signs.quietFor >= quiet ? .failed : .undecided
    }

    /// What `steamRoot`'s logs say about a Steam started at `start`. `running`: Engine.isSteamRunning.
    static func signs(steamRoot: URL, start: Date, running: Bool, now: Date = Date()) -> Signs {
        let logs = steamRoot.appendingPathComponent("logs", isDirectory: true)
        func modified(_ file: URL) -> Date? {
            (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        func fresh(_ name: String) -> Bool { modified(logs.appendingPathComponent(name)).map { $0 >= start } ?? false }
        let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.compactMap(modified).filter { $0 >= start }.max() ?? start
        var signs = Signs()
        signs.signedIn = fresh("connection_log.txt") && Engine.signedIn(steamRoot: steamRoot)
        signs.sessionReplaced = fresh("connection_log.txt") && Engine.sessionReplaced(steamRoot: steamRoot)
        signs.askingForAccount = SteamLogin.waitingForCredentials(steamRoot: steamRoot, since: start)
        signs.startupFinished = fresh("console_log.txt") && Engine.startupFinished(steamRoot: steamRoot)
        signs.bootstrap = SteamBootstrap(steamRoot: steamRoot)
        signs.running = running
        signs.quietFor = now.timeIntervalSince(newest)
        signs.sinceStart = now.timeIntervalSince(start)
        return signs
    }
}
