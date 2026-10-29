// Checks games on external drives: libraries there, moving games and drives that aren't plugged in.
// tests/ExternalDriveTest/run.sh – with NIGHTFORGE_TEST_DRIVE=/Volumes/<drive> it also moves a game
// to that drive and back, in a folder "nightforge-session-test" it deletes again; with
// NIGHTFORGE_TEST_IMAGES=1 it checks exFAT and FAT32 on small disk images.
import Foundation

@main
struct ExternalDriveTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("external-drive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let bottle = Bottle(name: "Test", url: prefix)
        let volumes = root.appendingPathComponent("Volumes", isDirectory: true)
        try? fm.createDirectory(at: volumes.appendingPathComponent("Plugged"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: prefix.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/z:").path, withDestinationPath: "/")
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/e:").path, withDestinationPath: "/Volumes/Gone Letter")

        // Where a library is and whether its drive is there.
        func missing(_ path: String) -> String? { LibraryScanner.missingVolume(forLibrary: path, in: bottle, volumes: volumes) }
        check(missing(#"Z:\Volumes\T7\Nightforge Games"#) == "T7", "through Z:, the drive's name")
        check(missing(#"E:\SteamLibrary"#) == "Gone Letter", "through a drive letter Wine linked to the drive")
        check(missing("/Volumes/Samsung T7/SteamLibrary") == "Samsung T7", "Steam for Mac's own paths")
        check(missing(#"Z:\Volumes\Plugged\SteamLibrary"#) == nil, "a drive that's there isn't missing")
        check(missing(#"C:\Program Files (x86)\Steam"#) == nil && missing("/Users/me/Steam") == nil, "folders on the Mac itself are never a missing drive")
        check(missing(#"F:\Games"#) == nil, "a letter Wine doesn't know: nothing to say")

        // Steam's list of each library's games.
        let steam = root.appendingPathComponent("Steam", isDirectory: true)
        try? fm.createDirectory(at: steam.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        let vdf = #"""
        "libraryfolders"
        {
            "0" { "path" "C:\\Program Files (x86)\\Steam" "apps" { "550" "14964354280" } }
            "1" { "path" "Z:\\Volumes\\T7\\Nightforge Games" "apps" { "1091500" "70000000000" "1245620" "60000000000" } }
            "2" { "path" "Z:\\Volumes\\Plugged\\SteamLibrary" "apps" { "570" "30000000000" } }
        }
        """#
        try? vdf.write(to: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        // missingDrives looks in the real /Volumes, where neither T7 nor Plugged is: both count as unplugged.
        let drives = LibraryScanner.missingDrives(steamRoot: steam, bottle: bottle)
        check(drives[1091500] == "T7" && drives[1245620] == "T7", "games on T7: \(drives)")
        check(drives[550] == nil, "games on the Mac aren't on a missing drive")

        // Only games not on this Mac get the mark.
        func game(_ id: Int, _ install: InstallState) -> Game {
            var game = Game(appID: id, name: "Game \(id)", bottle: bottle, steamRoot: steam, steamExeWindowsPath: "",
                            installDir: steam, sizeOnDisk: 0)
            game.install = install
            return game
        }
        let marked = LibraryScanner.markMissingDrives([game(1091500, .notInstalled), game(1245620, .installed), game(42, .notInstalled)],
                                                      drives: drives)
        check(marked[0].missingDrive == "T7", "not here, on T7: \"Connect T7 to play\"")
        check(marked[1].missingDrive == nil, "installed here too: plays from here")
        check(marked[2].missingDrive == nil, "on no drive at all: Download")

        checkLibraryList(root)
        checkPaths(bottle)
        checkDriveCheck()
        await checkSteamMove(root)
        await checkRollback(root)
        await checkEpicMove(root)
        checkChoices()
        if let drive = ProcessInfo.processInfo.environment["NIGHTFORGE_TEST_DRIVE"] { await checkRealDrive(URL(fileURLWithPath: drive)) }
        if ProcessInfo.processInfo.environment["NIGHTFORGE_TEST_IMAGES"] == "1" { await checkImages(root) }

        print(failures == 0 ? "✓ ExternalDrive" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Fixtures

    /// A Windows Steam in a prefix (Z: is the Mac, C: the prefix's drive_c) with one game, and a
    /// folder standing in for a drive.
    struct SteamFixture {
        let bottle: Bottle
        let steamRoot: URL
        let drive: URL
        var steamapps: URL { steamRoot.appendingPathComponent("steamapps", isDirectory: true) }
        var library: URL { DriveLibrary.windowsSteam(on: drive) }
        var driveSteamapps: URL { library.appendingPathComponent("steamapps", isDirectory: true) }
        var game: URL { steamapps.appendingPathComponent("common/Left 4 Dead 2", isDirectory: true) }
    }

    static let libraryList = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n"
        + "\t\t\"label\"\t\t\"\"\n\t\t\"contentid\"\t\t\"8773078355922679615\"\n\t\t\"totalsize\"\t\t\"0\"\n"
        + "\t\t\"update_clean_bytes_tally\"\t\t\"161233550912\"\n\t\t\"time_last_update_verified\"\t\t\"1793031931\"\n"
        + "\t\t\"apps\"\n\t\t{\n\t\t\t\"550\"\t\t\"3000\"\n\t\t\t\"228980\"\t\t\"128606066\"\n\t\t}\n\t}\n}\n"

    static func steamFixture(_ root: URL, _ name: String, drive: URL? = nil) -> SteamFixture {
        let fm = FileManager.default
        let prefix = root.appendingPathComponent(name, isDirectory: true)
        let steamRoot = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let fixture = SteamFixture(bottle: Bottle(name: name, url: prefix, isBuiltIn: true), steamRoot: steamRoot,
                                   drive: drive ?? root.appendingPathComponent("\(name)-drive/T7", isDirectory: true))
        for folder in ["dosdevices", "drive_c/Program Files (x86)/Steam/config", "drive_c/Program Files (x86)/Steam/steamapps"] {
            try? fm.createDirectory(at: prefix.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try? fm.createDirectory(at: fixture.drive, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/z:").path, withDestinationPath: "/")
        try? fm.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/c:").path, withDestinationPath: "../drive_c")
        fm.createFile(atPath: steamRoot.appendingPathComponent("steam.exe").path, contents: Data())
        for file in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] {
            try? libraryList.write(to: steamRoot.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let manifest = "\"AppState\"\n{\n\t\"appid\"\t\t\"550\"\n\t\"name\"\t\t\"Left 4 Dead 2\"\n\t\"StateFlags\"\t\t\"4\"\n"
            + "\t\"installdir\"\t\t\"Left 4 Dead 2\"\n\t\"SizeOnDisk\"\t\t\"3000\"\n}\n"
        try? manifest.write(to: fixture.steamapps.appendingPathComponent("appmanifest_550.acf"), atomically: true, encoding: .utf8)
        makeGame(fixture.game)
        let workshop = fixture.steamapps.appendingPathComponent("workshop/content/550/123", isDirectory: true)
        try? fm.createDirectory(at: workshop, withIntermediateDirectories: true)
        fm.createFile(atPath: workshop.appendingPathComponent("mod.vpk").path, contents: Data(repeating: 7, count: 500))
        try? "\"AppWorkshop\" { \"appid\" \"550\" }".write(to: fixture.steamapps.appendingPathComponent("workshop/appworkshop_550.acf"),
                                                           atomically: true, encoding: .utf8)
        let shaders = fixture.steamapps.appendingPathComponent("shadercache/550", isDirectory: true)
        try? fm.createDirectory(at: shaders, withIntermediateDirectories: true)
        fm.createFile(atPath: shaders.appendingPathComponent("cache.bin").path, contents: Data(repeating: 3, count: 300))
        return fixture
    }

    /// A game folder with what games have: big and small files, a hidden one, a program that must
    /// stay executable and a link (Mac games' frameworks are full of them).
    static func makeGame(_ folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder.appendingPathComponent("bin/Frameworks/Engine.framework/Versions/A"), withIntermediateDirectories: true)
        fm.createFile(atPath: folder.appendingPathComponent("game.pak").path, contents: Data((0..<2_000_000).map { UInt8($0 % 251) }))
        fm.createFile(atPath: folder.appendingPathComponent("bin/run").path, contents: Data("#!/bin/sh\necho ok\n".utf8),
                      attributes: [.posixPermissions: 0o755])
        fm.createFile(atPath: folder.appendingPathComponent(".egstore").path, contents: Data("store".utf8))
        try? fm.createSymbolicLink(atPath: folder.appendingPathComponent("bin/Frameworks/Engine.framework/Versions/Current").path,
                                   withDestinationPath: "A")
    }

    static func gameIsWhole(_ folder: URL) -> Bool {
        let fm = FileManager.default
        let pak = fm.contents(atPath: folder.appendingPathComponent("game.pak").path)
        let mode = (try? fm.attributesOfItem(atPath: folder.appendingPathComponent("bin/run").path)[.posixPermissions] as? Int) ?? 0
        let link = try? fm.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("bin/Frameworks/Engine.framework/Versions/Current").path)
        return pak == Data((0..<2_000_000).map { UInt8($0 % 251) }) && mode & 0o111 != 0 && link == "A"
            && fm.fileExists(atPath: folder.appendingPathComponent(".egstore").path)
    }

    /// Which library of the list holds an app.
    static func libraryHolding(_ appID: Int, _ fixture: SteamFixture, file: String = "config/libraryfolders.vdf") -> String? {
        let nodes = VDF.nodes((try? String(contentsOf: fixture.steamRoot.appendingPathComponent(file), encoding: .utf8)) ?? "") ?? []
        let list = nodes.first?.children ?? []
        let holding = list.filter { $0["apps"]?[String(appID)] != nil }.map(\.key)
        return holding.count == 1 ? holding[0] : holding.isEmpty ? nil : "several: \(holding)"
    }

    // MARK: - libraryfolders.vdf

    static func checkLibraryList(_ root: URL) {
        // Read and written back as Steam writes it.
        let nodes = VDF.nodes(libraryList)
        check(nodes != nil && VDF.text(nodes ?? []) == libraryList, "libraryfolders.vdf comes back as Steam wrote it")
        check(nodes?.first?["0"]?["path"]?.string == #"C:\Program Files (x86)\Steam"#, "a path's backslashes are read as one")
        check(VDF.nodes("\"a\" { \"b\" \"c\" } }") == nil && VDF.nodes("\"a\" {") == nil, "a broken list isn't taken as one")
        check(VDF.nodes(#""a" "x\"y""#)?.first?.string == "x\"y" && VDF.text(VDF.nodes(#""a" "x\"y""#) ?? []) == "\"a\"\t\t\"x\\\"y\"\n",
              "quotes in a value stay quotes")

        // A library on a drive: its folder and Steam's mark, and an entry in both lists.
        let fixture = steamFixture(root, "list")
        let path = DriveLibrary.windowsPath(of: fixture.library)
        func ensure() throws {
            try SteamLibraries.ensure(library: fixture.library, path: path, steamRoot: fixture.steamRoot,
                                      rootPath: #"C:\Program Files (x86)\Steam"#, bottle: fixture.bottle)
        }
        do { try ensure() } catch { check(false, "library added: \(error)") }
        let mark = VDF.nodes((try? String(contentsOf: fixture.library.appendingPathComponent("libraryfolder.vdf"), encoding: .utf8)) ?? "")
        let contentID = mark?.first?["contentid"]?.string
        check(contentID.map { !$0.isEmpty && Int64($0) != nil } == true, "Steam's mark with a number: \(String(describing: contentID))")
        check(FileManager.default.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("common").path), "steamapps/common is there")
        for file in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] {
            let list = VDF.nodes((try? String(contentsOf: fixture.steamRoot.appendingPathComponent(file), encoding: .utf8)) ?? "")?.first
            check(list?["1"]?["path"]?.string == path && list?["1"]?["contentid"]?.string == contentID,
                  "\(file): library 1 is the drive, with its number")
            check(list?["0"]?["contentid"]?.string == "8773078355922679615" && list?["0"]?["apps"]?["550"]?.string == "3000",
                  "\(file): Steam's own library is left as it was")
        }
        do { try ensure() } catch { check(false, "added twice: \(error)") }
        let twice = VDF.nodes((try? String(contentsOf: fixture.steamRoot.appendingPathComponent("config/libraryfolders.vdf"), encoding: .utf8)) ?? "")
        check(twice?.first?.children.count == 2, "a library already there isn't added again")
        let folders = LibraryScanner.libraryFolders(steamRoot: fixture.steamRoot, bottle: fixture.bottle).map { $0.resolvingSymlinksInPath().path }
        check(folders.contains(fixture.driveSteamapps.resolvingSymlinksInPath().path), "the scan looks in the new library: \(folders)")

        // A drive used with an earlier Nightforge: its games come back with the library.
        let again = steamFixture(root, "again", drive: fixture.drive)
        try? FileManager.default.copyItem(at: fixture.steamapps.appendingPathComponent("appmanifest_550.acf"),
                                          to: fixture.driveSteamapps.appendingPathComponent("appmanifest_550.acf"))
        do {
            try SteamLibraries.ensure(library: again.library, path: path, steamRoot: again.steamRoot,
                                      rootPath: #"C:\Program Files (x86)\Steam"#, bottle: again.bottle)
        } catch { check(false, "library added again: \(error)") }
        let back = VDF.nodes((try? String(contentsOf: again.steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8)) ?? "")?.first
        check(back?["1"]?["contentid"]?.string == contentID && back?["1"]?["apps"]?["550"]?.string == "3000",
              "same number, and the games on it listed")

        // A Steam without a list yet: its own folder comes first.
        let empty = root.appendingPathComponent("empty-steam", isDirectory: true)
        try? FileManager.default.createDirectory(at: empty.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        let macLibrary = root.appendingPathComponent("empty-drive/Nightforge Games/Steam for Mac", isDirectory: true)
        do {
            try SteamLibraries.ensure(library: macLibrary, path: macLibrary.path, steamRoot: empty, rootPath: empty.path,
                                      bottle: Bottle(name: "Steam for Mac", url: empty))
        } catch { check(false, "list made: \(error)") }
        let made = VDF.nodes((try? String(contentsOf: empty.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8)) ?? "")?.first
        check(made?["0"]?["path"]?.string == empty.path && made?["1"]?["path"]?.string == macLibrary.path, "new list: Steam's folder, then the drive")

        // A list that can't be read is left alone.
        let broken = steamFixture(root, "broken")
        try? "\"libraryfolders\" { \"0\" {".write(to: broken.steamRoot.appendingPathComponent("config/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        do {
            try SteamLibraries.ensure(library: broken.library, path: DriveLibrary.windowsPath(of: broken.library), steamRoot: broken.steamRoot,
                                      rootPath: "", bottle: broken.bottle)
            check(false, "an unreadable list isn't written over")
        } catch {
            check((try? String(contentsOf: broken.steamRoot.appendingPathComponent("config/libraryfolders.vdf"), encoding: .utf8)) == "\"libraryfolders\" { \"0\" {",
                  "the unreadable list stays as it was")
        }
    }

    // MARK: - Paths

    static func checkPaths(_ bottle: Bottle) {
        let drive = URL(fileURLWithPath: "/Volumes/Spiele test", isDirectory: true)
        check(DriveLibrary.windowsPath(of: DriveLibrary.windowsSteam(on: drive)) == #"Z:\Volumes\Spiele test\Nightforge Games"#,
              "Windows Steam's path: through Z:, no drive letter")
        check(DriveLibrary.macSteam(on: drive).path == "/Volumes/Spiele test/Nightforge Games/Steam for Mac", "Steam for Mac's library")
        check(DriveLibrary.epic(on: drive).path == "/Volumes/Spiele test/Nightforge Games/Epic Games", "Epic's folder")
        check(LibraryScanner.macPath(forWindowsPath: #"Z:\Volumes\Spiele test\Nightforge Games"#, in: bottle)?.path
              == "/Volumes/Spiele test/Nightforge Games", "and back to the Mac's path")
        check(DriveLibrary.drive(of: URL(fileURLWithPath: "/Volumes/Spiele test/Nightforge Games/steamapps/common/Game"))?.path == "/Volumes/Spiele test",
              "the drive a game is on")
        check(DriveLibrary.drive(of: URL(fileURLWithPath: "/Users/me/Library/Application Support/Steam")) == nil
              && DriveLibrary.drive(of: URL(fileURLWithPath: "/Volumes")) == nil, "a game on the Mac is on no drive")
        // A running game shows the same marks on the drive as on the Mac.
        var epic = Game(gameID: .epic("Fortnite"), name: "Game", bottle: bottle, steamRoot: drive, steamExeWindowsPath: "",
                        installDir: DriveLibrary.epic(on: drive).appendingPathComponent("Game"), sizeOnDisk: 0)
        epic.installDirName = "Game"
        check(Engine.windowsPath(of: epic.installDir.appendingPathComponent("Game.exe")).lowercased().contains(epic.windowsFolderMarker.lowercased()),
              "an Epic game on the drive is seen running")
    }

    // MARK: - Formats

    static func checkDriveCheck() {
        check(DriveCheck(format: "apfs", readOnly: false) == .fine && DriveCheck(format: "hfs", readOnly: false) == .fine, "APFS and Mac OS Extended")
        check(DriveCheck(format: "exfat", readOnly: false) == .caution, "exFAT: a calm warning")
        check(DriveCheck(format: "msdos", readOnly: false) == .fat && !DriveCheck.fat.allowed, "FAT32: refused (4 GB per file)")
        check(DriveCheck(format: "ntfs", readOnly: true) == .readOnly && !DriveCheck.readOnly.allowed, "NTFS (read only): refused")
        check(DriveCheck.fine.note("T7") == nil && DriveCheck.caution.note("T7") != nil, "only exFAT and the refused ones say something")
        check(ExternalDrive.at(FileManager.default.temporaryDirectory) == nil, "a folder that isn't a drive")
        check(ExternalDrive.at(URL(fileURLWithPath: "/")) == nil, "the Mac's own disk isn't an external drive")
    }

    static func checkChoices() {
        func drive(_ name: String, _ format: String, free: Int64, readOnly: Bool = false) -> ExternalDrive {
            ExternalDrive(name: name, url: URL(fileURLWithPath: "/Volumes/\(name)"), format: format, readOnly: readOnly, free: free, total: free * 2)
        }
        let gb: Int64 = 1 << 30
        let drives = [drive("Full", "apfs", free: 5 * gb), drive("Stick", "msdos", free: 100 * gb),
                      drive("T7", "apfs", free: 500 * gb), drive("Cam", "exfat", free: 50 * gb)]
        let choices = DriveChoice.options(drives, size: 20 * gb)
        check(choices.map(\.drive.name) == ["T7", "Cam", "Full", "Stick"], "the ones it fits on first: \(choices.map(\.drive.name))")
        check(choices.map(\.usable) == [true, true, false, false], "too full, FAT32: offered but not usable")
        check(choices[0].needed == 20 * gb + SpaceCheck.margin, "with Steam's room besides")
        check(!DriveChoice.options(drives, size: 1, except: URL(fileURLWithPath: "/Volumes/T7")).contains { $0.drive.name == "T7" },
              "not the drive it's on")
    }

    // MARK: - Moving

    static func checkSteamMove(_ root: URL) async {
        let fixture = steamFixture(root, "move")
        let fm = FileManager.default
        do {
            try SteamLibraries.ensure(library: fixture.library, path: DriveLibrary.windowsPath(of: fixture.library), steamRoot: fixture.steamRoot,
                                      rootPath: #"C:\Program Files (x86)\Steam"#, bottle: fixture.bottle)
            let progress = CopyProgress()
            let left = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.steamapps, to: fixture.driveSteamapps,
                                                         steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: progress) { false }
            check(left.isEmpty, "nothing left behind: \(left)")
            check(progress.fraction == 1 && progress.total > 2_000_000, "progress reaches the end: \(progress.copied) of \(progress.total)")
        } catch { check(false, "moved to the drive: \(error)") }
        let moved = fixture.driveSteamapps.appendingPathComponent("common/Left 4 Dead 2", isDirectory: true)
        check(gameIsWhole(moved), "the game on the drive is whole: files, program, link, hidden file")
        check(!fm.fileExists(atPath: fixture.game.path) && !fm.fileExists(atPath: fixture.steamapps.appendingPathComponent("appmanifest_550.acf").path),
              "the original is gone, manifest too")
        check(fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("appmanifest_550.acf").path)
              && fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("workshop/content/550/123/mod.vpk").path)
              && fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("workshop/appworkshop_550.acf").path)
              && fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("shadercache/550/cache.bin").path),
              "manifest, workshop items and shader cache came along")
        check(!(try! fm.contentsOfDirectory(atPath: fixture.driveSteamapps.appendingPathComponent("common").path)).contains { $0.hasPrefix(".nightforge") },
              "no half copy left")
        check(libraryHolding(550, fixture) == "1" && libraryHolding(550, fixture, file: "steamapps/libraryfolders.vdf") == "1",
              "the list says it's on the drive: \(String(describing: libraryHolding(550, fixture)))")
        // Steam's files are all the scan needs to find it there.
        let found = LibraryScanner.scan(bottle: fixture.bottle).first { $0.appID == 550 }
        check(found?.isInstalled == true && found?.installDir.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path,
              "found in the new library: \(String(describing: found?.installDir.path))")

        // Unplugged: the list still says what's on it.
        let config = fixture.steamRoot.appendingPathComponent("config/libraryfolders.vdf")
        let saved = try? Data(contentsOf: config)
        let unplugged = String(decoding: saved ?? Data(), as: UTF8.self)
            .replacingOccurrences(of: DriveLibrary.windowsPath(of: fixture.library).replacingOccurrences(of: "\\", with: "\\\\"),
                                  with: #"Z:\\Volumes\\Nightforge Test Gone\\Nightforge Games"#)
        try? unplugged.write(to: fixture.steamapps.appendingPathComponent("libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let missing = LibraryScanner.missingDrives(steamRoot: fixture.steamRoot, bottle: fixture.bottle)
        check(missing[550] == "Nightforge Test Gone", "a moved game on an unplugged drive: \(missing)")
        try? saved?.write(to: fixture.steamapps.appendingPathComponent("libraryfolders.vdf"))

        // And back to the Mac.
        do {
            let left = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.driveSteamapps, to: fixture.steamapps,
                                                         steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: CopyProgress()) { false }
            check(left.isEmpty, "nothing left on the drive: \(left)")
        } catch { check(false, "moved back: \(error)") }
        check(gameIsWhole(fixture.game) && !fm.fileExists(atPath: moved.path), "back on the Mac, whole")
        check(libraryHolding(550, fixture) == "0", "the list says it's on the Mac again")
        let home = LibraryScanner.scan(bottle: fixture.bottle).first { $0.appID == 550 }
        check(home?.installDir.resolvingSymlinksInPath().path == fixture.game.resolvingSymlinksInPath().path, "found on the Mac again")
    }

    static func checkRollback(_ root: URL) async {
        let fm = FileManager.default
        let fixture = steamFixture(root, "rollback")
        try? SteamLibraries.ensure(library: fixture.library, path: DriveLibrary.windowsPath(of: fixture.library), steamRoot: fixture.steamRoot,
                                   rootPath: #"C:\Program Files (x86)\Steam"#, bottle: fixture.bottle)
        let lists = SteamLibraries.files(steamRoot: fixture.steamRoot).map { try? Data(contentsOf: $0) }
        let target = fixture.driveSteamapps.appendingPathComponent("common/Left 4 Dead 2", isDirectory: true)
        func untouched(_ what: String) {
            check(gameIsWhole(fixture.game) && fm.fileExists(atPath: fixture.steamapps.appendingPathComponent("appmanifest_550.acf").path)
                  && fm.fileExists(atPath: fixture.steamapps.appendingPathComponent("workshop/appworkshop_550.acf").path),
                  "\(what): the original is as it was")
            check(!fm.fileExists(atPath: target.path) && !fm.fileExists(atPath: GameMover.staging(target).path)
                  && !fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("appmanifest_550.acf").path)
                  && !fm.fileExists(atPath: fixture.driveSteamapps.appendingPathComponent("workshop/content/550").path),
                  "\(what): no copy left on the drive")
            check(SteamLibraries.files(steamRoot: fixture.steamRoot).map { try? Data(contentsOf: $0) } == lists, "\(what): the lists are as they were")
        }
        func attempt(_ what: String, progress: CopyProgress = CopyProgress(), steamRunning: @escaping () -> Bool = { false },
                     expect: (Error) -> Bool) async {
            do {
                _ = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.steamapps, to: fixture.driveSteamapps,
                                                      steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: progress, steamRunning: steamRunning)
                check(false, "\(what): the move should have stopped")
            } catch {
                check(expect(error), "\(what): \(error)")
            }
            untouched(what)
        }

        // Steam started while the files were copied: it would write its own list over the change.
        await attempt("Steam started meanwhile", steamRunning: { true }) { if case DriveError.steamStarted = $0 { return true } else { return false } }
        // Cancelled.
        let cancelled = CopyProgress()
        cancelled.cancel()
        await attempt("cancelled", progress: cancelled) { if case DriveError.cancelled = $0 { return true } else { return false } }
        // The drive refuses to be written to (full, unplugged, locked).
        let common = fixture.driveSteamapps.appendingPathComponent("common")
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: common.path)
        await attempt("drive not writable") { if case DriveError.copyFailed(let reason) = $0 { return reason == FolderCopy.reason(EACCES) } else { return false } }
        check(FolderCopy.reason(EFBIG) != FolderCopy.reason(ENOSPC) && FolderCopy.reason(ENOSPC) == L10n.t("The drive is full."),
              "a full drive and a file too big for FAT32 say so in words")
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: common.path)
        // Something of the same name is there already.
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        fm.createFile(atPath: target.appendingPathComponent("save.dat").path, contents: Data("mine".utf8))
        do {
            _ = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.steamapps, to: fixture.driveSteamapps,
                                                  steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: CopyProgress()) { false }
            check(false, "a folder already there stops the move")
        } catch {
            check(fm.contents(atPath: target.appendingPathComponent("save.dat").path) == Data("mine".utf8) && gameIsWhole(fixture.game),
                  "the folder there and the original are both untouched: \(error)")
        }
        try? fm.removeItem(at: target)
        // An empty folder left behind isn't in the way.
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        do {
            _ = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.steamapps, to: fixture.driveSteamapps,
                                                  steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: CopyProgress()) { false }
            check(gameIsWhole(target), "moved over an empty folder")
        } catch { check(false, "an empty folder isn't in the way: \(error)") }

        // The check finds a copy that differs.
        let source = root.appendingPathComponent("compare/a", isDirectory: true), copy = root.appendingPathComponent("compare/b", isDirectory: true)
        makeGame(source)
        try? FolderCopy.copy(source, to: copy, progress: CopyProgress())
        check(FolderCopy.difference(source, copy) == nil, "a whole copy matches")
        fm.createFile(atPath: copy.appendingPathComponent("._game.pak").path, contents: Data(count: 4096))
        check(FolderCopy.difference(source, copy) == nil, "exFAT's extra files don't count")
        try? Data(count: 10).write(to: copy.appendingPathComponent("game.pak"))
        check(FolderCopy.difference(source, copy) == "game.pak", "a short file is found")
        try? fm.removeItem(at: copy.appendingPathComponent("bin/Frameworks/Engine.framework/Versions/Current"))
        try? fm.createSymbolicLink(atPath: copy.appendingPathComponent("bin/Frameworks/Engine.framework/Versions/Current").path, withDestinationPath: "B")
        try? FolderCopy.copy(source.appendingPathComponent("game.pak"), to: root.appendingPathComponent("compare/pak"), progress: CopyProgress())
        try? fm.removeItem(at: copy.appendingPathComponent("game.pak"))
        try? fm.moveItem(at: root.appendingPathComponent("compare/pak"), to: copy.appendingPathComponent("game.pak"))
        check(FolderCopy.difference(source, copy) == "bin/Frameworks/Engine.framework/Versions/Current", "a link pointing elsewhere is found")
    }

    static func checkEpicMove(_ root: URL) async {
        let fm = FileManager.default
        let macBase = root.appendingPathComponent("epic/Mac/Epic Games", isDirectory: true)
        let driveBase = DriveLibrary.epic(on: root.appendingPathComponent("epic/T7", isDirectory: true))
        let folder = macBase.appendingPathComponent("Game", isDirectory: true)
        makeGame(folder)
        let installed = try! JSONSerialization.data(withJSONObject: [
            "Game1": ["install_path": folder.path, "is_dlc": false],
            "DLC1": ["install_path": folder.path, "is_dlc": true],
            "Other": ["install_path": macBase.appendingPathComponent("Other").path],
        ])
        check(GameMover.epicEntries(inFolder: folder, installedJSON: installed) == ["DLC1", "Game1"], "the game and its add-on in that folder")

        // legendary refuses the add-on: the game's note is taken back, and the copy goes.
        var calls: [[String]] = []
        do {
            _ = try await GameMover.moveEpicGame(folder: folder, to: driveBase, installedJSON: installed, progress: CopyProgress()) { arguments in
                calls.append(arguments)
                if arguments[1] == "Game1" && arguments[2] == driveBase.path { throw EpicError.failed("locked") }
            }
            check(false, "a refused note stops the move")
        } catch {
            check(calls == [["move", "DLC1", driveBase.path, "--skip-move"], ["move", "Game1", driveBase.path, "--skip-move"],
                            ["move", "DLC1", macBase.path, "--skip-move"]], "notes taken back: \(calls)")
            check(gameIsWhole(folder) && !fm.fileExists(atPath: driveBase.appendingPathComponent("Game").path), "the original stays, the copy goes")
        }

        calls = []
        do {
            let left = try await GameMover.moveEpicGame(folder: folder, to: driveBase, installedJSON: installed, progress: CopyProgress()) { calls.append($0) }
            check(left.isEmpty, "nothing left on the Mac")
        } catch { check(false, "Epic game moved: \(error)") }
        check(calls == [["move", "DLC1", driveBase.path, "--skip-move"], ["move", "Game1", driveBase.path, "--skip-move"]],
              "legendary notes the game and its add-on: \(calls)")
        check(gameIsWhole(driveBase.appendingPathComponent("Game")) && !fm.fileExists(atPath: folder.path), "the Epic game is on the drive")
    }

    // MARK: - Real drives (only when asked)

    /// A move to a plugged-in drive and back, in "nightforge-session-test" on it, which goes again.
    static func checkRealDrive(_ volume: URL) async {
        let fm = FileManager.default
        guard let drive = ExternalDrive.at(volume) else {
            check(false, "\(volume.path) is a plugged-in drive")
            return
        }
        print("  \(drive.name): \(drive.format), \(Format.bytes(drive.free)) free, \(drive.check)")
        check(drive.check.allowed, "games can go on \(drive.name)")
        check(ExternalDrive.connected().contains { $0.url.path == volume.path }, "listed with the drives plugged in")
        let area = volume.appendingPathComponent("nightforge-session-test", isDirectory: true)
        guard !fm.fileExists(atPath: area.path) else {
            check(false, "\(area.path) is already there – left from an earlier run? Not touched.")
            return
        }
        defer { try? fm.removeItem(at: area) }
        let work = fm.temporaryDirectory.appendingPathComponent("real-drive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let fixture = steamFixture(work, "real", drive: area)
        do {
            try SteamLibraries.ensure(library: fixture.library, path: DriveLibrary.windowsPath(of: fixture.library), steamRoot: fixture.steamRoot,
                                      rootPath: #"C:\Program Files (x86)\Steam"#, bottle: fixture.bottle)
            let start = Date()
            _ = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.steamapps, to: fixture.driveSteamapps,
                                                  steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: CopyProgress()) { false }
            check(gameIsWhole(fixture.driveSteamapps.appendingPathComponent("common/Left 4 Dead 2")), "whole on \(drive.name)")
            check(LibraryScanner.scan(bottle: fixture.bottle).first { $0.appID == 550 }?.installDir.path.hasPrefix(area.path) == true,
                  "found on \(drive.name)")
            _ = try await GameMover.moveSteamGame(appID: 550, installDirName: "Left 4 Dead 2", from: fixture.driveSteamapps, to: fixture.steamapps,
                                                  steamRoot: fixture.steamRoot, bottle: fixture.bottle, progress: CopyProgress()) { false }
            check(gameIsWhole(fixture.game) && libraryHolding(550, fixture) == "0", "back from \(drive.name)")
            print("  there and back in \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        } catch { check(false, "move on \(drive.name): \(error)") }
    }

    /// exFAT and FAT32 on small disk images: what they're taken for, and a game copied onto exFAT.
    static func checkImages(_ root: URL) async {
        let mounts = root.appendingPathComponent("mounts", isDirectory: true)
        func run(_ arguments: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        for (format, name, expected) in [("ExFAT", "exfat", DriveCheck.caution), ("MS-DOS FAT32", "fat", DriveCheck.fat)] {
            let image = root.appendingPathComponent("\(name).dmg"), mount = mounts.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            guard run(["create", "-size", "40m", "-fs", format, "-volname", "NF\(name)", "-layout", "MBRSPUD", image.path]),
                  run(["attach", "-nobrowse", "-mountpoint", mount.path, image.path])
            else {
                check(false, "\(format) image")
                continue
            }
            defer { _ = run(["detach", mount.path, "-force"]) }
            let drive = ExternalDrive.at(mount, volumes: mounts)
            check(drive?.check == expected, "\(format) is taken for \(expected): \(String(describing: drive?.format))")
            let game = root.appendingPathComponent("image-game-\(name)", isDirectory: true)
            makeGame(game)
            do {
                try FolderCopy.copy(game, to: mount.appendingPathComponent("Game"), progress: CopyProgress())
                check(FolderCopy.difference(game, mount.appendingPathComponent("Game")) == nil, "a game copied onto \(format) checks out")
            } catch { check(false, "copy onto \(format): \(error)") }
        }
    }
}
