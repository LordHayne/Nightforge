import Foundation

/// gogdl (GPL-3.0, github.com/Heroic-Games-Launcher/heroic-gogdl), Heroic's GOG downloader, speaks
/// to GOG for Nightforge: sign-in tokens, downloads with resume and updates (as deltas), what a game
/// comes to, cloud saves. It comes as a component (components/manifest.json), packed like legendary,
/// but it won't run from a copy unpacked once (`PackedApp`). The library Nightforge reads from GOG's API
/// itself – gogdl has no list of games – and it starts the games itself, from their own info file.
enum GOGDL {
    static let componentID = "gogdl"

    /// gogdl's settings: the build manifests of what's installed (updates are deltas against them).
    static var configDir: URL { Engine.supportDir.appendingPathComponent("GOG/gogdl", isDirectory: true) }
    /// GOG's sign-in tokens; gogdl refreshes them itself.
    static var authFile: URL { configDir.appendingPathComponent("auth.json") }
    /// The manifest gogdl keeps of an installed game (GOGDL_CONFIG_PATH/heroic_gogdl/manifests).
    static func manifest(for id: String) -> URL {
        configDir.appendingPathComponent("heroic_gogdl/manifests/\(id)")
    }
    /// Files a game's installer would put elsewhere (its support folder).
    static func supportDir(for id: String) -> URL {
        Engine.supportDir.appendingPathComponent("GOG/Support/\(id)", isDirectory: true)
    }

    /// Windows versions go into the Windows environment next to Steam's and Epic's games, where
    /// GOG's own installers put them – "Remove Nightforge completely" takes them along.
    static var windowsGamesDir: URL { Engine.prefix.appendingPathComponent("drive_c/Program Files/GOG Games", isDirectory: true) }
    /// Mac versions are apps of their own, in Nightforge's folder (the library is where they're played).
    static var macGamesDir: URL { Engine.supportDir.appendingPathComponent("GOG/Games", isDirectory: true) }

    static func gamesDir(for platform: Platform) -> URL { platform == .mac ? macGamesDir : windowsGamesDir }

    /// One log per download: its progress is read from there, also after Nightforge was restarted.
    static var logsDir: URL { Engine.supportDir.appendingPathComponent("GOG/Logs", isDirectory: true) }

    static func log(for id: String) -> URL { logsDir.appendingPathComponent("\(id).log") }

    /// The log of a game's download that stopped, kept for a problem report until one finishes.
    static func failedLog(for id: String) -> URL { logsDir.appendingPathComponent("\(id).failed.log") }

