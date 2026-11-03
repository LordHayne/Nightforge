// Checks Subprocess.run with its limit, withDeadline and DetachedProcess.waitUntilExit(timeout:) –
// on programs of its own (sleep, echo, sh), never on Nightforge's, Wine's or Steam's:
// tests/SubprocessTest/run.sh
import Foundation

@main
struct SubprocessTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// Seconds a block takes.
    static func timed(_ work: () -> Void) -> TimeInterval {
        let start = Date()
        work()
        return Date().timeIntervalSince(start)
    }

    static func gone(_ pid: pid_t) -> Bool {
        for _ in 0..<50 {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            usleep(20_000)
        }
        return false
    }

    static func main() async {
        // The real ps is never asked: anything that reaches ProcessList without its own stand-in gets nothing.
        ProcessList.program = "/usr/bin/false"
        // The ordinary ways a program ends.
        let echo = Subprocess.run("/bin/echo", ["hello"], capture: true, timeout: 5)
        check(echo.launched && echo.succeeded && !echo.timedOut, "echo: ran and ended well")
        check(echo.text == "hello\n", "echo: its output comes back: \(echo.text.debugDescription)")
        let silent = Subprocess.run("/bin/echo", ["hello"], timeout: 5)
        check(silent.succeeded && silent.output.isEmpty, "without capture, nothing comes back")
        let failed = Subprocess.run("/usr/bin/false", timeout: 5)
        check(failed.launched && failed.status == 1 && !failed.succeeded && !failed.timedOut, "false: status 1")
        let missing = Subprocess.run("/nonexistent/program", timeout: 5)
        check(!missing.launched && !missing.succeeded, "a program that isn't there doesn't start")
        let environment = Subprocess.run("/usr/bin/env", [], environment: ["NIGHTFORGE_TEST": "yes"], capture: true, timeout: 5)
        check(environment.text.contains("NIGHTFORGE_TEST=yes"), "its environment is the one given")

        // A program that runs on is ended, and Subprocess comes back in time.
        var slow = Subprocess.Outcome()
        var seconds = timed { slow = Subprocess.run("/bin/sleep", ["30"], timeout: 0.5) }
        check(slow.timedOut && !slow.succeeded, "sleep 30 with 0.5 s: timed out")
        check(seconds < 4, "… and it was back after \(seconds) s, not 30")

        // One that ignores SIGTERM is killed after the grace period. It tells its pid first.
        var stubborn = Subprocess.Outcome()
        seconds = timed {
            stubborn = Subprocess.run("/bin/sh", ["-c", "echo $$; trap '' TERM; exec /bin/sleep 30"], capture: true,
                                      timeout: 0.5, grace: 0.5)
        }
        check(stubborn.timedOut, "a program that ignores SIGTERM: timed out")
        check(seconds < 5, "… and ended anyway, after \(seconds) s")
        if let pid = pid_t(stubborn.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            check(gone(pid), "… it is gone (\(pid))")
        } else {
            check(false, "the stubborn program told its pid: \(stubborn.text.debugDescription)")
        }

        // What a program wrote before the limit is kept. (3 s: on a Mac busy with other series the shell
        // may need more than one to get to its echo.)
        let partial = Subprocess.run("/bin/sh", ["-c", "echo first; exec /bin/sleep 30"], capture: true, timeout: 3)
        check(partial.timedOut && partial.text == "first\n", "output before the limit is kept: \(partial.text.debugDescription)")

        // Something the program started holds its pipe open: not waited for beyond a moment.
        var held = Subprocess.Outcome()
        seconds = timed { held = Subprocess.run("/bin/sh", ["-c", "(/bin/sleep 3 >&1 &) ; echo done"], capture: true, timeout: 10) }
        check(held.succeeded && held.text == "done\n", "a pipe held open by a child: output is there (\(held.text.debugDescription))")
        check(seconds < 2.5, "… without waiting for the child (\(seconds) s)")

        // The wait with a deadline.
        let quick: Int? = await withDeadline(5) { 42 }
        check(quick == 42, "work that is done in time answers")
        let start = Date()
        let late: Int? = await withDeadline(0.3) { () async -> Int in
            try? await Task.sleep(for: .seconds(20))
            return 7
        }
        check(late == nil, "work that takes too long gives nil")
        check(Date().timeIntervalSince(start) < 3, "… and nobody waits for it")

        // A program of DetachedProcess (without the helper app, as here, a plain child process).
        let quickProgram = DetachedProcess()
        quickProgram.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try? quickProgram.run()
        check(quickProgram.waitUntilExit(timeout: 5) && quickProgram.terminationStatus == 0, "true: ended within the time, status 0")

        let longProgram = DetachedProcess()
        longProgram.executableURL = URL(fileURLWithPath: "/bin/sleep")
        longProgram.arguments = ["30"]
        try? longProgram.run()
        let pid = longProgram.processIdentifier
        check(longProgram.isRunning, "sleep 30 runs")
        check(!longProgram.waitUntilExit(timeout: 0.3), "waiting 0.3 s for it says: still running")
        seconds = timed { longProgram.end(grace: 1) }
        check(!longProgram.isRunning && gone(pid), "end() ended it")
        check(seconds < 4, "… in \(seconds) s")

        let stubbornProgram = DetachedProcess()
        stubbornProgram.executableURL = URL(fileURLWithPath: "/bin/sh")
        stubbornProgram.arguments = ["-c", "trap '' TERM; exec /bin/sleep 30"]
        try? stubbornProgram.run()
        usleep(300_000)  // the shell has to get to its trap
        let stubbornPid = stubbornProgram.processIdentifier
        seconds = timed { stubbornProgram.end(grace: 0.5) }
        check(!stubbornProgram.isRunning && gone(stubbornPid), "end() kills a program that ignores SIGTERM")
        check(seconds < 4, "… in \(seconds) s")

        // The process list, with a stand-in for ps (a real ps answers for every process on the Mac, and
        // is exactly what can hang): its answer; no second ps for a while after one that missed its limit;
        // the last good answer only to whoever may take an old one.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("processlist-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let standIn = work.appendingPathComponent("ps")
        let hangs = work.appendingPathComponent("hang")
        let counter = work.appendingPathComponent("calls")
        let script = "#!/bin/sh\necho x >> '\(counter.path)'\n[ -f '\(hangs.path)' ] && exec /bin/sleep 30\necho \"1 launchd $*\"\n"
        try? Data(script.utf8).write(to: standIn)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standIn.path)
        func calls() -> Int { ((try? String(contentsOf: counter, encoding: .utf8)) ?? "").split(separator: "\n").count }
        ProcessList.program = standIn.path
        // Long enough for the stand-in to answer on a Mac busy with other series (-P 2: at 0.5 s it sometimes
        // didn't even start, and every check after it failed), far below the 30 s of one that hangs. The
        // waits below are measured against it.
        ProcessList.timeout = 3
        ProcessList.pause = 60
        ProcessList.reset()
        let good = ProcessList.ps("pid=,command=")
        check(good?.contains("launchd") == true && good?.contains("-axo pid=,command=") == true, "the list is what ps printed: \(good ?? "nil")")
        check(ProcessList.ps("pid=,command=", stale: true) == good && calls() == 2, "asked again, ps is asked again (\(calls()) calls)")
        try? Data().write(to: hangs)
        var answer: String? = "?"
        seconds = timed { answer = ProcessList.ps("pid=,command=") }
        check(answer == nil, "ps that misses its limit: no list")
        check(seconds >= ProcessList.timeout - 0.1 && seconds < ProcessList.timeout + 3,
              "… after \(seconds) s, at its limit of \(ProcessList.timeout) s, not the stand-in's 30")
        let asked = calls()
        var again: String? = "?"
        seconds = timed { again = ProcessList.ps("pid=,command=") }
        check(again == nil && calls() == asked, "… and for the next minute ps isn't asked at all (\(calls() - asked) more calls)")
        check(seconds < ProcessList.timeout / 3, "… so nobody waits (\(seconds) s, the limit is \(ProcessList.timeout) s)")
        check(ProcessList.ps("pid=,command=", stale: true) == good, "whoever may take an old list gets the last good one")
        if case .old(let text) = ProcessList.listing("pid=,command=", allowOld: true) {
            check(text == good, "… marked as old")
        } else {
            check(false, "an old list is marked as old")
        }
        if case .unavailable = ProcessList.listing("pid=,command="), ProcessList.listing("pid=,command=").value == nil {
        } else {
            check(false, "without allowOld there is no list in the pause")
        }
        check(ProcessList.ps("pid=,ppid=", stale: true) == nil, "… but only of the same kind (other columns: none yet)")
        try? FileManager.default.removeItem(at: hangs)
        check(ProcessList.ps("pid=,command=") == nil, "ps answers again, but the pause isn't over yet")
        ProcessList.reset()
        check(ProcessList.ps("pid=,command=") != nil, "after the pause (here: a reset), ps is asked again")

        // A ps that can't even be started (extra review, item 2): the pause holds for it too, no new try at every look.
        let notThere = work.appendingPathComponent("no-such-ps")
        ProcessList.program = notThere.path
        ProcessList.reset()
        check(ProcessList.ps("pid=,command=") == nil, "a ps that can't be started: no list")
        try? FileManager.default.copyItem(at: standIn, to: notThere)  // it could be started from now on
        let askedBefore = calls()
        check(ProcessList.ps("pid=,command=") == nil && calls() == askedBefore,
              "… and for the next minute it isn't tried again (\(calls() - askedBefore) more calls)")
        ProcessList.reset()
        check(ProcessList.ps("pid=,command=") != nil, "… after the pause it is")
        ProcessList.program = standIn.path

        // A source handed in answers instead, and no program is started.
        let before = calls()
        ProcessList.source = { columns in "from the source: \(columns)" }
        check(ProcessList.ps("pid=,ppid=") == "from the source: pid=,ppid=" && ProcessList.ps("pid=", stale: true) == "from the source: pid=",
              "a source handed in is what ps says")
        check(calls() == before, "… and ps isn't run (\(calls() - before) more calls)")
        ProcessList.source = nil

        // Down is not empty: no list at all ("not known") against a list without a process ("none").
        let marker = #"\steamapps\common\Some Game\"#
        let folders = [marker.lowercased(): "steam:1"]
        ProcessList.source = { _ in nil }
        check(ProcessList.listing("pid=").value == nil, "a source without an answer: no list")
        check(GameProcesses.lookup(allowOld: true).value == nil && GameProcesses.table().isEmpty, "GameProcesses: no list, table() is [] for what acts")
        check(GameProcesses.runningNow(folders) == nil, "the watcher is told 'not known', not 'no game'")
        check(GameProcesses.runningNow([:]) == [:], "no games to look for: nothing to ask")
        check(GameProcesses.curtainLook(marker: marker, folder: nil, front: nil) == nil, "the curtain's look decides nothing")
        check(Engine.ownProcessesKnown() == nil && Engine.steamRunningKnown == nil && Engine.windowsGameRunningKnown == nil,
              "Engine: not known")
        check(Engine.steamMayBeRunning && Engine.windowsGameRunning && !Engine.isSteamRunning,
              "… what mustn't happen to a Steam or under a game waits; plain isSteamRunning stays false")
        ProcessList.source = { _ in "" }
        check(GameProcesses.runningNow(folders) == [:], "an empty list is 'no game'")
        check(GameProcesses.curtainLook(marker: marker, folder: nil, front: nil) == GameProcesses.CurtainLook(pids: [], companion: false, askers: []),
              "the curtain's look sees no process")
        check(Engine.ownProcessesKnown()?.isEmpty == true && Engine.steamRunningKnown == false && Engine.windowsGameRunningKnown == false,
              "Engine: known to be none")
        check(!Engine.steamMayBeRunning && !Engine.windowsGameRunning, "… so nothing waits")
        ProcessList.source = { columns in columns == "pid=,ppid=,command="
            ? "500 1 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Some Game\\game.exe -x\n" : "" }
        check(GameProcesses.runningNow(folders) == ["steam:1": 500], "a running game is found: \(String(describing: GameProcesses.runningNow(folders)))")
        check(GameProcesses.curtainLook(marker: marker, folder: nil, front: 500)?.pids == [500], "and the curtain sees it")
        ProcessList.source = nil

        await processEnd()
        print(failures == 0 ? "✓ Subprocess" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// ProcessEnd: the end of a process from the kernel, the moment it comes – what Steam for Mac's
    /// quit waits for now, instead of a look every second (MacSteam.quit, TestSteam.quit).
    static func processEnd() async {
        func started(_ seconds: String) -> Process? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = [seconds]
            return (try? process.run()) == nil ? nil : process
        }
        guard let short = started("0.4"), let long = started("30") else { return check(false, "sleep started") }
        var begin = Date()
        let ended = await ProcessEnd.wait([short.processIdentifier], timeout: 10)
        let took = Date().timeIntervalSince(begin)
        check(ended && took >= 0.3 && took < 0.9, "its end noticed as it comes, not a second later: \(took) s")
        check(await ProcessEnd.wait([short.processIdentifier], timeout: 10), "already gone: at once")
        begin = Date()
        let runsOn = await ProcessEnd.wait([long.processIdentifier], timeout: 0.5)
        check(!runsOn && abs(Date().timeIntervalSince(begin) - 0.5) < 0.3, "one running on: false after the time given")
        guard let second = started("0.3") else { return check(false, "sleep started") }
        begin = Date()
        let both = Task { await ProcessEnd.wait([second.processIdentifier, long.processIdentifier], timeout: 5) }
        try? await Task.sleep(for: .milliseconds(600))
        long.terminate()
        check(await both.value && Date().timeIntervalSince(begin) >= 0.5, "two: only once both have ended")
        let none = await ProcessEnd.wait([], timeout: 1), unknown = await ProcessEnd.wait([-1, 0], timeout: 1)
        check(none && unknown, "none to wait for: done")
    }
}
