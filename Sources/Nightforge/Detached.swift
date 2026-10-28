import CryptoKit
import Foundation

/// A program that runs apart from Nightforge – for everything that may outlive it: Steam and its
/// Wine session (any Wine command can be the one that starts it), games, Epic downloads, and the
/// scripts that tidy up after Nightforge has quit.
///
/// macOS counts every process an app starts, and all they start in turn, as part of the app, and
/// keeps a quit app's Dock icon ("exited-with-subordinates") while any of them runs: after a
/// restart Nightforge stood in the Dock twice, and clicks, notifications and links could land on
/// the old one. Disclaiming responsibility doesn't change that, and neither does a launchd job or
/// an NSWorkspace launch – macOS lists those under the app too. A program started by an app of its
/// own does not count. So these start through "Nightforge Helper" (wrapper/nightforge-helper.c),
/// which /usr/bin/open launches; it runs the program and reports its process and its end through a
/// folder. Used like Process, as far as Nightforge uses that; where the helper isn't at hand (a
/// build without it, tests), the program runs as a plain child process instead.
final class DetachedProcess: @unchecked Sendable {
    var executableURL: URL?
    var arguments: [String]?
    /// nil: Nightforge's own.
    var environment: [String: String]?
    var currentDirectoryURL: URL?
    /// Files only (their path is handed on, output is appended); nil is /dev/null.
    var standardInput: FileHandle?
    var standardOutput: FileHandle?
    var standardError: FileHandle?
    /// Called once, on a background queue, when the program has ended.
    var terminationHandler: (@Sendable (DetachedProcess) -> Void)?

    private let lock = NSLock()
    private let ended = DispatchGroup()
    private var started = false
    private var exited = false
    private var helper: pid_t = 0
    private var program: pid_t = 0
    private var status: Int32 = 0
    private var folder: URL?
    private var watch: DispatchSourceProcess?
    private var attached: Process?

    init() {}

    var processIdentifier: pid_t { lock.withLock { attached?.processIdentifier ?? program } }

    var isRunning: Bool { lock.withLock { attached?.isRunning ?? (started && !exited) } }

    /// The exit code, or the signal that ended the program.
    var terminationStatus: Int32 { lock.withLock { attached?.terminationStatus ?? status } }

