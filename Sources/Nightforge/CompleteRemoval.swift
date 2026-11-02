import AppKit

/// "Remove Nightforge completely": the engine, the Windows environment with its games (Steam's,
/// Epic's, GOG's) and GOG's Mac versions, the caches and the settings go; saves that live only on
/// this Mac are copied to Documents first. Steam for Mac with its Mac games, CrossOver or Whisky
/// bottles and the stores' clouds stay untouched.
enum CompleteRemoval {
    /// The app's own identity (Resources/Info.plist).
    static let appBundleID = "io.github.lordhayne.nightforge"

    /// Whether this program is Nightforge. A test program has no bundle, and nothing of what follows may
    /// lead it to the player's things.
    static var isTheApp: Bool { Bundle.main.bundleIdentifier == appBundleID }

    /// Throws unless this is Nightforge: the whole job (`run`) is only ever the app's.
    static func requireApp() throws {
        guard isTheApp else { throw RemovalError.notTheApp }
    }

    /// Where Nightforge keeps things, so a test can point it at a folder of its own. Outside the app the
    /// places lead nowhere (a folder under the temporary folder that doesn't exist) and the settings
    /// are a domain no one has: a test that forgets to point one of them elsewhere removes nothing real –
    /// not the Windows environment, not the player's settings.
    struct Places {
        private static let nowhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightforge-not-the-app", isDirectory: true)
        private static func real(_ place: @autoclosure () -> URL, nowhere sub: String) -> URL {
            CompleteRemoval.isTheApp ? place() : nowhere.appendingPathComponent(sub, isDirectory: true)
        }

