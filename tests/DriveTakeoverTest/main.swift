// Checks how the games on a drive are taken over without a download, store by store, in an empty home:
// tests/DriveTakeoverTest/run.sh
import Foundation

@main
@MainActor
struct DriveTakeoverTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let fm = FileManager.default

    static func write(_ text: String, _ file: URL) {
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    static func snapshot(_ folder: URL) -> [String: String] {
        var result: [String: String] = [:]
        guard let files = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            result[file.path] = (try? String(contentsOf: file, encoding: .utf8)) ?? "?"
        }
        return result
    }

    static func manifest(_ appID: Int, _ name: String, size: Int64) -> String {
        "\"AppState\"\n{\n\t\"appid\"\t\t\"\(appID)\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"4\"\n"
            + "\t\"installdir\"\t\t\"\(name)\"\n\t\"SizeOnDisk\"\t\t\"\(size)\"\n}\n"
    }

    static func main() async {
        // Settings into the test's folder: .standard is a domain named after the program in ~/Library/Preferences,
        // whatever HOME says, and each run left d3dmetal-test.plist or drive-takeover-test.plist there (23.11.2026).
        TestDefaults.useWorkFolder()
        guard NSHomeDirectory().contains("/T/") || NSHomeDirectory().contains("/tmp") else {
            print("✗ This series writes Nightforge's data: it runs in a home of its own (tests/DriveTakeoverTest/run.sh)")
            exit(1)
        }
        FakeProcesses.installEmpty()
        let root = fm.temporaryDirectory.appendingPathComponent("drive-takeover-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let drive = root.appendingPathComponent("Volumes/Games", isDirectory: true)

        checkRules()
        checkTexts()
        checkSteam(root, drive)
        await checkGOG(drive)
        await checkEpic(drive)

        if failures == 0 {
            print("✓ A drive's games are taken over without a download, each store its own way")
        } else {
            print("\(failures) check(s) failed")
            exit(1)
        }
    }

    // MARK: - When

    static func checkRules() {
        typealias State = DriveTakeoverRules.State
        let idle = State(windowsSteam: true)
        check(DriveTakeoverRules.due(asked: true, waited: false, state: idle, last: idle), "asked for (start, a drive plugged in): a look")
        check(!DriveTakeoverRules.due(asked: false, waited: false, state: idle, last: nil), "nothing asked, nothing waiting: no look")
        check(!DriveTakeoverRules.due(asked: false, waited: true, state: idle, last: idle), "something waits and nothing changed: no look")
        var busy = idle
        busy.busy = true
        check(DriveTakeoverRules.due(asked: false, waited: true, state: idle, last: busy), "the game that was in the way has ended: a look")
        var signedIn = idle
        signedIn.epicSignedIn = true
        check(DriveTakeoverRules.due(asked: false, waited: true, state: signedIn, last: idle), "Epic signed in meanwhile: a look")
        var listed = signedIn
        listed.epicGames = 40
        check(DriveTakeoverRules.due(asked: false, waited: true, state: listed, last: signedIn), "Epic's list of games arrived: a look")
        var quit = idle
        quit.macSteamOpen = true
        check(DriveTakeoverRules.due(asked: false, waited: true, state: idle, last: quit), "the player quit Steam for Mac: a look")

        let waiting = [DriveFinds.Waiting(provider: .steam, platform: .windows, name: "A", reason: .steamNotSetUp),
                       DriveFinds.Waiting(provider: .steam, platform: .mac, name: "B", reason: .steamNotSetUp),
                       DriveFinds.Waiting(provider: .epic, platform: .windows, name: "C", reason: .notConnected),
                       DriveFinds.Waiting(provider: .gog, platform: .windows, name: "D", reason: .notOwned)]
        check(DriveTakeover.summary(waiting) == "2 Steam game(s) wait for their Steam to be set up, 1 Epic Games game(s) wait for the sign-in, "
              + "1 folder(s) are no GOG game of this account", "the log says what waits and for what: \(DriveTakeover.summary(waiting))")
        // The drives looked at are the test's own (TestDrives): what is plugged into the Mac, or mounted by another series
        // meanwhile, changes nothing here.
        let own = FileManager.default.temporaryDirectory.appendingPathComponent("drive-takeover-own-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: own) }
        let (games, _, _) = TestDrives.three(in: own)
        check(DriveTakeover.drives(testHome: true) == [games], "only the drive with Nightforge's folder that games can go on is looked at")
        TestDrives.none()
        check(DriveTakeover.drives(testHome: true).isEmpty, "no drive: nothing looked at, whatever the Mac has plugged in")
    }

    // MARK: - What the player reads (the user's pick 15.11.: A, one line)

    static func checkTexts() {
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        typealias Taken = DriveTakeover.TakenGame
        let many = (0..<14).map { Taken(name: "Game \($0)", provider: .steam, platform: .windows) }
        check(DriveTakeoverText.note(many, drive: "Games") == "14 games on “Games” are back", "the note: how many, and on which drive")
        check(DriveTakeoverText.note([Taken(name: "Mafia II", provider: .gog, platform: .windows)], drive: "Games") == "Mafia II on “Games” is back",
              "one game: its name")

        func waiting(_ provider: Provider, _ platform: Platform, _ reason: DriveFinds.Wait, _ count: Int) -> [DriveFinds.Waiting] {
            (1...count).map { DriveFinds.Waiting(provider: provider, platform: platform, name: "\(provider.rawValue) \($0)", reason: reason) }
        }
        let all = waiting(.steam, .windows, .steamNotSetUp, 8) + waiting(.steam, .mac, .steamNotSetUp, 5) + waiting(.gog, .windows, .notOwned, 2)
            + waiting(.epic, .windows, .notConnected, 9) + waiting(.gog, .mac, .notConnected, 1) + waiting(.epic, .windows, .notOwned, 3)
        let lines = DriveTakeoverText.lines(all, drive: "Games", path: "/Volumes/Games")
        check(lines.map(\.need) == [.signIn(.epic), .signIn(.gog), .macSteam],
              "a line only where the player can act – a sign-in, Steam for Mac – never for Windows Steam (the first start) or a folder of another account: \(lines.map(\.need))")
        check(lines.map(\.text) == ["9 Epic games on “Games” are waiting for sign-in", "One GOG game on “Games” is waiting for sign-in",
                                    "5 Mac games on “Games” are waiting for Steam for Mac"], "one line each: \(lines.map(\.text))")
        check(lines.map(\.button) == ["Sign In", "Sign In", "Set Up"], "each with its button")
        check(lines.map(\.count) == [9, 1, 5] && lines.last?.firstName == "steam 1", "how many, and the first game for the setup to name")
        check(Set(lines.map(\.id)).count == 3 && lines.allSatisfy { $0.drivePath == "/Volumes/Games" }, "told apart, by drive")
        check(DriveTakeoverText.lines(waiting(.steam, .windows, .steamNotSetUp, 3), drive: "Games", path: "/Volumes/Games").isEmpty,
              "Steam's Windows games alone: nothing to show, the first start sets Steam up")

        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        check(DriveTakeoverText.note(many, drive: "Games") == "14 Spiele auf „Games“ sind wieder da", "German: the note")
        check(DriveTakeoverText.lines(all, drive: "Games", path: "/Volumes/Games").map(\.text)
              == ["9 Epic-Spiele auf „Games“ warten auf die Anmeldung", "Ein GOG-Spiel auf „Games“ wartet auf die Anmeldung",
                  "5 Mac-Spiele auf „Games“ warten auf Steam für Mac"], "German: the lines")
        check(DriveTakeoverText.lines(all, drive: "Games", path: "/Volumes/Games").map(\.button) == ["Anmelden", "Anmelden", "Einrichten"],
              "German: the buttons")
    }

    // MARK: - Steam

    static func checkSteam(_ root: URL, _ drive: URL) {
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let bottle = Bottle(name: "Test", url: prefix, isBuiltIn: true)
        let steamRoot = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        try? fm.createDirectory(at: prefix.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/z:").path, withDestinationPath: "/")
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/c:").path, withDestinationPath: "../drive_c")
        // A fresh Steam: its own library, nothing else.
        let list = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t\t\"contentid\"\t\t\"11\"\n\t\t\"apps\"\n\t\t{\n\t\t}\n\t}\n}\n"
        for file in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] { write(list, steamRoot.appendingPathComponent(file)) }
        // The drive as an earlier Nightforge left it.
        let library = DriveLibrary.windowsSteam(on: drive)
        write("\"libraryfolder\"\n{\n\t\"contentid\"\t\t\"4242\"\n\t\"label\"\t\t\"\"\n}\n", library.appendingPathComponent("libraryfolder.vdf"))
        write(manifest(550, "Left 4 Dead 2", size: 3000), library.appendingPathComponent("steamapps/appmanifest_550.acf"))
        write(manifest(287700, "MGS_TPP", size: 7000), library.appendingPathComponent("steamapps/appmanifest_287700.acf"))
        write("x", library.appendingPathComponent("steamapps/common/Left 4 Dead 2/left4dead2.exe"))
        let before = snapshot(drive)

        func known() -> KnownInstalls {
            KnownInstalls(windowsSteamLibraries: LibraryScanner.libraryFolders(steamRoot: steamRoot, bottle: bottle))
        }
        let contents = DriveContents.read(drive: drive)
        var finds = DriveFinds.look(drive: drive, contents: contents, known: known())
        check(finds.windowsSteam.map(\.appID) == [550, 287700], "a fresh Steam doesn't know the drive's library: both games are new")
        check(!LibraryModel.listHas(library.appendingPathComponent("steamapps"), in: known().windowsSteamLibraries ?? []), "and its list doesn't have it")
        do {
            try SteamLibraries.ensure(library: library, path: DriveLibrary.windowsPath(of: library), steamRoot: steamRoot,
                                      rootPath: #"C:\Program Files (x86)\Steam"#, bottle: bottle)
        } catch { check(false, "the library is added: \(error)") }
        for file in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] {
            let entry = VDF.nodes((try? String(contentsOf: steamRoot.appendingPathComponent(file), encoding: .utf8)) ?? "")?.first?["1"]
            check(entry?["path"]?.string == DriveLibrary.windowsPath(of: library) && entry?["contentid"]?.string == "4242",
                  "\(file): the drive's library with the number it had")
            check(entry?["apps"]?["550"]?.string == "3000" && entry?["apps"]?["287700"]?.string == "7000", "\(file): and the games in it")
        }
        finds = DriveFinds.look(drive: drive, contents: contents, known: known())
        check(finds.windowsSteam.isEmpty && finds.isEmpty, "taken over: nothing of Steam's is new any more")
        check(LibraryModel.listHas(library.appendingPathComponent("steamapps"), in: known().windowsSteamLibraries ?? []), "the list has it now")
        let games = LibraryScanner.scan(bottle: bottle).filter { $0.install == .installed }.map(\.appID).sorted()
        write("", steamRoot.appendingPathComponent("steam.exe"))
        check(games.isEmpty, "without Steam there's no library to scan")
        let scanned = LibraryScanner.scan(bottle: bottle).filter { $0.install == .installed }.map(\.appID).sorted()
        check(scanned == [550, 287700], "the scan shows both as installed, from the drive: \(scanned)")
        check(snapshot(drive) == before, "nothing on the drive changed: Steam's mark was there and stays")
    }

    // MARK: - GOG

    static func checkGOG(_ drive: URL) async {
        let support = Engine.supportDir.appendingPathComponent("GOG", isDirectory: true)
        let base = DriveLibrary.gog(on: drive)
        let folder = base.appendingPathComponent("Mafia II", isDirectory: true)
        let info = #"""
            { "buildId": "51277443195366142", "clientId": "51014162722881154", "gameId": "1816059595", "language": "German",
              "languages": ["de-DE"], "name": "Mafia II",
              "playTasks": [{ "category": "game", "isPrimary": true, "name": "Mafia II", "path": "pc/mafia2.exe", "type": "FileTask", "workingDir": "pc" }],
              "rootGameId": "1816059595", "version": 1 }
            """#
        write(info, folder.appendingPathComponent("goggame-1816059595.info"))
        write("game", folder.appendingPathComponent("pc/mafia2.exe"))
        write(info.replacingOccurrences(of: "1816059595", with: "1999999999"), base.appendingPathComponent("Not Mine/goggame-1999999999.info"))
        let before = snapshot(drive)
        let contents = DriveContents.read(drive: drive)
        guard let mafia = contents.gog.first(where: { $0.id == "1816059595" }), let other = contents.gog.first(where: { $0.id == "1999999999" }) else {
            return check(false, "both GOG folders are read: \(contents.gog)")
        }

        // Not connected: nothing is known, nothing is taken.
        let signedOut = GOGStore()
        check(signedOut.knownInstalls() == nil, "GOG not connected: nothing to go by")
        check(!signedOut.adopt(mafia, folder: folder, size: 4), "and nothing is taken")
        check(!fm.fileExists(atPath: support.appendingPathComponent("installed.json").path), "nor recorded")

        // Connected, the account owns Mafia II.
        write(#"{ "username": "tester" }"#, support.appendingPathComponent("account.json"))
        let library = GOGLibrary(games: [GOGGame(id: "1816059595", title: "Mafia II")], loaded: Date())
        try? JSONEncoder().encode(library).write(to: support.appendingPathComponent("library.json"))
        let store = GOGStore()
        let known = store.knownInstalls()
        check(known?.owned == ["1816059595"] && known?.installed.isEmpty == true, "connected: what the account owns, nothing installed yet")
        let finds = DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls(gog: known))
        let waiting = finds.waiting.filter { $0.provider == .gog }
        check(finds.gog.map(\.id) == ["1816059595"] && waiting.map(\.name) == ["Mafia II"] && waiting.first?.reason == .notOwned,
              "the owned one is to take, the other waits: \(finds.gog.map(\.id)) \(waiting)")
        check(!store.adopt(other, folder: base.appendingPathComponent("Not Mine"), size: 4), "a game the account doesn't own isn't taken")
        check(!store.adopt(mafia, folder: base.appendingPathComponent("Elsewhere"), size: 4), "nor one whose info file isn't in the folder named")
        check(store.adopt(mafia, folder: folder, size: 4321), "the owned game is taken")
        check(!store.adopt(mafia, folder: folder, size: 4321), "once")
        let recorded = (try? Data(contentsOf: support.appendingPathComponent("installed.json"))).flatMap { try? JSONDecoder().decode([String: GOGInstall].self, from: $0) }
        check(recorded?["1816059595"] == GOGInstall(id: "1816059595", path: folder, platform: .windows, build: "51277443195366142",
                                                    language: "de-DE", size: 4321, dlcs: []),
              "recorded with its folder, build and language, as a finished download would be: \(String(describing: recorded))")
        // A new Nightforge start reads the record: the game stands as installed, from the drive.
        let game = await GOGStore().library().first { $0.gameID == .gog("1816059595") }
        check(game?.install == .installed && game?.installDir.path == folder.path && game?.sizeOnDisk == 4321,
              "it shows as installed, on the drive: \(String(describing: game?.install)) \(game?.installDir.path ?? "-")")
        check(game.flatMap { try? GOGStore().launchCommand(for: $0) }?.executable.path == folder.appendingPathComponent("pc/mafia2.exe").path,
              "and starts from its own info file")
        check(DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls(gog: GOGStore().knownInstalls())).gog.isEmpty,
              "taken over: nothing of GOG's is new any more")
        check(snapshot(drive) == before, "nothing on the drive changed")
    }

    // MARK: - Epic

    /// A legendary that answers `import` and `uninstall` the way 0.21.1 does (read from its code): it writes its
    /// list, warns about a game with files missing, ends with 0 after a refusal and stops on an add-on without files.
    static let legendary = #"""
        #!/bin/sh
        echo "$@" >> "$LEGENDARY_CONFIG_PATH/calls.log"
        cmd="$1"; app="$2"; path="$3"
        frag="$LEGENDARY_CONFIG_PATH/frag"; mkdir -p "$frag"
        list() {
          { printf '{'; first=1
            for f in "$frag"/*; do [ -f "$f" ] || continue; [ $first = 1 ] || printf ','; first=0; cat "$f"; done
            printf '}'; } > "$LEGENDARY_CONFIG_PATH/installed.json"
        }
        case "$cmd" in
        import)
          case "$app" in
          Quail|Heron|QuailDLC)
            [ "$app" = Heron ] && echo "[cli] WARNING: Some files are missing from the game installation, install may not match latest Epic Games Store version or might be corrupted." >&2
            dlc=false; [ "$app" = QuailDLC ] && dlc=true
            printf '"%s": {"app_name": "%s", "install_path": "%s", "executable": "Game.exe", "version": "1.0", "is_dlc": %s, "install_size": 5, "can_run_offline": true, "needs_verification": true}' "$app" "$app" "$path" "$dlc" > "$frag/$app"
            list ;;
          QuailEmpty) echo "ZeroDivisionError: division by zero" >&2; exit 1 ;;
          *) echo "[cli] ERROR: Game executable could not be found at \"$path/Game.exe\", please verify that the specified path is correct." >&2 ;;
          esac ;;
        uninstall) rm -f "$frag/$app"; list ;;
        esac
        exit 0
        """#

    static func checkEpic(_ drive: URL) async {
        let support = Engine.supportDir.appendingPathComponent("Epic", isDirectory: true)
        let config = Legendary.configDir
        let base = DriveLibrary.epic(on: drive)
        for name in ["ABZU", "AlanWake", "Refused"] { write("game", base.appendingPathComponent("\(name)/Game.exe")) }
        let before = snapshot(drive)
        // The stand-in, where Nightforge's legendary lies, noted as one that runs as it comes.
        let program = ComponentStore.shared.root.appendingPathComponent("legendary/9.9.9/legendary")
        write(legendary.split(separator: "\n", omittingEmptySubsequences: false).map { $0.drop(while: { $0 == " " }) }.joined(separator: "\n"), program)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        write("", program.deletingLastPathComponent().appendingPathComponent(".sha256"))
        write("", PackedApp.refusedNote(for: program))

        check(EpicStore.importArguments("Quail", folder: base.appendingPathComponent("ABZU"))
              == ["import", "Quail", base.appendingPathComponent("ABZU").path, "--platform", "Windows", "--skip-dlcs"],
              "legendary is asked for the Windows version, one app at a time")
        check(EpicStore.importFoundTooLittle("[cli] WARNING: Some files are missing from the game installation, install may not match …")
              && !EpicStore.importFoundTooLittle("[cli] INFO: Game install appears to be complete."), "its warning about missing files is read")

        var quail = EpicGame(appName: "Quail", title: "ABZÛ")
        quail.folder = "ABZU"
        quail.dlcs = [EpicDLC(appName: "QuailDLC", title: "Extra Level"), EpicDLC(appName: "QuailEmpty", title: "Nothing in it"),
                      EpicDLC(appName: "QuailAbsent", title: "Not on the drive")]
        var heron = EpicGame(appName: "Heron", title: "Alan Wake")
        heron.folder = "AlanWake"
        var refused = EpicGame(appName: "Stubborn", title: "Refused")
        refused.folder = "Refused"
        func find(_ game: EpicGame) -> DriveFinds.EpicFind {
            DriveFinds.EpicFind(appName: game.appName, title: game.title, folder: base.appendingPathComponent(game.folder), addOns: (game.dlcs ?? []).map(\.appName))
        }

        // Not connected, then connected but signed out: nothing is asked of legendary.
        check(EpicStore().knownInstalls() == nil, "Epic not connected: nothing to go by")
        write(#"{ "displayName": "tester" }"#, support.appendingPathComponent("account.json"))
        try? JSONEncoder().encode(EpicLibrary(games: [quail, heron, refused], loaded: Date())).write(to: support.appendingPathComponent("library.json"))
        let signedOut = EpicStore()
        check(signedOut.knownInstalls()?.signedIn == false, "connected, but Epic ended the sign-in")
        if case .refused = await signedOut.adopt(find(quail)) {} else { check(false, "signed out: not taken") }
        check(!fm.fileExists(atPath: config.appendingPathComponent("calls.log").path), "and legendary wasn't asked")

        write(#"{ "displayName": "tester" }"#, config.appendingPathComponent("user.json"))
        let store = EpicStore()
        let contents = DriveContents.read(drive: drive)
        var finds = DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls(epic: store.knownInstalls()))
        check(finds.epic.map(\.appName) == ["Quail", "Heron", "Stubborn"], "signed in: the three folders are games of the account: \(finds.epic.map(\.appName))")

        // A download that stopped: legendary's note of how far it got keeps the folder for that download.
        write("{}", config.appendingPathComponent("tmp/Quail.resume"))
        let stopped = DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls(epic: EpicStore().knownInstalls()))
        check(stopped.epic.map(\.appName) == ["Heron", "Stubborn"], "a download that stopped isn't offered to legendary as a game: \(stopped.epic.map(\.appName))")
        try? fm.removeItem(at: config.appendingPathComponent("tmp/Quail.resume"))

        // A whole game with one add-on there, one without files and one that isn't on the drive.
        let taken = await store.adopt(find(quail))
        check(taken == .taken, "a game that's all there is taken: \(taken)")
        func installed() -> Data { (try? Data(contentsOf: config.appendingPathComponent("installed.json"))) ?? Data() }
        check(EpicInstall.all(fromJSON: installed())["Quail"]?.path.path == base.appendingPathComponent("ABZU").path, "legendary's list has it, in its folder on the drive")
        check(EpicStore.recordedFolder(of: "QuailDLC", installedJSON: installed())?.path == base.appendingPathComponent("ABZU").path, "and the add-on whose files are there")
        check(EpicStore.recordedFolder(of: "QuailEmpty", installedJSON: installed()) == nil && EpicStore.recordedFolder(of: "QuailAbsent", installedJSON: installed()) == nil,
              "an add-on legendary stops on, and one it refuses, stay out – the game is taken all the same")
        let calls = ((try? String(contentsOf: config.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        check(calls.first == "import Quail \(base.appendingPathComponent("ABZU").path) --platform Windows --skip-dlcs" && calls.count == 4,
              "legendary was asked once for the game and once for each add-on: \(calls)")
        check(!store.isBusy, "legendary is free again afterwards")

        // A game with files missing: legendary records it with a warning – it's forgotten again, its files stay.
        let half = await store.adopt(find(heron))
        check(half == .incomplete, "a download that stopped part-way isn't taken for installed: \(half)")
        check(EpicStore.recordedFolder(of: "Heron", installedJSON: installed()) == nil, "legendary has forgotten it again")
        let after = ((try? String(contentsOf: config.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        check(after.last == "uninstall Heron -y --skip-uninstaller --keep-files", "forgotten with its files kept: \(after.last ?? "-")")

        // One legendary refuses (it ends with 0): its list decides, and its reason is passed on.
        let no = await store.adopt(find(refused))
        if case .refused(let reason) = no {
            check(reason.contains("Game executable could not be found"), "legendary's reason is passed on: \(reason)")
        } else {
            check(false, "what legendary's list doesn't have afterwards wasn't taken: \(no)")
        }

        finds = DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls(epic: EpicStore().knownInstalls()))
        check(finds.epic.map(\.appName) == ["Heron", "Stubborn"], "taken over: ABZÛ is nothing new any more, the other two still are: \(finds.epic.map(\.appName))")
        check(snapshot(drive) == before, "nothing on the drive changed")
    }
}
