// The start's small parts against odd input: the launch options a player types, Steam's console log
// (empty, rotated, another game's lines) and SteamStartCheck, which decides whether a Steam that started
// counts as failed: tests/LaunchEdgeTest/run.sh
import Foundation

@main
struct LaunchEdgeTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("launch-edge-\(UUID().uuidString)", isDirectory: true)

    static func main() {
        TestDefaults.useWorkFolder()
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        launchOptions()
        watcher()
        startCheck()
        print(failures == 0 ? "✓ The start against odd input" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func launchOptions() {
        func split(_ text: String) -> [String] { Launcher.splitArguments(text) }
        check(split("").isEmpty && split("   \t ").isEmpty, "nothing typed: no arguments")
        check(split(#"-foo "bar baz" -x"#) == ["-foo", "bar baz", "-x"], "quotes hold spaces together")
        check(split(#"-path="C:\Program Files\Spiel" -y"#) == [#"-path=C:\Program Files\Spiel"#, "-y"], "and work inside a word: \(split(#"-path="C:\Program Files\Spiel" -y"#))")
        check(split("  -a   -b\t-c\n") == ["-a", "-b", "-c"], "any white space separates")
        check(split("-name Jörg -städte") == ["-name", "Jörg", "-städte"], "umlauts as they are")
        check(split(#"-a "unfinished quote"#) == ["-a", "unfinished quote"], "a quote that never ends runs to the end")
    }

    static func log(_ steam: URL) -> URL { steam.appendingPathComponent("logs/console_log.txt") }

    static func append(_ text: String, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }

    static func watcher() {
        let steam = work.appendingPathComponent("steam folder ü", isDirectory: true)
        var nothing = LaunchWatcher(steamRoot: steam, appID: 730)
        check(nothing.poll() == nil && !nothing.steamReceivedLaunch, "no log yet: nothing, no crash")

        append("[2026] Game process added : AppID 730\n", to: log(steam))
        var past = LaunchWatcher(steamRoot: steam, appID: 730)
        check(past.poll() == nil, "what the log already said isn't news")
        append("[2026] GameAction [AppID 1730, ActionID 3] : Game process added\n", to: log(steam))
        check(past.poll() == nil, "another game's line (AppID 1730) isn't this one's (730)")
        append("[2026] Game process added : AppID 730\n", to: log(steam))
        check(past.poll() == .running, "a new line of this game is")

        var rotated = LaunchWatcher(steamRoot: steam, appID: 730)
        try? Data("[2026] Game process added : AppID 730\n".utf8).write(to: log(steam))
        check(rotated.poll() == .running, "Steam starting a fresh, shorter log: it's read from its start")

        try? Data().write(to: log(steam))
        var empty = LaunchWatcher(steamRoot: steam, appID: 730)
        append(String(decoding: [0xFF, 0xFE, 0x00, 0x0A], as: UTF8.self), to: log(steam))
        check(empty.poll() == nil, "bytes that aren't text are nothing")

        append("[2026] GameAction [AppID 730, ActionID 9] : LaunchApp waiting for user response to CloudSync\n", to: log(steam))
        var questioned = LaunchWatcher(steamRoot: steam, appID: 730)
        check(questioned.poll() == .needsConfirmation, "a question open before the start is told at once")
        check(questioned.poll() == nil, "and only once")
    }

    static func startCheck() {
        let steam = work.appendingPathComponent("steam-check", isDirectory: true)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let signs = SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: start.addingTimeInterval(120))
        check(!signs.signedIn && !signs.startupFinished && signs.quietFor == 120, "no logs folder at all: nothing signed in, quiet since the start")
        check(SteamStartCheck.judge(signs) == .failed, "that long with its process and no log: failed")

        // A log from the session before says nothing of this start.
        let connection = steam.appendingPathComponent("logs/connection_log.txt")
        append("[2026-11-08 10:00:00] Logged On\n", to: connection)
        try? FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(-600)], ofItemAtPath: connection.path)
        check(!SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: start.addingTimeInterval(120)).signedIn,
              "an old log's “Logged On” isn't this start's")

        // Never failed early, whatever else is wrong.
        for since in stride(from: 0.0, to: SteamStartCheck.patience, by: 13.0) {
            for running: Bool? in [true, false, nil] {
                let judged = SteamStartCheck.judge(.init(running: running, quietFor: 10_000, sinceStart: since))
                check(judged == .undecided, "before its patience is up: undecided (\(since), \(String(describing: running)))")
            }
        }
        // Not knowing isn't failing.
        check(SteamStartCheck.judge(.init(running: nil, quietFor: 10_000, sinceStart: 500)) == .undecided, "no process list: not judged")
        // A sign of life wins over everything.
        check(SteamStartCheck.judge(.init(askingForAccount: true, running: false, quietFor: 10_000, sinceStart: 500)) == .cameUp, "its window asking counts as up")
        // An update takes as long as it takes.
        check(SteamStartCheck.judge(.init(bootstrap: .downloading, running: false, quietFor: 10_000, sinceStart: 5000)) == .undecided, "while it updates itself: never judged")
    }
}
