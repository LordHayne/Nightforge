// Checks the Battle.net store (BattleNetLibrary, BattleNetStore): product.db read from a file of the
// shape Battle.net 2.53.8 writes – made up here, with no player's data in it – and from two real
// ones, Hearthstone downloading and installed, with the paths, the language and the account's
// country taken out (fixtures/); what doesn't add up refused without a crash; the product codes;
// which cards come of a client's list, Mac first and never in Steam's prefix. Nothing here reads a
// real Battle.net. `battlenet-test --read <copy of product.db>` prints what a copy holds, and its cards.
import Foundation

/// Protobuf's wire format, to write a product.db with.
struct Proto {
    var bytes: [UInt8] = []

    mutating func raw(_ value: UInt64) {
        var rest = value
        while rest >= 0x80 {
            bytes.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        bytes.append(UInt8(rest))
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        raw(UInt64(field) << 3)
        raw(value)
    }

    mutating func data(_ field: Int, _ value: [UInt8]) {
        raw(UInt64(field) << 3 | 2)
        raw(UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ text: String) { data(field, Array(text.utf8)) }

    mutating func double(_ field: Int, _ value: Double) {
        raw(UInt64(field) << 3 | 1)
        bytes += withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    static func message(_ build: (inout Proto) -> Void) -> [UInt8] {
        var proto = Proto()
        build(&proto)
        return proto.bytes
    }
}

@main
struct BattleNetTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() async {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--read" {
            let installs = BattleNetLibrary.read(URL(fileURLWithPath: CommandLine.arguments[2]))
            print(installs.map { $0.map { "\($0.code): installed \($0.installed), playable \($0.playable), version \($0.version)" }.joined(separator: "\n") } ?? "not readable")
            for game in BattleNetLibrary.games(installs ?? [], client: .mac) {
                print("card \(game.gameID.key): \(game.name), \(game.install), \(game.platform), \(game.sizeOnDisk) bytes, \(game.installDir.path)")
            }
            return
        }
        TestDefaults.useWorkFolder()
        parses()
        refuses()
        realFiles()
        codes()
        paths()
        cards()
        starts()
        await theRest()
        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("✓ Battle.net: product.db, codes, paths, cards, Mac first, starts through its client")
    }

    /// A product as the Agent writes it, the fields Nightforge steps over included.
    static func product(_ uid: String, _ code: String, path: String, installed: Bool = true, playable: Bool = true,
                        updateComplete: Bool = true, version: String = "1.2.3", progress: Double = 1, total: UInt64 = 5_000_000,
                        remaining: UInt64 = 0, operation: UInt64? = nil, subfolder: String? = nil, family: String? = nil) -> [UInt8] {
        Proto.message { product in
            product.string(1, uid)
            product.string(2, code)
            product.data(3, Proto.message { settings in
                settings.string(1, path)
                settings.string(2, "eu")
                settings.varint(3, 2)
                settings.varint(4, 2)
                settings.varint(5, 3)
                settings.string(6, "enUS")
                settings.data(8, Proto.message { language in
                    language.string(1, "enUS")
                    language.varint(2, 3)
                })
                settings.string(11, "enUS")
                settings.string(12, "eu")
                if let subfolder { settings.string(13, subfolder) }
            })
            product.data(4, Proto.message { state in
                state.data(1, Proto.message { base in
                    base.varint(1, installed ? 1 : 0)
                    base.varint(2, playable ? 1 : 0)
                    base.varint(3, updateComplete ? 1 : 0)
                    base.varint(4, 0)
                    base.string(7, version)
                    base.string(12, String(repeating: "0", count: 32))
                    base.varint(21, 1_793_990_384_000)
                })
                state.data(2, Proto.message { backfill in
                    backfill.double(1, 0)
                    backfill.varint(2, 0)
                })
                state.data(3, Proto.message { repair in repair.double(1, 0) })
                state.data(4, Proto.message { update in
                    update.double(2, progress)
                    update.varint(4, total)
                    update.varint(5, remaining)
                    update.data(6, Proto.message { $0.string(1, String(repeating: "0", count: 32)) })
                })
            })
            product.data(5, Proto.message { operations in
                if let operation { operations.varint(1, operation) }
                operations.varint(2, 3_006_477_107_200)
            })
            if let family { product.string(6, family) }
            product.varint(7, 0)
        }
    }

    static func database(_ products: [[UInt8]]) -> Data {
        Data(Proto.message { database in
            for product in products { database.data(1, product) }
            database.data(5, Proto.message { settings in
                settings.varint(1, 0)
                settings.varint(2, 1_000_000)
            })
            database.varint(6, 4_121_923)
        })
    }

    static func parses() {
        let file = database([
            product("agent", "agent", path: "/Users/Shared/Battle.net/Agent"),
            product("battle.net", "bna", path: "/Applications/Battle.net.app", total: 4_185_118),
            product("wow_enus", "wow", path: "/Applications/World of Warcraft", progress: 0.25, total: 80, remaining: 60,
                    operation: 0, subfolder: "_retail_", family: "wow"),
            product("prometheus", "pro", path: "C:/Program Files (x86)/Overwatch", installed: false, updateComplete: false, version: "2.20",
                    operation: 2),
            // OP_NONE, -1: ten bytes of varint.
            product("s2_dede", "s2", path: "/Applications/StarCraft II", operation: UInt64.max),
        ])
        guard let installs = ProductDB.parse(file), installs.count == 5 else { return check(false, "the five products: \(String(describing: ProductDB.parse(file)))") }
        check(installs.map(\.code) == ["agent", "bna", "wow", "pro", "s2"], "the product codes, in order")
        check(installs[1].uid == "battle.net" && installs[1].installPath == "/Applications/Battle.net.app" && installs[1].totalBytes == 4_185_118,
              "uid, path, size: \(installs[1])")
        let wow = installs[2]
        check(wow.region == "eu" && wow.subfolder == "_retail_" && wow.family == "wow", "region, WoW's variant folder, family: \(wow)")
        check(wow.progress == 0.25 && wow.totalBytes == 80 && wow.remainingBytes == 60 && wow.operation == .update, "what the update is at: \(wow)")
        check(wow.installed && wow.playable && wow.updateComplete && wow.version == "1.2.3", "its state: \(wow)")
        let overwatch = installs[3]
        check(!overwatch.installed && overwatch.playable && !overwatch.updateComplete && overwatch.version == "2.20", "another's: \(overwatch)")
        check(overwatch.operation == .repair, "a repair under way")
        check(installs[0].operation == nil && installs[4].operation == nil, "no operation, and OP_NONE: none")
        check(installs[0].subfolder.isEmpty && installs[0].family.isEmpty, "fields an older Agent doesn't write: empty")
        check(ProductDB.parse(database([])) == [], "nothing installed is a list too, with nothing in it")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BattleNetTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("product.db")
        try? file.write(to: copy)
        let before = try? FileManager.default.attributesOfItem(atPath: copy.path)[.modificationDate] as? Date
        check(BattleNetLibrary.read(copy)?.count == 5, "read from a file")
        check((try? Data(contentsOf: copy)) == file && (try? FileManager.default.attributesOfItem(atPath: copy.path)[.modificationDate] as? Date) == before,
              "the file stays as it was")
        check(BattleNetLibrary.read(folder.appendingPathComponent("gone.db")) == nil, "no file: nil, not an empty list")
    }

    /// What Battle.net 2.53.8 wrote while Hearthstone came down and after, without the player's details.
    static func realFiles() {
        func read(_ name: String) -> [ProductDB.Install] { BattleNetLibrary.read(URL(fileURLWithPath: "tests/BattleNetTest/fixtures/\(name)")) ?? [] }
        let folder = "/Users/Shared/Games/Hearthstone"
        let downloading = read("product-installing.db")
        check(downloading.map(\.code) == ["agent", "bna", "hsb"], "the client and the game, downloading: \(downloading.map(\.code))")
        guard let coming = downloading.last else { return }
        check(coming.uid == "hs_beta" && coming.code == "hsb", "hs_beta is its uid, hsb its code: \(coming.uid), \(coming.code)")
        check(coming.installPath == folder && coming.region == "eu", "its folder, already: \(coming.installPath)")
        check(!coming.installed && !coming.playable && !coming.updateComplete && coming.version.isEmpty, "nothing of it is there yet: \(coming)")
        check(coming.operation == .update && coming.progress == 0 && coming.totalBytes == 0, "the operation alone says it's coming: \(coming)")
        // The folder isn't asked for: it may not be there yet.
        let card = BattleNetLibrary.games(downloading, client: .mac) { _ in false }
        check(card.map(\.gameID.id) == ["hsb"] && card.first?.install == .downloading(nil), "a card, downloading: \(card.map(\.install))")
        check(card.first?.name == "Hearthstone" && card.first?.installDir.path == folder && card.first?.platform == .mac, "by name, folder and version")
        check(card.first?.pendingUpdate == nil, "a first download isn't an update waiting")

        let installed = read("product-installed.db")
        check(installed.map(\.code) == ["agent", "bna", "hsb"], "the client and the game, installed: \(installed.map(\.code))")
        guard let game = installed.last else { return }
        check(game.installed && game.playable && game.updateComplete && game.operation == nil, "ready: \(game)")
        check(game.version == "37.0.2.256589.255790" && game.totalBytes == 13_282_753_988 && game.remainingBytes == 0 && game.progress == 1, "its version and size: \(game)")
        let ready = BattleNetLibrary.games(installed, client: .mac) { $0.path == folder }
        check(ready.map(\.gameID.key) == ["battlenet.hsb"] && ready.first?.isInstalled == true, "a card, installed")
        check(ready.first?.installDir.path == folder && ready.first?.sizeOnDisk == 13_282_753_988 && ready.first?.pendingUpdate == nil, "with its size, nothing waiting")
        check(ready.first.map { !$0.inNightforgeFolder } == true, "the client's files, not Nightforge's to remove")
        check(BattleNetLibrary.games(installed, client: .mac) { _ in false }.isEmpty, "its folder gone: no card")

        let dropped = ["thomas", "AUT", "acct-", "geoip", "deDE"]
        for name in ["product-installing.db", "product-installed.db"] {
            let text = String(decoding: (try? Data(contentsOf: URL(fileURLWithPath: "tests/BattleNetTest/fixtures/\(name)"))) ?? Data(), as: UTF8.self)
            check(!text.isEmpty && !dropped.contains { text.contains($0) }, "\(name) holds nothing of the player's")
        }
    }

    static func refuses() {
        let good = [UInt8](database([product("wow", "wow", path: "/Applications/World of Warcraft")]))
        check(ProductDB.parse(Data()) == nil, "an empty file isn't a product.db")
        check(ProductDB.parse(Data(good.prefix(good.count - 40))) == nil, "cut off in a product: refused, not a shorter list")
        for length in 0..<good.count { _ = ProductDB.parse(Data(good.prefix(length))) }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<2_000 {
            let noise = (0..<64).map { _ -> UInt8 in
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return UInt8(truncatingIfNeeded: state >> 56)
            }
            _ = ProductDB.parse(Data(noise))
        }
        check(ProductDB.parse(Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])) == nil, "a length past the end of the file")
        check(ProductDB.parse(Data([0x0A] + [UInt8](repeating: 0xFF, count: 11))) == nil, "a varint with no end")
        check(ProductDB.parse(Data([0x0B])) == nil, "a group")
        check(ProductDB.parse(Data([0x00, 0x01])) == nil, "field number 0")
        check(ProductDB.parse(Data([0x0E])) == nil, "a wire type that doesn't exist")
        // A known field of another kind than expected: stepped over, as an unknown one would be.
        let odd = Proto.message { database in
            database.varint(1, 7)
            database.data(1, Proto.message { product in
                product.varint(2, 9)
                product.data(1, [0xFF, 0xFE])
            })
        }
        check(ProductDB.parse(Data(odd)) == [ProductDB.Install()], "other kinds of field and text that isn't UTF-8: left empty")
    }

    static func codes() {
        check(Provider.battlenet.label == "Battle.net" && Provider.battlenet.short == "BATTLE.NET", "its names")
        check(Provider(rawValue: "battlenet") == .battlenet, "kept by its raw value")
        check(Provider.allCases.last == .battlenet, "the older stores keep their places")
        check(GameID.battlenet("pro").key == "battlenet.pro", "the key")
        check(GameID(key: "battlenet.wow_classic_era") == .battlenet("wow_classic_era"), "and back, with its underscores")
        check(GameID(key: "battlenet.pro")?.steamAppID == nil, "no Steam app ID")
        for (code, title) in BattleNetLibrary.titles {
            check(GameID.isPlain(code) && GameID(key: "battlenet.\(code)") == .battlenet(code), "\(code) makes a key")
            check(!title.name.isEmpty, "\(code) has a name")
        }
        let titles = BattleNetLibrary.titles
        check(titles["bna"] == nil && titles["agent"] == nil, "the client is no game")
        check(titles["fenris"]?.startCode == "Fen" && titles["fen"] == nil, "Diablo IV: the code is fenris, Fen starts it")
        check(titles["pro"]?.startCode == "Pro" && titles["hsb"]?.startCode == "WTCG" && titles["wow"]?.startCode == "WoW", "start codes")
        check(titles["wow_classic"]?.startCode == nil, "WoW Classic has none that's known")
        let onTheMac = Set(titles.filter { $0.value.macVersion }.keys)
        check(onTheMac == ["wow", "wow_classic", "wow_classic_era", "hsb", "d3", "s2", "s1", "hero", "w3"], "the Mac versions: \(onTheMac.sorted())")
        check(titles["auks"]?.antiCheat == ["RICOCHET"], "Call of Duty's anti-cheat")
        check(titles.filter { !$0.value.antiCheat.isEmpty }.keys.sorted() == ["auks"], "no other title is stopped here")
    }

    static let prefix = URL(fileURLWithPath: "/Nightforge/BattleNet/Prefix", isDirectory: true)
    static var windows: BattleNetLibrary.Client { .windows(prefix: prefix) }

    static func paths() {
        func windowsFolder(_ path: String) -> String? { BattleNetLibrary.folder(path, client: windows)?.path }
        check(windowsFolder("C:/Program Files (x86)/Overwatch") == prefix.path + "/drive_c/Program Files (x86)/Overwatch", "C: is the prefix's")
        check(windowsFolder(#"C:\Program Files (x86)\Overwatch\"#) == prefix.path + "/drive_c/Program Files (x86)/Overwatch", "with backslashes")
        check(windowsFolder("c:/Games/Diablo IV") == prefix.path + "/drive_c/Games/Diablo IV", "the drive's case doesn't matter")
        check(windowsFolder("Z:/Volumes/Games/Overwatch") == "/Volumes/Games/Overwatch", "Z: is the Mac")
        check(windowsFolder("D:/Overwatch") == nil, "a drive Wine isn't known to have")
        check(windowsFolder("C:/Games/../../../../etc") == nil, "no climbing out")
        check(windowsFolder("C:") == nil && windowsFolder("") == nil, "no folder to it")
        check(BattleNetLibrary.folder("/Applications/World of Warcraft", client: .mac)?.path == "/Applications/World of Warcraft", "a Mac path")
        check(BattleNetLibrary.folder("Applications/World of Warcraft", client: .mac) == nil, "a Mac path that isn't absolute")
        check(BattleNetLibrary.folder("/Applications/../etc", client: .mac) == nil, "no climbing out on the Mac either")
        check(BattleNetLibrary.Client.mac.database.path == "/Users/Shared/Battle.net/Agent/product.db", "the Mac client's list")
        check(windows.database.path == prefix.path + "/drive_c/ProgramData/Battle.net/Agent/product.db", "the Windows client's")
    }

    static func install(_ code: String, path: String, installed: Bool = true, playable: Bool = true, updateComplete: Bool = true,
                        remaining: UInt64 = 0, subfolder: String = "") -> ProductDB.Install {
        var install = ProductDB.Install()
        install.code = code
        install.installPath = path
        install.installed = installed
        install.playable = playable
        install.updateComplete = updateComplete
        install.remainingBytes = remaining
        install.totalBytes = 1_000
        install.subfolder = subfolder
        return install
    }

    static func cards() {
        let wowFolder = "/Applications/World of Warcraft"
        let listed = [
            install("agent", path: "/Users/Shared/Battle.net/Agent"), install("bna", path: "/Applications/Battle.net.app"),
            install("wow", path: wowFolder), install("wow_classic", path: wowFolder, subfolder: "_anniversary_"),
            install("hsb", path: "/Applications/Hearthstone", installed: false, playable: true),
            install("d3", path: "/Applications/Diablo III", installed: false, playable: false),
            install("s2", path: "/Applications/Gone"), install("xyz", path: "/Applications/Xyz"),
            install("hsb", path: "/Applications/Hearthstone Copy"),
        ]
        let there = [wowFolder, wowFolder + "/_retail_", wowFolder + "/_anniversary_", "/Applications/Hearthstone", "/Applications/Diablo III", "/Applications/Xyz",
                     "/Users/Shared/Battle.net/Agent", "/Applications/Battle.net.app"]
        let mac = BattleNetLibrary.games(listed, client: .mac) { there.contains($0.path) }
        check(mac.map(\.gameID.id) == ["wow", "wow_classic", "hsb"],
              "known titles, installed or playable, whose folder is there, each once: \(mac.map(\.gameID.id))")
        check(mac.allSatisfy { $0.platform == .mac && $0.isInstalled && $0.provider == .battlenet }, "Mac versions, installed")
        check(mac.first?.name == "World of Warcraft" && mac.first?.macNative == true, "by its name")
        check(mac.first?.installDir.path == wowFolder + "/_retail_", "WoW in its variant's folder")
        check(mac.dropFirst().first?.installDir.path == wowFolder + "/_anniversary_", "a variant the client names")
        check(mac.first?.id == "Battle.net#battlenet.wow" && mac.first?.sizeOnDisk == 1_000, "its place in the list, its size")
        let noVariant = BattleNetLibrary.games([install("wow", path: wowFolder)], client: .mac) { $0.path == wowFolder }
        check(noVariant.first?.installDir.path == wowFolder, "no variant folder: the install folder")

        let overwatch = prefix.path + "/drive_c/Program Files (x86)/Overwatch"
        let hearthstone = prefix.path + "/drive_c/Program Files (x86)/Hearthstone"
        let call = prefix.path + "/drive_c/Program Files (x86)/Call of Duty"
        let inPrefix = BattleNetLibrary.games(
            [install("pro", path: "C:/Program Files (x86)/Overwatch", updateComplete: false, remaining: 1_234),
             install("hsb", path: "C:/Program Files (x86)/Hearthstone"), install("auks", path: "C:/Program Files (x86)/Call of Duty")],
            client: windows) { [overwatch, hearthstone, call].contains($0.path) }
        guard let pro = inPrefix.first else { return check(false, "Overwatch's card") }
        check(pro.platform == .windows && pro.bottle.url == prefix && !pro.bottle.isBuiltIn, "a Windows version in Battle.net's own prefix")
        check(pro.bottle != Engine.bottle && pro.steamTwin == 2_357_570, "not Steam's prefix; Steam's pictures")
        check(pro.windowsFolderMarker == #"\Program Files (x86)\Overwatch\"#, "what ps shows of it: \(pro.windowsFolderMarker)")
        check(!(#"C:\Program Files (x86)\Steam\steamapps\common\Overwatch\Overwatch.exe"#.contains(pro.windowsFolderMarker)), "Steam's copy doesn't count as this one")
        check(pro.pendingUpdate == 1_234, "an update the client has to do first")
        check(inPrefix[1].pendingUpdate == nil, "none waiting")
        check(pro.antiCheatBlock == nil, "Overwatch isn't stopped here")
        check(inPrefix[2].antiCheatBlock?.antiCheat == ["RICOCHET"], "Call of Duty is")

        // On an external drive, should it be there all the same: Nightforge suggests none (Game.moveNote).
        let onDrive = "/Volumes/Games/Nightforge Games/Battle.net/Hearthstone"
        let plugged = BattleNetLibrary.games([install("hsb", path: onDrive)], client: .mac) { ["/Volumes/Games", onDrive].contains($0.path) }
        check(plugged.first?.isInstalled == true && plugged.first?.installDir.path == onDrive, "a game on a drive that's there plays from it")
        check(plugged.first.map { DriveLibrary.drive(of: $0.installDir)?.lastPathComponent == "Games" && !$0.inNightforgeFolder } == true,
              "it counts as on that drive, not as Nightforge's to remove")
        let unplugged = BattleNetLibrary.games([install("hsb", path: onDrive)], client: .mac) { _ in false }
        check(unplugged.first?.onUnpluggedDrive == true && unplugged.first?.missingDrive == "Games" && unplugged.first?.isInstalled == false,
              "with the drive away it stays, waiting for it")
        check(BattleNetLibrary.games([install("hsb", path: onDrive)], client: .mac) { $0.path == "/Volumes/Games" }.isEmpty,
              "gone from a drive that's there: uninstalled")
        let zPath = "Z:/Volumes/Games/Nightforge Games/Battle.net/Overwatch"
        let viaWine = BattleNetLibrary.games([install("pro", path: zPath)], client: windows) { _ in true }
        check(viaWine.first?.windowsFolderMarker == #"\Volumes\Games\Nightforge Games\Battle.net\Overwatch\"#,
              "the Windows client's game on a drive, as ps shows it: \(viaWine.first?.windowsFolderMarker ?? "-")")

        check(mac.first?.moveNote?.contains("Battle.net") == true, "a Mac game says it stays on the internal disk")
        check(pro.moveNote == nil, "a Windows client's has nothing to say about that")
        let steam = Game(gameID: .steam(570), name: "Dota 2", bottle: Engine.bottle, steamRoot: Engine.steamRoot, steamExeWindowsPath: "",
                     installDir: Engine.steamRoot, sizeOnDisk: 1)
        check(steam.moveNote == nil, "other stores' games: no such note")

        let both = BattleNetLibrary.merged(mac: mac, windows: inPrefix)
        check(both.map(\.gameID.id) == ["wow", "wow_classic", "hsb", "pro", "auks"], "Mac first: \(both.map(\.gameID.id))")
        check(both.first { $0.gameID.id == "hsb" }?.platform == .mac, "Hearthstone from the Mac when both have it")
        check(BattleNetLibrary.merged(mac: [], windows: inPrefix).first { $0.gameID.id == "hsb" }?.platform == .windows, "from Wine when only it has it")

        check(BattleNetLibrary.prefix != Engine.prefix && !BattleNetLibrary.prefix.path.hasPrefix(Engine.prefix.path + "/"), "not in Steam's prefix")
        let real = BattleNetLibrary.Client.windows(prefix: BattleNetLibrary.prefix)
        check(real.bottle.name != Engine.bottle.name && real.bottle.url != Engine.bottle.url, "a bottle of its own")
    }

    /// The start through the Mac client (BattleNetStart). Nothing here runs a client: the logs are made up
    /// from lines the real one writes.
    static func starts() {
        // What the client is told.
        check(BattleNetStart.command(code: "hsb") == "launch WTCG", "Hearthstone by its start code, not its product code")
        check(BattleNetStart.command(code: "wow") == "launch WoW", "WoW")
        check(BattleNetStart.command(code: "wow_classic") == "launch_uid wow_classic", "Classic has no start code: by its name in the list")
        check(BattleNetStart.command(code: "pro") == nil, "no Mac version: nothing to ask the Mac client")
        check(BattleNetStart.command(code: "bna") == nil, "the client itself isn't a game")
        check(BattleNetStart.arguments(command: "launch WTCG") == ["--exec=launch WTCG"], "one argument, as the client wants it")
        check(BattleNetStart.gamePage(code: "hsb")?.absoluteString == "battlenet://WTCG", "the game's page")
        check(BattleNetStart.gamePage(code: "wow_classic") == nil, "Classic has none: the client as it is")

        // What stops a start before it begins.
        check(BattleNetStart.blocker(code: "hsb", pendingUpdate: false, clientThere: true) == nil, "ready to go")
        check(BattleNetStart.blocker(code: "hsb", pendingUpdate: true, clientThere: true) == .updateFirst, "the client's update first")
        check(BattleNetStart.blocker(code: "hsb", pendingUpdate: false, clientThere: false) == .noClient, "the client was removed")
        check(BattleNetStart.blocker(code: "pro", pendingUpdate: false, clientThere: true) == .notAMacGame, "Windows client's game")

        // The client's state by its log.
        func line(_ text: String) -> String { "I 2026-11-07 19:25:29.668161 " + text + "\n" }
        let ready = line("[AccountManager] {Main} " + BattleNetClient.accountReady)
        let up = line("[GameController] {Main} " + BattleNetStart.controllerReady)
        let down = line("[GameController] {Main} " + BattleNetStart.controllerDown)
        let asks = line("[Login] {Main} " + BattleNetClient.pageAsks + "Credential")
        check(BattleNetStart.state(running: false, log: ready + up) == .notRunning, "no process: not running, whatever an old log says")
        check(BattleNetStart.state(running: true, log: nil) == .starting, "no log of this run yet")
        check(BattleNetStart.state(running: true, log: ready) == .starting, "account there, games' side not yet: a command would go unheard")
        check(BattleNetStart.state(running: true, log: ready + up) == .ready, "both there")
        check(BattleNetStart.state(running: true, log: asks) == .signInNeeded, "the sign-in page asks")
        check(BattleNetStart.state(running: true, log: asks + ready + up) == .ready, "through the page")
        check(BattleNetStart.state(running: true, log: ready + up + asks) == .signInNeeded, "the page asks again")
        check(BattleNetStart.state(running: true, log: ready + up + down) == .starting, "a run that ends isn't ready")
        check(BattleNetStart.state(running: true, log: ready + up + down + ready + up) == .ready, "the same log, up again")

        // Which log is the client's.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func log(_ name: String, _ text: String, age: TimeInterval = 0) {
            let file = folder.appendingPathComponent(name)
            try? text.write(to: file, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        check(BattleNetStart.clientLog(in: folder, since: nil) == nil, "no logs")
        log("battle.net-20261107T192521.941521.log", line("[Main] {} Logging started for app_loader 2.53.8.17986"))
        check(BattleNetStart.clientLog(in: folder, since: nil) == nil, "the loader's short log isn't the client's")
        log("battle.net-20261107T192522.248808.log", ready + up)
        log("battle.net-20261107T193000.000000.log", line("[Main] {} Logging started for app_loader 2.53.8.17986"))
        let found = BattleNetStart.clientLog(in: folder, since: nil)
        check(found?.file.lastPathComponent == "battle.net-20261107T192522.248808.log", "the newest with an account in it, past the loader of a command sent")
        check(found?.text.contains(BattleNetStart.controllerReady) == true, "with its text")
        log("battle.net-20261107T192522.248808.log", ready + up, age: 3600)
        check(BattleNetStart.clientLog(in: folder, since: Date().addingTimeInterval(-60)) == nil, "written before this client started: an old run's")
        check(BattleNetStart.clientLog(in: folder, since: Date().addingTimeInterval(-7200)) != nil, "written since")

        // Lines to events.
        check(BattleNetStart.events(in: "") == [], "nothing new")
        check(BattleNetStart.events(in: line("[GameLaunchController] {Main} Data-sharing consent fetched from server: consentId=X optIn=0")) == [], "other lines say nothing")
        check(BattleNetStart.events(in: line("[GameLauncher] {Main} Game launch options: programId=WTCG")) == [.launching], "the client took it")
        check(BattleNetStart.events(in: line("[GameLauncher] {Main} Attempted to launch a game that is not installed. uid=hs_beta")) == [.refused], "not installed")
        check(BattleNetStart.events(in: line("[GameLaunchController] {Main} Pending game launch expired before Agent reported it running. uid=hs_beta")) == [.refused], "expired")
        check(BattleNetStart.events(in: line("[GameLaunchController] {Main} Game launch sequence canceled")) == [.calledOff], "called off")
        let shutdown = String(repeating: line("[GameLaunchController] {Main} Game launch sequence canceled"), count: 4) + down
        check(BattleNetStart.events(in: shutdown) == [.clientEnds], "at the client's end every launch is called off: that's the end (7.11. 20:15:55)")

        // Following the log.
        let followed = folder.appendingPathComponent("followed.log")
        try? "from before\n".write(to: followed, atomically: true, encoding: .utf8)
        var follower = BattleNetStart.LogFollower(file: followed)
        check(follower.newText().isEmpty, "what came before the command isn't read")
        func append(_ text: String) {
            guard let handle = try? FileHandle(forWritingTo: followed) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        }
        append("first line\nhalf a li")
        check(follower.newText() == "first line\n", "whole lines only")
        append("ne\nthird\n")
        check(follower.newText() == "half a line\nthird\n", "the rest of it once it's whole")
        check(follower.newText().isEmpty, "nothing twice")
        var missing = BattleNetStart.LogFollower(file: folder.appendingPathComponent("gone.log"))
        check(missing.newText().isEmpty, "a log that's gone says nothing")

        // Second by second.
        var quiet = BattleNetStart.Watch()
        var steps: [BattleNetStart.Watch.Step] = []
        for _ in 1...BattleNetStart.Watch.askAfter { steps.append(quiet.step([])) }
        check(steps.enumerated().filter { $0.element == .sendAgain }.map { $0.offset + 1 } == [12, 24], "not taken: sent again twice")
        check(steps.last == .playerAsked && steps.dropLast().allSatisfy { $0 != .playerAsked }, "and then the client's window, once")
        for _ in 1..<BattleNetStart.Watch.answerFor { check(quiet.step([]) == .wait, "the player has time to answer") }
        check(quiet.step([]) == .failed(.noAnswer), "and then the start is over")
        var taken = BattleNetStart.Watch()
        _ = taken.step([.launching])
        var after = (2...BattleNetStart.Watch.askAfter).map { _ in taken.step([]) }
        check(!after.contains(.sendAgain), "taken: nothing is sent again")
        check(!after.contains(.playerAsked), "taken: the curtain stays at 30 s, a game may take its time")
        after = ((BattleNetStart.Watch.askAfter + 1)..<BattleNetStart.Watch.askAfterTaken).map { _ in taken.step([]) }
        check(after.allSatisfy { $0 == .wait }, "taken: quiet until the longer wait is over")
        check(taken.step([]) == .playerAsked, "taken but still no game: the window after the longer wait")
        for _ in 1..<BattleNetStart.Watch.answerFor { check(taken.step([]) == .wait, "the player has time to answer then too") }
        check(taken.step([]) == .failed(.noAnswer), "and then that start is over too")
        var takenLate = BattleNetStart.Watch()
        for _ in 1..<20 { _ = takenLate.step([]) }
        _ = takenLate.step([.launching])
        after = (21..<BattleNetStart.Watch.askAfterTaken).map { _ in takenLate.step([]) }
        check(after.allSatisfy { $0 == .wait }, "taken only after a while: the longer wait counts as well")
        check(takenLate.step([]) == .playerAsked, "and ends at the same second")
        var refused = BattleNetStart.Watch()
        check(refused.step([.refused]) == .failed(.refused), "refused: at once")
        var offCalled = BattleNetStart.Watch()
        check(offCalled.step([.calledOff]) == .failed(.calledOff), "called off: at once")
        var ended = BattleNetStart.Watch()
        check(ended.step([.clientEnds, .calledOff]) == .failed(.clientEnded), "the client's end outweighs the rest")

        // Play time.
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let started = BattleNetStore.played(nil, at: day)
        check(started.lastPlayed == day && started.minutes == 0, "a start: last played, no minutes")
        let played = BattleNetStore.played(started, minutes: 42, at: day.addingTimeInterval(2520))
        check(played.minutes == 42 && played.lastPlayed == day.addingTimeInterval(2520), "a session adds up")
        check(BattleNetStore.played(played, minutes: -5, at: day).minutes == 42, "never less")
        let cards = BattleNetLibrary.games([install("hsb", path: "/Users/x/Hearthstone"), install("s2", path: "/Users/x/SC2")], client: .mac) { _ in true }
        let timed = BattleNetStore.withPlayTimes(cards, ["hsb": played])
        check(timed.first { $0.gameID.id == "hsb" }?.playtimeMinutes == 42, "the card has its minutes")
        check(timed.first { $0.gameID.id == "s2" }?.playtimeMinutes == nil, "one never played has none")
    }

    @MainActor
    static func theRest() async {
        let store = BattleNetStore()
        check(store.provider == .battlenet, "the store's provider")
        check(!store.isConnected, "off until its switch is on, whatever is on this Mac")
        let none = await store.library()
        check(none.isEmpty, "no cards then")
        let game = BattleNetLibrary.games([install("pro", path: "C:/Overwatch")], client: windows) { _ in true }[0]
        do {
            try await store.install(game, context: StoreContext())
            check(false, "installing isn't Nightforge's")
        } catch { check(error is BattleNetStore.ClientsOwn, "installing stays the client's") }
        do {
            try await store.uninstall(game)
            check(false, "removing isn't Nightforge's")
        } catch {
            check(error.localizedDescription.contains("Battle.net"), "removing stays the client's: \(error.localizedDescription)")
        }

        check(OfflineReadiness.of(game, analysis: nil, accountRemembered: false) == .battleNet, "needs the client online")
        check(GameTest.skip(GameTest.Facts(store: .battlenet)) == .battleNet, "the game test leaves them out")
        check(!GameTest.Skip.battleNet.german.isEmpty, "and says why")
        // Every other start reaches Steam's or Epic's way: Battle.net's games stop before them.
        let source = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        if let launch = source.range(of: "func launch(_ game: Game, d3dMetalChecked"),
           let guardLine = source.range(of: "if game.provider == .battlenet, game.platform != .mac {", range: launch.upperBound..<source.endIndex),
           let client = source.range(of: "case .battlenet: launchBattleNetMac(game)", range: guardLine.upperBound..<source.endIndex),
           let steamStart = source.range(of: "let viaSteam = game.provider == .steam", range: launch.upperBound..<source.endIndex) {
            check(guardLine.lowerBound < client.lowerBound && client.lowerBound < steamStart.lowerBound,
                  "a Mac card goes to its client, a Windows client's stops: never Steam's or Epic's way")
        } else {
            check(false, "LibraryModel.launch as this test knows it")
        }
    }
}
