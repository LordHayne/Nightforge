// Checks the script Nightforge leaves behind at quit (Engine.steamShutdownScript) against a stand-in
// ps, open, lsof, wine and wineserver in a folder of its own – nothing real is asked or ended:
// tests/QuitScriptTest/run.sh
//
// The stand-ins come first in the script's PATH. `ps` answers from a list the test writes, `open`,
// `wine` and `wineserver` write down what they were asked, `sleep` returns at once. The script's
// own command line never holds the text of a Nightforge program's path (only the app's folder).
import Foundation

@main
struct QuitScriptTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ text: String, to url: URL, executable: Bool = false) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
        if executable { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    /// One run's world: stand-ins, a prefix, an app folder and the list of "processes".
    struct World {
        let root: URL
        var bin: URL { root.appendingPathComponent("bin") }
        var log: URL { root.appendingPathComponent("calls.log") }
        var processList: URL { root.appendingPathComponent("processes.tsv") }
        var wine: URL { root.appendingPathComponent("engine/bin/wine") }
        var prefix: URL { root.appendingPathComponent("Prefix") }
        var steamapps: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps") }
        var app: String { root.appendingPathComponent("Applications/Nightforge.app").path }
        var dev: String { root.appendingPathComponent("dev/build/Nightforge.app").path }
        var script: URL { root.appendingPathComponent("steam-shutdown.sh") }
        var pidFile: URL { root.appendingPathComponent("steam-shutdown.pid") }
        /// What the pid file held each time the stand-in ps was asked (the script has begun by then).
        var pidLog: URL { root.appendingPathComponent("pids.log") }
        /// What `sleep` was asked for, one a line (the stand-in returns at once).
        var sleepLog: URL { root.appendingPathComponent("sleeps.log") }
        var later: URL { root.appendingPathComponent("processes-later.tsv") }

        init() {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("quit-\(UUID().uuidString)", isDirectory: true)
            let record = "echo \"$(basename \"$0\") $*\" >> \"$FAKE_LOG\""
            QuitScriptTest.write("""
                #!/bin/sh
                [ -f "$FAKE_PIDFILE" ] && cat "$FAKE_PIDFILE" >> "$FAKE_PIDLOG"
                file="$FAKE_PS"
                if [ -n "$FAKE_PS_LATER" ]; then
                  n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_COUNT"
                  [ "$n" -ge "${FAKE_SWITCH:-0}" ] && file="$FAKE_PS_LATER"
                fi
                case "$*" in
                  *pid=*) awk -F'\\t' '{ printf "%s %s\\n", $1, $2 }' "$file" ;;
                  *) awk -F'\\t' '{ print $2 }' "$file" ;;
                esac
                """, to: bin.appendingPathComponent("ps"), executable: true)
            QuitScriptTest.write("#!/bin/sh\nexit 1\n", to: bin.appendingPathComponent("pgrep"), executable: true)
            QuitScriptTest.write("#!/bin/sh\nexit 0\n", to: bin.appendingPathComponent("lsof"), executable: true)
            QuitScriptTest.write("#!/bin/sh\necho \"$*\" >> \"$FAKE_SLEEPLOG\"\n", to: bin.appendingPathComponent("sleep"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("open"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("osascript"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: wine, executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: wine.deletingLastPathComponent().appendingPathComponent("wineserver"), executable: true)
            QuitScriptTest.write(Engine.steamShutdownScript, to: script)
            try? FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        }

        /// Processes the stand-in `ps` lists: pid and command.
        func processes(_ list: [(Int, String)]) {
            QuitScriptTest.write(list.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n") + "\n", to: processList)
        }

        /// A download of Steam's: its folder in downloading/ and, unless nil, its manifest with these flags.
        func download(_ appID: Int, flags: Int?) {
            try? FileManager.default.createDirectory(at: steamapps.appendingPathComponent("downloading/\(appID)"),
                                                     withIntermediateDirectories: true)
            if let flags {
                QuitScriptTest.write("\"AppState\"\n{\n\t\"appid\"\t\t\"\(appID)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n}\n",
                                     to: steamapps.appendingPathComponent("appmanifest_\(appID).acf"))
            }
        }

        /// Runs the script; what the stand-ins were asked, one call a line.
        /// `switchAfter`: the stand-in ps lists `later` instead of `processes` from its n-th answer on.
        func run(limit: Int? = nil, quitting: Int = 0, app: String? = nil, lastGame: Int? = nil,
                 switchAfter: Int? = nil) -> (calls: [String], status: Int32, timedOut: Bool) {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: sleepLog)
            var environment = ["PATH": bin.path + ":/usr/bin:/bin:/usr/sbin", "FAKE_PS": processList.path, "FAKE_LOG": log.path,
                               "FAKE_PIDFILE": pidFile.path, "FAKE_PIDLOG": pidLog.path, "HOME": root.path]
            if let limit { environment["NIGHTFORGE_QUIT_LIMIT"] = String(limit) }
            environment["FAKE_SLEEPLOG"] = sleepLog.path
            environment["FAKE_COUNT"] = root.appendingPathComponent("ps-count").path
            if let switchAfter {
                environment["FAKE_PS_LATER"] = later.path
                environment["FAKE_SWITCH"] = String(switchAfter)
            }
            let outcome = Subprocess.run("/bin/bash", [script.path, wine.path, prefix.path, "", "0", app ?? self.app,
                                                       quitting == 0 ? "" : String(quitting), "1",
                                                       lastGame.map(String.init) ?? "0"],
                                         environment: environment, timeout: 60)
            let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            return (calls, outcome.status, outcome.timedOut)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    static let steam = #"C:\Program Files (x86)\Steam\steam.exe -silent"#

    /// The seconds `sleep` was asked for.
    static func sleeps(_ world: World) -> [String] {
        ((try? String(contentsOf: world.sleepLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    static func now() -> Int { Int(Date().timeIntervalSince1970) }

    static func shutDown(_ calls: [String]) -> Bool {
        calls.contains { $0.hasPrefix("wine ") && $0.contains("-shutdown") } && calls.contains("wineserver -k")
    }

    static func main() {
        let probe = World()
        defer { probe.cleanUp() }
        let syntax = Subprocess.run("/bin/bash", ["-n", probe.script.path], timeout: 20)
        check(syntax.succeeded, "the script is valid bash")

        // Another copy of Nightforge, or a tool that names the program, is not Nightforge opened again.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(100, "/usr/sbin/cfprefsd agent"), (200, steam),
                             (300, world.dev + "/Contents/MacOS/Nightforge"),
                             (301, "/usr/bin/lldb -f \(world.app)/Contents/MacOS/Nightforge -p 1"),
                             (302, "codesign --verify \(world.app)/Contents/MacOS/Nightforge"),
                             (303, "tail -f /tmp/log \(world.app)/Contents/MacOS/Nightforge-notes")])
            let result = world.run()
            check(!result.timedOut && result.status == 0, "other copies and tools: the script ended (status \(result.status))")
            check(shutDown(result.calls), "other copies and tools: Steam and the wineserver were ended: \(result.calls)")
            // Where "Remove Nightforge completely" finds the script: its process in a file beside it, while it runs.
            let pids = ((try? String(contentsOf: world.pidLog, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { pid_t($0) }
            check(!pids.isEmpty && pids.allSatisfy { $0 > 1 }, "the script wrote its pid to steam-shutdown.pid while it ran: \(pids)")
            check(Set(pids).count == 1, "… always the same one")
            check(!FileManager.default.fileExists(atPath: world.pidFile.path), "… and took the file away when it ended")
        }

        // Nightforge, opened again: its own program, with or without arguments.
        for command in ["/Contents/MacOS/Nightforge", "/Contents/MacOS/Nightforge -psn_0_12345"] {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (400, world.app + command)])
            let result = world.run()
            check(!result.timedOut && result.status == 0, "Nightforge open again (\(command)): ended quietly")
            check(result.calls.isEmpty, "Nightforge open again (\(command)): nothing was ended: \(result.calls)")
        }

        // The Nightforge that is quitting doesn't count as opened again.
        do {
            let world = World()
            defer { world.cleanUp() }
            let quitting = Int(getpid())
            world.processes([(200, steam), (quitting, world.app + "/Contents/MacOS/Nightforge")])
            let result = world.run(quitting: quitting)
            check(shutDown(result.calls), "the quitting Nightforge itself is not 'opened again': \(result.calls)")
        }

        // A download under way keeps Steam, up to the limit; the script ends then, leaving things as they are.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            world.download(123, flags: 1026)
            let result = world.run(limit: -1)
            check(!result.timedOut && result.status == 0, "a download under way, limit reached: the script ended")
            check(result.calls.isEmpty, "… and left Steam alone: \(result.calls)")
        }

        // A paused download, or the leftover of one without a manifest, doesn't hold Steam.
        let leftovers: [(String, Int?)] = [("paused", 1538), ("leftover without manifest", nil)]
        for (name, flags) in leftovers {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            world.download(456, flags: flags)
            let result = world.run()
            check(shutDown(result.calls), "a \(name) download doesn't hold Steam: \(result.calls)")
        }

        // One paused and one running: running counts.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            world.download(1, flags: 1538)
            world.download(2, flags: 1026)
            let result = world.run(limit: -1)
            check(result.calls.isEmpty, "a paused and a running download: the running one counts: \(result.calls)")
        }

        // A game that runs holds the script – and Nightforge isn't opened again after the limit.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (500, #"C:\Program Files (x86)\Steam\steamapps\common\Some Game\game.exe"#)])
            let result = world.run(limit: -1)
            check(!result.timedOut && result.status == 0, "a game runs, limit reached: the script ended")
            check(result.calls.isEmpty, "… without opening Nightforge or ending Steam: \(result.calls)")
        }

        // Steam goes at once unless a game ran (or was asked to start) in the last five minutes: then the
        // 30 s for its cloud saves come first.
        let waits: [(String, Int?, Bool)] = [("no game for a long time", nil, false), ("a game 10 minutes ago", now() - 600, false),
                                              ("a game a minute ago", now() - 60, true), ("a game just now", now(), true)]
        for (name, lastGame, waits30) in waits {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            let result = world.run(lastGame: lastGame)
            check(shutDown(result.calls), "\(name): Steam and the wineserver were ended: \(result.calls)")
            check(sleeps(world).contains("30") == waits30, "\(name): \(waits30 ? "waits 30 s for the cloud saves" : "no 30 s wait") (slept \(sleeps(world)))")
        }

        // A game seen running while the script waits counts as one that just ended: the cloud saves get their 30 s.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (500, #"C:\Program Files (x86)\Steam\steamapps\common\Some Game\game.exe"#)])
            QuitScriptTest.write("200\t\(steam)\n", to: world.later)
            let result = world.run(app: "", switchAfter: 3)
            check(!result.timedOut && shutDown(result.calls), "a game ends while the script waits: then Steam is ended: \(result.calls)")
            check(sleeps(world).contains("30"), "… after the 30 s for the cloud saves (slept \(sleeps(world)))")
        }

        // No "-shutdown" for a Steam that isn't running (it would start one); the Wine session is ended all the same.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(100, "/usr/sbin/cfprefsd agent")])
            let result = world.run()
            check(!result.calls.contains { $0.contains("-shutdown") }, "Steam isn't running: no -shutdown: \(result.calls)")
            check(result.calls.contains("wineserver -k"), "… the wineserver is ended all the same")
        }

        // A Steam that ignores "-shutdown": asked once, then the wineserver goes.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            let result = world.run()
            check(result.calls.filter { $0.contains("-shutdown") }.count == 1, "-shutdown is asked once: \(result.calls)")
            check(result.calls.last == "wineserver -k", "… and when Steam stays, the wineserver is ended: \(result.calls)")
        }

        print(failures == 0 ? "✓ QuitScript" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
