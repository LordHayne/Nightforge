import AppKit

/// One store as the player sees it: the one state both launcher menus read (the four cards,
/// `LauncherPage`, and the small menu at the top right, `LauncherMenu`).
struct LauncherState: Equatable, Identifiable {
    /// How its sign-in stands.
    enum Account: Equatable {
        case notSignedIn
        /// Its sign-in is open, or its answer is on its way.
        case signingIn
        /// `name` where the store gives one; Battle.net's files only hold the mail address, which stays out of it.
        case signedIn(name: String?)
        /// The store ended the sign-in. The games stay.
        case signedOut
        /// Signed in, but the last update didn't get through. The games still play.
        case unreachable(StoreSync)
        /// Battle.net for Mac isn't on this Mac.
        case noClient
    }

    /// What a press on the card, or on the row's button, does.
    enum Action: Equatable {
        case signIn, signInAgain, retry, manage, getClient
    }

    /// What the state is made from: read from the store or its client (`LibraryModel.refreshLaunchers`).
    struct Facts: Equatable {
        /// Its sign-in is open or being finished.
        var signingIn = false
        /// The store's games belong in the library.
        var connected = false
        /// The store or its client still holds the sign-in.
        var signedIn = false
        var clientMissing = false
        var name: String?
        var sync = StoreSync()
        var games = 0
    }

    let provider: Provider
    var account: Account
    var games: Int

    var id: String { provider.rawValue }

    init(_ provider: Provider, account: Account = .notSignedIn, games: Int = 0) {
        self.provider = provider
        self.account = account
        self.games = games
    }

    init(_ provider: Provider, facts: Facts) {
        self.init(provider, account: Self.account(facts), games: facts.games)
    }

    private static func account(_ facts: Facts) -> Account {
        if facts.signingIn { return .signingIn }
        if facts.clientMissing { return .noClient }
        if !facts.connected { return .notSignedIn }
        if !facts.signedIn || facts.sync.state == .signedOut { return .signedOut }
        if facts.sync.failed { return .unreachable(facts.sync) }
        return .signedIn(name: facts.name)
    }

    /// Counted in the pill's "3/4".
    var isSignedIn: Bool {
        switch account {
        case .signedIn, .unreachable: return true
        case .notSignedIn, .signingIn, .signedOut, .noClient: return false
        }
    }

    /// The card's line under the store's name.
    var status: String {
        switch account {
        case .notSignedIn: return L10n.t("Not signed in")
        case .signingIn: return L10n.t("Waiting for sign-in …")
        case .signedIn(let name?): return L10n.t("Signed in – %@", name)
        case .signedIn(nil): return L10n.t("Signed in")
        case .signedOut: return L10n.t("Signed out")
        case .unreachable: return L10n.t("Not reachable")
        case .noClient: return L10n.t("Not installed")
        }
    }

    /// The card's quieter line.
    var detail: String {
        switch account {
        case .notSignedIn, .signingIn: return pitch
        case .signedIn: return games == 1 ? L10n.t("1 game in your library") : L10n.t("%ld games in your library", games)
        case .signedOut: return L10n.t("Your games stay here. Sign in again to download and to play online.")
        case .unreachable(let sync): return StoreSyncText.text(provider: provider, sync: sync) ?? ""
        case .noClient: return L10n.t("Battle.net for Mac isn't on this Mac yet. Nightforge shows what it has installed.")
        }
    }

    /// What the store brings. Battle.net's says what's really there: the Mac client's games. Windows
    /// Battle.net isn't wired in, and Overwatch comes through Steam.
    private var pitch: String {
        switch provider {
        case .steam: return L10n.t("Your Steam library, Mac and Windows versions alike")
        case .epic: return L10n.t("Your Epic games, Nightforge downloads them itself")
        case .gog: return L10n.t("Games without copy protection, Nightforge downloads them itself")
        case .battlenet: return L10n.t("Shows what Battle.net for Mac has installed: WoW, Hearthstone and more. Overwatch runs through Steam.")
        }
    }

    /// The small menu's line under the store's name.
    var menuStatus: String {
        let count = games == 1 ? L10n.t("1 game") : L10n.t("%ld games", games)
        switch account {
        case .signedIn: return L10n.t("Signed in – %@", count)
        case .unreachable: return L10n.t("Not reachable – %@", count)
        case .signedOut: return L10n.t("Signed out – %@", count)
        case .notSignedIn, .signingIn, .noClient: return status
        }
    }

