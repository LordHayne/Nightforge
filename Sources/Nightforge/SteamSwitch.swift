import Foundation

/// A Steam's sign-in as it logs it, the same in Nightforge's Windows Steam and in Steam for Mac.
enum SteamLogin {
    /// The sign-in state since Steam last started: the newest "SetLoginState: …" in steamui_login.txt
    /// after its "Client version" line – "WaitingForCredentials" while its sign-in window waits,
    /// "Success" once signed in.
    static func state(steamRoot: URL) -> String? {
        state(log: tail(steamRoot.appendingPathComponent("logs/steamui_login.txt")))
    }

    /// "[2026-10-26 10:29:48] [ None ] SetLoginState: WaitingForCredentials - OK"
    static func state(log: String) -> String? {
        let start = log.range(of: "Client version:", options: .backwards)?.upperBound ?? log.startIndex
        guard let marker = log[start...].range(of: "SetLoginState: ", options: .backwards) else { return nil }
        let rest = log[marker.upperBound...]
        let name = rest.prefix { $0.isLetter }
        return name.isEmpty ? nil : String(name)
    }

    /// Steam shows its sign-in window and waits, logged since `since`: its first start, or a
    /// remembered sign-in that has run out (every few months, or after a password change).
    static func waitingForCredentials(steamRoot: URL, since: Date) -> Bool {
        let log = steamRoot.appendingPathComponent("logs/steamui_login.txt")
        guard let modified = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified >= since
        else { return false }
        return state(steamRoot: steamRoot) == "WaitingForCredentials"
    }

