import AppKit
import Foundation
import IOKit.pwr_mgt

/// Drives the game test (GameTest): waits for its switch, then plays through the installed games
/// with LibraryModel's own Play – the ladder, the curtain, Quit Game as the overlay does it – one
/// at a time, and writes the report after each game, so a run that stops halfway leaves what it saw.
/// The run's folder: Application Support/Nightforge/GameTests/<date>.
@MainActor
final class GameTestRun {
    private static var watching = false

    /// Looks for the switch every few seconds from now on (LibraryView): set with Nightforge open,
    /// the run starts within moments; set before, once it's ready.
    static func watch(_ model: LibraryModel) {
        guard !watching else { return }
        watching = true
        Task {
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard UserDefaults.standard.bool(forKey: GameTest.Keys.start), ready(model) else { continue }
                UserDefaults.standard.removeObject(forKey: GameTest.Keys.start)  // once, never again by itself
                UserDefaults.standard.removeObject(forKey: GameTest.Keys.stop)
                await GameTestRun(model: model).run()
            }
        }
    }

    /// The library is known, and nothing is being played, started or moved: the run never ends a game of the player's.
    private static func ready(_ model: LibraryModel) -> Bool {
        model.lastScan != nil && !model.isScanning && !model.showsFirstStart && model.launchingID == nil
            && model.running.isEmpty && model.move == nil && !model.allGames.isEmpty
    }

    private let model: LibraryModel
    private let settings = GameTest.Settings(.standard)
    private var report: GameTest.Report
    private let folder: URL
    private var stopAsked = false
    /// The games the run started so far: none of them may still run when the next one starts.
    private var startedGames: [Game] = []

    private init(model: LibraryModel) {
        self.model = model
        let started = Date()
        folder = Engine.supportDir.appendingPathComponent("GameTests/\(GameTest.folderName(started))", isDirectory: true)
        report = GameTest.Report(started: started, nightforge: Updater.currentVersion,
                                 engine: EngineRollback.shared.history().current?.parts,
                                 mac: "\(ProblemReport.chip) · macOS \(ProblemReport.osVersion)",
                                 pictureWait: settings.pictureWait, playSeconds: settings.playSeconds)
    }

    private func run() async {
        GameTest.active = true
        // The screen stays on, as for a video: asleep or locked, no game gets the front, and no curtain sinks.
        var awake: IOPMAssertionID = 0
        let holding = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                  IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                  "Nightforge plays through the installed games (game test)" as CFString,
                                                  &awake) == kIOReturnSuccess
        defer {
            GameTest.active = false
            if holding { IOPMAssertionRelease(awake) }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var plan: [GameTest.Candidate] = []
        for game in model.allGames where game.isInstalled {
            plan.append(await candidate(game))
        }
        let basket = GameTest.Basket.load(settings.basket)
        plan = GameTest.plan(plan, only: settings.only, basket: basket)
        if let basket {
            report.basket = .init(generated: basket.generated, entries: basket.games.count, installed: plan.filter(\.inBasket).count)
        } else if !settings.basket.isEmpty {
            // Its name only: the folder it lies in isn't for the repository.
            report.notes = ["Testkorb nicht lesbar (\((settings.basket as NSString).lastPathComponent), Format \(GameTest.Basket.format) erwartet) – nach Name gespielt."]
        }
        let total = plan.filter { $0.skip == nil }.count
        GameLog.note("Game test begins: \(total) of \(plan.count) installed games to start, into \(folder.lastPathComponent)")
        write()
        report.load = await waitForLowLoad()
        write()
        var number = 0
        for candidate in plan {
            stopAsked = stopAsked || UserDefaults.standard.bool(forKey: GameTest.Keys.stop)
            let game = model.allGames.first { $0.gameID.key == candidate.key && $0.platform == candidate.platform && $0.isInstalled }
            var entry: GameTest.Entry
            if let skip = candidate.skip {
                entry = .skipped(candidate, skip)
            } else if stopAsked {
                entry = .skipped(candidate, .stopped)
            } else if GameTest.blocked(candidate, after: report.games) {
                entry = .skipped(candidate, .signIn)
            } else if let game {
                await waitWhileLocked()
                stopAsked = UserDefaults.standard.bool(forKey: GameTest.Keys.stop)
                if stopAsked {
                    entry = .skipped(candidate, .stopped)
                } else {
                    number += 1
                    let before = await clearStage()
                    let front = await takeFront()
                    GameLog.note("Game test: \(game.name) (\(number) of \(total))")
                    startedGames.append(game)
                    entry = await test(game, candidate, notes: before + front)
                    await comeBack(from: game)
                    await settle()
                }
            } else {
                entry = .skipped(candidate, .gone)
            }
            report.games.append(entry.redacted())
            write()
        }
        _ = await clearStage()  // a start Steam carried out after the last game's end
        report.finished = Date()
        report.stopped = stopAsked
        UserDefaults.standard.removeObject(forKey: GameTest.Keys.stop)
        write()
        let pictures = report.games.filter { $0.outcome == .picture }.count
        GameLog.note("Game test ends: \(pictures) of \(number) started games showed a picture – \(folder.lastPathComponent)")
    }

    /// A Mac busy with other work makes the frame rates worthless: the run waits up to five minutes
    /// for its load to drop, and says how it was.
    private func waitForLowLoad() async -> GameTest.Load? {
        let until = Date().addingTimeInterval(GameTest.loadPatience)
        var load = GameTest.Load.now
        while let current = load, !current.low, Date() < until, !UserDefaults.standard.bool(forKey: GameTest.Keys.stop) {
            try? await Task.sleep(for: .seconds(15))
            load = GameTest.Load.now
        }
        if let load {
            GameLog.note("Game test: load \(load.average) on \(load.cores) cores" + (load.low ? "" : " – busy, frame rates won't say much"))
        }
        return load
    }

    /// A locked screen (the player locked it, or it locked before the run began): the run waits.
    private func waitWhileLocked() async {
        guard Self.screenLocked else { return }
        let since = Date()
        GameLog.note("Game test: the screen is locked – waiting")
        while Self.screenLocked, !UserDefaults.standard.bool(forKey: GameTest.Keys.stop) {
            try? await Task.sleep(for: .seconds(10))
        }
        report.waitedLocked = (report.waitedLocked ?? 0) + Int(Date().timeIntervalSince(since) / 60)
    }

    nonisolated private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    // MARK: - Before the run

    /// The game as the run sees it: whether it can start unattended (GameTest.skip).
    private func candidate(_ game: Game) async -> GameTest.Candidate {
        var facts = GameTest.Facts(platform: game.platform, store: game.provider,
                                   antiCheat: game.antiCheatBlock != nil && game.antiCheatBlock?.notYet == nil,
                                   vrOnly: game.isVROnly, builtInBottle: game.bottle.isBuiltIn,
                                   macSteamReady: MacSteam.isReady, pendingUpdate: game.pendingUpdate != nil)
        if game.provider == .steam, game.macNative {
            facts.versionSwitch = SaveTransfer.isSwitch(appID: game.appID, platform: game.platform)
        }
        if game.platform == .windows, game.bottle.isBuiltIn {
            facts.signedIn = game.provider == .steam ? Engine.isSteamSignedIn : game.provider == .epic ? model.epic.isSignedIn : true
            let profile = await ProfileStore.shared.profile(for: game.gameID)
            facts.missingRuntimes = Engine.missingWinetricks((profile?.winetricks ?? [])
                + LearnedFixes.winetricks(game.gameID).filter { $0 != GameLog.wineMono }).filter(Engine.isSafeWinetricksVerb)
            if game.provider == .gog, let setup = model.gog.setupFacts(of: game),
               await Engine.offMain({ GOGRedist.hasWork(setup.install) }) {
                facts.missingRuntimes.append("GOG-Redistributables")
            }
            // What Play asks before anything starts (askAboutD3DMetalBeforeStart): it would set D3DMetal up.
            let analysis = await model.insight(of: game)?.analysis
            facts.needsD3DMetal = !Engine.d3dMetalReady && Engine.installedWineNow().map({ Engine.isGPTKCapable(wine: $0) }) == true
                && D3DMetalSupply.needed(by: analysis, picked: GameOptionsStore.load(game.gameID).graphics)
        }
        let skip = GameTest.skip(facts)
        return GameTest.Candidate(key: game.gameID.key, name: game.name, store: game.provider, storeID: game.gameID.id,
                                  platform: game.platform, notYet: game.antiCheatBlock?.notYet != nil, skip: skip,
                                  skipNote: skip == .runtimes ? "fehlt: " + facts.missingRuntimes.joined(separator: ", ") : nil)
    }

    // MARK: - One game

    private func test(_ game: Game, _ candidate: GameTest.Candidate, notes before: [String]) async -> GameTest.Entry {
        let mark = GameLog.mark()
        let started = Date()
        let learnedBefore = LearnedFixes.winetricks(game.gameID)
        var seen = GameTest.Seen()
        var notes = before
        var processAt: Date?
        var pictureAt: Date?
        var appeared: Date?
        var idleSince: Date?
        var pids: [pid_t] = []
        /// What only the player could do, since when: Steam's question gets `steamAskPatience` to answer itself.
        var asking: (need: GameTest.Skip, since: Date)?
        var foreignSince: Date?
        var frontTakers: [String] = []
        // Unity's start window, from when it stood (GameTest.startWindowStands).
        let unity = game.platform == .windows ? await model.insight(of: game)?.analysis.engine == .unity : false
        let helper = UserDefaults.standard.bool(forKey: GameTest.Keys.unityDialogPlay)
        var startWindowSince: Date?
        model.sessionSummary = nil  // "Welcome back" for the game before, set once its curtain had gone
        let load = GameTest.Load.now
        model.launch(game)
        watching: while true {
            try? await Task.sleep(for: .seconds(1))
            let now = Date()
            if let need = needsPlayer() {
                if asking?.need != need { asking = (need, now) }
                if GameTest.callsOff(need, after: now.timeIntervalSince(asking?.since ?? now)) {
                    seen.needs = need
                    break
                }
            } else if let question = asking {
                if question.need == .steamAsks {
                    notes.append("Steam fragte \(Int(now.timeIntervalSince(question.since))) s lang etwas und machte von selbst weiter")
                }
                asking = nil
            }
            // Another app in front: the curtain can't hand the front to the game from there.
            if let app = foreignApp(for: game) {
                foreignSince = foreignSince ?? now
                if now.timeIntervalSince(foreignSince ?? now) >= 2 {
                    // macOS asking for permission, which the curtain makes way for: the player's to answer.
                    if let asker = await macOSAsking(game, since: mark) {
                        seen.needs = .macOSAsks
                        notes.append("macOS fragte um Erlaubnis (\(asker)) – niemand hat geantwortet, das Spiel wurde beendet; die Frage kann noch offen sein")
                        break
                    }
                    let name = app.localizedName ?? "?"
                    if !frontTakers.contains(name) { frontTakers.append(name) }
                    GameLog.note("Game test: \(name) had the front before the picture – Nightforge takes it back")
                    NSApp.comeToFront()
                    foreignSince = nil
                }
            } else {
                foreignSince = nil
            }
            if model.saveChoice != nil {
                model.answerSaveChoice(takeNewer: false)  // its own saves, nothing overwritten
                notes.append("Spielstand-Frage beantwortet: die eigenen behalten")
            }
            pids = await processes(of: game)
            if pids.isEmpty {
                appeared = nil
                idleSince = model.launchingID == game.id ? nil : idleSince ?? now
            } else {
                seen.process = true
                processAt = processAt ?? now
                appeared = appeared ?? now
                idleSince = nil
            }
            if let message = model.errorMessage {
                notes.append("Meldung: " + message)
                model.errorMessage = nil
            }
            if unity, !pids.isEmpty {
                let running = Set(pids)
                let asks = await Task.detached(priority: .utility) { GameProcesses.question(running) != nil }.value
                startWindowSince = asks ? startWindowSince ?? now : nil
                if GameTest.startWindowStands(unity: unity, picture: LaunchHealth.showedPicture(game.gameID, since: started),
                                              standing: startWindowSince.map { now.timeIntervalSince($0) }, helper: helper) {
                    seen.startWindow = true
                    let windows = await Task.detached(priority: .utility) { GameProcesses.windowList(running) }.value
                    notes.append("Startfenster des Spiels stand \(Int(GameTest.startWindowGrace(helper: helper))) s" + (helper ? " (mit Play-Helfer)" : "")
                                 + ": \(windows)")
                    break
                }
            } else {
                startWindowSince = nil
            }
            let gaveUp = model.failedLaunch?.game.id == game.id
            switch GameTest.look(picture: LaunchHealth.showedPicture(game.gameID, since: started), running: !pids.isEmpty,
                                 waited: appeared.map { now.timeIntervalSince($0) } ?? 0,
                                 idle: gaveUp ? GameTest.endGrace : idleSince.map { now.timeIntervalSince($0) } ?? 0,
                                 total: now.timeIntervalSince(started), settings: settings) {
            case .wait: continue
            case .picture:
                seen.picture = true
                pictureAt = now
            case .hang:
                if let asker = await macOSAsking(game, since: mark) {
                    seen.needs = .macOSAsks
                    notes.append("macOS fragte um Erlaubnis (\(asker)) – niemand hat geantwortet, das Spiel wurde beendet; die Frage kann noch offen sein")
                    break
                }
                seen.stillRunning = true
                // A window of its own smaller than a picture standing all the while: a start window or a question.
                let running = Set(pids)
                let (asks, windows) = await Task.detached(priority: .utility) {
                    (GameProcesses.question(running) != nil, GameProcesses.windowList(running))
                }.value
                seen.smallWindow = asks
                if asks { notes.append("Fenster des Spiels: \(windows)") }
            case .ended:
                break
            case .tooLong:
                seen.stillRunning = !pids.isEmpty
                notes.append("nach \(Int(GameTest.longestStart / 60)) min abgebrochen")
            }
            break watching
        }
        if !frontTakers.isEmpty {
            notes.append("vor dem Bild war vorne: \(frontTakers.joined(separator: ", ")) – Nightforge holte die Front zurück")
        }
        if let needs = seen.needs {
            callOff(needs)
            // macOS asks while the game runs: it's simply ended below; any other call-off may still be carried out by Steam.
            if needs != .macOSAsks, await endLateStart(game) { notes.append("Steam startete es nach dem Abbruch doch noch – wieder beendet") }
        }

        // A picture: it runs on a while, for its frame rates.
        var endedWhilePlaying = false
        if seen.picture {
            let until = Date().addingTimeInterval(settings.playSeconds)
            var gone = 0
            var playTakers: [String] = []
            while Date() < until {
                try? await Task.sleep(for: .seconds(2))
                gone = await processes(of: game).isEmpty ? gone + 1 : 0
                if gone >= 3 {
                    endedWhilePlaying = true
                    break
                }
                // Another app took the front: the game back in front, as Switch to Game does.
                if let app = foreignApp(for: game) {
                    let name = app.localizedName ?? "?"
                    if !playTakers.contains(name) { playTakers.append(name) }
                    model.switchToGame(game)
                }
            }
            if !playTakers.isEmpty {
                notes.append("während des Spiels war vorne: \(playTakers.joined(separator: ", ")) – das Spiel wieder nach vorn geholt")
            }
        }
        var files: [String] = []
        var stack: [String]?
        // The game's own process, not a launcher waiting for it (2.11.: Wukong's b1_benchmark.exe, 4 threads).
        if seen.stillRunning, !seen.smallWindow, let pid = await Task.detached(priority: .utility, operation: { [pids] in
            GameProcesses.biggest(pids)
        }).value {
            let name = GameTest.fileName(game.gameID.key, "sample.txt")
            if let sample = await Self.sample(pid, to: folder.appendingPathComponent(name)) {
                stack = GameTest.topOfStack(in: sample)
                files.append(name)
            } else {
                notes.append("sample konnte den Prozess nicht lesen")
            }
        }
        await quit(game)

        let installDir = game.installDir
        let (log, programs, unrealCrash) = await Engine.offMain {
            (GameLog.text(since: mark), Set(Engine.executables(in: installDir)),
             !GameLog.unrealCrashes(in: installDir, since: started).isEmpty)
        }
        seen.crashSigns = GameLog.crashed(in: log) || unrealCrash
        let outcome = GameTest.outcome(seen)
        let frames = GameTest.frames(FramePacing.periods(in: log, programs: programs))
        var entry = GameTest.Entry(candidate, outcome: outcome, skip: seen.needs)
        entry.ways = game.platform == .mac ? [GameTest.Way(way: "mac", outcome: outcome)]
            : GameTest.ways(of: game.name, in: log, last: outcome)
        entry.way = entry.ways.last?.way
        entry.issues = GameTest.issues(endedWhilePlaying: endedWhilePlaying, frames: frames)
        entry.result = GameTest.result(outcome, issues: entry.issues)
        entry.startedAt = started
        entry.load = load
        entry.secondsToProcess = processAt.map { ($0.timeIntervalSince(started) * 10).rounded() / 10 }
        entry.secondsToPicture = pictureAt.map { ($0.timeIntervalSince(started) * 10).rounded() / 10 }
        entry.frames = frames
        entry.stack = stack
        let learned = LearnedFixes.winetricks(game.gameID).filter { !learnedBefore.contains($0) }
        if !learned.isEmpty { notes.append("laut Log fehlen Laufzeiten, im Test nicht installiert: " + learned.joined(separator: ", ")) }
        if log.contains("Curtain under a window of \(game.name)'s") { notes.append("das Spiel zeigte vor dem Bild ein Fenster mit einer Frage") }
        if outcome != .picture, let look = GameTest.lastLook(of: game.name, in: log) { notes.append("letzter Blick des Vorhangs: " + look) }
        if GameTest.helperPressedPlay(in: log) { notes.append("der Play-Helfer drückte „Play!“ in Unitys Startfenster") }
        if outcome != .picture || endedWhilePlaying {
            let errors = GameLog.errors(in: log, limit: 20)
            entry.errors = errors.isEmpty ? nil : errors
            let name = GameTest.fileName(game.gameID.key, "log")
            let text = String(log.suffix(2_000_000))
            let file = folder.appendingPathComponent(name)
            _ = await Engine.offMain { try? GameLog.redacted(text).write(to: file, atomically: true, encoding: .utf8) }
            files.insert(name, at: 0)
        }
        entry.notes = notes.isEmpty ? nil : notes
        entry.files = files.isEmpty ? nil : files
        GameLog.note("Game test: \(game.name) – \(outcome.rawValue) on \(entry.way ?? "-")"
                     + (entry.secondsToPicture.map { ", picture after \(Int($0)) s" } ?? ""))
        return entry
    }

    /// Nightforge in front before each start: only from there does the curtain hand the front to the
    /// game (bringToFront, handFocus). What had it instead goes into the report.
    private func takeFront() async -> [String] {
        guard !NSApp.isFrontmost else { return [] }
        let before = NSWorkspace.shared.frontmostApplication?.localizedName ?? "keine App"
        NSApp.comeToFront()
        for _ in 0..<20 where !NSApp.isFrontmost { try? await Task.sleep(for: .milliseconds(250)) }
        let took = NSApp.isFrontmost
        GameLog.note("Game test: \(before) had the front before the start" + (took ? " – Nightforge took it" : " and kept it"))
        return [took ? "vor dem Start war \(before) vorne, Nightforge holte die Front" : "vor dem Start war \(before) vorne und blieb es"]
    }

    /// The app in front when it's none of the start's (GameTest.foreignFront).
    private func foreignApp(for game: Game) -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              GameTest.foreignFront(path: app.executableURL?.path, bundleID: app.bundleIdentifier,
                                    gameFolder: game.platform == .mac ? game.installDir.path : nil)
        else { return nil }
        return app
    }

    /// Nothing of an earlier game may run when the next one starts: what the run started and still
    /// runs – a start Steam carried out after all – is ended as Quit Game does. A game the run didn't
    /// start is waited for, up to ten minutes.
    private func clearStage() async -> [String] {
        var notes: [String] = []
        for earlier in startedGames where await !processes(of: earlier).isEmpty {
            await quit(earlier)
            notes.append("vorher lief noch \(earlier.name) – beendet")
            GameLog.note("Game test: \(earlier.name) still ran – ended before the next game")
        }
        let until = Date().addingTimeInterval(600)
        var waited = false
        while !model.running.isEmpty, Date() < until {
            waited = true
            try? await Task.sleep(for: .seconds(5))
        }
        if waited { notes.append(model.running.isEmpty ? "wartete, bis ein anderes Spiel beendet war" : "ein anderes Spiel lief weiter") }
        return notes
    }

    /// A start called off can still come: Steam carries on once its question answers itself (Left 4
    /// Dead 2, 2.11., ran on while the next game started). For 45 s after, any process of the game
    /// is ended as Quit Game does. True when one came.
    private func endLateStart(_ game: Game) async -> Bool {
        var came = false
        let until = Date().addingTimeInterval(45)
        while Date() < until {
            try? await Task.sleep(for: .seconds(1))
            if await !processes(of: game).isEmpty {
                came = true
                await quit(game)
            }
        }
        return came
    }

    /// Whether the curtain is under a question of macOS's for the game now (GameTest.macOSAsking).
    private func macOSAsking(_ game: Game, since mark: UInt64) async -> String? {
        let name = game.name
        return await Engine.offMain { GameTest.macOSAsking(name, in: GameLog.text(since: mark)) }
    }

    /// What only the player could do came up: the start can't go on unattended.
    private func needsPlayer() -> GameTest.Skip? {
        if model.launchNeedsConfirmation { return .steamAsks }
        switch model.launchPhase {
        case .signInInSteamWindow?, .signInAgain?: return .signIn
        case .updating?: return .update
        case .settingUpWindowsParts?: return .runtimes
        default: break
        }
        if model.d3dMetalDialog != nil { return .d3dMetal }
        if model.macSetup != nil { return .macSteamSetup }
        return nil
    }

    private func callOff(_ needs: GameTest.Skip) {
        model.callOffLaunch()
        if needs == .d3dMetal { model.d3dMetalDialog = nil }
        if needs == .macSteamSetup { model.closeMacSetup() }
        GameLog.note("Game test: the start needs the player (\(needs.rawValue)) – called off")
    }

    /// The game's processes: a Windows game's by its folder in Wine's command lines, a Mac game's by its folder.
    private func processes(of game: Game) async -> [pid_t] {
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        return await Task.detached(priority: .utility) {
            GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table())
        }.value
    }

    /// Quit Game, as the overlay does it: the player's end – nothing learned from it – and its
    /// processes ended, also when it hangs.
    private func quit(_ game: Game) async {
        if GameOverlay.isOpen { GameOverlay.close() }
        guard await !processes(of: game).isEmpty else { return }
        LaunchHealth.playerQuit(game.gameID)
        let marker = game.platform == .mac ? nil : game.windowsFolderMarker
        let folder = game.platform == .mac ? game.installDir.path : nil
        await Task.detached(priority: .userInitiated) {
            GameProcesses.end(GameProcesses.targets(windows: marker, mac: folder, in: GameProcesses.table()))
        }.value
    }

    /// Back in Nightforge as after any game, and what it shows for the player put away.
    private func comeBack(from game: Game) async {
        for _ in 0..<90 {
            if model.launchingID == nil, model.running[game.id] == nil, !GameBackdrop.isRaised { break }
            try? await Task.sleep(for: .seconds(1))
        }
        if model.launchingID != nil { model.callOffLaunch() }
        if GameOverlay.isOpen { GameOverlay.close() }
        try? await Task.sleep(for: .seconds(2))  // "Welcome back" comes once the curtain is gone
        model.sessionSummary = nil
        if model.failedLaunch?.game.id == game.id { model.failedLaunch = nil }
        model.errorMessage = nil
    }

    /// Until Steam and the Wine session are calm again – the save written, Steam idle – at least
    /// ten seconds, at most two minutes.
    private func settle() async {
        try? await Task.sleep(for: .seconds(10))
        var looks: [Double] = []
        let until = Date().addingTimeInterval(120)
        while Date() < until {
            looks.append(await Engine.offMain { GameTest.sessionCPU(Self.ps()) })
            if GameTest.calm(looks), !model.storeSaves.values.contains(.syncing) { return }
            try? await Task.sleep(for: .seconds(2))
        }
        GameLog.note("Game test: Steam and Wine still busy after two minutes – on to the next game")
    }

    nonisolated private static func ps() -> String {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pcpu=,command="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return "" }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output
    }

    /// Five seconds of `sample` on the game's process, written to `file` without paths or the
    /// account name. Nil when sample couldn't read it.
    nonisolated private static func sample(_ pid: pid_t, to file: URL) async -> String? {
        await Task.detached(priority: .utility) { sampled(pid, to: file) }.value
    }

    nonisolated private static func sampled(_ pid: pid_t, to file: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(pid), "5", "-mayDie", "-file", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { process.terminate() }
        guard let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty else { return nil }
        let clean = GameLog.redacted(text)
        try? clean.write(to: file, atomically: true, encoding: .utf8)
        return clean
    }

    private func write() {
        try? GameTest.json(report).write(to: folder.appendingPathComponent("report.json"), options: .atomic)
        try? GameTest.summary(report).write(to: folder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }
}
