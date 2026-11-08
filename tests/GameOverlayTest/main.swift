// Checks the controller overlay's parts that work without a screen: the two-second hold, its steps,
// which processes belong to a game, and pausing and ending a stand-in game's process tree:
// tests/GameOverlayTest/run.sh
import CoreGraphics
import Foundation

@main
struct GameOverlayTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        // No real process list: a hanging ps on this Mac doesn't stop the series (tests/Shared/FakeProcesses.swift).
        FakeProcesses.installEmpty()
        hold()
        steps()
        targets()
        presence()
        firstSeconds()
        windows()
        curtain()
        wayBack()
        curtainLines()
        brandArt()
        standIn()
        if failures == 0 { print("✓ GameOverlay: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }

    /// Both sticks – or ☰ and ⧉ on a pad without stick buttons – held for two seconds, once per hold.
    static func hold() {
        // Which buttons count: never the PS/Xbox button (Apple's Game Overlay) or Create alone.
        check(OverlayHold.chord(leftStick: true, rightStick: true, menu: false, view: false), "both sticks pressed")
        check(!OverlayHold.chord(leftStick: true, rightStick: false, menu: true, view: true), "one stick, even with ☰ and ⧉: no")
        check(!OverlayHold.chord(leftStick: false, rightStick: false, menu: true, view: true),
              "☰ and ⧉ don't count on a pad with stick buttons (Create carries macOS's share gestures)")
        check(OverlayHold.chord(leftStick: nil, rightStick: nil, menu: true, view: true), "a pad without stick buttons: ☰ and ⧉")
        check(!OverlayHold.chord(leftStick: nil, rightStick: nil, menu: true, view: false), "☰ alone: the game's menu")

        var hold = OverlayHold()
        check(!hold.update(pressed: true, now: 100), "pressed: not yet")
        check(hold.due == 102, "due two seconds after the press")
        check(!hold.update(pressed: true, now: 101.5), "1.5 s: not yet")
        check(hold.update(pressed: true, now: 102), "2 s: the overlay")
        check(hold.due == nil, "nothing due once it fired")
        check(!hold.update(pressed: true, now: 105), "held on: only once")
        check(!hold.update(pressed: false, now: 106), "let go")
        check(hold.since == nil, "let go: no hold")
        check(!hold.update(pressed: true, now: 107), "held again: the next hold starts")
        check(hold.update(pressed: true, now: 109), "and fires again after two seconds (closing the overlay)")

        var short = OverlayHold()
        _ = short.update(pressed: true, now: 0)
        _ = short.update(pressed: false, now: 0.5)
        check(!short.update(pressed: true, now: 1.75), "a short press (a game's own use) doesn't count towards the next")
        check(!short.update(pressed: true, now: 3.5), "the new press counts from its own start")
        check(short.update(pressed: true, now: 3.75), "two seconds after the new press")
    }

    /// B steps back, the PS button goes back to the game, a game is only quit from the question.
    static func steps() {
        typealias T = (OverlayStep, GameOverlay.Effect)
        func expect(_ from: OverlayStep, _ event: OverlayEvent, _ result: T, _ message: String) {
            let got = GameOverlay.transition(from, event)
            check(got.0 == result.0 && got.1 == result.1, message + " (\(got))")
        }
        expect(.menu, .back, (.menu, .close), "B in the choice: back to the game")
        expect(.menu, .resume, (.menu, .close), "Continue Playing or the sticks held again: back to the game")
        expect(.menu, .askQuit, (.confirmQuit, .none), "Quit Game asks first")
        expect(.menu, .restart, (.quitting, .restart), "Restart Game after a late controller: ends and starts again, no question")
        expect(.confirmQuit, .restart, (.confirmQuit, .none), "no restart from the quit question")
        expect(.menu, .quit, (.menu, .none), "no quitting without the question")
        expect(.menu, .nightforge, (.menu, .nightforge), "Go to Nightforge")
        expect(.confirmQuit, .back, (.menu, .none), "B in the question: back to the choice")
        expect(.confirmQuit, .resume, (.confirmQuit, .close), "the sticks held in the question: back to the game")
        expect(.confirmQuit, .quit, (.quitting, .quit), "confirmed: quitting")
        expect(.confirmQuit, .nightforge, (.confirmQuit, .none), "the question first")
        for event in [OverlayEvent.back, .resume, .askQuit, .quit, .nightforge] {
            expect(.quitting, event, (.quitting, .none), "while quitting nothing else (\(event))")
        }
        // "Not starting?" over the curtain: keep waiting, go to Nightforge, or quit after the question.
        expect(.notStarting, .resume, (.notStarting, .close), "Keep Waiting: the curtain stays, the question goes")
        expect(.notStarting, .back, (.notStarting, .close), "B: keep waiting too")
        expect(.notStarting, .nightforge, (.notStarting, .nightforge), "Go to Nightforge")
        expect(.notStarting, .askQuit, (.confirmQuit, .none), "Quit Game asks first here too")
        expect(.notStarting, .quit, (.notStarting, .none), "no quitting without the question")
        // The highlight starts on the safe answer, by its id: the first press already answers.
        check(GameOverlay.defaultButton(.menu) == "overlay.continue", "the choice: Continue Playing")
        check(GameOverlay.defaultButton(.notStarting) == "overlay.wait", "\"Not starting?\": Keep Waiting")
        check(GameOverlay.defaultButton(.confirmQuit) == "overlay.cancel", "the question: Cancel")
        check(GameOverlay.defaultButton(.quitting) == nil, "quitting: nothing to press")
    }

    /// Which processes are the game's: its folder, what it started, never the Wine session or Steam.
    static func targets() {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("processes.txt")
        let table = GameProcesses.parse((try? String(contentsOf: fixture, encoding: .utf8)) ?? "")
        check(table.count == 19, "the ps fixture reads as 19 processes (\(table.count))")
        let l4d2 = GameProcesses.targets(windows: #"\steamapps\common\Left 4 Dead 2\"#, mac: nil, in: table, me: 401)
        check(l4d2 == [7000, 7010, 7030], "Left 4 Dead 2: the game, its crash handler and what that started – not conhost, not Left 4 Dead (\(l4d2))")
        let overcooked = GameProcesses.targets(windows: #"\Epic Games\Overcooked2\"#, mac: nil, in: table, me: 401)
        check(overcooked == [8000, 8010], "an Epic game (\(overcooked))")
        let nms = GameProcesses.targets(windows: nil, mac: "/Users/tester/Library/Application Support/Steam/steamapps/common/No Man's Sky",
                                        in: table, me: 401)
        check(nms == [9000, 9010], "a Mac game and its helper, not a shell that only names the folder (\(nms))")
        check(GameProcesses.targets(windows: #"\steamapps\common\Gone\"#, mac: nil, in: table, me: 401).isEmpty, "a game that isn't running")
        check(GameProcesses.targets(windows: nil, mac: nil, in: table, me: 401).isEmpty, "nothing to go by")
        // In front while the curtain watches: another Windows program is the game's side, Steam isn't.
        check(GameProcesses.windowsCompanion(7010, in: table), "a Windows game's helper in front: the game's side")
        check(GameProcesses.windowsCompanion(8000, in: table), "an Epic game's program")
        check(!GameProcesses.windowsCompanion(6100, in: table), "Steam's window (a question, its sign-in) is Steam's")
        check(!GameProcesses.windowsCompanion(6110, in: table), "nor its web helper")
        check(!GameProcesses.windowsCompanion(9000, in: table), "a Mac app is another app")
        check(!GameProcesses.windowsCompanion(401, in: table), "Nightforge isn't")
        check(!GameProcesses.windowsCompanion(4242, in: table), "a process gone meanwhile isn't")
        // Steam started the game, but the game didn't start Steam: Steam and the Wine session stay.
        for spared: pid_t in [1, 401, 6058, 6060, 6070, 6080, 6100, 6110, 900] {
            check(!(l4d2 + overcooked + nms).contains(spared), "\(spared) is spared")
        }

        // Control (Epic, 2.11.): its launcher starts the game by its bare name, and Wine starts every
        // program with launchd as its parent – once the launcher ended, the game counted as ended.
        // Its working folder is the game's (winecx's spawn_process).
        let control = #"\Epic Games\Control\"#
        let prefix = "/Users/tester/Library/Application Support/Nightforge/Prefix/drive_c/Program Files/Epic Games"
        func runs(_ command: String, _ cwd: String?, _ folder: String = control) -> Bool {
            GameProcesses.runsFrom([folder], command: command, cwd: cwd)
        }
        check(runs(#"C:\Program Files\Epic Games\Control\Control.exe -epicapp=Calluna"#, nil), "the launcher by its Windows path")
        check(runs("Control_DX11.exe -AUTH_LOGIN=unused -epicapp=Calluna", prefix + "/Control"), "the game by its bare name, in its folder")
        check(runs("Control_DX11.exe", prefix + "/Control/data"), "in a folder of the game's")
        check(runs("Control_DX11.exe", "/Volumes/T7/Nightforge Games/Epic Games/Control"), "on an external drive")
        check(!runs("Control_DX11.exe", prefix + "/Control Ultimate"), "not another game's folder that starts the same")
        check(!runs("Control_DX11.exe", "/Users/tester"), "not one elsewhere")
        check(!runs("Control_DX11.exe", nil), "not without a working folder")
        check(!runs(#"C:\windows\system32\start.exe /unix Control.exe"#, prefix + "/Control"), "not Windows' own programs")
        check(!runs(#"C:\Program Files (x86)\Steam\gameoverlayui.exe -pid 7000"#, prefix + "/Control"), "not Steam's")
        check(!runs("/bin/zsh", prefix + "/Control"), "not a Mac program in the folder")
        check(runs("Game.exe", "/Users/tester/Library/Application Support/Nightforge/Prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Hades",
                   #"\steamapps\common\Hades\"#), "a Steam game too")
        check(GameProcesses.runsFrom(GameProcesses.gameFolders, command: "Control_DX11.exe", cwd: prefix + "/Control"),
              "any game's folder (Engine.windowsGameRunning)")
        let launched = [GameProcesses.Entry(pid: 6100, parent: 1, command: #"C:\Program Files (x86)\Steam\steam.exe -silent"#,
                                            cwd: "/Users/tester/Library/Application Support/Nightforge/Prefix/drive_c/Program Files (x86)/Steam"),
                        GameProcesses.Entry(pid: 7100, parent: 1, command: "Control_DX11.exe -AUTH_LOGIN=unused", cwd: prefix + "/Control"),
                        GameProcesses.Entry(pid: 7110, parent: 1, command: #"C:\windows\system32\conhost.exe"#, cwd: prefix + "/Control")]
        check(GameProcesses.targets(windows: control, mac: nil, in: launched, me: 401) == [7100], "the overlay and the curtain have the game")
        check(GameProcesses.running([control.lowercased(): "epic:Calluna"], in: launched) == ["epic:Calluna": 7100],
              "it counts as running once its launcher has gone")
        check(GameProcesses.running([control.lowercased(): "epic:Calluna"], in: Array(launched.prefix(1))).isEmpty, "gone when it's gone")
    }

    /// What the curtain waits for: a window of a game's size from one of the game's processes.
    /// A game's standing by the process list at hand (review N1): only a list asked for just now says it is gone;
    /// an old one (ps is down) says it runs for a game that was in it, and "not known" for one that wasn't.
    static func presence() {
        let marker = #"\steamapps\common\calluna\"#
        let folders = [marker: "steam.1"]
        let game = FakeProcesses.Row(pid: 4201, command: #"C:\Program Files (x86)\Steam\steamapps\common\Calluna\Calluna.exe"#)
        let other = FakeProcesses.Row(pid: 4202, command: #"C:\windows\system32\services.exe"#)
        defer { FakeProcesses.installEmpty() }
        func standing() -> GameProcesses.Presence { GameProcesses.presence(of: "steam.1", folders: folders) }

        FakeProcesses.install { [other, game] }
        check(standing() == .running(4201), "a list asked for just now with the game: it runs")
        FakeProcesses.install { [other] }
        check(standing() == .gone, "… without it: gone")
        FakeProcesses.installEmpty()
        check(standing() == .gone, "… an empty one: gone")
        FakeProcesses.installOld { [other, game] }
        check(standing() == .running(4201), "an old list (ps is down) with the game: it ran, so it runs")
        FakeProcesses.installOld { [other] }
        check(standing() == .unknown && standing().mayBeRunning,
              "an old list without it: not known – the game may have started after the list was made")
        FakeProcesses.installDown()
        check(standing() == .unknown && standing().mayBeRunning, "no list at all: not known")
        check(!GameProcesses.Presence.gone.mayBeRunning, "only gone is not running")

        // The curtain's look: an old list that doesn't show the game decides nothing (the !seenOnce case).
        func look() -> GameProcesses.CurtainLook? { GameProcesses.curtainLook(marker: marker, folder: nil, front: nil) }
        FakeProcesses.install { [other] }
        check(look() == GameProcesses.CurtainLook(pids: [], companion: false, askers: []), "the curtain: a list just asked for, no game – an empty look")
        FakeProcesses.installOld { [other] }
        check(look() == nil, "the curtain: an old list without the game – nothing decided")
        FakeProcesses.installOld { [other, game] }
        check(look()?.pids == [4201], "the curtain: an old list with the game – it is there")
        FakeProcesses.installDown()
        check(look() == nil, "the curtain: no list – nothing decided")

        // One look is one list (review N4): the game's processes and macOS's askers come from it together.
        let asker = FakeProcesses.Row(pid: 4210, command: "/System/Library/CoreServices/UserNotificationCenter.app/Contents/MacOS/UserNotificationCenter")
        var asked = 0
        FakeProcesses.install {
            asked += 1
            return [other, game, asker]
        }
        let both = look()
        check(asked == 1, "the curtain's look asks for the process list once (\(asked) times)")
        check(both?.pids == [4201] && both?.askers == [4210], "… and has the game's processes and macOS's asker from it")
    }

    /// The first-seconds watch (review N1): a look without an answer counts for neither side.
    static func firstSeconds() {
        typealias Verdict = FirstSecondsWatch.Verdict
        func run(_ looks: [GameProcesses.Presence]) -> (Verdict?, FirstSecondsWatch) {
            var watch = FirstSecondsWatch()
            for look in looks {
                if let verdict = watch.look(look) { return (verdict, watch) }
            }
            return (nil, watch)
        }
        let running = GameProcesses.Presence.running(1), gone = GameProcesses.Presence.gone, unknown = GameProcesses.Presence.unknown

        check(run([running] + Array(repeating: gone, count: 9)).0 == nil, "gone for nine looks: not yet")
        check(run([running] + Array(repeating: gone, count: 10)).0 == .ended, "gone for ten looks in a row: ended")
        check(run([running, gone, gone, gone, running] + Array(repeating: gone, count: 9)).0 == nil, "a gap of a launcher handing over: not ended")
        check(run(Array(repeating: gone, count: 3) + Array(repeating: unknown, count: 5) + Array(repeating: gone, count: 7)).0 == .ended,
              "looks without an answer between don't reset the absence: ten gone in all")
        check(run(Array(repeating: unknown, count: 29)).0 == nil && run(Array(repeating: unknown, count: 30)).0 == .unknown,
              "thirty looks without an answer: unknown, not ended")
        check(run([running, gone, gone, gone] + Array(repeating: unknown, count: 30)).0 == .unknown,
              "an absence that began, then no answer: unknown – not that it ended")

        // At the end of the window: seen running and not gone since → survived; otherwise nothing is known.
        check(run([unknown, unknown, running, unknown]).1.verdictAtEnd == .survived, "seen running, then a blind look: survived")
        check(run(Array(repeating: unknown, count: 20)).1.verdictAtEnd == .unknown, "never an answer: unknown, not survived")
        check(FirstSecondsWatch().verdictAtEnd == .unknown, "no look at all: unknown")

        // Whether the watch goes on: the window, then an absence that is under way.
        var watch = FirstSecondsWatch()
        check(watch.continues(after: 5) && !watch.continues(after: LaunchHealth.failureWindow), "the window, then it ends")
        _ = watch.look(running)
        _ = watch.look(gone)
        check(watch.continues(after: LaunchHealth.failureWindow + 5), "an absence that began goes on past the window")
        for _ in 0..<8 { _ = watch.look(gone) }
        check(watch.continues(after: LaunchHealth.failureWindow + 5), "… until it has lasted ten looks")
        check(watch.look(gone) == .ended && !watch.continues(after: LaunchHealth.failureWindow + 5), "ten looks: over")
    }

    static func windows() {
        func window(_ pid: Int32, _ width: Double, _ height: Double, layer: Int = 0, alpha: Double = 1, number: Int = 1) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowAlpha as String: NSNumber(value: alpha), kCGWindowNumber as String: NSNumber(value: number),
             kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": width, "Height": height] as [String: Any]]
        }
        let game: Set<pid_t> = [7000, 7010]
        check(GameProcesses.showsWindow([window(7000, 1920, 1080)], pids: game), "the game's full-screen window")
        check(GameProcesses.showsWindow([window(7010, 1280, 720)], pids: game), "a window of one of its processes")
        check(!GameProcesses.showsWindow([window(7000, 480, 270)], pids: game), "a splash or a launcher's dialog doesn't count")
        check(!GameProcesses.showsWindow([window(401, 1920, 1080)], pids: game), "Nightforge's own (or Steam's) window doesn't count")
        check(!GameProcesses.showsWindow([window(7000, 1920, 1080, alpha: 0)], pids: game), "an invisible window doesn't count")
        check(!GameProcesses.showsWindow([], pids: game), "nothing on screen yet")
        check(!GameProcesses.showsWindow([window(7000, 1920, 1080)], pids: []), "no processes, no window")

        // Overwatch, 8.11. 13:40: only the captured display's black shield on screen, the real window
        // hidden. Every run with a picture had a window above it (L…630, Control L…629).
        let blackShield = Int(CGShieldingWindowLevel())
        check(!GameProcesses.showsWindow([window(7000, 1512, 982, layer: blackShield)], pids: game), "the black shield alone is no picture")
        check(GameProcesses.onlyShield([window(7000, 1512, 982, layer: blackShield)], pids: game), "… and is told apart from no window at all")
        check(GameProcesses.showsWindow([window(7000, 1512, 982, layer: blackShield + 2), window(7000, 1512, 982, layer: blackShield)], pids: game),
              "the game's window over its shield is the picture (Overwatch 13:55)")
        check(GameProcesses.showsWindow([window(7000, 3024, 1964, layer: blackShield + 1), window(7000, 1920, 1200, layer: blackShield)], pids: game),
              "… one level over it too (Control)")
        check(!GameProcesses.onlyShield([window(7000, 1512, 982, layer: blackShield + 2), window(7000, 1512, 982, layer: blackShield)], pids: game),
              "a picture over the shield isn't only a shield")
        check(!GameProcesses.onlyShield([window(401, 1512, 982, layer: blackShield)], pids: game), "another program's shield says nothing of this game")
        check(!GameProcesses.onlyShield([], pids: game), "nothing on screen: no shield either")

        // The page keeps to the screen when a game changes the mode under it.
        let small = CGRect(x: 0, y: 0, width: 1512, height: 982), big = CGRect(x: 0, y: 0, width: 1920, height: 1200)
        check(GameBackdrop.shouldFollow(visible: true, frame: small, screen: big), "the mode changed: the page follows")
        check(!GameBackdrop.shouldFollow(visible: true, frame: big, screen: big), "the same size: nothing to do")
        check(!GameBackdrop.shouldFollow(visible: false, frame: small, screen: big), "not up: nothing to follow")

        // The overlay over ABZU (DXMT, macOS's Game Mode on, 3.11.): opened, never seen – behind the
        // game's window – and the game frozen under it. The panel goes above whatever covers the
        // screen, a game's window or a captured display's shield, not Nightforge's own curtain; the
        // game pauses only once nothing lies in front of the panel and macOS counts it as visible.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let abzu = window(7000, 1512, 982, layer: 27, number: 50)
        let curtain = window(getpid(), 1512, 982, layer: 999, number: 40)
        let menuBar = window(300, 1512, 33, layer: 24, number: 41)
        check(GameProcesses.coverLevel([curtain, menuBar, abzu, window(7010, 300, 200, layer: 3, number: 51)], screen: screen, except: getpid()) == 27,
              "what covers the screen: ABZU's L27 – not the curtain, the menu bar or a small window")
        check(GameProcesses.coverLevel([menuBar], screen: screen, except: getpid()) == nil, "nothing covering it: none")
        let shield = Int(CGShieldingWindowLevel())
        check(GameProcesses.coverLevel([window(88, 1512, 982, layer: shield, number: 3), abzu], screen: screen, except: getpid()) == shield,
              "a captured display's shield")
        let screenSaver = Int(CGWindowLevelForKey(.screenSaverWindow))
        check(GameOverlay.panelLevel(coverLevel: 27) == screenSaver && GameOverlay.panelLevel(coverLevel: nil) == screenSaver,
              "a game below the screen saver's level: the panel at that level, over the curtain")
        check(GameOverlay.panelLevel(coverLevel: 2000) == 2001 && GameOverlay.panelLevel(coverLevel: shield) == shield + 1,
              "higher than that: the panel just above it, over a shield too")
        let panel = window(401, 1512, 982, layer: screenSaver, number: 99)
        check(GameProcesses.covering([panel, abzu], window: 99)?.isEmpty == true, "the panel first: nothing in front of it")
        check(GameProcesses.covering([menuBar, panel, abzu], window: 99)?.isEmpty == true, "the menu bar over it doesn't count")
        check(GameProcesses.covering([abzu, panel], window: 99).map { $0.count } == 1, "ABZU's window before it: in front of it")
        check(GameProcesses.covering([abzu], window: 99) == nil, "not on the Space shown at all")
        check(GameProcesses.describe([window(7000, 1512, 982, layer: 27)]).hasSuffix(" L27 1512×982"), "named in wine.log with level and size")
        check(GameOverlay.raisedLevel(screenSaver, covering: [window(7000, 1512, 982, layer: 2500)]) == 2501,
              "the second try: above what lay in front of it")
        check(GameOverlay.raisedLevel(screenSaver, covering: [abzu]) == screenSaver && GameOverlay.raisedLevel(screenSaver, covering: []) == screenSaver,
              "never lower than it was")
        // ABZU switched the MacBook to 1920×1200 after its start (4.11.): the panel takes the display's frame as
        // it is when it opens, in AppKit's terms – not 1512×982 from before.
        check(GameOverlay.appKitFrame(CGRect(x: 0, y: 0, width: 1920, height: 1200), primaryHeight: 1200) == NSRect(x: 0, y: 0, width: 1920, height: 1200),
              "the main display in its new mode")
        check(GameOverlay.appKitFrame(CGRect(x: 1920, y: 0, width: 2560, height: 1440), primaryHeight: 1200) == NSRect(x: 1920, y: -240, width: 2560, height: 1440),
              "a taller display beside it reaches below the main one's bottom")
        check(GameProcesses.display(of: [], pids: game) == nil, "no window of the game's: the screen it was given")
        check(GameOverlay.shows(inFront: true, occlusionVisible: true), "in front and visible: the game pauses")
        check(!GameOverlay.shows(inFront: true, occlusionVisible: false) && !GameOverlay.shows(inFront: false, occlusionVisible: true),
              "either missing: raised once more, then the game runs on and the panel goes")

        // A window that asks something: Black Myth: Wukong's driver warning lay under the curtain (1.11.).
        check(GameProcesses.question([window(7000, 380, 330, number: 88)], pids: game) == 88, "the driver warning: its window")
        check(GameProcesses.questionWindow([window(7000, 601, 201, number: 87)], pids: game).map { $0.number == 87 && $0.size == CGSize(width: 601, height: 201) } == true,
              "with its size")
        check(GameProcesses.question([window(7010, 800, 300, number: 89)], pids: game) == 89, "a wide, low launcher question")
        check(GameProcesses.question([window(7000, 1920, 1080)], pids: game) == nil, "a picture asks nothing")
        check(GameProcesses.question([window(7000, 120, 60)], pids: game) == nil, "a sliver (a hidden helper window) doesn't")
        check(GameProcesses.question([window(7000, 380, 330, layer: 3, number: 92)], pids: game) == 92,
              "a topmost one, which Wine lifts to the floating level (the warning over Nightforge's page, 1.11.)")
        check(GameProcesses.question([window(7000, 286, 251, layer: 21, number: 93)], pids: game) == 93,
              "winecx's level for a topmost window, just above the Dock (Wukong's driver warning in the game tests, 2.11.)")
        check(GameProcesses.question([window(7000, 286, 251, layer: 20)], pids: game) == nil
              && GameProcesses.question([window(7000, 286, 251, layer: 19)], pids: game) == nil, "the Dock's and utility levels aren't Wine's")
        check(GameProcesses.question([window(7000, 1512, 982, layer: 21)], pids: game) == nil
              && GameProcesses.question([window(7000, 3024, 1964, layer: 26)], pids: game) == nil
              && GameProcesses.question([window(7000, 800, 400, layer: 27)], pids: game) == nil,
              "a full-screen window high up – topmost, or winecx's level for full screen – is a picture, not a question")
        check(GameProcesses.question([window(7000, 380, 330, layer: 101)], pids: game) == nil, "a menu doesn't")
        check(GameProcesses.question([window(7000, 380, 330, layer: -20)], pids: game) == nil, "nor one below the windows")
        check(GameProcesses.question([window(7000, 380, 330, alpha: 0)], pids: game) == nil, "an invisible one doesn't")
        check(GameProcesses.question([window(401, 380, 330)], pids: game) == nil, "Nightforge's or Steam's own doesn't")
        check(GameProcesses.question([window(7000, 380, 330, number: 90), window(7000, 500, 200, number: 91)], pids: game) == 90,
              "two: the frontmost")

        // macOS asks: Tomb Raider's access to its drive lay under the curtain (2.11.), drawn by
        // UserNotificationCenter, and the player saw only "Not starting?".
        let table = [
            GameProcesses.Entry(pid: 78961, parent: 1, command: "/System/Library/CoreServices/UserNotificationCenter.app/Contents/MacOS/UserNotificationCenter"),
            GameProcesses.Entry(pid: 59116, parent: 1, command: "/System/Library/CoreServices/CoreServicesUIAgent.app/Contents/MacOS/CoreServicesUIAgent"),
            GameProcesses.Entry(pid: 31541, parent: 1, command: "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Resources/"
                                + "universalAccessAuthWarn.app/Contents/MacOS/universalAccessAuthWarn launchd -s"),
            GameProcesses.Entry(pid: 812, parent: 1, command: "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/"
                                + "SecurityAgent.bundle/Contents/MacOS/SecurityAgent"),
            GameProcesses.Entry(pid: 900, parent: 1, command: "/System/Library/CoreServices/AuthorizationPromptService.app/Contents/MacOS/AuthorizationPromptService"),
            GameProcesses.Entry(pid: 700, parent: 1, command: "/System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter"),
            GameProcesses.Entry(pid: 701, parent: 1, command: "/System/Library/CoreServices/GameOverlayUI.app/Contents/MacOS/GameOverlayUI"),
            GameProcesses.Entry(pid: 702, parent: 1, command: "/Users/x/Games/UserNotificationCenter.app/Contents/MacOS/UserNotificationCenter"),
            GameProcesses.Entry(pid: 7000, parent: 1, command: "/Volumes/Nightforge Games/steamapps/common/Tomb Raider/Tomb Raider.app/Contents/MacOS/TombRaider"),
        ]
        let askers = GameProcesses.macOSAskers(in: table)
        check(askers == [78961, 59116, 31541, 812, 900],
              "macOS's askers: TCC's (UserNotificationCenter, AuthorizationPromptService), Gatekeeper's, Accessibility's, the password's")
        check(!askers.contains(700), "the notifications' banners ask nothing")
        check(!askers.contains(701), "nor Apple's Game Overlay")
        check(!askers.contains(702), "nor a program named like one outside the system")
        check(!askers.contains(7000), "nor the game")
        check(GameProcesses.macOSQuestion([window(78961, 420, 190, layer: 8, number: 120)], askers: askers) == 120,
              "the drive's permission: its window")
        check(GameProcesses.macOSQuestion([window(812, 420, 260, layer: 1000, number: 121)], askers: askers) == 121,
              "a password's, however high it lies")
        check(GameProcesses.macOSQuestion([window(7000, 420, 190, number: 122)], askers: askers) == nil, "the game's own isn't macOS's")
        check(GameProcesses.macOSQuestion([window(78961, 420, 190, alpha: 0)], askers: askers) == nil, "an invisible one doesn't")
        check(GameProcesses.macOSQuestion([window(78961, 40, 20)], askers: askers) == nil, "nor a sliver")
        check(GameProcesses.macOSQuestion([window(78961, 420, 190, layer: -20)], askers: askers) == nil, "nor one below the windows")
        check(GameProcesses.macOSQuestion([], askers: askers) == nil, "nothing asks: none")
        check(GameProcesses.macOSQuestion([window(78961, 420, 190, number: 123), window(59116, 500, 300, number: 124)], askers: askers) == 123,
              "two: the frontmost")
        check(GameProcesses.macOSQuestions([window(78961, 420, 190, number: 123), window(7000, 420, 190, number: 125),
                                            window(59116, 500, 300, number: 124)], askers: askers) == [123, 124],
              "all of them, the frontmost first: the curtain goes under the backmost")

        // The game test samples the game's own program, not a launcher waiting for it.
        check(GameProcesses.biggest([]) == nil, "no processes, nothing to sample")
        check(GameProcesses.biggest([999_999, getpid()]) == getpid(), "the one with memory, not one that's gone")
    }

    /// The curtain at each look: down only once the game itself is in front, and up again when
    /// another app takes the front from it (the TV test on 1.11.: the Claude app came up instead).
    static func curtain() {
        func step(lowered: Bool = false, gameFront: Bool = false, nightforgeFront: Bool = false, macOS: Bool = false,
                  here: Bool = false, anywhere: Bool = false, asks: Bool = false, frontFor: TimeInterval = 0,
                  settle: TimeInterval = 1, guardOver: Bool = false, pictureFor: TimeInterval = 0, broughtBack: Int = 0,
                  playerActed: Bool = false, shieldOnly: Bool = false) -> LibraryModel.CurtainStep {
            LibraryModel.curtainStep(lowered: lowered, gameFront: gameFront, nightforgeFront: nightforgeFront, macOSAsks: macOS,
                                     windowHere: here, windowAnywhere: anywhere || here, asks: asks, frontFor: frontFor,
                                     settle: settle, guardOver: guardOver, pictureFor: pictureFor, broughtBack: broughtBack,
                                     playerActed: playerActed, shieldOnly: shieldOnly)
        }
        check(step(gameFront: true, anywhere: true, frontFor: 5, broughtBack: 0, shieldOnly: true) == .bringBack,
              "only the black shield on screen: its real window is fetched")
        check(step(gameFront: true, anywhere: true, frontFor: 5, broughtBack: 2, shieldOnly: true) == .wait,
              "still only the shield after two tries: no curtain down for a black screen, \"Not starting?\" comes in its time")
        check(step(gameFront: true, anywhere: true, frontFor: 5, broughtBack: 2) == .lower,
              "a window off the screen without a shield sinks the curtain as before")

        // The pointer under the curtain: the panel only over the game itself.
        func pointer(gameFront: Bool = false, picture: Bool = false, second: Bool = false, newFront: Bool = false,
                     nightforge: Bool = false) -> LibraryModel.PointerStep {
            LibraryModel.pointerUnderCurtain(gameFront: gameFront, picture: picture, frontForSecond: second, newFront: newFront,
                                             nightforgeFront: nightforge)
        }
        check(pointer(gameFront: true, second: true) == .overGame, "the game a second in front without a picture: hidden over it")
        check(pointer(gameFront: true, picture: true, second: true) == .leave, "with a picture: never its keys")
        check(pointer(gameFront: true) == .leave, "only just in front: not yet")
        check(pointer(newFront: true, nightforge: true) == .fromNightforge, "Nightforge in front: no panel needed")
        check(pointer(newFront: true) == .leave, "Steam Helper, Claude or Finder in front: its keys stay its own (8.11.)")
        check(pointer() == .leave, "nothing changed: nothing to do")
        check(step() == .wait, "no window yet: the curtain waits")
        check(step(here: true) == .handOver, "its window is there, another app in front: the game gets the front")
        check(step(anywhere: true) == .handOver, "Mafia II's first start: its window in another Space, behind – handed over too")
        check(step(nightforgeFront: true, here: true) == .handOver, "Nightforge still in front: handed over too")
        check(step(gameFront: true, here: true, frontFor: 0.5) == .wait, "the game in front only just: a moment more")
        check(step(gameFront: true, here: true, frontFor: 1) == .lower, "the game in front for a second: the curtain sinks")
        check(step(gameFront: true, anywhere: true, frontFor: 3) == .wait, "in front, its window not on the Space shown yet: waits a moment")
        check(step(gameFront: true, frontFor: 3) == .wait, "in front without a window of a game's size: waits")
        check(step(lowered: true, gameFront: true) == .wait, "down and the game in front: all well")
        check(step(lowered: true) == .raiseAgain, "down and another app took the front: up again, back to the game")
        check(step(lowered: true, nightforgeFront: true, playerActed: true) == .done, "⌘-Tab or a click to Nightforge: the player's choice, the watch ends")
        // Valheim on 7.11.: macOS handed Nightforge the front, the watch took it for the player and ended.
        check(step(lowered: true, nightforgeFront: true) == .raiseAgain, "Nightforge in front by itself: the game gets the front back")
        check(step(lowered: true, guardOver: true) == .done, "after the guard time the front is the player's")
        // Up again once already (Sonic Mania on 1.11. built its window anew and the curtain came and went).
        let again = LibraryModel.settleAgain
        check(step(gameFront: true, here: true, frontFor: 1.5, settle: again) == .wait, "up again: one second isn't enough")
        check(step(gameFront: true, here: true, frontFor: again, settle: again) == .lower, "the game kept the front a while: it sinks")
        // In front with its window off the screen: shrunk into the Dock, or in a Space not shown.
        let patience = LibraryModel.windowAwayPatience
        check(step(gameFront: true, anywhere: true, frontFor: patience) == .bringBack, "its window off the screen: fetched back, activating it does nothing")
        check(step(gameFront: true, anywhere: true, frontFor: patience, broughtBack: 1) == .bringBack, "once more")
        check(step(gameFront: true, anywhere: true, frontFor: patience, broughtBack: LibraryModel.maxBroughtBack) == .lower,
              "it won't come: the curtain goes all the same, a running game is never left under it")
        check(step(gameFront: true, frontFor: 60) == .wait, "no window of a picture's size anywhere: nothing to fetch")
        check(step(gameFront: true, macOS: true, anywhere: true, frontFor: 30) == .wait, "macOS asks: its question keeps the front")
        // The ceiling: a picture under the curtain whoever has the front.
        let ceiling = LibraryModel.curtainCeiling
        check(step(here: true, pictureFor: ceiling - 1) == .handOver, "its picture for a while, another app in front: still handing over")
        check(step(here: true, pictureFor: ceiling) == .lower, "its picture for long enough: the curtain sinks, whoever has the front")
        check(step(nightforgeFront: true, here: true, pictureFor: ceiling) == .lower, "Nightforge in front too")
        check(step(macOS: true, here: true, pictureFor: ceiling) == .wait, "not while macOS's question holds the start")
        // A question of the game's before any picture: the game gets the front, its window goes over the curtain.
        check(step(asks: true) == .handOver, "a question, another app in front: the game gets the front")
        check(step(nightforgeFront: true, asks: true) == .handOver, "Nightforge in front: handed over too")
        check(step(gameFront: true, asks: true) == .makeWay, "the game in front with its question: over the curtain")
        check(step(gameFront: true, anywhere: true, asks: true) == .makeWay, "a picture elsewhere doesn't keep it under")
        check(step(gameFront: true, here: true, asks: true, frontFor: 1) == .lower, "the picture is there: the curtain sinks as ever")
        check(step(lowered: true, gameFront: true, asks: true) == .wait, "down already: nothing more")
        // macOS asks during the start: the watch looks for the game all the same (ABZU and The Forest
        // ran under Tomb Raider's question on 3.11. and counted as hanging without a picture).
        check(step(nightforgeFront: true, macOS: true, here: true) == .wait, "macOS asks, the game's window is there: not handed the front")
        check(step(macOS: true, asks: true) == .wait, "nor for a question of its own")
        check(step(gameFront: true, macOS: true, here: true, frontFor: 0.5) == .wait, "the game took the front: a moment more")
        check(step(gameFront: true, macOS: true, here: true, frontFor: 1) == .lower,
              "the game in front with its window: the curtain sinks, the question over it")
        check(step(gameFront: true, macOS: true, asks: true) == .makeWay, "the game's question in front: over the curtain too")
        check(step(lowered: true, macOS: true) == .wait, "down, macOS's question in front: the curtain stays down")
        check(step(lowered: true, nightforgeFront: true, macOS: true, playerActed: true) == .done, "the player went to Nightforge meanwhile: the watch ends")
        check(step(lowered: true, nightforgeFront: true, macOS: true) == .wait, "by itself, macOS's question open: the question keeps the front")
        check(step(lowered: true, macOS: true, guardOver: true) == .done, "after the guard time: the watch ends")

        // Steam's question before the start (ShowInterstitials, Black Myth: Wukong on 1.11.): the
        // curtain goes for it and comes back once it's answered, the watch goes on.
        func turn(asks: Bool = false, asked: Bool = false, goesOn: Bool = true, wrong: Bool = false) -> LibraryModel.SteamTurn {
            LibraryModel.steamTurn(asks: asks, asked: asked, startGoesOn: goesOn, wentWrong: wrong)
        }
        check(turn() == .none, "no question: the curtain watches as ever")
        check(turn(asks: true) == .away, "Steam asks: the curtain goes, Steam's window shows")
        check(turn(asks: true, asked: true) == .wait, "still asking: the watch waits")
        check(turn(asked: true) == .back, "answered, the start goes on: the curtain again, its watch with it")
        check(turn(asks: true, goesOn: false) == .over, "the start called off while Steam asks: the watch ends")
        check(turn(asked: true, goesOn: false) == .over, "answered with Cancel: no curtain again")
        check(turn(asked: true, wrong: true) == .over, "answered, then Steam couldn't start it: no curtain over the message")
        check(turn(asks: true, wrong: true) == .none, "a start gone wrong is the watch's own: curtain away, watch over")

        // What takes the curtain away now that it's up from Play on (`launchMac`, `launch`).
        func asks(confirm: Bool = false, phase: LaunchPhase? = nil, saves: Bool = false) -> Bool {
            LibraryModel.startAsksPlayer(needsConfirmation: confirm, phase: phase, savesToChoose: saves)
        }
        check(!asks(), "nothing to answer")
        check(asks(confirm: true), "Steam's question")
        check(asks(phase: .signInAgain), "Steam asks to sign in again")
        check(asks(phase: .signInInSteamWindow), "Steam for Mac's sign-in, under the curtain now")
        check(asks(saves: true), "the choice of saves is a sheet in Nightforge's window")
        check(!asks(phase: .signingIn), "signing in by itself needs nobody")
        check(!asks(phase: .startingSteamForMac), "the Steams changing over stay under the curtain")
        check(!asks(phase: .savingToCloud), "… so does the save going up")

        // Steam's dialogs of their own against its routine steps (console_log of both Steams, 8.11.).
        func dialog(_ what: String) -> Bool {
            MacSteam.waitsInDialog("[2026-11-08 13:30:55] GameAction [AppID 442070, ActionID 7] : LaunchApp waiting for user response to \(what)"[...])
        }
        check(dialog("ShowLaunchOption \"\""), "the pick among launch options has its own window")
        check(dialog("ShowEula \"\""), "a licence too")
        check(dialog("SynchronizingCloud \"syncfailed\""), "a cloud sync that failed too")
        check(dialog("SynchronizingCloud \"cloudconflict\""), "a cloud conflict too")
        check(dialog("KickingOtherSession \"OxyRail\""), "another session to kick too")
        check(!dialog("ShowInterstitials \"\""), "ShowInterstitials needs the main window shown")
        check(!dialog("CreatingProcess \"\""), "CreatingProcess goes on by itself")
        check(!MacSteam.waitsInDialog("GameAction [AppID 442070] : LaunchApp continues with user response \"\""[...]), "no question, no dialog")
        macOSWait()
        ownQuestion()

        // Steam's question itself: its hidden window first, the player only if it still waits
        // (Left 4 Dead 2 on 2.11.: ShowInterstitials went on 1 s after the window, 5 s in).
        func question(_ waited: Int, shownFor: Int? = nil) -> LibraryModel.SteamQuestionStep {
            LibraryModel.steamQuestionStep(waited: waited, shownFor: shownFor)
        }
        check(question(2) == .wait, "a routine step Steam answers within seconds: nothing")
        check(question(3) == .showWindow, "3 s: Steam's window, which some steps need before they go on")
        check(question(4, shownFor: 1) == .wait, "the window shown: the curtain stays while Steam may go on by itself")
        check(question(7, shownFor: 4) == .wait, "still within its grace")
        check(question(8, shownFor: LibraryModel.steamAnswerGrace) == .askPlayer, "still waiting 5 s after the window: the player is asked")

        // A start judged by its first seconds that ends early (Control on 2.11., every way): the start
        // tells what's next under the same curtain – not when it's an end like any other.
        check(LibraryModel.startJudgesEnd(quitByPlayer: false, showedPicture: false), "gone without a picture: the start decides, the curtain stays")
        check(!LibraryModel.startJudgesEnd(quitByPlayer: true, showedPicture: false), "Quit Game: back to Nightforge at once")
        check(!LibraryModel.startJudgesEnd(quitByPlayer: false, showedPicture: true), "it showed a picture: an end like any other")
    }

    /// The game's own question, answered by the player – Unity's configuration window, Quit: The Forest
    /// ended without a picture on 3.11., and the start went on to its next way. And a splash isn't a
    /// question (ABZU's Unreal splash, 601×201, showed "asking" for a moment).
    static func ownQuestion() {
        // The order: its question seen (the curtain made way), the player clicks Quit, the window goes,
        // and Wine ends its processes some seconds later (more than the 3 s first allowed, 4.11.).
        check(LibraryModel.answered(inputBefore: 0.6, shownFor: 8, inFront: true), "the window went 0.6 s after a click on it: answered")
        check(LibraryModel.endedAtOwnQuestion(answeredAgo: 9), "its processes gone 9 s after: the player's")
        check(LibraryModel.endedAtOwnQuestion(answeredAgo: LibraryModel.ownQuestionGrace), "within \(Int(LibraryModel.ownQuestionGrace)) s")
        let start = Date(timeIntervalSince1970: 1_793_800_000), end = start.addingTimeInterval(20)
        check(LibraryModel.ownQuestionEndStands(end: end, startedAt: start, lastRunning: end.addingTimeInterval(-1), graphicsFailed: false, crashed: false),
              "so the start tries no other way")
        // Not the player's: a splash gone by itself, a click elsewhere or from before, an end long after answering.
        check(!LibraryModel.answered(inputBefore: 30, shownFor: 8, inFront: true), "no click or key before it went: no one answered it")
        check(!LibraryModel.answered(inputBefore: 2, shownFor: 1, inFront: true), "a click from before the window came: not its answer")
        check(!LibraryModel.answered(inputBefore: 0.5, shownFor: 8, inFront: false), "another app in front: a click there, not on it")
        check(!LibraryModel.endedAtOwnQuestion(answeredAgo: 40), "Wukong's warning answered long before the end: the way's")
        check(!LibraryModel.endedAtOwnQuestion(answeredAgo: nil), "no answered question: the way's")
        // A launcher's window taken as a question, the launcher gone, the game itself started and crashed (Control).
        check(!LibraryModel.ownQuestionEndStands(end: end, startedAt: start, lastRunning: end.addingTimeInterval(6), graphicsFailed: false, crashed: false),
              "a process of the game's ran after that end: a handover, the way's")
        check(!LibraryModel.ownQuestionEndStands(end: start.addingTimeInterval(-5), startedAt: start, lastRunning: nil, graphicsFailed: false, crashed: false),
              "an end from a start before: as ever")
        // Play in Unity's window, then the graphics fail at once or it crashes (an Unreal crash report too): the way's after all.
        check(!LibraryModel.ownQuestionEndStands(end: end, startedAt: start, lastRunning: nil, graphicsFailed: true, crashed: false), "the graphics failed: the next way")
        check(!LibraryModel.ownQuestionEndStands(end: end, startedAt: start, lastRunning: nil, graphicsFailed: false, crashed: true), "a crash: the next way")
        check(!LibraryModel.ownQuestionEndStands(end: nil, startedAt: start, lastRunning: nil, graphicsFailed: false, crashed: false), "not at its question: as ever")

        // A thin window takes a while to count as a question; a dialog counts at once.
        check(!LibraryModel.takenAsQuestion(CGSize(width: 601, height: 201), standing: 1), "ABZU's splash, a second in: not asking")
        check(LibraryModel.takenAsQuestion(CGSize(width: 601, height: 201), standing: LibraryModel.thinPatience),
              "standing \(Int(LibraryModel.thinPatience)) s: a question after all (a wide error box)")
        check(LibraryModel.takenAsQuestion(CGSize(width: 464, height: 438), standing: 0), "Unity's configuration window: at once")
        check(LibraryModel.takenAsQuestion(CGSize(width: 286, height: 251), standing: 0), "Wukong's driver warning: at once")
        check(LibraryModel.takenAsQuestion(CGSize(width: 800, height: 330), standing: 0), "a wide launcher question under 2.5 : 1: at once")
        // Unity's window while the helper is to press Play! in it: under the curtain, unless it stands too long.
        check(!LibraryModel.takenAsQuestion(CGSize(width: 464, height: 438), standing: 1, helperPresses: true),
              "the helper about to press Play!: the curtain stays over it")
        check(LibraryModel.takenAsQuestion(CGSize(width: 464, height: 438), standing: LibraryModel.helperPatience, helperPresses: true),
              "still there after \(Int(LibraryModel.helperPatience)) s: the player's to answer")
    }

    /// A question of macOS's: the curtain under it, for three minutes at most – one that hangs or lies
    /// under another window held the start forever (review M8, 3.11.).
    static func macOSWait() {
        let start = Date(timeIntervalSince1970: 1_793_700_000)
        func turn(asking: Bool, since: Date? = nil, gaveUp: Bool = false, after seconds: TimeInterval = 0) -> LibraryModel.MacOSTurn {
            LibraryModel.macOSTurn(asking: asking, since: since, gaveUp: gaveUp, now: start.addingTimeInterval(seconds))
        }
        check(turn(asking: false) == .none, "nothing asks: the curtain as ever")
        check(turn(asking: true) == .makeWay, "macOS asks: the curtain under its window")
        check(turn(asking: true, since: start, after: 179) == .makeWay, "still asking within three minutes: still under it")
        check(turn(asking: true, since: start, after: LibraryModel.macOSPatience) == .giveUp,
              "three minutes: the curtain stops waiting, the start goes on")
        check(turn(asking: true, since: start, gaveUp: true, after: 600) == .none,
              "stopped waiting, the window still there: as without one, \"Not starting?\" may come")
        check(turn(asking: false, since: start, after: 30) == .answered, "answered: over everything again")
        check(turn(asking: false, since: start, gaveUp: true, after: 300) == .none, "gone after giving up: nothing more to do")
        check(LibraryModel.macOSPatience == 180, "three minutes")

        // A question from before the start (Tomb Raider's, unanswered on 3.11.) holds none: only one
        // that came up during it does.
        check(!LibraryModel.macOSAsksNow([297], before: [297]), "there at the first look: the start doesn't wait for it")
        check(turn(asking: LibraryModel.macOSAsksNow([297], before: [297])) == .none, "no wait, no \"answered\" later")
        check(LibraryModel.macOSAsksNow([301], before: []), "came up during the start: it waits")
        check(LibraryModel.macOSAsksNow([297, 301], before: [297]), "a new one beside the old one: it waits for that")
        check(!LibraryModel.macOSAsksNow([], before: [297]), "the old one answered meanwhile: nothing")
    }

    /// The way back: the curtain goes only once Nightforge is in front on the page the player comes
    /// back to (the monitor test on 1.11.: Home showed for a moment before the game's page).
    static func wayBack() {
        let detail = Route.detail(gameID: "steam:50130", from: .home)
        check(LibraryModel.mayUncover(active: true, windowShown: true, page: detail, target: detail), "in front, on the game's page: uncovered")
        check(!LibraryModel.mayUncover(active: true, windowShown: true, page: .home, target: detail), "still on Home: the curtain waits for the page")
        check(!LibraryModel.mayUncover(active: false, windowShown: true, page: detail, target: detail), "not in front yet: waits")
        check(!LibraryModel.mayUncover(active: true, windowShown: false, page: detail, target: detail), "its window on another Space: waits")
    }

    /// The curtain's line follows the start: its own step while it has one, then the game's.
    static func curtainLines() {
        func line(_ phase: String? = nil, shaders: Bool = false, runs: Bool = false, window: Bool = false) -> String? {
            LibraryModel.curtainStatus(phase: phase, shaders: shaders, gameRuns: runs, windowShown: window)
        }
        check(line() == nil, "nothing known yet: \"Starting …\"")
        check(line("Starting Steam …") == "Starting Steam …", "the start's own step, from the first look on")
        check(line("Starting again with WineD3D …", runs: true) == "Starting again with WineD3D …", "a step wins over the game's")
        check(line(runs: true) == L10n.t("Waiting for the first picture …"), "the game runs, no window yet")
        check(line(shaders: true, runs: true) == L10n.t("Preparing shaders for the first start …"), "its first start with these graphics")
        check(line(shaders: true, runs: true, window: true) == nil, "its window is there: nothing more to say")
        check(LibraryModel.curtainStatus(phase: "Starting Steam …", shaders: false, gameRuns: true, windowShown: false, asks: true)
              == L10n.t("The game is asking something – answer it with the mouse or trackpad."), "a question on it: said, before any step")
        check(LibraryModel.curtainStatus(phase: "Starting Steam …", shaders: false, gameRuns: true, windowShown: false, asks: true,
                                         macOSAsks: true)
              == L10n.t("macOS is asking for permission – answer it with the mouse or trackpad."),
              "macOS asks: said, before the game's question and any step")
        func detail(_ hint: String? = nil, asks: Bool = false, macOSOpen: Bool = false) -> String? {
            LibraryModel.curtainDetail(launchHint: hint, asks: asks, macOSOpen: macOSOpen)
        }
        check(detail() == nil, "nothing to add")
        check(detail(macOSOpen: true) == L10n.t("macOS still has a question open."), "a question from before the start: a word on it")
        check(detail("Steam updates the game first", macOSOpen: true) == "Steam updates the game first", "the start's hint goes first")
        check(detail("Steam updates the game first", asks: true, macOSOpen: true) == nil, "under a question it waits for: none")
    }

    /// The loading screen's N: drawn at the screen's scale, its seam left out for the layer on top.
    static func brandArt() {
        let unit: CGFloat = 0.5
        let size = CGSize(width: BrandArt.glyphSize.width * unit, height: BrandArt.glyphSize.height * unit)
        func picture(seam: Bool) -> CGImage? {
            BrandArt.image(size: size, scale: 2) { BrandArt.drawMark($0, origin: .zero, scale: unit, seam: seam, glow: 2 * unit) }
        }
        guard let lit = picture(seam: true), let dark = picture(seam: false) else {
            check(false, "the N drawn")
            return
        }
        check(lit.width == 332 && lit.height == 440, "twice the points in pixels (\(lit.width)×\(lit.height))")
        // Halfway along the seam, (49, 170) → (332, 440) in the design: blue light, or none.
        func blue(_ image: CGImage) -> Int {
            let point = CGPoint(x: (49 + 332) / 2 * unit * 2, y: (170 + 440) / 2 * unit * 2)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1, width: CGFloat(image.width), height: CGFloat(image.height)))
            return Int(pixel[2]) - Int(pixel[0])
        }
        check(blue(lit) > blue(dark) + 30, "seam: false leaves the light to the layer on top (\(blue(lit)) against \(blue(dark)))")
    }

    /// A stand-in game: a shell named like a Windows game, which shrugs off SIGTERM, and its child.
    static func standIn() {
        let marker = #"\steamapps\common\Stand In Game\"#
        let name = #"C:\Program Files (x86)\Steam\steamapps\common\Stand In Game\StandIn.exe"#
        let game = Process()
        game.executableURL = URL(fileURLWithPath: "/bin/bash")
        game.arguments = ["-c", "exec -a '\(name)' /bin/bash -c 'trap \"\" TERM; while :; do /bin/sleep 1; done'"]
        // A Wine session process under it, which must outlive the game.
        let session = Process()
        session.executableURL = URL(fileURLWithPath: "/bin/bash")
        session.arguments = ["-c", "exec -a '/tmp/standin/bin/wineserver' /bin/sleep 30"]
        guard (try? game.run()) != nil, (try? session.run()) != nil else {
            check(false, "the stand-in started")
            return
        }
        // Never left behind, whatever the checks find: it shrugs off SIGTERM and may be paused, so SIGKILL
        // by its own number (3.11.: with ps hanging, the list was empty, nothing ended it, the test waited for good).
        defer {
            kill(game.processIdentifier, SIGKILL)
            kill(session.processIdentifier, SIGKILL)
        }
        Thread.sleep(forTimeInterval: 0.6)
        // The process list: the stand-ins and what they started, each asked for by its own pid.
        FakeProcesses.install { FakeProcesses.rows(of: [game.processIdentifier, session.processIdentifier], descendants: true) }
        defer { FakeProcesses.installEmpty() }

        let pids = GameProcesses.targets(windows: marker, mac: nil, in: GameProcesses.table())
        check(pids.contains(game.processIdentifier), "the stand-in is found by its folder")
        check(pids.count >= 2, "with the child it started (\(pids))")
        check(!pids.contains(session.processIdentifier), "a wineserver is never the game's")

        // Paused under the overlay, and on again.
        for pid in pids { kill(pid, SIGSTOP) }
        Thread.sleep(forTimeInterval: 0.2)
        check(GameProcesses.stopped(game.processIdentifier), "paused (SIGSTOP)")
        for pid in pids { kill(pid, SIGCONT) }
        Thread.sleep(forTimeInterval: 0.2)
        check(!GameProcesses.stopped(game.processIdentifier) && GameProcesses.alive(game.processIdentifier), "running on (SIGCONT)")

        // Quit while paused: it ignores SIGTERM like a hung game, so SIGKILL ends it after the patience.
        kill(game.processIdentifier, SIGSTOP)
        let started = Date()
        GameProcesses.end(pids, patience: 1)
        let took = Date().timeIntervalSince(started)
        check(!GameProcesses.alive(game.processIdentifier), "ended, though it ignored SIGTERM and was paused")
        check(took >= 1 && took < 4, "after the patience, not before or long after (\(String(format: "%.1f", took)) s)")
        check(GameProcesses.alive(session.processIdentifier), "the Wine session lives on")
        if GameProcesses.alive(game.processIdentifier) { kill(game.processIdentifier, SIGKILL) }
        let until = Date().addingTimeInterval(5)
        while game.isRunning, Date() < until { Thread.sleep(forTimeInterval: 0.05) }
        check(!game.isRunning && game.terminationReason == .uncaughtSignal && game.terminationStatus == SIGKILL,
              "it took SIGKILL (\(game.isRunning ? "still running" : String(game.terminationStatus)))")
        bareName()
    }

    /// A program by its bare name in its game's folder, as Control's launcher starts it (2.11.): found
    /// by its working folder, the way Wine gives it one.
    static func bareName() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("standin-\(getpid())/Epic Games/Bare Game/bin")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }
        let game = Process()
        game.executableURL = URL(fileURLWithPath: "/bin/bash")
        game.currentDirectoryURL = folder
        game.arguments = ["-c", "exec -a 'BareGame_DX11.exe -AUTH_LOGIN=unused' /bin/sleep 5"]
        guard (try? game.run()) != nil else { return check(false, "the bare stand-in started") }
        defer { game.terminate() }
        Thread.sleep(forTimeInterval: 0.4)
        FakeProcesses.install { FakeProcesses.rows(of: [game.processIdentifier]) }
        defer { FakeProcesses.installEmpty() }
        let table = GameProcesses.table()
        let entry = table.first { $0.pid == game.processIdentifier }
        check(entry?.cwd?.lowercased().hasSuffix("/epic games/bare game/bin") == true, "its working folder is read (\(entry?.cwd ?? "none"))")
        let marker = #"\Epic Games\Bare Game\"#
        check(GameProcesses.running([marker.lowercased(): "epic:bare"], in: table)["epic:bare"] == game.processIdentifier,
              "the bare program counts as the game running")
        check(GameProcesses.targets(windows: marker, mac: nil, in: table) == [game.processIdentifier], "and as the game's process")
    }
}
