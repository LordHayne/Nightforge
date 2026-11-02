import Foundation

/// One way to start a game: which layer draws its Direct3D, and what's added to its command line.
struct LaunchAttempt: Equatable {
    var graphics: GraphicsLayer
    /// "-dx11" and the like, for a game that would otherwise pick Direct3D 12.
    var arguments: [String] = []

    var id: String { ([graphics.rawValue] + arguments).joined(separator: " ") }
    var label: String { ([graphics.label] + arguments).joined(separator: " ") }
    var shortLabel: String { ([graphics.shortLabel] + arguments).joined(separator: " ") }
}

/// Self-healing launches. A game left on "Automatic" gets a list of ways to start it, best first,
/// from what its files reveal (GameAnalysis). The first start with each way is watched: a game that
/// ends within its first seconds without a picture moves on to the next way, one that keeps running
/// keeps its way for good. Nightforge watches live when it can and otherwise looks at Steam's log of
/// when the game's processes started and ended, at the next launch.
enum LaunchHealth {
    /// A session this short counts as "didn't start" (crash, black window closed by the game).
    static let failureWindow: TimeInterval = 30

    /// Running past its first seconds isn't working yet: an error box keeps a game running too
    /// (Mafia II's "PhysX SDK not initialized" for a minute, 31.10.2026 – confirmed, and the game
    /// page said "Runs great"). A way is confirmed once the game has drawn frames: DXMT and
    /// Nightforge's Vulkan layer (DXVK and Vulkan games) log the frame rate 10 s after the first
    /// one – the layer only where the engine has a Vulkan loader, not under winecx. Where nothing
    /// logs frames (Wine's own Direct3D, D3DMetal, DXVK on winecx), a game still running after
    /// this long counts – once it has shown a picture (`showedPicture`, the curtain sank for its
    /// window). Without one it's still being watched: Overwatch sat there without a window at 0 %
    /// CPU on D3DMetal, and three minutes of that confirmed the way (1.11.2026). One that ends
    /// before, without a frame, stays unconfirmed – on the same way: what stopped it needn't be
    /// the graphics.
    static let drawingWindow: TimeInterval = 180

    enum Verdict: Equatable {
        case working, ended, watching
    }

    static func verdict(drewFrames: Bool, showedPicture: Bool, running: Bool, ranFor: TimeInterval) -> Verdict {
        if drewFrames { return .working }
        if !running { return .ended }
        return ranFor >= drawingWindow && showedPicture ? .working : .watching
    }

    /// What a watched start does to its way.
    enum Outcome: Equatable {
        case confirm
        /// Nothing against the way (yet).
        case keep
        /// It stopped working: watched again next time, on the same way.
        case unconfirm
        /// The graphics layer failed – or the way wasn't confirmed: on to the next one, as before.
        case nextWay
    }

    /// A start that ended within its first seconds. `drew`: it showed a picture – the curtain sank
    /// for it (`showedPicture`) or it logged frames. Then it worked, however soon it ended: the
    /// player looked in and quit (OxyRail, a few seconds on 1.11.2026, started again on DXVK). Only
    /// a graphics error still moves on. Without a picture a way not confirmed yet moves on, a
    /// confirmed one only on evidence: a crash in the log or the second such short start in a row
    /// unconfirms it. One short start alone isn't evidence – Wine's own Direct3D, D3DMetal and DXVK
    /// on winecx log no frames, and players start a game just to look (OxyRail, 22 s, 31.10.2026).
    static func earlyEnd(trusted: Bool, graphicsFailed: Bool, crashed: Bool, drew: Bool, shortEndsBefore: Int) -> Outcome {
        if graphicsFailed { return .nextWay }
        if drew { return .confirm }
        if !trusted { return .nextWay }
        return crashed || shortEndsBefore + 1 >= 2 ? .unconfirm : .keep
    }

