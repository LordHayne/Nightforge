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
        plan = GameTest.plan(plan, only: settings.only)
        let total = plan.filter { $0.skip == nil }.count
        GameLog.note("Game test begins: \(total) of \(plan.count) installed games to start, into \(folder.lastPathComponent)")
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
                    GameLog.note("Game test: \(game.name) (\(number) of \(total))")
                    entry = await test(game, candidate)
                    await comeBack(from: game)
                    await settle()
                }
            } else {
                entry = .skipped(candidate, .gone)
            }
            report.games.append(entry.redacted())
            write()
        }
        report.finished = Date()
        report.stopped = stopAsked
        UserDefaults.standard.removeObject(forKey: GameTest.Keys.stop)
        write()
        let pictures = report.games.filter { $0.outcome == .picture }.count
        GameLog.note("Game test ends: \(pictures) of \(number) started games showed a picture – \(folder.lastPathComponent)")
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

    private func test(_ game: Game, _ candidate: GameTest.Candidate) async -> GameTest.Entry {
        let mark = GameLog.mark()
        let started = Date()
        let learnedBefore = LearnedFixes.winetricks(game.gameID)
        var seen = GameTest.Seen()
        var notes: [String] = []
        var processAt: Date?
        var pictureAt: Date?
        var appeared: Date?
        var idleSince: Date?
        var pid: pid_t?
        model.sessionSummary = nil  // "Welcome back" for the game before, set once its curtain had gone
        model.launch(game)
        watching: while true {
            try? await Task.sleep(for: .seconds(1))
            let now = Date()
            if let needs = needsPlayer() {
                seen.needs = needs
                break
            }
            if model.saveChoice != nil {
                model.answerSaveChoice(takeNewer: false)  // its own saves, nothing overwritten
                notes.append("Spielstand-Frage beantwortet: die eigenen behalten")
            }
            let pids = await processes(of: game)
            if pids.isEmpty {
                appeared = nil
                idleSince = model.launchingID == game.id ? nil : idleSince ?? now
            } else {
                seen.process = true
                processAt = processAt ?? now
                appeared = appeared ?? now
                idleSince = nil
                pid = model.running[game.id] ?? pids.first
            }
            if let message = model.errorMessage {
                notes.append("Meldung: " + message)
                model.errorMessage = nil
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
                seen.stillRunning = true
            case .ended:
                break
            case .tooLong:
                seen.stillRunning = !pids.isEmpty
                notes.append("nach \(Int(GameTest.longestStart / 60)) min abgebrochen")
            }
            break watching
        }
        if let needs = seen.needs { callOff(needs) }

        // A picture: it runs on a while, for its frame rates.
        var endedWhilePlaying = false
        if seen.picture {
            let until = Date().addingTimeInterval(settings.playSeconds)
            var gone = 0
            while Date() < until {
                try? await Task.sleep(for: .seconds(2))
                gone = await processes(of: game).isEmpty ? gone + 1 : 0
                if gone >= 3 {
                    endedWhilePlaying = true
                    break
                }
            }
        }
        var files: [String] = []
        var stack: [String]?
        if seen.stillRunning, let pid {
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
        entry.secondsToProcess = processAt.map { ($0.timeIntervalSince(started) * 10).rounded() / 10 }
        entry.secondsToPicture = pictureAt.map { ($0.timeIntervalSince(started) * 10).rounded() / 10 }
        entry.frames = frames
        entry.stack = stack
        let learned = LearnedFixes.winetricks(game.gameID).filter { !learnedBefore.contains($0) }
        if !learned.isEmpty { notes.append("laut Log fehlen Laufzeiten, im Test nicht installiert: " + learned.joined(separator: ", ")) }
        if log.contains("Curtain under a window of \(game.name)'s") { notes.append("das Spiel zeigte vor dem Bild ein Fenster mit einer Frage") }
        if outcome != .picture, let look = GameTest.lastLook(of: game.name, in: log) { notes.append("letzter Blick des Vorhangs: " + look) }
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
