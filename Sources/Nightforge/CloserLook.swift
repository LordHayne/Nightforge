import Foundation

/// A closer look at a start that ended and left nothing that says why (docs/ENTWURF-STARTREZEPT.md 3.2,
/// step C). Metal Gear Solid V, 11.11.2026: "Failed to load SteamAPI" on every graphics way, no dump, no
/// log line. The cause showed only with Wine's channels for signature checks on, set by hand: WinVerifyTrust
/// answered 800b0109 for the game's steam_api64.dll. So the starts after such an end carry these channels
/// by themselves, and what they print is read here – text only, no debugger, nothing of the game touched.
/// Never for a game with an anti-cheat (the caller leaves those out, as with the rest of the diagnosis).
enum CloserLook {
    /// What a closer look adds to GameLog.wineDebug: each line's process (+pid), the libraries a process
    /// loads, what a program puts out for a debugger, signature checks with their certificate chains, and
    /// the texts of message boxes.
    static let channels = "+pid,+loaddll,warn+debugstr,+wintrust,+chain,+msgbox"

    /// WINEDEBUG of a start that looks closer.
    static var wineDebug: String { GameLog.wineDebug + "," + channels }

    /// The part of them every start carries (step E5 of docs/ENTWURF-STARTREZEPT.md 3.3, the player's
    /// decision of 14.11.2026): each line's process, the libraries a process loads, and the texts of message
    /// boxes. With them a game's error box is read at its first failed start, and what it loaded tells what
    /// it draws with. They print at a process's start and when a box opens, not while a game runs: Alan
    /// Wake's start on 14.11.2026 came to 88 such lines, 10 KB; the measuring run of that evening, 20 games
    /// in 81 minutes with +pid,+loaddll on, to 6,888 lines of them, 866 KB of its 2.9 MB. What a game puts out
    /// for a debugger and certificate chains stay a closer look's: a game can write the first with every
    /// frame, and Steam's browser builds chains as long as it runs (3,204 of the 4,423 lines of Batman's
    /// start with all channels on).
    static let everyStart = "+pid,+loaddll,+msgbox"

    /// WINEDEBUG of a start without a closer look: GameLog.wineDebug and `everyStart`. What Steam and every
    /// game start with (Engine.gameEnvironment, Engine.wineDebug).
    static var usualWineDebug: String { GameLog.wineDebug + "," + everyStart }

    /// An engine test's switch: every start carries the channels, with `defaults write
    /// io.github.lordhayne.nightforge closerLook -bool true` (docs/TODO.md › Engine-Tests; there's no
    /// switch in the app). Read once per app run, like GameLog.extraWineDebug. The first start restarts
    /// Steam for it; the log grows fast, so `defaults delete io.github.lordhayne.nightforge closerLook` after.
    static let always = UserDefaults.standard.bool(forKey: "closerLook")

    // MARK: - What a start with the channels printed

    /// A signature check (WinVerifyTrust) that didn't answer 0.
    struct Signature: Equatable {
        /// "steam_api64.dll": the checked file without its folder; nil when the check named none.
        var file: String?
        var code: UInt32
        /// From the last chain completed before the answer: whom it was issued to, and its self-signed element.
        var signer: String?
        var root: String?
        /// That chain's status says so (CERT_TRUST_IS_UNTRUSTED_ROOT, 0x20).
        var untrustedRoot = false
    }

    /// CERT_E_UNTRUSTEDROOT.
    static let untrustedRootCode: UInt32 = 0x800B_0109

    /// The common answers of a signature check, in words.
    static func meaning(of code: UInt32) -> String? {
        switch code {
        case untrustedRootCode: return "its root isn't trusted"
        case 0x800B_0100: return "no signature"
        case 0x8009_6010: return "the file doesn't match its signature"
        case 0x800B_0101: return "expired"
        case 0x800B_010A: return "its chain can't be built"
        default: return nil
        }
    }

    /// What the game's own processes printed. A process is the game's when it loaded a file from the
    /// game's folder; the log is shared with Steam and its helpers, whose lines stay out.
    struct Reading: Equatable {
        /// The log carried the channels at all: a library's load named its process.
        var channelsOn = false
        var signatures: [Signature] = []
        /// The last lines the game put out for a debugger (OutputDebugString), oldest first.
        var debugOutput: [String] = []
        /// The texts of its message boxes: the game's error window, when it is one of Windows' own.
        var boxes: [String] = []
        /// The text of its last message box, when the process that showed it loaded nothing after it: the
        /// window the game ended at, if it ended. A game that goes on after a box loads more.
        var endedAtBox: String?
        /// The Direct3D, OpenGL and Vulkan libraries it loaded, in the order they came.
        var graphics: [String] = []
        /// The last libraries it loaded at all.
        var lastLibraries: [String] = []

