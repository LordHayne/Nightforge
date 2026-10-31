import Foundation

/// Steam for Mac in the first start (docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md): it gets ready
/// alongside the Windows setup, hidden (MacSteam.prepare), and right after the Windows sign-in the
/// player scans a second QR code – only when the library has games Nightforge plays as their Mac
/// version. Then it quits again; the Windows Steam is the one that stays.
@MainActor
final class MacSteamPrep: ObservableObject {
    /// What the step does after the Windows sign-in.
    enum Decision: Equatable {
        /// The player scans its QR code.
        case signIn
        /// It remembers this account already: nothing to do.
        case alreadySignedIn
        /// It remembers another account – the player's own Steam for Mac, left as it is. Mac
        /// versions are set up the first time one is played (MacSteamSetup).
        case otherAccount
        /// No game in the library has a Mac version Nightforge would use.
        case notNeeded
    }

    enum State: Equatable {
        case idle
        case preparing(MacSteam.Preparation)
        /// Ready, and waiting for the Windows sign-in to decide.
        case ready(MacSteam.Preparation)
        /// Its sign-in window is up for the player.
        case signingIn
        case done(Decision)
        /// "Later": Mac versions get set up the first time one is played.
        case later
        case failed(String)
    }

    @Published private(set) var state = State.idle {
        didSet { describe() }
    }
    /// The line under the step (SetupDetail.macSteam), and its update's progress.
    @Published private(set) var detail: String?
    @Published private(set) var progress: Double?
    /// The games the second code is for (LibraryReveal.mac).
    @Published private(set) var macVersions = 0
    private var task: Task<Void, Never>?

    /// How long the decision waits for a preparation that hasn't got there yet: Steam for Mac's
    /// first start took 53 s on 26.10.2026, and it begins minutes before the Windows sign-in.
    nonisolated static let preparationPatience: TimeInterval = 180

    /// The checklist step's title (SetupModel.Step.macSteam).
    nonisolated static var stepTitle: String { L10n.t("Setting up Steam for Mac") }

    /// Added to the note before the Windows sign-in once Steam for Mac is ready: the phone stays at
    /// hand.
    nonisolated static var secondCodeAhead: String {
        L10n.t("If your games have Mac versions, a second code for Steam for Mac follows right after.")
    }

    /// Steam for Mac is on its way or ready for a code of its own: the Windows code's note says a
    /// second one may follow (it does when the library has Mac versions).
    var secondCodeFollows: Bool {
        switch state {
        case .preparing(.remembered), .ready(.remembered): return false
        case .preparing, .ready: return true
        default: return false
        }
    }

    /// The note while its sign-in window is up.
    nonisolated static func signInNote(macVersions: Int) -> String {
        macVersions == 1
            ? L10n.t("One more: this window is Steam for Mac. It gets the Mac version of 1 of your games – it runs without any Windows translation. Scan its QR code too.")
            : L10n.t("One more: this window is Steam for Mac. It gets the Mac versions of %ld of your games – they run without any Windows translation. Scan its QR code too.", macVersions)
    }

    /// The decision once the Windows Steam has signed in and the library check knows its games.
    /// `macVersions`: the player's games Nightforge plays as their Mac version (LibraryReveal.mac).
    nonisolated static func decide(macAccount: String?, windowsAccount: String?, macVersions: Int) -> Decision {
        if let macAccount {
            return macAccount == windowsAccount ? .alreadySignedIn : .otherAccount
        }
        return macVersions > 0 ? .signIn : .notNeeded
    }

