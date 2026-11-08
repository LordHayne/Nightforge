import AppKit

/// Windows Steam only when something needs it, on battery: left running hidden it costs 3–4 % of a
/// core all day (measured 7.11.2026), and nothing in Nightforge reads it while no game, download or
/// cloud sync goes on – the library comes from its files.
///
/// It sleeps once Nightforge has been out of front for `awayFor` on battery with nothing going on,
/// and is up again as soon as the player comes back, plugs in or presses Play – so by the time a game
/// is picked it has started or nearly so. `awayFor` is long on purpose: one start of Steam costs about
/// as much CPU as 40 minutes of idling (its start took 3 cores or more on 4./5.11.), so a short
/// absence mustn't cycle it. Plugged in, nothing changes.
struct SteamOnDemand {
    static let awayFor: TimeInterval = 30 * 60
    /// What Steam's end can take (`Engine.stopSteam`): until then a Steam still listed is the one going.
    static let endingFor: TimeInterval = 90

    /// What decides it, as `LibraryModel` finds it.
    struct Facts: Equatable {
        var onBattery = false
        /// Nightforge is the active app: the player may press Play any moment.
        var inFront = false
        var steamRunning = false
        /// Signed in, with "Remember me": it signs in by itself when it starts again. Else stopping
        /// it would cost the player a password.
        var signInKept = false
        /// A game runs or starts, or Steam waits on the player for one.
        var gameBusy = false
        /// One of Nightforge's Steam's games is downloading.
        var downloading = false
        /// A Mac version downloads through Steam for Mac, which this Steam signing in would sign out.
        var macDownload = false
        /// A game within the last five minutes: Steam may still be uploading its cloud saves.
        var gameRanRecently = false
        /// Steam's own update is going in; cut off, it would start over.
        var clientUpdating = false
        /// Something else that has to do with Steam: a game moving or being removed, the first
        /// start's setup, a game test.
        var otherWork = false
        /// A Mac version runs or starts: the Windows Steam stays out of its way (one sign-in per account).
        var macBusy = false
    }

    enum Step: Equatable { case keep, sleep, wake }

    /// Nightforge stopped Steam and hasn't started it since.
    private(set) var asleep = false
    private var quietSince: Date?
    private var sleptAt: Date?

    /// Nothing needs Steam just now.
    static func unneeded(_ facts: Facts) -> Bool {
        facts.onBattery && !facts.inFront && facts.steamRunning && facts.signInKept && !facts.gameBusy && !facts.downloading
            && !facts.gameRanRecently && !facts.clientUpdating && !facts.otherWork
    }

    /// What to do after this look.
    mutating func step(_ facts: Facts, now: Date = Date()) -> Step {
        if asleep {
            // Started by something else meanwhile (a game's own start): no longer ours to wake.
            if facts.steamRunning, now.timeIntervalSince(sleptAt ?? now) >= Self.endingFor {
                asleep = false
                return .keep
            }
            // Not under a Mac version: refused then, it would count as awake, and nothing would start it afterwards.
            // Not under a game (a start of Steam takes 3 cores or more), nor over a Mac version's download.
            guard facts.inFront || !facts.onBattery, !facts.gameBusy, !facts.macDownload, !facts.macBusy else { return .keep }
            asleep = false
            return .wake
        }
        guard Self.unneeded(facts) else {
            quietSince = nil
            return .keep
        }
        let since = quietSince ?? now
        quietSince = since
        guard now.timeIntervalSince(since) >= Self.awayFor else { return .keep }
        quietSince = nil
        asleep = true
        sleptAt = now
        return .sleep
    }

    /// The end of a look that said `.sleep`, once Steam's windows have been looked at, which takes a
    /// moment: false when the player came back meanwhile, or is using one of them.
    mutating func confirmSleep(windowOpen: Bool) -> Bool {
        guard asleep else { return false }
        if windowOpen { postpone() }
        return !windowOpen
    }

    /// It was woken, and something in the way (`wakeWay`) keeps it down for now: a later look wakes it.
    mutating func stayAsleep(now: Date = Date()) {
        asleep = true
        sleptAt = sleptAt ?? now
    }

