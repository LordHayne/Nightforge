import Foundation

/// What Steam's bootstrapper is doing, from its log (logs/bootstrap_log.txt): every start writes a
/// block beginning "Startup - updater built …", and an update downloads, installs and commits in it.
/// While it installs, Steam's files must be left alone and Steam must not be restarted: the install
/// writes Valve's steamwebhelper back, and swapping in the wrapper then (with the restart it leads
/// to) cuts the install off – Steam starts over with "installed version 0", every 13 s, for as long
/// as that goes on (a fresh prefix, 29.10.2026: 124 times in 30 minutes).
///
/// Only the markers Steam doesn't translate count; "Paket wird extrahiert …" and the like change
/// with Steam's language.
enum SteamBootstrap: Equatable {
    /// No update under way in the newest block: the client runs, or Steam is off.
    case idle
    /// A new client version is coming down.
    case downloading
    /// The update is being unpacked and installed.
    case installing
    /// An update went in; the bootstrapper ends and starts again as the new version.
    case updated

    /// Whether steamwebhelper.exe may be swapped for the wrapper: not while an update comes down or
    /// goes in.
    var allowsHelperSwap: Bool { self == .idle || self == .updated }

    /// The bootstrapper's state from its log's text (the tail is enough: the newest block counts).
    init(log text: String) {
        let messages = (Self.blocks(text).last ?? []).map(Self.message)
        func last(_ test: (Substring) -> Bool) -> Int? { messages.lastIndex(where: test) }

        let install = last { line in
            ["uninstalled manifest found", "Found pending update", "Bad NTFS transaction canary"].contains { line.contains($0) }
        }
        let committed = last { $0.hasPrefix("Committing NTFS transaction") }
        let shutdown = last { $0 == "Shutdown" }
        if let install {
            self = [committed, shutdown].contains { ($0 ?? -1) > install } ? .updated : .installing
            return
        }
        // "Downloading manifest: …" asks whether there's a new version; "Downloaded new manifest:
        // /client/steam_client_win32 version 1769731672, installed version 0, …" says there is,
        // "Download skipped: …" and "Nothing to do" that there's none.
        let manifest = last { line in
            ["Downloading manifest", "Downloaded new manifest", "Download skipped"].contains { line.hasPrefix($0) } || line == "Nothing to do"
        }
        if let manifest, messages[manifest].hasPrefix("Downloading manifest") || Self.newVersion(messages[manifest]),
           (shutdown ?? -1) < manifest {
            self = .downloading
        } else {
            self = .idle
        }
    }

    /// Reads the end of Steam's bootstrap log; no log yet is `.idle`.
    init(steamRoot: URL) {
        self.init(log: Self.log(steamRoot: steamRoot))
    }

    /// The end of Steam's bootstrap log (empty without one).
    static func log(steamRoot: URL) -> String {
        tail(of: steamRoot.appendingPathComponent("logs/bootstrap_log.txt"))
    }

