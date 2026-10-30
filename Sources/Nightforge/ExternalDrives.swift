import Foundation

/// A drive plugged into the Mac that games can go on: a USB stick, an external SSD.
struct ExternalDrive: Identifiable, Hashable {
    /// Its name in /Volumes ("Samsung T7"), which is also what "Connect … to Play" says.
    let name: String
    /// Where it's mounted: /Volumes/<name>.
    let url: URL
    /// statfs's name for its format: "apfs", "hfs", "exfat", "msdos", "ntfs" …
    let format: String
    let readOnly: Bool
    var free: Int64
    var total: Int64

    var id: String { url.path }

    /// Whether games can go there.
    var check: DriveCheck { DriveCheck(format: format, readOnly: readOnly) }

    /// The format as Disk Utility names it.
    var formatName: String {
        switch format {
        case "apfs": return "APFS"
        case "hfs": return "Mac OS Extended"
        case "exfat": return "exFAT"
        case "msdos": return "FAT32"
        case "ntfs": return "NTFS"
        default: return format.uppercased()
        }
    }

    /// Nightforge has put games there before: its folder is on it.
    var hasLibrary: Bool { FileManager.default.fileExists(atPath: DriveLibrary.root(on: url).path) }

    /// Drives plugged in now: mounted under /Volumes, not the Mac's own disk, not a network share
    /// and not a hidden one (disk images Nightforge mounts for itself).
    static func connected() -> [ExternalDrive] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsLocalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.compactMap { volume in
            let values = try? volume.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsInternal != true, values?.volumeIsLocal != false else { return nil }
            return at(volume)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The drive mounted at `url`; nil for the Mac's own disk, a network share, or a folder that
    /// isn't where a volume is mounted. `volumes` is /Volumes, other in tests.
    static func at(_ url: URL, volumes: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true)) -> ExternalDrive? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        let mountPoint = withUnsafeBytes(of: info.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let format = withUnsafeBytes(of: info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let flags = Int32(bitPattern: info.f_flags)
        guard URL(fileURLWithPath: mountPoint).standardizedFileURL.path == url.standardizedFileURL.path,
              flags & MNT_ROOTFS == 0, flags & MNT_LOCAL != 0,
              url.deletingLastPathComponent().standardizedFileURL.path == volumes.standardizedFileURL.path
        else { return nil }
        let block = Int64(info.f_bsize)
        return ExternalDrive(name: url.lastPathComponent, url: url, format: format.lowercased(), readOnly: flags & MNT_RDONLY != 0,
                             free: Int64(info.f_bavail) * block, total: Int64(info.f_blocks) * block)
    }

    /// Free space on whatever volume holds `folder` (or its nearest existing parent): statfs's
    /// own count, which external drives answer too.
    static func free(at folder: URL) -> Int64 {
        var info = statfs()
        guard statfs(SpaceCheck.existingFolder(for: folder).path, &info) == 0 else { return 0 }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }
}

extension Game {
    /// Installed on a drive that's unplugged: plays once it's plugged in ("Connect … to Play").
    var onUnpluggedDrive: Bool { install == .notInstalled && missingDrive != nil }

    /// Where Home and the library file it: a game on an unplugged drive stays with the installed
    /// ones – it's the player's, not a download to make again.
    var shelfState: InstallState { onUnpluggedDrive ? .installed : install }
}

/// A drive offered as a game's place – in the space sheet and in "Move to …" – and whether the game
/// fits there.
struct DriveChoice: Identifiable, Hashable {
    let drive: ExternalDrive
    /// What it takes there, with the room Steam needs besides (SpaceCheck.margin).
    let needed: Int64

    var id: String { drive.id }
    var fits: Bool { drive.free >= needed }
    /// The game can go there: room enough, and a format that holds games.
    var usable: Bool { fits && drive.check.allowed }

    /// The drives to offer for a game of `size` bytes, without the one it's on (`current`): those it
    /// can go on first, the rest after them to say why not.
    static func options(_ drives: [ExternalDrive], size: Int64, except current: URL? = nil) -> [DriveChoice] {
        let choices = drives.filter { $0.url.standardizedFileURL.path != current?.standardizedFileURL.path }
            .map { DriveChoice(drive: $0, needed: max(size, 0) + SpaceCheck.margin) }
        return choices.filter(\.usable) + choices.filter { !$0.usable }
    }
}

/// Whether games can go on a drive, from its format.
enum DriveCheck: Equatable {
    /// APFS or Mac OS Extended: like the Mac's own disk.
    case fine
    /// exFAT: no Unix permissions or links – most games run, a few may not.
    case caution
    /// FAT32 (and older FAT): no file may be over 4 GB, which most games have.
    case fat
    /// macOS can only read it (NTFS, a locked drive).
    case readOnly

