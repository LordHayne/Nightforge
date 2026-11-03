import AppKit

/// A game on its way to another drive ("Move to …" in Settings › Storage), shown with the downloads.
struct GameMove: Identifiable, Equatable {
    enum Phase: Equatable {
        /// Its Steam is being closed: Steam writes its list of libraries over any change when it quits.
        case stoppingSteam
        case copying
        /// Copied and checked: the store learns the new place, then the original goes.
        case finishing
    }

    let game: Game
    /// Where it goes, as the player reads it: the drive's name, or nil for the Mac.
    let drive: String?
    var phase = Phase.stoppingSteam
    var fraction: Double?
    /// Speed and time left, like a download's.
    var rate = DownloadRate()
    let progress: CopyProgress

    var id: String { game.id }

    static func == (a: GameMove, b: GameMove) -> Bool {
        a.game.id == b.game.id && a.phase == b.phase && a.fraction == b.fraction
    }
}

/// Where a game can move: a drive plugged in, or back to the Mac.
struct MoveTarget: Identifiable, Hashable {
    /// nil: the Mac.
    let choice: DriveChoice?
    /// The Mac's free space, when that's where it goes.
    var macFree: Int64 = 0
    var needed: Int64 = 0

    var id: String { choice?.id ?? "mac" }
    var usable: Bool { choice?.usable ?? (macFree >= needed) }
}

extension LibraryModel {
    // MARK: - Moving games between drives

    /// A game of this platform runs: a stopped Steam would cut it off (Windows games all share
    /// Nightforge's Wine session, Mac versions Steam for Mac).
    private func gameRunning(_ platform: Platform) -> Bool {
        allGames.contains { running[$0.id] != nil && $0.platform == platform }
    }

    /// "Move to …" can take the game now: installed through Nightforge's Steam, Steam for Mac, Epic
    /// or GOG, its files where they should be, and nothing running that its stopped Steam would end.
    func canMove(_ game: Game) -> Bool {
        guard move == nil, uninstallingID == nil, launchingID == nil, game.isInstalled, !isRunning(game),
              FileManager.default.fileExists(atPath: game.installDir.path)
        else { return false }
        switch (game.provider, game.platform) {
        case (.epic, _): return !epic.isBusy
        case (.gog, _): return !gog.isBusy  // no Steam to stop; gogdl mustn't be writing meanwhile
        case (_, .mac): return !gameRunning(.mac)
        default: return game.bottle.isBuiltIn && !gameRunning(.windows)
        }
    }

    /// Where it can go: back to the Mac when it's on a drive, and every drive plugged in besides the
    /// one it's on – those it fits on first.
    func moveTargets(for game: Game) -> [MoveTarget] {
        let current = DriveLibrary.drive(of: game.installDir)
        var targets = DriveChoice.options(ExternalDrive.connected(), size: game.sizeOnDisk, except: current)
            .map { MoveTarget(choice: $0) }
        if current != nil {
            let home = macLibrary(for: game)
            targets.insert(MoveTarget(choice: nil, macFree: ExternalDrive.free(at: home), needed: game.sizeOnDisk + SpaceCheck.macReserve), at: 0)
        }
        return targets
    }

    /// Where the game's store keeps its games on the Mac.
    private func macLibrary(for game: Game) -> URL {
        switch (game.provider, game.platform) {
        case (.epic, _): return Legendary.gamesDir
        case (.gog, _): return GOGDL.gamesDir(for: game.platform)
        case (_, .mac): return MacSteam.steamapps
        default: return Engine.steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        }
    }

    /// Settings › Storage's "Move to …": asks where, in the main window.
    func requestMove(_ game: Game) {
        guard canMove(game) else { return }
        pendingMove = game
    }

