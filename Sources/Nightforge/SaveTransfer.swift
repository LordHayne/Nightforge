import Foundation

/// Takes a game's saves along when it changes between its Windows and Mac versions. Steam Cloud
/// does that too, but only when the Steam that played last could upload them – one Steam sign-in
/// per account makes that miss now and then, and then the other version starts empty. So before
/// a version starts for the first time after a switch, every save folder it has (the folders
/// Steam Cloud uses, SteamCatalog.saveRules) that holds no saves yet gets the other version's.
/// Where both have saves and the other version's are newer, the player chooses which to continue
/// with (`newerElsewhere`, `takeNewer`); the ones replaced are backed up first. Nothing is ever
/// overwritten without asking.
enum SaveTransfer {
    /// Where the game's two versions keep their files: the Wine prefix and both install folders.
    struct Places {
        var prefix: URL = Engine.prefix
        var windowsUser = NSUserName()
        var windowsInstall: URL?
        var macHome = FileManager.default.homeDirectoryForCurrentUser
        var macInstall: URL?
    }

    private static func key(_ appID: Int) -> String { "saves.lastVersion.\(appID)" }

    /// Before `platform` starts: copies saves over if the game last ran as the other version (or
    /// Nightforge hasn't seen it run yet). Returns how many files were copied.
    @discardableResult
    static func beforeStart(appID: Int, platform: Platform, rules: [SaveRule], places: Places,
                            defaults: UserDefaults = .standard) -> Int {
        defer { defaults.set(platform.rawValue, forKey: key(appID)) }
        guard defaults.string(forKey: key(appID)) != platform.rawValue else { return 0 }
        return carryOver(to: platform, rules: rules, places: places)
    }

