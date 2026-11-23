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
            // FAKE_MAC_STEAM: Steam for Mac runs and doesn't go away.
            QuitScriptTest.write("#!/bin/sh\n[ -n \"$FAKE_MAC_STEAM\" ] && exit 0\nexit 1\n", to: bin.appendingPathComponent("pgrep"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("pkill"), executable: true)
            // Stays until it's told to go, as the real one does, and says so.
            QuitScriptTest.write("""
                #!/bin/sh
                echo "caffeinate $*" >> "$FAKE_AWAKELOG"
                trap 'echo ended >> "$FAKE_AWAKELOG"; exit 0' TERM
                /bin/sleep 4 &
                wait
                """, to: bin.appendingPathComponent("caffeinate"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n# lsof: the program of a listed process lies in the data folder (HOME is the world's root, the prefix in it), unless the\n# test lists it as foreign (FAKE_FOREIGN, a pid a line): a stand-in somebody else runs. Its working folder: none.\ncase \"$*\" in\n  *\"-d txt\"*)\n    pid=\"$(echo \"$*\" | sed -n 's/.*-p \\([0-9]*\\).*/\\1/p')\"\n    [ -n \"$FAKE_FOREIGN\" ] && grep -qx \"$pid\" \"$FAKE_FOREIGN\" 2>/dev/null && exit 1\n    printf 'p%s\\nn%s/engine/bin/wine-preloader\\n' \"$pid\" \"$(cd \"$HOME\" && pwd -P)\" ;;\nesac\nexit 0\n", to: bin.appendingPathComponent("lsof"), executable: true)
            QuitScriptTest.write("#!/bin/sh\necho \"$*\" >> \"$FAKE_SLEEPLOG\"\n", to: bin.appendingPathComponent("sleep"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("open"), executable: true)
            // FAKE_HANG: steam.exe -shutdown and osascript don't come back, as with a Steam that doesn't answer.
            let hangs = "case \"$*\" in *-shutdown*|*-e*) [ -n \"$FAKE_HANG\" ] && exec /bin/sleep 20 ;; esac"
            QuitScriptTest.write("#!/bin/sh\n\(record)\n\(hangs)\n", to: bin.appendingPathComponent("osascript"), executable: true)
            QuitScriptTest.write("#!/bin/sh\n\(record)\n\(hangs)\n", to: wine, executable: true)
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
                 switchAfter: Int? = nil, psLimit: Int? = nil, restart: Bool = false, hang: Bool = false,
                 macSteam: Bool = false, gameAtQuit: Bool? = nil, foreign: [Int] = []) -> (calls: [String], status: Int32, timedOut: Bool) {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: sleepLog)
            var environment = ["PATH": bin.path + ":/usr/bin:/bin:/usr/sbin", "FAKE_PS": processList.path, "FAKE_LOG": log.path,
                               "FAKE_PIDFILE": pidFile.path, "FAKE_PIDLOG": pidLog.path, "HOME": root.path]
            if let limit { environment["NIGHTFORGE_QUIT_LIMIT"] = String(limit) }
            if let psLimit { environment["NIGHTFORGE_PS_LIMIT"] = String(psLimit) }
            environment["FAKE_SLEEPLOG"] = sleepLog.path
            try? FileManager.default.removeItem(at: awakeLog)
            environment["FAKE_AWAKELOG"] = awakeLog.path
            if hang {
                environment["FAKE_HANG"] = "1"
                environment["NIGHTFORGE_HANG_LIMIT"] = "1"
            }
            if macSteam { environment["FAKE_MAC_STEAM"] = "1" }
            environment["FAKE_COUNT"] = root.appendingPathComponent("ps-count").path
            // Processes that aren't Nightforge's own: their program lies elsewhere (lsof stand-in).
            let foreignList = root.appendingPathComponent("foreign.txt")
            QuitScriptTest.write(foreign.map(String.init).joined(separator: "\n") + "\n", to: foreignList)
            environment["FAKE_FOREIGN"] = foreignList.path
            if let switchAfter {
                environment["FAKE_PS_LATER"] = later.path
                environment["FAKE_SWITCH"] = String(switchAfter)
            }
            let outcome = Subprocess.run("/bin/bash", [script.path, wine.path, prefix.path, "", macSteam ? "1" : "0", app ?? self.app,
                                                       quitting == 0 ? "" : String(quitting), "1",
                                                       lastGame.map(String.init) ?? "0", "", "", restart ? "1" : "0"]
                                                       + (gameAtQuit.map { [$0 ? "1" : "0"] } ?? []),
                                         environment: environment, timeout: 60)
            let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            return (calls, outcome.status, outcome.timedOut)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        var awakeLog: URL { root.appendingPathComponent("awake.log") }

        /// What the stand-in caffeinate wrote, once `wanted` is in it or a second has gone by: it runs beside the script.
        func awakeCalls(until wanted: String) -> [String] {
            for _ in 0..<40 {
                let text = (try? String(contentsOf: awakeLog, encoding: .utf8)) ?? ""
                if text.contains(wanted) { break }
                Thread.sleep(forTimeInterval: 0.025)
            }
            return ((try? String(contentsOf: awakeLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
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

    /// Engine.shutdownArguments against the script's own $1…$12.
    static func scriptArguments() {
        let arguments = Engine.shutdownArguments(script: "/s.sh", wine: "/w", prefix: "/p", macLibrary: "/m", macSteam: true, app: "/A.app",
                                                 quitting: 42, msync: false, lastGame: Date(timeIntervalSince1970: 1_700_000_000),
                                                 sandbox: ("/helper", "/profile"), restart: false, gameAtQuit: true)
        let pattern = try! NSRegularExpression(pattern: #"([A-Z_]+)="\$\{?([1-9][0-9]*)"#)
        let script = Engine.steamShutdownScript as NSString
        var position: [String: Int] = [:]
        for match in pattern.matches(in: script as String, range: NSRange(location: 0, length: script.length)) {
            position[script.substring(with: match.range(at: 1))] = Int(script.substring(with: match.range(at: 2)))
        }
        let wanted = ["WINE": "/w", "PREFIX": "/p", "MAC_STEAMAPPS": "/m", "QUIT_MAC": "1", "APP": "/A.app", "QUITTING": "42", "MSYNC": "0",
                      "LAST_GAME": "1700000000", "SANDBOX": "/helper", "PROFILE": "/profile", "RESTART": "0", "GAME_AT_QUIT": "1"]
        check(arguments.count == 13 && arguments[0] == "/s.sh" && position.count == 12, "the script and its twelve: \(position)")
        for (name, value) in wanted {
            check(position[name].map { arguments[$0] } == value, "\(name) ($\(position[name] ?? 0)) gets \(value)")
        }
        let off = Engine.shutdownArguments(script: "/s.sh", wine: nil, prefix: "/p", macLibrary: "", macSteam: false, app: "/A.app", quitting: 1,
                                           msync: true, lastGame: nil, sandbox: nil, restart: true, gameAtQuit: false)
        check(off[1] == "" && off[8] == "0" && off[9] == "" && off[10] == "" && off[11] == "1" && off[12] == "0",
              "no Wine, no game time, no sandbox: empty and 0; a restart, no game: \(off)")
    }

    static func main() {
        scriptArguments()
        let probe = World()
        defer { probe.cleanUp() }
        let syntax = Subprocess.run("/bin/bash", ["-n", probe.script.path], timeout: 20)
        check(syntax.succeeded, "the script is valid bash")

        // "Restart Nightforge": a game (a hung one) and a download don't hold it up, the session ends,
        // and Nightforge opens again last (8.11.).
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (400, #"C:\Games\steamapps\common\Hung\Hung.exe"#)])
            world.download(4000, flags: 1026)
            let result = world.run(restart: true)
            check(!result.timedOut && result.status == 0, "restart: the script ended (status \(result.status))")
            check(shutDown(result.calls), "restart: Steam and the wineserver were ended: \(result.calls)")
            check(result.calls.last == "open \(world.app)", "restart: Nightforge opens again, last: \(result.calls)")
            check(!sleeps(world).contains("10"), "restart: no waiting for the game or the download: \(sleeps(world))")
            // Right after a game Nightforge has waited already, where it shows (audit A11).
            let recent = world.run(lastGame: now(), restart: true)
            check(!sleeps(world).contains("30") && recent.calls.last == "open \(world.app)",
                  "restart right after a game: no silent half minute here: \(sleeps(world))")
            check(Engine.cloudSaveWait(since: nil) == 0, "no game: no wait")
            let moment = Date()
            check(Engine.cloudSaveWait(since: moment, now: moment.addingTimeInterval(10)) == 20, "what's left of the 30 s")
            check(Engine.cloudSaveWait(since: moment, now: moment.addingTimeInterval(45)) == 0, "half a minute on: none")
        }

        // A Steam that doesn't answer: the restart goes on all the same and Nightforge comes back (audit 8.11.).
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            let started = Date()
            let result = world.run(restart: true, hang: true)
            check(!result.timedOut && result.status == 0, "a hanging Steam: the script ended (status \(result.status))")
            check(Date().timeIntervalSince(started) < 15, "… after the limit, not after the hang")
            check(result.calls.contains("wineserver -k") && result.calls.last == "open \(world.app)",
                  "… and the session ended, Nightforge opens: \(result.calls)")
        }

        // Steam for Mac that doesn't quit: asked first, then ended, only on a restart.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            let restart = world.run(restart: true, macSteam: true)
            let quit = restart.calls.firstIndex { $0.hasPrefix("osascript") }
            let term = restart.calls.firstIndex(of: "pkill -x steam_osx")
            check(quit != nil && term != nil && quit! < term!, "restart: asked to quit, then ended: \(restart.calls)")
            check(restart.calls.contains("pkill -9 -x steam_osx"), "… by force when it stays: \(restart.calls)")
            check(restart.calls.last == "open \(world.app)", "… and Nightforge opens: \(restart.calls)")
            let plain = world.run(macSteam: true)
            check(plain.calls.contains { $0.hasPrefix("osascript") } && !plain.calls.contains { $0.hasPrefix("pkill") },
                  "an ordinary quit asks and leaves it: \(plain.calls)")
        }

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

        // Nightforge's hold on sleep goes with it: while a download is what the script waits for, its own.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            world.download(123, flags: 1026)
            let result = world.run(limit: -1)
            let calls = world.awakeCalls(until: "caffeinate")
            check(!result.timedOut && calls.first?.hasPrefix("caffeinate -i -w ") == true, "a download under way: the Mac stays awake, for as long as the script runs: \(calls)")
        }
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            world.download(123, flags: 1538)
            _ = world.run()
            check(world.awakeCalls(until: "never").isEmpty, "paused: the Mac may sleep")
        }
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(400, #"C:\Games\steamapps\common\Hung\Hung.exe"#)])
            _ = world.run(limit: -1, app: "")
            check(world.awakeCalls(until: "never").isEmpty, "only a game: nothing of this script's, the game is played by someone")
        }
        do {
            // The download is over (Steam gone from the list here): the hold goes before Steam is ended.
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            QuitScriptTest.write("300\tsomething else\n", to: world.later)
            world.download(123, flags: 1026)
            let result = world.run(app: "", switchAfter: 8)
            let calls = world.awakeCalls(until: "ended")
            check(!result.timedOut && calls.first?.hasPrefix("caffeinate") == true && calls.last == "ended", "the download done: the Mac may sleep again: \(calls)")
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

        // A download whose Steam no longer runs (it ended when Steam for Mac took over) holds nothing: it
        // kept Steam for Mac and the script waiting for 12 hours (It Takes Two, 8.11.).
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(100, "/usr/sbin/cfprefsd agent")])
            world.download(1426210, flags: 1026)
            let result = world.run(limit: 3600)
            check(!result.timedOut && result.status == 0, "a stopped Steam's download: the script ended")
            check(result.calls.contains("wineserver -k") && !sleeps(world).contains("10"),
                  "… without waiting for it, and the session ended: \(result.calls), \(sleeps(world))")
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

        // $12, GAME_AT_QUIT: only a game Nightforge knew of as it quit brings it back at its end (06:56 on 23.11.2026, a
        // test's stand-in named like a game opened a Nightforge just quit). Without $12 (a script from before): as known.
        for (gameAtQuit, opens, case_) in [(true, true, "a game Nightforge knew of"), (false, false, "a game Nightforge didn't know of"),
                                           (nil, true, "a script from before, without $12")] as [(Bool?, Bool, String)] {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (500, #"C:\Program Files (x86)\Steam\steamapps\common\Some Game\game.exe"#)])
            QuitScriptTest.write("200\t\(steam)\n", to: world.later)
            let result = world.run(switchAfter: 3, gameAtQuit: gameAtQuit)
            check(!result.timedOut && result.status == 0, "\(case_): the script ended (status \(result.status))")
            if opens {
                check(result.calls == ["open \(world.app)"], "\(case_): its end opens Nightforge, and Steam stays for it: \(result.calls)")
            } else {
                check(!result.calls.contains("open \(world.app)"), "\(case_): its end doesn't open Nightforge: \(result.calls)")
                check(shutDown(result.calls), "\(case_): Steam is ended once the game is gone: \(result.calls)")
            }
        }
        // A process that only names a game folder but isn't Nightforge's own – its program lies elsewhere, as a test's
        // stand-in – is no game: the script neither waits for it nor opens Nightforge after it (12:08 on 23.11.2026).
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam), (600, #"C:\Program Files (x86)\Steam\steamapps\common\Stand In Game\StandIn.exe"#)])
            let result = world.run(gameAtQuit: true, foreign: [600])
            check(!result.timedOut && !result.calls.contains("open \(world.app)") && shutDown(result.calls),
                  "a stranger's process named like a game: Steam ends, Nightforge stays closed: \(result.calls)")
        }
        check(Engine.gameAtQuit(started: true, windowsGame: nil) && Engine.gameAtQuit(started: false, windowsGame: true)
              && !Engine.gameAtQuit(started: false, windowsGame: nil) && !Engine.gameAtQuit(started: false, windowsGame: false),
              "GAME_AT_QUIT: a game Nightforge started or one in its session; not known is none")
        check(Engine.steamShutdownScript.contains(#"has_own_process '\steamapps\common\'"#)
              && Engine.steamShutdownScript.contains(#"SUPPORT="$(cd "$(dirname "$PREFIX")" 2>/dev/null && pwd -P || dirname "$PREFIX")""#),
              "Windows games count only as Nightforge's own processes, by the program in the data folder")
        do {
            // Known as it quit, but no game in the list any more: nothing to come back for, Steam goes.
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            let result = world.run(gameAtQuit: true)
            check(!result.calls.contains("open \(world.app)") && shutDown(result.calls),
                  "a game known at quit, gone already: Steam ends, Nightforge stays closed: \(result.calls)")
        }

        // A ps that answers nothing (a real one always lists the script) is "unknown", not "no game": the
        // script waits, and after its limit leaves everything as it is. Once ps answers again, it goes on.
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([])
            let result = world.run(app: "", psLimit: 1)
            check(!result.timedOut && result.status == 0 && !result.calls.contains { $0.contains("-shutdown") }
                  && !result.calls.contains("wineserver -k"), "no process list: nothing ended, and it ends at its limit: \(result.calls)")
        }
        do {
            let world = World()
            defer { world.cleanUp() }
            world.processes([])
            QuitScriptTest.write("200\t\(steam)\n", to: world.later)
            let result = world.run(app: "", switchAfter: 6)
            check(!result.timedOut && shutDown(result.calls), "the list comes back without a game: then Steam is ended: \(result.calls)")
        }

        // A game started from Steam's window just as Steam is asked to end: Steam refuses -shutdown then, and
        // `wineserver -k` would end the game as it starts. The stand-in wine brings the game up at -shutdown.
        let game = #"C:\Program Files (x86)\Steam\steamapps\common\Game\Game.exe"#
        for (steamStays, case_) in [(true, "Steam stays for the game"), (false, "Steam ended, the game came up right before the session would")] {
            let world = World()
            defer { world.cleanUp() }
            world.processes([(200, steam)])
            QuitScriptTest.write((steamStays ? "200\t\(steam)\n" : "") + "300\t\(game)\n", to: world.later)
            QuitScriptTest.write("""
                #!/bin/sh
                echo "$(basename "$0") $*" >> "$FAKE_LOG"
                case "$*" in *-shutdown*) cp "\(world.later.path)" "\(world.processList.path)" ;; esac
                """, to: world.wine, executable: true)
            let result = world.run(limit: 2, app: "")
            check(!result.timedOut && result.calls.contains { $0.contains("-shutdown") } && !result.calls.contains("wineserver -k"),
                  "\(case_): the session isn't ended under it, the script waits for the game: \(result.calls)")
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
