import AppKit
import Foundation

/// Valve's Steam for Mac, which Nightforge sets up and runs in the background for the games whose
/// native Mac version it uses (VersionChoice): the Windows Steam under Wine can't download macOS
/// builds. Like the Wine one, it is signed in to only in its own window – Nightforge never sees
/// the login.
enum MacSteam {
    static let bundleID = "com.valvesoftware.steam"
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/steam.dmg")!
    /// Valve's Developer ID: the Steam.app from the download has to be signed with it.
    private static let codeRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "MXGJJ98X76""#

    /// Steam for Mac's own folder: the client it downloads on first start, the library and the logs.
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steam", isDirectory: true)
    }

    static var steamapps: URL { root.appendingPathComponent("steamapps", isDirectory: true) }

    static var bottle: Bottle { Bottle(name: "Steam for Mac", url: root) }

    /// A first-start test with a home of its own (HOME and CFFIXED_USER_HOME set to an empty
    /// folder, e.g. build/fh). Valve's Steam for Mac can't be kept in there – it starts itself again
    /// through Launch Services, with the real home, the player's own Steam and sign-in – so a test
    /// home never runs it: a stand-in takes its place (TestSteam).
    static let isTestHome: Bool = {
        guard let entry = getpwuid(getuid()), let real = entry.pointee.pw_dir else { return false }
        let path = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        return path(NSHomeDirectory()) != path(String(cString: real))
    }()

    /// Steam.app – in Applications, where Valve's installer and Nightforge put it, or wherever
    /// the player moved it (but not the client inside Steam's own folder). A test home has only the
    /// stand-in, never Valve's – not even one copied into it.
    static var app: URL? {
        if isTestHome { return TestSteam.isStandIn(TestSteam.app) ? TestSteam.app : nil }
        let fm = FileManager.default
        let candidates = ["/Applications/Steam.app", NSHomeDirectory() + "/Applications/Steam.app"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let found = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }) {
            return found
        }
        guard let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              !registered.path.hasPrefix(root.path), !registered.path.hasPrefix("/Volumes/")
        else { return nil }
        return registered
    }

    static var isInstalled: Bool { app != nil }

    /// Someone has signed in to Steam for Mac on this Mac.
    static var hasSignedIn: Bool {
        let users = VDF.parse(contentsOf: root.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        return !(users ?? [:]).isEmpty
    }

    /// The account Steam for Mac remembers, by its SteamID – the same as the Windows Steam's, or
    /// the player uses it with another one (then Nightforge leaves it alone).
    static var account: String? { SteamLogin.rememberedAccount(steamRoot: root) }

    /// Its sign-in window waits, logged since `since`: its first start, or a remembered sign-in
    /// that has run out.
    static func waitingForCredentials(since: Date) -> Bool {
        SteamLogin.waitingForCredentials(steamRoot: root, since: since)
    }

    /// Games can go through it: installed, and signed in once – or right now: Steam writes its
    /// account list a few seconds after the sign-in.
    static var isReady: Bool { isInstalled && (hasSignedIn || signedIn) }

    /// The Steam running now has signed in.
    static var signedIn: Bool { Engine.signedIn(steamRoot: root) }

    /// Started up far enough to take steam:// commands.
    static var startupFinished: Bool { Engine.startupFinished(steamRoot: root) }

    /// Signed out because the Wine Steam signed in with the same account (Engine.sessionReplaced).
    static var sessionReplaced: Bool { Engine.sessionReplaced(steamRoot: root) }

    /// In a test home none: the player's Steam for Mac isn't the test's, and the stand-in is no app
    /// macOS lists (TestSteam).
    static var running: [NSRunningApplication] {
        isTestHome ? [] : NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    /// The Steam client's process. NSRunningApplication doesn't always say (its pid can read -1),
    /// so it's looked up by its program: Steam.AppBundle/…/MacOS/steam_osx in Steam's folder.
    static var clientPID: pid_t? {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let client = root.appendingPathComponent("Steam.AppBundle").resolvingSymlinksInPath().path
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = String(cString: buffer)
            if path.hasPrefix(client), path.hasSuffix("/steam_osx") { return pid }
        }
        return nil
    }

    static var isRunning: Bool { isTestHome ? TestSteam.isRunning : !running.isEmpty }

    /// Steam's own windows: the client (and Steam.app handing over to it), not the in-game overlay
    /// (gameoverlayui), which shares the bundle ID and has to stay as it is.
    private static var clientApps: [NSRunningApplication] {
        running.filter { $0.executableURL?.lastPathComponent == "steam_osx" }
    }

    /// Nightforge started the Steam that runs now, so it ends it again when it quits
    /// (Engine.scheduleSteamShutdown). A Steam the player started stays.
    static var startedByNightforge: Bool {
        get { UserDefaults.standard.bool(forKey: "macSteamStartedByNightforge") }
        set { UserDefaults.standard.set(newValue, forKey: "macSteamStartedByNightforge") }
    }

    // MARK: - Setup

    /// Where Nightforge put Steam.app when it installed it into a Mac that had no Steam for Mac at
    /// all – nothing of the player's in it, so the first start may take it back (removeFreshInstall).
    private static let freshInstallKey = "macSteamFreshInstall"

    /// Downloads Valve's installer (a few MB), checks it's signed by Valve and puts Steam.app into
    /// Applications – the player's own when the shared one isn't writable. Steam fetches the rest
    /// of itself on its first start. A test home gets the stand-in instead (TestSteam).
    static func install() async throws {
        guard !isInstalled else { return }
        let fm = FileManager.default
        let untouched = !fm.fileExists(atPath: root.path)
        if isTestHome {
            try TestSteam.install()
            if untouched { UserDefaults.standard.set(TestSteam.app.path, forKey: freshInstallKey) }
            return
        }
        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-steam-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let image = work.appendingPathComponent("steam.dmg")
        do {
            let (download, response) = try await URLSession.shared.download(from: installerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MacSteamError.downloadFailed }
            try fm.moveItem(at: download, to: image)
        } catch {
            throw MacSteamError.downloadFailed
        }

        let volume = work.appendingPathComponent("volume", isDirectory: true)
        try fm.createDirectory(at: volume, withIntermediateDirectories: true)
        let installed = try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let fm = FileManager.default
            guard run("/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", volume.path, image.path) == 0
            else { throw MacSteamError.installFailed }
            defer { run("/usr/bin/hdiutil", "detach", volume.path, "-force") }
            let source = volume.appendingPathComponent("Steam.app", isDirectory: true)
            guard run("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R=" + codeRequirement, source.path) == 0
            else { throw MacSteamError.notFromValve }
            let shared = URL(fileURLWithPath: "/Applications", isDirectory: true)
            let own = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Applications", isDirectory: true)
            let folder = fm.isWritableFile(atPath: shared.path) ? shared : own
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("Steam.app", isDirectory: true)
            guard run("/usr/bin/ditto", source.path, target.path) == 0
            else { throw MacSteamError.installFailed }
            return target
        }.value
        if untouched { UserDefaults.standard.set(installed.path, forKey: freshInstallKey) }
    }

    /// Takes back a Steam for Mac that Nightforge installed in the first start for an account with
    /// no Mac version (it takes 1.2 GB once it has updated itself): only the one it put on a Mac
    /// without any, while nobody has signed in to it and no game is in it. A later Mac version sets
    /// it up again (MacSteamSetup).
    static func removeFreshInstall() async {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: freshInstallKey) else { return }
        let fm = FileManager.default
        let games = (try? fm.contentsOfDirectory(atPath: steamapps.appendingPathComponent("common").path)) ?? []
        guard !hasSignedIn, games.filter({ !$0.hasPrefix(".") }).isEmpty, app?.path == path else { return }
        if isRunning { await quit() }
        guard !isRunning else { return }
        try? fm.removeItem(at: URL(fileURLWithPath: path, isDirectory: true))
        try? fm.removeItem(at: root)
        defaults.removeObject(forKey: freshInstallKey)
        startedByNightforge = false
    }

    /// Keeps the record of a fresh install only while it is one: once someone signs in, it's theirs.
    static func keepFreshInstall() {
        UserDefaults.standard.removeObject(forKey: freshInstallKey)
    }

    // MARK: - The first start

    /// How far the first start has got Steam for Mac ready (prepare).
    enum Preparation: Equatable {
        case installing
        /// Its update on its first start: how far, when its log says.
        case updating(Double?)
        /// Its sign-in window waits, hidden until the player's turn.
        case waitingForSignIn
        /// It remembers an account already (the player had Steam for Mac): nothing to start.
        case remembered
    }

    /// The first start gets Steam for Mac ready while the Windows side sets itself up: Valve's
    /// installer, then Steam's own update on its first start (289 MB, 53 s on 26.10.2026), up to
    /// its sign-in window – which stays hidden (`hold`) until the player's turn. One that remembers
    /// an account isn't started: signing in, it would sign the Windows Steam out.
    @MainActor
    static func prepare(report: (Preparation) -> Void) async throws {
        report(.installing)
        try await install()
        if hasSignedIn {
            report(.remembered)
            return
        }
        // The player's own Steam for Mac, open already: theirs to sign in to when the turn comes –
        // not hidden, not started again.
        if isRunning && !startedByNightforge {
            report(.waitingForSignIn)
            return
        }
        hold(true)
        let started = Date()
        if !isRunning { start() }
        while !Task.isCancelled {
            if waitingForCredentials(since: started) {
                report(.waitingForSignIn)
                return
            }
            let update = Engine.steamUpdateStatus(steamRoot: root)
            report(.updating((update.lastChange ?? .distantPast) >= started ? update.fraction : nil))
            try await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Running it

    /// Starts Steam in the background (hidden, without its main window), or brings it to the
    /// front with its main window when `visible` – for signing in.
    static func start(visible: Bool = false) {
        guard let app else { return }
        if visible && isRunning {
            show(keepFor: 600)
            return
        }
        if !isRunning { willStart() }
        if visible { allowVisible(for: 600) }
        if isTestHome { return TestSteam.launch(visible ? [] : ["-silent"]) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = visible
        configuration.hides = !visible
        configuration.arguments = visible ? [] : ["-silent"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// Nightforge is about to start Steam: it quits it again later (scheduleSteamShutdown), and the
    /// PS button doesn't call up Big Picture meanwhile – Steam for Mac does that too (SteamGuideButton).
    private static func willStart() {
        startedByNightforge = true
        SteamGuideButton.turnOff(steamRoot: root)
    }

    /// Steam's main window in front, for something the player does there (a question, the
    /// sign-in). The window guard leaves it up while Steam waits for the player, and `keepFor`
    /// seconds besides.
    static func show(keepFor seconds: TimeInterval = 0) {
        guard isRunning else { return start(visible: true) }
        allowVisible(for: seconds)
        for app in clientApps { app.unhide() }
        open("open/main", activate: true)
        comeForward()
    }

    /// A Steam dialog the player answers (steam://install/… asks where to install).
    static func ask(_ command: String) {
        allowVisible(for: 300)
        open(command, activate: true)
        comeForward()
    }

    /// Steam for Mac's windows belong to "Steam Helper", its web view process (an agent app without a
    /// Dock icon), not to steam_osx. And since macOS 14 an app comes forward only when the active one
    /// yields to it: Launch Services' `activates` alone left Steam's launch question behind Nightforge,
    /// which said "Confirm in Steam's window" over nothing (Drawful 2, 8.11.). So Nightforge yields to
    /// whichever Steam process shows a window, as it does for games, a few times while Steam opens it.
    static let helperBundleID = "com.valvesoftware.steam.helper"

    private static func comeForward() {
        if isTestHome { return }
        Task { @MainActor in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(400))
                bringForward()
                if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                   front == bundleID || front == helperBundleID { return }
            }
        }
    }

    @MainActor
    private static func bringForward() {
        let steam = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == helperBundleID || $0.executableURL?.lastPathComponent == "steam_osx"
        }
        steam.forEach { $0.unhide() }
        let owners = windowOwners()
        // The one with Steam's window; without a window anywhere yet, the client, which opens one.
        let target = steam.first { owners.contains($0.processIdentifier) && $0.bundleIdentifier == helperBundleID }
            ?? steam.first { owners.contains($0.processIdentifier) } ?? clientApps.first
        guard let target, NSApp.isActive || NSWorkspace.shared.frontmostApplication == target else { return }
        NSApp.yieldActivation(to: target)
        target.activate(from: .current, options: [.activateAllWindows])
    }

    /// The processes with a window of a normal level and some size, on screen or behind others.
    private static func windowOwners() -> Set<pid_t> {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { info -> pid_t? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 120, (bounds["Height"] ?? 0) > 80 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        })
    }

    /// Until when Nightforge wants Steam's window up although Steam doesn't log that it waits.
    private static let visibleLock = NSLock()
    private static var visibleUntil = Date.distantPast

    private static func allowVisible(for seconds: TimeInterval) {
        visibleLock.lock()
        visibleUntil = max(visibleUntil, Date().addingTimeInterval(seconds))
        visibleLock.unlock()
    }

    private static var allowedVisible: Bool {
        visibleLock.lock()
        defer { visibleLock.unlock() }
        return Date() < visibleUntil
    }

    /// The first start holds Steam for Mac's sign-in window back while it gets it ready, so it
    /// doesn't come up in the middle of the Windows setup (prepare); the window guard hides it
    /// although nobody has signed in yet. Released when the player's turn comes.
    private static var held = false

    static func hold(_ on: Bool) {
        visibleLock.lock()
        held = on
        visibleLock.unlock()
        if on { hide() }
    }

    private static var isHeld: Bool {
        visibleLock.lock()
        defer { visibleLock.unlock() }
        return held
    }

    /// Back to the background after the player has dealt with it.
    static func hide() {
        for app in clientApps { app.hide() }
    }

    /// Keeps Steam for Mac out of sight while Nightforge runs. Its window comes up when it starts,
    /// after signing in, when it starts a game and when a game ends (macOS hands it the focus),
    /// and it doesn't even know the games Nightforge plays through Wine. It stays up only while
    /// Steam waits for the player – a question before a start, a cloud conflict, its sign-in – and
    /// not even then while the first start holds it back.
    @MainActor
    static func guardWindows() async {
        while !Task.isCancelled {
            if clientApps.contains(where: { !$0.isHidden }), !allowedVisible, isHeld || (hasSignedIn && !waitingForPlayer) {
                hide()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Steam waits for the player: a question before a game starts ("waiting for user response"
    /// in its console log), a cloud sync it couldn't finish, or its sign-in window.
    static var waitingForPlayer: Bool {
        let now = Date()
        let console = logLines("console_log.txt")
        if let last = console.last(where: { $0.contains("GameAction [AppID") }), last.contains("waiting for user response"),
           let date = logDate(last), now.timeIntervalSince(date) < 600 {
            return true
        }
        let cloud = logLines("cloud_log.txt").filter { $0.contains("[AppID") }
        if let last = cloud.last(where: { ["Starting sync", "conflict", "Failed sync", "complete"].contains(where: $0.contains) }),
           last.contains("conflict") || last.contains("Failed sync"), let date = logDate(last), now.timeIntervalSince(date) < 120 {
            return true
        }
        // Still signed out a while after starting – and not because the Wine Steam signed in.
        if !signedIn, !sessionReplaced, let launched = running.compactMap(\.launchDate).min(), now.timeIntervalSince(launched) > 25 {
            return true
        }
        return false
    }

    private static func logLines(_ name: String) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: root.appendingPathComponent("logs/\(name)")) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return text.split(whereSeparator: \.isNewline)
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// "[2026-10-26 11:10:12] …"
    private static func logDate(_ line: Substring) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return logFormatter.date(from: String(line[line.index(after: line.startIndex)..<close]))
    }

    /// Hands Steam a steam:// command ("run/275850"), which starts it if it isn't running.
    static func open(_ command: String, activate: Bool = false) {
        guard let app, let url = URL(string: "steam://" + command) else { return }
        if !isRunning { willStart() }
        if isTestHome { return TestSteam.launch([url.absoluteString]) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }

    /// Asks Steam to quit (it saves its state and cloud files) and ends it the hard way after 20 s.
    /// Its end comes from the kernel (ProcessEnd), not from a look every second.
    static func quit() async {
        if isTestHome { return await TestSteam.quit() }
        let apps = running
        for app in apps { app.terminate() }
        // NSRunningApplication's pid can read -1 (`clientPID`): then the client's own.
        var pids = apps.map(\.processIdentifier).filter { $0 > 0 }
        if pids.count < apps.count, let client = clientPID { pids.append(client) }
        let deadline = Date().addingTimeInterval(20)
        var ended = false
        if !pids.isEmpty { ended = await ProcessEnd.wait(pids, timeout: 20) }
        // The workspace's list follows an end a moment later; with no process to watch, it alone says.
        var grace = ended ? 20 : 0
        while isRunning, Date() < deadline {
            try? await Task.sleep(for: grace > 0 ? .milliseconds(100) : .seconds(1))
            grace -= 1
        }
        if !isRunning { return endLeftoverIPCServer() }
        for app in running { app.forceTerminate() }
        try? await Task.sleep(for: .seconds(2))
        endLeftoverIPCServer()
    }

    /// Steam for Mac's ipcserver can outlive its Steam: one from this Steam's folder has run on its own
    /// since 27.10.2026 23:47:25, the second its Steam ended (one in 50-odd quits on the dev Mac). Once
    /// no client of this Steam runs, one left to launchd goes too.
    private static func endLeftoverIPCServer() {
        guard clientPID == nil else { return }
        let server = root.appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS/ipcserver").resolvingSymlinksInPath().path
        for process in TestSteam.processes() where process.path == server && parent(of: process.pid) == 1 {
            kill(process.pid, SIGTERM)
        }
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// Quits once the save of the game that ended at `endedAt` is in the Steam Cloud (CloudSaves),
    /// or after `limit` – quit earlier, the upload is lost. False when `keepWaiting` turns false
    /// first (Steam for Mac is needed again); then it keeps running.
    @MainActor
    static func quitWhenSynced(appID: Int, endedAt: Date, limit: TimeInterval, while keepWaiting: () -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < limit {
            guard keepWaiting(), !Task.isCancelled else { return false }
            let state = await Task.detached(priority: .utility) {
                CloudSaves.state(appID: appID, steamRoot: root, endedAt: endedAt)
            }.value
            if state != .syncing { break }
            try? await Task.sleep(for: .seconds(2))
        }
        guard keepWaiting(), !Task.isCancelled else { return false }
        // Not cut off once it quits: cancelled, the quit would end Steam the hard way.
        await Task { await quit() }.value
        return true
    }

    /// Nightforge quits: whether the shutdown script ends Steam for Mac too, once nothing needs it
    /// (Engine.scheduleSteamShutdown) – the one Nightforge started. A test home's is asked to quit
    /// right away instead: the script quits by bundle ID, which could reach the player's own.
    static func endsWithNightforge() -> Bool {
        guard startedByNightforge, isRunning else { return false }
        guard isTestHome else { return true }
        TestSteam.terminate()
        return false
    }

    // MARK: - Games

    private static func manifest(_ appID: Int) -> URL { steamapps.appendingPathComponent("appmanifest_\(appID).acf") }

    /// Asks Steam for Mac to download a game without an install dialog: like the Windows Steam
    /// (Engine.requestDownload) it fetches a game whose manifest says "update required" when it
    /// starts. A Steam that started before the manifest was written is restarted for that – unless
    /// it's one the player opened, or a Mac game runs that would go with it: then Steam shows its
    /// install dialog instead.
    static func download(appID: Int, name: String, installDir: String, macGameRunning: Bool) async throws {
        let written = { (try? manifest(appID).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        if isRunning, written() == nil, macGameRunning || !startedByNightforge {
            ask("install/\(appID)")
            return
        }
        try Engine.requestDownload(appID: appID, name: name, installDir: installDir, steamapps: steamapps)
        guard isRunning else { return start() }
        if !sessionReplaced, let launched = running.compactMap(\.launchDate).min(), let written = written(), launched > written {
            return
        }
        await quit()
        start()
    }

    /// Steam has taken up a requested download – it knows the size, or the files are coming in – or
    /// is busy with another one, behind which it queues this one.
    static func downloadStarted(appID: Int) -> Bool {
        let state = VDF.parse(contentsOf: manifest(appID))?["appstate"]
        let bytes = state?["bytestodownload"]?.string.flatMap { Int64($0) } ?? 0
        let flags = state?["stateflags"]?.string.flatMap { Int($0) } ?? 0
        let downloading = (try? FileManager.default.contentsOfDirectory(
            atPath: steamapps.appendingPathComponent("downloading").path)) ?? []
        return state == nil || bytes > 0 || flags & 4 != 0 || downloading.contains { Int($0) != nil }
    }

    /// Removes a Mac version the way Engine.uninstall removes a Windows one: with Steam closed,
    /// its manifest and files go. A Steam that was running starts again in the background.
    static func uninstall(appID: Int, installDir: URL) async throws {
        let wasRunning = isRunning
        let ours = startedByNightforge
        if wasRunning { await quit() }
        defer {
            if wasRunning {
                start(visible: !ours)  // the player's own Steam comes back as they had it
                startedByNightforge = ours
            }
        }
        // The game's own library folder: steamapps/common/<folder>.
        let library = installDir.deletingLastPathComponent().deletingLastPathComponent()
        try Engine.removeGameFiles(appID: appID, installDirName: installDir.lastPathComponent, steamapps: library)
        try? SteamLibraries.forget(appID: appID, steamRoot: root, bottle: bottle)  // while Steam is quit
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

enum MacSteamError: LocalizedError {
    case downloadFailed, notFromValve, installFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return L10n.t("Steam for Mac could not be downloaded. Check your internet connection.")
        case .notFromValve: return L10n.t("The Steam for Mac download isn't signed by Valve, so it wasn't installed.")
        case .installFailed: return L10n.t("Steam for Mac could not be installed.")
        }
    }
}
