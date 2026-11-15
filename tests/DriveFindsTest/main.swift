// Checks what a drive says it holds, from its own files, and what of it Nightforge would take over:
// tests/DriveFindsTest/run.sh
import Foundation

@main
struct DriveFindsTest {
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

    static func manifest(_ appID: Int, _ name: String, dir: String, size: Int64 = 1000, flags: Int = 4) -> String {
        """
        "AppState"
        {
        \t"appid"\t\t"\(appID)"
        \t"name"\t\t"\(name)"
        \t"StateFlags"\t\t"\(flags)"
        \t"installdir"\t\t"\(dir)"
        \t"SizeOnDisk"\t\t"\(size)"
        }
        """
    }

    static func gogInfo(_ id: String, root: String? = nil, name: String, build: String = "5000", languages: String = #""languages": ["de-DE"],"#,
                        task: Bool = true) -> String {
        """
        { "buildId": "\(build)", "clientId": "1", "gameId": "\(id)", "language": "German", \(languages)
          "name": "\(name)", \(task ? #""playTasks": [{ "isPrimary": true, "path": "pc\\game.exe", "type": "FileTask", "workingDir": "pc" }],"# : "")
          "rootGameId": "\(root ?? id)", "version": 1 }
        """
    }

    /// A drive as an earlier Nightforge left it.
    static func drive(_ root: URL) -> URL {
        let drive = root.appendingPathComponent("Volumes/Games", isDirectory: true)
        let games = DriveLibrary.root(on: drive)
        // Nightforge's Windows Steam: two games, one of them a download that stopped; and a file that isn't a manifest.
        write("\"libraryfolder\" { \"contentid\" \"77\" \"label\" \"\" }", games.appendingPathComponent("libraryfolder.vdf"))
        write(manifest(550, "Left 4 Dead 2", dir: "Left 4 Dead 2", size: 14_964_354_280), games.appendingPathComponent("steamapps/appmanifest_550.acf"))
        write(manifest(287700, "METAL GEAR SOLID V", dir: "MGS_TPP", flags: 1026), games.appendingPathComponent("steamapps/appmanifest_287700.acf"))
        write("not a manifest", games.appendingPathComponent("steamapps/appmanifest_12.acf"))
        write("x", games.appendingPathComponent("steamapps/common/Left 4 Dead 2/left4dead2.exe"))
        // Steam for Mac.
        write(manifest(892970, "Valheim", dir: "Valheim"), DriveLibrary.macSteam(on: drive).appendingPathComponent("steamapps/appmanifest_892970.acf"))
        // Epic: a game by its folder, one with an Epic launcher's note, one that's only Nightforge's settings, one nobody knows.
        let epic = DriveLibrary.epic(on: drive)
        write("x", epic.appendingPathComponent("ABZU/AbzuGame.exe"))
        write("x", epic.appendingPathComponent("ABZU/dxmt.conf"))
        write("x", epic.appendingPathComponent("AlanWake/AlanWake.exe"))
        write(#"{ "FormatVersion": 0, "AppName": "Heron", "CatalogItemId": "e6" }"#, epic.appendingPathComponent("AlanWake/.egstore/41.mancpn"))
        write("x", epic.appendingPathComponent("AlanWake/.egstore/41.manifest"))
        write("x", epic.appendingPathComponent("Leftover/dxmt.conf"))
        write("x", epic.appendingPathComponent("Leftover/nightforge-vulkan.conf"))
        write("x", epic.appendingPathComponent("Stranger/game.exe"))
        write("a file, not a folder", epic.appendingPathComponent("notes.txt"))
        // GOG: a Windows game with an add-on, a Mac app, a download gogdl hasn't finished, a folder whose file starts nothing.
        let gog = DriveLibrary.gog(on: drive)
        write(gogInfo("1816059595", name: "Mafia II"), gog.appendingPathComponent("Mafia II/goggame-1816059595.info"))
        write(gogInfo("1816059599", root: "1816059595", name: "Mafia II: Joe's Adventures", task: false),
              gog.appendingPathComponent("Mafia II/goggame-1816059599.info"))
        write("x", gog.appendingPathComponent("Mafia II/pc/game.exe"))
        write(gogInfo("1207658924", name: "Stardew", languages: ""), gog.appendingPathComponent("Stardew.app/Contents/Resources/goggame-1207658924.info"))
        write(gogInfo("1444444444", name: "Half There"), gog.appendingPathComponent("Half There/goggame-1444444444.info"))
        write("x", gog.appendingPathComponent("Half There/.gogdl-resume"))
        write(gogInfo("1555555555", name: "No Task", task: false), gog.appendingPathComponent("No Task/goggame-1555555555.info"))
        write(gogInfo("1666666666", name: "Wrong Name"), gog.appendingPathComponent("Wrong Name/goggame-1777777777.info"))
        // Battle.net's folder is the client's own: nothing reads it.
        write("x", games.appendingPathComponent("battle.net/Overwatch/Overwatch.exe"))
        return drive
    }

    static func snapshot(_ folder: URL) -> [String: String] {
        var result: [String: String] = [:]
        guard let files = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            result[file.path] = (try? String(contentsOf: file, encoding: .utf8)) ?? "?"
        }
        return result
    }

