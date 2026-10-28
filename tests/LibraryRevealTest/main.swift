// Checks LibraryReveal: owned games counted by level, store hits and demos of games not owned left
// out, games that don't run split into GeForce Now and VR, the headline: tests/LibraryRevealTest/run.sh
import Foundation

@main
struct LibraryRevealTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ install: InstallState = .installed, vr: Bool = false, cloud: Bool = false, demoOf: Int? = nil) -> Game {
        var game = Game(appID: id, name: "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = install
        game.isVROnly = vr
        game.demoOf = demoOf
        if cloud { game.antiCheatBlock = AntiCheatBlock(antiCheat: ["EAC"], geforceNow: "x") }
        return game
    }

    static func main() {
        let reveal = LibraryReveal([
            (game(1), .great), (game(2), .great), (game(3), .tweaks), (game(4, .notInstalled), .untested),
            (game(5, .notInstalled, cloud: true), .no), (game(6, .notInstalled, vr: true), .no), (game(7, .notInstalled), .no),
            (game(8, .inStore), .great), (game(9, .notInstalled, demoOf: 900), .untested),
        ])
        check(reveal.total == 7, "owned games only: \(reveal.total)")
        check(reveal.running == 3, "great and tweaks run: \(reveal.running)")
        check(reveal.untested == 1 && reveal.no == 3, "untested 1, not running 3")
        check(reveal.cloud == 1 && reveal.vr == 1, "one on GeForce Now, one VR: \(reveal.cloud) \(reveal.vr)")
        check(LibraryReveal([]).total == 0, "an empty library")
        check(reveal.headline == L10n.t("%ld of your %ld games run here", 3, 7), "the headline: \(reveal.headline)")
        check(LibraryReveal(great: 1).headline == L10n.t("%ld of your 1 game runs here", 1), "one game: \(LibraryReveal(great: 1).headline)")
        check(LibraryReveal().headline == L10n.t("Steam is connected"), "no games: Steam is connected")

        print(failures == 0 ? "✓ LibraryReveal" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