        /// Direct3D 9 and nothing newer: what the game draws with, as far as loading says.
        var loadsOnlyDirect3D9: Bool {
            graphics.contains("d3d9.dll") && !graphics.contains { $0.hasPrefix("d3d10") || $0.hasPrefix("d3d11") || $0.hasPrefix("d3d12") }
        }
    }

    static let graphicsLibraries: Set<String> = [
        "ddraw.dll", "d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll",
        "dxgi.dll", "opengl32.dll", "vulkan-1.dll",
    ]

    /// One line of Wine's debug output: "0454:trace:wintrust:WinVerifyTrust (…)", with +pid
    /// "0810:0804:trace:loaddll:build_module Loaded …", with +timestamp a time before that.
    struct Line {
        /// Only with +pid.
        var pid: Substring?
        var thread: Substring
        var channel: Substring
        var function: Substring
        var text: Substring

        private static let classes: Set<Substring> = ["trace", "warn", "err", "fixme"]

        init?(_ line: Substring) {
            // A time below 100 s is padded with spaces ("%3u.%03u:").
            let line = line.drop { $0 == " " }
            guard let space = line.firstIndex(of: " ") else { return nil }
            let parts = line[..<space].split(separator: ":", omittingEmptySubsequences: false)
            guard let kind = parts.firstIndex(where: Self.classes.contains), parts.count == kind + 3 else { return nil }
            var ids = parts[..<kind]
            if ids.first?.contains(".") == true { ids = ids.dropFirst() }
            guard ids.count == 1 || ids.count == 2, ids.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isHexDigit) }) else { return nil }
            pid = ids.count == 2 ? ids.first : nil
            thread = ids[ids.index(before: ids.endIndex)]
            channel = parts[kind + 1]
            function = parts[kind + 2]
            text = line[line.index(after: space)...]
        }
    }

    /// Reads `log` (Wine's output since a start began) for the game in `gameFolder`, the name of its folder.
    /// Signature checks count when one of the game's processes made them or when they are of a file in the
    /// game's folder – the second also without +pid, as on 11.11.2026.
    static func read(_ log: String, gameFolder: String) -> Reading {
        var reading = Reading()
        let folder = "\\" + gameFolder.lowercased() + "\\"
        func inFolder(_ path: String) -> Bool { !gameFolder.isEmpty && path.lowercased().contains(folder) }

        // Wine hands a process id out again once enough of them are free (server/process.c, alloc_ptid: the one
        // free the longest first), and a Steam session lives long while its helpers come and go. So a process
        // is a pid from one start of its own (ntdll's load) to the next.
        var processes = 0
        var processOf: [Substring: Int] = [:]
        func process(_ pid: Substring) -> Int {
            if let known = processOf[pid] { return known }
            processOf[pid] = processes
            processes += 1
            return processes - 1
        }
        var loads: [(process: Int, name: String, inFolder: Bool)] = []
        var lastLoad: [Substring: Int] = [:]
        var said: [(process: Int, text: String)] = []
        /// `loads`: how many libraries had loaded when it opened.
        var boxes: [(process: Int, text: String, loads: Int)] = []

        // A signature check as it goes, by the thread that makes it.
        struct Check {
            var process: Int?
            var path: String?
            var elements: [(by: String, to: String?)] = []
            /// The last chain completed: its elements from the root to the signer, and its status.
            var chain: (elements: [(by: String, to: String?)], status: UInt32)?
        }
        var open: [String: Check] = [:]
        var checks: [(process: Int?, inFolder: Bool, signature: Signature)] = []

        for raw in log.split(whereSeparator: \.isNewline) {
            guard let line = Line(raw) else { continue }
            switch line.channel {
            case "loaddll":
                // …:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\kernel32.dll" at 00006FFFFFEB0000: builtin
                guard let pid = line.pid, line.text.hasPrefix("Loaded "), let path = unquoted(line.text) else { continue }
                reading.channelsOn = true
                let name = path.lowercased().split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path.lowercased()
                if line.function == "build_ntdll_module" {
                    // A new process: its program's load comes right before ntdll's and belongs to it.
                    let before = processOf[pid]
                    processOf[pid] = processes
                    processes += 1
                    if let before, let last = lastLoad[pid], loads[last].process == before, loads[last].name.hasSuffix(".exe") {
                        loads[last].process = processes - 1
                    }
                }
                lastLoad[pid] = loads.count
                loads.append((process(pid), name, inFolder(path)))
            case "debugstr":
                // OutputDebugStringW prints its text and hands it on to OutputDebugStringA: read once, there.
                guard line.function == "OutputDebugStringA", let pid = line.pid, let text = unquoted(line.text) else { continue }
                for part in text.split(whereSeparator: \.isNewline) {
                    let words = part.trimmingCharacters(in: .whitespaces)
                    if !words.isEmpty { said.append((process(pid), cut(words, to: 200))) }
                }
            case "msgbox":
                // …:trace:msgbox:MSGBOX_OnInit L"Failed to load SteamAPI" (dlls/user32/msgbox.c: the text, not the title).
                guard line.function == "MSGBOX_OnInit", let pid = line.pid, let text = unquoted(line.text) else { continue }
                let words = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
                if !words.isEmpty { boxes.append((process(pid), cut(words, to: 300), loads.count)) }
            case "wintrust", "chain":
                let thread = (line.pid.map { $0 + ":" } ?? "") + line.thread
                switch (line.function, line.text) {
                case ("WinVerifyTrust", let text) where text.hasPrefix("("):
                    open[thread] = Check(process: line.pid.map(process))
                case ("dump_file_info", let text) where text.hasPrefix("pcwszFilePath:"):
                    open[thread]?.path = unquoted(text)
                case ("CRYPT_CheckSimpleChain", let text) where text.hasPrefix("checking chain"):
                    open[thread]?.elements = []
                case ("dump_element", let text) where text.hasPrefix("issued by "):
                    if let name = unquoted(text) { open[thread]?.elements.append((name, nil)) }
                case ("dump_element", let text) where text.hasPrefix("issued to "):
                    if let count = open[thread]?.elements.count, count > 0 { open[thread]?.elements[count - 1].to = unquoted(text) }
                case ("CertGetCertificateChain", let text) where text.hasPrefix("error status:"):
                    guard let check = open[thread], let status = hex(text.dropFirst("error status:".count)) else { continue }
                    open[thread]?.chain = (check.elements, status)
                    open[thread]?.elements = []
                case ("WinVerifyTrust", let text) where text.hasPrefix("returning "):
                    // The caller's close call (dwStateAction 2) comes as a check of its own and answers 0.
                    guard let check = open.removeValue(forKey: thread), let code = hex(text.dropFirst("returning ".count)), code != 0 else { continue }
                    let file = check.path.flatMap { $0.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) }
                    let signature = Signature(file: file, code: code, signer: check.chain?.elements.last?.to,
                                              root: check.chain?.elements.first { $0.to == $0.by }?.by,
                                              untrustedRoot: (check.chain?.status ?? 0) & 0x20 != 0)
                    checks.append((check.process, check.path.map(inFolder) ?? false, signature))
                default:
                    continue
                }
            default:
                continue
            }
        }

        var game = [Bool](repeating: false, count: processes)
        for load in loads where load.inFolder { game[load.process] = true }
        let libraries = loads.filter { game[$0.process] }.map(\.name)
        reading.graphics = unique(libraries.filter(graphicsLibraries.contains))
        reading.lastLibraries = Array(libraries.suffix(5))
        // The last six lines, a repeated one where it came last.
        reading.debugOutput = unique(said.filter { game[$0.process] }.map(\.text).reversed()).prefix(6).reversed()
        reading.boxes = Array(unique(boxes.filter { game[$0.process] }.map(\.text)).suffix(3))
        if let last = boxes.last(where: { game[$0.process] }), !loads[last.loads...].contains(where: { $0.process == last.process }) {
            reading.endedAtBox = last.text
        }
        for check in checks where check.inFolder || check.process.map({ game[$0] }) == true {
            if !reading.signatures.contains(check.signature) { reading.signatures.append(check.signature) }
        }
        return reading
    }

    /// Each once, where it came first.
    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private static func cut(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length)) + "…" : text
    }

    /// "800b0109", " 00000020": a number as Wine prints it with %08lx.
    private static func hex(_ text: Substring) -> UInt32? {
        UInt32(text.trimmingCharacters(in: .whitespaces), radix: 16)
    }

    /// The first string in `text` as Wine's debug output quotes it (wine_dbgstr_an and wine_dbgstr_wn in
    /// include/wine/debug.h): "…" with every byte past ASCII as \xNN, L"…" with every UTF-16 unit past
    /// ASCII as \NNNN. Both escape \n \r \t \" \\ and end a string cut off at about 290 characters with
    /// "..." behind the closing quote. The bytes of a "…" are the program's own: UTF-8 mostly, else read
    /// as Windows' Western code page.
    static func unquoted(_ text: Substring) -> String? {
        let scalars = Array(text.unicodeScalars)
        guard let quote = scalars.firstIndex(of: "\"") else { return nil }
        let wide = quote > 0 && scalars[quote - 1] == "L"
        var units: [UInt16] = []
        var bytes: [UInt8] = []
        func put(_ scalar: Unicode.Scalar) {
            if wide { units.append(contentsOf: String(scalar).utf16) } else { bytes.append(contentsOf: String(scalar).utf8) }
        }
        func number(at start: Int, digits: Int) -> UInt32? {
            guard start + digits <= scalars.count else { return nil }
            var value: UInt32 = 0
            for scalar in scalars[start..<start + digits] {
                guard let digit = Character(scalar).hexDigitValue else { return nil }
                value = value << 4 | UInt32(digit)
            }
            return value
        }
        var index = quote + 1
        while index < scalars.count, scalars[index] != "\"" {
            let scalar = scalars[index]
            index += 1
            guard scalar == "\\", index < scalars.count else {
                put(scalar)
                continue
            }
            switch scalars[index] {
            case "n": put("\n"); index += 1
            case "r": put("\r"); index += 1
            case "t": put("\t"); index += 1
            case "\"": put("\""); index += 1
            case "\\": put("\\"); index += 1
            case "x" where !wide:
                if let byte = number(at: index + 1, digits: 2) {
                    bytes.append(UInt8(byte))
                    index += 3
                } else {
                    put(scalar)
                }
            default:
                if wide, let unit = number(at: index, digits: 4) {
                    units.append(UInt16(unit))
                    index += 4
                } else {
                    put(scalar)
                }
            }
        }
        let cutOff = index + 3 < scalars.count && scalars[(index + 1)...(index + 3)].allSatisfy { $0 == "." }
        let string = wide ? String(decoding: units, as: UTF16.self)
            : String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
        return cutOff ? string + "…" : string
    }

    // MARK: - A message box: a question or a notice

    enum Box: Equatable {
        /// The player can answer it either way, and the game's end after it can be the answer.
        case question
        /// It says something and has the player confirm it: nothing to choose.
        case notice
    }

    /// Words of a text that reports a failure, whatever it asks after that ("… has crashed. Send a report?").
    /// English, which such boxes mostly stay in, and German, which this Mac's prefix speaks.
    static let failureWords = [
        "error", "failed", "failure", "fatal", "crash", "could not", "couldn't", "cannot", "can't", "unable to", "exception",
        "fehler", "fehlgeschlagen", "abgestürzt", "konnte nicht", "kann nicht",
    ]

    /// What a message box's text is. Wine's channel prints the text alone, not the buttons, so the text
    /// decides: without a question mark it's a notice – a box that asks nothing has only OK to press – and so
    /// is one that reports a failure before it asks.
    static func box(_ text: String) -> Box {
        let lower = text.lowercased()
        guard lower.contains(where: { $0 == "?" || $0 == "？" || $0 == "؟" }) else { return .notice }
        return failureWords.contains(where: lower.contains) ? .notice : .question
    }

    // MARK: - When to look closer

    enum Step: Equatable {
        case none
        /// The ways still to come start with the channels: no start of its own.
        case nextWay
        /// No way is left: the last one once more, with the channels.
        case sameWayAgain
    }

    /// After a start on the ladder that failed. `unexplained`: the diagnosis found nothing but its
    /// fallbacks (StartDiagnosis.unexplained). `carried`: a start of this Play had the channels already –
    /// one look per Play. `takenBefore`: one was taken for this game on this engine build (`taken`): a game
    /// that fails every time isn't started twice at every Play. `canCarry`: the start to come can have the
    /// channels at all – a game through Steam gets them from a Steam started with them, and Steam doesn't
    /// restart under another game.
    static func step(unexplained: Bool, antiCheat: Bool, carried: Bool, takenBefore: Bool, canCarry: Bool, lastWay: Bool) -> Step {
        guard unexplained, !antiCheat, !carried, !takenBefore, canCarry else { return .none }
        return lastWay ? .sameWayAgain : .nextWay
    }

    private static func key(_ game: GameID) -> String { "closerLook.\(game.key)" }

    /// Whether a closer look was taken for the game on this engine build ("winecx@4.7.3").
    static func taken(_ game: GameID, engine: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key(game)) == engine
    }

    static func noteTaken(_ game: GameID, engine: String, defaults: UserDefaults = .standard) {
        defaults.set(engine, forKey: key(game))
    }
}
