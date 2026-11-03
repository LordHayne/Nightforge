// Checks that a game from several stores is one card (DuplicateGames): which titles are the same
// game – and which only look alike –, which store a card starts through, the store picked on its
// page, and that marks and counts take the card once: tests/DuplicateGamesTest/run.sh
import Foundation

@main
struct DuplicateGamesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let now = Date()

    static func steam(_ appID: Int, _ name: String, _ install: InstallState = .notInstalled, bottle: Bottle = Engine.bottle,
                      daysAgo: Double? = nil, minutes: Int? = nil) -> Game {
        var game = Game(appID: appID, name: name, bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "",
                        installDir: bottle.url, sizeOnDisk: 1_000, lastPlayed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
                        playtimeMinutes: minutes)
        game.install = install
        return game
    }

    static func epic(_ appName: String, _ name: String, _ install: InstallState = .notInstalled,
                     daysAgo: Double? = nil, minutes: Int? = nil) -> Game {
        var game = Game(gameID: .epic(appName), name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 2_000, lastPlayed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
                        playtimeMinutes: minutes)
        game.install = install
        return game
    }

    static func main() {
        titles()
        matching()
        defaultStore()
        choice()
        marksAndCounts()
        print(failures == 0 ? "✓ DuplicateGames" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func same(_ a: String, _ b: String) -> Bool { DuplicateGames.titleKey(a) == DuplicateGames.titleKey(b) }

    /// The title key: what both stores write differently goes, what tells games apart stays.
    static func titles() {
        check(DuplicateGames.titleKey("ARC Raiders™") == "arc raiders", "™ and case: \(DuplicateGames.titleKey("ARC Raiders™"))")
        check(same("Sid Meier's Civilization VI", "Sid Meier’s Civilization® VI"), "apostrophes and ®")
        check(DuplicateGames.titleKey("Sid Meier's Civilization VI") == "sid meiers civilization vi", "an apostrophe joins")
        check(same("Rocket League®", "Rocket League"), "®")
        check(same("Shadow Tactics: Blades of the Shogun", "Shadow Tactics Blades of the Shogun"), "a colon")
        check(same("Hundred Days - Winemaking Simulator", "Hundred Days – Winemaking Simulator"), "dashes")
        check(same("S.T.A.L.K.E.R.: Shadow of Chernobyl", "STALKER: Shadow of Chernobyl"), "dots join")
        check(same("Blade & Sorcery", "Blade and Sorcery"), "& is and")
        check(same("Pokémon Café", "Pokemon Cafe"), "accents")
        check(same("ＡＢＣ", "ABC"), "full-width letters")
        check(same("Batman: Arkham Asylum GOTY Edition", "Batman Arkham Asylum Game of the Year Edition"), "GOTY edition")
        check(same("Fallout 3: Game of the Year Edition", "Fallout 3"), "Game of the Year Edition")
        check(same("Assassin's Creed Odyssey – Gold Edition", "Assassin's Creed Odyssey"), "Gold Edition")
        check(same("Injustice: Gods Among Us Ultimate Edition", "Injustice: Gods Among Us"), "Ultimate Edition")
        check(DuplicateGames.titleKey("GOTY") == "goty" && DuplicateGames.titleKey("Deluxe Edition") == "deluxe edition",
              "an edition name alone stays the title")
        check(DuplicateGames.titleKey("™") == "", "nothing but marks: no key")

        // Only alike: another part, a reworked game, a test build, a soundtrack, a demo.
        let apart = [
            ("Dead Island", "Dead Island 2"), ("Hades", "Hades II"), ("Tomb Raider", "Rise of the Tomb Raider"),
            ("The Outer Worlds", "The Outer Worlds: Spacer's Choice Edition"),
            ("The Elder Scrolls V: Skyrim", "The Elder Scrolls V: Skyrim Special Edition"),
            ("Age of Empires II", "Age of Empires II: Definitive Edition"), ("Mafia", "Mafia: Definitive Edition"),
            ("Baldur's Gate", "Baldur's Gate: Enhanced Edition"), ("Saints Row: The Third", "Saints Row: The Third Remastered"),
            ("Deus Ex: Human Revolution", "Deus Ex: Human Revolution - Director's Cut"),
            ("Chivalry 2", "Chivalry 2 - Public Testing"), ("PUBG: BATTLEGROUNDS", "PUBG: Test Server"),
            ("Cyberpunk 2077", "Cyberpunk 2077 Soundtrack"), ("Hades II", "Hades II Demo"), ("DOOM", "DOOM (1993)"),
            ("Grand Theft Auto V Legacy", "Grand Theft Auto V Enhanced"), ("Borderlands Game of the Year", "Borderlands Game of the Year Enhanced"),
        ]
        for (a, b) in apart {
            check(!same(a, b), "\(a) and \(b) are different games")
        }
    }

    /// Same title in two stores: one card. Everything else stays as it is.
    static func matching() {
        let arcSteam = steam(1_808_500, "ARC Raiders")
        var arcEpic = epic("Pioneer", "ARC Raiders™", .installed, daysAgo: 2, minutes: 120)
        var arkSteam = steam(346_110, "ARK: Survival Evolved", .installed, daysAgo: 10, minutes: 600)
        arkSteam.controller = .full
        let arkEpic = epic("aafc587fbf654758802c8e41e4fb3255", "ARK: Survival Evolved", daysAgo: 400, minutes: 30)
        arcEpic.controller = .none
        var hadesDemo = steam(1_145_351, "Hades II")  // a demo standing in for a game the account doesn't own
        hadesDemo.demoOf = 1_145_350
        let hadesEpic = epic("Hades2", "Hades II", .installed)
        var palworldHit = steam(1_623_730, "Palworld", .inStore)
        palworldHit.storePrice = "29,99 €"
        let palworldEpic = epic("Palworld", "Palworld")
        let crossOver = Bottle(name: "Games", url: URL(fileURLWithPath: "/tmp/Games"))
        let entries = [
            arcSteam, arkSteam, steam(407_530, "ARK: Survival Of The Fittest"),
            steam(91_310, "Dead Island"), epic("Crow", "Dead Island 2"),
            steam(203_160, "Tomb Raider"), epic("f7cc1c999ac146f39b356f53e3489514", "Rise of the Tomb Raider: 20 Year Celebration"),
            steam(219_640, "Chivalry: Medieval Warfare"), epic("Peppermint", "Chivalry 2"), epic("ca02598c9a5c", "Chivalry 2 - Public Testing"),
            steam(271_590, "Grand Theft Auto V"), steam(271_590, "Grand Theft Auto V", bottle: crossOver), epic("9d2d0eb64d5c", "Grand Theft Auto V"),
            hadesDemo, hadesEpic, palworldHit, palworldEpic,
            steam(42, "Saints Row: The Third Remastered"), epic("Saints", "Saints Row: The Third"),
            arcEpic, arkEpic,
        ]
        let cards = DuplicateGames.merge(entries) { _ in nil }
        check(cards.count == entries.count - 2, "two games in two stores: two cards fewer (\(cards.count) of \(entries.count))")
        let merged = cards.filter { !$0.others.isEmpty }
        check(merged.map(\.name).sorted() == ["ARC Raiders™", "ARK: Survival Evolved"], "only ARC Raiders and ARK merge: \(merged.map(\.name))")
        check(cards.filter { $0.name.hasPrefix("Grand Theft Auto V") }.count == 3, "a title one store has twice merges with nothing")
        check(cards.filter { $0.name == "Hades II" }.count == 2, "a demo isn't the player's game and merges with nothing")
        check(cards.filter { $0.name == "Palworld" }.count == 2, "a store hit merges with nothing")
        check(cards.firstIndex { $0.name == "ARC Raiders™" } == 0, "the card takes the place of the game's first entry")

        guard let arc = cards.first(where: { $0.name == "ARC Raiders™" }), let ark = cards.first(where: { $0.name == "ARK: Survival Evolved" })
        else { return check(false, "ARC Raiders and ARK have a card each") }
        check(arc.providers == [.epic, .steam], "ARC Raiders starts through Epic Games, where it's installed: \(arc.providers)")
        check(arc.gameID == .epic("Pioneer") && arc.gameIDs == [.epic("Pioneer"), .steam(1_808_500)], "each store keeps its own ID")
        check(arc.holds(arcSteam.id) && arc.holds(arcEpic.id) && !arc.holds(arkSteam.id) && !arc.holds(nil), "the card holds both entries")
        check(arc.isInstalled && arc.lastPlayed == arcEpic.lastPlayed && arc.playtimeMinutes == 120, "ARC Raiders: Epic's state and play time")
        check(arc.entries.map(\.provider) == [.epic, .steam] && arc.others.allSatisfy(\.others.isEmpty), "entries: the store it starts through first")
        check(ark.providers == [.steam, .epic] && ark.isInstalled, "ARK starts through Steam, where it's installed")
        check(ark.lastPlayed == arkSteam.lastPlayed, "last played: the latest of both")
        check(ark.playtimeMinutes == 630, "play time: both stores together: \(ark.playtimeMinutes ?? -1)")
        let epicFirst = DuplicateGames.card([arkEpic, arkSteam], chosen: .epic)
        check(epicFirst.controller == .full, "controller support from the store that knows it, whichever it starts through")
        check(epicFirst.lastPlayed == arkSteam.lastPlayed && epicFirst.playtimeMinutes == 630, "the same last played and play time either way")
    }

    /// Which store a card starts through when none was picked on its page.
    static func defaultStore() {
        func first(_ entries: [Game], chosen: Provider? = nil) -> Provider? { DuplicateGames.order(entries, chosen: chosen).first?.provider }
        check(first([steam(1, "A"), epic("A", "A", .installed)]) == .epic, "the store it's installed in")
        check(first([steam(1, "A", .installed), epic("A", "A")]) == .steam, "… either way round")
        check(first([steam(1, "A", .installed, daysAgo: 5), epic("A", "A", .installed, daysAgo: 1)]) == .epic, "both installed: the one played last")
        check(first([steam(1, "A", .installed, daysAgo: 1), epic("A", "A", .installed, daysAgo: 5)]) == .steam, "… the other way round")
        check(first([epic("A", "A", .installed), steam(1, "A", .installed)]) == .steam, "both installed, neither played: Steam")
        check(first([epic("A", "A", daysAgo: 1), steam(1, "A")]) == .steam, "neither installed: Steam, even if the other was played")
        check(first([steam(1, "A"), epic("A", "A", .downloading(0.4))]) == .epic, "the store it's downloading in")
        check(first([steam(1, "A", .installed), epic("A", "A", .downloading(0.4))]) == .steam, "installed comes before downloading")
        check(first([steam(1, "A"), epic("A", "A", .installed)], chosen: .steam) == .steam, "the store picked on its page comes first")
        check(first([steam(1, "A", .installed, daysAgo: 1), epic("A", "A", .installed, daysAgo: 9)], chosen: .epic) == .epic,
              "… whatever else is true")

        // What the card shows: a download in another store than the one it starts through.
        let card = DuplicateGames.card([steam(1, "A"), epic("A", "A", .downloading(0.4))], chosen: .steam)
        check(card.provider == .steam && card.install == .notInstalled, "it starts through Steam, which doesn't have it yet")
        check(card.shown.provider == .epic && card.shown.install == .downloading(0.4), "its cover shows Epic's download")
        let quiet = DuplicateGames.card([steam(1, "A", .installed), epic("A", "A")], chosen: nil)
        check(quiet.shown.id == quiet.id, "nothing under way: it shows the store it starts through")
        check(LibraryFilters(on: [.onMac]).admits(card) { _ in .untested }, "a download in one of its stores is on this Mac (filters)")
        check(LibraryFilters(store: .epic).admits(card) { _ in .untested } && LibraryFilters(store: .steam).admits(card) { _ in .untested }
              && !LibraryFilters(store: .gog).admits(card) { _ in .untested }, "a game from two stores is in each of them (store filter)")
        check(LibrarySection.make([card], sort: .recent, searching: false, hidden: false).first?.id == "downloading",
              "… and in the library's downloads group")
    }

    /// The store picked on a game's page, kept under each of its entries.
    static func choice() {
        let defaults = TestDefaults.suite("store-choice")

        let ids: [GameID] = [.steam(1_808_500), .epic("Pioneer")]
        check(StoreChoice.load(ids, from: defaults) == nil, "nothing picked yet")
        StoreChoice.save(.steam, for: ids, to: defaults)
        check(StoreChoice.load([.epic("Pioneer")], from: defaults) == .steam && StoreChoice.load([.steam(1_808_500)], from: defaults) == .steam,
              "found from either store's entry")
        check(defaults.string(forKey: "startsThrough.epic.Pioneer") == "steam", "kept under the entry's key")
        check(StoreChoice.load([.steam(570)], from: defaults) == nil, "other games keep their own")

        let entries = [steam(1_808_500, "ARC Raiders"), epic("Pioneer", "ARC Raiders", .installed)]
        let cards = DuplicateGames.merge(entries) { StoreChoice.load($0, from: defaults) }
        check(cards.count == 1 && cards[0].provider == .steam, "the card starts through the store picked, not the one it's installed in")
        StoreChoice.forget(ids, in: defaults)
        check(DuplicateGames.merge(entries) { StoreChoice.load($0, from: defaults) }.first?.provider == .epic,
              "forgotten: back to the store it's installed in")
    }

    /// Hidden and pinned when one of its stores is; counted once.
    static func marksAndCounts() {
        var demo = steam(9, "Some Demo")
        demo.demoOf = 8
        let entries = [
            steam(1_808_500, "ARC Raiders"), epic("Pioneer", "ARC Raiders", .installed, daysAgo: 1),
            steam(346_110, "ARK: Survival Evolved", .installed, daysAgo: 3), epic("ark", "ARK: Survival Evolved"),
            steam(570, "Dota 2", .installed, daysAgo: 2), epic("Fortnite", "Fortnite"),
            steam(1, "Palworld", .inStore), demo,
        ]
        let cards = DuplicateGames.merge(entries) { _ in nil }
        check(cards.count == 6, "six cards: \(cards.count)")
        guard let arc = cards.first(where: { $0.name == "ARC Raiders" }), let ark = cards.first(where: { $0.name == "ARK: Survival Evolved" })
        else { return check(false, "ARC Raiders and ARK have a card each") }

        check(arc.isMarked(in: [.steam(1_808_500)]) && arc.isMarked(in: [.epic("Pioneer")]), "marked when one of its stores is")
        check(!arc.isMarked(in: [.steam(346_110)]), "another game's mark isn't its")

        check(DuplicateGames.count(cards, hidden: []) == 4, "four games – each once, no store hits or demos")
        check(DuplicateGames.count(cards, hidden: [], in: .steam) == 3 && DuplicateGames.count(cards, hidden: [], in: .epic) == 3,
              "a game from both stores counts in each store's number")
        check(DuplicateGames.count(cards, hidden: [.epic("Pioneer")]) == 3, "hidden in one store: out of the count once")
        check(DuplicateGames.count(cards, hidden: [.epic("Pioneer")], in: .steam) == 2, "… also from the other store's number")

        // Home's rail and the Dock menu take the card, by any of its stores' marks.
        let rail = HomeRail.pick(cards, pinned: [.epic("ark")], now: now)
        check(rail.first == cards.firstIndex(of: ark), "pinned in its other store: first on Home")
        check(rail.filter { cards[$0].name == "ARC Raiders" }.count == 1, "on Home once")
        let recent = MacIntegration.recentGames(cards, hidden: [.steam(1_808_500)])
        check(recent.map(\.name) == ["Dota 2", "ARK: Survival Evolved"], "Dock menu: once, and not when hidden in either store: \(recent.map(\.name))")
    }
}