    /// Its error lines and how it ended, without the progress (and the links in between).
    static func failureLines(inLog text: String, limit: Int = 20) -> [String] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { $0.contains("ERROR") || $0.contains("CRITICAL") || $0.contains(endMark) || $0.contains("Not enough disk space") }
        return Array(lines.suffix(limit)).map { GameLog.redacted($0) }
    }

    /// How the last sign-in went (and a token refresh where gogdl didn't run): its code and log,
    /// without the sign-in code or any token.
    static var authLog: URL { logsDir.appendingPathComponent("auth.log") }

    // MARK: - The program

    /// gogdl, fetched on first use and unpacked once – which gogdl 1.4.0 refuses to run from, so it
    /// runs as it comes (`PackedApp.refusesUnpacked`). The copy there is used without asking the
    /// network (offline starts and sizes); a new version comes when the component list names one.
    static func program() async throws -> URL {
        if let installed = programNow(), PackedApp.isReady(installed) {
            return installed
        }
        let manifest = try? await ComponentStore.shared.manifest()
        guard let component = manifest?.component(componentID) ?? ComponentStore.bundledManifest()?.component(componentID)
        else { throw GOGError.unavailable }
        let dir = try await ComponentStore.shared.install(component)
        let binary = dir.appendingPathComponent(component.url.lastPathComponent)
        await Engine.offMain { _ = try? PackedApp.unpackOnce(binary) }
        return binary
    }

    /// Fetches gogdl and runs it once while the player signs in: macOS looks at every freshly
    /// unpacked library at its first start, which takes longest that once (gogdl: 7.6 s, then ~3 s),
    /// and how it runs (`PackedApp`) is settled before the sign-in's code reaches it.
    static func prepare() async {
        guard let program = try? await program() else { return }
        _ = try? await run(["--version"], program: program, timeout: 120)
    }

    static func programNow() -> URL? {
        guard let dir = Engine.installedComponentNow(componentID),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix("gogdl") && FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Its own folder for its settings and the Windows environment for saves; it runs from what
    /// was unpacked once.
    static func environment(program: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GOGDL_CONFIG_PATH"] = configDir.path
        env["WINEPREFIX"] = Engine.prefix.path
        env["NO_COLOR"] = "1"
        env["PYTHONUNBUFFERED"] = "1"  // its progress reaches the log as it goes
        env.merge(PackedApp.environment(binary: program)) { _, packed in packed }
        return env
    }

    /// Every call names the tokens' file first.
    static func arguments(_ command: [String]) -> [String] {
        ["--auth-config-path", authFile.path] + command
    }

    /// Runs gogdl and waits for it. JSON comes on stdout, its log on stderr.
    static func run(_ command: [String], program: URL? = nil, timeout: TimeInterval = 120) async throws -> Legendary.Output {
        let binary: URL
        if let program {
            binary = program
        } else {
            binary = try await self.program()
        }
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        return try await PackedApp.run(binary, arguments: arguments(command), directory: configDir, timeout: timeout) {
            environment(program: binary)
        }
    }

    /// The line a download's log ends with: gogdl itself says nothing when it's done, so the shell
    /// it runs in writes how it ended – also when Nightforge was quit meanwhile.
    static let endMark = "Nightforge: gogdl ended with "

    /// Starts gogdl without waiting (a download, which carries on after Nightforge quits), its
    /// output and how it ended into `log`.
    static func start(_ command: [String], log: URL) async throws -> DetachedProcess {
        let binary = try await program()
        if !PackedApp.knowsHowToRun(binary) { _ = try? await run(["--version"], program: binary) }
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let process = DetachedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #""$0" "$@"; echo "\#(endMark)$?""#, binary.path] + arguments(command)
        process.environment = environment(program: binary)
        process.currentDirectoryURL = configDir
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// gogdl downloads running, also from an earlier Nightforge, by product ID.
    static func runningDownloads() -> Set<String> {
        let root = ComponentStore.shared.root.appendingPathComponent(componentID, isDirectory: true)
        return Set(Engine.ownProcesses(under: root).compactMap { process in
            let words = process.command.split(separator: " ")
            guard let index = words.firstIndex(where: { ["download", "update", "repair"].contains($0) }), index + 1 < words.count
            else { return nil }
            return String(words[index + 1])
        })
    }

    // MARK: - What gogdl says

    /// gogdl ran and answered: its answers are JSON ("null" too). Nothing, or no JSON, with an
    /// error code: it didn't get that far.
    static func answered(_ result: Legendary.Output) -> Bool {
        (try? JSONSerialization.jsonObject(with: result.output, options: .fragmentsAllowed)) != nil
    }

    /// What goes into `authLog`: gogdl's exit code, what kind of answer it gave and its log, with
    /// `secrets` and whatever looks like a token or code blanked out.
    static func authLogText(_ result: Legendary.Output, command: String, hiding secrets: [String], at date: Date = Date()) -> String {
        var log = result.log
        for secret in secrets where !secret.isEmpty { log = log.replacingOccurrences(of: secret, with: "…") }
        log = log.replacingOccurrences(of: #"((?:access_token|refresh_token|id_token|session_id|code)["']?\s*[:=]\s*["']?)[^"'\s,&}]+"#,
                                       with: "$1…", options: .regularExpression)
        let answer: String
        switch (try? JSONSerialization.jsonObject(with: result.output, options: .fragmentsAllowed)) {
        case let object as [String: Any] where object["access_token"] != nil: answer = "credentials"
        case let object as [String: Any]: answer = "JSON with " + object.keys.sorted().joined(separator: ", ")
        case is NSNull: answer = "null"
        case .some: answer = "other JSON"
        case nil: answer = "none (\(result.output.count) bytes, not JSON)"
        }
        let stamp = ISO8601DateFormatter().string(from: date)
        return "\(stamp) gogdl \(command) ended with \(result.status)\nanswer: \(answer)\n\n\(log)"
    }

    static func writeAuthLog(_ result: Legendary.Output, command: String, hiding secrets: [String] = []) {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try? Data(authLogText(result, command: command, hiding: secrets).utf8).write(to: authLog, options: .atomic)
    }

    /// A download's state from its log: how far, how fast, how long still, and how it ended.
    struct Progress: Equatable {
        var fraction: Double?
        /// Bytes per second over the last second (gogdl's "raw" download speed).
        var speed: Double?
        var secondsLeft: Int?
        /// What it writes to disk in all.
        var total: Int64?
        /// gogdl ended: its exit code (0 when it's done).
        var exitCode: Int32?
        /// Why it stopped, when it did.
        var failure: String?

        var finished: Bool { exitCode == 0 }
    }

    /// gogdl logs "[PROGRESS] INFO: = Progress: 12.34 1234/10000, Running for: 00:00:10, ETA:
    /// 00:01:00" and " + Download\t- 1.23 MiB/s (raw) / …" every second; the shell adds how it ended.
    static func progress(inLog text: String) -> Progress {
        var progress = Progress()
        var lastError: String?
        var noSpace = false
        for line in text.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: "= Progress: ") {
                let rest = line[range.upperBound...]
                if let percent = Double(rest.prefix { $0.isNumber || $0 == "." }) { progress.fraction = min(max(percent / 100, 0), 1) }
                if let slash = rest.split(separator: ",").first?.split(separator: " ").last?.split(separator: "/"), slash.count == 2,
                   let total = Int64(slash[1]), total > 0 {
                    progress.total = total
                }
                if let eta = line.range(of: "ETA: ") { progress.secondsLeft = seconds(String(line[eta.upperBound...].prefix(8))) }
            } else if let range = line.range(of: "+ Download") {
                let rest = line[range.upperBound...].drop { !$0.isNumber }
                if let mib = Double(rest.prefix { $0.isNumber || $0 == "." }) { progress.speed = mib * 1_048_576 }
            } else if let range = line.range(of: endMark) {
                progress.exitCode = Int32(line[range.upperBound...].trimmingCharacters(in: .whitespaces))
            } else if line.contains("Not enough disk space") {
                noSpace = true
            } else if line.contains("ERROR:") || line.contains("CRITICAL:") {
                lastError = String(line.split(separator: ":", maxSplits: 1).last ?? line).trimmingCharacters(in: .whitespaces)
            }
        }
        if let code = progress.exitCode {
            if code == 0 {
                progress.fraction = 1
            } else {
                progress.failure = noSpace ? L10n.t("there isn't enough space on the Mac")
                    : lastError ?? L10n.t("gogdl stopped (code %d)", code)
            }
        }
        return progress
    }

    private static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// The start and the end of a log are enough: how it began and how far it is.
    static func logText(for id: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: log(for: id)) else { return "" }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 16_384)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
        let tail = (try? handle.readToEnd()) ?? Data()
        return String(decoding: head, as: UTF8.self) + "\n" + String(decoding: tail, as: UTF8.self)
    }
}

enum GOGError: LocalizedError {
    case unavailable
    case signInFailed
    /// gogdl itself didn't run (`GOGAuth.helperFailed`): GOG never saw the sign-in.
    case helperFailed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.t("GOG support isn't in the component list yet. Check your internet connection and try again.")
        case .signInFailed:
            return L10n.t("GOG didn't accept the sign-in. Please try again.")
        case .helperFailed:
            return L10n.t("Nightforge's GOG helper didn't start, so the sign-in didn't reach GOG. Please try again.")
        case .failed(let reason):
            return reason
        }
    }
}
