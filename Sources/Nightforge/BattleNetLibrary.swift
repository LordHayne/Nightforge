import Foundation

/// Battle.net's games as its Agent lists them in product.db. There are two clients: Blizzard's own for
/// the Mac (WoW and the other Mac versions), and the Windows one in a Wine prefix of its own for
/// the games without a Mac version (Overwatch, Diablo IV) – never in Steam's prefix, whose session
/// Nightforge ends whenever Steam restarts. A game both list plays from the Mac.
///
/// Only what's installed: which games an account owns, Blizzard tells no one without a web sign-in.
/// The files are only ever read, and the games stay the client's to download, update and remove.
enum BattleNetLibrary {
    /// What Nightforge knows of a product, by its code in product.db.
    struct Title: Equatable {
        var name: String
        /// What `--exec="launch …"` takes; nil where none is known (the WoW Classic variants).
        var startCode: String?
        /// Blizzard ships it for the Mac.
        var macVersion = false
        /// WoW's variants share one install folder and live in these below it.
        var variantFolder: String?
        /// The same game on Steam, for its pictures and store facts.
        var steamTwin: Int?
        /// Stops it on a Mac whichever way it's started.
        var antiCheat: [String] = []
    }

    /// The games Battle.net can bring, by product code (docs/recherche/battlenet.md, "Vier Kennungen pro
    /// Spiel"). Anything else in product.db – the client itself (bna, agent), test realms – isn't a
    /// game of the player's. Diablo IV's code is fenris; Fen is what starts it.
    static let titles: [String: Title] = [
        "wow": Title(name: "World of Warcraft", startCode: "WoW", macVersion: true, variantFolder: "_retail_"),
        "wow_classic": Title(name: "World of Warcraft Classic", macVersion: true, variantFolder: "_classic_"),
        "wow_classic_era": Title(name: "World of Warcraft Classic Era", macVersion: true, variantFolder: "_classic_era_"),
        "hsb": Title(name: "Hearthstone", startCode: "WTCG", macVersion: true),
        "d3": Title(name: "Diablo III", startCode: "D3", macVersion: true),
        "s2": Title(name: "StarCraft II", startCode: "S2", macVersion: true),
        "s1": Title(name: "StarCraft: Remastered", startCode: "S1", macVersion: true),
        "hero": Title(name: "Heroes of the Storm", startCode: "Hero", macVersion: true),
        "w3": Title(name: "Warcraft III: Reforged", startCode: "W3", macVersion: true),
        "pro": Title(name: "Overwatch", startCode: "Pro", steamTwin: 2_357_570),
        "fenris": Title(name: "Diablo IV", startCode: "Fen", steamTwin: 2_344_520),
        "osi": Title(name: "Diablo II: Resurrected", startCode: "OSI"),
        "anbs": Title(name: "Diablo Immortal", startCode: "ANBS"),
        "gryphon": Title(name: "Warcraft Rumble", startCode: "GRY"),
        "w1r": Title(name: "Warcraft I: Remastered", startCode: "W1R"),
        "w2r": Title(name: "Warcraft II: Remastered", startCode: "W2R"),
        "auks": Title(name: "Call of Duty", startCode: "AUKS", steamTwin: 1_938_090, antiCheat: ["RICOCHET"]),
    ]

    /// Which of the two clients a list comes from.
    enum Client {
        case mac
        /// The Windows client, in the prefix given.
        case windows(prefix: URL)

        var platform: Platform {
            if case .mac = self { return .mac }
            return .windows
        }

        var bottle: Bottle {
            switch self {
            case .mac: return Bottle(name: "Battle.net Mac", url: URL(fileURLWithPath: "/Users/Shared/Battle.net", isDirectory: true))
            case .windows(let prefix): return Bottle(name: "Battle.net", url: prefix)
            }
        }

        /// The Agent's list. Under Wine the program data folder is the prefix's.
        var database: URL {
            switch self {
            case .mac: return URL(fileURLWithPath: "/Users/Shared/Battle.net/Agent/product.db")
            case .windows(let prefix): return prefix.appendingPathComponent("drive_c/ProgramData/Battle.net/Agent/product.db")
            }
        }
    }

    /// Battle.net's Wine prefix: its own wineserver and registry, none of them Steam's.
    static var prefix: URL { Engine.supportDir.appendingPathComponent("BattleNet/Prefix", isDirectory: true) }

