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

    /// Whether `places` name the app's own things: its settings domain, its data folder, its caches, its
    /// game apps, or its folders in the player's Library (the bundle ID matters only there). `Places()` leads
    /// nowhere outside the app, but a test could still point one of them at the real thing – so outside the
    /// app `remove` refuses such places before it touches anything.
    static func namesTheRealApp(_ places: Places) -> Bool {
        func same(_ a: URL, _ b: URL) -> Bool { a.resolvingSymlinksInPath().standardizedFileURL == b.resolvingSymlinksInPath().standardizedFileURL }
        let realCaches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true)
        let realLibrary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return places.settingsDomain == appBundleID || (places.bundleID == appBundleID && same(places.library, realLibrary))
            || same(places.support, Engine.supportDir) || same(places.caches, realCaches) || same(places.shortcuts, GameShortcut.folder)
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
    /// caches), Steam's per-game folders (without Steam's own, "7") and the saves some games keep next to
    /// their program, in their own folder (`gameFolderSaves`). Paired with where each goes in the copy.
    /// `profileRules`: the saves the online profiles name, by app ID (they need an async look, `run` brings
    /// them); `catalog`: Steam Cloud's rules for a game, the prefix's appinfo.vdf unless a test hands in its own.
    static func saveSources(_ places: Places = Places(), profileRules: [Int: [SaveRule]] = [:],
                            catalog: ((Int) -> [SaveRule])? = nil) -> [(source: URL, name: String)] {
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
            + gameFolderSaves(places, profileRules: profileRules, catalog: catalog)
    }

    /// A Steam game in the prefix's library, from its manifest: its app ID and the folder it lies in.
    static func installedGames(_ places: Places = Places()) -> [(appID: Int, folder: URL)] {
        let steamapps = places.steam.appendingPathComponent("steamapps", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }.compactMap { file in
            guard let state = VDF.parse(contentsOf: file)?["appstate"], let appID = state["appid"]?.string.flatMap({ Int($0) }),
                  let name = state["installdir"]?.string, !name.isEmpty, !name.contains("/"), name != ".", name != ".."
            else { return nil }
            let folder = steamapps.appendingPathComponent("common/\(name)", isDirectory: true)
            return FileManager.default.fileExists(atPath: folder.path) ? (appID, folder) : nil
        }
        .sorted { $0.appID < $1.appID }
    }

    /// The saves a game keeps next to its program, in its folder in the prefix (Steam Cloud's rules with the
    /// root "gameinstall", and the profiles' saves): the files the rules name, one by one – not the game,
    /// which is gigabytes. A rule that would take the whole folder ('*' through all folders), one with `..`
    /// and a folder that leads out of the game's through a link are left out, as in `SaveTransfer`.
    static func gameFolderSaves(_ places: Places, profileRules: [Int: [SaveRule]] = [:],
                                catalog: ((Int) -> [SaveRule])? = nil) -> [(source: URL, name: String)] {
        var found: [(source: URL, name: String)] = []
        var seen = Set<String>()
        for (appID, folder) in installedGames(places) {
            let rules = (catalog?(appID) ?? SteamCatalog.saveRules(appID: appID, steamRoot: places.steam)) + (profileRules[appID] ?? [])
            for rule in rules where rule.root.lowercased() == "gameinstall" {
                let path = rule.path.replacingOccurrences(of: "\\", with: "/")
                guard !path.split(separator: "/").contains("..") else { continue }
                for relative in SaveTransfer.resolve(path, under: folder) where SaveTransfer.isSaveFolder(relative, root: rule.root, rule) {
                    let base = relative.isEmpty ? folder : folder.appendingPathComponent(relative, isDirectory: true)
                    guard relative.isEmpty || Engine.isInside(base, folder) else { continue }
                    for file in SaveTransfer.files(in: base, matching: rule.pattern, recursive: rule.recursive) {
                        let source = base.appendingPathComponent(file)
                        guard seen.insert(source.path).inserted else { continue }
                        found.append((source, "Steam games/\(folder.lastPathComponent)" + (relative.isEmpty ? "" : "/" + relative) + "/" + file))
                    }
                }
            }
        }
        return found
    }

    /// Copies the saves into a new folder of its own, Documents/Nightforge Saves/<date and time>; nil when
    /// there were none. Never into or over one that is there (an earlier removal's backup, the same day or
    /// the same minute): a second folder gets a number. Throws if anything couldn't be copied – then
    /// nothing gets deleted, and the folder begun is taken away again, so no half copy is taken for a whole one.
    static func copySaves(_ places: Places = Places(), now: Date = Date(), profileRules: [Int: [SaveRule]] = [:],
                          catalog: ((Int) -> [SaveRule])? = nil) throws -> URL? {
        let sources = saveSources(places, profileRules: profileRules, catalog: catalog)
        guard !sources.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: now)
        let parent = places.documents.appendingPathComponent("Nightforge Saves", isDirectory: true)
        let fm = FileManager.default
        var target = parent.appendingPathComponent(stamp, isDirectory: true)
        var number = 2
        while fm.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(stamp)-\(number)", isDirectory: true)
            number += 1
        }
        do {
            for (source, name) in sources {
                let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let destination = target.appendingPathComponent(name, isDirectory: isFolder)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Two sources can't share a name; if one did, the first stays (and the copy of the second fails loudly).
                try fm.copyItem(at: source, to: destination)
            }
        } catch {
            try? fm.removeItem(at: target)
            throw error
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
                       profileRules: [Int: [SaveRule]] = [:], phase: (@Sendable (Phase) -> Void)? = nil) throws -> URL? {
        if !isTheApp, namesTheRealApp(places) { throw RemovalError.notTheApp }  // before anything is touched
        phase?(.copyingSaves)
        let saves: URL?
        do {
            saves = try copySaves(places, profileRules: profileRules)
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
        // The list may be an old one (ProcessList): only a bash still running under that pid is ended.
        for process in Engine.processTable() where process.pid != getpid() && isBash(process.pid)
            && scripts.contains(where: { runsScript(process.command, $0) }) {
            kill(process.pid, SIGKILL)
        }
    }

    /// Whether `command` (as `ps` shows it) is a bash that runs `script`: the script is bash's first argument,
    /// the way Nightforge starts it. A command that only has the path in it – `less`, `tail -f`, a bash that is
    /// given the path as text – is no script. The path may hold spaces ("Application Support"), so the
    /// command is compared by its beginning, not split into words.
    static func runsScript(_ command: String, _ script: String) -> Bool {
        ["/bin/bash", "bash"].contains { shell in
            let head = shell + " " + script
            return command == head || command.hasPrefix(head + " ")
        }
    }

    private static func isBash(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 && String(cString: buffer) == "/bin/bash"
    }

    /// `pid` is a bash that began within half a minute of `file` being written.
    private static func isQuitScript(_ pid: pid_t, writtenTo file: URL) -> Bool {
        guard pid != getpid(), isBash(pid),
              let started = Engine.processStart(pid),
              let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return false }
        return abs(written.timeIntervalSince(started)) < 30
    }

    // MARK: - The whole job

    /// From the start of `run` until it quits: no quit from elsewhere meanwhile (Quit), one halfway
    /// would leave half of it behind.
    @MainActor private(set) static var isRunning = false

    /// The whole job from the app: stop Wine and Steam, remove, put Nightforge itself in the Bin
    /// and quit. Throws a `RemovalError`; after `savesNotCopied` nothing is deleted.
    @MainActor
    static func run(phase: @escaping @MainActor (Phase) -> Void = { _ in }) async throws {
        isRunning = true
        defer { isRunning = false }
        try requireApp()  // before anything is stopped
        phase(.stopping)
        await stop(polite: {
            if let wine = await Engine.installedWine() { try? await Engine.stopSteam(wine) }
        })
        // The saves the online profiles name for the games in the prefix (some keep theirs next to the program).
        var profileRules: [Int: [SaveRule]] = [:]
        for (appID, _) in await Task.detached(priority: .userInitiated, operation: { installedGames() }).value {
            if let rules = await ProfileStore.shared.profile(for: appID)?.saves, !rules.isEmpty { profileRules[appID] = rules }
        }
        let saves = try await Task.detached(priority: .userInitiated) { [profileRules] in
            try remove(profileRules: profileRules, phase: { step in Task { @MainActor in phase(step) } })
        }.value
        if let saves { NSWorkspace.shared.activateFileViewerSelecting([saves]) }
        // FileManager rather than NSWorkspace.recycle, which goes through the Finder. With its own
        // bundle in the Bin, Nightforge stayed open on "Removing …" and took no Quit, not even one
        // from outside (Mac mini and MacBook, 2.11.2026). Nothing of it is left to save, so if
        // AppKit doesn't get round to quitting, it ends anyway.
        try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        isRunning = false  // its own quit, past the Settings sheet it was started from
        Quit.now(by: "the removal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
