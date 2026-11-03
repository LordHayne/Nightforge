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
        let places = WineSandbox.Places(home: home, support: support)

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

        // MARK: Switch
        let wine = URL(fileURLWithPath: "/engine/bin/wine")
        let helper = URL(fileURLWithPath: "/app/nightforge-sandbox")
        var executable: URL? = wine
        var programArguments: [String]? = ["steam.exe", "-silent"]
        WineSandbox.wrap(&executable, &programArguments, enabled: false, helper: helper, places: places)
        check(executable == wine && programArguments == ["steam.exe", "-silent"], "switched off, the start is exactly as before")
        WineSandbox.wrap(&executable, &programArguments, enabled: true, helper: nil, places: places)
        check(executable == wine, "without the helper (a build without it, tests) the start stays as it is")
        WineSandbox.wrap(&executable, &programArguments, enabled: true, helper: helper, places: places)
        let file = WineSandbox.profileFile(places)
        check(executable == helper && programArguments == [file.path, wine.path, "steam.exe", "-silent"],
              "switched on: the helper, the profile, then the program: \(programArguments ?? [])")
        check((try? String(contentsOf: file, encoding: .utf8)) == profile, "the profile is written where the helper reads it")

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
            check(run(realHelper, [file.path, cat.path, secret.path]).status != 0, "can't be read inside: \(secret.lastPathComponent)")
        }
        for allowed in open {
            check(run(realHelper, [file.path, cat.path, allowed.path]).output == "x", "can be read inside: \(allowed.lastPathComponent)")
        }
        let planted = home.appendingPathComponent(".ssh/authorized_keys")
        _ = run(realHelper, [file.path, touch.path, planted.path])
        check(!FileManager.default.fileExists(atPath: planted.path), "nothing can be planted in a denied folder either")
        check(run(realHelper, [file.path, cat.path, secrets[0].path]).status != 0 && run(cat, [secrets[0].path]).output == "x",
              "outside the sandbox the same file reads as usual")

        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = "/usr/lib"
        check(run(realHelper, [file.path, showenv.path], environment: environment).output == "/usr/lib\n",
              "DYLD_* reaches the program (sandbox-exec would drop it, and with it DockHider's library)")
        check(run(realHelper, [root.appendingPathComponent("missing.sb").path, cat.path, open[0].path]).status == 71,
              "without its profile the helper starts nothing")
        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "✓ WineSandbox" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
