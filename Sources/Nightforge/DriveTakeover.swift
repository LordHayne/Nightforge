import AppKit

/// When a drive's games are looked at (again) – pure, for the tests.
enum DriveTakeoverRules {
    /// What can change while Nightforge runs and makes another look worthwhile: something that was in
    /// the way is over, a Steam got set up, a store signed in or its list of games arrived.
    struct State: Equatable {
        /// A game, a download, a move or the setup is under way.
        var busy = false
        var windowsSteam = false
        var macSteam = false
        /// The player has Steam for Mac open themselves: it isn't closed under their hands.
        var macSteamOpen = false
        var epicSignedIn = false
        var epicGames = 0
        var gogConnected = false
        var gogGames = 0
    }

    /// Asked for (Nightforge started, a drive was plugged in, a try is due again) – or something on a
    /// drive waited at the last look and what it waited for may have come.
    static func due(asked: Bool, waited: Bool, state: State, last: State?) -> Bool {
        asked || (waited && state != last)
    }

    /// How often one game is offered to legendary before it's left alone until Nightforge starts again
    /// or the drive comes back: once more after a refusal (Epic not reachable just then).
    static let epicTries = 2
    /// How often a look that failed somewhere is made again by itself, and after how long.
    static let retries = 3
    static let retryAfter: TimeInterval = 120
}

/// Takes the games on a plugged-in drive over: a drive that holds games in "Nightforge Games" from an
/// earlier Nightforge – after a reinstall, on a second Mac, or once Nightforge's data is gone – gets its
/// games back as installed, without downloading them again and without anything on the drive being
/// deleted or written over. Each store its own way: Steam learns the library (its list of libraries,
/// with Steam stopped), legendary takes an Epic game into its list (`legendary import`), and a GOG game
/// goes into Nightforge's own record. What its store isn't ready for waits, and comes once it is.
@MainActor
final class DriveTakeover {
    static let shared = DriveTakeover()

    struct TakenGame: Equatable {
        var name: String
        var provider: Provider
        var platform: Platform
    }

    /// What one look took over from one drive.
    struct Taken: Equatable {
        var drive: String
        var games: [TakenGame]
    }

    /// Told what came back. Nobody listens yet: what the player sees comes after its board
    /// (docs/entwuerfe/LaufwerkUebernahme.dc.html); until then the games simply stand as installed.
    var onTaken: (Taken) -> Void = { _ in }
    /// Everything taken over since Nightforge started.
    private(set) var history: [Taken] = []

    /// A look is wanted: at the start, and whenever a drive is plugged in.
    private var asked = true
    /// Something on a drive couldn't be taken at the last look.
    private var waited = false
    private var last: DriveTakeoverRules.State?
    private var stateLooked = Date.distantPast
    private var looking = false
    /// A look that failed somewhere is made again: when, and how often still.
    private var retryAt: Date?
    private var retriesLeft = DriveTakeoverRules.retries
    /// Epic games offered to legendary, by folder, and how often.
    private var epicTries: [String: Int] = [:]

    /// A drive was plugged in: its games are looked at the next time round.
    func ask() {
        asked = true
        retriesLeft = DriveTakeoverRules.retries
        epicTries = [:]
    }

    /// One look, from the loop that watches the running games – so it's known what runs. Without a
    /// reason to look it ends at its first lines; with something waiting it compares a few facts
    /// every ten seconds.
    func look(_ model: LibraryModel) {
        // Nightforge itself, or a program in a home of its own: a test series in the player's home takes nothing over.
        guard GameLog.writes, !looking, model.lastScan != nil else { return }
        if let retryAt, Date() >= retryAt {
            self.retryAt = nil
            asked = true
        }
        guard asked || (waited && Date().timeIntervalSince(stateLooked) >= 10) else { return }
        stateLooked = Date()
        let state = model.takeoverState
        guard DriveTakeoverRules.due(asked: asked, waited: waited, state: state, last: last) else { return }
        asked = false
        last = state
        looking = true
        Task {
            waited = await run(model)
            looking = false
        }
    }

    /// Looks at every drive plugged in that holds Nightforge's folder. True when something there still waits.
    private func run(_ model: LibraryModel) async -> Bool {
        let drives = await Engine.offMain { Self.drives() }
        var waits = false
        var failed = false
        for drive in drives {
            let contents = await Engine.offMain { DriveContents.read(drive: drive.url) }
            guard !contents.isEmpty else { continue }
            var finds = DriveFinds.look(drive: drive.url, contents: contents, known: await model.knownInstalls())
            finds.epic.removeAll { epicTries[$0.folder.path, default: 0] >= DriveTakeoverRules.epicTries }
            if !finds.waiting.isEmpty {
                waits = true
                GameLog.note("Drive takeover: on \(drive.name), \(Self.summary(finds.waiting))")
            }
            guard !finds.isEmpty else { continue }
            // Never while a game, a download or a move is under way: Steam stops for its list, and
            // legendary does one thing at a time.
            guard !model.takeoverBusy else {
                waits = true
                continue
            }
            let result = await take(finds, from: drive, model)
            if result.failed { failed = true }
            if result.games.count < finds.count { waits = true }
            guard !result.games.isEmpty else { continue }
            let taken = Taken(drive: drive.name, games: result.games)
            GameLog.note("Drive takeover: \(taken.games.count) game(s) on \(drive.name) are back without a download: "
                + taken.games.map { "\($0.name) (\($0.provider.label))" }.joined(separator: ", "))
            history.append(taken)
            model.reload(quiet: true)
            onTaken(taken)
        }
        if failed, retriesLeft > 0 {
            retriesLeft -= 1
            retryAt = Date().addingTimeInterval(DriveTakeoverRules.retryAfter)
        }
        return waits
    }

