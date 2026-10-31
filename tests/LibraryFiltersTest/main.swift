// Checks LibraryFilters (each filter, combined, store hits) and LibrarySection (which groups the
// grid shows for each order): tests/LibraryFiltersTest/run.sh
import Foundation

@main
struct LibraryFiltersTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ name: String, _ install: InstallState, size: Int64 = 0, controller: ControllerSupport = .none,
                     mac: Bool = false) -> Game {
        var game = Game(appID: id, name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: size)
        game.install = install
        game.controller = controller
        game.platform = mac ? .mac : .windows
        if id == 2 { game.playModes = [.single, .localCoop, .splitScreen] }
        return game
    }

    static func epic(_ appName: String, _ name: String, _ install: InstallState) -> Game {
        var game = Game(gameID: .epic(appName), name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 7)
        game.install = install
        return game
    }

    static func main() {
        let games = [
            game(1, "Valheim", .installed, size: 5, controller: .full, mac: true),
            game(2, "Palworld", .installed, size: 30, controller: .full),
            game(3, "Anno 2070", .downloading(0.5), size: 12),
            game(4, "7 Days to Die", .notInstalled, size: 20, controller: .full, mac: true),
            game(5, "Battlefield 6", .notInstalled, size: 90),
            game(6, "Hades II", .inStore),
            epic("Potoo", "Overcooked! 2", .notInstalled),
        ]
        // Rated by app ID: 1 and 4 run great, 5 doesn't run.
        let level: (Game) -> Compatibility.Level = { [1: .great, 4: .great, 5: .no][$0.appID] ?? .untested }
        func shown(_ filters: LibraryFilters) -> [Int] {
            filters.sorted(games.filter { filters.admits($0, level: level) }).map(\.appID)
        }

        check(shown(LibraryFilters()) == [1, 2, 3, 4, 5, 6, 0], "no filter: everything, in the library's order")
        check(!LibraryFilters().narrows, "the default leaves nothing out")
        check(shown(LibraryFilters(on: [.onMac])) == [1, 2, 3], "Only on this Mac: installed and downloading")
        check(shown(LibraryFilters(on: [.great])) == [1, 4], "Runs great")
        check(shown(LibraryFilters(on: [.controller])) == [1, 2, 4], "Controller: full support only")
        check(shown(LibraryFilters(on: [.mac])) == [1, 4], "Mac version")
        check(shown(LibraryFilters(on: [.couch])) == [2], "Two on one Mac: local co-op or split screen")
        check(shown(LibraryFilters(on: [.onMac, .controller, .mac])) == [1], "filters combine")
        check(shown(LibraryFilters(store: .epic)) == [0], "one store (Epic's game has no Steam app ID)")
        check(shown(LibraryFilters(store: .steam, on: [.great])) == [1, 4], "a store and a filter combine")
        check(LibraryFilters(store: .gog).narrows && LibraryFilters(on: [.mac]).narrows, "the store and each filter narrow")

        var byName = LibraryFilters(sort: .name)
        check(byName.sorted(games).map(\.name) == ["7 Days to Die", "Anno 2070", "Battlefield 6", "Hades II", "Overcooked! 2", "Palworld", "Valheim"],
              "by name: \(byName.sorted(games).map(\.name))")
        byName.toggle(.great)
        byName.store = .epic
        check(byName.switchesOff == LibraryFilters(store: .epic, sort: .name), "all filters off keeps the store and the order")
        check(byName.cleared == LibraryFilters(sort: .name), "clearing keeps the order")
        byName.toggle(.great)
        check(byName.on.isEmpty, "a second toggle takes it off")
        check(LibraryFilters.Sort.recent.next == .name && LibraryFilters.Sort.size.next == .recent, "A steps through the orders")
        check(LibraryFilters(sort: .size).sorted(games).map(\.appID) == [5, 2, 4, 3, 0, 1, 6], "largest first")

        // The grid's groups.
        let recent = LibrarySection.make(games, sort: .recent, searching: false, hidden: false)
        check(recent.map(\.id) == ["installed", "downloading", "library", "store"] && recent[0].items == [0, 1] && recent[3].items == [5],
              "recently played: installed, downloading, the rest, store: \(recent.map(\.id))")
        let named = LibrarySection.make(games, sort: .name, searching: false, hidden: false)
        check(named.map(\.id) == ["all", "store"] && named[0].items == [0, 1, 2, 3, 4, 6], "by name: one list, store hits after it")
        let search = LibrarySection.make(games, sort: .recent, searching: true, hidden: false)
        check(search.map(\.id) == ["results", "store"] && search[0].items.count == 6, "a search: one list of hits, best first")
        let hidden = LibrarySection.make(Array(games.prefix(2)), sort: .recent, searching: false, hidden: true)
        check(hidden.map(\.id) == ["hidden"], "hidden games: one list")
        check(LibrarySection.make([], sort: .recent, searching: false, hidden: false).isEmpty, "no games, no groups")

        // The grid layout follows the groups: each starts its own row.
        let layout = GridLayout(sections: named.map(\.items), columns: 3)
        check(layout.rows == [[0, 1, 2], [3, 4, 6], [5]], "rows follow the groups: \(layout.rows)")

        print(failures == 0 ? "✓ LibraryFilters" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
