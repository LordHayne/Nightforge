// Checks DetachedProcess and Nightforge Helper (wrapper/nightforge-helper.c):
// tests/DetachedProcessTest/run.sh [--dock]
// With --dock it also launches a small test app twice and checks that macOS forgets it once it has
// quit, while a program it started runs on – the bug the helper is for (two Nightforge icons in the
// Dock). Its Dock icon shows for a moment each time.
import AppKit
import Foundation

@main
struct DetachedProcessTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func parent(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : -1
    }

    static func executable(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }

    static func sh(_ script: String) -> DetachedProcess {
        let process = DetachedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        return process
    }

    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 5, arguments[1] == "--app" {
            return testApp(mode: arguments[2], home: URL(fileURLWithPath: arguments[3]), marker: URL(fileURLWithPath: arguments[4]))
        }
        guard arguments.count >= 2 else {
            print("usage: DetachedProcessTest <helper program> [--dock]")
            exit(2)
        }
        let helper = URL(fileURLWithPath: arguments[1])
        // In the worktree's build folder: under /private/var (the temp folder) Engine.ownProcesses finds
        // nothing at all, as resolvingSymlinksInPath drops the /private.
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/detached-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        DetachedProcess.home = home

        // Without the helper: a plain child process, same results.
        DetachedProcess.helperProgram = nil
        let plain = sh("exit 4")
        check((try? plain.run()) != nil, "runs without the helper")
        plain.waitUntilExit()
        check(plain.terminationStatus == 4 && !plain.isRunning, "status without the helper: \(plain.terminationStatus)")
        check(plain.processIdentifier > 0, "a process without the helper")
        check(DetachedProcess.helperApp() == nil, "no helper app without the helper program")

        DetachedProcess.helperProgram = helper
        guard let app = DetachedProcess.helperApp() else {
            print("✗ helper app not made")
            try? FileManager.default.removeItem(at: home)
            exit(1)
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        check(info?["CFBundleIdentifier"] as? String == "io.github.lordhayne.nightforge.helper", "helper bundle ID")
        check(info?["LSUIElement"] as? Bool == true, "helper stays out of the Dock")
        check((info?["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false, "helper says why a game wants the microphone")
        check(FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/nightforge-helper").path),
              "helper executable")
        let quarantine = getxattr(app.appendingPathComponent("Contents/MacOS/nightforge-helper").path, "com.apple.quarantine", nil, 0, 0, 0)
        check(quarantine < 0, "helper carries no quarantine flag")
        let stamp = try? Data(contentsOf: app.appendingPathComponent("Contents/Resources/helper.sha256"))
        check(stamp?.count == 64, "helper stamp")

        shippedHelper(app: app, home: home, helper: helper)

        // Output, working folder, environment, exit code.
        let log = home.appendingPathComponent("out.log")
        try? "old\n".write(to: log, atomically: true, encoding: .utf8)
        let handle = FileHandle(forWritingAtPath: log.path)
        let first = sh(#"pwd; echo "x=$X y=${Y-unset}"; echo err >&2; exit 3"#)
        first.currentDirectoryURL = URL(fileURLWithPath: "/usr")
        first.environment = ["X": "a b\nc", "PATH": "/usr/bin:/bin"]
        first.standardInput = FileHandle.nullDevice
        first.standardOutput = handle
        first.standardError = handle
        let ran = Date()
        do { try first.run() } catch { check(false, "run: \(error)") }
        check(Date().timeIntervalSince(ran) < 5, "starts quickly: \(Date().timeIntervalSince(ran)) s")
        first.waitUntilExit()
        check(first.terminationStatus == 3, "exit code: \(first.terminationStatus)")
        check(!first.isRunning, "not running after the end")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        check(text == "old\n/usr\nx=a b\nc y=unset\nerr\n", "output appended, cwd and environment: \(text.debugDescription)")
        try? handle?.close()

        // A program that runs on: not Nightforge's child, but the helper's (an app of its own).
        let ended = DispatchSemaphore(value: 0)
        let calls = Counter()
        let long = sh("sleep 30")
        long.terminationHandler = { process in
            calls.add()
            check(process.terminationStatus == SIGTERM, "ended by SIGTERM: \(process.terminationStatus)")
            ended.signal()
        }
        try? long.run()
        let pid = long.processIdentifier
        check(pid > 0 && long.isRunning, "running with a process")
        let helperPID = parent(of: pid)
        check(helperPID != getpid() && helperPID > 1, "started by the helper, not by us (parent \(helperPID))")
        check(executable(of: helperPID).hasSuffix("Nightforge Helper.app/Contents/MacOS/nightforge-helper"),
              "helper runs from its app: \(executable(of: helperPID))")
        check(parent(of: helperPID) == 1, "helper started by launchd (Launch Services)")
        // The list has the helper and the program in it (by their own pids); the helper still isn't one of the engine's.
        FakeProcesses.install { FakeProcesses.rows(of: [helperPID, pid]) }
        defer { FakeProcesses.installEmpty() }
        check(!Engine.ownProcesses(under: home).contains { $0.pid == helperPID },
              "the helper isn't one of Nightforge's engine processes (stopAll leaves it alone)")
        long.terminate()
        check(ended.wait(timeout: .now() + 10) == .success, "termination handler called")
        long.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.3)
        check(calls.value == 1, "termination handler once: \(calls.value)")
        check(kill(pid, 0) != 0, "program gone")

        let interrupted = sh(#"trap "exit 9" INT; sleep 30 & wait"#)
        try? interrupted.run()
        Thread.sleep(forTimeInterval: 0.3)
        interrupted.interrupt()
        interrupted.waitUntilExit()
        check(interrupted.terminationStatus == 9, "interrupt reaches the program: \(interrupted.terminationStatus)")

        // Several at once, as at a game start (regedit, Steam, the priority script).
        let many = (0..<6).map { sh("exit \($0)") }
        DispatchQueue.concurrentPerform(iterations: many.count) { try? many[$0].run() }
        many.forEach { $0.waitUntilExit() }
        check(many.enumerated().allSatisfy { $0.element.terminationStatus == Int32($0.offset) },
              "parallel starts: \(many.map(\.terminationStatus))")

        let missing = DetachedProcess()
        missing.executableURL = URL(fileURLWithPath: "/nonexistent/program")
        check((try? missing.run()) == nil, "a missing program throws")

        // The helper app stays as it is while nothing changed (a running one keeps its files).
        let modified = try? FileManager.default.attributesOfItem(atPath: app.path)[.modificationDate] as? Date
        check(DetachedProcess.helperApp() == app, "same helper app")
        check((try? FileManager.default.attributesOfItem(atPath: app.path)[.modificationDate] as? Date) == modified, "helper app not rebuilt")

        // A helper that starts but never answers (macOS turned it away, say): after the wait the program
        // runs as a plain child, and the starts after it don't wait at all. Last, as the helper stays
        // given up for the rest of the run.
        let silent = home.appendingPathComponent("silent-helper")
        try? "#!/bin/sh\nexit 0\n".write(to: silent, atomically: true, encoding: .utf8)
        DetachedProcess.helperProgram = silent
        let fallback = sh("exit 6")
        let tried = Date()
        check((try? fallback.run()) != nil, "runs although the helper doesn't answer")
        fallback.waitUntilExit()
        let waited = Date().timeIntervalSince(tried)
        check(fallback.terminationStatus == 6, "status after falling back: \(fallback.terminationStatus)")
        check(waited >= 10 && waited < 25, "falls back after the wait: \(Int(waited)) s")
        let next = sh("exit 7")
        let again = Date()
        try? next.run()
        next.waitUntilExit()
        check(next.terminationStatus == 7 && Date().timeIntervalSince(again) < 3, "the next start doesn't wait")
        check(DetachedProcess.helperApp() == nil, "the helper stays given up")

        if arguments.contains("--dock") { dockCheck(helper: helper, home: home) }

        try? FileManager.default.removeItem(at: home)
        if failures == 0 {
            print("✓ DetachedProcessTest passed")
        } else {
            print("\(failures) failure(s)")
            exit(1)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    // MARK: - The Dock

    /// Launches this test as a small app that starts `sleep` and quits, once with a plain Process (macOS
    /// keeps the quit app listed: the check sees the bug) and once detached (it must not).
    static func dockCheck(helper: URL, home: URL) {
        let app = home.appendingPathComponent("DetachedDockCheck.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try? FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: macOS.appendingPathComponent("check"))
        try? FileManager.default.copyItem(at: helper, to: home.appendingPathComponent("nightforge-helper"))
        let info: [String: Any] = ["CFBundleExecutable": "check", "CFBundleIdentifier": "io.github.lordhayne.nightforge.test.dock",
                                   "CFBundleName": "DetachedDockCheck", "CFBundlePackageType": "APPL"]
        try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        for mode in ["plain", "detached"] {
            let marker = home.appendingPathComponent("\(mode).pid")
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-n", "-g", app.path, "--args", "--app", mode, home.path, marker.path]
            try? open.run()
            open.waitUntilExit()
            // The app writes "<its pid> <sleep's pid>" and quits a second later.
            var pids: [pid_t] = []
            for _ in 0..<100 where pids.count != 2 {
                Thread.sleep(forTimeInterval: 0.1)
                pids = ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(separator: " ").compactMap { pid_t($0) }
            }
            guard pids.count == 2 else {
                check(false, "\(mode): test app didn't start its program")
                continue
            }
            for _ in 0..<100 where kill(pids[0], 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
            Thread.sleep(forTimeInterval: 1.5)
            check(kill(pids[1], 0) == 0, "\(mode): program runs on after the app quit")
            let listed = lsappinfoRecord(for: app).contains("exited-with-subordinates")
            if mode == "plain" {
                check(listed, "plain: macOS keeps the quit app listed (the check sees the bug)")
            } else {
                check(!listed, "detached: macOS forgot the quit app – no second Dock icon")
            }
            kill(pids[1], SIGTERM)
            for _ in 0..<50 where !lsappinfoRecord(for: app).isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
    }

    /// The signed helper inside Nightforge.app, copied out: when it's missing or another one lies there, and
    /// into a data folder that isn't there yet. `helper` is put back last, for the checks after this.
    static func shippedHelper(app: URL, home: URL, helper: URL) {
        let fm = FileManager.default
        let shipped = home.appendingPathComponent("shipped/\(DetachedProcess.helperName)", isDirectory: true)
        func write(_ text: String, _ path: String, in bundle: URL) {
            let file = bundle.appendingPathComponent(path)
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
        }
        write("signed helper", "Contents/MacOS/nightforge-helper", in: shipped)
        write("seal", "Contents/_CodeSignature/CodeResources", in: shipped)
        // Another pointer to the program: the helper is worked out anew.
        func prepare(_ name: String) -> URL? {
            let program = home.appendingPathComponent(name)
            try? fm.copyItem(at: helper, to: program)
            DetachedProcess.helperProgram = program
            return DetachedProcess.helperApp()
        }
        func program(of bundle: URL) -> String? {
            try? String(contentsOf: bundle.appendingPathComponent("Contents/MacOS/nightforge-helper"), encoding: .utf8)
        }
        let dataFolder = DetachedProcess.home
        defer {
            DetachedProcess.shippedHelper = URL(fileURLWithPath: "/nowhere")
            DetachedProcess.home = dataFolder
            DetachedProcess.helperProgram = helper
            _ = DetachedProcess.helperApp()
        }
        DetachedProcess.shippedHelper = shipped
        check(prepare("p1").flatMap(program) == "signed helper", "the shipped helper replaces the one made here")
        // An older Nightforge built its own over it: the copy itself counts, not a note beside it.
        write("ad hoc helper", "Contents/MacOS/nightforge-helper", in: app)
        check(prepare("p2").flatMap(program) == "signed helper", "another helper there is replaced")
        // Unchanged: left alone.
        let before = try? fm.attributesOfItem(atPath: app.appendingPathComponent("Contents/MacOS/nightforge-helper").path)[.creationDate] as? Date
        _ = prepare("p3")
        let after = try? fm.attributesOfItem(atPath: app.appendingPathComponent("Contents/MacOS/nightforge-helper").path)[.creationDate] as? Date
        check(before != nil && before == after, "the same helper isn't copied again")
        // The very first start: no data folder yet.
        DetachedProcess.home = home.appendingPathComponent("fresh/Nightforge", isDirectory: true)
        check(prepare("p4").flatMap(program) == "signed helper", "a data folder that isn't there yet is made")
    }

    static func lsappinfoRecord(for app: URL) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        process.arguments = ["list"]
        process.standardOutput = pipe
        try? process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // Records start with ` 12) "Name" ASN:…`.
        var records: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.range(of: #"^\s*\d+\) "#, options: .regularExpression) != nil { records.append("") }
            if !records.isEmpty { records[records.count - 1] += line + "\n" }
        }
        return records.first { $0.contains(app.resolvingSymlinksInPath().path) || $0.contains(app.path) } ?? ""
    }

    /// The test app: starts `sleep` one way or the other, notes both processes, quits.
    static func testApp(mode: String, home: URL, marker: URL) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        DetachedProcess.home = home
        DetachedProcess.helperProgram = home.appendingPathComponent("nightforge-helper")
        var pid: pid_t = 0
        if mode == "plain" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["60"]
            try? process.run()
            pid = process.processIdentifier
        } else {
            let process = DetachedProcess()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["60"]
            try? process.run()
            pid = process.processIdentifier
        }
        try? "\(getpid()) \(pid)".write(to: marker, atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { application.terminate(nil) }
        application.run()
    }
}
