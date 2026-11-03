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

    /// Whose places the profile names: the Mac's home, Nightforge's data folder, the app itself and
    /// the temporary folder (where DetachedProcess hands its helper app the programs to start).
    struct Places {
        var home = FileManager.default.homeDirectoryForCurrentUser
        var support = Engine.supportDir
        var app = URL(fileURLWithPath: Bundle.main.bundlePath)
        var temporary = FileManager.default.temporaryDirectory
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

    /// Readable, but not to be changed from inside: what Nightforge runs itself, outside the sandbox
    /// – a program inside could otherwise swap in its own and have it run without (review H2,
    /// 3.11.2026). In the data folder: the engines and the stores' tools (Components: wine,
    /// wineserver, legendary, gogdl), DetachedProcess's helper app, the library DockHider puts into
    /// every Wine process, the scripts Nightforge runs, Apple's D3DMetal and GOG's Mac games. Wine
    /// writes to the prefix and to the games' folders, never here.
    static let readOnlyInSupport: [(path: String, folder: Bool)] = [
        ("Components", true), (DetachedProcess.helperName, true), (DockHider.name, false), ("steam-shutdown.sh", false),
        ("steam-priority.sh", false), ("steam-priority.pid", false), ("D3DMetal", true), ("GOG/Games", true),
    ]

    /// In the home folder: the small apps "Add to Applications" makes, which open Nightforge (GameShortcut).
    static let readOnlyInHome: [(path: String, folder: Bool)] = [("Applications/Nightforge Games", true)]

    /// The profile: everything allowed, then the denied places, then the exceptions, then what keeps
    /// the places where they are.
    static func profile(_ places: Places = Places()) -> String {
        let home = canonical(places.home), support = canonical(places.support)
        typealias Place = (path: String, folder: Bool)
        func place(_ base: String, _ entry: Place) -> Place { (base + "/" + entry.path, entry.folder) }
        func rules(_ entries: [Place]) -> [String] {
            entries.compactMap { entry in quoted(entry.path).map { "    (\(entry.folder ? "subpath" : "literal") \($0))" } }
        }
        let denied = deniedInSupport.map { place(support, $0) } + deniedInHome.map { place(home, $0) }
        let allowed = allowedInSupport.map { place(support, ($0, true)) }
        // The app and the helper's requests: subpaths of folders that exist (the runs folder may not yet).
        let readOnly = readOnlyInSupport.map { place(support, $0) } + readOnlyInHome.map { place(home, $0) }
            + [(canonical(places.app), true), (canonical(places.temporary) + "/Nightforge-runs", true)]
        // Seatbelt checks a rename at the old and the new path, not at what's inside: renaming a folder
        // above a place moves the place to a path no rule names. "Epic" to "Epic-alt", and legendary's
        // token read; "Nightforge" away and a new one with Components of its own, which Nightforge
        // runs outside (review N2, proven with the helper 3.11.2026). So no folder above them can be
        // renamed or removed, nor the places themselves; inside them everything stays as it was.
        let protected = (denied + readOnly).map(\.path)
        var above: [String] = []
        for path in protected {
            for folder in ancestors(of: path) where !above.contains(folder) && !protected.contains(folder) { above.append(folder) }
        }
        let anchored = rules(above.map { ($0, false) }), fixed = rules(protected.map { ($0, false) })
        var lines = ["(version 1)", "; Nightforge (WineSandbox.swift): Wine may do anything but read or write the first places,",
                     "; or change the next ones, or move any of them or the folders they're in.",
                     "(allow default)"]
        if !denied.isEmpty { lines += ["(deny file-read* file-write*"] + rules(denied) + [")"] }
        if !allowed.isEmpty { lines += ["(allow file-read* file-write*"] + rules(allowed) + [")"] }
        if !readOnly.isEmpty { lines += ["(deny file-write*"] + rules(readOnly) + [")"] }
        if !anchored.isEmpty { lines += ["(deny file-write-unlink"] + anchored + [")"] }
        if !fixed.isEmpty { lines += ["(deny file-write-unlink file-write-create"] + fixed + [")"] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The folders above `path`, nearest first, down to (not including) "/".
    static func ancestors(of path: String) -> [String] {
        var folders: [String] = []
        var folder = (path as NSString).deletingLastPathComponent
        while !folder.isEmpty, folder != "/" {
            folders.append(folder)
            folder = (folder as NSString).deletingLastPathComponent
        }
        return folders
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

    /// Switched on, but the helper isn't in the app (a build without an x86_64 clang, a damaged
    /// bundle): Wine doesn't start at all, as when the helper can't apply the profile (exit 71).
    struct HelperMissing: LocalizedError {
        var errorDescription: String? {
            L10n.t("The Wine sandbox is switched on, but its helper is missing from Nightforge, so Windows programs don't start. Reinstall Nightforge or switch the sandbox off.")
        }
    }

    /// Turns a start of `executable` with `arguments` into one inside the sandbox when it's switched
    /// on; leaves it alone when it's off. The profile goes to the helper as text, never as a file a
    /// program inside could change first. Switched on, Wine never runs outside: without the helper
    /// this throws, and with a profile it can't apply the helper starts nothing.
    static func wrap(_ executable: inout URL?, _ arguments: inout [String]?, enabled: Bool = enabled,
                     helper: URL? = helper, places: Places = Places()) throws {
        guard enabled, let program = executable else { return }
        guard let helper else { throw HelperMissing() }
        executable = helper
        arguments = [profile(places), program.path] + (arguments ?? [])
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
            try wrap(&program, &programArguments)
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
