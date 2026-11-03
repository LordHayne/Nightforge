// Checks UpdateState: when an installed game has an update waiting, how big it is, and when Steam
// is applying it (from the manifest's StateFlags and bytes); and LibraryScanner reading a made-up
// bottle: its manifests, extra libraries, unplugged drives and playtimes: tests/UpdateStateTest/run.sh
import Foundation

@main
struct UpdateStateTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        // As on this Mac: Palworld fully installed, the bytes of its last download both equal.
        let installed = UpdateState(flags: 4, toDownload: 31_755_444_704, downloaded: 31_755_444_704, targetBuild: "25246127", build: "25246127")
        check(installed.pending == nil && !installed.isRunning, "fully installed: nothing waits")
        // Steamworks Common Redist here: flags 6, size not known yet.
        let unknown = UpdateState(flags: 6, toDownload: 0, downloaded: 0, targetBuild: "24098430", build: "24098430")
        check(unknown.pending == 0, "update required, size not known yet: 0")
        let sized = UpdateState(flags: 6, toDownload: 1_200_000_000, downloaded: 200_000_000)
        check(sized.pending == 1_000_000_000, "what's left of the update: \(sized.pending ?? -1)")
        let newBuild = UpdateState(flags: 4, toDownload: 0, downloaded: 0, targetBuild: "26220470", build: "26220464")
        check(newBuild.pending == 0, "heading for another build counts as waiting")
        check(UpdateState(flags: 4, toDownload: 0, downloaded: 0, targetBuild: "0", build: "26220464").pending == nil, "build 0 means none")
        let running = UpdateState(flags: 1026, toDownload: 1_000, downloaded: 250)
        check(running.isRunning && running.fraction == 0.25, "update started: running, a quarter done")
        check(UpdateState(flags: 4 | 1_048_576, toDownload: 0, downloaded: 0).isRunning && UpdateState(flags: 4 | 1_048_576, toDownload: 0, downloaded: 0).fraction == nil,
              "downloading without sizes: running, no percentage")
        check(UpdateState(flags: 1024, toDownload: 100, downloaded: 100).fraction == 0.99, "never shows 100 % before it's done")
        // OxyRail's update on 31.10. (content_log: "download 0/5809679168, … stage 0/7151561606"): Steam
        // writes BytesDownloaded only at the end, and "Update & Play" stood at 0 % for 4.5 minutes.
        let oxy = UpdateState(flags: 1030, toDownload: 5_809_679_168, downloaded: 0, toStage: 7_151_561_606, staged: 0)
        check(oxy.isRunning && oxy.fraction == 0, "the update starts: 0 %")
        check(UpdateState(flags: 1030, toDownload: 5_809_679_168, downloaded: 0, toStage: 7_151_561_606, staged: 3_575_780_803).fraction == 0.5,
              "half of it unpacked: 50 %, whatever BytesDownloaded says")
        check(UpdateState(flags: 1030, toDownload: 1000, downloaded: 600, toStage: 2000, staged: 400).fraction == 0.6,
              "whichever is further along")
        check(UpdateState(flags: 1030, toDownload: 0, downloaded: 0, toStage: 2000, staged: 2000).fraction == 0.99,
              "all unpacked, not moved into the game yet: still not 100 %")
        progress()

        // The app's own update: an app opened from its download runs translocated and can't be replaced.
        check(Updater.isTranslocated("/private/var/folders/ab/c_d1/T/AppTranslocation/6F1D2A3B-0000-4000-8000-0123456789AB/d/Nightforge.app"),
              "a translocated app is recognised")
        check(!Updater.isTranslocated("/Applications/Nightforge.app") && !Updater.isTranslocated("/Users/a/Applications/Nightforge.app"),
              "an app in Applications isn't")
        check(!Updater.runsFromProtectedPlace(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)), "the home folder is no protected place")
        // A release that raises the macOS it needs doesn't replace a copy that couldn't open it.
        func mac(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
        }
        check(Updater.needsNewerMac(minimum: "26.0", running: mac(15, 6)) && Updater.needsNewerMac(minimum: "26.0", running: mac(14, 8, 1)),
              "macOS 14 and 15 stay on the version they have")
        check(!Updater.needsNewerMac(minimum: "26.0", running: mac(26)) && !Updater.needsNewerMac(minimum: "26.0", running: mac(27, 1)),
              "macOS 26 and 27 take it")
        check(Updater.needsNewerMac(minimum: "26.1", running: mac(26)) && !Updater.needsNewerMac(minimum: "26.1", running: mac(26, 1))
              && Updater.needsNewerMac(minimum: "26.1.1", running: mac(26, 1)) && !Updater.needsNewerMac(minimum: "14", running: mac(14)),
              "minor and patch versions count; a bare 14 is 14.0")
        check(!Updater.needsNewerMac(minimum: nil, running: mac(14)), "no minimum named, nothing in the way")
        check(Updater.Failure.needsNewerMac(required: "26.0").errorDescription?.contains("26 ") == true
              && Updater.Failure.needsNewerMac(required: "26.0").errorDescription?.contains("26.0") == false, "the message says 26, not 26.0")

        do { try scanner() } catch { check(false, "the made-up bottle: \(error)") }
        try? FileManager.default.removeItem(at: root)

        print(failures == 0 ? "✓ UpdateState" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// "Update & Play" as the Play button follows it, a look a second: never back, and its speed.
    static func progress() {
        let start = Date(timeIntervalSince1970: 1_793_473_618)  // 31.10. 19:06:58
        func look(_ staged: Double) -> UpdateState {
            UpdateState(flags: 1030, toDownload: 1_000_000_000, downloaded: 0, toStage: 2_000_000_000, staged: staged)
        }
        var shown = UpdateProgress()
        check(shown.fraction == nil && shown.speed == nil, "nothing seen yet: \"Updating …\"")
        shown.add(UpdateState(flags: 1030, toDownload: 0, downloaded: 0), at: start)
        check(shown.fraction == nil, "sizes not known yet: still no percentage")
        shown.add(look(200_000_000), at: start)
        check(shown.fraction == 0.1 && shown.speed == nil, "the first look: 10 %, no speed yet")
        shown.add(look(400_000_000), at: start.addingTimeInterval(10))
        check(shown.fraction == 0.2, "10 s later: 20 %")
        // A tenth of the 1 GB download in 10 s: 10 MB/s, 80 s for the rest – as a download's line says it.
        var rate = DownloadRate()
        rate.add(bytes: 100_000_000, at: start)
        rate.add(bytes: 200_000_000, at: start.addingTimeInterval(10))
        check(shown.speed != nil && shown.speed == rate.label(total: 1_000_000_000),
              "the speed and the time left: \(shown.speed ?? "none")")
        // At the end Steam moves the unpacked files into the game: their folder empties.
        shown.add(look(100_000_000), at: start.addingTimeInterval(11))
        check(shown.fraction == 0.2, "the folder emptying doesn't take it back: \(shown.fraction ?? -1)")
        check(shown.speed != nil, "nor its speed")
        check(LaunchPhase.steamUpdateHint(speed: "10 MB/s").hasPrefix("10 MB/s"), "the speed under the Play button")
    }

    // MARK: A made-up bottle, as LibraryScanner reads it

    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nightforge-update-state-test-\(UUID().uuidString)", isDirectory: true)

    static func write(_ text: String, _ path: String, in base: URL) throws {
        let file = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    /// An appmanifest as Steam writes it; `fields` add to or replace the usual ones.
    static func manifest(_ appID: Int, _ name: String, _ fields: [String: String] = [:]) -> String {
        let all = ["appid": String(appID), "name": name, "installdir": name, "StateFlags": "4"].merging(fields) { $1 }
        return "\"AppState\"\n{\n" + all.sorted { $0.key < $1.key }.map { "\t\"\($0.key)\"\t\t\"\($0.value)\"\n" }.joined() + "}\n"
    }

    static func usage(_ apps: [Int: (lastPlayed: Int, playtime: Int?)]) -> String {
        let entries = apps.map { id, use in
            "\"\(id)\" { \"LastPlayed\" \"\(use.lastPlayed)\" " + (use.playtime.map { "\"Playtime\" \"\($0)\" " } ?? "") + "}"
        }
        return #""UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "# + entries.joined(separator: " ") + " } } } } }"
    }

    static func scanner() throws {
        let fm = FileManager.default
        let bottle = Bottle(name: "Main", url: root.appendingPathComponent("Bottles/Main", isDirectory: true))
        let steam = bottle.url.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let steamapps = steam.appendingPathComponent("steamapps", isDirectory: true)
        try write("", "steam.exe", in: steam)

        try write(manifest(1623730, "Palworld", ["SizeOnDisk": "31755444704", "buildid": "1", "TargetBuildID": "2",
                                                 "BytesToDownload": "500", "BytesDownloaded": "100"]),
                  "appmanifest_1623730.acf", in: steamapps)
        try write(manifest(228980, "Steamworks Common Redistributables"), "appmanifest_228980.acf", in: steamapps)
        try write(manifest(1493711, "Steam Linux Runtime 3.0 (sniper)"), "appmanifest_1493711.acf", in: steamapps)
        try write(manifest(100, "DirectX Redistributable Pack"), "appmanifest_100.acf", in: steamapps)
        try write(manifest(101, "Proton 9.0"), "appmanifest_101.acf", in: steamapps)
        try write(manifest(2000, "Anno 2070", ["StateFlags": "1026", "BytesToDownload": "1000", "BytesDownloaded": "250"]),
                  "appmanifest_2000.acf", in: steamapps)
        try write(manifest(3000, "Staged Game", ["StateFlags": "1026", "BytesToStage": "40000"]), "appmanifest_3000.acf", in: steamapps)
        try write(String(repeating: "x", count: 10_000), "downloading/3000/data/one.pak", in: steamapps)
        try write(String(repeating: "x", count: 10_000), "downloading/3000/two.pak", in: steamapps)
        try write(manifest(4000, "Waiting Game", ["StateFlags": "1026"]), "appmanifest_4000.acf", in: steamapps)
        try write(manifest(5000, "Full Disk", ["StateFlags": "1026", "UpdateResult": "12", "BytesToDownload": "2000", "BytesToStage": "3000"]),
                  "appmanifest_5000.acf", in: steamapps)
        try write(#""AppState" { "appid" "6000" "installdir" "Nameless" }"#, "appmanifest_6000.acf", in: steamapps)
        try write(#""AppState" { "appid" "6001" "name" "" "installdir" "Empty" }"#, "appmanifest_6001.acf", in: steamapps)
        try write(#""AppState" { "appid" "abc" "name" "Bad ID" "installdir" "Bad" }"#, "appmanifest_6002.acf", in: steamapps)
        try write(manifest(7000, "Half Written"), "appmanifest_7000.acf.tmp", in: steamapps)

        // Extra libraries: through drive letters Wine links, the old one-line format, a Mac path,
        // a drive letter that isn't there and the Steam folder itself again.
        let driveD = root.appendingPathComponent("DriveD", isDirectory: true)
        let driveE = root.appendingPathComponent("DriveE", isDirectory: true)
        let macLibrary = root.appendingPathComponent("MacLibrary", isDirectory: true)
        try fm.createDirectory(at: bottle.url.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: bottle.url.appendingPathComponent("dosdevices/d:"), withDestinationURL: driveD)
        try fm.createSymbolicLink(at: bottle.url.appendingPathComponent("dosdevices/e:"), withDestinationURL: driveE)
        try write("""
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" }
            "1" { "path" "D:\\\\SteamLibrary" "apps" { "6100" "1" } }
            "2" "E:\\\\Old"
            "3" { "path" "\(macLibrary.path)" }
            "4" { "path" "X:\\\\Gone" }
            "5" { "path" "nonsense" }
        }
        """, "libraryfolders.vdf", in: steamapps)
        try write(manifest(6100, "Hades"), "SteamLibrary/steamapps/appmanifest_6100.acf", in: driveD)
        try write(manifest(1623730, "Palworld (second copy)"), "SteamLibrary/steamapps/appmanifest_1623730.acf", in: driveD)
        try write(manifest(6200, "Old Game"), "Old/steamapps/appmanifest_6200.acf", in: driveE)
        try write(manifest(6300, "Mac Library Game"), "steamapps/appmanifest_6300.acf", in: macLibrary)

        // Two accounts' playtimes: the most recent start counts, 0 means never.
        try write(usage([1623730: (1_700_000_000, 120), 6100: (1_600_000_000, nil), 2000: (0, 3)]),
                  "userdata/111/config/localconfig.vdf", in: steam)
        try write(usage([1623730: (1_500_000_000, 5), 6200: (1_650_000_000, 7)]), "userdata/222/config/localconfig.vdf", in: steam)
        try write("not a config", "userdata/333/config/localconfig.vdf", in: steam)

        // A second Steam in the same bottle: what the first one has isn't listed twice.
        let other = bottle.url.appendingPathComponent("drive_c/Program Files/Steam", isDirectory: true)
        try write("", "steam.exe", in: other)
        try write(manifest(8000, "Second Steam Game"), "steamapps/appmanifest_8000.acf", in: other)
        try write(manifest(1623730, "Palworld (other Steam)"), "steamapps/appmanifest_1623730.acf", in: other)

        // Steam's own library first; the others in no set order (the file's keys come as a dictionary).
        let libraries = LibraryScanner.libraryFolders(steamRoot: steam, bottle: bottle).map(\.path)
        check(libraries.first == steamapps.path && libraries.count == 4
              && Set(libraries) == [steamapps.path, driveD.appendingPathComponent("SteamLibrary/steamapps").resolvingSymlinksInPath().path,
                                    driveE.appendingPathComponent("Old/steamapps").resolvingSymlinksInPath().path,
                                    macLibrary.appendingPathComponent("steamapps").path],
              "four libraries, each once: \(libraries)")

        let games = LibraryScanner.scan(bottle: bottle)
        let byID = Dictionary(games.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
        check(Set(byID.keys) == [1623730, 2000, 3000, 4000, 5000, 6100, 6200, 6300, 8000] && games.count == 9,
              "games without redistributables, runtimes, Proton, broken or half-written manifests: \(byID.keys.sorted())")
        let palworld = byID[1623730]
        check(palworld?.name == "Palworld" && palworld?.install == .installed && palworld?.sizeOnDisk == 31_755_444_704,
              "the first library's copy, installed, with its size")
        check(palworld?.pendingUpdate == 400, "an update to another build, what's left of it: \(palworld?.pendingUpdate ?? -1)")
        check(palworld?.installDir == steamapps.appendingPathComponent("common/Palworld", isDirectory: true)
              && palworld?.installDirName == "Palworld" && palworld?.steamExeWindowsPath == #"C:\Program Files (x86)\Steam\steam.exe"#,
              "where it lies and which Steam starts it")
        check(palworld?.lastPlayed == Date(timeIntervalSince1970: 1_700_000_000) && palworld?.playtimeMinutes == 120,
              "the most recent account's playtime")
        check(byID[6200]?.lastPlayed == Date(timeIntervalSince1970: 1_650_000_000) && byID[6200]?.playtimeMinutes == 7,
              "the other account's game")
        check(byID[6100]?.lastPlayed != nil && byID[6100]?.playtimeMinutes == nil, "played, no playtime noted")
        check(byID[2000]?.lastPlayed == nil && byID[2000]?.playtimeMinutes == 3, "LastPlayed 0 is never")
        check(byID[2000]?.install == .downloading(0.25) && byID[2000]?.sizeOnDisk == 1000 && byID[2000]?.pendingUpdate == nil,
              "a download: how far, and what it comes to")
        let staged = LibraryScanner.folderSize(steamapps.appendingPathComponent("downloading/3000"))
        check(staged >= 20_000, "unpacked files counted, in subfolders too: \(staged)")
        check(byID[3000]?.install == .downloading(min(Double(staged) / 40_000, 0.99)), "unpacked so far: \(String(describing: byID[3000]?.install))")
        check(byID[4000]?.install == .downloading(nil), "size not known yet")
        check(byID[5000]?.downloadNeedsSpace == 3000 && byID[5000]?.install == .downloading(0), "Steam's full disk: the space it needs")
        check(byID[6100]?.installDir.path.hasSuffix("DriveD/SteamLibrary/steamapps/common/Hades") == true, "a game on drive D:")
        check(byID[8000]?.steamExeWindowsPath == #"C:\Program Files\Steam\steam.exe"#, "the second Steam's own game")
        check(LibraryScanner.folderSize(root.appendingPathComponent("missing")) == 0, "a folder that isn't there takes no space")

        // What a game's manifest says while Nightforge waits for Steam.
        if let palworld {
            check(LibraryScanner.updateState(of: palworld) == UpdateState(flags: 4, toDownload: 500, downloaded: 100, targetBuild: "2", build: "1"),
                  "read from the game's own manifest")
            try write(manifest(1623730, "Palworld", ["StateFlags": "1030", "BytesToDownload": "800", "BytesDownloaded": "200"]),
                      "appmanifest_1623730.acf", in: steamapps)
            let running = LibraryScanner.updateState(of: palworld)
            check(running?.isRunning == true && running?.fraction == 0.25, "an update under way: \(String(describing: running))")
        }
        let gone = Game(appID: 9, name: "Gone", bottle: bottle, steamRoot: steam, steamExeWindowsPath: "",
                        installDir: steamapps.appendingPathComponent("common/Gone"), sizeOnDisk: 0)
        check(LibraryScanner.updateState(of: gone) == nil, "no manifest, nothing known")

        // OxyRail's update (31.10.), in a Steam of its own: Steam stages it in downloading/<appid>,
        // its files set to full size up front ("preallocated 476 files"), which Wine leaves sparse.
        let oxySteam = root.appendingPathComponent("OxySteam/steamapps", isDirectory: true)
        let oxyRail = Game(appID: 3907790, name: "OxyRail", bottle: bottle, steamRoot: oxySteam.deletingLastPathComponent(),
                           steamExeWindowsPath: "", installDir: oxySteam.appendingPathComponent("common/Oxygen Train"), sizeOnDisk: 0)
        try write(manifest(3907790, "OxyRail", ["installdir": "Oxygen Train", "StateFlags": "1030", "BytesToDownload": "80000000",
                                                "BytesDownloaded": "0", "BytesToStage": "100000000", "BytesStaged": "0"]),
                  "appmanifest_3907790.acf", in: oxySteam)
        check(LibraryScanner.updateState(of: oxyRail)?.fraction == 0, "the update starts, nothing unpacked: 0 %")
        let pak = oxySteam.appendingPathComponent("downloading/3907790/Oxygen Train_Data/data.unity3d")
        try fm.createDirectory(at: pak.deletingLastPathComponent(), withIntermediateDirectories: true)
        check(fm.createFile(atPath: pak.path, contents: nil), "the staged file")
        let handle = try FileHandle(forWritingTo: pak)
        try handle.truncate(atOffset: 100_000_000)  // as Wine sets a file's end: no space taken
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(repeating: 0x4E, count: 25_000_000))
        try handle.close()
        let quarter = LibraryScanner.updateState(of: oxyRail)?.fraction ?? -1
        check(quarter > 0.2 && quarter < 0.3, "a quarter written of a file set to its full size: about 25 %, not 99 % (\(quarter))")
        var oxyOnMac = oxyRail
        oxyOnMac.platform = .mac
        check(LibraryScanner.updateState(of: oxyOnMac)?.fraction == 0, "Steam for Mac reserves it all: not measured")
        try write(manifest(3907790, "OxyRail", ["installdir": "Oxygen Train", "StateFlags": "6", "BytesToDownload": "80000000",
                                                "BytesToStage": "100000000"]),
                  "appmanifest_3907790.acf", in: oxySteam)
        check(LibraryScanner.updateState(of: oxyRail)?.staged == 0, "an update waiting, not running: nothing measured")

        // Several bottles; a folder that is a bottle itself; one without Steam; a file among them.
        try fm.createDirectory(at: root.appendingPathComponent("Bottles/No Steam/drive_c"), withIntermediateDirectories: true)
        try write("", "Bottles/notes.txt", in: root)
        let all = LibraryScanner.scan(bottlesRoot: root.appendingPathComponent("Bottles"))
        check(all.map(\.appID) == [1623730, 6200, 6100, 6300, 8000, 2000, 5000, 3000, 4000],
              "installed by last start, then by name; then downloads by name: \(all.map(\.name))")
        check(LibraryScanner.scan(bottlesRoot: bottle.url).count == 9, "a chosen folder that is a bottle itself")
        check(LibraryScanner.scan(bottlesRoot: root.appendingPathComponent("Bottles/No Steam")).isEmpty, "a bottle without Steam")
        check(LibraryScanner.scan(bottlesRoot: root.appendingPathComponent("nowhere"), extraBottles: [bottle]).count == 9,
              "extra bottles, even with no bottles folder")

        // Windows paths in a bottle.
        check(LibraryScanner.macPath(forWindowsPath: #"C:\Games\x"#, in: bottle) == bottle.url.appendingPathComponent("drive_c/Games/x"),
              "C: without a link is drive_c")
        check(LibraryScanner.macPath(forWindowsPath: "d:/SteamLibrary", in: bottle)?.path == driveD.resolvingSymlinksInPath().path + "/SteamLibrary",
              "a linked drive, either slash, any case")
        check(LibraryScanner.macPath(forWindowsPath: #"Q:\x"#, in: bottle) == nil && LibraryScanner.macPath(forWindowsPath: "Games", in: bottle) == nil,
              "no such drive, no drive at all")

        // Libraries on drives that aren't plugged in.
        let volumes = root.appendingPathComponent("Volumes", isDirectory: true)
        try fm.createDirectory(at: volumes.appendingPathComponent("T7"), withIntermediateDirectories: true)
        func missing(_ path: String) -> String? { LibraryScanner.missingVolume(forLibrary: path, in: bottle, volumes: volumes) }
        check(missing("/Volumes/T7/SteamLibrary") == nil, "a plugged-in drive isn't missing")
        check(missing("/Volumes/Gone/SteamLibrary") == "Gone", "an unplugged drive, by its name")
        check(missing("/Users/me/SteamLibrary") == nil && missing("/Volumes") == nil, "not on a drive")
        try fm.createSymbolicLink(atPath: bottle.url.appendingPathComponent("dosdevices/f:").path, withDestinationPath: "/Volumes/Gone2")
        try fm.createSymbolicLink(atPath: bottle.url.appendingPathComponent("dosdevices/g:").path, withDestinationPath: "Volumes/T7")
        check(missing(#"F:\SteamLibrary"#) == "Gone2", "through a drive letter Wine linked to it")
        check(missing(#"G:\SteamLibrary"#) == nil, "a link without its leading slash, to a drive that's there")
        check(missing(#"H:\SteamLibrary"#) == nil && missing("SteamLibrary") == nil, "no link, no drive letter")

        let unplugged = "nightforge-test-\(UUID().uuidString)"
        let lonely = root.appendingPathComponent("LonelySteam", isDirectory: true)
        try write("""
        "libraryfolders"
        {
            "0" { "path" "\(lonely.path)" "apps" { "1" "1" } }
            "1" { "path" "/Volumes/\(unplugged)/SteamLibrary" "apps" { "6400" "123" "6401" "1" "notes" "x" } }
            "2" { "path" "/Volumes/\(unplugged)/Empty" }
        }
        """, "steamapps/libraryfolders.vdf", in: lonely)
        let drives = LibraryScanner.missingDrives(steamRoot: lonely, bottle: bottle)
        check(drives == [6400: unplugged, 6401: unplugged], "games on an unplugged drive, by app ID: \(drives)")
        check(LibraryScanner.missingDrives(steamRoot: root.appendingPathComponent("nowhere"), bottle: bottle).isEmpty, "no library list")
        var notHere = gone
        notHere.install = .notInstalled
        let hades = Game(appID: 6400, name: "Hades", bottle: bottle, steamRoot: steam, steamExeWindowsPath: "", installDir: steam, sizeOnDisk: 0)
        var hadesOwned = hades
        hadesOwned.install = .notInstalled
        let marked = LibraryScanner.markMissingDrives([hades, hadesOwned, notHere], drives: drives)
        check(marked.map(\.missingDrive) == [nil, unplugged, nil], "only owned games not on the Mac wait for their drive")
        check(LibraryScanner.markMissingDrives([hadesOwned], drives: [:]) == [hadesOwned], "no drive missing, nothing changes")

        // Anti-cheat that stops a Windows version (Steam offers no start without it here).
        let battlEye = AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: "g1")
        let onlineOnly = AntiCheatBlock(antiCheat: ["Easy Anti-Cheat"], geforceNow: nil, onlineOnly: true)
        let windows = byID[1623730]!
        var macVersion = windows
        macVersion.platform = .mac
        var storeHit = byID[6100]!
        storeHit.install = .inStore
        var online = byID[6200]!
        online.onlineOnly = true
        let blocked = LibraryScanner.markAntiCheat([windows, macVersion, storeHit, online, byID[6300]!],
                                                   blocks: [1623730: battlEye, 6100: battlEye, 6200: onlineOnly, 6300: onlineOnly])
        check(blocked.map(\.antiCheatBlock) == [battlEye, nil, nil, onlineOnly, nil],
              "the Windows version is stopped, not the Mac one nor a store hit; online-only anti-cheat only stops online-only games")
        // A game that doesn't start yet is marked the same way, but not for good: it can be tried, and streams when GeForce Now has it.
        let later = AntiCheatBlock(antiCheat: [], geforceNow: "g2", notYet: "Not yet.")
        let held = LibraryScanner.markAntiCheat([windows, macVersion, online], blocks: [1623730: later, 6200: later])
        check(held.map(\.antiCheatBlock) == [later, nil, later], "not yet stops the Windows version, even when it isn't online only")
        check(held[0].playsInCloud && held[0].antiCheatBlock?.notYet != nil && blocked[0].antiCheatBlock?.notYet == nil,
              "a game that doesn't start yet streams from GeForce Now when it can, and says it isn't ruled out for good")
    }
}