    init(format: String, readOnly: Bool) {
        if readOnly {
            self = .readOnly
            return
        }
        switch format {
        case "apfs", "hfs": self = .fine
        case "msdos", "fat", "fat32", "vfat": self = .fat
        default: self = .caution  // exFAT, and anything else that can be written to
        }
    }

    var allowed: Bool { self == .fine || self == .caution }

    /// What the player reads about it; nil when there's nothing to say.
    func note(_ drive: String) -> String? {
        switch self {
        case .fine: return nil
        case .caution:
            return L10n.t("%@ is formatted as exFAT, which has no Mac permissions or links. Most games run from it; if one doesn't, move it back to your Mac.", drive)
        case .fat:
            return L10n.t("%@ is formatted as FAT32, which can't hold files over 4 GB – most games have some. Erase it as APFS in Disk Utility to put games on it.", drive)
        case .readOnly:
            return L10n.t("Your Mac can only read from %@, not write to it.", drive)
        }
    }
}

/// Nightforge's folder on a drive, "Nightforge Games": the library of Nightforge's Windows Steam
/// (its steamapps folder right in it), one for Steam for Mac and Epic's games – each store apart,
/// so no Steam finds the other's games as its own.
enum DriveLibrary {
    static let folderName = "Nightforge Games"

    static func root(on drive: URL) -> URL { drive.appendingPathComponent(folderName, isDirectory: true) }

    /// The library folder of Nightforge's Windows Steam: `steamapps/` goes in it.
    static func windowsSteam(on drive: URL) -> URL { root(on: drive) }

    /// The library folder of Steam for Mac.
    static func macSteam(on drive: URL) -> URL { root(on: drive).appendingPathComponent("Steam for Mac", isDirectory: true) }

    /// Where legendary puts Epic games (each in its own folder): "Epic Games", like on the Mac, so a
    /// running game shows the same path (`Game.windowsFolderMarker`).
    static func epic(on drive: URL) -> URL { root(on: drive).appendingPathComponent("Epic Games", isDirectory: true) }

    /// The drive a folder is on: /Volumes/<name>; nil for a folder on the Mac itself.
    static func drive(of folder: URL) -> URL? {
        let parts = folder.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes", isDirectory: true).appendingPathComponent(parts[2], isDirectory: true)
    }

