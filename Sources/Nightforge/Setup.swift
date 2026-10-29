import AppKit
import Foundation

/// The first start, end to end: a welcome, the one-button setup – every step checks whether it's
/// already done, so pressing the button again after a failure (or on a second Mac start) just
/// carries on where it stopped – then the library check and what it found.
@MainActor
final class SetupModel: ObservableObject {
    /// The page the first start shows.
    enum Stage: Equatable {
        case welcome
        /// The setup's own steps; `phase` says where it is.
        case checklist
        /// After the sign-in: Steam sends the library, and every game is looked up.
        case checking(LibraryCheck)
        /// How many of the games run here, then "Let's Play".
        case reveal(LibraryReveal)
    }

    /// What Return or A, and Esc or B, do on the page now.
    enum Action: Equatable {
        case begin, installRosetta, showSteam, retry, skip, play

        var label: String {
            switch self {
            case .begin: return L10n.t("Let's Go")
            case .installRosetta: return L10n.t("Install Rosetta")
            case .showSteam: return L10n.t("Show Steam window again")
            case .retry: return L10n.t("Try again")
            case .skip: return L10n.t("Skip")
            case .play: return L10n.t("Let's Play")
            }
        }
    }

    enum Step: Int, CaseIterable, Identifiable {
        case rosetta, engine, environment, steam, signIn

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .rosetta: return L10n.t("Preparing your Mac")
            case .engine: return L10n.t("Downloading the game engine")
            case .environment: return L10n.t("Setting up Windows environment")
            case .steam: return L10n.t("Installing Steam")
            case .signIn: return L10n.t("Signing in to Steam")
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case running(Step)
        case needsRosetta
        case waitingForSignIn
        case done
        case failed(Step, String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Download progress of the current step, when it has one.
    @Published private(set) var progress: Double?
    /// Steam's first start, before its sign-in window: it updates itself, then the window comes.
    @Published private(set) var steamStarting = false

    @Published private(set) var stage = Stage.welcome
    /// From "Let's Go" until "Let's Play": the first start stays on Home while the games come in.
    @Published private(set) var isActive = false
    /// "Show the First Start Again": the welcome, the check and what it found – the setup is done.
    @Published private(set) var isReplay = false

    /// After the setup (and "Let's Go" in the replay): the library check starts (LibraryModel).
    var onFinished: (() -> Void)?
    /// The library check under way; "Skip" stops it.
    var checkTask: Task<Void, Never>?
    private var signInWatcher: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    /// Nothing left to do: Steam is installed and someone has signed in.
    static var isComplete: Bool { Engine.isSteamInstalled && Engine.isSteamSignedIn }

    // MARK: - The pages

    /// "Let's Go": the setup's checklist, or in the replay straight to the library check.
    func begin() {
        guard stage == .welcome else { return }
        isActive = true
        if isReplay {
            stage = .checking(LibraryCheck())
            onFinished?()
        } else {
            stage = .checklist
            start()
        }
    }

    /// From Settings › About, once the setup is done.
    func replay(setupDone: Bool? = nil) {
        guard setupDone ?? Self.isComplete, !isActive else { return }
        isReplay = true
        isActive = true
        stage = .welcome
    }

    func checking(_ check: LibraryCheck) {
        guard isActive else { return }
        stage = .checking(check)
    }

    func reveal(_ reveal: LibraryReveal) {
        guard isActive else { return }
        stage = .reveal(reveal)
    }

    /// "Let's Play" and "Skip": the library takes over.
    func close() {
        checkTask?.cancel()
        checkTask = nil
        isActive = false
        isReplay = false
        stage = .welcome
    }

    /// Return and A.
    func primary() {
        Self.confirmAction(stage: stage, phase: phase).map(perform)
    }

    /// Esc and B; false when there's nothing to leave (the setup itself can't be skipped).
    func back() -> Bool {
        guard let action = Self.backAction(stage: stage, replay: isReplay) else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: Action) {
        switch action {
        case .begin: begin()
        case .installRosetta: installRosetta()
        case .showSteam: reopenSteam()
        case .retry: start()
        case .skip, .play: close()
        }
    }

    nonisolated static func confirmAction(stage: Stage, phase: Phase) -> Action? {
        switch stage {
        case .welcome: return .begin
        case .checklist:
            switch phase {
            case .needsRosetta: return .installRosetta
            case .waitingForSignIn: return .showSteam
            case .failed: return .retry
            case .idle, .running, .done: return nil
            }
        case .checking: return nil
        case .reveal: return .play
        }
    }

    nonisolated static func backAction(stage: Stage, replay: Bool) -> Action? {
        switch stage {
        case .welcome: return replay ? .skip : nil
        case .checklist: return nil
        case .checking: return .skip
        case .reveal: return .play
        }
    }

    /// The welcome's line: what Nightforge is and what happens next. In the replay the setup and the
    /// sign-in are long done, so it says what's shown instead.
    nonisolated static func welcomeText(replay: Bool) -> String {
        replay ? L10n.t("Nightforge plays your Windows games on this Mac. Here's once more how your library runs on it.")
               : L10n.t("Nightforge plays your Windows games on this Mac – next, it sets up everything they need by itself in a few minutes, and you only sign in to Steam.")
    }

    /// The library check's headline and the line under it. On the first start the library comes
    /// from Steam right after the sign-in; the replay only reads what's on the Mac.
    nonisolated static func checkingTexts(_ check: LibraryCheck, replay: Bool) -> (headline: String, line: String) {
        let lookingUp = L10n.t("Looking up how each one runs on this Mac …")
        switch check.total {
        case nil:
            return replay ? (L10n.t("Reading your library …"), lookingUp)
                          : (L10n.t("Asking Steam for your games …"), L10n.t("Steam sends your library a moment after you sign in."))
        case 1?: return (L10n.t("%ld of 1 game", check.checked), lookingUp)
        case let total?: return (L10n.t("%ld of %ld games", check.checked, total), lookingUp)
        }
    }

    /// The line under the checklist about Steam's sign-in window: said before it opens, so the phone
    /// is at hand for its QR code, and again while it's open.
    nonisolated static func signInNote(phase: Phase, steamStarting: Bool) -> String? {
        switch phase {
        case .running(.steam) where steamStarting:
            return L10n.t("Steam's sign-in window opens next: scan its QR code with the Steam app on your phone – no typing.")
        case .waitingForSignIn:
            return L10n.t("Sign in in the Steam window – with the QR code from the Steam app on your phone or with your password. Nightforge never sees your login.")
        default:
            return nil
        }
    }

    // MARK: - The setup

    func currentStep() -> Step? {
        switch phase {
        case .running(let step), .failed(let step, _): return step
        case .needsRosetta: return .rosetta
        case .waitingForSignIn: return .signIn
        case .idle, .done: return nil
        }
    }

    func isFinished(_ step: Step) -> Bool {
        if phase == .done { return true }
        guard let current = currentStep() else { return false }
        return step.rawValue < current.rawValue
    }

    func start() {
        guard phase == .idle || phase == .needsRosetta || { if case .failed = phase { return true } else { return false } }() else { return }
        Task { await run() }
    }

    private func run() async {
        var step = Step.rosetta
        do {
            phase = .running(.rosetta)
            guard Engine.isRosettaInstalled else {
                phase = .needsRosetta
                return
            }

            step = .engine
            phase = .running(.engine)
            let manifest = try await ComponentStore.shared.manifest()
            // The engine every later start uses (winecx when the list has it), so a new Mac doesn't
            // download one engine for setup and switch to another at the first start.
            guard let engineComponent = Engine.engineComponent(in: manifest),
                  let graphicsComponent = Engine.graphicsComponent(in: manifest)
            else { throw ComponentError.noManifest }

            let total = Double(engineComponent.size + graphicsComponent.size)
            let engineShare = Double(engineComponent.size) / total
            let engineDir = try await ComponentStore.shared.install(engineComponent) { value in
                Task { @MainActor in self.progress = value * engineShare }
            }
            _ = try await ComponentStore.shared.install(graphicsComponent) { value in
                Task { @MainActor in self.progress = engineShare + value * (1 - engineShare) }
            }
            progress = nil
            guard let wine = Engine.wineBinary(in: engineDir) else { throw SetupError.engineBroken }

            step = .environment
            phase = .running(.environment)
            if !FileManager.default.fileExists(atPath: Engine.prefix.appendingPathComponent("drive_c").path) {
                try FileManager.default.createDirectory(at: Engine.prefix, withIntermediateDirectories: true)
                guard try await Engine.run(wine, ["wineboot", "--init"]) == 0 else { throw SetupError.environmentFailed }
            }
            // Graphics layers, D3DMetal, the controller package and the game environment, the same way
            // every later start checks them (off the main thread: it copies files and runs regedit).
            _ = try await Engine.ensureEngine()

            step = .steam
            phase = .running(.steam)
            if !Engine.isSteamInstalled {
                let installer = try await downloadSteamSetup()
                defer { try? FileManager.default.removeItem(at: installer) }
                _ = try await Engine.run(wine, [installer.path, "/S"])
                guard Engine.isSteamInstalled else { throw SetupError.steamInstallFailed }
            }

            step = .signIn
            if Engine.isSteamSignedIn {
                finish()
            } else {
                try await firstSteamStart(wine)
            }
        } catch {
            progress = nil
            phase = .failed(step, error.localizedDescription)
        }
    }

    /// Opens the password prompt macOS uses for system installs; Rosetta itself comes from Apple.
    func installRosetta() {
        let script = #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#
        Task {
            let ok = await Task.detached { () -> Bool in
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                return error == nil
            }.value
            if ok {
                phase = .idle
                start()
            } else {
                phase = .needsRosetta
            }
        }
    }

    /// Brings the Steam window back if someone closed it before signing in, in front of Nightforge.
    func reopenSteam() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            try? Engine.startSteam(wine)
            await SteamWindow.bringForward()
        }
    }