    /// The file as it's now, without touching it; nil when there's none or it can't be read whole.
    /// A real one is a few KB per product: anything huge isn't that.
    static func read(_ file: URL) -> [ProductDB.Install]? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size <= 16 << 20,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return ProductDB.parse(data)
    }

    /// Where a product's folder is on the Mac. The Windows client's C: is the prefix's drive_c and Z:
    /// the Mac's root, as Wine has them; other drives aren't known. It may write "/" or "\". A path
    /// that climbs out of where it says it is isn't followed: a Windows program can write this file.
    static func folder(_ path: String, client: Client) -> URL? {
        guard !path.isEmpty else { return nil }
        let parts = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        guard !parts.contains("..") else { return nil }
        switch client {
        case .mac:
            guard path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: true)
        case .windows(let prefix):
            guard let drive = parts.first?.lowercased(), parts.count > 1 else { return nil }
            let below = parts.dropFirst().joined(separator: "/")
            switch drive {
            case "c:": return prefix.appendingPathComponent("drive_c/" + below, isDirectory: true)
            case "z:": return URL(fileURLWithPath: "/" + below, isDirectory: true)
            default: return nil
            }
        }
    }

    /// The games of one client's list: known titles the Agent calls installed or playable, each once.
    /// Its folder has to be there: product.db can outlive an uninstall. On a drive that isn't plugged
    /// in, the game is only waiting for the drive, like Epic's and GOG's: it stays, to "Connect T7 to Play".
    /// A game the Windows client lists for a title that has a Mac version comes along too; `merged`
    /// decides between them.
    static func games(_ installs: [ProductDB.Install], client: Client,
                      exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [Game] {
        var seen = Set<String>()
        return installs.compactMap { install in
            guard let title = titles[install.code], install.installed || install.playable,
                  let top = folder(install.installPath, client: client)
            else { return nil }
            if !exists(top) {
                guard let drive = DriveLibrary.drive(of: top), !exists(drive), seen.insert(install.code).inserted else { return nil }
                var waiting = game(install, title, client: client, installDir: top)
                waiting.install = .notInstalled
                waiting.missingDrive = drive.lastPathComponent
                return waiting
            }
            guard seen.insert(install.code).inserted else { return nil }
            // WoW's variants share `top`: each its own folder, so that a running one is told from the others.
            let variant = (install.subfolder.isEmpty ? title.variantFolder : install.subfolder)
                .map { top.appendingPathComponent($0, isDirectory: true) }
            let installDir = variant.flatMap { exists($0) ? $0 : nil } ?? top
            return game(install, title, client: client, installDir: installDir)
        }
    }

    private static func game(_ install: ProductDB.Install, _ title: Title, client: Client, installDir: URL) -> Game {
        var game = Game(gameID: .battlenet(install.code), name: title.name, bottle: client.bottle, steamRoot: client.bottle.url,
                        steamExeWindowsPath: "", installDir: installDir, sizeOnDisk: Int64(clamping: install.totalBytes))
        game.platform = client.platform
        game.macNative = title.macVersion
        game.windowsBuild = true
        game.steamTwin = title.steamTwin
        if case .windows(let prefix) = client {
            // What `ps` shows of it: the whole path below the drive (C:, or Z: for one on an external
            // drive), so Steam's copy of the game is another one.
            let root = prefix.appendingPathComponent("drive_c").standardizedFileURL.path + "/"
            let path = installDir.standardizedFileURL.path
            game.installDirName = (path.hasPrefix(root) ? String(path.dropFirst(root.count)) : String(path.dropFirst()))
                .replacingOccurrences(of: "/", with: "\\")
        } else {
            game.installDirName = installDir.lastPathComponent
        }
        // The same place in the list whichever client it comes from.
        game.listID = "Battle.net#\(game.gameID.key)"
        if !title.antiCheat.isEmpty { game.antiCheatBlock = AntiCheatBlock(antiCheat: title.antiCheat, geforceNow: nil) }
        // The client updates it before it starts; what's left of that, 0 while it hasn't worked it out.
        if !install.playable || !install.updateComplete { game.pendingUpdate = Int64(clamping: install.remainingBytes) }
        return game
    }

    /// Mac first: a game the Mac client has plays from there, whatever the Windows client has of it.
    static func merged(mac: [Game], windows: [Game]) -> [Game] {
        let onTheMac = Set(mac.map(\.gameID))
        return mac + windows.filter { !onTheMac.contains($0.gameID) }
    }
}
