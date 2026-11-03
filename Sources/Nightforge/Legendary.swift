import Foundation

/// legendary (GPL-3.0, github.com/legendary-gl/legendary) speaks to Epic Games for Nightforge, the
/// way Heroic uses it: sign-in tokens, the library, downloads with resume and updates, the
/// parameters a game starts with, cloud saves. It comes as a component (components/manifest.json)
/// and keeps its settings and Epic's tokens in Nightforge's folder. The games themselves Nightforge
/// starts with its own engine, like Steam's.
enum Legendary {
    static let componentID = "legendary"

    /// legendary's settings, Epic's sign-in tokens, the library's metadata and installed.json.
    static var configDir: URL { Engine.supportDir.appendingPathComponent("Epic/legendary", isDirectory: true) }

    /// Where Epic games go: into the Windows environment next to Steam's, where Epic's own launcher
    /// would put them – "Remove Nightforge completely" takes them along like the Steam games.
    static var gamesDir: URL { Engine.prefix.appendingPathComponent("drive_c/Program Files/Epic Games", isDirectory: true) }

    /// One log per download: its progress is read from there, also after Nightforge was restarted.
    static var logsDir: URL { Engine.supportDir.appendingPathComponent("Epic/Logs", isDirectory: true) }

    static func log(for appName: String) -> URL { logsDir.appendingPathComponent("\(appName).log") }

    // MARK: - The program

    /// legendary, fetched on first use and unpacked once (`PackedApp`). The copy there is used
    /// without asking the network (offline starts); a new version comes when the component list
    /// names one (the engine's start removes versions it no longer names).
    static func program() async throws -> URL {
        if let installed = programNow(), PackedApp.isReady(installed) {
            return installed
        }
        let manifest = try? await ComponentStore.shared.manifest()
        guard let component = manifest?.component(componentID) ?? ComponentStore.bundledManifest()?.component(componentID)
        else { throw EpicError.unavailable }
        let dir = try await ComponentStore.shared.install(component)
        let binary = dir.appendingPathComponent(component.url.lastPathComponent)
        await Engine.offMain { _ = try? PackedApp.unpackOnce(binary) }
        return binary
    }

    /// Fetches and unpacks legendary and runs it once, while the player signs in: macOS looks at
    /// every freshly unpacked library at its first start, which takes a while only that once.
    static func prepare() async {
        guard let program = try? await program() else { return }
        _ = try? await run(["--version"], program: program, timeout: 120)
    }

