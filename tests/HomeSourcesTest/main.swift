// Checks what Settings › Home does to Home's stage (each source on and off, the pinned games' order),
// and that the page can be used with the pad: tests/HomeSourcesTest/run.sh
import AppKit

@main
struct HomeSourcesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Source = HomeSources.Source

    static func game(_ id: Int, _ install: InstallState = .installed, playedDaysAgo: Double? = nil, name: String? = nil) -> Game {
        var game = Game(appID: id, name: name ?? "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func sources(off: [Source] = [], on: [Source] = []) -> HomeSources {
        var sources = HomeSources()
        off.forEach { sources.set($0, false) }
        on.forEach { sources.set($0, true) }
        return sources
    }

    /// Pinned (0, 1), downloading (2), played lately (3), played long ago (4), on the list and not
    /// downloaded (5), on the list and installed (6), in the store and on the list (7).
    static let games = [
        game(0, playedDaysAgo: 400, name: "Zeta"), game(1, playedDaysAgo: 2, name: "Alpha"), game(2, .downloading(0.3), name: "Loading"),
        game(3, playedDaysAgo: 1, name: "Lately"), game(4, playedDaysAgo: 300, name: "Old"), game(5, .notInstalled, name: "Queued"),
        game(6, name: "Queued too"), game(7, .inStore, name: "Not mine"),
    ]
    static let pinned: Set<GameID> = [.steam(0), .steam(1)]
    static let later: Set<GameID> = [.steam(5), .steam(6), .steam(7)]

    static func rail(_ sources: HomeSources, order: [GameID] = [], fill: Bool = false, off: [GameID: Date] = [:]) -> [Int] {
        HomeRail.pick(games, pinned: pinned, off: off, fill: fill, sources: sources, pinOrder: order, later: later)
    }

    static func main() {
        TestDefaults.useWorkFolder()
        kept()
        eachSource()
        order()
        starters()
        thePage()
        print(failures == 0 ? "✓ HomeSources" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func kept() {
        let defaults = TestDefaults.suite("sources")
        let fresh = HomeSources.load(from: defaults)
        check(fresh == HomeSources(), "nothing stored: the defaults")
        check(Source.allCases.filter { !fresh.isOn($0) } == [.later], "only Play Later starts off, as on the board")
        var changed = fresh
        changed.set(.recent, false)
        changed.set(.later, true)
        changed.save(to: defaults)
        check(HomeSources.load(from: defaults) == changed, "kept")
        // A source that came later than what's stored starts with its own default.
        defaults.removeObject(forKey: Source.key(.starters))
        check(HomeSources.load(from: defaults).isOn(.starters), "a missing key is its default")
        let order: [GameID] = [.steam(3), .epic("Fortnite"), .gog("12")]
        HomePinOrder.save(order, to: defaults)
        check(HomePinOrder.load(from: defaults) == order, "the order comes back, from any store")
        check(Set(Source.allCases.map(\.title)).count == Source.allCases.count, "each source its own name")
        check(Source.recent.note == L10n.t("the last %ld days", HomeRail.recentDays), "the 90 days are the rail's own")
    }

    static func eachSource() {
        check(rail(HomeSources()) == [1, 0, 2, 3], "default: pinned, downloads, lately, no Play Later: \(rail(HomeSources()))")
        check(rail(sources(off: [.pinned])) == [2, 3, 1], "pinned off: an ordinary game, the one played lately stays: \(rail(sources(off: [.pinned])))")
        check(rail(sources(off: [.downloads])) == [1, 0, 3], "downloads off: not there, without saying so elsewhere")
        check(rail(sources(off: [.recent])) == [1, 0, 2], "recently played off")
        let list = rail(sources(on: [.later]))
        check(list == [1, 0, 2, 3, 5, 6], "Play Later on: last, by name, not downloaded too, no store hit: \(list)")
        check(rail(sources(off: [.pinned, .downloads, .recent])) == [], "the three off and Play Later off: nothing")
        check(rail(sources(off: [.pinned, .downloads, .recent], on: [.later])) == [5, 6], "only the list")
        let allOff = sources(off: Source.allCases)
        check(rail(allOff, fill: true).isEmpty, "all off: an empty stage, only the All games tile: \(rail(allOff, fill: true))")

        let taken: [GameID: Date] = [.steam(6): Date()]
        check(!rail(sources(on: [.later]), off: taken).contains(6), "taken off Home: not back through the list")
        var twice = sources(on: [.later])
        twice.set(.pinned, true)
        let both = HomeRail.pick(games, pinned: pinned, fill: false, sources: twice, later: [.steam(0), .steam(3)])
        check(Set(both).count == both.count, "on two sources: once")
    }

    static func order() {
        check(rail(HomeSources(), order: [.steam(0), .steam(1)]).prefix(2) == [0, 1], "the player's order")
        check(rail(HomeSources(), order: [.steam(1)]).prefix(2) == [1, 0], "in the order first, the others behind")
        check(rail(HomeSources(), order: []).prefix(2) == [1, 0], "no order: by name, as before")
        var byName = pinned
        byName.insert(.steam(4))
        let three = HomeRail.pick(games, pinned: byName, fill: false, pinOrder: [.steam(4)])
        check(Array(three.prefix(3)) == [4, 1, 0], "a game pinned later: behind the ordered, those by name: \(three)")

        var card = game(20, name: "Both")
        var epic = Game(gameID: .epic("both"), name: "Both", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        epic.install = .installed
        card.others = [epic]
        let cards = [game(21, name: "A"), card]
        check(HomePinOrder.sorted([0, 1], in: cards, order: [.epic("both"), .steam(21)]) == [1, 0], "a game goes by any of its stores")

        let list = [game(1, name: "A"), game(2, name: "B"), game(3, name: "C")]
        let gone = GameID.gog("not here")
        check(HomePinOrder.moved(list, index: 1, by: -1, order: [gone]) == [.steam(2), .steam(1), .steam(3), gone], "up, and what isn't here keeps its place behind")
        check(HomePinOrder.moved(list, index: 1, by: 1, order: []) == [.steam(1), .steam(3), .steam(2)], "down")
        check(HomePinOrder.moved(list, index: 0, by: -1, order: []) == nil, "not past the top")
        check(HomePinOrder.moved(list, index: 2, by: 1, order: []) == nil, "not past the end")
        check(HomePinOrder.moved(list, index: 0, by: 0, order: []) == nil, "no move")
        let two = HomePinOrder.moved(cardsOfTwo(card), index: 1, by: -1, order: []) ?? []
        check(two == [.steam(20), .epic("both"), .steam(21)], "a game from two stores moves with both: \(two)")
    }

    static func cardsOfTwo(_ card: Game) -> [Game] { [game(21, name: "A"), card] }

    static func starters() {
        let few = [game(0, name: "One"), game(1, name: "Two"), game(2, name: "Three"), game(3, name: "Four")]
        let on = HomeRail.stage(few, starters: { [1, 2] })
        check(on.rail == [1, 2] && on.startersFrom == 0, "on: a short Home fills with suggestions")
        var withoutStarters = HomeSources()
        withoutStarters.set(.starters, false)
        let off = HomeRail.stage(few, sources: withoutStarters, starters: { check(false, "not even asked"); return [1, 2] })
        check(off.rail.isEmpty && off.startersFrom == nil, "off: no suggestions")
        check(HomeRail.pick(few, sources: withoutStarters).isEmpty, "and no filling up with other installed games")
        check(HomeRail.pick(few).count == HomeRail.minimum, "on: filling up as before")
    }

    static func thePage() {
        check(SettingsView.Tab.allCases.prefix(2) == [.stores, .home], "the tab, beside Stores")
        check(SettingsView.Tab.home.label == L10n.t("Home"), "named like the level")
        let page = (try? String(contentsOfFile: "Sources/Nightforge/HomeSettings.swift", encoding: .utf8)) ?? ""
        check(page.contains(#".padFocus("settings.home.\(source.rawValue)", toggle:"#), "every switch on the pad's map")
        check(page.contains(#".padFocus("settings.home.pin.\(game.id)."#), "every arrow too, by the game: the highlight goes along")
    }
}