    /// Moves the game: its Steam stops for it (Steam for Mac, or Nightforge's Windows Steam), the
    /// files are copied and checked, the store is told, the original goes – and Steam starts again.
    /// The downloads panel shows how far it is.
    func startMove(_ game: Game, to target: MoveTarget) {
        pendingMove = nil
        guard canMove(game) else {
            errorMessage = L10n.t("%@ can't move right now – quit the game first, or wait until the download or the other move is done.", game.name)
            return
        }
        if let choice = target.choice {
            guard let drive = ExternalDrive.at(choice.drive.url) else {
                errorMessage = L10n.t("%@ isn't plugged in any more.", choice.drive.name)
                return
            }
            if let note = drive.check.note(drive.name), !drive.check.allowed {
                errorMessage = note
                return
            }
            guard drive.free >= choice.needed else {
                errorMessage = DriveError.notEnoughSpace(drive: drive.name, needed: choice.needed, free: drive.free).localizedDescription
                return
            }
        } else if ExternalDrive.free(at: macLibrary(for: game)) < target.needed {
            errorMessage = DriveError.notEnoughSpace(drive: L10n.t("Your Mac"), needed: target.needed,
                                                     free: ExternalDrive.free(at: macLibrary(for: game))).localizedDescription
            return
        }
        let progress = CopyProgress()
        move = GameMove(game: game, drive: target.choice?.drive.name, progress: progress)
        showingDownloads = true
        Task {
            // Once a second, and only a whole percent further: the library redraws with each change.
            let watch = Task {
                while !Task.isCancelled {
                    if move?.phase == .copying, let fraction = progress.fraction {
                        if fraction >= 1 {
                            move?.phase = .finishing
                        } else if Int(fraction * 100) != move?.fraction.map({ Int($0 * 100) }) {
                            move?.fraction = fraction
                            move?.rate.add(bytes: Double(progress.copied))
                        }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer {
                watch.cancel()
                move = nil
                if downloads.isEmpty { showingDownloads = false }
                reload(quiet: true)
            }
            do {
                let left = try await performMove(game, to: target, progress: progress)
                if !left.isEmpty {
                    errorMessage = L10n.t("%@ was moved, but its old folder couldn't be deleted completely: %@", game.name,
                                          left.map(\.path).joined(separator: ", "))
                } else if let drive = target.choice?.drive.name {
                    Toasts.shared.show(L10n.t("%@ is on %@ now", game.name, drive))
                } else {
                    Toasts.shared.show(L10n.t("%@ is back on your Mac", game.name))
                }
            } catch DriveError.cancelled {
                Toasts.shared.show(L10n.t("%@ stays where it was", game.name))
            } catch {
                errorMessage = L10n.t("%@ couldn't be moved: %@ It's still where it was and plays as before.", game.name, error.localizedDescription)
            }
        }
    }

    /// The downloads panel's Cancel: the copy stops, and the original stays as it was.
    func cancelMove() {
        guard move?.phase != .finishing else { return }
        move?.progress.cancel()
    }

    /// A start or download that has to wait for the move under way: the game itself, or one whose
    /// Steam is stopped meanwhile. Says so.
    func waitsForMove(_ game: Game) -> Bool {
        guard let move else { return false }
        let moving = move.game
        // legendary notes the moved game's place at the end and installs one thing at a time.
        let waits = game.holds(moving.id)
            || moving.provider == .steam && game.provider == .steam && game.platform == moving.platform
            || moving.provider == .epic && game.provider == .epic && !game.isInstalled
        if waits {
            Toasts.shared.show(game.holds(moving.id) ? L10n.t("%@ is moving – it plays once it's in its new place.", moving.name)
                               : moving.provider == .steam ? L10n.t("Steam is closed while %@ moves – a moment, please.", moving.name)
                               : L10n.t("%@ is moving – the download starts once it's done.", moving.name))
        }
        return waits
    }

    private func performMove(_ game: Game, to target: MoveTarget, progress: CopyProgress) async throws -> [URL] {
        let drive = target.choice?.drive.url
        switch (game.provider, game.platform) {
        case (.epic, _):
            let base = drive.map(DriveLibrary.epic(on:)) ?? Legendary.gamesDir
            let installed = (try? Data(contentsOf: Legendary.configDir.appendingPathComponent("installed.json"))) ?? Data()
            let program = try await Legendary.program()
            move?.phase = .copying
            return try await GameMover.moveEpicGame(folder: game.installDir, to: base, installedJSON: installed, progress: progress) { arguments in
                let result = try await Legendary.run(arguments, program: program)
                guard result.status == 0 else {
                    throw EpicError.failed(result.error ?? L10n.t("legendary stopped (code %d)", result.status))
                }
            }
        case (.gog, _):
            // gogdl keeps no list of where games are: Nightforge's own record learns the new place.
            let base = drive.map(DriveLibrary.gog(on:)) ?? GOGDL.gamesDir(for: game.platform)
            let to = base.appendingPathComponent(game.installDir.lastPathComponent, isDirectory: true)
            move?.phase = .copying
            return try await GameMover.move([GameMover.Part(from: game.installDir, to: to)], progress: progress) {
                gog.recordMove(game, to: to)
            }
        case (_, .mac):
            let wasRunning = MacSteam.isRunning, ours = MacSteam.startedByNightforge
            if wasRunning { await MacSteam.quit() }
            defer {
                if wasRunning {
                    MacSteam.start(visible: !ours)  // the player's own Steam comes back as they had it
                    MacSteam.startedByNightforge = ours
                }
            }
            guard !MacSteam.isRunning else { throw DriveError.steamStarted }
            var destination = MacSteam.steamapps
            if let drive {
                let library = DriveLibrary.macSteam(on: drive)
                let root = MacSteam.root
                try await Engine.offMain {
                    try SteamLibraries.ensure(library: library, path: library.path, steamRoot: root, rootPath: root.path, bottle: MacSteam.bottle)
                }
                destination = library.appendingPathComponent("steamapps", isDirectory: true)
            }
            move?.phase = .copying
            return try await GameMover.moveSteamGame(appID: game.appID, installDirName: game.installDirName,
                                                     from: game.installDir.deletingLastPathComponent().deletingLastPathComponent(),
                                                     to: destination, steamRoot: MacSteam.root, bottle: MacSteam.bottle,
                                                     progress: progress) { MacSteam.isRunning }
        default:
            guard let wine = await Engine.installedWine() else { throw DriveError.steamStarted }
            let wasRunning = Engine.isSteamRunning
            try await Engine.stopSteam(wine)
            do {
                guard !Engine.steamMayBeRunning else { throw DriveError.steamStarted }
                var destination = Engine.steamRoot.appendingPathComponent("steamapps", isDirectory: true)
                if let drive {
                    let library = DriveLibrary.windowsSteam(on: drive)
                    try await Engine.offMain {
                        try SteamLibraries.ensure(library: library, path: DriveLibrary.windowsPath(of: library), steamRoot: Engine.steamRoot,
                                                  rootPath: Engine.windowsPath(of: Engine.steamRoot), bottle: Engine.bottle)
                    }
                    destination = library.appendingPathComponent("steamapps", isDirectory: true)
                }
                move?.phase = .copying
                let left = try await GameMover.moveSteamGame(appID: game.appID, installDirName: game.installDirName,
                                                             from: game.installDir.deletingLastPathComponent().deletingLastPathComponent(),
                                                             to: destination, steamRoot: Engine.steamRoot, bottle: Engine.bottle,
                                                             progress: progress) { Engine.steamMayBeRunning }
                if wasRunning { try? await Engine.restartSteamInBackground(wine) }
                return left
            } catch {
                if wasRunning { try? await Engine.restartSteamInBackground(wine) }
                throw error
            }
        }
    }

    // MARK: - Downloads onto a drive

    /// Drives a download can go to instead of the Mac – for games of Nightforge's Steam, Steam for
    /// Mac, Epic and GOG (a CrossOver bottle's Steam keeps its own libraries).
    func driveChoices(for game: Game, needed: Int64) -> [DriveChoice] {
        guard game.provider != .steam || game.platform == .mac || game.bottle.isBuiltIn else { return [] }
        return DriveChoice.options(ExternalDrive.connected(), size: needed)
    }

    /// The space sheet's "Install on <drive>".
    func download(_ request: SpaceRequest, on choice: DriveChoice) {
        pendingSpace = nil
        // A moment may have passed: still plugged in, still room.
        guard let drive = ExternalDrive.at(choice.drive.url) else {
            errorMessage = L10n.t("%@ isn't plugged in any more.", choice.drive.name)
            return
        }
        guard DriveChoice(drive: drive, needed: choice.needed).usable else {
            errorMessage = drive.check.note(drive.name)
                ?? DriveError.notEnoughSpace(drive: drive.name, needed: choice.needed, free: drive.free).localizedDescription
            return
        }
        download(request.game, drive: drive.url)
    }

    /// The question where a download goes: the Mac.
    func downloadOnMac(_ request: SpaceRequest) {
        pendingSpace = nil
        download(request.game)
    }

    // MARK: - Drives plugged in and out

    /// A drive plugged in or out: the games on it can play again, or say to plug it in. Nightforge's
    /// Windows Steam looks at its libraries when it starts, so it starts again once nothing runs –
    /// for a drive with games for it.
    func watchDrives() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reload(quiet: true)
                    if name == NSWorkspace.didMountNotification, let volume, Engine.isSteamRunning, self.move == nil,
                       !SteamLibraries.installedApps(in: DriveLibrary.windowsSteam(on: volume).appendingPathComponent("steamapps")).isEmpty {
                        self.steam.restartWhenIdle = true
                    }
                }
            }
        }
    }
}

