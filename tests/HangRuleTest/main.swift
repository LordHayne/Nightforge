// The rule that tells a hung game from one that only loads long (HangRule), the log line (HangWatch.line) and the
// looks from outside on a process of the test's own: tests/HangRuleTest/run.sh
import AppKit
import Foundation

@main
struct HangRuleTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Sample = HangRule.Sample

    /// A game in front, shown, unpaused, from `start` every `step` s; `cpu` (cores) and `read` (bytes/s) per look.
    static func run(_ count: Int, from start: TimeInterval = 0, step: TimeInterval = 3, cpu: Double = 0, read: Double = 0,
                    sound: Bool? = false, base: Sample? = nil) -> [Sample] {
        var last = base ?? Sample(at: start, cpu: 10, read: 1_000_000, sound: sound, shown: true, front: true, paused: false)
        var samples = base == nil ? [last] : []
        for _ in 0..<(base == nil ? count - 1 : count) {
            last = Sample(at: last.at + step, cpu: last.cpu + cpu * step, read: last.read + UInt64(read * step), sound: sound,
                          shown: true, front: true, paused: false)
            samples.append(last)
        }
        return samples
    }

    static func rule() {
        // A game started at 0, looked at every 3 s.
        let settled = run(24, from: 20)  // 20 … 89 s, idle all along
        check(HangRule.judge(settled, started: 0, firstStart: false) == .hung(since: 20), "idle in front for 69 s: hung, since the first quiet look")
        check(HangRule.judge(Array(settled.prefix(8)), started: 0, firstStart: false) == .quiet(since: 20), "idle for 21 s: quiet, not yet hung")
        check(HangRule.judge(Array(settled.prefix(11)), started: 0, firstStart: false) == .hung(since: 20), "idle for 30 s: hung")
        check(HangRule.judge(Array(settled.prefix(11)), started: 0, firstStart: true) == .quiet(since: 20),
              "a first start gets 90 s: 30 s quiet is no hang yet")
        check(HangRule.judge(settled + run(8, base: settled.last!), started: 0, firstStart: true) == .hung(since: 20),
              "…but 93 s is")
        check(HangRule.judge(run(5, from: 0), started: 0, firstStart: false) == .unknown, "the first 20 s aren't judged")

        // Loading: reading files, compiling shaders, playing music.
        check(HangRule.judge(run(24, from: 20, read: 2_000_000), started: 0, firstStart: false) == .busy, "reading 2 MB/s: loads")
        check(HangRule.judge(run(24, from: 20, cpu: 0.8), started: 0, firstStart: false) == .busy, "80 % of a core: works")
        check(HangRule.judge(run(24, from: 20, sound: true), started: 0, firstStart: false) == .busy, "plays sound: alive")
        check(HangRule.judge(run(24, from: 20, cpu: 0.02, read: 100_000), started: 0, firstStart: false) != .busy,
              "2 % CPU and a log file's writes: still counts as idle")
        let loadedThenStopped = run(10, from: 20, read: 5_000_000)
        let stopped = loadedThenStopped + run(11, base: loadedThenStopped.last!)
        check(HangRule.judge(stopped, started: 0, firstStart: false) == .hung(since: loadedThenStopped.last!.at),
              "loaded, then stopped for 33 s: hung since it stopped")
        check(HangRule.judge(stopped + run(1, read: 3_000_000, base: stopped.last!), started: 0, firstStart: false) == .busy,
              "…and reads again: busy")

        // Where it can't be judged: behind, paused by the overlay, no window. Each breaks the quiet stretch.
        var behind = settled
        behind[behind.count - 1].front = false
        check(HangRule.judge(behind, started: 0, firstStart: false) == .unknown, "the player switched away: not judged")
        var paused = settled
        paused[paused.count - 1].paused = true
        check(HangRule.judge(paused, started: 0, firstStart: false) == .unknown, "the overlay holds it (SIGSTOP): not judged")
        var gone = settled
        gone[gone.count - 1].shown = false
        check(HangRule.judge(gone, started: 0, firstStart: false) == .unknown, "no window on the screen: not judged")
        var wasBehind = settled
        wasBehind[12].front = false
        check(HangRule.judge(wasBehind, started: 0, firstStart: false) == .hung(since: settled[13].at),
              "quiet counts only since it came back to the front (30 s later: hung)")
        check(HangRule.judge(Array(wasBehind.prefix(16)), started: 0, firstStart: false) == .quiet(since: settled[13].at),
              "…9 s after: quiet, not hung")
        check(HangRule.judge(run(24, from: 20, sound: nil), started: 0, firstStart: false) == .hung(since: 20),
              "sound unknown: the other signs decide")

        // Counters that go back (a new process under the same game) never count as work.
        var reset = Array(settled.prefix(3))
        reset.append(Sample(at: reset.last!.at + 3, cpu: 0, read: 0, sound: false, shown: true, front: true, paused: false))
        check(HangRule.quiet(from: reset[2], to: reset[3]), "a counter that went back: no work seen")
        check(!HangRule.quiet(from: reset[2], to: reset[2]), "no time between two looks: nothing concluded")

        // What goes into wine.log: only the start of a hang and its end.
        check(HangRule.change(from: .quiet(since: 20), to: .hung(since: 20)) == .hangs(since: 20), "hangs: a line")
        check(HangRule.change(from: .hung(since: 20), to: .hung(since: 20)) == nil, "still hung: no new line")
        check(HangRule.change(from: .hung(since: 20), to: .busy) == .movesAgain(after: 20), "moves again: a line")
        check(HangRule.change(from: .hung(since: 20), to: .unknown) == .movesAgain(after: 20), "switched away from a hung game: a line")
        check(HangRule.change(from: .busy, to: .quiet(since: 3)) == nil && HangRule.change(from: .unknown, to: .busy) == nil, "else: none")
        let line = HangWatch.line("Some Game", change: .hangs(since: 20), samples: settled) ?? ""
        check(line.hasPrefix("Hang watch: Some Game quiet in front for 69 s (CPU 0.0 %, reads 0 KB/s, sound no)"), line)
        check(HangWatch.line("Some Game", change: .movesAgain(after: 20), samples: settled) == "Hang watch: Some Game moves again after 69 s",
              "the line when it moves again")
        check(HangWatch.line("Some Game", change: nil, samples: settled) == nil, "no change: no line")
    }

    /// The looks from outside, on processes of the test's own: never on a game.
    static func outside() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let before = HangWatch.usage(me) else { return check(false, "own usage readable") }
        var sum = 0.0
        for i in 0..<20_000_000 { sum += Double(i % 7) }
        guard let after = HangWatch.usage(me) else { return check(false, "own usage readable again") }
        check(after.cpu > before.cpu && sum > 0, "CPU time grows while working (\(before.cpu) → \(after.cpu) s)")
        check(HangWatch.usage(-1) == nil, "a process that isn't there: nil")
        let sound = HangWatch.playsSound(me)
        check(sound == nil || sound == false, "a test that plays nothing: no sound, or not known to Core Audio")

        let window = { (pid: Int, layer: Int, width: Double, height: Double) -> [String: Any] in
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": width, "Height": height]]
        }
        check(HangWatch.shownOwners([window(10, 0, 1512, 982), window(11, 0, 120, 40), window(12, 25, 1512, 982)]) == [10],
              "shown: a normal window of a game's size; not a small one, not one on another level")
        check(HangWatch.shownOwners([window(13, Int(CGShieldingWindowLevel()), 1512, 982)]) == [13],
              "…and a game that captured the display, on the shielding level (Overwatch)")
    }

    static func main() {
        rule()
        outside()
        print(failures == 0 ? "✓ HangRule" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