    /// The drives looked at: those games can go on (not read-only, not FAT32 – games couldn't run from
    /// such a drive either) that hold Nightforge's folder. In a home of its own (a test,
    /// MacSteam.isTestHome) only disk images count and never a real drive: a test takes nothing of the
    /// player's, and a drive built for it in a disk image is seen.
    nonisolated static func drives(testHome: Bool = MacSteam.isTestHome) -> [ExternalDrive] {
        let candidates: [ExternalDrive]
        if testHome {
            let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
            candidates = volumes.compactMap { ExternalDrive.at($0) }.filter { ExternalDrive.isDiskImage($0.url) }
        } else {
            candidates = ExternalDrive.connected()
        }
        return candidates.filter { $0.hasLibrary && $0.check.allowed }
    }

    /// What waits, for the log: "3 Steam game(s) wait for Steam to be set up, 2 Epic game(s) for the sign-in".
    nonisolated static func summary(_ waiting: [DriveFinds.Waiting]) -> String {
        func count(_ reason: DriveFinds.Wait, _ provider: Provider) -> Int { waiting.filter { $0.reason == reason && $0.provider == provider }.count }
        var parts: [String] = []
        if count(.steamNotSetUp, .steam) > 0 { parts.append("\(count(.steamNotSetUp, .steam)) Steam game(s) wait for their Steam to be set up") }
        for provider in [Provider.epic, .gog] {
            if count(.notConnected, provider) > 0 { parts.append("\(count(.notConnected, provider)) \(provider.label) game(s) wait for the sign-in") }
            if count(.notOwned, provider) > 0 { parts.append("\(count(.notOwned, provider)) folder(s) are no \(provider.label) game of this account") }
        }
        return parts.joined(separator: ", ")
    }

    /// Takes over what `finds` names, store by store. What doesn't work stays as it was – not installed –
    /// and is said in the log.
    private func take(_ finds: DriveFinds, from drive: ExternalDrive, _ model: LibraryModel) async -> (games: [TakenGame], failed: Bool) {
        var games: [TakenGame] = []
        var failed = false
        if !finds.windowsSteam.isEmpty {
            do {
                try await model.takeOverSteamLibrary(on: drive.url)
                games += finds.windowsSteam.map { TakenGame(name: $0.name, provider: .steam, platform: .windows) }
            } catch {
                failed = true
                GameLog.note("Drive takeover: Steam's library on \(drive.name) wasn't added: \(error.localizedDescription)")
            }
        }
        if !finds.macSteam.isEmpty {
            do {
                try await model.takeOverMacSteamLibrary(on: drive.url)
                games += finds.macSteam.map { TakenGame(name: $0.name, provider: .steam, platform: .mac) }
            } catch {
                failed = true
                GameLog.note("Drive takeover: Steam for Mac's library on \(drive.name) wasn't added: \(error.localizedDescription)")
            }
        }
        let base = DriveLibrary.gog(on: drive.url)
        for found in finds.gog {
            let folder = base.appendingPathComponent(found.folder, isDirectory: true)
            let size = await Engine.offMain { LibraryScanner.folderSize(folder) }
            if model.gog.adopt(found, folder: folder, size: size) {
                games.append(TakenGame(name: found.title, provider: .gog, platform: found.platform))
            }
        }
        for find in finds.epic {
            // The player started something meanwhile: the rest waits for the next look.
            guard !model.takeoverBusy else { break }
            switch await model.epic.adopt(find) {
            case .taken:
                games.append(TakenGame(name: find.title, provider: .epic, platform: .windows))
            case .incomplete:
                epicTries[find.folder.path] = DriveTakeoverRules.epicTries
                GameLog.note("Drive takeover: \(find.title) on \(drive.name) isn't all there, it stays not installed")
            case .refused(let reason):
                epicTries[find.folder.path, default: 0] += 1
                failed = true
                GameLog.note("Drive takeover: legendary didn't take \(find.title) on \(drive.name): \(reason)")
            }
        }
        return (games, failed)
    }
}

extension LibraryModel {
    /// From the loop that watches the running games: takes over the games on a drive when a look is due.
    func lookAtDrives() {
        DriveTakeover.shared.look(self)
    }

