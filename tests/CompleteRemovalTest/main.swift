// Checks what "Remove Nightforge completely" deletes, keeps and copies first – on fake folders:
// tests/CompleteRemovalTest/run.sh
import Foundation

@main
struct CompleteRemovalTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ url: URL, _ text: String = "data") {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("removal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Library", isDirectory: true)
        var places = CompleteRemoval.Places()
        places.support = library.appendingPathComponent("Application Support/Nightforge", isDirectory: true)
        places.caches = library.appendingPathComponent("Caches/Nightforge", isDirectory: true)
        places.userCache = root.appendingPathComponent("C", isDirectory: true)
        places.library = library
        places.shortcuts = root.appendingPathComponent("Applications/Nightforge Games", isDirectory: true)
        places.documents = root.appendingPathComponent("Documents", isDirectory: true)
        places.bundleID = "io.github.lordhayne.nightforge"

        // Nightforge's things …
        let user = places.prefix.appendingPathComponent("drive_c/users/crossover", isDirectory: true)
        let game = places.steam.appendingPathComponent("steamapps/common/Left 4 Dead 2/left4dead2.exe")
        write(game)
        write(places.support.appendingPathComponent("Components/wine/bin/wine"))
        write(places.caches.appendingPathComponent("Artwork/550.jpg"))
        write(places.shortcuts.appendingPathComponent("Valheim.app/Contents/Info.plist"))
        write(library.appendingPathComponent("HTTPStorages/io.github.lordhayne.nightforge/httpstorages.sqlite"))
        write(places.userCache!.appendingPathComponent("io.github.lordhayne.nightforge.game/com.apple.metal/x.data"))
        write(places.userCache!.appendingPathComponent("org.winehq.wine/com.apple.metal/y.data"))
        // … saves in the Windows environment …
        write(user.appendingPathComponent("AppData/Roaming/Hades/Profile1.sav"), "hades save")
        write(user.appendingPathComponent("AppData/Local/Pal/Saved/SaveGames/0/World.sav"), "palworld world")
        write(user.appendingPathComponent("Documents/My Games/Skyrim/Saves/quick.ess"), "skyrim save")
        write(places.steam.appendingPathComponent("userdata/158043902/550/remote/cfg/config.cfg"), "l4d2 config")
        // … and caches beside them that aren't saves.
        write(user.appendingPathComponent("AppData/Local/Temp/huge.tmp"))
        write(user.appendingPathComponent("AppData/Local/Steam/htmlcache/index"))
        write(user.appendingPathComponent("AppData/Local/UnrealEngine/ShaderCache/a.bin"))
        write(user.appendingPathComponent("AppData/Local/D3DSCache/b.bin"))
        write(places.steam.appendingPathComponent("userdata/158043902/7/remote/sharedconfig.vdf"))
        write(places.prefix.appendingPathComponent("drive_c/users/Public/Documents/x.txt"))
        // What isn't Nightforge's.
        let steamForMac = library.appendingPathComponent("Application Support/Steam/steamapps/common/Valheim/valheim.app")
        let crossOver = library.appendingPathComponent("Application Support/CrossOver/Bottles/Games/system.reg")
        let otherCache = places.userCache!.appendingPathComponent("com.apple.Safari/com.apple.metal/z.data")
        let wineOther = places.userCache!.appendingPathComponent("org.winehq.wine/Cache.db")
        let oldDocs = places.documents.appendingPathComponent("Letter.pages")
        for file in [steamForMac, crossOver, otherCache, wineOther, oldDocs] { write(file) }

        let names = Set(CompleteRemoval.saveSources(places).map(\.name))
        check(names == ["crossover/Documents", "crossover/AppData/Roaming", "crossover/AppData/Local/Pal",
                        "Steam userdata/158043902/550"], "the saves, no caches or Steam's own: \(names.sorted())")
        check(CompleteRemoval.targets(places).count == 6, "six things to remove: \(CompleteRemoval.targets(places).map(\.lastPathComponent))")

        places.settingsDomain = "io.github.lordhayne.nightforge.removal-test"
        let defaults = UserDefaults(suiteName: places.settingsDomain)!
        defaults.set(true, forKey: "library.hidden")
        let saves = try? CompleteRemoval.remove(places, defaults: defaults)

        check(saves != nil, "the saves were copied")
        if let saves {
            check((try? String(contentsOf: saves.appendingPathComponent("crossover/AppData/Roaming/Hades/Profile1.sav"), encoding: .utf8)) == "hades save", "Hades' save is in Documents")
            check((try? String(contentsOf: saves.appendingPathComponent("crossover/AppData/Local/Pal/Saved/SaveGames/0/World.sav"), encoding: .utf8)) == "palworld world", "Palworld's world is in Documents")
            check(exists(saves.appendingPathComponent("crossover/Documents/My Games/Skyrim/Saves/quick.ess")), "Skyrim's save is in Documents")
            check(exists(saves.appendingPathComponent("Steam userdata/158043902/550/remote/cfg/config.cfg")), "Steam's per-game folder is in Documents")
            check(!exists(saves.appendingPathComponent("crossover/AppData/Local/Temp")), "no temp files copied")
            check(saves.path.contains("/Documents/Nightforge Saves/"), "under Documents/Nightforge Saves: \(saves.path)")
        }
        check(!exists(places.support) && !exists(places.caches) && !exists(places.shortcuts), "Nightforge's folders are gone")
        check(!exists(library.appendingPathComponent("HTTPStorages/io.github.lordhayne.nightforge")), "its web cache is gone")
        check(!exists(places.userCache!.appendingPathComponent("io.github.lordhayne.nightforge.game")), "the game bundle's caches are gone")
        check(!exists(game), "the Windows games went with the Windows environment")
        check(!exists(places.userCache!.appendingPathComponent("org.winehq.wine/com.apple.metal")), "Wine's shader cache is gone")
        check([steamForMac, crossOver, otherCache, wineOther, oldDocs].allSatisfy(exists),
              "Steam for Mac, CrossOver, other apps' caches, Wine's other files and your documents stay")
        check(defaults.object(forKey: "library.hidden") == nil, "the settings are gone")

        // Nothing to copy: no folder in Documents.
        var empty = places
        empty.support = root.appendingPathComponent("nothing", isDirectory: true)
        check((try? CompleteRemoval.copySaves(empty)) == .some(nil), "no saves, no folder")

        print(failures == 0 ? "✓ CompleteRemoval" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
