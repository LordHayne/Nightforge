import Foundation

/// Which program begins a Wine session, and with what AVX: Wine fills in the processor's features once per session, from
/// what its first process sees, and `IsProcessorFeaturePresent(AVX)` answers that for every program in it – CPUID goes by
/// each process (docs/ENTWURF-AVX.md, 23.11.2026). Nightforge's own Wine starts (regedit, winetricks, the helpers) carry no
/// AVX, Steam's and a game's do. Only a line in wine.log, to see how often which one comes first; nothing is changed.
enum WineSessionStart {
    /// Wine's own programs a session can begin with: wine, its loader, winetricks (which starts wine). Not the wineserver,
    /// which a program starts for itself.
    static let winePrograms: Set<String> = ["wine", "wine64", "wineloader", "wine-preloader", "wine64-preloader", "winetricks"]

    /// The line for a start of `executable` with `arguments` (inside the sandbox, `helper` and its profile come first), nil
    /// when it isn't a Wine program or a session runs already (`sessionRunning`, asked only for a Wine program). The program
    /// is named by its file name alone – a path can carry the player's name.
    static func line(executable: URL?, arguments: [String], environment: [String: String]?, helper: URL? = WineSandbox.helper,
                     sessionRunning: () -> Bool) -> String? {
        var wine = executable, rest = arguments
        if let helper, let executable, executable.standardizedFileURL.path == helper.standardizedFileURL.path, arguments.count >= 2 {
            wine = URL(fileURLWithPath: arguments[1])
            rest = Array(arguments.dropFirst(2))
        }
        guard let wine, winePrograms.contains(wine.lastPathComponent), !sessionRunning() else { return nil }
        let avx = (environment ?? ProcessInfo.processInfo.environment)["ROSETTA_ADVERTISE_AVX"] == "1"
        return "Wine session begins with \(programName(wine: wine, arguments: rest)), AVX \(avx ? "on" : "off")"
    }

    /// The Windows program a start runs, by file name ("steam.exe", "regedit", "wineboot"): its first argument that isn't a
    /// switch ("-silent", or regedit's "/S"). For winetricks, winetricks itself.
    static func programName(wine: URL, arguments: [String]) -> String {
        guard wine.lastPathComponent != "winetricks",
              let program = arguments.first(where: { !$0.isEmpty && !$0.hasPrefix("-") && !($0.hasPrefix("/") && $0.count <= 3) })
        else { return wine.lastPathComponent }
        let name = program.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? program
        return name.isEmpty ? wine.lastPathComponent : name
    }

    /// Before a Wine program starts (RosettaSupport.run): the line, when it begins a session. Never holds the start up – it
    /// runs on the main thread too (PadAnswerRun from a question's answer): no process list, only a look at the wineserver's
    /// lock (`sessionRunning`, microseconds; audit N2, 23.11.2026). Not to be told: no line.
    static func note(_ process: DetachedProcess) {
        if let line = line(executable: process.executableURL, arguments: process.arguments ?? [], environment: process.environment,
                           sessionRunning: { sessionRunning(prefix: prefix(of: process)) ?? true }) {
            GameLog.note(line)
        }
    }

    /// The prefix a start runs in: its WINEPREFIX (Battle.net's, a CrossOver bottle), else Nightforge's.
    static func prefix(of process: DetachedProcess) -> URL {
        process.environment?["WINEPREFIX"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Engine.prefix
    }

    /// Where the wineserver of the session for `prefix` keeps its socket and lock, as Wine names it (ntdll's
    /// init_server_dir): `/tmp/.wine-<uid>/server-<device>-<inode>`, both in hex, of the prefix's folder.
    static func serverFolder(prefix: URL, root: String = "/tmp", uid: uid_t = getuid()) -> String? {
        var info = stat()
        guard stat(prefix.path, &info) == 0 else { return nil }
        let device = String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16), inode = String(UInt64(info.st_ino), radix: 16)
        return "\(root)/.wine-\(uid)/server-\(device)-\(inode)"
    }

    /// Whether a wineserver runs for `prefix`: the one that runs holds a write lock on its folder's `lock` file for as long
    /// as it lives (F_GETLK reads that without touching the server – connecting to its socket would make it a client).
    /// False with no lock file or no lock on it, nil when it can't be told (no prefix, no answer).
    static func sessionRunning(prefix: URL = Engine.prefix, root: String = "/tmp") -> Bool? {
        guard let folder = serverFolder(prefix: prefix, root: root) else { return nil }
        let file = open(folder + "/lock", O_RDONLY)
        guard file >= 0 else { return errno == ENOENT ? false : nil }
        defer { close(file) }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard fcntl(file, F_GETLK, &lock) == 0 else { return nil }
        return lock.l_type != Int16(F_UNLCK)
    }
}
