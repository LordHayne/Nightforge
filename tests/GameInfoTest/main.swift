// Checks what GameInfo reads from real answers of Steam's store-browse API, GOG's page and GamesDB
// (fixtures from 31.10.2026), from legendary's catalog data, and how the library uses it:
// tests/GameInfoTest/run.sh
import Foundation

@main
struct GameInfoTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/\(name)")
        return (try? Data(contentsOf: here)) ?? (try? Data(contentsOf: url.appendingPathComponent(name))) ?? Data()
    }

    static func main() {
        steam()
        gog()
        epicAndTwins()
        texts()
        modes()
        asking()
        library()
        print(failures == 0 ? "✓ GameInfo" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Steam's store-browse API: Overcooked! 2, No Man's Sky and A SHEEP GAME, in German.
    static func steam() {
        let infos = GameInfo.steam(fromItems: fixture("steam-items-de.json"), language: "german")
        check(infos.count == 3, "three apps: \(infos.keys.sorted())")
        guard let overcooked = infos[728880], let sky = infos[275850], let sheep = infos[5391790] else { return }

        check(overcooked.summary?.hasPrefix("Overcooked kehrt mit einer brandneuen zweiten Portion") == true,
              "the German short description: \(overcooked.summary ?? "nil")")
        check(overcooked.developers == ["Ghost Town Games Ltd.", "Team17"] && overcooked.publishers == ["Team17"],
              "developers and publisher: \(overcooked.developers) / \(overcooked.publishers)")
        check(overcooked.modes.isSuperset(of: [.single, .onlineCoop, .localCoop, .splitScreen, .versus]),
              "single-player, online and local co-op, split screen, versus: \(overcooked.modes)")
        check(overcooked.controller == .full, "full controller support (category 28)")
        check(overcooked.age == nil, "Steam's own rating (agency 17) isn't shown")
        check(overcooked.macLanguage == LanguageSupport(text: true, audio: false), "German text, no German speech")
        check(Calendar(identifier: .gregorian).component(.year, from: overcooked.released ?? .distantPast) == 2018, "came out in 2018")
        check(overcooked.source == "steam.728880" && overcooked.language == "german", "where and how it was asked")
        check(overcooked.screenshots.count == GameInfo.maxScreenshots, "up to 12 screenshots: \(overcooked.screenshots.count)")
        check(overcooked.screenshots.first?.thumbnail.absoluteString.contains(".600x338.jpg") == true
              && overcooked.screenshots.first?.full.absoluteString.contains(".1920x1080.jpg") == true,
              "small and big screenshot: \(overcooked.screenshots.first.map { "\($0.thumbnail)" } ?? "none")")
        check(overcooked.cover?.absoluteString.hasPrefix("https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/728880/") == true
              && overcooked.cover?.absoluteString.contains("_2x.jpg") == true,
              "the portrait cover at its address: \(overcooked.cover?.absoluteString ?? "nil")")
        check(!overcooked.genres.isEmpty && overcooked.genres.count <= 4, "a few genres: \(overcooked.genres)")

        check(sky.age == AgeRating(system: "USK", age: 6), "No Man's Sky: USK 6 (agency 4)")
        check(sky.macLanguage == LanguageSupport(text: true, audio: true), "German text and speech")
        check(sky.modes.contains(.onlineCoop) && !sky.modes.contains(.localCoop), "online co-op, no local co-op: \(sky.modes)")

        // A new game: its art only under a hashed path, which the usual addresses don't reach.
        check(sheep.cover?.absoluteString.range(of: "/apps/5391790/[0-9a-f]{40}/library_capsule", options: .regularExpression) != nil,
              "A SHEEP GAME's cover with its hash: \(sheep.cover?.absoluteString ?? "nil")")
        check(sheep.controller == .partial, "partial controller support (category 18)")
        check(StoreArt(sheep).cover == sheep.cover && StoreArt(sheep).wideCover == sheep.wideCover, "its art for ArtworkStore")

        check(GameInfo.steam(fromItems: Data("{}".utf8), language: "german").isEmpty, "nothing from an empty answer")
        func rated(_ agency: Int, _ rating: String) -> AgeRating? {
            let json = #"{"response":{"store_items":[{"appid":1,"name":"A","game_rating":{"rating":"\#(rating)","agency":\#(agency)}}]}}"#
            return GameInfo.steam(fromItems: Data(json.utf8), language: "german")[1]?.age
        }
        check(rated(2, "18") == AgeRating(system: "PEGI", age: 18), "PEGI (Austria, most of Europe)")
        check(rated(1, "m") == nil && rated(17, "12") == nil, "not ESRB's letters, not Steam's own")
        let english = GameInfo.steam(fromItems: fixture("steam-items-de.json"), language: "english")
        check(english[275850]?.macLanguage == nil, "no German row on an English Mac")
    }

    /// GOG's own page of The Witcher 3, in German.
    static func gog() {
        guard let info = GameInfo.gog(fromJSON: fixture("gog-witcher3-de.json"), id: "1207664643", language: "german") else {
            return check(false, "GOG's page read")
        }
        check(info.source == "gog.1207664643", "from GOG")
        check(info.summary.map { !$0.isEmpty && $0.count <= 330 && !$0.contains("<") } == true,
              "a short plain description: \(info.summary ?? "nil")")
        check(info.developers == ["CD PROJEKT RED"] && info.publishers == ["CD PROJEKT RED"], "developer and publisher")
        check(info.controller == .full, "controller support")
        check(info.modes == [.single], "single-player: \(info.modes)")
        check(info.macLanguage == LanguageSupport(text: true, audio: true), "German text and speech")
        check(info.genres.contains("Rollenspiel"), "German genres: \(info.genres)")
        check(info.screenshots.first?.thumbnail.absoluteString.contains("product_card_screenshot_748") == true, "screenshots at a size")
        check(GameInfo.gog(fromJSON: Data("[]".utf8), id: "1", language: "german") == nil, "nothing from a broken answer")
    }

    static func epicAndTwins() {
        check(GameInfo.steamTwin(fromGamesDB: fixture("gamesdb-epic-potoo.json")) == 728880, "GamesDB: Epic's Potoo is Steam's 728880")
        check(GameInfo.steamTwin(fromGamesDB: Data(#"{"game":{"releases":[{"platform_id":"gog","external_id":"1"}]}}"#.utf8)) == nil,
              "no Steam release, no twin")
        let release = GOGRelease.from(gamesDB: Data(#"{"external_id":"1207664643","title":{"*":"The Witcher 3"},"game":{"releases":[{"platform_id":"steam","external_id":"292030"}]}}"#.utf8))
        check(release?.steamAppID == 292030, "a GOG release keeps its Steam app ID")

        let titleOnly = Data(#"{"metadata":{"title":"Overcooked! 2","description":"Overcooked! 2","developer":"Team17 Digital Ltd"}}"#.utf8)
        let epic = GameInfo.epic(fromMetadata: titleOnly, appName: "Potoo", language: "german")
        check(epic?.summary == nil && epic?.developers == ["Team17 Digital Ltd"], "Epic's description that's only the title isn't one")
        let real = Data(#"{"metadata":{"title":"Thief","description":"Thief is a 1st person stealth-action game by Eidos-Montréal. In this reimagination of the cult classic, you are Garrett."}}"#.utf8)
        check(GameInfo.epic(fromMetadata: real, appName: "Thief", language: "german")?.summary?.hasPrefix("Thief is a 1st person") == true,
              "a real one is")
    }

    static func texts() {
        check(HTMLText.plain("Optimierungs- &amp; Infrastruktur") == "Optimierungs- & Infrastruktur", "&amp;")
        check(HTMLText.plain("Baldur&#8217;s Gate &#x2013; 3") == "Baldur’s Gate – 3", "numbered entities")
        check(HTMLText.plain("<p>One</p><p><b>Two</b><br>Three</p>") == "One\nTwo\nThree", "tags become lines: \(HTMLText.plain("<p>One</p><p><b>Two</b><br>Three</p>"))")
        let long = String(repeating: "This sentence is part of a long description. ", count: 12)
        let short = GameInfo.summary(long)
        check(short.count <= 320 && short.hasSuffix("description."), "cut to whole sentences: \(short.count)")
        check(GameInfo.summary("First paragraph.\nSecond one.") == "First paragraph.", "the first paragraph")
    }

    static func modes() {
        check(PlayMode.steam([2, 1, 9, 38, 39, 24]) == [.single, .multi, .coop, .onlineCoop, .localCoop, .splitScreen], "Steam's categories")
        check(PlayMode.shown([.single, .multi, .coop, .onlineCoop]) == [.single, .onlineCoop],
              "the general ones only without exact ones: \(PlayMode.shown([.single, .multi, .coop, .onlineCoop]))")
        check(PlayMode.shown([.single, .coop, .multi]) == [.single, .coop], "GOG's co-op stays")
        check(ControllerSupport.steam([28, 55]) == .full && ControllerSupport.steam([18]) == .partial && ControllerSupport.steam([]) == .none,
              "Steam's controller categories")
    }

    static func asking() {
        let now = Date()
        let fresh = GameInfo(language: "german", source: "steam.1", asked: now.addingTimeInterval(-86_400))
        check(!GameInfoStore.needsAsking(fresh, language: "german", now: now), "a day old: kept")
        check(GameInfoStore.needsAsking(fresh, language: "english", now: now), "another language: asked again")
        var old = fresh
        old.asked = now.addingTimeInterval(-GameInfoStore.askAgainAfter - 1)
        check(GameInfoStore.needsAsking(old, language: "german", now: now), "a month old: asked again")
        check(GameInfoStore.needsAsking(nil as GameInfo?, language: "german", now: now), "unknown: asked")
        var older = fresh
        older.format = nil
        check(GameInfoStore.needsAsking(older, language: "german", now: now), "read by an older Nightforge: asked again once")
        check(!GameInfoStore.needsAsking(GameInfoStore.Twin(appID: 5, asked: .distantPast), now: now), "a twin found stays")
        check(GameInfoStore.needsAsking(GameInfoStore.Twin(appID: nil, asked: .distantPast), now: now), "none found: asked again after a month")
        check(!GameInfoStore.needsAsking(GameInfoStore.Twin(appID: nil, asked: now), now: now), "… not before")

        // What the player looks at first is filled in first.
        func entry(_ id: GameID, installed: Bool = false, played: Double? = nil) -> Game {
            var game = Game(gameID: id, name: id.key, bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                            steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
            game.install = installed ? .installed : .notInstalled
            game.lastPlayed = played.map { now.addingTimeInterval(-$0) }
            return game
        }
        let order = GameInfoStore.order([entry(.epic("A")), entry(.steam(1), played: 50), entry(.epic("B"), installed: true),
                                         entry(.gog("2")), entry(.steam(3), played: 5)]).map(\.gameID.key)
        check(order == ["gog.2", "epic.B", "steam.3", "steam.1", "epic.A"], "GOG, then installed, then played last: \(order)")

        var known = GameInfoStore.Known()
        known.infos["steam.728880"] = GameInfo(language: "german", source: "steam.728880", asked: now)
        known.twins["epic.Potoo"] = GameInfoStore.Twin(appID: 728880, asked: now)
        let data = try? JSONEncoder().encode(known)
        check(data.flatMap { try? JSONDecoder().decode(GameInfoStore.Known.self, from: $0) } == known, "kept on disk and read back")
        let epic = Game(gameID: .epic("Potoo"), name: "Overcooked! 2", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        check(GameInfoStore.source(of: epic, in: known) == "steam.728880" && GameInfoStore.info(for: epic, in: known) != nil,
              "an Epic game takes the info of the same game on Steam")
        let other = Game(gameID: .gog("1"), name: "Other", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                         steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        check(GameInfoStore.source(of: other, in: known) == "gog.1", "one without takes its own store's")
    }

    /// What the library does with it: controller support and profiles through the twin, one card for both stores.
    static func library() {
        var epic = Game(gameID: .epic("Potoo"), name: "Overcooked! 2", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        check(epic.knownController == nil, "Epic alone doesn't say")
        epic.controller = .full
        epic.controllerKnown = true
        epic.steamTwin = 728880
        check(epic.knownController == .full && epic.steamAppID == 728880, "with the twin's info it does, and profiles go by its app ID")
        check(LibraryFilters(on: [.controller]).admits(epic) { _ in .untested }, "the Controller filter takes it")

        var gog = Game(gameID: .gog("1207664643"), name: "The Witcher 3: Wild Hunt", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                       steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        gog.playModes = [.localCoop]
        var steam = Game(appID: 292030, name: "The Witcher 3: Wild Hunt", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                         steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        steam.controller = .partial
        steam.controllerKnown = true
        let card = DuplicateGames.card([gog, steam], chosen: .gog)
        check(card.provider == .gog && card.knownController == .partial, "a card's controller support from the store that says it")
        check(card.steamAppID == 292030, "… and its Steam app ID from its Steam entry")
        check(LibraryFilters(on: [.couch]).admits(card) { _ in .untested }, "ways to play from any of its stores")
    }
}
