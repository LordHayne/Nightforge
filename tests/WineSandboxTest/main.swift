// Checks Wine's sandbox – the profile, the switch, and the real helper on a home of its own:
// tests/WineSandboxTest/run.sh (it builds the helper and passes it, and a program that prints its
// environment). No process lists, nothing of the player's: every path is in a temporary folder.
import Foundation

@main
struct WineSandboxTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ text: String, _ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Runs `arguments` and returns the exit code and what it printed.
    static func run(_ program: URL, _ arguments: [String], environment: [String: String]? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "") }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    static func main() {
        let arguments = CommandLine.arguments
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wine-sandbox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A home whose name a profile string has to escape: a space, quotes and a backslash.
        let home = root.appendingPathComponent(#"Jane "Q" Doe\x"#, isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support/Nightforge", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // The app and the temporary folder of a Mac of its own as well.
        let app = root.appendingPathComponent("Applications/Nightforge.app", isDirectory: true)
        let temporary = root.appendingPathComponent("T", isDirectory: true)
        for folder in [app, temporary] { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let places = WineSandbox.Places(home: home, support: support, app: app, temporary: temporary)

        // MARK: Profile
        check(WineSandbox.quoted("/a b") == #""/a b""#, "a space stays as it is")
        check(WineSandbox.quoted(#"/a"b\c"#) == #""/a\"b\\c""#, "quotes and backslashes are escaped")
        check(WineSandbox.quoted("/a\nb") == nil, "a line break can't be in a profile string: no rule")
        let profile = WineSandbox.profile(places)
        let realSupport = WineSandbox.canonical(support)
        check(realSupport.hasPrefix("/private/"), "the real path, as the sandbox compares it: \(realSupport)")
        let denied = WineSandbox.quoted(realSupport + "/Epic/legendary")!, exception = WineSandbox.quoted(realSupport + "/Epic/legendary/tmp")!
        check(profile.hasPrefix("(version 1)") && profile.contains("(allow default)"), "everything else stays allowed")
        check(profile.contains("(subpath \(denied))") && profile.contains("(subpath \(WineSandbox.quoted(realSupport + "/GOG/gogdl")!))"),
              "legendary's and gogdl's folders are denied")
        check(profile.contains("(literal \(WineSandbox.quoted(realSupport + "/Epic/account.json")!))"), "the store accounts too")
        check(profile.contains("(subpath \(WineSandbox.quoted(WineSandbox.canonical(home) + "/.ssh")!))"), "and the home's keys")
        if let deny = profile.range(of: "(deny"), let allow = profile.range(of: "(allow file-read*") {
            check(deny.lowerBound < allow.lowerBound && profile[allow.lowerBound...].contains(exception),
                  "legendary's tmp comes back after the denial (the later rule wins)")
        } else {
            check(false, "the profile has a denial and an exception:\n\(profile)")
        }
        // What Nightforge runs itself, outside, can't be changed from inside (review H2, 3.11.2026).
        let readOnly = profile.range(of: "(deny file-write*").map { String(profile[$0.lowerBound...]) } ?? ""
        for path in [realSupport + "/Components", realSupport + "/Nightforge Helper.app", realSupport + "/hide-steam-dock.dylib",
                     realSupport + "/steam-shutdown.sh", realSupport + "/D3DMetal", WineSandbox.canonical(app),
                     WineSandbox.canonical(temporary) + "/Nightforge-runs", WineSandbox.canonical(home) + "/Applications/Nightforge Games"] {
            check(readOnly.contains(WineSandbox.quoted(path)!), "can't be changed inside: \(path)")
        }
        check(!readOnly.contains("/Prefix") && !profile.contains(realSupport + "\")"), "the prefix and the data folder as a whole stay writable")

        // MARK: Switch
        let wine = URL(fileURLWithPath: "/engine/bin/wine")
        let helper = URL(fileURLWithPath: "/app/nightforge-sandbox")
        var executable: URL? = wine
        var programArguments: [String]? = ["steam.exe", "-silent"]
        try? WineSandbox.wrap(&executable, &programArguments, enabled: false, helper: nil, places: places)
        check(executable == wine && programArguments == ["steam.exe", "-silent"], "switched off, the start is exactly as before")
        // Switched on without the helper (a build without an x86_64 clang, a damaged bundle): no start
        // at all, never one without the sandbox (review H3, 3.11.2026).
        do {
            try WineSandbox.wrap(&executable, &programArguments, enabled: true, helper: nil, places: places)
            check(false, "switched on without the helper: no start")
        } catch let error as WineSandbox.HelperMissing {
            check(error.localizedDescription.lowercased().contains("sandbox") && executable == wine, "it says why, and nothing was changed")
        } catch {
            check(false, "the error says the helper is missing: \(error)")
        }
        try? WineSandbox.wrap(&executable, &programArguments, enabled: true, helper: helper, places: places)
        check(executable == helper && programArguments == [profile, wine.path, "steam.exe", "-silent"],
              "switched on: the helper, the profile's text, then the program: \(programArguments?.dropFirst() ?? [])")
        check(!FileManager.default.fileExists(atPath: support.appendingPathComponent("wine-sandbox.sb").path),
              "no profile file in the data folder that a program inside could change before the helper reads it")

        // MARK: Every Wine start goes through WineSandbox.process
        everyWineStartWrapped()
        let plain = try? WineSandbox.process(wine, ["regedit", "/S", "x.reg"], sandboxed: false)
        check(plain?.executableURL == wine && plain?.arguments == ["regedit", "/S", "x.reg"], "a CrossOver bottle's Wine starts as it is")
        sessionSwitch(wine)

        // MARK: The helper with the real profile
        guard arguments.count >= 3 else {
            check(false, "run through run.sh, which builds the helper")
            finish()
        }
        let realHelper = URL(fileURLWithPath: arguments[1]), showenv = URL(fileURLWithPath: arguments[2])
        let secrets = [support.appendingPathComponent("Epic/legendary/user.json"), support.appendingPathComponent("GOG/gogdl/auth.json"),
                       support.appendingPathComponent("Epic/account.json"), home.appendingPathComponent(".ssh/id_ed25519"),
                       home.appendingPathComponent(".netrc"), home.appendingPathComponent("Library/Application Support/Firefox/key4.db")]
        let open = [support.appendingPathComponent("Epic/legendary/tmp/game.ovt"), support.appendingPathComponent("GOG/Redist/setup.exe"),
                    support.appendingPathComponent("Prefix/drive_c/save.dat"), home.appendingPathComponent("Library/Fonts/font.ttf")]
        for url in secrets + open { write("x", url) }
        let cat = URL(fileURLWithPath: "/bin/cat"), touch = URL(fileURLWithPath: "/usr/bin/touch")
        for secret in secrets {
            check(run(realHelper, [profile, cat.path, secret.path]).status != 0, "can't be read inside: \(secret.lastPathComponent)")
        }
        for allowed in open {
            check(run(realHelper, [profile, cat.path, allowed.path]).output == "x", "can be read inside: \(allowed.lastPathComponent)")
        }
        let planted = home.appendingPathComponent(".ssh/authorized_keys")
        _ = run(realHelper, [profile, touch.path, planted.path])
        check(!FileManager.default.fileExists(atPath: planted.path), "nothing can be planted in a denied folder either")
        check(run(realHelper, [profile, cat.path, secrets[0].path]).status != 0 && run(cat, [secrets[0].path]).output == "x",
              "outside the sandbox the same file reads as usual")

        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = "/usr/lib"
        check(run(realHelper, [profile, showenv.path], environment: environment).output == "/usr/lib\n",
              "DYLD_* reaches the program (sandbox-exec would drop it, and with it DockHider's library)")
        check(run(realHelper, ["(version 1)(allow nonsense)", cat.path, open[0].path]).status == 71,
              "with a profile it can't apply the helper starts nothing")
        check(run(realHelper, ["", cat.path, open[0].path]).status == 71, "nor with none")

        // Read, yes; changed, no – and the prefix stays writable.
        let ownCode = [support.appendingPathComponent("Components/winecx/4.7.3/Libraries/Wine/bin/wineserver"),
                       support.appendingPathComponent("Nightforge Helper.app/Contents/MacOS/nightforge-helper"),
                       support.appendingPathComponent("hide-steam-dock.dylib"), support.appendingPathComponent("steam-shutdown.sh"),
                       app.appendingPathComponent("Contents/MacOS/Nightforge"),
                       temporary.appendingPathComponent("Nightforge-runs/1234/request")]
        for url in ownCode { write("x", url) }
        let sh = URL(fileURLWithPath: "/bin/sh")
        for url in ownCode {
            check(run(realHelper, [profile, cat.path, url.path]).output == "x", "can be read inside: \(url.lastPathComponent)")
            _ = run(realHelper, [profile, sh.path, "-c", "printf y > \"$1\"", "sh", url.path])
            check((try? String(contentsOf: url, encoding: .utf8)) == "x", "can't be overwritten inside: \(url.lastPathComponent)")
        }
        let swapped = support.appendingPathComponent("Components/winecx/4.7.3/Libraries/Wine/bin/wine64")
        _ = run(realHelper, [profile, touch.path, swapped.path])
        check(!FileManager.default.fileExists(atPath: swapped.path), "nothing new can be put among them")
        _ = run(realHelper, [profile, URL(fileURLWithPath: "/bin/rm").path, ownCode[2].path])
        check(FileManager.default.fileExists(atPath: ownCode[2].path), "nor taken away")
        let save = support.appendingPathComponent("Prefix/drive_c/save.dat")
        _ = run(realHelper, [profile, sh.path, "-c", "printf y > \"$1\"", "sh", save.path])
        check((try? String(contentsOf: save, encoding: .utf8)) == "y", "the prefix stays writable inside")
        finish()
    }

    /// Reads the sources: a program is started only through WineSandbox.process, or is one of these,
    /// none of them Wine. A Wine start of its own – regedit and msiexec were, 3.11.2026 – would begin
    /// a session whose wineserver opens files outside the sandbox for every program in it.
    static func everyWineStartWrapped() {
        let notWine: [(file: String?, start: String)] = [
            (nil, #"URL(fileURLWithPath: "/"#),                 // system tools: /bin/ps, /usr/bin/open, …
            (nil, "URL(fileURLWithPath: tool)"),                // hdiutil, ditto and the like, by path
            // wineserver -k and -w end or wait for a session; they never begin one.
            (nil, #"wine.deletingLastPathComponent().appendingPathComponent("wineserver")"#),
            ("Detached.swift", "executableURL"),                // its own fallback, run as it was given
            ("WineSandbox.swift", "program"),                   // the start it built, wrapped
            ("Engine.swift", "lsregister"), ("Legendary.swift", "binary"), ("GOGStore.swift", "program"),  // Mac programs
            ("MacSteamTestHome.swift", "executable"),
            // h1-h3's runner with a time limit: system tools (ProcessList's ps) and wineserver -k, no Wine start.
            ("Subprocess.swift", "URL(fileURLWithPath: executable)"),
        ]
        let folder = URL(fileURLWithPath: "Sources/Nightforge", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        check(files.count > 50, "the sources are read from the repository: \(files.count) files")
        var starts = 0
        for file in files where file.pathExtension == "swift" {
            let lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                guard let range = line.range(of: "executableURL = ") else { continue }
                starts += 1
                let start = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let known = notWine.contains { ($0.file == nil || $0.file == file.lastPathComponent) && start.hasPrefix($0.start) }
                check(known, "\(file.lastPathComponent):\(number + 1) starts a program past WineSandbox.process: \(start)")
            }
        }
        check(starts > 10, "the starts were found: \(starts)")
        let engine = (try? String(contentsOf: folder.appendingPathComponent("Engine.swift"), encoding: .utf8)) ?? ""
        for start in [#"WineSandbox.process(wine, ["regedit""#, #"WineSandbox.process(wine, ["msiexec""#] {
            check(engine.contains(start), "\(start) – in the sandbox like the rest")
        }
    }

    /// A Wine session begun with the switch the other way ends before anything else starts in it,
    /// but never under a running game.
    static func sessionSwitch(_ wine: URL) {
        let suite = "nightforge.wine-sandbox-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var ended: [URL] = []
        func settle(_ enabled: Bool, game: Bool = false) {
            WineSandbox.settleSession(wine, enabled: enabled, defaults: defaults, gameRunning: { game }, end: { ended.append($0) })
        }
        settle(false)
        check(ended.isEmpty, "off, and never switched on: the session goes on")
        settle(true)
        check(ended == [wine] && defaults.bool(forKey: WineSandbox.sessionKey), "switched on: the session from before ends, once")
        settle(true)
        check(ended.count == 1, "and then goes on")
        settle(false, game: true)
        check(ended.count == 1 && defaults.bool(forKey: WineSandbox.sessionKey), "switched off under a running game: it goes on for now")
        settle(false)
        check(ended.count == 2 && !defaults.bool(forKey: WineSandbox.sessionKey), "once the game has ended, it ends")
    }

    static func finish() -> Never {
        print(failures == 0 ? "✓ WineSandbox" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