    /// How Nightforge's Windows Steam writes a Mac folder: Wine shows the Mac's files on Z:, so
    /// "Z:\Volumes\T7\Nightforge Games" needs no drive letter of its own.
    static func windowsPath(of folder: URL) -> String { Legendary.windowsPath(folder.standardizedFileURL.path) }
}

/// A Steam's list of its libraries (libraryfolders.vdf). Steam keeps it twice – in config/, which
/// it reads, and in steamapps/ for other programs – and writes its own state over both when it
/// quits, so it's changed only while that Steam is stopped.
enum SteamLibraries {
    /// The list's files that are there; steamapps/ alone when there's none yet.
    static func files(steamRoot: URL) -> [URL] {
        let candidates = [steamRoot.appendingPathComponent("config/libraryfolders.vdf"),
                          steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")]
        let present = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        return present.isEmpty ? [candidates[1]] : present
    }

    /// What the files hold now, to put back if a later step fails.
    static func snapshot(steamRoot: URL) -> [URL: Data?] {
        Dictionary(uniqueKeysWithValues: files(steamRoot: steamRoot).map { ($0, try? Data(contentsOf: $0)) })
    }

    static func restore(_ snapshot: [URL: Data?]) {
        for (file, data) in snapshot {
            if let data {
                try? data.write(to: file, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// The library entries: each one's key, its path as Steam wrote it and where that is on the Mac.
    static func entries(_ nodes: [VDFNode], bottle: Bottle) -> [(key: String, path: String, folder: URL?)] {
        guard let list = nodes.first(where: { $0.key.lowercased() == "libraryfolders" }) else { return [] }
        return list.children.compactMap { entry in
            guard let path = entry["path"]?.string ?? entry.string else { return nil }
            return (entry.key, path, folder(forPath: path, bottle: bottle))
        }
    }

    /// A library's path as a Mac folder: Steam for Mac writes Mac paths, the Windows Steam drive letters.
    static func folder(forPath path: String, bottle: Bottle) -> URL? {
        path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : LibraryScanner.macPath(forWindowsPath: path, in: bottle)
    }

    private static func same(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        return a.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
            == b.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    /// Makes `folder` one of this Steam's libraries: the folder with `steamapps/common`, its
    /// `libraryfolder.vdf` (Steam's mark with the library's number) and an entry in the list, with
    /// the games already in it – a drive used with an earlier Nightforge comes back with its games.
    /// `path` is how this Steam writes the folder; `rootPath` how it writes its own folder, for a
    /// list that doesn't exist yet. Nothing changes when it's a library already.
    static func ensure(library folder: URL, path: String, steamRoot: URL, rootPath: String, bottle: Bottle) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("steamapps/common", isDirectory: true), withIntermediateDirectories: true)
        let mark = folder.appendingPathComponent("libraryfolder.vdf")
        var contentID = VDF.nodes((try? String(contentsOf: mark, encoding: .utf8)) ?? "")?.first?["contentid"]?.string ?? ""
        if contentID.isEmpty {
            contentID = String(UInt64.random(in: 1...UInt64(Int64.max)))
            let text = VDF.text([VDFNode(key: "libraryfolder", value: .object([
                VDFNode(key: "contentid", value: .string(contentID)),
                VDFNode(key: "label", value: .string("")),
            ]))])
            try text.write(to: mark, atomically: true, encoding: .utf8)
        }
        for file in files(steamRoot: steamRoot) {
            var nodes = try read(file, rootPath: rootPath, contentID: nil)
            guard !entries(nodes, bottle: bottle).contains(where: { same($0.folder, folder) }) else { continue }
            let used = Set(entries(nodes, bottle: bottle).compactMap { Int($0.key) })
            let key = String((0...).first { !used.contains($0) }!)
            let apps = installedApps(in: folder.appendingPathComponent("steamapps", isDirectory: true))
            let entry = VDFNode(key: key, value: .object([
                VDFNode(key: "path", value: .string(path)),
                VDFNode(key: "label", value: .string("")),
                VDFNode(key: "contentid", value: .string(contentID)),
                VDFNode(key: "totalsize", value: .string("0")),
                VDFNode(key: "update_clean_bytes_tally", value: .string("0")),
                VDFNode(key: "time_last_update_verified", value: .string("0")),
                VDFNode(key: "apps", value: .object(apps.map { VDFNode(key: String($0.appID), value: .string(String($0.size))) })),
            ]))
            let index = nodes.firstIndex { $0.key.lowercased() == "libraryfolders" }!
            nodes[index].children.append(entry)
            try write(nodes, to: file)
        }
    }

    /// Notes a game in the library it's in now (`folder`) and takes it out of every other one, so a
    /// library on an unplugged drive still says which games are on it (LibraryScanner.missingDrives).
    /// A list without that library stays as it is – Steam notes the game itself when it starts.
    static func record(appID: Int, size: Int64, inLibrary folder: URL, steamRoot: URL, bottle: Bottle) throws {
        for file in files(steamRoot: steamRoot) where FileManager.default.fileExists(atPath: file.path) {
            var nodes = try read(file, rootPath: nil, contentID: nil)
            guard let index = nodes.firstIndex(where: { $0.key.lowercased() == "libraryfolders" }) else { continue }
            let target = entries(nodes, bottle: bottle).first { same($0.folder, folder) }?.key
            guard target != nil else { continue }
            var list = nodes[index].children
            for place in list.indices where list[place].string == nil {
                var apps = list[place]["apps"]?.children ?? []
                apps.removeAll { $0.key == String(appID) }
                if list[place].key == target { apps.append(VDFNode(key: String(appID), value: .string(String(size)))) }
                if let slot = list[place].children.firstIndex(where: { $0.key.lowercased() == "apps" }) {
                    list[place].children[slot].children = apps
                } else if list[place].key == target {
                    list[place].children.append(VDFNode(key: "apps", value: .object(apps)))
                }
            }
            nodes[index].children = list
            try write(nodes, to: file)
        }
    }

    /// Takes an uninstalled game out of the libraries it's no longer in (their folder is there, its
    /// manifest isn't), with that Steam stopped: otherwise a drive pulled out right after still says
    /// it holds the game until Steam writes its list again. A library whose drive is unplugged keeps it.
    static func forget(appID: Int, steamRoot: URL, bottle: Bottle) throws {
        let fm = FileManager.default
        for file in files(steamRoot: steamRoot) where fm.fileExists(atPath: file.path) {
            var nodes = try read(file, rootPath: nil, contentID: nil)
            guard let index = nodes.firstIndex(where: { $0.key.lowercased() == "libraryfolders" }) else { continue }
            let gone = Set(entries(nodes, bottle: bottle).compactMap { entry -> String? in
                guard let folder = entry.folder, fm.fileExists(atPath: folder.path) else { return nil }
                let manifest = folder.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
                return fm.fileExists(atPath: manifest.path) ? nil : entry.key
            })
            var changed = false
            for place in nodes[index].children.indices where gone.contains(nodes[index].children[place].key) {
                guard let slot = nodes[index].children[place].children.firstIndex(where: { $0.key.lowercased() == "apps" }),
                      nodes[index].children[place].children[slot].children.contains(where: { $0.key == String(appID) })
                else { continue }
                nodes[index].children[place].children[slot].children.removeAll { $0.key == String(appID) }
                changed = true
            }
            if changed { try write(nodes, to: file) }
        }
    }

    /// The games installed in a library folder (`steamapps`), from their manifests.
    static func installedApps(in steamapps: URL) -> [(appID: Int, size: Int64)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }.compactMap { file in
            guard let state = VDF.parse(contentsOf: file)?["appstate"], let appID = state["appid"]?.string.flatMap({ Int($0) })
            else { return nil }
            return (appID, state["sizeondisk"]?.string.flatMap { Int64($0) } ?? 0)
        }
        .sorted { $0.appID < $1.appID }
    }

    /// The list as written; a new one holds Steam's own folder as library "0".
    private static func read(_ file: URL, rootPath: String?, contentID: String?) throws -> [VDFNode] {
        if let data = try? Data(contentsOf: file) {
            guard let nodes = VDF.nodes(String(decoding: data, as: UTF8.self)),
                  nodes.contains(where: { $0.key.lowercased() == "libraryfolders" })
            else { throw DriveError.unreadableLibraryList(file.lastPathComponent) }
            return nodes
        }
        var root: [VDFNode] = []
        if let rootPath {
            root = [VDFNode(key: "0", value: .object([
                VDFNode(key: "path", value: .string(rootPath)),
                VDFNode(key: "label", value: .string("")),
                VDFNode(key: "contentid", value: .string(contentID ?? String(UInt64.random(in: 1...UInt64(Int64.max))))),
                VDFNode(key: "totalsize", value: .string("0")),
                VDFNode(key: "apps", value: .object([])),
            ]))]
        }
        return [VDFNode(key: "libraryfolders", value: .object(root))]
    }

    private static func write(_ nodes: [VDFNode], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try VDF.text(nodes).write(to: file, atomically: true, encoding: .utf8)
    }
}

enum DriveError: LocalizedError {
    case unreadableLibraryList(String)
    case notEnoughSpace(drive: String, needed: Int64, free: Int64)
    case notAllowed(String)
    case alreadyThere(String)
    case gone(String)
    case copyDiffers(String)
    case copyFailed(String)
    case cancelled
    case steamStarted
    case busy(String)

    var errorDescription: String? {
        switch self {
        case .unreadableLibraryList(let file):
            return L10n.t("Steam's list of libraries (%@) can't be read, so it was left as it is.", file)
        case .notEnoughSpace(let drive, let needed, let free):
            return L10n.t("%@ has %@ free – %@ is needed.", drive, Format.bytes(free), Format.bytes(needed))
        case .notAllowed(let reason), .busy(let reason):
            return reason
        case .alreadyThere(let folder):
            return L10n.t("There's already a folder “%@” where it would go.", folder)
        case .gone(let folder):
            return L10n.t("The game's folder “%@” isn't there.", folder)
        case .copyDiffers(let file):
            return L10n.t("The copy doesn't match the original (%@).", file)
        case .copyFailed(let reason):
            return reason
        case .cancelled:
            return L10n.t("Cancelled.")
        case .steamStarted:
            return L10n.t("Steam started again meanwhile.")
        }
    }
}