    static func main() {
        let root = fm.temporaryDirectory.appendingPathComponent("drive-finds-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let drive = drive(root)
        let before = snapshot(drive)

        // What the drive says, from its files alone.
        let contents = DriveContents.read(drive: drive)
        check(contents.windowsSteam.map(\.appID) == [550, 287700], "Windows Steam: both games, by appid: \(contents.windowsSteam)")
        check(contents.windowsSteam.first?.name == "Left 4 Dead 2" && contents.windowsSteam.first?.installDir == "Left 4 Dead 2"
              && contents.windowsSteam.first?.size == 14_964_354_280 && contents.windowsSteam.first?.complete == true,
              "a manifest's name, folder, size and that it's all there")
        check(contents.windowsSteam.last?.complete == false, "a download that stopped (StateFlags 1026) is said to be one")
        check(contents.macSteam.map(\.appID) == [892970], "Steam for Mac's library is read apart: \(contents.macSteam)")
        check(contents.epic.map(\.name) == ["ABZU", "AlanWake", "Stranger"],
              "Epic: the folders with a game's files – not one with only Nightforge's settings, not a file: \(contents.epic.map(\.name))")
        check(contents.epic.first { $0.name == "AlanWake" }?.appNames == ["Heron"], "an Epic launcher's note names the app")
        check(contents.epic.first { $0.name == "ABZU" }?.appNames == [], "legendary leaves no note: only the folder's name")
        check(contents.gog.map(\.id) == ["1816059595", "1207658924"],
              "GOG: games whose own file starts them – not an unfinished download, not a file without a task, not one named for another ID: \(contents.gog.map(\.title))")
        let mafia = contents.gog.first
        check(mafia?.title == "Mafia II" && mafia?.build == "5000" && mafia?.language == "de-DE" && mafia?.platform == .windows
              && mafia?.folder == "Mafia II" && mafia?.dlcs == ["1816059599"], "the game's name, build, language, folder and its add-on: \(String(describing: mafia))")
        let stardew = contents.gog.last
        check(stardew?.platform == .mac && stardew?.folder == "Stardew.app" && stardew?.language == "en-US",
              "a Mac version is its app; no language named: en-US: \(String(describing: stardew))")
        check(DriveContents.read(drive: root.appendingPathComponent("Volumes/Empty")).isEmpty, "a drive without Nightforge's folder holds nothing")

        // A manifest someone else wrote: its folder is one name in steamapps/common, never a path out of the library.
        for name in ["Left 4 Dead 2", "MGS_TPP", "Half-Life 2", "game.v2", "..hidden", "a..b", ""] {
            check(LibraryScanner.staysInLibrary(name), "a folder's name stays in the library: \"\(name)\"")
        }
        for name in ["..", ".", " .. ", "../../../Users/Shared/x", "a/b", "/Users/Shared", #"..\..\x"#, #"C:\Windows"#] {
            check(!LibraryScanner.staysInLibrary(name), "a path is no folder's name: \"\(name)\"")
        }
        let odd = root.appendingPathComponent("Volumes/Odd", isDirectory: true)
        let oddSteam = DriveLibrary.windowsSteam(on: odd).appendingPathComponent("steamapps", isDirectory: true)
        write(manifest(550, "Left 4 Dead 2", dir: "Left 4 Dead 2"), oddSteam.appendingPathComponent("appmanifest_550.acf"))
        write(manifest(11, "Out", dir: "../../../../../Users/Shared/out"), oddSteam.appendingPathComponent("appmanifest_11.acf"))
        write(manifest(12, "Up", dir: ".."), oddSteam.appendingPathComponent("appmanifest_12.acf"))
        check(DriveContents.read(drive: odd).windowsSteam.map(\.appID) == [550],
              "a manifest whose folder leads out of the library is no game: \(DriveContents.read(drive: odd).windowsSteam.map(\.name))")
        // … and the scan of a Steam's libraries leaves it out too: no game whose folder lies outside.
        let macRoot = root.appendingPathComponent("MacSteam", isDirectory: true)
        write(manifest(892970, "Valheim", dir: "Valheim"), macRoot.appendingPathComponent("steamapps/appmanifest_892970.acf"))
        write(manifest(13, "Out", dir: "../../../outside"), macRoot.appendingPathComponent("steamapps/appmanifest_13.acf"))
        let scanned = LibraryScanner.scanMac(root: macRoot)
        check(scanned.map(\.appID) == [892970], "the scan knows only the game whose folder is in the library: \(scanned.map(\.name))")
        check(scanned.allSatisfy { $0.installDir.standardizedFileURL.path.hasPrefix(macRoot.standardizedFileURL.path + "/") },
              "and every game's folder lies in its library")

        // A fresh Nightforge: no Steam set up, no store connected – everything waits, nothing is taken.
        let fresh = DriveFinds.look(drive: drive, contents: contents, known: KnownInstalls())
        check(fresh.isEmpty && fresh.count == 0, "nothing is taken over before its store is there")
        check(fresh.waiting.filter { $0.provider == .steam }.map(\.reason) == [.steamNotSetUp, .steamNotSetUp, .steamNotSetUp],
              "Steam's games wait for Steam: \(fresh.waiting.filter { $0.provider == .steam })")
        check(fresh.waiting.filter { $0.provider == .steam }.map(\.platform) == [.windows, .windows, .mac], "each Steam by itself")
        check(fresh.waiting.filter { $0.provider == .epic }.map(\.reason) == [.notConnected, .notConnected, .notConnected]
              && fresh.waiting.filter { $0.provider == .gog }.map(\.reason) == [.notConnected, .notConnected],
              "Epic's and GOG's wait for the sign-in")

        // Both Steams set up, their lists without the drive: the libraries come back whole.
        let macSteamapps = root.appendingPathComponent("Steam/steamapps")
        var known = KnownInstalls(windowsSteamLibraries: [root.appendingPathComponent("prefix/Steam/steamapps")], macSteamLibraries: [macSteamapps])
        var finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.windowsSteam.map(\.appID) == [550, 287700] && finds.macSteam.map(\.appID) == [892970],
              "a library not in the list comes back with all its games")
        check(!finds.waiting.contains { $0.provider == .steam }, "and nothing of Steam's waits")
        // The list knows the library (any spelling of its path): Steam looks after it itself.
        known.windowsSteamLibraries?.append(URL(fileURLWithPath: DriveLibrary.windowsSteam(on: drive).path.uppercased() + "/steamapps/"))
        known.macSteamLibraries = [macSteamapps, DriveLibrary.macSteam(on: drive).appendingPathComponent("steamapps")]
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.windowsSteam.isEmpty && finds.macSteam.isEmpty, "a library the list has is nothing new")

