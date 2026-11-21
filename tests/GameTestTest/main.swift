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

    static func main() async {
        await handsOff()
        steadyRates()
        wineFpsAsSeen()
        measuringRunFixture()
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
        check(GameTest.noFrames(way: "d3dmetal", frameLog: true) == .noneInLog && GameTest.noFrames(way: "dxvk", frameLog: true) == .noneInLog
              && GameTest.noFrames(way: "wined3d", frameLog: true) == .wayReportsNone && GameTest.noFrames(way: "mac", frameLog: true) == .wayReportsNone,
              "with the HUD's frame log every way through Metal reports; OpenGL and a Mac version still don't")
        check(GameTest.measure(of: "Control", way: "d3dmetal", in: sizes, frames: nil, held: held, frameLog: true).noFrames == "noneInLog",
              "… and the measure says so")
        // What a start is held to, as its line in the log says it.
        let limits = [
            GameTest.limitNote(game: "Control", GameTest.Held(frameLimit: 60, refreshRate: 120, metalFX: true)),
            GameTest.limitNote(game: "ABZU", GameTest.Held(frameLimit: 0, refreshRate: 120, metalFX: false)),
            GameTest.limitNote(game: "Mafia II", GameTest.Held(frameLimit: 30, refreshRate: 60, metalFX: false, throttled: "battery")),
            "Frame limit of Broken: lots at 120 Hz, MetalFX on", "Frame limit of Half: 60 FPS at 120 Hz",
            GameTest.limitNote(game: "Twice", GameTest.Held(frameLimit: 60, refreshRate: 120, metalFX: false)),
            GameTest.limitNote(game: "Twice", GameTest.Held(frameLimit: 40, refreshRate: 120, metalFX: true, throttled: "lowPower")),
        ]
        check(limits[0] == "Frame limit of Control: 60 FPS at 120 Hz, MetalFX on" && limits[1] == "Frame limit of ABZU: none at 120 Hz, MetalFX off"
              && limits[2] == "Frame limit of Mafia II: 30 FPS at 60 Hz, MetalFX off, throttled by battery", "the line as written: \(limits.prefix(3))")
        let limitLog = limits.map { "[20:10:13] " + $0 }.joined(separator: "\n")
        check(GameTest.held(of: "Control", in: limitLog) == GameTest.Held(frameLimit: 60, refreshRate: 120, metalFX: true)
              && GameTest.held(of: "ABZU", in: limitLog) == GameTest.Held(frameLimit: 0, refreshRate: 120, metalFX: false)
              && GameTest.held(of: "Mafia II", in: limitLog) == GameTest.Held(frameLimit: 30, refreshRate: 60, metalFX: false, throttled: "battery"),
              "… and read back: a limit, none, and what lowered it")
        check(GameTest.held(of: "Twice", in: limitLog) == GameTest.Held(frameLimit: 40, refreshRate: 120, metalFX: true, throttled: "lowPower"),
              "the last start's line counts")
        check(GameTest.held(of: "Broken", in: limitLog) == nil && GameTest.held(of: "Half", in: limitLog) == nil && GameTest.held(of: "Other", in: limitLog) == nil,
              "a line that doesn't read, or none: nothing known – no limit made up")
        check(GameTest.measure(of: "ABZU", way: "dxmt", in: limitLog, frames: full, held: GameTest.held(of: "ABZU", in: limitLog)).frameLimit == 0,
              "no limit is a 0 in the measure, not a missing value")
        let mac = GameTest.measure(of: "Valheim", way: "mac", in: "", frames: nil, held: nil)
        check(mac == GameTest.Measure(noFrames: "wayReportsNone"), "a Mac version: nothing but that nothing reports")
        check(GameTest.sizeText(onDXMT) == "1512×982 px, MetalFX auf 3024×1964" && GameTest.sizeText(onD3DMetal) == "1512×982 px, MetalFX auf 3024×1964"
              && GameTest.sizeText(GameTest.Measure(window: "1512×982", displayMode: "1512×982@120")) == "1512×982@120 (Modus des Spiels)"
              && GameTest.sizeText(GameTest.Measure(window: "1512×982")) == "Fenster 1512×982 Punkte" && GameTest.sizeText(mac) == "nicht gemessen",
              "the size's text: what was drawn, else the mode, else the window")
        hudAndCheck()
        wineFps()
        check(GameTest.slowestText(full) == "üblich 76 ms, schlimmster 4446 ms" && GameTest.slowestText(plain) == "nicht gemessen" && GameTest.slowestText(nil) == "nicht gemessen",
              "the slowest frame's text")
    }

    /// No tool attaches to the process of a game with a cheat protection: with the profile's field `sample` isn't
    /// called at all, without it as before; and the report says why a stack is missing.
    static func handsOff() async {
        func profile(_ json: String) -> GameProfile? { try? JSONDecoder().decode(GameProfile.self, from: Data(json.utf8)) }
        let own = profile(#"{"name": "Overwatch", "graphics": "dxmt", "ownAntiCheat": true}"#)
        check(own?.ownAntiCheat == true && profile(#"{"ownAntiCheat": "yes"}"#)?.ownAntiCheat == nil && profile("{}")?.ownAntiCheat == nil,
              "the profile's field is read, and only as true or false")
        check(GameTest.handsOff(profile: own, knownAntiCheat: false) == "ownAntiCheat" && GameTest.handsOff(profile: own, knownAntiCheat: true) == "ownAntiCheat",
              "a cheat protection of its own: hands off")
        check(GameTest.handsOff(profile: profile(#"{"ownAntiCheat": false}"#), knownAntiCheat: false) == nil
              && GameTest.handsOff(profile: profile(#"{"graphics": "dxmt"}"#), knownAntiCheat: false) == nil
              && GameTest.handsOff(profile: nil, knownAntiCheat: false) == nil, "without the field: nothing against a sample")
        check(GameTest.handsOff(profile: nil, knownAntiCheat: true) == "antiCheat", "an anti-cheat Nightforge knows of otherwise: hands off too")
        // The list that ships says it of Overwatch, in both files.
        for file in ["profiles/mac.json", "profiles/profiles.json"] {
            let list = (try? Data(contentsOf: URL(fileURLWithPath: file))).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let games = list?["games"] as? [String: [String: Any]]
            check(games?["2357570"]?["ownAntiCheat"] as? Bool == true, "Overwatch's own cheat protection in \(file)")
        }

        actor Calls {
            var count = 0
            func take() -> String? {
                count += 1
                return "Sort by top of stack\n        mach_msg2_trap  (in libsystem_kernel.dylib)        4321\n"
            }
        }
        let calls = Calls()
        let kept = await GameTest.hangSample(handsOff: GameTest.handsOff(profile: own, knownAntiCheat: false)) { await calls.take() }
        var count = await calls.count
        check(kept.sample == nil && kept.skipped == "ownAntiCheat" && count == 0, "with the field sample isn't called: \(count) calls")
        let taken = await GameTest.hangSample(handsOff: GameTest.handsOff(profile: profile("{}"), knownAntiCheat: false)) { await calls.take() }
        count = await calls.count
        check(taken.sample?.hasPrefix("Sort by top of stack") == true && taken.skipped == nil && count == 1, "without it sample is called as before: \(count) calls")
        let unread = await GameTest.hangSample(handsOff: nil) { nil }
        check(unread.sample == nil && unread.skipped == nil, "a sample that couldn't read the process is no skipped one")

        // In the report: a sentence where the stack would stand, a field of its own in the JSON – and what a game
        // drew without a picture is said as that, not as its frame rate (Overwatch, 14.11.2026).
        var guarded = GameTest.Entry(candidate("steam.2357570", "Overwatch", .steam), outcome: .hang)
        guarded.way = "dxmt"
        guarded.frames = GameTest.Frames(average: 49, low: 35.5, periods: 12)
        guarded.noSample = kept.skipped
        var hung = GameTest.Entry(candidate("steam.2", "Hanging Game", .steam), outcome: .hang)
        hung.way = "dxmt"
        hung.stack = ["4321 mach_msg2_trap  (in libsystem_kernel.dylib)"]
        let started = Date(timeIntervalSince1970: 1_794_681_660)
        var report = GameTest.Report(started: started, finished: started.addingTimeInterval(600), nightforge: "0.3.2",
                                     engine: ["winecx@4.7.3"], mac: "Apple M5 · macOS 27.0", pictureWait: 180, playSeconds: 190)
        report.games = [guarded, hung]
        let summary = GameTest.summary(report)
        check(summary.contains("Wo es hängt: kein sample: Spiel mit eigenem Cheat-Schutz."), "the report says why there is no stack:\n\(summary)")
        check(summary.components(separatedBy: "Wo es hängt (sample):").count == 2 && summary.contains("4321 mach_msg2_trap"), "the other game keeps its stack")
        check(summary.contains("| hängt ohne Bild | – | ohne Bild gezeichnet: 49 / 36 |"), "frames counted without a picture are named as that:\n\(summary)")
        check(GameTest.noSampleText("antiCheat") == "kein sample: Spiel mit Anti-Cheat", "the other reason in words")
        let games = ((try? JSONSerialization.jsonObject(with: GameTest.json(report))) as? [String: Any])?["games"] as? [[String: Any]]
        check(games?.first?["noSample"] as? String == "ownAntiCheat" && games?.last?["noSample"] == nil && games?.last?["stack"] != nil,
              "report.json has a field of its own for it")
    }

    /// Two games' lines from the measuring run of 14.11.2026, as wine.log had them (tests/fixtures): what the run's
    /// report said of them. The list's script reads the same file and has to say the same (tests/test_laeuft_liste.py):
    /// a session of play is measured by the script, with this arithmetic.
    static func measuringRunFixture() {
        guard let log = try? String(contentsOf: URL(fileURLWithPath: "tests/fixtures/messlauf-2026-11-14.log"), encoding: .utf8) else {
            check(false, "tests/fixtures/messlauf-2026-11-14.log not found from the repository's root")
            return
        }
        var guardians = GameTest.Frames(average: 49.8, low: 29.3, periods: 19, seconds: 191, slowestFrame: 616.7, slowestTypical: 21.8, source: "metal-hud")
        guardians.onePercentLow = 26.7
        guardians.gpuTime = 18.7
        let hud = GameTest.hudSample(in: log).flatMap { GameTest.measuredFrames($0) }
        check(hud == guardians, "Guardians of the Galaxy by the HUD's lines, as the report had it: \(String(describing: hud))")
        let rate = GameTest.wineFrames(GameTest.wineRates(in: log, programs: ["left4dead2.exe"]))
        check(rate == GameTest.Frames(average: 23.9, low: 23.3, periods: 17, seconds: 186, source: "wine-fps"),
              "Left 4 Dead 2 by Wine's fps channel, as the report had it: \(String(describing: rate))")
        check(GameTest.held(of: "Marvel's Guardians of the Galaxy", in: log)?.frameLimit == 60 && GameTest.held(of: "Left 4 Dead 2", in: log)?.frameLimit == 0,
              "each start's limit line")
    }

    /// A free number that hardly moved is a film's or a lock's pace: no frame rate that counts, and no low one.
    static func steadyRates() {
        func entry(_ way: String, limit: Int?, _ average: Double, _ low: Double, seconds: Double = 186, outcome: GameTest.Outcome = .picture) -> GameTest.Entry {
            var entry = GameTest.Entry(candidate("steam.550", "Left 4 Dead 2", .steam), outcome: outcome)
            entry.way = way
            entry.frames = GameTest.Frames(average: average, low: low, periods: 17, seconds: seconds)
            if let limit {
                entry.measure = GameTest.Measure(window: "1512×982")
                entry.measure?.frameLimit = limit
            }
            entry.load = GameTest.Load(average: 2, cores: 10)
            return entry
        }
        // The night of 14.11.2026: Left 4 Dead 2's intro film at 24 frames a second for the whole measuring.
        let film = entry("wined3d", limit: 0, 23.9, 23.3)
        let checked = GameTest.check(film, playSeconds: 190, onBattery: false, lowPower: false)
        check(GameTest.steady(film) && checked?.start == "ok" && checked?.fps == "steady" && checked?.done == false,
              "a steady free number is no frame rate that counts: \(String(describing: checked))")
        check(GameTest.issues(endedWhilePlaying: false, frames: film.frames, steady: true).isEmpty
              && GameTest.issues(endedWhilePlaying: false, frames: film.frames) == ["lowFrameRate"]
              && GameTest.issues(endedWhilePlaying: true, frames: film.frames, steady: true) == ["crashed"], "… and not a low one")
        check(GameTest.framesText(film) == "24 / 23 (starr)" && GameTest.checkWords["steady"]?.hasPrefix("starrer Wert") == true, "said in the report")
        // A number that moves is one; so is a short one, one under a limit that holds, one without its limit on record.
        check(!GameTest.steady(entry("wined3d", limit: 0, 119.5, 112.4)) && !GameTest.steady(entry("wined3d", limit: 0, 23.9, 23.3, seconds: 45))
              && !GameTest.steady(entry("dxmt", limit: 60, 59.9, 58.7)) && !GameTest.steady(entry("wined3d", limit: nil, 23.9, 23.3))
              && !GameTest.steady(entry("wined3d", limit: 0, 23.9, 23.3, outcome: .hang)), "what isn't steady")
        check(GameTest.check(entry("dxmt", limit: 60, 59.9, 58.7), playSeconds: 190, onBattery: false, lowPower: false)?.fps == "ok",
              "under a limit that holds a steady rate is the point")
        // Where the limit doesn't count the number is free: on D3DMetal, and past a limit by more than 5 %.
        check(GameTest.steady(entry("d3dmetal", limit: 60, 201, 198)) && GameTest.steady(entry("dxmt -dx11", limit: 60, 74, 73))
              && !GameTest.steady(entry("dxmt", limit: 60, 63, 62)), "free without a limit that holds")
        check(GameTest.check(film, playSeconds: 190, onBattery: true, lowPower: false)?.fps == "throttled", "battery is said before steadiness")
    }

    /// Wine's fps channel as the measuring run of 14.11.2026 wrote it (Left 4 Dead 2, the game's path shortened):
    /// two kinds of line for each stretch, with the same rate. Only Direct3D's counts – the other one, from Wine's
    /// OpenGL side, has no swapchain and ends on a total – so nothing goes into the average twice.
    static func wineFpsAsSeen() {
        let night = """
            25027.990:029c:02a0:trace:fps:wglSwapBuffers @ approx 0.00fps, total 0.00fps
            25595.556:06e4:06f0:trace:loaddll:build_module Loaded L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Left 4 Dead 2\\\\left4dead2.exe" at 00400000: native
            25603.617:06e4:0030:trace:fps:wglSwapBuffers @ approx 0.00fps, total 0.00fps
            25603.617:06e4:0030:trace:fps:wined3d_cs_exec_present 0A8D1530 @ approx 0.00fps
            25605.152:06e4:0030:trace:fps:wglSwapBuffers @ approx 23.45fps, total 24.10fps
            25605.152:06e4:0030:trace:fps:wined3d_cs_exec_present 0A8D1530 @ approx 23.45fps
            25606.687:06e4:0030:trace:fps:wglSwapBuffers @ approx 23.45fps, total 23.78fps
            25606.687:06e4:0030:trace:fps:wined3d_cs_exec_present 0A8D1530 @ approx 23.45fps
            25608.196:06e4:0030:trace:fps:wglSwapBuffers @ approx 23.19fps, total 23.59fps
            25608.196:06e4:0030:trace:fps:wined3d_cs_exec_present 0A8D1530 @ approx 23.19fps
            25609.747:06e4:0030:trace:fps:wglSwapBuffers @ approx 23.21fps, total 23.49fps
            25609.747:06e4:0030:trace:fps:wined3d_cs_exec_present 0A8D1530 @ approx 23.21fps
            """
        let rates = GameTest.wineRates(in: night, programs: ["left4dead2.exe"])
        check(rates.map(\.fps) == [23.45, 23.45, 23.19, 23.21], "one rate for each stretch, the swapchain's first line left out: \(rates)")
        let seconds = rates.map(\.seconds).reduce(0, +)
        check(abs(seconds - 6.13) < 0.001, "each by the time since the line before: \(seconds)")
        let frames = GameTest.wineFrames(rates)
        check(frames.map { abs($0.average - 23.3) < 0.05 } == true && frames?.seconds == 6.1 && frames?.source == "wine-fps",
              "the average of the four, not of eight: \(String(describing: frames))")
        // The OpenGL side's lines alone are no rate of the game's.
        let openGLOnly = night.split(separator: "\n").filter { !$0.contains("wined3d_cs_exec_present") }.joined(separator: "\n")
        check(GameTest.wineRates(in: openGLOnly, programs: ["left4dead2.exe"]).isEmpty, "wglSwapBuffers' lines don't count")
    }

    /// Wine's own Direct3D through Wine's fps channel (WINEDEBUG=+fps): the lines as Wine 11.17 writes them
    /// (dlls/wined3d/cs.c "%p @ approx %.2ffps", the header of dlls/ntdll/unix/debug.c).
    static func wineFps() {
        let game: Set<String> = ["ShippingPC-BmGame.exe", "BmLauncher.exe"]
        func load(_ time: String, _ pid: String, _ path: String) -> String {
            "\(time):\(pid):0804:trace:loaddll:build_module Loaded L\"\(path)\" at 0000000140000000: native"
        }
        func rate(_ time: String?, _ pid: String?, _ swapchain: String, _ fps: String, function: String = "wined3d_cs_exec_present") -> String {
            (time.map { $0 + ":" } ?? "") + (pid.map { $0 + ":" } ?? "") + "0124:trace:fps:\(function) \(swapchain) @ approx \(fps)fps"
        }
        // All four channels: Steam's helper presents through Wine's Direct3D too, and more often than the game.
        var lines = [load("253517.239", "0294", "C:\\\\Program Files (x86)\\\\Steam\\\\bin\\\\cef\\\\steamwebhelper.exe"),
                     load("253518.000", "0810", "Z:\\\\Volumes\\\\Games\\\\Batman\\\\Binaries\\\\ShippingPC-BmGame.exe"),
                     "253518.010:0810:0804:trace:loaddll:build_ntdll_module Loaded L\"C:\\\\windows\\\\system32\\\\ntdll.dll\" at 00006FFFFFF90000: builtin",
                     "253518.020:0810:0804:trace:loaddll:build_module Loaded L\"C:\\\\windows\\\\system32\\\\wined3d.dll\" at 00006FFFFE110000: builtin"]
        for step in 0..<40 { lines.append(rate(String(format: "%.3f", 253519.0 + Double(step)), "0294", "0000000000A1B2C0", "30.00")) }
        lines.append(rate("253520.000", "0810", "00000000012A3B40", "0.00"))  // the swapchain's first line: since Wine's start
        for step in 1...8 { lines.append(rate(String(format: "%.3f", 253520.0 + 1.5 * Double(step)), "0810", "00000000012A3B40", "60.00")) }
        lines.append(rate("253535.000", "0810", "00000000012A3B40", "20.00"))  // three seconds without a line: a slow stretch
        for step in 1...6 { lines.append(rate(String(format: "%.3f", 253535.0 + 1.5 * Double(step)), "0810", "00000000012A3B40", "60.00")) }
        lines.append("253520.500:0810:0124:fixme:d3d:wined3d_check_device_format_conversion output is 0000000000000000 @ approx nothing")
        let full = lines.joined(separator: "\n")
        let rates = GameTest.wineRates(in: full, programs: game)
        check(rates.count == 15 && rates.first == GameTest.WineRate(fps: 60, seconds: 1.5) && rates[8].fps == 20
              && abs(rates[8].seconds - 3) < 0.001, "the game's swapchain, each rate with the time since the line before: \(rates.count) \(rates.prefix(1))")
        let frames = GameTest.wineFrames(rates)
        // 14 × 1.5 s at 60 and 3 s at 20: 1320 frames in 24 s. Stretches: 7 × 1.5 s at 60, then 1.5 + 3 + 4 × 1.5 s with 510 frames.
        check(frames?.average == 55 && frames?.seconds == 24 && frames?.periods == 2 && frames?.low == 48.6 && frames?.source == "wine-fps",
              "the average by time, the lowest ten seconds: \(String(describing: frames))")
        check(frames?.slowestFrame == nil && frames?.slowestTypical == nil && frames?.onePercentLow == nil && frames?.gpuTime == nil,
              "a rate says nothing of single frames: no slowest frame, no slowest percent")
        check(GameTest.slowestText(frames) == "nicht gemessen", "… and the report says so")
        // Without +timestamp: each rate stands for the 1.5 s the channel waits at least.
        let untimed = [load("1", "0810", "C:\\\\Game\\\\BmLauncher.exe").dropFirst(2).description,
                       rate(nil, "0810", "012A3B40", "0.03"), rate(nil, "0810", "012A3B40", "59.94"), rate(nil, "0810", "012A3B40", "30.06")]
        let plain = GameTest.wineRates(in: untimed.joined(separator: "\n"), programs: game)
        check(plain == [GameTest.WineRate(fps: 59.94, seconds: 1.5), GameTest.WineRate(fps: 30.06, seconds: 1.5)], "no times: 1.5 s each: \(plain)")
        check(GameTest.wineFrames(plain)?.average == 45 && GameTest.wineFrames(plain)?.periods == 1 && GameTest.wineFrames(plain)?.seconds == 3,
              "less than ten seconds: one stretch of all there is")
        // Neither +pid nor +loaddll: nobody says whose a line is – the swapchain with the most lines.
        let bare = (0..<5).map { _ in rate(nil, nil, "00A1B2C0", "30.00") } + (0..<9).map { _ in rate(nil, nil, "012A3B40", "60.00") }
        check(GameTest.wineRates(in: bare.joined(separator: "\n"), programs: game) == Array(repeating: GameTest.WineRate(fps: 60, seconds: 1.5), count: 8),
              "without a process: whoever logged most, its first line left out")
        // Only another program's process logged, and its load says so: not the game's rate.
        let foreign = [load("10.000", "0294", "C:\\\\Steam\\\\steamwebhelper.exe")] + (0..<6).map { rate("\(20 + $0).000", "0294", "00A1B2C0", "30.00") }
        check(GameTest.wineRates(in: foreign.joined(separator: "\n"), programs: game).isEmpty && GameTest.wineFrames([]) == nil,
              "Steam's window alone: nothing measured")
        // Wine hands a pid out again: what a helper logged under it isn't the game's, what the game logs after its own load is.
        let reused = [load("10.000", "0810", "C:\\\\windows\\\\system32\\\\conhost.exe"), rate("11.000", "0810", "00A1B2C0", "5.00"), rate("12.500", "0810", "00A1B2C0", "5.00"),
                      rate("14.000", "0810", "00A1B2C0", "5.00"), rate("15.500", "0810", "00A1B2C0", "5.00"),
                      load("20.000", "0810", "D:\\\\Batman\\\\Binaries\\\\shippingpc-bmgame.EXE"), rate("21.000", "0810", "00A1B2C0", "0.00"),
                      rate("22.500", "0810", "00A1B2C0", "58.00"), rate("24.000", "0810", "00A1B2C0", "62.00")]
        check(GameTest.wineRates(in: reused.joined(separator: "\n"), programs: game).map(\.fps) == [58, 62], "a pid from one program's load to the next")
        // Whatever function Wine names (it moved between versions), and a second, smaller swapchain beside the game's.
        let other = [rate("1.000", "0810", "012A3B40", "0.00", function: "swapchain_gl_present"), rate("2.500", "0810", "012A3B40", "40.00", function: "swapchain_gl_present"),
                     rate("2.600", "0810", "0FFFF000", "0.00"), rate("4.000", "0810", "012A3B40", "41.00", function: "swapchain_gl_present"),
                     rate("4.100", "0810", "0FFFF000", "1.00"), rate("5.500", "0810", "012A3B40", "42.00", function: "wined3d_swapchain_present")]
        check(GameTest.wineRates(in: other.joined(separator: "\n"), programs: game).map(\.fps) == [40, 41, 42], "read by channel and text, the swapchain with the most lines")
        check(GameTest.wineRates(in: "0124:trace:fps:x 00 @ approx fastfps\n0124:err:fps:x 00 @ approx\ninfo:  [nightforge] fps", programs: game).isEmpty,
              "lines that are none")
        // The switch, and what a picture without a rate says with it.
        check(GameTest.wineFpsOn("+fps,+pid,+loaddll,+timestamp") && GameTest.wineFpsOn("+pid,+fps") && !GameTest.wineFpsOn("+loaddll,+timestamp,+pid")
              && !GameTest.wineFpsOn(nil) && !GameTest.wineFpsOn("-fps") && !GameTest.wineFpsOn("+fpsx"), "Wine's fps channel among the switch's channels")
        check(GameTest.noFrames(way: "wined3d", wineFps: true) == .noneInLog && GameTest.noFrames(way: "wined3d", frameLog: true) == .wayReportsNone
              && GameTest.noFrames(way: "mac", frameLog: true, wineFps: true) == .wayReportsNone
              && GameTest.noFrames(way: "d3dmetal", wineFps: true) == .wayReportsNone && GameTest.noFrames(way: "d3dmetal", frameLog: true, wineFps: true) == .noneInLog,
              "with the channel on Wine's own Direct3D reports; a Mac version never, D3DMetal by the HUD's log")
        check(GameTest.measure(of: "Batman", way: "wined3d", in: "", frames: nil, held: nil, wineFps: true).noFrames == "noneInLog", "… and the measure says so")
        // Done with a WineD3D game: a clean start and the rate Wine gave.
        var batman = GameTest.Entry(candidate("steam.35140", "Batman", .steam), outcome: .picture)
        batman.ways = [GameTest.Way(way: "wined3d", outcome: .picture)]
        batman.way = "wined3d"
        batman.frames = frames
        batman.measure = GameTest.measure(of: "Batman", way: "wined3d", in: "", frames: frames, held: GameTest.Held(frameLimit: 0, refreshRate: 120, metalFX: false), wineFps: true)
        check(GameTest.check(batman, playSeconds: 190, onBattery: false, lowPower: false) == GameTest.Check(start: "ok", fps: "ok"), "a rate from Wine counts as one")
        check(GameTest.framesText(batman) == "55 / 49", "… in the report as any other: \(GameTest.framesText(batman))")
        batman.frames = nil
        batman.measure?.noFrames = "wayReportsNone"
        check(GameTest.framesText(batman) == "nicht gemessen (WineD3D meldet keine ohne Wines fps-Kanal)", "without the channel: said why")
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
        // Steam's own window presents through Metal too, and may log more than a game at 30 FPS: the game's processes count.
        let busySteam = (0..<10).map { "wine[500:1] metal-HUD: \($0 * 60),1.0,2.0," + Array(repeating: "16.67,1.00", count: 60).joined(separator: ",") }
            + (0..<10).map { "wine[777:1] metal-HUD: \($0 * 30),1.0,2.0," + Array(repeating: "33.33,9.00", count: 30).joined(separator: ",") }
        let both = busySteam.joined(separator: "\n")
        check(GameTest.hudSample(in: both)?.intervals.first == 16.67, "without the game's processes: whoever logged most")
        check(GameTest.hudSample(in: both, processes: [777, 778])?.intervals == Array(repeating: 33.33, count: 300), "with them: the game's frames")
        check(GameTest.hudSample(in: both, processes: [42])?.intervals.first == 16.67, "none of them logged: whoever logged most, as before")
        // The switch: a game test's starts log frames unless told not to; a start by Play never does.
        let defaults = TestDefaults.suite("frameLog")
        check(GameTest.logsFrames(active: true, defaults: defaults) && !GameTest.logsFrames(active: false, defaults: defaults),
              "on in a game test, off outside one")
        defaults.set(false, forKey: GameTest.Keys.frameLog)
        check(!GameTest.logsFrames(active: true, defaults: defaults), "gameTest.frameLog false: off in a game test too")
        defaults.set(true, forKey: GameTest.Keys.frameLog)
        check(GameTest.logsFrames(active: true, defaults: defaults) && !GameTest.logsFrames(active: false, defaults: defaults),
              "set to true: still only in a game test")
        // Measuring play is a hidden switch of its own: without it no start by Play logs a frame, whatever else is set.
        let play = TestDefaults.suite("gameTest.measurePlay")
        check(!GameTest.measuresPlay(defaults: play) && !GameTest.logsFrames(active: false, defaults: play), "no switch: a start by Play logs nothing")
        play.set(false, forKey: GameTest.measurePlayKey)
        check(!GameTest.measuresPlay(defaults: play) && !GameTest.logsFrames(active: false, defaults: play), "set to false: nothing either")
        play.set("yes please", forKey: GameTest.measurePlayKey)
        play.set(true, forKey: GameTest.Keys.frameLog)
        check(!GameTest.logsFrames(active: false, defaults: play), "the game test's own switch doesn't reach a start by Play")
        play.set(true, forKey: GameTest.measurePlayKey)
        check(GameTest.measuresPlay(defaults: play) && GameTest.logsFrames(active: false, defaults: play), "the switch on: a start by Play logs its frames")
        play.set(false, forKey: GameTest.Keys.frameLog)
        check(GameTest.logsFrames(active: true, defaults: play), "… and a game test's start does then too")
        check(GameTest.measurePlayKey == "gameTest.measurePlay", "the switch's name, as the rules give it")
        let began = Date(timeIntervalSince1970: 1794773429)
        check(GameTest.playNote(game: "Control", at: began, onBattery: false, lowPower: false, load: GameTest.Load(average: 2.14, cores: 10))
              == "Play measuring of Control: 2026-11-15T20:10:29Z, on mains, load 2.1 on 10 cores", "when a measured session began, and under what")
        check(GameTest.playNote(game: "Control", at: began, onBattery: true, lowPower: true, load: nil)
              == "Play measuring of Control: 2026-11-15T20:10:29Z, on battery, Low Power Mode", "on battery, in Low Power Mode, without a load")

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
        check(summary.contains("## Messwerte") && summary.contains("(60 s nach dem ersten Bild)")
              && summary.contains("Das 1-%-Tief gibt es nur aus Apples Metal-HUD-Protokoll"), "what the measures stand for")
        check(summary.contains("| Overcooked 2 | dxmt | 60 FPS | 1512×982@120 (Modus des Spiels) | 60 / 41 über 50 s | – | üblich 24 ms, schlimmster 310 ms |"),
              "a measured row:\n\(summary)")
        check(summary.contains("| Control \\| Ultimate | d3dmetal | keins | Fenster 1512×982 Punkte | nicht gemessen (D3DMetal meldet keine) | – | nicht gemessen |"),
              "a row of a way that reports nothing")
        check(summary.contains("| Valheim | dxmt | nicht gemessen | nicht gemessen | 31 / 12 (Last hoch) | – | nicht gemessen |"), "a row without a measure")
        // D3DMetal has nothing that holds a limit: the row says what was asked for, not that it held.
        var underLimit = GameTest.Measure()
        underLimit.frameLimit = 60
        check(GameTest.limitText(underLimit, way: "d3dmetal") == "keins möglich (verlangt: 60 FPS)"
              && GameTest.limitText(underLimit, way: "dxmt -dx11") == "60 FPS" && GameTest.limitText(nil, way: "d3dmetal") == "nicht gemessen",
              "a limit D3DMetal was underLimit for is no limit it holds")
        underLimit.frameLimit = 0
        check(GameTest.limitText(underLimit, way: "d3dmetal") == "keins" && GameTest.limitText(underLimit, way: "wined3d") == "keins", "no limit underLimit for: none")
        // With the HUD's frame log: the run says so, D3DMetal had its chance, and a HUD's frames carry the slowest percent.
        check(!summary.contains("Metal-HUD hat die Frames mitgeschrieben"), "no frame log: no word of it")
        var logged = report
        logged.frameLog = true
        if let index = logged.games.firstIndex(where: { $0.game == "Control | Ultimate" }) {
            logged.games[index].measure?.noFrames = "noneInLog"
        }
        if let index = logged.games.firstIndex(where: { $0.game == "Overcooked 2" }) {
            logged.games[index].frames?.onePercentLow = 48.4
        }
        let loggedSummary = GameTest.summary(logged)
        check(loggedSummary.contains("Apples Metal-HUD hat die Frames mitgeschrieben (unsichtbar, wo die Leistungsanzeige aus ist)"), "the frame log said in the report")
        check(loggedSummary.contains("| Control \\| Ultimate | d3dmetal | keins | Fenster 1512×982 Punkte | nicht gemessen (keine im Log) | – | nicht gemessen |"),
              "D3DMetal with the frame log on and no lines: none in the log, not a way that reports none\n\(loggedSummary)")
        check(loggedSummary.contains("| 60 / 41 über 50 s | 48 FPS | üblich 24 ms, schlimmster 310 ms |"), "the slowest percent where the HUD gave it")
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
        check(summary.contains("| Overcooked 2 | Windows | 8,5 GB | ja | 60 / 41 | Start geprüft |"), "a clean start, with the first minutes beside it\n\(summary)")
        check(summary.contains("| Control \\| Ultimate | Windows | 48,4 GB | ja | der Weg meldet keine | Start geprüft |"), "a start without frames is checked all the same")
        check(summary.contains("| Spiel | Fassung | Größe | Start geprüft | In den ersten Minuten | Fazit |") && summary.contains("kein Leistungswert")
              && !summary.contains("fertig") && !summary.contains("fehlt: FPS") && !summary.contains("fehlt: Start"),
              "the first minutes are named as that, and nothing is called missing or done")
        check(summary.contains("| Shooter | Windows | 1,5 GB | – | – | nicht gestartet: bräuchte erst Laufzeiten (würde laden) |"), "skipped for something that can be mended")
        check(summary.contains("Start geprüft in diesem Lauf: 2 von 10 Spielen, zusammen 56,9 GB."), "what the ticks free:\n\(summary.components(separatedBy: "## Abhakliste").last ?? "")")
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
