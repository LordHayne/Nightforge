// Checks how games on a drive that isn't plugged in are found: tests/ExternalDriveTest/run.sh
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

    static func main() {
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

        print(failures == 0 ? "✓ ExternalDrive" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