    /// A start that ran past its first seconds, once its verdict is in: confirmed when it drew (or
    /// ran `drawingWindow`). Ending earlier without a picture changes nothing – no frames in the
    /// log says nothing on most layers; it isn't a short start either.
    static func afterFirstSeconds(_ verdict: Verdict) -> Outcome {
        switch verdict {
        case .working: return .confirm
        case .ended, .watching: return .keep
        }
    }

    /// A frame-rate line from one of the game's programs: it has drawn.
    static func drewFrames(in log: String, programs: Set<String>) -> Bool {
        FramePacing.periods(in: log, programs: programs).contains { $0.fps > 0 }
    }

    /// The ways to try, in order. `d3dMetal`: the engine carries Apple's D3DMetal, the one way
    /// Direct3D 12 runs on a Mac. DirectX 11 tries DXMT and DXVK first, which run it better, and
    /// D3DMetal (which runs Direct3D 11 too) last.
    /// A game with a DirectX 12 program of its own starts that one on D3DMetal (GameProgram, Control_DX12.exe).
    static func attempts(for analysis: GameAnalysis, profile: GameProfile?,
                         d3dMetal: Bool = Engine.d3dMetalReady, vulkanLayer: Bool = Engine.vulkanLayerLoads) -> [LaunchAttempt] {
        if analysis.usesD3D11, analysis.apis.contains(.d3d12), d3dMetal, profile?.graphics == .d3dmetal {
            // Measured to run better on DirectX 12 through D3DMetal than on DirectX 11: no -dx11 then.
            let arguments = analysis.preferD3D11Arguments
            return [LaunchAttempt(graphics: .d3dmetal), LaunchAttempt(graphics: .dxmt, arguments: arguments),
                    LaunchAttempt(graphics: .dxvk, arguments: arguments)]
        }
        if analysis.usesD3D11 || analysis.apis.isEmpty {
            let arguments = analysis.preferD3D11Arguments
            let first = profile?.graphics.flatMap { $0 == .d3dmetal && !d3dMetal ? nil : $0 } ?? Engine.defaultGraphics
            let second: GraphicsLayer = first == .dxmt ? .dxvk : .dxmt
            var list = [LaunchAttempt(graphics: first, arguments: arguments), LaunchAttempt(graphics: second, arguments: arguments)]
            // D3DMetal is the last resort: Direct3D 12 for games that would pick it, Apple's Direct3D
            // 11 for the rest – Control's DX11 build ends at once on DXMT and DXVK (2.11.2026).
            if d3dMetal {
                list.append(LaunchAttempt(graphics: .d3dmetal))
            } else if !arguments.isEmpty {
                list.append(LaunchAttempt(graphics: first))
            }
            return list
        }
        if analysis.usesD3D9 {
            // Without Nightforge's Vulkan layer (winecx) DXVK never gets a device – MoltenVK lacks
            // geometryShader and shaderCullDistance: Wine's own Direct3D only, so an early end can't
            // move on to a way that can't work here (Mafia II, 1.11.2026).
            return vulkanLayer ? [LaunchAttempt(graphics: .dxvk), LaunchAttempt(graphics: .wined3d)]
                : [LaunchAttempt(graphics: .wined3d)]
        }
        if analysis.onlyD3D12, d3dMetal {
            return [LaunchAttempt(graphics: .d3dmetal)]
        }
        // Vulkan, OpenGL and Direct3D 12 have one way each; there's nothing to switch.
        return [LaunchAttempt(graphics: Engine.defaultGraphics)]
    }

    /// The ways in the order a preset tries them. "Most compatible" starts with the safest: the
    /// layer a profile names (tested on a Mac), then Wine's own Direct3D, DXVK, DXMT, D3DMetal.
    /// A list in another order is a list of its own: switching starts it over.
    static func ladder(_ attempts: [LaunchAttempt], preset: GraphicsPreset, profile: GameProfile?) -> [LaunchAttempt] {
        guard preset == .compatible else { return attempts }
        let safest: [GraphicsLayer] = [.wined3d, .dxvk, .dxmt, .d3dmetal]
        let tested = attempts.firstIndex { $0.graphics == profile?.graphics }
        func rank(_ index: Int) -> Int {
            index == tested ? -1 : safest.firstIndex(of: attempts[index].graphics) ?? safest.count
        }
        return attempts.indices.sorted { (rank($0), $0) < (rank($1), $1) }.map { attempts[$0] }
    }

