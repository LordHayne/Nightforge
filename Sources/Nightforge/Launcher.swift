import Foundation

enum AfterLaunch: String, CaseIterable, Identifiable {
    case quit, hide, stay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quit: return L10n.t("Quit launcher")
        case .hide: return L10n.t("Hide launcher")
        case .stay: return L10n.t("Keep open")
        }
    }
}

enum Prefs {
    enum Keys {
        static let bottlesRoot = "bottlesRoot"
        static let runnerPath = "runnerPath"
        static let afterLaunch = "afterLaunch"
        static let performanceHUD = "performanceHUD"
        static let gameMode = "gameMode"
        static let sharpAndSmooth = "sharpAndSmooth"
        static let geforceNowExplained = "geforceNowExplained"
        static let padGlyphs = "padGlyphs"
        /// How many game starts showed the overlay's tip on the loading screen (LaunchTip).
        static let launchTipShown = "launchTipShown"
        static let notifyDownloads = "notifyDownloads"
        static let reduceMotion = "reduceMotion"
        static let largerText = "largerText"
        static let saveBattery = "saveBattery"
    }

    /// On battery, games are capped at 30 FPS to last longer. Off by default: the player chooses it.
    static var saveBattery: Bool {
        UserDefaults.standard.bool(forKey: Keys.saveBattery)
    }

    /// "Reduce motion": "on" or "off" once changed in Settings, else whatever macOS says.
    static func reduceMotion(system: Bool, stored: String) -> Bool {
        switch stored {
        case "on": return true
        case "off": return false
        default: return system
        }
    }

    /// A macOS notification when a download finishes while Nightforge isn't in front. On by default.
    static var notifyDownloads: Bool {
        UserDefaults.standard.object(forKey: Keys.notifyDownloads) as? Bool ?? true
    }

    /// Button labels in hints: the connected controller's own, or always Xbox's or PlayStation's.
    static var padGlyphs: PadSymbols.Style {
        PadSymbols.Style(rawValue: UserDefaults.standard.string(forKey: Keys.padGlyphs) ?? "") ?? .automatic
    }

    /// "Sharp & smooth": MetalFX upscaling to full Retina sharpness and an even frame rate that
    /// fits the display, for every game that doesn't choose otherwise. On by default.
    static var sharpAndSmooth: Bool {
        UserDefaults.standard.object(forKey: Keys.sharpAndSmooth) as? Bool ?? true
    }

    /// macOS Game Mode for games run by Nightforge's own Steam (see Engine.installGameBundle).
    /// On by default; the switch is there for the rare game whose sound crackles with it.
    static var gameMode: Bool {
        UserDefaults.standard.object(forKey: Keys.gameMode) as? Bool ?? true
    }

    /// FPS display in games run by Nightforge's own Steam (Metal HUD for DXMT, DXVK's for DXVK).
    static var performanceHUD: Bool {
        UserDefaults.standard.bool(forKey: Keys.performanceHUD)
    }

    static var bottlesRoot: URL {
        let stored = UserDefaults.standard.string(forKey: Keys.bottlesRoot) ?? ""
        let path = stored.isEmpty ? LibraryScanner.defaultBottlesRoot().path : (stored as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Empty setting = find CrossOver automatically.
    static var runnerPath: String {
        let stored = UserDefaults.standard.string(forKey: Keys.runnerPath) ?? ""
        return stored.isEmpty ? Launcher.detectRunner() : (stored as NSString).expandingTildeInPath
    }

    static var afterLaunch: AfterLaunch {
        // Hidden – behind the game, which no longer hides the app (LibraryModel.stepBack), the same
        // as kept open – Nightforge is back the moment the game ends; quitting frees a little
        // memory and comes back too, a few seconds later.
        if GameTest.active { return .stay }  // the game test starts the next game from it
        return AfterLaunch(rawValue: UserDefaults.standard.string(forKey: Keys.afterLaunch) ?? "") ?? .hide
    }
}

/// Which translation layer runs a game's Direct3D 10/11.
enum GraphicsLayer: String, Codable, CaseIterable, Identifiable {
    /// Nightforge's default (see Engine.defaultGraphics).
    case automatic
    /// DXMT: Direct3D straight to Metal.
    case dxmt
    /// DXVK: Direct3D → Vulkan → MoltenVK → Metal.
    case dxvk
    /// Wine's own Direct3D 9 on OpenGL, for older games DXVK can't run.
    case wined3d
    /// Apple's D3DMetal (Game Porting Toolkit): Direct3D 10–12 to Metal, the way DirectX 12 runs.
    case d3dmetal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .dxmt: return "DXMT (Metal)"
        case .dxvk: return "DXVK (Vulkan)"
        case .wined3d: return "WineD3D (OpenGL)"
        case .d3dmetal: return "D3DMetal (Metal)"
        }
    }

