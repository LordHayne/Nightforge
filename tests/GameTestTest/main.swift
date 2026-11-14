// Checks the game test's sequencing and report (GameTest): which games it starts and in which
// order, what each look while waiting decides, the ways and frame rates it reads from wine.log,
// where a hang waits, and that the report keeps compat-report.yml's words and no paths.
import AppKit
import Foundation

@main
struct GameTestTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func candidate(_ key: String, _ name: String, _ store: Provider, _ platform: Platform = .windows,
                          skip: GameTest.Skip? = nil) -> GameTest.Candidate {
        GameTest.Candidate(key: key, name: name, store: store, storeID: String(key.split(separator: ".").last ?? ""),
                           platform: platform, skip: skip)
    }

    static func main() {
        settings()
        skips()
        plan()
        basket()
        load()
        looks()
        questionsAndFront()
        outcomes()
        waysAndFrames()
        hangsAndCalm()
        report()
        launchWritesTheWay()
        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("✓ GameTest: switches, order, looks, outcomes, ways, frames, measures, sample, calm, report")
    }

    static func settings() {
        let defaults = TestDefaults.suite("game-test")
        check(GameTest.Settings(defaults) == GameTest.Settings(), "without switches: 120 s for a picture, 60 s of play, all games")
        defaults.set(5, forKey: GameTest.Keys.pictureWait)
        defaults.set(5000, forKey: GameTest.Keys.playSeconds)
        defaults.set(" steam.570, Black Myth: Wukong ;epic.Calluna\n", forKey: GameTest.Keys.only)
        defaults.set("~/testkorb.json", forKey: GameTest.Keys.basket)
        let set = GameTest.Settings(defaults)
        check(set.basket == "~/testkorb.json", "the test basket's file")
        check(set.pictureWait == 30 && set.playSeconds == 600, "waits are kept within bounds: \(set.pictureWait), \(set.playSeconds)")
        check(set.only == ["steam.570", "Black Myth: Wukong", "epic.Calluna"], "only: keys and names by commas, a name's colon kept: \(set.only)")
    }

    static func skips() {
        check(GameTest.skip(GameTest.Facts()) == nil, "a signed-in Windows game with nothing missing starts")
        check(GameTest.skip(GameTest.Facts(antiCheat: true)) == .antiCheat, "anti-cheat stops it")
        check(GameTest.skip(GameTest.Facts(vrOnly: true)) == .vrOnly, "VR only")
        check(GameTest.skip(GameTest.Facts(builtInBottle: false)) == .otherBottle, "a CrossOver bottle's game isn't ours to start")
        check(GameTest.skip(GameTest.Facts(signedIn: false)) == .signIn, "no sign-in: Steam's window would ask")
        check(GameTest.skip(GameTest.Facts(pendingUpdate: true)) == .update, "an update would download")
        check(GameTest.skip(GameTest.Facts(versionSwitch: true)) == .versionSwitch, "the other version's first start carries saves over")
        check(GameTest.skip(GameTest.Facts(missingRuntimes: ["vcrun2019"])) == .runtimes, "runtimes would download")
        check(GameTest.skip(GameTest.Facts(needsD3DMetal: true)) == .d3dMetal, "D3DMetal would be set up")
        check(GameTest.skip(GameTest.Facts(platform: .mac, store: .steam, macSteamReady: false)) == .macSteamSetup,
              "a Mac version without Steam for Mac set up")
        check(GameTest.skip(GameTest.Facts(platform: .mac, store: .gog, builtInBottle: false, macSteamReady: false)) == nil,
              "GOG's Mac versions need neither a bottle nor Steam for Mac")
        check(GameTest.skip(GameTest.Facts(antiCheat: true, signedIn: false)) == .antiCheat, "anti-cheat comes first")
    }

    static func plan() {
        let games = [
            candidate("steam.1245620", "Valheim Mac", .steam, .mac),
            candidate("gog.1207658930", "Mafia II", .gog),
            candidate("epic.Calluna", "Control", .epic),
            candidate("steam.892970", "Valheim", .steam),
            candidate("gog.1", "Mac GOG", .gog, .mac),
            candidate("steam.2357570", "Overwatch", .steam),
            candidate("steam.728880", "Overcooked 2", .steam),
        ]
        let order = GameTest.plan(games).map(\.key)
        check(order == ["steam.728880", "steam.2357570", "steam.892970", "epic.Calluna", "gog.1207658930", "gog.1", "steam.1245620"],
              "Windows Steam, Epic, GOG, then Mac GOG and Mac Steam last, by name: \(order)")
        let only = GameTest.plan(games, only: ["CONTROL", "steam.892970"]).map(\.key)
        check(only == ["steam.892970", "epic.Calluna"], "only: by key or name, any case: \(only)")

        var signIn = GameTest.Entry(candidate("steam.1", "A", .steam), outcome: .needsPlayer, skip: .signIn)
        check(GameTest.blocked(candidate("steam.2", "B", .steam), after: [signIn]), "after a sign-in the store's other games are skipped")
        check(!GameTest.blocked(candidate("steam.2", "B", .steam, .mac), after: [signIn]), "… not the other version's")
        check(!GameTest.blocked(candidate("epic.X", "C", .epic), after: [signIn]), "… nor another store's")
        signIn.skip = .steamAsks
        check(!GameTest.blocked(candidate("steam.2", "B", .steam), after: [signIn]), "Steam's question is the game's own")
    }

    static func basket() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gametest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // compat-db's testkorb.json as scripts/test-basket.py writes it, fields this run doesn't use included.
        let json = """
        {"formatVersion": 1, "generated": "2026-11-02T21:23:38Z", "games": [
          {"key": "steam.3678970", "name": "TBH", "category": "free", "kind": "f2p", "installed": false, "score": 0.6, "hint": null, "standsFor": []},
          {"key": "epic.Curry", "name": "ABZU", "category": "proxy", "installed": true, "score": 0.497, "hint": "dxmt",
           "standsFor": ["steam.1426210", "steam.548430"], "agw": null, "rank": null},
          {"key": "steam.892970", "name": "Valheim", "category": "owned", "installed": true, "score": 0.3, "hint": null, "standsFor": []},
          {"key": "steam.728880", "name": "Overcooked 2", "category": "owned", "installed": true, "score": 0.45},
          {"key": "steam.1245620", "name": "Mac game", "category": "owned", "installed": true, "score": 0.9},
          {"key": "steam.2154900", "name": "SF6 Demo", "category": "free", "kind": "demo", "demoOf": "steam.1364780", "score": 0.43}
        ]}
        """
        let file = folder.appendingPathComponent("testkorb.json")
        try? json.write(to: file, atomically: true, encoding: .utf8)
        let basket = GameTest.Basket.load(file.path)
        check(basket?.games.count == 6 && basket?.generated == "2026-11-02T21:23:38Z", "the basket reads, unknown fields left aside")
        try? json.replacingOccurrences(of: "\"formatVersion\": 1", with: "\"formatVersion\": 2").write(to: file, atomically: true, encoding: .utf8)
        check(GameTest.Basket.load(file.path) == nil, "another format isn't guessed at")
        check(GameTest.Basket.load(folder.appendingPathComponent("none.json").path) == nil && GameTest.Basket.load("") == nil, "no basket")

        let games = [
            candidate("steam.1245620", "Mac game", .steam, .mac),
            candidate("steam.892970", "Valheim", .steam),
            candidate("steam.100", "Aardvark", .steam),
            candidate("steam.728880", "Overcooked 2", .steam),
            candidate("epic.curry", "ABZU", .epic),
            candidate("gog.1", "Mafia II", .gog),
        ]
        let plan = GameTest.plan(games, basket: basket)
        check(plan.map(\.key) == ["steam.728880", "steam.892970", "steam.100", "epic.curry", "gog.1", "steam.1245620"],
              "the basket's games first by score within each group, the rest by name, Mac Steam still last: \(plan.map(\.key))")
        let abzu = plan.first { $0.key == "epic.curry" }
        check(abzu?.inBasket == true && abzu?.hint == "dxmt" && abzu?.standsFor == ["steam.1426210", "steam.548430"],
              "a basket game carries its hint and the games it stands for, Epic's key in any case")
        check(plan.first { $0.key == "steam.892970" }?.standsFor == nil, "an empty standsFor stays out")
        check(plan.first { $0.key == "steam.100" }?.inBasket == false, "not in the basket")
        let entry = GameTest.Entry(abzu!, outcome: .picture)
        check(entry.hint == "dxmt" && entry.standsFor?.count == 2, "the entry hands them on to the compatibility list")
        check(GameTest.plan(games).map(\.key) == ["steam.100", "steam.728880", "steam.892970", "epic.curry", "gog.1", "steam.1245620"],
              "without a basket: by name")
    }

    static func load() {
        check(GameTest.Load(average: 4.94, cores: 10).low, "under half the cores busy: low")
        check(!GameTest.Load(average: 4.96, cores: 10).low, "shown as 5,0 of 10 cores: not low")
        check(!GameTest.Load(average: 38.2, cores: 10).low, "24 compilers at once: busy")
        check(GameTest.Load(average: 1.234, cores: 8) == GameTest.Load(average: 1.2, cores: 8), "one decimal")
        check(GameTest.Load.now.map { $0.cores > 0 } ?? false, "this Mac's load reads")
    }

    static func looks() {
        let settings = GameTest.Settings()
        func look(picture: Bool = false, running: Bool, waited: TimeInterval = 0, idle: TimeInterval = 0, total: TimeInterval = 60) -> GameTest.Look {
            GameTest.look(picture: picture, running: running, waited: waited, idle: idle, total: total, settings: settings)
        }
        check(look(picture: true, running: true, waited: 500) == .picture, "the curtain sank: a picture, however long it took")
        check(look(running: true, waited: 119) == .wait, "running, no picture yet within its wait")
        check(look(running: true, waited: 120) == .hang, "running without a picture for the whole wait: it hangs")
        check(look(running: false, idle: 24) == .wait, "gone a moment: the ladder may start the next way")
        check(look(running: false, idle: 25) == .ended, "gone and nothing starting: it ended")
        check(look(running: false, total: 20 * 60) == .tooLong, "Steam never started it: given up after 20 minutes")
        check(look(running: true, waited: 10, total: 30 * 60) == .tooLong, "a game starting itself over and over")
    }

    static func questionsAndFront() {
        check(!GameTest.callsOff(.steamAsks, after: 5), "Steam's question that goes on by itself after 5 s (Left 4 Dead 2): no call-off")
        check(GameTest.callsOff(.steamAsks, after: 30), "one that stands 30 s needs the player")
        for need in [GameTest.Skip.signIn, .update, .d3dMetal, .macSteamSetup, .runtimes, .macOSAsks] {
            check(GameTest.callsOff(need, after: 0), "\(need) calls the start off at once")
        }

        let wine = "/Users/someone/Library/Application Support/Nightforge/Components/winecx/4.7.3/Libraries/Wine/bin/wine64-preloader"
        check(GameTest.foreignFront(path: "/Applications/Claude.app/Contents/MacOS/Claude", bundleID: "com.anthropic.claudefordesktop",
                                    gameFolder: nil), "the Claude app in front: foreign (2.11.)")
        check(!GameTest.foreignFront(path: "/Applications/Nightforge.app/Contents/MacOS/Nightforge", bundleID: "io.github.lordhayne.nightforge",
                                     gameFolder: nil), "Nightforge itself")
        check(!GameTest.foreignFront(path: wine, bundleID: nil, gameFolder: nil), "a Windows game or Steam's window under Wine")
        check(!GameTest.foreignFront(path: "/Applications/Steam.app/Contents/MacOS/steam_osx", bundleID: "com.valvesoftware.steam",
                                     gameFolder: nil), "Steam for Mac, asking something")
        let folder = "/Users/someone/Library/Application Support/Steam/steamapps/common/Valheim"
        check(!GameTest.foreignFront(path: folder + "/Valheim.app/Contents/MacOS/Valheim", bundleID: "com.irongate.valheim",
                                     gameFolder: folder), "the Mac version being tested")
        check(GameTest.foreignFront(path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", bundleID: "com.apple.finder",
                                    gameFolder: folder), "the Finder")
        check(!GameTest.foreignFront(path: nil, bundleID: nil, gameFolder: nil), "nothing known about it: left alone")

        // Who had the front, as the report names it: known focus-takers by name, any other app not (review 3.11.).
        check(GameTest.frontName("1Password", path: "/Applications/1Password.app/Contents/MacOS/1Password", bundleID: "com.1password.1password")
              == "eine andere App", "a password manager isn't named")
        check(GameTest.frontName("Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", bundleID: nil) == "eine andere App", "nor a chat app")
        check(GameTest.frontName("Nightforge", path: "/Applications/Nightforge.app/Contents/MacOS/Nightforge", bundleID: "io.github.lordhayne.nightforge")
              == "Nightforge", "Nightforge")
        check(GameTest.frontName("Steam", path: "/Applications/Steam.app/Contents/MacOS/steam_osx", bundleID: "com.valvesoftware.steam") == "Steam",
              "Steam for Mac")
        check(GameTest.frontName("steamwebhelper", path: wine, bundleID: nil) == "Steam", "Steam's window under Wine")
        check(GameTest.frontName("Nightforge Game", path: wine, bundleID: nil) == "ein Windows-Programm", "a Windows program under Wine")
        check(GameTest.frontName("UserNotificationCenter", path: "/System/Library/CoreServices/UserNotificationCenter.app/Contents/MacOS/UserNotificationCenter",
                                 bundleID: "com.apple.UserNotificationCenter") == "UserNotificationCenter", "macOS's own asker by name")
        check(GameTest.frontName(nil, path: nil, bundleID: nil) == "keine App", "nobody in front")
        let look = "2 processes, in front Claude (1276, not the game's), windows none, picture none, asks no, curtain up"
        check(GameTest.reportLook(look, game: "Wukong") == "2 processes, in front eine andere App (1276, not the game's), windows none, picture none, asks no, curtain up",
              "the curtain's look names no other app: \(GameTest.reportLook(look, game: "Wukong"))")
        for kept in ["1 processes, in front Tomb Raider (89315, the game's), windows 4 hidden",
                     "2 processes, in front Nightforge (33668, not the game's), windows 286×251 L21",
                     "1 processes, in front UserNotificationCenter (78961, not the game's), windows none"] {
            check(GameTest.reportLook(kept, game: "Tomb Raider") == kept, "kept: \(kept)")
        }

        // macOS asking for permission over the start, as the curtain logs it (Tomb Raider on the stick, 3.11.).
        let tomb = """
        info:  [nightforge] Curtain look at Tomb Raider: 1 processes, in front Tomb Raider (89315, the game's), windows 4 hidden
        info:  [nightforge] In front under the curtain: UserNotificationCenter (78961)
        info:  [nightforge] Curtain under a question of macOS's for Tomb Raider: UserNotificationCenter in front
        info:  [nightforge] Curtain under a question of macOS's for Tomb Raider II: SecurityAgent in front
        """
        check(GameTest.macOSAsking("Tomb Raider", in: tomb) == "UserNotificationCenter", "macOS asks, nobody answered: \(String(describing: GameTest.macOSAsking("Tomb Raider", in: tomb)))")
        check(GameTest.macOSAsking("Tomb Raider", in: tomb + "\ninfo:  [nightforge] Curtain up again for Tomb Raider: macOS's question is answered") == nil,
              "answered: nothing stands")
        check(GameTest.macOSAsking("Tomb Raider", in: tomb + "\ninfo:  [nightforge] Curtain stops waiting for macOS's question for Tomb Raider after 180 s: the start goes on")
              == "UserNotificationCenter", "the curtain giving up doesn't answer it")
        check(GameTest.macOSAsking("Mafia II", in: tomb) == nil, "another game's question isn't this one's")
        // The curtain giving up on it (after three minutes) says nothing more – not even when the question goes:
        // that line is the run's verdict, so a later hang is never taken for the question (review 3.11.).
        let gaveUp = tomb + "\ninfo:  [nightforge] Curtain stops waiting for macOS's question for Tomb Raider after 180 s: the start goes on"
        check(GameTest.macOSQuestion("Tomb Raider", in: tomb) == GameTest.MacOSQuestion(asker: "UserNotificationCenter"),
              "standing, the curtain still waiting")
        check(GameTest.macOSQuestion("Tomb Raider", in: gaveUp) == GameTest.MacOSQuestion(asker: "UserNotificationCenter", gaveUp: true),
              "three minutes unanswered: the verdict")
        check(GameTest.macOSQuestion("Tomb Raider II", in: gaveUp)?.gaveUp == false, "another game's give-up isn't this one's")
        check(GameTest.macOSQuestion("Tomb Raider", in: "info:  [nightforge] Curtain stops waiting for macOS's question for Tomb Raider after 180 s") == nil,
              "a give-up line without its question: nothing")
        check(GameTest.macOSQuestion("Tomb Raider", in: "info:  [nightforge] Curtain under a question of macOS's from before Tomb Raider's start: the start doesn't wait for it") == nil,
              "a question from before the start isn't the start's")
        // Unity's start window ("The Forest Configuration" with "Play!", 464×438, 3.11.): judged after a short grace,
        // longer with the helper that presses Play! (kosmickrisp-dx9) on – and only for Unity, where no splash is that small.
        check(!GameTest.startWindowStands(unity: true, picture: false, standing: 9, helper: false), "9 s: not yet")
        check(GameTest.startWindowStands(unity: true, picture: false, standing: 10, helper: false), "10 s standing: Unity's start window")
        check(!GameTest.startWindowStands(unity: true, picture: false, standing: 29, helper: true), "the helper on: its time to press Play! first")
        check(GameTest.startWindowStands(unity: true, picture: false, standing: 30, helper: true), "still there after 30 s: it needs a click")
        check(!GameTest.startWindowStands(unity: false, picture: false, standing: 100, helper: false),
              "not Unity: a small window may be a splash, judged only when the wait runs out")
        check(!GameTest.startWindowStands(unity: true, picture: true, standing: 100, helper: false), "a picture came: no start window")
        check(!GameTest.startWindowStands(unity: true, picture: false, standing: nil, helper: false), "no window: nothing")
        check(GameTest.Keys.unityDialogPlay == UnityDialog.switchKey && UnityDialog.switchKey == "unityDialogPlay",
              "the helper's own switch (UnityDialog.switchKey)")
        // The helper is on unless switched off: the run reads it the same way, not as "off" when nothing is set.
        let run = (try? String(contentsOf: URL(fileURLWithPath: "Sources/Nightforge/GameTestRun.swift"), encoding: .utf8)) ?? ""
        check(run.contains("let helper = UnityDialog.enabled") && !run.contains("bool(forKey: GameTest.Keys.unityDialogPlay)"),
              "the run takes the helper for on when the switch isn't set, as UnityDialog does")
        check(GameTest.helperPressedPlay(in: "info:  [nightforge] Unity's window \"The Forest Configuration\": pressed Play!\n"),
              "the helper's line: it pressed Play!")
        check(!GameTest.helperPressedPlay(in: "info:  [nightforge] Unity's window: didn't come up\n"), "no window, nothing pressed")
        // Two minutes without a process list (ps not answering): nothing is known – not "no-start" (review 3.11.).
        check(GameTest.outcome(.init(process: true, unknown: true)) == .unknown && GameTest.result(.unknown, issues: []) == nil,
              "no process list: unknown, no result for the compatibility list")
        check(GameTest.outcome(.init(unknown: true)) == .unknown, "not noStart either, although no process was seen")
        check(GameTest.outcome(.init(process: true, picture: true, unknown: true)) == .picture, "a picture before the list went: a picture")
        check(GameTest.blindLooks == 120, "two minutes of looks, one a second")
        // A picture the curtain saw counts without a list too, not "unknown" after two minutes (review 3.11.).
        check(GameTest.blindLook(picture: true, looks: 1) == .picture, "no list, but the curtain sank: a picture")
        check(GameTest.blindLook(picture: true, looks: 500) == .picture, "also after long without a list")
        check(GameTest.blindLook(picture: false, looks: 119) == .wait && GameTest.blindLook(picture: false, looks: 120) == .unknown,
              "no picture: two minutes, then unknown")
        // The wait for a list has an end, so a ps down for good doesn't hold the night's run (review 3.11.).
        check(GameTest.processListPatience == 15 * 60, "15 minutes")
        check(GameTest.waitsForProcessList(waited: 0, gaveUpBefore: false) && GameTest.waitsForProcessList(waited: 899, gaveUpBefore: false),
              "within 15 minutes: wait")
        check(!GameTest.waitsForProcessList(waited: 900, gaveUpBefore: false), "15 minutes without: on without a list")
        check(!GameTest.waitsForProcessList(waited: 0, gaveUpBefore: true), "ps still down since: no new wait")
        check(GameTest.outcome(.init(process: true, startWindow: true)) == .startWindow && GameTest.result(.startWindow, issues: []) == nil,
              "a start window: needs a click, says nothing yet about how it runs")
        check(GameTest.outcome(.init(process: true, picture: true, startWindow: true)) == .picture, "the picture after Play!: a picture")
        check(GameTest.outcome(.init(process: true, stillRunning: false, needs: .macOSAsks)) == .needsPlayer
              && GameTest.result(.needsPlayer, issues: []) == nil, "called off for the player, says nothing about the game")
    }

    static func outcomes() {
        check(GameTest.outcome(.init(process: true, picture: true, crashSigns: true)) == .picture, "a picture is a picture")
        check(GameTest.outcome(.init(process: true, needs: .steamAsks)) == .needsPlayer, "Steam's question calls it off")
        check(GameTest.outcome(.init(process: true, stillRunning: true)) == .hang, "running without a picture: hang")
        check(GameTest.outcome(.init(process: true, stillRunning: true, smallWindow: true)) == .dialog,
              "running with a window of its own smaller than a picture all along: it waits for a click (Wukong, 2.11.)")
        check(GameTest.outcome(.init(process: true, picture: true, smallWindow: true)) == .picture, "a picture after a start window: a picture")
        check(GameTest.result(.dialog, issues: []) == nil, "waiting for a click says nothing yet about how it runs")
        check(GameTest.outcome(.init(process: true, crashSigns: true)) == .crash, "ended with Wine's crash lines: crash")
        check(GameTest.outcome(.init(crashSigns: true)) == .crash, "a crash before the first look is a crash too")
        check(GameTest.outcome(.init(process: true)) == .noWindow, "ended quietly without a window")
        check(GameTest.outcome(.init()) == .noStart, "no process at all")

        let fast = GameTest.Frames(average: 58, low: 41, periods: 5)
        let slow = GameTest.Frames(average: 22, low: 18, periods: 5)
        check(GameTest.issues(endedWhilePlaying: false, frames: fast).isEmpty, "a steady picture: no issues")
        check(GameTest.issues(endedWhilePlaying: true, frames: slow) == ["crashed", "lowFrameRate"], "GameRating's words for both")
        check(GameTest.result(.picture, issues: []) == "good", "compat-report: good")
        check(GameTest.result(.picture, issues: ["crashed"]) == "problems", "compat-report: problems")
        for outcome in [GameTest.Outcome.noWindow, .crash, .hang, .noStart] {
            check(GameTest.result(outcome, issues: []) == "no-start", "compat-report: no-start for \(outcome)")
        }
        check(GameTest.result(.needsPlayer, issues: []) == nil && GameTest.result(.skipped, issues: []) == nil,
              "not tried: says nothing about the game")
    }

    static func waysAndFrames() {
        let note = GameTest.startNote(game: "Black Myth: Wukong", way: "dxmt -dx11", engine: "winecx@4.7.3")
        check(note == "Start of Black Myth: Wukong: dxmt -dx11 on winecx@4.7.3", "the start line: \(note)")
        let log = """
        info:  [nightforge] Curtain watch for Black Myth: Wukong begins
        info:  [nightforge] \(note)
        0124:err:module:import_dll Library MSVCP140.dll not found
        wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140001000
        info:  [nightforge] Start of Black Myth: Wukong: dxvk -dx11 on winecx@4.7.3
        info:  [nightforge] Start of Black Myth: d3dmetal
        info:  [nightforge] \(GameTest.startNote(game: "Black Myth: Wukong", way: "d3dmetal", engine: nil))
        [nightforge-dxmt] b1-Win64-Shipping: 50.0 FPS over 10 s, 1% low 40.0
        [nightforge-dxmt] b1-Win64-Shipping: 60.0 FPS over 30 s, 1% low 50.0
        [nightforge-dxmt] Other: 10.0 FPS over 60 s, 1% low 5.0
        """
        let starts = GameTest.starts(of: "Black Myth: Wukong", in: log)
        check(starts.map(\.way) == ["dxmt -dx11", "dxvk -dx11", "d3dmetal"], "three starts, another game's line left out: \(starts.map(\.way))")
        check(starts.map(\.engine) == ["winecx@4.7.3", "winecx@4.7.3", nil], "engines: \(starts.map(\.engine))")
        check(starts.first?.log.contains("Unhandled page fault") == true, "each start keeps its stretch of the log")
        let ways = GameTest.ways(of: "Black Myth: Wukong", in: log, last: .picture)
        check(ways.map(\.outcome) == [.crash, .noWindow, .picture], "the first crashed, the second ended, the last drew: \(ways.map(\.outcome))")
        check(GameTest.ways(of: "Control", in: log, last: .noStart).isEmpty, "no start line: no ways")
        let looks = """
        info:  [nightforge] Curtain look at Control: 1 processes, in front Nightforge (1), windows 0, picture none
        info:  [nightforge] Curtain look at Control: 2 processes, in front Control (9), windows 1, picture elsewhere
        info:  [nightforge] Curtain look at Control Ultimate: 1 processes
        """
        check(GameTest.lastLook(of: "Control", in: looks) == "2 processes, in front Control (9), windows 1, picture elsewhere",
              "the curtain's last look at the game")
        check(GameTest.lastLook(of: "Mafia II", in: looks) == nil, "no look at it")

        let periods = FramePacing.periods(in: log, programs: ["b1-Win64-Shipping.exe"])
        let frames = GameTest.frames(periods)
        check(frames == GameTest.Frames(average: 57.5, low: 50, periods: 2), "frames by length, the game's own: \(String(describing: frames))")
        check(GameTest.frames([]) == nil, "D3DMetal logs none")

        // LibraryModel's other "Start of <game>: …" note is no way (Alan Wake, 11.11.2026).
        let asked = """
        info:  [nightforge] Start of Alan Wake: d3dmetal on winecx@4.7.3
        info:  [nightforge] Start of Alan Wake: it ended at a question of its own – the player's choice, no other way
        """
        check(GameTest.starts(of: "Alan Wake", in: asked).map(\.way) == ["d3dmetal"], "a note about the start is no way")
        check(GameTest.ways(of: "Alan Wake", in: asked, last: .noWindow).map(\.outcome) == [.noWindow], "the way keeps the start's outcome")
        check(GameTest.starts(of: "Alan Wake", in: asked).first?.log.contains("question of its own") == true, "and the note stays in its log")

        // The lines as DXMT and the Vulkan layer write them: the slowest frame and who logged it.
        let measured = """
        info:  [nightforge-dxmt] prepare: on, level 1
        info:  [nightforge-dxmt] mgsvtpp: 30.0 FPS over 10 s, frames 33.3 ms on average, slowest 4446 ms
        info:  [nightforge-dxmt] mgsvtpp: 59.9 FPS over 10 s, frames 16.7 ms on average, slowest 20 ms
        info:  [nightforge-dxmt] MGSVTPP: 57.8 FPS over 10 s, frames 17.3 ms on average, slowest 76 ms
        info:  [nightforge-dxmt] steamwebhelper: 10.0 FPS over 10 s, frames 100.0 ms on average, slowest 900 ms
        [nightforge-vulkan] TheForest.exe: 58.0 FPS over 10 s, frames 17.2 ms on average, slowest 31 ms
        """
        let own = GameTest.periods(in: measured, programs: ["mgsvtpp.exe"])
        check(own.map(\.fps) == [30, 59.9, 57.8] && own.map(\.slowest) == [4446, 20, 76] && own.allSatisfy { $0.source == "dxmt" },
              "the game's periods with their slowest frames: \(own)")
        check(own.map(\.fps) == FramePacing.periods(in: measured, programs: ["mgsvtpp.exe"]).map(\.fps), "the same periods FramePacing reads")
        let full = GameTest.measuredFrames(own)
        check(full?.average == 49.2 && full?.low == 30 && full?.periods == 3 && full?.seconds == 30, "average, lowest period, seconds: \(String(describing: full))")
        check(full?.slowestFrame == 4446 && full?.slowestTypical == 76 && full?.source == "dxmt",
              "the slowest frame of all and of a usual period: \(String(describing: full))")
        let layer = GameTest.periods(in: measured, programs: ["TheForest.exe"])
        check(layer.count == 1 && layer.first?.source == "vulkan" && layer.first?.slowest == 31, "the Vulkan layer's line, its program with .exe")
        let plain = GameTest.measuredFrames(GameTest.periods(in: log, programs: ["b1-Win64-Shipping.exe"]))
        check(plain?.average == 57.5 && plain?.slowestFrame == nil && plain?.slowestTypical == nil, "a line without frame times: no slowest frame")
        check(GameTest.measuredFrames([]) == nil, "no periods: not measured")

        // The size: the curtain's window, the Vulkan layer's swapchain, DXMT's display mode.
        let sizes = """
        info:  [nightforge] Curtain down for Control Ultimate: Nightforge Game in front, its window 800×600 on 1512×982
        info:  [nightforge] Curtain down for Control: Nightforge Game in front, its window 1800×1125 on 1512×982
        info:  [nightforge] Curtain down for Batman: nobody in front, its window none on 1512×982
        [nightforge-vulkan] swapchain 1280x720 format 44 colour space 0
        [nightforge-vulkan] swapchain 1512x982 format 44 colour space 0, MetalFX to 3024x1964
        info:  Setting display mode: 1280x720@60
        info:  Setting display mode: 1512x982@120
        """
        let picture = GameTest.pictureSize(of: "Control", in: sizes)
        check(picture?.window == "1800×1125" && picture?.screen == "1512×982", "the game's window and the screen, not another game's: \(String(describing: picture))")
        check(GameTest.pictureSize(of: "Batman", in: sizes)?.window == nil && GameTest.pictureSize(of: "Batman", in: sizes)?.screen == "1512×982",
              "no window, the screen all the same")
        check(GameTest.pictureSize(of: "Mafia II", in: sizes) == nil, "no curtain line: no size")
        check(GameTest.swapchain(in: sizes)?.size == "1512×982" && GameTest.swapchain(in: sizes)?.upscaledTo == "3024×1964", "the last swapchain, with MetalFX's target")
        check(GameTest.swapchain(in: log) == nil, "no Vulkan layer: no swapchain")
        check(GameTest.displayMode(in: sizes) == "1512×982@120" && GameTest.displayMode(in: log) == nil, "the last display mode")

        let held = GameTest.Held(frameLimit: 60, refreshRate: 120, metalFX: true)
        let onDXMT = GameTest.measure(of: "Control", way: "dxmt -dx11", in: sizes, frames: full, held: held)
        check(onDXMT == GameTest.Measure(window: "1800×1125", screen: "1512×982", swapchain: "1512×982", upscaledTo: "3024×1964",
                                         displayMode: "1512×982@120", frameLimit: 60, refreshRate: 120, metalFX: true, noFrames: nil),
              "all a DXMT start says: \(onDXMT)")
        let onD3DMetal = GameTest.measure(of: "Control", way: "d3dmetal", in: sizes, frames: nil, held: held)
        check(onD3DMetal.displayMode == nil && onD3DMetal.noFrames == "wayReportsNone", "D3DMetal: no display mode of DXMT's, and its way reports no frames")
        check(GameTest.noFrames(way: "wined3d") == .wayReportsNone && GameTest.noFrames(way: "mac") == .wayReportsNone
              && GameTest.noFrames(way: "dxmt -dx11") == .noneInLog && GameTest.noFrames(way: "dxvk") == .noneInLog && GameTest.noFrames(way: nil) == .noneInLog,
              "which ways report none, and which only logged none")
        let mac = GameTest.measure(of: "Valheim", way: "mac", in: "", frames: nil, held: nil)
        check(mac == GameTest.Measure(noFrames: "wayReportsNone"), "a Mac version: nothing but that nothing reports")
        check(GameTest.sizeText(onDXMT) == "1512×982 px, MetalFX auf 3024×1964" && GameTest.sizeText(onD3DMetal) == "1512×982 px, MetalFX auf 3024×1964"
              && GameTest.sizeText(GameTest.Measure(window: "1512×982", displayMode: "1512×982@120")) == "1512×982@120 (Modus des Spiels)"
              && GameTest.sizeText(GameTest.Measure(window: "1512×982")) == "Fenster 1512×982 Punkte" && GameTest.sizeText(mac) == "nicht gemessen",
              "the size's text: what was drawn, else the mode, else the window")
        hudAndCheck()
        check(GameTest.slowestText(full) == "üblich 76 ms, schlimmster 4446 ms" && GameTest.slowestText(plain) == "nicht gemessen" && GameTest.slowestText(nil) == "nicht gemessen",
              "the slowest frame's text")
    }

    /// Apple's Metal HUD frame by frame, and whether a run has seen all a game needs to be done with.
    static func hudAndCheck() {
        // The game's process logs a line a second; a launcher's window a few frames of its own.
        var lines = ["2026-11-07 02:51:10.950 wine[111:1] metal-HUD: 1,300.00,3000.00,100.00,5.00,16.67,5.00"]
        for second in 0..<25 {
            let slow = second == 12 ? "33.33,9.00" : "16.67,10.00"
            lines.append("2026-11-07 02:51:\(10 + second).950 wine[18259:1984832] metal-HUD: \(second * 60),335.58,3079.71,"
                         + ([slow] + Array(repeating: "16.67,10.00", count: second == 12 ? 58 : 59)).joined(separator: ","))
        }
        lines += ["wine[18259:7] metal-HUD: 9,1.0,2.0,16.67", "wine[18259:7] metal-HUD: broken,1,2,3,4", "info:  [nightforge] metal-HUD is on"]
        let sample = GameTest.hudSample(in: lines.joined(separator: "\n"))
        check(sample?.intervals.count == 25 * 60 - 1 && sample?.gpuTimes.count == sample?.intervals.count,
              "the game's frames, not the launcher's, lines that are none left out: \(String(describing: sample?.intervals.count))")
        let hud = sample.flatMap { GameTest.measuredFrames($0) }
        check(hud?.average == 59.9 && hud?.periods == 2 && hud?.seconds == 25 && hud?.source == "metal-hud",
              "the average over all frames, two full stretches of ten seconds: \(String(describing: hud))")
        check(hud?.low == 59.9 && hud?.slowestFrame == 33.3 && hud?.slowestTypical == 16.7, "the lowest stretch and the slowest frames: \(String(describing: hud))")
        check(hud?.onePercentLow == 60 && hud?.gpuTime == 10, "the slowest percent and the GPU's time: \(String(describing: hud))")
        let stutter = GameTest.measuredFrames(GameTest.HUDSample(intervals: Array(repeating: 16.67, count: 95) + Array(repeating: 50, count: 5),
                                                                 gpuTimes: Array(repeating: 0, count: 100)))
        check(stutter?.onePercentLow == 20 && stutter?.periods == 1 && stutter?.gpuTime == nil, "five slow frames in a hundred show in the slowest percent: \(String(describing: stutter))")
        check(GameTest.hudSample(in: "info:  nothing here") == nil && GameTest.measuredFrames(GameTest.HUDSample(intervals: [16.67], gpuTimes: [1])) == nil,
              "no HUD lines, or a single frame: not measured")

        // Done with a game: a clean start and a frame rate that counts.
        func check2(_ entry: GameTest.Entry, play: Double = 200, battery: Bool = false, lowPower: Bool = false) -> GameTest.Check? {
            GameTest.check(entry, playSeconds: play, onBattery: battery, lowPower: lowPower)
        }
        var clean = GameTest.Entry(candidate("steam.287700", "MGS V", .steam), outcome: .picture)
        clean.ways = [GameTest.Way(way: "dxmt", outcome: .picture)]
        clean.way = "dxmt"
        clean.frames = GameTest.Frames(average: 59, low: 57, periods: 12)
        clean.load = GameTest.Load(average: 1, cores: 10)
        check(check2(clean) == GameTest.Check(start: "ok", fps: "ok") && check2(clean)?.done == true, "a picture on the first way with frames: done")
        check(check2(clean, play: 60)?.start == "ok", "frames counted: working whatever the run's length")
        var quiet = clean
        quiet.frames = nil
        quiet.way = "d3dmetal"
        check(check2(quiet) == GameTest.Check(start: "ok", fps: "wayReportsNone") && check2(quiet)?.done == false, "180 s with a picture is a start; D3DMetal gives no frames")
        check(check2(quiet, play: 60)?.start == "tooShort", "60 s without frames can't have seen it work")
        quiet.way = "dxmt"
        check(check2(quiet)?.fps == "noneInLog", "DXMT without a line")
        var twice = clean
        twice.ways = [GameTest.Way(way: "d3dmetal", outcome: .crash), GameTest.Way(way: "dxmt", outcome: .picture)]
        check(check2(twice)?.start == "severalWays" && check2(twice)?.fps == "ok", "a second way is no clean start, its frames count all the same")
        var crashed = clean
        crashed.issues = ["crashed"]
        check(check2(crashed)?.start == "endedByItself", "ended by itself while playing")
        check(check2(clean, battery: true)?.fps == "throttled" && check2(clean, lowPower: true)?.fps == "throttled", "battery and Low Power Mode: no frame rate that counts")
        var capped = clean
        capped.measure = GameTest.Measure(frameLimit: 30, throttled: "battery")
        check(check2(capped)?.fps == "throttled", "a limit lowered for the battery")
        var busy = clean
        busy.load = GameTest.Load(average: 9, cores: 10)
        check(check2(busy)?.fps == "loadHigh" && check2(busy)?.start == "ok", "a busy Mac: the start counts, the frames don't")
        let hung = GameTest.Entry(candidate("steam.1", "Hung", .steam), outcome: .hang)
        check(check2(hung) == GameTest.Check(start: "noPicture", fps: "noPicture"), "no picture: neither")
        let asked = GameTest.Entry(candidate("steam.2", "Asked", .steam), outcome: .needsPlayer, skip: .steamAsks)
        check(check2(asked)?.start == "neededPlayer", "called off for the player")
        check(check2(.skipped(candidate("steam.3", "Skipped", .steam), .antiCheat)) == nil, "not started: nothing to check")
        let held = GameTest.Held(frameLimit: 30, refreshRate: 120, metalFX: false, throttled: "battery")
        check(GameTest.measure(of: "X", way: "dxmt", in: "", frames: nil, held: held).throttled == "battery", "what the limit was lowered for goes into the measure")
    }

    static func hangsAndCalm() {
        let sample = """
        Analysis of sampling Overwatch.exe (pid 4242) every 1 millisecond
        Call graph:
            2000 Thread_1   DispatchQueue_1: com.apple.main-thread  (serial)
              2000 start  (in dyld) + 6000  [0x18c]

        Total number in stack (recursive counted multiple, when >=5):

        Sort by top of stack, same collapsed (when >= 5):
                semaphore_wait_trap  (in libsystem_kernel.dylib)        3999
                __psynch_cvwait  (in libsystem_kernel.dylib)        2000
                kevent  (in libsystem_kernel.dylib)        1000

        Binary Images:
               0x100000000 -        0x100ffffff +wine64-preloader (0) /Users/someone/Library/wine64-preloader
        """
        let top = GameTest.topOfStack(in: sample)
        check(top == ["semaphore_wait_trap (in libsystem_kernel.dylib) 3999", "__psynch_cvwait (in libsystem_kernel.dylib) 2000",
                      "kevent (in libsystem_kernel.dylib) 1000"], "where it waits, no binary images: \(top)")
        check(GameTest.topOfStack(in: sample, limit: 1).count == 1, "the heaviest only")
        check(GameTest.topOfStack(in: "sample: unable to examine process").isEmpty, "nothing when sample couldn't read it")

        let ps = """
         35.0 /Users/someone/Library/Application Support/Nightforge/Components/winecx/bin/wineserver
         12,5 C:\\Program Files (x86)\\Steam\\steam.exe
          8.0 /Applications/Steam.app/Contents/MacOS/steam_osx
         90.0 /Applications/Safari.app/Contents/MacOS/Safari
        garbage line
        """
        check(GameTest.sessionCPU(ps) == 55.5, "Wine and both Steams, not Safari: \(GameTest.sessionCPU(ps))")
        check(!GameTest.calm([10, 10]), "two looks aren't enough")
        check(GameTest.calm([80, 10, 20, 29]), "the last three under 30 %")
        check(!GameTest.calm([10, 10, 31]), "a busy last look")
    }

    static func report() {
        let home = "/Users/jdoe"
        var hung = GameTest.Entry(candidate("steam.2357570", "Overwatch", .steam), outcome: .hang)
        hung.ways = [GameTest.Way(way: "dxmt", engine: "winecx@4.7.3", outcome: .hang)]
        hung.way = "dxmt"
        hung.result = GameTest.result(.hang, issues: [])
        hung.errors = ["err:module:import_dll C:\\users\\jdoe\\AppData\\x.dll not found", "Z:\(home)/Library/Overwatch.exe crashed"]
        hung.stack = ["read (in libsystem_kernel.dylib) 3000"]
        hung.notes = ["log in \(home)/Desktop", "Meldung: a | pipe"]
        hung.files = ["steam.2357570.log", "steam.2357570.sample.txt"]
        hung.hint = "dxvk"
        var good = GameTest.Entry(candidate("epic.Calluna", "Control | Ultimate", .epic), outcome: .picture)
        good.ways = [GameTest.Way(way: "d3dmetal", outcome: .picture)]
        good.way = "d3dmetal"
        good.result = "good"
        good.secondsToPicture = 34.4
        good.measure = GameTest.Measure(window: "1512×982", screen: "1512×982", frameLimit: 0, refreshRate: 120, metalFX: false, noFrames: "wayReportsNone")
        good.sizeBytes = 48_392_303_260
        good.check = GameTest.Check(start: "ok", fps: "wayReportsNone")
        var dxmt = GameTest.Entry(candidate("steam.728880", "Overcooked 2", .steam), outcome: .picture)
        dxmt.way = "dxmt"
        dxmt.frames = GameTest.Frames(average: 59.6, low: 41, periods: 5, seconds: 50, slowestFrame: 310, slowestTypical: 24, source: "dxmt")
        dxmt.measure = GameTest.Measure(window: "1512×982", screen: "1512×982", displayMode: "1512×982@120", frameLimit: 60, refreshRate: 120, metalFX: true)
        dxmt.result = "good"
        dxmt.sizeBytes = 8_471_095_333
        dxmt.check = GameTest.Check(start: "ok", fps: "ok")
        dxmt.load = GameTest.Load(average: 1.5, cores: 10)
        var busy = GameTest.Entry(candidate("steam.892970", "Valheim", .steam), outcome: .picture)
        busy.way = "dxmt"
        busy.frames = GameTest.Frames(average: 31, low: 12, periods: 5)
        busy.result = "good"
        busy.load = GameTest.Load(average: 38.2, cores: 10)
        var skipped = GameTest.Candidate(key: "steam.9", name: "Shooter", store: .steam, storeID: "9", platform: .windows,
                                         skip: .runtimes, skipNote: "fehlt: vcrun2019")
        skipped.notYet = true
        skipped.sizeBytes = 1_500_000_000
        var guarded = GameTest.Candidate(key: "steam.7", name: "Guarded", store: .steam, storeID: "7", platform: .windows, skip: .antiCheat)
        guarded.sizeBytes = 84_222_583_639
        let started = Date(timeIntervalSince1970: 1_793_664_720)  // 2026-11-03 00:12 UTC
        var report = GameTest.Report(started: started, finished: started.addingTimeInterval(3600), nightforge: "0.3.1",
                                     engine: ["winecx@4.7.3", "dxmt@0.80"], mac: "Apple M5 · macOS 26.1",
                                     pictureWait: 120, playSeconds: 60)
        report.load = GameTest.Load(average: 2.04, cores: 10)
        let written = (try? JSONSerialization.jsonObject(with: GameTest.json(report))) as? [String: Any]
        check(written?["runsOn"] as? String == "x86_64 under Rosetta", "a report says how Wine ran")
        report.basket = .init(generated: "2026-11-02T21:23:38Z", entries: 239, installed: 4)
        var dialog = GameTest.Entry(candidate("steam.3132990", "Black Myth: Wukong Benchmark Tool", .steam), outcome: .dialog)
        dialog.way = "d3dmetal"
        dialog.notes = ["Fenster des Spiels: 286×251 L21, 1 hidden"]
        var forest = GameTest.Entry(candidate("steam.242760", "The Forest", .steam), outcome: .startWindow)
        forest.way = "dxmt"
        forest.notes = ["Startfenster des Spiels stand 10 s: 464×438 L0"]
        var blind = GameTest.Entry(candidate("steam.1", "Blind Game", .steam), outcome: .unknown)
        blind.way = "dxmt"
        var asked = GameTest.Entry(candidate("steam.203160", "Tomb Raider", .steam, .mac), outcome: .needsPlayer, skip: .macOSAsks)
        asked.way = "mac"
        report.waitedProcessList = 7
        report.built = started.addingTimeInterval(-7200)
        report.games = [dxmt, busy, good, hung.redacted(home: home, user: "jdoe"), dialog, forest, blind, asked, .skipped(skipped, .runtimes),
                        GameTest.Entry(candidate("steam.1", "Store", .steam), outcome: .needsPlayer, skip: .signIn)]

        let json = GameTest.json(report)
        let text = String(decoding: json, as: UTF8.self)
        check(!GameTest.leaks(text, home: home, user: "jdoe", machine: []), "the report keeps no home folder or account name")
        check(GameTest.leaks("C:\\\\users\\\\jdoe\\\\x", home: home, user: "jdoe", machine: []) && GameTest.leaks("\(home)/x", home: home, user: "jdoe", machine: []),
              "a path with the account name is caught")
        check(!GameTest.leaks("users/jdoey and Thomas Was Alone", home: home, user: "jdoe", machine: []), "another account, a game's name: no leak")
        // The second check knows what redacted knows (review 3.11.), and the Mac's names only as words.
        func leak(_ text: String) -> Bool { GameTest.leaks(text, home: home, user: "jdoe", machine: ["Mini", "Studio-7"]) }
        for text in ["write to jane@example.com", "access_token=abc123", "\"refresh_token\": \"xyz\"", "-AUTH_PASSWORD=abc", "Bearer abcdefgh12",
                     "owner jdoe", "[U:1:12345]", "userdata/123456", "users/48628349957132247/releases", "/var/folders/x7/abcd/T/x",
                     "/Volumes/Jane SSD/x", "COMPUTERNAME=mini", "host studio-7.local"] {
            check(leak(text), "a leak: \(text)")
        }
        for text in ["<email>", "access_token=<hidden>", "\"refresh_token\": \"<hidden>\"", "-AUTH_PASSWORD=<hidden>", "owner <user>", "<steam id>",
                     "users/<gog user>/releases", "/var/folders/<id>/T/x", "/Volumes/<drive>/x", "/System/Volumes/Preboot/x", "LOCAL_HOSTNAME=<computer>",
                     "Minigolf", "Studios", "Mini2", "jdoey"] {
            check(!leak(text), "no leak: \(text)")
        }
        check(GameTest.report(from: json) == report, "report.json reads back as written")
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let first = (object?["games"] as? [[String: Any]])?.first
        check(object?["formatVersion"] as? Int == 2, "format 2")
        let measure = first?["measure"] as? [String: Any], frames = first?["frames"] as? [String: Any]
        check(measure?["frameLimit"] as? Int == 60 && measure?["displayMode"] as? String == "1512×982@120" && measure?["window"] as? String == "1512×982",
              "the measure's conditions in each entry with a picture: \(String(describing: measure))")
        check(frames?["slowestFrame"] as? Double == 310 && frames?["slowestTypical"] as? Double == 24 && frames?["source"] as? String == "dxmt"
              && frames?["seconds"] as? Double == 50, "the frames' slowest and source: \(String(describing: frames))")
        check(object?["onBattery"] == nil && object?["lowPower"] == nil, "on mains: nothing said about power")
        check(object?["built"] as? String == "2026-11-02T22:12:00Z", "when this Nightforge was built")
        check(first?["sizeBytes"] as? Int == 8_471_095_333 && (first?["check"] as? [String: String]) == ["start": "ok", "fps": "ok"],
              "the size and the check in each entry: \(String(describing: first?["check"]))")
        // A report from before format 2 reads as it was written.
        let old = """
        {"formatVersion": 1, "started": "2026-11-03T00:12:00Z", "nightforge": "0.3.0", "mac": "Apple M5 · macOS 27.0", "pictureWait": 120,
         "playSeconds": 60, "stopped": false, "games": [{"game": "ABZU", "store": "epic", "storeID": "Curry", "platform": "windows",
         "outcome": "picture", "issues": [], "ways": [], "frames": {"average": 58.3, "low": 41.6, "periods": 13}}]}
        """
        let read = GameTest.report(from: Data(old.utf8))
        check(read?.formatVersion == 1 && read?.games.first?.frames == GameTest.Frames(average: 58.3, low: 41.6, periods: 13)
              && read?.games.first?.measure == nil && read?.onBattery == nil, "a format 1 report still reads: \(String(describing: read?.games.first))")
        for field in ["game", "store", "storeID", "result", "way", "issues"] {
            check(first?[field] != nil, "compat-report's field \(field) in each entry")
        }
        check(first?["store"] as? String == "steam" && first?["storeID"] as? String == "728880", "the store and its ID as the form has them")
        check(text.contains("\"started\" : \"2026-11-03T00:12:00Z\""), "dates as ISO 8601")

        let summary = GameTest.summary(report, timeZone: TimeZone(identifier: "UTC")!)
        check(!GameTest.leaks(summary, home: home, user: "jdoe"), "the summary keeps no home folder or account name")
        check(summary.hasPrefix("# Spieletest vom 3.11.2026\n"), "German title with the run's date")
        check(summary.contains("Nightforge 0.3.1 · winecx@4.7.3 · dxmt@0.80 · Apple M5 · macOS 26.1"), "what it ran on")
        check(summary.contains("Start 00:12, Ende 01:12."), "start and end")
        check(summary.contains("Ohne Prozessliste (ps antwortete nicht): 7 min gewartet."), "the run's wait for ps")
        // The run's own notes go through redacted when written, as the entries' do.
        var noted = report
        noted.notes = ["Testkorb nicht lesbar (jdoe@example.com.json, Format 1 erwartet)", "\(home)/x"]
        check(noted.redacted(home: home, user: "jdoe", machine: []).notes == ["Testkorb nicht lesbar (<email>, Format 1 erwartet)", "~/x"],
              "the run's notes redacted: \(String(describing: noted.redacted(home: home, user: "jdoe", machine: []).notes))")
        check(summary.contains("| Blind Game | Steam | Windows | dxmt | unbekannt: keine Prozessliste (ps antwortete nicht) | – | – |"), "unknown, said as such")
        check(summary.contains("**7 gestartet: 3 mit Bild, 4 ohne (1 hängt, 1 braucht einen Klick im Startfenster, 1 wartet auf einen Klick, 1 unbekannt). 2 abgebrochen. 1 nicht gestartet.**"),
              "the counts:\n\(summary)")
        check(summary.contains("| The Forest | Steam | Windows | dxmt | braucht einen Klick: Startfenster des Spiels (Unity, „Play!“) | – | – |")
              && summary.contains("- Startfenster des Spiels stand 10 s: 464×438 L0"), "Unity's start window named as such")
        check(summary.contains("| Tomb Raider | Steam | Mac | mac | abgebrochen: macOS fragt um Erlaubnis | – | – |"), "macOS's question: called off, not a hang")
        check(summary.contains("| Black Myth: Wukong Benchmark Tool | Steam | Windows | d3dmetal | wartet auf einen Klick in seinem eigenen Fenster (Starter oder Dialog) | – | – |")
              && summary.contains("- Fenster des Spiels: 286×251 L21, 1 hidden"), "a start window or dialog named as such, not as a hang")
        check(summary.contains("Systemlast zu Beginn: 2,0 bei 10 Kernen – niedrig."), "the load at the start")
        check(summary.contains("Bei 1 Spiel war die Last beim Start hoch (in der Tabelle markiert)."), "games started on a busy Mac")
        check(summary.contains("| Valheim | Steam | Windows | dxmt | Bild | – | 31 / 12 (Last hoch) |"), "their frame rates marked")
        check(summary.contains("Erwartet laut Testkorb: dxvk."), "the basket's hint next to the way it took")
        check(summary.contains("Testkorb vom 2026-11-02: 239 Einträge, 4 davon hier installiert und zuerst gespielt."), "the basket it went by")
        var busyRun = report
        busyRun.load = GameTest.Load(average: 38.2, cores: 10)
        check(GameTest.summary(busyRun).contains("38,2 bei 10 Kernen – hoch: Andere Arbeit lief mit, die FPS-Werte sind nicht verlässlich."),
              "a busy Mac at the start is said plainly")
        check(summary.contains("| Control \\| Ultimate | Epic Games | Windows | d3dmetal | Bild | 34 s | nicht gemessen (D3DMetal meldet keine) |"),
              "a table row, its pipe escaped")
        check(summary.contains("## Messwerte") && summary.contains("(60 s nach dem ersten Bild)") && summary.contains("Das 1-%-Tief meldet kein Weg"),
              "what the measures stand for")
        check(summary.contains("| Overcooked 2 | dxmt | 60 FPS | 1512×982@120 (Modus des Spiels) | 60 / 41 über 50 s | üblich 24 ms, schlimmster 310 ms |"),
              "a measured row:\n\(summary)")
        check(summary.contains("| Control \\| Ultimate | d3dmetal | keins | Fenster 1512×982 Punkte | nicht gemessen (D3DMetal meldet keine) | nicht gemessen |"),
              "a row of a way that reports nothing")
        check(summary.contains("| Valheim | dxmt | nicht gemessen | nicht gemessen | 31 / 12 (Last hoch) | nicht gemessen |"), "a row without a measure")
        check(!summary.contains("auf Akku"), "on mains: no word about power")
        var onBattery = report
        onBattery.onBattery = true
        onBattery.lowPower = true
        check(GameTest.summary(onBattery).contains("Der Mac lief auf Akku und im Stromsparmodus: Die Werte sind mit anderen Läufen nicht vergleichbar."),
              "battery and Low Power Mode said plainly")
        var noPicture = report
        noPicture.games = [blind]
        check(!GameTest.summary(noPicture).contains("## Messwerte"), "no picture: no measures")
        // The checklist: every installed game, what this run saw of it, what a tick would free.
        check(summary.contains("## Abhakliste") && summary.contains("Deinstalliert wird hier nie etwas."), "the checklist and what it never does")
        check(summary.contains("| Overcooked 2 | Windows | 8,5 GB | ja | ja | fertig |"), "done: a clean start and frames\n\(summary)")
        check(summary.contains("| Control \\| Ultimate | Windows | 48,4 GB | ja | der Weg meldet keine | fehlt: FPS |"), "a start without frames: FPS missing")
        check(summary.contains("| Shooter | Windows | 1,5 GB | – | – | nicht gestartet: bräuchte erst Laufzeiten (würde laden) |"), "skipped for something that can be mended")
        check(summary.contains("Fertig in diesem Lauf: 1 von 10 Spielen, zusammen 8,5 GB."), "what the ticks free")
        var withGuarded = report
        withGuarded.games = [.skipped(guarded, .antiCheat)]
        check(GameTest.summary(withGuarded).contains("| Guarded | Windows | 84,2 GB | – | – | von Hand zu prüfen: Anti-Cheat sperrt es auf dem Mac |"),
              "an anti-cheat game: to be looked at by hand")
        check(GameTest.byHand.contains(.versionSwitch) && !GameTest.byHand.contains(.update), "the other version's first start is by hand, an update isn't")
        check(summary.contains("| Overcooked 2 | Steam | Windows | dxmt | Bild | – | 60 / 41 |"), "DXMT's frame rates")
        check(summary.contains("### Overwatch (Steam, Windows)") && summary.contains("hängt ohne Bild. Wege: dxmt."), "the hang's section")
        check(summary.contains("read (in libsystem_kernel.dylib) 3000"), "where it hangs")
        check(summary.contains("Mehr im Ordner des Laufs: steam.2357570.log, steam.2357570.sample.txt"), "the run's files")
        check(summary.contains("- Shooter (Steam): bräuchte erst Laufzeiten (würde laden) (fehlt: vcrun2019)"), "why one wasn't started")
        check(summary.contains("abgebrochen: bräuchte eine Anmeldung"), "the sign-in that called one off")

        check(GameTest.folderName(started, timeZone: TimeZone(identifier: "UTC")!) == "2026-11-03-0012", "the run's folder")
        check(GameTest.fileName("epic.Some/App Name", "log") == "epic.Some_App_Name.log", "no path out of a key")
    }

    /// LibraryModel's start writes the line the report reads the ways from, and installs nothing during a run.
    static func launchWritesTheWay() {
        let source = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(source.contains("GameLog.note(GameTest.startNote(game: game.name, way: way, engine: build?.engine))"),
              "LibraryModel.launch notes each start's way")
        check(source.contains("if !missing.isEmpty, !GameTest.active {"), "no runtimes installed during a run")
        check(source.contains("func comeToFront("), "NSApp.comeToFront, which the run takes the front back with")
    }
}