    func run() throws {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: executableURL.map { [NSFilePathErrorKey: $0.path] } ?? [:])
        }
        guard let app = Self.helperApp() else { return try runAttached() }

        let folder = Self.runs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = [executableURL.path] + (arguments ?? [])
        let variables = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        let fields = [currentDirectoryURL?.path ?? "", Self.path(standardInput), Self.path(standardOutput),
                      Self.path(standardError), String(command.count)] + command + [String(variables.count)] + variables
        try Data(fields.map { $0 + "\0" }.joined().utf8).write(to: folder.appendingPathComponent("request"))

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-g", "-j", "-a", app.path, "--args", folder.path]
        open.standardInput = FileHandle.nullDevice
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        guard (try? open.run()) != nil else {
            try? FileManager.default.removeItem(at: folder)
            return try runAttached()
        }
        open.waitUntilExit()
        guard open.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: folder)
            return try runAttached()
        }

        // The helper says which process runs (usually within a few milliseconds), or why none does.
        let deadline = Date().addingTimeInterval(10)
        while true {
            if let pids = Self.read("pid", in: folder)?.split(separator: " ").compactMap({ pid_t($0) }), pids.count == 2 {
                ended.enter()
                lock.withLock { (helper, program, self.folder, started) = (pids[0], pids[1], folder, true) }
                break
            }
            if let failure = Self.read("status", in: folder), failure.hasPrefix("error ") {
                try? FileManager.default.removeItem(at: folder)
                throw POSIXError(POSIXErrorCode(rawValue: Int32(failure.dropFirst(6)) ?? EIO) ?? .EIO)
            }
            guard Date() < deadline else {
                try? FileManager.default.removeItem(at: folder)
                throw POSIXError(.ETIMEDOUT)
            }
            usleep(2_000)
        }
        // The helper writes the status and quits right after the program has ended.
        let watch = DispatchSource.makeProcessSource(identifier: helper, eventMask: .exit, queue: .global(qos: .utility))
        watch.setEventHandler { [self] in finish() }
        lock.withLock { self.watch = watch }
        watch.resume()
        if kill(helper, 0) != 0 && errno == ESRCH { finish() }  // gone before the watch began
    }

    func waitUntilExit() {
        if let attached = lock.withLock({ attached }) { return attached.waitUntilExit() }
        ended.wait()
    }

    func terminate() { send(SIGTERM) }

    func interrupt() { send(SIGINT) }

    private func send(_ number: Int32) {
        let (attached, program, running) = lock.withLock { (attached, program, started && !exited) }
        if let attached {
            number == SIGINT ? attached.interrupt() : attached.terminate()
        } else if running, program > 0 {
            kill(program, number)
        }
    }

    private func finish() {
        let done: (folder: URL?, handler: (@Sendable (DetachedProcess) -> Void)?)? = lock.withLock {
            guard started, !exited else { return nil }
            exited = true
            watch?.cancel()
            watch = nil
            // "exit 0", "signal 15"; none when the helper itself was killed.
            let words = folder.flatMap { Self.read("status", in: $0) }?.split(separator: " ") ?? []
            status = words.count == 2 ? Int32(words[1]) ?? 1 : 1
            return (folder, terminationHandler)
        }
        guard let done else { return }
        if let folder = done.folder { try? FileManager.default.removeItem(at: folder) }
        ended.leave()
        done.handler?(self)
    }

    private func runAttached() throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardInput = standardInput ?? FileHandle.nullDevice
        process.standardOutput = standardOutput ?? FileHandle.nullDevice
        process.standardError = standardError ?? FileHandle.nullDevice
        if let handler = terminationHandler {
            process.terminationHandler = { [self] _ in handler(self) }
        }
        lock.withLock { attached = process }
        try process.run()
    }

    // MARK: - The helper app

    /// Where "Nightforge Helper.app" goes; tests point it elsewhere.
    static var home = Engine.supportDir
    /// The helper program in Nightforge's resources (build.sh compiles it).
    static var helperProgram = Bundle.main.url(forResource: "nightforge-helper", withExtension: nil)
    static let helperName = "Nightforge Helper.app"
    private static let runs = FileManager.default.temporaryDirectory.appendingPathComponent("Nightforge-runs", isDirectory: true)
    private static let appLock = NSLock()
    private static var preparedApp: URL?

    /// The helper as an app of its own in Nightforge's data folder, made here rather than shipped
    /// inside Nightforge.app: a copy from the download would carry its quarantine flag, and macOS
    /// would ask for "Open Anyway" all over again. Rebuilt when the helper or its Info.plist change.
    static func helperApp() -> URL? {
        appLock.withLock {
            if let preparedApp { return preparedApp }
            preparedApp = makeHelperApp()
            return preparedApp
        }
    }

    private static func makeHelperApp() -> URL? {
        let fm = FileManager.default
        guard let helperProgram, let binary = try? Data(contentsOf: helperProgram) else { return nil }
        let info: [String: Any] = [
            "CFBundleExecutable": "nightforge-helper",
            "CFBundleIdentifier": "io.github.lordhayne.nightforge.helper",
            "CFBundleName": "Nightforge Helper",
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            // Never a window or a Dock icon of its own; the programs it starts show theirs.
            "LSUIElement": true,
        ]
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) else { return nil }
        let stamp = Data(SHA256.hash(data: binary + plist).map { String(format: "%02x", $0) }.joined().utf8)

        let app = home.appendingPathComponent(helperName, isDirectory: true)
        let stampFile = "Contents/Resources/helper.sha256"
        if (try? Data(contentsOf: app.appendingPathComponent(stampFile))) == stamp { return app }

        // Built beside the old one and swapped in: a helper still running from it keeps its files.
        let fresh = home.appendingPathComponent(".\(helperName)-\(UUID().uuidString)", isDirectory: true)
        do {
            let macOS = fresh.appendingPathComponent("Contents/MacOS", isDirectory: true)
            let resources = fresh.appendingPathComponent("Contents/Resources", isDirectory: true)
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            // Written as data, not copied: a copy would bring the quarantine flag along.
            let executable = macOS.appendingPathComponent("nightforge-helper")
            try binary.write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try plist.write(to: fresh.appendingPathComponent("Contents/Info.plist"))
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ try? Data(contentsOf: $0) }) {
                try icon.write(to: resources.appendingPathComponent("AppIcon.icns"))
            }
            try stamp.write(to: fresh.appendingPathComponent(stampFile))
            // Nightforge's own file; were it flagged anyway, Launch Services would refuse to start it.
            for path in [fresh.path, executable.path] { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
            // Signed as a bundle, so macOS knows it by its name when it asks for a permission for it.
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", fresh.path]
            sign.standardOutput = FileHandle.nullDevice
            sign.standardError = FileHandle.nullDevice
            if (try? sign.run()) != nil { sign.waitUntilExit() }
            if fm.fileExists(atPath: app.path) {
                _ = try fm.replaceItemAt(app, withItemAt: fresh)
            } else {
                try fm.moveItem(at: fresh, to: app)
            }
            return app
        } catch {
            try? fm.removeItem(at: fresh)
            return nil
        }
    }

    private static func path(_ handle: FileHandle?) -> String {
        guard let handle else { return "/dev/null" }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return fcntl(handle.fileDescriptor, F_GETPATH, &buffer) == 0 ? String(cString: buffer) : "/dev/null"
    }

    private static func read(_ name: String, in folder: URL) -> String? {
        (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
