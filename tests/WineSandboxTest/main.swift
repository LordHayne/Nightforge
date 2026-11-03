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
        check(!readOnly.contains("/Prefix") && !profile.contains("(subpath \(WineSandbox.quoted(realSupport)!))"),
              "the prefix and the data folder as a whole stay writable")
        // Nor moved: no folder above a place may be renamed or removed, nor the place itself (review N2).
        let anchored = profile.range(of: "(deny file-write-unlink\n").map { String(profile[$0.lowerBound...]) } ?? ""
        for path in [realSupport, realSupport + "/Epic", realSupport + "/GOG", WineSandbox.canonical(home) + "/Library/Application Support",
                     WineSandbox.canonical(home) + "/Library", WineSandbox.canonical(home), WineSandbox.canonical(temporary)] {
            check(anchored.contains("(literal \(WineSandbox.quoted(path)!))"), "can't be renamed inside: \(path)")
        }
        check(profile.contains("(deny file-write-unlink file-write-create\n") && profile.contains("(literal \(denied))"),
              "nor the places themselves")
        check(!anchored.contains(WineSandbox.quoted(realSupport + "/Prefix")!), "the prefix can still be renamed inside it")
        // What tells Nightforge what to do, and its preferences with the sandbox switch (review of 3.11.2026).
        check(readOnly.contains(WineSandbox.quoted(realSupport + "/launchoptions-written.json")!), "the LaunchOptions Nightforge wrote can't be changed inside")
        check(readOnly.contains(WineSandbox.quoted(WineSandbox.canonical(home) + "/Library/Preferences/io.github.lordhayne.nightforge.plist")!)
              && profile.contains(#"(deny user-preference-write (preference-domain "io.github.lordhayne.nightforge"))"#),
              "nor Nightforge's preferences, as a file or through cfprefsd")
        check(profile.contains("(literal \(WineSandbox.quoted(realSupport + "/shortcut-key")!))")
              && (profile.range(of: "(deny file-read* file-write*").map { profile[$0.lowerBound...].contains("shortcut-key") } ?? false),
              "the game apps' key can't even be read")
        check(WineSandbox.ancestors(of: "/Users/jane/Library/x") == ["/Users/jane/Library", "/Users/jane", "/Users"]
              && WineSandbox.ancestors(of: "/x").isEmpty, "the folders above a path, down to /")

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
        sessionSwitch(wine, folder: root)

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
        // Moving a folder above the places, from inside (review N2, 3.11.2026): before the fix "Epic" became
        // "Epic-alt" and legendary's token read there; "Nightforge" could be moved away and replaced.
        let mv = URL(fileURLWithPath: "/bin/mv")
        let moves: [(URL, String)] = [(support.appendingPathComponent("Epic"), "Epic-alt"), (support.appendingPathComponent("GOG"), "GOG-alt"),
                                      (support, "Nightforge-alt"), (support.deletingLastPathComponent(), "Application Support-alt"),
                                      (home.appendingPathComponent("Library"), "Library-alt"),
                                      (home.appendingPathComponent("Library/Application Support/Firefox"), "Firefox-alt"),
                                      (support.appendingPathComponent("Components"), "Components-alt"), (temporary, "T-alt")]
        for (folder, name) in moves {
            let moved = folder.deletingLastPathComponent().appendingPathComponent(name)
            _ = run(realHelper, [profile, mv.path, folder.path, moved.path])
            check(FileManager.default.fileExists(atPath: folder.path) && !FileManager.default.fileExists(atPath: moved.path),
                  "can't be renamed inside: \(folder.lastPathComponent)")
            if FileManager.default.fileExists(atPath: moved.path) { try? FileManager.default.moveItem(at: moved, to: folder) }
        }
        check(run(realHelper, [profile, cat.path, secrets[0].path]).status != 0, "legendary's token still can't be read inside")
        let replaced = run(realHelper, [profile, sh.path, "-c", "mv \"$1\" \"$1-alt\" && mkdir -p \"$1/Components\"", "sh", support.path])
        check(replaced.status != 0 && FileManager.default.fileExists(atPath: secrets[0].path), "the data folder can't be swapped for another")
        let save = support.appendingPathComponent("Prefix/drive_c/save.dat")
        _ = run(realHelper, [profile, sh.path, "-c", "printf y > \"$1\"", "sh", save.path])
        check((try? String(contentsOf: save, encoding: .utf8)) == "y", "the prefix stays writable inside")
        let renamed = save.deletingLastPathComponent().appendingPathComponent("save-old.dat")
        _ = run(realHelper, [profile, mv.path, save.path, renamed.path])
        check(FileManager.default.fileExists(atPath: renamed.path), "and its files can be renamed, as games do when they save")
        // Files and preferences that steer Nightforge, from inside (review of 3.11.2026).
        let record = support.appendingPathComponent("launchoptions-written.json"), key = support.appendingPathComponent("shortcut-key")
        write("{}", record)
        write("0123456789abcdef0123456789abcdef", key)
        _ = run(realHelper, [profile, sh.path, "-c", "printf '{\"570\":[\"-novid\"]}' > \"$1\"", "sh", record.path])
        check((try? String(contentsOf: record, encoding: .utf8)) == "{}" && run(realHelper, [profile, cat.path, record.path]).output == "{}",
              "launchoptions-written.json reads inside, but can't be changed there")
        check(run(realHelper, [profile, cat.path, key.path]).status != 0, "the game apps' key doesn't read inside")
        preferences(realHelper: realHelper, places: places)
        // The quit script's Wine start (review of 3.11.2026): it ran steam.exe from the prefix – which programs
        // inside can change – outside the sandbox. Its wine_program, from the script itself, with the helper.
        shutdownScript(realHelper: realHelper, profile: profile, token: secrets[0], prefix: support.appendingPathComponent("Prefix"))
        // Outside the sandbox nothing of this applies: Nightforge's complete removal deletes in its own process.
        check((try? FileManager.default.removeItem(at: support)) != nil && !FileManager.default.fileExists(atPath: support.path),
              "outside, the data folder can be removed as a whole (CompleteRemoval)")
        finish()
    }

    /// The sandbox switch is in Nightforge's preferences, and cfprefsd writes for a program that asks
    /// (`defaults write`) whatever the plist file's rule says – tried with the helper on 3.11.2026. With
    /// a test domain of its own, never Nightforge's: written and deleted inside, no; read, yes; another
    /// domain stays writable.
    static func preferences(realHelper: URL, places: WineSandbox.Places) {
        let domain = "nightforge.wine-sandbox-prefs-\(UUID().uuidString)", other = domain + "-other"
        var mine = places
        mine.preferences = domain
        // cfprefsd writes the real ~/Library/Preferences, so the plist's rule has to name that one.
        mine.home = FileManager.default.homeDirectoryForCurrentUser
        let profile = WineSandbox.profile(mine)
        let defaults = URL(fileURLWithPath: "/usr/bin/defaults")
        defer {
            for name in [domain, other] { _ = run(defaults, ["delete", name]) }
            forget([domain, other])
        }
        _ = run(defaults, ["write", domain, WineSandbox.defaultsKey, "-bool", "true"])
        check(run(realHelper, [profile, defaults.path, "write", domain, WineSandbox.defaultsKey, "-bool", "false"]).status != 0
              && run(defaults, ["read", domain, WineSandbox.defaultsKey]).output == "1\n", "the switch can't be turned off inside")
        _ = run(realHelper, [profile, defaults.path, "delete", domain])
        check(run(defaults, ["read", domain, WineSandbox.defaultsKey]).output == "1\n", "nor deleted")
        check(run(realHelper, [profile, defaults.path, "read", domain, WineSandbox.defaultsKey]).output == "1\n", "reading stays")
        _ = run(realHelper, [profile, defaults.path, "write", other, "k", "-bool", "true"])
        check(run(defaults, ["read", other, "k"]).output == "1\n", "other programs' preferences stay writable inside")
    }

    /// steam-shutdown.sh starts Steam's -shutdown through `wine_program`: with the switch on through the
    /// helper and the profile, without the helper not at all, switched off as before.
    static func shutdownScript(realHelper: URL, profile: String, token: URL, prefix: URL) {
        let script = Engine.steamShutdownScript
        guard let start = script.range(of: "wine_program() {\n"), let end = script.range(of: "\n}\n", range: start.upperBound..<script.endIndex) else {
            check(false, "the quit script has its wine_program")
            return
        }
        let function = String(script[start.lowerBound..<end.upperBound])
        check(script.contains(#"wine_program 'C:\Program Files (x86)\Steam\steam.exe' -noverifyfiles -shutdown"#)
              && !script.contains(#""$WINE" 'C:"#), "Steam's -shutdown goes through wine_program, never \"$WINE\" directly")
        let engine = (try? String(contentsOf: URL(fileURLWithPath: "Sources/Nightforge/Engine.swift"), encoding: .utf8)) ?? ""
        check(engine.contains(#"WineSandbox.enabled ? [WineSandbox.helper?.path ?? "-", WineSandbox.profile()] : ["", ""]"#),
              "scheduleSteamShutdown hands the script the helper and the profile when the switch is on")
        // A steam.exe a program inside replaced: here a script that copies legendary's token out.
        let steam = prefix.appendingPathComponent("drive_c/steam.exe"), stolen = prefix.appendingPathComponent("stolen")
        write("cat \"$1\" > \"$2\"\n", steam)
        func shutdown(sandbox: String) -> Int32 {
            try? FileManager.default.removeItem(at: stolen)
            let harness = "SANDBOX=\"$1\"; PROFILE=\"$2\"; WINE=/bin/sh\n" + function + "wine_program \"$3\" \"$4\" \"$5\"\n"
            return run(URL(fileURLWithPath: "/bin/bash"), ["-c", harness, "bash", sandbox, profile, steam.path, token.path, stolen.path]).status
        }
        _ = shutdown(sandbox: "")
        check((try? String(contentsOf: stolen, encoding: .utf8)) == "x", "switched off, it runs as before – outside, where the token reads")
        _ = shutdown(sandbox: realHelper.path)
        check((try? String(contentsOf: stolen, encoding: .utf8)) ?? "" != "x", "switched on, inside: the token doesn't read")
        check(shutdown(sandbox: "-") != 0 && !FileManager.default.fileExists(atPath: stolen.path),
              "switched on without the helper: nothing of Windows starts")
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
    static func sessionSwitch(_ wine: URL, folder: URL) {
        // A suite named by a path keeps its plist there, in the test's folder: one named like a domain
        // left an empty plist in ~/Library/Preferences after every run, written when the test ended.
        let defaults = UserDefaults(suiteName: folder.appendingPathComponent("session-defaults").path)!
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

        // Review N8: two Wine starts right after switching end the session once, not each other's.
        let lock = NSLock()
        var ends = 0
        let group = DispatchGroup()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                WineSandbox.settleSession(wine, enabled: true, defaults: defaults, gameRunning: { false }, end: { _ in
                    Thread.sleep(forTimeInterval: 0.3)
                    lock.lock(); ends += 1; lock.unlock()
                })
                group.leave()
            }
        }
        group.wait()
        check(ends == 1 && defaults.bool(forKey: WineSandbox.sessionKey), "two starts at once: one end (\(ends))")
        // Ending starts Steam's -shutdown, which comes through here again: it joins the session it ends.
        var nested = 0
        WineSandbox.settleSession(wine, enabled: false, defaults: defaults, gameRunning: { false }, end: { inner in
            nested += 1
            WineSandbox.settleSession(inner, enabled: false, defaults: defaults, gameRunning: { false }, end: { _ in nested += 10 })
        })
        check(nested == 1 && !defaults.bool(forKey: WineSandbox.sessionKey), "the start the ending makes passes, no second end, no deadlock")
        // At Nightforge's start it happens off the main thread: the process list and the ending take seconds.
        var checkedOnMain: Bool?, endedOnMain: Bool?
        let background = DispatchSemaphore(value: 0)
        Task.detached {
            await WineSandbox.settleInBackground(wine, enabled: true, defaults: defaults,
                                                 gameRunning: { checkedOnMain = Thread.isMainThread; return false },
                                                 end: { _ in endedOnMain = Thread.isMainThread })
            background.signal()
        }
        background.wait()
        check(checkedOnMain == false && endedOnMain == false && defaults.bool(forKey: WineSandbox.sessionKey),
              "settled in the background: checked and ended off the main thread")
    }

    /// Test domains gone for good: cfprefsd leaves an empty plist behind when a domain is deleted, a
    /// moment later – removed once it's there (it doesn't come back), not in a race with it.
    static func forget(_ domains: [String]) {
        Thread.sleep(forTimeInterval: 1)
        for name in domains {
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist"))
        }
    }

    static func finish() -> Never {
        print(failures == 0 ? "✓ WineSandbox" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