    private struct State: Codable {
        /// The attempts' ids when this was saved; a different list starts over.
        var ladder: [String]
        var index = 0
        /// The current way has worked once.
        var confirmed = false
        /// How: `proof` – it drew, or ran `drawingWindow`. nil: confirmed before that counted (it
        /// ran 30 s, which an error box does too) – checked again at its next start, and no
        /// "Runs great" until then.
        var proof: Int?
        /// Starts of the confirmed way in a row that ended within their first seconds without a
        /// picture and without an error (earlyEnd).
        var shortEnds: Int?
        /// When the current, unconfirmed way was last started.
        var startedAt: Date?

        var trusted: Bool { confirmed && proof == LaunchHealth.proof }
    }

    /// The kind of confirmation that counts (since 31.10.2026).
    static let proof = 2

    private static func key(_ game: GameID) -> String { "launchHealth.\(game.key)" }

    private static func load(_ game: GameID, _ attempts: [LaunchAttempt]) -> State {
        let ladder = attempts.map(\.id)
        if let data = UserDefaults.standard.data(forKey: key(game)),
           let state = try? JSONDecoder().decode(State.self, from: data), state.ladder == ladder {
            return state
        }
        var state = State(ladder: ladder)
        // Up to 0.2: only "DXMT failed, DXVK from now on" was remembered.
        let legacy = "health.dxmtFailed.\(game.key)"
        if UserDefaults.standard.bool(forKey: legacy), let dxvk = attempts.firstIndex(where: { $0.graphics == .dxvk }) {
            state.index = dxvk
        }
        UserDefaults.standard.removeObject(forKey: legacy)
        UserDefaults.standard.removeObject(forKey: "health.launch.\(game.key)")
        return state
    }

