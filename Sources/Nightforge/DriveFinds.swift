import Foundation

/// What lies in "Nightforge Games" on a drive, read from the drive's own files alone – nothing of
/// Nightforge's data on the Mac is asked. A drive used with an earlier Nightforge, or on another
/// Mac, says here what it holds.
struct DriveContents: Equatable {
    /// A Steam game in a library there, from its appmanifest_<id>.acf.
    struct SteamGame: Equatable {
        let appID: Int
        var name: String
        var installDir: String
        var size: Int64
        /// Steam had all of it (StateFlags 4); otherwise a download or update that stopped part-way.
        var complete: Bool
    }

    /// A folder in "Epic Games". legendary leaves nothing of its own in a game's folder (its manifest
    /// and its list are on the Mac), so the folder's name is what there is to go by. `appNames` is
    /// what an Epic Games Launcher's notes in it name (.egstore/*.mancpn) – few games bring those.
    struct EpicFolder: Equatable {
        let name: String
        var appNames: [String] = []
    }

    /// A GOG game, from the goggame-<id>.info its own files bring.
    struct GOGGame: Equatable {
        let id: String
        var title: String
        var build: String
        /// A language code as gogdl takes it ("de-DE"); "en-US" where the file names none.
        var language: String
        var platform: Platform
        /// The game's folder in "GOG Games" (a Mac version: its app).
        var folder: String
        /// The add-ons whose files are in the folder too.
        var dlcs: [String] = []
    }

    var windowsSteam: [SteamGame] = []
    var macSteam: [SteamGame] = []
    var epic: [EpicFolder] = []
    var gog: [GOGGame] = []

    var isEmpty: Bool { windowsSteam.isEmpty && macSteam.isEmpty && epic.isEmpty && gog.isEmpty }

    /// Reads "Nightforge Games" on `drive`. Only reads.
    static func read(drive: URL) -> DriveContents {
        DriveContents(windowsSteam: steamGames(in: DriveLibrary.windowsSteam(on: drive)),
                      macSteam: steamGames(in: DriveLibrary.macSteam(on: drive)),
                      epic: epicFolders(in: DriveLibrary.epic(on: drive)),
                      gog: gogGames(in: DriveLibrary.gog(on: drive)))
    }

