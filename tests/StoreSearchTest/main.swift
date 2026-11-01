// Checks which Steam store hits the library search shows, from the store's real answers (fixtures
// from 1.11.2026, cc=AT, l=german; long texts cut): the "games only" search, the search API and
// appdetails. tests/StoreSearchTest/run.sh
import Foundation

@main
struct StoreSearchTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func fixture(_ name: String) -> Any? {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/\(name)")
        guard let data = try? Data(contentsOf: here) else {
            check(false, "fixture \(name) missing")
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func details(_ appID: Int) -> StoreSearch.Hit? {
        StoreSearch.detailsHit(fixture("appdetails-\(appID).json"), appID: appID)
    }

    static func main() {
        reading()
        benchmarkByName()
        blackMythWukong()
        rules()
        print(failures == 0 ? "✓ StoreSearch" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// What each answer says.
    static func reading() {
        let games = StoreSearch.gameHits(fixture("search-results-benchmark-tool.json"))
        check(games?.map(\.appID) == [4122050] && games?.first?.name == "Automat", "games only: \(String(describing: games))")
        let detailed = StoreSearch.detailedHits(fixture("storesearch-benchmark-tool.json"))
        check(detailed?.map(\.appID) == [3132990], "search API: \(String(describing: detailed))")
        check(detailed?.first?.name == "Black Myth: Wukong Benchmark Tool" && detailed?.first?.macNative == false,
              "search API's name and platforms: \(String(describing: detailed?.first))")
        check(detailed?.first?.price == nil && detailed?.first?.metascore == nil, "free, no score: no price, no score")

        let benchmark = details(3132990)
        check(benchmark?.type == "game", "appdetails: the benchmark is a game: \(String(describing: benchmark?.type))")
        check(benchmark?.free == true && benchmark?.price != nil, "… and free, with a price line")
        check(benchmark?.macNative == false && benchmark?.controller == ControllerSupport.none, "… Windows only, no controller")
        let soundtrack = details(3288260)
        check(soundtrack?.type == "music" && soundtrack?.free == false, "soundtrack: \(String(describing: soundtrack))")
        let upgrade = details(2672610)
        check(upgrade?.type == "dlc" && upgrade?.price == "10,--€" && upgrade?.controller == .full, "DLC: \(String(describing: upgrade))")

        check(StoreSearch.detailsHit(fixture("appdetails-3132990.json"), appID: 3288260) == nil, "another app's answer: nothing")
        check(StoreSearch.detailsHit(["1": ["success": false]], appID: 1) == nil, "success false: nothing")
        check(StoreSearch.gameHits(nil) == nil && StoreSearch.detailedHits(["desc": ""]) == nil, "no answer: nil, not empty")
    }

    /// The live test of 1.11.: the full name found "Automat" and not the free benchmark.
    static func benchmarkByName() {
        let term = "Black Myth: Wukong Benchmark Tool"
        guard let games = StoreSearch.gameHits(fixture("search-results-benchmark-tool.json")),
              let detailed = StoreSearch.detailedHits(fixture("storesearch-benchmark-tool.json")),
              let benchmark = details(3132990)
        else { return check(false, "benchmark fixtures") }

        let asked = StoreSearch.unlisted(term, games: games, detailed: detailed)
        check(asked.map(\.appID) == [3132990], "appdetails is asked about the benchmark: \(asked.map(\.appID))")
        let hits = StoreSearch.merged(term, games: games, detailed: detailed, checked: [3132990: benchmark])
        check(hits.map(\.appID) == [3132990], "the benchmark, without Automat: \(hits.map(\.name))")
        check(hits.first?.free == true, "… free, so its button adds it")

        // appdetails didn't answer: no word in common anywhere is taken for a typo, the store's guess stays.
        let unchecked = StoreSearch.merged(term, games: games, detailed: detailed, checked: [:])
        check(unchecked.map(\.appID) == [4122050], "without appdetails, as before: \(unchecked.map(\.name))")
    }

    /// The game, its benchmark, its soundtrack and an upgrade DLC.
    static func blackMythWukong() {
        let term = "Black Myth Wukong"
        guard let games = StoreSearch.gameHits(fixture("search-results-black-myth-wukong.json")),
              let detailed = StoreSearch.detailedHits(fixture("storesearch-black-myth-wukong.json"))
        else { return check(false, "Black Myth: Wukong fixtures") }
        check(games.count == 14 && !games.contains { $0.appID == 3132990 }, "games only doesn't list the benchmark: \(games.count)")

        let asked = StoreSearch.unlisted(term, games: games, detailed: detailed)
        check(asked.map(\.appID) == [3288260, 3132990, 2672610], "asked: soundtrack, benchmark, DLC – not the game: \(asked.map(\.appID))")
        let checked = Dictionary(uniqueKeysWithValues: asked.compactMap { details($0.appID) }.map { ($0.appID, $0) })
        check(checked.count == 3, "three answers: \(checked.keys.sorted())")
        let hits = StoreSearch.merged(term, games: games, detailed: detailed, checked: checked)
        check(hits.prefix(2).map(\.appID) == [2358720, 3132990], "the game, then its benchmark: \(hits.map(\.name))")
        check(!hits.contains { $0.appID == 3288260 || $0.appID == 2672610 }, "no soundtrack, no DLC")
        check(hits.first?.macNative == false, "the game keeps what the search API says of it")
        let names = hits.map(\.name)
        check(!names.contains("Dharmayuddha - The Righteous War") && !names.contains("Spheroll"), "no word in common: gone: \(names)")
        let mystery = names.firstIndex { $0.hasSuffix("Black Mystery: Wujing") }
        check(mystery == 2, "a word in common (Black): after the full matches: \(names)")
    }

    /// Typos, a full list, the order.
    static func rules() {
        func hit(_ id: Int, _ name: String) -> StoreSearch.Hit { StoreSearch.Hit(appID: id, name: name) }

        let typo = [hit(1, "The Witcher 3: Wild Hunt"), hit(2, "Thronebreaker: The Witcher Tales")]
        check(StoreSearch.merged("witchr", games: typo, detailed: [], checked: [:]).map(\.appID) == [1, 2],
              "a typo keeps the store's guesses, in its order")

        let witchers = (1...12).map { hit($0, "Witcher \($0)") }
        let extra = [hit(99, "Witcher Collection")]
        check(StoreSearch.unlisted("witcher", games: witchers, detailed: extra).isEmpty,
              "twelve listed games match fully: appdetails isn't asked")
        check(StoreSearch.unlisted("witcher", games: Array(witchers.prefix(11)), detailed: extra).map(\.appID) == [99],
              "eleven: it is")
        check(StoreSearch.unlisted("witcher", games: [], detailed: [hit(5, "Gwent")]).isEmpty,
              "a name without the search isn't asked about")

        let mixed = [hit(1, "Undark"), hit(2, "Dark Souls III"), hit(3, "Darkest Dungeon")]
        check(StoreSearch.merged("dark", games: mixed, detailed: [], checked: [:]).map(\.appID) == [2, 3, 1],
              "word starts before words inside a name")
        let notGame = StoreSearch.Hit(appID: 7, name: "Dark Tool", type: "software")
        check(StoreSearch.merged("dark", games: [], detailed: [hit(7, "Dark Tool")], checked: [7: notGame]).isEmpty,
              "appdetails says software: left out")
        check(StoreSearch.merged("dark", games: Array(repeating: hit(2, "Dark Souls III"), count: 1) + (10...30).map { hit($0, "Dark \($0)") },
                                 detailed: [], checked: [:]).count == 12, "twelve at most")
    }
}