extension SteamStore {
    /// A download onto a drive: the drive's library goes into Steam's list first – with Steam
    /// stopped, which is why it needs nothing running the first time – then Steam is asked for the
    /// game there as usual.
    func install(_ game: Game, onDrive drive: URL, wine: URL, context: StoreContext) async throws {
        let library = DriveLibrary.windowsSteam(on: drive)
        let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
        let known = LibraryScanner.libraryFolders(steamRoot: Engine.steamRoot, bottle: Engine.bottle)
            .contains { $0.resolvingSymlinksInPath().path == steamapps.resolvingSymlinksInPath().path }
        if !known {
            guard !context.busy else {
                throw DriveError.busy(L10n.t("Steam restarts to set up %@ – quit the game first, then download again.", drive.lastPathComponent))
            }
            try await Engine.stopSteam(wine)
            guard !Engine.steamMayBeRunning else { throw DriveError.steamStarted }
            try await Engine.offMain {
                try SteamLibraries.ensure(library: library, path: DriveLibrary.windowsPath(of: library), steamRoot: Engine.steamRoot,
                                          rootPath: Engine.windowsPath(of: Engine.steamRoot), bottle: Engine.bottle)
            }
        }
        try Engine.requestDownload(appID: game.appID, name: game.name, installDir: game.installDirName, steamapps: steamapps)
        context.requested()
        if context.busy {
            restartWhenIdle = true
        } else {
            try await Engine.restartSteamInBackground(wine)
        }
    }
}