        var support = Places.real(Engine.supportDir, nowhere: "Application Support/Nightforge")
        var caches = Places.real(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true), nowhere: "Caches/Nightforge")
        var userCache = CompleteRemoval.isTheApp ? ShaderCaches.darwinUserCache : nil
        var library = Places.real(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true),
                                  nowhere: "Library")
        var shortcuts = Places.real(GameShortcut.folder, nowhere: "Applications/Nightforge Games")
        var documents = Places.real(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], nowhere: "Documents")
        var bundleID = CompleteRemoval.isTheApp ? CompleteRemoval.appBundleID : "nightforge.not-the-app"
        /// Where the settings live (the app's UserDefaults domain).
        var settingsDomain = CompleteRemoval.isTheApp ? CompleteRemoval.appBundleID : "nightforge.not-the-app"

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

    /// Where the job is, for the line under the button.
    enum Phase: Sendable {
        case stopping, copyingSaves, deleting
    }

    /// Why the job stopped. The two differ in what is left: after `savesNotCopied` nothing has been
    /// deleted; after `notDeleted` the rest has.
    enum RemovalError: LocalizedError {
        case savesNotCopied(String)
        case notDeleted([String])
        /// Asked outside the app (a test program): nothing is touched.
        case notTheApp

        var errorDescription: String? {
            switch self {
            case .notTheApp:
                return L10n.t("Nightforge can only remove itself when it runs as the app.")
            case .savesNotCopied(let reason):
                return L10n.t("The saves couldn't be copied to Documents (%@), so everything is still there.", reason)
            case .notDeleted(let names):
                let shown = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " …" : "")
                return L10n.t("Not everything could be deleted (%@). The rest is still there – try again, or delete it in Finder.", shown)
            }
        }
    }

    /// Saves first, then everything Nightforge put on the Mac and its settings. Wine must be
    /// stopped before (`run` does that). Returns where the saves went. A target that can't be deleted
    /// doesn't stop the others; the settings stay until all are gone, so a second try finds the rest.
    @discardableResult
    static func remove(_ places: Places = Places(), defaults: UserDefaults = .standard,
                       phase: (@Sendable (Phase) -> Void)? = nil) throws -> URL? {
        phase?(.copyingSaves)
        let saves: URL?
        do {
            saves = try copySaves(places)
        } catch {
            throw RemovalError.savesNotCopied(error.localizedDescription)
        }
        phase?(.deleting)
        var left: [String] = []
        for target in targets(places) where !delete(target) {
            left.append(target.lastPathComponent)
        }
        guard left.isEmpty else { throw RemovalError.notDeleted(left) }
        defaults.removePersistentDomain(forName: places.settingsDomain)
        return saves
    }

    /// Deletes `url`; a folder that has no write permission (some installers leave them) is made
    /// writable and tried once more. False if it is still there.
    private static func delete(_ url: URL) -> Bool {
        let fm = FileManager.default
        if (try? fm.removeItem(at: url)) != nil { return true }
        if let items = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            for case let item as URL in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
                }
            }
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? fm.removeItem(at: url)
        return !fm.fileExists(atPath: url.path)
    }

    // MARK: - Stopping

    /// Ends what runs from Nightforge's folder – Wine, Steam, the stores' downloaders, a quit script
    /// still waiting – so that nothing writes into it, or holds it, while it is deleted. Not by
    /// asking Wine (no `wineserver -k`, no Steam shutdown, which wait on the programs they ask and
    /// on Steam's update): SIGKILL, from the list of programs whose file lies in the folder. The
    /// polite way, `polite`, goes first for as long as `politeFor` allows – Steam keeps its state
    /// when it ends by itself; whatever it hasn't done by then is not waited for.
    static func stop(_ places: Places = Places(), politeFor seconds: TimeInterval = 20,
                     scriptsByCommandLine: Bool = true, polite: (@Sendable () async -> Void)?) async {
        if let polite { _ = await withDeadline(seconds, polite) }
        await Task.detached(priority: .userInitiated) {
            endProcesses(under: places.support, scriptsByCommandLine: scriptsByCommandLine)
        }.value
    }

    /// The quit script first (it would open Nightforge again once a game ended), then every program
    /// started from `support`, again until none is left.
    static func endProcesses(under support: URL, scriptsByCommandLine: Bool = true) {
        endScripts(under: support, byCommandLine: scriptsByCommandLine)
        for _ in 0..<5 {
            let pids = processes(under: support)
            if pids.isEmpty { return }
            for pid in pids { kill(pid, SIGKILL) }
            usleep(200_000)
        }
    }

    /// Programs run from a file inside `folder` (what the kernel says, not their command line).
    static func processes(under folder: URL) -> [pid_t] {
        let root = Engine.realPath(folder)
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        var found: [pid_t] = []
        for pid in pids.prefix(count) where pid > 1 && pid != getpid() {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = String(cString: buffer)
            if path == root || path.hasPrefix(root + "/") { found.append(pid) }
        }
        return found
    }

    /// The quit script of this folder (`Engine.steamShutdownScript`). It writes its process into
    /// `steam-shutdown.pid` beside itself, which is where it is looked for – not through `ps`, which
    /// has been seen not answering for good while every process is listed (2.11.2026), and which a
    /// removal must not depend on. The pid counts only if it is a bash that started when the file was
    /// written (the number may have gone to another program since). A script of a Nightforge from
    /// before the file existed is found by its command line (the whole path of the script, so no
    /// other script is hit) unless `byCommandLine` is off.
    static func endScripts(under support: URL, byCommandLine: Bool = true) {
        let file = support.appendingPathComponent("steam-shutdown.pid")
        defer { try? FileManager.default.removeItem(at: file) }
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            if let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), isQuitScript(pid, writtenTo: file) {
                kill(pid, SIGKILL)
            }
            return
        }
        guard byCommandLine else { return }
        let scripts = Set([support.path, Engine.realPath(support)].map { $0 + "/steam-shutdown.sh" })
        for process in Engine.processTable() where process.pid != getpid()
            && scripts.contains(where: { process.command.contains($0) }) {
            kill(process.pid, SIGKILL)
        }
    }

    /// `pid` is a bash that began within half a minute of `file` being written.
    private static func isQuitScript(_ pid: pid_t, writtenTo file: URL) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0, String(cString: buffer) == "/bin/bash",
              let started = Engine.processStart(pid),
              let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return false }
        return abs(written.timeIntervalSince(started)) < 30
    }

    // MARK: - The whole job

    /// The whole job from the app: stop Wine and Steam, remove, put Nightforge itself in the Bin
    /// and quit. Throws a `RemovalError`; after `savesNotCopied` nothing is deleted.
    @MainActor
    static func run(phase: @escaping @MainActor (Phase) -> Void = { _ in }) async throws {
        try requireApp()  // before anything is stopped
        phase(.stopping)
        await stop(polite: {
            if let wine = await Engine.installedWine() { try? await Engine.stopSteam(wine) }
        })
        let saves = try await Task.detached(priority: .userInitiated) {
            try remove(phase: { step in Task { @MainActor in phase(step) } })
        }.value
        if let saves { NSWorkspace.shared.activateFileViewerSelecting([saves]) }
        // FileManager rather than NSWorkspace.recycle, which goes through the Finder. With its own
        // bundle in the Bin, Nightforge stayed open on "Removing …" and took no Quit, not even one
        // from outside (Mac mini and MacBook, 2.11.2026). Nothing of it is left to save, so if
        // AppKit doesn't get round to quitting, it ends anyway.
        try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