    /// For "Automatic (DXMT)".
    var shortLabel: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wined3d: return "WineD3D"
        case .d3dmetal: return "D3DMetal"
        }
    }

    /// DXMT upscales with MetalFX itself; DXVK and games drawing with Vulkan get it from
    /// Nightforge's Vulkan layer; D3DMetal hands a game's DLSS to MetalFX. WineD3D draws through
    /// OpenGL, which MetalFX can't reach.
    var upscales: Bool { self != .wined3d }
}

/// Automatic follows the global "Sharp & smooth" setting; on and off override it for one game.
enum Choice: String, Codable, CaseIterable {
    case automatic, on, off
}

/// A game's graphics in one choice. Automatic is what the profile says and Nightforge learns; the
/// next three fix the frame limit and MetalFX (decided 27.10.); Custom is what the expert options say.
enum GraphicsPreset: String, Codable, CaseIterable, Identifiable {
    case automatic
    /// "Sharp & smooth" fixed: MetalFX and an even share of the display's rate (60 FPS on 120 Hz).
    case balanced
    /// MetalFX without a frame limit.
    case fastest
    /// The safest layer first (LaunchHealth.ladder), no MetalFX, 60 FPS.
    case compatible
    case custom

    var id: String { rawValue }

    /// The ones to pick; Custom comes from changing an expert option.
    static let choices: [GraphicsPreset] = [.automatic, .balanced, .fastest, .compatible]

    /// What "Most compatible" holds a game to.
    static let compatibleLimit = 60

    var label: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .balanced: return L10n.t("Balanced")
        case .fastest: return L10n.t("Fastest")
        case .compatible: return L10n.t("Most compatible")
        case .custom: return L10n.t("Custom")
        }
    }

    var help: String {
        switch self {
        case .automatic: return L10n.t("What the profile for this game says and what Nightforge learns while you play – the best choice for most games.")
        case .balanced: return L10n.t("MetalFX sharpness where the game can use it, and an even frame rate that fits your display (60 FPS on a 120 Hz screen).")
        case .fastest: return L10n.t("The highest frame rate: MetalFX upscaling, no frame limit.")
        case .compatible: return L10n.t("The slower, safest graphics path: no MetalFX, 60 FPS. For games that crash or show a black screen.")
        case .custom: return L10n.t("Custom: your own choice in the expert options below.")
        }
    }
}

struct GameOptions: Codable, Equatable {
    /// The graphics in one choice. `graphics`, `frameLimit` and `upscaling` count for Custom; with
    /// any other preset they stay automatic and the preset decides (`resolved`).
    var preset = GraphicsPreset.automatic
    var metalHUD = false
    var extraArgs = ""
    var graphics = GraphicsLayer.automatic
    /// Frames per second the game is held to: nil = automatic ("Sharp & smooth"), 0 = no limit.
    var frameLimit: Int?
    /// MetalFX spatial upscaling of the game's picture (DXMT, DXVK and Vulkan).
    var upscaling = Choice.automatic
    /// HDR for games that draw through Vulkan (themselves or via DXVK); off, since under Wine it
    /// mostly looks washed out (wrapper/nightforge-vulkan-layer.c).
    var hdr = false
    /// Mac or Windows version, for games Steam has both of (VersionChoice).
    var version = GameVersion.automatic
    /// The program to start instead of the store's, relative to the game folder; "" = automatic
    /// (GameProgram). Epic's and GOG's games only: Steam picks its own.
    var program = ""

