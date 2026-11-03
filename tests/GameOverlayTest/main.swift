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

        // A window that asks something: Black Myth: Wukong's driver warning lay under the curtain (1.11.).
        check(GameProcesses.question([window(7000, 380, 330, number: 88)], pids: game) == 88, "the driver warning: its window")
        check(GameProcesses.question([window(7010, 800, 300, number: 89)], pids: game) == 89, "a wide, low launcher question")
        check(GameProcesses.question([window(7000, 1920, 1080)], pids: game) == nil, "a picture asks nothing")
        check(GameProcesses.question([window(7000, 120, 60)], pids: game) == nil, "a sliver (a hidden helper window) doesn't")
        check(GameProcesses.question([window(7000, 380, 330, layer: 3, number: 92)], pids: game) == 92,
              "a topmost one, which Wine lifts to the floating level (the warning over Nightforge's page, 1.11.)")
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
    }

    /// The curtain at each look: down only once the game itself is in front, and up again when
    /// another app takes the front from it (the TV test on 1.11.: the Claude app came up instead).
    static func curtain() {
        func step(lowered: Bool = false, gameFront: Bool = false, nightforgeFront: Bool = false, here: Bool = false,
                  anywhere: Bool = false, asks: Bool = false, frontFor: TimeInterval = 0, settle: TimeInterval = 1,
                  guardOver: Bool = false) -> LibraryModel.CurtainStep {
            LibraryModel.curtainStep(lowered: lowered, gameFront: gameFront, nightforgeFront: nightforgeFront, windowHere: here,
                                     windowAnywhere: anywhere || here, asks: asks, frontFor: frontFor, settle: settle,
                                     guardOver: guardOver)
        }
        check(step() == .wait, "no window yet: the curtain waits")
        check(step(here: true) == .handOver, "its window is there, another app in front: the game gets the front")
        check(step(anywhere: true) == .handOver, "Mafia II's first start: its window in another Space, behind – handed over too")
        check(step(nightforgeFront: true, here: true) == .handOver, "Nightforge still in front: handed over too")
        check(step(gameFront: true, here: true, frontFor: 0.5) == .wait, "the game in front only just: a moment more")
        check(step(gameFront: true, here: true, frontFor: 1) == .lower, "the game in front for a second: the curtain sinks")
        check(step(gameFront: true, anywhere: true, frontFor: 3) == .wait, "in front, its window not on the Space shown yet: waits")
        check(step(gameFront: true, frontFor: 3) == .wait, "in front without a window of a game's size: waits")
        check(step(lowered: true, gameFront: true) == .wait, "down and the game in front: all well")
        check(step(lowered: true) == .raiseAgain, "down and another app took the front: up again, back to the game")
        check(step(lowered: true, nightforgeFront: true) == .done, "Go to Nightforge: the player's choice, the watch ends")
        check(step(lowered: true, guardOver: true) == .done, "after the guard time the front is the player's")
        // Up again once already (Sonic Mania on 1.11. built its window anew and the curtain came and went).
        let again = LibraryModel.settleAgain
        check(step(gameFront: true, here: true, frontFor: 1.5, settle: again) == .wait, "up again: one second isn't enough")
        check(step(gameFront: true, here: true, frontFor: again, settle: again) == .lower, "the game kept the front a while: it sinks")
        // Its window elsewhere, however long: sinking showed Nightforge's page under the game (1.11.).
        check(step(gameFront: true, anywhere: true, frontFor: 30) == .wait, "its window in another Space: the curtain stays")
        // A question of the game's before any picture: the game gets the front, its window goes over the curtain.
        check(step(asks: true) == .handOver, "a question, another app in front: the game gets the front")
        check(step(nightforgeFront: true, asks: true) == .handOver, "Nightforge in front: handed over too")
        check(step(gameFront: true, asks: true) == .makeWay, "the game in front with its question: over the curtain")
        check(step(gameFront: true, anywhere: true, asks: true) == .makeWay, "a picture elsewhere doesn't keep it under")
        check(step(gameFront: true, here: true, asks: true, frontFor: 1) == .lower, "the picture is there: the curtain sinks as ever")
        check(step(lowered: true, gameFront: true, asks: true) == .wait, "down already: nothing more")

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
        macOSWait()

        // A start judged by its first seconds that ends early (Control on 2.11., every way): the start
        // tells what's next under the same curtain – not when it's an end like any other.
        check(LibraryModel.startJudgesEnd(quitByPlayer: false, showedPicture: false), "gone without a picture: the start decides, the curtain stays")
        check(!LibraryModel.startJudgesEnd(quitByPlayer: true, showedPicture: false), "Quit Game: back to Nightforge at once")
        check(!LibraryModel.startJudgesEnd(quitByPlayer: false, showedPicture: true), "it showed a picture: an end like any other")
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
        defer {
            game.terminate()
            session.terminate()
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
        game.waitUntilExit()
        check(game.terminationReason == .uncaughtSignal && game.terminationStatus == SIGKILL, "it took SIGKILL (\(game.terminationStatus))")
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