    /// Whether a Steam's list of libraries (their steamapps folders) has this one.
    nonisolated static func listHas(_ steamapps: URL, in libraries: [URL]) -> Bool {
        let path = steamapps.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        return libraries.contains { $0.resolvingSymlinksInPath().standardizedFileURL.path.lowercased() == path }
    }

    /// Something is under way that taking games over would disturb – or be disturbed by: a game (Steam
    /// stops for its list), a download in any store, a move, an uninstall, the first setup, a game test.
    var takeoverBusy: Bool {
        gameUnderWay || awaitingSteam || launchNeedsConfirmation || macSteamBusy || move != nil || uninstallingID != nil
            || !downloads.isEmpty || epic.isBusy || gog.isBusy || GameTest.active || setup.isActive
    }

    /// The few facts another look depends on (DriveTakeoverRules.due).
    var takeoverState: DriveTakeoverRules.State {
        DriveTakeoverRules.State(busy: takeoverBusy, windowsSteam: SetupModel.isComplete,
                                 macSteam: MacSteam.isInstalled && MacSteam.hasSignedIn,
                                 macSteamOpen: MacSteam.isRunning && !MacSteam.startedByNightforge,
                                 epicSignedIn: epic.isConnected && epic.isSignedIn, epicGames: epic.catalog.games.count,
                                 gogConnected: gog.isConnected, gogGames: gog.catalog.games.count)
    }

    /// What Nightforge has on the Mac, for DriveFinds.look: each Steam's list of libraries once that
    /// Steam is set up and signed in, and what Epic and GOG know once they're connected.
    func knownInstalls() async -> KnownInstalls {
        let windows = SetupModel.isComplete
        let mac = MacSteam.isInstalled && MacSteam.hasSignedIn
        let lists = await Engine.offMain {
            (windows: windows ? LibraryScanner.libraryFolders(steamRoot: Engine.steamRoot, bottle: Engine.bottle) : nil,
             mac: mac ? LibraryScanner.libraryFolders(steamRoot: MacSteam.root, bottle: MacSteam.bottle) : nil)
        }
        return KnownInstalls(windowsSteamLibraries: lists.windows, macSteamLibraries: lists.mac,
                             epic: epic.knownInstalls(), gog: gog.knownInstalls())
    }

    /// Nightforge's Windows Steam learns the library on `drive`, with the games in it. Steam writes its
    /// own list over any change when it quits, so it's stopped for it and started again if it ran –
    /// queued like every other start of Steam, so none runs into it.
    func takeOverSteamLibrary(on drive: URL) async throws {
        let previous = steamStartup
        let work = Task { () -> Error? in
            await previous?.value
            do {
                try await self.addSteamLibrary(on: drive)
                return nil
            } catch {
                return error
            }
        }
        steamStartup = Task { _ = await work.value }
        if let error = await work.value { throw error }
    }

    private func addSteamLibrary(on drive: URL) async throws {
        // Something began while this waited its turn.
        guard !takeoverBusy else { throw DriveError.busy("a game, a download or a move is under way") }
        guard let wine = await Engine.installedWine() else { throw DriveError.steamNotKnown }
        let wasRunning = Engine.isSteamRunning
        try await Engine.stopSteam(wine, endWait: Engine.filesEndWait)
        do {
            // Asked a few times: a Steam a moment from its end is still listed (Engine.steamStillThere).
            if let still = await Engine.steamStillThere() { throw still }
            let library = DriveLibrary.windowsSteam(on: drive)
            try await Engine.offMain {
                try SteamLibraries.ensure(library: library, path: DriveLibrary.windowsPath(of: library), steamRoot: Engine.steamRoot,
                                          rootPath: Engine.windowsPath(of: Engine.steamRoot), bottle: Engine.bottle)
            }
        } catch {
            if wasRunning { try? await Engine.restartSteamInBackground(wine) }
            throw error
        }
        if wasRunning { try? await Engine.restartSteamInBackground(wine) }
    }

    /// The same for Steam for Mac. One Nightforge started comes back hidden as it was; one the player
    /// has open themselves isn't closed for this – the library waits until it's quit.
    func takeOverMacSteamLibrary(on drive: URL) async throws {
        guard !takeoverBusy else { throw DriveError.busy("a game, a download or a move is under way") }
        let wasRunning = MacSteam.isRunning
        if wasRunning, !MacSteam.startedByNightforge { throw DriveError.busy("Steam for Mac is open") }
        if wasRunning { await MacSteam.quit() }
        defer {
            if wasRunning {
                MacSteam.start()
                MacSteam.startedByNightforge = true
            }
        }
        if let still = await Engine.steamStillThere(running: { MacSteam.isRunning }) { throw still }
        let library = DriveLibrary.macSteam(on: drive)
        let root = MacSteam.root
        try await Engine.offMain {
            try SteamLibraries.ensure(library: library, path: library.path, steamRoot: root, rootPath: root.path, bottle: MacSteam.bottle)
        }
    }
}
