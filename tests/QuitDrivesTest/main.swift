// Checks the quit script (Engine.steamShutdownScript) where the player's folders aren't the usual ones: a
// game on an external drive still counts as running, folders with spaces and umlauts work everywhere,
// and a damaged manifest neither stops it nor keeps it waiting: tests/QuitDrivesTest/run.sh
import Foundation

@main
struct QuitDrivesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        windowsGamesOnADrive()
        namesWithSpacesAndUmlauts()
        damagedManifests()
        print(failures == 0 ? "✓ Quit script on drives and odd folders" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A game that runs keeps Steam: from whichever store's folder on the drive, and however Wine cases its path.
    static func windowsGamesOnADrive() {
        let games = [
            (#"Z:\Volumes\T7 Blau\Nightforge Games\steamapps\common\Elden Ring\Game\eldenring.exe"#, "Steam's library on a drive"),
            (#"Z:\Volumes\T7\Nightforge Games\Epic Games\Control\Control_DX11.exe"#, "Epic's folder on a drive"),
            (#"Z:\Volumes\T7\Nightforge Games\GOG Games\Mafia II\mafia2.exe"#, "GOG's folder on a drive"),
            (#"Z:\VOLUMES\T7\NIGHTFORGE GAMES\STEAMAPPS\COMMON\ABZU\AbzuGame.exe"#, "a path in capitals"),
        ]
        for (command, what) in games {
            let world = QuitWorld()
            defer { world.cleanUp() }
            world.processes([(100, QuitWorld.steam), (200, command)])
            let result = world.run(limit: 0)
            check(!QuitWorld.endedSteam(result.calls) && !result.timedOut, "\(what): the running game keeps Steam: \(result.calls)")
            check(result.status == 0, "\(what): ends cleanly at its limit: \(result.status)")
        }
    }

    static func namesWithSpacesAndUmlauts() {
        let odd = "quit-Jörg Müller's Spiele (Test) \(UUID().uuidString)"
        do {
            let world = QuitWorld(folder: odd, app: "Mäine Programme/Night Forge.app")
            defer { world.cleanUp() }
            world.processes([(100, QuitWorld.steam)])
            let result = world.run()
            check(QuitWorld.endedSteam(result.calls) && result.status == 0,
                  "no game, folders with spaces and umlauts: Steam and wineserver end: \(result.calls), \(result.status)")
        }
        do {
            let world = QuitWorld(folder: odd + "-opened", app: "Mäine Programme/Night Forge.app")
            defer { world.cleanUp() }
            world.processes([(100, QuitWorld.steam), (300, world.app + "/Contents/MacOS/Nightforge -psn_0_1")])
            let result = world.run()
            check(!QuitWorld.endedSteam(result.calls), "Nightforge open again from such a folder: Steam stays: \(result.calls)")
        }
        do {
            let world = QuitWorld(folder: odd + "-mac")
            defer { world.cleanUp() }
            world.processes([(100, world.macSteamapps.path + "/common/Sid Meier's Civilization VI/Civ6.app/Contents/MacOS/Civ6")])
            let result = world.run(limit: 0, macLibrary: world.macSteamapps.path, quitMac: true, macSteamRuns: true)
            check(!result.calls.contains { $0.hasPrefix("osascript") }, "a Mac game in Steam for Mac's own library keeps Steam for Mac: \(result.calls)")
        }
        do {
            let world = QuitWorld(folder: odd + "-download")
            defer { world.cleanUp() }
            world.processes([(100, QuitWorld.steam)])
            world.download(4000, flags: 1026, in: world.steamapps)
            let result = world.run(limit: 0)
            check(!QuitWorld.endedSteam(result.calls) && !result.timedOut, "a download in a prefix with spaces is found: \(result.calls)")
        }
    }

    /// What power loss leaves of a manifest: a download can't be told from it, so it doesn't count.
    static func damagedManifests() {
        let damaged: [(String, Data)] = [
            ("empty", Data()),
            ("binary", Data((0..<512).map { UInt8($0 % 251) })),
            ("without its flags", Data("\"AppState\"\n{\n\t\"appid\"\t\t\"4000\"\n}\n".utf8)),
            ("flags that aren't a number", Data("\"AppState\"\n{\n\t\"StateFlags\"\t\t\"abc\"\n}\n".utf8)),
        ]
        for (what, bytes) in damaged {
            let world = QuitWorld()
            defer { world.cleanUp() }
            world.processes([(100, QuitWorld.steam)])
            world.download(4000, flags: nil, in: world.steamapps)
            try? bytes.write(to: world.steamapps.appendingPathComponent("appmanifest_4000.acf"))
            let result = world.run()
            check(QuitWorld.endedSteam(result.calls) && !result.timedOut && result.status == 0, "a manifest \(what) holds nothing up: \(result.calls)")
        }
        // A number too long for bash wraps around, and it must still be read as a number.
        let world = QuitWorld()
        defer { world.cleanUp() }
        world.processes([(100, QuitWorld.steam)])
        world.download(4000, flags: nil, in: world.steamapps)
        world.write("\"AppState\"\n{\n\t\"StateFlags\"\t\t\"99999999999999999999999\"\n}\n", to: world.steamapps.appendingPathComponent("appmanifest_4000.acf"))
        let result = world.run(limit: 0)
        check(result.status == 0 && !result.timedOut, "a flag number too long for bash doesn't break the script: \(result.calls), \(result.status)")
    }
}
