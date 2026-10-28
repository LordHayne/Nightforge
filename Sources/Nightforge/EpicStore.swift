import Foundation

/// An Epic game as Nightforge keeps it between starts: what the library looked like last time, so
/// it shows (and plays) at once and offline.
struct EpicGame: Codable, Equatable {
    let appName: String
    let title: String
    var namespace = ""
    /// The folder it installs into under `Legendary.gamesDir` (Epic's "FolderName").
    var folder = ""
    /// Portrait cover, wide hero art and the logo (Epic's DieselGameBoxTall, DieselGameBox, DieselGameBoxLogo).
    var cover: URL?
    var hero: URL?
    var logo: URL?
    /// Epic keeps its saves in the cloud.
    var cloudSaves = false
}

/// What Nightforge knows about the library between starts.
struct EpicLibrary: Codable, Equatable {
    var games: [EpicGame] = []
    /// When Epic was last asked successfully.
    var loaded: Date?

    /// `legendary list --json`: one object per game with its catalog data under "metadata". Games
    /// another launcher runs (EA app, Ubisoft Connect), programs (Discord: "software", no "games")
    /// and extras that aren't a game of their own ("digitalextras") are left out.
    static func games(fromList json: Data) -> [EpicGame]? {
        guard let items = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let appName = item["app_name"] as? String, GameID.isPlain(appName),
                  let title = item["app_title"] as? String, !title.isEmpty
            else { return nil }
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let attributes = metadata["customAttributes"] as? [String: Any] ?? [:]
            func attribute(_ name: String) -> String? { (attributes[name] as? [String: Any])?["value"] as? String }
            if attribute("ThirdPartyManagedApp") != nil || attribute("ThirdPartyManagedProvider") != nil { return nil }
            let categories = Set((metadata["categories"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
            if !categories.isEmpty && (!categories.contains("games") || categories.contains("digitalextras")) { return nil }
            let images = (metadata["keyImages"] as? [[String: Any]] ?? []).reduce(into: [String: URL]()) { found, image in
                guard let type = image["type"] as? String, found[type] == nil,
                      let url = (image["url"] as? String).flatMap(URL.init(string:)), url.scheme == "https" else { return }
                found[type] = url
            }
            var game = EpicGame(appName: appName, title: title)
            game.namespace = metadata["namespace"] as? String ?? ""
            let folder = attribute("FolderName") ?? appName
            game.folder = Self.isFolderName(folder) ? folder : appName
            game.cover = images["DieselGameBoxTall"] ?? images["OfferImageTall"]
            game.hero = images["DieselGameBox"] ?? images["OfferImageWide"]
            game.logo = images["DieselGameBoxLogo"]
            game.cloudSaves = attribute("CloudSaveFolder") != nil
            return game
        }
    }

    /// A folder legendary may create under the games folder: one level, no way out of it.
    static func isFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }
}

/// An installed Epic game, from legendary's installed.json.
struct EpicInstall: Equatable {
    let appName: String
    let path: URL
    var executable = ""
    var size: Int64 = 0
    var version = ""
    var canRunOffline = false

    static func all(fromJSON json: Data) -> [String: EpicInstall] {
        guard let items = try? JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] else { return [:] }
        var result: [String: EpicInstall] = [:]
        for (appName, item) in items where item["is_dlc"] as? Bool != true {
            guard let path = item["install_path"] as? String, path.hasPrefix("/") else { continue }
            var install = EpicInstall(appName: appName, path: URL(fileURLWithPath: path, isDirectory: true))
            install.executable = item["executable"] as? String ?? ""
            install.size = (item["install_size"] as? NSNumber)?.int64Value ?? 0
            install.version = item["version"] as? String ?? ""
            install.canRunOffline = item["can_run_offline"] as? Bool ?? false
            result[appName] = install
        }
        return result
    }

