import AppKit

/// A download in line: a game, in the version it comes in, or the update of one on the Mac.
struct GOGJob: Codable, Equatable {
    let id: String
    var platform: Platform
    var update = false
    /// The games folder on an external drive it goes to ("Nightforge Games/GOG Games"); nil: the Mac.
    var base: String?

    /// The folder gogdl puts the game's own folder in.
    var folder: URL { base.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? GOGDL.gamesDir(for: platform) }
}

/// GOG (7.3), without GOG Galaxy: signed in once in GOG's own sign-in page, its library stays on
/// the Mac and is brought up to date in the background from GOG's API. gogdl downloads, updates and
/// syncs the saves; Nightforge starts the games itself – a Mac version as it is (GOG's games are
/// DRM-free), a Windows version through Wine like Epic's.
@MainActor
final class GOGStore: ObservableObject, StoreProvider, AccountStore {
    let provider = Provider.gog
    @Published private(set) var sync = StoreSync()
    /// The sign-in page is open: the Stores tab says what to do there.
    @Published var connecting = false
    @Published private(set) var catalog = GOGLibrary()
    /// Something to tell the library (a download is done or failed, the list changed).
    var changed: () -> Void = {}
    /// A download that stopped by itself: the game's name and gogdl's reason.
    var downloadFailed: (String, String) -> Void = { _, _ in }
    /// A Mac version that doesn't run on this Mac gave way to the Windows version: the game's name.
    var tookWindowsVersion: (String) -> Void = { _ in }

    /// The account's token for GOG's API, from gogdl (which refreshes it). Tests hand in their own.
    var authenticate: () async -> GOGAuth = {
        if let json = try? Data(contentsOf: GOGDL.authFile), let stored = GOGAuth.stored(json) { return stored }
        guard let result = try? await GOGDL.run(["auth"], timeout: 60) else { return .offline }
        let auth = GOGAuth.from(output: result.output, log: result.log, status: result.status)
        if auth == .helperFailed { GOGDL.writeAuthLog(result, command: "auth") }
        return auth
    }
    /// Asks GOG's API (with the token when one is given). Tests hand in their own.
    var fetch: @Sendable (URL, String?) async throws -> Data = { url, token in try await GOGStore.ask(url, token: token) }

    private var downloads: [String: DetachedProcess] = [:]
    /// Downloads whose gogdl is starting up: a look at the library meanwhile mustn't start it twice.
    private var starting: Set<String> = []
    /// Downloads asked for, in line: one gogdl at a time. They carry on after Nightforge was quit
    /// or the Mac restarted (gogdl picks a download up where it stopped).
    private var wanted: [GOGJob] = []
    private var installs: [String: GOGInstall] = [:]
    /// Sizes of games not on the Mac yet, by "<id>.<platform>", and the newest build of the
    /// installed ones (for updates).
    private var sizes: [String: GOGSize] = [:]
    private var latest: [String: GOGBuild] = [:]
    /// What GamesDB said about each product the player owns, kept so the library loads quickly –
    /// and asked again once a week (a Mac version GOG added, new art).
    private var releases = GOGReleases()
    /// Games whose Mac version doesn't run here (32-bit only) or can't be installed: Windows it is.
    private var macUnfit: Set<String> = []
    private var playTimes: [String: EpicPlayTime] = [:]
    /// When each save folder was last synced (gogdl's timestamp), by "<id>/<name>".
    private var saveTimes: [String: Double] = [:]
    /// Which games keep saves with GOG, once asked.
    private var cloudSaves: [String: Bool] = [:]
    private var sizing: [String: Task<GOGSize?, Never>] = [:]
    private var sizeFailed: [String: Date] = [:]
    /// The game being brought up to date before it starts.
    private var updatingGame: String?
    private var loadedFromDisk = false

    private static var folder: URL { Engine.supportDir.appendingPathComponent("GOG", isDirectory: true) }
    private static var libraryFile: URL { folder.appendingPathComponent("library.json") }
    private static var releasesFile: URL { folder.appendingPathComponent("releases.json") }
    private static var installedFile: URL { folder.appendingPathComponent("installed.json") }
    private static var wantedFile: URL { folder.appendingPathComponent("downloads.json") }
    private static var sizesFile: URL { folder.appendingPathComponent("sizes.json") }
    private static var buildsFile: URL { folder.appendingPathComponent("builds.json") }
    private static var macFile: URL { folder.appendingPathComponent("mac-unfit.json") }
    private static var playTimeFile: URL { folder.appendingPathComponent("playtime.json") }
    private static var savesFile: URL { folder.appendingPathComponent("saves.json") }
    /// The player connected GOG (until they disconnect), apart from gogdl's tokens: a sign-in GOG
    /// ends mustn't take the games with it.
    private static var accountFile: URL { folder.appendingPathComponent("account.json") }

    /// Connected in Settings › Stores – also while GOG has signed the player out.
    var isConnected: Bool { FileManager.default.fileExists(atPath: Self.accountFile.path) }

