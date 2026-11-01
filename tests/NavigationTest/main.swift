// Checks Home's rail (what's on it, in which order, how many), which section a game's page
// belongs to and where L1/R1 go: tests/NavigationTest/run.sh
import Foundation

@main
struct NavigationTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ install: InstallState, playedDaysAgo: Double? = nil, name: String? = nil) -> Game {
        var game = Game(appID: id, name: name ?? "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func main() {
        // Only what's on the Mac: downloads first, then games played in the last 90 days, latest first.
        let games = [
            game(0, .notInstalled, playedDaysAgo: 1),
            game(1, .installed, playedDaysAgo: 30),
            game(2, .inStore),
            game(3, .installed, playedDaysAgo: 2),
            game(4, .downloading(0.4)),
            game(5, .installed, name: "B never played"),
            game(6, .installed, name: "A never played"),
            game(7, .installed, playedDaysAgo: 200),
        ]
        let rail = HomeRail.pick(games)
        check(rail == [4, 3, 1], "downloads, then played lately; not long ago or never: \(rail)")
        check(!rail.contains(0) && !rail.contains(2), "games not on this Mac stay in the library")

        // A new library with little played lately: other installed games fill up to three.
        let fresh = [game(0, .installed, playedDaysAgo: 400), game(1, .installed, name: "B"), game(2, .installed, name: "A"),
                     game(3, .notInstalled), game(4, .installed, playedDaysAgo: 3)]
        check(HomeRail.pick(fresh) == [4, 0, 2], "filled up: the latest played, then never played by name: \(HomeRail.pick(fresh))")

        // 100+ games: the rail stays short (12 games and the "All games" tile).
        let many = (0..<140).map { game($0, $0 % 3 == 0 ? .notInstalled : .installed, playedDaysAgo: Double($0)) }
        let long = HomeRail.pick(many)
        check(long.count == HomeRail.limit, "at most \(HomeRail.limit) games: \(long.count)")
        check(long.first == 1 && long == long.sorted(), "the most recent first: \(long.prefix(4))")
        check(HomeRail.pick([]).isEmpty, "no games, no rail")

        // Pinned games lead the rail (by name), even ones not played for long; only games on this Mac.
        let pinned = HomeRail.pick(games, pinned: [.steam(5), .steam(0), .steam(7)])
        check(pinned == [5, 7, 4, 3, 1], "pinned first (by name), even unplayed; a pinned game not on the Mac stays off: \(pinned)")
        let pinnedMany = HomeRail.pick(many, pinned: [.steam(139), .steam(137)])
        check(pinnedMany.prefix(2) == [137, 139] && pinnedMany.count == HomeRail.limit, "pins beat recent games and the limit holds: \(pinnedMany.prefix(3))")

        // Hidden and pinned marks survive a restart (UserDefaults), by store and ID.
        let defaults = UserDefaults(suiteName: "nightforge.navigation-test")!
        defaults.removePersistentDomain(forName: "nightforge.navigation-test")
        GameMarks.save([.steam(570), .steam(10)], .hidden, to: defaults)
        GameMarks.save([.steam(1091500), .epic("Fortnite")], .pinned, to: defaults)
        check(GameMarks.load(.hidden, from: defaults) == [.steam(570), .steam(10)], "hidden games come back")
        check(GameMarks.load(.pinned, from: defaults) == [.steam(1091500), .epic("Fortnite")], "pinned games come back, from any store")
        check(GameMarks.load(.hidden, from: UserDefaults(suiteName: "nightforge.navigation-test.empty")!).isEmpty, "nothing marked at first")
        defaults.removePersistentDomain(forName: "nightforge.navigation-test")

        // The Dock menu: installed games played before, the last first, five at most, none hidden.
        let dock = MacIntegration.recentGames(games + many.map { var g = $0; g.lastPlayed = nil; return g }, hidden: [.steam(3)])
        check(dock.map(\.appID) == [1, 7], "only installed and played, hidden left out, latest first: \(dock.map(\.appID))")
        check(MacIntegration.recentGames(many).count == MacIntegration.dockLimit, "five at most")

        // The hint bar's controller line.
        check(ControllerStatus(name: "DualSense Wireless Controller", battery: 0.8).label == "DualSense · 80 %", "DualSense · 80 %")
        check(ControllerStatus(name: "Xbox Wireless Controller", battery: nil).label == "Xbox", "no battery reported: the name alone")
        check(ControllerStatus(name: "DualSense Wireless Controller", battery: 0.1).isLow, "below 20 % is low")
        check(!ControllerStatus(name: "DualSense Wireless Controller", battery: 0.1, charging: true).isLow, "not while charging")

        // A game's page belongs to where it was opened; Back goes there.
        check(Route.detail(gameID: "x", from: .library).level == .library, "a page opened in the library is in the library")
        check(Route.detail(gameID: "x", from: .home).level == .home, "a page opened on Home is on Home")
        check(Route.home.level == .home && Route.library.level == .library, "the levels are their own section")
        check(Route.detail(gameID: "x", from: .home).isDetail && !Route.library.isDetail, "only a game's page is a detail")

        // L1 always Home, R1 always the library – no switching back and forth.
        func section(_ shoulder: PadPart, _ route: Route, inFront: Bool = true, dialog: Bool = false, firstStart: Bool = false) -> Route.Level? {
            InputRouter.section(for: shoulder, route: route, inFront: inFront, dialog: dialog, firstStart: firstStart)
        }
        check(section(.l1, .library) == .home, "L1 in the library: Home")
        check(section(.r1, .home) == .library, "R1 on Home: the library")
        check(section(.l1, .home) == nil, "L1 on Home stays there – it doesn't flip to the library")
        check(section(.r1, .library) == nil, "R1 in the library stays there")
        check(section(.l1, .detail(gameID: "x", from: .library)) == .home, "L1 on a game's page from the library: Home")
        check(section(.r1, .detail(gameID: "x", from: .library)) == .library, "R1 on a game's page: back to the library")
        check(section(.l1, .detail(gameID: "x", from: .home)) == .home, "L1 on a game's page from Home: Home")
        check(section(.l1, .library, dialog: true) == nil && section(.r1, .home, dialog: true) == nil,
              "in a sheet (settings, options) or the downloads: nothing")
        check(section(.r1, .home, firstStart: true) == nil, "not during the first start")
        check(section(.r1, .home, inFront: false) == nil, "not in a game (the pad reaches Nightforge there for the overlay only)")
        check(section(.l3, .library) == nil && section(.l2, .library) == nil, "only the shoulders (L3 + R3 is the overlay, L2/R2 first and last)")
        check(PadSymbols().shoulders == ["LB", "RB"] && PadSymbols(style: .playstation).shoulders == ["L1", "R1"],
              "the chips say LB/RB, or L1/R1 for PlayStation")

        // A press on the sofa brings Nightforge when another app is in front – never over a game.
        check(InputRouter.wakes(inFront: false, overlayOpen: false, gameOn: false, frontIsGame: false),
              "no game, Safari in front: the pad brings Nightforge")
        check(!InputRouter.wakes(inFront: false, overlayOpen: false, gameOn: true, frontIsGame: false), "a game of the library runs: it's the game's")
        check(!InputRouter.wakes(inFront: false, overlayOpen: false, gameOn: false, frontIsGame: true), "another app that's a game: it's that game's")
        check(!InputRouter.wakes(inFront: true, overlayOpen: false, gameOn: false, frontIsGame: false), "Nightforge in front already")
        check(!InputRouter.wakes(inFront: false, overlayOpen: true, gameOn: false, frontIsGame: false), "the overlay has the pad")

        print(failures == 0 ? "✓ Navigation" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
