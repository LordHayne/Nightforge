import Foundation

/// How Nightforge rests while nobody uses it (the idea: a Mac mini as a console, on all day). Plugged in
/// or not, Nightforge may be left in front for hours; nothing it looks at matters to anyone then.
enum IdleRest {
    /// No keyboard, mouse or pad for this long: nobody's there. Long enough for a cut scene or a read,
    /// short of the display's own sleep.
    static let awayAfter: TimeInterval = 5 * 60

    static func nobodyThere(idle: TimeInterval) -> Bool { idle >= awayAfter }

    /// Seconds between two looks at the running games (a process list each). A game, a start, a
    /// download or the curtain keep their pace; with nobody there, not even Nightforge in front does.
    /// Coming back or pressing Play cuts the pause short (`LibraryModel.lookNow`).
    static func lookPause(gameEnding: Bool, gameOrStart: Bool, downloading: Bool, inFront: Bool, nobodyThere: Bool) -> Int {
        if gameEnding { return 1 }
        if gameOrStart { return 3 }
        if nobodyThere, !downloading { return 30 }
        return inFront ? 3 : 10
    }
}
