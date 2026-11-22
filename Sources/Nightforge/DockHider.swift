import CryptoKit
import Foundation

/// The library that keeps Steam out of the Dock (wrapper/hide-steam-dock.m) and gives Wine the network
/// interfaces in an order Steam's sign-in finds the connected one in (wrapper/network-order.c), kept in Nightforge's
/// data folder rather than inside Nightforge.app. Every Wine process loads it from the path in
/// DYLD_INSERT_LIBRARIES, and Steam hands that path on to everything it starts for as long as it
/// runs – for days, long after Nightforge has quit. Once the file is gone from there (Nightforge.app
/// moved to Applications, an old build deleted), dyld ends every new process before it starts:
/// each game, and whatever Wine starts when a controller connects (28./29.10.2026).
enum DockHider {
    /// Where the library goes; tests point it elsewhere.
    static var home = Engine.supportDir
    /// The library in Nightforge's resources (build.sh compiles it).
    static var bundled = Bundle.main.url(forResource: "hide-steam-dock", withExtension: "dylib")
    static let name = "hide-steam-dock.dylib"
    /// Raised when a change of the library has to reach a session that runs already: Steam restarts, and
    /// the session it ran in ends (Engine.applyLibraryVersion, which since 0.3.5 goes by `fingerprint()` as well). 1: the network order (wrapper/network-order.c).
    /// 2: the frame limit on D3DMetal (wrapper/d3dmetal-pace.m).
    static let sessionVersion = 2
    private static let lock = NSLock()
    /// The library put in place from `bundled`, and the file it left in the data folder: once per run of Nightforge,
    /// whether it worked or not – and again whenever that file is no longer the one it left there.
    private static var prepared: (source: URL?, ready: Bool, file: FileIdentity?, fingerprint: String?)?

    /// Which file a path names, cheaply: a copy renamed over it brings another inode, one written in place another
    /// modification time or size.
    struct FileIdentity: Equatable {
        var path: String, device: Int, inode: Int, size: Int, modified: TimeInterval

        init?(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            self.path = path
            device = Int(info.st_dev)
            inode = Int(info.st_ino)
            size = Int(info.st_size)
            modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
        }
    }

    /// The installed library for DYLD_INSERT_LIBRARIES, put in place or updated first; nil without
    /// one (tests, a build without it) – never a path that isn't there, which would end every process.
    /// Another Nightforge with the same data folder (the release in /Applications next to a test build, 22.11.2026)
    /// puts its own library there; the next call here puts this one's back, before anything starts with it.
    static func path() -> String? { prepare()?.path }

    /// SHA-256 of the library in the data folder as `path()` leaves it (hex, 16 bytes), nil without one. What a Wine
    /// session began with (Engine.applyLibraryVersion) and Steam's signature go by the content, not by a version
    /// number: another copy of Nightforge brings the same number with other code.
    static func fingerprint() -> String? { prepare()?.fingerprint }

    private static func prepare() -> (path: String, fingerprint: String?)? {
        lock.withLock {
            let target = home.appendingPathComponent(name)
            // Changed since it was put there, or gone: put in place again.
            let replaced = prepared?.ready == true && prepared?.file != FileIdentity(target.path)
            if prepared == nil || prepared?.source != bundled || replaced {
                let ready = install(to: target)
                let file = ready ? FileIdentity(target.path) : nil
                let fingerprint = ready ? (try? Data(contentsOf: target)).map(hash) : nil
                prepared = (bundled, ready, file, fingerprint)
            }
            guard let prepared, prepared.ready else { return nil }
            return (target.path, prepared.fingerprint)
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// A new library goes in under a name of its own and is then renamed over the old one: a process
    /// that has the old one loaded keeps it (the name moves on, the file stays until nothing uses
    /// it), and one starting meanwhile gets either file whole. Written over in place, the file a
    /// running process has mapped would change under it, and macOS ends a process whose code does.
    private static func install(to target: URL) -> Bool {
        let fm = FileManager.default
        guard let bundled, let library = try? Data(contentsOf: bundled) else { return false }
        if (try? Data(contentsOf: target)) == library { return true }
        let fresh = home.appendingPathComponent(".\(name)-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            // Written as data, not copied: a copy would bring the download's quarantine flag along.
            try library.write(to: fresh)
            guard rename(fresh.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            return true
        } catch {
            try? fm.removeItem(at: fresh)
            return false
        }
    }

    // MARK: - The running Steam

    /// Where the running Steam's processes load the library from, compared with `path()`.
    enum State: Equatable {
        /// From `path()` – or nothing to tell (no Steam, nothing installed, unreadable).
        case current
        /// From somewhere else that's still there (an app bundle that may go any time), or not at all.
        case outdated
        /// From a file that's gone: every program Steam starts now dies in dyld, games included.
        case missing
    }

    /// `started`: DYLD_INSERT_LIBRARIES of the running Steam ("" without it, nil when unknown);
    /// `installed`: `path()`.
    static func state(started: String?, installed: String?, exists: (String) -> Bool) -> State {
        guard let started, let installed else { return .current }
        let libraries = started.split(separator: ":").map(String.init)
        if libraries.contains(where: { !exists($0) }) { return .missing }
        return libraries.contains(installed) ? .current : .outdated
    }

    /// The state of Nightforge's running Steam: what it was started with, read from the process itself,
    /// so a Steam another Nightforge started (a build since moved or deleted) counts as well.
    static func runningSteamState() -> State {
        state(started: runningSteamLibraries(), installed: path()) { FileManager.default.fileExists(atPath: $0) }
    }

    /// DYLD_INSERT_LIBRARIES of Nightforge's running Steam ("" when it has none), nil without a Steam.
    static func runningSteamLibraries() -> String? {
        let steam = Engine.ownProcesses().filter { $0.command.lowercased().contains(#"\steam\steam.exe"#) }
        // The oldest is Steam itself; a newer one is a start handing a command (-applaunch) over to it.
        let started = steam.map { ($0.pid, Engine.processStart($0.pid) ?? .distantFuture) }
        guard let pid = started.min(by: { $0.1 < $1.1 })?.0 else { return nil }
        return startValue(of: "DYLD_INSERT_LIBRARIES", pid: pid)
    }

    /// An environment variable as the process got it when it started ("" when it had none), nil when
    /// its environment can't be read.
    static func startValue(of name: String, pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return startValue(of: name, procArgs: Array(buffer.prefix(size)))
    }

    /// From KERN_PROCARGS2: argc, the executable's path, padding, the arguments, then the environment.
    /// The variable is looked for in everything after the path rather than counted out by argc:
    /// Wine moves its arguments together in place (to show the Windows program in ps), so there
    /// are fewer strings than argc says, and counting would skip the first variable or two.
    static func startValue(of name: String, procArgs bytes: [UInt8]) -> String? {
        guard bytes.count > 4 else { return nil }
        let strings = bytes.dropFirst(4).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        guard !strings.isEmpty else { return nil }
        let prefix = name + "="
        guard let entry = strings.dropFirst().first(where: { $0.hasPrefix(prefix) }) else { return "" }
        return String(entry.dropFirst(prefix.count))
    }

    /// Steam once more, the way it always starts, but with a new Wine session: Wine's own services
    /// were started with the old path as well, and the next device that connects would start a
    /// process from them. For a moment when nothing needs Steam (LibraryModel.watchDockHider).
    /// `reason`: for the log line of the session's end.
    static func restartSteam(_ wine: URL, reason: String) async throws {
        try await Engine.stopSteam(wine)
        Engine.stopAll(wine, reason: reason)
        try await Engine.restartSteamInBackground(wine)
    }
}