    static let frameLimits = [0, 30, 40, 60, 120]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case preset, metalHUD, extraArgs, graphics, fps, metalFX, hdr, version, program
        // 0.1.4 stored these; their defaults (0, false) meant "untouched", so they read as automatic.
        case frameLimit, upscaling
    }

    // Options saved before a field existed decode with that field's default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        extraArgs = try c.decodeIfPresent(String.self, forKey: .extraArgs) ?? ""
        graphics = try c.decodeIfPresent(GraphicsLayer.self, forKey: .graphics) ?? .automatic
        let legacyLimit = try c.decodeIfPresent(Int.self, forKey: .frameLimit) ?? 0
        frameLimit = try c.decodeIfPresent(Int.self, forKey: .fps) ?? (legacyLimit > 0 ? legacyLimit : nil)
        let legacyUpscaling = try c.decodeIfPresent(Bool.self, forKey: .upscaling) ?? false
        upscaling = try c.decodeIfPresent(Choice.self, forKey: .metalFX) ?? (legacyUpscaling ? .on : .automatic)
        hdr = try c.decodeIfPresent(Bool.self, forKey: .hdr) ?? false
        version = (try? c.decodeIfPresent(GameVersion.self, forKey: .version)) ?? .automatic
        program = (try? c.decodeIfPresent(String.self, forKey: .program)) ?? ""
        // Before the presets (and a preset from a newer Nightforge): expert options set by hand are Custom.
        preset = (try? c.decodeIfPresent(GraphicsPreset.self, forKey: .preset))
            ?? (graphics == .automatic && frameLimit == nil && upscaling == .automatic ? .automatic : .custom)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset, forKey: .preset)
        try c.encode(metalHUD, forKey: .metalHUD)
        try c.encode(extraArgs, forKey: .extraArgs)
        try c.encode(graphics, forKey: .graphics)
        try c.encodeIfPresent(frameLimit, forKey: .fps)
        try c.encode(upscaling, forKey: .metalFX)
        if hdr { try c.encode(hdr, forKey: .hdr) }
        if version != .automatic { try c.encode(version, forKey: .version) }
        if !program.isEmpty { try c.encode(program, forKey: .program) }
    }

    /// The frame limit actually used: the game's own choice, or with "Sharp & smooth" half the
    /// display's refresh rate on fast displays (60 on 120 Hz) and the refresh rate on 60 Hz ones,
    /// so every frame lasts the same number of screen refreshes.
    /// A game profile (profiles/profiles.json) can set its own automatic limit.
    func effectiveFrameLimit(displayRefreshRate: Int, profile: GameProfile? = nil) -> Int {
        if let frameLimit { return frameLimit }
        guard Prefs.sharpAndSmooth else { return 0 }
        return profile?.frameLimit ?? Self.standardFrameLimit(displayRefreshRate, lowPower: Hardware.current.lowPower)
    }

    /// Half the refresh rate on fast displays (60 on 120 Hz), the refresh rate on 60 Hz ones – the
    /// fixed limit of "Balanced", whatever the power mode.
    static func evenLimit(_ refreshRate: Int) -> Int {
        standardFrameLimit(refreshRate, lowPower: false)
    }

    /// The options a start goes by: Automatic and Custom as stored, the other presets with their
    /// frame limit and MetalFX fixed – so FramePacing doesn't learn against them. Their layer stays
    /// automatic: LaunchHealth tries the ways in the preset's order. A game whose profile rules
    /// MetalFX out goes without (WineD3D can't upscale anyway); a profile's frame limit stands for Balanced.
    func resolved(refreshRate: Int, profile: GameProfile?) -> GameOptions {
        var options = self
        let metalFX: Choice = profile?.metalFX == false ? .off : .on
        switch preset {
        case .automatic, .custom:
            return self
        case .balanced:
            options.upscaling = metalFX
            options.frameLimit = profile?.frameLimit ?? Self.evenLimit(refreshRate)
        case .fastest:
            options.upscaling = metalFX
            options.frameLimit = 0
        case .compatible:
            options.upscaling = .off
            options.frameLimit = GraphicsPreset.compatibleLimit
        }
        options.graphics = .automatic
        return options
    }

    /// Picks a preset; the expert options go back to automatic, as they count for Custom only.
    mutating func choose(_ preset: GraphicsPreset) {
        self.preset = preset
        graphics = .automatic
        frameLimit = nil
        upscaling = .automatic
    }

    /// "Sharp & smooth" without a profile: an even share of the refresh rate. In Low Power Mode,
    /// with CPU and GPU held back, one share lower (40 instead of 60 on 120 Hz), so frames stay even.
    static func standardFrameLimit(_ refreshRate: Int, lowPower: Bool) -> Int {
        guard refreshRate > 0 else { return 0 }
        return refreshRate / ((refreshRate >= 100 ? 2 : 1) + (lowPower ? 1 : 0))
    }

    /// A game profile can rule MetalFX out for games it doesn't suit. Automatic upscales only on a
    /// Retina screen: on a screen without (an external monitor, many TV modes) the upscaled frame
    /// would only be scaled down again, GPU time spent for nothing.
    func effectiveUpscaling(profile: GameProfile? = nil) -> Bool {
        switch upscaling {
        case .on: return true
        case .off: return false
        case .automatic: return Prefs.sharpAndSmooth && profile?.metalFX != false && Hardware.current.retina
        }
    }
}

