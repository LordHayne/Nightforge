// Checks which shader caches are cleared and that nothing else goes: tests/ShaderCachesTest/run.sh
import Foundation

@main
struct ShaderCachesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ url: URL, bytes: Int = 4096) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(repeating: 7, count: bytes).write(to: url)
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shader-caches-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let steamapps = root.appendingPathComponent("Steam/steamapps", isDirectory: true)
        let external = root.appendingPathComponent("T7/SteamLibrary/steamapps", isDirectory: true)
        let dxmt = root.appendingPathComponent("Caches/Nightforge/dxmt", isDirectory: true)
        let mesa = root.appendingPathComponent("Caches/Nightforge/mesa", isDirectory: true)
        let userCache = root.appendingPathComponent("C", isDirectory: true)

        // Caches …
        write(steamapps.appendingPathComponent("shadercache/550/DXVK_state_cache/left4dead2.dxvk-cache"))
        write(external.appendingPathComponent("shadercache/1623730/fozpipelinesv6/steamapp_pipeline_cache.foz"))
        write(dxmt.appendingPathComponent("ab/cd.bin"))
        write(mesa.appendingPathComponent("mesa_shader_cache_db/kosmickrisp/index"))
        write(userCache.appendingPathComponent("io.github.lordhayne.nightforge.game/com.apple.metal/16777235_339/functions.data"))
        write(userCache.appendingPathComponent("org.winehq.wine/com.apple.gpuarchiver/archive.bin"))
        write(userCache.appendingPathComponent("dxmt/Overwatch.exe/com.apple.metal/16777235_339/functions.data"))
        // … and what must stay.
        let game = steamapps.appendingPathComponent("common/Left 4 Dead 2/left4dead2.exe")
        let manifest = steamapps.appendingPathComponent("appmanifest_550.acf")
        let appUICache = userCache.appendingPathComponent("io.github.lordhayne.nightforge/com.apple.metal/ui.data")
        let otherApp = userCache.appendingPathComponent("com.apple.Safari/com.apple.metal/x.data")
        for file in [game, manifest, appUICache, otherApp] { write(file) }

        let folders = ShaderCaches.folders(steamapps: [steamapps, external, root.appendingPathComponent("gone/steamapps")],
                                           dxmt: dxmt, mesa: mesa, userCache: userCache)
        check(folders.count == 7, "the seven cache folders that are there, nothing for a missing library: \(folders.map(\.lastPathComponent))")
        check(ShaderCaches.size(folders) >= 7 * 4096, "their size: \(ShaderCaches.size(folders))")

        let defaults = TestDefaults.suite("shaders")
        defaults.set("winecx|dxmt", forKey: "shaders.550")
        defaults.set(true, forKey: "library.hidden")
        let freed = ShaderCaches.clear(folders, defaults: defaults)

        check(freed >= 7 * 4096, "freed what was there: \(freed)")
        check(ShaderCaches.size(folders) == 0, "the caches are empty")
        check(folders.allSatisfy(exists), "the folders themselves stay for whoever writes there next")
        check([game, manifest, appUICache, otherApp].allSatisfy(exists), "games, manifests, Nightforge's own UI cache and other apps stay")
        check(defaults.string(forKey: "shaders.550") == nil, "the next start says again that it prepares shaders")
        check(defaults.bool(forKey: "library.hidden"), "other settings stay")

        // MARK: Early translation
        let programs = { (names: [String]) in names.map { URL(fileURLWithPath: "/Games/X/\($0)") } }
        let early = TestDefaults.suite("early-translation")
        check(ShaderCaches.translatesEarly(programs: programs(["AbzuGame-Win64-Shipping.exe"]), defaults: early), "on without any setting")
        check(ShaderCaches.translatesEarly(programs: [], defaults: early), "also when no program was found")
        for name in ["Overwatch.exe", "OVERWATCH.EXE", "overwatch.exe"] {
            check(!ShaderCaches.translatesEarly(programs: programs(["Launcher.exe", name]), defaults: early), "off for \(name)")
        }
        check(ShaderCaches.translatesEarly(programs: programs(["NotOverwatch.exe"]), defaults: early), "only the program of that name")
        early.set(false, forKey: ShaderCaches.earlyTranslationKey)
        check(!ShaderCaches.translatesEarly(programs: programs(["Game.exe"]), defaults: early), "the hidden setting turns it off")
        early.set(true, forKey: ShaderCaches.earlyTranslationKey)
        check(ShaderCaches.translatesEarly(programs: programs(["Game.exe"]), defaults: early), "and on again")

        // MARK: Upper limit
        let shared = root.appendingPathComponent("limit/dxmt", isDirectory: true)
        let limitDefaults = TestDefaults.suite("translation-limit")
        limitDefaults.set(true, forKey: "shaders.550")
        limitDefaults.set(true, forKey: "library.hidden")
        let database = shared.appendingPathComponent("shaders_320.db"), journal = shared.appendingPathComponent("shaders_320.db-wal")
        let lock = shared.appendingPathComponent("shaders_320.db-lock"), other = shared.appendingPathComponent("pipelines/recipe.json")
        write(database, bytes: 600); write(journal, bytes: 300); write(lock, bytes: 0); write(other, bytes: 5000)
        check(ShaderCaches.limitTranslations(in: shared, limit: 1000, defaults: limitDefaults) == 0, "under the limit nothing goes")
        check([database, journal, lock].allSatisfy(exists), "and the files stay")
        check(limitDefaults.bool(forKey: "shaders.550"), "as does what the app remembers")
        write(journal, bytes: 500)
        check(ShaderCaches.limitTranslations(in: shared, limit: 1000, defaults: limitDefaults) == 1100, "over the limit, journal counted: all of it")
        check(![database, journal, lock].contains(where: exists), "the file, its journal and its lock go together")
        check(exists(other), "anything else in the folder stays")
        check(limitDefaults.object(forKey: "shaders.550") == nil, "the next start says again that it prepares shaders")
        check(limitDefaults.bool(forKey: "library.hidden"), "other settings stay")
        check(ShaderCaches.limitTranslations(in: root.appendingPathComponent("nowhere"), limit: 0, defaults: limitDefaults) == 0, "no folder, nothing to do")
        // The real limit, without writing gigabytes: a sparse file.
        write(database, bytes: 0)
        let sparse = try? FileHandle(forWritingTo: database)
        try? sparse?.truncate(atOffset: UInt64(ShaderCaches.translationLimit))
        try? sparse?.close()
        check(ShaderCaches.limitTranslations(in: shared, defaults: limitDefaults) == 0 && exists(database), "exactly 4 GB is still allowed")
        write(journal, bytes: 1)
        check(ShaderCaches.limitTranslations(in: shared, defaults: limitDefaults) == ShaderCaches.translationLimit + 1, "one byte more isn't")

        print(failures == 0 ? "✓ ShaderCaches" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
