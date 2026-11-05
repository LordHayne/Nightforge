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
    /// Add-ons (DLCs) the player owns for it that come as files – they download with the game.
    /// Missing in a library.json from before add-ons were kept.
    var dlcs: [EpicDLC]?
}

/// An add-on the player owns for a game; legendary installs it into the game's folder.
struct EpicDLC: Codable, Equatable {
    let appName: String
    let title: String
}

/// What Nightforge knows about the library between starts.
struct EpicLibrary: Codable, Equatable {
    var games: [EpicGame] = []
    /// When Epic was last asked successfully.
    var loaded: Date?

    /// `legendary list --json`: one object per game with its catalog data under "metadata". Games
    /// another launcher runs (EA app, Ubisoft Connect), programs (Discord: "software", no "games")
    /// and extras that aren't a game of their own ("digitalextras") are left out. Each game's "dlcs"
    /// are the add-ons the player owns that have files (legendary lists only those); extras like
    /// soundtracks and art books aren't part of the game and stay out there too.
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
            game.dlcs = (item["dlcs"] as? [[String: Any]] ?? []).compactMap { dlc in
                guard let appName = dlc["app_name"] as? String, GameID.isPlain(appName),
                      let title = dlc["app_title"] as? String, !title.isEmpty else { return nil }
                let metadata = dlc["metadata"] as? [String: Any] ?? [:]
                let categories = (metadata["categories"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                return categories.contains("digitalextras") ? nil : EpicDLC(appName: appName, title: title)
            }
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

    /// The version of everything installed, add-ons included.
    static func versions(fromJSON json: Data) -> [String: String] {
        guard let items = try? JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] else { return [:] }
        return items.reduce(into: [:]) { versions, item in versions[item.key] = item.value["version"] as? String ?? "" }
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

/// What a game comes to before it's downloaded, from `legendary info --json` (legendary reads the
/// game's manifest from Epic): kept per build in sizes.json, so the game page and the space check
/// know it before the download starts.
struct EpicSize: Codable, Equatable {
    /// The build it was read for: a newer one is asked again.
    var version: String
    /// What legendary downloads (compressed), and what the game takes on disk.
    var download: Int64
    var install: Int64

    static func from(info json: Data) -> EpicSize? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let manifest = object["manifest"] as? [String: Any],
              let install = (manifest["disk_size"] as? NSNumber)?.int64Value, install >= 0
        else { return nil }
        let download = (manifest["download_size"] as? NSNumber)?.int64Value ?? install
        let version = manifest["build_version"] as? String ?? (object["game"] as? [String: Any])?["version"] as? String ?? ""
        return EpicSize(version: version, download: download, install: install)
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
final class EpicStore: ObservableObject, StoreProvider, AccountStore {
    let provider = Provider.epic
    @Published private(set) var sync = StoreSync()
    /// The sign-in page is open: the Stores tab says what to do there.
    @Published var connecting = false
    @Published private(set) var catalog = EpicLibrary() {
        didSet { gameOfAddOn = Self.addOnGames(catalog) }
    }
    /// Something to tell the library (a download is done or failed, the list changed).
    var changed: () -> Void = {}
    /// A download that stopped by itself: the game's or add-on's name, legendary's reason, and
    /// whether it was an add-on (its game is on the Mac then).
    var downloadFailed: (String, String, Bool) -> Void = { _, _, _ in }

    private var downloads: [String: DetachedProcess] = [:]
    /// Downloads whose legendary is starting up: a look at the library meanwhile mustn't start it twice.
    private var starting: Set<String> = []
    /// Downloads asked for, in line: games and their add-ons. legendary installs one thing at a time
    /// (it locks its list of what's installed), so they take turns, an add-on after its game. A part
    /// that's done stays until its game's whole download is, which shows as one. They carry on after
    /// Nightforge was quit or the Mac restarted.
    private var wanted: [String] = []
    /// Where a download goes when it isn't the Mac: the "Epic Games" folder on a drive, by app name.
    private var destinations: [String: String] = [:]
    /// Each add-on's game, by app name.
    private var gameOfAddOn: [String: String] = [:]
    private var playTimes: [String: EpicPlayTime] = [:]
    /// Sizes of games not on the Mac yet, by app name, and the newest build of each (assets.json).
    private var sizes: [String: EpicSize] = [:]
    private var latest: [String: String] = [:]
    /// Sizes being asked for, and when asking last failed (offline): not again for a few minutes.
    private var sizing: [String: Task<EpicSize?, Never>] = [:]
    private var sizeFailed: [String: Date] = [:]
    /// Anti-cheat by catalog namespace (profiles.json "epic.<namespace>").
    private var antiCheat: [String: AntiCheatBlock] = [:]
    private var loadedFromDisk = false
    private let profiles: ProfileStore

    /// `profiles`: where the anti-cheat entries come from; a test hands in its own list.
    init(profiles: ProfileStore = .shared) {
        self.profiles = profiles
    }

    private static var folder: URL { Engine.supportDir.appendingPathComponent("Epic", isDirectory: true) }
    private static var libraryFile: URL { folder.appendingPathComponent("library.json") }
    private static var wantedFile: URL { folder.appendingPathComponent("downloads.json") }
    private static var playTimeFile: URL { folder.appendingPathComponent("playtime.json") }
    private static var sizesFile: URL { folder.appendingPathComponent("sizes.json") }
    private static var destinationsFile: URL { folder.appendingPathComponent("destinations.json") }
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
            wanted = stored.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        if let data = try? Data(contentsOf: Self.playTimeFile), let stored = try? decoder.decode([String: EpicPlayTime].self, from: data) {
            playTimes = stored
        }
        if let data = try? Data(contentsOf: Self.sizesFile), let stored = try? decoder.decode([String: EpicSize].self, from: data) {
            sizes = stored
        }
        if let data = try? Data(contentsOf: Self.destinationsFile), let stored = try? decoder.decode([String: String].self, from: data) {
            destinations = stored
        }
    }

    /// The folder a game (or its add-on) downloads into: the Mac's, or one on a drive.
    private func base(for appName: String) -> URL {
        destinations[game(ofAddOn: appName) ?? appName].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Legendary.gamesDir
    }

    /// legendary has something to do or in line: it installs one thing at a time, and moving a game
    /// (legendary notes the new place) waits for it.
    var isBusy: Bool { !downloads.isEmpty || !starting.isEmpty || !updates.isEmpty || updatingGame != nil || !wanted.isEmpty }

    private func save<T: Encodable>(_ value: T, to file: URL) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: - Library

    func library() async -> [Game] {
        loadFromDisk()
        guard isConnected else { return [] }
        antiCheat = await profiles.epicAntiCheatBlocks()
        let config = Legendary.configDir
        let (installed, versions, latest) = await Engine.offMain {
            let installedJSON = (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data()
            return (EpicInstall.all(fromJSON: installedJSON), EpicInstall.versions(fromJSON: installedJSON),
                    EpicInstall.latestVersions(fromAssets: (try? Data(contentsOf: config.appendingPathComponent("assets.json"))) ?? Data()))
        }
        self.latest = latest
        let running = await Engine.offMain { Self.runningDownloads() }
        carryOn(versions: versions, running: running)
        let wanted = self.wanted
        let progress = await Engine.offMain {
            Dictionary(wanted.map { ($0, Legendary.progress(inLog: Self.logText(for: $0))) }, uniquingKeysWith: { first, _ in first })
        }
        var games: [Game] = []
        var listed = Set<String>()
        for entry in catalog.games {
            listed.insert(entry.appName)
            games.append(game(entry, install: installed[entry.appName], versions: versions, progress: progress))
        }
        // Installed but not in the list Nightforge has (it was never loaded here): still there.
        for (appName, install) in installed where !listed.contains(appName) {
            games.append(game(EpicGame(appName: appName, title: install.path.lastPathComponent, folder: install.path.lastPathComponent),
                              install: install, versions: versions, progress: progress))
        }
        return games
    }

    private func game(_ entry: EpicGame, install: EpicInstall?, versions: [String: String],
                      progress: [String: Legendary.Progress]) -> Game {
        let folder = install?.path ?? base(for: entry.appName).appendingPathComponent(entry.folder, isDirectory: true)
        let addOns = entry.dlcs ?? []
        // The game and its add-ons download as one, one part after the other.
        let names = ([entry.appName] + addOns.map(\.appName)).filter(wanted.contains)
        let parts = names.map { part in
            JobPart(done: versions[part] != nil || progress[part]?.finished == true || isEmptyAddOn(part),
                    progress: progress[part], size: knownSize(part)?.download)
        }
        let isDownloading = parts.contains { !$0.done }
        let job = Self.jobProgress(parts)
        // While it downloads: what the download comes to, which its progress is a share of. Before:
        // what it takes on disk (the space check), once Epic has said.
        let known = install == nil ? knownSize(of: entry) : nil
        let size = isDownloading ? (job.size > 0 ? job.size : known?.download ?? 0) : install?.size ?? known?.install ?? 0
        var game = Game(gameID: .epic(entry.appName), name: entry.title, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                        steamExeWindowsPath: "", installDir: folder, sizeOnDisk: size,
                        lastPlayed: playTimes[entry.appName]?.lastPlayed, playtimeMinutes: playTimes[entry.appName]?.minutes)
        game.installDirName = folder.lastPathComponent
        game.addOns = addOns.map(\.title)
        if isDownloading {
            game.install = .downloading(job.fraction)
            // What it takes on disk once it's down: legendary's install size, else what Epic said before.
            let unpacked = names.map { progress[$0]?.installSize ?? knownSize($0)?.install ?? (isEmptyAddOn($0) ? 0 : nil) }
            if !unpacked.contains(nil) { game.installedSize = unpacked.reduce(0) { $0 + ($1 ?? 0) } }
        } else if let install {
            game.install = .installed
            game.onlineOnly = !install.canRunOffline  // Epic's own say on offline play
            if !Self.updateParts(entry.appName, addOns: addOns.map(\.appName), versions: versions, latest: latest,
                                 empty: Set(addOns.map(\.appName).filter(isEmptyAddOn))).isEmpty {
                game.pendingUpdate = 0
            }
        } else {
            game.install = .notInstalled
            game.downloadSize = known?.download
        }
        if let block = antiCheat[entry.namespace], !block.onlineOnly { game.antiCheatBlock = block }
        // On a drive that's unplugged: "Connect <drive> to Play" until it's back.
        if game.isInstalled, let drive = LibraryScanner.missingVolume(forLibrary: folder.path, in: Engine.bottle) {
            game.install = .notInstalled
            game.missingDrive = drive
        }
        game.art = StoreArt(cover: entry.cover, hero: entry.hero, logo: entry.logo)
        return game
    }

    /// One part of a game's download: the game itself or one of its add-ons.
    struct JobPart {
        /// On the Mac (or nothing to download).
        var done: Bool
        var progress: Legendary.Progress?
        /// What Epic said it comes to before it started.
        var size: Int64?
    }

    /// A game and its add-ons download one after the other and show as one download: how far all of
    /// it is, weighed by size – a part's size from its log once it started, before that what Epic
    /// said. With no size known, the part that's under way says.
    nonisolated static func jobProgress(_ parts: [JobPart]) -> (fraction: Double?, size: Int64) {
        var total: Int64 = 0
        var done = 0.0
        var started = false
        for part in parts {
            let size = part.progress?.downloadSize ?? part.size ?? 0
            total += size
            if part.done {
                done += Double(size)
                started = true
            } else if let fraction = part.progress?.fraction {
                done += fraction * Double(size)
                started = true
            }
        }
        guard total > 0 else { return (parts.first { !$0.done }?.progress?.fraction, 0) }
        return (started ? min(done / Double(total), 1) : nil, total)
    }

    /// An add-on's game, when it is one.
    private func game(ofAddOn appName: String) -> String? { gameOfAddOn[appName] }

    private func addOns(of appName: String) -> [String] {
        catalog.games.first { $0.appName == appName }?.dlcs?.map(\.appName) ?? []
    }

    private static func addOnGames(_ catalog: EpicLibrary) -> [String: String] {
        catalog.games.reduce(into: [:]) { found, game in
            for dlc in game.dlcs ?? [] { found[dlc.appName] = game.appName }
        }
    }

    /// An add-on with nothing to download (legendary then never lists it as installed).
    private func isEmptyAddOn(_ appName: String) -> Bool {
        game(ofAddOn: appName) != nil && knownSize(appName)?.download == 0
    }

    private func markEmpty(_ appName: String) {
        sizes[appName] = EpicSize(version: latest[appName] ?? "", download: 0, install: 0)
        save(sizes, to: Self.sizesFile)
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

    // MARK: - Sizes

    /// The size known for the game's newest build, without asking.
    private func knownSize(_ appName: String) -> EpicSize? {
        guard let size = sizes[appName] else { return nil }
        if let build = latest[appName], build != size.version { return nil }
        return size
    }

    /// What the game and its add-ons come to, once Epic has said what the game itself does.
    private func knownSize(of entry: EpicGame) -> EpicSize? {
        guard var total = knownSize(entry.appName) else { return nil }
        for dlc in entry.dlcs ?? [] {
            guard let size = knownSize(dlc.appName) else { continue }
            total.download += size.download
            total.install += size.install
        }
        return total
    }

    /// What a game not on the Mac yet comes to with its add-ons: asked from Epic once per build, in
    /// the background, and kept. nil when Epic can't be asked (offline, signed out).
    func size(of game: Game) async -> EpicSize? {
        loadFromDisk()
        let appName = game.gameID.id
        guard await askSize(appName) != nil else { return nil }
        // The add-ons a few at a time: each is a legendary of its own.
        let addOns = addOns(of: appName)
        for start in stride(from: 0, to: addOns.count, by: 4) {
            await withTaskGroup(of: Void.self) { group in
                for dlc in addOns[start..<min(start + 4, addOns.count)] { group.addTask { _ = await self.askSize(dlc) } }
            }
        }
        return catalog.games.first { $0.appName == appName }.flatMap(knownSize(of:)) ?? knownSize(appName)
    }

    private func askSize(_ appName: String) async -> EpicSize? {
        if let known = knownSize(appName) { return known }
        guard isSignedIn, Date().timeIntervalSince(sizeFailed[appName] ?? .distantPast) > 5 * 60 else { return nil }
        if let asking = sizing[appName] { return await asking.value }
        let asking = Task { () -> EpicSize? in
            guard let result = try? await Legendary.run(["info", appName, "--json", "--platform", "Windows"], timeout: 90),
                  result.status == 0 else { return nil }
            return EpicSize.from(info: result.output)
        }
        sizing[appName] = asking
        let size = await asking.value
        sizing[appName] = nil
        guard let size else {
            sizeFailed[appName] = Date()
            return nil
        }
        sizes[appName] = size
        save(sizes, to: Self.sizesFile)
        changed()
        return size
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
        for process in downloads.values.map({ $0 }) + updates.values where process.isRunning { Legendary.stop(process.processIdentifier) }
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
        guard !wanted.contains(appName) else { return }
        destinations[appName] = context.drive.map { DriveLibrary.epic(on: $0).path }
        save(destinations, to: Self.destinationsFile)
        try FileManager.default.createDirectory(at: base(for: appName), withIntermediateDirectories: true)
        // Its add-ons come along, each after the game (they go into its folder).
        let job = [appName] + addOns(of: appName).filter { !wanted.contains($0) }
        wanted += job
        save(wanted, to: Self.wantedFile)
        let running = await Engine.offMain { Self.runningDownloads() }
        if isFree(running: running) {
            do {
                try await startDownload(appName)
            } catch {
                // Didn't start (legendary not at hand): nothing to carry on with later.
                wanted.removeAll(where: job.contains)
                save(wanted, to: Self.wantedFile)
                throw error
            }
        }
        context.requested()
    }

    /// Nothing of this Nightforge's – nor of an earlier one's – has legendary installing. Not known what an
    /// earlier one's does (`running` nil): not free.
    private func isFree(running: Set<String>?) -> Bool {
        downloads.isEmpty && starting.isEmpty && updates.isEmpty && updatingGame == nil && running?.isEmpty == true
    }

    private func startDownload(_ appName: String) async throws {
        starting.insert(appName)
        defer { starting.remove(appName) }
        let process = try await Legendary.start(["install", appName, "--base-path", base(for: appName).path,
                                                 "--platform", "Windows", "--skip-sdl", "--skip-dlcs", "-y"],
                                                log: Legendary.log(for: appName))
        downloads[appName] = process
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.downloadEnded(appName, status: status) }
        }
    }

    /// Starts the next download in line once legendary is free; an add-on waits for its game.
    private func startNext() async {
        guard isFree(running: []), !wanted.isEmpty else { return }
        let config = Legendary.configDir
        let (versions, running) = await Engine.offMain {
            (EpicInstall.versions(fromJSON: (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data()),
             Self.runningDownloads())
        }
        guard isFree(running: running),
              let next = wanted.first(where: { part in
                  versions[part] == nil && !isEmptyAddOn(part) && game(ofAddOn: part).map { versions[$0] != nil } ?? true
              })
        else { return }
        try? await startDownload(next)
    }

    private func downloadEnded(_ appName: String, status: Int32) {
        downloads[appName] = nil
        defer { Task { await startNext() } }
        guard wanted.contains(appName) else { return }  // cancelled
        let progress = Legendary.progress(inLog: Self.logText(for: appName))
        let base = game(ofAddOn: appName)
        if !progress.finished {
            // The rest of that game's download goes too. A game that's on the Mac gets a missing
            // add-on with its next "Update & Play".
            let job = [base ?? appName] + addOns(of: base ?? appName)
            wanted.removeAll(where: job.contains)
            save(wanted, to: Self.wantedFile)
            let title = base.flatMap { addOnTitle($0, appName) } ?? catalog.games.first { $0.appName == appName }?.title ?? appName
            downloadFailed(title, progress.failure ?? L10n.t("legendary stopped (code %d)", status), base != nil)
        } else if base != nil, EpicInstall.versions(fromJSON: (try? Data(contentsOf: Legendary.configDir
            .appendingPathComponent("installed.json"))) ?? Data())[appName] == nil {
            markEmpty(appName)  // "up to date" without being installed: nothing to download
        }
        changed()
    }

    private func addOnTitle(_ game: String, _ appName: String) -> String? {
        catalog.games.first { $0.appName == game }?.dlcs?.first { $0.appName == appName }?.title
    }

    /// legendary downloads still running from an earlier Nightforge, by app name. Without a process list the
    /// last look stands; nil when there is none either (the first look, with `ps` down): a download may be
    /// running then, and "none" would start a second one of the same game. `remembered`: for the test.
    nonisolated static func runningDownloads(remembered: LockedValue<Set<String>?> = lastRunning) -> Set<String>? {
        let root = ComponentStore.shared.root.appendingPathComponent(Legendary.componentID, isDirectory: true)
        guard let processes = Engine.ownProcessesKnown(under: root) else { return remembered.withLock { $0 } }
        let running = Set(processes.compactMap { process -> String? in
            let words = process.command.split(separator: " ")
            guard let index = words.firstIndex(of: "install"), index + 1 < words.count else { return nil }
            return String(words[index + 1])
        })
        remembered.withLock { $0 = running }
        return running
    }

    nonisolated private static let lastRunning = LockedValue<Set<String>?>(nil)

    /// Keeps the line of downloads in order: a game's download leaves it once the game and all its
    /// add-ons are there (also when that happened while Nightforge was away), add-ons whose game is
    /// neither here nor coming leave it, and what's next starts – legendary picks a download up
    /// where it stopped.
    /// `running`: nil when it isn't known which downloads run (no process list): no job is taken off the line then.
    private func carryOn(versions: [String: String], running: Set<String>?) {
        let before = wanted
        if let running {
            for base in Set(wanted.map { game(ofAddOn: $0) ?? $0 }) {
                let job = wanted.filter { $0 == base || game(ofAddOn: $0) == base }
                let busy = job.contains { downloads[$0] != nil || starting.contains($0) || running.contains($0) }
                let done = job.allSatisfy { versions[$0] != nil || isEmptyAddOn($0) }
                let orphaned = versions[base] == nil && !wanted.contains(base)
                if !busy && (done || orphaned) { wanted.removeAll(where: job.contains) }
            }
        }
        if wanted != before { save(wanted, to: Self.wantedFile) }
        Task { await startNext() }
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
        let parts = [appName] + addOns(of: appName)
        if parts.contains(where: { wanted.contains($0) || downloads[$0] != nil }) {
            wanted.removeAll(where: parts.contains)
            save(wanted, to: Self.wantedFile)
            let root = ComponentStore.shared.root.appendingPathComponent(Legendary.componentID)
            let started = parts.compactMap { downloads.removeValue(forKey: $0)?.processIdentifier }
            let earlier = Engine.ownProcesses(under: root)
                .filter { process in parts.contains { process.command.contains(" install \($0) ") } }.map(\.pid)
            // Gone before its files go (see Legendary.run); one that hangs doesn't hold the removal up.
            await Legendary.end(started + earlier, under: root)
        }
        // Nightforge removes a folder inside a games folder (the Mac's or a drive's) itself, with whatever is in
        // it – the settings files it writes beside the game (dxmt.conf …), a cancelled download. A game elsewhere
        // legendary removes, its own files only.
        let folder = game.installDir.standardizedFileURL
        let gamesFolders = [Legendary.gamesDir] + (DriveLibrary.drive(of: folder).map { [DriveLibrary.epic(on: $0)] } ?? [])
        let ownFolder = gamesFolders.contains { folder.deletingLastPathComponent().path == $0.standardizedFileURL.path }
        let installedFile = Legendary.configDir.appendingPathComponent("installed.json")
        let installed = EpicInstall.all(fromJSON: (try? Data(contentsOf: installedFile)) ?? Data())
        if installed[appName] != nil {
            // The folder first, and legendary forgets the game only once it's gone: a folder that stays (in
            // use, no permission) keeps the game installed, so it can be removed again. That's said, as for a
            // Steam game (Engine.removeGameFiles).
            if ownFolder, FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            let result = try await Legendary.run(Self.uninstallArguments(appName, filesGone: ownFolder), timeout: 600)
            guard result.status == 0 else { throw EpicError.failed(result.error ?? L10n.t("legendary stopped (code %d)", result.status)) }
        } else {
            for part in parts {
                try? FileManager.default.removeItem(at: Legendary.configDir.appendingPathComponent("tmp/\(part).resume"))
            }
        }
        // A cancelled download's folder: one that stays is said once the rest is done.
        var left: Error?
        if ownFolder, FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) } catch { left = error }
        }
        for part in parts { try? FileManager.default.removeItem(at: Legendary.log(for: part)) }
        if destinations.removeValue(forKey: appName) != nil { save(destinations, to: Self.destinationsFile) }
        Task { await startNext() }
        if let left { throw left }
    }

    /// legendary's uninstall without the game's uninstaller; `filesGone`: Nightforge removed the folder
    /// itself, legendary only forgets the game.
    nonisolated static func uninstallArguments(_ appName: String, filesGone: Bool) -> [String] {
        ["uninstall", appName, "-y", "--skip-uninstaller"] + (filesGone ? ["--keep-files"] : [])
    }

    // MARK: - A drive that's gone

    /// legendary's list without the games on a drive that isn't plugged in (or just `appName`'s), their
    /// manifests there, and the places downloads were meant to go on it. Epic's own files on the Mac stay.
    /// Returns how many installs went.
    @discardableResult
    func forgetDrive(_ name: String, only appName: String? = nil) -> Int {
        loadFromDisk()
        var count = 0
        let file = Legendary.configDir.appendingPathComponent("installed.json")
        if let data = try? Data(contentsOf: file),
           let result = ForgetDrive.epic(installedJSON: data, drive: name, appName: appName, bottle: Engine.bottle),
           (try? result.json.write(to: file, options: .atomic)) != nil {
            for manifest in result.manifests {
                try? FileManager.default.removeItem(at: Legendary.configDir.appendingPathComponent("manifests/\(manifest)"))
            }
            count = result.removed.count
        }
        let lost = destinations.filter { (appName == nil || $0.key == appName) && ForgetDrive.isOn($0.value, drive: name, bottle: Engine.bottle) }
        if !lost.isEmpty {
            for key in lost.keys { destinations[key] = nil }
            save(destinations, to: Self.destinationsFile)
        }
        return count
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

    /// How the update before a start went ("Update & Play"). Busy: another Epic download has
    /// legendary, which installs one thing at a time.
    typealias UpdateOutcome = StoreUpdate
    typealias UpdateSkip = StoreUpdate.Skip

    /// Updates running before a start, by app name, and the game being brought up to date (its
    /// parts take turns, and no download may slip in between).
    private var updates: [String: DetachedProcess] = [:]
    private var updatingGame: String?

    /// What brings an installed game up to date, in order: the game when Epic has a newer build,
    /// then its add-ons that are behind or not on the Mac yet (bought later, or a download that
    /// stopped) – except ones known to have nothing to download.
    nonisolated static func updateParts(_ appName: String, addOns: [String], versions: [String: String],
                                        latest: [String: String], empty: Set<String>) -> [String] {
        func behind(_ app: String) -> Bool {
            guard let have = versions[app], !have.isEmpty, let newest = latest[app] else { return false }
            return have != newest
        }
        return (behind(appName) ? [appName] : []) + addOns.filter { versions[$0] == nil ? !empty.contains($0) : behind($0) }
    }

    /// Brings an installed game and its add-ons up to date before it starts, like Steam's "Update &
    /// Play": legendary fetches only what changed and carries on where an earlier try stopped.
    /// `progress` hears how far all of it is, from legendary's logs.
    func update(_ game: Game, progress: @escaping @MainActor (Double?) -> Void) async -> UpdateOutcome {
        loadFromDisk()
        let appName = game.gameID.id
        let config = Legendary.configDir
        let (versions, latest) = await Engine.offMain {
            (EpicInstall.versions(fromJSON: (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data()),
             EpicInstall.latestVersions(fromAssets: (try? Data(contentsOf: config.appendingPathComponent("assets.json"))) ?? Data()))
        }
        self.latest = latest
        let addOns = addOns(of: appName)
        let parts = Self.updateParts(appName, addOns: addOns, versions: versions, latest: latest,
                                     empty: Set(addOns.filter(isEmptyAddOn)))
        guard !parts.isEmpty else { return .updated }
        updatingGame = appName
        defer {
            updatingGame = nil
            Task { await startNext() }  // downloads asked for meanwhile
        }
        let running = await Engine.offMain { Self.runningDownloads() }
        // legendary installs one thing at a time: while another Epic download runs, the game starts
        // as it is. One of its own parts an earlier Nightforge started is followed instead.
        // Not known which downloads run (no process list): as if another did.
        guard let running, downloads.isEmpty, starting.isEmpty, running.isSubset(of: Set(parts)) else { return .skipped(.busy) }
        for (index, part) in parts.enumerated() {
            let outcome = await updatePart(part, installed: versions[part] != nil, following: running.contains(part)) { fraction in
                let share = fraction ?? 0
                progress(fraction == nil && index == 0 ? nil : (Double(index) + share) / Double(parts.count))
            }
            switch outcome {
            case .updated:
                if part != appName, versions[part] == nil, await Engine.offMain({
                    EpicInstall.versions(fromJSON: (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data())[part] == nil
                }) {
                    markEmpty(part)  // "up to date" without being installed: nothing to download
                }
            case .skipped:
                // Nothing of it fetched: the game starts as it is; after the game's own update, an
                // add-on waits for the next time.
                return index == 0 ? outcome : .updated
            case .failed(let reason) where part != appName:
                return .addOnFailed(addOnTitle(appName, part) ?? part, reason)
            case .failed, .addOnFailed:
                return outcome
            }
        }
        return .updated
    }

    /// One part of an update: the game or an add-on, fetched by legendary (a missing add-on in full).
    private func updatePart(_ appName: String, installed: Bool, following: Bool,
                            progress: @escaping @MainActor (Double?) -> Void) async -> UpdateOutcome {
        var process: DetachedProcess?
        if !following {
            let arguments = installed ? ["install", appName, "--update-only", "--skip-sdl", "--skip-dlcs", "-y"]
                : ["install", appName, "--platform", "Windows", "--skip-sdl", "--skip-dlcs", "-y"]
            do {
                process = try await Legendary.start(arguments, log: Legendary.log(for: appName))
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
                if let process { Legendary.stop(process.processIdentifier) }  // it carries on next time
                return .skipped(.offline)
            }
            let state = await Engine.offMain { Legendary.progress(inLog: Self.logText(for: appName)) }
            progress(state.fraction)
            let ended: Bool
            if let process {
                ended = !process.isRunning
            } else {
                // Ended only as a list says so: without one it goes on (the 90 quiet seconds below end it).
                ended = await Engine.offMain { Self.runningDownloads() }.map { !$0.contains(appName) } ?? false
            }
            if ended { return Self.updateOutcome(state, status: process?.terminationStatus) }
            // Not a word from Epic for 90 s (a network that doesn't answer): the game starts as it is.
            silent = state.fraction == nil ? silent + 1 : 0
            if silent >= 90 {
                if let process { Legendary.stop(process.processIdentifier) }
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

    /// A game's catalog namespace, from the library Nightforge keeps on disk: what profiles.json
    /// keys Epic's games by ("epic.<namespace>"). Nil before the library was first read.
    nonisolated static func namespace(of appName: String) -> String? {
        struct Library: Decodable { let games: [EpicGame] }
        let file = Engine.supportDir.appendingPathComponent("Epic/library.json")
        guard let data = try? Data(contentsOf: file), let library = try? JSONDecoder().decode(Library.self, from: data),
              let namespace = library.games.first(where: { $0.appName == appName })?.namespace, !namespace.isEmpty
        else { return nil }
        return namespace
    }

    /// Whether the game may start without Epic (legendary's installed.json).
    nonisolated static func executable(of appName: String) -> String? {
        let file = Legendary.configDir.appendingPathComponent("installed.json")
        return EpicInstall.all(fromJSON: (try? Data(contentsOf: file)) ?? Data())[appName]?.executable
    }
}

/// The line on a game's page about its add-ons: the first few by name, then how many more.
enum AddOns {
    static let named = 3

    static func line(_ titles: [String]) -> String {
        let shown = titles.prefix(named).joined(separator: ", ")
        let list = titles.count > named ? L10n.t("%@ and %ld more", shown, titles.count - named) : shown
        return titles.count == 1 ? L10n.t("Your add-on: %@ – it downloads and updates with the game.", list)
            : L10n.t("Your add-ons: %@ – they download and update with the game.", list)
    }
}
