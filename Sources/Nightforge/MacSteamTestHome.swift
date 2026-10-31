import AppKit
import Darwin
import Foundation

/// Steam for Mac in a test home (MacSteam.isTestHome): a stand-in Nightforge writes there itself,
/// never Valve's Steam for Mac.
///
/// Valve's can't be kept inside a test home. After installing its client on its first start, and
/// after each update, its launcher starts Steam again through Launch Services – `/bin/sh -c "sleep 1;
/// open -n … --args …"` and NSWorkspace's launchApplicationAtURL – which hands the new Steam the login
/// session's environment: the real home, the player's own Steam folder and sign-in. On 31.10.2026 a
/// first-start test in build/f2 started the real ~/Library/Application Support/Steam client 37 s
/// after the test one; it signed in with the player's account and signed their Windows Steam out.
///
/// So the stand-in writes what Nightforge reads of Steam for Mac – its update in bootstrap_log, its
/// sign-in window in steamui_login, the sign-in in connection_log and loginusers.vdf once the tester
/// "scans" by creating `sign-in-now` in its folder, steam:// commands in console_log – and nothing
/// else. And while Nightforge runs in a test home, a Steam for Mac process from the real home that
/// starts after it is ended at once (guardRealSteam).
enum TestSteam {
    static let bundleID = "com.nightforge.test-steam"
    static let executableName = "nightforge-test-steam"

