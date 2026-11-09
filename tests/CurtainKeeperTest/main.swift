// Checks that a curtain never stays with nobody to take it away. Tomb Raider on 8.11. at 22:28 (wine.log):
// quit through the overlay, Nightforge back in front, and then Steam Helper coming forward raised the curtain for
// a game that had ended. It stayed, and B did nothing: tests/CurtainKeeperTest/run.sh
import AppKit

/// The parts of a game's end that decide about the curtain, with the app's own rules in them.
struct Sim {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var stage = GameStage()
    var raised = false
    var raisedAt: Date?
    var launching = false
    var watching = false
    var playing = false
    var comingBack = false
    var orphan = CurtainEscape.Orphan()
    var offered = false

    var owners: CurtainEscape.Owners {
        CurtainEscape.Owners(starting: launching, watching: watching,
                             playing: CurtainEscape.playingOwns(gamePlaying: playing, upFor: raisedAt.map { now.timeIntervalSince($0) } ?? 0),
                             comingBack: comingBack)
    }

    var wayOut: Bool { CurtainEscape.wayOutOpen(raised: raised, offered: offered, owners: owners) }

    mutating func raise() {
        if !raised { raisedAt = now }
        raised = true
    }

    mutating func pass(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }

    /// A game on the stage with its picture, as after the curtain sinks.
    mutating func gameOnStage() {
        stage = GameStage()
        stage.pictureSeen()
        playing = true
        raised = false
    }

    /// GameBackdrop.frontMoved → LibraryModel.frontMoved: another app came forward, no game's window here.
    mutating func frontMoves() {
        let look = GameStage.Look(gameFront: false, windowHere: false, windowAnywhere: false, now: now)
        guard CurtainEscape.mayRaiseForEnd(gamePlaying: playing, comingBack: comingBack), stage.pictureWent(look) else { return }
        raise()
    }

    /// LibraryModel.gameProcessExited.
    mutating func processEnds() {
        guard CurtainEscape.mayRaiseForEnd(gamePlaying: playing, comingBack: comingBack),
              LibraryModel.exitRaisesCurtain(curtainUp: raised, sawPicture: stage.sawPicture, judged: false, othersRunning: false)
        else { return }
        raise()
    }

    mutating func comeBack() {
        playing = false
        comingBack = true
    }

    /// GameBackdrop.hide(once:) ends: the curtain is gone, "Welcome back".
    mutating func curtainGone() {
        raised = false
        comingBack = false
    }

    /// One look of the watch over running games.
    @discardableResult
    mutating func look() -> Bool {
        guard orphan.look(raised: raised, owners: owners, now: now) else { return false }
        raised = false
        return true
    }
}