enum GameOptionsStore {
    private static func key(_ game: GameID) -> String { "options.\(game.key)" }

    static func load(_ game: GameID) -> GameOptions {
        guard let data = UserDefaults.standard.data(forKey: key(game)),
              let options = try? JSONDecoder().decode(GameOptions.self, from: data)
        else { return GameOptions() }
        return options
    }

    static func save(_ options: GameOptions, for game: GameID) {
        if options == GameOptions() {
            UserDefaults.standard.removeObject(forKey: key(game))
        } else if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key(game))
        }
    }

    /// A preset picked outside the options sheet (after a failed start, in "Welcome back").
    static func choose(_ preset: GraphicsPreset, for game: GameID) {
        var options = load(game)
        options.choose(preset)
        save(options, for: game)
    }
}

enum LaunchError: LocalizedError {
    case runnerMissing(String)

    var errorDescription: String? {
        switch self {
        case .runnerMissing(let path):
            return L10n.t("Wine was not found at %@. Install CrossOver or enter the path to your wine binary in Settings.", path)
        }
    }
}

/// Follows Steam's console log after a launch request so Nightforge knows whether the game really
/// started, or whether Steam is waiting on a question (licence, first-time setup) in its own window.
/// Steam writes Windows line ends, and "\r\n" is one Character in Swift: lines are split with
/// `isNewline`, never on "\n".
struct LaunchWatcher {
    enum Event {
        case needsConfirmation
        /// Steam got its answer (or never needed one – it logs routine steps the same way).
        case continued
        case running
        case cancelled
        case failed
    }

    private let log: URL
    private let appID: Int
    private var offset: UInt64
    /// Steam logged the "-applaunch" request, i.e. it's alive and took it.
    private(set) var steamReceivedLaunch = false
    /// steam:// commands Steam turned away because it hadn't finished starting ("not allowed yet").
    private(set) var rejectedCommands = 0
    /// Steam was already waiting on a question for this game before the launch (e.g. an earlier
    /// attempt); the new request just queues behind it.
    private var openQuestion = false

    /// Remembers where the log ends now, so only lines written after the launch count.
    init(steamRoot: URL, appID: Int) {
        log = steamRoot.appendingPathComponent("logs/console_log.txt")
        self.appID = appID
        offset = (try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? UInt64) ?? 0

        if let handle = try? FileHandle(forReadingFrom: log) {
            try? handle.seek(toOffset: offset > 65_536 ? offset - 65_536 : 0)
            let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
            try? handle.close()
            let last = tail.split(whereSeparator: \.isNewline).last { $0.contains("GameAction [AppID \(appID),") }
            openQuestion = last?.contains("waiting for user response") ?? false
        }
    }

    /// Newest relevant event since the last call, if any.
    mutating func poll() -> Event? {
        if openQuestion {
            openQuestion = false
            return .needsConfirmation
        }
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }  // Steam started a fresh log
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)

        var event: Event?
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            if SteamCommands.isLaunch(line, appID: appID) { steamReceivedLaunch = true }
            if line.contains("ExecuteSteamURL"), line.contains("not allowed yet") {
                rejectedCommands += 1
            }
            guard mentionsApp(line) else { continue }
            if line.contains("GameAction") { steamReceivedLaunch = true }
            if line.contains("Game process added") || line.contains("changed task to Completed") {
                event = .running
            } else if line.contains("waiting for user response") {
                event = .needsConfirmation
            } else if line.contains("continues with user response") {
                event = .continued
            } else if line.contains("GameAction"), line.localizedCaseInsensitiveContains("cancel") {
                event = .cancelled
            } else if line.contains("GameAction"), line.localizedCaseInsensitiveContains("failed") {
                event = .failed
            }
        }
        return event
    }

    /// "AppID 10" must not match "AppID 1000": the ID has to end there.
    private func mentionsApp(_ line: Substring) -> Bool {
        var rest = line[...]
        while let range = rest.range(of: "AppID \(appID)") {
            let next = rest[range.upperBound...].first
            if next == nil || !next!.isNumber { return true }
            rest = rest[range.upperBound...]
        }
        return false
    }
}

