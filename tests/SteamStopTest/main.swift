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

        init(lifetime: Int? = nil, installFor: Int = 0, goneAfterInstallAsks: Int? = nil, endsAfterShutdown: Int? = 1) {
            self.lifetime = lifetime
            self.installFor = installFor
            self.goneAfterInstallAsks = goneAfterInstallAsks
            self.endsAfterShutdown = endsAfterShutdown
        }

        func running() -> Bool {
            asks += 1
            if hardStops > 0 { return false }
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

        func hardStop() { hardStops += 1 }
    }

    static func stop(_ steam: FakeSteam, installWait: Int = 120, endWait: Int = 20) async {
        try? await Engine.stopSteam(URL(fileURLWithPath: "/nonexistent/wine"), running: steam.running, installing: steam.installing,
                                    shutdown: { _ in steam.shutdown() }, hardStop: { _ in steam.hardStop() },
                                    pause: .milliseconds(1), installWait: installWait, endWait: endWait)
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

        print(failures == 0 ? "✓ SteamStop" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
