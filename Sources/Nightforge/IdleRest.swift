import AppKit

/// How Nightforge rests while nobody uses it (the idea: a Mac mini as a console, on all day). Plugged in
/// or not, Nightforge may be left in front for hours; nothing it looks at matters to anyone then.
enum IdleRest {
    /// No keyboard, mouse or pad for this long: nobody's there. Long enough for a cut scene or a read,
    /// short of the display's own sleep.
    static let awayAfter: TimeInterval = 5 * 60

    static func nobodyThere(idle: TimeInterval) -> Bool { idle >= awayAfter }

    /// Seconds between two looks at the running games (a process list each). A game, a start, a
    /// download or the curtain keep their pace; with nobody there, not even Nightforge in front does.
    /// Coming back or pressing Play cuts the pause short (`LibraryModel.lookNow`).
    static func lookPause(gameEnding: Bool, gameOrStart: Bool, downloading: Bool, inFront: Bool, nobodyThere: Bool) -> Int {
        if gameEnding { return 1 }
        if gameOrStart { return 3 }
        if nobodyThere, !downloading { return 30 }
        return inFront ? 3 : 10
    }

    /// Seconds between two looks at the downloads (their manifests, every tenth a whole scan). A
    /// paused one stays listed, and nobody reads progress that isn't there: it went on every 3 s all day.
    static func downloadLookPause(fetching: Bool, nobodyThere: Bool) -> Int {
        nobodyThere && !fetching ? 30 : 3
    }

    /// Seconds between two looks for Steam for Mac's windows. It went round every second for as long as
    /// Nightforge was open, mostly with no Steam for Mac there; macOS says when one starts, so
    /// this is only for a word that got lost. A test home's stand-in is no app macOS tells about.
    static func windowGuardPause(steamRunning: Bool, testHome: Bool) -> Int {
        steamRunning || testHome ? 1 : 30
    }
}

/// Nightforge never wakes the Mac for an update (no schedule, no admin rights): what's new is looked
/// for when the player wakes it, and a Nightforge left open for weeks gets it that way. A game comes
/// first: nothing begins during a start or a game, and Play calls off what's still being fetched.
struct WakeCatchUp {
    /// Short naps ask nothing new; a night does.
    static let every: TimeInterval = 6 * 60 * 60
    /// The network takes a moment after a wake: an answer before that would be "offline".
    static let settle: TimeInterval = 20

    private var lastDone: Date
    private var wokeAt: Date?
    /// New components are here and wait to go in.
    private(set) var applyDue = false

    init(now: Date = Date()) { lastDone = now }

    mutating func woke(now: Date = Date()) {
        guard wokeAt == nil, now.timeIntervalSince(lastDone) >= Self.every else { return }
        wokeAt = now
    }

    /// Whether to look for updates now. Nobody there is a wake nobody asked for (Power Nap, the network).
    mutating func take(gameOrStart: Bool, nobodyThere: Bool, now: Date = Date()) -> Bool {
        guard let wokeAt, now.timeIntervalSince(wokeAt) >= Self.settle, !gameOrStart, !nobodyThere else { return false }
        self.wokeAt = nil
        lastDone = now
        return true
    }

    /// A start called the fetch off: once more when it's over.
    mutating func again(now: Date = Date()) { wokeAt = now }

    mutating func fetched() { applyDue = true }

    mutating func takeApply(gameOrStart: Bool) -> Bool {
        guard applyDue, !gameOrStart else { return false }
        applyDue = false
        return true
    }
}

extension Engine {
    /// What the next `ensureEngine` wants from the component list, to fetch ahead of it. Never Apple's
    /// D3DMetal: that one comes as the player has said (D3DMetalSupply).
    static func wantedAhead(_ manifest: ComponentManifest) -> [Component] {
        guard let engine = engineComponent(in: manifest), let graphics = graphicsComponent(in: manifest) else { return [] }
        var ids = [moltenVKID, dxvkID]
        if engine.id == winecxEngineID {
            ids += [gamepadID, kosmicKrispID, dxvkUpstreamID]
            if manifest.component(engineFixID)?.version.hasPrefix(engine.version + "-") == true { ids.append(engineFixID) }
        }
        return [engine, graphics] + ids.compactMap(manifest.component)
    }

    /// Fetches those and changes nothing else: beside a start or a game nothing notices. True when something new came.
    static func fetchComponents() async throws -> Bool {
        let store = ComponentStore.shared
        var found = false
        for component in wantedAhead(try await store.manifest()) {
            try Task.checkCancellation()
            if await store.installedPath(for: component) != nil { continue }
            _ = try await store.install(component)
            found = true
        }
        return found
    }
}

extension LibraryModel {
    func beginWakeWatch() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.lookNow()
                    self?.wakeCatchUp.woke()
                }
            }
        }
    }

    /// One look, from the loop that watches the running games.
    func lookAtWakeCatchUp() {
        let busy = !running.isEmpty || launchingID != nil || GameBackdrop.isRaised
        if wakeCatchUp.take(gameOrStart: busy, nobodyThere: IdleRest.nobodyThere(idle: InputRouter.secondsSinceUse)) { catchUpAfterWake() }
        if wakeCatchUp.takeApply(gameOrStart: busy) { applyFetchedComponents() }
    }

    /// A start has the Mac's attention: nothing further is fetched. What's on its way ends by itself and waits unused.
    func callOffWakeUpdate() {
        wakeFetch?.cancel()
        wakeFetch = nil
    }

    private func catchUpAfterWake() {
        guard SetupModel.isComplete else { return }
        GameLog.note("The Mac woke: Nightforge looks for updates at \(GameLog.clock())")
        refreshStores()
        wakeFetch = Task { [weak self] in
            await self?.lookForAppUpdate()
            await ProfileStore.shared.refresh()
            await AGWStore.shared.refresh()
            let found = (try? await Engine.fetchComponents()) ?? false
            guard let self else { return }
            if Task.isCancelled { self.wakeCatchUp.again() } else if found { self.wakeCatchUp.fetched() }
        }
    }

    /// In line with Steam's starts, as at Nightforge's own start. Everything is here by now, so a Play meanwhile waits seconds.
    private func applyFetchedComponents() {
        let previous = steamStartup
        steamStartup = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            // A start may have come while this waited in line.
            guard self.running.isEmpty, self.launchingID == nil else {
                self.wakeCatchUp.fetched()
                return
            }
            let steamWasUp = await Engine.offMain { Engine.isSteamRunning }
            guard let wine = try? await Engine.ensureEngine(gameRunning: false), steamWasUp, !self.macSteamBusy else { return }
            try? await Engine.ensureSteamRunning(wine, busy: self.gameUnderWay)
        }
    }
}
