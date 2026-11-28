// Checks the steps of Engine.stopSteam with a Steam of its own (nothing real is asked or ended):
// tests/SteamStopTest/run.sh
import Foundation

@main
struct SteamStopTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A Steam that is running for `lifetime` asks, installing for `installFor` asks, and what was done to it.
    final class FakeSteam {
        var asks = 0
        var installAsks = 0
        var shutdowns = 0
        var hardStops = 0
        let lifetime: Int?
        let installFor: Int
        /// It ends once its update has been asked about this often (the player quit it, its restart).
        let goneAfterInstallAsks: Int?
        /// It ends when asked to shut down (like Steam normally does), after this many more asks; nil: it ignores it.
        let endsAfterShutdown: Int?
        var shutdownAt: Int?
        /// After its hard stop it is still listed for this many asks (a process a moment from its end); nil: for good.
        let listedAfterHardStop: Int?
        var hardStopAt: Int?

        init(lifetime: Int? = nil, installFor: Int = 0, goneAfterInstallAsks: Int? = nil, endsAfterShutdown: Int? = 1,
             listedAfterHardStop: Int? = 0) {
            self.lifetime = lifetime
            self.installFor = installFor
            self.goneAfterInstallAsks = goneAfterInstallAsks
            self.endsAfterShutdown = endsAfterShutdown
            self.listedAfterHardStop = listedAfterHardStop
        }

        func running() -> Bool {
            asks += 1
            if let hardStopAt {
                guard let listedAfterHardStop else { return true }
                return asks <= hardStopAt + listedAfterHardStop
            }
            if let lifetime, asks > lifetime { return false }
            if let goneAfterInstallAsks, installAsks >= goneAfterInstallAsks { return false }
            if let shutdownAt, let endsAfterShutdown { return asks <= shutdownAt + endsAfterShutdown }
            return true
        }

        func installing() -> Bool {
            installAsks += 1
            return installAsks <= installFor
        }

        func shutdown() { shutdowns += 1; shutdownAt = asks }

        func hardStop() { hardStops += 1; hardStopAt = asks }
    }

    static func stop(_ steam: FakeSteam, installWait: Int = 120, endWait: Int = 20, goneWait: Int = 10) async {
        try? await Engine.stopSteam(URL(fileURLWithPath: "/nonexistent/wine"), running: steam.running, installing: steam.installing,
                                    shutdown: { _ in steam.shutdown() }, hardStop: { _ in steam.hardStop() },
                                    pause: .milliseconds(1), installWait: installWait, endWait: endWait, goneWait: goneWait)
    }

    /// After steam.exe: the rest of Steam ends by itself, and a new Steam waits for that (22.11.2026: started 2–5 s
    /// after the last one ended, Steam took 27–32 s, its web helper and service still about).
    static func leftovers() async {
        let ps = [#"C:\Program Files (x86)\Steam\steam.exe -silent -noverifyfiles"#,
                  #"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe -lang=de "--user-data-dir=C:\users\x""#,
                  #"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper_real.exe --type=gpu-process"#,
                  #"C:\Program Files (x86)\Common Files\Steam\SteamService.exe /RunAsService"#,
                  #"C:\Program Files (x86)\Steam\bin\gldriverquery64.exe"#,
                  #"C:\Program Files (x86)\Steam\bin\vulkandriverquery.exe"#,
                  #"C:\Program Files (x86)\Steam\steamapps\common\Game\game.exe --steam.exe"#,
                  #"C:\windows\system32\services.exe"#, "/opt/wine/bin/wineserver",
                  #"C:\Program Files (x86)\Steam\notsteam.exe steamservice.exe"#]
        check(Engine.steamProcessNames(in: ps) == ["gldriverquery64.exe", "steam.exe", "steamservice.exe", "steamwebhelper.exe",
                                                    "steamwebhelper_real.exe", "vulkandriverquery.exe"],
              "Steam's programs by their file name, each once; a game, Wine's services and an argument that names one don't count")
        check(Engine.steamProcessNames(in: []).isEmpty, "nothing running: none")

        func run(_ lists: [[String]?], limit: Int = 15, service: Int = 5) async -> (looks: Int, log: [String]) {
            var lists = lists, looks = 0, log: [String] = []
            let steam = FakeSteam()
            try? await Engine.stopSteam(URL(fileURLWithPath: "/nonexistent/wine"), running: steam.running,
                                        leftovers: { looks += 1; return lists.count > 1 ? lists.removeFirst() : lists.first ?? [] },
                                        installing: steam.installing, shutdown: { _ in steam.shutdown() },
                                        hardStop: { _ in steam.hardStop() }, pause: .milliseconds(1),
                                        leftoverWait: limit, serviceWait: service, log: { log.append($0) })
            check(steam.hardStops == 0, "(nothing hard: Steam ended when asked)")
            return (looks, log)
        }
        let clean = await run([[]])
        check(clean.looks == 1 && clean.log.isEmpty, "nothing left of it: Steam goes on at once, no line")
        let helper = await run([["steamwebhelper.exe", "steamservice.exe"], ["steamwebhelper.exe"], []])
        check(helper.looks == 3 && helper.log == ["Steam's last processes ended 0.002 s after steam.exe, last steamwebhelper.exe"],
              "its web helper ends two pauses later: waited for, and said how long and what went last")
        let never = await run([["steamwebhelper.exe"]], limit: 6)
        check(never.looks == 7 && never.log == ["Steam's processes still there 0.006 s after steam.exe: steamwebhelper.exe – Steam goes on without waiting longer"],
              "one that doesn't end: the limit, then on as before, with the names – nothing ended")
        let service = await run([["steamservice.exe"]], limit: 15, service: 3)
        check(service.looks == 4 && service.log.first?.contains(" 0.003 s after steam.exe: steamservice.exe") == true,
              "Steam's service alone (a Windows service, it may stay): its own shorter limit")
        let both = await run([["steamservice.exe", "steamwebhelper.exe"]], limit: 8, service: 3)
        check(both.looks == 9, "the service beside the web helper: the whole limit")
        let blind = await run([nil])
        check(blind.looks == 1 && blind.log.isEmpty, "no process list: no wait, as before")

        // The log says the wait in seconds, whatever the pause (S3, 23.11.2026).
        check(Engine.seconds(1, of: .seconds(1)) == "1" && Engine.seconds(3, of: .milliseconds(250)) == "0.75"
              && Engine.seconds(60, of: .milliseconds(250)) == "15" && Engine.seconds(2, of: .milliseconds(1)) == "0.002"
              && Engine.seconds(0, of: .seconds(1)) == "0", "a wait in seconds, no trailing zeros")
        // Before a Steam starts again it looks four times a second, up to the same 15 s (5 s for the service alone): on
        // 23.11. at 06:37 Steam's service went 0.6 s after steam.exe, the whole seconds made that 1 s before the game.
        check(Engine.steamLeftoverLooks == 4 && 1000 % Engine.steamLeftoverLooks == 0 && Engine.steamLeftoverWait == 15
              && Engine.steamServiceWait == 5, "four looks a second, the same limits")

        // Only a stop before Steam's files are touched waits for the rest of Steam (S3): a stop that the session's end
        // or Steam for Mac follows went on at once before 22.11., and a Steam that starts again waits anyway.
        let sources = ((try? FileManager.default.contentsOfDirectory(atPath: "Sources/Nightforge")) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .map { (try? String(contentsOfFile: "Sources/Nightforge/" + $0, encoding: .utf8)) ?? "" }
        let waiting = sources.flatMap { $0.components(separatedBy: "\n") }.filter { $0.contains("stopSteam(") && $0.contains("leftovers: true") }
        check(waiting.count == 4 && waiting.allSatisfy { $0.contains("endWait: Engine.filesEndWait") },
              "the four stops before Steam's files are touched wait for the rest of Steam (\(waiting.count))")
        let engineText = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        check(engineText.contains("static func stopSteam(_ wine: URL, endWait: Int = 20, leftovers: Bool = false)")
              && engineText.contains("leftovers: { leftovers ? steamLeftovers : [] }"), "every other stop goes on once steam.exe is gone")

        // Every start of Steam in the background after one ended – by "-shutdown", with its session (stopAll, a new
        // session for msync, Retina or the library) – waits the same way first (19:32 on 22.11.: ended :23, started :24).
        let engine = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        let silentStarts = engine.components(separatedBy: "try startSteam(wine, arguments: [\"-silent\"])").dropLast()
        check(silentStarts.count == 3 && silentStarts.allSatisfy { $0.hasSuffix("await waitForSteamToEnd()\n            ") || $0.hasSuffix("await waitForSteamToEnd()\n        ") },
              "each of the three background starts after an end waits for the last Steam first (\(silentStarts.count))")
    }

    /// Every end of the Wine session says why in the log ("Wine session ends: …"), by a name, never a value: at 19:32
    /// on 22.11.2026 Steam ended with its session and no line said why. Read from the sources – stopAll itself ends
    /// real processes, so it isn't called here.
    static func sessionEndReasons() {
        let folder = URL(fileURLWithPath: "Sources/Nightforge")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var calls = 0, without: [String] = [], reasons: [String] = []
        let call = try! NSRegularExpression(pattern: #"stopAll\(([^()]*(\([^()]*\))?[^()]*)\)"#)
        let reason = try! NSRegularExpression(pattern: #"reason: "([^"]*)""#)
        for file in files where file.pathExtension == "swift" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let ns = text as NSString
            for match in call.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let inside = ns.substring(with: match.range(at: 1))
                if inside.hasPrefix("_ wine: URL") { continue }  // the declaration
                calls += 1
                if let found = reason.firstMatch(in: inside, range: NSRange(location: 0, length: (inside as NSString).length)) {
                    reasons.append((inside as NSString).substring(with: found.range(at: 1)))
                } else if !inside.contains("reason: reason") {
                    without.append(file.lastPathComponent + ": stopAll(" + inside + ")")
                }
            }
        }
        check(calls >= 14 && without.isEmpty, "every end of the session names its reason (\(calls) calls; without: \(without))")
        check(reasons.allSatisfy { !$0.isEmpty && !$0.contains("\\(") && !$0.contains("/") }, "a reason is a name: no value, no path")
        let engine = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        check(engine.contains(#"GameLog.note("Wine session ends: \(reason)")"#), "and stopAll writes it down first")
    }

    /// Steam that didn't end after "-shutdown" (Engine.hardStopSteam): the session ends only with no game in it.
    static func hardStopRule() {
        let wine = URL(fileURLWithPath: "/nowhere/bin/wine")
        for (running, ends, case_) in [(false, true, "no game"), (true, false, "a game in the session"),
                                       (nil, false, "no process list")] as [(Bool?, Bool, String)] {
            var stops: [String] = [], notes: [String] = []
            Engine.hardStopSteam(wine, gameRunning: running, stop: { stops.append($0.path + " " + $1) }, log: { notes.append($0) })
            check(ends ? stops == ["/nowhere/bin/wine Steam didn't end after -shutdown"] && notes.isEmpty
                       : stops.isEmpty && notes == ["Steam didn't end, and a game runs in its session: it's left as it is"],
                  "hard stop, \(case_): \(stops) \(notes)")
        }
    }

    /// Before a Steam starts again (Engine.waitForSteamToEnd): four looks a second until the last one's rest is gone.
    static func waitToEndRule() async {
        var looks = 0, notes: [String] = []
        let began = Date()
        await Engine.waitForSteamToEnd(leftovers: { looks += 1; return looks <= 2 ? ["steamservice.exe"] : [] }, log: { notes.append($0) })
        let took = Date().timeIntervalSince(began)
        check(looks == 3 && took >= 0.45 && took < 2, "two quarter-second pauses for Steam's service: \(looks) looks, \(took) s")
        check(notes == ["Steam's last processes ended 0.5 s after steam.exe, last steamservice.exe"], "the log says how long: \(notes)")
        looks = 0; notes = []
        await Engine.waitForSteamToEnd(leftovers: { looks += 1; return [] }, log: { notes.append($0) })
        check(looks == 1 && notes.isEmpty, "nothing left: no wait, no line")
        await Engine.waitForSteamToEnd(leftovers: { nil }, log: { notes.append($0) })
        check(notes.isEmpty, "no process list: no wait")
    }

    /// A Wine session that came up without Wine's network driver (Engine.sessionBootBroken; 23.11.2026, 11:34): told by
    /// Steam's own line, or by mountmgr.sys and steam.exe in a new session with no nsiproxy.sys 15 s on.
    static func brokenSessionRule() {
        func loaded(_ pid: String, _ file: String) -> String {
            #"\#(pid):\#(pid):trace:loaddll:build_module Loaded L"C:\\windows\\system32\\\#(file)" at 0000000140000000: builtin"#
        }
        let boot = [loaded("0028", "wineboot.exe"), loaded("0034", "services.exe"), loaded("0044", "winedevice.exe"),
                    loaded("0044", #"drivers\\mountmgr.sys"#), loaded("006c", "plugplay.exe")]
        let steam = #"0020:0024:trace:loaddll:build_module Loaded L"C:\\Program Files (x86)\\Steam\\steam.exe" at 0000000140000000: native"#
        let said = #"src\common\net_misc.cpp (252) : Assertion Failed: CalcUnIPThisBox - GetAdaptersAddresses returned 2"#
        let broken = (boot + [steam, said]).joined(separator: "\n")
        let quiet = (boot + [steam]).joined(separator: "\n")
        let good = (boot + [loaded("0044", #"drivers\\nsiproxy.sys"#), steam]).joined(separator: "\n")
        check(Engine.sessionBootBroken(log: broken, age: 1), "Steam's own line tells it at once")
        check(Engine.sessionBootBroken(log: quiet, age: 15) && !Engine.sessionBootBroken(log: quiet, age: 14),
              "without it: no nsiproxy.sys 15 s after Steam's start, not before")
        check(!Engine.sessionBootBroken(log: good, age: 60), "nsiproxy.sys came: the session is whole")
        check(!Engine.sessionBootBroken(log: steam, age: 60), "Steam in a session that was there already: nothing to tell by")
        check(!Engine.sessionBootBroken(log: (boot + [steam]).filter { !$0.contains("mountmgr") }.joined(separator: "\n"), age: 60),
              "no mountmgr.sys yet either: the session is still on its way")
        check(!Engine.sessionBootBroken(log: boot.joined(separator: "\n"), age: 60), "no steam.exe: not Steam's start")
        check(!Engine.sessionBootBroken(log: quiet + "\n" + good, age: 60), "a newer session that came up whole counts, not the one before")
        check(!Engine.sessionBootBroken(log: "", age: 60) && !Engine.sessionBootBroken(log: "Steam started", age: 60),
              "without loaddll lines (another WINEDEBUG) only Steam's own line tells")
        // N4: a game inherits Steam's stderr and loads steamclient64.dll, so after a game's first program the line may be its own.
        let game = #"0120:0124:trace:loaddll:build_module Loaded L"C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\game.exe" at 0000000140000000: native"#
        let helper = #"00cc:00d0:trace:loaddll:build_module Loaded L"C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win64\\steamwebhelper.exe" at 0000000140000000: native"#
        let good2 = (boot + [loaded("0044", #"drivers\\nsiproxy.sys"#), steam, helper]).joined(separator: "\n")
        check(Engine.sessionBootBroken(log: good2 + "\n" + said, age: 60), "after Steam's own programs the line is still Steam's")
        check(!Engine.sessionBootBroken(log: good2 + "\n" + game + "\n" + said, age: 60), "after a game's first program: not counted")
        check(Engine.sessionBootBroken(log: said + "\n" + game, age: 1), "said before the game came: counted")
        check(Engine.SessionBootScan.wineOrSteam(Substring(loaded("0028", "WINEBOOT.EXE"))), "Wine's folder in any case")
        // N3: read in pieces it says what the whole says, and a look reads only what came since the last one.
        for text in [broken, quiet, good, good2 + "\n" + game + "\n" + said, quiet + "\n" + good] {
            var pieces = Engine.SessionBootScan()
            for line in text.split(separator: "\n") { pieces.read(line: line) }
            check(pieces.broken(age: 60) == Engine.sessionBootBroken(log: text, age: 60), "line by line as a whole")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("boot-scan-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        let head = (boot + [steam]).joined(separator: "\n") + "\n"
        try? Data((head + "src\\common\\net_misc.cpp (252) : Assertion Failed: CalcUnIPThisBox - GetAdaptersAdd").utf8).write(to: file)
        var state = Engine.scanGrowth(of: file, state: (mark: 0, readTo: 0, scan: Engine.SessionBootScan()))
        check(state.readTo == UInt64(head.utf8.count) && !state.scan.broken(age: 1), "half a line waits for the next look")
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("resses returned 2\n".utf8))
            try? handle.close()
        }
        state = Engine.scanGrowth(of: file, state: state)
        check(state.scan.broken(age: 1), "the next look reads the rest of the line")
        let size = UInt64((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0)
        check(state.readTo == size, "and stands at the end")
        try? Data((loaded("0028", "wineboot.exe") + "\n").utf8).write(to: file)
        state = Engine.scanGrowth(of: file, state: state)
        check(!state.scan.broken(age: 60) && state.readTo < size, "a shorter log is a fresh one: read anew")
        let engineSource = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        check(engineSource.contains("bootScan.withLock") && !engineSource.contains("sessionBootBroken(log: GameLog.text(since: mark)"),
              "steamSessionBroken keeps its scan instead of reading 4 MB each look")
        check(LibraryModel.steamSignInStep(signedIn: false, running: true, waited: 0, quietFor: 0, sessionBroken: true) == .stuck,
              "before a game: a broken session is stuck at once")
        check(LibraryModel.steamSignInStep(signedIn: true, running: true, waited: 0, quietFor: 0, sessionBroken: true) == .signedIn,
              "signed in all the same: nothing to restart")
        // The watch after Steam's start and the start of a game act on it: a new session, never with a Windows game in it.
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(model.contains("Engine.steamSessionBroken() && Engine.windowsGameRunningKnown == false")
              && model.contains("restartStuckSteam(wine, freshSession: Self.brokenSessionReason, hung: true)"),
              "the watch: a new session at once, with no game in it")
        check(model.contains("steamSessionBroken ? await Engine.offMain { Engine.windowsGameRunningKnown == false } : false"),
              "the start of a game: a new session only with no Windows game in it")
        let engine = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        check(engine.contains("if fresh { steamStartLogMark = GameLog.mark() }\n            try RosettaSupport.run(process)"),
              "the mark is taken right before Steam's process starts")
        check(!LibraryModel.brokenSessionReason.contains("/") && !LibraryModel.brokenSessionReason.isEmpty, "the reason is a name")
        // Audit N1: a broken session never counts against the engine, wherever a Steam start is judged – also after the
        // quick restart, when the new session is broken again.
        if let judged = model.range(of: "private func steamStartFailed(since began: Date) async -> Bool {"),
           let broken = model.range(of: "Engine.steamSessionBroken()", range: judged.upperBound..<model.endIndex),
           let counted = model.range(of: "SteamStartCheck.judge(", range: judged.upperBound..<model.endIndex) {
            check(broken.lowerBound < counted.lowerBound, "steamStartFailed asks about the session before it judges the start")
        } else {
            check(false, "steamStartFailed, its question about the session and its judgement are found")
        }
        check(model.components(separatedBy: "await steamStartFailed(since:").count - 1 >= 2,
              "every judgement of a Steam start goes through steamStartFailed (the watch and the restart)")
    }

    /// A Steam on its way out isn't taken for a running one (23.11.2026, 19:57: the quit script of the Nightforge just
    /// quit had asked it to end, the new one left it, and only the 45 s watch for a hung start brought it back).
    static func endingSteamRule() async {
        let start = "[2026-11-23 19:48:38] Client version: 1794536281"
        let ask = #"[2026-11-23 19:57:45] ExecCommandLine: ""C:\Program Files (x86)\Steam\steam.exe" -noverifyfiles -shutdown""#
        let own = #"[2026-11-23 19:48:44] ExecCommandLine: ""C:\Program Files (x86)\Steam\steam.exe" -no-cef-sandbox -silent""#
        let bootUp = "[2026-11-23 19:48:38] Startup - updater built Nov 12 2026 18:00:27\r\n[2026-11-23 19:48:38] Verification skipped"
        let bootDown = bootUp + "\r\n[2026-11-23 19:57:47] Shutdown"
        check(Engine.steamEnding(console: [start, own, ask].joined(separator: "\n"), bootstrap: bootUp),
              "asked to -shutdown since its start: ending")
        check(!Engine.steamEnding(console: [start, own].joined(separator: "\n"), bootstrap: bootUp), "only its own start line: running")
        check(!Engine.steamEnding(console: [ask, start, own].joined(separator: "\n"), bootstrap: bootUp),
              "a -shutdown before its start was the last Steam's")
        check(Engine.steamEnding(console: [start, own].joined(separator: "\n"), bootstrap: bootDown), "the bootstrapper's Shutdown last: ending")
        check(!Engine.steamEnding(console: "", bootstrap: bootDown + "\r\n[2026-11-23 19:58:37] Startup - updater built Nov 12 2026"),
              "a Startup after the Shutdown: the next one runs")
        check(!Engine.steamEnding(console: "", bootstrap: ""), "no logs: nothing ending")

        var notes: [String] = []
        var looks = 0
        let gone = await Engine.waitForEndingSteam(running: { looks += 1; return looks <= 3 }, pause: .milliseconds(1), limit: 80,
                                                   log: { notes.append($0) })
        check(gone && looks == 4, "waited until it was gone (\(looks) looks)")
        check(notes.count == 1 && notes[0].contains("on its way out") && notes[0].contains("gone after 0.003 s"), "and says so: \(notes)")
        notes = []
        let stays = await Engine.waitForEndingSteam(running: { true }, pause: .milliseconds(1), limit: 5, log: { notes.append($0) })
        check(!stays && notes.count == 1 && notes[0].contains("still runs after 0.005 s"), "a Steam that stays is left after the limit: \(notes)")
        check(Engine.steamEndingWait * 4 == 80, "20 s at most, as stopSteam gives one it asked itself")

        // In ensureSteamRunning: before deciding on "runs" – never with a game in its session, nor during an update.
        let engine = (try? String(contentsOfFile: "Sources/Nightforge/Engine.swift", encoding: .utf8)) ?? ""
        let body = engine.components(separatedBy: "static func ensureSteamRunning(").dropFirst().first ?? ""
        let wait = body.range(of: "await waitForEndingSteam()")
        let decide = body.range(of: "if isSteamRunning {")
        check(wait != nil && decide != nil && wait!.lowerBound < decide!.lowerBound, "the wait comes before the decision")
        check(body.contains("steamEnding,") && body.contains("!gameKeepsSession(ownProcesses()") && body.contains("!= .installing {"),
              "only with no game in the session and no update going in")
    }

    static func main() async {
        await leftovers()
        await endingSteamRule()
        sessionEndReasons()
        hardStopRule()
        await waitToEndRule()
        brokenSessionRule()
        // Not running: nothing is done – above all no "-shutdown", which would start a Steam.
        let off = FakeSteam(lifetime: 0)
        await stop(off)
        check(off.shutdowns == 0 && off.hardStops == 0, "Steam isn't running: no -shutdown, no hard stop")

        // Running, and ends when asked: one -shutdown, no hard stop.
        let normal = FakeSteam()
        await stop(normal)
        check(normal.shutdowns == 1 && normal.hardStops == 0, "a Steam that ends when asked: one -shutdown, no hard stop (\(normal.shutdowns)/\(normal.hardStops))")

        // Running and ignoring it: -shutdown once, then the hard way after the wait.
        let stubborn = FakeSteam(endsAfterShutdown: nil)
        await stop(stubborn, endWait: 5)
        check(stubborn.shutdowns == 1 && stubborn.hardStops == 1, "a Steam that ignores -shutdown: asked once, then wineserver -k (\(stubborn.shutdowns)/\(stubborn.hardStops))")

        // Gone during the wait for its update: no -shutdown (it would start a new one), nothing hard either.
        let gone = FakeSteam(installFor: 100, goneAfterInstallAsks: 3)
        await stop(gone)
        check(gone.shutdowns == 0 && gone.hardStops == 0, "Steam ended while its update went in: no -shutdown for a Steam that isn't there (\(gone.shutdowns)/\(gone.hardStops))")

        // An update that never ends in the log is waited for only so long, then Steam is asked.
        let stale = FakeSteam(installFor: 1_000_000)
        await stop(stale, installWait: 7)
        check(stale.installAsks == 7 && stale.shutdowns == 1, "an update that never ends is waited for 7 pauses, then -shutdown (\(stale.installAsks) looks, \(stale.shutdowns) shutdowns)")

        // Still listed a moment after its hard stop (The Forest's move, 5.11.2026): stopSteam returns only once
        // it's gone, so the move's look right after doesn't take it for a Steam started again.
        let lingering = FakeSteam(endsAfterShutdown: nil, listedAfterHardStop: 3)
        await stop(lingering, endWait: 5)
        check(lingering.hardStops == 1 && !lingering.running(), "a Steam still listed after its hard stop is waited for until it's gone")
        // One that never goes holds nothing up for ever: back after `goneWait`, with one hard stop.
        let stuck = FakeSteam(endsAfterShutdown: nil, listedAfterHardStop: nil)
        await stop(stuck, endWait: 5, goneWait: 4)
        check(stuck.hardStops == 1 && stuck.asks == 1 + 1 + 5 + 4, "a Steam that never goes: one hard stop, then 4 more looks (\(stuck.asks) looks)")

        // What a move says after the stop: nothing once Steam is gone – also a moment late – and otherwise which it is.
        var answers: [Bool?] = [true, true, false]
        var looks = 0
        let late = await Engine.steamStillThere(wait: 5, pause: .milliseconds(1)) { looks += 1; return answers.removeFirst() }
        check(late == nil && looks == 3, "a Steam that is gone a moment late lets the move go on (\(looks) looks)")
        let still = await Engine.steamStillThere(wait: 3, pause: .milliseconds(1)) { true }
        check(still.map { if case .steamDidNotEnd = $0 { return true } else { return false } } == true,
              "a Steam still running after its stop says so – not \"started again\"")
        answers = [nil, nil, nil, nil]
        let unknown = await Engine.steamStillThere(wait: 3, pause: .milliseconds(1)) { answers.removeFirst() }
        check(unknown.map { if case .steamNotKnown = $0 { return true } else { return false } } == true,
              "no process list: \"can't tell\", not \"started again\"")
        check(DriveError.steamDidNotEnd.localizedDescription != DriveError.steamStarted.localizedDescription
              && DriveError.steamNotKnown.localizedDescription != DriveError.steamStarted.localizedDescription,
              "each of the three has its own words")

        // Within five minutes of a game Steam gets 45 s for its cloud saves before the hard stop, otherwise 20.
        let kept = Engine.lastGameActivity
        Engine.lastGameActivity = Date().addingTimeInterval(-60)
        check(Engine.filesEndWait == 45, "a game a minute ago: 45 s for Steam's end")
        Engine.lastGameActivity = Date().addingTimeInterval(-400)
        check(Engine.filesEndWait == 20, "a game seven minutes ago: 20 s")
        Engine.lastGameActivity = nil
        check(Engine.filesEndWait == 20, "no game: 20 s")
        Engine.lastGameActivity = kept

        // The moves take the stop with that wait and the look that tells the three apart, not a single look.
        let sources = ["DriveMoves.swift", "LibraryModel.swift"].map {
            (try? String(contentsOfFile: "Sources/Nightforge/\($0)", encoding: .utf8)) ?? ""
        }.joined()
        check(!sources.contains("guard !Engine.steamMayBeRunning else { throw DriveError.steamStarted }"),
              "no move throws \"started again\" from one look right after the stop")
        check(sources.components(separatedBy: "Engine.stopSteam(wine, endWait: Engine.filesEndWait, leftovers: true)\n").count == 4
              && sources.components(separatedBy: "if let still = await Engine.steamStillThere() { throw still }").count == 4,
              "the three Windows Steam paths (move, drive download, forget) stop with filesEndWait, wait for the rest of Steam and ask steamStillThere")

        print(failures == 0 ? "✓ SteamStop" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
