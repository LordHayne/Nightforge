// FAILS on staging-032 c475580: the quit script (Engine.steamShutdownScript) only knows each Steam's first
// library. A Mac game in Steam for Mac's library on an external drive isn't "running" to it (Steam for
// Mac is told to quit under it), and a download into a library on a drive isn't "under way" (Steam ends and
// the download stops). Nightforge puts those libraries there itself: DriveLibrary.macSteam / windowsSteam.
// See "Befunde" in docs/TESTABDECKUNG.md: tests/BugQuitExternalLibrariesTest/run.sh
import Foundation

@main
struct BugQuitExternalLibrariesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        macGameOnADrive()
        windowsDownloadOnADrive()
        macDownloadOnADrive()
        print(failures == 0 ? "✓ Quit script knows every library" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Steam for Mac's library on the drive, as Nightforge makes it, listed in its libraryfolders.vdf.
    static func macLibrary(_ world: QuitWorld) -> URL {
        let library = world.root.appendingPathComponent("Volumes/T7/Nightforge Games/Steam for Mac", isDirectory: true)
        let vdf = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"\(world.macSteamapps.deletingLastPathComponent().path)\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"\(library.path)\"\n\t}\n}\n"
        world.write(vdf, to: world.macSteamapps.appendingPathComponent("libraryfolders.vdf"))
        world.write(vdf, to: world.macSteamapps.deletingLastPathComponent().appendingPathComponent("config/libraryfolders.vdf"))
        return library.appendingPathComponent("steamapps", isDirectory: true)
    }

    static func macGameOnADrive() {
        let world = QuitWorld()
        defer { world.cleanUp() }
        let library = macLibrary(world)
        world.processes([(100, library.path + "/common/Valheim/Valheim.app/Contents/MacOS/Valheim")])
        let result = world.run(limit: 0, macLibrary: world.macSteamapps.path, quitMac: true, macSteamRuns: true)
        check(!result.calls.contains { $0.hasPrefix("osascript") },
              "a Mac game running from a library on a drive keeps Steam for Mac: \(result.calls)")
    }

    static func macDownloadOnADrive() {
        let world = QuitWorld()
        defer { world.cleanUp() }
        let library = macLibrary(world)
        world.processes([(100, "/bin/zsh")])
        world.download(892970, flags: 1026, in: library)
        let result = world.run(limit: 0, macLibrary: world.macSteamapps.path, quitMac: true, macSteamRuns: true)
        check(!result.calls.contains { $0.hasPrefix("osascript") },
              "a download into a library on a drive keeps Steam for Mac: \(result.calls)")
    }

    static func windowsDownloadOnADrive() {
        let world = QuitWorld()
        defer { world.cleanUp() }
        let drive = world.root.appendingPathComponent("Volumes/T7/Nightforge Games", isDirectory: true)
        let windowsPath = "Z:" + drive.path.replacingOccurrences(of: "/", with: "\\\\")
        let vdf = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"\(windowsPath)\"\n\t}\n}\n"
        world.write(vdf, to: world.steamapps.appendingPathComponent("libraryfolders.vdf"))
        world.write(vdf, to: world.steamapps.deletingLastPathComponent().appendingPathComponent("config/libraryfolders.vdf"))
        world.processes([(100, QuitWorld.steam)])
        world.download(1245620, flags: 1026, in: drive.appendingPathComponent("steamapps", isDirectory: true))
        let result = world.run(limit: 0)
        check(!QuitWorld.endedSteam(result.calls), "a download into a library on a drive keeps Windows Steam: \(result.calls)")
    }
}