    /// Steam updates itself twice on first start and restarts in between; under Wine the second round
    /// sometimes stalls or the restart doesn't come back. Watch it and restart Steam when that happens.
    private func firstSteamStart(_ wine: URL) async throws {
        // Already up (e.g. setup was restarted while the login window is open): just wait for the sign-in.
        if Engine.isSteamRunning {
            phase = .waitingForSignIn
            watchForSignIn()
            return
        }

        let start = Date()
        var restarts = 0
        var lastRestart = Date()
        // When the wrapper went in: a steamwebhelper started before that is Valve's.
        var swappedAt: Date?
        phase = .running(.steam)
        steamStarting = true
        defer { steamStarting = false }
        try Engine.startSteam(wine)

        while true {
            try await Task.sleep(for: .seconds(2))
            if Engine.isSteamSignedIn {
                progress = nil
                finish()
                return
            }
            // Steam's first update unpacks its browser, and the new client starts it – Valve's,
            // unwrapped, i.e. black. Once the update is in and the new client runs (never during
            // the install: that cut it off, and Steam started over every 13 s), the wrapper goes in.
            // A client that hasn't started its browser yet starts the wrapper itself; Steam is
            // restarted only when Valve's already runs.
            let bootstrap = SteamBootstrap(steamRoot: Engine.steamRoot)
            let clientInstalled = SteamBootstrap.clientInstalled(steamRoot: Engine.steamRoot)
            if bootstrap == .idle, clientInstalled {
                if Engine.installWebHelperWrapper() { swappedAt = Date() }
                if let swappedAt, await Engine.offMain({ Engine.unwrappedWebHelperRunning(swappedAt: swappedAt) }) {
                    restarts += 1
                    guard restarts <= 5 else { throw SetupError.steamWontStart }
                    try await restartSteam(wine)
                    lastRestart = Date()
                    continue
                }
            }
            if Engine.isSteamWaitingForSignIn(since: start) {
                progress = nil
                phase = .waitingForSignIn
                watchForSignIn()
                return
            }

            let update = Engine.steamUpdateStatus()
            progress = update.fraction
            let quiet = update.lastChange.map { Date().timeIntervalSince($0) } ?? 0
            let sinceRestart = Date().timeIntervalSince(lastRestart)
            let stalled = bootstrap.stalled(quietFor: quiet, sinceRestart: sinceRestart, clientInstalled: clientInstalled,
                                            clientStarted: SteamBootstrap.clientStarted(steamRoot: Engine.steamRoot))
            let gone = bootstrap.gone(steamRunning: Engine.isSteamRunning, sinceRestart: sinceRestart, quietFor: quiet)

            if stalled || gone {
                restarts += 1
                guard restarts <= 5 else { throw SetupError.steamWontStart }
                try await restartSteam(wine)
                lastRestart = Date()
            }
        }
    }