    /// After the engine download (the line is free then): install and update it in the background.
    func start() {
        guard task == nil else { return }
        task = Task {
            do {
                try await MacSteam.prepare { self.state = .preparing($0) }
                if case .preparing(let preparation) = state { state = .ready(preparation) }
            } catch is CancellationError {
                return
            } catch {
                MacSteam.hold(false)
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Right after the Windows sign-in. Waits for the preparation (it's usually long done), decides,
    /// and with `.signIn` shows Steam for Mac's sign-in window and waits for the player. Afterwards
    /// Steam for Mac quits and the Windows Steam – signed out by it – starts again, hidden.
    func finish(windowsAccount: String?, macVersions: Int) async {
        self.macVersions = macVersions
        let deadline = Date().addingTimeInterval(Self.preparationPatience)
        while case .preparing = state, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
        // Stuck on the way: the Windows side doesn't wait for it – Mac versions are set up the
        // first time one is played.
        if case .preparing = state {
            task?.cancel()
            MacSteam.hold(false)
            if MacSteam.startedByNightforge && MacSteam.isRunning { await MacSteam.quit() }
            state = .later
            return
        }
        // Failed, or put off meanwhile (the first start was skipped: abandon).
        switch state {
        case .failed, .later: return
        default: break
        }
        guard !Task.isCancelled else { return }
        let decision = Self.decide(macAccount: MacSteam.hasSignedIn ? MacSteam.account : nil,
                                   windowsAccount: windowsAccount, macVersions: macVersions)
        switch decision {
        case .alreadySignedIn, .otherAccount:
            MacSteam.hold(false)
            state = .done(decision)
        case .notNeeded:
            MacSteam.hold(false)
            await MacSteam.removeFreshInstall()
            if MacSteam.startedByNightforge && MacSteam.isRunning { await MacSteam.quit() }
            state = .done(decision)
        case .signIn:
            guard MacSteam.isInstalled else {
                state = .later
                return
            }
            await signIn()
        }
    }

    /// On its way, or ready and waiting for the library: its row shows under the library check.
    var isGettingReady: Bool {
        switch state {
        case .preparing, .ready: return true
        default: return false
        }
    }

    /// Return and A while its sign-in window waits: the window again. False otherwise.
    func primary() -> Bool {
        guard state == .signingIn else { return false }
        showWindow()
        return true
    }

    /// Esc and B while its sign-in window waits: "Later". False otherwise.
    func back() -> Bool {
        guard state == .signingIn else { return false }
        later()
        return true
    }

    private func describe() {
        if case .preparing(.updating(let fraction)) = state {
            progress = fraction
            detail = SetupDetail.macSteam(state, log: SteamBootstrap.log(steamRoot: MacSteam.root))
        } else {
            progress = nil
            detail = SetupDetail.macSteam(state, log: "")
        }
    }

    /// "Show Steam window again" while its sign-in waits.
    func showWindow() {
        guard state == .signingIn else { return }
        MacSteam.show(keepFor: 600)
    }

    /// "Later" (Esc or B) at the second QR code: the Windows side is ready; Steam for Mac stays
    /// installed and signs in the first time a Mac version is played.
    func later() {
        guard state == .signingIn else { return }
        task?.cancel()
        state = .later
        Task {
            MacSteam.hide()
            if MacSteam.startedByNightforge { await MacSteam.quit() }
            await restartWindowsIfSignedOut()
        }
    }

    func cancel() {
        task?.cancel()
        MacSteam.hold(false)
    }

    /// The first start closed ("Skip") before Steam for Mac's turn: it stops getting ready and
    /// quits; Mac versions are set up the first time one is played. A finished one stays as it is.
    func abandon() {
        switch state {
        case .idle, .done, .later, .failed: return
        case .signingIn: return later()
        case .preparing, .ready: break
        }
        task?.cancel()
        MacSteam.hold(false)
        state = .later
        Task {
            if MacSteam.startedByNightforge && MacSteam.isRunning { await MacSteam.quit() }
        }
    }

    private func signIn() async {
        state = .signingIn
        // The Windows Steam restarts hidden after its sign-in (SetupModel.finish): signing in after
        // Steam for Mac, it would sign that one out before it has written its account list.
        var waited = 0
        while !Engine.steamSignedIn, !Engine.sessionReplaced(), waited < 60, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        MacSteam.hold(false)
        let asked = Date()
        task = Task {
            MacSteam.show(keepFor: 600)
            // Steam writes its account list a few seconds after the sign-in; quit before that, it
            // wouldn't remember it.
            while !Task.isCancelled, !Self.accountsWritten(since: asked) {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        await task?.value
        guard state == .signingIn else { return }
        MacSteam.keepFreshInstall()
        // Back to the Windows Steam – unless this is the player's own Steam for Mac, open before.
        if MacSteam.startedByNightforge {
            MacSteam.hide()
            await MacSteam.quit()
        }
        state = .done(.signIn)
        await restartWindowsIfSignedOut()
    }

    /// Its sign-in signed the Windows Steam out (one session per account on one Mac).
    private func restartWindowsIfSignedOut() async {
        guard Engine.isSteamRunning, Engine.sessionReplaced(), let wine = await Engine.installedWine() else { return }
        try? await Engine.restartSteamInBackground(wine)
    }

    private static func accountsWritten(since date: Date) -> Bool {
        let users = MacSteam.root.appendingPathComponent("config/loginusers.vdf")
        let modified = (try? users.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return MacSteam.hasSignedIn && (modified ?? .distantPast) >= date
    }
}
