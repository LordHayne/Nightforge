import Foundation
import SystemConfiguration

/// What Wine, DXVK and MoltenVK print while Steam and its games run. Steam's output lands here
/// (Engine.startSteam) and its games inherit it. Nightforge reads it after a start that went
/// wrong, to fix what it recognises by itself, and for problem reports.
enum GameLog {
    static var url: URL { Engine.supportDir.appendingPathComponent("Logs/wine.log") }

    /// Wine's own messages that help: libraries a program can't load, and .NET without Mono.
    /// Everything else stays quiet – unless an engine test asks for more (`extraWineDebug`).
    static let wineDebug = "-all,err+module,err+mscoree" + (extraWineDebug.map { "," + $0 } ?? "")

    /// Wine debug channels an engine test adds, with `defaults write io.github.lordhayne.nightforge
    /// wineDebug -string "+loaddll,+timestamp,+pid,+tid"` (docs/TODO.md › Engine-Tests; there's no
    /// switch in the app). Read once per app run; the background Steam restarts for it
    /// (Engine.steamConfigSignature). Only channel lists count: letters, digits and + - , _.
    static let extraWineDebug = extraChannels(UserDefaults.standard.string(forKey: "wineDebug"))

    static func extraChannels(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.wholeMatch(of: #/[A-Za-z0-9+\-,_]+/#) != nil else { return nil }
        return value
    }

    /// Not a winetricks verb: Wine Mono, which Nightforge installs itself (Engine.installWineMono).
    static let wineMono = "wine-mono"

    /// A line of Nightforge's own, for problem reports and to see in a live test what happened.
    static func note(_ text: String) {
        let descriptor = open(url.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { return }
        FileHandle(fileDescriptor: descriptor, closeOnDealloc: true).write(Data(("info:  [nightforge] " + text + "\n").utf8))
    }

    /// For a Steam about to start: appends to the log, starting a fresh one when it has grown large.
    static func handleForSteam() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > 8_000_000 {
            let previous = url.deletingLastPathComponent().appendingPathComponent("wine.previous.log")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: url, to: previous)
        }
        // O_APPEND: an old Steam still shutting down and the new one both write to it.
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return descriptor < 0 ? nil : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Where the log ends now; what a launch prints comes after it.
    static func mark() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 ?? 0
    }

    static func text(since mark: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = mark <= end ? mark : 0  // a fresh log was started meanwhile
        try? handle.seek(toOffset: max(start, end > 4_000_000 ? end - 4_000_000 : 0))
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// The game died on a processor instruction Rosetta doesn't run – what a game does that takes
    /// Rosetta's AVX hint (`ROSETTA_ADVERTISE_AVX`) at its word on a path Rosetta lacks. Wine says
    /// so in the log; Unreal games catch it themselves and leave a crash report in their folder.
    static func illegalInstruction(since mark: UInt64, installDir: URL, startedAt: Date) -> Bool {
        illegalInstruction(in: text(since: mark)) || unrealCrashes(in: installDir, since: startedAt).contains {
            ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains("EXCEPTION_ILLEGAL_INSTRUCTION")
        }
    }

    /// A Windows program crashed: Wine says "wine: Unhandled page fault on …", "wine: Unhandled
    /// exception …" (and starts its debugger). The log is shared, so it may be another program of
    /// the session – good enough as one sign among others (LaunchHealth.earlyEnd).
    static func crashed(in text: String) -> Bool {
        text.contains("wine: Unhandled ") || text.contains("Unhandled exception:")
    }

    static func illegalInstruction(in text: String) -> Bool {
        text.lowercased().contains("unhandled illegal instruction") || text.contains("EXCEPTION_ILLEGAL_INSTRUCTION")
    }

    /// Unreal's crash reports (…/Saved/Crashes/<id>/CrashContext.runtime-xml) written since `date`.
    static func unrealCrashes(in installDir: URL, since date: Date) -> [URL] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: installDir, includingPropertiesForKeys: [.contentModificationDateKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let file as URL in files {
            if files.level > 5 { files.skipDescendants(); continue }
            guard file.lastPathComponent == "CrashContext.runtime-xml",
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= date
            else { continue }
            found.append(file)
        }
        return found
    }

    /// Runtimes (winetricks verbs) a game's programs needed and didn't find, since `mark`.
    static func missingRuntimes(since mark: UInt64, gameFolder: String) -> [String] {
        missingRuntimes(in: text(since: mark), gameFolder: gameFolder)
    }

    static func missingRuntimes(in text: String, gameFolder: String) -> [String] {
        var verbs: [String] = []
        let folder = gameFolder.lowercased()
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            let dll: Substring?
            if lower.contains("import_dll"), lower.contains("not found") || lower.contains("failed"),
               lower.contains(folder) || !lower.contains("which is needed by") {
                // err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\…\\Game.exe") not found
                dll = lower.range(of: "library ").map { lower[$0.upperBound...].prefix { $0 != " " } }
            } else if lower.contains("wine mono is not installed") || lower.contains("install mono for windows") {
                if !verbs.contains(wineMono) { verbs.append(wineMono) }
                dll = nil
            } else if let range = lower.range(of: "unimplemented function ") {
                // wine: Call from … to unimplemented function msvcp140.dll.?_Xbad_alloc@std@@YAXXZ, aborting
                let function = lower[range.upperBound...]
                dll = function.range(of: ".dll").map { function[..<$0.upperBound] }
            } else {
                dll = nil
            }
            if let dll, let verb = winetricksVerb(forDLL: String(dll)), !verbs.contains(verb) { verbs.append(verb) }
        }
        return verbs
    }

