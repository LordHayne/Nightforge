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
        hold()
        steps()
        targets()
        windows()
        curtain()
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
    }

    /// What the curtain waits for: a window of a game's size from one of the game's processes.
    static func windows() {
        func window(_ pid: Int32, _ width: Double, _ height: Double, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowAlpha as String: NSNumber(value: alpha),
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
    }

    /// The curtain at each look: down only once the game itself is in front, and up again when
    /// another app takes the front from it (the TV test on 1.11.: the Claude app came up instead).
    static func curtain() {
        func step(lowered: Bool = false, gameFront: Bool = false, nightforgeFront: Bool = false, here: Bool = false,
                  anywhere: Bool = false, frontFor: TimeInterval = 0, settle: TimeInterval = 1,
                  guardOver: Bool = false) -> LibraryModel.CurtainStep {
            LibraryModel.curtainStep(lowered: lowered, gameFront: gameFront, nightforgeFront: nightforgeFront, windowHere: here,
                                     windowAnywhere: anywhere || here, frontFor: frontFor, settle: settle, guardOver: guardOver)
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
    }
}
