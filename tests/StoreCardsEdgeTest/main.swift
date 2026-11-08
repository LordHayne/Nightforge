// The search across stores against titles and terms as players and stores write them: three stores with
// one game, the same title twice in one store, empty and symbol-only terms, umlauts and accents, what's already
// owned: tests/StoreCardsEdgeTest/run.sh
import Foundation

@main
struct StoreCardsEdgeTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func hit(_ provider: Provider, _ id: String, _ name: String, page: String? = nil) -> Game {
        var game = Game(gameID: GameID(provider: provider, id: id), name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = .inStore
        game.storePage = page.flatMap(URL.init(string:))
        return game
    }

    static func owned(_ provider: Provider, _ id: String, _ name: String) -> Game {
        var game = hit(provider, id, name)
        game.install = .installed
        return game
    }

    static func main() {
        TestDefaults.useWorkFolder()
        cards()
        ranks()
        addresses()
        whatsOwned()
        print(failures == 0 ? "✓ Store cards against odd titles" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func cards() {
        check(StoreHits.cards([:], term: "x").isEmpty, "no store answered: no cards")
        let three: [Provider: [Game]] = [
            .steam: [hit(.steam, "1", "The Witcher 3: Wild Hunt")],
            .gog: [hit(.gog, "2", "The Witcher 3: Wild Hunt — Game of the Year Edition", page: "https://www.gog.com/game/the_witcher_3_wild_hunt_game_of_the_year_edition")],
            .epic: [hit(.epic, "e3", "The Witcher 3: Wild Hunt")],
        ]
        let one = StoreHits.cards(three, term: "witcher")
        check(one.count == 1 && one.first?.providers.count == 3, "one game in three stores is one card: \(one.map(\.name))")

        let twice = StoreHits.cards([.steam: [hit(.steam, "1", "Tomb Raider"), hit(.steam, "2", "Tomb Raider")]], term: "tomb")
        check(twice.count == 2, "a store's two games of one title stay two")

        // "Sudoomo" only holds the word; "Doom" starts one: whichever store and in whatever order they came.
        let ordered = StoreHits.cards([.gog: [hit(.gog, "1", "Doom Eternal")], .steam: [hit(.steam, "2", "Sudoomo Arena"), hit(.steam, "3", "Doom")]], term: "doom")
        check(ordered.last?.name == "Sudoomo Arena", "the weaker fit last, whichever store: \(ordered.map(\.name))")
        let symbols = hit(.steam, "9", "???")
        check(StoreHits.cards([.steam: [symbols]], term: "x").count == 1, "a title of symbols alone doesn't crash or vanish")
    }

    static func ranks() {
        check(Search.rank(name: "Überleben im Wald", query: "uberleben") == 0, "accents don't matter")
        check(Search.rank(name: "Pokémon", query: "pokemon") == 0, "nor here")
        check(Search.rank(name: "Baldur's Gate 3", query: "bg3") == 1, "initials and numbers")
        check(Search.rank(name: "Half-Life 2", query: "half life") == 0, "a hyphen is a word break")
        check(Search.rank(name: "S.T.A.L.K.E.R. 2", query: "stalker") != nil, "dots in a title: found")
        check(Search.rank(name: "Doom", query: "   ") == 0, "white space alone is no search")
        check(Search.rank(name: "Doom", query: "zzzz") == nil, "a name that doesn't fit is out")
        check(StoreSearch.fit("Doom", "zzzz") == StoreSearch.unrelated, "and unrelated")
        check(StoreSearch.fit("Doom 3", "doom zzzz") == 3, "one word of two fits: a weak hit, not none")
    }

    static func addresses() {
        for term in ["Mär & Sage+", "a/b?c=d#e", "🎮 Spiel", "\"quotes\""] {
            guard let url = StoreHits.epicSearch(term), url.absoluteString.hasPrefix("https://store.epicgames.com/browse?") else {
                check(false, "\(term): an Epic address")
                continue
            }
            let back = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            check(back == term, "\(term) comes back whole from Epic's address: \(back ?? "nil")")
            check(GOGSearch.url(term, region: "AT", german: true) != nil, "\(term): a GOG address")
        }
    }

    static func whatsOwned() {
        let library = [owned(.steam, "570", "Dota 2"), owned(.epic, "Abc", "Control"), owned(.battlenet, "pro", "Overwatch")]
        let mine = OwnedGames(library)
        check(mine.game(of: hit(.steam, "570", "Dota 2")) == .steam(570), "the same ID")
        check(mine.game(of: hit(.gog, "77", "Control")) == .epic("Abc"), "the title, in another store")
        check(mine.game(of: hit(.steam, "2357570", "Overwatch")) == .battlenet("pro"), "Overwatch on Steam, held in Battle.net")
        check(mine.game(of: hit(.steam, "12345", "Something Else")) == nil, "a game the player doesn't have isn't theirs")

        var store = owned(.steam, "111", "Hades")
        store.install = .inStore
        check(OwnedGames([store]).game(of: hit(.gog, "55", "Hades")) == nil, "a store entry in the list isn't the player's game")
    }
}