    private static func save(_ game: GameID, _ state: State) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key(game)) }
    }

    /// The way to start the game now.
    static func current(_ game: GameID, _ attempts: [LaunchAttempt]) -> (index: Int, confirmed: Bool) {
        let state = load(game, attempts)
        return (min(state.index, max(attempts.count - 1, 0)), state.trusted)
    }

    /// How it stands without touching what's saved: nil when the game hasn't been started this way yet.
    static func peek(_ game: GameID, _ attempts: [LaunchAttempt]) -> (index: Int, confirmed: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key(game)),
              let state = try? JSONDecoder().decode(State.self, from: data), state.ladder == attempts.map(\.id)
        else { return nil }
        return (min(state.index, max(attempts.count - 1, 0)), state.trusted)
    }

    static func recordStart(_ game: GameID, _ attempts: [LaunchAttempt], at date: Date = Date()) {
        var state = load(game, attempts)
        state.startedAt = date
        save(game, state)
    }

    static func confirm(_ game: GameID, _ attempts: [LaunchAttempt]) {
        var state = load(game, attempts)
        state.confirmed = true
        state.proof = proof
        state.shortEnds = nil
        state.startedAt = nil
        save(game, state)
    }

    /// How many starts of the confirmed way in a row ended early without a picture or an error.
    static func shortEnds(_ game: GameID, _ attempts: [LaunchAttempt]) -> Int { load(game, attempts).shortEnds ?? 0 }

    /// Counts such a start – or starts over after one that drew, or ran past its first seconds.
    static func noteStart(_ game: GameID, _ attempts: [LaunchAttempt], short: Bool) {
        var state = load(game, attempts)
        state.shortEnds = short ? (state.shortEnds ?? 0) + 1 : nil
        save(game, state)
    }

    /// A confirmed way that stopped working (`earlyEnd`): it keeps its place and is watched again
    /// at the next start.
    static func unconfirm(_ game: GameID, _ attempts: [LaunchAttempt]) {
        var state = load(game, attempts)
        state.confirmed = false
        state.proof = nil
        state.shortEnds = nil
        save(game, state)
    }

    /// Moves on to the next way. False when there is none: then the list starts over next time.
    static func advance(_ game: GameID, _ attempts: [LaunchAttempt]) -> Bool {
        var state = load(game, attempts)
        state.startedAt = nil
        state.confirmed = false
        state.proof = nil
        let next = state.index + 1 < attempts.count
        state.index = next ? state.index + 1 : 0
        save(game, state)
        return next
    }

    /// Games whose way is confirmed, with that way's id: what they ran well with so far
    /// (EngineRollback starts from it).
    static func confirmedWays(_ defaults: UserDefaults = .standard) -> [GameID: String] {
        var ways: [GameID: String] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("launchHealth.") {
            let stored = String(key.dropFirst("launchHealth.".count))
            // Only store keys ("steam.570"): the bare app IDs GameIDMigration left behind are older copies.
            guard Int(stored) == nil, let game = GameID(key: stored), let data = value as? Data,
                  let state = try? JSONDecoder().decode(State.self, from: data), state.trusted,
                  state.ladder.indices.contains(state.index)
            else { continue }
            ways[game] = state.ladder[state.index]
        }
        return ways
    }

    /// Choosing a layer by hand starts over: the player wants to try for themselves.
    static func reset(_ game: GameID) {
        UserDefaults.standard.removeObject(forKey: quitKey(game))
        UserDefaults.standard.removeObject(forKey: pictureKey(game))
        UserDefaults.standard.removeObject(forKey: key(game))
        UserDefaults.standard.removeObject(forKey: "health.dxmtFailed.\(game.key)")
    }

    /// Quit Game in the overlay: that end is the player's, whatever its timing or exit code – never
    /// a start that didn't take, here or in Steam's log later (`review`). Sonic Mania, quit so on
    /// 1.11., counted as one, and its next start would have gone another way.
    static func playerQuit(_ game: GameID, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: quitKey(game))
    }

    /// Whether the player quit the game in the overlay since `start`.
    static func quitByPlayer(_ game: GameID, since start: Date) -> Bool {
        guard let quit = UserDefaults.standard.object(forKey: quitKey(game)) as? Date else { return false }
        return quit >= start
    }

    private static func quitKey(_ game: GameID) -> String { "launchHealth.playerQuit.\(game.key)" }

    /// The curtain sank for the game: its window in picture size had the front. Kept like Quit
    /// Game, so a start that ends soon after still counts as one that showed a picture – in the
    /// start flow (`earlyEnd`) and in Steam's log later (`review`), also when a new start called
    /// the watch off.
    static func pictureShown(_ game: GameID, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: pictureKey(game))
    }

    /// Whether the curtain sank for the game since `start`.
    static func showedPicture(_ game: GameID, since start: Date) -> Bool {
        guard let shown = UserDefaults.standard.object(forKey: pictureKey(game)) as? Date else { return false }
        return shown >= start
    }

    private static func pictureKey(_ game: GameID) -> String { "launchHealth.picture.\(game.key)" }

    /// Looks at how the last unconfirmed start went when Nightforge wasn't there to watch it.
    static func review(_ game: GameID, _ attempts: [LaunchAttempt], steamRoot: URL) {
        let state = load(game, attempts)
        guard !state.trusted, let started = state.startedAt, !quitByPlayer(game, since: started),
              let appID = game.steamAppID, let span = sessionSpan(appID: appID, since: started, steamRoot: steamRoot)
        else { return }
        if span < failureWindow, showedPicture(game, since: started) {
            confirm(game, attempts)  // a picture, then the end: it started (earlyEnd)
        } else if span < failureWindow {
            _ = advance(game, attempts)
        } else if span >= drawingWindow {
            // Without Nightforge watching, Steam's log only says how long it ran (`drawingWindow`).
            confirm(game, attempts)
        }
    }

    /// What the player should know about the way Nightforge picked, if it isn't the first.
    static func note(_ game: GameID, _ attempts: [LaunchAttempt]) -> String? {
        let (index, _) = current(game, attempts)
        guard index > 0 else { return nil }
        // Which graphics layer that is shows in the game's options; here it's enough to know it was handled.
        return L10n.t("This game didn't start the usual way, so Nightforge now starts it another way, automatically.")
    }

    /// How long the game's processes ran in the first session after `since`: from the first
    /// "Game process added" to the moment the last of them was removed. nil when Steam's log
    /// doesn't show a finished session (never started, still running, or log gone).
    static func sessionSpan(appID: Int, since: Date, steamRoot: URL) -> TimeInterval? {
        let logs = ["logs/console_log.previous.txt", "logs/console_log.txt"].map { steamRoot.appendingPathComponent($0) }
        let text = logs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        // Launchers end after a few seconds and start the game itself; a process that follows
        // within this gap still belongs to the same session.
        let handOver: TimeInterval = 15
        var first: Date?
        var ended: Date?
        var running = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("[") {
            let added = line.contains("Game process added : AppID \(appID) ")
            let removed = line.contains("Game process removed: AppID \(appID) ")
            guard added || removed,
                  let close = line.firstIndex(of: "]"),
                  let time = formatter.date(from: String(line[line.index(after: line.startIndex)..<close])),
                  time >= since.addingTimeInterval(-2)
            else { continue }
            let process = line.range(of: "ProcID ").map { String(line[$0.upperBound...].prefix { $0.isNumber }) } ?? ""
            if added {
                if let ended, time.timeIntervalSince(ended) > handOver { break }  // a later session
                first = first ?? time
                ended = nil
                running.insert(process)
            } else if first != nil {
                running.remove(process)
                if running.isEmpty { ended = time }
            }
        }
        guard let first, let ended, running.isEmpty else { return nil }
        return ended.timeIntervalSince(first)
    }
}

