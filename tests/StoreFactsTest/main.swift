// Checks genre, year and Metacritic score read from Steam's catalog (the line above a game's title,
// the score on its page), and when a score the store didn't know is asked again:
// tests/StoreFactsTest/run.sh
import Foundation

@main
struct StoreFactsTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    // MARK: Binary KeyValues as Steam writes them (as in MacVersionTest)

    indirect enum KV {
        case object([(String, KV)])
        case string(String)
        case int(Int32)
    }

    static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) } }
    static func le64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(value >> (8 * UInt64($0)) & 0xFF) } }

    static func encode(_ pairs: [(String, KV)], table: inout [String]?) -> [UInt8] {
        var out: [UInt8] = []
        for (key, value) in pairs {
            switch value {
            case .object: out.append(0)
            case .string: out.append(1)
            case .int: out.append(2)
            }
            if table != nil {
                if let index = table!.firstIndex(of: key) {
                    out += le32(UInt32(index))
                } else {
                    table!.append(key)
                    out += le32(UInt32(table!.count - 1))
                }
            } else {
                out += Array(key.utf8) + [0]
            }
            switch value {
            case .object(let children): out += encode(children, table: &table)
            case .string(let text): out += Array(text.utf8) + [0]
            case .int(let number): out += le32(UInt32(bitPattern: number))
            }
        }
        return out + [8]
    }

    static func appinfo(_ apps: [(Int, [(String, KV)])]) -> Data {
        var table: [String]? = []
        var body: [UInt8] = []
        for (appID, info) in apps {
            let kv = encode([("appinfo", .object(info))], table: &table)
            let header = [UInt8](repeating: 0, count: 60)
            body += le32(UInt32(appID)) + le32(UInt32(header.count + kv.count)) + header + kv
        }
        body += le32(0)
        let tableOffset = 16 + body.count
        var strings = le32(UInt32(table!.count))
        for key in table! { strings += Array(key.utf8) + [0] }
        return Data(le32(0x0756_4429) + le32(1) + le64(UInt64(tableOffset)) + body + strings)
    }

    static func packageinfo(_ appIDs: [Int]) -> Data {
        var none: [String]?
        let apps = appIDs.enumerated().map { (String($0.offset), KV.int(Int32($0.element))) }
        let kv = encode([("1", .object([("packageid", .int(1)), ("appids", .object(apps))]))], table: &none)
        let entry = le32(1) + [UInt8](repeating: 0, count: 20 + 4 + 8) + kv
        return Data(le32(0x0656_5528) + le32(1) + entry + le32(0xFFFF_FFFF))
    }

    static func list(_ ids: [Int32]) -> KV {
        .object(ids.enumerated().map { (String($0.offset), .int($0.element)) })
    }

    static func game(_ name: String, _ common: [(String, KV)]) -> [(String, KV)] {
        [("common", .object([("name", .string(name)), ("type", .string("Game"))] + common))]
    }

    /// Unix time of 1 July of `year`.
    static func midyear(_ year: Int) -> Int32 {
        Int32(DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                             year: year, month: 7, day: 1).date!.timeIntervalSince1970)
    }

    @MainActor
    static func main() {
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)

        // MARK: Genre
        // Steam's tags, most voted first: modes and themes ("Multiplayer", "Zombies") aren't genres,
        // and "Open World Survival Craft" is too long for the line – the next one says it shorter.
        check(StoreFacts(tags: [3859, 4182, 1659, 1662]).genre == "Survival", "first tag that's a genre: Survival")
        check(StoreFacts(tags: [1100689, 1662, 1695]).genre == "Survival", "Open World Survival Craft skipped")
        check(StoreFacts(tags: [113, 620519]).genre == "Hero Shooter", "Free to Play skipped: Hero Shooter")
        check(StoreFacts(tags: [21978, 4608, 3810]).genre == "Sandbox", "VR and Swordplay skipped: Sandbox")
        // No genre among the tags: Steam's genres, its primary one first, never Indie or Free to Play.
        check(StoreFacts(tags: [1659], genres: [1, 37], primaryGenre: 37).genre == "Action", "primary genre Free to Play: Action")
        check(StoreFacts(genres: [28, 2], primaryGenre: 2).genre == "Strategy", "primary genre first: Strategy")
        check(StoreFacts(genres: [23, 70]).genre == nil, "only Indie and Early Access: no genre")
        check(StoreFacts().genre == nil, "nothing known: no genre")
        // In German through L10n; names that are the same in both stay as they are.
        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        check(StoreFacts(tags: [122]).genre == "Rollenspiel", "RPG in German: \(StoreFacts(tags: [122]).genre ?? "nil")")
        check(StoreFacts(tags: [1625]).genre == "Jump ’n’ Run", "Platformer in German")
        check(StoreFacts(genres: [9]).genre == "Rennspiel", "Racing genre in German")
        check(StoreFacts(tags: [1695]).genre == "Open World", "Open World stays")
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)

        // MARK: Read from the catalog
        let fm = FileManager.default
        let steam = fm.temporaryDirectory.appendingPathComponent("store-facts-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: steam.appendingPathComponent("appcache"), withIntermediateDirectories: true)
        let apps: [(Int, [(String, KV)])] = [
            (1001, game("Lies of P", [("store_tags", list([4182, 29482, 4231])), ("genres", list([1, 25, 3])),
                                      ("primary_genre", .int(1)), ("steam_release_date", .int(midyear(2023))),
                                      ("metacritic_score", .int(84))])),
            // Out in Early Access (original date) years before its Steam 1.0 date.
            (1002, game("Astroneer", [("store_tags", list([3859, 1100689, 1695])), ("genres", list([25, 23])),
                                      ("steam_release_date", .int(midyear(2019))), ("original_release_date", .int(midyear(2016)))])),
            // Steam knows nothing: every part is left out.
            (1003, game("Spacewar", [])),
            // A score of 0 isn't a score.
            (1004, game("Tropico 3", [("genres", list([28, 2])), ("primary_genre", .int(2)), ("metacritic_score", .int(0))])),
        ]
        try? appinfo(apps).write(to: steam.appendingPathComponent("appcache/appinfo.vdf"))
        try? packageinfo([1001, 1002, 1003, 1004]).write(to: steam.appendingPathComponent("appcache/packageinfo.vdf"))

        check(SteamCatalog.storeFacts(appID: 1001, steamRoot: steam) == nil, "before a scan: nothing (no disk access while drawing)")
        let owned = SteamCatalog.ownedGames(steamRoot: steam)
        check(owned.count == 4, "four games read: \(owned.count)")

        let lies = SteamCatalog.storeFacts(appID: 1001, steamRoot: steam)
        check(lies?.genre == "Souls-like", "Lies of P: Souls-like, \(lies?.genre ?? "nil")")
        check(lies?.year == 2023, "Lies of P: 2023, \(lies?.year ?? 0)")
        check(lies?.metascore == 84, "Lies of P: Metascore 84, \(lies?.metascore ?? 0)")
        let astroneer = SteamCatalog.storeFacts(appID: 1002, steamRoot: steam)
        check(astroneer?.genre == "Open World", "Astroneer: Open World, \(astroneer?.genre ?? "nil")")
        check(astroneer?.year == 2016, "Astroneer: out since 2016, \(astroneer?.year ?? 0)")
        check(astroneer?.metascore == nil, "Astroneer: no score")
        let spacewar = SteamCatalog.storeFacts(appID: 1003, steamRoot: steam)
        check(spacewar != nil && spacewar?.genre == nil && spacewar?.year == nil && spacewar?.metascore == nil,
              "Spacewar: nothing known, nothing shown")
        let tropico = SteamCatalog.storeFacts(appID: 1004, steamRoot: steam)
        check(tropico?.genre == "Strategy" && tropico?.metascore == nil, "Tropico 3: Strategy, a 0 score is none")
        // The game's own Steam doesn't know it, another one does (Steam for Mac beside Nightforge's).
        check(SteamCatalog.storeFacts(appID: 1001, steamRoot: steam.appendingPathComponent("other"))?.year == 2023,
              "another Steam install stands in")
        check(SteamCatalog.storeFacts(appID: 9999, steamRoot: steam) == nil, "an app not in the catalog: nil")
        try? fm.removeItem(at: steam)

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
