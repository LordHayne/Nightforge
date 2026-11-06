// Checks the library's search across the stores, from GOG's real answers (fixtures from 6.11.2026,
// countryCode=AT, EUR, cut to the fields that matter; no network): what's read from GOG's catalog,
// one list from several stores, what's already the player's, and that a slow or failing store
// holds up nothing. tests/StoreHitsTest/run.sh
import Foundation

@main
struct StoreHitsTest {
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

    static func main() async {
        reading()
        requests()
        hitsAsGames()
        oneList()
        ownGames()
        sections()
        await slowAndFailingStores()
        print(failures == 0 ? "✓ StoreHits" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func steam(_ id: Int, _ name: String) -> Game {
        StoreHits.game(StoreHit(StoreSearch.Hit(appID: id, name: name)), info: nil, blocks: [:])
    }

    static func gog(_ id: String, _ name: String, slug: String? = nil, mac: Bool = false) -> Game {
        var hit = StoreHit(gameID: .gog(id), name: name, page: URL(string: "https://www.gog.com/de/game/\(slug ?? "game_\(id)")"))
        hit.macNative = mac
        return StoreHits.game(hit, info: nil, blocks: [:])
    }

    /// A game of the player's in `store`.
    static func own(_ id: GameID, _ name: String) -> Game {
        var game = Game(gameID: id, name: name, bottle: Engine.bottle, steamRoot: Engine.steamRoot, steamExeWindowsPath: "",
                        installDir: Engine.steamRoot, sizeOnDisk: 0)
        game.install = .notInstalled
        return game
    }

    /// What's read from GOG's catalog.
    static func reading() {
        let witcher = GOGSearch.hits(fixture("gog-witcher.json"), term: "witcher") ?? []
        let names = witcher.map(\.name)
        check(names.first == "The Witcher: Enhanced Edition" || names.first == "The Witcher 3: Wild Hunt — Remastered", "best fits first: \(names)")
        check(names.contains("The Witcher 3: Wild Hunt — Remastered"), "a pack that is the game itself stays")
        check(names.contains("Reigns: The Witcher"), "the word anywhere in the title fits")
        check(!names.contains("Creature Kitchen") && !names.contains("The Witch's Love Diary"), "GOG's guesses go: \(names)")
        check(!names.contains { $0.contains("Bundle") }, "bundles go: \(names)")
        check(witcher.count <= 12, "no more than a store's share")

        let first = witcher.first { $0.name == "The Witcher: Enhanced Edition" }
        check(first?.gameID == .gog("1207658924"), "the ID gogdl uses")
        check(first?.macNative == true, "osx is a Mac version")
        check(first?.price == "7,99\u{a0}€", "the price as GOG writes it: \(first?.price ?? "–")")
        check(first?.page?.absoluteString == "https://www.gog.com/de/game/the_witcher", "the store link")
        check(first?.art?.cover?.host == "images.gog-statics.com" && first?.art?.hero != nil, "both covers")
        check(witcher.first { $0.name == "The Witcher 3: Wild Hunt — Remastered" }?.macNative == false, "no osx, no Mac version")

        let cyberpunk = (GOGSearch.hits(fixture("gog-cyberpunk.json"), term: "cyberpunk") ?? []).map(\.name)
        check(cyberpunk.contains("Cyberpunk 2077"), "Cyberpunk 2077 is a pack on GOG, and stays: \(cyberpunk)")
        check(!cyberpunk.contains("Cyberpunk 2077: Phantom Liberty") && !cyberpunk.contains { $0.contains("Piggyback") }, "add-ons go: \(cyberpunk)")

        let early = GOGSearch.hits(["products": [
            product("1", "Knight Witch", type: "game"), product("2", "Knight Witch Deluxe Edition", type: "pack"),
            product("3", "Knight Witch Collection", type: "pack"), product("4", "Other Witch Pack", type: "pack"),
        ]], term: "witch")?.map(\.name)
        check(early == ["Knight Witch", "Other Witch Pack"], "a pack of a game that's listed goes: \(early ?? [])")

        let upcoming = GOGSearch.hits(fixture("gog-upcoming.json"), term: "the") ?? []
        check(upcoming.first { $0.name == "After the Wane" }?.price == L10n.t("Coming soon"), "not out yet: no price")
        check(upcoming.first { $0.name == "Thief: The Dark Project Remastered" }?.price?.contains("29,99") == true, "a pre-order has its price")

        let gwent = GOGSearch.hits(fixture("gog-gwent.json"), term: "gwent") ?? []
        check(gwent.first { $0.name.hasPrefix("GWENT: The Witcher") }?.price == L10n.t("Free"), "free, not 0,00 €")

        check(GOGSearch.hits(fixture("gog-nothing.json"), term: "zzqq")?.isEmpty == true, "an answer without games: empty")
        check(GOGSearch.hits(nil, term: "x") == nil && GOGSearch.hits(["error": "x"], term: "x") == nil, "no answer: nil, not empty")

        var elsewhere = product("9", "Witch", type: "game")
        elsewhere["storeLink"] = "https://gog.example.com/game/witch"
        var plain = product("8", "Witch", type: "game")
        plain["storeLink"] = "http://www.gog.com/game/witch"
        var unnamed = product("not-a-number", "Witch", type: "game")
        unnamed["coverVertical"] = "http://images.gog-statics.com/x.jpg"
        check(GOGSearch.hits(["products": [elsewhere, plain, unnamed]], term: "witch")?.isEmpty == true, "only GOG's own https pages, numeric IDs")
        var cover = product("7", "Witch", type: "game")
        cover["coverVertical"] = "http://images.gog-statics.com/x.jpg"
        check(GOGSearch.hits(["products": [cover]], term: "witch")?.first?.art?.cover == nil, "no plain http for covers")
    }

    static func product(_ id: String, _ title: String, type: String) -> [String: Any] {
        ["id": id, "title": title, "productType": type, "operatingSystems": ["windows"], "storeLink": "https://www.gog.com/en/game/x\(id)"]
    }

    /// What goes out.
    static func requests() {
        let url = GOGSearch.url("a&b+c d", region: "AT", german: true)?.absoluteString ?? ""
        check(url.hasPrefix("https://catalog.gog.com/v1/catalog?"), url)
        check(url.contains("query=like:a%26b%2Bc%20d"), "the search whole, not read as parameters: \(url)")
        check(url.contains("countryCode=AT") && url.contains("locale=de-DE") && url.contains("currencyCode=EUR"), url)
        check(GOGSearch.url("x", region: "US", german: false)?.absoluteString.contains("locale=en-US") == true, "the app's language")

        let agent = GOGSearch.userAgent
        check(agent.hasPrefix("Nightforge/"), agent)
        check(!["Mozilla", "Epic", "Chrome", "GOG Galaxy"].contains { agent.contains($0) }, "says who it is: \(agent)")

        let epic = StoreHits.epicSearch("the witcher & co+")?.absoluteString ?? ""
        check(epic.hasPrefix("https://store.epicgames.com/browse?q=the%20witcher%20%26%20co%2B"), epic)
    }

    /// What a hit becomes, and that nothing looks for a Steam app ID in another store's.
    static func hitsAsGames() {
        let block = AntiCheatBlock(antiCheat: ["X"], geforceNow: nil)
        var free = StoreHit(gameID: .gog("5"), name: "Gwent", page: URL(string: "https://www.gog.com/en/game/gwent"))
        free.free = true
        free.art = StoreArt(cover: URL(string: "https://images.gog-statics.com/a.jpg"), hero: nil, logo: nil)
        let game = StoreHits.game(free, info: nil, blocks: [0: block, 5: block])
        check(game.install == .inStore && game.provider == .gog && game.appID == 0, "a store entry of GOG's")
        check(game.antiCheatBlock == nil, "anti-cheat goes by Steam's IDs, which it has none of")
        check(!game.storeFree, "only Steam adds a free licence; GOG's are taken on their page")
        check(!game.controllerKnown, "GOG's catalog doesn't say")
        check(game.art?.cover?.host == "images.gog-statics.com", "its own cover")
        check(game.storePageURL?.host == "www.gog.com", "its own page, not Steam's app 0")
        check(game.steamAppID == nil, "no Steam data for it")

        var blocked = StoreSearch.Hit(appID: 77, name: "Shooter")
        blocked.free = true
        let steamGame = StoreHits.game(StoreHit(blocked), info: nil, blocks: [77: block])
        check(steamGame.antiCheatBlock == block && steamGame.storeFree && steamGame.controllerKnown, "Steam's hits as before")
        check(steamGame.storePageURL?.absoluteString == "https://store.steampowered.com/app/77", "Steam's page")
        var onMac = blocked
        onMac.macNative = true
        check(StoreHits.game(StoreHit(onMac), info: nil, blocks: [77: block]).antiCheatBlock == nil, "a Mac version: no Windows anti-cheat")
        var demo = steamGame
        demo.demoOf = 70
        check(demo.storePageURL?.absoluteString == "https://store.steampowered.com/app/70", "a demo: the game's page")
    }

    /// One list from several stores.
    static func oneList() {
        let witcher3 = steam(292030, "The Witcher 3: Wild Hunt")
        let renamed = gog("1640424747", "The Witcher 3: Wild Hunt — Remastered", slug: "the_witcher_3_wild_hunt_game_of_the_year_edition")
        var list = StoreHits.cards([.steam: [witcher3], .gog: [renamed]], term: "witcher")
        check(list.count == 1, "one game, one card: \(list.map(\.name))")
        check(list.first?.providers == [.steam, .gog], "marked with both stores")
        check(list.first?.storePageURL?.host == "store.steampowered.com", "Steam first")
        check(list.first?.others.first?.storePageURL?.host == "www.gog.com", "and the way to the other store")

        list = StoreHits.cards([.steam: [steam(1, "Dark Light")], .gog: [gog("2", "Dark Light", mac: true)]], term: "dark")
        check(list.first?.provider == .gog && list.first?.macNative == true, "the store with the Mac version first")
        check(list.first?.steamTwin == 1, "its Steam twin: profile and logo go by that")

        var scored = steam(3, "Disco Elysium")
        scored.metascore = 91
        list = StoreHits.cards([.steam: [scored], .gog: [gog("4", "Disco Elysium", mac: true)]], term: "disco")
        check(list.first?.metascore == 91, "what a store knows stays on the card")

        list = StoreHits.cards([.gog: [gog("1", "Tomb"), gog("2", "Tomb")]], term: "tomb")
        check(list.count == 2, "a title one store has twice stays two")

        list = StoreHits.cards([.steam: [steam(1, "Portal"), steam(2, "Portal 2")], .gog: [gog("3", "Portal Stories")]], term: "portal")
        check(list.map(\.provider) == [.steam, .gog, .steam], "the stores take turns: \(list.map(\.name))")

        list = StoreHits.cards([.steam: [steam(1, "Automat Tool")], .gog: [gog("2", "Automat")]], term: "automat tool")
        check(list.map(\.name) == ["Automat Tool", "Automat"], "better fits first, from any store: \(list.map(\.name))")

        check(StoreHits.cards([:], term: "x").isEmpty && StoreHits.cards([.gog: []], term: "x").isEmpty, "nothing found: nothing")
    }

    /// A hit that's the player's already.
    static func ownGames() {
        let cyberpunk = GameID.gog("1423049311")
        let owned = OwnedGames([
            own(cyberpunk, "Cyberpunk 2077"),
            own(.gog("1495134320"), "The Witcher 3: Wild Hunt - Game of the Year Edition"),
            own(.gog("1207658924"), "The Witcher"),
            own(.steam(620), "Portal 2"),
            own(.epic("Fortnite"), "Overcooked! 2"),
            {
                var twin = own(.gog("99"), "Original Title")
                twin.steamTwin = 4000
                return twin
            }(),
            {
                var demo = own(.steam(500), "Hollow Demo")
                demo.demoOf = 501
                return demo
            }(),
        ])
        check(owned.game(of: gog("1207658924", "The Witcher: Enhanced Edition")) == .gog("1207658924"), "exactly, by GOG's ID")
        check(owned.game(of: gog("2093619782", "Cyberpunk 2077", slug: "cyberpunk_2077")) == cyberpunk, "a pack has its own ID: by title")
        check(owned.game(of: gog("1640424747", "The Witcher 3: Wild Hunt — Remastered", slug: "the_witcher_3_wild_hunt_game_of_the_year_edition")) == .gog("1495134320"),
              "renamed: by what its page's address calls it")
        check(owned.game(of: gog("7", "Portal 2")) == .steam(620), "owned on Steam, found on GOG")
        check(owned.game(of: steam(728880, "Overcooked! 2")) == .epic("Fortnite"), "owned on Epic, found on Steam")
        check(owned.game(of: steam(4000, "Another Title")) == .gog("99"), "by the same game on Steam")
        check(owned.game(of: gog("8", "Hollow Demo")) == nil, "a demo isn't the player's game")
        check(owned.game(of: steam(500, "Hollow Demo")) == .steam(500), "but its own entry is known")
        check(owned.game(of: gog("9", "Something Else")) == nil, "not owned: stays a hit")

        let card = StoreHits.cards([.steam: [steam(620, "Portal 2")], .gog: [gog("6", "Portal 2")]], term: "portal")[0]
        check(owned.game(of: card) == .steam(620), "a card for two stores: owned in one of them")
        check(OwnedGames([own(.gog("1"), "™")]).game(of: gog("2", "®")) == nil, "a title of marks only matches nothing")
    }

    /// The heading over the hits.
    static func sections() {
        func title(_ hits: [Game]) -> String? {
            LibrarySection.make(hits, sort: .recent, searching: true, hidden: false).first { $0.id == "store" }?.title
        }
        check(title([steam(1, "A")]) == Provider.steam.inStore, "Steam's alone")
        check(title([gog("1", "A")]) == Provider.gog.inStore, "GOG's alone")
        check(title([steam(1, "A"), gog("2", "B")]) == L10n.t("In the Stores"), "several")
        let both = StoreHits.cards([.steam: [steam(1, "A")], .gog: [gog("2", "A")]], term: "a")
        check(title(both) == L10n.t("In the Stores"), "one game from two stores")
        check(Provider.gog.viewInStore != Provider.steam.viewInStore, "the button names its store")
    }

    /// Delivered one by one: the fast store's hits while the slow one still runs.
    @MainActor static func slowAndFailingStores() async {
        let hit = StoreHit(gameID: .steam(1), name: "Fast")
        let (arrivals, sink) = AsyncStream.makeStream(of: (Provider, [StoreHit]).self)
        let started = Date()
        let run = Task {
            await StoreHits.gather([
                (.gog, { try? await Task.sleep(for: .seconds(30)); return [] }),
                (.steam, { [hit] }),
            ]) { provider, hits in sink.yield((provider, hits)) }
            sink.finish()
        }
        var iterator = arrivals.makeAsyncIterator()
        let first = await iterator.next()
        check(first?.0 == .steam && first?.1 == [hit], "the fast store first")
        check(Date().timeIntervalSince(started) < 10, "a slow store holds up nothing")
        run.cancel()  // the next keystroke
        await run.value
        check(Date().timeIntervalSince(started) < 10, "cancelling stops the slow one too")

        // A store that fails has nothing to say, and the others stand.
        var found: [Provider: [StoreHit]] = [:]
        await StoreHits.gather([(.gog, { [] }), (.steam, { [hit] }), (.epic, { [] })]) { found[$0] = $1 }
        check(found[.steam] == [hit] && found[.gog] == [] && found[.epic] == [], "each store answers for itself")
        let cards = StoreHits.cards(found.mapValues { $0.map { StoreHits.game($0, info: nil, blocks: [:]) } }, term: "fast")
        check(cards.map(\.name) == ["Fast"], "the others' hits stand")
    }
}
