import Foundation
import Security

/// Nightforge's own free Wine setup: the engine component, one Windows environment ("prefix")
/// and the Windows Steam client inside it. Used when CrossOver isn't the chosen runner.
enum Engine {
    static let engineID = "wine"
    /// CodeWeavers' CrossOver changes on current Wine (dappermint/winecx-gptk): the engine Apple's
    /// D3DMetal runs on. Preferred over `engineID` when the component list has it; a new ID, so
    /// older Nightforge versions reading the same list keep the engine they know.
    static let winecxEngineID = "winecx"
    /// Apple's D3DMetal (Game Porting Toolkit, /redist/lib): Direct3D 10–12 → Metal.
    static let d3dMetalID = "d3dmetal"
    /// winebus.so with the SDL bus for winecx, plus SDL2 (.github/workflows/gamepad.yml): without it
    /// a DualSense or DualShock 4 never reaches Windows games on winecx.
    static let gamepadID = "gamepad"
    /// ntdll.so and winecoreaudio.so rebuilt from winecx's own source with Nightforge's patches
    /// (.github/workflows/enginefix.yml): msync without closing other files at a thread's end, and
    /// Wine 11.21's downmix for 5.1/7.1 sound. Version "<engine version>-N", for that engine only.
    static let engineFixID = "enginefix"

    static func engineComponent(in manifest: ComponentManifest) -> Component? {
        manifest.component(winecxEngineID) ?? manifest.component(engineID)
    }
    /// Nightforge's own DXMT build for Wine 11 (with winemac.so); plain upstream DXMT as fallback.
    static let graphicsID = "graphics"
    static let upstreamGraphicsID = "dxmt"
    /// What "Automatic" means: DXMT ran OxyRail better than DXVK (fewer layers, correct video
    /// memory); games that don't work with it can be switched to DXVK in their options.
    static let defaultGraphics = GraphicsLayer.dxmt

    static func graphicsComponent(in manifest: ComponentManifest) -> Component? {
        manifest.component(graphicsID) ?? manifest.component(upstreamGraphicsID)
    }
    /// DirectX 9–11 → Vulkan → Metal. Draws reliably on Wine 11 today, while DXMT can't attach to
    /// Wine 11's windows yet (that needs a patched DXMT build).
    static let dxvkID = "dxvk-macos"
    /// Vulkan → Metal for DXVK and Vulkan games, newer than the copy the engine brings along.
    static let moltenVKID = "moltenvk"
    /// KosmicKrisp, Mesa's Vulkan driver on Metal, with the Khronos loader (scripts/build-kosmickrisp.sh):
    /// under winecx DXVK's Direct3D 9 draws through it instead of MoltenVK, which lacks the geometry
    /// shaders and cull distances DXVK needs for it (Mafia II, Left 4 Dead 2: no device on MoltenVK).
    static let kosmicKrispID = "kosmickrisp"
    /// Upstream DXVK, whose Direct3D 9 goes with KosmicKrisp: it needs Vulkan 1.3 and geometry shaders,
    /// so it never runs on MoltenVK. DXVK-macOS (`dxvkID`) stays for DirectX 10/11.
    static let dxvkUpstreamID = "dxvk"
    static let steamSetupURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    static let steamExeWindowsPath = #"C:\Program Files (x86)\Steam\steam.exe"#
    /// Steam's web UI (CEF) paints a black window under Wine on macOS unless it renders in software
    /// in a single process. The single-process part is done by the steamwebhelper wrapper, which
    /// -noverifyfiles keeps Steam from "repairing" away; the CEF sandbox needs Windows features Wine lacks.
    /// Friends and chat are web views of their own that Steam keeps up in the background, rendered in
    /// software like the rest; Nightforge never shows them, so they stay off (-nofriendsui, -nochatui).
    /// Sign-in, downloads and cloud saves don't go through them. Read at Steam's start only: a Steam that
    /// runs takes them at its next start, no restart needed.
    static let steamArguments = [
        "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles",
        "-cef-disable-gpu", "-cef-disable-gpu-compositing", "-nofriendsui", "-nochatui",
    ]
    /// `steamArguments` for a start of Steam. Before its first update has put the client in place,
    /// without -noverifyfiles: told not to verify, a bootstrapper with nothing installed found
    /// nothing missing and sat there for 90 s instead of fetching the client (29.10.2026); its
    /// restarts after an update inherit the arguments. From then on Steam mustn't verify its files:
    /// it would put Valve's steamwebhelper back over the wrapper.
    static func startArguments(clientInstalled: Bool) -> [String] {
        clientInstalled ? steamArguments : steamArguments.filter { $0 != "-noverifyfiles" }
    }

    /// Settings games inherit from the background Steam. Bump `steamConfigVersion` whenever this
    /// or `steamDLLOverrides` changes, so a running Steam gets restarted with them.
    static let steamConfigVersion = 10
    static var gameEnvironment: [String: String] {
        var env = [
            // Compile shaders in the background instead of stalling the frame that first needs them.
            "DXVK_ASYNC": "1",
            // Into GameLog: libraries a game can't load, and MoltenVK's errors (not its chatter).
            "WINEDEBUG": GameLog.wineDebug,
            "MVK_CONFIG_LOG_LEVEL": "1",
            // DXVK's warnings go there as well, instead of log files in the Windows user folder.
            "DXVK_LOG_LEVEL": "warn",
            "DXVK_LOG_PATH": "none",
            // Rosetta runs AVX and AVX2 (macOS 15 and later) but only tells programs so when asked;
            // many newer games refuse to start or crash without it.
            "ROSETTA_ADVERTISE_AVX": "1",
            // DXMT keeps the shaders it has translated in the Mac's per-user cache folder by default,
            // which macOS empties at every restart – and then each game stutters through compiling
            // them all over again. The user's Caches folder keeps them (and stays out of backups).
            "DXMT_SHADER_CACHE_PATH": shaderCache.path,
        ]
        // Apple's Metal HUD: DXMT draws with Metal directly, so this is its FPS display. Only an
        // environment variable turns it on, and games get theirs from Steam, hence app-wide.
        if Prefs.performanceHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }

