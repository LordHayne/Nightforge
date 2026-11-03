import Foundation

/// Unity's configuration window: Unity games up to 2019.2 can open "<product> Configuration"
/// (screen, quality, "Play!") before they start and wait there. A controller can't press "Play!",
/// and no start option skips it – Unity only has -show-screen-selector, which forces it; whether it
/// comes up is in the game's PlayerSettings. So Nightforge starts wrapper/unity-play.c beside such a
/// game in its Wine session: it presses "Play!" in the game's own window and ends (The Forest,
/// Unity 5.6, 3.11.2026). The screen it then starts on is the one GameResolution wrote beforehand.
///
/// Behind a switch until the live test: `defaults write io.github.lordhayne.nightforge
/// unityDialogPlay -bool true` (there's none in the app). A profile's `skipUnityDialog: false` leaves
/// the window to the player, for a game that asks something there that matters.
enum UnityDialog {
    static let switchKey = "unityDialogPlay"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: switchKey) }

    /// How long the program looks for the window: Steam may have to start first (with an update, a
    /// minute or two) before the game does.
    static let seconds = 180

    /// One of the game's Unity programs that can show the window.
    struct Program: Equatable {
        /// "TheForest.exe"
        let executable: String
        /// "TheForest", as <Program>_Data/app.info names it: the window's title without " Configuration".
        let product: String
    }

    /// <Name>.exe beside <Name>_Data, when the data folder holds the window's picture
    /// (ScreenSelector.bmp, which Unity ships with the window) and the product's name, and the Unity
    /// is older than 2019.3 (or of a version that can't be read), which dropped the window.
    static func programs(installDir: URL) -> [Program] {
        let fm = FileManager.default
        let programs = GameResolution.unityDataFolders(installDir: installDir).compactMap { data -> Program? in
            let name = String(data.lastPathComponent.dropLast("_Data".count))
            let executable = data.deletingLastPathComponent().appendingPathComponent(name + ".exe")
            guard !name.isEmpty, fm.fileExists(atPath: data.appendingPathComponent("ScreenSelector.bmp").path),
                  fm.fileExists(atPath: executable.path),
                  let product = (try? String(contentsOf: data.appendingPathComponent("app.info"), encoding: .utf8))
                      .flatMap(product(appInfo:))
            else { return nil }
            if let version = unityVersion(dataFolder: data), !hasWindow(version) { return nil }
            return Program(executable: executable.lastPathComponent, product: product)
        }
        return programs.sorted { $0.executable < $1.executable }
    }

    /// "SKS\nTheForest" → "TheForest": app.info's second line, the product's name. Nil for one the
    /// program's command line shouldn't carry (empty, control characters, very long).
    static func product(appInfo text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, let product = Optional(lines[1]), !product.isEmpty, product.count <= 200,
              !product.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return product
    }

    /// The Unity that built the game, from the start of its data ("5.6.5p4" → (5, 6)): globalgamemanagers
    /// (Unity 5 and later), mainData (Unity 4) or a data.unity3d bundle, which all carry it as text in
    /// their first bytes.
    static func unityVersion(dataFolder: URL) -> (major: Int, minor: Int)? {
        for name in ["globalgamemanagers", "mainData", "data.unity3d"] {
            guard let file = FileHandle(forReadingAtPath: dataFolder.appendingPathComponent(name).path) else { continue }
            defer { try? file.close() }
            if let version = unityVersion(header: (try? file.read(upToCount: 128)) ?? Data()) { return version }
        }
        return nil
    }

    /// The first "5.6.5p4" or "2017.4.30f1" among the NUL-separated words of a data file's header.
    static func unityVersion(header: Data) -> (major: Int, minor: Int)? {
        for word in header.split(separator: 0) {
            let text = String(decoding: word, as: UTF8.self)
            guard let match = text.wholeMatch(of: #/(\d+)\.(\d+)\.\d+[abfpx]\d+/#),
                  let major = Int(match.1), let minor = Int(match.2) else { continue }
            return (major, minor)
        }
        return nil
    }

    /// Unity 2019.3 dropped the window (its "Display Resolution Dialog" setting).
    static func hasWindow(_ version: (major: Int, minor: Int)) -> Bool {
        version.major < 2019 || version.major == 2019 && version.minor < 3
    }

    /// "180 TheForest.exe TheForest TheForest32.exe TheForest …" – what wrapper/unity-play.c takes.
    static func arguments(_ programs: [Program], seconds: Int) -> [String] {
        [String(seconds)] + programs.flatMap { [$0.executable, $0.product] }
    }

    /// Whether the window is pressed for this game: the switch is on, its profile doesn't keep it,
    /// and it has programs that can show it.
    static func programs(for game: Game, profile: GameProfile?, enabled: Bool = enabled) -> [Program] {
        guard enabled, game.bottle.isBuiltIn, profile?.skipUnityDialog != false else { return [] }
        return programs(installDir: game.installDir)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: (game: String, process: DetachedProcess)?

    /// Right after the game's start, in the Wine session it joins (`wine`: the engine that runs it). A
    /// start sent again (LibraryModel resends one Steam didn't take) leaves the program that still looks.
    static func start(for game: Game, profile: GameProfile?, wine: URL,
                      program: URL? = Bundle.main.url(forResource: "unity-play", withExtension: "exe")) {
        let programs = programs(for: game, profile: profile)
        guard !programs.isEmpty, let program else { return }
        lock.lock()
        defer { lock.unlock() }
        if let running, running.game == game.gameID.key, running.process.isRunning { return }
        let process = DetachedProcess()
        process.executableURL = wine
        process.arguments = [Engine.windowsPath(of: program)] + arguments(programs, seconds: seconds)
        process.environment = Engine.environment(wine: wine)
        // Not in the game's folder, where it would count as the game's own (GameProcesses.runsFrom).
        process.currentDirectoryURL = Engine.prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        // Its line ("pressed Play!", "didn't come up") goes into the game log.
        let descriptor = open(GameLog.url.path, O_WRONLY | O_APPEND)
        process.standardError = descriptor < 0 ? FileHandle.nullDevice : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard (try? process.run()) != nil else { return }
        running = (game.gameID.key, process)
        GameLog.note("Unity's window: pressing Play! when \(programs.map(\.executable).joined(separator: ", ")) shows it")
    }
}