    /// The card's button; nil while its sign-in is being finished.
    var action: Action? {
        switch account {
        case .notSignedIn: return .signIn
        case .signingIn: return nil
        case .signedIn, .unreachable: return .manage
        case .signedOut: return .signInAgain
        case .noClient: return .getClient
        }
    }

    /// The small menu's button; a signed-in store's row has none and leads to its card.
    var quickAction: Action? {
        switch account {
        case .signedIn: return nil
        case .unreachable: return .retry
        case .notSignedIn, .signingIn, .signedOut, .noClient: return action
        }
    }

    /// The card's button says it in full.
    var actionLabel: String { action.map(label) ?? status }

    func label(_ action: Action) -> String {
        switch action {
        case .signIn: return L10n.t("Sign In to %@", provider.label)
        case .signInAgain: return L10n.t("Sign In Again")
        case .retry: return L10n.t("Try Again")
        case .manage: return L10n.t("Manage")
        case .getClient: return L10n.t("Get %@", provider.label)
        }
    }

    /// The small menu's button, in the room a row has.
    func shortLabel(_ action: Action) -> String {
        switch action {
        case .signIn, .signInAgain: return L10n.t("Sign In")
        case .retry: return L10n.t("Try Again")
        case .manage: return L10n.t("Manage")
        case .getClient: return L10n.t("Get")
        }
    }

    /// Where the pad's highlight marks the card.
    static func cardID(_ provider: Provider) -> String { "launcher.\(provider.rawValue)" }
    /// And the small menu's row.
    static func rowID(_ provider: Provider) -> String { "launcher.row.\(provider.rawValue)" }

    /// Plain type in place of a logo: the app has none of the stores' marks, and doesn't draw any.
    var letter: String { String(provider.label.prefix(1)) }
}

/// The two stores that live in a client of their own, as their files show them. Read off the main
/// thread (`read`), like everything that touches the disk here.
struct LauncherClients: Equatable {
    var steamSignedIn = false
    /// The name Steam shows; never the login name.
    var steamName: String?
    var battleNetInstalled = false
    var battleNetSignedIn = false

    nonisolated static func read() -> LauncherClients {
        var clients = LauncherClients()
        clients.steamSignedIn = Engine.isSteamSignedIn || MacSteam.hasSignedIn
        clients.steamName = SteamLogin.personaName(steamRoot: Engine.steamRoot) ?? SteamLogin.personaName(steamRoot: MacSteam.root)
        clients.battleNetInstalled = BattleNetClient.app != nil
        clients.battleNetSignedIn = BattleNetClient.isSignedIn()
        return clients
    }
}

/// Blizzard's Mac client, as far as a sign-in goes: it stays Blizzard's. Password and two-factor
/// code stay in its window, and Nightforge only reads which state its sign-in was last in.
enum BattleNetClient {
    nonisolated static let bundleID = "net.battle.app"
    /// Blizzard's page for the client, for a Mac that hasn't got it.
    nonisolated static let downloadPage = URL(string: "https://download.battle.net/en-us/desktop")!

    nonisolated static var app: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    nonisolated private static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Battle.net/Logs", isDirectory: true)
    }

    /// Whether the newest client start that says so has the player. A start that hasn't got that far
    /// yet (or the short log every start writes beside its real one) says nothing, and the one before counts.
    nonisolated static func isSignedIn(logs: URL? = nil) -> Bool {
        let folder = logs ?? Self.logs
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // Their names hold the time they were started.
        for name in names.filter({ $0.hasPrefix("battle.net-") && $0.hasSuffix(".log") }).sorted().reversed().prefix(6) {
            // Bytes it can't read as text mustn't hide the sign-in, so not `String(contentsOf:)`.
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let signedIn = signedIn(log: String(decoding: data, as: UTF8.self)) else { continue }
            return signedIn
        }
        return false
    }

    /// The account loaded: the client has the player, after its sign-in page or with a remembered
    /// sign-in, which shows no page at all (7.11.). At its end the client writes "Incomplete": that's
    /// it shutting down, no sign-out.
    nonisolated static let accountReady = "Account manager state has changed to: Ready"
    /// Its sign-in page asks: "Login" and "LoginCredential". Its other states say nothing: "Done" and
    /// "None" come and go while it hands over, and it loads a fresh sign-in page behind a finished one.
    nonisolated static let pageAsks = "UAuth: browser state changed: Login"

    /// What a client log says of the sign-in, by whichever of the two came last: true signed in,
    /// false asked and not through, nil nothing either way. Only these two lines are looked for: the
    /// ones around them can hold the account's mail address and country, and the log is never kept.
    nonisolated static func signedIn(log: String) -> Bool? {
        let ready = log.range(of: accountReady, options: .backwards)?.lowerBound
        let asks = log.range(of: pageAsks, options: .backwards)?.lowerBound
        switch (ready, asks) {
        case let (ready?, asks?): return ready > asks
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return nil
        }
    }

    /// Its window, for the sign-in, or in front again when it's up already.
    @MainActor
    static func show() {
        guard let app else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Out of sight, where it goes on running.
    @MainActor
    static func hide() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.hide() }
    }
}