/// Whether the running Steam still takes commands. A "-applaunch" client hands its command to it
/// and ends, and Steam logs "ExecCommandLine" in the same second: on 31.10.2026 the client ran
/// 16:36:10.854–11.077 (the helper's start and end in macOS's log) and console_log has
/// "[16:36:11] ExecCommandLine: … -applaunch 3907790", the same at 16:36:58 and 16:39:11. From
/// about 16:46 that signed-in Steam took none: the clients at 16:52:32, 16:52:44, 17:21:24 and
/// 17:21:37 ended as quickly (so how long the client runs tells nothing), but nothing reached
/// console_log after 16:46:43 – while configstore_log and appinfo_log were still written until
/// 17:09, so quiet logs are no sign either. A request that arrives while Steam is still starting
/// can get lost (LibraryModel resends it); this is for a Steam that was done starting.
enum SteamCommands {
    /// Far more than the second it takes.
    static let answerWithin: TimeInterval = 15

    /// Steam was running, signed in and done starting when the command went out, and hasn't
    /// logged it `sentAgo` seconds later.
    static func hung(steamWasReady: Bool, received: Bool, sentAgo: TimeInterval) -> Bool {
        steamWasReady && !received && sentAgo >= answerWithin
    }

    /// "ExecCommandLine: ""C:\…\steam.exe" … -silent -applaunch 3907790"" – Steam took a start of `appID`.
    static func isLaunch(_ line: Substring, appID: Int) -> Bool {
        line.contains("ExecCommandLine") && (line.hasSuffix("-applaunch \(appID)\"") || line.contains("-applaunch \(appID) "))
    }
}

/// Starts a game through the Windows Steam client in its bottle – one process call, nothing kept running.
enum Launcher {
    static let crossOverCandidates = [
        "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
        NSHomeDirectory() + "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
    ]

    static func detectRunner() -> String {
        crossOverCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? crossOverCandidates[0]
    }

    /// `frameLimit`: what the game is held to (FramePacing.automaticLimit or the player's choice).
    /// The client it starts: it ends once it has handed the command to the running Steam, or is
    /// that Steam when none ran.
    @discardableResult
    static func launch(_ game: Game, runnerPath: String, options: GameOptions, profile: GameProfile? = nil,
                       frameLimit: Int = 0, extraArguments: [String] = []) throws -> DetachedProcess {
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw LaunchError.runnerMissing(runnerPath)
        }

        let runner = URL(fileURLWithPath: runnerPath)
        // If Steam isn't running yet, this call starts it, so it needs the same game settings.
        var environment = game.bottle.isBuiltIn
            ? Engine.environment(wine: runner).merging(Engine.steamEnvironment) { _, new in new }
            : ProcessInfo.processInfo.environment
        var arguments: [String] = []

        if game.bottle.isBuiltIn {
            environment["WINEDLLOVERRIDES"] = Engine.steamDLLOverrides
            environment["WINEDEBUG"] = GameLog.wineDebug
            Engine.installWebHelperWrapper()
        } else if runnerPath.contains("CrossOver.app") {
            arguments += ["--bottle", game.bottle.name]
        } else {
            // Plain Wine / Whisky / GPTK: the bottle is the prefix
            environment["WINEPREFIX"] = game.bottle.url.path
        }
        if game.bottle.isBuiltIn {
            Engine.writeGameConfigs(installDir: game.installDir,
                                    frameLimit: frameLimit,
                                    upscaling: options.effectiveUpscaling(profile: profile),
                                    vulkanSamplers: profile?.vulkanSamplers, hdr: options.hdr)
            Engine.applyFileEdits(profile?.fileEdits ?? [], installDir: game.installDir, game: game.gameID.key)
            Engine.applyIniSettings(profile?.iniSettings ?? [])
            Engine.applyGameSettings(options.graphics, profile: profile, installDir: game.installDir, wine: runner)
            GameResolution.fit(game, profile: profile, retina: Engine.launchRetina, wine: runner)
            // This call starts Steam when it isn't running: in the Retina mode the game wants, and
            // with the Guide button left to Nightforge (SteamGuideButton).
            if !Engine.isSteamRunning {
                Engine.applyRetinaMode(runner)
                SteamGuideButton.turnOff(steamRoot: Engine.steamRoot)
            }
        }
        // CrossOver bottles: the game inherits this process's environment. Nightforge's own
        // games get the HUD from the background Steam instead (Prefs.performanceHUD).
        if options.metalHUD && !game.bottle.isBuiltIn {
            environment["MTL_HUD_ENABLED"] = "1"
        }

