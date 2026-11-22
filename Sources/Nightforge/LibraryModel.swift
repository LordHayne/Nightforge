import AppKit
import Combine
import GameController
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    /// Everything the scan found: each store's entry of a game on its own.
    @Published private(set) var allGames: [Game] = [] {
        didSet {
            ownedGames = nil
            mergeCards()
        }
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
            libraryMenu = nil
            closeQuickMenu()
            // Hits show in the library, wherever the search started.
            if !searchText.isEmpty, route != .library {
                rememberSelection()
                route = .library
            }
            applyFilter(selectBestMatch: true)
            searchStore()
        }
    }
    /// The stores' hits for the current search, each game once.
    @Published private(set) var storeResults: [Game] = []
    /// Each store's hits, as they came (`searchStore`).
    private var storeFound: [Provider: [StoreHit]] = [:]
    /// Steam's info for its hits: their covers and controller support.
    private var storeInfos: [Int: GameInfo] = [:]
    private var storeSearch: Task<Void, Never>?
    private var storeCovers: Task<Void, Never>?
    /// What the player has, once a search has asked: kept while the library doesn't change.
    private var ownedGames: OwnedGames?
    private var ownedIndex: OwnedGames {
        if let ownedGames { return ownedGames }
        let index = OwnedGames(allGames)
        ownedGames = index
        return index
    }
    /// Bumped to move keyboard focus into the search field in the library's header (⌘F, /).
    @Published private(set) var searchFocusRequest = 0
    /// The keyboard for the controller while it's open.
    @Published private(set) var padKeyboard: PadKeyboardSession?
    /// The search stands as the bar over the keyboard, or is on its way there or back (PadSearchBar).
    @Published private(set) var searchBarFloats = false
    @Published private(set) var searchBarRaised = false
    /// Where the search field is in the header, and where the bar goes.
    @Published var searchFieldFrame = CGRect.zero
    @Published var searchBarTarget = CGRect.zero
    /// A focus request the field hasn't taken yet: it may only appear with the library.
    private var searchFocusPending = false
    /// Home, the library grid, or a game's page.
    @Published private(set) var route = Route.home {
        didSet {
            guard route != oldValue else { return }
            history.moved(from: oldValue, to: route, by: historyStep)
            libraryMenu = nil
            quickMenu = nil
            quickMenuReturn = nil
            lightbox = nil
            launcherMenuOpen = false
            launcherMenuReturn = nil
            // The pad's highlight stays with the level it was on (a chip kept behind a game's page).
            PadFocus.shared.clear()
        }
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
    /// Games hidden from the library, pinned to Home and on the Play Later list (GameMarks).
    @Published private(set) var hiddenGames = GameMarks.load(.hidden)
    @Published private(set) var pinnedGames = GameMarks.load(.pinned)
    /// Taken off Home until played again (HomeRemovals).
    @Published private(set) var offHome = HomeRemovals.load()
    /// What Home's stage is made of, and the order of the pinned games (Settings › Home).
    @Published private(set) var homeSources = HomeSources.load()
    @Published private(set) var pinOrder = HomePinOrder.load()
    @Published private(set) var laterGames = GameMarks.load(.later)
    /// The library shows only the hidden games, to bring them back.
    @Published private(set) var showingHidden = false
    /// What the library grid shows and how it's ordered (only the library applies them).
    @Published var filters = LibraryFilters() {
        didSet { if filters != oldValue { applyFilter() } }
    }
    /// The list one of the library's chips opened (stores, order, filters).
    @Published var libraryMenu: LibraryMenu?
    /// The game (`Game.id`) whose quick menu is open (GameMenu.swift).
    @Published var quickMenu: String?
    /// What the pad had highlighted when the quick menu opened.
    var quickMenuReturn: String?
    /// A game's screenshot shown big over the window.
    @Published var lightbox: Lightbox?
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
    /// That question is Steam's licence: the frame comes at once and says so (SteamLicence).
    private var launchAsksLicence = false
    /// Steam's name for the step it waits on (LaunchWatcher.questionTask): the curtain's heading (SteamQuestion.kind).
    private var launchQuestionTask: String?
    /// What the launch is busy with when it's more than waiting for Steam ("Restarting Steam …"). Each one in the
    /// log as it begins, with what the curtain no longer says (LaunchPhase.curtainTitle).
    @Published private(set) var launchPhase: LaunchPhase? {
        didSet {
            guard let launchPhase, launchPhase.kind != oldValue?.kind else { return }
            GameLog.note("Start phase: \(launchPhase.kind) – \"\(launchPhase.title)\": \(launchPhase.hint)")
        }
    }
    /// A start Nightforge mends after one that ended without a picture (LaunchRepair): said on the curtain
    /// while no phase of its own (a Steam restart, an update) has the line.
    @Published private(set) var launchRepair: LaunchRepair?
    /// How fast Steam's update before a start goes ("12.4 MB/s · 4 min left"), once it's known.
    @Published private(set) var updateSpeed: String?
    /// The start in progress is the game's first with these graphics: its shaders get built.
    @Published private(set) var launchBuildsShaders = false

    /// The line under the Play button while a game starts: why it takes a moment.
    var launchHint: String? {
        guard launchingID != nil else { return nil }
        if launchNeedsConfirmation { return LaunchPhase.confirmHint }
        let provider = allGames.first { $0.id == launchingID }?.provider
        if case .updating? = launchPhase, let provider, provider != .steam { return LaunchPhase.storeUpdateHint(provider, speed: updateSpeed) }
        if case .updating? = launchPhase, let updateSpeed { return LaunchPhase.steamUpdateHint(speed: updateSpeed) }
        if launchPhase == .syncingSaves, provider == .gog { return LaunchPhase.gogSavesHint }
        if let launchPhase { return launchPhase.hint }
        if let launchRepair { return launchRepair.detail }
        return launchBuildsShaders ? LaunchPhase.shaderHint : nil
    }

    /// The line on the Play button and the curtain while a game starts: its phase, else what Nightforge
    /// mends (LaunchRepair).
    var launchTitle: String? { launchPhase?.title ?? launchRepair?.title }
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
    /// What AppleGamingWiki says about games on a Mac (profiles/agw.json), the copy at hand.
    @Published private(set) var macSources = AGWIndex()
    /// What each game is, kept on the Mac (GameInfoStore): its page's text and facts, and for Epic and
    /// GOG games the same game on Steam, which the filters and profiles go by.
    @Published private(set) var gameInfo = GameInfoStore.load()
    @Published var showingOptions = false
    /// Settings, as a dialog over the library (also over it in full screen).
    @Published var showingSettings = false
    /// Waiting for the user to confirm removing this game (or its download).
    @Published var pendingUninstall: Game?
    @Published var offersFullScreen = false
    /// The Windows game that stands at a question now: A and B answer it (PadAnswer).
    private(set) var windowsQuestion: Game?
    private var padAnswered: Date?
    private var fullScreenOffered = false
    /// Sleeping the Mac or quitting, waiting for its "are you sure" (PowerMenu).
    @Published var pendingPower: PowerMenu.Entry?
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
    @Published var showingDownloads = false {
        didSet { if showingDownloads && !oldValue { refreshLowSpace() } }
    }
    /// What Steam is downloading now, in the library's order.
    var downloads: [Game] { allGames.filter { Self.isDownloading($0.install) } }
    /// Speed and time left of each download.
    @Published private(set) var downloadRates: [GameID: DownloadRate] = [:]
    /// A download that wouldn't fit: which games could make room (SpaceCheck) – or a drive to put it on.
    @Published var pendingSpace: SpaceRequest?
    /// A volume with games that has run low on room (SpaceCheck.lowest): a calm note on Home and in the
    /// downloads, with the way to Settings › Storage. Looked at when Nightforge starts, after a download
    /// and when the downloads open – not all the time.
    @Published private(set) var lowSpace: SpaceCheck.Place?
    /// A game moving to another drive (DriveMoves), shown with the downloads.
    @Published var move: GameMove?
    /// Settings › Storage's "Move to …": asking where the game goes.
    @Published var pendingMove: Game?
    /// An Epic or GOG game whose download waits for its store to say how big it is.
    @Published private(set) var sizingID: String?
    /// A game about to open in GeForce Now for the first time: what that means is said once.
    @Published var pendingCloudGame: Game?
    /// The question about Apple's D3DMetal, while it's asked (D3DMetalFlow).
    @Published var d3dMetalDialog: D3DMetalDialog?
    /// What is going on behind it: the import or download, and the game whose start waits for the answer.
    var d3dMetalRun = D3DMetalRun()
    /// A demo or free game about to get its licence in Steam's install window: what that takes is said first.
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
    /// Every connected controller with its battery, one capsule each in the hint bar.
    @Published var controllerStatuses: [ControllerStatus] = []
    /// A newer Nightforge release, offered with one click in the top bar.
    @Published private(set) var availableUpdate: AppUpdate?
    @Published private(set) var updating = false
    /// Plugged in or on battery (for the top bar and "Save battery when unplugged").
    @Published private(set) var power = PowerSource.current()
    /// What the ring and the Downloads panel say about the Mac.
    @Published private(set) var downloadStanding: DownloadStanding = .silent
    /// What the last scan found to keep the Mac awake for, and whether anything can be fetching it.
    private var keptAwakeFor: (downloads: [KeepAwake.Download], fetching: Bool) = ([], false)
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

    /// The stores as both launcher menus show them (LauncherState), in their own order.
    @Published var launchers = Provider.allCases.map { LauncherState($0) }
    var launcherRefresh: Task<Void, Never>?
    var launcherUpdate: Task<Void, Never>?
    /// What the two clients' files said last.
    var launcherClients = LauncherClients()
    /// The small menu at the top right.
    @Published var launcherMenuOpen = false
    var launcherMenuReturn: String?
    /// The store whose card was last used: the highlight comes back to it.
    var lastLauncher: Provider?
    /// "Manage" on a store's card.
    @Published var managedLauncher: Provider?
    /// The store signing in on the curtain (SignInStage).
    @Published var signingIn: Provider? {
        didSet {
            if signingIn != oldValue { refreshLaunchers() }
            if oldValue == .gog, signingIn != .gog {
                phoneSignIn.close()
                signInOnPhone = false
            }
        }
    }
    /// GOG's sign-in from the phone: its small page on the local network, while the stage shows it.
    let phoneSignIn = PhoneSignIn()
    /// GOG's stage shows the QR code and not the page for a keyboard.
    @Published var signInOnPhone = false
    /// Waits for a client's own window to be through.
    var signInWatch: Task<Void, Never>?
    private var storeChanges: [AnyCancellable] = []

    /// The stores the library comes from (7.1); a game's own store downloads, removes and starts it.
    let steam = SteamStore()
    let epic = EpicStore()
    let gog = GOGStore()
    let battleNet = BattleNetStore()
    var stores: [StoreProvider] { [steam, epic, gog, battleNet] }

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
        // The four cards after the sign-in: Steam's window had the front.
        setup.onLaunchers = { [weak self] in
            self?.comeForward()
            self?.refreshLaunchers()
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
        storeChanges = [epic.objectWillChange.sink { [weak self] _ in self?.storeChanged() },
                        gog.objectWillChange.sink { [weak self] _ in self?.storeChanged() }]
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

    // MARK: - Rosetta

    /// Rosetta is missing where macOS still has it: the question with its install, and what the player wanted
    /// (`then`) done after it.
    struct RosettaQuestion: Identifiable {
        let id = UUID()
        let then: (@MainActor () -> Void)?
    }

    @Published var rosettaQuestion: RosettaQuestion?
    /// The question came without a start this session (`askAboutRosettaOnce`).
    private var rosettaAskedOnce = false

    /// Whether x86_64 code can run now. If not it says so: the install offered, `then` after it – or past macOS 27
    /// that Windows games can't run here (RosettaSupport.notice). Checked before anything starts, so a start never
    /// fails for want of Rosetta and nothing counts against its way (LaunchHealth, start-evidence).
    func rosettaReady(for what: String, then: (@MainActor () -> Void)?) -> Bool {
        let state = RosettaSupport.stateHere()
        guard state != .ready else { return true }
        GameLog.note("Rosetta \(state == .gone ? "isn't available on this macOS" : "is missing"): \(what) waits")
        if state == .gone { errorMessage = RosettaSupport.notice } else { rosettaQuestion = RosettaQuestion(then: then) }
        return false
    }

    /// Once a session, without a start: the library has games and the first start's Rosetta step never came – the
    /// way through Settings › Launchers › Manage (the gear is there during the first start too) signs in to Epic,
    /// GOG or Steam for Mac, and with games in the list `needsSetup` is false (the user's new Mac, 21.11.2026).
    func askAboutRosettaOnce() {
        guard !rosettaAskedOnce, rosettaQuestion == nil, !setup.isActive, !needsSetup else { return }
        rosettaAskedOnce = true
        guard Self.asksAboutRosetta(RosettaSupport.stateHere(), setupActive: setup.isActive, needsSetup: needsSetup) else { return }
        GameLog.note("Rosetta is missing and the first start's step never came: asked now")
        rosettaQuestion = RosettaQuestion(then: nil)
    }

    /// The question without a start: Rosetta missing where Apple still installs it, a library there, and the first
    /// start not running – that asks in its own step (SetupModel's `.needsRosetta`), and with no games yet it's
    /// still to come. Past macOS 27 the notice comes with the first start of a Windows game.
    nonisolated static func asksAboutRosetta(_ state: RosettaSupport.State, setupActive: Bool, needsSetup: Bool) -> Bool {
        state == .missing && !setupActive && !needsSetup
    }

    /// A start that failed after all for want of Rosetta ("Bad CPU type", RosettaSupport.Missing): the question,
    /// and the start again after the install – the start loop has ended without a verdict, nothing on the way's
    /// account. Any other error as before (`say`).
    private func startFailed(_ game: Game, _ error: Error, say: () -> String) {
        guard RosettaSupport.isBadCPUType(error) else { return errorMessage = say() }
        GameLog.note("\(game.name) couldn't start: Rosetta is missing – asked, the start comes again after the install")
        rosettaQuestion = RosettaQuestion(then: { [weak self] in self?.launch(game) })
    }

    /// Whether a start runs x86_64 code: every Windows game (Wine), and a Mac version Steam says is made for Intel.
    nonisolated static func startNeedsRosetta(platform: Platform, provider: Provider, macAppleSilicon: Bool) -> Bool {
        platform != .mac || (provider == .steam && !macAppleSilicon)
    }

    /// "Install Rosetta" in the question: macOS's password prompt, then what the player wanted.
    func installRosetta(_ question: RosettaQuestion) {
        rosettaQuestion = nil
        Task {
            guard await RosettaSupport.install(), RosettaSupport.stateHere() == .ready else { return }
            question.then?()
        }
    }
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
        Quit.closeModelSheets = { [weak self] in self?.closeAllSheets() }
        Quit.modelSheets = { [weak self] in self?.openSheets ?? [] }
        watchRunningGames()
        beginWakeWatch()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))  // after the window and Steam got going
            availableUpdate = await Updater.check()
        }
        // Continue Playing: whatever the stage gave up on, the player wants the game now.
        GameOverlay.resumed = { [weak self] in self?.stage.again() }
        // Where the page behind a game goes when Nightforge comes to the front: behind Nightforge's
        // window while the game shows its own, over it a moment longer when the game is ending.
        GameBackdrop.gameShowsWindow = { [weak self] in
            guard let self else { return false }
            return GameProcesses.showsWindow(Set(playing.compactMap { self.running[$0] }), anySpace: true)
        }
        GameBackdrop.frontMoved = { [weak self] front in self?.frontMoved(to: front) }
        DarkWatch.shared.begin(with: self)
        // A screen plugged in or pulled: whether the lid matters changes with it.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDownloadStanding() }
        }
        // Back from buying in the browser (or from Steam): pick up newly owned games.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lookNow()
                self?.wakeSteam()
                self?.reload(quiet: true)
                self?.refreshStores()
                self?.refreshLaunchers()
            }
        }
        refreshStores()
        refreshLaunchers()
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

    /// Epic's sign-in page on the stage; its code goes to legendary.
    func connectEpic() {
        if !epic.connecting {
            epic.connecting = true
            Task { await Legendary.prepare() }
        }
        signingIn = .epic
    }

    /// A store's page on the stage is through: its code, or nil when the player called it off.
    func signInPageDone(_ provider: Provider, code: String?) {
        signingIn = nil
        switch provider {
        case .epic: finishEpicSignIn(code)
        case .gog: finishGOGSignIn(code)
        case .steam, .battlenet: break
        }
    }

    private func finishEpicSignIn(_ code: String?) {
        guard let code else {
            epic.connecting = false
            return
        }
        Task {
            defer { epic.connecting = false }
            do {
                try await epic.connect(code: code)
                storeAsked[.epic] = Date()
                reload(quiet: true)
                Toasts.shared.show(L10n.t("Epic Games is connected – your games are in the library"))
            } catch {
                errorMessage = RosettaSupport.playerText(error)
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

    /// GOG's sign-in page on the stage; its code goes to gogdl.
    func connectGOG() {
        if !gog.connecting {
            gog.connecting = true
            Task { await GOGDL.prepare() }
        }
        signInOnPhone = controllerConnected
        signingIn = .gog
    }

    private func finishGOGSignIn(_ code: String?) {
        guard let code else {
            gog.connecting = false
            return
        }
        Task {
            defer { gog.connecting = false }
            do {
                try await gog.connect(code: code)
                storeAsked[.gog] = Date()
                reload(quiet: true)
                Toasts.shared.show(L10n.t("GOG is connected – your games are in the library"))
            } catch {
                errorMessage = RosettaSupport.playerText(error)
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
            let outcome = await gog.update(game, speed: { [weak self] in self?.showUpdateSpeed($0) }) { [weak self] fraction in
                self?.launchPhase = .updating(fraction)
            }
            awaitingSteam = false
            launchPhase = nil
            updateSpeed = nil
            if Task.isCancelled { return false }
            switch outcome {
            case .updated, .addOnFailed:
                analyses[game.gameID] = nil  // its files changed
                reload(quiet: true)
            case .skipped(.offline):
                noteDuringStart(L10n.t("%@ can't be reached – %@ starts without its update.", Provider.gog.label, game.name))
            case .skipped(.busy):
                noteDuringStart(L10n.t("Another %@ download is running – %@ starts now and updates next time.", Provider.gog.label, game.name))
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
        hintDuringStart(outcome.retried
            ? L10n.t("Not all Windows parts for %@ could be set up (%@). It starts anyway; Nightforge tries again at the next start.", game.name, parts)
            : L10n.t("Not all Windows parts for %@ could be set up (%@). It starts anyway – if it doesn't run right, this may be why.", game.name, parts))
    }

    /// A GOG game's Mac version: no Steam and no Wine – its update and save first, then the app
    /// itself; Nightforge follows it like any game it started.
    private func launchGOGMac(_ game: Game) {
        let number = beginLaunch(game)
        let behavior = Prefs.afterLaunch
        let arguments = Launcher.splitArguments(GameOptionsStore.load(game.gameID).extraArgs)
        launchTask = Task {
            defer { endLaunch(number) }
            raiseCurtain(for: game)  // the update and the save under it, with their progress and B to stop
            await leftStartEnded()
            guard !Task.isCancelled, await beforeGOGStart(game) else { return }
            let installDir = game.installDir
            let playerArguments = arguments.joined(separator: " ")
            let screen = await Task.detached(priority: .userInitiated) { () -> MacUnityScreen.Decision in
                ControllerCompatibility.prepare(installDir: installDir)
                return MacUnityScreen.look(installDir: installDir, playerArguments: playerArguments)
            }.value
            // A Unity Mac version's first start in full screen (MacUnityScreen).
            if let note = MacUnityScreen.note(screen, game: game.name) { GameLog.note(note) }
            let withScreen = Launcher.splitArguments(MacUnityScreen.arguments(playerArguments, screen))
            do {
                try await gog.launchMac(game, extraArguments: withScreen)
            } catch {
                errorMessage = L10n.t("%@ couldn't start: %@", game.name, RosettaSupport.playerText(error))
                return
            }
            gog.recordStart(game)
            launchingID = nil
            startedHere.insert(game.id)
            await bringToFront(game)
            if !Task.isCancelled { stepBack(behind: game, behavior) }  // a new start has the curtain
        }
    }

    /// A Blizzard Mac game, through Blizzard's own client: Nightforge sees to it that the client is up
    /// and signed in, asks it to start the game, and follows the game like any other from there.
    private func launchBattleNetMac(_ game: Game) {
        let code = game.gameID.id
        switch BattleNetStart.blocker(code: code, pendingUpdate: game.pendingUpdate != nil, clientThere: BattleNetClient.app != nil) {
        case .notAMacGame?:
            errorMessage = L10n.t("%@ can't start from Nightforge yet: start it in Battle.net.", game.name)
            return
        case .noClient?:
            errorMessage = L10n.t("%@ starts through Battle.net for Mac, which isn't on this Mac any more.", game.name)
            return
        case .updateFirst?:
            BattleNetClient.showGame(code: code)
            errorMessage = L10n.t("%@ has an update waiting. Battle.net is open: update it there, then press Play here.", game.name)
            return
        case nil:
            break
        }
        guard let command = BattleNetStart.command(code: code) else { return }
        let number = beginLaunch(game)
        let behavior = Prefs.afterLaunch
        launchTask = Task {
            defer { endLaunch(number) }
            awaitingSteam = true  // B or Esc calls the start off
            defer { awaitingSteam = false }
            guard let log = await readyBattleNet(for: game) else { return }
            BattleNetClient.hide()  // up from its sign-in, or open from before: the curtain has the screen
            raiseCurtain(for: game)
            // From before the command goes out: handing it over takes a moment, and what the client answers meanwhile counts.
            let follower = BattleNetStart.LogFollower(file: log)
            let sent = await Task.detached(priority: .userInitiated) { (try? BattleNetClient.send(command)) != nil }.value
            guard sent else {
                errorMessage = L10n.t("%@ couldn't start: %@", game.name, L10n.t("Battle.net didn't take the request."))
                return
            }
            let failure = await waitForBattleNetStart(game, command: command, follower: follower)
            launchPhase = nil
            if Task.isCancelled { return }
            if let failure {
                sayBattleNetFailed(game, failure)
                return
            }
            awaitingSteam = false
            launchingID = nil
            battleNet.recordStart(game)
            startedHere.insert(game.id)
            BattleNetClient.hide()  // the game has the stage now
            await bringToFront(game)
            if !Task.isCancelled { stepBack(behind: game, behavior) }  // a new start has the curtain
        }
    }

    /// The client up and signed in, its log to follow; nil when the start is off (it says why).
    /// A sign-in stays the client's: its window comes up for it, and the player gets ten minutes.
    private func readyBattleNet(for game: Game) async -> URL? {
        var look = await Task.detached(priority: .userInitiated) { BattleNetClient.lookAtClient() }.value
        if look.state == .notRunning {
            launchPhase = .startingBattleNet
            BattleNetClient.startHidden()
        }
        var waited = 0
        var asked = false
        defer { launchPhase = nil }
        while waited < (asked ? 600 : 90) {
            if look.state == .ready, let log = look.log { return log }
            if look.state == .signInNeeded, !asked {
                asked = true
                launchPhase = .signInInBattleNetWindow
                BattleNetClient.show()
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return nil }
            waited += 1
            look = await Task.detached(priority: .userInitiated) { BattleNetClient.lookAtClient() }.value
        }
        if asked {
            errorMessage = L10n.t("Battle.net isn't signed in, so %@ didn't start. Sign in there and press Play again.", game.name)
        } else {
            BattleNetClient.show()
            errorMessage = L10n.t("Battle.net didn't get ready, so %@ didn't start. Please try again.", game.name)
        }
        return nil
    }

    /// Follows the start until the game's process is there (or it's called off in Nightforge): nil
    /// then, otherwise what stopped it.
    private func waitForBattleNetStart(_ game: Game, command: String, follower: BattleNetStart.LogFollower) async -> BattleNetStart.Watch.Failure? {
        let folders = Self.processFolders([game])
        var follower = follower
        var watch = BattleNetStart.Watch()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil { return nil }
            let events = BattleNetStart.events(in: follower.newText())
            switch watch.step(events) {
            case .wait:
                break
            case .sendAgain:
                _ = await Task.detached(priority: .userInitiated) { try? BattleNetClient.send(command) }.value
            case .playerAsked:
                // The curtain makes way (`steamAsks`), the client comes forward.
                launchPhase = .battleNetAsks
                BattleNetClient.showGame(code: game.gameID.id)
            case .failed(let failure):
                return failure
            }
        }
        return nil
    }

    /// The start is over without the game: what happened, the client in front where the player can go on.
    private func sayBattleNetFailed(_ game: Game, _ failure: BattleNetStart.Watch.Failure) {
        switch failure {
        case .refused:
            BattleNetClient.showGame(code: game.gameID.id)
            errorMessage = L10n.t("Battle.net couldn't start %@. Its window says why.", game.name)
        case .calledOff:
            BattleNetClient.showGame(code: game.gameID.id)
            errorMessage = L10n.t("Battle.net called off the start of %@. Press Play again to try once more.", game.name)
        case .clientEnded:
            errorMessage = L10n.t("Battle.net closed before %@ started. Please try again.", game.name)
        case .noAnswer:
            // Started by hand now, it still counts as a game started here.
            startedHere.insert(game.id)
            BattleNetClient.showGame(code: game.gameID.id)
            errorMessage = L10n.t("Battle.net didn't start %@. Press Play in its window: Nightforge notices the game by itself.", game.name)
        }
    }

    // MARK: - Running games

    /// Wine shows each game process with its Windows path, e.g.
    /// "C:\…\steamapps\common\Oxygen Train\Oxygen Train.exe" – match that against the install folders.
    private func watchRunningGames() {
        Task {
            while !Task.isCancelled {
                // First, and without a process list: nothing may keep it from going.
                if curtainOrphan.look(raised: GameBackdrop.isRaised, owners: curtainOwners, now: Date()) { takeAwayOrphanCurtain("nobody came") }
                let loaded = libraryLoaded
                let folders = Self.processFolders(allGames)
                let known = await Task.detached(priority: .utility) { Self.runningGamesKnown(folders) }.value
                // No process list at all (ps doesn't answer, GameProcesses.lookup): nothing is concluded from
                // "no games" – no game ended, no play time stopped, no idle Steam restarted.
                guard let found = known else {
                    nap = Task { try? await Task.sleep(for: .seconds(3)) }
                    await nap?.value
                    continue
                }
                if found != running { running = found }
                if !found.isEmpty { Engine.noteGameActivity() }
                if loaded { runningScanned = true }  // only a look with the games known counts
                await Task.detached(priority: .utility) { GameDisplay.observeWineSession() }.value
                watchForGameEnd(found)
                if found.isEmpty, launchingID == nil, playing.isEmpty, judging == nil { idleLooks += 1 } else { idleLooks = 0 }
                if idleLooks == 20 {  // a start that never got going (~1 min)
                    GameDisplay.leaveGame()
                    GameBackdrop.hide(after: .zero)
                }
                if steam.restartWhenIdle && found.isEmpty && !gameUnderWay && move == nil {
                    steam.restartWhenIdle = false
                    if let wine = await Engine.installedWine() { try? await Engine.restartSteamInBackground(wine) }
                }
                // Every few seconds while it matters (Nightforge in front, a game running or starting),
                // otherwise less often: nothing waits on it then, and the Mac stays quieter. A game
                // that just ended is looked after quickest: the player waits to be back in Nightforge.
                // Also with a game in front, every few minutes: a pad running low says so.
                if controllerConnected, NSApp.isActive || Date().timeIntervalSince(batteryLooked) > 180 {
                    batteryLooked = Date()
                    input.refreshBattery()
                }
                let reading = PowerSource.reading()
                if reading.source != power {
                    power = reading.source
                    refreshDownloadStanding()
                }
                IdleAwake.apply(IdleAwake.holds(minutes: Prefs.keepAwakeMinutes, onBattery: reading.source.onBattery, idle: InputRouter.secondsSinceUse),
                                reason: L10n.t("Nightforge keeps the Mac awake for a while, as set in its settings"))
                let warning = chargerCheck.add(reading.source, batteryCurrent: reading.batteryCurrent)
                if warning != chargerWarning { chargerWarning = warning }
                await lookAtSteamOnDemand()
                lookAtDrives()
                lookAtWakeCatchUp()
                offerFullScreenIfDue()
                input.takeHomeButton()
                DarkWatch.shared.look()
                watchExits(found)
                if NotificationMoment.asksNow(alreadyAsked: askedAboutNotifications, setting: Prefs.notifyDownloads, inFront: NSApp.isActive,
                                              gameOn: gameOnScreen, firstStart: showsFirstStart, padUsedLast: InputRouter.padUsedLast) {
                    askedAboutNotifications = true
                    MacIntegration.askIfUndecided()
                }
                let pause = Duration.seconds(IdleRest.lookPause(gameEnding: goneFor > 0, gameOrStart: !found.isEmpty || launchingID != nil || GameBackdrop.isRaised,
                                                                downloading: KeepAwake.isHolding, inFront: NSApp.isActive,
                                                                nobodyThere: IdleRest.nobodyThere(idle: InputRouter.secondsSinceUse)))
                nap = Task { try? await Task.sleep(for: pause) }
                await nap?.value
            }
        }
    }

    /// The pause between looks; a game's process ending cuts it short, and so does the player coming back.
    private var nap: Task<Void, Never>?
    func lookNow() { nap?.cancel() }
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
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.gameProcessExited(pid)
                    self?.nap?.cancel()
                }
            }
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
    /// Windows games started while no controller was connected (padArrivedLate).
    private var padlessStarts: Set<String> = []
    /// "Restart Nightforge" waits for a game's cloud saves.
    private var restartWait: Task<Void, Never>?
    /// "Restart Game" was pressed: the game to start again once its end is seen.
    private var restartAfterEnd: Game?
    /// When each of them started running, and the play time Steam had for it then.
    private var sessionStarts: [String: (date: Date, totalBefore: Int)] = [:]
    /// The way each Windows game's last start took (`LaunchAttempt.id`), for "How did it run?".
    private var waysUsed: [GameID: String] = [:]
    /// The "Welcome back" sheet after a real session (a minute or more).
    @Published var sessionSummary: SessionSummary?
    private var goneFor = 0
    private var batteryLooked = Date.distantPast
    private var goneSince = Date.distantPast
    private var idleLooks = 0
    private var askedAboutNotifications = false
    /// The game whose start is still judged by its first seconds (`survivesFirstSeconds`), and when
    /// that start began: should it end now, the start tells what's next – another way under the same
    /// curtain, or Nightforge with what happened. Control (Epic) crashed on every way on 2.11., and
    /// the curtain went, Nightforge came, the curtain came again for each.
    private var judging: (id: String, since: Date)?

    /// A game is starting or running, also in the moments the look at the processes doesn't show it yet:
    /// what restarts Steam ends its Wine session, and a store's game lives in that one too.
    var gameUnderWay: Bool { launchingID != nil || judging != nil || !running.isEmpty }

    /// A game on the stage for the curtain and the page behind it: one being played, or one whose
    /// start is still judged – gone already, maybe about to start again another way.
    private var gameOnStage: Bool { !playing.isEmpty || judging != nil }

    /// Whether the end of the game being played is the start's to tell (`judging`).
    private func startJudgesEnd() -> Bool {
        guard let judging, playing.contains(judging.id), let game = allGames.first(where: { $0.id == judging.id }) else { return false }
        return Self.startJudgesEnd(quitByPlayer: LaunchHealth.quitByPlayer(game.gameID, since: judging.since),
                                   showedPicture: LaunchHealth.showedPicture(game.gameID, since: judging.since))
    }

    /// An early end is the start's to tell, unless it's an end like any other: the player quit the
    /// game (Quit Game, waiting ten seconds more on "Back to Nightforge …" for the start's verdict
    /// would be odd), or it showed a picture – a start that worked, whatever comes after.
    nonisolated static func startJudgesEnd(quitByPlayer: Bool, showedPicture: Bool) -> Bool {
        !quitByPlayer && !showedPicture
    }

    /// The start's judging is over without another way: Nightforge comes back from the curtain as
    /// after any game, on the game's page – where it says what happened (didn't start, still
    /// running) – or, should the game run on, the curtain just goes. Not for a start called off by
    /// a newer one (`current`), whose curtain it is now.
    private func finishJudging(_ game: Game, current: Bool) {
        guard let judged = judging, judged.id == game.id else { return }
        judging = nil
        // Called off, or the curtain went already (an error the watch showed).
        guard current, GameBackdrop.isRaised else { return }
        guard running[game.id] == nil, !playing.contains(game.id) else {
            if GameBackdrop.isRaised, !GameBackdrop.isReturning { GameBackdrop.hide(after: .zero) }
            return
        }
        GameBackdrop.returning()
        if game.inLibrary, reveal(game), !route.isDetail { openDetail() }
        comeBack(to: route)
    }

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
            if goneFor > 0 || raisedForExit { GameBackdrop.playing() }  // a launcher handed over to the game after all
            goneFor = 0
            raisedForExit = false
            return
        }
        // A start whose first seconds are still judged: its end is the start's to tell, under the
        // same curtain – another way, or Nightforge with what happened (`finishJudging`).
        let judged = startJudgesEnd()
        if goneFor == 0, !judged {
            goneSince = Date()
            // The curtain at once, over Steam for Mac's window, which comes up when a game ends –
            // and Steam's, should it still be open from a question before the start.
            GameBackdrop.returning()
            MacSteam.hide()
            if steamWindowShown {
                steamWindowShown = false
                Task { await SteamWindow.hide() }
            }
        } else if goneFor == 0 {
            goneSince = Date()
        }
        goneFor += 1
        let ranFor = playing.compactMap { sessionStarts[$0]?.date }.map { goneSince.timeIntervalSince($0) }.max() ?? 0
        guard Self.gameEnded(looksGone: goneFor, goneFor: Date().timeIntervalSince(goneSince), ranFor: ranFor) else { return }
        let ended = playing
        playing = []
        goneFor = 0
        GameOverlay.gameEnded()
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
            if game.provider == .battlenet { battleNet.recordSession(game, minutes: minutes) }
            return minutes >= 1 ? SessionSummary(game: game, minutes: minutes, totalBefore: start.totalBefore,
                                                 endedAt: endedAt, way: game.platform == .mac ? "mac" : waysUsed[game.gameID]) : nil
        }
        // "Restart Game" (the overlay): its start follows here, under the same curtain. Coming back first
        // took that curtain away and laid "Welcome back" over the new start.
        if let game = restartAfterEnd, Self.endRestarts(game.id, ended: ended) {
            restartAfterEnd = nil
            if let id = judging?.id, ended.contains(id) { judging = nil }
            play(game)
            return
        }
        if judged { return }
        // An end like any other while the start still judges (the player quit, it showed a picture):
        // Nightforge comes back from here, the start's end adds nothing.
        if let id = judging?.id, ended.contains(id) { judging = nil }
        // Back on the game's page, as from a console's game.
        if let game = endedGames.first(where: { $0.inLibrary }), reveal(game), !route.isDetail { openDetail() }
        // "Welcome back" once the curtain is gone, not under it while the Spaces change.
        let summary = sessions.max { $0.minutes < $1.minutes }
        comeBack(to: route) { [weak self] in self?.sessionSummary = summary }
    }

    /// The curtain came for a process that ended, before the look that finds out what that means.
    private var raisedForExit = false
    /// The curtain came for a picture that went (`GameStage.pictureWent`), the game's process still there.
    private var pictureWentAt: Date?
    /// The game on stage as of the stage watch's last list.
    private var stagePids = Set<pid_t>()
    private var stageAskers = Set<pid_t>()
    /// Another app's window over the game's picture, as of the stage watch's last look.
    private(set) var overGame: PadPointerRules.OverGame?
    private(set) var overGameFront = false
    private var overGameHanded: Int?

    /// A game's process ended: the curtain now, in the same moment, not at the look it cuts short. A Mac
    /// game in its own Space starts sliding away at once, and the page behind it slid in from the side
    /// with the desktop beside it. The look after it says whether that was the end.
    private func gameProcessExited(_ pid: pid_t) {
        guard CurtainEscape.mayRaiseForEnd(gamePlaying: !playing.isEmpty, comingBack: comingBackSince != nil),
              Self.exitRaisesCurtain(curtainUp: GameBackdrop.isRaised, sawPicture: stage.sawPicture, judged: startJudgesEnd(),
                                     othersRunning: playing.contains { running[$0] != nil && running[$0] != pid })
        else { return }
        GameLog.note("A game's process ended: the curtain comes at once, at \(GameLog.clock())")
        raisedForExit = true
        GameBackdrop.returning()
    }

    /// Before its first picture the curtain is up already, and an early end is the start's to tell.
    nonisolated static func exitRaisesCurtain(curtainUp: Bool, sawPicture: Bool, judged: Bool, othersRunning: Bool) -> Bool {
        !curtainUp && sawPicture && !judged && !othersRunning
    }

    /// Another app came to the front over the page: if the game's picture went with it and nobody asked
    /// for that, the curtain comes this moment (`GameStage.pictureWent`).
    private func frontMoved(to front: pid_t) {
        guard pictureWentAt == nil, stageHintSince == nil, !stagePids.isEmpty,
              CurtainEscape.mayRaiseForEnd(gamePlaying: !playing.isEmpty, comingBack: comingBackSince != nil)
        else { return }
        let look = GameStage.Look(gameFront: stagePids.contains(front), windowHere: GameProcesses.showsWindow(stagePids), windowAnywhere: false,
                                  handsOff: GameOverlay.isOpen || stageAskers.contains(front) || overGame != nil,
                                  playerActed: Self.playerActed(within: GameStage.leftWithin) || GameBackdrop.spaceJustChanged,
                                  guarded: curtainGuards, now: Date())
        guard stage.pictureWent(look) else { return }
        pictureWentAt = Date()
        GameLog.note("The game's picture went, the front moved on: the curtain comes at once, at \(GameLog.clock())")
        GameBackdrop.returning()
    }

    /// `page`: the page the player comes back to, set already. `then`: once the curtain is gone.
    private func comeBack(to page: Route, then: @escaping @MainActor () -> Void = {}) {
        GameLog.note("Back to Nightforge at \(GameLog.clock())")
        comingBackSince = Date()
        // The stage is over: what comes to the front from now on says nothing about a game (Tomb Raider, 8.11.).
        pictureWentAt = nil
        stageHintSince = nil
        fullScreenHint = nil
        stagePids = []
        stageAskers = []
        MacSteam.hide()
        Task {
            // The page's change (0.22 s) done first: a switch of Spaces shows the window as it is
            // at that moment (Home flashed before the game's page on 1.11.).
            try? await Task.sleep(for: .milliseconds(300))
            // Nightforge to the front (NSApp.comeToFront), then its window over the page behind the
            // game – on a TV over the whole screen (FullScreen) – and only then may the screens
            // change (GameDisplay.backFromGame), where nobody sees it.
            NSApp.comeToFront {
                GameDisplay.backFromGame()
                // Not on a timer: once Nightforge's window is in front on the Space shown, on that page.
                GameBackdrop.hide(once: { [weak self] in
                    Self.mayUncover(active: NSApp.isActive,
                                    windowShown: NSApp.windows.first { $0.title == "Nightforge" }?.isOnActiveSpace != false,
                                    page: self?.route ?? page, target: page)
                }, then: { [weak self] in
                    self?.comingBackSince = nil
                    InputRouter.hidePointerSoon()  // in Nightforge as before the game, when the pad was last
                    then()
                })
            }
        }
        reload(quiet: true)  // play time, last played
    }

    /// Whether the curtain may go on the way back: Nightforge in front, its window on the Space
    /// shown, and on the page the player comes back to – never on the one before.
    nonisolated static func mayUncover(active: Bool, windowShown: Bool, page: Route, target: Route) -> Bool {
        active && windowShown && page == target
    }

    /// Once a game has the screen: Nightforge stays where it is behind it, the page behind the
    /// game in place of the desktop (GameBackdrop). Hidden, as it used to be, the desktop was all
    /// that showed when the game ended, until Nightforge came back.
    private func stepBack(behind game: Game, _ behavior: AfterLaunch) {
        switch behavior {
        case .quit: Quit.now(by: "the game starting")
        case .hide, .stay: GameBackdrop.show(game.name, on: GameDisplay.gameScreen) { [weak self] in self?.gameOnStage == true }
        }
    }

    /// A game runs or starts: the pad belongs to it (InputRouter doesn't wake Nightforge meanwhile).
    var gameOnScreen: Bool { gamePlaying || launchingID != nil }
    /// A game is running, not just starting: a pad's touchpad is the game's now (PadPointerRules).
    var gamePlaying: Bool { !running.isEmpty || !playing.isEmpty }

    /// Nightforge in front again after a Steam window had it (its sign-in), the way it comes back
    /// after a game (comeBack): keys and the pad only reach the app in front.
    func comeForward() {
        guard !NSApp.isFrontmost else { return }
        NSApp.comeToFront()
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

    /// A game that a launcher started by its bare name counts too (GameProcesses.runsFrom: Control, 2.11.).
    nonisolated private static func runningGames(_ folders: [String: String]) -> [String: pid_t] {
        runningGamesKnown(folders) ?? [:]
    }

    /// The same, nil when no process list is to be had (GameProcesses.runningNow): for what decides from a
    /// game's absence – its end, a start that failed – which mustn't at such a time.
    nonisolated private static func runningGamesKnown(_ folders: [String: String]) -> [String: pid_t]? {
        GameProcesses.runningNow(folders)
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
    var macSteamBusy: Bool {
        anyRunning(.mac) || allGames.contains { $0.id == launchingID && $0.platform == .mac && $0.provider == .steam }
    }

    private func runningGame(_ platform: Platform) -> Game? {
        let ids = Set(running.keys)
        // GOG's Mac versions need no Steam; its Windows versions share the Wine session.
        return allGames.first { ids.contains($0.id) && $0.platform == platform && (platform == .windows || $0.provider == .steam) }
    }

    /// What the Steam switch goes by, now.
    /// A Mac version downloads through Steam for Mac.
    var macDownloading: Bool {
        allGames.contains { game in
            (game.platform == .mac && game.provider == .steam && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
    }

    var steamFacts: SteamSwitch.Facts {
        SteamSwitch.Facts(
            macSteamRunning: MacSteam.isRunning, macSteamOurs: MacSteam.startedByNightforge, macGameBusy: macSteamBusy,
            macDownload: macDownloading,
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

    // MARK: - The curtain

    private var curtainWatch: Task<Void, Never>?
    private var stageWatch: Task<Void, Never>?
    private var stage = GameStage()
    /// The curtain's watch has the game down and still guards its front (`curtainStep`).
    private var curtainGuards = false
    /// Nightforge opened Steam's window for a question (`showSteamWindow`) and hasn't hidden it since.
    private var steamWindowShown = false
    /// The questions of macOS's on screen at the first look of this start, for each way it tries:
    /// they came before it and don't hold it (`macOSAsksNow`).
    private var macOSQuestionsBefore: Set<Int>?

    /// A game whose own full screen hides its picture under the curtain, and where its setting is (fullScreenWords).
    private var fullScreenHint: (game: Game, setting: String?)?
    /// The stage raised the curtain again for it, after the start's curtain had gone (fullScreenOnStage).
    private var stageHintSince: Date?

    /// The start on the curtain the player may leave, and why (CurtainEscape).
    private var curtainEscape: (game: Game, reason: CurtainEscape.Reason)?
    private var stuckAskedAt: Date?

    var curtainEscapeOpen: Bool {
        CurtainEscape.wayOutOpen(raised: GameBackdrop.isRaised, offered: curtainEscape != nil, owners: curtainOwners)
    }

    private var curtainOrphan = CurtainEscape.Orphan()
    /// Curtain watches running; one that was called off may end after the next has begun.
    private var curtainWatches = 0
    private var comingBackSince: Date?

    private var curtainOwners: CurtainEscape.Owners {
        CurtainEscape.Owners(starting: launchingID != nil || judging != nil, watching: curtainWatches > 0 || stageHintSince != nil,
                             playing: CurtainEscape.playingOwns(gamePlaying: !playing.isEmpty, upFor: GameBackdrop.upFor),
                             comingBack: comingBackSince.map { Date().timeIntervalSince($0) < CurtainEscape.comingBackHoldsFor } ?? false)
    }

    /// A curtain nobody will take away goes by itself, with a game still running by uncovering it, and
    /// otherwise the way any game's end comes back.
    private func takeAwayOrphanCurtain(_ who: String) {
        GameLog.note("Curtain: nobody would take it away (\(who)), it goes, at \(GameLog.clock())")
        GameBackdrop.setSteamAsks(false)
        if running.isEmpty { comeBack(to: route) } else { GameBackdrop.hide(after: .zero) }
    }

    /// The curtain's watch at each look: B and Esc lead out from now on, and the curtain says so.
    private func offerWayOut(_ game: Game, reason: CurtainEscape.Reason?) {
        let had = curtainEscape?.reason
        curtainEscape = reason.map { (game, $0) }
        guard had != reason else { return }
        let pad = GCController.controllers().contains { $0.extendedGamepad != nil } ? padSymbols : nil
        GameBackdrop.setWayOut(reason.map { CurtainEscape.tip($0, pad: pad) })
        GameLog.note(reason.map { "Curtain over \(game.name): no process of it for a while (\($0)), B and Esc lead out" }
                     ?? "Curtain over \(game.name): the way out is closed again")
    }

    /// B or Esc on such a curtain, or the watch by itself: wait on, or back to Nightforge. Epic's and GOG's
    /// update and save end at once, as from the Play button: the update carries on from where it stopped.
    func askAboutStuckStart() {
        if GameBackdrop.isRaised, curtainEscape == nil, !curtainOwners.anyone { return takeAwayOrphanCurtain("B or Esc") }
        guard let (game, reason) = curtainEscape, !GameOverlay.isOpen else { return }
        if reason.atOnce { return leaveStuckStart(game, handedOver: reason == .steamAsks) }
        stuckAskedAt = Date()
        let actions = GameOverlay.Actions(quit: {}, nightforge: { [weak self] in self?.leaveStuckStart(game, handedOver: true) })
        GameOverlay.open(game.name, pids: [], pause: false, on: GameDisplay.gameScreen, symbols: padSymbols, step: .stuck,
                         stuck: CurtainEscape.words(reason, game: game.name, store: game.provider.label), actions: actions)
    }

    /// Back to Nightforge from a start that has no game yet. Only Nightforge's waiting ends: Steam and its
    /// update are left alone, a Steam that hangs is dealt with at the next Play, and a game Steam still
    /// starts afterwards is followed to its end like any other. `handedOver`: a store has the game
    /// already and may still start it.
    private func leaveStuckStart(_ game: Game, handedOver: Bool) {
        GameLog.note("Curtain over \(game.name): the player went back to Nightforge, at \(GameLog.clock())")
        curtainWatch?.cancel()
        stageWatch?.cancel()
        abandonLaunch()
        if handedOver {
            startedHere.insert(game.id)
            hideSteamWindow(for: game)  // a question of Steam's that stands: out of sight, and asked again at the next Play
        }
        GameBackdrop.setSteamAsks(false)
        curtainEscape = nil
        GameBackdrop.returning()
        if game.inLibrary, reveal(game), !route.isDetail { openDetail() }
        comeBack(to: route)
    }

    /// A store's update or save said how fast it goes (`updateSpeed`, on the curtain's second line).
    private func showUpdateSpeed(_ speed: String?) {
        if updateSpeed != speed { updateSpeed = speed }
    }

    /// A word on a start that goes on anyway (no update this time): a toast in Nightforge and the log, not the
    /// curtain – the player has nothing to do (the rule of 15.11.2026).
    private func noteDuringStart(_ text: String) {
        Toasts.shared.show(text)
        GameLog.note("During the start: \(text)")
    }

    /// A word to the player in a start that goes on ("It starts anyway"): it waits on Nightforge's page,
    /// and the curtain stays. As an error it took the curtain away for a start that was fine.
    private var startHint: String?

    private func hintDuringStart(_ text: String) {
        startHint = text
        errorMessage = text
    }

    nonisolated static func startWentWrong(message: String?, hint: String?, failed: Bool) -> Bool {
        failed || (message != nil && message != hint)
    }

    /// The moment a game is handed to its store (Steam, Steam for Mac, Epic, GOG): Nightforge's
    /// curtain until the game shows its window in front (GameBackdrop). A question from Steam, an
    /// error or a start that didn't take take it away; a game that runs but shows nothing for a
    /// minute gets the overlay's "Not starting?".
    private func raiseCurtain(for game: Game) {
        curtainWatch?.cancel()
        // The tip for new players on a curtain that comes up for this start, not again for each way it tries.
        let tip = GameBackdrop.isRaised ? nil : LaunchTip.take(padSymbols)
        if !GameBackdrop.isRaised { macOSQuestionsBefore = nil }
        GameBackdrop.mayCapture = false  // until this start's game runs (watchCurtain)
        raisedForExit = false
        pictureWentAt = nil
        stageHintSince = nil
        stuckAskedAt = nil
        comingBackSince = nil
        stagePids = []
        stageAskers = []
        GameBackdrop.raise(game.name, on: GameDisplay.gameScreen, tip: tip) { [weak self] in self?.gameOnStage == true }
        InputRouter.hidePointerForGame()  // Nightforge in front still
        curtainWatch = Task { await watchCurtain(game) }
        stageWatch?.cancel()
        stageWatch = Task { await watchStage(game) }
        announceLicence(of: game)
    }

    /// A word on the loading screen when Steam will show the game's licence. Only a word: when it's
    /// wrong or missing nothing else changes, the frame comes when Steam asks.
    private func announceLicence(of game: Game) {
        guard game.provider == .steam else { return }
        let appID = game.appID
        let root = game.platform == .mac ? MacSteam.root : game.steamRoot
        Task {
            let open = await Task.detached(priority: .utility) {
                SteamLicenceFiles.stillOpen(entries: SteamCatalog.licences(appID: appID, steamRoot: root), steamRoot: root)
            }.value
            guard open else { return }
            // In the log only: the curtain says what happens, and the licence's frame says it when it comes (the rule of 15.11.2026).
            GameLog.note("Steam's licence for \(game.name) is still open: Steam shows it at this start")
        }
    }

    /// What Steam asks and how the player can answer it, for the heading and the bar on the curtain.
    private var questionLook: GameBackdrop.QuestionLook {
        let inHand = GCController.current?.extendedGamepad ?? GCController.controllers().compactMap(\.extendedGamepad).first
        let pad = SteamLicence.pad(inHandHasTouchpad: inHand.map { Touchpad($0) != nil })
        return GameBackdrop.QuestionLook(kind: SteamQuestion.kind(licence: launchAsksLicence, task: launchQuestionTask, phase: launchPhase),
                                         answering: SteamLicence.answering(pad: pad, pointerOn: Prefs.padPointer, mayClick: PadPointerAccess.granted),
                                         click: PadPart.r2.name(padSymbols.layout))
    }

    /// Steam's question is over. `yes`: it was the licence, answered by the player, and the curtain thanks them.
    private func steamQuestionOver(yes: Bool) {
        launchNeedsConfirmation = false
        if launchAsksLicence, yes { launchPhase = .licenceAnswered }
        launchAsksLicence = false
        launchQuestionTask = nil
    }

    private func watchCurtain(_ game: Game) async {
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        var askAt = Date().addingTimeInterval(Self.curtainPatience)
        var seenOnce = false
        var frontSince: Date?
        var loweredAt: Date?
        var raisedAgain = 0
        /// Its picture on the Space shown since, and how often its window was fetched back under the curtain.
        var pictureSince: Date?
        var broughtBack = 0
        defer { fullScreenHint = nil }
        /// Since when its own full screen hides its picture (ownCaptureHides), and whether the log has it.
        var hiddenByFullScreen: Date?
        var fullScreenSaid = false
        /// The picture's size on the Space shown, and since when it hasn't changed.
        var pictureSize: (size: String, since: Date)?
        /// The game's time in front the pointer was hidden for, and the app in front at the last look.
        var pointerHidden: Date?
        var pointerFront: pid_t? = getpid()  // raiseCurtain hid it with Nightforge in front
        /// The curtain under a question of the game's (makeWay), until it's answered or the picture comes.
        var madeWay = false
        /// The game's question window on screen and since when; when it was last taken as one.
        var questionSeen: (number: Int, since: Date)?
        /// That window's text, when it's one of Windows' message boxes (Wine's +msgbox, which every start
        /// carries): read for each window, a few looks long until Wine has printed it.
        var boxRead: (number: Int, text: String?, looks: Int)?
        var lastAsked: Date?
        /// When that question went, answered by the player – a click or key press just before.
        var answeredAt: Date?
        /// Since when it was taken as one, and whether the game had the front at the last look at it.
        var askedSince: Date?
        var askedInFront = false
        func answeredNow() -> Bool {
            if let padAnswered, Date().timeIntervalSince(padAnswered) < 5 { return true }
            return Self.answered(inputBefore: Self.sinceInput(), shownFor: askedSince.map { Date().timeIntervalSince($0) } ?? 0, inFront: askedInFront)
        }
        /// The curtain away for a question of Steam's (`steamAsks`), until it's answered.
        var steamAsked = false
        /// Steam's question stands on the curtain: when its window was last seen there.
        var steamWindowSeen: Date?
        /// The window the pointer was brought into for Steam's licence, once per window.
        var pointerBroughtTo: Int?
        /// macOS's questions on screen at the last look (`GameProcesses.macOSQuestions`), the frontmost
        /// first: the curtain lies under them while it's up.
        var macOSOnScreen: [Int] = []
        /// The start waits for one that came up during it since then, until it's gone – or until it
        /// waited `macOSPatience` (`macOSGaveUp`), and the start goes on as without one.
        var macOSAskedSince: Date?
        var macOSGaveUp = false
        var macOSBeforeNoted = false
        // The start builds its shaders: known before it's handed over, true until the first picture.
        var buildsShaders = false
        // In wine.log: what each look sees when it changes, and why the watch ends (Black Myth:
        // Wukong's driver warning stayed hidden on 1.11. with not one line of the curtain's).
        var lastLook = ""
        /// Looks in a row without a process list.
        var blindLooks = 0
        /// Since when the curtain has stood with no process of the game's (CurtainEscape).
        var noProcessSince: Date?
        /// Steam's update: how far it was at the last move, and when that was.
        var updateProgress: (fraction: Double?, movedAt: Date)?
        func end(_ why: String) { GameLog.note("Curtain watch for \(game.name) ends: \(why)") }
        /// The curtain over everything again – under macOS's questions on screen still, which have to show.
        func curtainUp() {
            GameBackdrop.raise(game.name, on: GameDisplay.gameScreen) { [weak self] in self?.gameOnStage == true }
            if let lowest = macOSOnScreen.last { GameBackdrop.makeWay(under: lowest) }
        }
        GameLog.note("Curtain watch for \(game.name) begins")
        GameLog.note("  at \(GameLog.clock())")
        curtainWatches += 1
        defer {
            curtainWatches -= 1
            curtainGuards = false
            offerWayOut(game, reason: nil)
            windowsQuestion = nil
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            // The game's end has the curtain now (watchForGameEnd, Quit Game).
            if Task.isCancelled { return end("a new start or Go to Nightforge") }
            if GameBackdrop.isReturning { return end("the game ended") }
            let wentWrong = Self.startWentWrong(message: errorMessage, hint: startHint, failed: failedLaunch != nil)
            let startGoesOn = launchingID == game.id || startedHere.contains(game.id) || playing.contains(game.id)
            if loweredAt == nil {
                switch Self.steamTurn(asks: steamAsks, asked: steamAsked, startGoesOn: startGoesOn, wentWrong: wentWrong) {
                case .away:
                    steamAsked = true
                    noProcessSince = nil  // the question's time isn't the game's
                    if GameOverlay.asksWayOut { GameOverlay.close() }
                    if Self.steamAsksOnCurtain(savesToChoose: saveChoice != nil, battleNet: game.provider == .battlenet) {
                        steamWindowSeen = Date()
                        GameBackdrop.setSteamAsks(true, question: questionLook)
                        offerWayOut(game, reason: .steamAsks)
                        GameLog.note("Curtain stays for \(game.name): Steam asks something, on the curtain")
                    } else {
                        offerWayOut(game, reason: nil)
                        GameBackdrop.hide(after: .zero)
                        GameLog.note("Curtain away for \(game.name): the saves to choose or Battle.net's window are what's asked")
                    }
                    continue
                case .wait:
                    guard let seen = steamWindowSeen else { continue }
                    let steamWindows = await steamWindowsOnScreen(game)
                    // Every question of Steam's alike: what it is at the top, its window framed, the pad's pointer brought
                    // into it once. Only a licence comes before its window, so only it waits longer for one (below).
                    GameBackdrop.sayQuestion(questionLook)
                    let number = SteamLicence.windowToFrame(frontToBack: steamWindows)
                    let frame = await Engine.offMain { number.flatMap { GameProcesses.frame(ofWindow: $0) } }
                    GameBackdrop.frameSteamWindow(frame)
                    if let number, let frame, pointerBroughtTo != number {
                        pointerBroughtTo = number
                        InputRouter.bringPointer(into: frame)
                    }
                    switch Self.steamOnCurtainStep(lowest: steamWindows.last, sinceSeen: Date().timeIntervalSince(seen), savesToChoose: saveChoice != nil,
                                                   patience: launchAsksLicence ? Self.licenceWindowPatience : Self.steamWindowPatience) {
                    case .lieUnder(let lowest):
                        steamWindowSeen = Date()
                        GameBackdrop.makeWay(under: lowest)
                    case .wait:
                        break
                    case .giveUp:
                        // Nothing to answer on the curtain, or the saves' sheet on Nightforge's page: as before it stood here.
                        steamWindowSeen = nil
                        GameBackdrop.setSteamAsks(false)
                        offerWayOut(game, reason: nil)
                        GameBackdrop.hide(after: .zero)
                        GameLog.note("Curtain away for \(game.name): Steam's window isn't to be found under it")
                    }
                    continue
                case .over:
                    // Answered with Cancel, or the start went wrong: Steam's window doesn't stay.
                    hideSteamWindow(for: game)
                    if steamWindowSeen != nil {
                        steamWindowSeen = nil
                        GameBackdrop.setSteamAsks(false)
                        GameBackdrop.returning()
                        comeBack(to: route)
                    }
                    return end("Steam asked, the start is over")
                case .back:
                    steamAsked = false
                    steamWindowSeen = nil
                    GameBackdrop.setSteamAsks(false)
                    offerWayOut(game, reason: nil)
                    curtainUp()
                    hideSteamWindow(for: game)
                    askAt = Date().addingTimeInterval(Self.curtainPatience)  // the question's time isn't the game's
                    GameLog.note("Curtain up again for \(game.name): Steam's question is answered")
                case .none:
                    break
                }
                guard GameBackdrop.isRaised else { return end("the curtain is gone") }
                // The start went wrong: the player has to see what Nightforge says.
                if wentWrong {
                    GameBackdrop.hide(after: .zero)
                    return end("the start went wrong")
                }
            }
            buildsShaders = buildsShaders || launchBuildsShaders
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // One list for all of it: the game's processes and macOS's askers come from the same look.
            let (listing, macOSQuestions) = await Task.detached(priority: .utility) {
                let listing = GameProcesses.curtainLook(marker: marker, folder: folder, front: front)
                return (listing, GameProcesses.macOSQuestions(askers: listing?.askers ?? []))
            }.value
            // No process list (ps doesn't answer): the game's absence is not known, so nothing is decided at
            // this look – above all not that it is gone. The old list stands in for a while, but only to say the
            // game is there (GameProcesses.curtainLook); past three minutes without any, the curtain goes rather
            // than stay for good.
            guard let (pids, companion, askers) = listing.map({ ($0.pids, $0.companion, $0.askers) }) else {
                blindLooks += 1
                if blindLooks == 1 { GameLog.note("Curtain look at \(game.name): no process list (ps doesn't answer), nothing decided") }
                if blindLooks > 360 {
                    GameBackdrop.hide(after: .zero)
                    return end("no process list for three minutes")
                }
                continue
            }
            blindLooks = 0
            seenOnce = seenOnce || !pids.isEmpty
            if !pids.isEmpty, game.platform != .mac { GameBackdrop.expectCapture() }
            if loweredAt == nil { GameBackdrop.keepOverShield() }
            // macOS asks the player something – Tomb Raider's access to its drive (2.11.), a password,
            // an app from the internet: the curtain lies under its window as under a question of the
            // game's, so it shows over everything, and the watch goes on looking for the game – one
            // that shows its window in front lowers the curtain as ever, the question over it still.
            // Down already, it stays down: up again over the game, the player couldn't see it. Only a
            // question that came up during this start holds anything: no "Not starting?" over it, the
            // curtain says so, the game isn't handed the front, the pointer is neither shown nor
            // hidden (the panel that does it takes the keys, a password field's too). One there
            // before it gets a word on the curtain, no more: Tomb Raider's, left unanswered on 3.11.,
            // held every start after it, and ABZU running at 57 FPS counted as hanging.
            let before = macOSQuestionsBefore ?? Set(macOSQuestions)
            macOSQuestionsBefore = before
            macOSOnScreen = macOSQuestions
            let asksNow = Self.macOSAsksNow(macOSQuestions, before: before)
            let turn = Self.macOSTurn(asking: asksNow, since: macOSAskedSince, gaveUp: macOSGaveUp, now: Date())
            switch turn {
            case .makeWay:
                if macOSAskedSince == nil {
                    macOSAskedSince = Date()
                    let name = front.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "nobody"
                    GameLog.note("Curtain under a question of macOS's for \(game.name): \(name) in front")
                }
                if loweredAt == nil {
                    if GameOverlay.asksAboutStart { GameOverlay.close() }
                    askAt = Date().addingTimeInterval(Self.curtainPatience)
                }
            case .giveUp:
                // A question that hangs, or one under another window, never holds the start: from now
                // on it's as one from before it (review M8, 3.11.).
                macOSGaveUp = true
                GameLog.note("Curtain stops waiting for macOS's question for \(game.name) after \(Int(Self.macOSPatience)) s: the start goes on")
            case .answered:
                macOSAskedSince = nil
                // Down already, the game has the screen: no curtain over it.
                if loweredAt == nil {
                    curtainUp()
                    GameLog.note("Curtain up again for \(game.name): macOS's question is answered")
                }
            case .none:
                if !asksNow {
                    macOSAskedSince = nil
                    macOSGaveUp = false
                }
            }
            if !macOSBeforeNoted, macOSQuestions.contains(where: before.contains) {
                macOSBeforeNoted = true
                GameLog.note("Curtain under a question of macOS's from before \(game.name)'s start: the start doesn't wait for it")
            }
            // Under all of them, the backmost lowest; again at each look: nothing gets between.
            if loweredAt == nil, let lowest = macOSQuestions.last { GameBackdrop.makeWay(under: lowest) }
            let macOSAsks = turn == .makeWay
            // Nightforge's own work explains the wait (Steam signing in or restarting, setting up): "Stuck?" counts from its end.
            noProcessSince = pids.isEmpty && loweredAt == nil && !Self.phaseExplainsWait(launchPhase) ? (noProcessSince ?? Date()) : nil
            if case .updating(let fraction)? = launchPhase {
                if updateProgress == nil || updateProgress?.fraction != fraction { updateProgress = (fraction, Date()) }
            } else {
                updateProgress = nil
            }
            let ownStore = game.provider != .steam
            let stuck = CurtainEscape.Look(gameRuns: noProcessSince == nil, startGoesOn: launchingID == game.id, questionUp: macOSAsks,
                                           waited: noProcessSince.map { Date().timeIntervalSince($0) } ?? 0,
                                           updating: !ownStore && updateProgress != nil, ownUpdate: ownStore && updateProgress != nil,
                                           ownSaves: ownStore && launchPhase == .syncingSaves,
                                           updateStillFor: updateProgress.flatMap { $0.fraction == nil ? nil : Date().timeIntervalSince($0.movedAt) },
                                           askedAgo: stuckAskedAt.map { Date().timeIntervalSince($0) })
            let stuckReason = CurtainEscape.reason(stuck)
            offerWayOut(game, reason: stuckReason)
            if stuckReason == nil, GameOverlay.asksWayOut { GameOverlay.close() }
            if CurtainEscape.asks(stuck), !GameOverlay.isOpen { askAboutStuckStart() }
            if pids.isEmpty {
                sayOnCurtain(gameRuns: false, shaders: buildsShaders, macOSAsks: macOSAsks)
            }
            // Started and gone again, nothing starting any more: the start flow says what happened.
            if pids.isEmpty, seenOnce || launchingID == nil, !playing.contains(game.id) {
                // The start judges its first seconds: it tells what's next, under this curtain.
                // Closed at a question of its own – Unity's configuration window, Quit (The Forest, 3.11.): the
                // player's choice, not a way that failed (LaunchHealth.endedAtOwnQuestion). Gone together with
                // its question at this look: answered now.
                if lastAsked != nil, answeredAt == nil, answeredNow() { answeredAt = Date() }
                if loweredAt == nil, Self.endedAtOwnQuestion(answeredAgo: answeredAt.map { Date().timeIntervalSince($0) }) {
                    lastAsked = nil
                    answeredAt = nil
                    LaunchHealth.endedAtOwnQuestion(game.gameID)
                    GameLog.note("\(game.name) ended right at a question of its own, answered by the player: no other way")
                }
                if judging?.id == game.id { return end("its processes are gone, the start decides what's next") }
                if loweredAt != nil { return end("its processes are gone") }  // watchForGameEnd brings Nightforge back
                if launchingID == nil {
                    GameBackdrop.hide(after: .zero)
                    return end(seenOnce ? "its processes are gone, the start is over" : "no process of it seen, the start is over")
                }
                continue
            }
            // Another Windows program of the game's in front (a launcher, an overlay, a dialog of
            // its own) is the game's side too: no handing over, no curtain again.
            let gameFront = front.map(pids.contains) ?? false || companion
            frontSince = gameFront ? (frontSince ?? Date()) : nil
            let (here, anywhere, asking, windows, shieldOnly, size) = await Task.detached(priority: .utility) {
                (GameProcesses.showsWindow(pids), GameProcesses.showsWindow(pids, anySpace: true), GameProcesses.questionWindow(pids),
                 GameProcesses.windowList(pids), GameProcesses.onlyShield(pids), GameProcesses.windowSize(pids))
            }.value
            if here, let size {
                if pictureSize?.size != size { pictureSize = (size, Date()) }
            } else {
                pictureSize = nil
            }
            if let asking, asking.number != questionSeen?.number { questionSeen = (asking.number, Date()) }
            if asking == nil { questionSeen = nil }
            // Its own full screen hiding its picture: one more read, only while only its shield shows.
            let ownCapture = gameFront && !here && anywhere && shieldOnly
                ? await Task.detached(priority: .utility) { GameProcesses.ownCaptureHides(pids) }.value : false
            hiddenByFullScreen = ownCapture ? (hiddenByFullScreen ?? Date()) : nil
            if !fullScreenSaid, Self.fullScreenHidesPicture(hides: ownCapture, gameFront: gameFront, broughtBack: broughtBack,
                                                            hiddenFor: hiddenByFullScreen.map { Date().timeIntervalSince($0) } ?? 0) {
                fullScreenSaid = true
                let capture = await Engine.offMain { GameProcesses.captureNote() }
                let setting = await ProfileStore.shared.profile(for: game.gameID)?.fullscreenHint(german: AppLanguage.current.resolved == .german)
                fullScreenHint = (game, setting)
                GameLog.note("Curtain: \(game.name)'s own full screen hides its picture – its window off the screen under its capture (\(capture));"
                             + " said on the curtain, ⌘-Tab or the pad's Restart")
            }
            let question = asking?.number
            // A thin window is a splash more often than a question (ABZU's Unreal splash, 601×201, showed
            // "asking" for a moment on 3.11.): taken as one once it has stood a while. So is Unity's
            // window while the helper is about to press Play! in it (UnityDialog.isPressing).
            let helperPresses = UnityDialog.isPressing(for: game)
            let asks = loweredAt == nil && !here
                && asking.map { Self.takenAsQuestion($0.size, standing: Date().timeIntervalSince(questionSeen?.since ?? Date()),
                                                     helperPresses: helperPresses) } == true
            windowsQuestion = asks && game.bottle.isBuiltIn ? game : nil
            // A message box that reports an error (CloserLook.errorNotice): said so on the curtain around it, and
            // that Nightforge takes it from there (board "Vorhang bei Fehlstart", way 1, the player's pick of 15.11.2026).
            if asks, let question, game.platform == .windows,
               boxRead?.number != question || (boxRead?.text == nil && (boxRead?.looks ?? 0) < 3) {
                let mark = LearnedFixes.lastLaunchMark(game.gameID) ?? 0, gameFolder = game.installDirName
                let text = await Task.detached(priority: .utility) {
                    CloserLook.read(GameLog.text(since: mark), gameFolder: gameFolder).boxes.last
                }.value
                boxRead = (question, text, boxRead?.number == question ? (boxRead?.looks ?? 0) + 1 : 1)
                if let text, CloserLook.errorNotice(text) {
                    GameLog.note("Curtain under a window of \(game.name)'s: a message box that reports an error – \"\(GameLog.redacted(String(text.prefix(160))))\"")
                }
            }
            let reportsError = asks && boxRead?.number == question && boxRead?.text.map(CloserLook.errorNotice) == true
            if asks {
                if lastAsked == nil { askedSince = Date() }
                lastAsked = Date()
                askedInFront = gameFront
            } else if lastAsked != nil, asking == nil {
                // Its question went: answered, if the player clicked or pressed a key just before, while it
                // stood and the game had the front – not a click elsewhere, nor one from before it came.
                if answeredNow() { answeredAt = Date() }
                lastAsked = nil
            }
            let frontName = front.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "nobody"
            let look = "\(pids.count) processes, in front \(frontName) (\(front.map(String.init) ?? "-"), \(gameFront ? "the game's" : "not the game's")), "
                + "windows \(windows), picture \(here ? "here" : anywhere ? "elsewhere" : "none"), asks \(asks ? "yes" : "no"), "
                + "curtain \(loweredAt == nil ? (madeWay ? "under the question" : "up") : "down")"
                + (macOSQuestions.isEmpty ? "" : ", macOS asks \(macOSAsks ? "now" : "from before")")
            if look != lastLook {
                lastLook = look
                GameLog.note("Curtain look at \(game.name): \(look)")
            }
            // Each app coming to the front brings the pointer back over the curtain (1.11.): another
            // one (Steam's, Nightforge handing over) hidden again at once, the game only while it shows
            // no picture yet. Taking the keys from a game in full screen for those 50 ms tells it that it
            // lost the focus, and a Unity or Unreal game minimises itself then (The Forest, 6.11.:
            // gone right after "Curtain down" in the runs with the pad, there in those with the
            // mouse; GameStage). Not while it asks something, which takes the mouse.
            let newFront = front != pointerFront
            pointerFront = front
            // Nor while macOS asks, nor while one of its askers has the front before its window shows.
            if loweredAt == nil, !asks, !madeWay, !macOSAsks, !(front.map(askers.contains) ?? false) {
                switch Self.pointerUnderCurtain(gameFront: gameFront, picture: here || anywhere,
                                                frontForSecond: frontSince.map { $0 != pointerHidden && Date().timeIntervalSince($0) >= 1 } ?? false,
                                                newFront: newFront, nightforgeFront: front == getpid()) {
                case .overGame:
                    pointerHidden = frontSince
                    InputRouter.hidePointerOverGame()
                case .fromNightforge:
                    InputRouter.hidePointerForGame()
                case .leave:
                    break
                }
            }
            // Its question answered, no picture yet: the curtain over everything again until there is one.
            if madeWay, !asks, !here, loweredAt == nil {
                madeWay = false
                curtainUp()
            }
            sayOnCurtain(gameRuns: !pids.isEmpty, shaders: buildsShaders, asks: asks, errorBox: reportsError,
                         macOSAsks: macOSAsks, fullScreen: fullScreenHint.map { $0.setting ?? "" })
            pictureSince = here ? (pictureSince ?? Date()) : nil
            switch Self.curtainStep(lowered: loweredAt != nil, gameFront: gameFront, nightforgeFront: front == getpid(),
                                    macOSAsks: macOSAsks || front.map(askers.contains) ?? false,
                                    windowHere: here, windowAnywhere: anywhere, asks: asks,
                                    frontFor: frontSince.map { Date().timeIntervalSince($0) } ?? 0,
                                    settle: raisedAgain == 0 ? 1 : Self.settleAgain,
                                    guardOver: loweredAt.map { Date().timeIntervalSince($0) > Self.focusGuard } ?? false,
                                    pictureFor: pictureSince.map { Date().timeIntervalSince($0) } ?? 0,
                                    broughtBack: broughtBack, playerActed: Self.playerActed(), shieldOnly: shieldOnly,
                                    steadyFor: pictureSize.map { Date().timeIntervalSince($0.since) } ?? 0) {
            case .wait:
                break
            case .handOver:
                _ = await handFocus(to: pids)
            case .bringBack:
                broughtBack += 1
                frontSince = nil
                GameLog.note("Curtain: \(game.name) has the front, its window isn't on the screen: fetching it back (\(broughtBack))")
                _ = await handFocus(to: pids, again: true)
            case .makeWay:
                if GameOverlay.asksAboutStart { GameOverlay.close() }
                if asks, let question { GameBackdrop.makeWay(under: question) }  // again at each look: nothing gets between
                if !madeWay {
                    madeWay = true
                    InputRouter.showPointerOverGame()
                    GameLog.note("Curtain under a window of \(game.name)'s: it asks something")
                }
                askAt = Date().addingTimeInterval(Self.curtainPatience)  // no "Not starting?" over its question
            case .lower:
                fullScreenHint = nil
                if GameOverlay.asksAboutStart { GameOverlay.close() }
                GameBackdrop.lower()
                input.parkPointerForGame()
                loweredAt = Date()
                curtainGuards = true
                stage.pictureSeen()
                madeWay = false
                LaunchHealth.pictureShown(game.gameID)  // it started, however soon it ends now
                let size = await Task.detached(priority: .utility) { GameProcesses.windowSize(pids) }.value
                let screen = GameDisplay.gameScreen.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "?"
                GameLog.note("Curtain down for \(game.name): \(front.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "nobody") in front, its window \(size ?? "none") on \(screen)")
                GameLog.note("  at \(GameLog.clock())")
                // Down because it had stood long enough: going up again for the front would only flap.
                if !gameFront { return end("its picture doesn't stay under the curtain, the stage watch has it") }
            case .raiseAgain:
                if raisedAgain >= Self.maxRaisedAgain { return end("the front doesn't stay with it, the curtain stays down") }
                // Another app took the front from the game – Unity builds its window anew for full
                // screen, and macOS hands the front on meanwhile: back to the game, under the curtain.
                curtainUp()
                loweredAt = nil
                curtainGuards = false
                frontSince = nil
                raisedAgain += 1
                GameLog.note("Curtain up again for \(game.name): \(front.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "nobody") in front")
            case .done:
                return end(front == getpid() ? "Nightforge in front" : "the game kept the front")
            }
            if loweredAt == nil, !pids.isEmpty, Date() >= askAt, !GameOverlay.isOpen {
                askAt = Date().addingTimeInterval(Self.curtainPatience)
                askAboutStart(game)
            }
        }
        end("a new start or Go to Nightforge")
    }

    /// From a start to the game's end, once the curtain is down: the game stays where the player can
    /// reach it (GameStage), and Nightforge's page never lies over it. A look a second, without a
    /// process list as long as the game is in front (the game's frames come first).
    private func watchStage(_ game: Game) async {
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        stage = GameStage()
        // Over with the game. Left standing, the next finger on the touchpad would give that window's app
        // the front, with the player back in Nightforge.
        defer {
            overGame = nil
            overGameFront = false
            overGameHanded = nil
        }
        var pids = Set<pid_t>()
        var companion = false
        var askers = Set<pid_t>()
        var listed = Date.distantPast
        var noted = ""
        var handedBack = false
        func goesOn() -> Bool {
            launchingID == game.id || startedHere.contains(game.id) || playing.contains(game.id) || judging?.id == game.id
                || GameBackdrop.isRaised
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(stage.left ? 5 : 1))  // nothing to do meanwhile but see it return
            guard !Task.isCancelled, goesOn() else { return }
            // The curtain that came for a picture that went is this watch's own to take away again.
            if pictureWentAt != nil, !GameBackdrop.isReturning { pictureWentAt = nil }
            guard !GameBackdrop.isRaised || pictureWentAt != nil || stageHintSince != nil else { continue }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let inFront = front.map(pids.contains) ?? false
            if !inFront || Date().timeIntervalSince(listed) > 30 {
                guard let look = await Task.detached(priority: .utility, operation: {
                    GameProcesses.curtainLook(marker: marker, folder: folder, front: front)
                }).value else { continue }
                (pids, companion, askers) = (look.pids, look.companion, look.askers)
                (stagePids, stageAskers) = (pids, askers)
                listed = Date()
            }
            let page = GameBackdrop.pageNumber
            let known = pids
            let screen = GameDisplay.gameScreen.map { GameProcesses.cgRect($0.frame) }
            let windows = await Task.detached(priority: .utility) { GameProcesses.onStage(known, page: page, screen: screen) }.value
            if windows.pageOver {
                GameBackdrop.stepAside()
                GameLog.note("Stage: the page lay over \(game.name)'s picture, it goes behind")
            }
            let gameFront = (front.map(pids.contains) ?? false) || companion
            if gameFront, windows.here { GameBackdrop.keepUnderGame(at: windows.level) }
            let askerFront = front.map(askers.contains) ?? false
            if let went = pictureWentAt, GameStage.curtainEnds(cameBack: gameFront && windows.here, waited: Date().timeIntervalSince(went)) {
                pictureWentAt = nil
                GameBackdrop.playing()
                GameLog.note("Stage: \(game.name) \(gameFront && windows.here ? "is back" : "runs on without its picture"), the curtain goes behind it")
            }
            // Another app's window over the game (Steam's store from its menu): the stage leaves it be, and
            // once it's gone, however it was closed, the game is brought back.
            let over = await Task.detached(priority: .utility) { () -> PadPointerRules.OverGame? in
                let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                return PadPointerRules.windowOverGame(list, game: known, ignoring: [getpid()])
            }.value
            let windowWent = overGame != nil && over == nil
            overGame = over
            overGameFront = gameFront
            if windowWent {
                stage.again()
                overGameHanded = nil
                GameLog.note("Stage: the window over \(game.name) has gone")
            }
            reachWindowOverGame(touched: false)
            let stageLook = GameStage.Look(gameFront: gameFront, windowHere: windows.here, windowAnywhere: windows.anywhere,
                                           handsOff: GameOverlay.isOpen || askerFront || over != nil,
                                           // A swipe to another Space moves no key and no click.
                                           playerActed: !windowWent && (Self.playerActed() || GameBackdrop.spaceJustChanged),
                                           guarded: curtainGuards, now: Date())
            // Its own full screen hiding its picture after the curtain went (GameStage.hiddenByOwnFullScreen): one more
            // read of the window list, only while it's in front with no picture.
            let onlyOwnShield = gameFront && !windows.here
                ? await Task.detached(priority: .utility) { GameProcesses.onlyShield(known) }.value : false
            if await fullScreenOnStage(game, hides: stage.hiddenByOwnFullScreen(stageLook, onlyOwnShield: onlyOwnShield),
                                       gameFront: gameFront, pictureHere: windows.here, pids: pids, handedBack: &handedBack) { continue }
            let step = stage.step(stageLook)
            let name = front.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "nobody"
            let look = "\(name) in front, picture \(windows.here ? "here" : windows.anywhere ? "elsewhere" : "none")"
                + (gameFront ? " (the game's)" : "") + (stage.left ? ", the player went elsewhere" : "")
            if look != noted, stage.sawPicture {
                noted = look
                GameLog.note("Stage of \(game.name): \(look)")
            }
            switch step {
            case .wait:
                break
            case .bringBack:
                GameLog.note("Stage: fetching \(game.name) back (\(stage.tries)), \(name) in front")
                await handFocus(to: pids, again: true)
            case .gaveUp:
                GameLog.note("Stage: \(game.name) didn't come back, the player has the Dock, Switch to Game and the overlay")
            }
        }
    }

    /// The stage's part in the full-screen hint (GameStage.hiddenByOwnFullScreen), when the game's own full screen
    /// hides its picture only after the start's curtain went (Overwatch, 21.11.2026: 60 Hz half a minute later). The
    /// curtain comes up again with the words and the pad's Restart it has during the start (fullScreenWords), goes
    /// behind the game once its picture is back, and after the player's ⌘-Tab – Wine gives the display back then and
    /// hides the game – hands the game the front once, as the curtain's watch does. Only the window list and the
    /// display's state, as ever: nothing at the game's process (Overwatch's cheat protection). True while the hint
    /// stands: the stage fetches nothing meanwhile.
    private func fullScreenOnStage(_ game: Game, hides: Bool, gameFront: Bool, pictureHere: Bool, pids: Set<pid_t>,
                                   handedBack: inout Bool) async -> Bool {
        guard stageHintSince != nil else {
            guard hides, !GameOverlay.isOpen else { return false }
            stageHintSince = Date()
            handedBack = false
            let setting = await ProfileStore.shared.profile(for: game.gameID)?.fullscreenHint(german: AppLanguage.current.resolved == .german)
            let capture = await Engine.offMain { GameProcesses.captureNote() }
            fullScreenHint = (game, setting)
            GameLog.note("Stage: \(game.name)'s own full screen hides its picture after the curtain went – only its capture's shield"
                         + " on the screen (\(capture)); the curtain says so again, ⌘-Tab or the pad's Restart")
            GameBackdrop.raise(game.name, on: GameDisplay.gameScreen) { [weak self] in self?.gameOnStage == true }
            let words = Self.fullScreenWords(setting: setting)
            let restart = controllerConnected ? [CurtainButton(symbol: padSymbols.confirm, label: L10n.t("Restart"))] : []
            GameBackdrop.setStatus(words.line, detail: words.sentence, buttons: restart)
            return true
        }
        if fullScreenHint == nil {
            // Restarted with the pad (restartsHiddenGame): the new start's curtain has it from here.
            stageHintSince = nil
            return true
        }
        if gameFront, pictureHere {
            stageHintSince = nil
            fullScreenHint = nil
            GameBackdrop.lower()
            input.parkPointerForGame()
            GameLog.note("Stage: \(game.name)'s picture is back, the curtain goes behind it")
            return false
        }
        if !gameFront, !handedBack {
            handedBack = true
            GameLog.note("Stage: another app in front under the full-screen hint (the player's ⌘-Tab), \(game.name) gets the front again")
            await handFocus(to: pids)
        }
        return true
    }

    enum MacOSTurn: Equatable { case none, makeWay, giveUp, answered }

    /// How long the curtain waits under a question of macOS's before the start goes on without it.
    nonisolated static let macOSPatience: TimeInterval = 180

    /// The start around a question of macOS's that came up during it (`asking`, `macOSAsksNow`;
    /// `since`: when it began, `gaveUp`: the start stopped waiting for this one): it waits while it
    /// stands, for `macOSPatience` at most – one that hangs, or lies under another window, would
    /// hold it forever (review M8) – and the curtain is over everything again once it's gone.
    nonisolated static func macOSTurn(asking: Bool, since: Date?, gaveUp: Bool, now: Date) -> MacOSTurn {
        if asking {
            if gaveUp { return .none }
            if let since, now.timeIntervalSince(since) >= macOSPatience { return .giveUp }
            return .makeWay
        }
        return since != nil && !gaveUp ? .answered : .none
    }

    /// Whether one of macOS's questions on screen (`questions`) came up during this start: not among
    /// those at its first look (`before`). One left from before holds no start (3.11.).
    nonisolated static func macOSAsksNow(_ questions: [Int], before: Set<Int>) -> Bool {
        questions.contains { !before.contains($0) }
    }

    /// The start waits for the player where the curtain would hide it: Steam's question (licence,
    /// ShowInterstitials), its sign-in – after a restart (`restartStuckSteam`) or a Steam for Mac that
    /// lost it (`launchMac`) – or the choice of saves, a sheet in Nightforge's own window.
    private var steamAsks: Bool {
        Self.startAsksPlayer(needsConfirmation: launchNeedsConfirmation, phase: launchPhase, savesToChoose: saveChoice != nil)
    }

    nonisolated static func startAsksPlayer(needsConfirmation: Bool, phase: LaunchPhase?, savesToChoose: Bool) -> Bool {
        needsConfirmation || savesToChoose || phase == .signInAgain || phase == .signInInSteamWindow || phase == .battleNetAsks
    }

    enum SteamTurn: Equatable { case none, away, wait, back, over }

    /// The start's curtain around a question of Steam's (`asks`; `asked`: the curtain went for it
    /// already). The player has to see it, so the curtain goes meanwhile; the watch waits and raises
    /// it again once it's answered and the start goes on. It used to end there, and the rest of
    /// Black Myth: Wukong's start (1.11.) ran without a curtain or a look for the game's own driver
    /// warning. A start that ended or went wrong meanwhile ends the watch; one that went wrong
    /// without a question is the watch's own business (`none`).
    /// The choice of saves is a sheet in Nightforge's own window, under the curtain, and Battle.net's question
    /// stands in Battle.net's window, which `steamWindowsOnScreen` doesn't look for: only those take it away.
    nonisolated static func steamAsksOnCurtain(savesToChoose: Bool, battleNet: Bool = false) -> Bool { !savesToChoose && !battleNet }

    enum SteamOnCurtain: Equatable { case wait, lieUnder(Int), giveUp }

    /// How long the curtain stands without Steam's window on it before it goes as it used to, so a
    /// question nobody can see never holds the start.
    nonisolated static let steamWindowPatience: TimeInterval = 8

    /// `lowest`: the backmost of Steam's windows on screen, which the curtain lies right under.
    nonisolated static func steamOnCurtainStep(lowest: Int?, sinceSeen: TimeInterval, savesToChoose: Bool,
                                               patience: TimeInterval = steamWindowPatience) -> SteamOnCurtain {
        if savesToChoose { return .giveUp }
        if let lowest { return .lieUnder(lowest) }
        return sinceSeen >= patience ? .giveUp : .wait
    }

    /// The frame comes with Steam's first word about the licence, its window later: 6 s later with a
    /// Steam that had only just started (9.11.), and it may take longer on a slower Mac.
    nonisolated static let licenceWindowPatience: TimeInterval = 30

    private func steamWindowsOnScreen(_ game: Game) async -> [Int] {
        if game.platform == .mac {
            let pids = MacSteam.windowPids
            return await Engine.offMain { GameProcesses.steamWindows(pids: pids) }
        }
        return await SteamWindow.onScreen()
    }

    /// How far an update is, for the thin bar on the curtain; nil without a figure.
    nonisolated static func curtainProgress(phase: LaunchPhase?) -> Double? {
        guard case .updating(let fraction?)? = phase else { return nil }
        return min(max(fraction, 0), 1)
    }

    /// The line under the bar: how fast and how long once that's known, and until then what's going on.
    nonisolated static func curtainHint(progress: Double?, speed: String?, launchHint: String?) -> String? {
        progress == nil ? launchHint : speed ?? launchHint
    }

    nonisolated static func steamTurn(asks: Bool, asked: Bool, startGoesOn: Bool, wentWrong: Bool) -> SteamTurn {
        if asks, !wentWrong { return !startGoesOn ? .over : asked ? .wait : .away }
        if asked { return startGoesOn && !wentWrong ? .back : .over }
        return .none
    }

    /// Steam's window that Nightforge opened for a question (`showSteamWindow`), out of sight again
    /// once it's answered: left open, it came forward when the game ended, before the curtain (1.11.).
    private func hideSteamWindow(for game: Game) {
        if game.provider == .battlenet {
            if Self.hidesBattleNetWindow(messageUp: errorMessage != nil) { BattleNetClient.hide() }
        } else if game.platform == .mac {
            MacSteam.hide()
        } else if steamWindowShown {
            steamWindowShown = false
            Task { await SteamWindow.hide() }
        }
    }

    /// Not when the start ended with a message: those send the player to the client ("Press Play in its
    /// window", "Its window says why", sayBattleNetFailed), and the window went half a second after it came.
    nonisolated static func hidesBattleNetWindow(messageUp: Bool) -> Bool { !messageUp }

    /// The curtain's lines at a look (`curtainStatus`, `curtainDetail`); once it's down they wait for the next start.
    private func sayOnCurtain(gameRuns: Bool, shaders: Bool, asks: Bool = false, errorBox: Bool = false, macOSAsks: Bool = false,
                              fullScreen: String? = nil) {
        // The game's own full screen hides its picture: what the player can do, and the pad's Restart. A question of
        // its own or of macOS's comes first.
        if let fullScreen, !asks, !macOSAsks {
            let words = Self.fullScreenWords(setting: fullScreen.isEmpty ? nil : fullScreen)
            let restart = controllerConnected ? [CurtainButton(symbol: padSymbols.confirm, label: L10n.t("Restart"))] : []
            return GameBackdrop.setStatus(words.line, detail: words.sentence, buttons: restart)
        }
        let phase = launchingID == nil ? nil : launchPhase?.curtainTitle ?? launchRepair?.title
        let progress = launchingID == nil ? nil : Self.curtainProgress(phase: launchPhase)
        // A pad answers the game's question where the helper can press for it (PadAnswerRun).
        let pad = controllerConnected && PadAnswerRun.available ? padSymbols : nil
        let sentence = launchingID == nil ? nil
            : Self.curtainSentence(phase: launchPhase, repair: launchRepair, confirming: launchNeedsConfirmation)
        GameBackdrop.setStatus(Self.curtainStatus(phase: phase, shaders: shaders, gameRuns: gameRuns,
                                                  asks: asks, errorBox: errorBox, macOSAsks: macOSAsks),
                               detail: Self.curtainDetail(sentence: Self.curtainHint(progress: progress, speed: updateSpeed, launchHint: sentence),
                                                  asks: asks, errorBox: errorBox && !macOSAsks, pad: pad != nil,
                                                  macOSAsks: macOSAsks, shaders: shaders && gameRuns && phase == nil),
                               progress: progress,
                               buttons: Self.curtainButtons(asks: asks, errorBox: errorBox, macOSAsks: macOSAsks, pad: pad))
    }

    /// What the curtain says when the game's own full screen hides its picture (fullScreenHidesPicture), with the
    /// place of the setting from its profile (`setting`, GameProfile.fullscreenHint). The board "Vorhang nach der
    /// Regel": one line, one sentence, Restart on the pad. One ⌘-Tab should do: Wine gives the display back at its own
    /// ⌘-Tab, and the curtain's watch hands the game the front again (live check pending, 15.11.2026).
    nonisolated static func fullScreenWords(setting: String?) -> (line: String, sentence: String) {
        let sentence = setting.map { L10n.t("⌘⇥ brings it to the front. So it doesn't happen again: %@ in the game.", $0) }
            ?? L10n.t("⌘⇥ brings it to the front. So it doesn't happen again: “Borderless window” in the game.")
        return (L10n.t("Full screen is hiding the game"), sentence)
    }

    /// The pad's Restart on a curtain whose game's full screen hides its picture (InputRouter, A): the game ends and
    /// starts again, as the overlay's Restart Game does. About every second start of Overwatch's came with its picture
    /// (15.11.2026). Nothing while the overlay is up: A is its own then.
    func restartsHiddenGame() -> Bool {
        guard let game = fullScreenHint?.game, GameBackdrop.isRaised, !GameOverlay.isOpen else { return false }
        fullScreenHint = nil
        GameBackdrop.setStatus(nil, detail: nil)  // "Starting …" until the new start says its own
        GameLog.note("Curtain: the player restarts \(game.name) with the pad – its full screen hid its picture")
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        LaunchHealth.playerQuit(game.gameID)
        restartAfterEnd = game
        Task {
            await Task.detached(priority: .userInitiated) {
                GameProcesses.end(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
            }.value
            await startAgainWhenEnded(game)
        }
        return true
    }

    /// The pad's buttons under a question the player answers (the rule of 15.11.2026): the game's error box OK, its
    /// question confirm and cancel – where the pad answers it (`pad`, PadAnswerRun). macOS takes only the mouse.
    nonisolated static func curtainButtons(asks: Bool, errorBox: Bool, macOSAsks: Bool, pad: PadSymbols?) -> [CurtainButton] {
        guard asks, !macOSAsks, let pad else { return [] }
        if errorBox { return [CurtainButton(symbol: pad.confirm, label: L10n.t("OK"))] }
        return [CurtainButton(symbol: pad.confirm, label: L10n.t("Confirm")), CurtainButton(symbol: pad.back, label: L10n.t("Cancel"))]
    }

    /// The short sentence under the curtain's line: the step's own where it's true once or the player has a window
    /// to answer in, Steam's question before the start, the end of a start Nightforge mends. The rule of 15.11.2026:
    /// everything else the Play button's line says goes to the log as the phase begins.
    nonisolated static func curtainSentence(phase: LaunchPhase?, repair: LaunchRepair?, confirming: Bool) -> String? {
        if confirming { return LaunchPhase.confirmHint }
        if let phase { return phase.curtainSentence }
        return repair?.detail
    }

    /// Asks the player whether the root `root` goes into the prefix (GameOverlay.askRoot), and waits for the
    /// answer. A start called off meanwhile takes the question away: no.
    private func askToTrust(_ root: String, for game: Game) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (answered: CheckedContinuation<Bool, Never>) in
                GameOverlay.askRoot(game.name, root: root, on: GameDisplay.gameScreen, symbols: padSymbols) { answered.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in GameOverlay.close() }
        }
    }

    /// What Nightforge mends, on the curtain at once: the start loop says it between two starts, when no
    /// curtain look runs to say it. What it found and does goes to the log (LaunchRepair.logLine).
    private func sayRepair(_ repair: LaunchRepair?) {
        launchRepair = repair
        guard let repair else { return }
        GameLog.note("Curtain: \"\(repair.title)\" – \(repair.logLine)")
        GameBackdrop.setStatus(repair.title, detail: repair.detail)
    }

    /// The curtain's second line: how to answer macOS (`macOSAsks`); none under a question of the game's it waits
    /// for (`asks`) – under its error box (`errorBox`) what to press and that Nightforge goes on from there, with the
    /// pad's button (`padOK`) where one answers it –; else the start's sentence (`curtainSentence`), else that shaders
    /// are built only once (`shaders`). A question of macOS's the start doesn't wait for is in the look's line only.
    nonisolated static func curtainDetail(sentence: String?, asks: Bool, errorBox: Bool = false, pad: Bool = false,
                                          macOSAsks: Bool = false, shaders: Bool = false) -> String? {
        if macOSAsks { return L10n.t("Answer with the mouse or trackpad.") }
        if asks, errorBox { return pad ? L10n.t("Nightforge takes care of the rest.") : L10n.t("Press OK – Nightforge takes care of the rest.") }
        if asks { return pad ? nil : L10n.t("Answer with the mouse or trackpad.") }
        return sentence ?? (shaders ? L10n.t("Only the first time.") : nil)
    }

    /// The step the curtain names: a question on it – macOS's (`macOSAsks`) or the game's (`asks`) –
    /// else the start's own (`phase`, "Starting Steam …") while it has one, then what the game does
    /// until its window shows. Nil: "Starting …".
    /// `errorBox`: the game's question is one of Windows' message boxes reporting an error, with only OK
    /// to press (CloserLook.errorNotice).
    nonisolated static func curtainStatus(phase: String?, shaders: Bool, gameRuns: Bool,
                                          asks: Bool = false, errorBox: Bool = false, macOSAsks: Bool = false) -> String? {
        if macOSAsks { return L10n.t("macOS is asking for permission") }
        if asks, errorBox { return L10n.t("The game reports an error") }
        if asks { return L10n.t("The game is asking something") }
        if let phase { return phase }
        // Its process running is no new line: "Starting …" until the picture (the rule of 15.11.2026; the look's
        // line in the log says it runs). Its first start with new graphics takes long, and says why.
        return gameRuns && shaders ? L10n.t("Preparing shaders …") : nil
    }

    /// How long after the game's own question went, answered by the player, its end with no picture
    /// still counts as that answer: Wine takes a while to end a Unity game after Quit – longer than
    /// the 3 s counted from the last look at the question at first (The Forest, 4.11.).
    nonisolated static let ownQuestionGrace: TimeInterval = 15
    /// The player's click or key press at most this long before the question went: its answer.
    nonisolated static let answerInput: TimeInterval = 4

    /// Whether the game's question that just went was answered: the player's last click or key press
    /// (`inputBefore` seconds ago) came while it stood (`shownFor`) and the game had the front
    /// (`inFront`). A splash that goes by itself isn't: no one answered it.
    nonisolated static func answered(inputBefore: TimeInterval, shownFor: TimeInterval, inFront: Bool) -> Bool {
        inFront && inputBefore <= answerInput && inputBefore < shownFor
    }

    /// Whether a game that ended with no picture ended at a question of its own: answered
    /// `answeredAgo` seconds before.
    nonisolated static func endedAtOwnQuestion(answeredAgo: TimeInterval?) -> Bool {
        answeredAgo.map { $0 <= ownQuestionGrace } ?? false
    }

    /// Whether the start takes an end at the game's own question (`end`, LaunchHealth.ownQuestionEnd)
    /// as the player's: one of this start, with no process of the game's running after it – a
    /// launcher whose window counted as one hands over to the game (`lastRunning`, the first seconds'
    /// last look at it) – and neither the graphics failing nor a crash in its log.
    nonisolated static func ownQuestionEndStands(end: Date?, startedAt: Date, lastRunning: Date?, graphicsFailed: Bool, crashed: Bool) -> Bool {
        guard let end, end >= startedAt, !graphicsFailed, !crashed else { return false }
        return (lastRunning ?? .distantPast) <= end.addingTimeInterval(2)
    }

    /// Seconds since the player last clicked or pressed a key, anywhere (no permission needed).
    nonisolated static func sinceInput() -> TimeInterval {
        [CGEventType.leftMouseDown, .rightMouseDown, .keyDown]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }

    /// How long a thin window – at least `thinRatio` times as wide as high – stands before the
    /// curtain takes it as a question: a splash goes by then, a question waits.
    nonisolated static let thinPatience: TimeInterval = 4
    nonisolated static let thinRatio: CGFloat = 2.5
    /// How long a question stands under the curtain while Unity's helper is to press Play! in it
    /// (`helperPresses`): it does in a moment, and one it can't press shows after this.
    nonisolated static let helperPatience: TimeInterval = 5

    nonisolated static func takenAsQuestion(_ size: CGSize, standing: TimeInterval, helperPresses: Bool = false) -> Bool {
        if helperPresses { return standing >= helperPatience }
        return size.width < thinRatio * size.height || standing >= thinPatience
    }

    enum PointerStep: Equatable { case leave, overGame, fromNightforge }

    /// How the pointer is hidden under the curtain, when at all. Over a game without a picture yet the
    /// sheer panel may take its keys for 50 ms; Nightforge in front needs no panel. Any other app is
    /// left alone: the panel took the keys from Steam Helper – as its question came up (Drawful 2,
    /// 8.11.), five times on the way back – and from Claude, Chrome and Finder.
    /// The price: while such an app has the front, the pointer can show on the curtain.
    nonisolated static func pointerUnderCurtain(gameFront: Bool, picture: Bool, frontForSecond: Bool, newFront: Bool,
                                                nightforgeFront: Bool) -> PointerStep {
        if gameFront { return !picture && frontForSecond ? .overGame : .leave }
        return newFront && nightforgeFront ? .fromNightforge : .leave
    }

    enum CurtainStep: Equatable { case wait, handOver, makeWay, bringBack, lower, raiseAgain, done }

    /// What the curtain does at a look. Up: it waits for the game's window – `windowHere` on the
    /// Space shown, `windowAnywhere` in any (Mafia II's first start opened behind, in another) –
    /// hands the front to the game when another app has it, and sinks once the game has been in
    /// front with its window shown for `settle` seconds. Down, for `focusGuard`: another app taking
    /// the front raises it again; Nightforge in front (Go to Nightforge) ends the watch. A window of
    /// the game's that asks something (`asks`) before any picture gets the front too, over the
    /// curtain (`makeWay`): under it the player could never answer (Black Myth: Wukong, 1.11.).
    /// While macOS asks something the start waits for, or its question has the front (`macOSAsks`),
    /// the game isn't handed the front – the question may have it, and the keys – but taking it
    /// with its window, it sinks the curtain as ever; down already, the curtain stays down, the
    /// question over the game.
    ///
    /// The curtain never stays over a game that runs: its picture shown for `curtainCeiling` seconds,
    /// it sinks whoever has the front. In front with its window off the screen – shrunk into the Dock,
    /// or in a Space not shown – it's fetched back (`bringBack`, Wine does nothing for an app that's
    /// active already), then the curtain sinks anyway (GameStage has it from there). Nightforge
    /// in front is the player's choice only after a ⌘ or a click (`playerActed`); by itself it's macOS
    /// handing the front on, and the game gets it back (Valheim, 7.11.: the watch ended there).
    nonisolated static func curtainStep(lowered: Bool, gameFront: Bool, nightforgeFront: Bool, macOSAsks: Bool = false,
                                        windowHere: Bool, windowAnywhere: Bool, asks: Bool = false, frontFor: TimeInterval,
                                        settle: TimeInterval = 1, guardOver: Bool, pictureFor: TimeInterval = 0,
                                        broughtBack: Int = 0, playerActed: Bool = false, shieldOnly: Bool = false,
                                        steadyFor: TimeInterval = .infinity) -> CurtainStep {
        if lowered {
            if guardOver || (nightforgeFront && playerActed) { return .done }
            return gameFront || macOSAsks ? .wait : .raiseAgain
        }
        let handOver: CurtainStep = macOSAsks ? .wait : .handOver
        if asks, !windowHere { return gameFront ? .makeWay : handOver }
        guard windowHere || windowAnywhere else { return .wait }
        if windowHere, !macOSAsks, pictureFor >= curtainCeiling { return .lower }
        guard gameFront else { return handOver }
        // Only with its window on the Space shown: elsewhere, the curtain sinking showed Nightforge's
        // page while the game had the front (1.11.).
        if windowHere { return frontFor >= settle && steadyFor >= pictureSteady ? .lower : .wait }
        guard !macOSAsks, frontFor >= windowAwayPatience else { return .wait }
        if broughtBack < maxBroughtBack { return .bringBack }
        // Only a black shield on screen (Overwatch, 8.11.): sinking would count it as a picture and
        // never ask. The start stays open, "Not starting?" comes over the shield in its time.
        return shieldOnly ? .wait : .lower
    }

    /// How long the picture's size has to stay before the curtain sinks: Overwatch on 8.11. 14:53 showed
    /// a window of 1392×742, then 1342×710, and only then set its display mode. The curtain sank in
    /// between, so the page and a black screen flashed up.
    nonisolated static let pictureSteady: TimeInterval = 2
    /// How long a picture may stand under the curtain, whatever has the front.
    nonisolated static let curtainCeiling: TimeInterval = 15
    /// How long the game has the front with its window off the screen before it's fetched back.
    nonisolated static let windowAwayPatience: TimeInterval = 4
    nonisolated static let maxBroughtBack = 2

    /// The game's own full screen hides its picture for good (GameProcesses.ownCaptureHides): it has the front, it was
    /// fetched back `maxBroughtBack` times, and it has stood so `fullScreenHidesFor`. In Overwatch's starts with a
    /// picture the window was off for a moment only (15.11.2026); in those without, it never came back. What the
    /// curtain says then waits for the player's pick on the board "Vollbild verdeckt das Spiel".
    nonisolated static func fullScreenHidesPicture(hides: Bool, gameFront: Bool, broughtBack: Int, hiddenFor: TimeInterval) -> Bool {
        hides && gameFront && broughtBack >= maxBroughtBack && hiddenFor >= fullScreenHidesFor
    }

    nonisolated static let fullScreenHidesFor: TimeInterval = 10

    /// A ⌘ (⌘-Tab, ⌘H) or a click within `seconds`: the player moved, what came to the front is their
    /// choice. Not any key: one playing with the keyboard presses them all the time. A click in the
    /// game just as the front goes counts too – Nightforge leaves it then, the safe side.
    nonisolated static func playerActed(within seconds: TimeInterval = 1.5) -> Bool {
        [CGEventType.leftMouseDown, .rightMouseDown, .flagsChanged]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity <= seconds
    }

    /// How long after the curtain sinks the game's front is still watched.
    private static let focusGuard: TimeInterval = 8
    /// How often the curtain comes up again for one start: a game that can't be given the front
    /// doesn't get the curtain going up and down for ever.
    private static let maxRaisedAgain = 4
    /// How long the game has to keep the front before the curtain sinks a second time: a game
    /// building its window anew more than once made it come and go (Sonic Mania on 1.11.).
    nonisolated static let settleAgain: TimeInterval = 2.5

    /// Hands the front to the game: its program with windows (a Windows game's .exe under Wine, a
    /// Mac game's app). Since macOS 14 only the app in front can pass it on – asking from behind
    /// is ignored, and macOS gives the front to whatever app is next – so Nightforge comes to the
    /// front first when it isn't (under the curtain, or from its own page).
    ///
    /// `again`: its window is gone though it may be the active app, so an activation that does nothing
    /// won't do (GameStage). A Mac version gets what a click on the Dock sends; Wine brings a window
    /// back when it becomes active, so a Windows game loses the front to Nightforge for a moment. Not
    /// Launch Services for that: Steam's Wine and the game's are the same app to it.
    @discardableResult
    private func handFocus(to pids: Set<pid_t>, again: Bool = false) async -> Bool {
        guard let app = Self.gameApp(pids) else { return false }
        if app.isHidden { app.unhide() }  // Go to Nightforge hid it (leaveGame)
        if again, app.bundleIdentifier != Engine.gameBundleID, let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return app.isActive
        }
        if app.isActive, !again { return true }
        GameBackdrop.handingOver = again  // the page stays while Nightforge has the front for this
        defer { GameBackdrop.handingOver = false }
        if !NSApp.isActive {
            // Not through Launch Services for a plain handover: its activation can land after it and
            // take the front back from the game.
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<(again ? 6 : 20) where !NSApp.isActive { try? await Task.sleep(for: .milliseconds(50)) }
            if Self.fetchesFrontItself(again: again, active: NSApp.isActive) {
                // macOS ignores `activate` from behind while the app in front doesn't yield: Overwatch's
                // three fetches on 8.11. changed nothing (not one activation in wine.log), a click on the
                // Dock brought it back at once. The Dock sends a reopen event, which Wine answers like
                // becoming active (unminimizeWindowIfNoneVisible) – but such an event from Nightforge
                // would ask the player for Automation rights. So a real round: Nightforge in front
                // through Launch Services, awaited, and then the handover below makes the game active.
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                for _ in 0..<30 where !NSApp.isActive { try? await Task.sleep(for: .milliseconds(50)) }
                guard NSApp.isActive else {
                    GameLog.note("Fetching the game back: Nightforge didn't get the front to hand it over")
                    return app.isActive
                }
            }
        }
        InputRouter.hidePointerForGame()
        NSApp.yieldActivation(to: app)
        // All its windows: with only the key one, Wine's full-screen window stayed under others.
        app.activate(from: .current, options: [.activateAllWindows])
        for _ in 0..<20 where !app.isActive { try? await Task.sleep(for: .milliseconds(50)) }
        // Its coming forward brings the pointer back (Switch to Game, 1.11.), and that stays: taking
        // a game's keys to hide it costs its full screen (watchCurtain).
        return app.isActive
    }

    /// The app of the window over the game gets the front, when that's due (PadPointerRules.handsFront):
    /// while the game has it, the game keeps the mouse for itself. `touched`: a finger on the touchpad.
    func reachWindowOverGame(touched: Bool = true) {
        guard PadPointerRules.handsFront(over: overGame, gameFront: overGameFront, alreadyHanded: overGameHanded, touched: touched,
                                         overlay: GameOverlay.isOpen),
              let over = overGame, let app = NSRunningApplication(processIdentifier: over.owner)
        else { return }
        overGameHanded = over.number
        GameLog.note("Stage: \(app.localizedName ?? "another app")'s window stands over the game, it gets the front")
        Task {
            GameBackdrop.handingOver = true  // the page stays while Nightforge has the front for this
            defer { GameBackdrop.handingOver = false }
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
                for _ in 0..<6 where !NSApp.isActive { try? await Task.sleep(for: .milliseconds(50)) }
                if !NSApp.isActive {  // macOS ignores `activate` from behind (handFocus)
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                }
            }
            NSApp.yieldActivation(to: app)
            app.activate(from: .current, options: [.activateAllWindows])
        }
    }

    /// A game to be fetched back (`again`) needs a real change of the active app, and Nightforge's own
    /// `activate` didn't get it the front: it goes through Launch Services.
    nonisolated static func fetchesFrontItself(again: Bool, active: Bool) -> Bool { again && !active }

    /// The game's program with windows among its processes: a Windows game's .exe under Wine, a Mac game's app.
    private static func gameApp(_ pids: Set<pid_t>) -> NSRunningApplication? {
        pids.sorted().compactMap { NSRunningApplication(processIdentifier: $0) }.first { $0.activationPolicy == .regular }
    }

    /// Go to Nightforge in the overlay, the game running on behind it. Nightforge asks for the front
    /// – on 1.11. it never did: with the overlay's keys it counted as active already (comeForward).
    /// A game that keeps it is hidden, and macOS gives the front to the app before it: Nightforge,
    /// which handed it over. Should another app get it, the game shows again – never a third app in
    /// front of a hidden game. Switch to Game shows it again too (handFocus).
    private func leaveGame(_ pids: Set<pid_t>) async {
        curtainWatch?.cancel()
        stage.playerLeft()
        let window = NSApp.windows.first { $0.title == "Nightforge" }
        window?.orderFrontRegardless()
        NSApp.comeToFront()
        if await !Self.cameToFront(), let game = Self.gameApp(pids) {
            game.hide()
            if await !Self.cameToFront() { NSApp.comeToFront() }
            if await !Self.cameToFront() { game.unhide() }
            GameLog.note("Go to Nightforge: \(game.localizedName ?? "the game") kept the front, hidden – "
                         + "\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nobody") in front now")
        }
        window?.makeKeyAndOrderFront(nil)
        InputRouter.hidePointerSoon()
    }

    /// Nightforge in front within half a second.
    private static func cameToFront() async -> Bool {
        for _ in 0..<10 where !NSApp.isFrontmost { try? await Task.sleep(for: .milliseconds(50)) }
        return NSApp.isFrontmost
    }

    /// How long a running game may show nothing before the curtain asks.
    private static let curtainPatience: TimeInterval = 60

    private func askAboutStart(_ game: Game) {
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        let actions = GameOverlay.Actions(
            quit: {
                LaunchHealth.playerQuit(game.gameID)
                await Task.detached(priority: .userInitiated) {
                    GameProcesses.end(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
                }.value
            },
            nightforge: { [weak self] in
                self?.curtainWatch?.cancel()
                GameBackdrop.hide(after: .zero)
                let pids = await Task.detached(priority: .userInitiated) {
                    Set(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
                }.value
                await self?.leaveGame(pids)
            })
        GameOverlay.open(game.name, pids: [], pause: false, on: GameDisplay.gameScreen, symbols: padSymbols, step: .notStarting,
                         actions: actions)
    }

    /// Both sticks held in a game (InputRouter): the overlay over the game being played. The game
    /// is paused under it (OverlayStillness). Quit ends its processes, also when it hangs, and its end
    /// is then seen like any other (watchForGameEnd); Go to Nightforge leaves it running.
    func openOverlay() {
        guard !GameOverlay.isOpen,
              let game = allGames.first(where: { playing.contains($0.id) && running[$0.id] != nil })
                ?? allGames.first(where: { running[$0.id] != nil })
        else { return }
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        let stillness = OverlayRules.stillness(platform: game.platform, onlineOnly: game.onlineOnly)
        let pauses = stillness == .paused
        input.refreshBattery()  // otherwise read only while Nightforge is in front
        let runsOn = OverlayRules.runsOnIfSilent(platform: game.platform, onlineOnly: game.onlineOnly)
        // The one that runs on if our driver answers says what it does once that's known.
        let context = OverlayContext(stillness: runsOn ? nil : stillness, startedAt: running[game.id].flatMap(GameProcesses.started),
                                     pads: controllerStatuses, silencesPad: game.platform == .windows, runsOnIfSilent: runsOn)
        Task {
            let pids = await Task.detached(priority: .userInitiated) {
                GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table())
            }.value
            let actions = GameOverlay.Actions(
                quit: {
                    LaunchHealth.playerQuit(game.gameID)
                    // Looked up again: the game may have started more processes since.
                    await Task.detached(priority: .userInitiated) {
                        GameProcesses.end(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
                    }.value
                },
                nightforge: { [weak self] in await self?.leaveGame(Set(pids)) },
                restart: { [weak self] in
                    LaunchHealth.playerQuit(game.gameID)
                    self?.restartAfterEnd = game
                    await Task.detached(priority: .userInitiated) {
                        GameProcesses.end(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
                    }.value
                    await self?.startAgainWhenEnded(game)
                })
            GameOverlay.open(game.name, pids: pids, pause: pauses, on: GameDisplay.gameScreen, symbols: padSymbols,
                             soundStaysOn: game.platform == .windows ? GameAudio.gameStillOn : nil, context: context,
                             actions: actions)
        }
    }

    /// A controller came after a Windows game started without one. Only games known to look for pads
    /// at their start hear about it (Left 4 Dead 2, 7.11.): The Forest and Valheim took one at once on
    /// 8.11. and were offered a restart all the same. Said once for a few seconds over the game, then
    /// asked in the overlay.
    func padArrivedLate() {
        guard let game = allGames.first(where: { padlessStarts.contains($0.id) && running[$0.id] != nil }) else { return }
        padlessStarts.remove(game.id)
        let folder = game.installDir
        Task {
            guard await Task.detached(priority: .utility, operation: { Self.readsPadsOnlyAtStart(installDir: folder) }).value,
                  running[game.id] != nil
            else { return }
            GameOverlay.lateController = true
            GameLog.note("A controller came after \(game.name) started without one: hint shown, the overlay offers a restart")
            GameHint.show(title: L10n.t("Controller connected"),
                          detail: L10n.t("%@ may only find it after a restart – the overlay offers one.", game.name),
                          on: GameDisplay.gameScreen)
        }
    }

    /// Whether a game is known to look for controllers only when it starts: Valve's Source engine
    /// (bin/engine.dll, and gameinfo.txt in its folder or a folder of its content). From outside
    /// Nightforge can't see whether a game reads a pad, so everything else hears nothing.
    nonisolated static func readsPadsOnlyAtStart(installDir: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: installDir.appendingPathComponent("bin/engine.dll").path) else { return false }
        if manager.fileExists(atPath: installDir.appendingPathComponent("gameinfo.txt").path) { return true }
        let folders = (try? manager.contentsOfDirectory(at: installDir, includingPropertiesForKeys: nil)) ?? []
        return folders.contains { manager.fileExists(atPath: $0.appendingPathComponent("gameinfo.txt").path) }
    }

    /// "Restart Nightforge" (menu, Settings): Nightforge quits, the shutdown script ends Steam (both),
    /// the Wine session and its helpers at once, then opens Nightforge again – a clean start when
    /// something in the background hangs (the user, 8.11.). Not while a game runs: the overlay ends it first.
    func restartNightforge() {
        guard running.isEmpty else {
            errorMessage = L10n.t("Quit the game first, then restart Nightforge.")
            return
        }
        guard restartWait == nil else { return }  // counting down already
        let wait = Engine.cloudSaveWait(since: Engine.lastGameActivity)
        guard wait > 0 else { return restartNow() }
        // Right after a game: its cloud saves first, with Nightforge still there to say so. Gone already,
        // nothing would show for half a minute, and opening it again called the restart off (audit A11).
        restartWait = Task {
            defer { restartWait = nil }
            var left = Int(wait.rounded(.up))
            while left > 0 {
                Toasts.shared.show(L10n.t("Nightforge restarts in %ld s, once your game's cloud saves are through.", left))
                let step = min(left, 2)  // the message stays for 2.8 s
                try? await Task.sleep(for: .seconds(step))
                left -= step
            }
            guard running.isEmpty, launchingID == nil else {
                GameLog.note("Restart called off: a game started while it waited")
                return
            }
            restartNow()
        }
    }

    private func restartNow() {
        GameLog.note("Restart asked for: Steam, Wine and the helpers end, then Nightforge opens again")
        Engine.restarting = true
        if !Quit.now(by: "Restart Nightforge") { Engine.restarting = false }
    }

    /// The overlay's restart: `watchForGameEnd` starts the game again when it sees its end. Here only
    /// for a game it doesn't watch (not started from Nightforge), or one that doesn't end in 30 s.
    func startAgainWhenEnded(_ game: Game) async {
        for _ in 0..<60 where restartAfterEnd?.id == game.id && (playing.contains(game.id) || running[game.id] != nil) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard restartAfterEnd?.id == game.id else { return }
        restartAfterEnd = nil
        play(game)
    }

    /// The end just seen is that of the game "Restart Game" asked to start again.
    nonisolated static func endRestarts(_ restart: String, ended: Set<String>) -> Bool { ended.contains(restart) }

    /// Brings the running game's window to the front.
    func switchToGame(_ game: Game) {
        guard let entry = game.entries.first(where: { running[$0.id] != nil }) else { return }
        let marker = entry.platform == .mac ? nil : entry.windowsFolderMarker
        let folder = entry.platform == .mac ? entry.installDir.path : nil
        Task {
            let pids = await Task.detached(priority: .userInitiated) {
                Set(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
            }.value
            stage.again()
            await handFocus(to: pids, again: true)
        }
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

    /// A scan the caller waits for, one at a time like any other. Past `reload`, it ran beside a scan under way, and
    /// whichever ended first let a third begin.
    func scanInLine() async {
        while scanInFlight { try? await Task.sleep(for: .milliseconds(50)) }
        scanInFlight = true
        await rescan()
        while scanInFlight { try? await Task.sleep(for: .milliseconds(50)) }  // one asked for meanwhile
    }

    /// Reads every store's library from the Mac and shows what it found.
    private func rescan() async {
        antiCheatBlocks = await ProfileStore.shared.antiCheatBlocks()
        profiles = await ProfileStore.shared.knownProfiles()
        let sources = await AGWStore.shared.current()
        if sources != macSources { macSources = sources }
        var found: [Game] = []
        for store in stores {
            found += await store.library()
        }
        found = LibraryScanner.sorted(found)
        let wasDownloading = Set(allGames.filter { Self.isDownloading($0.install) }.map(\.id))
        let wasRefused = Set(allGames.filter(\.downloadRefused).map(\.id))
        allGames = withGameInfo(withStorePrices(found))
        lastScan = Date()
        downloadLooks = 0
        measureDownloads()
        libraryLoaded = true
        askAboutRosettaOnce()
        let finished = found.filter { $0.isInstalled && wasDownloading.contains($0.id) }
        for game in finished { prepare(game) }
        if !finished.isEmpty || !spaceLooked { refreshLowSpace() }
        applyFilter()
        MacIntegration.announceFinished(finished)
        let toFetch = found.flatMap(KeepAwake.downloads(of:))
        let fetched = KeepAwake.fetched(toFetch)
        KeepAwake.update(downloading: fetched)
        keptAwakeFor = (toFetch, !fetched.isEmpty)
        refreshDownloadStanding()
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
        fillGameInfo()
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
    /// How far each Mac download had got when Steam for Mac last got its turn.
    private var lastMacTurnProgress: [String: Double]?

    private func takeTurnsDownloading() {
        // Not while a game moves to another drive: that stops and starts its Steam itself.
        guard launchingID == nil, running.isEmpty, move == nil, Date().timeIntervalSince(lastSignInSwitch) > 120 else { return }
        let macDownload = allGames.contains { game in
            (game.platform == .mac && game.provider == .steam && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
        let windowsDownload = allGames.contains { SteamSwitch.usesWindowsSteam($0) && Self.isDownloading($0.install) }
        guard macDownload || windowsDownload else { return }
        // A Mac download that got nowhere in its last turn (Steam for Mac finds no download
        // servers, say) doesn't get another: Steam for Mac would come up and sign the Wine Steam out
        // every few minutes for nothing. Any progress lets it take turns again.
        // What the scan measured (it asks nettop off the main thread); asking again here would block the window.
        let macProgress = Dictionary(allGames.compactMap { game -> (String, Double)? in
            (Self.downloadFraction(game.macPending) ?? (game.platform == .mac && game.provider == .steam ? Self.downloadFraction(game.install) : nil))
                .map { (game.id, $0) }
        }, uniquingKeysWith: max)
        let turn = SteamSwitch.downloadTurn(SteamSwitch.DownloadFacts(
            macDownload: macDownload, windowsDownload: windowsDownload, macReady: macDownload && MacSteam.isReady,
            macSignedIn: macDownload && MacSteam.signedIn, windowsSignedIn: windowsDownload && Engine.steamSignedIn,
            macStalled: SteamSwitch.macDownloadsStalled(macProgress, since: lastMacTurnProgress),
            windowsRunning: windowsDownload && Engine.isSteamRunning, windowsReplaced: windowsDownload && Engine.sessionReplaced(),
            windowsStopped: steamSwitch.windowsStopped))
        if turn == .mac {
            lastSignInSwitch = Date()
            lastMacTurnProgress = macProgress
            steamSwitch.stopWindowsForMacDownload()
            Task {
                if MacSteam.isRunning { await MacSteam.quit() }
                MacSteam.start()
            }
        } else if turn == .windows {
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
    /// The downloads' looks since the last full scan.
    private var downloadLooks = 0
    /// Every this many looks the full scan: it alone sees a download Steam began by itself, or one
    /// Steam won't fetch (`downloadRefused`).
    private static let fullScanEvery = 10

    /// Adds this look's progress to each download's speed – at the time it was measured, which for
    /// a Steam download on the Windows side can be some seconds back (StagingSizes); a download that
    /// ended drops out.
    private func measureDownloads(now: Date = Date()) {
        var rates: [GameID: DownloadRate] = [:]
        for game in downloads where game.downloadNeedsSpace == nil {
            guard case .downloading(let fraction?) = game.install, game.sizeOnDisk > 0 else { continue }
            var rate = downloadRates[game.gameID] ?? DownloadRate()
            rate.add(bytes: fraction * Double(game.sizeOnDisk), at: LibraryScanner.stagingMeasured(game, now: now) ?? now)
            rates[game.gameID] = rate
        }
        if rates != downloadRates { downloadRates = rates }
    }

    func refreshDownloadStanding() {
        let listed = !downloads.isEmpty
        let displays = listed ? DownloadStanding.onlineDisplays() : (builtIn: false, external: false)
        let standing = DownloadStanding.of(listed: listed, fetching: keptAwakeFor.fetching, holding: KeepAwake.isHolding, downloads: keptAwakeFor.downloads,
                                           lidMatters: DownloadStanding.lidMatters(hasBattery: power.level != nil, builtInDisplay: displays.builtIn,
                                                                                   externalDisplay: displays.external, onBattery: power.onBattery))
        if standing != downloadStanding { downloadStanding = standing }
    }

    /// While Steam downloads something, a look every few seconds for progress.
    private func watchDownloads() {
        let downloading = allGames.contains { Self.isDownloading($0.install) || Self.isDownloading($0.macPending) }
        guard downloading, downloadWatcher == nil else { return }
        let pause = IdleRest.downloadLookPause(fetching: KeepAwake.isHolding, nobodyThere: IdleRest.nobodyThere(idle: InputRouter.secondsSinceUse))
        downloadWatcher = Task {
            try? await Task.sleep(for: .seconds(pause))
            downloadWatcher = nil
            await lookAtDownloads()
        }
    }

    /// Only the downloading games' manifests (LibraryScanner.downloadLook): every library and every
    /// download's files read again every 3 s cost more than the progress is worth (the UI power
    /// budget). Anything but progress – a download done or gone, its size worked out, out of room,
    /// a Mac version on its way, another store's – and every tenth look go to the full scan.
    private func lookAtDownloads() async {
        downloadLooks += 1
        let games = allGames.filter { Self.isDownloading($0.install) }
        guard downloadLooks < Self.fullScanEvery, !scanInFlight, !games.isEmpty, games.allSatisfy({ $0.provider == .steam }),
              !allGames.contains(where: { Self.isDownloading($0.macPending) })
        else { return reload(quiet: true) }
        let looks = await Task.detached(priority: .utility) { games.map(LibraryScanner.downloadLook) }.value
        // A full scan meanwhile has the newer word, and looks on after it.
        guard !scanInFlight else { return }
        var updated = allGames
        for (old, fresh) in zip(games, looks) {
            guard let index = updated.firstIndex(where: { $0.id == old.id }), updated[index] == old else { continue }
            guard let game = LibraryScanner.takeLook(old, fresh: fresh) else { return reload(quiet: true) }
            updated[index] = game
        }
        if updated != allGames {
            allGames = updated
            applyFilter()
        }
        measureDownloads()
        watchDownloads()
    }

    /// The engine built again from what the component list and the player's D3DMetal now say, queued
    /// behind a Steam start that may still be at it. False when it couldn't (offline, a broken download).
    func rebuildEngine(report: (@Sendable (Engine.SetupStep) -> Void)? = nil) async -> Bool {
        let previous = steamStartup
        let build = Task { () -> Bool in
            await previous?.value
            return (try? await Engine.ensureEngine(gameRunning: !running.isEmpty, report: report)) != nil
        }
        steamStartup = Task { _ = await build.value }
        return await withTaskCancellationHandler { await build.value } onCancel: { build.cancel() }
    }

    /// After a game test: the Steam its starts gave the HUD's frame log (Engine.setFrameLog) starts again
    /// without it, so the next game by Play has the environment it had before. Not left to Steam's signature:
    /// a Steam that a game's own start began has none noted.
    func endFrameLog() {
        guard Engine.setFrameLog(false), SetupModel.isComplete else { return }
        let previous = steamStartup
        steamStartup = Task {
            await previous?.value
            guard let wine = await Engine.installedWine(), !macSteamBusy, !gameUnderWay, Engine.isSteamRunning else { return }
            try? await Engine.restartSteamInBackground(wine)
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
            try? await Engine.ensureSteamRunning(wine, busy: gameUnderWay)
        }
    }

    /// Keeps Nightforge's own Steam running hidden once it's set up.
    /// The engine check and Steam (re)start at app launch; game launches wait for it so a pending
    /// Steam restart can't cut off a game that was just started.
    var steamStartup: Task<Void, Never>?
    /// Steam only when something needs it.
    var steamOnDemand = SteamOnDemand()
    /// What's due after the Mac woke, and the fetch of it that a start calls off.
    var wakeCatchUp = WakeCatchUp()
    var wakeFetch: Task<Void, Never>?

    func startBackgroundSteam() {
        // onAppear can fire more than once; one start per app run is enough.
        guard SetupModel.isComplete, steamStartup == nil else { return }
        Task { await ProfileStore.shared.refresh() }
        Task {
            await AGWStore.shared.refresh()
            let sources = await AGWStore.shared.current()
            if sources != macSources { macSources = sources }
        }
        steamStartup = Task {
            // Let the running-game check see the processes before deciding on a restart – or on
            // replacing the engine's files, which ends the Wine session a game would run in.
            while !runningScanned { try? await Task.sleep(for: .milliseconds(100)) }
            // A new engine that can't be fetched now (offline, broken download): Steam starts with
            // the one already installed, and the new one is tried again at the next start.
            var ensured = try? await Engine.ensureEngine(gameRunning: !running.isEmpty)
            if ensured == nil { ensured = await Engine.installedWine() }
            guard let wine = ensured else { return }
            // A session begun with the sandbox switch the other way ends here, off the main thread,
            // rather than at the first Wine start, which may come from it (WineSandbox, review N8).
            await WineSandbox.settleInBackground(wine)
            // Signing in would sign out the Steam for Mac a running Mac game uses; Play starts it later.
            guard !macSteamBusy else { return }
            // A Steam for Mac Nightforge left running – it quit after starting a Mac version and came
            // back when that ended – goes first (SteamSwitch): quit, it finishes its cloud sync;
            // signed out by the Windows Steam, it wouldn't.
            if MacSteam.startedByNightforge, MacSteam.isRunning, !steamFacts.macDownload { await MacSteam.quit() }
            try? await Engine.ensureSteamRunning(wine, busy: gameUnderWay)
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
            if !gameUnderWay, !downloading, !launchNeedsConfirmation,
               !(await Engine.offMain { Engine.windowsGameRunning }) {
                _ = await restartStuckSteam(wine, freshSession: true)
                return
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// A Steam woken by SteamOnDemand is watched like one started with Nightforge.
    func watchWokenSteam(_ wine: URL) { Task { await watchSteamStart(wine) } }

    /// Steam hangs now and then while starting under Wine (see Engine.steamLooksStuck), and one
    /// restart fixes it. Watched for the first two minutes, ideally before anyone presses Play.
    /// A start that didn't come up counts against its engine (steamStartFailed).
    private func watchSteamStart(_ wine: URL) async {
        let began = Date()
        for _ in 0..<24 {
            try? await Task.sleep(for: .seconds(5))
            if Engine.steamSignedIn {
                await steamCameUp(since: began)
                return
            }
            if Engine.steamHadTimeToHang(began: began, quietFor: 45), !gameUnderWay, Engine.steamLooksStuck(quietFor: 45),
               !(await Engine.offMain { Engine.windowsGameRunning }) {
                _ = await steamStartFailed(since: began)
                _ = await restartStuckSteam(wine)
                return
            }
        }
    }

    /// The Steam Nightforge started since `began` came up: its engine is one Steam runs on (EngineRollback).
    private func steamCameUp(since began: Date) async {
        guard let start = Engine.lastSteamStart, start.at >= began.addingTimeInterval(-60),
              let build = await Engine.offMain({ EngineRollback.shared.build(running: start.wine) })
        else { return }
        EngineRollback.shared.recordSteamStarted(build)
    }

    /// The Steam Nightforge started since `began` hasn't come up. Judged (SteamStartCheck) – an
    /// update or a slow start isn't counted – and counted against its engine: the second time on
    /// a new engine, Steam and its games go back to the previous one (EngineRollback). True then.
    private func steamStartFailed(since began: Date) async -> Bool {
        guard let start = Engine.lastSteamStart, start.at >= began.addingTimeInterval(-60) else { return false }
        let (outcome, build) = await Engine.offMain {
            (SteamStartCheck.judge(SteamStartCheck.signs(steamRoot: Engine.steamRoot, start: start.at, running: Engine.steamRunningKnown)),
             EngineRollback.shared.build(running: start.wine))
        }
        guard outcome == .failed, let build else { return false }
        switch EngineRollback.shared.afterFailedSteamStart(build) {
        case .rollBack(let held):
            GameLog.note("Steam didn't come up on engine \(build.engineVersion) twice: it starts with the previous one from \(EngineRollback.day(held.setUp))")
            return true
        case .heldFailed:
            GameLog.note("Steam didn't come up on the previous engine either: back to the newest")
        case .none:
            GameLog.note("Steam didn't come up on engine \(build.engineVersion)")
        }
        return false
    }

    // MARK: - Steam's patience (F3)

    enum SteamSignInStep: Equatable { case signedIn, wait, stuck }

    /// How long a Windows Steam may take to sign in before a start. A new Mac's Rosetta translates all of it at its
    /// first starts: the user's MacBook Pro took 40–45 s to "Logged On" (21.11.2026), and the 45 s here restarted a
    /// Steam that had just got there – which then took as long again.
    nonisolated static let steamSignInPatience: TimeInterval = 120
    /// Nothing in its logs for this long: it doesn't come along.
    nonisolated static let steamQuietPatience: TimeInterval = 45
    /// No Steam process for this long after the wait began: none is coming.
    nonisolated static let steamGonePatience: TimeInterval = 10

    /// The wait for a Steam that signs in: on while it comes along – its process there, something in its logs
    /// lately – up to two minutes; stuck without a process, with its logs quiet, or after that.
    nonisolated static func steamSignInStep(signedIn: Bool, running: Bool, waited: TimeInterval, quietFor: TimeInterval) -> SteamSignInStep {
        if signedIn { return .signedIn }
        if waited >= steamSignInPatience { return .stuck }
        if !running, waited >= steamGonePatience { return .stuck }
        if waited >= steamQuietPatience, quietFor >= steamQuietPatience { return .stuck }
        return .wait
    }

    /// One Steam restart for a start: the game's settings that come with Steam's environment (only while no Windows
    /// game runs in it), or a Steam stuck signing in – both at once in one.
    nonisolated static func restartsSteamForStart(environmentChanged: Bool, stuck: Bool, running: Bool, gamesRunning: Bool) -> Bool {
        stuck || (environmentChanged && running && !gamesRunning)
    }

    /// Nightforge's own work that explains a wait with no process of the game's yet: "Stuck?" counts from its end. Not an
    /// update, which has its own way out, nor Epic's and GOG's saves, which B stops at once (CurtainEscape).
    nonisolated static func phaseExplainsWait(_ phase: LaunchPhase?) -> Bool {
        switch phase {
        case .startingSteam?, .startingSteamForMac?, .signingIn?, .savingToCloud?, .settingUp?, .settingUpDotNet?, .restartingSteam?,
             .steamNotResponding?, .signingInEpic?, .settingUpWindowsParts?, .startingBattleNet?:
            return true
        default:
            return false
        }
    }

    /// Restarts a hung Steam, queued like any other Steam start so a launch waits for it.
    /// True once it has signed in again (up to 90 s). It signs in by itself; when it asks instead
    /// (its remembered sign-in ran out) while a game waits to start, its window comes to the front
    /// and the player gets ten minutes for it. `freshSession`: with a new Wine session (DockHider).
    /// `hung`: it stopped taking commands, so it's ended with its Wine session (no game may run).
    /// Not up again because of its engine (steamStartFailed), it starts once more on the previous
    /// one when nothing waits on it; a start under way gets the previous engine with its next try.
    private func restartStuckSteam(_ wine: URL, freshSession: Bool = false, hung: Bool = false, again: Bool = true) async -> Bool {
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
            if Engine.steamSignedIn {
                await steamCameUp(since: began)
                return true
            }
            if !asked, launchingID != nil, SteamLogin.waitingForCredentials(steamRoot: Engine.steamRoot, since: began) {
                asked = true
                launchPhase = .signInAgain
                showSteamWindow()
            }
            if second >= 90 && !asked {
                if await steamStartFailed(since: began), again, launchingID == nil, running.isEmpty {
                    return await restartStuckSteam(wine, again: false)
                }
                return false
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return false }
        }
        return false
    }

    /// The big button: play when installed, otherwise ask Steam to download it.
    func primaryAction() {
        guard let game = selected, uninstallingID != game.id else { return }
        if launchingID == game.id {
            if game.provider == .battlenet {
                if launchPhase == .battleNetAsks || launchPhase == .signInInBattleNetWindow { BattleNetClient.show() }
            } else if launchNeedsConfirmation && game.platform == .mac {
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
        // What anti-cheat stops does nothing here (the button says why); a game that doesn't start yet has `tryAnyway`.
        case .installed where game.antiCheatBlock != nil: break
        case .installed: launchSelected()
        case .notInstalled where game.isVROnly || game.antiCheatBlock != nil: break
        case .notInstalled: downloadIfRoom(game)
        case .downloading: if game.downloadNeedsSpace != nil { resumeDownload(game) }
        case .inStore where game.storeFree: pendingDemoLicense = freeEntry(game)
        case .inStore: openStorePage(game)
        }
    }

    /// "Download Anyway" / "Play Anyway": a game that doesn't start on a Mac yet isn't ruled out – it
    /// may work for this player – so it stays possible, only not as the big button. Room and the
    /// drive are asked as for any download.
    func tryAnyway() {
        guard let game = selected, game.antiCheatBlock?.notYet != nil, !isRunning(game),
              uninstallingID != game.id, launchingID != game.id, !waitsForMove(game), game.missingDrive == nil else { return }
        switch game.install {
        case .installed: launchSelected()
        case .notInstalled: downloadIfRoom(game)
        case .downloading, .inStore: break
        }
    }

    /// A free game from the store, added through the Steam it'll run in: Steam for Mac for a Mac
    /// version once that's signed in, else Nightforge's own.
    private func freeEntry(_ game: Game) -> Game {
        var game = game
        if game.macNative && MacSteam.signedIn { game.platform = .mac }
        return game
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

    /// Buying happens on the store's own page in the browser; Nightforge never sees payment data.
    /// Once the store has the new licence, the game shows up in the library with its Download button.
    func openStorePage(_ game: Game) {
        guard let url = game.storePageURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// A search, not among the hidden games: Epic's store is one link away.
    var offersEpicSearch: Bool { !showingHidden && searchTerm.count >= 2 }

    /// Epic's own search in the player's browser, for what's in the search field.
    func openEpicSearch() {
        guard let url = StoreHits.epicSearch(searchTerm) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Steam adds a demo's or free game's licence when it's asked to install it (steam://install), in
    /// its own install window: once the player has confirmed there, Steam writes its manifest and
    /// downloads it, and the library shows that like any download.
    func addDemoLicense(_ game: Game) {
        pendingDemoLicense = nil
        Task {
            do {
                if try await steam.addDemoLicense(game) { reload(quiet: true) }
            } catch {
                errorMessage = RosettaSupport.playerText(error)
            }
        }
    }

    /// Asks GitHub again. No answer keeps what it knew: an offline Mac says "none" as well.
    func lookForAppUpdate() async {
        if let update = await Updater.check() { availableUpdate = update }
    }

    func installUpdate() {
        guard let update = availableUpdate, !updating else { return }
        // Not under a game or a move (Updater.Hold): said, as "Restart Nightforge" says it.
        if let hold = Updater.hold(gameUnderWay: gameUnderWay, moving: move != nil) {
            errorMessage = hold.message
            return
        }
        updating = true
        Task {
            do {
                try await Updater.install(update)  // quits and restarts Nightforge when done
            } catch {
                updating = false
                if case Updater.Failure.notWritable = error { NSWorkspace.shared.open(update.page) }
                errorMessage = RosettaSupport.playerText(error)
            }
        }
    }

    // MARK: - Store search

    private var searchTerm: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Waits for a pause in typing, then asks every store at once; each one's hits show as they
    /// come, and until they do those of the last search stay, so nothing blinks while typing on.
    private func searchStore() {
        storeSearch?.cancel()
        storeCovers?.cancel()
        let term = searchTerm
        guard term.count >= 2 else {
            storeFound = [:]
            storeInfos = [:]
            if !storeResults.isEmpty { storeResults = []; applyFilter() }
            return
        }
        let searches: [StoreHits.Query] = stores.map { store in (store.provider, { await store.search(term) }) }
        storeSearch = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await StoreHits.gather(searches) { provider, hits in
                guard !Task.isCancelled, term == searchTerm, storeFound[provider] ?? [] != hits else { return }
                storeFound[provider] = hits
                showStoreHits()
                if provider == .steam { askCovers(of: hits) }
            }
        }
    }

    /// Steam's covers: newer games keep them only at addresses its store-browse API names.
    private func askCovers(of hits: [StoreHit]) {
        let appIDs = hits.compactMap(\.gameID.steamAppID)
        storeCovers = Task {
            let infos = await GameInfoStore.shared.storeInfos(appIDs)
            guard !Task.isCancelled, !infos.isEmpty else { return }
            storeInfos.merge(infos) { _, new in new }
            showStoreHits()
        }
    }

    private func showStoreHits() {
        let found = storeFound.mapValues { hits in
            hits.map { StoreHits.game($0, info: $0.gameID.steamAppID.flatMap { storeInfos[$0] }, blocks: antiCheatBlocks) }
        }
        storeResults = StoreHits.cards(found, term: searchTerm)
        applyFilter()
    }

    /// Games whose anti-cheat stops them on a Mac, so the store search can say so before buying.
    private var antiCheatBlocks: [Int: AntiCheatBlock] = [:]

    /// Hits from the games-only search can lack price and platforms; fetch them once it's selected.
    private var storeDetailsRequested: Set<Int> = []
    /// Prices of the library's store entries, once looked up; every scan brings them back.
    private var storePrices: [Int: String] = [:]
    /// … and which of them are free.
    private var freeInStore: Set<Int> = []

    // MARK: - What each game is

    /// Each store's entry with what GameInfoStore knows: an Epic or GOG game's twin on Steam, its
    /// controller support and ways to play; a Steam game's art at the addresses newer games need.
    private func withGameInfo(_ games: [Game]) -> [Game] {
        let known = gameInfo
        return games.map { game in
            var game = game
            if game.provider != .steam, game.steamTwin == nil { game.steamTwin = known.twins[game.gameID.key]?.appID }
            guard let info = GameInfoStore.info(for: game, in: known) else { return game }
            if game.provider != .steam {
                if let controller = info.controller {
                    game.controller = controller
                    game.controllerKnown = true
                }
                game.playModes = info.modes
            } else {
                if game.playModes.isEmpty { game.playModes = info.modes }
                if game.art == nil, info.cover != nil || info.hero != nil { game.art = StoreArt(info) }
            }
            return game
        }
    }

    /// Asks for what isn't known yet about the library (after a scan, in the background); the
    /// filters, controller support and covers follow each step as it comes.
    private func fillGameInfo() {
        let entries = allGames
        Task { [weak self] in
            await GameInfoStore.shared.fill(entries) { known in self?.takeGameInfo(known) }
        }
    }

    /// What its store or the same game on Steam says about a game (its page).
    func info(for game: Game) -> GameInfo? {
        GameInfoStore.info(for: game, in: gameInfo)
    }

    /// A game's page opens: Steam's info for it now, when the fill hasn't come to it yet (a store
    /// hit, a game just added) or it's a month old.
    func askInfo(for game: Game) async {
        guard let known = await GameInfoStore.shared.ask(game) else { return }
        takeGameInfo(known)
    }

    private func takeGameInfo(_ known: GameInfoStore.Known) {
        guard known != gameInfo else { return }
        gameInfo = known
        allGames = withGameInfo(allGames)
        applyFilter()
    }

    private func withStorePrices(_ games: [Game]) -> [Game] {
        guard !storePrices.isEmpty else { return games }
        return games.map { game in
            var game = game
            if game.install == .inStore, let price = storePrices[game.appID] {
                game.storePrice = price
                game.storeFree = freeInStore.contains(game.appID)
            }
            return game
        }
    }

    private func loadStoreDetailsIfNeeded() {
        guard let game = selected, game.provider == .steam, game.install == .inStore, game.storePrice == nil,
              storeDetailsRequested.insert(game.appID).inserted  // once: some games have no price at all
        else { return }
        Task {
            guard let hit = await StoreSearch.shared.details(for: game.appID) else { return }
            // Also for the library's store entries: games Steam knows that the account doesn't own.
            storePrices[game.appID] = hit.price
            if hit.free { freeInStore.insert(game.appID) }
            allGames = withStorePrices(allGames)
            guard let index = storeFound[.steam]?.firstIndex(where: { $0.gameID == game.gameID }) else {
                applyFilter()
                return
            }
            var updated = StoreHit(hit)
            updated.metascore = hit.metascore ?? storeFound[.steam]?[index].metascore
            storeFound[.steam]?[index] = updated
            showStoreHits()
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
        // Windows Steam downloads it, and Windows Steam is x86_64 (Epic's and GOG's downloaders aren't).
        if game.provider == .steam, !rosettaReady(for: "the download of \(game.name)", then: { [weak self] in self?.download(game, drive: drive) }) {
            return
        }
        Task {
            do {
                var context = StoreContext(busy: !running.isEmpty || launchingID != nil) { self.reload(quiet: true) }
                context.drive = drive
                try await store(for: game).install(game, context: context)
            } catch {
                errorMessage = RosettaSupport.playerText(error)
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
        case .steam, .battlenet: return nil
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
        // What the other downloads on this volume still need counts as taken, and the Mac's own disk keeps more over.
        let committed = SpaceCheck.committed(by: allGames, except: game) { SpaceCheck.sameVolume($0.installDir, folder) }
        let margin = SpaceCheck.margin(for: folder)
        guard let shortfall = SpaceCheck.shortfall(needed: needed, free: free, committed: committed, margin: margin) else {
            // It fits; on the Mac with little to spare after all downloads, the player hears that first.
            let kept = SpaceCheck.kept(needed: needed, free: free, committed: committed)
            let tight = needed > 0 && SpaceCheck.isMacDisk(folder) && SpaceCheck.isTight(kept: kept)
            let request = SpaceRequest(game: game, needed: needed, free: free, shortfall: 0, candidates: [], drives: drives,
                                       committed: committed, margin: margin, kept: tight ? kept : nil)
            // A drive the player has put games on before: where this one goes is theirs to say.
            if request.asksWhere || tight {
                pendingSpace = request
            } else {
                download(game)
            }
            return
        }
        let removable = allGames.filter { canUninstall($0) && !isRunning($0) && SpaceCheck.sameVolume($0.installDir, folder) }
        pendingSpace = SpaceRequest(game: game, needed: needed, free: free, shortfall: shortfall,
                                    candidates: SpaceCheck.candidates(removable, except: game), drives: drives,
                                    committed: committed, margin: margin)
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
            if SpaceCheck.shortfall(needed: request.needed, free: free, committed: request.committed, margin: request.margin) == nil {
                download(request.game)
            } else {
                errorMessage = L10n.t("There's still not enough space: %@ needs %@, your Mac has %@ free.",
                                      request.game.name, Format.bytes(request.required), Format.bytes(free))
            }
        }
    }

    /// A download Steam stopped for lack of disk space: once there's room, unpause it in Steam's
    /// manifest and restart that Steam, which then carries on – by itself it never tries again.
    func resumeDownload(_ game: Game) {
        guard let needed = game.downloadNeedsSpace else { return }
        // The nearest folder there is: a library's first download may have no steamapps/common yet, and that isn't "0 free".
        let free = Self.freeSpace(at: SpaceCheck.existingFolder(for: game.installDir))
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
                if !gameUnderWay {
                    try? await Engine.restartSteamInBackground(wine)
                } else {
                    steam.restartWhenIdle = true
                }
            }
            reload(quiet: true)
        }
    }

    private var spaceLooked = false

    /// Looks at the room on the Mac and on the drives plugged in that hold games, and sets `lowSpace`.
    func refreshLowSpace() {
        spaceLooked = true
        var places: [SpaceCheck.Place] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        if allGames.contains(where: { ($0.isInstalled || Self.isDownloading($0.install)) && SpaceCheck.isMacDisk($0.installDir) }) {
            places.append(SpaceCheck.Place(name: "Mac", free: Self.freeSpace(at: home),
                                           floor: SpaceCheck.macReserve, isMac: true))
        }
        for drive in ExternalDrive.connected() where drive.hasLibrary {
            places.append(SpaceCheck.Place(name: drive.name, free: drive.free, floor: SpaceCheck.margin, isMac: false))
        }
        let low = SpaceCheck.lowest(in: places)
        if low != lowSpace { lowSpace = low }
    }

    /// The note's button: Settings › Storage, where games move to a drive or go.
    func makeRoom() {
        openSettings(tab: .storage)
    }

    /// The tight-room sheet's "Download Anyway".
    func downloadTight(_ request: SpaceRequest) {
        pendingSpace = nil
        download(request.game)
    }

    /// The tight-room sheet's "Make Room …": Settings › Storage, once the sheet is gone.
    func makeRoomInstead() {
        pendingSpace = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))  // one sheet closes before the next opens
            makeRoom()
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

    /// Every sheet over the library closed through its state, as with Cancel or Close – before a quit
    /// (Quit): SwiftUI holds a sheet by these, and one AppKit ended came back (3.11.). A question
    /// waiting for its answer hears no; Settings' own sheets go with Settings.
    func closeAllSheets() {
        showingOptions = false
        showingSettings = false
        pendingSpace = nil
        pendingMove = nil
        managedLauncher = nil
        if macSetup != nil { closeMacSetup() }
        errorMessage = nil
        rosettaQuestion = nil
        sessionSummary = nil
        failedLaunch = nil
        if saveChoice != nil { answerSaveChoice(takeNewer: false) }
        pendingDemoLicense = nil
        d3dMetalDialog = nil  // its onDismiss calls the setup off
        pendingCloudGame = nil
        pendingUninstall = nil
        pendingLeftoverRemoval = nil
        // Two it didn't know (14.11.): either one up, and no quit got past it.
        pendingPower = nil
        offersFullScreen = false
    }

    /// The sheets over the library that are up, each by the state that holds it: what wine.log names when
    /// a quit waits for one (SwiftUI's sheet windows all go by one name). Every `.sheet` of LibraryView is
    /// here and in `closeAllSheets` (tests/ExperienceAuditTest reads the three against each other).
    var openSheets: [String] {
        [("showingOptions", showingOptions), ("showingSettings", showingSettings), ("pendingSpace", pendingSpace != nil),
         ("pendingMove", pendingMove != nil), ("managedLauncher", managedLauncher != nil), ("macSetup", macSetup != nil),
         ("errorMessage", errorMessage != nil), ("rosettaQuestion", rosettaQuestion != nil), ("sessionSummary", sessionSummary != nil), ("failedLaunch", failedLaunch != nil),
         ("saveChoice", saveChoice != nil), ("pendingDemoLicense", pendingDemoLicense != nil), ("d3dMetalDialog", d3dMetalDialog != nil),
         ("pendingCloudGame", pendingCloudGame != nil), ("pendingUninstall", pendingUninstall != nil),
         ("pendingLeftoverRemoval", pendingLeftoverRemoval != nil), ("pendingPower", pendingPower != nil),
         ("offersFullScreen", offersFullScreen)].filter(\.1).map(\.0)
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
                errorMessage = RosettaSupport.playerText(error)
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
        let number = beginLaunch(game)
        let behavior = Prefs.afterLaunch
        let arguments = GameOptionsStore.load(game.gameID).extraArgs.trimmingCharacters(in: .whitespaces)
        launchTask = Task {
            var gameStarted = false
            defer {
                endLaunch(number)
                // No game came of it (failed, called off, the player went back): nothing's end will hand the account back.
                if !gameStarted, !macSteamBusy { steamSwitch.macGivesAccountBack() }
            }
            // The curtain at once: the Steams changing over took 9–27 s behind Nightforge's page, with
            // Steam's windows coming up (8.11.). It says what's happening, and goes for what the player
            // has to answer (`steamAsks`).
            raiseCurtain(for: game)
            await leftStartEnded()
            if Task.isCancelled { return }
            // The Windows Steam goes (one sign-in per account on a Mac), once its last game's save is up.
            await steamSwitch.makeWayForMac(facts: steamFacts, phase: { self.launchPhase = $0 })
            if Task.isCancelled { return }  // the player went back: no Steam for Mac started for it
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
            } else if !(MacSteam.signedIn && MacSteam.startupFinished) {
                launchPhase = .startingSteamForMac  // up and still starting: no wait without a word
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
            await waitForSteamCloud(MacSteam.root)
            if Task.isCancelled { return }  // no saves taken along for a start that's over
            await takeSavesAlong(game, to: .mac)
            let installDir = game.installDir  // the library it's really in, an external drive's included
            let appID = game.appID
            let (macLaunch, screen) = await Task.detached(priority: .userInitiated) { () -> ([SteamCatalog.LaunchEntry], MacUnityScreen.Decision) in
                ControllerCompatibility.prepare(installDir: installDir)
                MacGameHUD.prepare(folder: installDir)
                return (SteamCatalog.macLaunchEntries(appID: appID, steamRoot: MacSteam.root),
                        MacUnityScreen.look(installDir: installDir, playerArguments: arguments))
            }.value
            let launchType = SteamProgram.macLaunchType(macLaunch)
            // A Unity Mac version's first start in full screen (MacUnityScreen), where steam://run carries the switch:
            // not with several launch options, which go by steam://launch without arguments.
            let carries = launchType == nil || !arguments.isEmpty
            if let note = MacUnityScreen.note(screen, game: game.name) {
                GameLog.note(carries ? note : "Mac version of \(game.name): several launch options, Steam's own way – no switch")
            }
            let withScreen = carries ? MacUnityScreen.arguments(arguments, screen) : arguments
            // steam://run/<id>//<arguments>: the extra part goes to the game.
            let extra = withScreen.isEmpty ? ""
                : "//" + (withScreen.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
            let watcher = LaunchWatcher(steamRoot: MacSteam.root, appID: game.appID)
            let launchStarted = Date()
            // With several launch options Steam asks which one, in a window that didn't come forward
            // (Drawful 2: standalone or the Jackbox Megapicker, 8.11.). steam://launch starts Steam's
            // first straight away; it passes no arguments, so with the player's own Steam asks as before.
            let command = launchType.flatMap { withScreen.isEmpty ? "launch/\(appID)/\($0)" : nil } ?? "run/\(appID)" + extra
            // Options steam://launch has no name for ("none", no type), or the player's own arguments:
            // -applaunch starts the first and takes arguments, with no question. Tried once; a resend
            // (Steam didn't note it) goes the old way, where Steam may ask.
            var handOver = SteamProgram.macNeedsApplaunch(macLaunch, hasArguments: !arguments.isEmpty)
            let run = {
                if handOver {
                    handOver = false
                    if MacSteam.applaunch(appID, arguments: Launcher.splitArguments(arguments)) { return }
                }
                MacSteam.open(command)
            }
            if Task.isCancelled { return }  // the player went back while the saves came along
            raiseCurtain(for: game)
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
                gameStarted = true
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
                // A picture before its end: it started (LaunchHealth.earlyEnd), no Windows version for it.
                // Called off by a new start: nothing else starts either.
                // Without a process list nothing is known of it: no confirmation, no crash report held against it.
                let first = await survivesFirstSeconds(game)
                if first == .survived || LaunchHealth.showedPicture(game.gameID, since: launchStarted) {
                    MacHealth.confirm(game.appID)
                } else if first == .ended, !Task.isCancelled, !LaunchHealth.quitByPlayer(game.gameID, since: launchStarted),
                          !LaunchHealth.endedAtOwnQuestion(game.gameID, since: launchStarted),
                          let program, Self.crashed(program, since: launchStarted), fallBackToWindows(game) {
                    return
                }
            }
            if !Task.isCancelled { stepBack(behind: game, behavior) }  // a new start has the curtain
        }
    }

    /// A Steam that has only just started finishes its own first cloud sync before it gets a game
    /// (`SteamCloudStart`). Steam then decides for itself as ever; nothing of its cloud is skipped.
    private func waitForSteamCloud(_ root: URL) async {
        var waiting = false
        defer { if waiting { launchPhase = nil } }
        for _ in 0..<35 {
            guard !Task.isCancelled,
                  await Task.detached(priority: .utility, operation: { SteamCloudStart.shouldWait(steamRoot: root) }).value
            else { return }
            if !waiting {
                waiting = true
                launchPhase = .signingIn
                GameLog.note("Steam Cloud: Steam finishes its first sync before the game starts, at \(GameLog.clock())")
            }
            try? await Task.sleep(for: .seconds(1))
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
            } catch let error as SaveTransfer.PartlyTaken {
                hintDuringStart(L10n.t("The newer save was copied over only in part (%@). The saves from before are in %@.",
                                       error.reason, error.backup.path))
            } catch {
                hintDuringStart(L10n.t("The newer save couldn't be copied over (%@). %@ starts with its own.", RosettaSupport.playerText(error), game.name))
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
            await scanInLine()  // after the Mac launch has wound down: one launch at a time
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
        launchAsksLicence = false
        launchQuestionTask = nil
        defer { if launchPhase == .licenceAnswered { launchPhase = nil } }
        let folders = Self.processFolders([game])
        var quietSeconds = 0
        var seconds = 0
        var askingSince: Int?
        var shownAt: Int?
        var onPlayerSeconds = 0
        var handledRejections = 0
        var resent = 0
        awaitingSteam = true
        defer { awaitingSteam = false }
        while Self.followsSteam(quietSeconds: quietSeconds, seconds: seconds, onPlayerSeconds: onPlayerSeconds) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return .cancelled }
            seconds += 1
            if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil {
                launchNeedsConfirmation = false
                return .processSeen
            }
            if askingSince != nil {
                onPlayerSeconds += 1
                if seconds % Self.steamLookEvery == 0, !MacSteam.isRunning {
                    steamQuestionOver(yes: false)
                    askingSince = nil
                    shownAt = nil
                    GameLog.note("Steam for Mac ended while it asked about \(game.name), at \(GameLog.clock())")
                }
            }
            let event = watcher.poll()
            if watcher.rejectedCommands > handledRejections && resent < 5 {
                handledRejections = watcher.rejectedCommands
                resent += 1
                try? await Task.sleep(for: .seconds(2))
                guard Self.asksAgain(cancelled: Task.isCancelled, send: send) else { return .cancelled }
                quietSeconds = 0
                continue
            }
            if !watcher.steamReceivedLaunch && seconds % 15 == 0 && resent < 5 {
                resent += 1
                guard Self.asksAgain(cancelled: Task.isCancelled, send: send) else { return .cancelled }
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
                launchQuestionTask = watcher.questionTask
            case .licence?:
                askingSince = askingSince ?? seconds
                quietSeconds = 0
                launchAsksLicence = true
                if !launchNeedsConfirmation {
                    launchNeedsConfirmation = true
                    MacSteam.show()
                }
            case .continued?:
                steamQuestionOver(yes: watcher.licenceContinued)
                askingSince = nil
                shownAt = nil
                quietSeconds = 0
            case .cancelled?:
                return .cancelled
            case .failed?:
                return .failed
            case nil:
                if let since = askingSince {
                    switch Self.steamQuestionStep(waited: seconds - since, shownFor: shownAt.map { seconds - $0 }) {
                    case .showWindow:
                        shownAt = seconds
                        MacSteam.show()
                    case .askPlayer where !launchNeedsConfirmation:
                        launchNeedsConfirmation = true
                        MacSteam.show()
                    default:
                        break
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
        // Hidden games only show where they're brought back from; the filters only in the library,
        // and not during a search: it finds every game, whatever the filters leave out.
        var shelf = cards.filter { isHidden($0) == showingHidden }
        if route.level == .library {
            if words.isEmpty { shelf = shelf.filter { filters.admits($0, laterGames: laterGames) { compatibility(of: $0).level } } }
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
            // Store hits are games you don't own – in any store: not Overcooked! 2 on Steam when it's
            // in your Epic library. A hit you do own leads to your game, whatever the library calls it.
            let hits = (showingHidden ? [] : storeResults).map { (hit: $0, yours: ownedIndex.game(of: $0)) }
            let yours = Set(hits.compactMap(\.yours))
            let listed = Set(ranked.map(\.0.id))
            let reached = yours.isEmpty ? [] : shelf.filter { !listed.contains($0.id) && $0.gameIDs.contains(where: yours.contains) }
            games = (0...2).flatMap { rank in ranked.filter { $0.1 == rank }.map(\.0) } + reached
                + hits.filter { $0.yours == nil }.map(\.hit)
        }
        let first = route.level == .library ? gridLayout.order.first ?? 0 : 0
        selectedIndex = selectBestMatch && !words.isEmpty ? first : games.firstIndex(where: { $0.holds(previous) }) ?? first
        if words.isEmpty && !showingHidden {
            let shown = games
            let stage = HomeRail.stage(shown, pinned: pinnedGames, off: offHome, sources: homeSources, pinOrder: pinOrder,
                                       later: laterGames) { StarterPicks.order(shown, facts: starterFacts) }
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
        if quickMenu != nil, quickMenuGame == nil { closeQuickMenu() }  // its game is gone
        storeChanged()  // the launchers' game counts; this runs at every key of a search too
    }

    /// The search lives in the library's header: from Home or a game's page it opens the library.
    func focusSearch() {
        guard !allGames.isEmpty else { return }
        if route != .library { goLibrary() }
        searchFocusPending = true
        searchFocusRequest += 1
    }

    /// A controller at the MacBook: the full screen is offered, once per start (FullScreenOffer).
    private func offerFullScreenIfDue() {
        guard let window = NSApp.windows.first(where: { $0.title == "Nightforge" }) else { return }
        let open = window.attachedSheet != nil || NSApp.modalWindow != nil || launcherMenuOpen || quickMenu != nil || padKeyboard != nil
        guard FullScreenOffer.offers(alreadyOffered: fullScreenOffered, padConnected: controllerConnected, inFront: NSApp.isActive,
                                     fullScreen: FullScreen.isOn, onBuiltInScreen: window.screen.map(GameDisplay.isBuiltIn) ?? false,
                                     firstStart: showsFirstStart, gameOn: gameOnScreen, somethingOpen: open) else { return }
        fullScreenOffered = true
        offersFullScreen = true
    }

    func askForHomeButton() { input.askForHomeButton() }

    func acceptFullScreen() {
        offersFullScreen = false
        FullScreen.toggle()
    }

    /// A or B on a Windows game's question: the helper presses the button in it.
    func answerQuestion(_ choice: PadAnswer.Choice) {
        guard windowsQuestion != nil else { return }
        Task {
            // The engine Steam runs on: the helper has to join the game's Wine session.
            var engine = Engine.lastSteamStart?.wine
            if engine == nil { engine = await Engine.installedWine() }
            guard let wine = engine else { return }
            padAnswered = Date()
            PadAnswerRun.send(choice, wine: wine) { status in
                GameLog.note("The pad answered a game's question (\(choice.rawValue)): exit \(status)")
                guard PadAnswer.needsPointer(exit: status) else { return }
                Task { @MainActor in
                    GameHint.show(title: L10n.t("This question needs the pointer"),
                                  detail: L10n.t("Use the touchpad as a mouse, or the right stick and R2."), on: GameDisplay.gameScreen)
                }
            }
        }
    }

    /// The keyboard for the controller, over the library: the hits show above it.
    func openPadKeyboard() -> PadKeyboardSession? {
        guard !allGames.isEmpty else { return nil }
        if route != .library { goLibrary() }
        let session = PadKeyboardSession(text: searchText)
        searchBarFloats = true
        searchBarRaised = false
        withAnimation(searchBarMotion) { padKeyboard = session }
        // A beat for the field to be measured, coming from Home; then it moves.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard padKeyboard === session else { return }
            withAnimation(searchBarMotion) { searchBarRaised = true }
        }
        return session
    }

    /// The bar goes back to its place as the keyboard leaves; the field takes over once it's there.
    func closePadKeyboard() {
        guard padKeyboard != nil else { return }
        withAnimation(searchBarMotion) {
            padKeyboard = nil
            searchBarRaised = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(searchBarMotion == nil ? 0 : 340))
            if padKeyboard == nil { searchBarFloats = false }
        }
    }

    /// Short and quiet, once there and once back; none with Reduce Motion.
    private var searchBarMotion: Animation? {
        Prefs.reduceMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                           stored: UserDefaults.standard.string(forKey: Prefs.Keys.reduceMotion) ?? "") ? nil : .smooth(duration: 0.32)
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
        route == .launchers || (route == .home && (homeOnAllGames || setup.isActive)) ? nil : selected
    }

    /// Stands for the "All games" tile in `homeGameID`.
    private static let allGamesTile = "\u{0}all"

    private func rememberSelection() {
        switch route {
        case .home: homeGameID = homeOnAllGames ? Self.allGamesTile : selected?.id
        case .library: libraryGameID = selected?.id
        case .detail, .launchers: break
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

    /// The four launcher cards; Settings › Stores leads here.
    func openLaunchers() {
        showingSettings = false
        rememberSelection()
        refreshLaunchers()
        route = .launchers
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
        case .launchers:
            goHome()
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
        case .launchers:
            openLaunchers()
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
        case .launchers: break  // the selected card has it (InputRouter)
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
        // Controller support where a store says it: Epic and GOG through the same game on Steam.
        return StarterFacts(installed: game.isInstalled, level: compatibility(of: game).level,
                            controller: game.knownController,
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

    /// The stores with games in the library, in their own order: the store chip shows from two on.
    var storesWithGames: [Provider] {
        let found = Set(cards.lazy.filter(\.inLibrary).flatMap(\.providers))
        return Provider.allCases.filter(found.contains)
    }

    /// B on the open downloads panel: it closes, and the pad's highlight goes back to its ring.
    func closeDownloads() {
        showingDownloads = false
        if PadFocus.shared.focused != nil, !downloads.isEmpty || move != nil { PadFocus.shared.focus("top.downloads") }
    }

    /// Esc or B on an open list: it closes, and the pad's highlight goes back to its chip.
    func closeLibraryMenu(_ menu: LibraryMenu) {
        libraryMenu = nil
        if PadFocus.shared.focused != nil { PadFocus.shared.focus(menu.chipID) }
    }

    /// A on a chip of the library's row: its list opens, the pad's highlight on what's chosen now (the
    /// first switch in the filter panel). B closes it again (closeLibraryMenu).
    /// The library row's "Clear filters": store, filters and search back to the start, the order
    /// stays. The button goes with them, so the pad's highlight moves to the Filter chip.
    func clearFilters() {
        let highlighted = PadFocus.shared.focused != nil
        searchText = ""
        filters = filters.cleared
        if highlighted { PadFocus.shared.focus(LibraryMenu.filters.chipID) }
    }

    func openLibraryMenu(_ menu: LibraryMenu) {
        libraryMenu = menu
        switch menu {
        case .store: PadFocus.shared.focus("store.\(filters.store?.rawValue ?? "all")")
        case .sort: PadFocus.shared.focus("sort.\(filters.sort)")
        case .filters: PadFocus.shared.focus(LibraryFilters.Filter.allCases.first.map { "filter.\($0)" } ?? "filter.off")
        }
    }

    /// How many games `filter` leaves, with the store picked: the number beside it in the filter panel.
    func count(with filter: LibraryFilters.Filter) -> Int {
        let only = LibraryFilters(store: filters.store, on: [filter])
        return cards.lazy.filter { !self.isHidden($0) && $0.counted && only.admits($0) { self.compatibility(of: $0).level } }.count
    }

    /// The hidden games, each once.
    var hiddenCount: Int { cards.lazy.filter { self.isHidden($0) && $0.install != .inStore }.count }

    /// Marked in any of its stores: a game from several stores shares its marks.
    func isHidden(_ game: Game) -> Bool { game.isMarked(in: hiddenGames) }
    func isPinned(_ game: Game) -> Bool { game.isMarked(in: pinnedGames) }
    func isLater(_ game: Game) -> Bool { game.isMarked(in: laterGames) }

    /// Any game in the library, installed or not; a game that's hidden comes back first.
    func canMarkLater(_ game: Game) -> Bool { game.inLibrary && !isHidden(game) }

    /// The Play Later list as the library's chip counts it, with the store picked. A game that left
    /// the library doesn't count, and is on the list again when it returns.
    var laterCount: Int {
        laterGames.isEmpty ? 0 : DuplicateGames.count(cards, hidden: hiddenGames, in: filters.store, on: laterGames)
    }

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

    /// On Home's rail right now.
    func isOnHome(_ game: Game) -> Bool { homeRail.contains { games.indices.contains($0) && games[$0].id == game.id } }

    /// Off Home until it's played again (a pinned one is unpinned too); the library keeps it. With Undo.
    func removeFromHome(_ game: Game) {
        let wasPinned = isPinned(game)
        var removals = offHome
        game.gameIDs.forEach { removals[$0] = Date() }
        setOffHome(removals)
        mark(game.gameIDs, pinned: wasPinned ? false : nil)
        Toasts.shared.show(L10n.t("%@ is off Home until you play it again", game.name),
                           action: .init(label: L10n.t("Undo")) { [weak self] in
                               guard let self else { return }
                               var back = self.offHome
                               game.gameIDs.forEach { back[$0] = nil }
                               self.setOffHome(back)
                               self.mark(game.gameIDs, pinned: wasPinned ? true : nil)
                           })
    }

    private func setOffHome(_ removals: [GameID: Date]) {
        offHome = removals
        HomeRemovals.save(removals)
    }

    /// P: stays on Home's rail even when it hasn't been played for a while.
    func togglePinned(_ game: Game) {
        guard canPin(game) || isPinned(game) else { return }
        let pin = !isPinned(game)
        // Pinned is on Home again, whenever it was taken off.
        if pin, game.gameIDs.contains(where: { offHome[$0] != nil }) {
            var removals = offHome
            game.gameIDs.forEach { removals[$0] = nil }
            setOffHome(removals)
        }
        mark(game.gameIDs, pinned: pin)
        Toasts.shared.show(pin ? L10n.t("%@ stays on Home – even when you haven't played it for a while", game.name)
                               : L10n.t("%@ is no longer pinned", game.name))
    }

    /// A game to play some day, marked from its card while scrolling the library.
    func toggleLater(_ game: Game) {
        guard canMarkLater(game) || isLater(game) else { return }
        let add = !isLater(game)
        mark(game.gameIDs, later: add)
        Toasts.shared.show(add ? L10n.t("%@ is on your Play Later list", game.name) : L10n.t("%@ is off your Play Later list", game.name))
    }

    /// All of a game's stores at once, so it's marked or not wherever it's looked up.
    private func mark(_ games: [GameID], hidden: Bool? = nil, pinned: Bool? = nil, later: Bool? = nil) {
        if let hidden {
            GameMarks.set(games, hidden, in: &hiddenGames)
            GameMarks.save(hiddenGames, .hidden)
            if hiddenGames.isEmpty { showingHidden = false }
        }
        if let pinned {
            GameMarks.set(games, pinned, in: &pinnedGames)
            GameMarks.save(pinnedGames, .pinned)
            // Pinned again later it starts behind the others, not at a place it once had.
            if !pinned, pinOrder.contains(where: games.contains) {
                pinOrder.removeAll(where: games.contains)
                HomePinOrder.save(pinOrder)
            }
        }
        if let later {
            GameMarks.set(games, later, in: &laterGames)
            GameMarks.save(laterGames, .later)
        }
        // The list's last game gone: no empty grid, the library again.
        if filters.later, laterCount == 0 { filters.later = false }
        applyFilter()
    }

    /// The pinned games in the library, in their order (Settings › Home).
    var pinnedHomeGames: [Game] {
        let pinned = cards.indices.filter { cards[$0].inLibrary && cards[$0].isMarked(in: pinnedGames) }
        return HomePinOrder.sorted(pinned, in: cards, order: pinOrder).map { cards[$0] }
    }

    func setHomeSource(_ source: HomeSources.Source, _ on: Bool) {
        homeSources.set(source, on)
        homeSources.save()
        applyFilter()
    }

    /// Moves a pinned game a place up (-1) or down (1) in Settings › Home.
    func movePin(_ game: Game, by delta: Int) {
        let pinned = pinnedHomeGames
        guard let index = pinned.firstIndex(where: { $0.id == game.id }),
              let order = HomePinOrder.moved(pinned, index: index, by: delta, order: pinOrder) else { return }
        pinOrder = order
        HomePinOrder.save(order)
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
        case .detail, .launchers:
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
        case .detail, .launchers:
            break
        }
    }

    func launchSelected() {
        guard let game = selected else { return }
        input.feel(.gameStart)
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

    /// The game test calls a start off at any step: one that came to a sign-in or Steam's question.
    func callOffLaunch() {
        launchTask?.cancel()
    }

    /// The start in progress is Nightforge's own: the game again another way after a start that didn't take.
    private var startsAgain = false
    /// Each start's number: one called off by a newer start leaves that one's state alone when it ends.
    private var launchNumber = 0

    /// Whether a Play may start a game now: no start in progress – or only Nightforge's own start
    /// again another way, which gives way to the player's.
    nonisolated static func mayStart(launching: Bool, startsAgain: Bool) -> Bool {
        !launching || startsAgain
    }

    /// A start begins: its number, and nothing left of the one before.
    private func beginLaunch(_ game: Game) -> Int {
        launchNumber += 1
        launchingID = game.id
        lookNow()
        callOffWakeUpdate()
        startsAgain = false
        GameDisplay.enterGame()
        launchNeedsConfirmation = false
        launchPhase = nil
        launchBuildsShaders = false
        return launchNumber
    }

    /// A start is over – unless a newer one has begun since, whose state this is now.
    private func endLaunch(_ number: Int) {
        guard number == launchNumber else { return }
        launchingID = nil
        startsAgain = false
        launchNeedsConfirmation = false
        launchPhase = nil
        launchBuildsShaders = false
    }

    /// The player left a start on the curtain. What it waits for may not be interruptible (Steam coming
    /// up), so it's over for Nightforge now: its number moves on, and its own end changes nothing later.
    private func abandonLaunch() {
        launchTask?.cancel()
        leftStart = launchTask
        endLaunch(launchNumber)
        launchNumber += 1
    }

    private var leftStart: Task<Void, Never>?

    /// A start the player left may still be winding down. The next one waits for it under its own
    /// curtain, so that two never work on Steam or the saves at once.
    private func leftStartEnded() async {
        await leftStart?.value
    }

    /// `d3dMetalChecked`: the question about D3DMetal is answered (or isn't needed) – D3DMetalFlow starts it again.
    func launch(_ game: Game, d3dMetalChecked: Bool = false) {
        guard game.isInstalled, Self.mayStart(launching: launchingID != nil, startsAgain: startsAgain) else { return }
        // The Windows client can't be asked yet: nothing below knows it, and Steam's or Epic's way
        // would start the wrong thing. The Mac client's games go below (launchBattleNetMac).
        if game.provider == .battlenet, game.platform != .mac {
            errorMessage = L10n.t("%@ can't start from Nightforge yet: start it in Battle.net.", game.name)
            return
        }
        // What the start before still does – watch its game's first seconds, start it again another
        // way – ends with a Play: OxyRail, quit a few seconds in on 1.11., started again on DXVK
        // while Valheim started, and took Valheim's curtain.
        launchTask?.cancel()
        Engine.noteGameActivity()  // the quit script waits for cloud saves if Nightforge quits soon after (Engine.steamShutdownScript)
        if needsEpicSignIn(game) { return }
        if game.platform == .mac {
            // A Mac version made for Intel runs on Rosetta too.
            if Self.startNeedsRosetta(platform: .mac, provider: game.provider, macAppleSilicon: game.macAppleSilicon),
               !rosettaReady(for: "the start of \(game.name)", then: { [weak self] in self?.launch(game, d3dMetalChecked: d3dMetalChecked) }) {
                return
            }
            switch game.provider {
            case .gog: launchGOGMac(game)
            case .battlenet: launchBattleNetMac(game)
            default: launchMac(game)
            }
            return
        }
        // Wine is x86_64: without Rosetta nothing below can start, and the start isn't begun (nothing on its way's account).
        guard rosettaReady(for: "the start of \(game.name)", then: { [weak self] in self?.launch(game, d3dMetalChecked: d3dMetalChecked) })
        else { return }
        // DirectX 12 only, and Apple's D3DMetal isn't in the engine: asked once, before anything starts.
        if !d3dMetalChecked, askAboutD3DMetalBeforeStart(game) { return }
        let viaSteam = game.provider == .steam
        if viaSteam && game.bottle.isBuiltIn && !Engine.steamSignedIn && !otherSteamFree(for: .windows) { return }
        let number = beginLaunch(game)
        let behavior = Prefs.afterLaunch
        launchRepair = nil  // a start before this one mended nothing of this one's
        launchTask = Task {
            defer { endLaunch(number) }
            // However the start ends, one judged by its first seconds brings Nightforge back from its curtain.
            defer { finishJudging(game, current: number == launchNumber && !Task.isCancelled) }
            // The curtain at once for a game through Steam, as for a Mac version (`launchMac`): Steam for
            // Mac going and this Steam coming up happen under it, not behind the page.
            // Epic's and GOG's update and save too, with their progress and B to stop them (CurtainEscape).
            raiseCurtain(for: game)
            await leftStartEnded()
            if Task.isCancelled { return }
            if viaSteam, game.bottle.isBuiltIn {
                await steamSwitch.makeWayForWindows(facts: steamFacts, phase: { self.launchPhase = $0 },
                                                    restartWindows: { await self.restartWindowsSteam() })
                launchPhase = nil
            }
            if viaSteam, game.bottle.isBuiltIn { wakeSteam(forStart: true, game: (game.gameID.key, game.name)) }
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
            // Offline Mode"): wait for it while it comes along (steamSignInStep). One that is stuck is
            // restarted once, together with a restart the game's settings need anyway (restartsSteamForStart).
            var steamStuck = false
            if viaSteam, game.bottle.isBuiltIn, Engine.isSteamSignedIn, !Engine.steamSignedIn {
                launchPhase = .signingIn
                let began = Date()
                waiting: while true {
                    let quiet = await Engine.offMain { Engine.steamLogsQuiet() }
                    switch Self.steamSignInStep(signedIn: Engine.steamSignedIn, running: Engine.isSteamRunning,
                                                waited: Date().timeIntervalSince(began), quietFor: quiet) {
                    case .signedIn:
                        break waiting
                    case .stuck:
                        steamStuck = true
                        GameLog.note("Steam isn't signed in after \(Int(Date().timeIntervalSince(began))) s"
                                     + (Engine.isSteamRunning ? ", nothing in its logs for \(Int(min(quiet, 9999))) s" : ", and it isn't running")
                                     + ": it's restarted once, before the game")
                        break waiting
                    case .wait:
                        try? await Task.sleep(for: .seconds(1))
                        if Task.isCancelled { return }
                    }
                }
                launchPhase = nil
            }
            if viaSteam, game.bottle.isBuiltIn { await waitForSteamCloud(Engine.steamRoot) }
            if Task.isCancelled { return }  // no saves taken along, and no question about them, for a start that's over
            if viaSteam, game.bottle.isBuiltIn { await takeSavesAlong(game, to: .windows) }
            // A Steam restart still under way ends its Wine session at its end, with whatever started in it.
            if !viaSteam, game.bottle.isBuiltIn, let restart = steamStartup {
                await restart.value
                if Task.isCancelled { return }
            }
            // Epic: a waiting update comes first, like Steam's "Update & Play".
            if game.provider == .epic, game.pendingUpdate != nil {
                guard await updateEpic(game) else { return }
            }
            // Epic: the newest save comes down from Epic before the game reads it.
            if game.provider == .epic, epic.catalog.games.contains(where: { $0.appName == game.gameID.id && $0.cloudSaves }) {
                launchPhase = .syncingSaves
                await epic.syncSaves(game, upload: false)
                launchPhase = nil
                if Task.isCancelled { return }  // it ran to its end, nothing is left half done, and the game doesn't start
            }
            // GOG: the same, an update first and then the newest save.
            if game.provider == .gog { guard await beforeGOGStart(game) else { return } }
            var runner = game.bottle.isBuiltIn ? await Engine.installedWine()?.path : Prefs.runnerPath
            let newest = runner
            // Known fixes for this game (profiles/profiles.json) and what its files reveal.
            let profile = game.bottle.isBuiltIn ? await ProfileStore.shared.profile(for: game.gameID) : nil
            // On the first run the wiki's list may still be on its way: one start waits a few seconds for it.
            await macSourcesAtHand()
            let insight = await insight(of: game)
            let analysis = insight?.analysis
            // A game with an anti-cheat or a cheat protection of its own (NextStart.handsOff): nothing of Nightforge's
            // in its process – no frame limit on D3DMetal either (D3DMetalPace), on any way it starts.
            let handsOff: Bool
            if game.bottle.isBuiltIn {
                let block = game.antiCheatBlock, installDir = game.installDir
                handsOff = await Engine.offMain { NextStart.handsOff(profile: profile, block: block, installDir: installDir) }
            } else {
                handsOff = false
            }
            let refreshRate = GameDisplay.screen?.maximumFramesPerSecond ?? 60
            Hardware.refresh()  // the screen the game opens on, Low Power Mode: the automatic choices follow them
            // A preset fixes frame limit and MetalFX; "Most compatible" tries the safest way first.
            var options = GameOptionsStore.load(game.gameID).resolved(refreshRate: refreshRate, profile: profile)
            let automatic = game.bottle.isBuiltIn && options.graphics == .automatic
            let attempts = LaunchHealth.ladder(insight?.attempts ?? [], preset: options.preset, profile: profile, hint: insight?.hint)
            if automatic { LaunchHealth.review(game.gameID, attempts, steamRoot: game.steamRoot) }
            if automatic, !attempts.isEmpty, let analysis {
                let (index, confirmed) = LaunchHealth.current(game.gameID, attempts)
                GameLog.note(LaunchHealth.plan(game.name, attempts: attempts, index: index, confirmed: confirmed, analysis: analysis,
                                               profile: profile, hint: insight?.hint, source: insight?.hintSource,
                                               sortGames: insight?.sortGames ?? 0))
            }
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
            // The one quiet second start a confirmed way gets after an early end (LaunchHealth.startsAgainQuietly).
            var startedQuietlyAgain = false
            // Step C (docs/ENTWURF-STARTREZEPT.md 3.2): after a start nothing explains, this Play's starts
            // carry Wine's debug channels (CloserLook). The places below are marked "Step C": where a start
            // gets them, what the diagnosis says of its end, and the decision after a failure.
            var looksCloser = false
            // Step E2: starts on the same way again in this Play, for the cap on them (NextStart.againLimit).
            var sameWayAgain = 0
            // Step E6: the roots the player was asked about in this Play – once each.
            var askedRoots = Set<String>()
            // Step E6: the way that had worked before and got a closer look in this Play. It keeps its place after
            // the one start more the look takes on it, which runs as a way not confirmed.
            var lookedAtProven: String?
            // Starts of this Play that ended at a window of the game's own that says nothing Nightforge can read
            // (LaunchHealth.endedAtUnreadableWindow): the second such end is the player's choice.
            var unreadableEnds = 0
            starts: while true {
                // Another way after one that didn't take: the curtain stays up through all the next
                // one needs first (an engine, runtimes, Steam restarted for its settings), saying so.
                if judging?.id == game.id, !Task.isCancelled { raiseCurtain(for: game) }
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
                // What earlier starts taught about this game (LearnedFixes.learned), read once per start: its
                // runtimes are set up here, and with the way and the profile it makes the start's recipe below.
                let learned = LearnedFixes.learned(game.gameID)
                if let runner {
                    await installRuntimes(for: game, profile: profile, analysis: analysis, learned: learned.runtimes,
                                          wine: URL(fileURLWithPath: runner), showStatus: true)
                    if game.provider == .gog { await setUpGOG(game, wine: URL(fileURLWithPath: runner), showStatus: true) }
                }
                // A start again another way the player's Play called off (`mayStart`): no Steam restarted for it either.
                if Task.isCancelled { return }
                var arguments = (options.graphics == .d3dmetal ? analysis?.preferD3D12Arguments : analysis?.preferD3D11Arguments) ?? []
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
                if game.bottle.isBuiltIn {
                    waysUsed[game.gameID] = LaunchAttempt(graphics: options.graphics == .automatic ? Engine.defaultGraphics : options.graphics,
                                                          arguments: arguments).id
                }
                let logMark = GameLog.mark()
                let startedAt = Date()
                if controllerConnected { padlessStarts.remove(game.id) } else { padlessStarts.insert(game.id) }
                LearnedFixes.setLastLaunch(game.gameID, logMark: logMark)
                var (frameLimit, learning) = FramePacing.automaticLimit(game: game.gameID, options: options,
                                                                         profile: profile, refreshRate: refreshRate)
                // On battery with "Save battery" on: 30 FPS, and nothing learned from a capped session.
                let capped = PowerSource.cappedLimit(frameLimit, onBattery: power.onBattery, saveBattery: Prefs.saveBattery)
                // What holds the limit below Nightforge's own for this screen, for the start's line in the log.
                let throttled = capped != frameLimit ? "battery" : Hardware.current.lowPower ? "lowPower" : nil
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
                // The screens changed since Wine's session began (a TV plugged in, mirroring on): Wine
                // keeps the ones it saw then, and the game would open in their size. A fresh session.
                if game.bottle.isBuiltIn, !anyRunning(.windows), let runner,
                   await Engine.offMain({ GameDisplay.wineSessionStale() }) {
                    launchPhase = .startingSteam
                    let wine = URL(fileURLWithPath: runner)
                    if viaSteam {
                        _ = await restartStuckSteam(wine, freshSession: true)
                    } else {
                        // A store's game starts its own session; Steam comes back when it's needed.
                        try? await Engine.stopSteam(wine)
                        await Engine.offMain { Engine.stopAll(wine) }
                    }
                    launchPhase = nil
                }
                // Settings a game only takes from the environment come with the Steam that starts it.
                let layer = options.graphics == .automatic ? (profile?.graphics ?? Engine.defaultGraphics) : options.graphics
                // Watched once with each new engine build or way, so one the newest engine crashes is noticed.
                let way = LaunchAttempt(graphics: layer, arguments: arguments).id
                if let build, EngineRollback.shared.needsWatch(game.gameID, build: build, way: way) { watchFirstSeconds = true }
                StartDiagnosis.remember([], for: game.gameID)  // an earlier start's
                // Step C: this start's debug channels – on for a closer look or the engine test's switch, off
                // again for the next start without one. A game through Steam gets them from the Steam that
                // starts it (restarted below when they changed); a store's game from its own start.
                let closerLook = game.bottle.isBuiltIn && (looksCloser || CloserLook.always)
                let debugChanged = game.bottle.isBuiltIn && Engine.setCloserLook(closerLook)
                // A game test's starts have Apple's Metal HUD log their frames, a start by Play has it off again
                // (GameTest.logsFrames). It comes as the channels do: through Steam from the Steam that starts it.
                let frameLogBefore = Engine.frameLog
                let frameLogChanged = game.bottle.isBuiltIn && Engine.setFrameLog(GameTest.logsFrames())
                // DXVK's Direct3D 9 draws on KosmicKrisp under winecx – on a held build too: DXVK-macOS's
                // d3d9 gets its device there as well (31.10.2026). Not with the engine test's loader on: that way wins.
                let winecx = game.bottle.isBuiltIn && runner.map { Engine.isGPTKCapable(wine: URL(fileURLWithPath: $0)) } == true
                // Step E1: all this start is made of, as one value (StartRecipe) – the way, the profile and what
                // was learned. Its record, the prefix's settings for the game's programs, its arguments and
                // Rosetta's AVX are all read from it, so what is recorded is what started.
                let recipe = StartRecipe.of(way: LaunchAttempt(graphics: layer, arguments: arguments), learned: learned, profile: profile,
                                            launcherSwitch: analysis?.launcherSwitch, d3dMetalEngine: winecx)
                // Step E4: a way is proven for what it was started with (LaunchHealth.holds). Made of something
                // else now – its profile changed, a start taught something, another engine's DLLs – it counts
                // as not proven for this start: watched to its picture again, and confirmed anew with this recipe.
                // A way proven before recipes were kept takes the one the start record has for it, else this one's.
                if wayConfirmed {
                    let key = game.gameID.key
                    let recorded = await Engine.offMain { StartEvidence.knownProofs()[key]?.workedWith[way] }
                    LaunchHealth.adoptRecipe(game.gameID, attempts, recorded: recorded, starting: recipe)
                }
                if wayConfirmed, !LaunchHealth.holds(game.gameID, attempts, for: recipe) {
                    GameLog.note("\(game.name): its way was proven with another recipe – this start is watched to its picture again")
                    LaunchHealth.unconfirm(game.gameID, attempts)
                    LaunchHealth.recordStart(game.gameID, attempts)
                    wayConfirmed = false
                }
                if automatic, !attempts.isEmpty {
                    StartEvidence.note(.started, game: game.gameID, way: way, engine: build?.engine, known: wayConfirmed,
                                       kind: analysis?.kind, recipe: recipe, profiled: profile?.shapesStart, closerLook: closerLook,
                                       name: game.name, parts: build?.parts)
                }
                // Another program in the game's LaunchOptions also comes with the Steam that starts it (SteamProgram).
                let programChanged = viaSteam && game.bottle.isBuiltIn
                    ? await Engine.offMain { [options] in
                        SteamProgram.prepare(game, route: SteamProgram.route(game, layer: layer, options: options, profile: profile))
                    }
                    : false
                let vulkan = Engine.vulkanDriver(layer: layer, analysis: analysis, winecx: winecx,
                                                 kosmicKrisp: Engine.kosmicKrispReady ? Engine.kosmicKrispNow : nil)
                // A session has msync or doesn't: a game joining one that runs takes it as it is.
                let msyncWanted = anyRunning(.windows) ? nil : Engine.msyncWanted(profile: profile)
                let environmentChanged = viaSteam && game.bottle.isBuiltIn &&
                   (Engine.prepareLaunchEnvironment(avx: recipe.avx, d3dMetal: layer == .d3dmetal,
                                                   frameLimit: frameLimit, upscaling: options.effectiveUpscaling(profile: profile),
                                                   retina: options.retina(profile: profile, layer: layer, analysis: analysis),
                                                   environment: GameEnvironment.wanted(for: game.gameID, profile: profile),
                                                   vulkan: vulkan,
                                                   vulkanLoader: Engine.vulkanLoaderEnvironment(layer: layer, d3d9: analysis?.usesD3D9 == true,
                                                                                                wine: runner.map(URL.init(fileURLWithPath:))),
                                                   msyncWanted: msyncWanted, antiCheat: handsOff)
                    || programChanged || debugChanged || frameLogChanged)
                // What Steam's next start for this game begins with (F5): its settings as they are now.
                if viaSteam, game.bottle.isBuiltIn { Engine.rememberLaunch(for: game.gameID.key) }
                // One restart at most: the settings the game takes from Steam's environment, and a Steam that got stuck
                // signing in, together (F3, 21.11.2026: the stuck one's restart and the settings' made two in a row).
                if viaSteam, game.bottle.isBuiltIn, let runner,
                   Self.restartsSteamForStart(environmentChanged: environmentChanged, stuck: steamStuck,
                                              running: Engine.isSteamRunning, gamesRunning: anyRunning(.windows)) {
                    launchPhase = .restartingSteam
                    GameLog.note("Steam restarts for \(game.name)" + (steamStuck ? ": it got stuck signing in" : "")
                                 + (environmentChanged ? (steamStuck ? ", and " : ": ") + "the game's settings come with its environment" : ""))
                    _ = await restartStuckSteam(URL(fileURLWithPath: runner))
                    steamStuck = false  // restarted: the next way of this start finds it fresh
                    launchPhase = nil
                }
                if Task.isCancelled { return }
                if viaSteam, game.bottle.isBuiltIn, layer == .d3dmetal {
                    GameLog.note(GameLog.d3dMetalStart(game.name, environment: Engine.steamEnvironment, retina: Engine.launchRetina))
                }
                // A store's game (Epic, GOG) starts a session of its own: msync as it wants it, before anything
                // else of that session; Steam ended first, it would stay in the old one.
                if !viaSteam, game.bottle.isBuiltIn, let msyncWanted, let runner {
                    Engine.msync = msyncWanted
                    if Engine.msyncSessionDiffers() {
                        launchPhase = .startingSteam
                        let wine = URL(fileURLWithPath: runner)
                        try? await Engine.stopSteam(wine)
                        await Engine.offMain { Engine.applyMsyncMode(wine) }
                        launchPhase = nil
                    }
                }
                // A store's game (Epic, GOG) starts a session of its own: Wine's Retina mode goes into the
                // prefix before it, Steam ended first as for a fresh session, not with a Steam start.
                let retina = options.retina(profile: profile, layer: layer, analysis: analysis)
                if !viaSteam, game.bottle.isBuiltIn, Engine.retinaModeApplied != retina, !anyRunning(.windows), let runner {
                    launchPhase = .startingSteam
                    let wine = URL(fileURLWithPath: runner)
                    try? await Engine.stopSteam(wine)
                    Engine.launchRetina = retina
                    await Engine.offMain { Engine.applyRetinaMode(wine) }
                    launchPhase = nil
                }
                let shaders = LaunchPhase.graphicsSignature(runner: runner, layer: layer,
                                                            components: ComponentStore.localManifest()?.components ?? [])
                // Starting it again another way, and the player pressed Play meanwhile: theirs has the curtain.
                if Task.isCancelled { return }
                launchBuildsShaders = game.bottle.isBuiltIn && LaunchPhase.isFirstStart(game.gameID, signature: shaders)
                GameLog.note(GameTest.startNote(game: game.name, way: way, engine: build?.engine))  // the ways a start took (GameTest)
                // What this start is held to (GameTest.held reads it): the limit goes to DXMT, DXVK and D3DMetal,
                // as MetalFX does – Wine's own Direct3D takes neither.
                if game.bottle.isBuiltIn {
                    GameLog.note(GameTest.limitNote(game: game.name, GameTest.Held(
                        frameLimit: layer == .wined3d ? 0 : frameLimit, refreshRate: refreshRate,
                        metalFX: layer.upscales && options.effectiveUpscaling(profile: profile), throttled: throttled)))
                    // Measuring play (the hidden switch gameTest.measurePlay): when the session began and under what.
                    if GameTest.measuresPlay(), !GameTest.active {
                        GameLog.note(GameTest.playNote(game: game.name, onBattery: power.onBattery,
                                                       lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, load: GameTest.Load.now))
                    }
                }
                // Past the game's own launcher window where its program knows the switch: straight into the
                // game, as on a console (Guardians of the Galaxy, 9.11.2026). Not part of the way; the recipe has it.
                if let past = analysis?.launcherSwitch, StartRecipe.pastLauncher(arguments, switch: past) != arguments {
                    GameLog.note("\(game.name) starts past its own launcher window (\(past))")
                }
                // Whether a display is taken before the game takes one, and by whom: ABZU's quiet first start and
                // Overwatch's hidden window (15.11.2026) look like a game starting into another's capture.
                if game.bottle.isBuiltIn {
                    let capture = await Engine.offMain { GameProcesses.captureNote() }
                    GameLog.note("Displays at the start of \(game.name): \(capture)")
                }
                // "Back to Nightforge" while Steam came up ends the start here: nothing goes to Steam after it. Up to
                // 21.11.2026 the game started seconds after the player had gone back (F3).
                if Task.isCancelled { return }
                // The permit for Nightforge's frame limit on D3DMetal: this game's start only, never one with an anti-cheat.
                if game.bottle.isBuiltIn {
                    let installDir = game.installDir, d3dMetal = layer == .d3dmetal
                    await Engine.offMain { D3DMetalPace.prepare(limit: frameLimit, installDir: installDir, handsOff: handsOff, d3dMetal: d3dMetal) }
                }
                raiseCurtain(for: game)
                let started = viaSteam
                    ? await start(game, runner: runner, options: options, profile: profile, recipe: recipe, frameLimit: frameLimit)
                    : await startDirect(game, runner: runner, options: options, profile: profile, recipe: recipe,
                                        frameLimit: frameLimit, layer: layer, vulkan: vulkan, usesD3D9: analysis?.usesD3D9 == true,
                                        handsOff: handsOff)
                // Step C: a store's game has the channels from its own start; Steam's settings don't keep them.
                if !viaSteam, closerLook { Engine.setCloserLook(false) }
                // … and the frame log is back at what Steam has: the next game through Steam then asks for its
                // restart, where one left on here would pass for Steam's own.
                if !viaSteam, frameLogChanged { Engine.setFrameLog(frameLogBefore) }
                guard started else { return }
                if game.bottle.isBuiltIn { LaunchPhase.recordStart(game.gameID, signature: shaders) }
                launchBuildsShaders = false
                launchingID = nil
                startsAgain = false
                if viaSteam, game.bottle.isBuiltIn {
                    SteamPriority.watch(game)
                    // Steam took the start: it runs on this build (EngineRollback).
                    if let build { EngineRollback.shared.recordSteamStarted(build) }
                }
                startedHere.insert(game.id)
                judging = watchFirstSeconds ? (game.id, startedAt) : nil
                await bringToFront(game)
                guard watchFirstSeconds else { break }

                // The first start with this way: is the game still there after its first seconds? Not known
                // (no process list): nothing learned either way – only a picture confirms it then (confirmOnceDrawing).
                var firstSeconds = await survivesFirstSeconds(game, logMark: logMark, layer: layer, startedAt: startedAt)
                // A way not proven yet hasn't started until there's a picture. Not for what starts through another
                // launcher or with an anti-cheat, whose hand-overs and sign-ins take as long as they take.
                var noPicture: String?
                if firstSeconds == .survived, automatic, !attempts.isEmpty, !wayConfirmed, !GameTest.active,
                   analysis?.launcher == nil, analysis?.antiCheat.isEmpty != false {
                    noPicture = await waitForPicture(game, logMark: logMark, startedAt: startedAt)
                    if noPicture != nil { firstSeconds = .ended }
                }
                if firstSeconds != .ended {
                    if judging?.id == game.id { judging = nil }  // its end is a session's like any other
                    confirmOnceDrawing(game, attempts: automatic ? attempts : [], build: build, way: way, recipe: recipe, logMark: logMark,
                                       startedAt: startedAt, wasConfirmed: wayConfirmed)
                    break
                }
                // Every start that was recorded gets its outcome in the record (StartEvidence.Event.ended).
                let recorded = automatic && !attempts.isEmpty
                func noteEnded(_ reason: String, diagnosis: [String] = []) {
                    guard recorded else { return }
                    StartEvidence.note(.ended, game: game.gameID, way: way, reason: reason, diagnosis: diagnosis,
                                       picture: LaunchHealth.showedPicture(game.gameID, since: startedAt),
                                       seconds: Int(Date().timeIntervalSince(startedAt)))
                }
                // Quit Game in the overlay: the player's end, nothing learned from it.
                if LaunchHealth.quitByPlayer(game.gameID, since: startedAt) {
                    noteEnded("quit by the player")
                    return
                }
                // It ended within its first seconds – or a new start called this one off (Task.isCancelled).
                // One that showed a picture worked; without one a confirmed way loses its confirmation
                // only on evidence, and moves on only on a graphics error (Mafia II on DXVK:
                // "DxvkAdapter: Failed to create device", 31.10.2026) – LaunchHealth.earlyEnd.
                let graphicsFailed = GameLog.graphicsFailed(since: logMark, layer: layer)
                let installDir = game.installDir
                let (log, programs) = await Task.detached(priority: .utility) {
                    (GameLog.text(since: logMark), Set(Engine.executables(in: installDir)))
                }.value
                let drew = LaunchHealth.showedPicture(game.gameID, since: startedAt) || LaunchHealth.drewFrames(in: log, programs: programs)
                // Direct3D 9 on a way whose Direct3D 9 is DXVK's: no way of the player's to answer that.
                let direct3D9Failed = !drew && GameLog.direct3D9Failed(in: log, layer: layer)
                let crashed = wayConfirmed && !drew
                    && (GameLog.crashed(in: log) || !GameLog.crashReports(installDir: installDir, since: startedAt).isEmpty)
                let outcome = LaunchHealth.earlyEnd(trusted: wayConfirmed, graphicsFailed: graphicsFailed, crashed: crashed, drew: drew,
                                                    shortEndsBefore: wayConfirmed ? LaunchHealth.shortEnds(game.gameID, attempts) : 0)
                if outcome == .confirm {
                    // The game is gone; Nightforge comes back as after any game (watchForGameEnd).
                    if automatic, !attempts.isEmpty {
                        LaunchHealth.confirm(game.gameID, attempts, recipe: recipe)
                        if !wayConfirmed { StartEvidence.note(.worked, game: game.gameID, way: way) }
                    }
                    if let build { EngineRollback.shared.recordGood(game.gameID, build: build, way: way) }
                    return
                }
                // It ended without a picture: the curtain says Nightforge looks into it while it does
                // (LaunchRepair, board B of 15.11.2026) – "One more try …", so not where the end may be the player's
                // own and no start follows (LaunchRepair.saysLooking): that one goes back as before, without the line.
                if !Task.isCancelled, LaunchRepair.saysLooking(provenFirstShortEnd: wayConfirmed && outcome == .keep,
                                                               endedAtOwnQuestion: LaunchHealth.endedAtOwnQuestion(game.gameID, since: startedAt)) {
                    sayRepair(.looking)
                }
                // What the start left behind, read through the table (StartDiagnosis): said in the log, kept for
                // the record and the problem report, and what the decision below goes by (step E3). Never for a
                // game with an anti-cheat or a cheat protection of its own (NextStart.handsOff): its dumps aren't
                // looked into (`found` stays nil), and all that follows from nil below holds for both kinds.
                var diagnosis: [String] = []
                var found: [StartDiagnosis]?
                // Step E5: the message box the game ended at, if it ended at one (CloserLook.Reading.endedAtBox).
                var endedAtBox: String?
                // Step C: nothing in the diagnosis says why (StartDiagnosis.unexplained). Never for an anti-cheat game.
                var unexplained = false
                if !Task.isCancelled {
                    let hung = noPicture != nil, folder = game.installDirName, block = game.antiCheatBlock
                    (found, endedAtBox) = await Task.detached(priority: .utility) {
                        guard !NextStart.handsOff(profile: profile, block: block, installDir: installDir) else { return (nil, nil) }
                        let finding = StartDiagnosis.finding(logText: log, installDir: installDir, gameFolder: folder,
                                                             since: startedAt, layer: layer, hung: hung)
                        // The test switch's finding comes on top here, past the anti-cheat's guard (StartDiagnosis.testFinding).
                        return (StartDiagnosis.withTestFinding(StartDiagnosis.diagnose(finding)), finding.reading.endedAtBox)
                    }.value
                    diagnosis = (found ?? []).map { GameLog.redacted($0.line) }
                    unexplained = found.map(StartDiagnosis.unexplained) ?? false
                    for line in diagnosis { GameLog.note("Diagnosis for \(game.name): \(line)") }
                    StartDiagnosis.remember(diagnosis, for: game.gameID)
                }
                // Closed at a question of its own (the curtain saw it): the player's choice too – unless
                // the log says the graphics failed or it crashed, as after Play in Unity's window it might.
                // Step E5: nor when the table saw the start fail, or the window was a message box that only says
                // something (LaunchHealth.ownQuestionWasAChoice) – Metal Gear Solid V's "Failed to load SteamAPI"
                // went into the record as the player's choice on 11.11.2026. Then the start failed, and what
                // comes after a failed start comes below.
                if let end = LaunchHealth.ownQuestionEnd(game.gameID), end >= startedAt {
                    let crashedAtAll = GameLog.crashed(in: log) || !GameLog.crashReports(installDir: installDir, since: startedAt).isEmpty
                    let cannotDraw = automatic && !wayConfirmed && LaunchHealth.layerCannotDraw(analysis, layer: layer)
                    let stands = Self.ownQuestionEndStands(end: end, startedAt: startedAt, lastRunning: firstSecondsRunning[game.id],
                                                           graphicsFailed: graphicsFailed || cannotDraw || direct3D9Failed, crashed: crashedAtAll)
                    let failureSeen = StartDiagnosis.sawFailure(found ?? [])
                    let knownWindow = LaunchHealth.showsOwnWindow(analysis)
                    let unreadable = LaunchHealth.endedAtUnreadableWindow(explained: failureSeen, endedAtBox: endedAtBox, knownWindow: knownWindow)
                    let choice = LaunchHealth.ownQuestionWasAChoice(explained: failureSeen, endedAtBox: endedAtBox, knownWindow: knownWindow,
                                                                    unreadableBefore: unreadableEnds,
                                                                    somethingFound: StartDiagnosis.speaksAgainstAChoice(found ?? []))
                    if stands, unreadable { unreadableEnds += 1 }
                    if stands, !choice {
                        let why = failureSeen ? "the diagnosis says why it ended"
                            : endedAtBox.map { "a message box that only says \"\(GameLog.redacted(String($0.prefix(120))))\"" }
                            ?? "a window of its own that isn't one of Windows' message boxes, before any picture, in a game with no window of its own known"
                        GameLog.note("Start of \(game.name): the window it ended at was no question – \(why): a failed start")
                    }
                    if stands, choice {
                        GameLog.note("Start of \(game.name): it ended at a question of its own – "
                            + (unreadable ? "a window that says nothing, for the second time in this Play and with nothing found against it: " : "")
                            + "the player's choice, no other way")
                        noteEnded("closed at a question of its own", diagnosis: diagnosis)
                        return
                    }
                    LaunchHealth.forgetOwnQuestion(game.gameID)  // nor does the next start's review go by it
                }
                // Called off by a new start: that one has the curtain, nothing here starts again, and
                // a game gone only a moment (a launcher handing over) isn't judged.
                if Task.isCancelled { return }
                let quietly = wayConfirmed && LaunchHealth.startsAgainQuietly(outcome, alreadyAgain: startedQuietlyAgain,
                                                                              ownLauncher: analysis?.launcher != nil,
                                                                              antiCheat: analysis?.antiCheat.isEmpty == false)
                if wayConfirmed {
                    if outcome == .keep {
                        LaunchHealth.noteStart(game.gameID, attempts, short: true)
                        noteEnded("ended in its first seconds without a picture", diagnosis: diagnosis)
                        // Quit early, by the look of it: the game is gone, Nightforge stays in front – after one
                        // more start on the same way, which ABZU needed now and then.
                        if !quietly { return }
                    } else {
                        LaunchHealth.unconfirm(game.gameID, attempts)
                    }
                }
                launchingID = game.id
                startsAgain = true
                NSApp.activate()
                // Nothing starts again while the game still runs – crashed behind a dialog, hanging, or
                // not ended after a graphics error: a second copy is only turned away ("Game Already
                // Running", Control, 1.11.2026). Every other way below starts it again.
                let folders = Self.processFolders([game])
                let presence = await Task.detached(priority: .utility) { GameProcesses.presence(of: game.id, folders: folders) }.value
                if Task.isCancelled { return }
                if quietly {
                    // Not sure it's gone: as before, Nightforge stays in front and says nothing.
                    if presence.mayBeRunning { return }
                    startedQuietlyAgain = true
                    GameLog.note("\(game.name) ended in its first seconds without a picture on its proven way: started once more on it")
                    sayRepair(.onceMore)
                    continue
                }
                // Not known (no process list, or an old one from before the start) counts as running too.
                if presence.mayBeRunning {
                    if presence == .unknown { GameLog.note("\(game.name): no process list to tell if it still runs – not started again") }
                    errorMessage = L10n.t("%@ is still running, or it hangs. Quit it first, then press Play again.", game.name)
                    return
                }
                // Step E2: what comes after this start is one decision (NextStart.after), where the loop had a
                // branch each for the engine before, a missing runtime, a settings file fixed, no AVX, a closer
                // look and the next way. The loop gathers what is known, asks, and does what the answer says.
                // It ran well this way on the engine before and ends at once on the newest: the newest
                // broke it, so it starts with the one before – the way stays (EngineRollback holds it).
                if let build, case .rollBack = EngineRollback.shared.afterFailedStart(game.gameID, build: build, way: way) {
                    if case .again = NextStart.after(NextStart.Failed(engineBefore: true)) {
                        launchPhase = .rollingBack
                        continue
                    }
                }
                // The game wrote its settings file at its first start, with a setting its profile turns off
                // (Engine.applyFileEdits): fixed here, and a reason for the same way again.
                let filesFixed = game.bottle.isBuiltIn
                    && Engine.applyFileEdits(profile?.fileEdits ?? [], installDir: game.installDir, game: game.gameID.key)
                // What the game itself said goes first: it can rule out ways without trying them.
                let crashTexts = await Task.detached(priority: .utility) {
                    GameLog.crashMessages(installDir: installDir, since: startedAt)
                }.value
                // What acted on a failed start before step E, read as before: the game's words in its crash
                // reports, and Wine's log for a missing runtime, an illegal instruction and the layer's failure.
                // For a game with an anti-cheat this is all the decision ever gets (NextStart.asBefore); for
                // every other game the whole diagnosis decides, with every remedy of the table (step E3).
                let antiCheat = found == nil || analysis?.antiCheat.isEmpty == false
                let decides = !antiCheat ? found ?? [] : NextStart.asBefore(StartDiagnosis.diagnose(StartFinding(
                    messages: crashTexts,
                    missingRuntimes: GameLog.missingRuntimes(since: logMark, gameFolder: game.installDirName),
                    illegalInstruction: game.bottle.isBuiltIn && recipe.avx
                        && GameLog.illegalInstruction(since: logMark, installDir: game.installDir, startedAt: startedAt),
                    graphicsFailed: graphicsFailed, direct3D9Failed: direct3D9Failed, layer: layer)))
                let onLadder = automatic && !attempts.isEmpty
                let index = onLadder ? LaunchHealth.current(game.gameID, attempts).index : 0
                // Step C: nothing explains this end – the ways still to come carry Wine's debug channels, and
                // with no way left the last one starts once more with them, as quietly as a proven way's
                // second start; after that the ladder ends as before. Once per game and engine build.
                // Step E6: a way that had worked before gets that one start more too, and keeps its place after it.
                let proven = wayConfirmed || lookedAtProven == way
                let engineID = build?.engine ?? "unknown"
                let look = !onLadder ? CloserLook.Step.none
                    : CloserLook.step(unexplained: unexplained, antiCheat: antiCheat,
                                      carried: closerLook, takenBefore: CloserLook.taken(game.gameID, engine: engineID),
                                      // Steam restarts for them only with no other Windows game running; this
                                      // one may still be on the list for a moment.
                                      canCarry: game.bottle.isBuiltIn && (!viaSteam || runningGame(.windows).map { $0.id == game.id } != false),
                                      lastWay: index + 1 >= attempts.count, proven: proven)
                let next = NextStart.after(NextStart.Failed(
                    ladder: onLadder ? attempts : [], index: index, proven: proven, learned: learned, recipe: recipe,
                    found: decides, antiCheat: antiCheat,
                    againSoFar: sameWayAgain, filesFixed: filesFixed, look: look))
                /// What the ladder's own steps – a closer look, the next way, giving up – put on record first.
                func noteFailed() {
                    if let said = crashTexts.first { GameLog.note("\(game.name) says: \(GameLog.redacted(String(said.prefix(200))))") }
                    StartEvidence.note(.failed, game: game.gameID, way: way, reason: crashTexts.first ?? noPicture, diagnosis: diagnosis)
                }
                /// The start to come carries the closer look's channels (step C).
                func lookCloser(_ how: String) {
                    looksCloser = true
                    CloserLook.noteTaken(game.gameID, engine: engineID)
                    GameLog.note("\(game.name): nothing explains why it ended – \(how)")
                }
                // Step E6, the player's decision of 14.11.2026 and the board's question of 15.11.: a root the game's
                // signature check stopped at, one Nightforge knows by its fingerprints and holds only on a yes
                // (WindowsRoots.onRequest), is asked about on the curtain. Yes puts it into the prefix and starts the
                // same way once more; no ends the start – the game checks the same file on every way. Never for a
                // game with an anti-cheat, nor in a game test, where nobody answers.
                if !antiCheat, let found,
                   let root = NextStart.rootToAskAbout(found, known: { WindowsRoots.toAsk(named: $0) != nil }, askedBefore: askedRoots,
                                                       needed: WindowsRoots.needed(by: game.gameID)) {
                    askedRoots.insert(root)
                    WindowsRoots.noteNeeded(root, by: game.gameID)
                    if GameTest.active {
                        GameLog.note("\(game.name) needs the root \"\(root)\": a game test asks nobody")
                    } else {
                        noteFailed()
                        GameLog.note("\(game.name) needs the root \"\(root)\", which Nightforge knows: the player is asked")
                        let yes = await askToTrust(root, for: game)
                        if Task.isCancelled { return }
                        GameLog.note("\(game.name): the player " + (yes ? "added" : "didn't add") + " the root \"\(root)\"")
                        if yes, let known = WindowsRoots.toAsk(named: root) { WindowsRoots.trust(known) }
                        if case .again = NextStart.after(rootTrusted: yes, againSoFar: sameWayAgain) {
                            sameWayAgain += 1
                            sayRepair(.rootAdded)
                            continue
                        }
                        // No – or a yes past the cap on starts, which the next Play starts with.
                        sayRepair(yes ? .gaveUp : .rootDeclined)
                        try? await Task.sleep(for: .seconds(LaunchRepair.endStands))
                        return
                    }
                }
                // What the curtain says for it (LaunchRepair.after): the try that comes, or – a proven way keeping its
                // place, no other way to try – that none does. Every way tried says so below, after its record.
                if let repair = LaunchRepair.after(next), repair != .gaveUp { sayRepair(repair) }
                switch next {
                case .again(let changed, let why):
                    // The same way once more: with what Wine said is missing installed, the settings file
                    // fixed, without Rosetta's AVX hint, with a DLL kept unloaded that the crash came from –
                    // all of it in this one start – or for a closer look.
                    sameWayAgain += 1
                    if why == [NextStart.closerLook] {
                        noteFailed()
                        if proven { lookedAtProven = way }
                        lookCloser("it starts once more on this way with Wine's debug channels")
                    } else {
                        if changed != learned {
                            LearnedFixes.keep(changed, for: game.gameID)
                            // The recipe changes: this one failed, on record, so that the way's proof is told
                            // apart by what it was started with (StartEvidence.Proof.failedWith).
                            if onLadder { noteFailed() }
                        }
                        GameLog.note("\(game.name) starts once more on the same way: \(why.joined(separator: ", "))")
                    }
                    continue
                case .noOtherWay:
                    // Graphics chosen by hand, or nothing known about the game: no other way to try. The curtain said
                    // "One more try …" while Nightforge looked (`looking`), so it says that none comes, a moment before
                    // the page (LaunchRepair.noOtherWay). The game is gone: nothing to step back behind, as the loop's
                    // end did up to 15.11.2026 – with "Quit launcher" that quit Nightforge after a start that failed.
                    try? await Task.sleep(for: .seconds(LaunchRepair.endStands))
                    return
                case .keepsItsPlace:
                    // A way that worked before and ended without a graphics error keeps its place:
                    // watched again at the next start. Nightforge stays in front, after the curtain said so
                    // (LaunchRepair.keptPlace).
                    StartEvidence.note(.failed, game: game.gameID, way: way, reason: "a proven way ended in its first seconds again",
                                       diagnosis: diagnosis)
                    try? await Task.sleep(for: .seconds(LaunchRepair.endStands))
                    return
                case .way(let other, _):
                    // On to the way that answers what the game said, or simply the next.
                    noteFailed()
                    if look == .nextWay { lookCloser("the next start carries Wine's debug channels") }
                    LaunchHealth.advance(game.gameID, attempts, to: other)
                    continue
                case .giveUp:
                    noteFailed()
                    // No way is left: the list starts over next time.
                    LaunchHealth.advance(game.gameID, attempts, to: 0)
                    // One way only (Vulkan, DirectX 12): what the game draws with says more than a layer.
                    let tried = attempts.count > 1 ? attempts.map(\.label) : [analysis?.summary ?? attempts.first?.label ?? ""]
                    StartEvidence.note(.gaveUp, game: game.gameID, way: way)
                    // The honest end, on the curtain a moment before the library and its sheet.
                    sayRepair(.gaveUp)
                    try? await Task.sleep(for: .seconds(LaunchRepair.endStands))
                    if Task.isCancelled { return }  // a new start has the curtain: no sheet over it
                    failedLaunch = FailedLaunch(game: game, tried: tried)
                    return
                }
            }

            // Not behind it once a new start has the curtain: its page would take that start's place.
            if !Task.isCancelled { stepBack(behind: game, behavior) }
        }
    }

    /// Runtimes the profile asks for and those an earlier start turned out to need (`learned`:
    /// StartRecipe.Learned.runtimes), and Wine Mono for .NET games. `showStatus` says so on the Play button
    /// while it takes.
    private func installRuntimes(for game: Game, profile: GameProfile?, analysis: GameAnalysis?, learned: [String],
                                 wine: URL, showStatus: Bool) async {
        // What the game is known to need from the start (PCGamingWiki, macSources) goes in before its first start.
        let known = macSources.runtimes(for: game)
        let missing = Engine.missingWinetricks((profile?.winetricks ?? []) + learned.filter { $0 != GameLog.wineMono } + known)
            .filter(Engine.isSafeWinetricksVerb)
        // A runtime set up for a start Nightforge mends keeps that line (LaunchRepair.settingUp).
        let says = showStatus && launchRepair != .settingUp
        // The game test fetches nothing: what a game lacks goes into its report instead (GameTestRun).
        if !missing.isEmpty, !GameTest.active {
            if says { launchPhase = .settingUp }
            await Engine.installWinetricks(missing, wine: wine)
            if says { launchPhase = nil }
        }
        if game.bottle.isBuiltIn, analysis?.usesDotNet == true || learned.contains(GameLog.wineMono),
           !Engine.wineMonoInstalled {
            if says { launchPhase = .settingUpDotNet }
            await Engine.installWineMono(wine)
            if says { launchPhase = nil }
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
            let profile = await ProfileStore.shared.profile(for: game.gameID)
            let analysis = await insight(of: game)?.analysis
            await installRuntimes(for: game, profile: profile, analysis: analysis, learned: LearnedFixes.learned(game.gameID).runtimes,
                                  wine: wine, showStatus: false)
            if game.provider == .gog { await setUpGOG(game, wine: wine, showStatus: false) }
        }
    }

    /// Hands the game to Steam and follows Steam's log until the game runs. True once it does; a
    /// question from Steam can take as long as the player needs, no sign of life ends after 2 min.
    private func start(_ game: Game, runner: String?, options: GameOptions, profile: GameProfile?,
                       recipe: StartRecipe, frameLimit: Int) async -> Bool {
        var watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
        var licenceLog = SteamLicenceLog(steamRoot: game.steamRoot, appID: game.appID)
        launchAsksLicence = false
        launchQuestionTask = nil
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
                                    frameLimit: frameLimit, recipe: recipe)
            }.value
        } catch {
            startFailed(game, error) { RosettaSupport.playerText(error) }
            return false
        }

        var quietSeconds = 0
        var totalSeconds = 0
        var askingSince: Int?
        var shownAt: Int?
        var onPlayerSeconds = 0
        var retriedAfterRestart = false
        var signedInSince: Int?
        var resent = false
        var updated = UpdateProgress()
        /// When the player said yes to Steam's licence, and whether the start went out once more for it.
        var licenceAnsweredAt: Int?
        var startedAgainAfterLicence = false
        /// Steam's own record of the licence, when it asked and whether the answer is in it now (SteamLicence.afterAnswer).
        var licenceOpenWhenAsked: Bool?
        var answerStored = false
        let (appID, root) = (game.appID, game.steamRoot)
        let licences = await Task.detached(priority: .utility) { SteamCatalog.licences(appID: appID, steamRoot: root) }.value
        licenceLog.know(Set(licences.map(\.id)))
        awaitingSteam = true
        defer {
            awaitingSteam = false
            updateSpeed = nil
            if launchPhase == .licenceAnswered { launchPhase = nil }
        }
        while Self.followsSteam(quietSeconds: quietSeconds, seconds: totalSeconds, onPlayerSeconds: onPlayerSeconds) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return false }
            // Steam updates the game first ("Update & Play"): that's no silence, however long it takes.
            if let update = await Task.detached(priority: .utility, operation: { LibraryScanner.updateState(of: game) }).value,
               update.isRunning {
                updated.add(update, at: LibraryScanner.stagingMeasured(game) ?? Date())
                launchPhase = .updating(updated.fraction)
                if updateSpeed != updated.speed { updateSpeed = updated.speed }
                quietSeconds = 0
                continue
            } else if case .updating? = launchPhase {
                launchPhase = nil
                updateSpeed = nil
            }
            totalSeconds += 1
            if askingSince != nil {
                onPlayerSeconds += 1
                if game.bottle.isBuiltIn, totalSeconds % Self.steamLookEvery == 0,
                   await Engine.offMain({ Engine.steamRunningKnown }) == false {
                    steamQuestionOver(yes: false)
                    askingSince = nil
                    shownAt = nil
                    GameLog.note("Steam ended while it asked about \(game.name), at \(GameLog.clock())")
                }
            }
            let event = watcher.poll()
            if watcher.licenceAsked, !startedAgainAfterLicence, !watcher.wentOnAfterLicence, !answerStored {
                let open = await Task.detached(priority: .utility) { SteamLicenceFiles.openInConfig(entries: licences, steamRoot: root) }.value
                licenceOpenWhenAsked = licenceOpenWhenAsked ?? open
                if SteamLicence.answeredInConfig(openWhenAsked: licenceOpenWhenAsked, openNow: open) {
                    answerStored = true
                    GameLog.note("Steam has stored the answer to the licence of \(game.name), at \(GameLog.clock())")
                }
            }
            if event != .licence, watcher.licenceAsked, licenceAnsweredAt == nil, licenceLog.answered() || answerStored {
                licenceAnsweredAt = totalSeconds
                steamQuestionOver(yes: true)
                askingSince = nil
                shownAt = nil
                quietSeconds = 0
                GameLog.note("Steam's licence for \(game.name) is answered with yes, at \(GameLog.clock())")
            }
            switch SteamLicence.afterAnswer(windowsSteam: game.platform != .mac, answeredAgo: licenceAnsweredAt.map { totalSeconds - $0 },
                                            steamWentOn: watcher.wentOnAfterLicence, startedAgain: startedAgainAfterLicence,
                                            answerStored: answerStored) {
            case .nothing:
                break
            case .wait:
                quietSeconds = 0
            case .startAgain:
                startedAgainAfterLicence = true
                quietSeconds = 0
                sentAt = Date()
                GameLog.note("\(game.name) is sent to Steam once more: it doesn't go on by itself after its licence"
                             + (answerStored ? "" : " (the answer isn't to be seen in its record)") + ", at \(GameLog.clock())")
                client = try? await Task.detached(priority: .userInitiated) {
                    try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                        frameLimit: frameLimit, recipe: recipe)
                }.value
                continue
            }
            switch event {
            case .running?:
                launchNeedsConfirmation = false
                return true
            case .needsConfirmation?:
                askingSince = askingSince ?? totalSeconds
                quietSeconds = 0
                launchQuestionTask = watcher.questionTask
            case .licence?:
                // A question from its first word on: the 3 + 5 s below are for steps that answer themselves.
                askingSince = askingSince ?? totalSeconds
                quietSeconds = 0
                if licenceAnsweredAt != nil {
                    licenceLog.askedAgain()
                    licenceOpenWhenAsked = nil
                    answerStored = false
                }
                licenceAnsweredAt = nil
                launchAsksLicence = true
                if !launchNeedsConfirmation {
                    launchNeedsConfirmation = true
                    if game.bottle.isBuiltIn { showSteamWindow() }
                    GameLog.note("Steam shows the licence of \(game.name), at \(GameLog.clock())")
                }
            case .continued?:
                steamQuestionOver(yes: watcher.licenceContinued)
                askingSince = nil
                shownAt = nil
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
                                                frameLimit: frameLimit, recipe: recipe)
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
                                                frameLimit: frameLimit, recipe: recipe)
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
                                                frameLimit: frameLimit, recipe: recipe)
                        }.value
                    }
                    launchPhase = nil
                    quietSeconds = 0
                    continue
                }
                guard let since = askingSince else {
                    // The game's own installers say nothing to this log, however long the player takes over
                    // them. The limit of 15 minutes for the start stands (followsSteam).
                    quietSeconds = watcher.runningInstallScript ? 0 : quietSeconds + 1
                    continue
                }
                // A question that stands: Steam's window first, which runs hidden – some steps go on
                // only once it's shown – and the player only if it still waits (steamQuestionStep).
                switch Self.steamQuestionStep(waited: totalSeconds - since, shownFor: shownAt.map { totalSeconds - $0 }) {
                case .showWindow:
                    shownAt = totalSeconds
                    if game.bottle.isBuiltIn { showSteamWindow() }
                case .askPlayer where !launchNeedsConfirmation:
                    launchNeedsConfirmation = true
                    if game.bottle.isBuiltIn { showSteamWindow() }  // in front again, now for the player
                default:
                    break
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
        let outcome = await epic.update(game, speed: { [weak self] in self?.showUpdateSpeed($0) }) { [weak self] fraction in
            self?.launchPhase = .updating(fraction)
        }
        awaitingSteam = false
        launchPhase = nil
        updateSpeed = nil
        if Task.isCancelled { return false }
        switch outcome {
        case .updated:
            analyses[game.gameID] = nil  // its files changed
            reload(quiet: true)
        case .skipped(.offline):
            noteDuringStart(L10n.t("Epic Games can't be reached – %@ starts without its update.", game.name))
        case .skipped(.busy):
            noteDuringStart(L10n.t("Another Epic download is running – %@ starts now and updates next time.", game.name))
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
    /// `survivesFirstSeconds` sees. `usesD3D9`: from the start's analysis (`insight`).
    private func startDirect(_ game: Game, runner: String?, options: GameOptions, profile: GameProfile?,
                             recipe: StartRecipe, frameLimit: Int, layer: GraphicsLayer, vulkan: Engine.VulkanDriver?,
                             usesD3D9: Bool, handsOff: Bool) async -> Bool {
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
            if !Task.isCancelled { startFailed(game, error) { L10n.t("%@ couldn't start: %@", game.name, RosettaSupport.playerText(error)) } }
            return false
        }
        launchPhase = nil
        guard !Task.isCancelled else { return false }
        let environment = Engine.directLaunchEnvironment(avx: recipe.avx, d3dMetal: layer == .d3dmetal,
                                                         frameLimit: frameLimit, upscaling: options.effectiveUpscaling(profile: profile),
                                                         vulkan: vulkan, antiCheat: handsOff)
        if layer == .d3dmetal {
            let switches = GameEnvironment.wanted(for: game.gameID, profile: profile)
            GameLog.note(GameLog.d3dMetalStart(game.name, environment: environment.merging(switches) { _, game in game },
                                               retina: Engine.retinaModeApplied))
        }
        let process: DetachedProcess
        do {
            process = try await Task.detached(priority: .userInitiated) {
                try Launcher.launchDirect(game, command: command, runnerPath: runner, options: options, profile: profile,
                                          frameLimit: frameLimit, recipe: recipe, environment: environment,
                                          usesD3D9: usesD3D9)
            }.value
        } catch {
            startFailed(game, error) { RosettaSupport.playerText(error) }
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
    private func confirmOnceDrawing(_ game: Game, attempts: [LaunchAttempt], build: EngineBuild?, way: String, recipe: StartRecipe,
                                    logMark: UInt64, startedAt: Date, wasConfirmed: Bool = false) {
        let folders = Self.processFolders([game])
        let installDir = game.installDir
        Task {
            let programs = await Task.detached(priority: .utility) { Set(Engine.executables(in: installDir)) }.value
            var absent = 0
            while true {
                let (text, running) = await Task.detached(priority: .utility) {
                    // Without a process list – or with an old one that doesn't show the game – it counts as running:
                    // its absence would end the watch and mark the way as failed.
                    (GameLog.text(since: logMark), GameProcesses.presence(of: game.id, folders: folders).mayBeRunning)
                }.value
                // Gone for two looks (10 s): a launcher handing over leaves a shorter gap.
                absent = running ? 0 : absent + 1
                let verdict = LaunchHealth.verdict(drewFrames: LaunchHealth.drewFrames(in: text, programs: programs),
                                                   showedPicture: LaunchHealth.showedPicture(game.gameID, since: startedAt),
                                                   running: absent < 2, ranFor: Date().timeIntervalSince(startedAt))
                switch LaunchHealth.afterFirstSeconds(verdict) {
                case .confirm:
                    if !attempts.isEmpty {
                        LaunchHealth.confirm(game.gameID, attempts, recipe: recipe)  // proven for what it was made of (step E4)
                        if !wasConfirmed { StartEvidence.note(.worked, game: game.gameID, way: way) }
                    }
                    if let build { EngineRollback.shared.recordGood(game.gameID, build: build, way: way) }
                    return
                case _ where verdict == .ended:
                    // Past its first seconds without a picture: no evidence against a confirmed way
                    // (most layers log no frames), and no short start either.
                    if wasConfirmed, !attempts.isEmpty { LaunchHealth.noteStart(game.gameID, attempts, short: false) }
                    // Its outcome for the record: ended before it counted as working, with or without a picture.
                    if !attempts.isEmpty {
                        StartEvidence.note(.ended, game: game.gameID, way: way, reason: "ended before it counted as working",
                                           picture: LaunchHealth.showedPicture(game.gameID, since: startedAt),
                                           seconds: Int(Date().timeIntervalSince(startedAt)))
                    }
                    return
                default:
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    /// Whether the game is still running `LaunchHealth.failureWindow` seconds after it started.
    /// A launcher handing over to the game leaves a gap of a few seconds, so only a longer absence
    /// counts as the game having ended (FirstSecondsWatch) – by a list asked for just now; a look without
    /// an answer counts for neither, and a watch that gets none says `unknown`. A game whose Direct3D
    /// layer failed (GameLog) is ended here: it would only sit behind its own error box.
    /// `layer`: the way it started with – only that layer's failure ends it (GameLog.graphicsFailed).
    /// `ended` at once when a new start calls the watch off: nothing is known then.
    /// When the first seconds' watch last saw a game running (`ownQuestionEndStands`).
    private var firstSecondsRunning: [String: Date] = [:]

    private func survivesFirstSeconds(_ game: Game, logMark: UInt64? = nil, layer: GraphicsLayer? = nil,
                                      startedAt: Date? = nil) async -> FirstSecondsWatch.Verdict {
        let folders = Self.processFolders([game])
        let installDir = game.installDir
        let started = Date()
        var watch = FirstSecondsWatch()
        var looks = 0
        while watch.continues(after: Date().timeIntervalSince(started)) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return .ended }
            let presence = await Task.detached(priority: .utility) { GameProcesses.presence(of: game.id, folders: folders) }.value
            if case .running = presence { firstSecondsRunning[game.id] = Date() }
            if let verdict = watch.look(presence) { return verdict }
            // A crash report of this start: the game is dead, whatever still runs. Unreal's crash reporter
            // stays about a minute and holds up the next way (Hogwarts Legacy, 9.11.2026: 80 s a way).
            looks += 1
            if let startedAt, looks % 2 == 0, !LaunchHealth.showedPicture(game.gameID, since: startedAt) {
                let crashed = await Task.detached(priority: .utility) {
                    !GameLog.crashReports(installDir: installDir, since: startedAt).isEmpty
                }.value
                if crashed {
                    GameLog.note("\(game.name) left a crash report in its first seconds, at \(GameLog.clock())")
                    await endWhatsLeft(of: game, folders: folders)
                    return .ended
                }
            }
            if case .running(let pid) = presence, let logMark, let layer, GameLog.graphicsFailed(since: logMark, layer: layer) {
                kill(pid, SIGTERM)
                // Steam has to see it gone before the next way can start.
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { break }
                    if await Task.detached(priority: .utility, operation: { Self.runningGames(folders)[game.id] }).value == nil { break }
                }
                return .ended
            }
        }
        return watch.verdictAtEnd
    }

    /// Ends what's left of a start that failed. Steam has to see it gone before the next way can start.
    private func endWhatsLeft(of game: Game, folders: [String: String]) async {
        for _ in 0..<15 {
            let rest = await Task.detached(priority: .utility) { GameProcesses.presence(of: game.id, folders: folders) }.value
            guard case .running(let pid) = rest, !Task.isCancelled else { return }
            kill(pid, SIGTERM)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Waits for the first picture of a way not proven yet. Nil once there is one, or the wait is called off;
    /// otherwise why it didn't start: gone without one, or hung (PictureWatch).
    private func waitForPicture(_ game: Game, logMark: UInt64, startedAt: Date) async -> String? {
        let installDir = game.installDir
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        let folders = Self.processFolders([game])
        let programs = await Task.detached(priority: .utility) { Set(Engine.executables(in: installDir)) }.value
        var watch = PictureWatch()
        var absent = 0
        while true {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return nil }
            if LaunchHealth.showedPicture(game.gameID, since: startedAt) { return nil }
            let seen = await Task.detached(priority: .utility) {
                let pids = GameProcesses.lookup().freshValue.map { GameProcesses.targets(windows: marker, mac: folder, in: $0) } ?? []
                return (log: GameLog.text(since: logMark), presence: GameProcesses.presence(of: game.id, folders: folders),
                        window: GameProcesses.windowSize(Set(pids)), cpu: GameProcesses.cpuSeconds(pids))
            }.value
            if LaunchHealth.drewFrames(in: seen.log, programs: programs) || PictureWatch.isPicture(windowSize: seen.window) { return nil }
            if case .running = seen.presence { firstSecondsRunning[game.id] = Date() }
            absent = seen.presence == .gone ? absent + 1 : 0
            if absent >= 2 {  // two looks: a launcher handing over leaves a shorter gap
                GameLog.note("\(game.name) ended without a picture, at \(GameLog.clock())")
                return "ended without a picture"
            }
            let asked = windowsQuestion?.id == game.id || launchNeedsConfirmation || saveChoice != nil
                || (GameOverlay.isOpen && !GameOverlay.asksAboutStart)
            if watch.look(span: 5, cpu: seen.cpu, playerAsked: asked) == .hung {
                GameLog.note("\(game.name) shows no picture and doesn't get anywhere: the next way, at \(GameLog.clock())")
                if GameOverlay.asksAboutStart { GameOverlay.close() }
                await endWhatsLeft(of: game, folders: folders)
                return "hung without a picture"
            }
        }
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
        let profile = await ProfileStore.shared.profile(for: game.gameID)
        // What others ran it with orders the ways too, where it fits and no profile names a layer:
        // Highball's Mac database, what PCGamingWiki says it can draw with, then AppleGamingWiki's reports.
        let report = await ProfileStore.shared.reportedWay(steamAppID: game.steamAppID)
            ?? macSources.directXHint(steamAppID: game.steamAppID) ?? macSources.entry(for: game)?.weightedHint
        // … after what games of its sort have proven on this Mac.
        let sort = await Engine.offMain { StartEvidence.sortScores(for: analysis.kind, excluding: game.gameID.key) }
        let (attempts, hint, _) = LaunchHealth.attempts(for: analysis, profile: profile, hint: report, game: game.gameID,
                                                        preset: GameOptionsStore.load(game.gameID).preset, sort: sort.mapValues(\.points))
        let insight = GameInsight(analysis: analysis, attempts: attempts, hint: hint,
                                  hintSource: hint == nil ? nil : report?.source,
                                  sortGames: profile?.graphics == nil ? attempts.first.flatMap { sort[$0.id]?.games } ?? 0 : 0)
        if insights[game.gameID] != insight { insights[game.gameID] = insight }
        return insight
    }

    /// How well it runs on a Mac, from the profile list and what this Mac learned about it.
    func compatibility(of game: Game) -> Compatibility {
        // Epic's and GOG's games by the same game on Steam, whose profile it is.
        Compatibility.of(game, profile: game.steamAppID.flatMap { profiles[$0] }, analysis: insights[game.gameID]?.analysis,
                         insight: insights[game.gameID], reported: macSources.entry(for: game))
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
                errorMessage = L10n.t("%@ couldn't be added to Applications: %@", game.name, RosettaSupport.playerText(error))
            }
        }
    }

    /// Bumped when a game's app was added, so its button turns into "Show in Applications".
    @Published private(set) var shortcutsChanged = 0

    /// After a failed start: every way again from the first, as if the game were new.
    func startOver(_ failed: FailedLaunch) {
        failedLaunch = nil
        beginAnew(failed.game)
        play(failed.game)
    }

    /// After a failed start: "Most compatible" from now on, starting again with its safest way.
    func startMostCompatible(_ failed: FailedLaunch) {
        failedLaunch = nil
        GameOptionsStore.choose(.compatible, for: failed.game.gameID)
        beginAnew(failed.game)
        play(failed.game)
    }

    /// As if the game were new: its ways from the first (LaunchHealth.reset), and nothing kept of what earlier
    /// starts taught (LearnedFixes.forget) – the two buttons after a start that failed are how a player gets rid
    /// of a remedy that was learned and didn't help. What went is in the log.
    private func beginAnew(_ game: Game) {
        LaunchHealth.reset(game.gameID)
        let had = LearnedFixes.forget(game.gameID)
        if had != StartRecipe.Learned() {
            GameLog.note("\(game.name) starts over: what earlier starts taught is forgotten – \(had.summary)")
        }
    }

    /// L1/R1 in Settings: a tab to the left or right (SettingsView takes it, PadRules.settingsTab).
    struct SettingsTabStep: Equatable {
        var count = 0
        var shoulder = PadPart.r1
    }

    @Published private(set) var settingsTabStep = SettingsTabStep()

    func stepSettingsTab(_ shoulder: PadPart) {
        settingsTabStep = SettingsTabStep(count: settingsTabStep.count + 1, shoulder: shoulder)
    }

    /// The tab Settings opens on (set by `openSettings`).
    private(set) var settingsStart = SettingsView.Tab.general

    func openSettings(tab: SettingsView.Tab = .general) {
        NSApp.windows.first { $0.title == "Nightforge" }?.makeKeyAndOrderFront(nil)
        settingsStart = tab
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

    /// What AppleGamingWiki says, when there's no copy yet (the first run): the first start waits a
    /// few seconds for this run's download, once (`AGWStore.beforeFirstStart`), so it can already take
    /// the way the reports point to; offline it starts without, and the list comes in the background.
    private func macSourcesAtHand() async {
        guard macSources.isEmpty else { return }
        await AGWStore.shared.beforeFirstStart()
        let sources = await AGWStore.shared.current()
        if sources != macSources { macSources = sources }
    }

    /// "Didn't start" in "Welcome back": the way it took gave the player nothing, so with "Automatic"
    /// the next start goes the next way, as after a start that ended at once (LaunchHealth). True when it does.
    func wayDidntWork(_ game: Game) async -> Bool {
        guard game.bottle.isBuiltIn, game.platform == .windows, let insight = await insight(of: game) else { return false }
        let profile = await ProfileStore.shared.profile(for: game.gameID)
        let options = GameOptionsStore.load(game.gameID).resolved(refreshRate: GameDisplay.screen?.maximumFramesPerSecond ?? 60,
                                                                  profile: profile)
        let attempts = LaunchHealth.ladder(insight.attempts, preset: options.preset, profile: profile, hint: insight.hint)
        guard options.graphics == .automatic, attempts.count > 1 else { return false }
        _ = LaunchHealth.advance(game.gameID, attempts)
        return true
    }

    /// Opens the report form for how the game ran, filled in, in the browser (CompatReport).
    func shareReport(_ game: Game, rating: GameRating) {
        let options = GameOptionsStore.load(game.gameID)
        let url = CompatReport.url(game: game, rating: rating, preset: game.platform == .windows ? options.preset : nil,
                                   engine: game.platform == .windows && game.bottle.isBuiltIn ? EngineRollback.shared.history().current : nil,
                                   chip: ProblemReport.chip, macOS: ProblemReport.osVersion, nightforge: Updater.currentVersion)
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Opens a pre-filled problem report for the game in the browser.
    func reportProblem(for game: Game, tried: [String] = []) {
        Task {
            ProblemReport.open(game: game, insight: await insight(of: game),
                               profile: await ProfileStore.shared.profile(for: game.gameID), tried: tried)
        }
    }

    /// Steam starts the game in the background, and since macOS 14 an app can't push itself to
    /// the front. Nightforge is the active app at this point, so it hands activation over as soon
    /// as the game shows its window (Wine makes it a regular app then) – before quitting or hiding.
    private func bringToFront(_ game: Game) async {
        let folders = Self.processFolders([game])
        var absent = 0
        for _ in 0..<60 {
            let presence = await Task.detached(priority: .utility) { GameProcesses.presence(of: game.id, folders: folders) }.value
            // Only a list asked for just now says it is gone; a look without an answer counts for neither.
            switch presence {
            case .gone: absent += 1
            case .running: absent = 0
            case .unknown: break
            }
            if absent >= 10 { return }  // gone again: it crashed before showing a window
            let pid: pid_t? = { if case .running(let pid) = presence { return pid } else { return nil } }()
            if let pid, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                guard NSApp.isActive else { return }  // the player has moved on to something else
                // Already there while macOS changes to the game's Space (on a TV it has one of its own).
                GameBackdrop.show(game.name, on: GameDisplay.gameScreen) { [weak self] in self?.gameOnStage == true }
                InputRouter.hidePointerForGame()
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [.activateAllWindows])
                try? await Task.sleep(for: .milliseconds(600))
                if app.isActive { return }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    enum SteamQuestionStep: Equatable { case wait, showWindow, askPlayer }

    /// What a start does about a question of Steam's that has stood `waited` seconds, its window
    /// shown `shownFor` seconds ago (nil: not yet). Steam logs routine steps as questions too and
    /// answers them within a second or two. Some – ShowInterstitials – go on only once its hidden
    /// window has been shown, and then within 0–2 s with nobody there: of 129 such waits in the
    /// Windows Steam's log up to 2.11., all over 4 s came after Nightforge had shown the window;
    /// Left 4 Dead 2 went on 1 s after it, at 5 s. Saying "Confirm in the Steam window" at 3 s took
    /// the curtain away for those, and the game test called the start off. So the window comes at
    /// 3 s as before, and the player is asked – curtain away, Steam's window in front – only when
    /// the question still stands `steamAnswerGrace` seconds later: a real one (an EULA, launch
    /// options, the Wukong benchmark's notice) shows that much later.
    nonisolated static func steamQuestionStep(waited: Int, shownFor: Int?) -> SteamQuestionStep {
        guard let shownFor else { return waited >= 3 ? .showWindow : .wait }
        return shownFor >= steamAnswerGrace ? .askPlayer : .wait
    }

    nonisolated static let steamAnswerGrace = 5

    /// How long a start waits with no word from Steam, and for Steam altogether.
    nonisolated static let steamSilencePatience = 120
    nonisolated static let steamStartPatience = 900
    /// How often a start looks whether the Steam with a standing question still runs, in seconds.
    nonisolated static let steamLookEvery = 10

    /// Whether a start goes on following Steam. The time a question of Steam's stands is the player's
    /// (`onPlayerSeconds`) and doesn't count: a licence left open for 20 minutes used to end in "Steam
    /// didn't respond" with its window still there, and a yes after 15 minutes would have ended the start
    /// at once. B leads out of such a wait, and a Steam that ends takes its question with it.
    nonisolated static func followsSteam(quietSeconds: Int, seconds: Int, onPlayerSeconds: Int) -> Bool {
        quietSeconds < steamSilencePatience && seconds - onPlayerSeconds < steamStartPatience
    }

    /// Steam asked again, unless the player has left the start: neither the pause before it nor the look at the
    /// processes stops for that, and Steam would start the game, or ask which way, with nobody there.
    nonisolated static func asksAgain(cancelled: Bool, send: () -> Void) -> Bool {
        guard !cancelled else { return false }
        send()
        return true
    }

    /// Brings Steam's main window, with the question it's waiting on, in front of Nightforge.
    func showSteamWindow() {
        steamWindowShown = true
        Task {
            guard let wine = await Engine.installedWine() else { return }
            await SteamWindow.reveal()  // hidden after its last question (hideSteamWindow)
            await Engine.showSteamWindow(wine)
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
        if game.provider == .battlenet { return false }  // the client's to remove (BattleNetStore)
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
                errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, RosettaSupport.playerText(error))
            }
        }
    }

    func requestUninstall(_ game: Game? = nil) {
        guard let game = game ?? selected, canUninstall(game) else { return }
        pendingUninstall = game
    }

    func askPower(_ entry: PowerMenu.Entry) {
        closeLauncherMenu()
        pendingPower = entry
    }

    func confirmPower() {
        guard let entry = pendingPower else { return }
        pendingPower = nil
        switch entry {
        case .quitNightforge: Quit.now(by: "the small menu")
        case .sleepMac:
            do { try PowerMenu.sleepMac() } catch { GameLog.note("Couldn't put the Mac to sleep: \(error.localizedDescription)") }
        }
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
            errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, RosettaSupport.playerText(error))
        }
    }

    // MARK: - A drive that's gone

    /// Nothing runs, downloads, moves or uninstalls: the lists of what's installed where can change.
    var canForgetDrive: Bool {
        move == nil && uninstallingID == nil && launchingID == nil && !anyRunning(.windows) && !anyRunning(.mac)
            && !epic.isBusy && !gog.isBusy && downloads.isEmpty
    }

    /// Settings › Storage's "Forget Drive": `name` isn't unplugged for a while, it's gone. Its games count
    /// as not installed then (`only`: just that one's copy), and download again. Steam is stopped for it, the
    /// way a move does, and comes back. Only the stores' lists change; the Windows environment and its saves stay.
    @discardableResult
    func forgetDrive(_ name: String, only game: Game? = nil) async -> Bool {
        guard canForgetDrive else {
            errorMessage = L10n.t("Nothing can be forgotten while a game runs or a download or move is under way – wait a moment.")
            return false
        }
        let appID = game?.provider == .steam ? game?.appID : nil
        let bottle = Engine.bottle, macBottle = MacSteam.bottle
        let steamRoot = Engine.steamRoot, macRoot = MacSteam.root
        let wantsWindows = (game == nil || (game?.provider == .steam && game?.platform == .windows))
            && SteamLibraries.holds(drive: name, appID: appID, steamRoot: steamRoot, bottle: bottle)
        let wantsMac = (game == nil || (game?.provider == .steam && game?.platform == .mac))
            && SteamLibraries.holds(drive: name, appID: appID, steamRoot: macRoot, bottle: macBottle)
        do {
            if wantsWindows, let wine = await Engine.installedWine() {
                let wasRunning = Engine.isSteamRunning
                try await Engine.stopSteam(wine, endWait: Engine.filesEndWait)
                if let still = await Engine.steamStillThere() { throw still }
                defer { if wasRunning { Task { try? await Engine.restartSteamInBackground(wine) } } }
                try await Engine.offMain { _ = try SteamLibraries.forget(drive: name, appID: appID, steamRoot: steamRoot, bottle: bottle) }
            }
            if wantsMac {
                let wasRunning = MacSteam.isRunning, ours = MacSteam.startedByNightforge
                if wasRunning { await MacSteam.quit() }
                if let still = await Engine.steamStillThere(running: { MacSteam.isRunning }) { throw still }
                defer {
                    if wasRunning {
                        MacSteam.start(visible: !ours)  // the player's own Steam comes back as they had it
                        MacSteam.startedByNightforge = ours
                    }
                }
                try await Engine.offMain { _ = try SteamLibraries.forget(drive: name, appID: appID, steamRoot: macRoot, bottle: macBottle) }
            }
        } catch {
            errorMessage = L10n.t("%@ couldn't be forgotten: %@", name, RosettaSupport.playerText(error))
            return false
        }
        if game == nil || game?.provider == .epic { epic.forgetDrive(name, only: game?.gameID.id) }
        if game == nil || game?.provider == .gog { gog.forgetDrive(name, only: game?.gameID.id) }
        reload(quiet: true)
        refreshLowSpace()
        return true
    }

    /// The game page's "Download Again": a game on a drive that isn't plugged in is forgotten there and
    /// downloads as any other, with the usual check for room and the choice of where it goes.
    func redownload(_ game: Game) {
        guard game.onUnpluggedDrive, let drive = game.missingDrive else { return }
        Task {
            guard await forgetDrive(drive, only: game) else { return }
            // The scan after it says where the game would go now; its old place was on the drive.
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                if let fresh = allGames.first(where: { $0.id == game.id }), fresh.missingDrive == nil, fresh.install == .notInstalled {
                    downloadIfRoom(fresh)
                    return
                }
            }
        }
    }

    /// Opens Steam in Nightforge's prefix, e.g. to install a game.
    func openSteam() {
        guard rosettaReady(for: "Steam's window", then: { [weak self] in self?.openSteam() }) else { return }
        Task {
            guard let wine = await Engine.installedWine() else { return }
            do {
                try await Engine.startSteamOffMain(wine)
            } catch {
                errorMessage = RosettaSupport.playerText(error)
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

extension NSApplication {
    /// In front for macOS. Not `isActive`: that says yes while a panel that doesn't activate
    /// Nightforge has the keys – the overlay's, with the game in front (probe on 1.11.).
    var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Nightforge to the front because the player asked: Go to Nightforge, a game's end. Since
    /// macOS 14 asking politely from behind loses to any app with a window in the Space shown (on
    /// 1.11. the Claude app on the TV took the front, the game stayed behind it), so it's activated
    /// regardless – and opened through Launch Services as well, which unhides it and changes to
    /// its window's Space. `then` once that's done.
    func comeToFront(then: (@MainActor () -> Void)? = nil) {
        activate(ignoringOtherApps: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in then?() }
        }
    }
}
