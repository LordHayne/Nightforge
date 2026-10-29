// Checks GameID (keys, links) and the update from settings kept by Steam app ID: a game's options,
// what its starts taught Nightforge, its rating, marks and cached art are all still there
// afterwards: tests/GameIDTest/run.sh
import Foundation

@main
struct GameIDTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        // Keys and what reads them back.
        check(GameID.steam(570).key == "steam.570" && GameID.epic("Fortnite").key == "epic.Fortnite", "keys name the store")
        check(GameID(key: "steam.570") == .steam(570) && GameID(key: "epic.Fortnite") == .epic("Fortnite"), "keys read back")
        check(GameID(key: "570") == .steam(570), "a bare number is a Steam app ID, as before")
        check(GameID(key: "0") == nil && GameID(key: "-3") == nil && GameID(key: "steam.abc") == nil, "Steam IDs are positive numbers")
        check(GameID(key: "epic.") == nil && GameID(key: "itch.1") == nil && GameID(key: "epic") == nil, "no ID, no store we know")
        check(GameID(key: "epic.a/b") == nil && GameID(key: "epic...") == nil, "IDs become file names: nothing but plain ones")
        check(GameID.steam(570).steamAppID == 570 && GameID.epic("Sugar").steamAppID == nil, "only Steam games have an app ID")

        // A game's identity: two stores, same number – two games.
        var steam = Game(appID: 42, name: "Game", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                         installDir: Engine.bottle.url, sizeOnDisk: 0)
        let epic = Game(gameID: GameID(provider: .epic, id: "42"), name: "Game", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        check(steam.id == "Nightforge#42", "a Steam game's place in the list is as before: \(steam.id)")
        check(steam.id != epic.id && steam.gameID != epic.gameID, "another store's game with the same number is another game")
        check(epic.appID == 0 && epic.provider == .epic, "an Epic game has no Steam app ID")
        steam.listID = "kept"
        check(steam.id == "kept", "a list ID still keeps the place")

        migration()

        print(failures == 0 ? "✓ GameID" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Settings as Nightforge kept them before, then one update.
    static func migration() {
        let defaults = UserDefaults.standard
        let app = 990_570
        let keys = GameIDMigration.prefixes.flatMap { ["\($0)\(app)", "\($0)steam.\(app)"] }
            + ["options.\(app + 1)", "options.steam.\(app + 1)", "options.\(app + 2)", "options.steam.\(app + 2)",
               "library.hidden", "library.pinned", "marks.hidden", "marks.pinned", GameIDMigration.doneKey]
        keys.forEach(defaults.removeObject(forKey:))
        defer { keys.forEach(defaults.removeObject(forKey:)) }

        var options = GameOptions()
        options.graphics = .dxvk
        options.frameLimit = 60
        options.extraArgs = "-dx11"
        defaults.set(try! JSONEncoder().encode(options), forKey: "options.\(app)")
        defaults.set(["vcrun2019"], forKey: "learned.winetricks.\(app)")
        defaults.set(true, forKey: "learned.noAVX.\(app)")
        defaults.set("sig-1", forKey: "shaders.\(app)")
        defaults.set(try! JSONEncoder().encode(GameRating(good: false, issues: [.stutters])), forKey: "rating.\(app)")
        defaults.set(true, forKey: "health.dxmtFailed.\(app)")
        defaults.set([app, 10], forKey: "library.hidden")
        defaults.set([app], forKey: "library.pinned")
        // Already under the new key (saved by this version before): that one wins.
        var newer = GameOptions()
        newer.graphics = .d3dmetal
        defaults.set(try! JSONEncoder().encode(GameOptions()), forKey: "options.\(app + 1)")
        defaults.set(try! JSONEncoder().encode(newer), forKey: "options.steam.\(app + 1)")

        let art = FileManager.default.temporaryDirectory.appendingPathComponent("gameid-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: art) }
        FileManager.default.createFile(atPath: art.appendingPathComponent("\(app)_cover").path, contents: Data("cover".utf8))
        FileManager.default.createFile(atPath: art.appendingPathComponent("\(app)_logo.missing").path, contents: nil)
        FileManager.default.createFile(atPath: art.appendingPathComponent("readme.txt").path, contents: nil)

        GameIDMigration.run(defaults: defaults, domain: nil, artwork: art)
        let game = GameID.steam(app)

        let kept = GameOptionsStore.load(game)
        check(kept == options, "the game's options are there after the update: \(kept.graphics) \(kept.frameLimit ?? -1) \(kept.extraArgs)")
        check(GameOptionsStore.load(.steam(app + 1)).graphics == .d3dmetal, "options saved under the new key aren't overwritten")
        check(LearnedFixes.winetricks(game) == ["vcrun2019"] && LearnedFixes.noAVX(game), "what starts taught Nightforge stays")
        check(!LaunchPhase.isFirstStart(game, signature: "sig-1"), "shaders built once don't count as new")
        let rating = GameRatings.load(game)
        check(rating?.good == false && rating?.issues == [.stutters], "the player's rating stays")
        check(LaunchHealth.current(game, LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11]), profile: nil)).index == 1,
              "the old \"DXMT failed\" still moves the game on")
        check(GameMarks.load(.hidden, from: defaults) == [game, .steam(10)], "hidden games stay hidden")
        check(GameMarks.load(.pinned, from: defaults) == [game], "pinned games stay pinned")
        check(defaults.data(forKey: "options.\(app)") != nil, "the old entry stays for an older Nightforge")

        let cover = art.appendingPathComponent("steam.\(app)_cover")
        check((try? Data(contentsOf: cover)) == Data("cover".utf8), "the cached cover is there under its new name")
        check(FileManager.default.fileExists(atPath: art.appendingPathComponent("steam.\(app)_logo.missing").path),
              "so is what Steam doesn't have")
        check(FileManager.default.fileExists(atPath: art.appendingPathComponent("\(app)_cover").path), "the old name stays")

        // Once only: a later start doesn't bring back an option the player has reset since.
        GameOptionsStore.save(GameOptions(), for: game)
        defaults.set(try! JSONEncoder().encode(options), forKey: "options.\(app + 2)")
        GameIDMigration.run(defaults: defaults, domain: nil, artwork: art)
        check(GameOptionsStore.load(game) == GameOptions(), "a reset stays reset")
        check(defaults.object(forKey: "options.steam.\(app + 2)") == nil, "it runs once")
    }
}