    /// The account a Steam remembers (config/loginusers.vdf), by its SteamID: the most recent one.
    static func rememberedAccount(steamRoot: URL) -> String? {
        rememberedAccount(users: VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"])
    }

    /// The name the remembered account shows in Steam; never its login name.
    static func personaName(steamRoot: URL) -> String? {
        personaName(users: VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"])
    }

    static func personaName(users: VDF?) -> String? {
        guard let id = rememberedAccount(users: users), let name = users?[id]?["PersonaName"]?.string, !name.isEmpty else { return nil }
        return name
    }

    /// "MostRecent" 1 where Steam still writes it, else the one it signs in by itself ("AutoLogin"
    /// 1), else the newest.
    static func rememberedAccount(users: VDF?) -> String? {
        let accounts = users?.object ?? [:]
        func flag(_ id: String, _ key: String) -> Bool { accounts[id]?[key]?.string == "1" }
        func stamp(_ id: String) -> Int { accounts[id]?["timestamp"]?.string.flatMap { Int($0) } ?? 0 }
        let ids = accounts.keys.sorted()
        return ids.first { flag($0, "MostRecent") } ?? ids.first { flag($0, "AutoLogin") }
            ?? ids.max { stamp($0) < stamp($1) }
    }

    private static func tail(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
}

/// Which of the two Steams runs. Both sign in with the same account, and Steam keeps one session
/// per account, login ID and public IP – the login ID comes from the Mac's local address, so the
/// second Steam to sign in signs the first one out ("Session Replaced"), and it stays out. The
/// remembered sign-in survives that: started again, a Steam signs in by itself, without a window
/// (216 of 216 restarts on the dev Mac, 29.10.2026). So Nightforge keeps one of them running – the
/// one the next game needs – and quits the other instead of letting it be signed out: a signed-out
/// Steam keeps running, its downloads stall, its cloud syncs fail ("Failed sync … login=false"
/// 28 times on 26./27.10.2026) and its windows come up (docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md).
///
/// - Resting state: the Windows Steam (most games, Play starts at once), Steam for Mac quit.
/// - A Mac version starts: the Windows Steam goes (`makeWayForMac`).
/// - It has ended: once its save is in the Steam Cloud, Steam for Mac quits and the Windows Steam
///   starts again, hidden (`afterMacGame`) – the next Windows game doesn't wait for a sign-in.
/// - Never while the other side plays, starts or uploads a save.
/// - A Steam for Mac the player opened stays as it is.
@MainActor
final class SteamSwitch {
    /// What the switch goes by, read fresh each time.
    struct Facts: Equatable {
        var macSteamRunning = false
        /// Nightforge started the Steam for Mac that runs (MacSteam.startedByNightforge).
        var macSteamOurs = false
        /// A Mac version runs or starts.
        var macGameBusy = false
        /// A Mac version downloads – it has its turn (LibraryModel.takeTurnsDownloading).
        var macDownload = false
        var windowsSteamRunning = false
        /// A Windows game runs or starts on Nightforge's Steam.
        var windowsGameBusy = false
        /// A game moves to another drive (DriveMoves), which stops and starts its Steam itself.
        var moving = false
    }

    /// A game that ended, whose Steam may still be putting its save into the cloud.
    struct Session {
        let appID: Int
        let steamRoot: URL
        let endedAt: Date
    }

    /// How long a switch waits for a save to reach the cloud: in the background after a game, and
    /// while a start waits for it. Steam that hasn't confirmed by then syncs on its next start.
    nonisolated static let backgroundPatience: TimeInterval = 180
    nonisolated static let launchPatience: TimeInterval = 60

    private(set) var lastSession: [Platform: Session] = [:]
    /// Nightforge quit its Windows Steam for Steam for Mac; it starts again when that's done.
    private(set) var windowsStopped = false
    private var afterMac: Task<Void, Never>?
    /// The switch back has got to starting the Windows Steam: a start waits for that to finish
    /// rather than calling it off halfway (settle).
    private var restartingWindows = false

    // MARK: - The rules

    /// After a Mac version: Steam for Mac goes, unless the player opened it, another Mac version
    /// runs or starts, a Mac download has its turn, or a game moves to another drive.
    nonisolated static func switchesBackAfterMac(_ facts: Facts) -> Bool {
        facts.macSteamRunning && facts.macSteamOurs && !facts.macGameBusy && !facts.macDownload && !facts.windowsGameBusy
            && !facts.moving
    }

    /// Before a Mac version starts: the Windows Steam goes, unless a Windows game still needs it
    /// (then the start doesn't get this far – LibraryModel.otherSteamFree).
    nonisolated static func stopsWindowsForMac(_ facts: Facts) -> Bool {
        facts.windowsSteamRunning && !facts.windowsGameBusy
    }

    /// Before a Windows game starts: Steam for Mac goes when Nightforge started it and no Mac
    /// version needs it.
    nonisolated static func quitsMacForWindows(_ facts: Facts) -> Bool {
        facts.macSteamRunning && facts.macSteamOurs && !facts.macGameBusy
    }

    /// The Windows Steam starts again: Nightforge quit it for Steam for Mac and it isn't back, or
    /// Steam for Mac signed it out.
    nonisolated static func restartsWindows(stoppedByNightforge: Bool, running: Bool, replaced: Bool) -> Bool {
        stoppedByNightforge ? !running : running && replaced
    }

    // MARK: - Saves on their way to the cloud

    /// A game ended: its Steam uploads its save now, which a switch must not cut off.
    func ended(_ game: Game, at date: Date) {
        guard game.provider == .steam else { return }
        lastSession[game.platform] = Session(appID: game.appID, steamRoot: game.steamRoot, endedAt: date)
    }

    /// The save of the last game on `platform` isn't confirmed in the cloud yet (CloudSaves).
    func savesPending(_ platform: Platform, now: Date = Date()) async -> Bool {
        guard let session = lastSession[platform], now.timeIntervalSince(session.endedAt) < Self.backgroundPatience else { return false }
        let state = await Task.detached(priority: .utility) {
            CloudSaves.state(appID: session.appID, steamRoot: session.steamRoot, endedAt: session.endedAt)
        }.value
        return state == .syncing
    }

    /// Waits until it is, for up to `limit` and while `keepWaiting` says so.
    func waitForSaves(_ platform: Platform, limit: TimeInterval, while keepWaiting: () -> Bool = { true }) async {
        let start = Date()
        while !Task.isCancelled, keepWaiting(), Date().timeIntervalSince(start) < limit, await savesPending(platform) {
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Switching

    /// After a Mac version ended: back to the resting state in the background, once its save is up.
    /// `restartWindows` starts the Windows Steam again, queued like any of its starts.
    func afterMacGame(facts: @escaping () -> Facts, restartWindows: @escaping () async -> Void) {
        guard let session = lastSession[.mac] else { return }
        afterMac?.cancel()
        afterMac = Task {
            guard await MacSteam.quitWhenSynced(appID: session.appID, endedAt: session.endedAt, limit: Self.backgroundPatience,
                                                while: { Self.switchesBackAfterMac(facts()) })
            else { return }
            // Called off meanwhile for a start, which sees to the Windows Steam itself.
            guard !Task.isCancelled else { return }
            restartingWindows = true
            defer { restartingWindows = false }
            await restartWindowsIfNeeded(restartWindows)
        }
    }

    /// Before a Mac version starts. A switch back still waiting for a save is called off (one that
    /// is quitting Steam for Mac finishes); a Windows game's save goes up first; then the Windows
    /// Steam makes way. One that is still starting is stopped before Steam for Mac starts – it
    /// would sign in after it and sign it out. A signed-in (or already signed-out) one goes
    /// alongside: Steam for Mac signing in signs it out anyway, and nothing waits for it.
    func makeWayForMac(facts: Facts, phase: (LaunchPhase) -> Void) async {
        if afterMac != nil { phase(.startingSteamForMac) }  // a switch back under way: no wait without a word
        await settle()
        var facts = facts
        facts.windowsSteamRunning = Engine.isSteamRunning  // a switch back may have just started it
        if await savesPending(.windows) {
            phase(.savingToCloud)
            await waitForSaves(.windows, limit: Self.launchPatience)
        }
        guard Self.stopsWindowsForMac(facts), let wine = await Engine.installedWine() else { return }
        windowsStopped = true
        GameLog.note("Steam switch: the Windows Steam makes way for Steam for Mac at \(GameLog.clock())")
        if Engine.steamSignedIn || Engine.sessionReplaced() {
            Task { try? await Engine.stopSteam(wine) }
        } else {
            phase(.startingSteamForMac)
            try? await Engine.stopSteam(wine)
        }
    }

    /// A Mac download's turn (LibraryModel.takeTurnsDownloading): the Windows Steam goes alongside.
    func stopWindowsForMacDownload() {
        guard Engine.isSteamRunning else { return }
        windowsStopped = true
        Task {
            guard let wine = await Engine.installedWine() else { return }
            try? await Engine.stopSteam(wine)
        }
    }

    /// Before a Windows game starts through Nightforge's Steam, or the Windows downloads get their
    /// turn: Steam for Mac goes when it should (its last game's save first), and a Windows Steam
    /// that Nightforge quit or Steam for Mac signed out starts again – `restartWindows`, which
    /// returns once it has signed in.
    func makeWayForWindows(facts: Facts, phase: (LaunchPhase) -> Void, restartWindows: () async -> Void) async {
        if afterMac != nil { phase(.startingSteam) }  // a switch back under way: no wait without a word
        await settle()
        if Self.quitsMacForWindows(facts) {
            GameLog.note("Steam switch: Steam for Mac makes way for the Windows Steam at \(GameLog.clock())")
            if await savesPending(.mac) {
                phase(.savingToCloud)
                await waitForSaves(.mac, limit: Self.launchPatience)
            }
            phase(.signingIn)
            await Task { await MacSteam.quit() }.value
        }
        if Self.restartsWindows(stoppedByNightforge: windowsStopped, running: Engine.isSteamRunning, replaced: false) {
            GameLog.note("Steam switch: the Windows Steam starts again at \(GameLog.clock())")
            phase(.startingSteam)
            windowsStopped = false
            await restartWindows()
        }
    }

    /// A switch back under way: called off while it waits for a save, waited for once it quits
    /// Steam for Mac, and to the end once it starts the Windows Steam – called off then, that Steam
    /// would come up behind the start's back.
    private func settle() async {
        guard let task = afterMac else { return }
        if !restartingWindows { task.cancel() }
        await task.value
        afterMac = nil
    }

    private func restartWindowsIfNeeded(_ restart: () async -> Void) async {
        guard Self.restartsWindows(stoppedByNightforge: windowsStopped, running: Engine.isSteamRunning,
                                   replaced: Engine.sessionReplaced())
        else { return }
        windowsStopped = false
        await restart()
    }
}
