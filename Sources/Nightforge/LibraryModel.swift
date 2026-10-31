import AppKit
import Combine
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    /// Everything the scan found: each store's entry of a game on its own.
    @Published private(set) var allGames: [Game] = [] {
        didSet { mergeCards() }
    }
    /// One card per game: `allGames` with a game from several stores merged (DuplicateGames).
    @Published private(set) var cards: [Game] = []
    /// What's shown and navigated: `cards` narrowed by the search.
    @Published private(set) var games: [Game] = []
    @Published var selectedIndex = 0 {
        didSet {
            loadStoreDetailsIfNeeded()
            loadStoreSizeIfNeeded()
            if let game = selected { Task { _ = await insight(of: game) } }
        }
    }
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            // Hits show in the library, wherever the search started.
            if !searchText.isEmpty, route != .library {
                rememberSelection()
                route = .library
            }
            applyFilter(selectBestMatch: true)
            searchStore()
        }
    }
    /// Steam store hits for the current search, games the account doesn't own yet.
    @Published private(set) var storeResults: [Game] = []
    private var storeSearch: Task<Void, Never>?
    /// Bumped to move keyboard focus into the search field in the library's header (⌘F, /).
    @Published private(set) var searchFocusRequest = 0
    /// A focus request the field hasn't taken yet: it may only appear with the library.
    private var searchFocusPending = false
    /// Home, the library grid, or a game's page.
    @Published private(set) var route = Route.home {
        didSet { if route != oldValue { history.moved(from: oldValue, to: route, by: historyStep) } }
    }
    /// What forward (the trackpad swipe) can retrace, and what kind of step changes the route now.
    private var history = NavigationHistory()
    private var historyStep = NavigationHistory.Step.other
    /// The games on Home's rail, as indices into `games` (HomeRail).
    @Published private(set) var homeRail: [Int] = []
    /// Where "To start with" begins on Home's rail (StarterPicks); nil once three games were played.
    @Published private(set) var homeStartersFrom: Int?
    /// On Home, the "All games" tile after the rail is selected instead of a game.
    @Published private(set) var homeOnAllGames = false
    /// Games hidden from the library and pinned to Home (GameMarks).
    @Published private(set) var hiddenGames = GameMarks.load(.hidden)
    @Published private(set) var pinnedGames = GameMarks.load(.pinned)
    /// The library shows only the hidden games, to bring them back.
    @Published private(set) var showingHidden = false
    /// What the library grid shows and how it's ordered (only the library applies them).
    @Published var filters = LibraryFilters() {
        didSet { if filters != oldValue { applyFilter() } }
    }
    /// The game each level had selected, so going back to it finds it there again.
    private var homeGameID: String?
    private var libraryGameID: String?
    /// Covers per row in the grid, reported by the grid so ↑/↓ can jump a row.
    var gridColumns = 1
    @Published private(set) var isScanning = false
    /// When the last scan finished: the library's header says how fresh it is.
    @Published private(set) var lastScan: Date?
    @Published private(set) var launchingID: String?
    /// Steam is showing a question (licence, setup) for the game being launched.
    @Published private(set) var launchNeedsConfirmation = false
    /// What the launch is busy with when it's more than waiting for Steam ("Restarting Steam …").
    @Published private(set) var launchPhase: LaunchPhase?
    /// The start in progress is the game's first with these graphics: its shaders get built.
    @Published private(set) var launchBuildsShaders = false

    /// The line under the Play button while a game starts: why it takes a moment.
    var launchHint: String? {
        guard launchingID != nil else { return nil }
        if launchNeedsConfirmation { return LaunchPhase.confirmHint }
        let provider = allGames.first { $0.id == launchingID }?.provider
        if case .updating? = launchPhase, let provider, provider != .steam { return LaunchPhase.storeUpdateHint(provider) }
        if launchPhase == .syncingSaves, provider == .gog { return LaunchPhase.gogSavesHint }
        if let launchPhase { return launchPhase.hint }
        return launchBuildsShaders ? LaunchPhase.shaderHint : nil
    }
    /// A game that ended right after starting with every way Nightforge knows.
    @Published var failedLaunch: FailedLaunch?
    /// Both versions of a game have saves and the one played before has newer ones: which to go on with.
    @Published var saveChoice: SaveChoice?
    private var saveChoiceAnswer: CheckedContinuation<Bool, Never>?

    struct SaveChoice: Identifiable {
        let id = UUID()
        let game: Game
        /// The version played before, whose saves are newer.
        let from: Platform
        let newer: SaveTransfer.Newer
    }
    /// What Nightforge knows about installed games before starting them.
    @Published private(set) var insights: [GameID: GameInsight] = [:]
    private var analyses: [GameID: GameAnalysis] = [:]
    /// The profile list at hand, for how well each game runs (Compatibility), by Steam app ID.
    @Published private(set) var profiles: [Int: GameProfile] = [:]
    @Published var showingOptions = false
    /// Settings, as a dialog over the library (also over it in full screen).
    @Published var showingSettings = false
    /// Waiting for the user to confirm removing this game (or its download).
    @Published var pendingUninstall: Game?
    /// Waiting for the user to confirm removing the Windows version of a game that now runs its Mac one.
    @Published var pendingLeftoverRemoval: Game?
    /// Steam for Mac being set up for a game whose Mac version is wanted.
    @Published var macSetup: MacSteamSetup?
    /// Settings › About: the first start once more on Home – the welcome, the library check and
    /// how many of the games run here.
    func showFirstStartAgain() {
        goHome()
        setup.replay()
    }

    /// The downloads panel under the top bar's ring (D).
    @Published var showingDownloads = false
    /// What Steam is downloading now, in the library's order.
    var downloads: [Game] { allGames.filter { Self.isDownloading($0.install) } }
    /// Speed and time left of each download.
    @Published private(set) var downloadRates: [GameID: DownloadRate] = [:]
    /// A download that wouldn't fit: which games could make room (SpaceCheck) – or a drive to put it on.
    @Published var pendingSpace: SpaceRequest?
    /// A game moving to another drive (DriveMoves), shown with the downloads.
    @Published var move: GameMove?
    /// Settings › Storage's "Move to …": asking where the game goes.
    @Published var pendingMove: Game?
    /// An Epic or GOG game whose download waits for its store to say how big it is.
    @Published private(set) var sizingID: String?
    /// A game about to open in GeForce Now for the first time: what that means is said once.
    @Published var pendingCloudGame: Game?
    /// A demo about to get its free licence in Steam's install window: what that takes is said first.
    @Published var pendingDemoLicense: Game?
    private var macSteamPrewarmed = false
    /// Which of the two Steams runs: the one the next game needs (SteamSwitch).
    let steamSwitch = SteamSwitch()
    @Published private(set) var uninstallingID: String?
    /// Games whose Windows process is running right now, with that process's pid.
    @Published private(set) var running: [String: pid_t] = [:]
    @Published var errorMessage: String?
    @Published var controllerConnected = false
    /// The buttons of the controller in use, as that controller labels them (InputRouter).
    @Published var padSymbols = PadSymbols()
    /// The controller in use and its battery (InputRouter), for the hint bar.
    @Published var controllerStatus: ControllerStatus?
    /// A newer Nightforge release, offered with one click in the top bar.
    @Published private(set) var availableUpdate: AppUpdate?
    @Published private(set) var updating = false
    /// Plugged in or on battery (for the top bar and "Save battery when unplugged").
    @Published private(set) var power = PowerSource.current()
    /// Plugged in, but the charger is too weak for games (3.5).
    @Published private(set) var chargerWarning: ChargerCheck.Warning?
    private var chargerCheck = ChargerCheck()
    /// macOS Low Power Mode: CPU and graphics run much slower, and so do games.
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// The first start: the setup of Nightforge's own Steam, the library check and the reveal.
    let setup = SetupModel()
    /// Steam for Mac in the first start, alongside the setup (MacSteamPrep).
    let macSteamPrep = MacSteamPrep()
    private var setupChanges: AnyCancellable?

    /// The stores the library comes from (7.1); a game's own store downloads, removes and starts it.
    let steam = SteamStore()
    let epic = EpicStore()
    let gog = GOGStore()
    var stores: [StoreProvider] { [steam, epic, gog] }

    func store(for game: Game) -> StoreProvider {
        stores.first { $0.provider == game.provider } ?? steam
    }

    private lazy var input = InputRouter()
    private var inputStarted = false

    init() {
        // The first start ends with how the library runs here, on Home in place of the games.
        setup.onFinished = { [weak self] in
            // Steam's sign-in window had the front; keys and the pad only reach the app in front.
            self?.comeForward()
            self?.checkLibrary()
        }
        // Steam for Mac gets ready once the Windows Steam waits for its sign-in (not in the replay).
        setup.onSignInReady = { [weak self] in
            guard let self, self.setup.isActive, !self.setup.isReplay else { return }
            self.macSteamPrep.start()
        }
        setup.onClosed = { [weak self] in
            guard let self else { return }
            self.macSteamPrep.abandon()
            // Home begins at its first place – Nightforge's recommendation to start – not where the
            // still empty library left the selection (the "All games" tile).
            if self.route == .home {
                self.homeGameID = nil
                self.selectOnHome(place: 0)
            }
        }
        setupChanges = setup.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        epic.changed = { [weak self] in self?.reload(quiet: true) }
        watchDrives()
        epic.downloadFailed = { [weak self] name, reason, addOn in
            self?.errorMessage = addOn
                ? L10n.t("The add-on %@ didn't download: %@. Its game is ready – the add-on follows with its next Update & Play.", name, reason)
                : L10n.t("The download of %@ stopped: %@. Download it again to carry on where it stopped.", name, reason)
        }
        gog.changed = { [weak self] in self?.reload(quiet: true) }
        gog.downloadFailed = { [weak self] name, reason in
            self?.errorMessage = L10n.t("The download of %@ stopped: %@. Download it again to carry on where it stopped.", name, reason)
        }
        gog.tookWindowsVersion = { name in
            Toasts.shared.show(L10n.t("The Mac version of %@ is too old for this Mac – the Windows version comes instead.", name))
        }
    }

    /// Nothing to show and Nightforge's own Steam isn't ready yet.
    var needsSetup: Bool { allGames.isEmpty && !SetupModel.isComplete }
    /// Home shows the first start (SetupView): until the setup is done, then until "Let's Play".
    var showsFirstStart: Bool { setup.isActive || needsSetup }

    var selected: Game? {
        games.indices.contains(selectedIndex) ? games[selectedIndex] : nil
    }

    /// After the button labels changed in Settings.
    func refreshPadSymbols() {
        input.refreshConnected()
    }

    func startInput() {
        guard !inputStarted else { return }
        inputStarted = true
        MacIntegration.model = self
        // Left over from an earlier run whose Steam for Mac has ended since: a Steam the player
        // starts later isn't Nightforge's to quit.
        if !MacSteam.isRunning { MacSteam.startedByNightforge = false }
        Task { await MacSteam.guardWindows() }
        if MacSteam.isTestHome {
            Task { [weak self] in await TestSteam.guardRealSteam { line in self?.errorMessage = line } }
        }
        input.start(model: self)
        watchRunningGames()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))  // after the window and Steam got going
            availableUpdate = await Updater.check()
        }
        // Back from buying in the browser (or from Steam): pick up newly owned games.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload(quiet: true)
                self?.refreshStores()
            }
        }
        refreshStores()
    }

    // MARK: - Stores

    /// When each store was last asked (not only successfully): a store that can't be reached isn't
    /// asked again at every switch back to Nightforge.
    private var storeAsked: [Provider: Date] = [:]

    /// Asks the stores whose library was loaded a while ago again, in the background; what's on
    /// the Mac shows meanwhile. `force`: "Try again".
    func refreshStores(force: Bool = false) {
        for store in stores where store.isConnected && store.sync.state != .syncing {
            let asked = storeAsked[store.provider] ?? .distantPast
            guard force || Date().timeIntervalSince(asked) > 15 * 60 else { continue }
            storeAsked[store.provider] = Date()
            Task { await store.refresh() }
        }
    }

    /// Epic's sign-in page in its own window; its code goes to legendary.
    func connectEpic() {
        guard !epic.connecting else {
            EpicSignIn.bringToFront()
            return
        }
        epic.connecting = true
        Task { await Legendary.prepare() }
        EpicSignIn.present { [weak self] code in
            guard let self else { return }
            guard let code else {
                self.epic.connecting = false
                return
            }
            Task {
                defer { self.epic.connecting = false }
                do {
                    try await self.epic.connect(code: code)
                    self.storeAsked[.epic] = Date()
                    self.reload(quiet: true)
                    Toasts.shared.show(L10n.t("Epic Games is connected – your games are in the library"))
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Epic ended the sign-in: the game needs a fresh one to download or start (its sign-in code
    /// comes from Epic), so Epic's sign-in window opens, with a word on why.
    private func needsEpicSignIn(_ game: Game) -> Bool {
        guard game.provider == .epic, !epic.isSignedIn else { return false }
        Toasts.shared.show(L10n.t("Epic Games signed you out – sign in again to play %@", game.name))
        connectEpic()
        return true
    }

    /// Signs out of Epic Games; the games on this Mac stay there and return with the next sign-in.
    func disconnectEpic() {
        Task {
            await epic.disconnect()
            reload(quiet: true)
        }
    }

    /// Epic's and GOG's cloud saves after a session: how the upload is going (Welcome back sheet).
    @Published private(set) var storeSaves: [GameID: CloudSaves.State] = [:]

    /// After an Epic game: its save goes up to Epic, and its play time is kept.
    private func afterEpicSession(_ game: Game, minutes: Int) {
        epic.recordSession(game, minutes: minutes)
        let hasCloud = epic.catalog.games.contains { $0.appName == game.gameID.id && $0.cloudSaves }
        storeSaves[game.gameID] = hasCloud ? .syncing : .noCloud
        guard hasCloud else { return }
        Task {
            let done = await epic.syncSaves(game, upload: true)
            storeSaves[game.gameID] = done ? .synced : .failed
        }
    }

    // MARK: - GOG

    /// GOG's sign-in page in its own window; its code goes to gogdl.
    func connectGOG() {
        guard !gog.connecting else {
            GOGSignIn.bringToFront()
            return
        }
        gog.connecting = true
        Task { await GOGDL.prepare() }
        GOGSignIn.present { [weak self] code in
            guard let self else { return }
            guard let code else {
                self.gog.connecting = false
                return
            }
            Task {
                defer { self.gog.connecting = false }
                do {
                    try await self.gog.connect(code: code)
                    self.storeAsked[.gog] = Date()
                    self.reload(quiet: true)
                    Toasts.shared.show(L10n.t("GOG is connected – your games are in the library"))
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// GOG ended the sign-in: downloads need a fresh one (the games themselves start without it).
    private func needsGOGSignIn(_ game: Game) -> Bool {
        guard game.provider == .gog, !gog.isSignedIn else { return false }
        Toasts.shared.show(L10n.t("GOG signed you out – sign in again to download %@", game.name))
        connectGOG()
        return true
    }

    func disconnectGOG() {
        Task {
            await gog.disconnect()
            reload(quiet: true)
        }
    }

    /// After a GOG game: its save goes up to GOG, and its play time is kept.
    private func afterGOGSession(_ game: Game, minutes: Int) {
        gog.recordSession(game, minutes: minutes)
        storeSaves[game.gameID] = gog.hasCloudSaves(game) == false ? .noCloud : .syncing
        Task { storeSaves[game.gameID] = await gog.syncSaves(game, upload: true) }
    }

    /// Before a GOG game starts: a waiting update first (Update & Play), then the newest save from
    /// GOG's cloud. False when the start is off (called off, or the update stopped halfway).
    private func beforeGOGStart(_ game: Game) async -> Bool {
        if game.pendingUpdate != nil, gog.isSignedIn {
            launchPhase = .updating(nil)
            awaitingSteam = true
            let outcome = await gog.update(game) { [weak self] fraction in self?.launchPhase = .updating(fraction) }
            awaitingSteam = false
            launchPhase = nil
            if Task.isCancelled { return false }
            switch outcome {
            case .updated, .addOnFailed:
                analyses[game.gameID] = nil  // its files changed
                reload(quiet: true)
            case .skipped(.offline):
                Toasts.shared.show(L10n.t("%@ can't be reached – %@ starts without its update.", Provider.gog.label, game.name))
            case .skipped(.busy):
                Toasts.shared.show(L10n.t("Another %@ download is running – %@ starts now and updates next time.", Provider.gog.label, game.name))
            case .failed(let reason):
                errorMessage = L10n.t("The update of %@ stopped: %@. Press Play again to carry on where it stopped.", game.name, reason)
                reload(quiet: true)
                return false
            }
        }
        if gog.isSignedIn, gog.hasCloudSaves(game) != false {
            launchPhase = .syncingSaves
            _ = await gog.syncSaves(game, upload: false)
            launchPhase = nil
        }
        return !Task.isCancelled
    }

    /// A GOG game's Windows parts – GOG Galaxy's redistributables its manifest names, and its
    /// install script – right after its download and before a start, until they're there
    /// (GOGRedist; nothing to do costs nothing). Something that fails is said, and the game starts anyway.
    private func setUpGOG(_ game: Game, wine: URL, showStatus: Bool) async {
        guard game.platform == .windows, let facts = gog.setupFacts(of: game),
              await Engine.offMain({ GOGRedist.hasWork(facts.install) }) else { return }
        if showStatus { launchPhase = .settingUpWindowsParts(nil) }
        let outcome = await GOGRedist.setUp(facts.install, versionName: facts.versionName, wine: wine) { part in
            if showStatus { self.launchPhase = .settingUpWindowsParts(part) }
        }
        if showStatus { launchPhase = nil }
        guard showStatus, !outcome.failed.isEmpty else { return }
        let parts = outcome.failed.joined(separator: ", ")
        errorMessage = outcome.retried
            ? L10n.t("Not all Windows parts for %@ could be set up (%@). It starts anyway; Nightforge tries again at the next start.", game.name, parts)
            : L10n.t("Not all Windows parts for %@ could be set up (%@). It starts anyway – if it doesn't run right, this may be why.", game.name, parts)
    }

    /// A GOG game's Mac version: no Steam and no Wine – its update and save first, then the app
    /// itself; Nightforge follows it like any game it started.
    private func launchGOGMac(_ game: Game) {
        launchingID = game.id
        GameDisplay.enterGame()
        launchNeedsConfirmation = false
        launchPhase = nil
        let behavior = Prefs.afterLaunch
        let arguments = Launcher.splitArguments(GameOptionsStore.load(game.gameID).extraArgs)
        launchTask = Task {
            defer {
                launchingID = nil
                launchPhase = nil
            }
            guard await beforeGOGStart(game) else { return }
            let installDir = game.installDir
            await Task.detached(priority: .userInitiated) { ControllerCompatibility.prepare(installDir: installDir) }.value
            do {
                try await gog.launchMac(game, extraArguments: arguments)
            } catch {
                errorMessage = L10n.t("%@ couldn't start: %@", game.name, error.localizedDescription)
                return
            }
            gog.recordStart(game)
            launchingID = nil
            startedHere.insert(game.id)
            await bringToFront(game)
            stepBack(behind: game, behavior)
        }
    }

    // MARK: - Running games

    /// Wine shows each game process with its Windows path, e.g.
    /// "C:\…\steamapps\common\Oxygen Train\Oxygen Train.exe" – match that against the install folders.
    private func watchRunningGames() {
        Task {
            while !Task.isCancelled {
                let loaded = libraryLoaded
                let folders = Self.processFolders(allGames)
                let found = await Task.detached(priority: .utility) { Self.runningGames(folders) }.value
                if found != running { running = found }
                if loaded { runningScanned = true }  // only a look with the games known counts
                watchForGameEnd(found)
                if found.isEmpty, launchingID == nil, playing.isEmpty { idleLooks += 1 } else { idleLooks = 0 }
                if idleLooks == 20 {  // a start that never got going (~1 min)
                    GameDisplay.leaveGame()
                    GameBackdrop.hide(after: .zero)
                }
                if steam.restartWhenIdle && found.isEmpty && launchingID == nil && move == nil {
                    steam.restartWhenIdle = false
                    if let wine = await Engine.installedWine() { try? await Engine.restartSteamInBackground(wine) }
                }
                // Every few seconds while it matters (Nightforge in front, a game running or starting),
                // otherwise less often: nothing waits on it then, and the Mac stays quieter. A game
                // that just ended is looked after quickest: the player waits to be back in Nightforge.
                if controllerConnected && NSApp.isActive { input.refreshBattery() }
                let reading = PowerSource.reading()
                if reading.source != power { power = reading.source }
                let warning = chargerCheck.add(reading.source, batteryCurrent: reading.batteryCurrent)
                if warning != chargerWarning { chargerWarning = warning }
                let busy = NSApp.isActive || !found.isEmpty || launchingID != nil
                watchExits(found)
                let pause = Duration.seconds(goneFor > 0 ? 1 : busy ? 3 : 10)
                nap = Task { try? await Task.sleep(for: pause) }
                await nap?.value
            }
        }
    }

    /// The pause between looks; a game's process ending cuts it short.
    private var nap: Task<Void, Never>?
    private var exitWatches: [pid_t: DispatchSourceProcess] = [:]

    /// The processes of the games being played, watched for their end (kqueue): the look that
    /// notices it comes at once rather than up to three seconds later.
    private func watchExits(_ found: [String: pid_t]) {
        let pids = Set(playing.compactMap { found[$0] })
        for (pid, source) in exitWatches where !pids.contains(pid) {
            source.cancel()
            exitWatches[pid] = nil
        }
        for pid in pids where exitWatches[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.nap?.cancel() } }
            source.resume()
            exitWatches[pid] = source
        }
    }

    /// Whether games whose processes are gone have ended: gone at two looks (the end itself wakes
    /// the first, the next is a second later). One that ran for less than a minute gets three
    /// seconds: launchers hand over to the game early on, sometimes with a gap.
    nonisolated static func gameEnded(looksGone: Int, goneFor: TimeInterval, ranFor: TimeInterval) -> Bool {
        looksGone >= 2 && (ranFor >= 60 || goneFor >= 3)
    }

    // MARK: - Back after a game

    /// Games Nightforge started, from when their process shows up until it ends.
    private var startedHere: Set<String> = []
    private var playing: Set<String> = []
    /// When each of them started running, and the play time Steam had for it then.
    private var sessionStarts: [String: (date: Date, totalBefore: Int)] = [:]
    /// The "Welcome back" sheet after a real session (a minute or more).
    @Published var sessionSummary: SessionSummary?
    private var goneFor = 0
    private var goneSince = Date.distantPast
    private var idleLooks = 0

    /// Once the games Nightforge started have all ended (`gameEnded`, about a second after their
    /// processes went), Nightforge comes back to the front: the controller keeps working, and
    /// neither the desktop nor Steam is what the player sees. Until then the page behind the game
    /// says it's on its way (GameBackdrop).
    private func watchForGameEnd(_ found: [String: pid_t]) {
        for id in startedHere.intersection(found.keys) where sessionStarts[id] == nil {
            sessionStarts[id] = (Date(), allGames.first { $0.id == id }?.playtimeMinutes ?? 0)
        }
        playing.formUnion(startedHere.intersection(found.keys))
        startedHere.subtract(playing)
        guard !playing.isEmpty else { return }
        if playing.contains(where: { found[$0] != nil }) {
            if goneFor > 0 { GameBackdrop.playing() }  // a launcher handed over to the game after all
            goneFor = 0
            return
        }
        if goneFor == 0 {
            goneSince = Date()
            GameBackdrop.returning()
        }
        goneFor += 1
        let ranFor = playing.compactMap { sessionStarts[$0]?.date }.map { goneSince.timeIntervalSince($0) }.max() ?? 0
        guard Self.gameEnded(looksGone: goneFor, goneFor: Date().timeIntervalSince(goneSince), ranFor: ranFor) else { return }
        let ended = playing
        playing = []
        goneFor = 0
        // The processes went a moment ago; a margin for the save Steam is still writing.
        let endedAt = Date().addingTimeInterval(-10)
        let endedGames = allGames.filter { ended.contains($0.id) }
        for game in endedGames { steamSwitch.ended(game, at: endedAt) }
        if endedGames.contains(where: { $0.platform == .mac && $0.provider == .steam }) {
            steamSwitch.afterMacGame(facts: { [weak self] in self?.steamFacts ?? SteamSwitch.Facts() },
                                     restartWindows: { [weak self] in await self?.restartWindowsSteam() })
        }
        let sessions = ended.compactMap { id -> SessionSummary? in
            guard let start = sessionStarts.removeValue(forKey: id), let game = allGames.first(where: { $0.id == id }) else { return nil }
            let minutes = Int(Date().timeIntervalSince(start.date) / 60)
            // Shorter is a start that didn't take (LaunchHealth deals with those).
            if game.provider == .epic { afterEpicSession(game, minutes: minutes) }
            if game.provider == .gog { afterGOGSession(game, minutes: minutes) }
            return minutes >= 1 ? SessionSummary(game: game, minutes: minutes, totalBefore: start.totalBefore,
                                                 endedAt: endedAt) : nil
        }
        comeBack()
        sessionSummary = sessions.max { $0.minutes < $1.minutes }
    }

    private func comeBack() {
        MacSteam.hide()
        // Since macOS 14 an app can't push itself to the front; opening it through Launch
        // Services can, and unhides it too. Then its window comes forward over the page behind the
        // game – on a TV it's in Nightforge's own full-screen Space – and only then may the
        // screens change (GameDisplay.backFromGame), where nobody sees it.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                GameDisplay.backFromGame()
                GameBackdrop.hide()
            }
        }
        reload(quiet: true)  // play time, last played
    }

    /// Once a game has the screen: Nightforge stays where it is behind it, the page behind the
    /// game in place of the desktop (GameBackdrop). Hidden, as it used to be, the desktop was all
    /// that showed when the game ended, until Nightforge came back.
    private func stepBack(behind game: Game, _ behavior: AfterLaunch) {
        switch behavior {
        case .quit: NSApp.terminate(nil)
        case .hide, .stay: GameBackdrop.show(game.name, on: GameDisplay.screen) { [weak self] in self?.playing.isEmpty == false }
        }
    }

    /// Nightforge in front again after a Steam window had it (its sign-in), the way it comes back
    /// after a game (comeBack): keys and the pad only reach the app in front.
    func comeForward() {
        guard !NSApp.isActive else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    /// What a game's processes show in `ps`, by game: Wine's Windows path of the game folder, or
    /// for Mac versions the folder itself.
    private static func processFolders(_ games: [Game]) -> [String: String] {
        Dictionary(games.filter(\.isInstalled).map { game in
            game.platform == .mac
                ? (game.installDir.path.lowercased() + "/", game.id)
                : (game.windowsFolderMarker.lowercased(), game.id)
        }, uniquingKeysWith: { first, _ in first })
    }

    nonisolated private static func runningGames(_ folders: [String: String]) -> [String: pid_t] {
        guard !folders.isEmpty else { return [:] }
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,command="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [:] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()

        var result: [String: pid_t] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.drop { $0 == " " }.split(separator: " ", maxSplits: 1)
            guard fields.count == 2, let pid = pid_t(fields[0]) else { continue }
            let command = fields[1].lowercased()
            // Steam's crash handler and similar helpers live in the same folder; the game's
            // own process is the first .exe there that isn't one of those.
            guard !command.contains("crashhandler"), !command.contains("unitycrash") else { continue }
            let windowsProgram = command.contains(".exe")
            for (folder, id) in folders where result[id] == nil {
                // Mac versions: the program itself runs from the folder ("/…/steamapps/common/Game/
                // Game.app/Contents/MacOS/Game"); a script that merely names the folder doesn't count.
                let matches = folder.hasPrefix("/") ? command.hasPrefix(folder) : windowsProgram && command.contains(folder)
                if matches { result[id] = pid }
            }
        }
        return result
    }

    /// The running-game check has looked at the processes at least once, knowing the library.
    private var runningScanned = false
    /// The first library scan has finished.
    private var libraryLoaded = false

    /// The name of the program a process runs ("No Man's Sky"), as crash reports are named.
    nonisolated private static func programName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    /// macOS wrote a crash report for `program` since `date` (~/Library/Logs/DiagnosticReports).
    nonisolated private static func crashed(_ program: String, since date: Date) -> Bool {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.contains { file in
            ["ips", "crash"].contains(file.pathExtension) && file.lastPathComponent.hasPrefix(program)
                && ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= date
        }
    }

    /// From any of its stores: a card plays one copy at a time.
    func isRunning(_ game: Game) -> Bool { game.entries.contains { running[$0.id] != nil } }

    /// A game of this platform is running – Windows games depend on Nightforge's Wine Steam,
    /// Mac versions on Steam for Mac.
    private func anyRunning(_ platform: Platform) -> Bool { runningGame(platform) != nil }

    /// Steam for Mac is busy for a Mac version: one is running or starting. The Wine Steam stays
    /// out of the way then – signing in, it would sign Steam for Mac out (one sign-in per account),
    /// and the game's saves would no longer reach Steam Cloud.
    private var macSteamBusy: Bool {
        anyRunning(.mac) || allGames.contains { $0.id == launchingID && $0.platform == .mac && $0.provider == .steam }
    }

    private func runningGame(_ platform: Platform) -> Game? {
        let ids = Set(running.keys)
        // GOG's Mac versions need no Steam; its Windows versions share the Wine session.
        return allGames.first { ids.contains($0.id) && $0.platform == platform && (platform == .windows || $0.provider == .steam) }
    }

    /// What the Steam switch goes by, now.
    private var steamFacts: SteamSwitch.Facts {
        SteamSwitch.Facts(
            macSteamRunning: MacSteam.isRunning, macSteamOurs: MacSteam.startedByNightforge, macGameBusy: macSteamBusy,
            macDownload: allGames.contains { game in
                (game.platform == .mac && game.provider == .steam && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
            },
            windowsSteamRunning: Engine.isSteamRunning,
            windowsGameBusy: anyRunning(.windows) || allGames.contains { $0.id == launchingID && $0.platform == .windows },
            moving: move != nil)
    }

    /// The Windows Steam starts again in the background, queued like any of its starts, and signs in.
    private func restartWindowsSteam() async {
        guard let wine = await Engine.installedWine() else { return }
        _ = await restartStuckSteam(wine)
    }

    /// Steam can be signed in on one client at a time, so starting the other Steam would sign out
    /// the one a running game uses. Says so and returns false while such a game runs.
    private func otherSteamFree(for platform: Platform) -> Bool {
        guard let busy = runningGame(platform == .mac ? .windows : .mac) else { return true }
        errorMessage = L10n.t("%@ is still running and needs Steam. Steam can be signed in only once at a time, so quit the game first.", busy.name)
        return false
    }

    /// Brings the running game's window to the front.
    func switchToGame(_ game: Game) {
        guard let pid = game.entries.lazy.compactMap({ self.running[$0.id] }).first else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    }

    /// The player asked to rescan (⌘R, the button): the stores are asked again too, not only once
    /// their 15 minutes are up – a sign-in that ran out or came back shows at once.
    func rescan() {
        refreshStores(force: true)
        reload()
    }

    /// `quiet` refreshes without the scanning indicator (used for download progress).
    func reload(quiet: Bool = false) {
        if !quiet { isScanning = true }
        // One scan at a time: two overlapping ones could land in the wrong order and bring back an
        // uninstalled game or an older download state. A request during a scan gets one scan after it.
        guard !scanInFlight else {
            scanAgain = true
            return
        }
        scanInFlight = true
        Task { await rescan() }
    }

    private var scanInFlight = false
    private var scanAgain = false

    /// Reads every store's library from the Mac and shows what it found.
    private func rescan() async {
        antiCheatBlocks = await ProfileStore.shared.antiCheatBlocks()
        profiles = await ProfileStore.shared.knownProfiles()
        var found: [Game] = []
        for store in stores {
            found += await store.library()
        }
        found = LibraryScanner.sorted(found)
        let wasDownloading = Set(allGames.filter { Self.isDownloading($0.install) }.map(\.id))
        let wasRefused = Set(allGames.filter(\.downloadRefused).map(\.id))
        allGames = withStorePrices(found)
        lastScan = Date()
        measureDownloads()
        libraryLoaded = true
        let finished = found.filter { $0.isInstalled && wasDownloading.contains($0.id) }
        for game in finished { prepare(game) }
        applyFilter()
        MacIntegration.announceFinished(finished)
        KeepAwake.update(downloading: found.filter { Self.isDownloading($0.install) && $0.downloadNeedsSpace == nil }.map(\.name))
        if downloads.isEmpty && move == nil { showingDownloads = false }
        MacIntegration.libraryLoaded()
        if let game = finished.first {
            Toasts.shared.show(finished.count == 1 ? L10n.t("%@ is ready to play", game.name) : L10n.t("%ld games are ready to play", finished.count),
                               action: .init(label: L10n.t("Play")) { [weak self] in self?.play(game) })
        }
        // Said once, not left at "Preparing download …": Steam won't fetch a game the account doesn't own.
        if let game = found.first(where: { $0.downloadRefused && !wasRefused.contains($0.id) }) {
            Toasts.shared.show(L10n.t("Steam won't download %@: it isn't in your Steam library.", game.name),
                               action: .init(label: L10n.t("Cancel Download")) { [weak self] in self?.requestUninstall(game) })
        }
        watchDownloads()
        afterScan()
        if scanAgain {
            scanAgain = false
            Task { await rescan() }
        } else {
            scanInFlight = false
            isScanning = false
        }
    }

    /// Steam for Mac starts in the background with Nightforge while it has a Mac version to
    /// download. Not otherwise: it would sign the Wine Steam out (one sign-in per account), which
    /// most games need; Play starts it when a Mac version is played.
    private func afterScan() {
        if MacSteam.isReady { Engine.excludeGamesFromBackup(steamapps: MacSteam.steamapps) }
        let macDownload = allGames.contains { game in
            (game.platform == .mac && game.provider == .steam && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
        if !macSteamPrewarmed, macDownload, MacSteam.isReady, !anyRunning(.windows), launchingID == nil {
            macSteamPrewarmed = true
            if !MacSteam.isRunning { MacSteam.start() }
        }
        takeTurnsDownloading()
    }

    /// One Steam can be signed in at a time, and a signed-out one soon gets no download servers
    /// any more ("Failed to get list of download sources"). With downloads waiting in both, the
    /// signed-in one finishes first, then the other is signed in – not while a game runs or starts.
    private var lastSignInSwitch = Date.distantPast
    /// How far the Mac downloads had got when Steam for Mac last got its turn.
    private var lastMacTurnProgress: Double?

    private func takeTurnsDownloading() {
        // Not while a game moves to another drive: that stops and starts its Steam itself.
        guard launchingID == nil, running.isEmpty, move == nil, Date().timeIntervalSince(lastSignInSwitch) > 120 else { return }
        let macDownload = allGames.contains { game in
            (game.platform == .mac && game.provider == .steam && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
        let windowsDownload = allGames.contains { $0.platform == .windows && $0.bottle.isBuiltIn && Self.isDownloading($0.install) }
        // A Mac download that got nowhere in its last turn (Steam for Mac finds no download
        // servers, say) doesn't get another: Steam for Mac would come up and sign the Wine Steam out
        // every few minutes for nothing. Any progress lets it take turns again.
        // What the scan measured (it asks nettop off the main thread); asking again here would block the window.
        let macProgress = allGames.compactMap { game in
            Self.downloadFraction(game.macPending) ?? (game.platform == .mac && game.provider == .steam ? Self.downloadFraction(game.install) : nil)
        }.reduce(0, +)
        let macStalled = lastMacTurnProgress.map { macProgress <= $0 } ?? false
        if macDownload, MacSteam.isReady, !MacSteam.signedIn, !(windowsDownload && Engine.steamSignedIn), !macStalled {
            lastSignInSwitch = Date()
            lastMacTurnProgress = macProgress
            steamSwitch.stopWindowsForMacDownload()
            Task {
                if MacSteam.isRunning { await MacSteam.quit() }
                MacSteam.start()
            }
        } else if windowsDownload, Engine.isSteamRunning ? Engine.sessionReplaced() : steamSwitch.windowsStopped,
                  !(macDownload && MacSteam.signedIn) {
            lastSignInSwitch = Date()
            Task {
                await steamSwitch.makeWayForWindows(facts: steamFacts, phase: { _ in }, restartWindows: { await self.restartWindowsSteam() })
                if Engine.isSteamRunning, Engine.sessionReplaced() { await restartWindowsSteam() }
            }
        }
    }

    private static func isDownloading(_ state: InstallState?) -> Bool {
        if case .downloading? = state { return true }
        return false
    }

    /// How far a download has got (0 while Steam hasn't worked out its size); nil when it isn't one.
    private static func downloadFraction(_ state: InstallState?) -> Double? {
        if case .downloading(let fraction)? = state { return fraction ?? 0 }
        return nil
    }

    private var downloadWatcher: Task<Void, Never>?

    /// Adds this look's progress to each download's speed; a download that ended drops out.
    private func measureDownloads(now: Date = Date()) {
        var rates: [GameID: DownloadRate] = [:]
        for game in downloads where game.downloadNeedsSpace == nil {
            guard case .downloading(let fraction?) = game.install, game.sizeOnDisk > 0 else { continue }
            var rate = downloadRates[game.gameID] ?? DownloadRate()
            rate.add(bytes: fraction * Double(game.sizeOnDisk), at: now)
            rates[game.gameID] = rate
        }
        if rates != downloadRates { downloadRates = rates }
    }

    /// While Steam downloads something, re-read the manifests every few seconds for progress.
    private func watchDownloads() {
        let downloading = allGames.contains { Self.isDownloading($0.install) || Self.isDownloading($0.macPending) }
        guard downloading, downloadWatcher == nil else { return }
        downloadWatcher = Task {
            try? await Task.sleep(for: .seconds(3))
            downloadWatcher = nil
            reload(quiet: true)
        }
    }

    /// After a setting games get from Steam changed: restart it now if no game would be cut off.
    func applySteamSettings() {
        guard SetupModel.isComplete else { return }
        // Queued behind any start still in progress: two Steam starts at once end up as two
        // Steam instances fighting over the same prefix, and games no longer start.
        let previous = steamStartup
        steamStartup = Task {
            await previous?.value
            guard let wine = await Engine.installedWine(), !macSteamBusy else { return }
            await Engine.offMain { Engine.applyGameEnvironment(wine: wine) }
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
        }
    }

    /// Keeps Nightforge's own Steam running hidden once it's set up.
    /// The engine check and Steam (re)start at app launch; game launches wait for it so a pending
    /// Steam restart can't cut off a game that was just started.
    private var steamStartup: Task<Void, Never>?

    func startBackgroundSteam() {
        // onAppear can fire more than once; one start per app run is enough.
        guard SetupModel.isComplete, steamStartup == nil else { return }
        Task { await ProfileStore.shared.refresh() }
        steamStartup = Task {
            // Let the running-game check see the processes before deciding on a restart – or on
            // replacing the engine's files, which ends the Wine session a game would run in.
            while !runningScanned { try? await Task.sleep(for: .milliseconds(100)) }
            // A new engine that can't be fetched now (offline, broken download): Steam starts with
            // the one already installed, and the new one is tried again at the next start.
            var ensured = try? await Engine.ensureEngine(gameRunning: !running.isEmpty)
            if ensured == nil { ensured = await Engine.installedWine() }
            guard let wine = ensured else { return }
            // Signing in would sign out the Steam for Mac a running Mac game uses; Play starts it later.
            guard !macSteamBusy else { return }
            // A Steam for Mac Nightforge left running – it quit after starting a Mac version and came
            // back when that ended – goes first (SteamSwitch): quit, it finishes its cloud sync;
            // signed out by the Windows Steam, it wouldn't.
            if MacSteam.startedByNightforge, MacSteam.isRunning, !steamFacts.macDownload { await MacSteam.quit() }
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
            Task { await self.watchSteamStart(wine) }
            Task { await self.watchDockHider(wine) }
        }
    }

    /// A Steam that another Nightforge started may load hide-steam-dock.dylib from that one's app
    /// bundle, which can go any time – and with it every program Steam starts (DockHider). Moved over
    /// to the data folder's library with one restart, once nothing needs Steam: no game, no
    /// download, no launch. A game started meanwhile restarts it first if the file is already gone.
    private func watchDockHider(_ wine: URL) async {
        while await Engine.offMain({ DockHider.runningSteamState() }) != .current {
            let downloading = allGames.contains { Self.isDownloading($0.install) || Self.isDownloading($0.macPending) }
            if launchingID == nil, running.isEmpty, !downloading, !launchNeedsConfirmation,
               !(await Engine.offMain { Engine.windowsGameRunning }) {
                _ = await restartStuckSteam(wine, freshSession: true)
                return
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Steam hangs now and then while starting under Wine (see Engine.steamLooksStuck), and one
    /// restart fixes it. Watched for the first two minutes, ideally before anyone presses Play.
    private func watchSteamStart(_ wine: URL) async {
        for _ in 0..<24 {
            try? await Task.sleep(for: .seconds(5))
            if Engine.steamSignedIn { return }
            if launchingID == nil, running.isEmpty, Engine.steamLooksStuck(quietFor: 45) {
                _ = await restartStuckSteam(wine)
                return
            }
        }
    }

    /// Restarts a hung Steam, queued like any other Steam start so a launch waits for it.
    /// True once it has signed in again (up to 90 s). It signs in by itself; when it asks instead
    /// (its remembered sign-in ran out) while a game waits to start, its window comes to the front
    /// and the player gets ten minutes for it. `freshSession`: with a new Wine session (DockHider).
    /// `hung`: it stopped taking commands, so it's ended with its Wine session (no game may run).
    private func restartStuckSteam(_ wine: URL, freshSession: Bool = false, hung: Bool = false) async -> Bool {
        let previous = steamStartup
        let began = Date()
        let restart = Task {
            await previous?.value
            if hung {
                try? await Engine.restartHungSteam(wine)
            } else if freshSession {
                try? await DockHider.restartSteam(wine)
            } else {
                try? await Engine.restartSteamInBackground(wine)
            }
        }
        steamStartup = restart
        await restart.value
        var asked = false
        for second in 0..<600 {
            if Engine.steamSignedIn { return true }
            if !asked, launchingID != nil, SteamLogin.waitingForCredentials(steamRoot: Engine.steamRoot, since: began) {
                asked = true
                launchPhase = .signInAgain
                showSteamWindow()
            }
            if second >= 90 && !asked { return false }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return false }
        }
        return false
    }

    /// The big button: play when installed, otherwise ask Steam to download it.
    func primaryAction() {
        guard let game = selected, uninstallingID != game.id else { return }
        if launchingID == game.id {
            if launchNeedsConfirmation && game.platform == .mac {
                MacSteam.show()
            } else if launchNeedsConfirmation && game.bottle.isBuiltIn {
                showSteamWindow()
            }
            return
        }
        if isRunning(game) {
            switchToGame(game)
            return
        }
        if game.playsInCloud {
            playInCloud(game)
            return
        }
        if waitsForMove(game) { return }
        // On a drive that's unplugged: plugging it in plays it; downloading would make a second copy.
        if game.install == .notInstalled && game.missingDrive != nil { return }
        switch game.install {
        case .installed: launchSelected()
        case .installed where game.antiCheatBlock != nil: break
        case .notInstalled where game.isVROnly || game.antiCheatBlock != nil: break
        case .notInstalled: downloadIfRoom(game)
        case .downloading: if game.downloadNeedsSpace != nil { resumeDownload(game) }
        case .inStore: openStorePage(game)
        }
    }

    /// Anti-cheat games GeForce Now streams open there, with the copy the player owns on Steam.
    /// The first time Nightforge says what that involves (NVIDIA account, free hour) before going.
    func playInCloud(_ game: Game) {
        guard let url = game.antiCheatBlock?.geforceNowURL else { return }
        if UserDefaults.standard.bool(forKey: Prefs.Keys.geforceNowExplained) {
            NSWorkspace.shared.open(url)
        } else {
            pendingCloudGame = game
        }
    }

    func confirmCloud() {
        guard let url = pendingCloudGame?.antiCheatBlock?.geforceNowURL else { return }
        pendingCloudGame = nil
        UserDefaults.standard.set(true, forKey: Prefs.Keys.geforceNowExplained)
        NSWorkspace.shared.open(url)
    }

    /// Buying happens on Steam's own store page in the browser; Nightforge never sees payment data.
    /// Once Steam has the new licence, the game shows up in the library with its Download button.
    func openStorePage(_ game: Game) {
        guard let url = URL(string: "https://store.steampowered.com/app/\(game.demoOf ?? game.appID)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Steam adds a demo's free licence when it's asked to install the demo (steam://install), in
    /// its own install window: once the player has confirmed there, Steam writes the demo's manifest
    /// and downloads it, and the library shows that like any download.
    func addDemoLicense(_ game: Game) {
        pendingDemoLicense = nil
        Task {
            do {
                if try await steam.addDemoLicense(game) { reload(quiet: true) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func installUpdate() {
        guard let update = availableUpdate, !updating else { return }
        updating = true
        Task {
            do {
                try await Updater.install(update)  // quits and restarts Nightforge when done
            } catch {
                updating = false
                if case Updater.Failure.notWritable = error { NSWorkspace.shared.open(update.page) }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Steam store search

    /// Waits for a pause in typing, then asks the store; owned games are left out.
    private func searchStore() {
        storeSearch?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            if !storeResults.isEmpty { storeResults = []; applyFilter() }
            return
        }
        storeSearch = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let hits = await StoreSearch.shared.search(term)
            guard !Task.isCancelled, term == searchText.trimmingCharacters(in: .whitespaces) else { return }
            storeResults = hits.map(storeGame)
            applyFilter()
        }
    }

    /// Games whose anti-cheat stops them on a Mac, so the store search can say so before buying.
    private var antiCheatBlocks: [Int: AntiCheatBlock] = [:]

    private func storeGame(_ hit: StoreSearch.Hit) -> Game {
        var game = Game(
            appID: hit.appID, name: hit.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
            steamExeWindowsPath: Engine.steamExeWindowsPath,
            installDir: Engine.steamRoot.appendingPathComponent("steamapps/common", isDirectory: true),
            sizeOnDisk: 0
        )
        game.install = .inStore
        game.macNative = hit.macNative ?? false
        game.controller = hit.controller ?? .none
        game.storePrice = hit.price
        game.metascore = hit.metascore
        // Store hits don't say whether there's single player, so only blocks that always hold.
        if hit.macNative != true, let block = antiCheatBlocks[hit.appID], !block.onlineOnly { game.antiCheatBlock = block }
        return game
    }

    /// Hits from the games-only search can lack price and platforms; fetch them once it's selected.
    private var storeDetailsRequested: Set<Int> = []
    /// Prices of the library's store entries, once looked up; every scan brings them back.
    private var storePrices: [Int: String] = [:]

    private func withStorePrices(_ games: [Game]) -> [Game] {
        guard !storePrices.isEmpty else { return games }
        return games.map { game in
            var game = game
            if game.install == .inStore, let price = storePrices[game.appID] { game.storePrice = price }
            return game
        }
    }

    private func loadStoreDetailsIfNeeded() {
        guard let game = selected, game.install == .inStore, game.storePrice == nil,
              storeDetailsRequested.insert(game.appID).inserted  // once: some games have no price at all
        else { return }
        Task {
            guard let hit = await StoreSearch.shared.details(for: game.appID) else { return }
            // Also for the library's store entries: games Steam knows that the account doesn't own.
            storePrices[game.appID] = hit.price
            allGames = withStorePrices(allGames)
            guard let index = storeResults.firstIndex(where: { $0.appID == game.appID }) else {
                applyFilter()
                return
            }
            var updated = storeGame(hit)
            updated.metascore = hit.metascore ?? storeResults[index].metascore
            storeResults[index] = updated
            applyFilter()
        }
    }

    /// `drive`: onto that external drive instead of the Mac.
    func download(_ game: Game, drive: URL? = nil) {
        if needsEpicSignIn(game) || needsGOGSignIn(game) { return }
        if game.demoNeedsLicense {
            pendingDemoLicense = game
            return
        }
        if game.platform == .mac && game.provider == .steam {
            downloadMac(game, drive: drive)
            return
        }
        Task {
            do {
                var context = StoreContext(busy: !running.isEmpty || launchingID != nil) { self.reload(quiet: true) }
                context.drive = drive
                try await store(for: game).install(game, context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// An Epic or GOG game not on the Mac yet: how big it is, asked from its store once its page has
    /// been looked at for a moment (not for every cover scrolled past).
    private func loadStoreSizeIfNeeded() {
        guard let game = selected, game.install == .notInstalled, game.sizeOnDisk == 0, game.antiCheatBlock == nil,
              (game.provider == .epic && epic.isSignedIn) || (game.provider == .gog && gog.isSignedIn) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard selected?.id == game.id else { return }
            _ = await storeSize(of: game) { self.selected?.id == game.id }
        }
    }

    /// What an Epic or GOG game takes on the Mac, asked from its store. GOG asks one game at a
    /// time, and not for a page left meanwhile (`stillWanted`).
    private func storeSize(of game: Game, stillWanted: () -> Bool = { true }) async -> Int64? {
        switch game.provider {
        case .epic: return await epic.size(of: game)?.install
        case .gog: return await gog.size(of: game, stillWanted: stillWanted)?.install
        case .steam: return nil
        }
    }

    /// Download, unless it wouldn't fit: then the player picks games to make room first. An Epic or
    /// GOG game whose size isn't known yet asks its store first; without an answer the download
    /// checks for itself.
    private func downloadIfRoom(_ game: Game) {
        guard sizingID == nil else { return }  // a second press while the store is asked
        guard game.sizeOnDisk == 0, (game.provider == .epic && epic.isSignedIn) || (game.provider == .gog && gog.isSignedIn) else {
            downloadIfRoom(game, needed: game.sizeOnDisk)
            return
        }
        sizingID = game.id
        Task {
            let size = await storeSize(of: game)
            sizingID = nil
            downloadIfRoom(game, needed: size ?? 0)
        }
    }

    private func downloadIfRoom(_ game: Game, needed: Int64) {
        let folder = game.installDir
        let free = Self.freeSpace(at: SpaceCheck.existingFolder(for: folder))
        let drives = driveChoices(for: game, needed: needed)
        guard let shortfall = SpaceCheck.shortfall(needed: needed, free: free) else {
            // A drive the player has put games on before: where this one goes is theirs to say.
            if drives.contains(where: { $0.usable && $0.drive.hasLibrary }) {
                pendingSpace = SpaceRequest(game: game, needed: needed, free: free, shortfall: 0, candidates: [], drives: drives)
            } else {
                download(game)
            }
            return
        }
        let removable = allGames.filter { canUninstall($0) && !isRunning($0) && SpaceCheck.sameVolume($0.installDir, folder) }
        pendingSpace = SpaceRequest(game: game, needed: needed, free: free, shortfall: shortfall,
                                    candidates: SpaceCheck.candidates(removable, except: game), drives: drives)
    }

    /// The space sheet's button: uninstall the picked games one after another, then download.
    func freeUpAndDownload(_ ids: Set<String>) {
        guard let request = pendingSpace else { return }
        pendingSpace = nil
        let picked = request.candidates.filter { ids.contains($0.id) }
        Task {
            for game in picked {
                await uninstall(game)
            }
            reload(quiet: true)
            let free = Self.freeSpace(at: SpaceCheck.existingFolder(for: request.game.installDir))
            if SpaceCheck.shortfall(needed: request.needed, free: free) == nil {
                download(request.game)
            } else {
                errorMessage = L10n.t("There's still not enough space: %@ needs %@, your Mac has %@ free.",
                                      request.game.name, Format.bytes(request.needed + SpaceCheck.margin), Format.bytes(free))
            }
        }
    }

    /// A download Steam stopped for lack of disk space: once there's room, unpause it in Steam's
    /// manifest and restart that Steam, which then carries on – by itself it never tries again.
    func resumeDownload(_ game: Game) {
        guard let needed = game.downloadNeedsSpace else { return }
        let free = Self.freeSpace(at: game.installDir.deletingLastPathComponent())
        guard free >= needed else {
            errorMessage = L10n.t("There's still not enough space: Steam needs %@ for %@, your Mac has %@ free.",
                                  Format.bytes(needed), game.name, Format.bytes(free))
            return
        }
        let steamapps = game.installDir.deletingLastPathComponent().deletingLastPathComponent()
        Engine.unpauseDownload(appID: game.appID, steamapps: steamapps)
        Task {
            if game.platform == .mac {
                guard !anyRunning(.mac) else { return }  // it carries on at Steam for Mac's next start
                await MacSteam.quit()
                MacSteam.start()
            } else if let wine = await Engine.installedWine() {
                if running.isEmpty && launchingID == nil {
                    try? await Engine.restartSteamInBackground(wine)
                } else {
                    steam.restartWhenIdle = true
                }
            }
            reload(quiet: true)
        }
    }

    /// Space left for downloads on the volume holding `folder`.
    nonisolated static func freeSpace(at folder: URL) -> Int64 {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Mac versions

    /// Opens the Steam for Mac setup when a game's Mac version is wanted and Steam for Mac isn't
    /// ready yet; Nightforge carries on with `next` once the player has signed in.
    private func needsMacSteam(_ game: Game, then next: MacSteamSetup.Next) -> Bool {
        guard game.platform == .mac, !MacSteam.isReady else { return false }
        guard macSetup == nil else { return true }
        let setup = MacSteamSetup(game: game, next: next)
        setup.onReady = { [weak self] setup in
            guard let self else { return }
            self.macSetup = nil
            switch setup.next {
            case .download: self.downloadMac(setup.game)
            case .play: self.launch(setup.game)
            }
        }
        macSetup = setup
        return true
    }

    func closeMacSetup() {
        macSetup?.cancel()
        macSetup = nil
    }

    /// From the setup sheet: this game keeps to its Windows version.
    func useWindowsVersion(of game: Game) {
        closeMacSetup()
        var options = GameOptionsStore.load(game.gameID)
        options.version = .windows
        GameOptionsStore.save(options, for: game.gameID)
        MacHealth.reset(game.appID)
        reload(quiet: true)
    }

    /// For a game played through its installed Windows version: fetch its Mac version in the
    /// background; the game switches over once it's installed.
    func loadMacVersion(of game: Game) {
        downloadMac(LibraryScanner.macEntry(for: game))
    }

    /// Stops fetching the Mac version (asks first, like any download).
    func cancelMacVersion(of game: Game) {
        var entry = LibraryScanner.macEntry(for: game)
        entry.listID = game.id + "#mac"  // the Windows version stays playable meanwhile
        requestUninstall(entry)
    }

    private func downloadMac(_ game: Game, drive: URL? = nil) {
        guard !needsMacSteam(game, then: .download) else { return }
        guard MacSteam.signedIn || otherSteamFree(for: .mac) else { return }
        Task {
            do {
                if let drive {
                    try await MacSteam.download(appID: game.appID, name: game.name, installDir: game.installDirName,
                                                onDrive: drive, macGameRunning: anyRunning(.mac))
                } else {
                    try await MacSteam.download(appID: game.appID, name: game.name, installDir: game.installDirName,
                                                macGameRunning: anyRunning(.mac))
                }
                reload(quiet: true)
                await watchMacDownloadStart(game)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Steam for Mac normally takes up the requested download within a minute of signing in. If it
    /// hasn't, its install dialog does the same with one click; if it hasn't signed in (an expired
    /// login), its window comes up for that.
    private func watchMacDownloadStart(_ game: Game) async {
        var signedInFor = 0
        for second in 1...180 {
            try? await Task.sleep(for: .seconds(1))
            if MacSteam.downloadStarted(appID: game.appID) { return }
            signedInFor = MacSteam.signedIn ? signedInFor + 1 : 0
            if second == 40 && signedInFor == 0 { MacSteam.show() }
            if signedInFor >= 60 {
                MacSteam.ask("install/\(game.appID)")
                return
            }
        }
    }

    /// Starts a Mac version through Steam for Mac and follows it until the game runs.
    private func launchMac(_ game: Game) {
        guard !needsMacSteam(game, then: .play) else { return }
        guard MacSteam.signedIn || otherSteamFree(for: .mac) else { return }
        launchingID = game.id
        GameDisplay.enterGame()
        launchNeedsConfirmation = false
        launchPhase = nil
        let behavior = Prefs.afterLaunch
        let arguments = GameOptionsStore.load(game.gameID).extraArgs.trimmingCharacters(in: .whitespaces)
        launchTask = Task {
            defer {
                launchingID = nil
                launchNeedsConfirmation = false
                launchPhase = nil
                launchBuildsShaders = false
            }
            // The Windows Steam goes (one sign-in per account on a Mac), once its last game's save is up.
            await steamSwitch.makeWayForMac(facts: steamFacts, phase: { self.launchPhase = $0 })
            let steamStarted = Date()
            if !MacSteam.isRunning {
                launchPhase = .startingSteamForMac
                MacSteam.start()
            } else if MacSteam.sessionReplaced {
                // The Wine Steam signed in since; signing in again needs a fresh start. Without it
                // the game would start without its cloud saves.
                launchPhase = .signingIn
                await MacSteam.quit()
                MacSteam.start()
            }
            // Steam turns commands away until it has signed in and finished starting. It signs in by
            // itself; when it asks instead (its remembered sign-in ran out), its window comes at once,
            // and the player gets ten minutes for it – B or Esc calls the start off.
            var waited = 0
            var asked = false
            while !(MacSteam.signedIn && MacSteam.startupFinished) && (waited < 90 || asked && !MacSteam.signedIn && waited < 600) {
                if !asked, waited == 25 || waited >= 2 && MacSteam.waitingForCredentials(since: steamStarted) {
                    asked = true
                    awaitingSteam = true
                    launchPhase = MacSteam.hasSignedIn && waited < 25 ? .signInAgain : .signInInSteamWindow
                    MacSteam.show()
                }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    awaitingSteam = false
                    return
                }
                waited += 1
            }
            awaitingSteam = false
            launchPhase = nil
            // steam://run/<id>//<arguments>: the extra part goes to the game.
            let extra = arguments.isEmpty ? ""
                : "//" + (arguments.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
            await takeSavesAlong(game, to: .mac)
            let installDir = game.installDir  // the library it's really in, an external drive's included
            await Task.detached(priority: .userInitiated) { ControllerCompatibility.prepare(installDir: installDir) }.value
            let watcher = LaunchWatcher(steamRoot: MacSteam.root, appID: game.appID)
            let launchStarted = Date()
            let run = { MacSteam.open("run/\(game.appID)" + extra) }
            run()
            let start = await waitForMacStart(game, watcher: watcher, send: run)
            switch start {
            case .failed:
                if !fallBackToWindows(game) { errorMessage = L10n.t("Steam couldn't start %@.", game.name) }
                return
            case .cancelled:
                return
            case .noSignOfLife:
                errorMessage = L10n.t("Steam didn't respond, so %@ didn't start. Please try again.", game.name)
                return
            case .processSeen, .steamSaysRunning:
                break
            }
            launchingID = nil
            SteamPriority.watch(game)
            startedHere.insert(game.id)
            // Steam's window may still be up from a question it asked; the game has the stage now.
            MacSteam.hide()
            await bringToFront(game)

            // The first start of a Mac version: does it run past its first seconds? Only judged
            // when its process was seen at all – Steam may know better where a game runs from.
            // Ending early alone isn't a fail (the player may have closed it, or a launcher window);
            // a crash report from macOS is.
            if start == .processSeen && !MacHealth.confirmed(game.appID) {
                let folders = Self.processFolders([game])
                let program = await Task.detached(priority: .utility) {
                    Self.runningGames(folders)[game.id].flatMap(Self.programName)
                }.value
                if await survivesFirstSeconds(game) {
                    MacHealth.confirm(game.appID)
                } else if let program, Self.crashed(program, since: launchStarted), fallBackToWindows(game) {
                    return
                }
            }
            stepBack(behind: game, behavior)
        }
    }

    /// The first start of a game's other version (SaveTransfer): its empty save folders get the
    /// saves the version played before left, so it doesn't start from scratch. Where it has saves
    /// of its own but the other version's are newer, the player picks which to go on with.
    private func takeSavesAlong(_ game: Game, to platform: Platform) async {
        guard game.macNative, SaveTransfer.isSwitch(appID: game.appID, platform: platform) else { return }
        let appID = game.appID
        let installDir = game.installDirName
        // Where each version really is when that's known (an extra library on an external drive),
        // else the default library.
        let started = game.platform == platform ? game.installDir : nil
        let windowsDir = platform == .windows ? started : game.windowsLeftoverDir
        let macDir = platform == .mac ? started : nil
        let profileRules = await ProfileStore.shared.profile(for: appID)?.saves ?? []
        let (rules, places, newer) = await Task.detached(priority: .userInitiated) {
            let macCatalog = MacSteam.root.appendingPathComponent("appcache/appinfo.vdf")
            let rules = SteamCatalog.saveRules(
                appID: appID, steamRoot: FileManager.default.fileExists(atPath: macCatalog.path) ? MacSteam.root : Engine.steamRoot)
                + profileRules
            var places = SaveTransfer.Places()
            places.windowsInstall = windowsDir
                ?? Engine.steamRoot.appendingPathComponent("steamapps/common/\(installDir)", isDirectory: true)
            places.macInstall = macDir ?? MacSteam.steamapps.appendingPathComponent("common/\(installDir)", isDirectory: true)
            return (rules, places, SaveTransfer.newerElsewhere(to: platform, rules: rules, places: places))
        }.value
        if let newer, await askSaveChoice(game, from: platform == .mac ? .windows : .mac, newer: newer) {
            let backup = SaveTransfer.backupFolder(game: game.name, platform: platform)
            do {
                try await Engine.offMain { try SaveTransfer.takeNewer(to: platform, rules: rules, places: places, backup: backup) }
            } catch {
                errorMessage = L10n.t("The newer save couldn't be copied over (%@). %@ starts with its own.", error.localizedDescription, game.name)
            }
        }
        _ = await Task.detached(priority: .userInitiated) {
            SaveTransfer.beforeStart(appID: appID, platform: platform, rules: rules, places: places)
        }.value
    }

    /// Shows the choice and waits for it: true to go on with the other version's newer saves.
    private func askSaveChoice(_ game: Game, from: Platform, newer: SaveTransfer.Newer) async -> Bool {
        saveChoiceAnswer?.resume(returning: false)
        return await withCheckedContinuation { answer in
            saveChoiceAnswer = answer
            saveChoice = SaveChoice(game: game, from: from, newer: newer)
        }
    }

    /// The player's answer (or the sheet closed: keep this version's own).
    func answerSaveChoice(takeNewer: Bool) {
        saveChoice = nil
        saveChoiceAnswer?.resume(returning: takeNewer)
        saveChoiceAnswer = nil
    }

    /// A Mac version that didn't start: "Automatic" moves the game to the best alternative, its
    /// Windows version, and goes on with it at once – starts it when it's installed, else
    /// downloads it. The game's note says so; its options can switch back.
    private func fallBackToWindows(_ game: Game) -> Bool {
        guard game.switchable, GameOptionsStore.load(game.gameID).version == .automatic else { return false }
        MacHealth.fail(game.appID)
        NSApp.activate()
        Task {
            await rescan()  // after the Mac launch has wound down: one launch at a time
            guard let windows = allGames.first(where: { $0.gameID == game.gameID && $0.platform == .windows }) else { return }
            if windows.isInstalled {
                launch(windows)
            } else if windows.install == .notInstalled {
                download(windows)
            }
        }
        return true
    }

    private enum MacStart {
        case processSeen, steamSaysRunning, failed, cancelled, noSignOfLife
    }

    /// Follows the start of a Mac game until its process is there, or Steam's log says it runs.
    /// Steam's questions (licence, first-time setup) wait in its window as long as the player
    /// needs; no sign of life ends after 2 min.
    /// `send` asks Steam again: it turns the command away while it's still starting, and now and
    /// then takes it without a word.
    private func waitForMacStart(_ game: Game, watcher: LaunchWatcher, send: () -> Void) async -> MacStart {
        var watcher = watcher
        let folders = Self.processFolders([game])
        var quietSeconds = 0
        var seconds = 0
        var askingSince: Int?
        var handledRejections = 0
        var resent = 0
        awaitingSteam = true
        defer { awaitingSteam = false }
        while quietSeconds < 120 && seconds < 900 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return .cancelled }
            seconds += 1
            if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil {
                launchNeedsConfirmation = false
                return .processSeen
            }
            let event = watcher.poll()
            if watcher.rejectedCommands > handledRejections && resent < 5 {
                handledRejections = watcher.rejectedCommands
                resent += 1
                try? await Task.sleep(for: .seconds(2))
                send()
                quietSeconds = 0
                continue
            }
            if !watcher.steamReceivedLaunch && seconds % 15 == 0 && resent < 5 {
                resent += 1
                send()
            }
            switch event {
            case .running?:
                // Give the process a few seconds to show up before trusting the log alone.
                for _ in 0..<5 {
                    try? await Task.sleep(for: .seconds(1))
                    if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil {
                        launchNeedsConfirmation = false
                        return .processSeen
                    }
                }
                launchNeedsConfirmation = false
                return .steamSaysRunning
            case .needsConfirmation?:
                askingSince = askingSince ?? seconds
                quietSeconds = 0
            case .continued?:
                launchNeedsConfirmation = false
                askingSince = nil
                quietSeconds = 0
            case .cancelled?:
                return .cancelled
            case .failed?:
                return .failed
            case nil:
                if let since = askingSince {
                    // Steam logs routine steps as questions too and answers them within a second.
                    if seconds - since >= 3, !launchNeedsConfirmation {
                        launchNeedsConfirmation = true
                        MacSteam.show()
                    }
                } else {
                    quietSeconds += 1
                }
            }
        }
        return .noSignOfLife
    }

    // MARK: - Search & views

    /// `selectBestMatch`: while typing, jump to the first hit instead of keeping the old selection.
    private func applyFilter(selectBestMatch: Bool = false) {
        let previous = selected?.id
        let words = Search.key(searchText).split(separator: " ")
        // Hidden games only show where they're brought back from; the filters only in the library.
        var shelf = cards.filter { isHidden($0) == showingHidden }
        if route.level == .library {
            shelf = shelf.filter { filters.admits($0) { compatibility(of: $0).level } }
            shelf = showingHidden ? LibraryFilters(sort: .name).sorted(shelf) : filters.sorted(shelf)
        }
        if words.isEmpty {
            games = shelf
        } else {
            // Word starts first ("ark" → ARK, Arkham), then initials ("rdr2"), then mid-word hits
            // (Amnesia: The Dark Descent); within each, the order above.
            // A game from several stores by the best of its names ("Rocket League®", "Rocket League").
            let ranked = shelf.compactMap { game in
                game.entries.compactMap { Search.rank(name: $0.name, query: searchText) }.min().map { (game, $0) }
            }
            let owned = Set(allGames.map(\.gameID))
            // Store hits are games you don't own: only without filters that ask about your copy.
            let storeHits = showingHidden || filters.status != .all || filters.controller || filters.mac ? []
                : storeResults.filter { !owned.contains($0.gameID) && (!filters.great || compatibility(of: $0).level == .great) }
            games = (0...2).flatMap { rank in ranked.filter { $0.1 == rank }.map(\.0) } + storeHits
        }
        let first = route.level == .library ? gridLayout.order.first ?? 0 : 0
        selectedIndex = selectBestMatch && !words.isEmpty ? first : games.firstIndex(where: { $0.holds(previous) }) ?? first
        if words.isEmpty && !showingHidden {
            let shown = games
            let stage = HomeRail.stage(shown, pinned: pinnedGames) { StarterPicks.order(shown, facts: starterFacts) }
            homeRail = stage.rail
            homeStartersFrom = stage.startersFrom
        } else {
            homeRail = []
            homeStartersFrom = nil
        }
        switch route {
        case .detail(let id, let from) where !games.contains(where: { $0.holds(id) }):
            route = from == .home ? .home : .library  // its game is gone (another scan, another version)
            if route == .home { selectOnHome() }
        case .home where !homeOnAllGames && !homeRail.contains(selectedIndex):
            selectOnHome()
        default:
            break
        }
    }

    /// The search lives in the library's header: from Home or a game's page it opens the library.
    func focusSearch() {
        guard !allGames.isEmpty else { return }
        if route != .library { goLibrary() }
        searchFocusPending = true
        searchFocusRequest += 1
    }

    /// The search field takes a focus request once, when it's asked or when it appears.
    func takeSearchFocus() -> Bool {
        defer { searchFocusPending = false }
        return searchFocusPending
    }

    // MARK: - Navigation

    var showingLibrary: Bool { route == .library }

    /// The game shown big: on Home nil while the "All games" tile is selected, or the first start shows.
    var heroGame: Game? {
        route == .home && (homeOnAllGames || setup.isActive) ? nil : selected
    }

    /// Stands for the "All games" tile in `homeGameID`.
    private static let allGamesTile = "\u{0}all"

    private func rememberSelection() {
        switch route {
        case .home: homeGameID = homeOnAllGames ? Self.allGamesTile : selected?.id
        case .library: libraryGameID = selected?.id
        case .detail: break
        }
    }

    /// Home's selection: the one it had, else the rail's first game, else the "All games" tile. An
    /// empty library (the first start, before Steam sends the games) picks nothing yet: the "All
    /// games" tile would stick once the games are there.
    private func selectOnHome() {
        if homeRail.isEmpty && games.isEmpty { return }
        if homeGameID == Self.allGamesTile || homeRail.isEmpty {
            homeOnAllGames = true
        } else if let index = homeRail.first(where: { games[$0].holds(homeGameID) }) ?? homeRail.first {
            homeOnAllGames = false
            selectedIndex = index
        }
    }

    func goHome() {
        guard route != .home else { return }
        rememberSelection()
        route = .home
        showingHidden = false
        applyFilter()  // without the library's filters
        if !searchText.isEmpty { searchText = "" }  // Home is the whole collection
        selectOnHome()
    }

    func goLibrary() {
        guard route != .library, !allGames.isEmpty else { return }
        rememberSelection()
        route = .library
        applyFilter()  // with its filters
        if let id = libraryGameID, let index = games.firstIndex(where: { $0.holds(id) }) {
            selectedIndex = index
        }
    }

    /// L, ☰ and the top bar's switch: between Home and the library.
    func toggleLibrary() {
        route.level == .library ? goHome() : goLibrary()
    }

    /// The selected game's page. A second click on a cover comes here – it never starts or downloads.
    func openDetail() {
        guard let game = heroGame, !route.isDetail else { return }
        rememberSelection()
        route = .detail(gameID: game.id, from: route.level)
    }

    /// Esc and B: a game's page goes back where it came from, the library first drops its search
    /// and then goes Home. False when there's nothing to go back from.
    @discardableResult
    func back() -> Bool {
        historyStep = .back
        defer { historyStep = .other }
        switch route {
        case .detail(_, .library):
            route = .library
        case .detail(_, .home):
            route = .home
        case .library:
            if !searchText.isEmpty {
                history.forget()
                searchText = ""
            } else if showingHidden {
                history.forget()
                toggleShowingHidden()
            } else {
                goHome()
            }
        case .home:
            return showsFirstStart && (macSteamPrep.back() || setup.back())
        }
        return true
    }

    /// Where back() leads; nil when it stays on this level (the library drops its search or the
    /// hidden games first) or on Home.
    var backTarget: Route? {
        if route == .library, !searchText.isEmpty || showingHidden { return nil }
        return route.parent
    }

    /// Where forward() leads: the level just gone back from, while its game is still there.
    var forwardTarget: Route? {
        guard let next = history.next(from: route) else { return nil }
        if case .detail(let id, let from) = next {
            guard let index = games.firstIndex(where: { $0.holds(id) }) else { return nil }
            if from == .home, !homeRail.contains(index) { return nil }
        }
        return next
    }

    /// Two fingers the other way after going back (the trackpad, like Safari): the level just
    /// left comes back. False when there's nothing to retrace.
    @discardableResult
    func forward() -> Bool {
        guard let next = forwardTarget else { return false }
        historyStep = .forward
        defer { historyStep = .other }
        switch next {
        case .home:
            goHome()
        case .library:
            goLibrary()
        case .detail(let id, _):
            guard let index = games.firstIndex(where: { $0.holds(id) }) else { return false }
            if route == .home { homeOnAllGames = false }
            selectedIndex = index
            openDetail()
        }
        // A game from several stores may start through another store than when its page was left.
        return next.isDetail ? route.isDetail : route == next
    }

    /// Return and A: Home plays the game (its last tile opens the library), the library opens the
    /// game's page, and the page plays it.
    func activate() {
        // Not while a game is just ending: a press meant for its last menu would start it again.
        guard goneFor == 0 else { return }
        switch route {
        case .home:
            if showsFirstStart {
                if !macSteamPrep.primary() { setup.primary() }
            } else {
                homeOnAllGames ? goLibrary() : primaryAction()
            }
        case .library: openDetail()
        case .detail: primaryAction()
        }
    }

    /// Home's rail by place; `homeRail.count` is the "All games" tile.
    func selectOnHome(place: Int) {
        if homeRail.indices.contains(place) {
            homeOnAllGames = false
            selectedIndex = homeRail[place]
        } else if !allGames.isEmpty {
            homeOnAllGames = true
        }
    }

    /// The place of Home's selection on its rail (the tile after the games for "All games").
    var homePlace: Int {
        homeOnAllGames ? homeRail.count : homeRail.firstIndex(of: selectedIndex) ?? 0
    }

    /// What a place on Home's stage is: played lately; the first start Nightforge recommends and
    /// the other starts (nothing played yet); a start after what was played ("Up next"); or, in a
    /// library with three games played lately, just the next game.
    enum HomeRole: Equatable { case played, recommended, starter, upNext, next }

    func homeRole(place: Int) -> HomeRole {
        HomeRail.role(place: place, startersFrom: homeStartersFrom, count: homeRail.count)
    }

    /// What StarterPicks weighs, from what this Mac knows about the game.
    func starterFacts(_ game: Game) -> StarterFacts {
        let steam = game.entries.first { $0.provider == .steam }
        let score = game.metascore ?? steam.flatMap {
            SteamCatalog.storeFacts(appID: $0.appID, steamRoot: $0.steamRoot)?.metascore ?? Metascores.cached($0.appID)
        }
        // Controller support only Steam knows; Epic and GOG don't say.
        return StarterFacts(installed: game.isInstalled, level: compatibility(of: game).level,
                            controller: steam == nil ? nil : game.controller,
                            mac: game.platform == .mac || (game.macNative && game.mac64), metascore: score,
                            size: game.downloadSize ?? game.sizeOnDisk)
    }

    /// Play from somewhere else (a message's button, the Dock menu, a link): shows the game, then
    /// plays it. A game from several stores plays through the one picked – unless that one isn't
    /// installed and this store's copy is (it just finished downloading): then this one, from now on.
    func play(_ game: Game) {
        if let card = card(holding: game.id), card.id != game.id, !card.isInstalled, game.isInstalled {
            chooseStore(game.provider, for: card)
        }
        guard reveal(game) else { return }
        primaryAction()
    }

    /// Selects the game where it's shown – on Home when a search or filter hides it in the library.
    @discardableResult
    func reveal(_ game: Game) -> Bool {
        if !games.contains(where: { $0.holds(game.id) }) { goHome() }
        guard let index = games.firstIndex(where: { $0.holds(game.id) }) else { return false }
        select(index)
        return true
    }

    // MARK: - One card for a game from several stores

    /// The card a store's entry is on (`id` from `allGames`).
    func card(holding id: String) -> Game? {
        cards.first { $0.holds(id) }
    }

    private func mergeCards() {
        cards = LibraryScanner.sorted(DuplicateGames.merge(allGames))
    }

    /// "Start through" on a game's page: the store it plays, downloads and uninstalls through from
    /// now on. Its options and what Nightforge learned stay with each store.
    func chooseStore(_ provider: Provider, for game: Game) {
        // Not while it starts or is being uninstalled through the store picked so far.
        guard provider != game.provider, game.providers.contains(provider), !game.holds(launchingID), !game.holds(uninstallingID)
        else { return }
        StoreChoice.save(provider, for: game.gameIDs)
        mergeCards()
        applyFilter()  // keeps the selection and the page: the card holds the old entry too
    }

    /// A game picked directly (a right-click on its cover).
    func select(_ index: Int) {
        if route == .home { homeOnAllGames = false }
        selectedIndex = index
    }

    // MARK: - Hide & pin

    /// The games in the library, without the hidden ones; a game from several stores once.
    var visibleCount: Int { DuplicateGames.count(cards, hidden: hiddenGames) }

    /// … of one store (a game from several stores counts in each).
    func visibleCount(of provider: Provider) -> Int {
        DuplicateGames.count(cards, hidden: hiddenGames, in: provider)
    }

    /// The hidden games, each once.
    var hiddenCount: Int { cards.lazy.filter { self.isHidden($0) && $0.install != .inStore }.count }

    /// Marked in any of its stores: a game from several stores shares its marks.
    func isHidden(_ game: Game) -> Bool { game.isMarked(in: hiddenGames) }
    func isPinned(_ game: Game) -> Bool { game.isMarked(in: pinnedGames) }

    /// Pinning keeps a game on Home's rail; only games on this Mac are there.
    func canPin(_ game: Game) -> Bool {
        guard !isHidden(game) else { return false }
        switch game.shown.install {
        case .installed, .downloading: return true
        case .notInstalled, .inStore: return false
        }
    }

    /// H: out of the library, Home and searches (or back in), with Undo.
    func toggleHidden(_ game: Game) {
        guard game.install != .inStore else { return }
        let hide = !isHidden(game), wasPinned = isPinned(game)
        mark(game.gameIDs, hidden: hide, pinned: hide ? false : nil)
        Toasts.shared.show(hide ? L10n.t("%@ is hidden from your library", game.name) : L10n.t("%@ is back in your library", game.name),
                           action: .init(label: L10n.t("Undo")) { [weak self] in
                               self?.mark(game.gameIDs, hidden: !hide, pinned: hide && wasPinned ? true : nil)
                           })
    }

    /// P: stays on Home's rail even when it hasn't been played for a while.
    func togglePinned(_ game: Game) {
        guard canPin(game) || isPinned(game) else { return }
        let pin = !isPinned(game)
        mark(game.gameIDs, pinned: pin)
        Toasts.shared.show(pin ? L10n.t("%@ stays on Home – even when you haven't played it for a while", game.name)
                               : L10n.t("%@ is no longer pinned", game.name))
    }

    /// All of a game's stores at once, so it's marked or not wherever it's looked up.
    private func mark(_ games: [GameID], hidden: Bool? = nil, pinned: Bool? = nil) {
        if let hidden {
            if hidden { hiddenGames.formUnion(games) } else { hiddenGames.subtract(games) }
            GameMarks.save(hiddenGames, .hidden)
            if hiddenGames.isEmpty { showingHidden = false }
        }
        if let pinned {
            if pinned { pinnedGames.formUnion(games) } else { pinnedGames.subtract(games) }
            GameMarks.save(pinnedGames, .pinned)
        }
        applyFilter()
    }

    /// The library's "Hidden" switch: only the hidden games, to bring some back – or all games again.
    func toggleShowingHidden() {
        guard showingHidden || !hiddenGames.isEmpty else { return }
        showingHidden.toggle()
        applyFilter()
        selectedIndex = gridLayout.order.first ?? 0
    }

    /// The grid's groups for what the library shows now.
    var librarySections: [LibrarySection] {
        LibrarySection.make(games, sort: filters.sort, searching: !Search.key(searchText).isEmpty, hidden: showingHidden)
    }

    var gridLayout: GridLayout { GridLayout(sections: librarySections.map(\.items), columns: gridColumns) }

    /// The selection is in the grid's first row, where ↑ leaves the grid for the top bar.
    var selectionInTopGridRow: Bool { (gridLayout.position(of: selectedIndex)?.row ?? 0) == 0 }

    /// ↑/↓ in the grid move a whole row, keeping the column (or the last card of a shorter row).
    func moveRow(_ delta: Int) {
        guard showingLibrary, let next = gridLayout.index(from: selectedIndex, rows: delta) else { return }
        selectedIndex = next
    }

    /// ←/→: the rail goes through its games to the "All games" tile, the grid through what it
    /// shows, group by group. A game's page stays on its game.
    func move(_ delta: Int) {
        guard !games.isEmpty else { return }
        switch route {
        case .home:
            selectOnHome(place: max(0, min(homeRail.count, homePlace + delta)))
        case .library:
            if let next = gridLayout.index(from: selectedIndex, steps: delta) { selectedIndex = next }
        case .detail:
            break
        }
    }

    func jump(toStart: Bool) {
        guard !games.isEmpty else { return }
        switch route {
        case .home:
            selectOnHome(place: toStart ? 0 : homeRail.count)
        case .library:
            let order = gridLayout.order
            selectedIndex = (toStart ? order.first : order.last) ?? 0
        case .detail:
            break
        }
    }

    func launchSelected() {
        guard let game = selected else { return }
        launch(game)
    }

    /// The launch in progress, so B or Esc can call it off while Nightforge waits for Steam.
    private var launchTask: Task<Void, Never>?

    /// While Nightforge waits for Steam to start the game (not while it watches a running game's first seconds).
    private(set) var awaitingSteam = false

    /// Stops waiting for a game Steam hasn't started yet. A game that already runs isn't touched.
    func cancelLaunch() {
        guard awaitingSteam else { return }
        launchTask?.cancel()
    }

    private func launch(_ game: Game) {
        guard game.isInstalled, launchingID == nil else { return }
        if needsEpicSignIn(game) { return }
        if game.platform == .mac {
            if game.provider == .gog { launchGOGMac(game) } else { launchMac(game) }
            return
        }
        let viaSteam = game.provider == .steam
        if viaSteam && game.bottle.isBuiltIn && !Engine.steamSignedIn && !otherSteamFree(for: .windows) { return }
        launchingID = game.id
        GameDisplay.enterGame()
        launchNeedsConfirmation = false
        launchPhase = nil
        let behavior = Prefs.afterLaunch
        launchTask = Task {
            defer {
                launchingID = nil
                launchNeedsConfirmation = false
                launchPhase = nil
                launchBuildsShaders = false
            }
            if viaSteam, game.bottle.isBuiltIn {
                await steamSwitch.makeWayForWindows(facts: steamFacts, phase: { self.launchPhase = $0 },
                                                    restartWindows: { await self.restartWindowsSteam() })
                launchPhase = nil
            }
            if viaSteam, game.bottle.isBuiltIn, let startup = steamStartup {
                if !Engine.isSteamRunning { launchPhase = .startingSteam }
                await startup.value
                launchPhase = nil
            }
            // Steam for Mac signed in since and signed this Steam out: sign it in again, or the
            // game starts without its cloud saves.
            if viaSteam, game.bottle.isBuiltIn, Engine.sessionReplaced(), let wine = await Engine.installedWine() {
                launchPhase = .signingIn
                _ = await restartStuckSteam(wine)
                launchPhase = nil
            }
            // A Steam that is still signing in starts the game offline ("Steam is currently in
            // Offline Mode"): wait for it, and start it afresh if it doesn't get there.
            if viaSteam, game.bottle.isBuiltIn, Engine.isSteamSignedIn, !Engine.steamSignedIn, let wine = await Engine.installedWine() {
                launchPhase = .signingIn
                var waited = 0
                while !Engine.steamSignedIn, waited < 45 {
                    try? await Task.sleep(for: .seconds(1))
                    waited += 1
                }
                if !Engine.steamSignedIn { _ = await restartStuckSteam(wine) }
                launchPhase = nil
            }
            if viaSteam, game.bottle.isBuiltIn { await takeSavesAlong(game, to: .windows) }
            // Epic: a waiting update comes first, like Steam's "Update & Play".
            if game.provider == .epic, game.pendingUpdate != nil {
                guard await updateEpic(game) else { return }
            }
            // Epic: the newest save comes down from Epic before the game reads it.
            if game.provider == .epic, epic.catalog.games.contains(where: { $0.appName == game.gameID.id && $0.cloudSaves }) {
                launchPhase = .syncingSaves
                await epic.syncSaves(game, upload: false)
                launchPhase = nil
            }
            // GOG: the same, an update first and then the newest save.
            if game.provider == .gog { guard await beforeGOGStart(game) else { return } }
            var runner = game.bottle.isBuiltIn ? await Engine.installedWine()?.path : Prefs.runnerPath
            let newest = runner
            // Known fixes for this game (profiles/profiles.json) and what its files reveal.
            let profile = viaSteam && game.bottle.isBuiltIn ? await ProfileStore.shared.profile(for: game.appID) : nil
            let insight = await insight(of: game)
            let analysis = insight?.analysis
            let refreshRate = GameDisplay.screen?.maximumFramesPerSecond ?? 60
            // A preset fixes frame limit and MetalFX; "Most compatible" tries the safest way first.
            var options = GameOptionsStore.load(game.gameID).resolved(refreshRate: refreshRate, profile: profile)
            let automatic = game.bottle.isBuiltIn && options.graphics == .automatic
            let attempts = LaunchHealth.ladder(insight?.attempts ?? [], preset: options.preset, profile: profile)
            if automatic { LaunchHealth.review(game.gameID, attempts, steamRoot: game.steamRoot) }
            if game.bottle.isBuiltIn {
                // The last session's frame rates decide this one's automatic frame limit.
                await Task.detached(priority: .utility) {
                    FramePacing.learn(game: game.gameID, installDir: game.installDir)
                }.value
            }

            if let preparing = preparations[game.gameID] {
                launchPhase = .settingUp
                await preparing.value
                launchPhase = nil
            }
            while true {
                // The newest engine – or, for a game it crashed, the one before (EngineRollback).
                var build: EngineBuild?
                if game.bottle.isBuiltIn, let newest {
                    let pinned = EngineRollback.shared.pinnedBuild(game.gameID) != nil
                    let engine = await Engine.engineForStart(game: game.gameID, newest: URL(fileURLWithPath: newest)) {
                        // Steam moves over to the other engine: it starts afresh.
                        if self.launchPhase == nil { self.launchPhase = pinned ? .heldEngine : .startingSteam }
                    }
                    runner = engine.wine.path
                    build = engine.build
                }
                if let runner {
                    await installRuntimes(for: game, profile: profile, analysis: analysis,
                                          wine: URL(fileURLWithPath: runner), showStatus: true)
                    if game.provider == .gog { await setUpGOG(game, wine: URL(fileURLWithPath: runner), showStatus: true) }
                }
                var arguments = analysis?.preferD3D11Arguments ?? []
                var watchFirstSeconds = false
                var wayConfirmed = false
                if automatic, !attempts.isEmpty {
                    let (index, confirmed) = LaunchHealth.current(game.gameID, attempts)
                    options.graphics = attempts[index].graphics
                    arguments = attempts[index].arguments
                    // Every start is watched: a confirmed way can stop working too (an engine or game
                    // update, a part missing) – it then loses its confirmation (below).
                    watchFirstSeconds = true
                    wayConfirmed = confirmed
                    if !confirmed { LaunchHealth.recordStart(game.gameID, attempts) }
                }
                let logMark = GameLog.mark()
                let startedAt = Date()
                LearnedFixes.setLastLaunch(game.gameID, logMark: logMark)
                var (frameLimit, learning) = FramePacing.automaticLimit(game: game.gameID, options: options,
                                                                         profile: profile, refreshRate: refreshRate)
                // On battery with "Save battery" on: 30 FPS, and nothing learned from a capped session.
                let capped = PowerSource.cappedLimit(frameLimit, onBattery: power.onBattery, saveBattery: Prefs.saveBattery)
                if capped != frameLimit {
                    frameLimit = capped
                    learning = false
                }
                // A limit set by a preset, by hand or by the battery says nothing about what the game
                // holds, and mustn't wipe what was learned for Automatic.
                if game.bottle.isBuiltIn, learning {
                    FramePacing.recordStart(game: game.gameID, options: options, profile: profile, refreshRate: refreshRate,
                                            logMark: logMark, limit: frameLimit, learning: learning)
                }
                // A Steam that loads hide-steam-dock.dylib from a file that's gone can't start the game (DockHider).
                if viaSteam, game.bottle.isBuiltIn, !anyRunning(.windows), let runner,
                   await Engine.offMain({ DockHider.runningSteamState() }) == .missing {
                    launchPhase = .startingSteam
                    _ = await restartStuckSteam(URL(fileURLWithPath: runner), freshSession: true)
                    launchPhase = nil
                }
                // Settings a game only takes from the environment come with the Steam that starts it.
                let layer = options.graphics == .automatic ? (profile?.graphics ?? Engine.defaultGraphics) : options.graphics
                // Watched once with each new engine build or way, so one the newest engine crashes is noticed.
                let way = LaunchAttempt(graphics: layer, arguments: arguments).id
                if let build, EngineRollback.shared.needsWatch(game.gameID, build: build, way: way) { watchFirstSeconds = true }
                if viaSteam, game.bottle.isBuiltIn,
                   Engine.prepareLaunchEnvironment(avx: LearnedFixes.avx(game.gameID, profile: profile), d3dMetal: layer == .d3dmetal,
                                                   frameLimit: frameLimit, upscaling: options.effectiveUpscaling(profile: profile),
                                                   retina: profile?.retina == true),
                   Engine.isSteamRunning, !anyRunning(.windows), let runner {
                    launchPhase = .signingIn
                    _ = await restartStuckSteam(URL(fileURLWithPath: runner))
                    launchPhase = nil
                }
                let shaders = LaunchPhase.graphicsSignature(runner: runner, layer: layer,
                                                            components: ComponentStore.localManifest()?.components ?? [])
                launchBuildsShaders = game.bottle.isBuiltIn && LaunchPhase.isFirstStart(game.gameID, signature: shaders)
                let started = viaSteam
                    ? await start(game, runner: runner, options: options, profile: profile, arguments: arguments, frameLimit: frameLimit)
                    : await startDirect(game, runner: runner, options: options, profile: profile, arguments: arguments,
                                        frameLimit: frameLimit, layer: layer)
                guard started else { return }
                if game.bottle.isBuiltIn { LaunchPhase.recordStart(game.gameID, signature: shaders) }
                launchBuildsShaders = false
                launchingID = nil
                if viaSteam, game.bottle.isBuiltIn { SteamPriority.watch(game) }
                startedHere.insert(game.id)
                await bringToFront(game)
                guard watchFirstSeconds else { break }

                // The first start with this way: is the game still there after its first seconds?
                if await survivesFirstSeconds(game, logMark: logMark) {
                    confirmOnceDrawing(game, attempts: automatic ? attempts : [], build: build, way: way, logMark: logMark,
                                       startedAt: startedAt, wasConfirmed: wayConfirmed)
                    break
                }
                // It ended within its first seconds. A confirmed way loses its confirmation only on
                // evidence, and moves on only on a graphics error (Mafia II on DXVK: "DxvkAdapter:
                // Failed to create device", 31.10.2026) – LaunchHealth.earlyEnd.
                let graphicsFailed = GameLog.graphicsFailed(since: logMark)
                if wayConfirmed {
                    let installDir = game.installDir
                    let programs = await Task.detached(priority: .utility) { Set(Engine.executables(in: installDir)) }.value
                    let log = GameLog.text(since: logMark)
                    let drew = LaunchHealth.drewFrames(in: log, programs: programs)
                    let crashed = GameLog.crashed(in: log) || !GameLog.unrealCrashes(in: installDir, since: startedAt).isEmpty
                    switch LaunchHealth.earlyEnd(trusted: true, graphicsFailed: graphicsFailed, crashed: crashed, drew: drew,
                                                 shortEndsBefore: LaunchHealth.shortEnds(game.gameID, attempts)) {
                    case .keep:
                        // Quit early, by the look of it: the game is gone, Nightforge stays in front.
                        LaunchHealth.noteStart(game.gameID, attempts, short: !drew)
                        return
                    case .unconfirm, .nextWay, .confirm:
                        LaunchHealth.unconfirm(game.gameID, attempts)
                    }
                }
                launchingID = game.id
                NSApp.activate()
                // It ran well this way on the engine before and ends at once on the newest: the newest
                // broke it, so it starts with the one before – the way stays.
                if let build, case .rollBack = EngineRollback.shared.afterFailedStart(game.gameID, build: build, way: way) {
                    launchPhase = .rollingBack
                    continue
                }
                let needed = GameLog.missingRuntimes(since: logMark, gameFolder: game.installDirName)
                    .filter { !LearnedFixes.winetricks(game.gameID).contains($0) }
                if !needed.isEmpty {
                    // Wine said what's missing: install it and try the same way again.
                    LearnedFixes.addWinetricks(needed, for: game.gameID)
                    continue
                }
                if game.bottle.isBuiltIn, Engine.applyFileEdits(profile?.fileEdits ?? [], installDir: game.installDir, game: game.gameID.key) {
                    // The game wrote its settings file at its first start, with a setting its
                    // profile turns off: the same way again, with the file fixed.
                    continue
                }
                if game.bottle.isBuiltIn, LearnedFixes.avx(game.gameID, profile: profile),
                   GameLog.illegalInstruction(since: logMark, installDir: game.installDir, startedAt: startedAt) {
                    // Rosetta's AVX hint sent it down a path Rosetta can't run: the same way without it.
                    LearnedFixes.setNoAVX(game.gameID)
                    continue
                }
                // Graphics chosen by hand, or nothing known about the game: no other way to try.
                guard automatic, !attempts.isEmpty else { break }
                // A way that worked before and ended without a graphics error keeps its place:
                // watched again at the next start. Nightforge stays in front.
                if wayConfirmed && !graphicsFailed { return }
                if LaunchHealth.advance(game.gameID, attempts) {
                    let next = attempts[LaunchHealth.current(game.gameID, attempts).index]
                    launchPhase = .retrying(next.label)
                    continue
                }
                // One way only (Vulkan, DirectX 12): what the game draws with says more than a layer.
                let tried = attempts.count > 1 ? attempts.map(\.label) : [analysis?.summary ?? attempts.first?.label ?? ""]
                failedLaunch = FailedLaunch(game: game, tried: tried)
                return
            }

            stepBack(behind: game, behavior)
        }
    }

    /// Runtimes the profile asks for and those an earlier start turned out to need, and Wine Mono
    /// for .NET games. `showStatus` says so on the Play button while it takes.
    private func installRuntimes(for game: Game, profile: GameProfile?, analysis: GameAnalysis?,
                                 wine: URL, showStatus: Bool) async {
        let learned = LearnedFixes.winetricks(game.gameID)
        let missing = Engine.missingWinetricks((profile?.winetricks ?? []) + learned.filter { $0 != GameLog.wineMono })
            .filter(Engine.isSafeWinetricksVerb)
        if !missing.isEmpty {
            if showStatus { launchPhase = .settingUp }
            await Engine.installWinetricks(missing, wine: wine)
            if showStatus { launchPhase = nil }
        }
        if game.bottle.isBuiltIn, analysis?.usesDotNet == true || learned.contains(GameLog.wineMono),
           !Engine.wineMonoInstalled {
            if showStatus { launchPhase = .settingUpDotNet }
            await Engine.installWineMono(wine)
            if showStatus { launchPhase = nil }
        }
    }

    /// Games being set up in the background right after their download; Play waits for them.
    private var preparations: [GameID: Task<Void, Never>] = [:]

    /// A Windows game Steam has just finished downloading gets what it needs to start (runtimes,
    /// .NET) now, while nobody waits – so its first Play starts it at once. Not while a game runs
    /// or starts: that one gets the Mac's full attention, and Play does the setup then.
    private func prepare(_ game: Game) {
        guard game.bottle.isBuiltIn, game.platform == .windows, preparations[game.gameID] == nil,
              running.isEmpty, launchingID == nil
        else { return }
        preparations[game.gameID] = Task {
            defer { preparations[game.gameID] = nil }
            guard let wine = await Engine.installedWine() else { return }
            let profile = await ProfileStore.shared.profile(for: game.appID)
            let analysis = await insight(of: game)?.analysis
            await installRuntimes(for: game, profile: profile, analysis: analysis, wine: wine, showStatus: false)
            if game.provider == .gog { await setUpGOG(game, wine: wine, showStatus: false) }
        }
    }

    /// Hands the game to Steam and follows Steam's log until the game runs. True once it does; a
    /// question from Steam can take as long as the player needs, no sign of life ends after 2 min.
    private func start(_ game: Game, runner: String?, options: GameOptions, profile: GameProfile?,
                       arguments: [String], frameLimit: Int) async -> Bool {
        var watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
        // Running, signed in and done starting: Steam logs the command within a second (SteamCommands).
        var steamWasReady = game.bottle.isBuiltIn && Engine.isSteamRunning && Engine.steamSignedIn
            && Engine.startupFinished(steamRoot: Engine.steamRoot)
        var client: DetachedProcess?
        var sentAt = Date()
        do {
            // Off the main thread: it reads Steam's app catalog and writes the registry, which
            // would freeze the window for a moment.
            client = try await Task.detached(priority: .userInitiated) {
                try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                    frameLimit: frameLimit, extraArguments: arguments)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        var quietSeconds = 0
        var totalSeconds = 0
        var askingSince: Int?
        var retriedAfterRestart = false
        var signedInSince: Int?
        var resent = false
        awaitingSteam = true
        defer { awaitingSteam = false }
        while quietSeconds < 120 && totalSeconds < 900 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return false }
            // Steam updates the game first ("Update & Play"): that's no silence, however long it takes.
            if let update = await Task.detached(priority: .utility, operation: { LibraryScanner.updateState(of: game) }).value,
               update.isRunning {
                launchPhase = .updating(update.fraction)
                quietSeconds = 0
                continue
            } else if case .updating? = launchPhase {
                launchPhase = nil
            }
            totalSeconds += 1
            switch watcher.poll() {
            case .running?:
                launchNeedsConfirmation = false
                return true
            case .needsConfirmation?:
                askingSince = askingSince ?? totalSeconds
                quietSeconds = 0
            case .continued?:
                launchNeedsConfirmation = false
                askingSince = nil
                quietSeconds = 0
            case .cancelled?:
                return false
            case .failed?:
                errorMessage = L10n.t("Steam couldn't start %@.", game.name)
                return false
            case nil:
                // A Steam that was ready and hasn't taken the command has stopped taking any – also
                // signed in (SteamCommands). Restarted once, without its "-shutdown" (it wouldn't
                // take that either), and asked again.
                if steamWasReady, !retriedAfterRestart, let runner,
                   SteamCommands.hung(steamWasReady: true, received: watcher.steamReceivedLaunch,
                                      sentAgo: Date().timeIntervalSince(sentAt)) {
                    retriedAfterRestart = true
                    steamWasReady = false  // the fresh Steam may lose a request while starting: resent below
                    guard running.isEmpty, !(await Engine.offMain { Engine.windowsGameRunning }) else {
                        errorMessage = L10n.t("Steam isn't responding, and restarting it would end the game that's running. Quit that game and press Play again.")
                        return false
                    }
                    if client?.isRunning == true { client?.terminate() }
                    launchPhase = .steamNotResponding
                    if await restartStuckSteam(URL(fileURLWithPath: runner), hung: true) {
                        watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
                        signedInSince = nil
                        sentAt = Date()
                        client = try? await Task.detached(priority: .userInitiated) {
                            try Launcher.launch(game, runnerPath: runner, options: options, profile: profile,
                                                frameLimit: frameLimit, extraArguments: arguments)
                        }.value
                    }
                    launchPhase = nil
                    quietSeconds = 0
                    continue
                }
                // A request that arrives while Steam is still starting can get lost. Once Steam has
                // signed in and still hasn't logged it, ask once more.
                if game.bottle.isBuiltIn, !steamWasReady, !watcher.steamReceivedLaunch, !resent {
                    if signedInSince == nil, Engine.steamSignedIn { signedInSince = totalSeconds }
                    if let since = signedInSince, totalSeconds - since >= 10 {
                        resent = true
                        sentAt = Date()
                        client = try? await Task.detached(priority: .userInitiated) {
                            try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                                frameLimit: frameLimit, extraArguments: arguments)
                        }.value
                        continue
                    }
                }
                // Steam never took the request and has gone silent: it hung while starting.
                // Restart it once and ask again.
                if game.bottle.isBuiltIn, !watcher.steamReceivedLaunch, !retriedAfterRestart,
                   totalSeconds % 5 == 0, running.isEmpty, let runner, Engine.steamLooksStuck(quietFor: 30) {
                    retriedAfterRestart = true
                    launchPhase = .restartingSteam
                    if await restartStuckSteam(URL(fileURLWithPath: runner)) {
                        watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
                        sentAt = Date()
                        client = try? await Task.detached(priority: .userInitiated) {
                            try Launcher.launch(game, runnerPath: runner, options: options, profile: profile,
                                                frameLimit: frameLimit, extraArguments: arguments)
                        }.value
                    }
                    launchPhase = nil
                    quietSeconds = 0
                    continue
                }
                guard let since = askingSince else {
                    quietSeconds += 1
                    continue
                }
                // Steam logs routine steps as questions too and answers them within a second;
                // a real question waits for the player in Steam's window, which runs hidden –
                // so only then say so and show it.
                if totalSeconds - since >= 3, !launchNeedsConfirmation {
                    launchNeedsConfirmation = true
                    if game.bottle.isBuiltIn { showSteamWindow() }
                }
            }
        }
        // No sign of life for two minutes: say so instead of quietly turning back into Play.
        errorMessage = L10n.t("Steam didn't respond, so %@ didn't start. Please try again.", game.name)
        return false
    }

    /// Brings an Epic game up to date before it starts, its progress on the Play button. Without
    /// Epic, or while another Epic download runs, the version on the Mac starts (Epic allows that).
    /// False when the start is off: called off, or the update stopped halfway (Play carries on with it).
    private func updateEpic(_ game: Game) async -> Bool {
        launchPhase = .updating(nil)
        awaitingSteam = true
        let outcome = await epic.update(game) { [weak self] fraction in self?.launchPhase = .updating(fraction) }
        awaitingSteam = false
        launchPhase = nil
        if Task.isCancelled { return false }
        switch outcome {
        case .updated:
            analyses[game.gameID] = nil  // its files changed
            reload(quiet: true)
        case .skipped(.offline):
            Toasts.shared.show(L10n.t("Epic Games can't be reached – %@ starts without its update.", game.name))
        case .skipped(.busy):
            Toasts.shared.show(L10n.t("Another Epic download is running – %@ starts now and updates next time.", game.name))
        case .failed(let reason):
            errorMessage = L10n.t("The update of %@ stopped: %@. Press Play again to carry on where it stopped.", game.name, reason)
            reload(quiet: true)
            return false
        case .addOnFailed(let addOn, let reason):
            Toasts.shared.show(L10n.t("The add-on %@ didn't update (%@) – %@ starts without it and tries again next time.",
                                      addOn, reason, game.name))
            reload(quiet: true)
        }
        return true
    }

    /// A game from another store starts straight with Nightforge's engine, no Steam in between: the
    /// store hands over how (Epic: legendary's parameters with a fresh sign-in; GOG: the game's own
    /// info file), and Nightforge waits until its process is there. Whether it keeps running,
    /// `survivesFirstSeconds` sees.
    private func startDirect(_ game: Game, runner: String?, options: GameOptions, profile: GameProfile?,
                             arguments: [String], frameLimit: Int, layer: GraphicsLayer) async -> Bool {
        guard let runner else {
            errorMessage = L10n.t("Nightforge's engine isn't installed yet. Open Settings › Stores, or restart Nightforge to set it up.")
            return false
        }
        awaitingSteam = true
        defer { awaitingSteam = false }
        if game.provider == .epic { launchPhase = .signingInEpic }
        let command: StoreLaunchCommand
        do {
            command = game.provider == .gog ? try gog.launchCommand(for: game) : try await epic.launchCommand(for: game)
        } catch {
            launchPhase = nil
            if !Task.isCancelled { errorMessage = L10n.t("%@ couldn't start: %@", game.name, error.localizedDescription) }
            return false
        }
        launchPhase = nil
        guard !Task.isCancelled else { return false }
        let environment = Engine.directLaunchEnvironment(avx: LearnedFixes.avx(game.gameID, profile: profile), d3dMetal: layer == .d3dmetal,
                                                         frameLimit: frameLimit, upscaling: options.effectiveUpscaling(profile: profile))
        let process: DetachedProcess
        do {
            process = try await Task.detached(priority: .userInitiated) {
                try Launcher.launchDirect(game, command: command, runnerPath: runner, options: options, profile: profile,
                                          frameLimit: frameLimit, extraArguments: arguments, environment: environment)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        if game.provider == .gog { gog.recordStart(game) } else { epic.recordStart(game) }
        // Its process shows up within seconds; one that ends before that is the next way's business.
        let folders = Self.processFolders([game])
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return false }
            if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil { break }
            if !process.isRunning { break }
        }
        return true
    }

    /// Confirms the way a game started with once it has drawn frames (LaunchHealth.verdict), watching
    /// in the background from the end of its first seconds. One that ends without a frame stays
    /// unconfirmed and is watched again next time.
    private func confirmOnceDrawing(_ game: Game, attempts: [LaunchAttempt], build: EngineBuild?, way: String,
                                    logMark: UInt64, startedAt: Date, wasConfirmed: Bool = false) {
        let folders = Self.processFolders([game])
        let installDir = game.installDir
        Task {
            let programs = await Task.detached(priority: .utility) { Set(Engine.executables(in: installDir)) }.value
            var absent = 0
            while true {
                let (text, running) = await Task.detached(priority: .utility) {
                    (GameLog.text(since: logMark), Self.runningGames(folders)[game.id] != nil)
                }.value
                // Gone for two looks (10 s): a launcher handing over leaves a shorter gap.
                absent = running ? 0 : absent + 1
                let verdict = LaunchHealth.verdict(drewFrames: LaunchHealth.drewFrames(in: text, programs: programs),
                                                   running: absent < 2, ranFor: Date().timeIntervalSince(startedAt))
                switch LaunchHealth.afterFirstSeconds(verdict) {
                case .confirm:
                    if !attempts.isEmpty { LaunchHealth.confirm(game.gameID, attempts) }
                    if let build { EngineRollback.shared.recordGood(game.gameID, build: build, way: way) }
                    return
                case _ where verdict == .ended:
                    // Past its first seconds without a picture: no evidence against a confirmed way
                    // (most layers log no frames), and no short start either.
                    if wasConfirmed, !attempts.isEmpty { LaunchHealth.noteStart(game.gameID, attempts, short: false) }
                    return
                default:
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    /// Whether the game is still running `LaunchHealth.failureWindow` seconds after it started.
    /// A launcher handing over to the game leaves a gap of a few seconds, so only a longer absence
    /// counts as the game having ended. A game whose Direct3D layer failed (GameLog) is ended here:
    /// it would only sit behind its own error box.
    private func survivesFirstSeconds(_ game: Game, logMark: UInt64? = nil) async -> Bool {
        let folders = Self.processFolders([game])
        let started = Date()
        var absent = 0
        while Date().timeIntervalSince(started) < LaunchHealth.failureWindow || (absent > 0 && absent < 10) {
            try? await Task.sleep(for: .seconds(1))
            let pid = await Task.detached(priority: .utility) { Self.runningGames(folders)[game.id] }.value
            absent = pid == nil ? absent + 1 : 0
            if absent >= 10 { return false }
            if let pid, let logMark, GameLog.graphicsFailed(since: logMark) {
                kill(pid, SIGTERM)
                // Steam has to see it gone before the next way can start.
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(1))
                    if await Task.detached(priority: .utility, operation: { Self.runningGames(folders)[game.id] }).value == nil { break }
                }
                return false
            }
        }
        return true
    }

    /// What a game's files reveal (read once per game and app run) and the ways to start it.
    private var analyzing: [GameID: Task<GameAnalysis, Never>] = [:]

    func insight(of game: Game) async -> GameInsight? {
        guard game.bottle.isBuiltIn, game.isInstalled else { return nil }
        let analysis: GameAnalysis
        if let known = analyses[game.gameID] {
            analysis = known
        } else {
            // Scrolling through the covers asks again before the first look is done: one look per game.
            let running = analyzing[game.gameID] ?? Task.detached(priority: .utility) {
                GameAnalysis.analyze(installDir: game.installDir,
                                     launchExecutable: game.provider == .epic ? EpicStore.executable(of: game.gameID.id)
                                         : game.provider == .gog ? GOGStore.executable(of: game.gameID.id, in: game.installDir)
                                         : SteamCatalog.launchExecutable(appID: game.appID, steamRoot: game.steamRoot))
            }
            analyzing[game.gameID] = running
            analysis = await running.value
            analyzing[game.gameID] = nil
            analyses[game.gameID] = analysis
        }
        let profile = await ProfileStore.shared.profile(for: game.appID)
        let insight = GameInsight(analysis: analysis, attempts: LaunchHealth.attempts(for: analysis, profile: profile))
        if insights[game.gameID] != insight { insights[game.gameID] = insight }
        return insight
    }

    /// How well it runs on a Mac, from the profile list and what this Mac learned about it.
    func compatibility(of game: Game) -> Compatibility {
        Compatibility.of(game, profile: game.gameID.steamAppID.flatMap { profiles[$0] }, analysis: insights[game.gameID]?.analysis)
    }

    /// The previous engine this game runs with, because the newest crashed it (EngineRollback).
    func heldEngine(of game: Game) -> HeldBuild? {
        guard game.bottle.isBuiltIn, game.platform == .windows, game.isInstalled else { return nil }
        return EngineRollback.shared.pinnedBuild(game.gameID)
    }

    /// "Try the newest now": the next start uses the newest engine; should it crash again,
    /// Nightforge switches back by itself.
    func tryNewestEngine(_ game: Game) {
        let rollback = EngineRollback.shared
        let held = rollback.pinnedBuild(game.gameID)
        objectWillChange.send()
        rollback.tryNewest(game.gameID)
        let history = rollback.history()
        guard let current = history.current else { return }
        Toasts.shared.show(L10n.t("Next start uses the newest engine (%@). If it crashes again, Nightforge switches back by itself.",
                                  EngineRollback.label(current, setUp: history.currentSetUp, other: held?.build)))
    }

    /// The detail page's "Add to Applications": a little app that opens the game, found by Spotlight.
    func addShortcut(for game: Game) {
        Task {
            let cover = await ArtworkStore.shared.image(for: game, kind: .cover)
            do {
                let app = try GameShortcut.create(for: game, icon: cover)
                shortcutsChanged += 1
                Toasts.shared.show(L10n.t("%@ is in Applications now – Spotlight finds it", game.name),
                                   action: .init(label: L10n.t("Show")) { NSWorkspace.shared.activateFileViewerSelecting([app]) })
            } catch {
                errorMessage = L10n.t("%@ couldn't be added to Applications: %@", game.name, error.localizedDescription)
            }
        }
    }

    /// Bumped when a game's app was added, so its button turns into "Show in Applications".
    @Published private(set) var shortcutsChanged = 0

    /// After a failed start: every way again from the first, as if the game were new.
    func startOver(_ failed: FailedLaunch) {
        failedLaunch = nil
        LaunchHealth.reset(failed.game.gameID)
        play(failed.game)
    }

    /// After a failed start: "Most compatible" from now on, starting again with its safest way.
    func startMostCompatible(_ failed: FailedLaunch) {
        failedLaunch = nil
        GameOptionsStore.choose(.compatible, for: failed.game.gameID)
        LaunchHealth.reset(failed.game.gameID)
        play(failed.game)
    }

    func openSettings() {
        NSApp.windows.first { $0.title == "Nightforge" }?.makeKeyAndOrderFront(nil)
        showingSettings = true
    }

    /// Closes the settings, then does what asks in the main window (a question, a sheet).
    func closeSettings(then action: @escaping () -> Void) {
        showingSettings = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))  // one sheet closes before the next opens
            action()
        }
    }

    /// After a failed start: the game's options, where the graphics layer is picked by hand.
    func chooseGraphicsByHand(_ failed: FailedLaunch) {
        failedLaunch = nil
        guard reveal(failed.game) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))  // one sheet closes before the next opens
            showingOptions = true
        }
    }

    /// Opens a pre-filled problem report for the game in the browser.
    func reportProblem(for game: Game, tried: [String] = []) {
        Task {
            ProblemReport.open(game: game, insight: await insight(of: game),
                               profile: await ProfileStore.shared.profile(for: game.appID), tried: tried)
        }
    }

    /// Steam starts the game in the background, and since macOS 14 an app can't push itself to
    /// the front. Nightforge is the active app at this point, so it hands activation over as soon
    /// as the game shows its window (Wine makes it a regular app then) – before quitting or hiding.
    private func bringToFront(_ game: Game) async {
        let folders = Self.processFolders([game])
        var absent = 0
        for _ in 0..<60 {
            let pid = await Task.detached(priority: .utility) { Self.runningGames(folders)[game.id] }.value
            absent = pid == nil ? absent + 1 : 0
            if absent >= 10 { return }  // gone again: it crashed before showing a window
            if let pid, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                guard NSApp.isActive else { return }  // the player has moved on to something else
                // Already there while macOS changes to the game's Space (on a TV it has one of its own).
                GameBackdrop.show(game.name, on: GameDisplay.screen) { [weak self] in self?.playing.isEmpty == false }
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [])
                try? await Task.sleep(for: .milliseconds(600))
                if app.isActive { return }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Brings Steam's main window, with the question it's waiting on, in front of Nightforge.
    func showSteamWindow() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            Engine.showSteamWindow(wine)
            await SteamWindow.bringForward()  // in front of Nightforge, once it's there
        }
    }

    // MARK: - Uninstall

    /// Only games in Nightforge's own Steam or Steam for Mac; CrossOver bottles are managed by their
    /// own Steam. Uninstalling stops that Steam for a moment, so not while one of its games runs or
    /// anything starts – it would go too.
    func canUninstall(_ game: Game) -> Bool {
        guard game.isInstalled || game.downloadRefused || { if case .downloading = game.install { return true } else { return false } }()
        else { return false }
        guard uninstallingID == nil && launchingID == nil && move == nil else { return false }
        if game.provider == .gog && game.platform == .mac { return !isRunning(game) }
        if game.platform == .mac { return !anyRunning(.mac) }
        return game.bottle.isBuiltIn && !anyRunning(.windows)
    }

    /// The Windows version a game left behind when it moved to its Mac version.
    func requestLeftoverRemoval(_ game: Game) {
        guard game.windowsLeftover != nil, uninstallingID == nil, launchingID == nil, !anyRunning(.windows) else { return }
        pendingLeftoverRemoval = game
    }

    func confirmLeftoverRemoval() {
        guard let game = pendingLeftoverRemoval else { return }
        pendingLeftoverRemoval = nil
        uninstallingID = game.id
        Task {
            defer {
                uninstallingID = nil
                reload(quiet: true)
            }
            do {
                guard let wine = await Engine.installedWine(), let leftover = game.windowsLeftoverDir else { return }
                try await Engine.uninstall(appID: game.appID, installDir: leftover, wine: wine)
            } catch {
                errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, error.localizedDescription)
            }
        }
    }

    func requestUninstall(_ game: Game? = nil) {
        guard let game = game ?? selected, canUninstall(game) else { return }
        pendingUninstall = game
    }

    func confirmUninstall() {
        guard let game = pendingUninstall else { return }
        pendingUninstall = nil
        Task {
            await uninstall(game)
            reload(quiet: true)
        }
    }

    private func uninstall(_ game: Game) async {
        uninstallingID = game.id
        defer { uninstallingID = nil }
        do {
            try await store(for: game).uninstall(game)
            // Its copy from the store picked is gone: the card goes back to the store it's still installed in.
            if let card = card(holding: game.id), card.id == game.id, card.others.contains(where: \.isInstalled) {
                StoreChoice.forget(card.gameIDs)
            }
        } catch {
            errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, error.localizedDescription)
        }
    }

    /// Opens Steam in Nightforge's prefix, e.g. to install a game.
    func openSteam() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            do {
                try Engine.startSteam(wine)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealSelected() {
        guard let game = selected else { return }
        let fm = FileManager.default
        // Not downloaded yet from another store: the nearest folder there is on the way to it.
        let target = fm.fileExists(atPath: game.installDir.path) ? game.installDir
            : game.provider == .steam ? game.steamRoot : SpaceCheck.existingFolder(for: game.installDir)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func chooseBottlesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Prefs.bottlesRoot
        panel.prompt = L10n.t("Use This Folder")
        panel.message = L10n.t("Choose the folder that contains your bottles, or a single bottle.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Prefs.Keys.bottlesRoot)
        reload()
    }
}