extension MacSteam {
    /// A Mac version onto a drive: like `download`, into Steam for Mac's library there, which goes
    /// into its list first – with Steam for Mac quit, and back as it was.
    static func download(appID: Int, name: String, installDir: String, onDrive drive: URL, macGameRunning: Bool) async throws {
        let library = DriveLibrary.macSteam(on: drive)
        let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
        let known = LibraryScanner.libraryFolders(steamRoot: root, bottle: bottle)
            .contains { $0.resolvingSymlinksInPath().path == steamapps.resolvingSymlinksInPath().path }
        if isRunning, macGameRunning {
            throw DriveError.busy(L10n.t("Steam for Mac restarts for the download to %@ – quit the game first, then download again.", drive.lastPathComponent))
        }
        let wasRunning = isRunning, ours = startedByNightforge
        if wasRunning { await quit() }
        if !known {
            guard !isRunning else { throw DriveError.steamStarted }
            let root = self.root
            try await Engine.offMain {
                try SteamLibraries.ensure(library: library, path: library.path, steamRoot: root, rootPath: root.path, bottle: MacSteam.bottle)
            }
        }
        try Engine.requestDownload(appID: appID, name: name, installDir: installDir, steamapps: steamapps)
        start(visible: wasRunning && !ours)
        if wasRunning { startedByNightforge = ours }
    }
}