    /// The log's blocks, one per start from its "Startup - updater built" (whatever comes before
    /// the first is a block too). Steam writes Windows line ends: "\r\n" is one Character, so this
    /// splits on any newline.
    private static func blocks(_ text: String) -> [[Substring]] {
        var blocks: [[Substring]] = [[]]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.contains("Startup - updater built") { blocks.append([]) }
            blocks[blocks.count - 1].append(line)
        }
        return blocks
    }

    /// The newest start has checked Steam's files, or was told not to, and nothing is being
    /// installed: the wrapper can go in now and stays. Not before that check: without
    /// -noverifyfiles – the start Steam makes itself after its update has none – it put Valve's
    /// helper back, also over a wrapper of the same size and date (29.10.2026, a scratch prefix).
    /// Right after it the client starts its browser, about half a second later; swapped in that
    /// moment, the browser it started was the wrapper's, and no restart was needed.
    static func verified(log text: String) -> Bool {
        guard SteamBootstrap(log: text) == .idle else { return false }
        let messages = (blocks(text).last ?? []).map(message)
        return messages.contains("Verification complete") || messages.contains("Verification skipped")
    }

    /// The moment for the 64-bit client's packages (SteamPrefetch): the 32-bit step's install is
    /// through – its clean-up, right before its "Shutdown", deletes every package file there is,
    /// fetched ahead or not (29.10.2026, a scratch prefix) – and no start since has looked for its
    /// packages yet. The next bootstrapper does so about a second after that "Shutdown".
    static func clientPackagesDue(log text: String) -> Bool {
        let blocks = blocks(text)
        guard let done = blocks.lastIndex(where: { block in
            let messages = block.map(message)
            return messages.contains { $0.hasPrefix("uninstalled manifest found") && $0.contains("steam_client_win32") }
                && messages.contains("Shutdown")
        }) else { return false }
        return !blocks[(done + 1)...].joined().contains { line in
            let message = message(line)
            return ["Downloaded new manifest", "Download skipped", "Package file"].contains { message.hasPrefix($0) }
        }
    }

    /// The last 128 KB of a log: a bootstrap block with a whole download is ~30 KB (a line per
    /// package and per progress step). Empty when there's no log.
    fileprivate static func tail(of log: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 131_072 ? end - 131_072 : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// "2026-10-29 20:58:53" from "[2026-10-29 20:58:53] …".
    private static func stamp(_ line: Substring) -> Substring? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return line[line.index(after: line.startIndex)..<close]
    }

    /// Steam has stopped moving: its log hasn't changed for `quiet` seconds, and it was started at
    /// least that long ago. An install is quiet for a while (unpacking several hundred MB under Wine)
    /// and is given five minutes before it counts as hung; anything else 90 s, as before. Without a
    /// client yet, a bootstrapper that hasn't asked for one never will: started with -noverifyfiles,
    /// the first start of each bootstrapper skipped its check and sat there until the 90 s were up
    /// (29.10.2026, twice) – it's started again after 15 s. With the client there, a start whose
    /// client never came up (`clientStarted`) hung: its browser launched, then nothing for 90 s
    /// (29.10.2026, 20:57:19) – it's started again after 20 s.
    func stalled(quietFor quiet: TimeInterval, sinceRestart: TimeInterval, clientInstalled: Bool,
                 clientStarted: Bool = true) -> Bool {
        if self == .idle, !clientInstalled { return quiet > 15 && sinceRestart > 15 }
        if self == .idle, !clientStarted { return quiet > 20 && sinceRestart > 20 }
        return quiet > (self == .installing ? 300 : 90) && sinceRestart > 90
    }

    /// The newest start's client came up: console_log.txt has a "Client version" line from that
    /// start on (the bootstrap log's last "Startup - updater built"). Both logs stamp their lines
    /// "[2026-10-29 20:58:53]" from the same clock, so the stamps compare as text. Without a start
    /// in the log, nothing is known: true.
    static func clientStarted(bootstrapLog: String, consoleLog: String) -> Bool {
        guard let start = bootstrapLog.split(whereSeparator: \.isNewline).last(where: { $0.contains("Startup - updater built") }),
              let since = stamp(start)
        else { return true }
        return consoleLog.split(whereSeparator: \.isNewline).contains { line in
            line.contains("Client version") && (stamp(line).map { $0 >= since } ?? false)
        }
    }

    static func clientStarted(steamRoot: URL) -> Bool {
        clientStarted(bootstrapLog: tail(of: steamRoot.appendingPathComponent("logs/bootstrap_log.txt")),
                      consoleLog: tail(of: steamRoot.appendingPathComponent("logs/console_log.txt")))
    }

    /// Valve's own steamwebhelper still runs: one started before the wrapper went in (`swappedAt`)
    /// came from Valve's file, and Steam's window stays black until Steam is restarted. The
    /// wrapper's own process has the same name but starts later (and starts
    /// steamwebhelper_real.exe). A process whose start isn't known doesn't count: restarting for
    /// it again and again would be worse.
    static func unwrappedHelperRunning(_ processes: [(command: String, started: Date?)], swappedAt: Date) -> Bool {
        processes.contains { process in
            process.command.lowercased().contains("steamwebhelper.exe") && (process.started.map { $0 < swappedAt } ?? false)
        }
    }

    /// Steam's browser among processes (Wine shows the Windows command line): Valve's
    /// steamwebhelper.exe with its GPU and renderer processes, or the wrapper and
    /// steamwebhelper_real.exe – not Steam's client.
    static func webHelperProcesses(_ processes: [(pid: pid_t, command: String)]) -> [pid_t] {
        processes.filter { $0.command.lowercased().contains(#"\steamwebhelper"#) }.map(\.pid)
    }

    /// Steam's client is in place: its first update has put the 64-bit client there (the
    /// bootstrapper first installs steam_client_win32, then steam_client_win64). Any client
    /// manifest besides the 32-bit step's counts, should Valve name the next one differently.
    static func clientInstalled(steamRoot: URL) -> Bool {
        let package = steamRoot.appendingPathComponent("package", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: package.path)) ?? []
        return names.contains { $0.hasPrefix("steam_client_") && $0.hasSuffix(".installed") && $0 != "steam_client_win32.installed" }
    }

    /// Steam isn't running any more and should be started again. Right after an update the
    /// bootstrapper starts itself again as the new version, which under Wine took up to 25 s
    /// (23.10.2026) – starting a second Steam meanwhile would cut that off.
    func gone(steamRunning: Bool, sinceRestart: TimeInterval, quietFor quiet: TimeInterval) -> Bool {
        guard !steamRunning, sinceRestart > 15 else { return false }
        return self != .updated || quiet > 60
    }

    /// A log line without its "[2026-10-29 19:34:12] " in front.
    private static func message(_ line: Substring) -> Substring {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return line }
        return line[line.index(after: close)...].drop { $0 == " " }
    }

    /// "Downloaded new manifest: … version 1769731672, installed version 0, …": a version other
    /// than the installed one (unreadable numbers count as new).
    private static func newVersion(_ message: Substring) -> Bool {
        guard message.hasPrefix("Downloaded new manifest") else { return false }
        let words = message.replacingOccurrences(of: ",", with: " ").split(separator: " ")
        guard let new = words.firstIndex(of: "version"), let installed = words.firstIndex(of: "installed"),
              words.indices.contains(new + 1), words.indices.contains(installed + 2)
        else { return true }
        return words[new + 1] != words[installed + 2]
    }
}