extension LibraryModel {
    /// The stores' state, fresh from their files. Called whenever it may have moved (a scan, a store
    /// changing, Nightforge coming back to the front): the views only read `launchers`.
    func refreshLaunchers() {
        launcherRefresh?.cancel()
        launcherRefresh = Task { [weak self] in
            let clients = await Engine.offMain { LauncherClients.read() }
            guard !Task.isCancelled, let self else { return }
            self.launcherClients = clients
            // Signed in on this Mac and never disconnected: its games come in by themselves.
            if !self.battleNet.isLinked,
               BattleNetStore.links(linked: false, unlinked: self.battleNet.wasUnlinked, clientSignedIn: clients.battleNetSignedIn) {
                self.battleNet.link()
                self.reload(quiet: true)
            }
            self.updateLaunchers()
        }
    }

    /// A store of Nightforge's own or the library changed, which a download does many times a
    /// second: the state follows at most three times a second, and the clients' files stay unread.
    func storeChanged() {
        guard launcherUpdate == nil else { return }
        launcherUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.launcherUpdate = nil
            self?.updateLaunchers()
        }
    }

    private func updateLaunchers() {
        let states = Provider.allCases.map { LauncherState($0, facts: launcherFacts($0, clients: launcherClients)) }
        if states != launchers { launchers = states }
    }

    private func launcherFacts(_ provider: Provider, clients: LauncherClients) -> LauncherState.Facts {
        var facts = LauncherState.Facts(signingIn: signingIn == provider, games: visibleCount(of: provider))
        switch provider {
        case .steam:
            facts.connected = clients.steamSignedIn
            facts.signedIn = clients.steamSignedIn
            facts.name = clients.steamName
        case .epic:
            facts.signingIn = facts.signingIn || epic.connecting
            facts.connected = epic.isConnected
            facts.signedIn = epic.isSignedIn
            facts.name = epic.accountName
            facts.sync = epic.sync
        case .gog:
            facts.signingIn = facts.signingIn || gog.connecting
            facts.connected = gog.isConnected
            facts.signedIn = gog.isSignedIn
            facts.name = gog.accountName
            facts.sync = gog.sync
        case .battlenet:
            facts.connected = BattleNetStore.links(linked: battleNet.isLinked, unlinked: battleNet.wasUnlinked,
                                                   clientSignedIn: clients.battleNetSignedIn)
            facts.signedIn = clients.battleNetSignedIn
            facts.clientMissing = !clients.battleNetInstalled
        }
        return facts
    }

    var signedInLaunchers: Int { launchers.filter(\.isSignedIn).count }

    /// The four cards show, on their own page or in the first start.
    var showsLauncherCards: Bool {
        route == .launchers || (route == .home && showsFirstStart && setup.stage == .launchers)
    }

    /// The highlight goes on `provider`'s card, else the first store still to sign in to.
    func focusLauncherCards(_ provider: Provider? = nil) {
        let target = provider ?? lastLauncher ?? launchers.first { $0.action == .signIn }?.provider ?? .steam
        PadFocus.shared.focus(LauncherState.cardID(target))
    }

    /// The small menu at the top right. By pad the highlight starts on its first store to sign in
    /// to; by mouse there's none, and the menu closes to what was highlighted before.
    func openLauncherMenu(byPad: Bool = false) {
        guard !launcherMenuOpen else { return }
        let focus = PadFocus.shared
        launcherMenuReturn = focus.focused
        launcherMenuOpen = true
        refreshLaunchers()
        if byPad {
            focus.focus(LauncherState.rowID(launchers.first { $0.quickAction != nil }?.provider ?? .steam))
        } else {
            focus.clear()
        }
    }

    /// Esc, B, a click beside it.
    func closeLauncherMenu() {
        guard launcherMenuOpen else { return }
        launcherMenuOpen = false
        if let back = launcherMenuReturn { PadFocus.shared.focus(back) } else { PadFocus.shared.clear() }
        launcherMenuReturn = nil
    }

    /// The card's or the row's button.
    func perform(_ action: LauncherState.Action, on provider: Provider) {
        lastLauncher = provider
        switch action {
        case .signIn, .signInAgain: connect(provider)
        case .retry: refreshStores(force: true)
        case .manage: managedLauncher = provider
        case .getClient: NSWorkspace.shared.open(BattleNetClient.downloadPage)
        }
    }

    /// A signed-in store's row: its card, where it's managed.
    func showLauncher(_ provider: Provider) {
        closeLauncherMenu()
        lastLauncher = provider
        openLaunchers()
    }

    /// Opens the store's sign-in, at once.
    func connect(_ provider: Provider) {
        switch provider {
        case .steam: connectSteam()
        case .epic: connectEpic()
        case .gog: connectGOG()
        case .battlenet: connectBattleNet()
        }
    }

    /// Steam's own window, which Steam signs in in. Nightforge's Steam isn't there yet on a Mac that
    /// never went through the first start: that sets it up and leads to the same window.
    private func connectSteam() {
        guard Engine.isSteamInstalled else {
            goHome()
            setup.begin()
            return
        }
        signingIn = .steam
        Task {
            await SteamWindow.reveal()
            setup.reopenSteam()
        }
        watchClientSignIn(.steam)
    }

    /// Battle.net for Mac's own window. A client that's signed in already only has to be linked.
    private func connectBattleNet() {
        Task {
            let clients = await Engine.offMain { LauncherClients.read() }
            guard clients.battleNetInstalled else { return }
            if clients.battleNetSignedIn {
                clientSignedIn(.battlenet)
                return
            }
            signingIn = .battlenet
            BattleNetClient.show()
            watchClientSignIn(.battlenet)
        }
    }

    /// A client signs in in its own window: its files tell when it's done.
    private func watchClientSignIn(_ provider: Provider) {
        signInWatch?.cancel()
        signInWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let clients = await Engine.offMain { LauncherClients.read() }
                guard !Task.isCancelled, let self, self.signingIn == provider else { return }
                if provider == .steam ? clients.steamSignedIn : clients.battleNetSignedIn {
                    self.clientSignedIn(provider)
                    return
                }
            }
        }
    }

    /// The client has the player: it goes out of sight, and Nightforge is in front with the new state.
    private func clientSignedIn(_ provider: Provider) {
        signingIn = nil
        switch provider {
        case .steam:
            // As after the first start: Steam opens its big window now, and works in the background.
            Task {
                guard let wine = await Engine.installedWine() else { return }
                try? await Engine.restartSteamInBackground(wine)
            }
        case .battlenet:
            battleNet.link()
            BattleNetClient.hide()
        case .epic, .gog:
            break
        }
        comeForward()
        reload(quiet: true)
        refreshLaunchers()
        Toasts.shared.show(L10n.t("%@ is connected – your games are in the library", provider.label))
    }

    /// B or Esc on the stage: back to where it was opened from, and nothing has changed.
    func cancelSignIn() {
        guard let provider = signingIn else { return }
        signInWatch?.cancel()
        switch provider {
        case .epic, .gog:
            signInPageDone(provider, code: nil)
        case .steam:
            signingIn = nil
            Task { await SteamWindow.hide() }
        case .battlenet:
            signingIn = nil
            BattleNetClient.hide()
        }
        comeForward()
    }

    /// Brings a client's own window forward again, over the curtain.
    func showSignInWindow(_ provider: Provider) {
        if provider == .steam { setup.reopenSteam() } else { BattleNetClient.show() }
    }

    /// Battle.net's games leave the library; the client stays as it is.
    func disconnectBattleNet() {
        battleNet.unlink()
        reload(quiet: true)
        refreshLaunchers()
    }

    /// The manage dialog's "Disconnect".
    func disconnect(_ provider: Provider) {
        switch provider {
        case .epic: disconnectEpic()
        case .gog: disconnectGOG()
        case .battlenet: disconnectBattleNet()
        case .steam: break  // Steam's account is Steam's own
        }
    }

    /// The manage dialog's way to the client's own window.
    func openClient(_ provider: Provider) {
        switch provider {
        case .steam: openSteam()
        case .battlenet: BattleNetClient.show()
        case .epic, .gog: break
        }
    }
}