/// What Nightforge found out about a game by itself, beyond the profile list: runtimes its
/// programs turned out to need, and where its last start begins in GameLog.
enum LearnedFixes {
    private static func winetricksKey(_ game: GameID) -> String { "learned.winetricks.\(game.key)" }
    private static func markKey(_ game: GameID) -> String { "learned.logMark.\(game.key)" }

    static func winetricks(_ game: GameID) -> [String] {
        UserDefaults.standard.stringArray(forKey: winetricksKey(game)) ?? []
    }

    static func addWinetricks(_ verbs: [String], for game: GameID) {
        let known = winetricks(game)
        UserDefaults.standard.set(known + verbs.filter { !known.contains($0) }, forKey: winetricksKey(game))
    }

    private static func noAVXKey(_ game: GameID) -> String { "learned.noAVX.\(game.key)" }

    /// The game crashed on an instruction Rosetta can't run while AVX was advertised: it starts
    /// without the hint from now on.
    static func noAVX(_ game: GameID) -> Bool { UserDefaults.standard.bool(forKey: noAVXKey(game)) }

    static func setNoAVX(_ game: GameID) { UserDefaults.standard.set(true, forKey: noAVXKey(game)) }

    /// Whether Rosetta advertises AVX to this game.
    static func avx(_ game: GameID, profile: GameProfile?) -> Bool {
        profile?.avx != false && !noAVX(game)
    }

    static func setLastLaunch(_ game: GameID, logMark: UInt64) {
        UserDefaults.standard.set(String(logMark), forKey: markKey(game))
    }

    static func lastLaunchMark(_ game: GameID) -> UInt64? {
        UserDefaults.standard.string(forKey: markKey(game)).flatMap(UInt64.init)
    }
}