    /// Which winetricks verb installs a Windows library Wine lacks or only half implements.
    static func winetricksVerb(forDLL dll: String) -> String? {
        let name = dll.lowercased()
        let table: [(prefixes: [String], verb: String)] = [
            (["msvcp140", "vcruntime140", "concrt140", "vcomp140", "mfc140", "vccorlib140"], "vcrun2022"),
            (["msvcp120", "msvcr120", "vcomp120", "mfc120"], "vcrun2013"),
            (["msvcp110", "msvcr110", "vcomp110", "mfc110"], "vcrun2012"),
            (["msvcp100", "msvcr100", "vcomp100", "mfc100"], "vcrun2010"),
            (["msvcp90", "msvcr90", "mfc90"], "vcrun2008"),
            (["d3dx9_"], "d3dx9"),
            (["d3dx10_"], "d3dx10"),
            (["d3dx11_"], "d3dx11_43"),
            (["d3dcompiler_43"], "d3dcompiler_43"),
            (["d3dcompiler_47"], "d3dcompiler_47"),
            (["xinput1_3"], "xinput"),
            (["physxloader", "physxcore", "physxcooking"], "physx"),
            (["openal32"], "openal"),
        ]
        return table.first { entry in entry.prefixes.contains { name.hasPrefix($0) } }?.verb
    }

    /// Whether the Direct3D layer gave up since `mark`: DXVK couldn't create its device or its
    /// buffers on MoltenVK. The game then shows its own error box ("Failed to create D3D device")
    /// and stays open, so running past its first seconds doesn't mean it started.
    static func graphicsFailed(since mark: UInt64, layer: GraphicsLayer) -> Bool {
        graphicsFailed(in: text(since: mark), layer: layer)
    }

    /// The signs are DXVK's, so they count only for a start on DXVK: the log is shared, and on
    /// another way they aren't the game's renderer failing. A WineD3D start of Mafia II (1.11.2026)
    /// was ended over two such lines and moved on to DXVK, which never gets a device on MoltenVK.
    static func graphicsFailed(in text: String, layer: GraphicsLayer) -> Bool {
        layer == .dxvk && graphicsFailed(in: text)
    }

    static func graphicsFailed(in text: String) -> Bool {
        let signs = ["dxvkadapter: failed to create device", "dxvkbuffer: failed to create buffer"]
        let lower = text.lowercased()
        return signs.contains { lower.contains($0) }
    }