@main
struct CurtainKeeperTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// wine.log, 8.11.: 22:28:41 "Back to Nightforge", 22:28:44 "The game's picture went …", and nobody after that.
    static func tombRaider() {
        var sim = Sim()
        sim.gameOnStage()
        sim.raise()  // the overlay's Quit: `returning(held: true)`
        sim.pass(1)
        sim.comeBack()
        sim.pass(1)
        sim.curtainGone()
        sim.pass(1)
        sim.frontMoves()  // Steam Helper, after Steam switched over
        check(!sim.raised, "after the way back, Steam Helper coming forward raises no curtain")

        // While Nightforge is on its way back too.
        var coming = Sim()
        coming.gameOnStage()
        coming.comeBack()
        coming.frontMoves()
        check(!coming.raised, "on the way back: nothing that comes forward says anything about a game")

        // The same with a process's end arriving late.
        var late = Sim()
        late.gameOnStage()
        late.comeBack()
        late.curtainGone()
        late.processEnds()
        check(!late.raised, "a process's end after the way back raises no curtain")

        // What f4386c4 is there for still works.
        var ending = Sim()
        ending.gameOnStage()
        ending.frontMoves()
        check(ending.raised, "a game being played whose picture goes: the curtain comes at once")
        var exited = Sim()
        exited.gameOnStage()
        exited.processEnds()
        check(exited.raised, "a game being played whose process ends: the curtain comes at once")
    }

    /// Whatever raised it: nobody left to take it away, it goes by itself.
    static func safety() {
        var sim = Sim()
        sim.raise()
        check(!sim.look(), "the first look only notes it")
        sim.pass(CurtainEscape.orphanAfter - 1)
        check(!sim.look() && sim.raised, "a moment between two owners: it stays")
        sim.pass(1)
        check(sim.look() && !sim.raised, "nobody for a while: it goes by itself")

        for (name, set) in [("a start", { (s: inout Sim) in s.launching = true }), ("the curtain's watch", { $0.watching = true }),
                            ("a game being played", { $0.playing = true }), ("the way back", { $0.comingBack = true })]
            as [(String, (inout Sim) -> Void)] {
            var held = Sim()
            set(&held)
            held.raise()
            _ = held.look()
            held.pass(CurtainEscape.orphanAfter + 1)
            check(!held.look() && held.raised, "\(name) has it: it stays")
        }

        var handed = Sim()
        handed.raise()
        _ = handed.look()
        handed.pass(4)
        handed.launching = true
        _ = handed.look()
        handed.launching = false
        handed.pass(4)
        check(!handed.look() && handed.raised, "an owner came between: the time starts over")

        var running = Sim()
        running.playing = true
        running.raise()
        running.pass(CurtainEscape.playingHoldsFor - 1)
        _ = running.look()
        running.pass(CurtainEscape.orphanAfter)
        check(!running.owners.anyone, "a game that runs on holds no curtain for ever")
        _ = running.look()
        running.pass(CurtainEscape.orphanAfter)
        check(running.look() && !running.raised, "the curtain over a game that runs on goes too")

        var down = Sim()
        check(!down.look(), "no curtain: nothing to do")
        down.pass(100)
        check(!down.look(), "still nothing")
    }

    /// Item 2 of the report: B and Esc lead out of such a curtain, at once.
    static func wayOut() {
        var orphan = Sim()
        orphan.raise()
        check(orphan.wayOut, "nobody owns it: B and Esc lead out, before it goes by itself")
        check(PadRules.back(PadRules.Open(curtain: true, curtainEscape: orphan.wayOut)) == .curtainEscape, "the pad's B asks for it")

        var starting = Sim()
        starting.launching = true
        starting.raise()
        check(!starting.wayOut, "a start under way that offers none: B stays out, as ever")
        check(PadRules.back(PadRules.Open(curtain: true, curtainEscape: starting.wayOut)) == .nothing, "the pad's B does nothing there")
        starting.offered = true
        check(starting.wayOut, "the way out it offers: open")

        let nothing = Sim()
        check(!nothing.wayOut, "no curtain: no way out to take")
    }

    /// Any order of what can happen: at the end, with time passing, no curtain is left.
    static func anyOrder() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<20_000 {
            var sim = Sim()
            if Bool.random(using: &random) { sim.gameOnStage() }
            for _ in 0..<Int.random(in: 1...30, using: &random) {
                switch Int.random(in: 0...11, using: &random) {
                case 0: sim.frontMoves()
                case 1: sim.processEnds()
                case 2: sim.comeBack()
                case 3: sim.curtainGone()
                case 4: sim.raise()
                case 5: sim.playing = true
                case 6: sim.playing = false
                case 7: sim.launching.toggle()
                case 8: sim.watching.toggle()
                case 9: sim.pass(.random(in: 0...3, using: &random))
                case 10: sim.look()
                default: sim.gameOnStage()
                }
            }
            // Everybody done, as they all are in the end.
            sim.launching = false
            sim.watching = false
            sim.comingBack = false
            sim.playing = false
            for _ in 0..<4 {
                sim.look()
                sim.pass(CurtainEscape.orphanAfter)
            }
            check(!sim.raised, "whatever came before, the curtain is gone once nobody owns it")
            if sim.raised { break }
        }
    }

    /// The watch's own rule under any timing: never away from an owner, never before its time, and not long after it.
    static func orphanTiming() {
        var random = SystemRandomNumberGenerator()
        let look: TimeInterval = 2  // at most this far apart, as the watch over running games goes
        for _ in 0..<5_000 {
            var orphan = CurtainEscape.Orphan()
            var now = Date(timeIntervalSince1970: 1_000_000)
            var nobodySince: Date?
            var raised = false
            for _ in 0..<80 {
                now.addTimeInterval(.random(in: 0.2...look, using: &random))
                if Int.random(in: 0...6, using: &random) == 0 { raised.toggle() }
                var owners = CurtainEscape.Owners()
                if Int.random(in: 0...4, using: &random) == 0 { owners.starting = true }
                if Int.random(in: 0...4, using: &random) == 0 { owners.watching = true }
                if Int.random(in: 0...6, using: &random) == 0 { owners.playing = true }
                if Int.random(in: 0...6, using: &random) == 0 { owners.comingBack = true }
                let orphaned = raised && !owners.anyone
                let goes = orphan.look(raised: raised, owners: owners, now: now)
                if goes {
                    check(orphaned, "it goes from under an owner, or with nothing raised")
                    check(nobodySince.map { now.timeIntervalSince($0) >= CurtainEscape.orphanAfter } ?? false, "it goes before its time")
                    raised = false
                    nobodySince = nil
                } else if orphaned {
                    let since = nobodySince ?? now
                    nobodySince = since
                    check(now.timeIntervalSince(since) < CurtainEscape.orphanAfter + look, "it stays long after its time")
                } else {
                    nobodySince = nil
                }
                if failures > 0 { return }
            }
        }
        let flags = [false, true]
        for starting in flags { for watching in flags { for playing in flags { for comingBack in flags { for raised in flags { for offered in flags {
            let owners = CurtainEscape.Owners(starting: starting, watching: watching, playing: playing, comingBack: comingBack)
            let open = CurtainEscape.wayOutOpen(raised: raised, offered: offered, owners: owners)
            check(open == (raised && (offered || !(starting || watching || playing || comingBack))), "the way out at the wrong moment")
        } } } } } }
    }

    /// The rules above do nothing unless the app asks them: what went wrong on 8.11. was a place that didn't.
    static func wiring() {
        let source = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(!source.isEmpty, "LibraryModel.swift is readable from the repository's root")
        func body(of name: String) -> String {
            guard let start = source.range(of: "func \(name)(") else { return "" }
            let rest = source[start.upperBound...]
            let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex
            return String(rest[..<end])
        }
        check(body(of: "frontMoved").contains("mayRaiseForEnd"), "frontMoved asks whether a game is still being played")
        check(body(of: "gameProcessExited").contains("mayRaiseForEnd"), "gameProcessExited asks too")
        check(body(of: "comeBack").contains("comingBackSince = Date()"), "the way back says so")
        check(body(of: "comeBack").contains("stagePids = []"), "the way back ends the stage")
        check(body(of: "askAboutStuckStart").contains("takeAwayOrphanCurtain"), "B and Esc lead out of a curtain nobody owns")
        check(body(of: "watchRunningGames").contains("curtainOrphan.look"), "the watch over running games looks after it, every time")
        check(body(of: "watchCurtain").contains("curtainWatches += 1"), "a curtain's watch counts as its owner")
    }

    static func main() {
        tombRaider()
        safety()
        wayOut()
        anyOrder()
        orphanTiming()
        wiring()
        print(failures == 0 ? "CurtainKeeperTest: all good" : "CurtainKeeperTest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