    /// Where DXMT keeps translated shaders, shared by all games (its entries are keyed by shader).
    static var shaderCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/dxmt", isDirectory: true)
    }

    /// Where Mesa keeps KosmicKrisp's translated shaders (MSL), next to DXMT's instead of ~/.cache.
    static var mesaShaderCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/mesa", isDirectory: true)
    }

    /// What versions up to 0.3.x also put into the user environment (HKCU\Environment), on the
    /// belief that Steam builds its games' environment from the registry. It doesn't: Wine takes the
    /// registry's variables only into the Windows side of a program started from the Mac (Steam,
    /// dlls/ntdll/unix/env.c build_initial_params), and a program another one starts – every game –
    /// keeps its parent's Unix environment (process.c spawn_process forks). So MTL_HUD_ENABLED,
    /// ROSETTA_ADVERTISE_AVX, MVK_CONFIG_LOG_LEVEL and Wine's own switches never came from there
    /// (probe 3.11.2026: WINE_LARGE_ADDRESS_AWARE in HKCU\Environment left a 32-bit child at 2 GB,
    /// in its parent's Unix environment it gave 4 GB); everything a game needs comes with Steam's
    /// own environment (steamEnvironment) or the direct start's. Worse, Wine adds the registry's
    /// after the Unix ones, and a child takes WINEDEBUG from the Windows side: a WINEDEBUG left there
    /// beat Steam's for every game. So these go, once per prefix (`applyPrefixRegistry`).
    static let formerRegistryEnvironment = ["DXVK_ASYNC", "MTL_HUD_ENABLED", "WINEDEBUG", "MVK_CONFIG_LOG_LEVEL",
                                            "DXVK_LOG_LEVEL", "DXVK_LOG_PATH", "ROSETTA_ADVERTISE_AVX", "DXMT_SHADER_CACHE_PATH"]

    /// What the prefix's registry gets from Nightforge: the controller setting, and the user
    /// environment cleared of `formerRegistryEnvironment`.
    static var prefixRegistry: String {
        "[HKEY_CURRENT_USER\\Environment]\n" + formerRegistryEnvironment.map { "\"\($0)\"=-" }.joined(separator: "\n")
            + "\n\n" + controllerRegistry
    }

    /// Bumped when `prefixRegistry` changes, so every prefix gets it once more.
    static let prefixRegistryVersion = "1"

    /// Writes `prefixRegistry` into the prefix once (its stamp there says so); a fresh prefix gets it again.
    static func applyPrefixRegistry(wine: URL) {
        try? FileManager.default.createDirectory(at: shaderCache, withIntermediateDirectories: true)
        let marker = stamp(in: prefix, name: "registry")
        guard readStamp(marker) != prefixRegistryVersion else { return }
        if importRegistry(prefixRegistry, wine: wine) { writeStamp(marker, prefixRegistryVersion) }
    }

    /// Controllers for Windows games come through SDL, which reads every common pad and hands it
    /// to games as an XInput controller. Wine would rather pass PlayStation pads through raw, but
    /// macOS keeps a DualSense or DualShock 4 in its extended report mode, which leaves a raw pad
    /// dead in DirectInput and missing from XInput. winebus reads this when Steam (re)starts.
    static let controllerRegistry = """
        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus]
        "DisableHidraw"=dword:00000001
        """

    /// Changes whenever the background Steam has to restart to hand games different settings.
    static var steamConfigSignature: String {
        let launch = launchSettings.withLock { $0 }
        return "\(steamConfigVersion)-hud\(Prefs.performanceHUD ? 1 : 0)-gamemode\(Prefs.gameMode ? 1 : 0)-"
            + launch.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + (launch.retina ? "-retina" : "") + (WineSandbox.enabled ? "-sandbox" : "")
            + (msync ? "" : "-nomsync") + (GameLog.extraWineDebug.map { "-debug" + $0 } ?? "")
            // Setting D3DMetal up gives Steam a variable it only takes at its start (`environment`).
            + (d3dMetalReady ? "-rosetta" : "")
    }

    /// Wine's Retina mode for the game about to start (GameProfile.retina): it sees the screen's full
    /// resolution rather than half of it. Wine takes it for a whole session, like the environment.
    static var launchRetina: Bool {
        get { launchSettings.withLock { $0.retina } }
        set { launchSettings.withLock { $0.retina = newValue } }
    }

    /// What the game about to start needs on top of `gameEnvironment` ("" takes a variable away).
    /// A game gets the Unix environment of the Steam that starts it, as it was when that Steam
    /// started (Wine's spawn_process forks) – the registry's never reaches it (formerRegistryEnvironment).
    /// So these go into Steam's own.
    static var launchEnvironment: [String: String] {
        get { launchSettings.withLock { $0.environment } }
        set { launchSettings.withLock { $0.environment = newValue } }
    }

    /// Both, under one lock: prepareLaunchEnvironment sets them on the main actor, a Steam start reads
    /// them in a task of its own (startSteamOffMain, stopSessionNow → steamEnvironment), and a
    /// Dictionary read while it's being replaced can crash.
    private static let launchSettings = LockedValue<(environment: [String: String], retina: Bool)>(([:], false))

    /// The environment the background Steam starts with, and its games with it.
    static var steamEnvironment: [String: String] {
        var env = gameEnvironment
        for (name, value) in launchEnvironment { env[name] = value.isEmpty ? nil : value }
        return env
    }

    /// Sets what a game needs from Steam's environment: Rosetta's AVX hint, and D3DMetal's
    /// settings, which it only takes from there (Apple's readme): D3DM_MAX_FPS caps the frame rate,
    /// D3DM_ENABLE_METALFX hands DLSS to MetalFX. A game on another layer leaves D3DMetal's as they
    /// are, so going back and forth costs no restart. `retina`: Wine's Retina mode, which the
    /// session has to start with as well. `environment`: the game's own Wine switches
    /// (GameEnvironment), which the game before it may have had others of. `vulkan`: the driver its
    /// Vulkan goes to (`vulkanDriver`), nil leaves the one Steam has. `vulkanLoader`: the engine
    /// test's loader (vulkanLoaderEnvironment), over those – never with KosmicKrisp, which gives way
    /// to it (`kosmicKrispReady`). Once its switch is off, what it left in the session goes too, unless
    /// the game's own switches set it. True when the running Steam has to restart.
    static func prepareLaunchEnvironment(avx: Bool, d3dMetal: Bool, frameLimit: Int, upscaling: Bool,
                                         retina: Bool = false, environment: [String: String] = [:],
                                         vulkan: VulkanDriver? = nil, vulkanLoader: [String: String] = [:],
                                         defaults: UserDefaults = .standard) -> Bool {
        let launch = launchSettings.withLock { $0 }
        var wanted = launch.environment
        wanted["ROSETTA_ADVERTISE_AVX"] = avx ? nil : ""
        for name in GameEnvironment.allowed.keys { wanted[name] = environment[name] ?? "" }
        if d3dMetal {
            wanted["D3DM_MAX_FPS"] = frameLimit > 0 ? String(frameLimit) : ""
            wanted["D3DM_ENABLE_METALFX"] = upscaling ? "1" : ""
        }
        switch vulkan {
        case .kosmicKrisp(let folder):
            wanted.merge(kosmicKrispEnvironment(folder)) { _, new in new }
            wanted["VK_ADD_IMPLICIT_LAYER_PATH"] = nil
        // A game's own switch of the same name (GameEnvironment: CX_ACTIVE_GRAPHICS_BACKEND) stays;
        // KosmicKrisp's start needs "wined3d" there and takes it over.
        case .moltenVK:
            for name in kosmicKrispVariables + ["VK_ADD_IMPLICIT_LAYER_PATH"] where environment[name] == nil { wanted[name] = nil }
        case nil:
            // Steam keeps the driver it has. Its library (CX_LIBVULKAN) counts only with "wined3d", so a
            // game without a backend switch of its own leaves that as it is too.
            if environment["CX_ACTIVE_GRAPHICS_BACKEND"] == nil, launch.environment["CX_LIBVULKAN"]?.isEmpty == false {
                wanted["CX_ACTIVE_GRAPHICS_BACKEND"] = launch.environment["CX_ACTIVE_GRAPHICS_BACKEND"]
            }
        }
        if !vulkanLoader.isEmpty {
            for name in vulkanLoaderNames { wanted[name] = vulkanLoader[name] }
            wanted["CX_ACTIVE_GRAPHICS_BACKEND"] = vulkanLoader["CX_ACTIVE_GRAPHICS_BACKEND"]
        } else if wanted["VK_ADD_IMPLICIT_LAYER_PATH"]?.isEmpty == false, !vulkanLoaderSwitchedOn(defaults: defaults) {
            // The loader is still in the session (nothing else sets the layer path; KosmicKrisp and MoltenVK
            // take it away) and its switch is off. While it's on, a game without Vulkan leaves it, no restart.
            for name in vulkanLoaderNames + ["CX_ACTIVE_GRAPHICS_BACKEND"] where environment[name] == nil { wanted[name] = nil }
        }
        wanted = wanted.filter { name, value in (value.isEmpty ? nil : value) != gameEnvironment[name] }
        launchSettings.withLock { [wanted] in $0 = (wanted, retina) }
        return wanted != launch.environment || retina != launch.retina
    }

    /// Puts Wine's Retina mode where `launchRetina` wants it, with Steam down. Wine shows a session
    /// the screen the way it was when the session began, so the one regedit opens ends as well.
    static func applyRetinaMode(_ wine: URL, defaults: UserDefaults = .standard) {
        let key = "retinaMode"
        // Never under a running game: ending the session would end it too.
        // Any Windows game (Steam's, Epic's, GOG's), and not when that can't be told.
        guard defaults.bool(forKey: key) != launchRetina, windowsGameRunningKnown == false else { return }
        // Noted only once the prefix has it: a regedit that failed or ran out of time leaves the note as it was,
        // and the next start tries again (review B2).
        guard importRegistry("[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]\n\"RetinaMode\"=" + (launchRetina ? "\"y\"" : "-"),
                             wine: wine) else { return }
        stopAll(wine)
        defaults.set(launchRetina, forKey: key)
    }

    /// Wine's Retina mode as the prefix has it now: what `applyRetinaMode` put there last.
    static var retinaModeApplied: Bool { UserDefaults.standard.bool(forKey: "retinaMode") }

    /// What a game started straight by Nightforge (not through Steam) gets on top of `gameEnvironment`:
    /// the same as `prepareLaunchEnvironment` hands Steam ("" takes a variable away).
    static func directLaunchEnvironment(avx: Bool, d3dMetal: Bool, frameLimit: Int, upscaling: Bool,
                                        vulkan: VulkanDriver? = nil) -> [String: String] {
        var environment = gameEnvironment
        if !avx { environment["ROSETTA_ADVERTISE_AVX"] = nil }
        if d3dMetal {
            if frameLimit > 0 { environment["D3DM_MAX_FPS"] = String(frameLimit) }
            if upscaling { environment["D3DM_ENABLE_METALFX"] = "1" }
        }
        if case .kosmicKrisp(let folder) = vulkan { environment.merge(kosmicKrispEnvironment(folder)) { _, new in new } }
        return environment
    }

    /// Under winecx, where a start's Vulkan goes. CrossOver's win32u loads MoltenVK straight, or the
    /// library CX_LIBVULKAN names while CX_ACTIVE_GRAPHICS_BACKEND is "wined3d" (vulkan_init_once in
    /// winecx 4.7.3; the only other thing the value changes is an adapter query answered for
    /// "d3dmetal", which Nightforge never sets). That library is KosmicKrisp's Khronos loader, which
    /// takes the driver VK_DRIVER_FILES names.
    enum VulkanDriver: Equatable {
        case moltenVK
        /// KosmicKrisp's folder (`kosmicKrispNow`).
        case kosmicKrisp(URL)
    }

    static let kosmicKrispVariables = ["CX_ACTIVE_GRAPHICS_BACKEND", "CX_LIBVULKAN", "VK_DRIVER_FILES", "MESA_SHADER_CACHE_DIR"]

    static func kosmicKrispEnvironment(_ folder: URL) -> [String: String] {
        try? FileManager.default.createDirectory(at: mesaShaderCache, withIntermediateDirectories: true)
        return ["CX_ACTIVE_GRAPHICS_BACKEND": "wined3d",
                "CX_LIBVULKAN": folder.appendingPathComponent("libvulkan.1.dylib").path,
                "VK_DRIVER_FILES": folder.appendingPathComponent("kosmickrisp_icd.json").path,
                // Mesa 44989e5a doesn't keep one yet (scripts/kosmickrisp/proposed/0003).
                "MESA_SHADER_CACHE_DIR": mesaShaderCache.path]
    }

    /// The Vulkan driver a start under winecx draws through: KosmicKrisp for DXVK's Direct3D 9 once
    /// it's installed; MoltenVK for DXVK's DirectX 10/11, Vulkan games and games whose Direct3D isn't
    /// known. nil: this start draws without Vulkan and Steam keeps the driver it has, so going back
    /// and forth between Mafia II and a DXMT game costs no restart. Gcenx's engine: nil, its loader
    /// finds MoltenVK and Nightforge's layer by itself (VK_DRIVER_FILES would take that away).
    static func vulkanDriver(layer: GraphicsLayer, analysis: GameAnalysis?, winecx: Bool, kosmicKrisp: URL?) -> VulkanDriver? {
        guard winecx else { return nil }
        if layer == .dxvk, let analysis, analysis.usesD3D9, !analysis.usesD3D11, let kosmicKrisp { return .kosmicKrisp(kosmicKrisp) }
        if layer == .dxvk || analysis.map({ $0.apis.isEmpty || $0.apis.contains(.vulkan) }) ?? true { return .moltenVK }
        return nil
    }

    /// The Windows path of a file in the prefix ("C:\Program Files\…"), else as Wine sees the Mac (Z:).
    static func windowsPath(of url: URL) -> String {
        let drive = prefix.appendingPathComponent("drive_c", isDirectory: true).standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        if path.hasPrefix(drive) {
            return "C:\\" + path.dropFirst(drive.count).replacingOccurrences(of: "/", with: "\\")
        }
        return Legendary.windowsPath(path)
    }

    /// Wine's builtin crypto avoids TLS failures in Steam's browser; the overlay DLL deadlocks games.
    /// Games inherit these from Steam, so DirectX goes to DXVK's DLLs in the prefix (native first).
    /// The Direct3D choice itself lives in the registry (see `installDXVK` / `applyGameSettings`): an
    /// override in this variable would beat the per-game AppDefaults.
    static let steamDLLOverrides = "bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true)
    }

    /// The Windows environment Steam and the games live in.
    static var prefix: URL { supportDir.appendingPathComponent("Prefix", isDirectory: true) }

    static var bottle: Bottle { Bottle(name: "Nightforge", url: prefix, isBuiltIn: true) }

    static var steamRoot: URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    static var isSteamInstalled: Bool {
        FileManager.default.fileExists(atPath: steamRoot.appendingPathComponent("steam.exe").path)
    }

    /// True once someone has signed in to Steam in this prefix.
    static var isSteamSignedIn: Bool {
        let users = VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        return !(users ?? [:]).isEmpty
    }

    /// Steam's own login screen is up and waiting (it logs this once its update is done).
    static func isSteamWaitingForSignIn(since start: Date) -> Bool {
        let log = steamRoot.appendingPathComponent("logs/steamui_login.txt")
        guard let modified = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified >= start,
              let text = try? String(contentsOf: log, encoding: .utf8)
        else { return false }
        return text.components(separatedBy: "\n").suffix(20).contains { $0.contains("WaitingForCredentials") }
    }

    /// Steam's self-update: (downloaded, total) in KB from the newest bootstrap log line, and when it last changed.
    static func steamUpdateStatus(steamRoot: URL = steamRoot) -> (fraction: Double?, lastChange: Date?) {
        let log = steamRoot.appendingPathComponent("logs/bootstrap_log.txt")
        let modified = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              let line = text.components(separatedBy: "\n").last(where: { $0.contains(" KB)") })
        else { return (nil, modified) }
        // "… (12,345 von 336,229 KB) …" – the word in the middle depends on Steam's language.
        let numbers = line.split(separator: "(").last?.split(separator: " ").compactMap {
            Double($0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ""))
        } ?? []
        guard numbers.count >= 2, numbers[1] > 0 else { return (nil, modified) }
        return (min(numbers[0] / numbers[1], 1), modified)
    }

    /// Whether Steam's main process is running (any prefix; good enough to notice a crash or restart).
    /// Only Nightforge's own Steam counts – not one from a CrossOver bottle, and not a Steam left
    /// behind without its wineserver (it can't do anything any more and would block a fresh start).
    /// False also when `ps` doesn't answer: where "not running" lets Nightforge start, write or move
    /// something, ask `steamRunningKnown` (nil: not known) or `steamMayBeRunning`.
    static var isSteamRunning: Bool { steamRunningKnown ?? false }

    /// Whether Steam runs, nil when no process list is to be had (`ProcessList`: `ps` has been seen not answering
    /// for good). An empty list that was asked for says "no".
    static var steamRunningKnown: Bool? {
        ownProcessesKnown().map { ours in
            ours.contains { $0.command.lowercased().contains(#"\steam\steam.exe"#) }
                && ours.contains { $0.command.hasSuffix("/wineserver") || $0.command.contains("/wineserver ") }
        }
    }

    /// For what mustn't happen to a Steam that runs (its files written, its game moved): true while it can't be
    /// told it doesn't.
    static var steamMayBeRunning: Bool { steamRunningKnown != false }

    /// A Windows game runs in Nightforge's Wine session (its process shows the game folder's path:
    /// Steam's steamapps\common, Epic's Program Files\Epic Games, GOG's Program Files\GOG Games – or,
    /// started by a launcher with its bare name, runs from there: GameProcesses.runsFrom).
    /// True also when no process list is to be had: it is asked before things that mustn't happen under a game
    /// (an engine switch, a graphics install, D3DMetal's removal, a Steam restart), which wait then.
    static var windowsGameRunning: Bool { windowsGameRunningKnown ?? true }

    /// Whether a Windows game runs, nil when that isn't known (`ProcessList`).
    static var windowsGameRunningKnown: Bool? {
        ownProcessesKnown().map { ours in
            ours.contains { process in
                let command = process.command.lowercased()
                return GameProcesses.gameFolders.contains { command.contains($0.lowercased()) }
                    || command.contains(".exe") && GameProcesses.runsFrom(GameProcesses.gameFolders, command: command,
                                                                          cwd: GameProcesses.cwd(of: process.pid))
            }
        }
    }

    /// Processes started from Nightforge's engine (executable inside its folder), with the command
    /// line ps shows – Wine rewrites that to the Windows program. Not Nightforge Helper, which only
    /// waits for the program it started (and ending it would look as if that program had failed).
    /// An old list counts here (`ProcessList`'s last good one while `ps` doesn't answer): its pids are checked
    /// again by their programs below, and only what they show is acted on.
    static func ownProcesses(under folder: URL = supportDir) -> [(pid: pid_t, command: String)] {
        own(in: processLookup().value ?? [], under: folder)
    }

    /// The same for deciding – may Nightforge end a session, write a game's files, take an engine away? –
    /// from a list asked for just now; nil when there is none, an old one included: it can't show what
    /// started since, so "none there" would be a guess (review B1). "none" and "not known" are two answers.
    static func ownProcessesKnown(under folder: URL = supportDir) -> [(pid: pid_t, command: String)]? {
        processLookup(allowOld: false).value.map { own(in: $0, under: folder) }
    }

    private static func own(in table: [(pid: pid_t, command: String)], under folder: URL) -> [(pid: pid_t, command: String)] {
        let root = folder.resolvingSymlinksInPath().path
        let helper = DetachedProcess.home.appendingPathComponent(DetachedProcess.helperName).resolvingSymlinksInPath().path + "/"
        return table.filter { process in
            // Inside the folder, not merely a sibling with the same start (engine 4.7.3 vs 4.7.3-3).
            guard let path = executablePath(process.pid) else { return false }
            return (path == root || path.hasPrefix(root + "/")) && !path.hasPrefix(helper)
        }
    }

    /// Every process with the command line `ps` shows (`ProcessList`: limited, and the last list when `ps`
    /// has stopped answering – the callers check each pid they act on). [] when there is none at all: callers
    /// that conclude from an empty list use `processLookup`.
    static func processTable() -> [(pid: pid_t, command: String)] {
        processLookup().value ?? []
    }

    static func processLookup(allowOld: Bool = true) -> ProcessListing<[(pid: pid_t, command: String)]> {
        ProcessList.listing("pid=,command=", allowOld: allowOld).map { text in
            text.split(separator: "\n").compactMap { line in
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let pid = pid_t(parts[0]) else { return nil }
                return (pid, String(parts[1]))
            }
        }
    }

    /// The wine of the engine Steam's session runs on: the folder its wineserver comes from. Usually
    /// the newest engine, but one held back for a game (EngineRollback) after that game's start.
    static func sessionWine() -> URL? {
        for process in ownProcesses() {
            guard let path = executablePath(process.pid), path.hasSuffix("/bin/wineserver") else { continue }
            let wine = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("wine")
            if FileManager.default.isExecutableFile(atPath: wine.path) { return wine }
        }
        return nil
    }

    /// Steam's browser caches in the prefix, one per Windows user (its helper's -cachedir,
    /// `C:\users\crossover\AppData\Local\Steam\htmlcache`).
    static func steamBrowserCaches(prefix: URL = prefix) -> [URL] {
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("AppData/Local/Steam/htmlcache", isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// When a process started.
    static func processStart(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// Valve's steamwebhelper, started before the wrapper went in at `swappedAt`, still runs
    /// (SteamBootstrap.unwrappedHelperRunning).
    static func unwrappedWebHelperRunning(swappedAt: Date) -> Bool {
        SteamBootstrap.unwrappedHelperRunning(ownProcesses().map { ($0.command, processStart($0.pid)) }, swappedAt: swappedAt)
    }

    /// Ends Steam's browser, every process of it, and leaves Steam running: its client starts the
    /// browser again by itself from steamwebhelper.exe, ~8 s later – four times in a row
    /// (30.10.2026, a scratch prefix; "Restart webhelper process").
    static func endWebHelpers() {
        for pid in SteamBootstrap.webHelperProcesses(ownProcesses()) where pid != getpid() { kill(pid, SIGKILL) }
    }

    /// The program a process runs, as the kernel has it (/private/var/…); nil for one that's gone.
    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Runs engine work that waits on Wine or copies files (regedit, wineserver -k, installs) away
    /// from the main thread, so the window and the controller keep responding meanwhile.
    @discardableResult
    static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    @discardableResult
    static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    /// Ends every Windows process in Nightforge's prefix – through the wineserver that runs, which
    /// is another engine's while a game is held back on one (EngineRollback).
    static func stopAll(_ wine: URL) {
        let wine = sessionWine() ?? wine
        // `wineserver -k` asks the server to end and waits for it. A server that doesn't (a process of
        // the session stuck in the kernel) must not hold up what comes after – Steam's restart, the
        // engine switch, "Remove Nightforge completely": after the limit it is dropped, and
        // `killLeftovers` ends what is still there.
        Subprocess.run(wine.deletingLastPathComponent().appendingPathComponent("wineserver").path, ["-k"],
                       environment: environment(wine: wine), timeout: serverTimeout)
        killLeftovers()
    }

    /// How long `stopAll` waits for `wineserver -k`.
    static let serverTimeout: TimeInterval = 15

    /// Wine helpers (winedevice.exe in particular) sometimes outlive `wineserver -k` and then
    /// hang around for days. A Wine program still running with its working directory in our
    /// prefix after the server is gone is such a leftover – only Wine's: Nightforge's downloaders
    /// (gogdl, legendary) work there too and carry on (The Evil Within 2, ended at 84 % by a GOG
    /// game's fresh Wine session, 1.11.2026).
    static func killLeftovers() {
        // As the kernel reports them: /private/var/… stays (resolvingSymlinksInPath drops /private).
        let root = realPath(prefix)
        let engines = engineFolders.map(realPath), components = realPath(ComponentStore.shared.root)
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return }
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            guard let path = executablePath(pid), isWineProgram(path, engines: engines, components: components) else { continue }
            var info = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { continue }
            let cwd = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            // The prefix itself or below it: "Prefix-backup" beside it starts with the same letters.
            if cwd == root || cwd.hasPrefix(root + "/") { kill(pid, SIGKILL) }
        }
        // Wine processes working somewhere else (Steam's own folder resolved differently, …)
        // still run Nightforge's engine.
        for process in ownProcesses() where process.pid != getpid() {
            guard let path = executablePath(process.pid), isWineProgram(path, engines: engines, components: components) else { continue }
            kill(process.pid, SIGKILL)
        }
    }

    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.resolvingSymlinksInPath().path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The engines Wine runs from (the game-mode loader `Nightforge Game.app` lives inside them).
    static var engineFolders: [URL] {
        [engineID, winecxEngineID, "wine-staging"].map { ComponentStore.shared.root.appendingPathComponent($0, isDirectory: true) }
    }

    /// A Wine program: run from one of the engines, or a Wine binary by name elsewhere in Nightforge's
    /// components (`components`: ComponentStore's folder, resolved like the paths). Nightforge's other
    /// components (gogdl, legendary) aren't, nor another app's Wine (CrossOver, Homebrew) by its name.
    static func isWineProgram(_ path: String, engines: [String], components: String) -> Bool {
        engines.contains { path.hasPrefix($0 + "/") }
            || path.hasPrefix(components + "/")
                && ["wine", "wine64", "wineserver", "wine-preloader", "wine64-preloader"].contains((path as NSString).lastPathComponent)
    }

    /// Puts the bundled steamwebhelper wrapper in place of Steam's own (which becomes
    /// steamwebhelper_real.exe). Repeats safely; returns true when it changed anything, e.g. after
    /// Steam's first update unpacked its browser or a later update replaced it. Only once Steam's
    /// client is in place, and never while its bootstrapper downloads or installs an update
    /// (SteamBootstrap): the install writes Valve's helper back, and a swap then cut it off.
    @discardableResult
    static func installWebHelperWrapper(steamRoot: URL = steamRoot,
                                        wrapper: URL? = Bundle.main.url(forResource: "steamwebhelper", withExtension: "exe")) -> Bool {
        guard let wrapper, SteamBootstrap.clientInstalled(steamRoot: steamRoot),
              SteamBootstrap(steamRoot: steamRoot).allowsHelperSwap else { return false }
        let fm = FileManager.default
        let cef = steamRoot.appendingPathComponent("bin/cef", isDirectory: true)
        let wrapperSize = (try? fm.attributesOfItem(atPath: wrapper.path)[.size] as? Int) ?? 0
        let dirs = (try? fm.contentsOfDirectory(at: cef, includingPropertiesForKeys: nil)) ?? []
        var changed = false

        for dir in dirs where dir.lastPathComponent.hasPrefix("cef.win") {
            let helper = dir.appendingPathComponent("steamwebhelper.exe")
            let real = dir.appendingPathComponent("steamwebhelper_real.exe")
            guard let size = try? fm.attributesOfItem(atPath: helper.path)[.size] as? Int else { continue }
            if size == wrapperSize { continue }
            // Valve's helper is several MB, the wrapper ~150 KB: anything else is Steam's (new) original.
            guard size > 1_000_000 else { continue }
            // The wrapper is copied in beside it first, so a failed copy (disk full) never leaves Steam
            // without any helper: with -noverifyfiles it wouldn't repair that, and its window stays black.
            let staged = dir.appendingPathComponent("steamwebhelper.nightforge-new")
            do {
                try? fm.removeItem(at: staged)
                try fm.copyItem(at: wrapper, to: staged)
                try? fm.removeItem(at: real)
                try fm.moveItem(at: helper, to: real)
                do {
                    try fm.moveItem(at: staged, to: helper)
                } catch {
                    try? fm.moveItem(at: real, to: helper)  // Steam's own helper back in place
                    throw error
                }
                changed = true
            } catch {
                try? fm.removeItem(at: staged)
                continue
            }
        }
        return changed
    }

    static var isRosettaInstalled: Bool {
        // Rosetta is what runs Wine's x86_64 code; `arch -x86_64` fails without it.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        probe.arguments = ["-x86_64", "/usr/bin/true"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return false }
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }

    /// `bin/wine` inside an unpacked engine component: Gcenx's archive holds a "Wine ….app" bundle,
    /// winecx's a Whisky-style `Libraries/Wine` tree.
    static func wineBinary(in engineDir: URL) -> URL? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: engineDir, includingPropertiesForKeys: nil)) ?? []
        let candidates = apps.filter { $0.pathExtension == "app" }.map { $0.appendingPathComponent("Contents/Resources/wine/bin/wine") }
            + [engineDir.appendingPathComponent("Libraries/Wine/bin/wine")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Whether an engine can run D3DMetal: winecx says so in the version file next to its tree.
    static func isGPTKCapable(wine: URL) -> Bool {
        let plist = wine.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WhiskyWineVersion.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return info["gptkCapable"] as? Bool == true
    }

    /// D3DMetal is in the engine (installD3DMetal): DirectX 12 games have a way to run.
    static var d3dMetalReady: Bool { installedWineNow().map(isD3DMetalDeployed(wine:)) ?? false }

    /// Nightforge's Vulkan layer reaches the games: not under winecx, whose winevulkan loads
    /// MoltenVK straight, without a Vulkan loader (docs/TODO.md › Vulkan-Layer und winecx). Without
    /// the layer DXVK asks MoltenVK for what it lacks (geometryShader, shaderCullDistance) and gets
    /// no device – Left 4 Dead 2 and Mafia II on DirectX 9.
    static var vulkanLayerLoads: Bool { installedWineNow().map { !isGPTKCapable(wine: $0) || vulkanLoader(for: $0) != nil } ?? true }

    /// Engine test, off unless `defaults write io.github.lordhayne.nightforge vulkanLoader -bool true`
    /// (or the path of an x86_64 libvulkan.1.dylib instead of true): on winecx, which loads MoltenVK
    /// itself, DXVK's Direct3D 9 draws through the Khronos loader, so Nightforge's Vulkan layer is
    /// there to drop what MoltenVK lacks. DXVK-macOS 1.10.3's Direct3D 9 asks for geometryShader and
    /// shaderCullDistance whatever the GPU says (d3d9_device.cpp), and MoltenVK refuses the device
    /// (L4D2, Mafia II); its Direct3D 11 asks only for what's there (d3d11_device.cpp), which is why
    /// OxyRail draws on DXVK without (probe, 3.11.2026, docs/TODO.md › Vulkan-Layer und winecx).
    /// With `true` the loader is the Gcenx engine's (Khronos 1.4.350), what Wine 11.18 drew through.
    static func vulkanLoader(for wine: URL, defaults: UserDefaults = .standard) -> URL? {
        guard isGPTKCapable(wine: wine) else { return nil }
        let fm = FileManager.default
        if let path = defaults.string(forKey: "vulkanLoader"), path.hasPrefix("/") {
            return fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        guard defaults.bool(forKey: "vulkanLoader"), let gcenx = installedComponentNow(engineID).flatMap(wineBinary(in:)) else { return nil }
        let loader = gcenx.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/libvulkan.1.dylib")
        return fm.fileExists(atPath: loader.path) ? loader : nil
    }

    /// The variables that send a start's Vulkan through `vulkanLoader`, beside CX_ACTIVE_GRAPHICS_BACKEND.
    static let vulkanLoaderNames = ["CX_LIBVULKAN", "VK_DRIVER_FILES", "VK_ADD_IMPLICIT_LAYER_PATH"]

    /// Whether the engine test's switch for `vulkanLoader` is on, whatever the game: a loader's path that
    /// is there, or `true` (the Gcenx engine's).
    static func vulkanLoaderSwitchedOn(defaults: UserDefaults = .standard) -> Bool {
        if let path = defaults.string(forKey: "vulkanLoader"), path.hasPrefix("/") { return FileManager.default.fileExists(atPath: path) }
        return defaults.bool(forKey: "vulkanLoader")
    }

    /// What a start on `layer` gets for the loader: a Direct3D 9 game on DXVK, with the switch on.
    /// CW Hack 25909 (dlls/win32u/vulkan.c) takes CX_LIBVULKAN only with
    /// CX_ACTIVE_GRAPHICS_BACKEND=wined3d; MoltenVK and the layer come from the game bundle's files
    /// (installGameBundle), the same the loader finds inside the bundle by itself.
    static func vulkanLoaderEnvironment(layer: GraphicsLayer, d3d9: Bool, wine: URL?,
                                        defaults: UserDefaults = .standard) -> [String: String] {
        guard layer == .dxvk, d3d9, let wine, let loader = vulkanLoader(for: wine, defaults: defaults) else { return [:] }
        let vulkan = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("\(gameBundleName)/Contents/Resources/vulkan", isDirectory: true)
        return ["CX_LIBVULKAN": loader.path, "CX_ACTIVE_GRAPHICS_BACKEND": "wined3d",
                "VK_DRIVER_FILES": vulkan.appendingPathComponent("icd.d/MoltenVK_icd.json").path,
                "VK_ADD_IMPLICIT_LAYER_PATH": vulkan.appendingPathComponent("implicit_layer.d").path]
    }

    /// KosmicKrisp's folder, once it and upstream DXVK are installed (the components list names them
    /// with winecx only): DXVK's Direct3D 9 gets its device there.
    static var kosmicKrispNow: URL? {
        guard installedComponentNow(dxvkUpstreamID) != nil, let dir = installedComponentNow(kosmicKrispID) else { return nil }
        return kosmicKrispFolder(in: dir)
    }

    /// DXVK's Direct3D 9 draws on winecx: KosmicKrisp is there for it (`vulkanDriver`).
    static var kosmicKrispReady: Bool { !vulkanLayerLoads && kosmicKrispNow != nil }

    /// The folder in an unpacked KosmicKrisp archive that holds the loader, the driver and its manifest.
    static func kosmicKrispFolder(in dir: URL) -> URL? {
        let fm = FileManager.default
        let candidates = [dir] + ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        return candidates.first { folder in
            ["libvulkan.1.dylib", "libvulkan_kosmickrisp.dylib", "kosmickrisp_icd.json"]
                .allSatisfy { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
    }

    static func isD3DMetalDeployed(wine: URL) -> Bool {
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        let fm = FileManager.default
        return fm.fileExists(atPath: lib.appendingPathComponent("external/libd3dshared.dylib").path)
            && (try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("wine/x86_64-unix/d3d12.so").path)) != nil
    }

    /// Makes sure the engine and graphics layer from the current component list are installed –
    /// e.g. after the list moved to a newer engine. Returns the wine binary to use.
    /// `gameRunning`: a game of Nightforge's own Steam runs, so its Wine session must not end –
    /// a new graphics package (which can bring a new wineserver) waits for the next start then.
    /// What ensureEngine is doing, for the first start's checklist (SetupDetail.engine).
    enum SetupStep: Sendable {
        /// A component coming down (0…1); at 1 it's being unpacked.
        case downloading(Component, Double)
        case graphics
        case gameEnvironment
    }

    static func ensureEngine(gameRunning: Bool = false, report: (@Sendable (SetupStep) -> Void)? = nil) async throws -> URL {
        let store = ComponentStore.shared
        func install(_ component: Component) async throws -> URL {
            try await store.install(component) { fraction in report?(.downloading(component, fraction)) }
        }
        let manifest = try await store.manifest()
        guard let engine = engineComponent(in: manifest), let graphics = graphicsComponent(in: manifest) else {
            throw ComponentError.noManifest
        }
        let engineDir = try await store.install(engine)
        let graphicsDir = try await store.install(graphics)
        guard let wine = wineBinary(in: engineDir) else { throw SetupError.engineBroken }
        let rollback = EngineRollback.shared
        // A wineserver from a previous engine – or from one held back for a game – can't talk to the
        // new one, so its session has to end – but not under a running game: that keeps the old
        // engine until the next start without one.
        let oldEngines = [engineID, winecxEngineID, "wine-staging"].flatMap { id in
            ((try? FileManager.default.contentsOfDirectory(
                at: store.root.appendingPathComponent(id), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0 != engineDir }
        } + rollback.heldEngineFolders()
        for dir in oldEngines {
            // Something runs from it – or that can't be told (no process list): it counts as in use, and a
            // session that may hold a game isn't ended (`windowsGameRunning` is true then too).
            guard ownProcessesKnown(under: dir)?.isEmpty != true else { continue }
            guard let old = wineBinary(in: dir) else { continue }
            if gameRunning || windowsGameRunning { return old }
            stopAll(old)
        }
        if !gameRunning, !windowsGameRunning { applyMsyncMode(wine) }
        // On winecx, D3DMetal takes the engine's Direct3D builtins and DXMT and DXVK move into the
        // prefix as native DLLs (see `layerOverrides`).
        let gptk = isGPTKCapable(wine: wine)
        // Apple's D3DMetal only once the player has said how it comes (D3DMetalSupply) – or had it before.
        let d3dMetal = gptk ? D3DMetalSupply.current(manifest: manifest, componentsRoot: store.root) : nil
        let gamepad = gptk ? manifest.component(gamepadID) : nil
        // Built for one runtime: only with that engine version (installEngineFix checks its files as well).
        let engineFix = gptk ? manifest.component(engineFixID).flatMap { $0.version.hasPrefix(engine.version + "-") ? $0 : nil } : nil
        // DXVK's Direct3D 9 on KosmicKrisp: winecx only, the one engine that loads it per start.
        let kosmicKrisp = gptk ? manifest.component(kosmicKrispID) : nil
        let dxvkUpstream = kosmicKrisp != nil ? manifest.component(dxvkUpstreamID) : nil
        // Copying the graphics files again would give them new inodes and so rebuild the game
        // bundle Steam runs from, and every regedit starts Wine: each part is only redone when what
        // it installs has changed. The stamps live in what they describe, so a fresh engine or
        // prefix starts without one.
        let matchesEngine = graphics.version.hasPrefix(engine.version + "-")
        let graphicsStamp = graphicsStampFile(wine: wine)
        let moltenVK = manifest.component(moltenVKID)
        let graphicsWanted = "\(graphics.id) \(graphics.version) engine-match \(matchesEngine) moltenvk \(moltenVK?.version ?? "engine")"
            + " d3dmetal \(d3dMetal?.version ?? "-") gamepad \(gamepad?.version ?? "-")"
            + (engineFix.map { " enginefix \($0.version)" } ?? "")
        let dxvk = manifest.component(dxvkID)
        let build = EngineBuild(engine: engine, graphics: [graphics, moltenVK, gamepad, engineFix, dxvk, kosmicKrisp, dxvkUpstream]
                                    .compactMap { $0 },
                                d3dMetal: d3dMetal?.version, stamp: graphicsWanted)
        // Before anything of the engine changes, the build games last ran well on stays as a copy:
        // a game the new one breaks starts with it instead (EngineRollback).
        if !gameRunning, !windowsGameRunning {
            rollback.holdBack(before: build, copying: [graphicsID, upstreamGraphicsID, dxvkID, dxvkUpstreamID]) { current, folder in
                wineBinary(in: folder).map { readStamp(graphicsStampFile(wine: $0)) == current.stamp } ?? false
            }
        }
        if readStamp(graphicsStamp) != graphicsWanted, !gameRunning, !windowsGameRunning {
            var moltenVKDir: URL?
            if let moltenVK { moltenVKDir = try await install(moltenVK) }
            var d3dMetalDir: URL?
            switch d3dMetal?.origin {
            case .download(let component)?: d3dMetalDir = try await install(component)
            case .kept(let dir)?, .imported(let dir)?: d3dMetalDir = dir
            case nil: break
            }
            var gamepadDir: URL?
            if let gamepad { gamepadDir = try await install(gamepad) }
            var engineFixDir: URL?
            if let engineFix { engineFixDir = try await install(engineFix) }
            report?(.graphics)
            try installGraphics(graphicsDir, into: wine, matchesEngine: matchesEngine, nativeInPrefix: gptk)
            try installMoltenVK(moltenVKDir, into: wine)
            if let d3dMetalDir { try installD3DMetal(d3dMetalDir, into: wine) }
            if let gamepadDir { try installGamepad(gamepadDir, into: wine) }
            // Without one (or for another engine version) the engine's own files come back.
            if gptk { try installEngineFix(engineFixDir, into: wine) }
            writeStamp(graphicsStamp, graphicsWanted)
        }
        installGameBundle(wine: wine)  // after the graphics: its links must point at the new files
        if gptk { linkCrossOverProfile() }
        detachUserFolders()
        trimSteamLogs()
        excludeGamesFromBackup()
        var dxvkDir: URL?
        if let dxvk { dxvkDir = try await install(dxvk) }
        // KosmicKrisp isn't copied anywhere: each start on it names its folder (`vulkanDriver`).
        if let kosmicKrisp { _ = try await install(kosmicKrisp) }
        var d3d9Dir: URL?
        if let dxvkUpstream { d3d9Dir = try await install(dxvkUpstream) }
        report?(.gameEnvironment)
        try preparePrefix(wine: wine, build: build, graphicsDir: graphicsDir, dxvkDir: dxvkDir, d3d9Dir: d3d9Dir)
        // Only once the engine points at the current versions: with a game running, the graphics
        // install above waits, and the engine's links (D3DMetal, MoltenVK) may still lead to older ones.
        if !gameRunning, !windowsGameRunning {
            if await store.manifestIsSigned { removeUnusedComponents(keeping: manifest, store: store, d3dMetal: d3dMetal) }
            rollback.settle(build, seed: LaunchHealth.confirmedWays()) { ownProcessesKnown(under: $0)?.isEmpty != true }
        }
        return wine
    }

    /// The prefix's share of an engine build: the game environment, DXVK's DLLs and load orders, and
    /// on winecx DXMT's DLLs and Wine's own Direct3D 12 as natives. Redone only when the build or the
    /// environment changed since (the stamp) – after an update, or switching to a held-back build and back.
    /// `d3d9Dir`: upstream DXVK, whose Direct3D 9 takes the place of DXVK-macOS's on winecx (KosmicKrisp).
    static func preparePrefix(wine: URL, build: EngineBuild, graphicsDir: URL, dxvkDir: URL?, d3d9Dir: URL? = nil) throws {
        let gptk = isGPTKCapable(wine: wine)
        let prefixStamp = stamp(in: prefix, name: "setup")
        let prefixWanted = prefixStampText(build, gptk: gptk)
        applyPrefixRegistry(wine: wine)  // stamped on its own: older prefixes get it once as well
        guard readStamp(prefixStamp) != prefixWanted else { return }
        if let dxvkDir { try installDXVK(dxvkDir, wine: wine, d3d9Only: gptk, d3d9From: gptk ? d3d9Dir : nil) }
        let written = loadOrdersWritten
        if gptk {
            try installDXMTNatives(graphicsDir)
            try installWineD3D12Natives(wine: wine)
        }
        if written { writeStamp(prefixStamp, prefixWanted) }
    }

    static func prefixStampText(_ build: EngineBuild, gptk: Bool) -> String {
        let graphics = build.version(of: graphicsID) ?? build.version(of: upstreamGraphicsID) ?? "-"
        return "\(build.engineVersion) \(build.version(of: dxvkID) ?? "-") \(gptk ? graphics + " d3dmetal " + (build.version(of: d3dMetalID) ?? "-") : "-") "
            + (gptk ? build.version(of: dxvkUpstreamID).map { "d3d9 \($0) " } ?? "" : "")
            + gameEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// The stamp in an engine's lib/wine that says which graphics builds were installed into it.
    static func graphicsStampFile(wine: URL) -> URL {
        stamp(in: wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine", isDirectory: true),
              name: "graphics")
    }

    /// Versions the component list no longer names, and components it dropped (an older engine
    /// line, say), take space for nothing – a gigabyte and more after a few updates. Anything
    /// still running from a folder stays, like the old engine a game keeps until it ends.
    private static func removeUnusedComponents(keeping manifest: ComponentManifest, store: ComponentStore,
                                                d3dMetal: D3DMetalSupply.Current?) {
        let fm = FileManager.default
        // What only the app's own list names (legendary before the online list has it) stays too.
        let bundled = ComponentStore.bundledManifest()?.components ?? []
        var wanted = Dictionary((manifest.components + bundled).map { ($0.id, $0.version) }, uniquingKeysWith: { first, _ in first })
        // A D3DMetal from before the question stays as long as it's the one in use.
        if case .kept(let dir)? = d3dMetal?.origin { wanted[d3dMetalID] = dir.lastPathComponent }
        let ids = (try? fm.contentsOfDirectory(at: store.root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for id in ids where !id.lastPathComponent.hasPrefix(".")
            && (try? id.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let versions = (try? fm.contentsOfDirectory(at: id, includingPropertiesForKeys: nil)) ?? []
            for version in versions where version.lastPathComponent != wanted[id.lastPathComponent] {
                // Not one something runs from – nor one whose users can't be told.
                guard ownProcessesKnown(under: version)?.isEmpty == true else { continue }
                try? fm.removeItem(at: version)
            }
            if (try? fm.contentsOfDirectory(atPath: id.path))?.isEmpty == true { try? fm.removeItem(at: id) }
        }
    }

    /// What `ensureEngine` last set up in a folder (the engine's lib/wine, the prefix).
    private static func stamp(in folder: URL, name: String) -> URL {
        folder.appendingPathComponent(".nightforge-\(name)")
    }

    private static func readStamp(_ file: URL) -> String? {
        try? String(contentsOf: file, encoding: .utf8)
    }

    private static func writeStamp(_ file: URL, _ text: String) {
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// The engine's wine binary without async work (for app shutdown, `d3dMetalReady`): the newest
    /// installed copy of the engine the component list names (`engineComponent`), winecx when there
    /// is no list. Gcenx's engine stays on disk after the switch to winecx, and its folder may well be
    /// the younger one – going by dates alone took it, and D3DMetal looked missing.
    static func installedWineNow(root: URL = ComponentStore.shared.root,
                                 manifest: ComponentManifest? = ComponentStore.localManifest()) -> URL? {
        let preferred = manifest.flatMap(engineComponent(in:))?.id ?? winecxEngineID
        for id in [preferred] + [winecxEngineID, engineID].filter({ $0 != preferred }) {
            let versions = (try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent(id, isDirectory: true),
                includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let newest = versions
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }
                .lazy.compactMap(wineBinary(in:)).first
            if let newest { return newest }
        }
        return nil
    }

    /// An installed component's folder without async work: the newest unpacked version of `id`.
    static func installedComponentNow(_ id: String) -> URL? {
        let dir = ComponentStore.shared.root.appendingPathComponent(id, isDirectory: true)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return versions
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".sha256").path) }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    /// When a game last ran, or was last asked to start (Play pressed): the quit script waits for its cloud
    /// saves only within five minutes of that, and only then. Set by `noteGameActivity`.
    nonisolated(unsafe) static var lastGameActivity: Date?

    static func noteGameActivity(_ date: Date = Date()) { lastGameActivity = date }

    /// A game ran, or was asked to start, within the last five minutes (the quit script's `recent_game`).
    static var gameRanRecently: Bool { lastGameActivity.map { Date().timeIntervalSince($0) < 300 } ?? false }

    /// When Nightforge quits, Steam should go too – but not while a game runs (it uploads cloud
    /// saves after the game ends) or a download is going. Nightforge itself quits right after a
    /// launch, so a small detached script waits for that and then stops Steam and the Wine session.
    /// It gives up if Nightforge is opened again in the meantime. Steam for Mac goes the same way
    /// when Nightforge started it. A game that was running when Nightforge quit brings Nightforge
    /// back when it ends, so the player lands in the launcher again, controller in hand.
    /// "Restart Nightforge" (LibraryModel.restartNightforge): the script ends everything at once, Steam
    /// for Mac too, and opens Nightforge again once the session is down.
    nonisolated(unsafe) static var restarting = false

    static func scheduleSteamShutdown(restart: Bool = false) {
        let wine = isSteamInstalled ? sessionWine() ?? installedWineNow() : nil
        let macSteam = restart || MacSteam.endsWithNightforge()
        let macLibrary = FileManager.default.fileExists(atPath: MacSteam.steamapps.path) ? MacSteam.steamapps.path : ""
        let script = supportDir.appendingPathComponent("steam-shutdown.sh")
        let text = steamShutdownScript
        guard (try? text.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }

        let process = DetachedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Steam's -shutdown is a Windows program like any other: in the sandbox when it's switched on.
        let sandbox = WineSandbox.enabled ? [WineSandbox.helper?.path ?? "-", WineSandbox.profile()] : ["", ""]
        process.arguments = [script.path, wine?.path ?? "", prefix.path, macLibrary, macSteam ? "1" : "0", Bundle.main.bundlePath,
                             String(getpid()), msync ? "1" : "0", String(Int(lastGameActivity?.timeIntervalSince1970 ?? 0))] + sandbox
            + [restart ? "1" : "0"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()  // keeps running after Nightforge has quit
    }

    /// The script scheduleSteamShutdown runs: $1 wine, $2 prefix, $3 Steam for Mac's steamapps,
    /// $4 "1" to quit Steam for Mac too, $5 the Nightforge app to bring back after a game, $6 the
    /// process of the Nightforge that is quitting, $7 WINEMSYNC as the session has it (`msync`), $8 when a
    /// game last ran or was asked to start (`lastGameActivity`, epoch seconds): only within five minutes of
    /// that does it wait 30 s for the cloud saves before it ends Steam. $9 and $10 Wine's sandbox helper and
    /// profile (WineSandbox; review of 3.11.2026: it ran steam.exe from the prefix outside the sandbox).
    /// $11 "1" for a restart: no waiting for games or downloads, then Nightforge opens again (8.11.).
    /// It waits for a game or a download for 12 hours at most (`NIGHTFORGE_QUIT_LIMIT`, seconds), and
    /// counts a download only if it isn't paused. A game that starts while Steam is being ended (from Steam's
    /// window) sends it back to waiting, never under `wineserver -k`. Its process is in `steam-shutdown.pid`
    /// beside it while it waits.
    static let steamShutdownScript = #"""
        #!/bin/bash
        # Written by Nightforge on quit: ends the background Steam once nothing needs it, and brings
        # Nightforge back when a game that was running ends.
        # WINE is empty without Nightforge's own Steam; QUIT_MAC is 1 when Steam for Mac should go too.
        # SANDBOX and PROFILE: Wine's sandbox helper and its profile when the switch is on (WineSandbox),
        # SANDBOX "-" when it's on but the helper is missing; both empty when it's off.
        WINE="$1"; PREFIX="$2"; MAC_STEAMAPPS="$3"; QUIT_MAC="$4"; APP="$5"; QUITTING="$6"; MSYNC="${7:-1}"
        # When a game last ran or was asked to start (epoch seconds, 0: not for long), told by Nightforge and
        # kept up to date here whenever one is seen running.
        LAST_GAME="${8:-0}"
        recent_game() { [ $(( $(date +%s) - LAST_GAME )) -lt 300 ]; }
        SANDBOX="$9"; PROFILE="${10}"
        # RESTART is 1 for "Restart Nightforge": no game or download is waited for (Nightforge offers it only
        # with no game running; a hung one ends with the session), Steam for Mac goes too, and Nightforge
        # opens again once everything is down. A game that ran in the last five minutes still gets its 30 s
        # for the cloud saves.
        RESTART="${11:-0}"
        finish() { [ "$RESTART" = 1 ] && [ -n "$APP" ] && open "$APP"; exit 0; }
        # A Windows program of the session: steam.exe lies in the prefix, which programs in the sandbox can
        # change, so with the switch on it runs inside too, as every other Wine start does. Switched on
        # without the helper, nothing of Windows starts; the session still ends below (wineserver -k).
        wine_program() {
          [ "$SANDBOX" = "-" ] && return 1
          if [ -n "$SANDBOX" ]; then "$SANDBOX" "$PROFILE" "$WINE" "$@"; else "$WINE" "$@"; fi
        }
        # A request to a Steam that may not answer: ended after HANG_LIMIT seconds (settable for the test), so
        # the script goes on to what ends it anyway. Hanging here, it never reached `open` after a restart.
        HANG_LIMIT="${NIGHTFORGE_HANG_LIMIT:-30}"
        limited() {
          local pid watch status
          "$@" & pid=$!
          ( /bin/sleep "$HANG_LIMIT"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 & watch=$!
          wait "$pid"
          status=$?
          kill "$watch" 2>/dev/null
          return "$status"
        }
        STEAMAPPS="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps"
        # The longest this waits for a game or a download (seconds, 12 h): then it leaves things as they
        # are and ends, rather than stay for as long as the Mac is on. Settable for the test.
        LIMIT="${NIGHTFORGE_QUIT_LIMIT:-43200}"
        late() { [ "$SECONDS" -gt "$LIMIT" ]; }
        # Where "Remove Nightforge completely" finds this script, without asking ps (CompleteRemoval.endScripts).
        PIDFILE="${0%/*}/steam-shutdown.pid"
        echo $$ > "$PIDFILE" 2>/dev/null
        trap '[ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"' EXIT
        # A ps that doesn't answer, or answers nothing (it always lists this script), is "unknown", not
        # "no process": a game may be running. Unknown counts as one; unknown for half an hour on end
        # (NIGHTFORGE_PS_LIMIT, seconds), the script leaves everything as it is and ends.
        PS_LIMIT="${NIGHTFORGE_PS_LIMIT:-1800}"
        UNKNOWN_SINCE=""
        PS_OUT=""
        read_processes() {
          if PS_OUT="$(ps "$@" 2>/dev/null)" && [ -n "$PS_OUT" ]; then UNKNOWN_SINCE=""; return 0; fi
          [ -n "$UNKNOWN_SINCE" ] || UNKNOWN_SINCE="$(date +%s)"
          return 1
        }
        unknown_too_long() { [ -n "$UNKNOWN_SINCE" ] && [ $(( $(date +%s) - UNKNOWN_SINCE )) -ge "$PS_LIMIT" ]; }
        # The process list is read before searching it, so the search never finds itself; -F
        # because the Windows paths are full of backslashes, which grep would read as escapes.
        has_process() { read_processes -axo command || return 0; printf '%s\n' "$PS_OUT" | grep -qiF -- "$1"; }
        # Nightforge runs again: a process whose command line BEGINS with this app's program – not one
        # that merely names it (a build in another folder, lldb, codesign, a tail in a terminal), and
        # not the Nightforge that is quitting. The needle goes in by environment, so that no command
        # line of ours holds it.
        reopened() {
          ps -axo pid=,command= | NEEDLE="$APP/Contents/MacOS/Nightforge" QUITTING="$QUITTING" awk '
            BEGIN { needle = ENVIRON["NEEDLE"]; quitting = ENVIRON["QUITTING"]; found = 0 }
            { pid = $1; line = $0; sub(/^[ ]*[0-9]+[ ]+/, "", line) }
            pid == quitting { next }
            index(line, needle) == 1 { rest = substr(line, length(needle) + 1); if (rest == "" || substr(rest, 1, 1) == " ") found = 1 }
            END { exit found ? 0 : 1 }'
        }
        steam_running() { has_process '\steam\steam.exe'; }
        # A Windows program a launcher started by its bare name ("Control_DX11.exe -AUTH_LOGIN=…") shows
        # no folder; Wine gives it the game's as its working folder. Not Windows' or Steam's own programs.
        runs_from_game_folder() {
          local list pids
          list="$(ps -axo pid=,command=)"
          pids="$(printf '%s\n' "$list" | grep -iF .exe | grep -viF -e 'c:\windows\' -e '\steam\' -e steamwebhelper | awk '{ print $1 }' | paste -sd, -)"
          [ -n "$pids" ] && lsof -a -d cwd -Fn -p "$pids" 2>/dev/null | grep -qiE '/steamapps/common/|/epic games/|/gog games/'
        }
        game_running() {
          has_process '\steamapps\common\' && return 0                                  # a Windows game
          has_process '\Epic Games\' && return 0                                         # an Epic game (same Wine session)
          has_process '\GOG Games\' && return 0                                          # a GOG game (same Wine session)
          [ -n "$MAC_STEAMAPPS" ] && has_process "/steamapps/common/" && return 0         # a Mac game, in any library (Windows paths have backslashes)
          runs_from_game_folder && return 0                                               # one a launcher started
          return 1
        }
        # A download is under way in this steamapps folder: a folder in downloading/ whose appmanifest is
        # not marked paused (StateFlags 512). Steam leaves the folders of paused and failed downloads
        # there for good; counted, they would keep Steam and this script running for as long as the Mac
        # is on. A folder without a manifest is a leftover Steam doesn't carry on with.
        downloading_in() {
          local dir flags
          for dir in "$1"/downloading/*/; do
            [ -d "$dir" ] || continue
            flags="$(sed -n 's/.*"StateFlags"[[:space:]]*"\([0-9]*\)".*/\1/p' "$1/appmanifest_$(basename "$dir").acf" 2>/dev/null | head -n 1)"
            [ -n "$flags" ] || continue
            [ $(( flags & 512 )) -ne 0 ] || return 0
          done
          return 1
        }
        # Every steamapps folder of a Steam: its own and what its libraryfolders.vdf lists (an external
        # drive's). Windows paths arrive as Z:\\Volumes\\…, with the backslashes doubled.
        library_folders() {
          printf '%s\n' "$1"
          sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$1/libraryfolders.vdf" 2>/dev/null | while IFS= read -r path; do
            case "$path" in
              /*) ;;
              *)
                path="$(printf '%s' "$path" | sed -e 's|\\\\|/|g' -e 's|\\|/|g')"
                case "$path" in
                  [zZ]:/*) path="/${path#??/}" ;;
                  [cC]:/*) path="$PREFIX/drive_c/${path#??/}" ;;
                  ?:/*) path="$PREFIX/dosdevices/$(printf '%s' "${path%%:*}" | tr 'A-Z' 'a-z'):/${path#??/}" ;;
                  *) continue ;;
                esac
                ;;
            esac
            printf '%s\n' "$path/steamapps"
          done
        }
        downloading_anywhere() {
          local folder IFS=$'\n'
          for folder in $(library_folders "$1"); do
            downloading_in "$folder" && return 0
          done
          return 1
        }
        # A download counts only while its Steam runs: one Steam ends when the other takes over (one sign-in
        # per account), and its download stops there. Counted anyway, it kept the script and Steam for Mac
        # waiting for 12 hours (It Takes Two, 8.11.).
        busy() {
          if game_running; then LAST_GAME="$(date +%s)"; return 0; fi
          [ -n "$WINE" ] && steam_running && downloading_anywhere "$STEAMAPPS" && return 0
          [ -n "$MAC_STEAMAPPS" ] && pgrep -qx steam_osx && downloading_anywhere "$MAC_STEAMAPPS" && return 0
          return 1
        }
        # The Nightforge that started this is still on its way out (it waits until this runs): until
        # it's gone it would count as opened again.
        if [ -n "$QUITTING" ]; then
          for i in $(seq 1 100); do kill -0 "$QUITTING" 2>/dev/null || break; sleep 0.1; done
        fi
        # The game ends: back to Nightforge (gone for three looks, so a launcher handing over doesn't count).
        if [ "$RESTART" != 1 ] && [ -n "$APP" ] && game_running; then
          gone=0
          while [ "$gone" -lt 3 ]; do
            reopened && exit 0
            late && exit 0
            unknown_too_long && exit 0
            sleep 2
            if game_running; then gone=0; else gone=$((gone + 1)); fi
          done
          open "$APP"
          exit 0
        fi
        # WINEMSYNC like every other Wine process of the session (Engine.environment).
        export WINEPREFIX="$PREFIX" WINEDEBUG=-all WINEMSYNC="$MSYNC"
        # A game started from Steam's window meanwhile (Steam refuses -shutdown then) is waited for like
        # any other: looked for while Steam ends and right before the session does, which would end the
        # game with it.
        while true; do
          while true; do
            if [ "$RESTART" = 1 ]; then recent_game && sleep 30; break; fi
            while busy; do reopened && exit 0; late && exit 0; unknown_too_long && exit 0; sleep 10; done
            recent_game && sleep 30        # cloud saves of a game that just ended (or is just starting): not otherwise
            reopened && exit 0
            busy || break
          done
          if [ "$QUIT_MAC" = 1 ] && pgrep -qx steam_osx; then
            limited osascript -e 'tell application id "com.valvesoftware.steam" to quit' >/dev/null 2>&1
            if [ "$RESTART" = 1 ]; then
              for i in $(seq 1 20); do pgrep -qx steam_osx || break; sleep 1; done
              # Still there: it hangs on something (a dialog nobody answers), and that's what the restart is for.
              if pgrep -qx steam_osx; then
                pkill -x steam_osx 2>/dev/null
                for i in $(seq 1 5); do pgrep -qx steam_osx || break; sleep 1; done
                pkill -9 -x steam_osx 2>/dev/null
              fi
            fi
          fi
          [ -n "$WINE" ] || finish
          # Nightforge opened again meanwhile has its own plans for Steam (and may start a game right
          # away): asked again before each step that would end the session.
          reopened && exit 0
          if steam_running; then
            # -noverifyfiles: checking its files, Steam would put its own steamwebhelper back over Nightforge's.
            limited wine_program 'C:\Program Files (x86)\Steam\steam.exe' -noverifyfiles -shutdown >/dev/null 2>&1
            for i in $(seq 1 20); do
              steam_running || break
              reopened && exit 0
              [ "$RESTART" != 1 ] && game_running && continue 2
              sleep 1
            done
          fi
          reopened && exit 0
          [ "$RESTART" = 1 ] && break
          game_running || break
        done
        "$(dirname "$WINE")/wineserver" -k
        sleep 2
        # Wine helpers that outlive the server, recognisable by their working directory in the prefix –
        # Wine's only, which map the engine's files (Nightforge's downloaders work there too).
        is_wine() { lsof -a -p "$1" -d txt -Fn 2>/dev/null | grep -qE '/Components/(winecx|wine|wine-staging)/'; }
        lsof -a -d cwd -Fpn 2>/dev/null           | awk -v root="$PREFIX" '/^p/ { pid = substr($0, 2) } /^n/ { if (index(substr($0, 2), root) == 1) print pid }'           | while read -r pid; do is_wine "$pid" && kill -9 "$pid" 2>/dev/null; done
        finish
        """#

    /// Installed engine binary, if setup has got that far. While the engine the component list
    /// names isn't there yet (still downloading, or its download failed), the newest installed one.
    static func installedWine() async -> URL? {
        if let manifest = try? await ComponentStore.shared.manifest(),
           let component = engineComponent(in: manifest),
           let dir = await ComponentStore.shared.installedPath(for: component),
           let wine = wineBinary(in: dir) {
            return wine
        }
        return installedWineNow()
    }

    /// The engine a game of Nightforge's own Steam starts with, and its build (nil before the first
    /// setup that recorded one). Normally `newest`; a game the newest crashed starts with the build
    /// held back for it (EngineRollback). Steam's session moves to that engine first and the prefix
    /// gets its graphics DLLs – unless a game still runs on the other one: then this start stays
    /// with the engine that runs, held or not. `switching` is told before Steam is stopped for it.
    static func engineForStart(game: GameID, newest: URL,
                               switching: @MainActor () -> Void = {}) async -> (wine: URL, build: EngineBuild?, held: HeldBuild?) {
        let rollback = EngineRollback.shared
        let history = rollback.history()
        func root(_ wine: URL) -> String { wine.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path }
        var target: (wine: URL, build: EngineBuild?, held: HeldBuild?, graphics: URL?, dxvk: URL?, d3d9: URL?)
            = (newest, nil, nil, nil, nil, nil)
        if let held = rollback.pinnedBuild(game), let wine = wineBinary(in: rollback.folder(of: held, part: held.build.engineID)) {
            let graphics = held.build.version(of: graphicsID) != nil ? graphicsID : upstreamGraphicsID
            target = (wine, held.build, held, rollback.folder(of: held, part: graphics), rollback.folder(of: held, part: dxvkID),
                      held.build.version(of: dxvkUpstreamID).map { _ in rollback.folder(of: held, part: dxvkUpstreamID) })
        } else if let current = history.current, let folder = rollback.installedFolder(of: current, part: current.engineID),
                  wineBinary(in: folder).map(root) == root(newest) {
            let graphics = current.version(of: graphicsID) != nil ? graphicsID : upstreamGraphicsID
            target = (newest, current, nil, rollback.installedFolder(of: current, part: graphics),
                      rollback.installedFolder(of: current, part: dxvkID), rollback.installedFolder(of: current, part: dxvkUpstreamID))
        }
        guard let build = target.build else { return (newest, nil, nil) }

        if let session = await offMain({ sessionWine() }), root(session) != root(target.wine) {
            guard await offMain({ !windowsGameRunning }) else {
                // Another game runs there: this start joins it, on whichever build that is.
                let held = history.held.first { held in
                    wineBinary(in: rollback.folder(of: held, part: held.build.engineID)).map(root) == root(session)
                }
                return (session, held?.build ?? (root(session) == root(newest) ? history.current : nil), held)
            }
            await switching()
            try? await stopSteam(session)
            await offMain { stopAll(session) }
        }
        let (wine, held) = (target.wine, target.held)
        let (graphics, dxvk, d3d9) = (target.graphics, target.dxvk, target.d3d9)
        await offMain {
            func existing(_ folder: URL?) -> URL? { folder.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } }
            if let held {
                useHeld(held, wine: wine)
            } else if let graphics {
                try? preparePrefix(wine: wine, build: build, graphicsDir: graphics, dxvkDir: existing(dxvk), d3d9Dir: existing(d3d9))
            }
        }
        return (wine, build, held)
    }

    /// Puts the prefix's share of `held` in place for a start with its engine `wine`. A held copy
    /// builds its own game bundle the first time; the newest one has it from setup.
    static func useHeld(_ held: HeldBuild, wine: URL) {
        let rollback = EngineRollback.shared
        let graphics = held.build.version(of: graphicsID) != nil ? graphicsID : upstreamGraphicsID
        func existing(_ folder: URL) -> URL? { FileManager.default.fileExists(atPath: folder.path) ? folder : nil }
        let d3d9 = held.build.version(of: dxvkUpstreamID).flatMap { _ in existing(rollback.folder(of: held, part: dxvkUpstreamID)) }
        try? preparePrefix(wine: wine, build: held.build, graphicsDir: rollback.folder(of: held, part: graphics),
                           dxvkDir: existing(rollback.folder(of: held, part: dxvkID)), d3d9Dir: d3d9)
        installGameBundle(wine: wine)
        if isGPTKCapable(wine: wine) { linkCrossOverProfile() }
    }

    /// The engine Nightforge last started Steam with, and when (SteamStartCheck judges that start).
    /// Written by a Steam start (off the main thread, in a task) and read by the watch of that start (on it):
    /// one value at a time, under a lock.
    static var lastSteamStart: (wine: URL, at: Date)? {
        get { steamStart.withLock { $0 } }
        set { steamStart.withLock { $0 = newValue } }
    }

    private static let steamStart = LockedValue<(wine: URL, at: Date)?>(nil)

    /// The engine a fresh Steam starts with: `wine` – or, when Steam didn't come up on the newest
    /// engine, the build held back for it (EngineRollback.steamPinnedBuild), its share of the prefix
    /// put in place. A Wine session left on another engine ends first; one a game runs in, Steam
    /// joins instead (two engines can't share the prefix).
    static func steamEngine(_ wine: URL) -> URL {
        let rollback = EngineRollback.shared
        guard let held = rollback.steamPinnedBuild(), rollback.build(running: wine) == rollback.history().current,
              let heldWine = wineBinary(in: rollback.folder(of: held, part: held.build.engineID))
        else { return wine }
        if let session = sessionWine(), session.standardizedFileURL.path != heldWine.standardizedFileURL.path {
            guard !windowsGameRunning else { return session }
            stopAll(session)
        }
        useHeld(held, wine: heldWine)
        return heldWine
    }

    /// Copies DXMT (Direct3D 10/11 → Metal) into the engine's builtin DLL folders. Safe to repeat.
    /// Nightforge's package also carries winemac.so built for one Wine version; it's only used
    /// when that matches the engine (`matchesEngine`), since a mismatched driver breaks every window.
    /// `nativeInPrefix` (winecx): only DXMT's unix bridge, winemetal, goes into the engine; its
    /// Direct3D DLLs are natives in the prefix (`installDXMTNatives`), D3DMetal holds the builtins.
    static func installGraphics(_ dxmtDir: URL, into wine: URL, matchesEngine: Bool = false, nativeInPrefix: Bool = false) throws {
        let fm = FileManager.default
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine", isDirectory: true)
        let top = graphicsTop(dxmtDir)

        for arch in ["x86_64-windows", "i386-windows", "x86_64-unix"] {
            let source = top.appendingPathComponent(arch, isDirectory: true)
            let target = lib.appendingPathComponent(arch, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                // Wine's own unix libraries, rebuilt from this Wine version: only for that engine.
                if ["winemac.so", "winebus.so"].contains(file.lastPathComponent) && !matchesEngine { continue }
                if nativeInPrefix, file.pathExtension == "dll", file.lastPathComponent != "winemetal.dll" { continue }
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: file, to: destination)
            }
        }
        // winecx has msync of its own; Nightforge's ntdll.so for it is the engine fix's (installEngineFix),
        // whose *.engine copies this mustn't take for its own.
        if !nativeInPrefix {
            try installMsync(top.appendingPathComponent("msync", isDirectory: true), into: wine, matchesEngine: matchesEngine)
        }
    }

    /// The graphics archive has one versioned top folder: v0.80/{x86_64-windows,i386-windows,x86_64-unix}
    private static func graphicsTop(_ dir: URL) -> URL {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .first { fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows").path) } ?? dir
    }

    /// DXMT's Direct3D DLLs as natives in the prefix (64-bit → system32, 32-bit → syswow64), for
    /// engines whose builtins are D3DMetal's. Wine swaps a builtin-marked DLL found in the prefix
    /// for the engine's builtin of that name, so the copies lose the marker. Safe to repeat.
    static func installDXMTNatives(_ dxmtDir: URL, windows: URL = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)) throws {
        let fm = FileManager.default
        let top = graphicsTop(dxmtDir)
        for (arch, folder) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
            let target = windows.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: target.path),
                  let files = try? fm.contentsOfDirectory(at: top.appendingPathComponent(arch), includingPropertiesForKeys: nil)
            else { continue }
            for file in files where file.pathExtension == "dll" && file.lastPathComponent != "winemetal.dll" {
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try writeAsNative(try Data(contentsOf: file), to: destination)
            }
        }
    }

    /// Wine's own Direct3D 12, which D3DMetal took the place of in the engine (kept as *.wine), as
    /// natives in system32: for games on DXMT or DXVK that look for Direct3D 12 (`layerOverrides`).
    static func installWineD3D12Natives(wine: URL, windows: URL = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)) throws {
        let engine = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/x86_64-windows")
        for name in ["d3d12.dll", "d3d12core.dll"] {
            guard let original = try? Data(contentsOf: engine.appendingPathComponent(name + ".wine")) else { continue }
            try writeAsNative(original, to: windows.appendingPathComponent("system32/\(name)"))
        }
    }

    /// Wine's builtin DLLs carry "Wine builtin DLL" right after the DOS header.
    private static let builtinMarker = Data("Wine builtin DLL".utf8)

    /// Writes a DLL with Wine's builtin marker cleared, so Wine loads it as the native it is.
    static func writeAsNative(_ dll: Data, to destination: URL) throws {
        var bytes = dll
        let range = 0x40..<(0x40 + builtinMarker.count)
        if bytes.count > range.upperBound, bytes.subdata(in: range) == builtinMarker {
            bytes.replaceSubrange(range, with: Data(count: builtinMarker.count))
        }
        if (try? Data(contentsOf: destination)) == bytes { return }
        try bytes.write(to: destination, options: .atomic)
    }

    /// Puts Apple's D3DMetal into the engine as its Direct3D builtins, the layout Apple's toolkit
    /// documents: each front end into lib/wine/x86_64-windows (Wine's own kept as *.wine), its unix
    /// half as a symlink to external/libd3dshared.dylib – a copy would move the dylib's
    /// @loader_path away from the D3DMetal framework it loads – and external/ beside them.
    /// Only files Apple signed are installed; nothing of them is changed (Apple's licence).
    /// What is there stays until the new files are all copied and checked: a copy that fails or isn't
    /// Apple's leaves the engine as it was.
    static func installD3DMetal(_ payloadDir: URL, into wine: URL) throws {
        let fm = FileManager.default
        guard let payload = d3dMetalPayloadRoot(in: payloadDir) else { throw SetupError.engineBroken }
        let external = payload.appendingPathComponent("external", isDirectory: true)
        let codes = ["libd3dshared.dylib", "D3DMetal.framework"]
        for code in codes where !isAppleSigned(external.appendingPathComponent(code)) {
            throw SetupError.engineBroken
        }
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        let windows = lib.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        let unix = lib.appendingPathComponent("wine/x86_64-unix", isDirectory: true)

        // Apple's front ends are the DLLs with a unix half; a toolkit that brings no unix folder
        // (the bridges are only links anyway) has nothing but them.
        let payloadUnix = payload.appendingPathComponent("wine/x86_64-unix", isDirectory: true)
        let bridged = Set(((try? fm.contentsOfDirectory(atPath: payloadUnix.path)) ?? []).filter { $0.hasSuffix(".so") }
            .map { String($0.dropLast(3)) })
        let frontEnds = ((try? fm.contentsOfDirectory(at: payload.appendingPathComponent("wine/x86_64-windows"),
                                                      includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "dll" && (bridged.isEmpty || bridged.contains($0.deletingPathExtension().lastPathComponent)) }
        // DLSS → MetalFX: Apple's readme has nvngx-on-metalfx installed under NVIDIA's name, nvngx.
        let names = frontEnds.map { ($0, $0.lastPathComponent) }
            + frontEnds.filter { $0.lastPathComponent == "nvngx-on-metalfx.dll" }.map { ($0, "nvngx.dll") }

        // Everything copied beside the engine's files first, and checked.
        let staging = lib.appendingPathComponent(".d3dmetal-staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging.appendingPathComponent("windows"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let stagedExternal = staging.appendingPathComponent("external", isDirectory: true)
        try fm.copyItem(at: external, to: stagedExternal)
        for code in codes where !isAppleSigned(stagedExternal.appendingPathComponent(code)) {
            throw SetupError.engineBroken
        }
        for (dll, name) in names {
            try fm.copyItem(at: dll, to: staging.appendingPathComponent("windows/\(name)"))
        }

        // Then the swap: renames on one volume, with nothing left to fail but the disk itself.
        let installedExternal = lib.appendingPathComponent("external", isDirectory: true)
        try? fm.removeItem(at: installedExternal)
        try fm.moveItem(at: stagedExternal, to: installedExternal)
        for (dll, name) in names {
            let target = windows.appendingPathComponent(name)
            let original = target.appendingPathExtension("wine")
            if fm.fileExists(atPath: target.path), !fm.fileExists(atPath: original.path), !fm.contentsEqual(atPath: dll.path, andPath: target.path) {
                try fm.copyItem(at: target, to: original)
            }
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging.appendingPathComponent("windows/\(name)"), to: target)
            let bridge = unix.appendingPathComponent((name as NSString).deletingPathExtension + ".so")
            if fm.fileExists(atPath: bridge.path) || (try? fm.destinationOfSymbolicLink(atPath: bridge.path)) != nil {
                try fm.removeItem(at: bridge)
            }
            try fm.createSymbolicLink(atPath: bridge.path, withDestinationPath: "../../external/libd3dshared.dylib")
        }
    }

    /// The D3DMetal in the engine: the version its framework says ("3.0", "4.0b3"), nil when there is none.
    static func deployedD3DMetalVersion(wine: URL? = installedWineNow()) -> String? {
        guard let wine, isD3DMetalDeployed(wine: wine) else { return nil }
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        return D3DMetalSupply.version(ofFramework: lib.appendingPathComponent("external/D3DMetal.framework"))
    }

    /// What `ensureEngine` last put in as D3DMetal, by the engine's stamp: "3.0", "apple-3.0"; nil for none.
    static func deployedD3DMetalLabel(wine: URL? = installedWineNow()) -> String? {
        guard let wine, let text = readStamp(graphicsStampFile(wine: wine)),
              let range = text.range(of: #"d3dmetal [^\s]+"#, options: .regularExpression) else { return nil }
        let label = String(text[range].dropFirst("d3dmetal ".count))
        return label == "-" ? nil : label
    }

    /// Takes Apple's D3DMetal out of the engine again, as `installD3DMetal` put it in: its front ends go
    /// (Wine's own come back from the *.wine copies, which stay for the prefix's Direct3D 12), so do the
    /// unix links to it and external/. The graphics stamp goes too, so the next `ensureEngine` sets the
    /// rest up again without it.
    static func removeD3DMetal(from wine: URL) {
        let fm = FileManager.default
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        let windows = lib.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        let unix = lib.appendingPathComponent("wine/x86_64-unix", isDirectory: true)
        let links = ((try? fm.contentsOfDirectory(atPath: unix.path)) ?? []).filter {
            (try? fm.destinationOfSymbolicLink(atPath: unix.appendingPathComponent($0).path)) == "../../external/libd3dshared.dylib"
        }
        for link in links {
            try? fm.removeItem(at: unix.appendingPathComponent(link))
            let dll = windows.appendingPathComponent((link as NSString).deletingPathExtension + ".dll")
            let original = dll.appendingPathExtension("wine")
            try? fm.removeItem(at: dll)
            if fm.fileExists(atPath: original.path) { try? fm.copyItem(at: original, to: dll) }
        }
        try? fm.removeItem(at: lib.appendingPathComponent("external"))
        try? fm.removeItem(at: graphicsStampFile(wine: wine))
    }

    /// Puts the gamepad package's winebus.so in place of the engine's (kept as winebus.so.engine)
    /// and its SDL2 next to the engine's other libraries, where winebus.so's rpath finds it.
    /// Copied to a new file and swapped in: a running Wine session keeps the one it has loaded.
    static func installGamepad(_ packageDir: URL, into wine: URL) throws {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: packageDir, includingPropertiesForKeys: nil),
              let bus = (files.compactMap { $0 as? URL }.first { $0.lastPathComponent == "winebus.so" })
        else { throw SetupError.engineBroken }
        let package = bus.deletingLastPathComponent().deletingLastPathComponent()
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        let pairs = [(bus, lib.appendingPathComponent("wine/x86_64-unix/winebus.so")),
                     (package.appendingPathComponent("lib/libSDL2-2.0.0.dylib"), lib.appendingPathComponent("libSDL2-2.0.0.dylib"))]
        for (source, target) in pairs where fm.fileExists(atPath: source.path) {
            if target.lastPathComponent == "winebus.so", fm.fileExists(atPath: target.path) {
                let original = target.appendingPathExtension("engine")
                if !fm.fileExists(atPath: original.path) { try fm.copyItem(at: target, to: original) }
            }
            if fm.fileExists(atPath: target.path), fm.contentsEqual(atPath: source.path, andPath: target.path) { continue }
            let staged = target.appendingPathExtension("new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: source, to: staged)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: target)
            }
        }
    }

    /// The engine's own files the engine fix may stand in for.
    static let engineFixFiles = ["ntdll.so", "winecoreaudio.so"]

    /// Puts the engine fix's ntdll.so and winecoreaudio.so in place of winecx's (kept as *.engine).
    /// They're built from the winecx commit of one runtime, so they only go over that runtime's own
    /// files: the package names their SHA-256 (originals.sha256), and an engine whose files are
    /// anything else keeps its own. The engine gets them back as well when the list drops the
    /// package or has it for another engine version (`packageDir` nil). The fix leaves the
    /// wineserver protocol alone, so a running session carries on with the files it has loaded.
    /// True when the fix is in.
    @discardableResult
    static func installEngineFix(_ packageDir: URL?, into wine: URL) throws -> Bool {
        let fm = FileManager.default
        let unix = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let package = packageDir.flatMap(engineFixPackage(in:))
        let originals = package.map(engineFixOriginals(in:)) ?? [:]
        // The engine's own file: the copy kept of it, or – before anything went over it – the file itself.
        func own(_ name: String) -> URL {
            let kept = unix.appendingPathComponent(name).appendingPathExtension("engine")
            return fm.fileExists(atPath: kept.path) ? kept : unix.appendingPathComponent(name)
        }
        let fits = !originals.isEmpty && originals.allSatisfy { name, sha256 in
            package.map { fm.fileExists(atPath: $0.appendingPathComponent("x86_64-unix/\(name)").path) } == true
                && (try? ComponentStore.sha256(of: own(name))) == sha256
        }
        func swap(_ source: URL, over target: URL) throws {
            guard !fm.contentsEqual(atPath: source.path, andPath: target.path) else { return }
            let staged = target.appendingPathExtension("new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: source, to: staged)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        }
        for name in engineFixFiles {
            let target = unix.appendingPathComponent(name)
            let kept = target.appendingPathExtension("engine")
            if fits, let package, originals[name] != nil {
                if !fm.fileExists(atPath: kept.path) { try fm.copyItem(at: target, to: kept) }
                try swap(package.appendingPathComponent("x86_64-unix/\(name)"), over: target)
            } else if fm.fileExists(atPath: kept.path) {
                try swap(kept, over: target)
            }
        }
        return fits
    }

    /// The folder holding originals.sha256 and x86_64-unix/ in an engine fix download.
    static func engineFixPackage(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("originals.sha256").path) { return dir }
        return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .first { fm.fileExists(atPath: $0.appendingPathComponent("originals.sha256").path) }
    }

    /// originals.sha256 as `shasum -a 256` writes it ("<hash>  ntdll.so"): what each file the package
    /// replaces was in the runtime it was built for. Names other than `engineFixFiles` don't count.
    static func engineFixOriginals(in package: URL) -> [String: String] {
        let text = (try? String(contentsOf: package.appendingPathComponent("originals.sha256"), encoding: .utf8)) ?? ""
        var originals: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let match = line.wholeMatch(of: #/([0-9a-f]{64}) [ *](\S+)/#),
                  engineFixFiles.contains(String(match.2)) else { continue }
            originals[String(match.2)] = String(match.1)
        }
        return originals
    }

    /// The folder holding external/libd3dshared.dylib and wine/ in a D3DMetal download.
    static func d3dMetalPayloadRoot(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) else { return nil }
        for case let file as URL in files where file.lastPathComponent == "libd3dshared.dylib" {
            let root = file.deletingLastPathComponent().deletingLastPathComponent()
            if fm.fileExists(atPath: root.appendingPathComponent("wine/x86_64-windows/d3d12.dll").path) { return root }
        }
        return nil
    }

    /// Signed by Apple itself (the "Software Signing" chain), not just by anyone.
    static func isAppleSigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    /// winecx keeps the Windows user folder under CrossOver's fixed name, "crossover". Pointed at
    /// the folder the prefix already has, Steam's sign-in and every game's saves stay where they are.
    static func linkCrossOverProfile(users: URL = prefix.appendingPathComponent("drive_c/users", isDirectory: true),
                                     userName: String = NSUserName()) {
        let fm = FileManager.default
        let crossover = users.appendingPathComponent("crossover")
        guard userName != "crossover", fm.fileExists(atPath: users.appendingPathComponent(userName).path),
              (try? fm.attributesOfItem(atPath: crossover.path)) == nil
        else { return }
        try? fm.createSymbolicLink(atPath: crossover.path, withDestinationPath: userName)
    }

    /// msync: Wine's synchronization (events, mutexes, semaphores every game thread waits on) on
    /// Mach semaphores instead of round trips to the wineserver, which otherwise burns CPU time a
    /// game would rather have (engine/patches/wine-11.18-msync.patch). The package's ntdll.so and
    /// wineserver replace the engine's, which stay as *.engine and come back for a package without
    /// them or for another engine version. The two only work together, so a Wine session started
    /// with the old pair ends before the swap. Switched on by WINEMSYNC (see `environment`).
    private static func installMsync(_ msyncDir: URL, into wine: URL, matchesEngine: Bool) throws {
        let fm = FileManager.default
        let root = wine.deletingLastPathComponent().deletingLastPathComponent()
        let pairs = [
            (msyncDir.appendingPathComponent("x86_64-unix/ntdll.so"), root.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")),
            (msyncDir.appendingPathComponent("bin/wineserver"), wine.deletingLastPathComponent().appendingPathComponent("wineserver")),
        ]
        let available = matchesEngine && pairs.allSatisfy { fm.fileExists(atPath: $0.0.path) }
        let sources = pairs.map { pair -> URL in
            let original = pair.1.appendingPathExtension("engine")
            return available ? pair.0 : original
        }
        let changes = zip(sources, pairs).contains { source, pair in
            fm.fileExists(atPath: source.path) && !fm.contentsEqual(atPath: source.path, andPath: pair.1.path)
        }
        guard changes else { return }
        // With the old wineserver, before it's replaced. A session that can't be told about (no process list)
        // is not left with half the pair: nothing is swapped, the stamp isn't written, the next start does it.
        guard let session = ownProcessesKnown() else { throw SetupError.sessionUnknown }
        if !session.isEmpty { stopAll(wine) }
        for (source, pair) in zip(sources, pairs) {
            let original = pair.1.appendingPathExtension("engine")
            if available, !fm.fileExists(atPath: original.path) { try fm.copyItem(at: pair.1, to: original) }
            guard fm.fileExists(atPath: source.path) else { continue }
            let staged = pair.1.appendingPathExtension("new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: source, to: staged)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
            _ = try fm.replaceItemAt(pair.1, withItemAt: staged)
        }
    }

    /// Puts MoltenVK from its component in place of the engine's own (kept as libMoltenVK.dylib.engine,
    /// which comes back when the component list drops it: `moltenVKDir` nil). The Vulkan loader finds
    /// it there inside and outside the game bundle. Copied, not moved: a running Steam keeps the
    /// library it has loaded.
    static func installMoltenVK(_ moltenVKDir: URL?, into wine: URL) throws {
        let fm = FileManager.default
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
        let installed = lib.appendingPathComponent("libMoltenVK.dylib")
        let original = lib.appendingPathComponent("libMoltenVK.dylib.engine")
        if !fm.fileExists(atPath: original.path), fm.fileExists(atPath: installed.path) {
            try fm.copyItem(at: installed, to: original)
        }
        let source = moltenVKDir.map { $0.appendingPathComponent("MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib") }
            ?? original
        guard fm.fileExists(atPath: source.path) else { return }
        let staged = lib.appendingPathComponent("libMoltenVK.dylib.new")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: source, to: staged)
        _ = try fm.replaceItemAt(installed, withItemAt: staged)
    }

    /// Direct3D DLLs a game can take from DXVK (native, in the prefix) or DXMT (builtin, in the engine).
    private static let direct3DLibraries = ["dxgi", "d3d11", "d3d10core", "d3d9"]

    /// Copies DXVK's DLLs into the prefix (64-bit → system32, 32-bit → syswow64) and makes them the
    /// default for every program; games set to DXMT override that in `applyGameSettings`. Safe to repeat.
    /// `d3d9Only` (winecx): system32 holds DXMT's DirectX 10/11 natives, so only DXVK's d3d9 goes
    /// there; a game that takes DXVK for DirectX 11 gets its DLLs next to its program (`placeDXVK`).
    /// `d3d9From`: another DXVK whose d3d9 goes there instead – upstream's, for KosmicKrisp.
    /// False when the load orders couldn't be written (a wineserver of another engine still
    /// running, say), so setup tries again next time instead of counting it done.
    @discardableResult
    static func installDXVK(_ dxvkDir: URL, wine: URL, d3d9Only: Bool = false, d3d9From: URL? = nil) throws -> Bool {
        defer { loadOrdersWritten = importRegistry("[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n"
            + direct3DLibraries.map { "\"\($0)\"=\"\(defaultLoadOrder($0, d3dMetalEngine: d3d9Only))\"" }.joined(separator: "\n"),
            wine: wine) }
        let fm = FileManager.default
        let top = dxvkTop(dxvkDir)
        let d3d9Top = d3d9From.map(dxvkTop)
        let windows = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        for (arch, folder) in [("x64", "system32"), ("x32", "syswow64")] {
            let source = top.appendingPathComponent(arch, isDirectory: true)
            let target = windows.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: target.path),
                  let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "dll" && (!d3d9Only || file.lastPathComponent == "d3d9.dll") {
                let destination = target.appendingPathComponent(file.lastPathComponent)
                let other = d3d9Top?.appendingPathComponent("\(arch)/d3d9.dll")
                let copy = file.lastPathComponent == "d3d9.dll" ? other.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil } ?? file : file
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: copy, to: destination)
            }
        }
        return true
    }

    /// Whether the last `installDXVK` got its load orders into the registry.
    private(set) static var loadOrdersWritten = true

    /// What every program without a per-game choice takes – Steam's browser above all. Gcenx's
    /// engine: DXVK's natives. winecx: DirectX 10/11 from the builtins (D3DMetal, or Wine's own);
    /// DXMT's natives in system32 are for the games that choose them (`layerOverrides`), and Steam's
    /// browser crashes on them over and over.
    static func defaultLoadOrder(_ dll: String, d3dMetalEngine: Bool) -> String {
        d3dMetalEngine && dll != "d3d9" ? "builtin" : "native,builtin"
    }

    private static func dxvkTop(_ dir: URL) -> URL {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .first { fm.fileExists(atPath: $0.appendingPathComponent("x64").path) } ?? dir
    }

    /// DXVK's DirectX 10/11 DLLs, which `placeDXVK` lays next to a game's programs.
    static let dxvkGameLibraries = ["dxgi.dll", "d3d11.dll", "d3d10core.dll"]

    /// With `use`, puts DXVK's DirectX 10/11 DLLs next to each of the game's programs (Wine looks
    /// in a program's own folder before system32, where DXMT's are), matching each program's
    /// bitness; without, takes away what an earlier call put there. A DLL the game ships itself is
    /// never touched: only files identical to DXVK's count as ours.
    static func placeDXVK(_ use: Bool, dxvkDir: URL, installDir: URL) {
        let fm = FileManager.default
        let top = dxvkTop(dxvkDir)
        func dxvk(_ name: String, arch: String) -> URL { top.appendingPathComponent("\(arch)/\(name)") }
        var folders: [URL: String] = [:]
        for exe in executableFiles(in: installDir) {
            folders[exe.deletingLastPathComponent().standardizedFileURL] = isPE32Plus(exe) == false ? "x32" : "x64"
        }
        for (folder, arch) in folders {
            for name in dxvkGameLibraries {
                let target = folder.appendingPathComponent(name)
                let exists = fm.fileExists(atPath: target.path)
                let ours = ["x64", "x32"].contains { fm.contentsEqual(atPath: target.path, andPath: dxvk(name, arch: $0).path) }
                if use {
                    guard !exists || ours, fm.fileExists(atPath: dxvk(name, arch: arch).path) else { continue }
                    if exists, fm.contentsEqual(atPath: target.path, andPath: dxvk(name, arch: arch).path) { continue }
                    try? fm.removeItem(at: target)
                    try? fm.copyItem(at: dxvk(name, arch: arch), to: target)
                } else if exists, ours {
                    try? fm.removeItem(at: target)
                }
            }
        }
    }

    /// Whether a Windows program is 64-bit (PE32+); nil when it can't be read.
    static func isPE32Plus(_ exe: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: exe) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096), head.count > 0x40 else { return nil }
        let offset = Int(head[0x3C]) | Int(head[0x3D]) << 8 | Int(head[0x3E]) << 16 | Int(head[0x3F]) << 24
        guard offset + 26 <= head.count, head[offset] == 0x50, head[offset + 1] == 0x45 else { return nil }
        let magic = Int(head[offset + 24]) | Int(head[offset + 25]) << 8
        return magic == 0x20B
    }

    /// winetricks verbs that would change every game in the shared prefix, not just the one that
    /// asks (Proton gives each game its own prefix; Nightforge has one for all): dsound, and every
    /// one of winetricks' settings that is a plain word (winetricks 20260125, `w_metadata … settings`;
    /// those with "=" aren't verbs here anyway). The Windows versions above all, which would switch
    /// Steam and every game: one game's version is `windowsVersion`, per program (AppDefaults).
    static let sharedPrefixUnsafeVerbs: Set<String> = windowsVersionVerbs.union([
        "dsound", "bad", "good", "fontfix", "forcemono", "heapcheck", "hosts", "isolate_home", "native_mdac",
        "native_oleaut32", "nocrashdialog", "remove_mono", "sandbox", "set_mididevice", "set_userpath",
    ])

    /// winetricks' verbs that set the Windows version of the whole prefix.
    static let windowsVersionVerbs: Set<String> = [
        "nt351", "nt40", "vista", "win20", "win2k", "win2k3", "win2k8", "win2k8r2", "win30", "win31",
        "win7", "win8", "win81", "win10", "win11", "win95", "win98", "winme", "winxp",
    ]

    /// .NET programs run on Wine Mono, which the engine brings along (share/wine/mono) and Wine finds
    /// by itself. Its Windows side – the .NET registry keys and libraries games and launchers check
    /// for – comes with its support package, which setup leaves out (it would show dialogs then).
    static var wineMonoInstalled: Bool {
        let registry = (try? String(contentsOf: prefix.appendingPathComponent("system.reg"), encoding: .utf8)) ?? ""
        return registry.contains("Wine Mono Windows Support")
    }

    /// Installs Wine Mono's support package quietly; a few seconds.
    static func installWineMono(_ wine: URL) async {
        let mono = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/wine/mono")
        guard let version = (try? FileManager.default.contentsOfDirectory(atPath: mono.path))?
            .filter({ $0.hasPrefix("wine-mono-") }).sorted().last
        else { return }
        let package = mono.appendingPathComponent("\(version)/support/winemono-support.msi")
        await Task.detached(priority: .userInitiated) {
            guard let process = try? WineSandbox.process(wine, ["msiexec", "/i", "Z:" + package.path.replacingOccurrences(of: "/", with: "\\"), "/qn"])
            else { return }
            var env = environment(wine: wine)
            env["WINEDLLOVERRIDES"] = nil  // setup's switch that keeps Mono out
            process.environment = env
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        }.value
    }

    /// The profile's winetricks verbs that aren't in the prefix yet (winetricks logs what it installed).
    static func missingWinetricks(_ verbs: [String]) -> [String] {
        let log = (try? String(contentsOf: prefix.appendingPathComponent("winetricks.log"), encoding: .utf8)) ?? ""
        let installed = Set(log.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return verbs.filter { !installed.contains($0) && isSafeWinetricksVerb($0) }
    }

    /// winetricks commands that look like verbs but aren't installs (scripts/build-profiles.py keeps the same list).
    static let winetricksCommands: Set<String> = [
        "annihilate", "apps", "benchmarks", "dlls", "fonts", "games", "settings", "list", "help", "version",
    ]

    /// A plain install verb that changes only what the game asks for: installWinetricks runs nothing else.
    static func isSafeWinetricksVerb(_ verb: String) -> Bool {
        !verb.isEmpty && verb.count <= 64 && !winetricksCommands.contains(verb) && !sharedPrefixUnsafeVerbs.contains(verb)
            && verb.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    /// Installs winetricks verbs into the prefix (runtimes like vcrun2019, d3dcompiler_47). Needs the
    /// winetricks and cabextract components; returns false when something was missing or failed –
    /// the game is started anyway. Output goes to Logs/winetricks.log for troubleshooting.
    @discardableResult
    static func installWinetricks(_ verbs: [String], wine: URL) async -> Bool {
        // The verbs come from the online fixes: only plain install verbs, never an option or one of
        // winetricks' commands (`annihilate` deletes the whole prefix, Steam and games included).
        let verbs = verbs.filter(isSafeWinetricksVerb)
        guard !verbs.isEmpty else { return true }
        let store = ComponentStore.shared
        guard let manifest = try? await store.manifest(),
              let winetricksComponent = manifest.component("winetricks"),
              let cabextractComponent = manifest.component("cabextract"),
              let winetricksDir = try? await store.install(winetricksComponent),
              let cabextractDir = try? await store.install(cabextractComponent)
        else { return false }
        let fm = FileManager.default
        let script = winetricksDir.appendingPathComponent("winetricks")
        let cabextract = (fm.enumerator(at: cabextractDir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "cabextract" })?.deletingLastPathComponent()
        guard fm.isExecutableFile(atPath: script.path), let cabextract else { return false }

        let logs = supportDir.appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let logFile = logs.appendingPathComponent("winetricks.log")
        // Like wine.log: one older copy, so it doesn't grow with every game for good.
        if let size = (try? fm.attributesOfItem(atPath: logFile.path))?[.size] as? UInt64, size > 8_000_000 {
            let previous = logs.appendingPathComponent("winetricks.previous.log")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: logFile, to: previous)
        }
        if !fm.fileExists(atPath: logFile.path) { fm.createFile(atPath: logFile.path, contents: nil) }
        let log = try? FileHandle(forWritingTo: logFile)
        _ = try? log?.seekToEnd()
        log?.write(Data("\n== \(Date()) winetricks \(verbs.joined(separator: " "))\n".utf8))

        var env = environment(wine: wine)
        env["WINEDLLOVERRIDES"] = nil  // installers like dotnet need mscoree, which setup turns off
        env["WINE"] = wine.path
        env["WINESERVER"] = wine.deletingLastPathComponent().appendingPathComponent("wineserver").path
        env["PATH"] = cabextract.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        // Its download cache (XDG_CACHE_HOME/winetricks) belongs in the Mac's cache folder, not ~/.cache.
        env["XDG_CACHE_HOME"] = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true).path

        guard let process = try? WineSandbox.process(script, ["--unattended"] + verbs) else {
            try? log?.close()
            return false
        }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                try? log?.close()
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            if (try? process.run()) == nil {
                try? log?.close()
                continuation.resume(returning: false)
            }
        }
    }

    /// Which copy of each Direct3D DLL a layer takes. Gcenx's engine: DXMT is the builtin, DXVK
    /// the native in system32 (the default). winecx (`d3dMetalEngine`): D3DMetal is the builtin,
    /// DXMT the native in system32 and DXVK the native next to the game (`placeDXVK`), which Wine
    /// finds before system32.
    static func layerOverrides(_ layer: GraphicsLayer, d3dMetalEngine: Bool) -> [String: String] {
        switch layer {
        case .dxmt, .dxvk:
            guard d3dMetalEngine else {
                // d3d9 stays with DXVK: DXMT only covers Direct3D 10/11.
                return layer == .dxmt ? ["dxgi": "builtin", "d3d11": "builtin", "d3d10core": "builtin"] : [:]
            }
            // Games that probe for Direct3D 12 at start (Unity does, through a delay-load that
            // needs the DLL to exist) would get D3DMetal's, which crashes against DXMT's or DXVK's
            // dxgi. Wine's own (`installWineD3D12Natives`) just answers that there's none.
            return ["dxgi": "native", "d3d11": "native", "d3d10core": "native", "d3d12": "native", "d3d12core": "native"]
        case .d3dmetal:
            return Dictionary(uniqueKeysWithValues: ["dxgi", "d3d10", "d3d10core", "d3d11", "d3d12", "d3d12core", "nvapi64", "nvngx"]
                .map { ($0, "builtin") })
        case .wined3d:
            // Wine's own Direct3D 9 (OpenGL) instead of DXVK's, for games DXVK can't run.
            return ["d3d9": "builtin"]
        case .automatic:
            return [:]
        }
    }

    /// Per-program settings for a game's executables (Wine's AppDefaults): the Direct3D layer, the
    /// profile's DLL overrides and Windows version. Rewritten in full at every launch, so a changed
    /// choice or profile never leaves stale entries. The profile's registry entries go in as well.
    static func applyGameSettings(_ choice: GraphicsLayer, profile: GameProfile?, installDir: URL, wine: URL) {
        let layer = choice == .automatic ? (profile?.graphics ?? defaultGraphics) : choice
        let d3dMetalEngine = isGPTKCapable(wine: wine)
        if d3dMetalEngine, let dxvk = installedComponentNow(dxvkID) {
            placeDXVK(layer == .dxvk, dxvkDir: dxvk, installDir: installDir)
        }
        // D3DMetal 3.0 presents itself as an AMD card whose driver Unreal warns about.
        if layer == .d3dmetal, d3dMetalEngine { clearUnrealDriverDenyList(installDir: installDir) }
        let exes = executables(in: installDir)
        var sections = [crashDialogOff]
        for exe in exes where isPlainProgramName(exe) {
            let app = "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)"
            var overrides = profile?.dllOverrides ?? [:]
            overrides.merge(layerOverrides(layer, d3dMetalEngine: d3dMetalEngine)) { _, layer in layer }
            var section = "[-\(app)\\DllOverrides]"
            if !overrides.isEmpty {
                section += "\n[\(app)\\DllOverrides]\n" + overrides.sorted { $0.key < $1.key }
                    .map { "\(regString($0.key))=\(regString($0.value))" }.joined(separator: "\n")
            }
            section += "\n[\(app)]\n\"Version\"=" + (profile?.windowsVersion.map(regString) ?? "-")
            sections.append(section)
        }
        sections += (profile?.registry ?? []).compactMap(regSection)
        importRegistry(sections.joined(separator: "\n\n"), wine: wine)
    }

    // MARK: - Unreal's driver warning

    /// The sections of an Unreal game's Hardware.ini that name the drivers it warns about: the three
    /// vendors the engine knows (they stand side by side in its code: GPU_NVIDIA, GPU_AMD, GPU_Intel; the
    /// other GPU_ names in it are shader defines), each plain and with the platform behind it.
    static let unrealDriverSections = ["GPU_AMD", "GPU_NVIDIA", "GPU_Intel"].flatMap { [$0, $0 + " Windows"] }
    /// … and the keys for the list: DriverDenyList in Unreal 5, Blacklist before. "!" clears the list.
    static let unrealDriverLists = ["!DriverDenyList", "!Blacklist"]

    /// The Unreal projects in a game folder: the ones with <Project>/Binaries/Win64/<Name>-Shipping.exe.
    static func unrealProjects(in installDir: URL) -> [URL] {
        let projects = executableFiles(in: installDir).filter { exe in
            let win64 = exe.deletingLastPathComponent()
            return exe.lastPathComponent.hasSuffix("-Shipping.exe") && win64.lastPathComponent == "Win64"
                && win64.deletingLastPathComponent().lastPathComponent == "Binaries"
        }.map { $0.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
        return Array(Set(projects)).filter { $0.lastPathComponent != "Engine" }.sorted { $0.path < $1.path }
    }

    /// D3DMetal 3.0 presents itself as an AMD card ("AMD Compatibility Mode") with driver 30.0.15.1233, which
    /// is on Unreal's own lists of drivers with known issues: the game opens "WARNING: Known issues with
    /// graphics driver", and its Yes (to the vendor's download page) ends the game. It was seen with the
    /// AMD list and, once that was cleared, with NVIDIA's – 30.0.15.1233 is 512.33 in NVIDIA's numbering, and
    /// Unreal checks the version against more than the one vendor's list. The lists come from the game's
    /// Hardware.ini, and the player's file in Saved/Config is read last: it clears them all. (The version
    /// can't be changed from outside – D3DMetal states it itself.) The lists alone didn't do it: with all
    /// three cleared the warning came again in both game tests on 2.11. So the check itself goes off as
    /// well – the console variable r.WarnOfBadDrivers (0: off; in the game's code beside the warning's
    /// text), which the player's Engine.ini sets in [SystemSettings] before the graphics start, in
    /// shipped games too. Set before every start of an Unreal game on D3DMetal, as the game may rewrite
    /// the files when it quits.
    static func clearUnrealDriverDenyList(installDir: URL) {
        let fm = FileManager.default
        let lists = Dictionary(uniqueKeysWithValues: unrealDriverLists.map { ($0, "ClearArray") })
        for project in unrealProjects(in: installDir) {
            let config = project.appendingPathComponent("Saved/Config", isDirectory: true)
            // Unreal 5 keeps its saved files under Windows, Unreal 4 under WindowsNoEditor (once it has run).
            let platforms = ["Windows"] + (fm.fileExists(atPath: config.appendingPathComponent("WindowsNoEditor").path) ? ["WindowsNoEditor"] : [])
            for platform in platforms {
                let folder = config.appendingPathComponent(platform, isDirectory: true)
                mergeIniFile(folder.appendingPathComponent("Hardware.ini"), unrealDriverSections.map { ($0, lists) })
                mergeIniFile(folder.appendingPathComponent("Engine.ini"), [unrealDriverWarningOff])
            }
        }
    }

    /// Unreal's switch for the driver check, in Engine.ini.
    static let unrealDriverWarningOff = (section: "SystemSettings", values: ["r.WarnOfBadDrivers": "0"])

    /// `sections` merged into an ini file (`mergingIni`), written only when that changes it.
    private static func mergeIniFile(_ file: URL, _ sections: [(section: String, values: [String: String])]) {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let merged = sections.reduce(text) { mergingIni($0, section: $1.section, values: $1.values) }
        guard merged != text else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? merged.write(to: file, atomically: true, encoding: .utf8)
    }

    /// No "Program Error – … has encountered a serious problem" window: Wine's debugger (AeDebug's
    /// "winedbg --auto", already the prefix's) writes the backtrace into the game log and ends the
    /// crashed game at once. With the window open the game ran on, Nightforge didn't see it end, and
    /// it held its "only one instance" lock (Control, 1.11.2026). winecx's winedbg reads the value.
    /// Set before every start, so every prefix has it.
    static let crashDialogOff = "[HKEY_CURRENT_USER\\Software\\Wine\\WineDbg]\n\"ShowCrashDialog\"=dword:00000000"

    /// A quoted .reg string. Line breaks and other control characters are dropped: in a .reg file
    /// they would end the line and start lines of their own.
    static func regString(_ text: String) -> String {
        let plain = String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f })
        return "\"" + plain.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Where a profile from the online fixes may write: a game's own settings under Software, and
    /// drive letters (MountedDevices). Never autostart entries, file associations, policies or Wine's
    /// own settings, which would reach every program in the prefix. scripts/build-profiles.py checks the same.
    /// A program's file name that can stand in a .reg section's name (AppDefaults\<name>): a game
    /// folder's name with "]", a line break and a section of its own (…\CurrentVersion\Run) would
    /// write that too. No control characters, brackets or backslashes, which no Windows program has.
    static func isPlainProgramName(_ name: String) -> Bool {
        !name.isEmpty && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F || "[]\\".unicodeScalars.contains($0) }
    }

    static func isAllowedRegistryKey(_ key: String) -> Bool {
        guard !key.unicodeScalars.contains(where: { $0.value < 0x20 || $0 == "[" || $0 == "]" }) else { return false }
        let lower = key.lowercased()
        let drives = #"hkey_local_machine\system\mounteddevices"#
        if lower == drives || lower.hasPrefix(drives + #"\"#) { return true }
        guard let root = [#"hkey_current_user\software\"#, #"hkey_local_machine\software\"#].first(where: lower.hasPrefix)
        else { return false }
        var rest = lower.dropFirst(root.count)
        if rest.hasPrefix(#"wow6432node\"#) { rest = rest.dropFirst(#"wow6432node\"#.count) }
        let vendor = rest.split(separator: "\\", maxSplits: 1).first.map(String.init) ?? ""
        return !vendor.isEmpty && !["microsoft", "classes", "policies", "wine", "wow6432node"].contains(vendor)
    }

    /// One registry entry from a profile as a .reg section; nil for types it can't express safely.
    private static func regSection(_ entry: GameProfile.RegistryEntry) -> String? {
        let roots = ["HKLM": "HKEY_LOCAL_MACHINE", "HKCU": "HKEY_CURRENT_USER"]
        var key = entry.key
        for (short, long) in roots where key.uppercased().hasPrefix(short + "\\") {
            key = long + key.dropFirst(short.count)
        }
        guard isAllowedRegistryKey(key) else { return nil }
        let header = "[\(key)]"
        guard let name = entry.name, let type = entry.type?.uppercased(), let value = entry.value else { return header }
        let data: String
        switch type {
        case "REG_SZ": data = regString(value)
        case "REG_DWORD":
            guard let number = value.hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value) else { return nil }
            data = String(format: "dword:%08x", number)
        default: return nil
        }
        return header + "\n" + regString(name) + "=" + data
    }

    /// Windows programs in a game folder (a few levels deep, where Unity/Unreal put them).
    static func executables(in dir: URL) -> [String] {
        Set(executableFiles(in: dir).map(\.lastPathComponent)).sorted()
    }

    private static func executableFiles(in dir: URL) -> [URL] {
        guard let files = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let file as URL in files {
            // Unreal's game program sits four levels down: <Project>/Binaries/Win64/<Name>-Shipping.exe.
            if files.level > 4 { files.skipDescendants(); continue }
            if file.pathExtension.lowercased() == "exe" { found.append(file) }
        }
        return found
    }

    /// Imports registry settings into the prefix and waits only for regedit itself (not for the
    /// wineserver, which keeps running as long as Steam does). Detached like every Wine command: the
    /// first one of a session starts the wineserver and Wine's services, which Steam then joins.
    @discardableResult
    static func importRegistry(_ body: String, wine: URL) -> Bool {
        let temp = prefix.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("nightforge-\(UUID().uuidString).reg")
        guard (try? ("REGEDIT4\n\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: file) }

        // In the sandbox like every Wine start: the first of a session starts its wineserver.
        guard let regedit = try? WineSandbox.process(wine, ["regedit", "/S", #"C:\windows\temp\"# + file.lastPathComponent]) else {
            return false
        }
        regedit.environment = environment(wine: wine)
        regedit.standardOutput = FileHandle.nullDevice
        regedit.standardError = FileHandle.nullDevice
        guard (try? regedit.run()) != nil else { return false }
        // A regedit takes seconds, the first of a session a few more (it starts the wineserver). One
        // that is still at it after half a minute is stuck in a session that doesn't answer: ended,
        // so the game start that asked for the import goes on – or fails – instead of waiting for good.
        guard regedit.waitUntilExit(timeout: registryTimeout) else {
            regedit.end()
            return false
        }
        return regedit.terminationStatus == 0
    }

    /// How long `importRegistry` waits for regedit.
    static let registryTimeout: TimeInterval = 30

    /// macOS only turns Game Mode on (CPU and GPU priority, lower Bluetooth latency) for apps whose
    /// bundle says they're games. Wine's loader is a bare binary, so this builds a small "Nightforge
    /// Game.app" next to it: the loader's folder hard-linked into Contents/MacOS, everything else it
    /// finds relative to itself linked back to the engine. Wine starts every Windows program with
    /// the loader it was started with, so Steam run from here hands it to its games.
    /// Rebuilt when a file was replaced since (graphics), which breaks its hard link.
    @discardableResult
    static func installGameBundle(wine: URL) -> URL? {
        let fm = FileManager.default
        let root = wine.deletingLastPathComponent().deletingLastPathComponent()  // …/Resources/wine
        let unix = root.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let bundle = root.appendingPathComponent(gameBundleName, isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)

        func inode(_ path: String) -> Int? { (try? fm.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int }
        let files = (try? fm.contentsOfDirectory(atPath: unix.path)) ?? []
        let vulkanDriver = resources.appendingPathComponent("vulkan/icd.d/MoltenVK_icd.json")
        let current = fm.fileExists(atPath: vulkanDriver.path)
            && files.allSatisfy { name in
                let original = unix.appendingPathComponent(name).path
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: original, isDirectory: &isDirectory)
                return isDirectory.boolValue || inode(original) == inode(macOS.appendingPathComponent(name).path)
            }
        // Steam may be running from it; leave a bundle that's still right alone.
        if current {
            installVulkanLayer(resources: resources)
            return macOS.appendingPathComponent("wine")
        }

        // The bundle's name under Nightforge's old name; Launch Services should forget it too.
        let legacy = root.appendingPathComponent("Nachtschicht Game.app", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) {
            let unregister = Process()
            unregister.executableURL = lsregister
            unregister.arguments = ["-u", legacy.path]
            if (try? unregister.run()) != nil { unregister.waitUntilExit() }
            try? fm.removeItem(at: legacy)
        }

        do {
            try? fm.removeItem(at: bundle)
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            for file in try fm.contentsOfDirectory(at: unix, includingPropertiesForKeys: [.isDirectoryKey]) {
                let name = file.lastPathComponent
                let target = macOS.appendingPathComponent(name)
                if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try fm.createSymbolicLink(atPath: target.path, withDestinationPath: "../../../lib/wine/x86_64-unix/\(name)")
                } else {
                    try fm.linkItem(at: file, to: target)
                }
            }
            // Wine looks for its other folders next to the loader's.
            try fm.createSymbolicLink(atPath: macOS.appendingPathComponent("x86_64-unix").path, withDestinationPath: ".")
            for arch in ["x86_64-windows", "i386-windows"] {
                try fm.createSymbolicLink(atPath: macOS.appendingPathComponent(arch).path, withDestinationPath: "../../../lib/wine/\(arch)")
            }
            // Libraries are found at @loader_path/../../, i.e. the bundle folder itself.
            for name in ["bin", "share"] {
                try fm.createSymbolicLink(atPath: bundle.appendingPathComponent(name).path, withDestinationPath: "../\(name)")
            }
            for lib in try fm.contentsOfDirectory(atPath: root.appendingPathComponent("lib").path) where lib != "wine" {
                try fm.createSymbolicLink(atPath: bundle.appendingPathComponent(lib).path, withDestinationPath: "../lib/\(lib)")
            }
            // Inside an app bundle the Vulkan loader looks for drivers in Contents/Resources only.
            // Without MoltenVK there, Steam's browser loops on failing to draw and never takes
            // a game launch.
            try fm.createDirectory(at: vulkanDriver.deletingLastPathComponent(), withIntermediateDirectories: true)
            let driver: [String: Any] = [
                "file_format_version": "1.0.0",
                "ICD": [
                    "library_path": root.appendingPathComponent("lib/libMoltenVK.dylib").path,
                    "api_version": "1.4.0",
                    "is_portability_driver": true,
                ],
            ]
            try JSONSerialization.data(withJSONObject: driver, options: .prettyPrinted).write(to: vulkanDriver)
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                try fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
            }
            let info: [String: Any] = [
                "CFBundleExecutable": "wine",
                "CFBundleIdentifier": gameBundleID,
                "CFBundleName": "Nightforge Game",
                "CFBundleIconFile": "AppIcon",
                "CFBundlePackageType": "APPL",
                "LSApplicationCategoryType": "public.app-category.games",
                "LSSupportsGameMode": true,
                "NSHighResolutionCapable": true,
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        } catch {
            try? fm.removeItem(at: bundle)
            return nil
        }
        installVulkanLayer(resources: resources)
        // Let Launch Services read the game category now rather than whenever it gets round to it.
        let register = Process()
        register.executableURL = lsregister
        register.arguments = ["-f", bundle.path]
        if (try? register.run()) != nil { register.waitUntilExit() }
        return macOS.appendingPathComponent("wine")
    }

    /// Games that draw with Vulkan themselves get Nightforge's layer (wrapper/nightforge-vulkan-layer.c)
    /// between them and MoltenVK; the Vulkan loader in the bundle picks up implicit layers from
    /// Contents/Resources. Copied rather than linked, so an app update can't pull it from under a
    /// running game.
    private static func installVulkanLayer(resources: URL) {
        let fm = FileManager.default
        guard let library = Bundle.main.url(forResource: "nightforge-vulkan-layer", withExtension: "dylib") else { return }
        let folder = resources.appendingPathComponent("vulkan/implicit_layer.d", isDirectory: true)
        let installed = folder.appendingPathComponent(library.lastPathComponent)
        let manifest = folder.appendingPathComponent("nightforge.json")
        // Written as text: the loader counts every key after "layer" as another layer and then
        // drops the file, so "layer" has to come last.
        let layer = Data("""
            {
                "file_format_version": "1.2.0",
                "layer": {
                    "name": "VK_LAYER_NIGHTFORGE_compat",
                    "type": "GLOBAL",
                    "library_path": "./\(library.lastPathComponent)",
                    "api_version": "1.4.323",
                    "implementation_version": "1",
                    "description": "Nightforge: lets Windows games start on MoltenVK",
                    "disable_environment": { "DISABLE_NIGHTFORGE_VULKAN_LAYER": "1" }
                }
            }

            """.utf8)
        if (try? Data(contentsOf: manifest)) == layer, fm.contentsEqual(atPath: library.path, andPath: installed.path) { return }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fm.removeItem(at: installed)
            try fm.copyItem(at: library, to: installed)
            try layer.write(to: manifest)
        } catch {
            try? fm.removeItem(at: manifest)
        }
    }

    /// The bundle Wine's windowed programs run as: every Windows game, and Steam's helpers too.
    static let gameBundleID = "io.github.lordhayne.nightforge.game"
    private static let gameBundleName = "Nightforge Game.app"
    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")

    /// Wine links the Windows user folders (Documents, Desktop, Downloads …) to the Mac's own. Run
    /// from the game bundle, that's a new app to macOS, and the first access waits on a privacy
    /// prompt – the whole Wine session hangs. Games also have no business in those folders, so they
    /// get ordinary folders inside the prefix. Nothing in the Mac's folders is read here: even a
    /// look would make macOS ask the user for access to Documents on every new Mac.
    static func detachUserFolders() {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        for user in (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for name in ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Templates"] {
                let folder = user.appendingPathComponent(name)
                guard (try? fm.destinationOfSymbolicLink(atPath: folder.path)) != nil else { continue }
                try? fm.removeItem(at: folder)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        }
    }

    /// Steam never limits its logs; under Wine its browser log alone can reach gigabytes.
    static func trimSteamLogs() {
        let logs = steamRoot.appendingPathComponent("logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files where ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 50_000_000 {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The program to start Steam with: the Game Mode loader when that's on and built, else `wine`.
    static func loader(for wine: URL) -> URL {
        guard Prefs.gameMode else { return wine }
        let loader = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(gameBundleName).appendingPathComponent("Contents/MacOS/wine")
        return FileManager.default.isExecutableFile(atPath: loader.path) ? loader : wine
    }

    /// msync for every Wine session, unless an engine test turns it off with `defaults write
    /// io.github.lordhayne.nightforge msync -bool false` (docs/TODO.md › Engine-Tests; there's no
    /// switch in the app). Read once per app run: every process of a session has to agree with its
    /// wineserver, and `applyMsyncMode` ends a session started the other way.
    static let msync = UserDefaults.standard.object(forKey: "msync") as? Bool ?? true

    /// Whether a session started with msync as `session` says (nil: before this was noted, when
    /// every session had it) has to end for one that wants it as `wanted`.
    static func msyncSessionEnds(wanted: Bool, session: Bool?) -> Bool { (session ?? true) != wanted }

    /// Ends the Wine session when it began with msync the other way round from `msync`. Not under
    /// a running game – the caller makes sure of that.
    static func applyMsyncMode(_ wine: URL, defaults: UserDefaults = .standard) {
        let key = "msyncSession"
        guard msyncSessionEnds(wanted: msync, session: defaults.object(forKey: key) as? Bool) else { return }
        // Not known whether a session runs (no process list): it isn't ended, and the switch isn't noted as
        // if it had been – the next start looks again.
        guard let session = ownProcessesKnown() else { return }
        if !session.isEmpty { stopAll(wine) }
        defaults.set(msync, forKey: key)
        GameLog.note("msync \(msync ? "on" : "off") from this Wine session on (engine test switch)")
    }

    static func environment(wine: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Keeps Steam's own processes out of the Dock (wrapper/hide-steam-dock.m); games are untouched.
        // From the data folder: Steam passes this on for days, and Nightforge.app may move meanwhile.
        if let hider = DockHider.path() {
            env["DYLD_INSERT_LIBRARIES"] = hider
        }
        env["WINEPREFIX"] = prefix.path
        // msync (installMsync); every Wine process of the session, wineserver included, has to agree,
        // so it's in the environment all of them start with. Engines without it ignore it.
        env["WINEMSYNC"] = msync ? "1" : "0"
        env["WINEDEBUG"] = "-all"
        // Gecko/Mono installers would otherwise pop up dialogs during setup.
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        env["PATH"] = wine.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        // With this, winecx registers every Windows module with Rosetta through Apple's library
        // (CW HACK 22434, dlls/ntdll/unix/loader.c). CrossOver and Recall set it; without it,
        // Overwatch's loader hangs at start with no window (7.11.2026). It comes with D3DMetal.
        let rosettaLibrary = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/external/libd3dshared.dylib")
        if FileManager.default.fileExists(atPath: rosettaLibrary.path) {
            env[GameEnvironment.rosettaLibrary] = rosettaLibrary.path
        }
        return env
    }

    /// Runs a Wine command and waits for it (and the wineserver it started) to finish.
    static func run(_ wine: URL, _ arguments: [String]) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = try WineSandbox.process(wine, arguments)
            process.environment = environment(wine: wine)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let server = Process()
            server.executableURL = wine.deletingLastPathComponent().appendingPathComponent("wineserver")
            server.arguments = ["-w"]
            server.environment = environment(wine: wine)
            try? server.run()
            server.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    /// Takes the "paused" mark (StateFlags 512) and the failure off a download in Steam's manifest,
    /// so Steam carries on with it at its next start.
    static func unpauseDownload(appID: Int, steamapps: URL) {
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        guard var text = try? String(contentsOf: manifest, encoding: .utf8) else { return }
        let flags = #/"StateFlags"(\s+)"(\d+)"/#
        if let match = text.firstMatch(of: flags), let value = Int(match.2) {
            text.replaceSubrange(match.range, with: "\"StateFlags\"\(match.1)\"\(value & ~512)\"")
        }
        text.replace(#/"UpdateResult"(\s+)"\d+"/#) { "\"UpdateResult\"\($0.1)\"0\"" }
        try? text.write(to: manifest, atomically: true, encoding: .utf8)
    }

    /// Asks Steam to download a game without any Steam window: an appmanifest marked "update
    /// required" makes Steam fetch the game on its next start. Call `restartSteamInBackground` after.
    static func requestDownload(appID: Int, name: String, installDir: String,
                                steamapps: URL = steamRoot.appendingPathComponent("steamapps", isDirectory: true)) throws {
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return }
        // Steam's text format reads a backslash as an escape: a name ending in one would swallow the closing quote.
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "'") + "\""
        }
        let text = """
        "AppState"
        {
        \t"appid"\t\t\(quoted(String(appID)))
        \t"Universe"\t\t"1"
        \t"name"\t\t\(quoted(name))
        \t"StateFlags"\t\t"1026"
        \t"installdir"\t\t\(quoted(installDir))
        \t"LastUpdated"\t\t"0"
        \t"SizeOnDisk"\t\t"0"
        \t"buildid"\t\t"0"
        \t"AutoUpdateBehavior"\t\t"0"
        \t"AllowOtherDownloadsWhileRunning"\t\t"0"
        \t"ScheduledAutoUpdate"\t\t"0"
        }

        """
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
    }

    /// Starts Steam hidden unless it's already running. Downloads and game launches go through it.
    /// A Steam started with older game settings is restarted, unless `busy` (a game is running).
    static func ensureSteamRunning(_ wine: URL, busy: Bool = false) async throws {
        let key = "steamConfigSignature"
        let current = UserDefaults.standard.string(forKey: key) == steamConfigSignature
        // No process list to be had: neither a second Steam is started nor this one ended.
        guard steamRunningKnown != nil else { return }
        // A Steam whose wineserver is gone: clear it away before starting afresh. A running game's
        // path (…\steamapps\common\…) also says "steam"; while one runs, its session stays.
        let ours = ownProcesses().map { $0.command.lowercased() }
        if !isSteamRunning, !ours.contains(where: { $0.contains(#"\steamapps\common\"#) }),
           ours.contains(where: { $0.contains("steam") }) {
            stopAll(wine)
        }
        if isSteamRunning {
            guard !current, !busy else { return }
            try await restartSteamInBackground(wine)
        } else {
            if !busy { applyRetinaMode(wine) }
            try startSteam(wine, arguments: ["-silent"])
        }
        UserDefaults.standard.set(steamConfigSignature, forKey: key)
    }

    /// Settings for the graphics layers go into dxvk.conf and dxmt.conf, which DXVK and DXMT read
    /// from the game's working folder – the game is started by the already running Steam, so
    /// environment variables don't reach it. Written next to every program of the game, since some
    /// start from a subfolder; a config the game ships itself is left alone.
    static func writeGameConfigs(installDir: URL, frameLimit: Int, upscaling: Bool, vulkanSamplers: Int? = nil, hdr: Bool = false) {
        var dxvk = ["dxvk.enableAsync = True"]
        if Prefs.performanceHUD { dxvk.append("dxvk.hud = fps,frametimes,gpuload") }
        var dxmt: [String] = []
        if frameLimit > 0 {
            // DXVK keeps the two apart: DirectX 10/11 through dxgi, Direct3D 9 on its own.
            dxvk += ["dxgi.maxFrameRate = \(frameLimit)", "d3d9.maxFrameRate = \(frameLimit)"]
            dxmt.append("d3d11.preferredMaxFrameRate = \(frameLimit)")  // paced by Metal
        }
        if upscaling {
            // engine/patches/dxmt-0.80-metalfx-*.patch: switched on per game, and without a fixed
            // factor DXMT upscales to exactly the window's Retina pixels.
            dxmt.append("d3d11.metalSpatialUpscale = True")
        }
        // Read by Nightforge's Vulkan layer (wrapper/nightforge-vulkan-layer.c), for games that draw
        // through Vulkan themselves or via DXVK.
        var vulkan = vulkanSamplers.map { ["maxPerStageDescriptorSamplers = \($0)"] } ?? []
        if hdr { vulkan.append("hdr = on") }
        if upscaling { vulkan.append("upscale = on") }  // MetalFX, as DXMT does it
        var folders = Set([installDir.standardizedFileURL])
        for exe in executableFiles(in: installDir) { folders.insert(exe.deletingLastPathComponent().standardizedFileURL) }
        for folder in folders {
            writeConfig(folder.appendingPathComponent("dxvk.conf"), lines: dxvk)
            writeConfig(folder.appendingPathComponent("dxmt.conf"), lines: dxmt)
            writeConfig(folder.appendingPathComponent("nightforge-vulkan.conf"), lines: vulkan, keepWhenEmpty: false)
        }
    }

    /// A profile's changes to the game's own settings files (GameProfile.fileEdits). A file the game
    /// writes at its first start isn't there before it; true when anything changed, so a start
    /// that crashed on such a setting can be tried again right away. An edit marked `once` counts
    /// as done at the first start that finds its file, matched or not: from then on the player decides.
    @discardableResult
    static func applyFileEdits(_ edits: [GameProfile.FileEdit], installDir: URL, game: String = "",
                               places: SaveTransfer.Places = SaveTransfer.Places(),
                               defaults: UserDefaults = .standard) -> Bool {
        var changed = false
        var places = places
        places.windowsInstall = installDir
        for edit in edits {
            let done = "fileEdit.done.\(game).\(edit.root ?? "GameInstall")/\(edit.path)#\(edit.find)"
            guard edit.once != true || !defaults.bool(forKey: done),
                  let base = edit.root.map({ SaveTransfer.windowsRoot($0, places) }) ?? installDir
            else { continue }
            let file = base.appendingPathComponent(edit.path).standardizedFileURL
            guard isInside(file, base), !edit.find.isEmpty,
                  let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            if edit.once == true { defaults.set(true, forKey: done) }
            let edited = editing(text, find: edit.find, replace: edit.replace)
            guard edited != text else { continue }
            if (try? edited.write(to: file, atomically: true, encoding: .utf8)) != nil {
                changed = true
            }
        }
        return changed
    }

    /// `text` with `find` made `replace`. Where `replace` holds `find` (a line added after it, say),
    /// the places replaced at an earlier start stay as they are: else `find` would be there again
    /// after every start and the file would grow by one `replace` each time.
    static func editing(_ text: String, find: String, replace: String) -> String {
        guard !find.isEmpty, text.contains(find) else { return text }
        guard replace.contains(find) else { return text.replacingOccurrences(of: find, with: replace) }
        // The earlier ones out of the way under a mark that can't be part of `find`, then back.
        let mark = "\u{1}\u{2}"
        guard !text.contains(mark), !find.unicodeScalars.contains(where: { $0.value == 1 || $0.value == 2 }) else { return text }
        return text.replacingOccurrences(of: replace, with: mark)
            .replacingOccurrences(of: find, with: replace)
            .replacingOccurrences(of: mark, with: replace)
    }

    /// Whether `file` lies in `base` with the links on the way resolved: a link in the prefix or the
    /// game folder that leads out (users\<name>\Documents once led to the Mac's own) isn't written
    /// through. resolvingSymlinksInPath leaves a path alone whose end isn't there yet (an .ini the game
    /// hasn't written), so the part that is there is resolved and the rest goes on it; a link that
    /// leads nowhere counts as outside.
    static func isInside(_ file: URL, _ base: URL) -> Bool {
        let fm = FileManager.default
        func resolved(_ url: URL) -> String? {
            var existing = url.standardizedFileURL
            var rest: [String] = []
            while (try? fm.attributesOfItem(atPath: existing.path)) == nil, existing.pathComponents.count > 1 {
                rest.insert(existing.lastPathComponent, at: 0)
                existing.deleteLastPathComponent()
            }
            let real = existing.resolvingSymlinksInPath()
            guard (try? fm.destinationOfSymbolicLink(atPath: real.path)) == nil else { return nil }
            return rest.reduce(real) { $0.appendingPathComponent($1) }.path
        }
        guard let inner = resolved(file), let outer = resolved(base) else { return false }
        return inner.hasPrefix(outer + "/")
    }

    /// A profile's values for the game's own .ini files (GameProfile.iniSettings), set in their
    /// section before every start; the file and its folders are made when the game hasn't yet.
    static func applyIniSettings(_ settings: [GameProfile.IniSetting], places: SaveTransfer.Places = SaveTransfer.Places()) {
        for setting in settings where !setting.values.isEmpty {
            guard let base = SaveTransfer.windowsRoot(setting.root, places) else { continue }
            let file = base.appendingPathComponent(setting.path).standardizedFileURL
            guard isInside(file, base) else { continue }
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let merged = mergingIni(text, section: setting.section, values: setting.values)
            guard merged != text else { continue }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? merged.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// A value for an .ini line: control characters and line breaks dropped, which would end the line
    /// and start lines (and sections) of the list's own, as in regString.
    static func iniValue(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.properties.generalCategory != .control && !CharacterSet.newlines.contains($0) })
    }

    /// A section's or key's name for an .ini line: as a value, and without "[", "]" and "=", which
    /// would close the section, open another or end the key early.
    static func iniName(_ text: String) -> String {
        String(iniValue(text).unicodeScalars.filter { !"[]=".unicodeScalars.contains($0) }).trimmingCharacters(in: .whitespaces)
    }

    /// `text` with `values` set in `[section]`: keys already there get the new value, the others
    /// go at the end of the section (sorted, so the file stays the same from start to start), and
    /// a missing section is added at the end. Everything else stays as the game wrote it. Names and
    /// values are made plain first (iniName, iniValue; the file's names the same way to find them);
    /// a section or key left empty sets nothing.
    static func mergingIni(_ text: String, section rawSection: String, values: [String: String]) -> String {
        let section = iniName(rawSection)
        var pending: [String: String] = [:]
        // In order: two keys that come out the same give the same file at every start.
        for key in values.keys.sorted() where !iniName(key).isEmpty { pending[iniName(key)] = iniValue(values[key]!) }
        guard !section.isEmpty, values.isEmpty || !pending.isEmpty else { return text }
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let crlf = lines.first?.hasSuffix("\r") == true
        var out: [String] = []
        var inSection = false
        var found = false
        func flush() {
            // Before the blank lines that end the section.
            var tail: [String] = []
            while let last = out.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tail.insert(out.removeLast(), at: 0) }
            out += pending.keys.sorted().map { "\($0)=\(pending[$0]!)" + (crlf ? "\r" : "") }
            out += tail
            pending = [:]
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inSection { flush() }
                inSection = iniName(String(trimmed.dropFirst().dropLast())).caseInsensitiveCompare(section) == .orderedSame
                found = found || inSection
                out.append(line)
                continue
            }
            if inSection, let equals = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                if let value = pending.removeValue(forKey: iniName(key)) {
                    out.append("\(key)=\(value)" + (crlf ? "\r" : ""))
                    continue
                }
            }
            out.append(line)
        }
        if inSection { flush() }
        if !found, !pending.isEmpty {
            if let last = out.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(crlf ? "\r" : "") }
            out.append("[\(section)]" + (crlf ? "\r" : ""))
            flush()
        }
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    private static func writeConfig(_ file: URL, lines: [String], keepWhenEmpty: Bool = true) {
        let marker = "# Written by Nightforge"
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let ours = existing.hasPrefix(marker) || existing.hasPrefix("# Written by Nachtschicht")  // the old name
        guard ours || !FileManager.default.fileExists(atPath: file.path) else { return }  // the game ships its own
        if lines.isEmpty && !keepWhenEmpty {
            if ours { try? FileManager.default.removeItem(at: file) }
            return
        }
        let text = (["\(marker) before each start – changes here are overwritten."] + lines).joined(separator: "\n")
        try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Game files can be downloaded again any time; backing up tens of gigabytes of them would
    /// only make Time Machine busy (and the disk with it) while you play. Saves live elsewhere.
    /// Steam for Mac's library gets the same (LibraryModel, after each scan).
    static func excludeGamesFromBackup(steamapps: URL = steamRoot.appendingPathComponent("steamapps", isDirectory: true)) {
        for name in ["common", "downloading", "shadercache", "temp"] {
            var folder = steamapps.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path),
                  (try? folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) != true
            else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
    }

    /// Quits Steam politely (so it saves its state) and starts it again hidden.
    static func restartSteamInBackground(_ wine: URL) async throws {
        try await stopSteam(wine)
        applyRetinaMode(wine)
        try startSteam(wine, arguments: ["-silent"])
        UserDefaults.standard.set(steamConfigSignature, forKey: "steamConfigSignature")
    }

    /// A Steam that stopped taking commands (SteamCommands) doesn't take its "-shutdown" either: it
    /// ends with its Wine session instead – the caller makes sure no game runs in it – and starts
    /// again in the background. A client update going in finishes first.
    static func restartHungSteam(_ wine: URL) async throws {
        var waited = 0
        while waited < 120, SteamBootstrap(steamRoot: steamRoot) == .installing {
            try await Task.sleep(for: .seconds(1))
            waited += 1
        }
        await offMain { stopAll(wine) }
        applyRetinaMode(wine)
        try startSteam(wine, arguments: ["-silent"])
        UserDefaults.standard.set(steamConfigSignature, forKey: "steamConfigSignature")
    }

    /// Asks Steam to quit and waits up to 20 s before ending it the hard way. Asked with the engine
    /// it runs on, which may be one held back for a game.
    /// stopSteam for a caller that can't await (WineSandbox.settleSession), on a thread that may wait:
    /// a client update going in finishes first, Steam is asked to quit – a download stops cleanly and
    /// goes on at the next start – and whatever's left of the session ends. Starting Steam's -shutdown
    /// passes through settleSession, which lets it join the session it ends. Without a process list it
    /// can't be told whether Steam runs (an update may be going in), so nothing is ended: false then.
    @discardableResult
    static func stopSessionNow(_ wine: URL) -> Bool {
        guard let running = steamRunningKnown else { return false }
        if running {
            var waited = 0
            while waited < 120, SteamBootstrap(steamRoot: steamRoot) == .installing {
                Thread.sleep(forTimeInterval: 1)
                waited += 1
            }
            try? startSteam(sessionWine() ?? wine, arguments: ["-shutdown"])
            var left = 20
            while left > 0, steamMayBeRunning {
                Thread.sleep(forTimeInterval: 1)
                left -= 1
            }
        }
        stopAll(wine)
        return true
    }

    /// `endWait`: seconds Steam gets for its "-shutdown" – `filesEndWait` where its files are touched after.
    static func stopSteam(_ wine: URL, endWait: Int = 20) async throws {
        try await stopSteam(wine, running: { isSteamRunning },
                            installing: { SteamBootstrap(steamRoot: steamRoot) == .installing },
                            shutdown: { try startSteam(sessionWine() ?? $0, arguments: ["-shutdown"]) },
                            hardStop: { stopAll($0) }, endWait: endWait)
    }

    /// For a stop before Steam's files are touched (a game moved, a library added or forgotten): within five
    /// minutes of a game, as the quit script, 45 s – Steam uploads its cloud saves as it ends, and the hard
    /// stop after 20 s would cut that off.
    static var filesEndWait: Int { gameRanRecently ? 45 : 20 }

    /// The steps of `stopSteam`, with what they ask and do handed in (a test hands in a Steam of its own):
    /// "-shutdown" only to a Steam that is running – asked of none, it starts one – and the hard way
    /// (`wineserver -k`) when Steam hasn't ended `endWait` pauses after it, as it sometimes doesn't. After
    /// that up to `goneWait` pauses until it's gone: a process ended a moment ago can still be listed, and
    /// the caller that looks right after took it for a Steam started again (The Forest's move, 5.11.2026).
    static func stopSteam(_ wine: URL, running: () -> Bool, installing: () -> Bool, shutdown: (URL) throws -> Void,
                          hardStop: (URL) -> Void, pause: Duration = .seconds(1), installWait: Int = 120,
                          endWait: Int = 20, goneWait: Int = 10) async throws {
        guard running() else { return }
        // A client update going in finishes first (up to 2 min): cut off, Steam would start it over.
        var waited = 0
        while waited < installWait, installing() {
            try await Task.sleep(for: pause)
            waited += 1
        }
        // It may have ended meanwhile (the update's restart, the player): a "-shutdown" would start a new one.
        guard running() else { return }
        try shutdown(wine)
        for _ in 0..<endWait {
            guard running() else { return }
            try await Task.sleep(for: pause)
        }
        hardStop(wine)
        for _ in 0..<goneWait {
            guard running() else { return }
            try await Task.sleep(for: pause)
        }
    }

    /// Why Steam's files can't be touched after its stop: nil once it is gone. A Steam still listed is asked
    /// again `wait` pauses apart before it counts as running – it may be a moment from its end – and the
    /// answer says which it is: still running, or not to be told (no process list) – never "started again".
    static func steamStillThere(wait: Int = 5, pause: Duration = .seconds(1),
                                running: () -> Bool? = { steamRunningKnown }) async -> DriveError? {
        var answer = running()
        for _ in 0..<wait where answer != false {
            try? await Task.sleep(for: pause)
            answer = running()
        }
        switch answer {
        case false?: return nil
        case true?: return .steamDidNotEnd
        case nil: return .steamNotKnown
        }
    }

    /// Removes a game (or a download in progress) without any Steam window: with Steam stopped,
    /// its manifest and files go, and Steam simply finds it not installed when it starts again.
    /// The game stays in the Steam library, and saves outside the game folder are untouched.
    static func uninstall(appID: Int, installDir: URL, wine: URL) async throws {
        try await stopSteam(wine)
        defer { try? startSteam(wine, arguments: ["-silent"]) }
        // The game's own library folder (steamapps/common/<folder>), which may be an extra one.
        let library = installDir.deletingLastPathComponent().deletingLastPathComponent()
        try removeGameFiles(appID: appID, installDirName: installDir.lastPathComponent, steamapps: library)
        try? SteamLibraries.forget(appID: appID, steamRoot: steamRoot, bottle: bottle)  // while Steam is stopped
    }

    /// A game's manifest, files, download leftovers and shader cache in one Steam library folder. Each
    /// is tried, whatever happened to the others; the manifest goes last and only once the game's folder
    /// is gone, so Steam never forgets a game whose files are still there (it's still installed then and
    /// can be removed again). A folder name that can't be one (empty, "..", with a "/") removes no
    /// folder, so the manifest stays too. Whatever stays is in the error.
    static func removeGameFiles(appID: Int, installDirName: String, steamapps: URL) throws {
        let fm = FileManager.default
        var targets: [URL] = []
        // Never let an empty or odd folder name turn into deleting all of steamapps/common.
        let name = installDirName.trimmingCharacters(in: .whitespaces)
        let folder = steamapps.appendingPathComponent("common/\(name)", isDirectory: true)
        let plain = !name.isEmpty && !name.contains("/") && name != "." && name != ".."
        if plain { targets.append(folder) }
        targets += [steamapps.appendingPathComponent("downloading/\(appID)", isDirectory: true),
                    steamapps.appendingPathComponent("shadercache/\(appID)", isDirectory: true)]
        var left: [URL] = []
        for target in targets where fm.fileExists(atPath: target.path) {
            if (try? fm.removeItem(at: target)) == nil { left.append(target) }
        }
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        if fm.fileExists(atPath: manifest.path), !plain || left.contains(folder) || (try? fm.removeItem(at: manifest)) == nil {
            left.append(manifest)
        }
        guard left.isEmpty else { throw FilesLeft(folder: steamapps, files: left) }
    }

    /// What removeGameFiles couldn't take away, named for the player ("… could not be uninstalled: …").
    struct FilesLeft: LocalizedError {
        let folder: URL
        let files: [URL]
        var errorDescription: String? {
            L10n.t("still there in %@: %@", folder.path, files.map { String($0.path.dropFirst(folder.path.count + 1)) }.joined(separator: ", "))
        }
    }

    /// Under Wine, Steam now and then hangs while starting: it never signs in, stops writing its
    /// logs and swallows every launch request. Signed out *and* silent for `seconds` is that state;
    /// a Steam that is merely slow (first start, client update) keeps logging – a client update
    /// only in bootstrap_log, so every log counts here, not console_log alone. A signed-in Steam
    /// that stops taking commands still writes configstore_log and appinfo_log: that hang is told
    /// by the command itself (SteamCommands).
    static func steamLooksStuck(quietFor seconds: TimeInterval) -> Bool {
        let logs = steamRoot.appendingPathComponent("logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
        guard let newest, Date().timeIntervalSince(newest) >= seconds else { return false }
        // An update going in is quiet for a while; restarting would cut it off (SteamBootstrap).
        guard SteamBootstrap(steamRoot: steamRoot) != .installing else { return false }
        // Signed out by Steam for Mac signing in isn't hanging: it waits to be needed again.
        return !steamSignedIn && !sessionReplaced()
    }

    /// Whether the Steam started last is signed in: connection_log tags each line with the
    /// connection state it was written in, and "Client version" opens each start. The newest
    /// line counts – a Steam that signed in and was signed out again ends in "[Logged Off …]".
    static var steamSignedIn: Bool { signedIn(steamRoot: steamRoot) }

    static func signedIn(steamRoot: URL) -> Bool {
        let session = currentSession(steamRoot: steamRoot)
        guard let last = session.split(whereSeparator: \.isNewline).last(where: { $0.contains("] [") }) else { return false }
        return last.contains("] [Logged On") && !last.contains("LoggedOff")
    }

    /// A Steam account can be signed in on one Steam client at a time: when the other one (Wine
    /// or Steam for Mac) signs in, Steam signs this one out ("Session Replaced"), and it doesn't
    /// sign in again by itself. Restarting it does.
    static func sessionReplaced(steamRoot: URL = steamRoot) -> Bool {
        currentSession(steamRoot: steamRoot).contains("Session Replaced") && !signedIn(steamRoot: steamRoot)
    }

    /// Steam has finished starting ("System startup time" in console_log since its "Client
    /// version" line). Until then it turns steam:// commands away.
    static func startupFinished(steamRoot: URL) -> Bool {
        let log = steamRoot.appendingPathComponent("logs/console_log.txt")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        let start = tail.range(of: "Client version:", options: .backwards)?.upperBound ?? tail.startIndex
        return tail[start...].contains("System startup time:")
    }

    /// connection_log since the running Steam started.
    private static func currentSession(steamRoot: URL) -> Substring {
        let log = steamRoot.appendingPathComponent("logs/connection_log.txt")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        let start = tail.range(of: "Client version:", options: .backwards)?.upperBound ?? tail.startIndex
        return tail[start...]
    }

    /// Opens Steam's main window. Questions Steam asks before a launch (licence agreement, which
    /// version to start) appear in it, and with -silent it stays hidden. SteamWindow brings it to
    /// the front.
    static func showSteamWindow(_ wine: URL) async {
        try? await startSteamOffMain(wine)
    }

    /// `startSteam` away from the main thread, for whoever is on it (the window, the controller): it looks at the
    /// processes (`ps`, up to 4 s), may set up an engine held back for Steam (a regedit), ends a session on a switch
    /// of the sandbox and waits for the helper app – seconds, in which everything would freeze.
    static func startSteamOffMain(_ wine: URL, arguments: [String] = [], extraEnvironment: [String: String] = [:]) async throws {
        try await offMain { try startSteam(wine, arguments: arguments, extraEnvironment: extraEnvironment) }
    }

    /// Starts Steam without waiting; used for signing in and for launching games.
    static func startSteam(_ wine: URL, arguments: [String] = [], extraEnvironment: [String: String] = [:]) throws {
        installWebHelperWrapper()
        var wine = wine
        // Only for a Steam that is known not to run: its files are written here (LaunchOptions too).
        let fresh = steamRunningKnown == false
        if fresh {
            SteamGuideButton.turnOff(steamRoot: steamRoot)
            SteamProgram.apply(steamRoot: steamRoot)
            wine = steamEngine(wine)
        }
        do {
            let loader = loader(for: wine)
            let process = try WineSandbox.process(loader, [steamExeWindowsPath]
                + startArguments(clientInstalled: SteamBootstrap.clientInstalled(steamRoot: steamRoot)) + arguments)
            var env = environment(wine: wine).merging(steamEnvironment) { _, new in new }
            env["WINEDLLOVERRIDES"] = steamDLLOverrides
            if loader != wine { env["WINELOADER"] = loader.path }
            env["WINEDEBUG"] = GameLog.wineDebug
            process.environment = env.merging(extraEnvironment) { _, new in new }
            process.standardInput = FileHandle.nullDevice
            // Its games inherit this, so their errors end up in the log too.
            let log = GameLog.handleForSteam()
            process.standardOutput = log ?? FileHandle.nullDevice
            process.standardError = log ?? FileHandle.nullDevice
            try process.run()
        } catch {
            // A start that never happened isn't judged as the engine's failure (SteamStartCheck, review B5).
            if fresh { lastSteamStart = nil }
            throw error
        }
        if fresh { lastSteamStart = (wine, Date()) }
    }
}
