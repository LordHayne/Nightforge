import AppKit

/// "Remove Nightforge completely": the engine, the Windows environment with its games (Steam's,
/// Epic's, GOG's) and GOG's Mac versions, the caches and the settings go; saves that live only on
/// this Mac are copied to Documents first. Steam for Mac with its Mac games, CrossOver or Whisky
/// bottles and the stores' clouds stay untouched.
enum CompleteRemoval {
    /// Where Nightforge keeps things, so a test can point it at a folder of its own.
    struct Places {
        var support = Engine.supportDir
        var caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true)
        var userCache = ShaderCaches.darwinUserCache
        var library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        var shortcuts = GameShortcut.folder
        var documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var bundleID = Bundle.main.bundleIdentifier ?? "io.github.lordhayne.nightforge"
        /// Where the settings live (the app's UserDefaults domain).
        var settingsDomain = Bundle.main.bundleIdentifier ?? "io.github.lordhayne.nightforge"

        var prefix: URL { support.appendingPathComponent("Prefix", isDirectory: true) }
        var steam: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true) }
    }

    /// What goes, the biggest first. Only what's there.
    static func targets(_ places: Places = Places()) -> [URL] {
        var targets = [places.support, places.caches, places.shortcuts,
                       places.library.appendingPathComponent("HTTPStorages/\(places.bundleID)", isDirectory: true),
                       places.library.appendingPathComponent("Saved Application State/\(places.bundleID).savedState", isDirectory: true)]
        if let userCache = places.userCache {
            // Nightforge's own processes: everything they cached. Wine's loaders: only the shaders.
            targets += [places.bundleID, places.bundleID + ".game"].map { userCache.appendingPathComponent($0, isDirectory: true) }
            targets += ShaderCaches.bundleIDs.filter { !$0.hasPrefix(places.bundleID) }.flatMap { id in
                ShaderCaches.metalFolders.map { userCache.appendingPathComponent("\(id)/\($0)", isDirectory: true) }
            }
        }
        return targets.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Saves

    /// Folders in a Windows user profile that hold caches, not saves.
    private static let notSaves: Set<String> = ["temp", "steam", "microsoft", "cef", "crashdumps", "d3dscache", "nvidia", "amd",
                                                "unrealengine"]

    /// Where games keep saves inside the Windows environment: the Windows users' folders (without
    /// caches) and Steam's per-game folders (without Steam's own, "7"). Paired with where each goes
    /// in the copy.
    static func saveSources(_ places: Places = Places()) -> [(source: URL, name: String)] {
        let fm = FileManager.default
        func folders(in url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        var sources: [(URL, String)] = []
        for user in folders(in: places.prefix.appendingPathComponent("drive_c/users", isDirectory: true)) where user.lastPathComponent != "Public" {
            for name in ["Documents", "Saved Games", "AppData/Roaming", "AppData/LocalLow"] {
                sources.append((user.appendingPathComponent(name, isDirectory: true), "\(user.lastPathComponent)/\(name)"))
            }
            for folder in folders(in: user.appendingPathComponent("AppData/Local", isDirectory: true))
            where !notSaves.contains(folder.lastPathComponent.lowercased()) && !folder.lastPathComponent.lowercased().contains("cache") {
                sources.append((folder, "\(user.lastPathComponent)/AppData/Local/\(folder.lastPathComponent)"))
            }
        }
        // Saves a switch between a game's versions replaced, and older backups of saves.
        for backup in folders(in: places.support.appendingPathComponent("Backups", isDirectory: true))
        where backup.lastPathComponent.lowercased().contains("saves") {
            sources.append((backup, "Backups/\(backup.lastPathComponent)"))
        }
        for account in folders(in: places.steam.appendingPathComponent("userdata", isDirectory: true)) {
            for app in folders(in: account) where Int(app.lastPathComponent) != nil && app.lastPathComponent != "7" {
                sources.append((app, "Steam userdata/\(account.lastPathComponent)/\(app.lastPathComponent)"))
            }
        }
        return sources.filter { LibraryScanner.folderSize($0.0) > 0 }
    }

    /// Copies the saves into Documents/Nightforge Saves/<date>; nil when there were none.
    /// Throws if anything couldn't be copied – then nothing gets deleted.
    static func copySaves(_ places: Places = Places(), now: Date = Date()) throws -> URL? {
        let sources = saveSources(places)
        guard !sources.isEmpty else { return nil }
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let target = places.documents.appendingPathComponent("Nightforge Saves/\(stamp)", isDirectory: true)
        let fm = FileManager.default
        for (source, name) in sources {
            let destination = target.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }
        return target
    }

    // MARK: - What the question says

    /// The games that go with Nightforge's folder and where they stay: "2 games (30 GB) are
    /// deleted – they stay in your library on Steam and GOG …". nil when there are none.
    static func gamesNote(count: Int, size: Int64, stores: Set<Provider>) -> String? {
        guard count > 0 else { return nil }
        let names = Provider.names(Provider.allCases.filter(stores.contains))
        return count == 1
            ? L10n.t("1 game (%@) is deleted – it stays in your library on %@ and can be downloaded again.", Format.bytes(size), names)
            : L10n.t("%ld games (%@) are deleted – they stay in your library on %@ and can be downloaded again.", count, Format.bytes(size), names)
    }

    // MARK: - Removing

    /// Saves first, then everything Nightforge put on the Mac and its settings. Wine must be
    /// stopped before (`run` does that). Returns where the saves went.
    @discardableResult
    static func remove(_ places: Places = Places(), defaults: UserDefaults = .standard) throws -> URL? {
        let saves = try copySaves(places)
        for target in targets(places) {
            try FileManager.default.removeItem(at: target)
        }
        defaults.removePersistentDomain(forName: places.settingsDomain)
        return saves
    }

    /// The whole job from the app: stop Wine and Steam, remove, put Nightforge itself in the Bin
    /// and quit. Throws (with nothing deleted) if the saves couldn't be copied.
    @MainActor
    static func run() async throws {
        if let wine = await Engine.installedWine() {
            try? await Engine.stopSteam(wine)
            await Engine.offMain { Engine.stopAll(wine) }
        }
        let saves = try await Task.detached(priority: .userInitiated) { try remove() }.value
        if let saves { NSWorkspace.shared.activateFileViewerSelecting([saves]) }
        _ = try? await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
        NSApp.terminate(nil)
    }
}