    /// The program when it's there already – without the network (offline starts).
    static func programNow() -> URL? {
        guard let dir = Engine.installedComponentNow(componentID),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix("legendary") && FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Its own folder for its settings and Epic's tokens, the Windows environment for the paths of
    /// saves, and it runs from what was unpacked once.
    static func environment(program: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["LEGENDARY_CONFIG_PATH"] = configDir.path
        env["WINEPREFIX"] = Engine.prefix.path
        // No colours or progress bars meant for a terminal.
        env["NO_COLOR"] = "1"
        env.merge(PackedApp.environment(binary: program)) { _, packed in packed }
        return env
    }

    struct Output {
        let status: Int32
        let output: Data
        let log: String

        var text: String { String(decoding: output, as: UTF8.self) }
        /// The last error legendary gave, for a message when nothing better is known.
        var error: String? {
            log.split(whereSeparator: \.isNewline).last { $0.contains("ERROR:") || $0.contains("CRITICAL:") }
                .map { String($0.split(separator: ":", maxSplits: 1).last ?? $0).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Runs legendary and waits for it. JSON comes on stdout, its log on stderr.
    static func run(_ arguments: [String], program: URL? = nil, timeout: TimeInterval = 120) async throws -> Output {
        let binary: URL
        if let program {
            binary = program
        } else {
            binary = try await self.program()
        }
        PackedApp.keepPrivate(configDir)
        return try await PackedApp.run(binary, arguments: arguments, directory: configDir, timeout: timeout) {
            environment(program: binary)
        }
    }

    /// Starts legendary without waiting (a download, which carries on after Nightforge quits), its
    /// output into `log`.
    static func start(_ arguments: [String], log: URL) async throws -> DetachedProcess {
        let binary = try await program()
        if !PackedApp.knowsHowToRun(binary) { _ = try? await run(["--version"], program: binary) }
        PackedApp.keepPrivate(configDir)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let process = DetachedProcess()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment(program: binary)
        process.currentDirectoryURL = configDir
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Ends a legendary and the processes it started: its downloader and their helpers run apart
    /// and go on without it (18 of them, for good), so they're gathered first and ended with it.
    /// legendary keeps what it has downloaded and carries on from there next time.
    static func stop(_ pid: pid_t) {
        let family = descendants(of: pid, in: processTable())
        kill(pid, SIGTERM)
        for child in family { kill(child, SIGTERM) }
    }

    /// `ps -axo pid=,ppid=`: each process and its parent ("" when ps doesn't answer, `ProcessList`).
    private static func processTable() -> String {
        ProcessList.ps("pid=,ppid=") ?? ""
    }

    /// The processes below `pid`, children and theirs, from a `pid ppid` table.
    static func descendants(of pid: pid_t, in table: String) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for line in table.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            guard fields.count == 2, let child = pid_t(fields[0]), let parent = pid_t(fields[1]) else { continue }
            children[parent, default: []].append(child)
        }
        var found: [pid_t] = []
        var open = [pid]
        while let next = open.popLast() {
            for child in children[next] ?? [] where !found.contains(child) && child != pid {
                found.append(child)
                open.append(child)
            }
        }
        return found
    }

    // MARK: - What legendary says

    /// A download's state from its log: how far, how fast, how long still, and how it ended.
    struct Progress: Equatable {
        var fraction: Double?
        /// Bytes per second over the last seconds (legendary's "raw" download speed).
        var speed: Double?
        var secondsLeft: Int?
        /// What the download comes to (legendary's "Download size"), and the game on disk.
        var downloadSize: Int64?
        var installSize: Int64?
        var finished = false
        /// legendary gave up: its reason.
        var failure: String?
    }

    /// Reads a download log: legendary writes "= Progress: 12.34% (…), Running for 00:00:10, ETA:
    /// 00:01:00" and "+ Download\t- 12.34 MiB/s (raw) / …" every few seconds.
    static func progress(inLog text: String) -> Progress {
        var progress = Progress()
        for line in text.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: "= Progress: ") {
                let rest = line[range.upperBound...]
                if let percent = Double(rest.prefix { $0.isNumber || $0 == "." }) { progress.fraction = min(percent / 100, 1) }
                if let eta = line.range(of: "ETA: ") { progress.secondsLeft = seconds(String(line[eta.upperBound...].prefix(8))) }
            } else if let range = line.range(of: "+ Download") {
                let rest = line[range.upperBound...].drop { !$0.isNumber }
                if let mib = Double(rest.prefix { $0.isNumber || $0 == "." }) { progress.speed = mib * 1_048_576 }
            } else if let range = line.range(of: "Download size: ") {
                progress.downloadSize = mebibytes(line[range.upperBound...])
            } else if let range = line.range(of: "Install size: ") {
                progress.installSize = mebibytes(line[range.upperBound...])
            } else if line.contains("Finished installation process") || line.contains("already up to date") {
                progress.finished = true
                progress.fraction = 1
            } else if line.contains("Installation failed") || line.contains("cannot proceed") {
                progress.failure = progress.failure ?? String(line)
            } else if line.contains("! Failure:") {
                progress.failure = String(line.split(separator: ":", maxSplits: 1).last ?? line).trimmingCharacters(in: .whitespaces)
            } else if line.contains("ERROR:") || line.contains("CRITICAL:") {
                progress.failure = String(line.split(separator: ":", maxSplits: 1).last ?? line).trimmingCharacters(in: .whitespaces)
            }
        }
        return progress
    }

    private static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private static func mebibytes(_ text: Substring) -> Int64? {
        Double(text.prefix { $0.isNumber || $0 == "." }).map { Int64($0 * 1_048_576) }
    }

    /// What `legendary launch <app> --json` hands over, as Nightforge starts it under Wine.
    typealias LaunchCommand = StoreLaunchCommand

    /// `json`: legendary's launch parameters. Its ownership token file (`-epicovt=/…`) is a Mac
    /// path; Windows games see the Mac's files under Z:.
    static func launchCommand(fromJSON json: Data) -> LaunchCommand? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let directory = object["game_directory"] as? String, !directory.isEmpty,
              let executable = object["game_executable"] as? String, !executable.isEmpty
        else { return nil }
        func strings(_ key: String) -> [String] { (object[key] as? [Any])?.compactMap { $0 as? String } ?? [] }
        let egl = strings("egl_parameters").map { argument -> String in
            guard argument.hasPrefix("-epicovt=/") else { return argument }
            return "-epicovt=" + windowsPath(String(argument.dropFirst("-epicovt=".count)))
        }
        let exe = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(executable)
        let working = (object["working_directory"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return LaunchCommand(executable: exe, workingDirectory: working ?? exe.deletingLastPathComponent(),
                             arguments: strings("game_parameters") + strings("user_parameters") + egl,
                             environment: (object["environment"] as? [String: String]) ?? [:])
    }

    /// "/Users/a/b" → "Z:\Users\a\b": Wine shows the Mac's own files on Z:.
    static func windowsPath(_ macPath: String) -> String {
        "Z:" + macPath.replacingOccurrences(of: "/", with: "\\")
    }
}

enum EpicError: LocalizedError {
    case unavailable
    case signInFailed(String?)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.t("Epic Games support isn't in the component list yet. Check your internet connection and try again.")
        case .signInFailed(let reason?):
            return L10n.t("Epic Games didn't accept the sign-in (%@). Please try again.", reason)
        case .signInFailed(nil):
            return L10n.t("Epic Games didn't accept the sign-in. Please try again.")
        case .failed(let reason):
            return reason
        }
    }
}

