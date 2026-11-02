// Checks Home's stage: the best starts and their order, when they follow what was played, each
// place's role, and the stage's two-finger steps: tests/StageTest/run.sh
import Foundation

@main
struct StageTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ install: InstallState = .notInstalled, playedDaysAgo: Double? = nil, name: String? = nil) -> Game {
        var game = Game(appID: id, name: name ?? "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func facts(_ installed: Bool = false, _ level: Compatibility.Level = .great, _ controller: ControllerSupport? = .full,
                      mac: Bool = false, score: Int? = nil, gb: Int64 = 10) -> StarterFacts {
        StarterFacts(installed: installed, level: level, controller: controller, mac: mac, metascore: score, size: gb << 30)
    }

    static func main() {
        // The order: installed, runs great, full controller, the Mac version, the Metascore, a smaller download.
        let games = [
            game(0),                       // great, full, Windows, 95
            game(1),                       // great, full, Mac, 87
            game(2),                       // great, full, Mac, 89 – the best start
            game(3, .installed),           // tweaks, but already on the Mac
            game(4),                       // doesn't run on a Mac
            game(5, .inStore),             // not owned
            game(6),                       // great, partial controller
            game(7),                       // not tested
            game(8),                       // great, full, Mac, 89, but bigger than 2
            game(10),                      // doesn't start yet
        ]
        var known: [Int: StarterFacts] = [
            0: facts(score: 95, gb: 11), 1: facts(mac: true, score: 87, gb: 9), 2: facts(mac: true, score: 89, gb: 1),
            3: facts(true, .tweaks), 4: facts(false, .no), 5: facts(score: 99), 6: facts(false, .great, .partial, score: 91),
            7: facts(false, .untested, score: 70), 8: facts(mac: true, score: 89, gb: 30), 10: facts(true, .notYet, score: 99),
        ]
        var vr = game(9)
        vr.isVROnly = true
        known[9] = facts(score: 99)
        let all = games + [vr]
        let order = StarterPicks.order(all) { known[$0.appID]! }
        check(order == [3, 2, 8, 1, 0, 6, 7], "installed, great, controller, Mac, score, size: \(order)")
        check(!order.contains(4) && !order.contains(5) && !order.contains(9) && !order.contains(10),
              "no games that don't run (for good or not yet), aren't owned or need VR")

        // Nothing played yet: "To start with" fills the stage, its first is "Recommended to start".
        let starters = { order }
        let fresh = HomeRail.stage(all, starters: starters)
        check(fresh.rail == order, "a new library: the starts only: \(fresh.rail)")
        check(fresh.startersFrom == 0, "the starts begin at the front")
        check(HomeRail.role(place: 0, startersFrom: fresh.startersFrom, count: fresh.rail.count) == .recommended, "the first is recommended")
        check(HomeRail.role(place: 1, startersFrom: fresh.startersFrom, count: fresh.rail.count) == .starter, "the next ones are starts")
        check(HomeRail.role(place: fresh.rail.count, startersFrom: fresh.startersFrom, count: fresh.rail.count) == .next, "the All games tile has no role")

        // One game played: it leads ("Continue playing"), the starts follow without it ("Up next").
        var oneGame = all
        oneGame[2].install = .installed
        oneGame[2].lastPlayed = Date().addingTimeInterval(-3600)
        let one = HomeRail.stage(oneGame, starters: starters)
        check(one.rail.first == 2 && one.startersFrom == 1, "the played game first, then the starts: \(one.rail)")
        check(one.rail.filter { $0 == 2 }.count == 1, "a played start isn't on the stage twice")
        check(HomeRail.role(place: 0, startersFrom: one.startersFrom, count: one.rail.count) == .played, "played")
        check(HomeRail.role(place: 1, startersFrom: one.startersFrom, count: one.rail.count) == .upNext, "after it: up next")

        // Three played lately: "To start with" is gone, the stage is "Continue playing" only.
        let three = (0..<3).map { game(100 + $0, .installed, playedDaysAgo: Double($0 + 1)) } + all
        let played = HomeRail.stage(three) { StarterPicks.order(three) { known[$0.appID] ?? facts() } }
        check(played.rail == [0, 1, 2] && played.startersFrom == nil, "three played: only them: \(played.rail)")
        check(HomeRail.role(place: 0, startersFrom: played.startersFrom, count: played.rail.count) == .next, "and no roles")

        // Played long ago doesn't count: still a new library.
        let old = [game(200, .installed, playedDaysAgo: 300)] + all
        let oldStage = HomeRail.stage(old) { StarterPicks.order(old) { known[$0.appID] ?? facts(true) } }
        check(oldStage.startersFrom == 0, "played 300 days ago: the starts lead")

        // No starts at all (nothing that runs): the rail fills with installed games as before.
        let none = HomeRail.stage([game(300, .installed), game(301, .installed)]) { [] }
        check(none.rail == [0, 1] && none.startersFrom == nil, "no starts: today's fill: \(none.rail)")

        // Never more than the rail's limit: two played and ten starts.
        let many = (0..<2).map { game(400 + $0, .installed, playedDaysAgo: 1) } + (0..<20).map { game(500 + $0) }
        let full = HomeRail.stage(many) { Array(2..<22) }
        check(full.rail.count == HomeRail.limit && full.startersFrom == 2, "2 played + 10 starts = 12: \(full.rail.count)")

        // The sentence says what it knows.
        check(StarterPicks.reason(facts(true)) != StarterPicks.reason(facts()), "an installed start says so")
        // A game only Epic or GOG has: nobody said how it plays with a controller.
        let unknown = facts(false, .great, nil, mac: true)
        check(([.full, .partial, .none] as [ControllerSupport]).allSatisfy { StarterPicks.reason(unknown) != StarterPicks.reason(facts(false, .great, $0, mac: true)) },
              "controller support not known: the sentence claims none")
        check(StarterPicks.rank(facts(false, .great, .full)).lexicographicallyPrecedes(StarterPicks.rank(facts(false, .great, nil)))
              && StarterPicks.rank(facts(false, .great, nil)).lexicographicallyPrecedes(StarterPicks.rank(facts(false, .great, ControllerSupport.none))),
              "and it ranks between a game with full support and one without")
        check(!StarterPicks.reason(facts(mac: true)).isEmpty && StarterPicks.reason(facts(mac: true)) != StarterPicks.reason(facts()),
              "a Mac version says so")

        // Two fingers sideways: one game per 60 points, the way the covers move.
        var scroll = StageScroll()
        scroll.begin()
        check(scroll.add(30) == 0 && scroll.add(35) == -1, "right: the previous game, after 60 points")
        check(scroll.add(-50) == 0 && scroll.add(-80) == 1, "left: the next game")
        scroll.begin()
        check(scroll.add(-59) == 0, "less than a step does nothing")

        // The text column's rows (FlowRow): whole items, the next line once one is full. The stats of a
        // starter at 1512 pt – Home's column about 520 pt wide (31.10.2026).
        let stats: [CGFloat] = [118, 150, 76, 96, 102]  // Download · up to 12 GB, Metascore, Version, Controller, …
        let lines = FlowRow.lines(widths: stats, available: 520, spacing: 34)
        check(lines == [[0, 1, 2], [3, 4]], "a full line goes on below: \(lines)")
        check(FlowRow.lines(widths: stats, available: 2000, spacing: 34) == [[0, 1, 2, 3, 4]], "a wide column keeps one line")
        check(FlowRow.lines(widths: [600, 50], available: 520, spacing: 12) == [[0], [1]], "one too wide gets a line of its own")
        check(FlowRow.lines(widths: [], available: 520, spacing: 12).isEmpty, "nothing, no lines")

        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ Stage")
    }
}