    /// The games a Steam library folder holds, by its manifests.
    static func steamGames(in library: URL) -> [SteamGame] {
        let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }.compactMap { file in
            guard let state = VDF.parse(contentsOf: file)?["appstate"], let appID = state["appid"]?.string.flatMap({ Int($0) }),
                  let installDir = state["installdir"]?.string, !installDir.isEmpty
            else { return nil }
            return SteamGame(appID: appID, name: state["name"]?.string ?? installDir, installDir: installDir,
                             size: state["sizeondisk"]?.string.flatMap { Int64($0) } ?? 0,
                             complete: (state["stateflags"]?.string.flatMap { Int($0) } ?? 4) == 4)
        }
        .sorted { $0.appID < $1.appID }
    }

    /// The settings files Nightforge writes beside a game: a folder with nothing else holds no game.
    static let ownFiles: Set<String> = ["dxmt.conf", "dxvk.conf", "nightforge-vulkan.conf"]

    /// The folders in "Epic Games" that hold something of a game.
    static func epicFolders(in base: URL) -> [EpicFolder] {
        let fm = FileManager.default
        return folders(in: base).compactMap { folder in
            let entries = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            guard entries.contains(where: { !$0.hasPrefix(".") && !ownFiles.contains($0) }) else { return nil }
            let notes = (try? fm.contentsOfDirectory(at: folder.appendingPathComponent(".egstore"), includingPropertiesForKeys: nil)) ?? []
            let names = notes.filter { $0.pathExtension == "mancpn" }.compactMap { note -> String? in
                guard let data = try? Data(contentsOf: note), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return (object["AppName"] as? String).flatMap { GameID.isPlain($0) ? $0 : nil }
            }
            return EpicFolder(name: folder.lastPathComponent, appNames: names.sorted())
        }
    }

    /// The GOG games in "GOG Games": every folder (or app) whose info file names a game that starts.
    /// A download gogdl hasn't finished (its .gogdl-resume is still there) is none yet.
    static func gogGames(in base: URL) -> [GOGGame] {
        let fm = FileManager.default
        return folders(in: base).compactMap { folder -> GOGGame? in
            guard !fm.fileExists(atPath: folder.appendingPathComponent(".gogdl-resume").path) else { return nil }
            let resources = folder.appendingPathComponent("Contents/Resources", isDirectory: true)
            var infos: [(id: String, root: String, object: [String: Any], data: Data, mac: Bool)] = []
            for (place, mac) in [(folder, false), (resources, true)] {
                let files = (try? fm.contentsOfDirectory(at: place, includingPropertiesForKeys: nil)) ?? []
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.lastPathComponent.hasPrefix("goggame-") && file.pathExtension == "info" {
                    guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = text(object["gameId"]), GOGRelease.isProductID(id),
                          file.lastPathComponent == "goggame-\(id).info"
                    else { continue }
                    infos.append((id, text(object["rootGameId"]) ?? id, object, data, mac))
                }
            }
            // The game itself is its own root; add-ons name the game as theirs.
            guard let game = infos.first(where: { $0.id == $0.root }), let info = GOGGameInfo.from(json: game.data) else { return nil }
            let language = (game.object["languages"] as? [Any])?.first as? String
            return GOGGame(id: game.id, title: info.name.isEmpty ? folder.deletingPathExtension().lastPathComponent : info.name,
                           build: info.build ?? "", language: language.flatMap { isLanguageCode($0) ? $0 : nil } ?? "en-US",
                           platform: game.mac ? .mac : .windows, folder: folder.lastPathComponent,
                           dlcs: infos.filter { $0.root == game.id && $0.id != game.id }.map(\.id).sorted())
        }
    }

    private static func folders(in base: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { !$0.lastPathComponent.hasPrefix(".") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func text(_ value: Any?) -> String? {
        (value as? String) ?? (value as? NSNumber)?.stringValue
    }

    /// "de-DE", "en-US", "zh-Hans": what GOG's files name a language by – not "German".
    private static func isLanguageCode(_ text: String) -> Bool {
        text.range(of: #"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil
    }
}

/// What Nightforge has on the Mac about each store, as far as taking a drive's games over goes.
struct KnownInstalls: Equatable {
    struct Epic: Equatable {
        /// legendary holds a sign-in: it needs one to take a game over (it asks Epic for the game's manifest).
        var signedIn = true
        /// What legendary's list has installed, by app name, with each one's folder.
        var installed: [String: URL] = [:]
        /// The account's games: app name, title and the folder Epic names for it.
        var games: [EpicGame] = []
        /// Downloads in line: their folders are theirs.
        var downloading: Set<String> = []
    }

    struct GOG: Equatable {
        var installed: [String: URL] = [:]
        /// The products the account owns.
        var owned: Set<String> = []
        var downloading: Set<String> = []
    }

    /// The library folders (their steamapps) in the list of Nightforge's Windows Steam; nil when
    /// that Steam isn't set up on this Mac yet.
    var windowsSteamLibraries: [URL]?
    /// The same for Steam for Mac.
    var macSteamLibraries: [URL]?
    /// nil: the store isn't connected.
    var epic: Epic?
    var gog: GOG?
}

/// What a plugged-in drive holds that Nightforge doesn't know yet: what can be taken over now
/// without downloading it again, and what has to wait – and for what.
struct DriveFinds: Equatable {
    /// Why something on the drive isn't taken over now.
    enum Wait: Equatable {
        /// That Steam isn't set up on this Mac yet.
        case steamNotSetUp
        /// The store isn't connected (or, Epic: signed out).
        case notConnected
        /// The account connected doesn't own it – or, Epic, no game of the account's goes by that folder.
        case notOwned
    }

    struct EpicFind: Equatable {
        let appName: String
        var title: String
        var folder: URL
        /// The add-ons the account owns for it: legendary looks whether their files are there.
        var addOns: [String] = []
    }

    struct Waiting: Equatable {
        let provider: Provider
        let platform: Platform
        var name: String
        var reason: Wait
    }

    var drive: URL
    /// The library of Nightforge's Windows Steam there isn't in Steam's list: these come back with it.
    var windowsSteam: [DriveContents.SteamGame] = []
    /// The same for Steam for Mac.
    var macSteam: [DriveContents.SteamGame] = []
    var epic: [EpicFind] = []
    var gog: [DriveContents.GOGGame] = []
    var waiting: [Waiting] = []

    /// Nothing to take over now.
    var isEmpty: Bool { windowsSteam.isEmpty && macSteam.isEmpty && epic.isEmpty && gog.isEmpty }
    /// How many games would come back now.
    var count: Int { windowsSteam.count + macSteam.count + epic.count + gog.count }

    /// Sorts what's on the drive by what Nightforge knows: known already (left out), to take over now,
    /// or waiting. Pure – the same drive and the same knowledge give the same answer.
    static func look(drive: URL, contents: DriveContents, known: KnownInstalls) -> DriveFinds {
        var finds = DriveFinds(drive: drive)
        func same(_ a: URL, _ b: URL) -> Bool { path(a) == path(b) }

        // Steam: a library is in the list whole or not at all, and Steam looks at what's in it itself.
        for (games, library, libraries, platform) in [
            (contents.windowsSteam, DriveLibrary.windowsSteam(on: drive), known.windowsSteamLibraries, Platform.windows),
            (contents.macSteam, DriveLibrary.macSteam(on: drive), known.macSteamLibraries, Platform.mac),
        ] where !games.isEmpty {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            guard let libraries else {
                finds.waiting += games.map { Waiting(provider: .steam, platform: platform, name: $0.name, reason: .steamNotSetUp) }
                continue
            }
            if libraries.contains(where: { same($0, steamapps) }) { continue }
            if platform == .mac { finds.macSteam = games } else { finds.windowsSteam = games }
        }

        // Epic: a folder is a game when exactly one game of the account goes by its name (or an Epic
        // launcher's note in it names one) – and that game is nowhere yet.
        let base = DriveLibrary.epic(on: drive)
        for found in contents.epic {
            let folder = base.appendingPathComponent(found.name, isDirectory: true)
            guard let epic = known.epic, epic.signedIn else {
                finds.waiting.append(Waiting(provider: .epic, platform: .windows, name: found.name, reason: .notConnected))
                continue
            }
            if epic.installed.values.contains(where: { same($0, folder) }) { continue }
            let noted = epic.games.filter { found.appNames.contains($0.appName) }
            let named = epic.games.filter { $0.folder.lowercased() == found.name.lowercased() }
            guard let game = noted.count == 1 ? noted[0] : named.count == 1 ? named[0] : nil else {
                finds.waiting.append(Waiting(provider: .epic, platform: .windows, name: found.name, reason: .notOwned))
                continue
            }
            // On the Mac already, or its download is in line: this folder isn't the one to take.
            if epic.installed[game.appName] != nil || epic.downloading.contains(game.appName) { continue }
            finds.epic.append(EpicFind(appName: game.appName, title: game.title, folder: folder,
                                       addOns: (game.dlcs ?? []).map(\.appName)))
        }

        // GOG: its own file says which product it is.
        for found in contents.gog {
            guard let gog = known.gog else {
                finds.waiting.append(Waiting(provider: .gog, platform: found.platform, name: found.title, reason: .notConnected))
                continue
            }
            if gog.installed[found.id] != nil || gog.downloading.contains(found.id) { continue }
            guard gog.owned.contains(found.id) else {
                finds.waiting.append(Waiting(provider: .gog, platform: found.platform, name: found.title, reason: .notOwned))
                continue
            }
            finds.gog.append(found)
        }
        return finds
    }

    private static func path(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }
}
