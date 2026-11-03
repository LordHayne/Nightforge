import Foundation

/// Wine is no sandbox: every Windows program sees the whole Mac on Z:, and \\?\unix\ reaches any
/// path past the drives – Epic's and GOG's sign-in tokens in Nightforge's own folder included. With
/// this switched on, Nightforge starts Wine inside a macOS sandbox that allows everything but a
/// list of places with sign-in data (docs/ENTWURF-LAUFWERKE.md). Whatever a sandboxed program
/// starts stays inside: Steam's games, installers, Wine's helpers.
///
/// Off until a live test has shown that Steam, games, Epic, GOG, controllers and Game Mode get on
/// with it (docs/TODO.md): `defaults write io.github.lordhayne.nightforge wineSandbox -bool true`,
/// then quit Nightforge so Steam starts afresh. Off, Nightforge starts Wine exactly as before.
enum WineSandbox {
    static let defaultsKey = "wineSandbox"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// The helper that applies the profile and becomes the program (wrapper/nightforge-sandbox.c).
    /// Not /usr/bin/sandbox-exec: as a protected system program it drops DYLD_INSERT_LIBRARIES, and
    /// Steam would be back in the Dock (DockHider).
    static var helper: URL? { Bundle.main.url(forResource: "nightforge-sandbox", withExtension: nil) }

    /// Whose places the profile names: the Mac's home and Nightforge's data folder.
    struct Places {
        var home = FileManager.default.homeDirectoryForCurrentUser
        var support = Engine.supportDir
    }

    /// Kept away from Windows programs, reading and writing: in Nightforge's data folder (paths
    /// relative to it), the sign-in tokens of legendary and gogdl and the store accounts.
    static let deniedInSupport: [(path: String, folder: Bool)] = [
        ("Epic/legendary", true), ("GOG/gogdl", true), ("Epic/account.json", false), ("GOG/account.json", false),
    ]

    /// In the home folder: where other programs keep keys and passwords that macOS doesn't guard
    /// itself (it does Documents, Desktop, Downloads, Mail, Messages and Safari). Not the keychain
    /// files: they're encrypted, and Wine's certificate code may read them.
    static let deniedInHome: [(path: String, folder: Bool)] = [
        (".ssh", true), (".gnupg", true), (".aws", true), (".config", true), (".kube", true), (".docker", true),
        (".netrc", false), (".git-credentials", false), (".npmrc", false), (".pypirc", false),
        ("Library/Application Support/Google/Chrome", true), ("Library/Application Support/Firefox", true),
        ("Library/Application Support/BraveSoftware", true), ("Library/Application Support/Microsoft Edge", true),
        ("Library/Application Support/Arc", true), ("Library/Application Support/Claude", true),
    ]

    /// Back in, inside a denied folder: Epic games read their ownership token (`-epicovt=`) from
    /// legendary's tmp folder. In a profile the later rule wins.
    static let allowedInSupport = ["Epic/legendary/tmp"]

    /// The profile: everything allowed, then the denied places, then the exceptions.
    static func profile(_ places: Places = Places()) -> String {
        let home = canonical(places.home), support = canonical(places.support)
        func rule(_ base: String, _ entry: (path: String, folder: Bool)) -> String? {
            quoted(base + "/" + entry.path).map { "    (\(entry.folder ? "subpath" : "literal") \($0))" }
        }
        let denied = deniedInSupport.compactMap { rule(support, $0) } + deniedInHome.compactMap { rule(home, $0) }
        let allowed = allowedInSupport.compactMap { rule(support, ($0, true)) }
        var lines = ["(version 1)", "; Written by Nightforge (WineSandbox.swift): Wine may do anything but read or write these.",
                     "(allow default)"]
        if !denied.isEmpty { lines += ["(deny file-read* file-write*"] + denied + [")"] }
        if !allowed.isEmpty { lines += ["(allow file-read* file-write*"] + allowed + [")"] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A path as a string in the profile: quotes and backslashes escaped. nil for one with control
    /// characters, which a profile string can't hold – that rule is left out.
    static func quoted(_ path: String) -> String? {
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The real path the sandbox compares with (/tmp is /private/tmp): `realpath` of the folder, which
    /// exists. Foundation's resolvingSymlinksInPath drops /private instead.
    static func canonical(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func profileFile(_ places: Places = Places()) -> URL {
        places.support.appendingPathComponent("wine-sandbox.sb")
    }

    /// Writes the profile where the helper reads it, unless it's there already.
    static func writeProfile(_ places: Places = Places()) -> URL {
        let file = profileFile(places)
        let text = profile(places)
        if (try? String(contentsOf: file, encoding: .utf8)) != text {
            try? FileManager.default.createDirectory(at: places.support, withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }

    /// Turns a start of `executable` with `arguments` into one inside the sandbox, when it's switched
    /// on and the helper is there; leaves it alone otherwise. Should the profile be missing, the
    /// helper starts nothing: switched on, Wine never runs outside.
    static func wrap(_ executable: inout URL?, _ arguments: inout [String]?, enabled: Bool = enabled,
                     helper: URL? = helper, places: Places = Places()) {
        guard enabled, let helper, let program = executable else { return }
        let file = writeProfile(places)
        executable = helper
        arguments = [file.path, program.path] + (arguments ?? [])
    }

    /// A process for a Wine program – `wine`, its loader, winetricks – inside the sandbox when it's
    /// switched on. Every start of Wine goes through here (WineSandboxTest reads the sources for
    /// others): the first program of a session starts the wineserver, and the wineserver opens files
    /// for every program in it. A session begun outside the sandbox (a regedit before Steam, say)
    /// would open for all of them what the sandbox keeps away. `sandboxed` false: a CrossOver bottle,
    /// not Nightforge's Wine. Throws when the sandbox is switched on and can't be applied.
    static func process(_ executable: URL, _ arguments: [String], sandboxed: Bool = true) throws -> DetachedProcess {
        var program: URL? = executable
        var programArguments: [String]? = arguments
        if sandboxed {
            settleSession(executable)
            wrap(&program, &programArguments)
        }
        let process = DetachedProcess()
        process.executableURL = program
        process.arguments = programArguments
        return process
    }

    /// The switch as the programs of the running Wine session were started with it.
    static let sessionKey = "wineSandboxSession"

    /// A Wine session begun with the switch the other way ends before anything else starts in it –
    /// whoever started its wineserver – unless a game runs in it; the switch as it is now is noted
    /// then. Without a note the session began before there was a switch: outside. `end`: Engine.stopAll.
    static func settleSession(_ wine: URL, enabled: Bool = enabled, defaults: UserDefaults = .standard,
                              gameRunning: () -> Bool = { Engine.windowsGameRunning },
                              end: (URL) -> Void = { Engine.stopAll($0) }) {
        guard (defaults.object(forKey: sessionKey) as? Bool ?? false) != enabled, !gameRunning() else { return }
        end(wine)
        defaults.set(enabled, forKey: sessionKey)
    }
}