    /// A log line without what identifies the player or lets anyone in as them: the Mac's home
    /// folder, the account name in Windows and prefix paths (C:\users\<name>, which Wine's own
    /// messages print as C:\\users\\<name>; drive_c/users/<name>) and anywhere else as a word, the
    /// names of external drives (often their owner's: /Volumes/<name>, Z:\Volumes\<name>), the Mac's
    /// computer and host names (Steam's LOCAL_HOSTNAME=…), macOS's per-account temp folder, Steam
    /// account ids, GOG user ids, the sign-in arguments a store hands a game (Epic's -AUTH_PASSWORD
    /// exchange code, -epicusername), tokens and e-mail addresses. A heuristic: what it misses is in
    /// whatever the line goes into, which is why log lines stay out of report links (ProblemReportText).
    static func redacted(_ line: String, home: String = NSHomeDirectory(), user: String = NSUserName(),
                         machine: [String] = machineNames) -> String {
        var text = home.isEmpty ? line : line.replacingOccurrences(of: home, with: "~")
        for (pattern, template) in drivePatterns {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        for name in machine {
            text = text.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}_])"#,
                                             with: "<computer>", options: .regularExpression)
        }
        if !user.isEmpty {
            // One, two or no backslashes between the parts, or a slash; not "users\thomasine".
            text = text.replacingOccurrences(of: #"(?i)\b(users)(\\{1,2}|/)"# + NSRegularExpression.escapedPattern(for: user) + #"(?![\p{L}\p{N}_])"#,
                                             with: "$1$2<user>", options: .regularExpression)
        }
        for (pattern, template) in secretPatterns {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        if user.count >= 3 {
            // The account name in other programs' lines ("uid 501 (jane)", "owner jane"), as a word only –
            // last, so an e-mail address or a sign-in argument is recognised whole first.
            text = text.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}_<])"# + NSRegularExpression.escapedPattern(for: user) + #"(?![\p{L}\p{N}_>])"#,
                                             with: "<user>", options: .regularExpression)
        }
        return text
    }

    /// Paths that name the Mac's drives and its account's temp folder: an external drive's name up to
    /// the next separator (Steam writes Z:\Volumes\<name>\…, Wine's messages Z:\\Volumes\\<name>), and
    /// macOS's /var/folders/<xx>/<id>, which is one account's.
    private static let drivePatterns: [(String, String)] = [
        (#"(/Volumes/)[^/\\\n"'<>]+"#, "$1<drive>"),
        (#"(?i)(\\{1,2}Volumes\\{1,2})[^\\/\n"'<>]+"#, "$1<drive>"),
        // Not one done already ("/var/folders/<id>/T/…"): redacting twice must change nothing (GameTest.leaks).
        (#"(/(?:private/)?var/folders/)(?!<id>)[^/\s"']+/[^/\s"']+"#, "$1<id>"),
    ]

    /// The Mac's names as other programs print them: its computer name ("Jane’s MacBook Pro"), its
    /// host name with and without ".local", and the NetBIOS name Wine makes of it (upper case, at
    /// most 15 characters) – each at least 3 characters long, so a shorter one doesn't eat words.
    /// Read again once they're 10 s old, so each report has the names of its moment: one a network
    /// (DHCP) changed since Nightforge started is no longer readable in it.
    static var machineNames: [String] {
        machineNamesRead.withLock { read in
            if let read, Date().timeIntervalSince(read.at) < 10 { return read.names }
            var names: [String] = []
            if let computer = SCDynamicStoreCopyComputerName(nil, nil) as String? { names.append(computer) }
            var buffer = [CChar](repeating: 0, count: 256)
            if gethostname(&buffer, buffer.count) == 0 {
                let host = String(cString: buffer)
                let short = host.split(separator: ".").first.map(String.init) ?? host
                names += [host, short, String(short.prefix(15))]
            }
            read = (Date(), machineNameList(names))
            return read!.names
        }
    }

    private static let machineNamesRead = LockedValue<(at: Date, names: [String])?>(nil)

    /// `names` without repeats (ignoring case) and short ones, the longest first so a longer name
    /// is replaced whole before a shorter one that's part of it.
    static func machineNameList(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { $0.count >= 3 && seen.insert($0.lowercased()).inserted }.sorted { $0.count > $1.count }
    }

    /// Patterns for `redacted`, in order. The sign-in arguments Epic's launcher parameters bring
    /// (and legendary passes on to the game) come first: quoted as a whole when the value holds a
    /// space ("-epicusername=Jane Doe"), then bare or with the value in quotes.
    private static let secretPatterns: [(String, String)] = {
        let epic = "(?:AUTH_PASSWORD|AUTH_LOGIN|epicusername|epicuserid)"
        let words = "access_token|refresh_token|id_token|session_id|sessionid|exchange_code|exchangecode|authorization_code|auth_code"
            + "|client_secret|api_key|apikey|password|passwd|secret|token"
        return [
            (#"(?i)("\s*-{1,2}"# + epic + #"\s*=)[^"]*""#, "$1<hidden>\""),
            (#"(?i)(-{1,2}"# + epic + #"\s*=)(?:"[^"]*"|[^\s"]*)"#, "$1<hidden>"),
            // JSON, key=value and key: value, also a quoted key ("refresh_token": "…").
            (#"(?i)(?<![A-Za-z0-9])("# + words + #")(["']?\s*[:=]\s*["']?)[^"'\s,&}]+"#, "$1$2<hidden>"),
            (#"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/=-]{8,}"#, "$1<hidden>"),
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"#, "<email>"),
            // Steam: the friend code, the 64-bit ID and the account number in userdata\<number>.
            (#"\[U:1:\d+\]"#, "<steam id>"),
            (#"\b7656119\d{10}\b"#, "<steam id>"),
            (#"(?i)(\buserdata(?:\\{1,2}|/))\d{3,}"#, "$1<steam id>"),
            // GOG: the user id in galaxy-library.gog.com/users/<id>/… and in gogdl's JSON.
            (#"(?i)(\busers/)\d{6,}"#, "$1<gog user>"),
            (#"(?i)(?<![A-Za-z0-9])((?:galaxy_?)?user_?id)(["']?\s*[:=]\s*["']?)\d{6,}"#, "$1$2<gog user>"),
        ]
    }()

    /// The error lines since `mark`, for a problem report: Wine, DXVK and MoltenVK errors, without
    /// repeats and with the Mac's home folder left out.
    static func errors(since mark: UInt64, limit: Int = 30) -> [String] {
        errors(in: text(since: mark), limit: limit)
    }

    static func errors(in text: String, limit: Int = 30) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard lower.contains(":err:") || lower.contains("mvk-error") || lower.hasPrefix("err:")
                || lower.hasPrefix("wine:") || lower.contains("unhandled")
            else { continue }
            // Thread ids ("0124:err:…") differ between otherwise equal lines.
            var cleaned = String(line)
            if line.count > 5, line.prefix(4).allSatisfy(\.isHexDigit), line.dropFirst(4).first == ":" {
                cleaned = String(line.dropFirst(5))
            }
            cleaned = redacted(cleaned)
            if seen.insert(cleaned).inserted { result.append(cleaned) }
        }
        return Array(result.suffix(limit))
    }
}