        // Epic.
        var abzu = EpicGame(appName: "Quail", title: "ABZÛ")
        abzu.folder = "ABZU"
        abzu.dlcs = [EpicDLC(appName: "QuailDLC", title: "Soundtrack Level")]
        var alan = EpicGame(appName: "Heron", title: "Alan Wake")
        alan.folder = "AlanWakeRemastered"  // not the folder's name: the launcher's note decides
        var other = EpicGame(appName: "Other", title: "Something else")
        other.folder = "SomethingElse"
        known.epic = KnownInstalls.Epic(signedIn: true, installed: [:], games: [abzu, alan, other], downloading: [])
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.epic.map(\.appName) == ["Quail", "Heron"], "Epic: by the folder Epic names, and by the launcher's note: \(finds.epic)")
        check(finds.epic.first?.folder.path == DriveLibrary.epic(on: drive).appendingPathComponent("ABZU").path
              && finds.epic.first?.title == "ABZÛ" && finds.epic.first?.addOns == ["QuailDLC"], "with its folder, title and add-ons")
        check(finds.waiting.filter { $0.provider == .epic } == [DriveFinds.Waiting(provider: .epic, platform: .windows, name: "Stranger", reason: .notOwned)],
              "a folder no game of the account goes by is left alone")
        known.epic?.signedIn = false
        check(DriveFinds.look(drive: drive, contents: contents, known: known).epic.isEmpty, "signed out: legendary can't take anything over")
        known.epic?.signedIn = true
        known.epic?.installed = ["Quail": DriveLibrary.epic(on: drive).appendingPathComponent("abzu/"), "Heron": URL(fileURLWithPath: "/elsewhere/AlanWake")]
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.epic.isEmpty, "known from this folder, or on the Mac already: nothing to take")
        check(!finds.waiting.contains { $0.name == "ABZU" || $0.name == "AlanWake" }, "and neither waits")
        known.epic?.installed = [:]
        known.epic?.downloading = ["Quail"]
        check(DriveFinds.look(drive: drive, contents: contents, known: known).epic.map(\.appName) == ["Heron"], "a download in line keeps its folder")
        // Two games Epic sends to the same folder name: no guess.
        var twin = EpicGame(appName: "QuailDemo", title: "ABZÛ Demo")
        twin.folder = "abzu"
        known.epic = KnownInstalls.Epic(games: [abzu, twin])
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.epic.isEmpty && finds.waiting.contains { $0.name == "ABZU" && $0.reason == .notOwned }, "two games for one folder: none is guessed")

        // GOG.
        known.gog = KnownInstalls.GOG(installed: [:], owned: ["1816059595"], downloading: [])
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.gog.map(\.id) == ["1816059595"], "GOG: the game the account owns")
        check(finds.waiting.filter { $0.provider == .gog } == [DriveFinds.Waiting(provider: .gog, platform: .mac, name: "Stardew", reason: .notOwned)],
              "one it doesn't own is left alone")
        known.gog?.installed = ["1816059595": URL(fileURLWithPath: "/Users/me/GOG Games/Mafia II")]
        check(DriveFinds.look(drive: drive, contents: contents, known: known).gog.isEmpty, "installed already (wherever): nothing to take")
        known.gog = KnownInstalls.GOG(owned: ["1816059595", "1207658924"], downloading: ["1207658924"])
        finds = DriveFinds.look(drive: drive, contents: contents, known: known)
        check(finds.gog.map(\.id) == ["1816059595"] && !finds.waiting.contains { $0.provider == .gog }, "a download in line keeps its folder")
        check(finds.count == finds.windowsSteam.count + finds.macSteam.count + finds.epic.count + finds.gog.count && finds.count == 1,
              "the count is what would come back now: \(finds.count)")

        check(snapshot(drive) == before, "reading and sorting changed nothing on the drive")

        if failures == 0 {
            print("✓ What a drive holds, and what of it is new, is read right")
        } else {
            print("\(failures) check(s) failed")
            exit(1)
        }
    }
}