    /// gogdl holds GOG's tokens (whether GOG still takes them shows when it's asked).
    var isSignedIn: Bool { FileManager.default.fileExists(atPath: GOGDL.authFile.path) && sync.state != .signedOut }

    /// The GOG account's name.
    var accountName: String? {
        guard let data = try? Data(contentsOf: Self.accountFile),
              let account = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = account["username"] as? String, !name.isEmpty else { return nil }
        return name
    }

    private func loadFromDisk() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        func load<T: Decodable>(_ type: T.Type, _ file: URL) -> T? {
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(type, from: $0) }
        }
        if let stored = load(GOGLibrary.self, Self.libraryFile) {
            catalog = stored
            sync.lastSuccess = stored.loaded
        }
        releases = load(GOGReleases.self, Self.releasesFile) ?? GOGReleases()
        installs = load([String: GOGInstall].self, Self.installedFile) ?? [:]
        wanted = load([GOGJob].self, Self.wantedFile) ?? []
        sizes = load([String: GOGSize].self, Self.sizesFile) ?? [:]
        latest = load([String: GOGBuild].self, Self.buildsFile) ?? [:]
        macUnfit = load(Set<String>.self, Self.macFile) ?? []
        playTimes = load([String: EpicPlayTime].self, Self.playTimeFile) ?? [:]
        saveTimes = load([String: Double].self, Self.savesFile) ?? [:]
        // These files are Nightforge's own, but the ID becomes a file name, a link and a bundle name: only a product
        // ID passes (digits), as it does where the IDs come from GOG (GOGRelease.isProductID) – and as Epic's do.
        catalog.games = catalog.games.filter { GOGRelease.isProductID($0.id) }.map { game in
            var game = game
            game.dlcs = game.dlcs.filter { GOGRelease.isProductID($0.id) }
            return game
        }
        releases.items = releases.items.filter { GOGRelease.isProductID($0.key) }
        installs = installs.filter { GOGRelease.isProductID($0.key) }
        wanted = wanted.filter { GOGRelease.isProductID($0.id) }
    }

    private func save<T: Encodable>(_ value: T, to file: URL) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: - Library

    func library() async -> [Game] {
        loadFromDisk()
        guard isConnected else { return [] }
        let running = await Engine.offMain { GOGDL.runningDownloads() }
        carryOn(running: running)
        let jobs = wanted.map(\.id)
        let progress = await Engine.offMain {
            Dictionary(jobs.map { ($0, GOGDL.progress(inLog: GOGDL.logText(for: $0))) }, uniquingKeysWith: { first, _ in first })
        }
        var games: [Game] = []
        var listed = Set<String>()
        for entry in catalog.games {
            listed.insert(entry.id)
            games.append(game(entry, progress: progress[entry.id]))
        }
        // On the Mac but not in the list Nightforge has (it was never loaded here): still there.
        for install in installs.values where !listed.contains(install.id) {
            let title = GOGGameInfo.read(id: install.id, in: install.path)?.name ?? install.path.deletingPathExtension().lastPathComponent
            games.append(game(GOGGame(id: install.id, title: title.isEmpty ? install.id : title), progress: progress[install.id]))
        }
        return games
    }

    private func game(_ entry: GOGGame, progress: GOGDL.Progress?) -> Game {
        let install = installs[entry.id]
        let job = wanted.first { $0.id == entry.id }
        let platform = job?.platform ?? install?.platform ?? version(of: entry)
        let size = knownSize(entry.id, platform)
        let folder = install?.path ?? (job?.folder ?? GOGDL.gamesDir(for: platform))
            .appendingPathComponent(size?.folder.isEmpty == false ? size!.folder : Self.folderName(entry.title), isDirectory: true)
        let isDownloading = job != nil
        // While it downloads: what comes down, as the game page said before it started – gogdl counts
        // the bytes it writes (the size on the Mac), and its share goes for either.
        let download = (size?.download).flatMap { $0 > 0 ? $0 : nil }
        let onDisk = isDownloading ? download ?? progress?.total ?? size?.install ?? 0 : install?.size ?? size?.install ?? 0
        let played = playTimes[entry.id]
        var game = Game(gameID: .gog(entry.id), name: entry.title, bottle: platform == .mac ? Self.macBottle : Engine.bottle,
                        steamRoot: Engine.steamRoot, steamExeWindowsPath: "", installDir: folder, sizeOnDisk: onDisk,
                        lastPlayed: played?.lastPlayed, playtimeMinutes: played?.minutes)
        game.installDirName = folder.lastPathComponent
        game.platform = platform
        // The same place in the list whichever version it comes in.
        game.listID = "\(Engine.bottle.name)#\(game.gameID.key)"
        game.macNative = entry.mac
        game.addOns = entry.dlcs.map(\.title)
        game.art = StoreArt(cover: entry.cover, hero: entry.hero, logo: nil)
        game.steamTwin = releases.items[entry.id]?.steamAppID
        if isDownloading {
            game.install = .downloading(progress?.fraction)
            // What gogdl writes in all, else what the game page said: more than comes down.
            game.installedSize = progress?.total ?? size?.install
        } else if let install {
            game.install = .installed
            if needsUpdate(install, entry: entry) { game.pendingUpdate = 0 }
        } else {
            game.install = .notInstalled
            game.downloadSize = size?.download
        }
        // On a drive that's unplugged: "Connect <drive> to Play" until it's back.
        if game.isInstalled, let drive = LibraryScanner.missingVolume(forLibrary: folder.path, in: Engine.bottle) {
            game.install = .notInstalled
            game.pendingUpdate = nil
            game.missingDrive = drive
        }
        return game
    }

    /// Mac versions run as they are, outside Wine – like Steam's Mac versions, no graphics presets.
    static var macBottle: Bottle { Bottle(name: Provider.gog.label, url: GOGDL.macGamesDir) }

    /// The version a game not on the Mac yet comes in: the Mac version when GOG has one that runs
    /// here, unless the player picked Windows in its options.
    func version(of entry: GOGGame) -> Platform {
        guard entry.mac, !macUnfit.contains(entry.id) else { return .windows }
        return Self.version(mac: true, unfit: false, choice: GameOptionsStore.load(.gog(entry.id)).version)
    }

    nonisolated static func version(mac: Bool, unfit: Bool, choice: GameVersion) -> Platform {
        choice != .windows && mac && !unfit ? .mac : .windows
    }

    /// A folder name for a game before GOG has said its own: the title without what a file name can't hold.
    nonisolated static func folderName(_ title: String) -> String {
        let name = title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined().trimmingCharacters(in: .whitespaces)
        return EpicLibrary.isFolderName(name) ? name : "Game"
    }

    /// GOG has a newer build than the one on the Mac, or the player bought add-ons since.
    private func needsUpdate(_ install: GOGInstall, entry: GOGGame?) -> Bool {
        Self.needsUpdate(install, latest: latest[install.id], owned: entry?.dlcs.map(\.id) ?? [])
    }

    nonisolated static func needsUpdate(_ install: GOGInstall, latest: GOGBuild?, owned: [String]) -> Bool {
        if let latest, !install.build.isEmpty, !latest.matches(install.build) { return true }
        return !Set(owned).isSubset(of: Set(install.dlcs))
    }

    /// Asks GOG for the library: the products the player owns, what each of them is (asked once
    /// per product and kept), and the newest build of the games on the Mac. On failure the games
    /// from last time stay, and `sync` says why and since when.
    func refresh() async {
        loadFromDisk()
        guard isConnected, sync.state != .syncing else { return }
        guard FileManager.default.fileExists(atPath: GOGDL.authFile.path) else {
            sync = StoreSync(state: .signedOut, lastSuccess: catalog.loaded)
            changed()
            return
        }
        sync.state = .syncing
        switch await authenticate() {
        case .signedOut:
            sync = StoreSync(state: .signedOut, lastSuccess: catalog.loaded)
        case .offline:
            sync = StoreSync(state: .failed(L10n.t("Couldn't reach GOG")), lastSuccess: catalog.loaded)
        case .helperFailed:
            sync = StoreSync(state: .failed(L10n.t("Nightforge's GOG helper didn't start")), lastSuccess: catalog.loaded)
        case .signedIn(let token, let user):
            do {
                try await load(token: token, user: user)
                sync = StoreSync(state: .ok, lastSuccess: catalog.loaded)
            } catch {
                sync = StoreSync(state: .failed(L10n.t("Couldn't reach GOG")), lastSuccess: catalog.loaded)
            }
        }
        changed()
    }

    private func load(token: String, user: String) async throws {
        var owned: [String] = []
        var page: String?
        repeat {
            var components = URLComponents(string: "https://galaxy-library.gog.com/users/\(user)/releases")!
            if let page { components.queryItems = [URLQueryItem(name: "page_token", value: page)] }
            guard let url = components.url, let found = GOGOwned.page(fromJSON: try await fetch(url, token)) else {
                throw GOGError.failed("library")
            }
            owned += found.ids
            page = found.next
        } while page != nil && owned.count < 20_000
        // What each product is, for those not known yet (all of them once a week) – a few at a time.
        let fetch = self.fetch
        let weekly = Date().timeIntervalSince(releases.checked ?? .distantPast) > 7 * 86_400
        let unknown = weekly ? Array(Set(owned)) : Array(Set(owned).subtracting(releases.items.keys))
        var failed = 0
        for start in stride(from: 0, to: unknown.count, by: 8) {
            let found = await withTaskGroup(of: (String, GOGRelease?, Bool).self) { group in
                for id in unknown[start..<min(start + 8, unknown.count)] {
                    group.addTask {
                        guard let url = URL(string: "https://gamesdb.gog.com/platforms/gog/external_releases/\(id)") else { return (id, nil, true) }
                        do {
                            return (id, GOGRelease.from(gamesDB: try await fetch(url, token)), true)
                        } catch GOGFetchError.status(404) {
                            return (id, nil, true)  // not in GamesDB: nothing to show
                        } catch {
                            return (id, nil, false)
                        }
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
            for (id, release, answered) in found {
                if let release {
                    releases.items[id] = release
                } else if answered {
                    releases.items[id] = GOGRelease(id: id, title: id, type: "none")
                }
                if !answered { failed += 1 }
            }
        }
        // GOG didn't answer for most of it: not a library to replace the last one with.
        if failed > 0 && failed * 2 >= unknown.count { throw GOGError.failed("gamesdb") }
        if weekly && failed == 0 { releases.checked = Date() }
        save(releases, to: Self.releasesFile)
        catalog = GOGLibrary(games: GOGLibrary.games(from: owned.compactMap { releases.items[$0] }), loaded: Date())
        save(catalog, to: Self.libraryFile)
        await checkBuilds()
    }

    /// The newest build of each game on the Mac (GOG's content system, no sign-in needed).
    private func checkBuilds() async {
        for install in installs.values {
            let system = install.platform == .mac ? "osx" : "windows"
            guard let url = URL(string: "https://content-system.gog.com/products/\(install.id)/os/\(system)/builds?generation=2"),
                  let data = try? await fetch(url, nil), let build = GOGBuild.latest(fromJSON: data) else { continue }
            latest[install.id] = build
        }
        save(latest, to: Self.buildsFile)
    }

    nonisolated static func ask(_ url: URL, token: String?) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw GOGFetchError.status(status) }
        return data
    }

    // MARK: - Signing in

    /// The code GOG's sign-in page ends with goes to gogdl, which swaps it for its tokens. How that
    /// went goes into GOG/Logs/auth.log, without the code or the tokens.
    func connect(code: String) async throws {
        let result = try await GOGDL.run(["auth", "--code", code], timeout: 60)
        GOGDL.writeAuthLog(result, command: "auth --code", hiding: [code])
        let auth = GOGAuth.from(output: result.output, log: result.log, status: result.status)
        if auth == .helperFailed { throw GOGError.helperFailed }
        guard result.status == 0, case .signedIn(let token, let user) = auth else { throw GOGError.signInFailed }
        var name = ""
        if let url = URL(string: "https://users.gog.com/users/\(user)"), let data = try? await fetch(url, token),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            name = object["username"] as? String ?? ""
        }
        let account = ["username": name, "connected": ISO8601DateFormatter().string(from: Date())]
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: account).write(to: Self.accountFile, options: .atomic)
        sync = StoreSync(state: .ok, lastSuccess: catalog.loaded)
        objectWillChange.send()
        await refresh()
    }

    /// Signs out (gogdl's tokens go). Installed games stay on the Mac and come back with the next
    /// sign-in; downloads stop.
    func disconnect() async {
        for process in downloads.values where process.isRunning { Legendary.stop(process.processIdentifier) }
        downloads = [:]
        try? FileManager.default.removeItem(at: GOGDL.authFile)
        try? FileManager.default.removeItem(at: Self.accountFile)
        sync = StoreSync(state: .ok, lastSuccess: nil)
        objectWillChange.send()
        changed()
    }

    // MARK: - Sizes

    /// The size known for the game's newest build in that version, without asking.
    private func knownSize(_ id: String, _ platform: Platform) -> GOGSize? {
        sizes["\(id).\(platform.rawValue)"]
    }

    /// What a game not on the Mac yet comes to with its add-ons, in the Mac's language when GOG has
    /// it: asked from GOG once (gogdl reads the build's manifest) and kept. A Mac version gogdl
    /// can't install is noted, and the Windows version's size comes instead. nil when GOG can't be
    /// asked (offline, signed out), or when `stillWanted` says no after waiting its turn.
    func size(of game: Game, stillWanted: () -> Bool = { true }) async -> GOGSize? {
        loadFromDisk()
        let id = game.gameID.id
        guard let entry = catalog.games.first(where: { $0.id == id }) ?? (installs[id] == nil ? nil : GOGGame(id: id, title: game.name))
        else { return nil }
        let platform = installs[id]?.platform ?? version(of: entry)
        let size = await askSize(id, platform, stillWanted: stillWanted)
        if size == nil, platform == .mac, macUnfit.contains(id) { return await askSize(id, .windows, stillWanted: stillWanted) }
        return size
    }

    private func askSize(_ id: String, _ platform: Platform, stillWanted: () -> Bool = { true }) async -> GOGSize? {
        let key = "\(id).\(platform.rawValue)"
        if let known = sizes[key] { return known }
        guard FileManager.default.fileExists(atPath: GOGDL.authFile.path),
              Date().timeIntervalSince(sizeFailed[key] ?? .distantPast) > 5 * 60 else { return nil }
        if let asking = sizing[key] { return await asking.value }
        // One gogdl at a time – each takes ~3 s to start: pages looked at one after another don't
        // pile up, and one passed by meanwhile isn't asked at all.
        while !sizing.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
        if let known = sizes[key] { return known }
        guard stillWanted(), Date().timeIntervalSince(sizeFailed[key] ?? .distantPast) > 5 * 60 else { return nil }
        let asking = Task { () -> GOGSize? in
            guard let result = try? await GOGDL.run(["info", id, "--platform", Self.system(platform), "--with-dlcs"], timeout: 120)
            else { return nil }
            if result.status == 0 { return GOGSize.from(info: result.output) }
            // GOG lists a Mac version that its content system can't hand out (an old installer).
            if platform == .mac, result.log.contains("doesn't support content system") || result.log.contains("No builds found") {
                self.markMacUnfit(id)
            }
            return nil
        }
        sizing[key] = asking
        let size = await asking.value
        sizing[key] = nil
        guard let size else {
            sizeFailed[key] = Date()
            return nil
        }
        sizes[key] = size
        save(sizes, to: Self.sizesFile)
        changed()
        return size
    }

    private func markMacUnfit(_ id: String) {
        macUnfit.insert(id)
        save(macUnfit, to: Self.macFile)
        changed()
    }

    /// gogdl's names for the systems.
    nonisolated static func system(_ platform: Platform) -> String { platform == .mac ? "osx" : "windows" }

    // MARK: - Downloads

    func install(_ game: Game, context: StoreContext) async throws {
        loadFromDisk()
        let id = game.gameID.id
        guard !wanted.contains(where: { $0.id == id }) else { return }
        // Its size and language first – which also tells whether the Mac version can be installed.
        _ = await size(of: game)
        let entry = catalog.games.first { $0.id == id } ?? GOGGame(id: id, title: game.name)
        try? FileManager.default.removeItem(at: GOGDL.log(for: id))  // how an earlier try ended isn't this one's
        wanted.append(GOGJob(id: id, platform: version(of: entry), base: context.drive.map { DriveLibrary.gog(on: $0).path }))
        save(wanted, to: Self.wantedFile)
        context.requested()
        await startNext()
    }

    /// Nothing of this Nightforge's – nor of an earlier one's – has gogdl downloading.
    private var isFree: Bool { downloads.isEmpty && starting.isEmpty && updatingGame == nil }

    /// gogdl has something to do or in line: a move waits, so no game changes place under it.
    var isBusy: Bool { !isFree || !wanted.isEmpty }

    /// Starts the next download in line once nothing else downloads from GOG.
    private func startNext() async {
        guard isFree, let job = wanted.first else { return }
        // Nothing starts while it isn't known what runs (no process list): a second download of the same game.
        guard (await Engine.offMain { GOGDL.runningDownloads() })?.isEmpty == true, isFree else { return }
        do {
            try await startDownload(job)
        } catch {
            wanted.removeAll { $0 == job }
            save(wanted, to: Self.wantedFile)
            downloadFailed(title(of: job.id), error.localizedDescription)
            changed()
        }
    }

    /// gogdl's arguments for a download (into the games folder, which gets the game's own folder)
    /// or an update (in the game's folder), with the add-ons the player owns.
    func downloadArguments(_ job: GOGJob, folder: URL?) -> [String] {
        let size = knownSize(job.id, job.platform)
        let language = size?.language ?? installs[job.id]?.language ?? "en-US"
        let target = job.update ? (folder ?? installs[job.id]?.path)?.path ?? "" : job.folder.path
        return [job.update ? "update" : "download", job.id, "--platform", Self.system(job.platform), "--path", target,
                "--support", GOGDL.supportDir(for: job.id).path, "--with-dlcs", "--lang", language]
    }

    private func startDownload(_ job: GOGJob) async throws {
        starting.insert(job.id)
        defer { starting.remove(job.id) }
        // The language and folder come from GOG's size (asked again for a version that took over).
        if knownSize(job.id, job.platform) == nil { _ = await askSize(job.id, job.platform) }
        try FileManager.default.createDirectory(at: job.folder, withIntermediateDirectories: true)
        let process = try await GOGDL.start(downloadArguments(job, folder: nil), log: GOGDL.log(for: job.id))
        downloads[job.id] = process
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.downloadEnded(job.id) }
        }
    }

    private func downloadEnded(_ id: String) {
        downloads[id] = nil
        defer { Task { await startNext() } }
        guard let job = wanted.first(where: { $0.id == id }) else { return }  // cancelled
        ended(job, progress: GOGDL.progress(inLog: GOGDL.logText(for: id)))
        changed()
    }

    /// A download gogdl has ended: done – the game is recorded – or stopped, with its reason. Its
    /// log goes: what comes next for the game (the Windows version, a new try) writes its own. One
    /// that stopped is kept as <id>.failed.log for a problem report, until a download finishes.
    private func ended(_ job: GOGJob, progress: GOGDL.Progress) {
        wanted.removeAll { $0.id == job.id }
        let fm = FileManager.default
        try? fm.removeItem(at: GOGDL.failedLog(for: job.id))
        if !progress.finished { try? fm.moveItem(at: GOGDL.log(for: job.id), to: GOGDL.failedLog(for: job.id)) }
        try? fm.removeItem(at: GOGDL.log(for: job.id))
        guard progress.finished else {
            save(wanted, to: Self.wantedFile)
            downloadFailed(title(of: job.id), progress.failure ?? L10n.t("gogdl stopped (code %d)", progress.exitCode ?? -1))
            return
        }
        let size = knownSize(job.id, job.platform)
        let base = job.folder
        guard let folder = Self.installFolder(id: job.id, preferred: size?.folder, in: base) else {
            save(wanted, to: Self.wantedFile)
            downloadFailed(title(of: job.id), L10n.t("GOG's files for it aren't where gogdl put them"))
            return
        }
        let info = GOGGameInfo.read(id: job.id, in: folder)
        // A Mac version from the 32-bit days: macOS won't start it, so the Windows version comes instead.
        if job.platform == .mac, let info, MachO.runsHere(file: folder.pathExtension == "app" ? folder : folder.appendingPathComponent(info.path)) == false {
            removeFiles(of: job.id, folder: folder, platform: .mac)
            markMacUnfit(job.id)
            wanted.insert(GOGJob(id: job.id, platform: .windows, base: job.base), at: 0)
            save(wanted, to: Self.wantedFile)
            tookWindowsVersion(title(of: job.id))
            return
        }
        installs[job.id] = GOGInstall(id: job.id, path: folder, platform: job.platform, build: info?.build ?? size?.build ?? "",
                                      language: size?.language ?? "en-US", size: size?.install ?? progress.total ?? 0,
                                      dlcs: size?.dlcs.map(\.id) ?? catalog.games.first { $0.id == job.id }?.dlcs.map(\.id) ?? [])
        save(installs, to: Self.installedFile)
        save(wanted, to: Self.wantedFile)
    }

    /// The game's folder after its download: the one GOG named, or whichever folder in the games
    /// folder holds its info file.
    nonisolated static func installFolder(id: String, preferred: String?, in base: URL) -> URL? {
        if let preferred, !preferred.isEmpty {
            let folder = base.appendingPathComponent(preferred, isDirectory: true)
            if GOGGameInfo.file(id: id, in: folder) != nil { return folder }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return folders.first { GOGGameInfo.file(id: id, in: $0) != nil }
    }

    /// Keeps the line of downloads in order after a look at the processes: a download that ended
    /// while Nightforge was away is recorded (or reported), one cut off by a restart of the Mac
    /// starts again – gogdl carries on where it stopped.
    /// `running`: nil when it isn't known which downloads run (no process list): no job is judged ended then.
    private func carryOn(running: Set<String>?) {
        if let running {
            for job in wanted where downloads[job.id] == nil && !starting.contains(job.id) && !running.contains(job.id) {
                let progress = GOGDL.progress(inLog: GOGDL.logText(for: job.id))
                if progress.exitCode != nil { ended(job, progress: progress) }
            }
        }
        Task { await startNext() }
    }

    private func title(of id: String) -> String {
        catalog.games.first { $0.id == id }?.title ?? id
    }

    /// A download is stopped and its files go; an installed game is removed from the Mac.
    func uninstall(_ game: Game) async throws {
        loadFromDisk()
        let id = game.gameID.id
        if wanted.contains(where: { $0.id == id }) || downloads[id] != nil {
            wanted.removeAll { $0.id == id }
            save(wanted, to: Self.wantedFile)
            if let process = downloads.removeValue(forKey: id) {
                Legendary.stop(process.processIdentifier)
                while process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            }
            let root = ComponentStore.shared.root.appendingPathComponent(GOGDL.componentID, isDirectory: true)
            for pid in Engine.ownProcesses(under: root).filter({ $0.command.contains(" \(id) ") }).map(\.pid) {
                Legendary.stop(pid)
            }
        }
        if let install = installs.removeValue(forKey: id) {
            save(installs, to: Self.installedFile)
            removeFiles(of: id, folder: install.path, platform: install.platform)
        } else {
            // A cancelled download: what it had fetched so far.
            removeFiles(of: id, folder: game.installDir, platform: game.platform)
        }
        try? FileManager.default.removeItem(at: GOGDL.log(for: id))
        objectWillChange.send()
        Task { await startNext() }
    }

    /// The game's folder (only inside GOG's games folders), gogdl's manifest and its support files.
    private func removeFiles(of id: String, folder: URL, platform: Platform) {
        let parent = folder.standardizedFileURL.deletingLastPathComponent().path
        if Self.gamesFolders(of: folder).contains(where: { $0.standardizedFileURL.path == parent }) {
            try? FileManager.default.removeItem(at: folder)
        }
        try? FileManager.default.removeItem(at: GOGDL.manifest(for: id))
        try? FileManager.default.removeItem(at: GOGDL.supportDir(for: id))
    }

    /// The folders GOG games may lie in: the Mac's two, and the one on the drive `folder` is on.
    nonisolated static func gamesFolders(of folder: URL) -> [URL] {
        [GOGDL.windowsGamesDir, GOGDL.macGamesDir] + (DriveLibrary.drive(of: folder).map { [DriveLibrary.gog(on: $0)] } ?? [])
    }

    // MARK: - A drive that's gone

    /// Nightforge's list of GOG installs without the games on a drive that isn't plugged in (or just `id`'s),
    /// gogdl's manifest and the support files of each (all in Nightforge's own folder, never the Windows
    /// environment), and the downloads waiting for that drive. Returns how many installs went.
    @discardableResult
    func forgetDrive(_ name: String, only id: String? = nil) -> Int {
        loadFromDisk()
        let (kept, removed) = ForgetDrive.gog(installs, drive: name, id: id, bottle: Engine.bottle)
        if !removed.isEmpty {
            installs = kept
            save(installs, to: Self.installedFile)
            for install in removed {
                try? FileManager.default.removeItem(at: GOGDL.manifest(for: install.id))
                try? FileManager.default.removeItem(at: GOGDL.supportDir(for: install.id))
            }
        }
        let waiting = wanted.filter { job in
            (id == nil || job.id == id) && job.base.map { ForgetDrive.isOn($0, drive: name, bottle: Engine.bottle) } == true
        }
        if !waiting.isEmpty {
            wanted.removeAll { job in waiting.contains(job) }
            save(wanted, to: Self.wantedFile)
        }
        return removed.count
    }

    // MARK: - Moving

    /// A game "Move to …" brought to another drive (or back to the Mac): from now on it's there.
    /// Its build, language and add-ons stay; gogdl updates it in its new folder.
    func recordMove(_ game: Game, to folder: URL) {
        loadFromDisk()
        guard var install = installs[game.gameID.id] else { return }
        install.path = folder
        installs[game.gameID.id] = install
        save(installs, to: Self.installedFile)
        objectWillChange.send()
    }

    // MARK: - Updates

    /// Brings an installed game up to date before it starts ("Update & Play"): gogdl fetches only
    /// what changed, add-ons bought since included, and carries on where an earlier try stopped.
    func update(_ game: Game, progress: @escaping @MainActor (Double?) -> Void) async -> StoreUpdate {
        loadFromDisk()
        let id = game.gameID.id
        guard let install = installs[id] else { return .updated }
        guard isFree, (await Engine.offMain { GOGDL.runningDownloads() })?.isEmpty == true else { return .skipped(.busy) }
        updatingGame = id
        let job = GOGJob(id: id, platform: install.platform, update: true)
        defer {
            updatingGame = nil
            Task { await startNext() }  // downloads asked for meanwhile
        }
        let process: DetachedProcess
        do {
            process = try await GOGDL.start(downloadArguments(job, folder: install.path), log: GOGDL.log(for: id))
        } catch {
            return .skipped(.offline)
        }
        var silent = 0
        while true {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                Legendary.stop(process.processIdentifier)  // it carries on next time
                return .skipped(.offline)
            }
            let state = await Engine.offMain { GOGDL.progress(inLog: GOGDL.logText(for: id)) }
            progress(state.fraction)
            if !process.isRunning || state.exitCode != nil {
                let outcome = Self.updateOutcome(state)
                if outcome == .updated { recordUpdate(id, folder: install.path) }
                return outcome
            }
            // Not a word from GOG for 90 s (a network that doesn't answer): the game starts as it is.
            silent = state.fraction == nil ? silent + 1 : 0
            if silent >= 90 {
                Legendary.stop(process.processIdentifier)
                return .skipped(.offline)
            }
        }
    }

    /// What an update's log says once gogdl has ended.
    nonisolated static func updateOutcome(_ state: GOGDL.Progress) -> StoreUpdate {
        if state.finished { return .updated }
        let reason = state.failure ?? L10n.t("gogdl stopped (code %d)", state.exitCode ?? -1)
        // Nothing written yet: the game's files are as they were, so it starts with them – unless
        // there's no room for the update, which the player has to hear about.
        if state.fraction == nil && !reason.contains(L10n.t("there isn't enough space on the Mac")) { return .skipped(.offline) }
        return .failed(reason)
    }

    private func recordUpdate(_ id: String, folder: URL) {
        guard var install = installs[id] else { return }
        if let build = GOGGameInfo.read(id: id, in: folder)?.build ?? latest[id]?.id { install.build = build }
        install.dlcs = Array(Set(install.dlcs + (catalog.games.first { $0.id == id }?.dlcs.map(\.id) ?? []))).sorted()
        installs[id] = install
        save(installs, to: Self.installedFile)
        try? FileManager.default.removeItem(at: GOGDL.log(for: id))
    }

    // MARK: - Playing

    /// A Windows version's install record and GOG's name for its build, for its setup (GOGRedist).
    func setupFacts(of game: Game) -> (install: GOGInstall, versionName: String?)? {
        loadFromDisk()
        guard let install = installs[game.gameID.id], install.platform == .windows else { return nil }
        let build = latest[install.id]
        return (install, build?.matches(install.build) == true ? build?.version : nil)
    }

    /// How the Windows version starts under Wine, from the game's own info file.
    func launchCommand(for game: Game) throws -> StoreLaunchCommand {
        loadFromDisk()
        let folder = installs[game.gameID.id]?.path ?? game.installDir
        guard let info = GOGGameInfo.read(id: game.gameID.id, in: folder) else {
            throw GOGError.failed(L10n.t("%@ is missing GOG's start information. Download it again.", game.name))
        }
        let command = info.command(in: folder)
        guard FileManager.default.fileExists(atPath: command.executable.path) else {
            throw GOGError.failed(L10n.t("%@ is missing GOG's start information. Download it again.", game.name))
        }
        return command
    }

    /// Starts a Mac version: an app the way macOS opens apps, anything else as the program it is.
    func launchMac(_ game: Game, extraArguments: [String]) async throws {
        loadFromDisk()
        let folder = installs[game.gameID.id]?.path ?? game.installDir
        let info = GOGGameInfo.read(id: game.gameID.id, in: folder)
        let program = folder.pathExtension == "app" ? folder : info.map { folder.appendingPathComponent($0.path) }
        guard let program, FileManager.default.fileExists(atPath: program.path) else {
            throw GOGError.failed(L10n.t("%@ is missing GOG's start information. Download it again.", game.name))
        }
        let arguments = (info?.arguments ?? []) + extraArguments
        // A program inside an app: the app is what starts.
        let app = program.pathComponents.firstIndex { $0.hasSuffix(".app") }
            .map { URL(fileURLWithPath: NSString.path(withComponents: Array(program.pathComponents[...$0]))) }
        if let app {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else {
            let process = DetachedProcess()
            process.executableURL = program
            process.arguments = arguments
            process.currentDirectoryURL = info?.workingDir.map { folder.appendingPathComponent($0, isDirectory: true) } ?? folder
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }
    }

    /// The program the Windows version starts, relative to its folder (what its files reveal).
    nonisolated static func executable(of id: String, in folder: URL) -> String? {
        GOGGameInfo.read(id: id, in: folder)?.path
    }

    /// Whether the game keeps its saves with GOG – known once its saves were synced.
    func hasCloudSaves(_ game: Game) -> Bool? { cloudSaves[game.gameID.id] }

    /// Brings the cloud saves up to date: before playing the newer ones from GOG, afterwards this
    /// Mac's (gogdl never overwrites a newer save with an older one; when both changed it leaves
    /// them as they are). Where the saves live comes from GOG's config for the game.
    func syncSaves(_ game: Game, upload: Bool) async -> CloudSaves.State {
        loadFromDisk()
        let id = game.gameID.id
        guard FileManager.default.fileExists(atPath: GOGDL.authFile.path), let install = installs[id],
              let client = GOGGameInfo.read(id: id, in: install.path)?.clientID,
              let url = URL(string: "https://remote-config.gog.com/components/galaxy_client/clients/\(client)?component_version=2.0.45")
        else { return cloudSaves[id] == true ? .failed : .noCloud }
        guard let config = try? await fetch(url, nil) else { return cloudSaves[id] == true ? .failed : .noCloud }
        guard let locations = GOGSaves.locations(fromConfig: config, platform: install.platform, clientID: client, installDir: install.path,
                                                 windowsUser: Engine.prefix.appendingPathComponent("drive_c/users/crossover", isDirectory: true))
        else {
            cloudSaves[id] = false
            return .noCloud
        }
        cloudSaves[id] = true
        var allDone = true
        for location in locations {
            let key = "\(id)/\(location.name)"
            let result = try? await GOGDL.run(["save-sync", location.folder.path, id, "--os", Self.system(install.platform),
                                               "--ts", String(saveTimes[key] ?? 0), "--name", location.name,
                                               upload ? "--skip-download" : "--skip-upload"], timeout: 300)
            guard let result, result.status == 0,
                  let stamp = result.text.split(whereSeparator: \.isWhitespace).last.flatMap({ Double($0) }) else {
                allDone = false
                continue
            }
            saveTimes[key] = stamp
        }
        save(saveTimes, to: Self.savesFile)
        return allDone ? .synced : .failed
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
}

enum GOGFetchError: Error, Equatable {
    case status(Int)
}