    /// A start after a switch, or the first Nightforge sees.
    static func isSwitch(appID: Int, platform: Platform, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key(appID)) != platform.rawValue
    }

    /// One save folder of the version played before (`source`) and the same of the one starting.
    struct Pair {
        let source: URL
        let target: URL
        let pattern: String
        let recursive: Bool
        /// Where it goes in a backup, e.g. "WinAppDataRoaming/Hades".
        let name: String

        var sourceSaves: [String] { SaveTransfer.files(in: source, matching: pattern, recursive: recursive) }
        var targetSaves: [String] { SaveTransfer.files(in: target, matching: pattern, recursive: recursive) }
    }

    /// Every save folder the other version has, paired with this version's.
    static func pairs(to platform: Platform, rules: [SaveRule], places: Places) -> [Pair] {
        var pairs: [Pair] = []
        for rule in rules {
            // Rules come from Steam's catalog and the online profiles: nothing may climb out of a save folder.
            guard ![rule.path, rule.macAddPath].contains(where: { $0.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") }),
                  let windows = windowsRoot(rule.root, places), let macRootName = rule.macRoot,
                  let mac = macRoot(macRootName, places)
            else { continue }
            let (from, to) = platform == .mac
                ? (windows, mac.appendingPathComponent(rule.macAddPath))
                : (mac.appendingPathComponent(rule.macAddPath), windows)
            for folder in resolve(rule.path, under: from)
            where isSaveFolder(folder, root: rule.root, rule) && isSaveFolder(rule.macAddPath + "/" + folder, root: macRootName, rule) {
                pairs.append(Pair(source: from.appendingPathComponent(folder, isDirectory: true),
                                  target: to.appendingPathComponent(folder, isDirectory: true),
                                  pattern: rule.pattern, recursive: rule.recursive,
                                  name: rule.root + (folder.isEmpty ? "" : "/" + folder)))
            }
        }
        return pairs
    }

    /// A save folder a rule may name, on one side (`relative` to `root`): `takeNewer` empties it of
    /// what the other side lacks. Never a root itself – Application Support and Caches hold every app's
    /// files, a Windows root every program's – but the game's own folder, and that not as a whole
    /// (all files through all folders).
    static func isSaveFolder(_ relative: String, root: String, _ rule: SaveRule) -> Bool {
        let parts = relative.split(whereSeparator: { $0 == "/" || $0 == "\\" }).filter { $0 != "." }
        guard !parts.contains("..") else { return false }
        guard parts.isEmpty else { return true }
        return root.lowercased() == "gameinstall" && !(rule.recursive && ["*", "*.*"].contains(rule.pattern))
    }

    /// Fills each empty save folder of `platform` from the other version's.
    static func carryOver(to platform: Platform, rules: [SaveRule], places: Places) -> Int {
        var copied = 0
        for pair in pairs(to: platform, rules: rules, places: places) {
            let saves = pair.sourceSaves
            guard !saves.isEmpty, pair.targetSaves.isEmpty else { continue }
            for relative in saves {
                let destination = pair.target.appendingPathComponent(relative)
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? FileManager.default.copyItem(at: pair.source.appendingPathComponent(relative), to: destination)) != nil {
                    copied += 1
                }
            }
        }
        return copied
    }

    // MARK: - Both versions have saves

    /// The newest save on each side where the version played before has newer ones.
    struct Newer: Equatable {
        let theirs: Date
        let ours: Date
    }

    /// Folders both versions have filled, the other one with newer saves – the ones `carryOver`
    /// leaves alone. The same files on both sides don't count.
    static func newerPairs(to platform: Platform, rules: [SaveRule], places: Places) -> [(pair: Pair, newer: Newer)] {
        pairs(to: platform, rules: rules, places: places).compactMap { pair in
            let theirs = pair.sourceSaves, ours = pair.targetSaves
            guard !theirs.isEmpty, !ours.isEmpty, !same(theirs, in: pair.source, as: ours, in: pair.target),
                  let theirsNewest = newest(theirs, in: pair.source), let oursNewest = newest(ours, in: pair.target),
                  theirsNewest.timeIntervalSince(oursNewest) > 2
            else { return nil }
            return (pair, Newer(theirs: theirsNewest, ours: oursNewest))
        }
    }

    /// Across all folders: the newest save of each side, nil when the starting version is up to date.
    static func newerElsewhere(to platform: Platform, rules: [SaveRule], places: Places) -> Newer? {
        let found = newerPairs(to: platform, rules: rules, places: places).map(\.newer)
        guard let theirs = found.map(\.theirs).max(), let ours = found.map(\.ours).max() else { return nil }
        return Newer(theirs: theirs, ours: ours)
    }

    /// Continues with the other version's newer saves: this version's go to `backup` first, then
    /// each such folder gets exactly the other version's saves. Those are copied into a folder beside
    /// it first and only then renamed into place, each over its old one at once, so a copy that fails
    /// (a save that can't be read, a full disk) leaves this version's saves as they were. Throws
    /// before changing a folder whose backup or copy failed; `PartlyTaken` if it stopped while
    /// changing one. Returns how many files were copied.
    @discardableResult
    static func takeNewer(to platform: Platform, rules: [SaveRule], places: Places, backup: URL) throws -> Int {
        let fm = FileManager.default
        var copied = 0
        for (pair, _) in newerPairs(to: platform, rules: rules, places: places) {
            let ours = pair.targetSaves
            for relative in ours {
                let destination = backup.appendingPathComponent(pair.name, isDirectory: true).appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: pair.target.appendingPathComponent(relative), to: destination)
            }
            let theirs = pair.sourceSaves
            // Beside the folder, on its volume: a rename there is one step.
            let staging = pair.target.deletingLastPathComponent()
                .appendingPathComponent(".\(pair.target.lastPathComponent).nightforge-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            for relative in theirs {
                let destination = staging.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: pair.source.appendingPathComponent(relative), to: destination)
            }
            do {
                for relative in theirs {
                    let destination = pair.target.appendingPathComponent(relative)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard rename(staging.appendingPathComponent(relative).path, destination.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    copied += 1
                }
                for relative in Set(ours).subtracting(theirs) {
                    try fm.removeItem(at: pair.target.appendingPathComponent(relative))
                }
            } catch {
                throw PartlyTaken(backup: backup, reason: error.localizedDescription)
            }
        }
        return copied
    }

    /// takeNewer stopped while it changed a save folder (a rename, a removal): the saves from before
    /// are in `backup`.
    struct PartlyTaken: LocalizedError {
        let backup: URL
        let reason: String
        var errorDescription: String? { L10n.t("%@; the saves from before are in %@", reason, backup.path) }
    }

    /// Where a switch's replaced saves are kept: Nightforge's Backups folder, by game and time.
    static func backupFolder(game: String, platform: Platform, now: Date = Date(), support: URL = Engine.supportDir) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let safe = game.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        return support.appendingPathComponent("Backups/\(safe.isEmpty ? "Game" : safe)-saves-\(formatter.string(from: now))/" +
                                              (platform == .mac ? "Mac version" : "Windows version"), isDirectory: true)
    }

    private static func newest(_ files: [String], in folder: URL) -> Date? {
        files.compactMap { try? folder.appendingPathComponent($0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    private static func same(_ a: [String], in folderA: URL, as b: [String], in folderB: URL) -> Bool {
        guard Set(a) == Set(b) else { return false }
        return a.allSatisfy { FileManager.default.contentsEqual(atPath: folderA.appendingPathComponent($0).path,
                                                               andPath: folderB.appendingPathComponent($0).path) }
    }

    /// A Windows root inside the Wine prefix. Folders that still lead out of it (a user folder
    /// linked to the Mac's own) are left alone: macOS would ask for access to them. Profiles'
    /// settings files use the same roots (Engine.applyFileEdits, Engine.applyIniSettings).
    static func windowsRoot(_ root: String, _ places: Places) -> URL? {
        let user = places.prefix.appendingPathComponent("drive_c/users/\(places.windowsUser)", isDirectory: true)
        let folder: URL
        switch root.lowercased() {
        case "gameinstall": return places.windowsInstall
        case "winappdataroaming": folder = user.appendingPathComponent("AppData/Roaming", isDirectory: true)
        case "winappdatalocal": folder = user.appendingPathComponent("AppData/Local", isDirectory: true)
        case "winappdatalocallow": folder = user.appendingPathComponent("AppData/LocalLow", isDirectory: true)
        case "winmydocuments": folder = user.appendingPathComponent("Documents", isDirectory: true)
        case "winsavedgames": folder = user.appendingPathComponent("Saved Games", isDirectory: true)
        default: return nil
        }
        // Inside means in the prefix's folder: "Prefix-old" beside it starts with the same letters.
        let inside = places.prefix.resolvingSymlinksInPath().path, path = folder.resolvingSymlinksInPath().path
        return path == inside || path.hasPrefix(inside + "/") ? folder : nil
    }

    /// A macOS root. Documents, Desktop and Downloads are out: reading them makes macOS ask.
    private static func macRoot(_ root: String, _ places: Places) -> URL? {
        switch root.lowercased() {
        case "gameinstall": return places.macInstall
        case "macappsupport": return places.macHome.appendingPathComponent("Library/Application Support", isDirectory: true)
        case "maccaches": return places.macHome.appendingPathComponent("Library/Caches", isDirectory: true)
        default: return nil
        }
    }

    /// The concrete folders a rule's path names under `root`. Placeholders like {64BitSteamID}
    /// match whatever folder is there ("st_76561198118309630"), so no account ID is needed.
    static func resolve(_ path: String, under root: URL) -> [String] {
        var found = [""]
        for part in path.split(separator: "/").map(String.init) where !part.isEmpty {
            guard part.contains("{") else {
                found = found.map { $0.isEmpty ? part : $0 + "/" + part }
                continue
            }
            let pattern = part.replacingOccurrences(of: #"\{[^}]*\}"#, with: "*", options: .regularExpression)
            found = found.flatMap { parent -> [String] in
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(parent).path)) ?? []
                return entries.filter { fnmatch(pattern, $0, 0) == 0 }.map { parent.isEmpty ? $0 : parent + "/" + $0 }
            }
        }
        return found
    }

    /// Files under `folder` matching `pattern`, as paths relative to it.
    static func files(in folder: URL, matching pattern: String, recursive: Bool) -> [String] {
        let fm = FileManager.default
        guard let entries = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                          options: recursive ? [] : [.skipsSubdirectoryDescendants])
        else { return [] }
        let base = folder.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in entries {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  fnmatch(pattern, url.lastPathComponent, 0) == 0,
                  url.lastPathComponent != "steam_autocloud.vdf"
            else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(base) { result.append(String(path.dropFirst(base.count))) }
        }
        return result
    }
}
