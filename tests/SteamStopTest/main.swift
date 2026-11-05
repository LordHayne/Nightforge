// Checks the steps of Engine.stopSteam with a Steam of its own (nothing real is asked or ended):
// tests/SteamStopTest/run.sh
import Foundation

@main
struct SteamStopTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A Steam that is running for `lifetime` asks, installing for `installFor` asks, and what was done to it.
    final class FakeSteam {
        var asks = 0
        var installAsks = 0
        var shutdowns = 0
        var hardStops = 0
        let lifetime: Int?
        let installFor: Int
        /// It ends once its update has been asked about this often (the player quit it, its restart).
        let goneAfterInstallAsks: Int?
        /// It ends when asked to shut down (like Steam normally does), after this many more asks; nil: it ignores it.
        let endsAfterShutdown: Int?
        var shutdownAt: Int?
        /// After its hard stop it is still listed for this many asks (a process a moment from its end); nil: for good.
        let listedAfterHardStop: Int?
        var hardStopAt: Int?

        init(lifetime: Int? = nil, installFor: Int = 0, goneAfterInstallAsks: Int? = nil, endsAfterShutdown: Int? = 1,
             listedAfterHardStop: Int? = 0) {
            self.lifetime = lifetime
            self.installFor = installFor
            self.goneAfterInstallAsks = goneAfterInstallAsks
            self.endsAfterShutdown = endsAfterShutdown
            self.listedAfterHardStop = listedAfterHardStop
        }

        func running() -> Bool {
            asks += 1
            if let hardStopAt {
                guard let listedAfterHardStop else { return true }
                return asks <= hardStopAt + listedAfterHardStop
            }
            if let lifetime, asks > lifetime { return false }
            if let goneAfterInstallAsks, installAsks >= goneAfterInstallAsks { return false }
            if let shutdownAt, let endsAfterShutdown { return asks <= shutdownAt + endsAfterShutdown }
            return true
        }

        func installing() -> Bool {
            installAsks += 1
            return installAsks <= installFor
        }

        func shutdown() { shutdowns += 1; shutdownAt = asks }

        func hardStop() { hardStops += 1; hardStopAt = asks }
    }

    static func stop(_ steam: FakeSteam, installWait: Int = 120, endWait: Int = 20, goneWait: Int = 10) async {
        try? await Engine.stopSteam(URL(fileURLWithPath: "/nonexistent/wine"), running: steam.running, installing: steam.installing,
                                    shutdown: { _ in steam.shutdown() }, hardStop: { _ in steam.hardStop() },
                                    pause: .milliseconds(1), installWait: installWait, endWait: endWait, goneWait: goneWait)
    }

    static func main() async {
        // Not running: nothing is done – above all no "-shutdown", which would start a Steam.
        let off = FakeSteam(lifetime: 0)
        await stop(off)
        check(off.shutdowns == 0 && off.hardStops == 0, "Steam isn't running: no -shutdown, no hard stop")

        // Running, and ends when asked: one -shutdown, no hard stop.
        let normal = FakeSteam()
        await stop(normal)
        check(normal.shutdowns == 1 && normal.hardStops == 0, "a Steam that ends when asked: one -shutdown, no hard stop (\(normal.shutdowns)/\(normal.hardStops))")

        // Running and ignoring it: -shutdown once, then the hard way after the wait.
        let stubborn = FakeSteam(endsAfterShutdown: nil)
        await stop(stubborn, endWait: 5)
        check(stubborn.shutdowns == 1 && stubborn.hardStops == 1, "a Steam that ignores -shutdown: asked once, then wineserver -k (\(stubborn.shutdowns)/\(stubborn.hardStops))")

        // Gone during the wait for its update: no -shutdown (it would start a new one), nothing hard either.
        let gone = FakeSteam(installFor: 100, goneAfterInstallAsks: 3)
        await stop(gone)
        check(gone.shutdowns == 0 && gone.hardStops == 0, "Steam ended while its update went in: no -shutdown for a Steam that isn't there (\(gone.shutdowns)/\(gone.hardStops))")

        // An update that never ends in the log is waited for only so long, then Steam is asked.
        let stale = FakeSteam(installFor: 1_000_000)
        await stop(stale, installWait: 7)
        check(stale.installAsks == 7 && stale.shutdowns == 1, "an update that never ends is waited for 7 pauses, then -shutdown (\(stale.installAsks) looks, \(stale.shutdowns) shutdowns)")

        // Still listed a moment after its hard stop (The Forest's move, 5.11.2026): stopSteam returns only once
        // it's gone, so the move's look right after doesn't take it for a Steam started again.
        let lingering = FakeSteam(endsAfterShutdown: nil, listedAfterHardStop: 3)
        await stop(lingering, endWait: 5)
        check(lingering.hardStops == 1 && !lingering.running(), "a Steam still listed after its hard stop is waited for until it's gone")
        // One that never goes holds nothing up for ever: back after `goneWait`, with one hard stop.
        let stuck = FakeSteam(endsAfterShutdown: nil, listedAfterHardStop: nil)
        await stop(stuck, endWait: 5, goneWait: 4)
        check(stuck.hardStops == 1 && stuck.asks == 1 + 1 + 5 + 4, "a Steam that never goes: one hard stop, then 4 more looks (\(stuck.asks) looks)")

        // What a move says after the stop: nothing once Steam is gone – also a moment late – and otherwise which it is.
        var answers: [Bool?] = [true, true, false]
        var looks = 0
        let late = await Engine.steamStillThere(wait: 5, pause: .milliseconds(1)) { looks += 1; return answers.removeFirst() }
        check(late == nil && looks == 3, "a Steam that is gone a moment late lets the move go on (\(looks) looks)")
        let still = await Engine.steamStillThere(wait: 3, pause: .milliseconds(1)) { true }
        check(still.map { if case .steamDidNotEnd = $0 { return true } else { return false } } == true,
              "a Steam still running after its stop says so – not \"started again\"")
        answers = [nil, nil, nil, nil]
        let unknown = await Engine.steamStillThere(wait: 3, pause: .milliseconds(1)) { answers.removeFirst() }
        check(unknown.map { if case .steamNotKnown = $0 { return true } else { return false } } == true,
              "no process list: \"can't tell\", not \"started again\"")
        check(DriveError.steamDidNotEnd.localizedDescription != DriveError.steamStarted.localizedDescription
              && DriveError.steamNotKnown.localizedDescription != DriveError.steamStarted.localizedDescription,
              "each of the three has its own words")

        // Within five minutes of a game Steam gets 45 s for its cloud saves before the hard stop, otherwise 20.
        let kept = Engine.lastGameActivity
        Engine.lastGameActivity = Date().addingTimeInterval(-60)
        check(Engine.filesEndWait == 45, "a game a minute ago: 45 s for Steam's end")
        Engine.lastGameActivity = Date().addingTimeInterval(-400)
        check(Engine.filesEndWait == 20, "a game seven minutes ago: 20 s")
        Engine.lastGameActivity = nil
        check(Engine.filesEndWait == 20, "no game: 20 s")
        Engine.lastGameActivity = kept

        // The moves take the stop with that wait and the look that tells the three apart, not a single look.
        let sources = ["DriveMoves.swift", "LibraryModel.swift"].map {
            (try? String(contentsOfFile: "Sources/Nightforge/\($0)", encoding: .utf8)) ?? ""
        }.joined()
        check(!sources.contains("guard !Engine.steamMayBeRunning else { throw DriveError.steamStarted }"),
              "no move throws \"started again\" from one look right after the stop")
        check(sources.components(separatedBy: "Engine.stopSteam(wine, endWait: Engine.filesEndWait)\n").count == 4
              && sources.components(separatedBy: "if let still = await Engine.steamStillThere() { throw still }").count == 4,
              "the three Windows Steam paths (move, drive download, forget) stop with filesEndWait and ask steamStillThere")

        print(failures == 0 ? "✓ SteamStop" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