/// Steam's browser of the newest start (steamwebhelper; logs/webhelper.txt and cef_log.txt): its
/// launch, Chrome in it begun, through to its message loop. The first start after Valve's helper
/// had been ended hung in every live run (29.10.2026, five runs; 21:15:51 and 21:36:40 in the last
/// two): Chrome began – "This is Chrome version", "WSALookupServiceBegin failed" – and went no
/// further, while the next start got through in under a second. Replayed in a scratch prefix five
/// ways (cold and warm engine, ended early and late, with Nightforge's SIGKILL and Game Mode
/// loader) it never hung, so the cause stays open; the setup restarts a hung browser early instead.
struct SteamBrowser: Equatable {
    /// The newest "Startup - webhelper launched pid: …" line; nil before any.
    var launch: String?
    /// Chrome in it has begun: cef_log.txt's "This is Chrome version" from its pid, not older than the launch.
    var chromeStarted = false
    /// Through to its message loop: it's up.
    var running = false

    init(webhelperLog: String, cefLog: String) {
        let lines = webhelperLog.split(whereSeparator: \.isNewline)
        guard let start = lines.lastIndex(where: { $0.contains("Startup - webhelper launched") }) else { return }
        let launch = lines[start]
        self.launch = String(launch)
        running = lines[start...].contains { $0.contains("Starting message loop") }
        guard let pid = launch.range(of: "pid: ").map({ launch[$0.upperBound...].prefix(while: \.isNumber) }), !pid.isEmpty,
              let since = Self.cefStamp(launch)
        else { return }
        // "[404:408:1029/213640.648:WARNING:chrome_main_delegate.cc(748)] This is Chrome version …": pid,
        // thread, then month, day and time, the same clock as webhelper.txt's.
        chromeStarted = cefLog.split(whereSeparator: \.isNewline).contains { line in
            line.hasPrefix("[\(pid):") && line.contains("This is Chrome version")
                && (line.split(separator: ":").dropFirst(2).first.map { $0.prefix(11) >= since } ?? false)
        }
    }