    /// The newest build Epic has for each game, from legendary's assets.json (updated with the library).
    static func latestVersions(fromAssets json: Data) -> [String: String] {
        guard let platforms = try? JSONSerialization.jsonObject(with: json) as? [String: [[String: Any]]] else { return [:] }
        var versions: [String: String] = [:]
        for asset in platforms["Windows"] ?? [] {
            if let app = asset["app_name"] as? String, let build = asset["build_version"] as? String { versions[app] = build }
        }
        return versions
    }
}

/// Play time Nightforge counts itself for Epic games (Epic's own isn't at hand offline).
struct EpicPlayTime: Codable, Equatable {
    var lastPlayed: Date?
    var minutes = 0
}

/// Epic Games (7.2): signed in once in Epic's own sign-in page, its library stays on the Mac and
/// is brought up to date in the background; Nightforge downloads, updates, starts and removes the
/// games itself through legendary – no Epic launcher.
@MainActor
final class EpicStore: ObservableObject, StoreProvider {
    let provider = Provider.epic
    @Published private(set) var sync = StoreSync()
    /// The sign-in page is open: the Stores tab says what to do there.
    @Published var connecting = false
    @Published private(set) var catalog = EpicLibrary()
    /// Something to tell the library (a download is done or failed, the list changed).
    var changed: () -> Void = {}
    /// A download that stopped by itself, with legendary's reason.
    var downloadFailed: (String, String) -> Void = { _, _ in }

    private var downloads: [String: Process] = [:]
    /// Downloads whose legendary is starting up: a look at the library meanwhile mustn't start it twice.
    private var starting: Set<String> = []
    /// Downloads asked for: they carry on after Nightforge was quit or the Mac restarted.
    private var wanted: Set<String> = []
    private var playTimes: [String: EpicPlayTime] = [:]
    /// Anti-cheat by catalog namespace (profiles.json "epic.<namespace>").
    private var antiCheat: [String: AntiCheatBlock] = [:]
    private var loadedFromDisk = false

    private static var folder: URL { Engine.supportDir.appendingPathComponent("Epic", isDirectory: true) }
    private static var libraryFile: URL { folder.appendingPathComponent("library.json") }
    private static var wantedFile: URL { folder.appendingPathComponent("downloads.json") }
    private static var playTimeFile: URL { folder.appendingPathComponent("playtime.json") }
    private static var userFile: URL { Legendary.configDir.appendingPathComponent("user.json") }
    /// The player connected Epic (until they disconnect). Kept apart from legendary's sign-in, which
    /// legendary drops when Epic ends it: the games mustn't go with it.
    private static var accountFile: URL { folder.appendingPathComponent("account.json") }

    /// Connected in Settings › Stores – also while Epic has signed the player out.
    var isConnected: Bool { FileManager.default.fileExists(atPath: Self.accountFile.path) }

    /// legendary holds Epic's sign-in: the library can be asked for and games get their sign-in code.
    var isSignedIn: Bool { FileManager.default.fileExists(atPath: Self.userFile.path) }

    /// The Epic account's name, as Epic shows it.
    var accountName: String? {
        for file in [Self.userFile, Self.accountFile] {
            if let data = try? Data(contentsOf: file),
               let user = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = user["displayName"] as? String { return name }
        }
        return nil
    }