    /// A window of Steam's turned up on the screen: the player is using it, the wait begins anew.
    mutating func postpone() {
        asleep = false
        quietSince = nil
    }

    enum WakeWay: Equatable { case stay, start, quitMacFirst }

    /// How it comes back, with Steam for Mac in mind (SteamSwitch): whichever signs in last signs the other
    /// out, and that cuts off a save on its way to the cloud or a download. A Windows game's start
    /// (`forStart`) goes ahead of a Mac download, as with the Steams changing over.
    static func wakeWay(macGameBusy: Bool, macDownload: Bool, macRunning: Bool, macOurs: Bool, forStart: Bool) -> WakeWay {
        if macGameBusy || (macDownload && !forStart) { return .stay }
        return macRunning && macOurs && !macDownload ? .quitMacFirst : .start
    }

    /// The player or a game wants Steam now. True if it was asleep and has to start.
    mutating func wakeNow() -> Bool {
        guard asleep else { return false }
        asleep = false
        return true
    }
}

extension LibraryModel {
    /// One look, from the loop that watches the running games. Plugged in and awake, the usual case
    /// there, it ends at the first line.
    func lookAtSteamOnDemand() async {
        guard power.onBattery || steamOnDemand.asleep else { return }
        var facts = SteamOnDemand.Facts(onBattery: power.onBattery, inFront: NSApp.isActive,
                                        gameBusy: !running.isEmpty || launchingID != nil || awaitingSteam || launchNeedsConfirmation,
                                        downloading: downloads.contains { $0.provider == .steam && $0.platform == .windows },
                                        macDownload: macDownloading,
                                        gameRanRecently: Engine.gameRanRecently,
                                        otherWork: move != nil || uninstallingID != nil || GameTest.active || !SetupModel.isComplete
                                            || macSteamBusy,
                                        macBusy: macSteamBusy)
        let engine = await Engine.offMain {
            (running: Engine.isSteamRunning, kept: Engine.steamSignedIn && OfflineReadiness.accountRemembered(steamRoot: Engine.steamRoot),
             updating: SteamBootstrap(steamRoot: Engine.steamRoot) == .installing)
        }
        facts.steamRunning = engine.running
        facts.signInKept = engine.kept
        facts.clientUpdating = engine.updating
        switch steamOnDemand.step(facts) {
        case .keep:
            break
        case .wake:
            startSteamAgain(forStart: false)
        case .sleep:
            // Checked last, it asks the window server: the player may be using Steam's own window.
            let windowOpen = await SteamWindow.isOpen()
            guard steamOnDemand.confirmSleep(windowOpen: windowOpen) else { return }
            GameLog.note("Steam sleeps: on battery, nothing has needed it for \(Int(SteamOnDemand.awayFor / 60)) minutes")
            let previous = steamStartup
            steamStartup = Task {
                await previous?.value
                guard let wine = await Engine.installedWine() else { return }
                try? await Engine.stopSteam(wine, endWait: Engine.filesEndWait)
            }
        }
    }

    /// Steam back up if it's asleep: the player came back, or wants to play (`forStart`).
    func wakeSteam(forStart: Bool = false) {
        if steamOnDemand.wakeNow() { startSteamAgain(forStart: forStart) }
    }

    /// Queued like any other start of Steam, so a game's start waits for it.
    private func startSteamAgain(forStart: Bool) {
        let previous = steamStartup
        steamStartup = Task {
            await previous?.value
            guard let wine = await Engine.installedWine() else { return }
            let facts = steamFacts
            switch SteamOnDemand.wakeWay(macGameBusy: macSteamBusy, macDownload: facts.macDownload, macRunning: facts.macSteamRunning,
                                         macOurs: facts.macSteamOurs, forStart: forStart) {
            case .stay:
                steamOnDemand.stayAsleep()
                return
            case .quitMacFirst:
                await MacSteam.quit()  // quit, it finishes its cloud sync; signed out by this Steam, it wouldn't
            case .start:
                break
            }
            GameLog.note("Steam wakes")
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
            watchWokenSteam(wine)
        }
    }
}