    /// Its app in the test home, beside where Valve's would go.
    static var app: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications/Nightforge Test Steam.app", isDirectory: true)
    }

    static var executable: URL { app.appendingPathComponent("Contents/MacOS/\(executableName)") }

    /// Its folder: the test home's Steam folder (MacSteam.root).
    private static var folder: URL { MacSteam.root }
    private static var pidFile: URL { folder.appendingPathComponent("nightforge-test-steam.pid") }

    /// The tester's QR scan: create this file and the stand-in signs in.
    static var signInTrigger: URL { folder.appendingPathComponent("sign-in-now") }

    /// The player's real home, whatever HOME says.
    static let realHome: String? = {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).resolvingSymlinksInPath().path
    }()

    /// The one program a test home may start for Steam for Mac: the stand-in's, inside the test home.
    /// Valve's Steam.app – in /Applications, in the real home or copied into the test home – never.
    static func mayLaunch(_ program: URL) -> Bool {
        guard MacSteam.isTestHome else { return false }
        let path = program.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
        return path.hasPrefix(home) && path == executable.resolvingSymlinksInPath().path && isStandIn(app)
    }

    /// The stand-in's app, not Valve's (which has com.valvesoftware.steam).
    static func isStandIn(_ app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == bundleID
            || (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String) == bundleID
    }

    // MARK: - Running it

    /// Puts the stand-in in place – in place of Valve's download.
    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleExecutable": executableName,
            "CFBundleName": "Nightforge Test Steam", "CFBundlePackageType": "APPL", "LSUIElement": true,
        ]
        guard (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true) else {
            throw MacSteamError.installFailed
        }
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    /// Starts it (or hands a running one a steam:// command), apart from Nightforge like Steam.
    static func launch(_ arguments: [String]) {
        guard mayLaunch(executable) else { return }
        let process = DetachedProcess()
        process.executableURL = executable
        process.arguments = arguments
        // Spelled out: started without the helper (a test), a program would get none, and the
        // stand-in has to know the test home.
        process.environment = ProcessInfo.processInfo.environment
        try? process.run()
    }

    /// Its process, from the file it writes when it starts – and only while that process is the one
    /// that wrote it (started no later), not another that got the number since.
    static var pid: pid_t? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0, kill(pid, 0) == 0,
              let written = (try? pidFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              let started = Engine.processStart(pid), started <= written.addingTimeInterval(1)
        else { return nil }
        return pid
    }

    static var isRunning: Bool { pid != nil }

    /// Asks it to quit, and ends it after 5 s.
    static func quit() async {
        guard let pid else { return }
        kill(pid, SIGTERM)
        for _ in 0..<10 {
            guard isRunning else { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        kill(pid, SIGKILL)
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// Nightforge quits: so does the stand-in.
    static func terminate() {
        if let pid { kill(pid, SIGTERM) }
    }

    // MARK: - The guard

    /// Valve's Steam for Mac processes that started after `since` – from the real home, from
    /// /Applications, or a copy in the test home (it would start itself again in the real one): in a
    /// test home, nothing may run them (the stand-in doesn't).
    static func leaks(_ processes: [(pid: pid_t, path: String, started: Date?)], since: Date, realHome: String?,
                      testHome: String) -> [pid_t] {
        var roots = ["/Applications/Steam.app/", testHome + "/Applications/Steam.app/",
                     testHome + "/Library/Application Support/Steam/Steam.AppBundle/"]
        if let realHome {
            roots += [realHome + "/Library/Application Support/Steam/", realHome + "/Applications/Steam.app/"]
        }
        return processes.filter { process in
            roots.contains { process.path.hasPrefix($0) } && (process.started ?? .distantPast) >= since
        }.map(\.pid)
    }

    /// While Nightforge runs in a test home: every quarter second, a Steam for Mac from the real home
    /// that has started since is ended at once – signing in, it would sign the player's own Steams
    /// out. Steam takes seconds to sign in (4 s median on the dev Mac). Reported in the window and in
    /// nightforge-test-guard.log in the test home.
    @MainActor
    static func guardRealSteam(report: @escaping (String) -> Void) async {
        guard MacSteam.isTestHome else { return }
        let since = Date()
        let testHome = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        while !Task.isCancelled {
            let found = await Task.detached(priority: .userInitiated) {
                leaks(processes(), since: since, realHome: realHome, testHome: testHome)
            }.value
            for pid in found {
                kill(pid, SIGKILL)
                let line = "Test home: Nightforge ended Steam for Mac from the real home (process \(pid)) – it must not run in a test."
                note(line)
                report(line)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func note(_ line: String) {
        let log = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("nightforge-test-guard.log")
        let stamped = "[\(Date())] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? stamped.write(to: log, atomically: true, encoding: .utf8)
        }
    }

    /// Every process with its program and start.
    static func processes() -> [(pid: pid_t, path: String, started: Date?)] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return pids.prefix(max(count, 0)).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            return (pid, String(cString: buffer), Engine.processStart(pid))
        }
    }

    // MARK: - The stand-in

    /// What the stand-in does, in Steam's own log lines (as Nightforge reads them).
    /// NIGHTFORGE_TEST_STEAM_SECONDS: how long its first-start update takes (Valve's: ~53 s).
    static let script = #"""
        #!/bin/bash
        # Nightforge's stand-in for Steam for Mac in a test home (TestSteam, MacSteamTestHome.swift).
        # It is never Valve's Steam: it only writes the logs and files Nightforge reads.
        # Only ever in a test home: not without HOME, and never in the player's real home.
        REAL_HOME="$(eval echo "~$(id -un)")"
        if [ -z "$HOME" ] || [ "$(cd "$HOME" 2>/dev/null && pwd -P)" = "$(cd "$REAL_HOME" && pwd -P)" ]; then
          echo "nightforge-test-steam: not in a test home (HOME=$HOME)" >&2
          exit 1
        fi
        ROOT="$HOME/Library/Application Support/Steam"
        LOGS="$ROOT/logs"
        PIDFILE="$ROOT/nightforge-test-steam.pid"
        mkdir -p "$LOGS" "$ROOT/config" "$ROOT/steamapps"
        log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$2" >> "$LOGS/$1"; }
        # A steam:// command for the one that runs: logged like Steam's console does.
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
          for arg in "$@"; do case "$arg" in steam://*) log console_log.txt "ExecuteSteamURL: \"$arg\"";; esac; done
          exit 0
        fi
        echo $$ > "$PIDFILE"
        trap 'log connection_log.txt "[Logged Off, 0, 0] [U:1:0] Log session ended"; rm -f "$PIDFILE"; exit 0' TERM INT
        # Its first start: the update, as Steam logs it.
        if [ ! -f "$ROOT/nightforge-test-steam-installed" ]; then
          log bootstrap_log.txt "Startup - updater built Nightforge test stand-in"
          total=289112
          steps="${NIGHTFORGE_TEST_STEAM_SECONDS:-50}"
          for i in $(seq 1 "$steps"); do
            log bootstrap_log.txt "Downloading update ($((total * i / steps)) of $total KB)..."
            sleep 1
          done
          log bootstrap_log.txt "Update complete, launching Steam..."
          touch "$ROOT/nightforge-test-steam-installed"
        fi
        for name in connection_log.txt console_log.txt steamui_login.txt; do log "$name" "Client version: 1792618285"; done
        for arg in "$@"; do case "$arg" in steam://*) log console_log.txt "ExecuteSteamURL: \"$arg\"";; esac; done
        signed_in() {
          log steamui_login.txt "[ WaitingForLibraryReady ] SetLoginState: Success - OK"
          log connection_log.txt "[Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'"
          log connection_log.txt "[Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete"
          log console_log.txt "System startup time: 1.00 seconds"
        }
        if [ -s "$ROOT/config/loginusers.vdf" ]; then
          signed_in
        else
          log steamui_login.txt "[ None ] SetLoginState: WaitingForCredentials - OK"
          # The QR code: the tester scans it by creating sign-in-now in this folder.
          while [ ! -e "$ROOT/sign-in-now" ]; do sleep 1; done
          rm -f "$ROOT/sign-in-now"
          signed_in
          sleep 4  # Steam writes its account list a few seconds after the sign-in
          account="${NIGHTFORGE_TEST_STEAM_ACCOUNT:-76561190000000001}"
          printf '"users"\n{\n\t"%s"\n\t{\n\t\t"AccountName"\t\t"test"\n\t\t"RememberPassword"\t\t"1"\n\t\t"AutoLogin"\t\t"1"\n\t}\n}\n' "$account" > "$ROOT/config/loginusers.vdf"
        fi
        while true; do sleep 1; done
        """#
}