    private func loadFromDisk() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Self.libraryFile), let stored = try? decoder.decode(EpicLibrary.self, from: data) {
            catalog = stored
            sync.lastSuccess = stored.loaded
        }
        if let data = try? Data(contentsOf: Self.wantedFile), let stored = try? decoder.decode([String].self, from: data) {
            wanted = Set(stored)
        }
        if let data = try? Data(contentsOf: Self.playTimeFile), let stored = try? decoder.decode([String: EpicPlayTime].self, from: data) {
            playTimes = stored
        }
    }

    private func save<T: Encodable>(_ value: T, to file: URL) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: - Library

    func library() async -> [Game] {
        loadFromDisk()
        guard isConnected else { return [] }
        antiCheat = await ProfileStore.shared.epicAntiCheatBlocks()
        let config = Legendary.configDir
        let (installed, latest) = await Engine.offMain {
            (EpicInstall.all(fromJSON: (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data()),
             EpicInstall.latestVersions(fromAssets: (try? Data(contentsOf: config.appendingPathComponent("assets.json"))) ?? Data()))
        }
        let running = await Engine.offMain { Self.runningDownloads() }
        resumeDownloads(installed: installed, running: running)
        let wanted = self.wanted
        let progress = await Engine.offMain {
            Dictionary(uniqueKeysWithValues: wanted.map { ($0, Legendary.progress(inLog: Self.logText(for: $0))) })
        }
        var games: [Game] = []
        var listed = Set<String>()
        for entry in catalog.games {
            listed.insert(entry.appName)
            games.append(game(entry, install: installed[entry.appName], latest: latest[entry.appName],
                              downloading: wanted.contains(entry.appName) ? progress[entry.appName] : nil))
        }
        // Installed but not in the list Nightforge has (it was never loaded here): still there.
        for (appName, install) in installed where !listed.contains(appName) {
            games.append(game(EpicGame(appName: appName, title: install.path.lastPathComponent, folder: install.path.lastPathComponent),
                              install: install, latest: latest[appName], downloading: nil))
        }
        return games
    }

    private func game(_ entry: EpicGame, install: EpicInstall?, latest: String?, downloading: Legendary.Progress?) -> Game {
        let folder = install?.path ?? Legendary.gamesDir.appendingPathComponent(entry.folder, isDirectory: true)
        // While it downloads: what the download comes to, which its progress is a share of.
        let isDownloading = downloading != nil && (install == nil || downloads[entry.appName] != nil)
        let size = isDownloading ? downloading?.downloadSize ?? install?.size ?? 0 : install?.size ?? 0
        var game = Game(gameID: .epic(entry.appName), name: entry.title, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                        steamExeWindowsPath: "", installDir: folder, sizeOnDisk: size,
                        lastPlayed: playTimes[entry.appName]?.lastPlayed, playtimeMinutes: playTimes[entry.appName]?.minutes)
        game.installDirName = folder.lastPathComponent
        if isDownloading, let downloading {
            game.install = .downloading(downloading.fraction)
        } else if let install {
            game.install = .installed
            game.onlineOnly = !install.canRunOffline  // Epic's own say on offline play
            if let latest, !install.version.isEmpty, latest != install.version { game.pendingUpdate = 0 }
        } else {
            game.install = .notInstalled
        }
        if let block = antiCheat[entry.namespace], !block.onlineOnly { game.antiCheatBlock = block }
        game.art = StoreArt(cover: entry.cover, hero: entry.hero, logo: entry.logo)
        return game
    }

    /// Asks Epic for the library (signed in through legendary). On failure the games from last
    /// time stay, and `sync` says why and since when.
    func refresh() async {
        loadFromDisk()
        guard isConnected, sync.state != .syncing else { return }
        guard isSignedIn else {
            sync = StoreSync(state: .signedOut, lastSuccess: catalog.loaded)
            changed()
            return
        }
        sync.state = .syncing
        do {
            let result = try await Legendary.run(["list", "--json", "--platform", "Windows"], timeout: 180)
            guard result.status == 0, let games = EpicLibrary.games(fromList: result.output) else {
                throw EpicError.failed(Self.reachError(result.log))
            }
            catalog = EpicLibrary(games: games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                                  loaded: Date())
            save(catalog, to: Self.libraryFile)
            sync = StoreSync(state: .ok, lastSuccess: catalog.loaded)
        } catch {
            // legendary drops a sign-in Epic turned down; anything else is Epic out of reach.
            sync = StoreSync(state: isSignedIn ? .failed(L10n.t("Couldn't reach Epic Games")) : .signedOut, lastSuccess: catalog.loaded)
        }
        changed()
    }

    private static func reachError(_ log: String) -> String {
        log.split(whereSeparator: \.isNewline).last { $0.contains("ERROR") }.map(String.init) ?? "no answer"
    }

    // MARK: - Signing in

    /// The code Epic's sign-in page ends with goes to legendary, which swaps it for its tokens.
    func connect(code: String) async throws {
        let result = try await Legendary.run(["auth", "--code", code], timeout: 60)
        guard result.status == 0, isSignedIn else { throw EpicError.signInFailed(result.error) }
        let account = ["displayName": accountName ?? "", "connected": ISO8601DateFormatter().string(from: Date())]
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: account).write(to: Self.accountFile, options: .atomic)
        objectWillChange.send()
        await refresh()
    }

    /// Signs out (legendary forgets the tokens). Installed games stay on the Mac and come back
    /// with the next sign-in.
    func disconnect() async {
        for process in downloads.values.map({ $0 }) + updates.values where process.isRunning { process.interrupt() }
        _ = try? await Legendary.run(["auth", "--delete"], timeout: 30)
        try? FileManager.default.removeItem(at: Self.userFile)
        try? FileManager.default.removeItem(at: Self.accountFile)
        sync = StoreSync(state: .ok, lastSuccess: nil)
        objectWillChange.send()
        changed()
    }

    // MARK: - Downloads

    func install(_ game: Game, context: StoreContext) async throws {
        loadFromDisk()
        let appName = game.gameID.id
        guard downloads[appName] == nil, !starting.contains(appName) else { return }
        try FileManager.default.createDirectory(at: Legendary.gamesDir, withIntermediateDirectories: true)
        wanted.insert(appName)
        save(wanted.sorted(), to: Self.wantedFile)
        do {
            try await startDownload(appName)
        } catch {
            // Didn't start (legendary not at hand): nothing to carry on with later.
            wanted.remove(appName)
            save(wanted.sorted(), to: Self.wantedFile)
            throw error
        }
        context.requested()
    }

    private func startDownload(_ appName: String) async throws {
        starting.insert(appName)
        defer { starting.remove(appName) }
        let process = try await Legendary.start(["install", appName, "--base-path", Legendary.gamesDir.path,
                                                 "--platform", "Windows", "--skip-sdl", "--skip-dlcs", "-y"],
                                                log: Legendary.log(for: appName))
        downloads[appName] = process
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.downloadEnded(appName, status: status) }
        }
    }

    private func downloadEnded(_ appName: String, status: Int32) {
        downloads[appName] = nil
        guard wanted.contains(appName) else { return }  // cancelled
        let progress = Legendary.progress(inLog: Self.logText(for: appName))
        wanted.remove(appName)
        save(wanted.sorted(), to: Self.wantedFile)
        if !progress.finished || status != 0 {
            let title = catalog.games.first { $0.appName == appName }?.title ?? appName
            downloadFailed(title, progress.failure ?? L10n.t("legendary stopped (code %d)", status))
        }
        changed()
    }

    /// legendary downloads still running from an earlier Nightforge, by app name.
    nonisolated private static func runningDownloads() -> Set<String> {
        let root = ComponentStore.shared.root.appendingPathComponent(Legendary.componentID, isDirectory: true)
        return Set(Engine.ownProcesses(under: root).compactMap { process in
            let words = process.command.split(separator: " ")
            guard let index = words.firstIndex(of: "install"), index + 1 < words.count else { return nil }
            return String(words[index + 1])
        })
    }

    /// A download asked for that isn't running (Nightforge or the Mac were restarted) carries on:
    /// legendary picks it up where it stopped.
    private func resumeDownloads(installed: [String: EpicInstall], running: Set<String>) {
        for appName in wanted where downloads[appName] == nil && !starting.contains(appName) {
            if installed[appName] != nil && !running.contains(appName) {
                wanted.remove(appName)  // done meanwhile
                save(wanted.sorted(), to: Self.wantedFile)
            } else if !running.contains(appName) {
                starting.insert(appName)
                Task { try? await startDownload(appName) }
            }
        }
    }

    nonisolated static func logText(for appName: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: Legendary.log(for: appName)) else { return "" }
        defer { try? handle.close() }
        // The sizes come first, the progress last: the start and the end are enough.
        let head = (try? handle.read(upToCount: 16_384)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
        let tail = (try? handle.readToEnd()) ?? Data()
        return String(decoding: head, as: UTF8.self) + "\n" + String(decoding: tail, as: UTF8.self)
    }

    /// A download is stopped and its files go; an installed game is removed by legendary.
    func uninstall(_ game: Game) async throws {
        loadFromDisk()
        let appName = game.gameID.id
        if wanted.contains(appName) || downloads[appName] != nil {
            wanted.remove(appName)
            save(wanted.sorted(), to: Self.wantedFile)
            if let process = downloads.removeValue(forKey: appName) {
                process.terminate()
                await Engine.offMain { process.waitUntilExit() }
            }
            for pid in Engine.ownProcesses(under: ComponentStore.shared.root.appendingPathComponent(Legendary.componentID))
                .filter({ $0.command.contains(" install \(appName) ") }).map(\.pid) {
                kill(pid, SIGTERM)
            }
        }
        let installedFile = Legendary.configDir.appendingPathComponent("installed.json")
        let installed = EpicInstall.all(fromJSON: (try? Data(contentsOf: installedFile)) ?? Data())
        if installed[appName] != nil {
            let result = try await Legendary.run(["uninstall", appName, "-y", "--skip-uninstaller"], timeout: 600)
            guard result.status == 0 else { throw EpicError.failed(result.error ?? L10n.t("legendary stopped (code %d)", result.status)) }
        } else {
            try? FileManager.default.removeItem(at: Legendary.configDir.appendingPathComponent("tmp/\(appName).resume"))
        }
        // legendary removes the game's own files; what's left is a cancelled download, or the settings
        // files Nightforge writes beside the game (dxmt.conf …). Only inside the games folder.
        let folder = game.installDir.standardizedFileURL
        if folder.deletingLastPathComponent().path == Legendary.gamesDir.standardizedFileURL.path {
            try? FileManager.default.removeItem(at: folder)
        }
        try? FileManager.default.removeItem(at: Legendary.log(for: appName))
    }

    // MARK: - Playing

    /// What the game starts with: Epic's parameters with a fresh sign-in code, or – offline, or when
    /// Epic can't be reached – without one, as Epic's launcher does offline.
    func launchCommand(for game: Game) async throws -> Legendary.LaunchCommand {
        let appName = game.gameID.id
        let program = try await Legendary.program()
        let language = ["--language", Self.gameLanguage()]
        let online = try await Legendary.run(["launch", appName, "--json", "--no-wine", "--skip-version-check"] + language,
                                             program: program, timeout: 60)
        if online.status == 0, let command = Legendary.launchCommand(fromJSON: online.output) { return command }
        let offline = try await Legendary.run(["launch", appName, "--json", "--no-wine", "--offline"] + language,
                                              program: program, timeout: 30)
        if offline.status == 0, let command = Legendary.launchCommand(fromJSON: offline.output) { return command }
        throw EpicError.failed(online.error ?? offline.error ?? L10n.t("Epic Games didn't give the launch details for %@.", game.name))
    }

    // MARK: - Updates

    /// How the update before a start went ("Update & Play").
    enum UpdateOutcome: Equatable {
        /// Up to date now, or legendary found nothing to fetch.
        case updated
        /// Nothing was fetched, so the version on the Mac starts – as Epic's launcher does offline.
        case skipped(UpdateSkip)
        /// It stopped once it had begun, or there's no room for it: the game may be half updated, and
        /// the next try carries on where this one stopped.
        case failed(String)
    }

    enum UpdateSkip: Equatable {
        /// Epic out of reach (offline, no answer).
        case offline
        /// Another Epic download has legendary, which installs one thing at a time.
        case busy
    }

    /// Updates running before a start, by app name.
    private var updates: [String: Process] = [:]

    /// Brings an installed game up to date before it starts, like Steam's "Update & Play": legendary
    /// fetches only what changed and carries on where an earlier try stopped. `progress` hears how
    /// far it is, from legendary's log.
    func update(_ game: Game, progress: @escaping @MainActor (Double?) -> Void) async -> UpdateOutcome {
        loadFromDisk()
        let appName = game.gameID.id
        let running = await Engine.offMain { Self.runningDownloads() }
        // An update an earlier Nightforge started is still going: follow it instead of starting a second.
        let following = running.contains(appName)
        if !following && (!downloads.isEmpty || !starting.isEmpty || !running.isEmpty) { return .skipped(.busy) }
        var process: Process?
        if !following {
            do {
                process = try await Legendary.start(["install", appName, "--update-only", "--skip-sdl", "--skip-dlcs", "-y"],
                                                    log: Legendary.log(for: appName))
            } catch {
                return .skipped(.offline)
            }
        }
        updates[appName] = process
        defer { updates[appName] = nil }
        var silent = 0
        while true {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                process?.interrupt()  // legendary keeps what it has for next time
                return .skipped(.offline)
            }
            let state = await Engine.offMain { Legendary.progress(inLog: Self.logText(for: appName)) }
            progress(state.fraction)
            let ended: Bool
            if let process {
                ended = !process.isRunning
            } else {
                ended = !(await Engine.offMain { Self.runningDownloads() }).contains(appName)
            }
            if ended { return Self.updateOutcome(state, status: process?.terminationStatus) }
            // Not a word from Epic for 90 s (a network that doesn't answer): the game starts as it is.
            silent = state.fraction == nil ? silent + 1 : 0
            if silent >= 90 {
                process?.interrupt()
                return .skipped(.offline)
            }
        }
    }

    /// What an update's log says once legendary has ended.
    nonisolated static func updateOutcome(_ state: Legendary.Progress, status: Int32?) -> UpdateOutcome {
        if state.finished { return .updated }
        let reason = state.failure ?? L10n.t("legendary stopped (code %d)", status ?? -1)
        // Nothing fetched yet: the game's files are as they were, so it starts with them – unless
        // there's no room for the update, which the player has to hear about.
        if state.fraction == nil && !reason.contains("disk space") {
            return reason.contains("lock") ? .skipped(.busy) : .skipped(.offline)
        }
        return .failed(reason)
    }

    /// The Mac's language for the game ("de"), as Epic's launcher hands it over (-epiclocale):
    /// legendary would otherwise say "en", not knowing the Mac's settings.
    nonisolated static func gameLanguage(preferred: [String] = Locale.preferredLanguages) -> String {
        guard let first = preferred.first else { return "en" }
        let code = Locale(identifier: first).language.languageCode?.identifier ?? "en"
        return code.allSatisfy(\.isLetter) && (2...3).contains(code.count) ? code : "en"
    }

    /// Brings the cloud saves up to date: before playing the newer ones from Epic, afterwards this
    /// Mac's. legendary keeps whichever is newer and never overwrites a newer save with an older one.
    @discardableResult
    func syncSaves(_ game: Game, upload: Bool) async -> Bool {
        let appName = game.gameID.id
        guard isSignedIn, catalog.games.first(where: { $0.appName == appName })?.cloudSaves == true else { return false }
        let direction = upload ? "--skip-download" : "--skip-upload"
        let result = try? await Legendary.run(["sync-saves", appName, "-y", "--accept-path", direction], timeout: 300)
        return result?.status == 0
    }

    /// A session that ended: for "Continue playing" and the play time.
    func recordSession(_ game: Game, minutes: Int, endedAt: Date = Date()) {
        loadFromDisk()
        var time = playTimes[game.gameID.id] ?? EpicPlayTime()
        time.lastPlayed = endedAt
        time.minutes += max(minutes, 0)
        playTimes[game.gameID.id] = time
        save(playTimes, to: Self.playTimeFile)
    }

    func recordStart(_ game: Game, at date: Date = Date()) {
        loadFromDisk()
        var time = playTimes[game.gameID.id] ?? EpicPlayTime()
        time.lastPlayed = date
        playTimes[game.gameID.id] = time
        save(playTimes, to: Self.playTimeFile)
    }

    /// Whether the game may start without Epic (legendary's installed.json).
    nonisolated static func executable(of appName: String) -> String? {
        let file = Legendary.configDir.appendingPathComponent("installed.json")
        return EpicInstall.all(fromJSON: (try? Data(contentsOf: file)) ?? Data())[appName]?.executable
    }
}