    /// Ends everything of Steam's and starts it again – only once all of it is gone (up to 10 s):
    /// a Steam started while the old one was still going away hung right after its browser came
    /// up (29.10.2026, 20:57:19, until a restart 90 s later).
    private func restartSteam(_ wine: URL) async throws {
        await Engine.offMain { Engine.stopAll(wine) }
        var waited = 0
        while waited < 40, await Engine.offMain({ !Engine.ownProcesses().isEmpty }) {
            try await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        try Engine.startSteam(wine)
    }

    private func watchForSignIn() {
        showSignInWindow()
        signInWatcher?.cancel()
        signInWatcher = Task {
            while !Task.isCancelled {
                if Engine.isSteamSignedIn {
                    finish()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Steam's sign-in in front of Nightforge (it opened behind it). When Nightforge wasn't the
    /// active app just then, the next time it is.
    private func showSignInWindow() {
        Task {
            if await SteamWindow.bringForward() { return }
            showSignInWindowOnActivation()
        }
    }

    private func showSignInWindowOnActivation() {
        guard phase == .waitingForSignIn, activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let observer = self.activationObserver else { return }
                NotificationCenter.default.removeObserver(observer)
                self.activationObserver = nil
                guard self.phase == .waitingForSignIn else { return }
                Task { await SteamWindow.bringForward() }
            }
        }
    }

    private func finish() {
        signInWatcher?.cancel()
        phase = .done
        if isActive { stage = .checking(LibraryCheck()) }
        onFinished?()
        // Steam opens its big main window after sign-in; from now on it only works in the background.
        Task {
            guard let wine = await Engine.installedWine() else { return }
            try? await Engine.restartSteamInBackground(wine)
        }
    }

    private func downloadSteamSetup() async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: Engine.steamSetupURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SetupError.steamDownloadFailed }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("SteamSetup-\(UUID().uuidString).exe")
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }
}

enum SetupError: LocalizedError {
    case engineBroken, environmentFailed, steamDownloadFailed, steamInstallFailed, steamWontStart

    var errorDescription: String? {
        switch self {
        case .engineBroken: return L10n.t("The game engine is incomplete. Please try again.")
        case .environmentFailed: return L10n.t("The Windows environment could not be created.")
        case .steamDownloadFailed: return L10n.t("Steam could not be downloaded. Check your internet connection.")
        case .steamInstallFailed: return L10n.t("Steam could not be installed.")
        case .steamWontStart: return L10n.t("Steam keeps stopping during its first start. Please try again.")
        }
    }
}