        arguments += [game.steamExeWindowsPath]
        if game.bottle.isBuiltIn { arguments += Engine.steamArguments }
        arguments += ["-silent", "-applaunch", String(game.appID)]
        if game.bottle.isBuiltIn {
            arguments += SteamCatalog.antiCheatOffArguments(appID: game.appID, steamRoot: game.steamRoot)
            arguments += profile?.arguments ?? []
            arguments += extraArguments
        }
        arguments += splitArguments(options.extraArgs)

        let program = game.bottle.isBuiltIn ? Engine.loader(for: runner) : runner
        if program != runner { environment["WINELOADER"] = program.path }
        // A CrossOver bottle is CrossOver's Wine, not Nightforge's: no sandbox there.
        let process = try WineSandbox.process(program, arguments, sandboxed: game.bottle.isBuiltIn)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        // When Steam isn't running yet, this becomes the Steam its games inherit output from.
        let log = game.bottle.isBuiltIn ? GameLog.handleForSteam() : nil
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        try process.run()
        return process
    }

    /// A game from another store (Epic, GOG), started straight with Nightforge's engine: the game's
    /// settings and graphics layer as for Steam's games, the store's parameters, and its output into
    /// the game log. `environment`: `Engine.directLaunchEnvironment`.
    static func launchDirect(_ game: Game, command: StoreLaunchCommand, runnerPath: String, options: GameOptions,
                             profile: GameProfile?, frameLimit: Int, extraArguments: [String],
                             environment gameEnvironment: [String: String]) throws -> DetachedProcess {
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw LaunchError.runnerMissing(runnerPath)
        }
        let runner = URL(fileURLWithPath: runnerPath)
        Engine.writeGameConfigs(installDir: game.installDir, frameLimit: frameLimit,
                                upscaling: options.effectiveUpscaling(profile: profile),
                                vulkanSamplers: profile?.vulkanSamplers, hdr: options.hdr)
        Engine.applyFileEdits(profile?.fileEdits ?? [], installDir: game.installDir, game: game.gameID.key)
        Engine.applyIniSettings(profile?.iniSettings ?? [])
        Engine.applyGameSettings(options.graphics, profile: profile, installDir: game.installDir, wine: runner)
        // It joins the Wine session that runs, or starts one in the Retina mode the prefix has.
        GameResolution.fit(game, profile: profile, retina: Engine.retinaModeApplied, wine: runner)

        var environment = Engine.environment(wine: runner).merging(gameEnvironment) { _, game in game }
        // Setting up the prefix keeps Wine Mono and Gecko out; a game may need them. The Direct3D
        // choice is in the registry (AppDefaults), which an override here would beat.
        environment["WINEDLLOVERRIDES"] = nil
        environment["WINEDEBUG"] = GameLog.wineDebug
        if options.metalHUD { environment["MTL_HUD_ENABLED"] = "1" }
        environment.merge(command.environment) { _, store in store }
        // The store's program, or the one picked for the game (GameProgram). The store's parameters
        // (Epic's sign-in) go to whichever starts; another program runs in its own folder.
        let layer = options.graphics == .automatic ? (profile?.graphics ?? Engine.defaultGraphics) : options.graphics
        let program = GameProgram.resolve(store: command.executable, installDir: game.installDir, layer: layer,
                                          chosen: options.program, profile: profile?.executable)
        let otherProgram = program.standardizedFileURL.path != command.executable.standardizedFileURL.path
        if otherProgram {
            GameLog.note("\(game.name) starts \(program.lastPathComponent) on \(layer.rawValue) instead of \(command.executable.lastPathComponent)")
        }
        let loader = Engine.loader(for: runner)
        if loader != runner { environment["WINELOADER"] = loader.path }
        let process = try WineSandbox.process(loader, [Engine.windowsPath(of: program)] + command.arguments + (profile?.arguments ?? [])
            + extraArguments + splitArguments(options.extraArgs))
        process.currentDirectoryURL = otherProgram ? program.deletingLastPathComponent() : command.workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let log = GameLog.handleForSteam()
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Splits `-foo "bar baz" -x` into ["-foo", "bar baz", "-x"].
    static func splitArguments(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
