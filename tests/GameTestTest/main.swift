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
        print("✓ GameTest: switches, order, looks, outcomes, ways, frames, sample, calm, report")
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
        check(GameTest.helperPressedPlay(in: "info:  [nightforge] Unity's window \"The Forest Configuration\": pressed Play!\n"),
              "the helper's line: it pressed Play!")
        check(!GameTest.helperPressedPlay(in: "info:  [nightforge] Unity's window: didn't come up\n"), "no window, nothing pressed")
        // Two minutes without a process list (ps not answering): nothing is known – not "no-start" (review 3.11.).
        check(GameTest.outcome(.init(process: true, unknown: true)) == .unknown && GameTest.result(.unknown, issues: []) == nil,
              "no process list: unknown, no result for the compatibility list")
        check(GameTest.outcome(.init(unknown: true)) == .unknown, "not noStart either, although no process was seen")
        check(GameTest.outcome(.init(process: true, picture: true, unknown: true)) == .picture, "a picture before the list went: a picture")
        check(GameTest.blindLooks == 120, "two minutes of looks, one a second")
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
        var dxmt = GameTest.Entry(candidate("steam.728880", "Overcooked 2", .steam), outcome: .picture)
        dxmt.way = "dxmt"
        dxmt.frames = GameTest.Frames(average: 59.6, low: 41, periods: 5)
        dxmt.result = "good"
        dxmt.load = GameTest.Load(average: 1.5, cores: 10)
        var busy = GameTest.Entry(candidate("steam.892970", "Valheim", .steam), outcome: .picture)
        busy.way = "dxmt"
        busy.frames = GameTest.Frames(average: 31, low: 12, periods: 5)
        busy.result = "good"
        busy.load = GameTest.Load(average: 38.2, cores: 10)
        var skipped = GameTest.Candidate(key: "steam.9", name: "Shooter", store: .steam, storeID: "9", platform: .windows,
                                         skip: .runtimes, skipNote: "fehlt: vcrun2019")
        skipped.notYet = true
        let started = Date(timeIntervalSince1970: 1_793_664_720)  // 2026-11-03 00:12 UTC
        var report = GameTest.Report(started: started, finished: started.addingTimeInterval(3600), nightforge: "0.3.1",
                                     engine: ["winecx@4.7.3", "dxmt@0.80"], mac: "Apple M5 · macOS 26.1",
                                     pictureWait: 120, playSeconds: 60)
        report.load = GameTest.Load(average: 2.04, cores: 10)
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
        report.games = [dxmt, busy, good, hung.redacted(home: home, user: "jdoe"), dialog, forest, blind, asked, .skipped(skipped, .runtimes),
                        GameTest.Entry(candidate("steam.1", "Store", .steam), outcome: .needsPlayer, skip: .signIn)]

        let json = GameTest.json(report)
        let text = String(decoding: json, as: UTF8.self)
        check(!GameTest.leaks(text, home: home, user: "jdoe"), "the report keeps no home folder or account name")
        check(GameTest.leaks("C:\\\\users\\\\jdoe\\\\x", home: home, user: "jdoe") && GameTest.leaks("\(home)/x", home: home, user: "jdoe"),
              "a path with the account name is caught")
        check(!GameTest.leaks("users/jdoey and Thomas Was Alone", home: home, user: "jdoe"), "another account, a game's name: no leak")
        check(GameTest.report(from: json) == report, "report.json reads back as written")
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let first = (object?["games"] as? [[String: Any]])?.first
        check(object?["formatVersion"] as? Int == 1, "format 1")
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
        check(summary.contains("| Control \\| Ultimate | Epic Games | Windows | d3dmetal | Bild | 34 s | – (D3DMetal meldet keine) |"),
              "a table row, its pipe escaped")
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