/// A program packed into one file with everything it needs (PyInstaller, as legendary comes): at
/// every start it unpacks its Python and libraries into a fresh temporary folder, and macOS checks
/// each unpacked library anew – 5 to 15 s before it does anything. Unpacked once next to it, it
/// runs from there in a fifth of a second. Should the unpacked copy not be there, it unpacks itself
/// as before.
enum PackedApp {
    static let magic = Data([0x4D, 0x45, 0x49, 0x0C, 0x0B, 0x0A, 0x0B, 0x0E])  // "MEI\014\013\012\013\016"

    struct Entry: Equatable {
        let name: String
        let offset: Int
        let length: Int
        let compressed: Bool
        /// b: library, x: data file, n: symbolic link – what the program unpacks; the rest it reads in place.
        let kind: Character
    }

    /// A folder that holds a program's sign-in tokens: the player's alone (mode 700), whatever mask the
    /// program writes its files with (legendary leaves user.json and gogdl auth.json at 644).
    static func keepPrivate(_ folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }

    /// The folder next to `binary` that holds what it unpacks.
    static func folder(for binary: URL) -> URL {
        binary.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
    }

    /// The entries in the archive at the end of `data`, with where the archive starts.
    static func entries(in data: Data) -> (start: Int, entries: [Entry])? {
        guard let cookie = data.range(of: magic, options: .backwards)?.lowerBound, cookie + 24 <= data.count else { return nil }
        func int(_ at: Int) -> Int {
            data[data.startIndex + at ..< data.startIndex + at + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        let length = int(cookie + 8), tableOffset = int(cookie + 12), tableLength = int(cookie + 16)
        let start = cookie + 88 - length
        guard start >= 0, start + tableOffset + tableLength <= data.count else { return nil }
        var entries: [Entry] = []
        var position = start + tableOffset
        while position + 18 <= start + tableOffset + tableLength {
            let size = int(position)
            guard size >= 18, position + size <= data.count else { return nil }
            let nameBytes = data[data.startIndex + position + 18 ..< data.startIndex + position + size].prefix { $0 != 0 }
            entries.append(Entry(name: String(decoding: nameBytes, as: UTF8.self), offset: int(position + 4),
                                 length: int(position + 8), compressed: data[data.startIndex + position + 16] != 0,
                                 kind: Character(UnicodeScalar(data[data.startIndex + position + 17]))))
            position += size
        }
        return (start, entries)
    }

    /// A name or link inside the folder: no absolute paths, nothing that climbs out of it.
    static func isInside(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    /// Unpacks what `binary` would unpack at each start into `folder(for:)`, unless that was done.
    /// Into a staging folder first, so a half-unpacked copy is never used. True when it's there.
    @discardableResult
    static func unpackOnce(_ binary: URL) throws -> Bool {
        let fm = FileManager.default
        let target = folder(for: binary)
        if refusesUnpacked(binary) { return false }
        if fm.fileExists(atPath: target.appendingPathComponent(".complete").path) { return true }
        let data = try Data(contentsOf: binary, options: .alwaysMapped)
        guard let (start, entries) = entries(in: data) else { return false }
        let staging = binary.deletingLastPathComponent().appendingPathComponent(".unpacking-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for entry in entries where "bxn".contains(entry.kind) {
            guard isInside(entry.name), start + entry.offset + entry.length <= data.count else { return false }
            var bytes = data[data.startIndex + start + entry.offset ..< data.startIndex + start + entry.offset + entry.length]
            if entry.compressed {
                // zlib: a two-byte header, then plain deflate.
                guard bytes.count > 2, let inflated = try? (Data(bytes.dropFirst(2)) as NSData).decompressed(using: .zlib) else { return false }
                bytes = Data(referencing: inflated)
            }
            let file = staging.appendingPathComponent(entry.name)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.kind == "n" {
                let destination = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
                let resolved = (entry.name as NSString).deletingLastPathComponent
                guard isInside(destination), isInside(resolved.isEmpty ? destination : resolved + "/" + destination) else { return false }
                try fm.createSymbolicLink(atPath: file.path, withDestinationPath: destination)
            } else {
                try Data(bytes).write(to: file)
                if entry.kind == "b" { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
            }
        }
        FileManager.default.createFile(atPath: staging.appendingPathComponent(".complete").path, contents: nil)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
        return true
    }

    /// Lets the program run from the unpacked copy, as it does when it has just unpacked itself.
    static func environment(binary: URL) -> [String: String] {
        let target = folder(for: binary)
        guard !refusesUnpacked(binary), FileManager.default.fileExists(atPath: target.appendingPathComponent(".complete").path)
        else { return [:] }
        return ["_PYI_APPLICATION_HOME_DIR": target.path, "_PYI_ARCHIVE_FILE": binary.path, "_PYI_PARENT_PROCESS_LEVEL": "1"]
    }

    // MARK: - Programs that won't run from it

    /// Newer PyInstaller bootloaders (gogdl 1.4.0's) check that their home folder is one they made
    /// themselves – named `_MEI…`, with their parent's PID, owned by them – and otherwise stop with
    /// "Security validation failure" and code 255 before any of the program runs. That check is
    /// deliberate, so such a program runs as it comes and unpacks itself at each start (gogdl: ~3 s).
    /// A note next to it says so; one that ran from the unpacked copy gets a note too.
    static func refusedNote(for binary: URL) -> URL {
        binary.deletingLastPathComponent().appendingPathComponent(".runs-packed")
    }

    static func acceptedNote(for binary: URL) -> URL {
        binary.deletingLastPathComponent().appendingPathComponent(".runs-unpacked")
    }

    static func refusesUnpacked(_ binary: URL) -> Bool { FileManager.default.fileExists(atPath: refusedNote(for: binary).path) }

    /// It ran once already, one way or the other – or there's nothing unpacked to try.
    static func knowsHowToRun(_ binary: URL) -> Bool {
        environment(binary: binary).isEmpty || FileManager.default.fileExists(atPath: acceptedNote(for: binary).path)
    }

    /// Unpacked once, or known to run as it comes.
    static func isReady(_ binary: URL) -> Bool {
        refusesUnpacked(binary) || FileManager.default.fileExists(atPath: folder(for: binary).path)
    }

    /// How a refusal ends: "[PYI-45608:ERROR] Security validation failure: unexpected name of
    /// application's home directory!" and code 255.
    static func refused(status: Int32, log: String) -> Bool {
        status == 255 && log.contains("Security validation failure")
    }

    /// From now on it runs as it comes; the unpacked copy goes (the note first, so nothing unpacks it again meanwhile).
    static func markRefused(_ binary: URL) {
        FileManager.default.createFile(atPath: refusedNote(for: binary).path, contents: nil)
        try? FileManager.default.removeItem(at: folder(for: binary))
    }

    /// Runs `binary` and waits for it – from the unpacked copy while it lets itself be run from
    /// there. One that refuses is noted and run again as it comes, now and from then on: nothing of
    /// it ran the first time, so running it again is safe.
    static func run(_ binary: URL, arguments: [String], directory: URL, timeout: TimeInterval,
                    environment: @escaping @Sendable () -> [String: String]) async throws -> Legendary.Output {
        let first = environment()
        let output = try await execute(binary, arguments: arguments, environment: first, directory: directory, timeout: timeout)
        guard first["_PYI_APPLICATION_HOME_DIR"] != nil else { return output }
        guard refused(status: output.status, log: output.log) else {
            if !FileManager.default.fileExists(atPath: acceptedNote(for: binary).path) {
                FileManager.default.createFile(atPath: acceptedNote(for: binary).path, contents: nil)
            }
            return output
        }
        markRefused(binary)
        return try await execute(binary, arguments: arguments, environment: environment(), directory: directory, timeout: timeout)
    }

    private static func execute(_ binary: URL, arguments: [String], environment: [String: String], directory: URL,
                                timeout: TimeInterval) async throws -> Legendary.Output {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = directory
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            // Both pipes at once: a full one would stop the program midway.
            async let output = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
            async let log = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
            let (data, logData) = await (output, log)
            // Not `waitUntilExit`: from a task it can miss the program ending a moment after it closed
            // its output and never return (1 in ~400 legendary calls; a size check then waited for ever).
            while process.isRunning { try? await Task.sleep(for: .milliseconds(20)) }
            killer.cancel()
            return Legendary.Output(status: process.terminationStatus, output: data, log: String(decoding: logData, as: UTF8.self))
        }.value
    }
}
