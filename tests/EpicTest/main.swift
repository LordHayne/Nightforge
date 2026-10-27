// Checks Epic Games without Epic: what Nightforge reads from legendary, unpacking legendary once,
// Epic's sign-in code, and the store offline with the library from last time: tests/EpicTest/run.sh
import Foundation

@main
struct EpicTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor
    static func main() async {
        guard FileManager.default.homeDirectoryForCurrentUser.path.contains("/home") else {
            print("✗ runs only in its own home (tests/EpicTest/run.sh)")
            exit(1)
        }
        libraryList()
        installs()
        progress()
        launch()
        signIn()
        packed()
        profiles()
        await store()

        print(failures == 0 ? "✓ Epic" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static let list = #"""
    [{"app_name": "Sugar", "app_title": "Rocket League", "asset_infos": {"Windows": "GameAsset(app_name='Sugar')"},
      "metadata": {"namespace": "9773aa1aa54f4f7b80e44bef04986cea", "categories": [{"path": "applications"}, {"path": "games"}],
                   "keyImages": [{"type": "DieselGameBox", "url": "https://cdn1.epicgames.com/wide.jpg"},
                                 {"type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/tall.jpg"},
                                 {"type": "DieselGameBoxLogo", "url": "https://cdn1.epicgames.com/logo.png"},
                                 {"type": "Thumbnail", "url": "http://insecure.example/thumb.jpg"}],
                   "customAttributes": {"FolderName": {"type": "STRING", "value": "rocketleague"},
                                        "CloudSaveFolder": {"type": "STRING", "value": "{AppData}/RL"}}}, "dlcs": []},
     {"app_name": "Ubi", "app_title": "Far Cry", "metadata": {"customAttributes": {"ThirdPartyManagedApp": {"value": "Uplay"}}}},
     {"app_name": "discord", "app_title": "Discord", "metadata": {"categories": [{"path": "applications"}, {"path": "software"}]}},
     {"app_name": "dsc", "app_title": "Death Stranding Content",
      "metadata": {"categories": [{"path": "applications"}, {"path": "digitalextras"}, {"path": "games"}]}},
     {"app_name": "../x", "app_title": "Escape", "metadata": {}},
     {"app_name": "Odd", "app_title": "Odd Folder", "metadata": {"customAttributes": {"FolderName": {"value": "../.."}}}},
     {"app_name": "NoTitle", "app_title": "", "metadata": {}}]
    """#

    static func libraryList() {
        let games = EpicLibrary.games(fromList: Data(list.utf8)) ?? []
        check(games.map(\.appName) == ["Sugar", "Odd"],
              "games another launcher runs, programs, extras and odd entries are left out: \(games.map(\.appName))")
        let rl = games.first
        check(rl?.title == "Rocket League" && rl?.namespace == "9773aa1aa54f4f7b80e44bef04986cea", "title and namespace")
        check(rl?.cover?.absoluteString == "https://cdn1.epicgames.com/tall.jpg", "the portrait cover is the tall box art")
        check(rl?.hero?.absoluteString == "https://cdn1.epicgames.com/wide.jpg" && rl?.logo != nil, "hero and logo")
        check(rl?.folder == "rocketleague" && rl?.cloudSaves == true, "its folder and that Epic keeps its saves")
        check(games.last?.folder == "Odd", "a folder name that would climb out falls back to the app name")
        check(EpicLibrary.games(fromList: Data("not json".utf8)) == nil, "no list, no games (the old ones stay)")
    }

    static func installs() {
        let json = #"""
        {"Sugar": {"app_name": "Sugar", "install_path": "/G/rocketleague", "executable": "Binaries\\Win64\\RocketLeague.exe",
                   "install_size": 26000000000, "version": "++Prime+Update50-CL-1", "can_run_offline": true, "is_dlc": false},
         "SugarDLC": {"app_name": "SugarDLC", "install_path": "/G/rocketleague", "is_dlc": true},
         "Rel": {"app_name": "Rel", "install_path": "relative/path"}}
        """#
        let all = EpicInstall.all(fromJSON: Data(json.utf8))
        check(Set(all.keys) == ["Sugar"], "DLCs and odd paths aren't games of their own: \(all.keys.sorted())")
        let rl = all["Sugar"]
        check(rl?.path.path == "/G/rocketleague" && rl?.size == 26_000_000_000 && rl?.canRunOffline == true, "where, how big, offline")
        check(rl?.executable == #"Binaries\Win64\RocketLeague.exe"#, "its program")
        let assets = #"{"Windows": [{"app_name": "Sugar", "build_version": "++Prime+Update51-CL-2"}], "Mac": [{"app_name": "Sugar", "build_version": "mac"}]}"#
        check(EpicInstall.latestVersions(fromAssets: Data(assets.utf8)) == ["Sugar": "++Prime+Update51-CL-2"], "the newest Windows build")
    }

    static func progress() {
        let log = """
        [cli] INFO: Preparing download for "Rocket League" (Sugar)...
        [cli] INFO: Install size: 25000.50 MiB
        [cli] INFO: Download size: 12000.00 MiB (Compression savings: 52.0%)
        [DLManager] INFO: = Progress: 12.34% (123/996), Running for 00:01:10, ETA: 00:12:34
        [DLManager] INFO:  - Downloaded: 1480.00 MiB, Written: 3000.00 MiB
        [DLManager] INFO:  + Download\t- 21.50 MiB/s (raw) / 44.00 MiB/s (decompressed)
        """
        let state = Legendary.progress(inLog: log)
        check(state.fraction.map { abs($0 - 0.1234) < 0.0001 } == true, "how far: \(String(describing: state.fraction))")
        check(state.secondsLeft == 754, "time left: \(String(describing: state.secondsLeft))")
        check(state.speed.map { abs($0 - 21.5 * 1_048_576) < 1 } == true, "how fast (raw)")
        check(state.downloadSize == 12_582_912_000 && state.installSize == Int64(25000.5 * 1_048_576), "sizes")
        check(!state.finished && state.failure == nil, "still going")
        let done = Legendary.progress(inLog: log + "\n[cli] INFO: Finished installation process in 600.00 seconds.")
        check(done.finished && done.fraction == 1, "done")
        let full = Legendary.progress(inLog: log + "\n ! Failure: Not enough available disk space! 12.00 GiB < 25.00 GiB\n[cli] CRITICAL: Installation cannot proceed, exiting.")
        check(full.failure?.contains("Not enough available disk space") == true, "why it stopped: \(full.failure ?? "-")")
        check(Legendary.progress(inLog: "").fraction == nil, "nothing yet: no share")
    }

    static func launch() {
        let json = #"""
        {"game_parameters": ["-nomovie"], "game_executable": "Binaries/Win64/RocketLeague.exe",
         "game_directory": "/G/rocketleague", "egl_parameters": ["-AUTH_LOGIN=unused", "-AUTH_PASSWORD=abc123",
         "-AUTH_TYPE=exchangecode", "-epicapp=Sugar", "-epicenv=Prod", "-epicovt=/Users/a/Epic/legendary/tmp/x.ovt", "-EpicPortal"],
         "launch_command": [], "working_directory": "/G/rocketleague/Binaries/Win64", "user_parameters": ["-windowed"],
         "environment": {}, "pre_launch_command": "", "pre_launch_wait": false}
        """#
        let command = Legendary.launchCommand(fromJSON: Data(json.utf8))
        check(command?.executable.path == "/G/rocketleague/Binaries/Win64/RocketLeague.exe", "the game's program")
        check(command?.workingDirectory.path == "/G/rocketleague/Binaries/Win64", "where it runs")
        check(command?.arguments.first == "-nomovie" && command?.arguments.contains("-AUTH_PASSWORD=abc123") == true
              && command?.arguments.contains("-windowed") == true, "game, player and Epic parameters")
        check(command?.arguments.contains(#"-epicovt=Z:\Users\a\Epic\legendary\tmp\x.ovt"#) == true, "the ownership token as Wine sees it")
        check(Legendary.launchCommand(fromJSON: Data(#"{"game_directory": ""}"#.utf8)) == nil, "no program, no start")
        check(EpicStore.gameLanguage(preferred: ["de-AT", "en-US"]) == "de", "games start in the Mac's language")
        check(EpicStore.gameLanguage(preferred: []) == "en" && EpicStore.gameLanguage(preferred: ["x;rm"]) == "en", "else English")

        let inPrefix = Engine.prefix.appendingPathComponent("drive_c/Program Files/Epic Games/rocketleague/Binaries/Win64/RL.exe")
        check(Engine.windowsPath(of: inPrefix) == #"C:\Program Files\Epic Games\rocketleague\Binaries\Win64\RL.exe"#,
              "a game in the Windows environment starts by its Windows path: \(Engine.windowsPath(of: inPrefix))")
        check(Engine.windowsPath(of: URL(fileURLWithPath: "/Volumes/T7/a.exe")) == #"Z:\Volumes\T7\a.exe"#, "elsewhere through Z:")
        var game = Game(gameID: .epic("Sugar"), name: "Rocket League", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                        steamExeWindowsPath: "", installDir: inPrefix, sizeOnDisk: 0)
        game.installDirName = "rocketleague"
        check(game.windowsFolderMarker == #"\Epic Games\rocketleague\"#, "a running Epic game is found by its folder")
    }

    static func signIn() {
        let page = #"{"warning":"Do not share this code with any 3rd party service.","redirectUrl":"https://localhost/launcher/authorized?code=0a1b2c","authorizationCode":"0a1b2c3d4e","exchangeCode":null,"sid":null}"#
        check(EpicSignIn.code(fromPage: page) == "0a1b2c3d4e", "the code from Epic's last page")
        check(EpicSignIn.code(fromPage: #"{"authorizationCode": null}"#) == nil, "no code yet")
        check(EpicSignIn.code(fromPage: #"{"authorizationCode": "a b;rm"}"#) == nil, "only a plain code goes to legendary")
        check(EpicSignIn.signInURL.absoluteString.hasPrefix("https://www.epicgames.com/id/login?redirectUrl="), "Epic's own sign-in page")
    }

    /// A program packed like legendary: a few files, a link, an archive it reads in place – and a
    /// second one that tries to write outside its folder.
    static func packed() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("epic-packed-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let library = Data(repeating: 0x41, count: 5000)
        let deflated = (try? (library as NSData).compressed(using: .zlib) as Data) ?? Data()
        let good = archive([("Python.framework/Versions/3.14/Python", "b", Data([0x78, 0x9C]) + deflated, true),
                            ("certifi/cacert.pem", "x", Data("certs".utf8), false),
                            ("Python", "n", Data("Python.framework/Versions/3.14/Python\0".utf8), false),
                            ("PYZ.pyz", "z", Data("modules".utf8), false)])
        let binary = dir.appendingPathComponent("tool/legendary")
        try? fm.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? good.write(to: binary)
        check(PackedApp.entries(in: good)?.entries.map(\.name) == ["Python.framework/Versions/3.14/Python", "certifi/cacert.pem", "Python", "PYZ.pyz"],
              "the archive's table")
        check(PackedApp.environment(binary: binary).isEmpty, "nothing unpacked yet: it unpacks itself as usual")
        check((try? PackedApp.unpackOnce(binary)) == true, "unpacks")
        let unpacked = PackedApp.folder(for: binary)
        check((try? Data(contentsOf: unpacked.appendingPathComponent("Python.framework/Versions/3.14/Python"))) == library, "a library, inflated")
        check((try? String(contentsOf: unpacked.appendingPathComponent("certifi/cacert.pem"), encoding: .utf8)) == "certs", "a data file")
        check((try? fm.destinationOfSymbolicLink(atPath: unpacked.appendingPathComponent("Python").path)) == "Python.framework/Versions/3.14/Python",
              "a link")
        check(!fm.fileExists(atPath: unpacked.appendingPathComponent("PYZ.pyz").path), "the module archive stays in the program")
        let environment = PackedApp.environment(binary: binary)
        check(environment["_PYI_APPLICATION_HOME_DIR"] == unpacked.path && environment["_PYI_ARCHIVE_FILE"] == binary.path,
              "then it runs from there")
        check((try? PackedApp.unpackOnce(binary)) == true, "once is enough")

        let evil = archive([("../outside.txt", "x", Data("x".utf8), false)])
        let evilBinary = dir.appendingPathComponent("evil/legendary")
        try? fm.createDirectory(at: evilBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? evil.write(to: evilBinary)
        check((try? PackedApp.unpackOnce(evilBinary)) == false, "a name that climbs out stops the unpacking")
        check(!fm.fileExists(atPath: dir.appendingPathComponent("outside.txt").path), "and nothing lands outside")
        let link = archive([("lib", "n", Data("../../etc\0".utf8), false)])
        try? link.write(to: evilBinary)
        check((try? PackedApp.unpackOnce(evilBinary)) == false, "a link out of the folder too")
        check(PackedApp.entries(in: Data("no archive here".utf8)) == nil, "a plain file has no table")
    }

    /// PyInstaller's layout: some bytes, the entries, their table, then the cookie.
    static func archive(_ files: [(name: String, kind: Character, data: Data, compressed: Bool)]) -> Data {
        func be(_ value: Int) -> Data { Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]) }
        let lead = Data("#!bootloader".utf8)
        var body = Data()
        var table = Data()
        for file in files {
            let offset = body.count
            body += file.data
            let name = Data(file.name.utf8) + Data([0, 0, 0, 0])
            var entry = be(18 + name.count) + be(offset) + be(file.data.count) + be(file.data.count)
            entry += Data([file.compressed ? 1 : 0, UInt8(file.kind.asciiValue!)]) + name
            table += entry
        }
        let packageLength = body.count + table.count + 88
        var cookie = PackedApp.magic + be(packageLength) + be(body.count) + be(table.count) + be(314)
        cookie += Data("Python".utf8) + Data(repeating: 0, count: 58)
        return lead + body + table + cookie
    }

    static func profiles() {
        let json = #"{"formatVersion": 1, "games": {"570": {"name": "Dota 2", "antiCheatOnline": ["VAC"]},"#
            + #""epic.fn": {"name": "Fortnite", "source": "anticheat", "antiCheat": ["Easy Anti-Cheat"]}}}"#
        let epic = ProfileStore.decodeEpic(Data(json.utf8))
        check(Set(epic.keys) == ["fn"] && epic["fn"]?.antiCheat == ["Easy Anti-Cheat"], "Epic games' profiles by namespace")
    }

    /// The store with Epic's files from last time and no way to reach Epic (no legendary here).
    @MainActor
    static func store() async {
        let fm = FileManager.default
        let epicFolder = Engine.supportDir.appendingPathComponent("Epic", isDirectory: true)
        try? fm.createDirectory(at: Legendary.configDir, withIntermediateDirectories: true)
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        var known = EpicLibrary(games: EpicLibrary.games(fromList: Data(list.utf8)) ?? [], loaded: threeDaysAgo)
        known.games.append(EpicGame(appName: "fn", title: "Fortnite", namespace: "fn", folder: "Fortnite"))
        try? JSONEncoder().encode(known).write(to: epicFolder.appendingPathComponent("library.json"))
        let installPath = Legendary.gamesDir.appendingPathComponent("rocketleague").path
        let installed = #"{"Sugar": {"app_name": "Sugar", "install_path": "\#(installPath)", "executable": "RL.exe", "install_size": 1000, "version": "1"}}"#
        try? Data(installed.utf8).write(to: Legendary.configDir.appendingPathComponent("installed.json"))
        try? Data(#"{"Windows": [{"app_name": "Sugar", "build_version": "2"}]}"#.utf8).write(to: Legendary.configDir.appendingPathComponent("assets.json"))
        try? Data(#"{"formatVersion": 1, "games": {"epic.fn": {"name": "Fortnite", "antiCheat": ["Easy Anti-Cheat"]}}}"#.utf8)
            .write(to: Engine.supportDir.appendingPathComponent("profiles.json"))

        let store = EpicStore()
        check(await store.library().isEmpty, "not connected: no Epic games")
        try? Data(#"{"displayName": "Player"}"#.utf8).write(to: epicFolder.appendingPathComponent("account.json"))
        try? Data(#"{"displayName": "Player", "account_id": "1"}"#.utf8).write(to: Legendary.configDir.appendingPathComponent("user.json"))
        check(store.isConnected && store.isSignedIn && store.accountName == "Player", "connected and signed in, as Player")

        let games = await store.library()
        check(games.count == 3, "the library from last time is there at once: \(games.map(\.name))")
        let rl = games.first { $0.gameID == .epic("Sugar") }
        check(rl?.install == .installed && rl?.installDir.path == installPath && rl?.sizeOnDisk == 1000, "Rocket League is installed")
        check(rl?.pendingUpdate != nil, "and Epic has a newer build of it")
        check(rl?.art?.cover?.absoluteString == "https://cdn1.epicgames.com/tall.jpg", "with Epic's cover")
        check(rl?.provider == .epic && rl?.appID == 0 && rl?.platform == .windows, "an Epic game run through Wine")
        check(rl.map { var g = $0; g.onlineOnly = false; return OfflineReadiness.of(g, analysis: nil, accountRemembered: true) } == OfflineReadiness.startOnlineOnce,
              "never played: start it online once (an update waiting doesn't stop Epic games offline)")
        check(rl?.onlineOnly == true && rl.map { var g = $0; g.lastPlayed = Date(); return OfflineReadiness.of(g, analysis: nil, accountRemembered: true) } == OfflineReadiness.epicOnline,
              "not approved for offline by Epic: needs internet")
        check(rl.map { OfflineReadiness.of($0, analysis: nil, accountRemembered: false) } == OfflineReadiness.epicSignedOut, "signed out: not yet")
        let odd = games.first { $0.gameID == .epic("Odd") }
        check(odd?.install == .notInstalled && odd?.installDir.deletingLastPathComponent().path == Legendary.gamesDir.path,
              "a game not downloaded goes into Epic's folder in the Windows environment")
        check(games.first { $0.gameID == .epic("fn") }?.antiCheatBlock?.antiCheat == ["Easy Anti-Cheat"],
              "anti-cheat games are marked like Steam's")

        // Epic can't be reached: the games stay, and the store says since when they are.
        await store.refresh()
        check(store.sync.failed, "Epic not reached")
        check(store.sync.lastSuccess.map { abs($0.timeIntervalSince(threeDaysAgo)) < 1 } == true, "the library is from three days ago")
        check(await store.library().count == 3, "and nothing has gone from it")

        // Epic ended the sign-in (legendary drops it): the games stay, and signing in again is the way out.
        try? fm.removeItem(at: Legendary.configDir.appendingPathComponent("user.json"))
        check(store.isConnected && !store.isSignedIn, "still connected, no longer signed in")
        await store.refresh()
        check(store.sync.state == .signedOut && store.sync.failed, "says Epic signed the player out")
        check(await store.library().count == 3, "and the games are still there")

        store.recordSession(rl!, minutes: 42, endedAt: threeDaysAgo)
        let played = await store.library().first { $0.gameID == .epic("Sugar") }
        check(played?.playtimeMinutes == 42 && played?.lastPlayed.map { abs($0.timeIntervalSince(threeDaysAgo)) < 1 } == true,
              "Nightforge counts Epic games' play time itself")
        check(await EpicStore().library().first { $0.gameID == .epic("Sugar") }?.playtimeMinutes == 42, "it's kept")
    }
}
