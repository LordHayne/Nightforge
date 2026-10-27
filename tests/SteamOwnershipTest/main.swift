// Checks which Steam games count as owned – read from Steam's licence list, not from every package
// Steam happens to cache – and what's offered for the rest: tests/SteamOwnershipTest/run.sh
import Foundation

@main
struct SteamOwnershipTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    // MARK: Steam's files, written the way Steam writes them

    indirect enum KV {
        case object([(String, KV)])
        case string(String)
        case int(Int32)
    }

    static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) } }
    static func le64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(value >> (8 * UInt64($0)) & 0xFF) } }

    /// Binary KeyValues; with `table`, key names are indices into it (appinfo v29).
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

    /// appinfo.vdf v29: games and demos (a demo names its game as "parent").
    static func appinfo(_ apps: [(id: Int, name: String, demoOf: Int?)]) -> Data {
        var table: [String]? = []
        var body: [UInt8] = []
        for app in apps {
            var common: [(String, KV)] = [("name", .string(app.name)), ("type", .string(app.demoOf == nil ? "Game" : "Demo")),
                                          ("oslist", .string("windows"))]
            if let parent = app.demoOf { common.append(("parent", .string(String(parent)))) }
            let kv = encode([("appinfo", .object([("common", .object(common)),
                                                  ("config", .object([("installdir", .string(app.name))]))]))], table: &table)
            let header = [UInt8](repeating: 0, count: 60)
            body += le32(UInt32(app.id)) + le32(UInt32(header.count + kv.count)) + header + kv
        }
        body += le32(0)
        var strings = le32(UInt32(table!.count))
        for key in table! { strings += Array(key.utf8) + [0] }
        return Data(le32(0x0756_4429) + le32(1) + le64(UInt64(16 + body.count)) + body + strings)
    }

    /// packageinfo.vdf with the given packages and their apps.
    static func packageinfo(_ packages: [Int: [Int]]) -> Data {
        var out = le32(0x0656_5528) + le32(1)
        for (packageID, appIDs) in packages.sorted(by: { $0.key < $1.key }) {
            var none: [String]?
            let apps = appIDs.enumerated().map { (String($0.offset), KV.int(Int32($0.element))) }
            let kv = encode([(String(packageID), .object([("packageid", .int(Int32(packageID))), ("appids", .object(apps))]))], table: &none)
            out += le32(UInt32(packageID)) + [UInt8](repeating: 0, count: 20 + 4 + 8) + kv
        }
        return Data(out + le32(0xFFFF_FFFF))
    }

    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var out: [UInt8] = []
        repeat {
            out.append(UInt8(value & 0x7F) | (value > 0x7F ? 0x80 : 0))
            value >>= 7
        } while value > 0
        return out
    }

    /// licensecache as Steam keeps it: CMsgClientLicenseList (eresult 1, one License per entry with
    /// package_id, time_created, flags, purchase country, owner), its CRC32, all scrambled.
    static func licensecache(_ licenses: [(package: Int, flags: Int)], accountID: UInt32) -> [UInt8] {
        var list = [0x08] + varint(1)
        for license in licenses {
            let body = [0x08] + varint(UInt64(license.package)) + [0x15] + le32(1_700_000_000)
                + [0x38] + varint(UInt64(license.flags)) + [0x42, 2] + Array("AT".utf8) + [0x60] + varint(UInt64(accountID))
            list += [0x12] + varint(UInt64(body.count)) + body
        }
        return SteamCatalog.licenseCipher(list + le32(SteamCatalog.crc32(list)), accountID: accountID)
    }

    static func main() {
        let fm = FileManager.default

        // MARK: Steam's scrambling and checksum
        // Known answers from a reference implementation that unscrambles a real licensecache (its CRC matched).
        check(Array(SteamCatalog.licenseCipher([UInt8](repeating: 0, count: 16), accountID: 12_345_678))
              == [121, 50, 94, 44, 79, 108, 106, 66, 84, 58, 94, 61, 102, 94, 67, 68],
              "Valve's random stream seeded with the account ID")
        check(SteamCatalog.licenseCipher([UInt8](repeating: 0, count: 8), accountID: 4_000_000_000) == [77, 109, 72, 100, 116, 96, 76, 83],
              "account IDs above 2^31 seed as Steam's signed int does")
        check(SteamCatalog.crc32(Array("123456789".utf8)) == 0xCBF4_3926, "CRC32 as zlib computes it")

        // MARK: Reading a licence list
        let account: UInt32 = 87_654_321
        let sample = licensecache([(10, 0), (20, 8), (30, 512), (40, 32), (50, 8), (50, 0), (60, 1024 | 512)], accountID: account)
        let read = SteamCatalog.licenses(sample, accountID: account)
        check(read == [10: 0, 20: 8, 30: 512, 40: 32, 50: 0, 60: 1536],
              "packages and flags, a package's good licence beats its expired one: \(String(describing: read))")
        check(SteamCatalog.licenses(sample, accountID: account + 1) == nil, "another account's key doesn't check out")
        var damaged = sample
        damaged[9] ^= 0x01
        check(SteamCatalog.licenses(damaged, accountID: account) == nil, "a damaged file doesn't check out")
        check(SteamCatalog.licenses([1, 2, 3], accountID: account) == nil, "too short")
        check(SteamCatalog.licenses(licensecache([], accountID: account), accountID: account) == [:], "an empty list is a list")

        // MARK: A Steam folder
        let steam = fm.temporaryDirectory.appendingPathComponent("sot-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: steam.appendingPathComponent("appcache"), withIntermediateDirectories: true)
        let apps: [(id: Int, name: String, demoOf: Int?)] = [
            (1001, "Bought", nil), (1002, "Free Weekend Over", nil), (1003, "Store Page Opened", nil),
            (1004, "Has A Demo", nil), (1005, "Has A Demo Demo", 1004), (1006, "Demo Not Added", nil),
            (1007, "Demo Not Added Demo", 1006), (1008, "Refunded", nil), (1009, "Old Demo", 1010),
            (1011, "Bought Too", nil), (1012, "Bought Too Demo", 1011),
        ]
        try? appinfo(apps).write(to: steam.appendingPathComponent("appcache/appinfo.vdf"))
        // Steam caches packages it holds no licence for, too (98, 99): that alone isn't owning.
        try? packageinfo([10: [1001], 20: [1002], 99: [1003], 98: [1004], 60: [1005], 40: [1008], 70: [1009],
                          80: [1011, 1012]]).write(to: steam.appendingPathComponent("appcache/packageinfo.vdf"))

        func ids(_ list: [CatalogApp]) -> [Int] { list.map(\.appID).sorted() }

        // No licence list (an old Steam, never signed in): every cached package counts, as before.
        check(ids(SteamCatalog.ownedGames(steamRoot: steam)) == [1001, 1002, 1003, 1004, 1008, 1011],
              "without a licence list: \(ids(SteamCatalog.ownedGames(steamRoot: steam)))")
        check(SteamCatalog.unownedGames(steamRoot: steam).isEmpty && SteamCatalog.owns(1001, steamRoot: steam) == nil,
              "without a licence list nothing is known not to be owned")

        let config = steam.appendingPathComponent("userdata/\(account)/config", isDirectory: true)
        try? fm.createDirectory(at: config, withIntermediateDirectories: true)
        try? Data(licensecache([(10, 512), (20, 520), (40, 32), (60, 0), (70, 0), (80, 0)], accountID: account))
            .write(to: config.appendingPathComponent("licensecache"))
        // Rewritten within the same second as the catalog read above, which the cache keys on.
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                              ofItemAtPath: config.appendingPathComponent("licensecache").path)

        let owned = SteamCatalog.ownedGames(steamRoot: steam)
        check(ids(owned) == [1001, 1011], "only licensed games, no demos among them: \(ids(owned))")
        let unowned = Dictionary(SteamCatalog.unownedGames(steamRoot: steam).map { ($0.appID, $0) }, uniquingKeysWith: { a, _ in a })
        check(Set(unowned.keys) == [1002, 1003, 1005, 1008], "known but not owned: \(unowned.keys.sorted())")
        check(unowned[1002]?.owned == false && unowned[1002]?.demoOf == nil, "an expired free weekend is a store entry")
        check(unowned[1003]?.owned == false, "a store page Steam cached is a store entry")
        check(unowned[1008]?.owned == false, "a refunded game is a store entry")
        check(unowned[1005]?.demoOf == 1004 && unowned[1005]?.owned == true && unowned[1005]?.name == "Has A Demo Demo",
              "a game with a demo is offered as its demo, licence already there: \(String(describing: unowned[1005]))")
        check(unowned[1004] == nil && unowned[1009] == nil && unowned[1012] == nil,
              "no entry for the game itself, an old demo of a game Steam doesn't cache, or a demo of an owned game")
        check(SteamCatalog.owns(1001, steamRoot: steam) == true && SteamCatalog.owns(1002, steamRoot: steam) == false
              && SteamCatalog.owns(1005, steamRoot: steam) == true && SteamCatalog.owns(1003, steamRoot: steam) == false,
              "owns(): licensed apps, demos included")

        // A demo whose free licence the account doesn't have yet.
        try? packageinfo([10: [1001], 97: [1006]]).write(to: steam.appendingPathComponent("appcache/packageinfo.vdf"))
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(10)],
                              ofItemAtPath: steam.appendingPathComponent("appcache/packageinfo.vdf").path)
        let needsLicense = SteamCatalog.unownedGames(steamRoot: steam).first { $0.appID == 1007 }
        check(needsLicense?.demoOf == 1006 && needsLicense?.owned == false, "a demo still needing its free licence: \(String(describing: needsLicense))")

        // Two accounts on one Steam: the one that signed in last counts.
        let other: UInt32 = 11_111_111
        let otherConfig = steam.appendingPathComponent("userdata/\(other)/config", isDirectory: true)
        try? fm.createDirectory(at: otherConfig, withIntermediateDirectories: true)
        try? Data(licensecache([(97, 0)], accountID: other)).write(to: otherConfig.appendingPathComponent("licensecache"))
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(20)],
                              ofItemAtPath: otherConfig.appendingPathComponent("licensecache").path)
        check(ids(SteamCatalog.ownedGames(steamRoot: steam)) == [1006], "the newest licence list: \(ids(SteamCatalog.ownedGames(steamRoot: steam)))")

        // A licence list that doesn't check out: back to every cached package.
        try? Data([1, 2, 3, 4, 5, 6, 7, 8]).write(to: otherConfig.appendingPathComponent("licensecache"))
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(30)],
                              ofItemAtPath: otherConfig.appendingPathComponent("licensecache").path)
        check(ids(SteamCatalog.ownedGames(steamRoot: steam)) == [1001, 1006] && SteamCatalog.owns(1001, steamRoot: steam) == nil,
              "an unreadable licence list falls back: \(ids(SteamCatalog.ownedGames(steamRoot: steam)))")

        // tests/SteamOwnershipTest/run.sh <Steam folder>: what a real Steam's licence list says.
        if CommandLine.arguments.count > 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let real = SteamCatalog.ownedGames(steamRoot: root)
            print("  \(real.count) owned games, licence list \(SteamCatalog.owns(7, steamRoot: root) == nil ? "unreadable" : "read")")
            for app in SteamCatalog.unownedGames(steamRoot: root) {
                print("  not owned: \(app.appID) \(app.name)\(app.demoOf.map { " – demo of \($0)\(app.owned ? "" : ", free licence missing")" } ?? "")")
            }
        }

        try? fm.removeItem(at: steam)
        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
