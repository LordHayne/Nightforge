import Foundation

/// Whether a running game has stopped – alive, in front, but doing nothing – or only takes long to load (docs/ENTWURF-HAENGER.md).
/// Stage 1 only measures (HangWatch, behind a hidden test switch); later the overlay could offer "Quit Game" on a hang.
///
/// Every sign is read from outside the game's process, as anyone may: its CPU time and the bytes it read (the kernel's
/// accounting, `proc_pid_rusage`), whether it plays sound (Core Audio's process list), whether its window is on the
/// screen, whether it's the app in front. Nothing is loaded into the game, nothing asks it anything, so the same holds
/// for games with an anti-cheat.
///
/// The rule is cautious by design: a hang is only a game that is in front, shows its window, isn't held by the
/// overlay's pause, and for a while uses next to no CPU, reads next to nothing and plays no sound. A loading screen
/// reads files or compiles shaders (CPU); one with music plays sound. A game spinning a whole core without a picture
/// isn't caught here: that needs its frames (stage 2).
enum HangRule {
    /// One look at the game, every few seconds. `cpu` and `read` count up from the process's start.
    struct Sample: Equatable {
        var at: TimeInterval
        /// CPU time, user and system, in seconds.
        var cpu: TimeInterval
        /// Bytes read from disk.
        var read: UInt64
        /// It plays sound; nil when that can't be told.
        var sound: Bool?
        /// One of its windows is on the screen, at least 200 × 200.
        var shown: Bool
        /// It's the app in front.
        var front: Bool
        /// The overlay holds it (SIGSTOP), or something else Nightforge knows stops it.
        var paused: Bool
    }

    enum Verdict: Equatable {
        /// Not enough looks yet, or the game isn't where it can be judged (behind, paused, no window).
        case unknown
        /// It works: CPU, disk or sound.
        case busy
        /// Quiet since `since`, not long enough to call it a hang.
        case quiet(since: TimeInterval)
        /// Quiet since `since`, for at least the limit.
        case hung(since: TimeInterval)
    }

    /// Below this a game counts as idle: 3 % of one core. A game drawing a menu uses far more under Wine and Rosetta.
    static let idleCPU = 0.03
    /// Below this per second it reads nothing worth naming (a log, a settings file).
    static let idleRead = 256.0 * 1024
    /// How long a quiet game in front counts as hung.
    static let limit: TimeInterval = 30
    /// The first start of a game, and the first look after its start: room for setup, first shaders and a slow drive.
    static let firstStartLimit: TimeInterval = 90
    /// Nothing is judged in a game's first seconds: it may not have its window or its sound yet.
    static let settling: TimeInterval = 20

    /// The verdict on `samples` (oldest first, the game's start at `started`). `firstStart`: the game hasn't shown a
    /// picture on this Mac before (LaunchHealth), so a long quiet setup is more likely.
    static func judge(_ samples: [Sample], started: TimeInterval, firstStart: Bool) -> Verdict {
        guard let last = samples.last, last.at - started >= settling, last.shown, last.front, !last.paused else { return .unknown }
        // Walk back while the game stays in front, shown and unpaused, and quiet between each pair of looks.
        var quietSince: TimeInterval?
        var index = samples.count - 1
        while index > 0 {
            let newer = samples[index], older = samples[index - 1]
            guard older.shown, older.front, !older.paused, older.at - started >= settling else { break }
            guard quiet(from: older, to: newer) else { break }
            quietSince = older.at
            index -= 1
        }
        guard let since = quietSince else {
            // The last stretch wasn't quiet (or there's only one look in the window that counts).
            return samples.count >= 2 && !quiet(from: samples[samples.count - 2], to: last) ? .busy : .unknown
        }
        return last.at - since >= (firstStart ? firstStartLimit : limit) ? .hung(since: since) : .quiet(since: since)
    }

    /// Between two looks: next to no CPU, next to no reading, no sound at either.
    static func quiet(from older: Sample, to newer: Sample) -> Bool {
        let seconds = newer.at - older.at
        guard seconds > 0 else { return false }
        let cpu = max(0, newer.cpu - older.cpu) / seconds
        let read = Double(newer.read >= older.read ? newer.read - older.read : 0) / seconds
        return cpu < idleCPU && read < idleRead && older.sound != true && newer.sound != true
    }

    /// What changed worth a line in wine.log: a hang begins, or a game that hung works again (`.busy`). Nil otherwise –
    /// also when a hung game merely can't be judged for a while (the overlay opened, it went behind, it was paused:
    /// `.unknown`) or is quiet still; that said "moves again" though nothing moved (W3 of the cross-read, 23.11.2026).
    static func change(from old: Verdict, to new: Verdict) -> Change? {
        switch (old, new) {
        case (.hung, .hung): return nil
        case (_, .hung(let since)): return .hangs(since: since)
        case (.hung(let since), .busy): return .movesAgain(after: since)
        default: return nil
        }
    }

    /// The verdict to remember after a look: a hang stands until the game works again, so a look that can't judge it
    /// (or finds it quiet, not yet long enough) doesn't end it, and its return doesn't log a second "hangs".
    static func remembered(old: Verdict, new: Verdict) -> Verdict {
        if case .hung = old, new != .busy { if case .hung = new { return new }; return old }
        return new
    }

    enum Change: Equatable {
        case hangs(since: TimeInterval)
        case movesAgain(after: TimeInterval)
    }
}