    init(steamRoot: URL) {
        let logs = steamRoot.appendingPathComponent("logs", isDirectory: true)
        self.init(webhelperLog: SteamBootstrap.tail(of: logs.appendingPathComponent("webhelper.txt")),
                  cefLog: SteamBootstrap.tail(of: logs.appendingPathComponent("cef_log.txt")))
    }

    /// Hung: no message loop 5 s after Chrome began – it takes under one when it works (29.10.2026,
    /// live and in a scratch prefix) – or 15 s after the launch when Chrome never began (what comes
    /// before it took 5 s at most, with nothing cached yet). The times are since the setup saw each.
    func hung(sinceLaunch: TimeInterval, sinceChrome: TimeInterval?) -> Bool {
        guard launch != nil, !running else { return false }
        if chromeStarted, let sinceChrome { return sinceChrome > 5 }
        return sinceLaunch > 15
    }

    /// "1029/213640", as cef_log.txt stamps, from webhelper.txt's "[2026-10-29 21:36:40] …".
    private static func cefStamp(_ line: Substring) -> String? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let parts = line[line.index(after: line.startIndex)..<close].split { $0 == "-" || $0 == " " || $0 == ":" }
        guard parts.count == 6 else { return nil }
        return "\(parts[1])\(parts[2])/\(parts[3])\(parts[4])\(parts[5])"
    }

    /// When the setup first saw the newest launch, and Chrome in it begin; a launch from before
    /// Nightforge's latest start of Steam isn't this start's and doesn't count.
    struct Watch {
        private var launch: String?
        private var launchSeen = Date()
        private var chromeSeen: Date?
        private var stale: String?
        private var endedAt: Date?
        /// This start of Steam has launched a browser: its client is up.
        private(set) var seen = false

        /// Right before Nightforge starts Steam: the browser launched so far is an earlier one's.
        mutating func ignore(_ launch: String?) {
            stale = launch
            endedAt = nil
            seen = false
        }

        /// The setup has ended this browser (Engine.endWebHelpers); Steam's client starts the next.
        mutating func ended(_ browser: SteamBrowser, now: Date = Date()) {
            stale = browser.launch
            endedAt = now
        }

        mutating func hung(_ browser: SteamBrowser, now: Date = Date()) -> Bool {
            guard let current = browser.launch, current != stale else { return false }
            seen = true
            endedAt = nil
            if current != launch {
                launch = current
                launchSeen = now
                chromeSeen = nil
            }
            if browser.chromeStarted, chromeSeen == nil { chromeSeen = now }
            return browser.hung(sinceLaunch: now.timeIntervalSince(launchSeen), sinceChrome: chromeSeen.map { now.timeIntervalSince($0) })
        }

        /// The client hasn't started a browser again 25 s after the setup ended one (it took 8 s).
        func relaunchOverdue(_ browser: SteamBrowser, now: Date = Date()) -> Bool {
            guard let endedAt, browser.launch == stale else { return false }
            return now.timeIntervalSince(endedAt) > 25
        }
    }
}
