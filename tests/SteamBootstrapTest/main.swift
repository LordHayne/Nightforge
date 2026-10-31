// Checks SteamBootstrap against Steam's own bootstrap logs: the first update on 23.10.2026 that went
// through (win32, win64, then the new client) and the loop of 29.10.2026, where Nightforge swapped
// in its steamwebhelper wrapper and restarted Steam in the middle of every install – its first four
// starts and its last four, of 131 – and the first start after the fix the same evening, where the
// first start of each bootstrapper (with -noverifyfiles) sat still for 90 s – and the second run,
// where the client Nightforge started after swapping in the wrapper hung for 90 s. Also that the
// wrapper isn't swapped in while an update goes in, nor before Steam's client is there, how Steam is
// started then, and when Valve's own helper still runs. And from the last live run (29.10.2026,
// 21:35) and a scratch prefix with Steam's packages fetched ahead (same evening): the moment the
// wrapper goes in and stays, the moment for the 64-bit packages, and Steam's browser hanging on
// its way up: tests/SteamBootstrapTest/run.sh
// The logs are Steam's real lines (German where Steam translates), the repeated package and
// progress lines cut down to two per block.
import Foundation

@main
struct SteamBootstrapTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let good = (try? String(contentsOf: folder.appendingPathComponent("good-2026-10-23.txt"), encoding: .utf8)) ?? ""
    static let loop = (try? String(contentsOf: folder.appendingPathComponent("loop-2026-10-29-start.txt"), encoding: .utf8)) ?? ""
    static let loopEnd = (try? String(contentsOf: folder.appendingPathComponent("loop-2026-10-29-end.txt"), encoding: .utf8)) ?? ""
    static let fixed = (try? String(contentsOf: folder.appendingPathComponent("fixed-2026-10-29.txt"), encoding: .utf8)) ?? ""
    static let relaunch = (try? String(contentsOf: folder.appendingPathComponent("relaunch-2026-10-29-bootstrap.txt"), encoding: .utf8)) ?? ""
    static let relaunchConsole = (try? String(contentsOf: folder.appendingPathComponent("relaunch-2026-10-29-console.txt"), encoding: .utf8)) ?? ""
    static let run5 = (try? String(contentsOf: folder.appendingPathComponent("run5-2026-10-29-bootstrap.txt"), encoding: .utf8)) ?? ""
    static let run5Webhelper = (try? String(contentsOf: folder.appendingPathComponent("run5-2026-10-29-webhelper.txt"), encoding: .utf8)) ?? ""
    static let run5Cef = (try? String(contentsOf: folder.appendingPathComponent("run5-2026-10-29-cef.txt"), encoding: .utf8)) ?? ""
    static let prefetched = (try? String(contentsOf: folder.appendingPathComponent("prefetched-2026-10-29-bootstrap.txt"), encoding: .utf8)) ?? ""

    /// The log as it stood when the `occurrence`-th line containing `marker` had just been written.
    static func log(_ text: String, through marker: String, _ occurrence: Int = 1) -> String {
        var seen = 0
        var lines: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(line)
            if line.contains(marker) {
                seen += 1
                if seen == occurrence { return lines.joined(separator: "\n") }
            }
        }
        failures += 1
        print("✗ no \(occurrence). \(marker.debugDescription) in the log")
        return ""
    }

    static func state(_ text: String, through marker: String, _ occurrence: Int = 1) -> SteamBootstrap {
        SteamBootstrap(log: log(text, through: marker, occurrence))
    }

    /// As Steam writes it: Windows line ends.
    static func crlf(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: "\r\n") }

    static func main() {
        check(!good.isEmpty && !loop.isEmpty && !loopEnd.isEmpty && !fixed.isEmpty && !relaunch.isEmpty && !relaunchConsole.isEmpty
              && !run5.isEmpty && !run5Webhelper.isEmpty && !run5Cef.isEmpty && !prefetched.isEmpty, "the logs are there")
        goodRun()
        theLoop()
        afterTheFix()
        theHungClient()
        valvesHelper()
        steamDetails()
        browserCaches()
        decisions()
        starting()
        wrapperSwap()
        swapMoment()
        clientPackagesMoment()
        browserHang()
        print(failures == 0 ? "✓ SteamBootstrap" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// 23.10.: win32 update, restart, win64 update, restart, the new client.
    static func goodRun() {
        check(state(good, through: "Downloading manifest") == .downloading, "asking for a new version: downloading")
        check(state(good, through: "Downloaded new manifest") == .downloading, "win32 manifest, installed version 0: downloading")
        check(state(good, through: " KB) ") == .downloading, "download progress: downloading")
        check(state(good, through: "uninstalled manifest found") == .installing, "win32 unpacked next: installing")
        check(state(good, through: "Paket wird extrahiert") == .installing, "unpacking: installing")
        check(state(good, through: "Update wird installiert") == .installing, "installing: installing")
        check(state(good, through: "Committing NTFS transaction") == .updated, "committed: updated")
        check(state(good, through: "] Shutdown") == .updated, "win32 done, bootstrapper ends: updated")
        check(state(good, through: "Downloaded new manifest", 2) == .downloading, "win64 manifest: downloading")
        check(state(good, through: "uninstalled manifest found", 2) == .installing, "win64 unpacked next: installing")
        check(state(good, through: "] Shutdown", 2) == .updated, "win64 done: updated")
        check(SteamBootstrap(log: crlf(log(good, through: "] Shutdown", 2))) == .updated, "with Windows line ends too")
        check(state(good, through: "Verification complete", 3) == .idle, "the new client runs: idle")
        check(state(good, through: "Background update loop") == .idle, "the client looks for updates: idle")
        check(state(good, through: "Download skipped") == .idle, "no new version: idle")
        check(state(good, through: "Nothing to do") == .idle, "nothing to do: idle")
        check(state(good, through: "Downloading manifest", 4) == .downloading, "the next start asks again: downloading")
    }

    /// 29.10.: every start finds the downloaded update and starts installing it – until Nightforge
    /// swapped the helper and restarted Steam, before "Shutdown" ever came. The last starts were
    /// Nightforge's "-shutdown" on its way out: that one got through, without "Committing" (the
    /// non-atomic replacement doesn't commit), and the win64 update began.
    static func theLoop() {
        check(state(loop, through: "Verification complete") == .idle, "the old bootstrapper with -noverifyfiles: idle")
        check(state(loop, through: "Found pending update") == .installing, "pending update: installing")
        check(state(loop, through: "Paket wird extrahiert", 2) == .installing, "unpacking again: installing")
        check(state(loop, through: "Bad NTFS transaction canary") == .installing, "non-atomic replacement: installing")
        let cutOff = SteamBootstrap(log: loop)
        check(cutOff == .installing, "the fourth start, cut off: installing")
        check(!cutOff.allowsHelperSwap, "no helper swap while it installs")
        check(SteamBootstrap(log: crlf(loop)) == .installing, "with Windows line ends too")

        check(state(loopEnd, through: "Paket wird extrahiert", 2) == .installing, "start 129: installing")
        // Start 130 was "steam.exe -shutdown": its command line isn't the bootstrapper's "Shutdown".
        check(state(loopEnd, through: "Found pending update", 3) == .installing, "start 130 with -shutdown: installing")
        check(state(loopEnd, through: "Could not remove backup file") == .installing, "cleaning up: still installing")
        check(state(loopEnd, through: "] Shutdown") == .updated, "done without Committing: updated")
        check(SteamBootstrap(log: crlf(log(loopEnd, through: "] Shutdown"))) == .updated, "with Windows line ends too")
        check(state(loopEnd, through: "Downloaded new manifest", 4) == .downloading, "then win64: downloading")
        check(SteamBootstrap(log: loopEnd) == .installing, "the log's end, win64 going in: installing")
    }

    /// 29.10., evening, with the loop fixed: win32 and win64 went in at the first try. But the first
    /// start of each bootstrapper, told -noverifyfiles, skipped its update check and sat there
    /// (20:22:18 until the 90 s rule; 20:24:27 until the helper swap restarted it). And at the end
    /// a "steam.exe -shutdown" without -noverifyfiles found the wrapper and put Valve's helper back.
    static func afterTheFix() {
        let stuck = state(fixed, through: "Verification complete")
        check(stuck == .idle, "the first start, nothing asked: idle")
        check(stuck.stalled(quietFor: 16, sinceRestart: 16, clientInstalled: false), "no client and no check: restarted after 15 s")
        check(!stuck.stalled(quietFor: 16, sinceRestart: 16, clientInstalled: true), "with a client, idle is the client running")
        check(!stuck.stalled(quietFor: 10, sinceRestart: 16, clientInstalled: false), "not before 15 s")
        check(!stuck.stalled(quietFor: 30, sinceRestart: 5, clientInstalled: false), "nor right after a restart (its new block isn't there yet)")
        check(state(fixed, through: "Downloaded new manifest") == .downloading, "the restart asks: downloading")
        check(state(fixed, through: "] Shutdown") == .updated, "win32 went in at the first try: updated")
        check(state(fixed, through: "Verification complete", 2) == .idle, "the next bootstrapper sits there too: idle")
        check(state(fixed, through: "] Shutdown", 2) == .updated, "win64 went in: updated")
        check(state(fixed, through: "Nothing to do") == .idle, "the client runs: idle")
        check(state(fixed, through: "BVerifyInstalledFiles") == .idle, "-shutdown without -noverifyfiles finds the wrapper …")
        check(state(fixed, through: "uninstalled manifest found", 3) == .installing, "… and installs Valve's helper again")
        check(SteamBootstrap(log: fixed) == .idle, "the log's end: idle")
    }

    /// 29.10., second run: win64 in at 20:57:13, the new client (started by the bootstrapper) ran
    /// Valve's helper; Nightforge swapped in the wrapper and restarted Steam (20:57:18). That start's
    /// browser launched, then nothing – console_log has no "Client version" until the next restart
    /// at 20:58:52, which the 90 s rule made.
    static func theHungClient() {
        let hung = log(relaunch, through: "20:57:18] Verification skipped")
        let state = SteamBootstrap(log: hung)
        check(state == .idle, "the hung start: idle")
        check(!SteamBootstrap.clientStarted(bootstrapLog: hung, consoleLog: ""), "no Client version: the client didn't come up")
        check(!SteamBootstrap.clientStarted(bootstrapLog: crlf(hung), consoleLog: ""), "with Windows line ends too")
        check(state.stalled(quietFor: 21, sinceRestart: 21, clientInstalled: true, clientStarted: false), "restarted after 20 s, not 90")
        check(!state.stalled(quietFor: 19, sinceRestart: 21, clientInstalled: true, clientStarted: false), "not before")
        check(!state.stalled(quietFor: 60, sinceRestart: 60, clientInstalled: true, clientStarted: true), "a client that came up isn't hung")

        let good = log(relaunch, through: "20:58:52] Startup - updater built")
        let console = log(relaunchConsole, through: "Client version")
        check(SteamBootstrap.clientStarted(bootstrapLog: good, consoleLog: console), "the restart's client came up at 20:58:53")
        check(SteamBootstrap.clientStarted(bootstrapLog: crlf(good), consoleLog: crlf(console)), "with Windows line ends too")
        // The background restart after the sign-in (20:59:22): the earlier start's lines don't count.
        let later = log(relaunch, through: "20:59:22] Startup - updater built")
        check(!SteamBootstrap.clientStarted(bootstrapLog: later, consoleLog: log(relaunchConsole, through: "Console Log Start")),
              "an earlier start's Client version doesn't count")
        check(SteamBootstrap.clientStarted(bootstrapLog: later, consoleLog: relaunchConsole), "its own at 20:59:23 does")
        check(SteamBootstrap.clientStarted(bootstrapLog: "", consoleLog: ""), "no start in the log: nothing to say")
    }

    /// Valve's helper started at 20:57:14, the wrapper went in at 20:57:15: that one is Valve's.
    /// The wrapper's own process has the same name but starts later, with steamwebhelper_real.exe.
    static func valvesHelper() {
        let at = { (time: String) -> Date in
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return format.date(from: "2026-10-29 " + time)!
        }
        let swapped = at("20:57:15")
        let valve = #""C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe" -nocrashdialog -lang=de_DE"#
        let real = #""C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper_real.exe" --disable-gpu --single-process"#
        let steam = #"C:\Program Files (x86)\Steam\steam.exe -no-cef-sandbox"#
        check(SteamBootstrap.unwrappedHelperRunning([(steam, at("20:57:13")), (valve, at("20:57:14"))], swappedAt: swapped),
              "Valve's helper from before the swap: restart")
        check(!SteamBootstrap.unwrappedHelperRunning([(steam, at("20:57:18")), (valve, at("20:57:19")), (real, at("20:57:19"))], swappedAt: swapped),
              "the wrapper and its real helper after the swap: no restart")
        check(!SteamBootstrap.unwrappedHelperRunning([(steam, at("20:57:13"))], swappedAt: swapped), "no browser yet: only the file is swapped")
        check(!SteamBootstrap.unwrappedHelperRunning([(valve, nil)], swappedAt: swapped), "a start that isn't known doesn't count")
        check(Engine.processStart(getpid()).map { $0 <= Date() && $0 > Date().addingTimeInterval(-600) } ?? false, "this test's own start is known")
    }

    /// The checklist's line under "Installing Steam" (SetupDetail.steam), from the same logs: which of
    /// Steam's two packages, how far, how fast (from the log's own stamps), installing, restarting.
    static func steamDetails() {
        func detail(_ text: String, client: Bool = false) -> String { SetupDetail.steam(log: text, clientInstalled: client) }
        func kb(_ value: Double) -> Int64 { Int64(value * 1024) }

        check(detail(log(good, through: "Downloading manifest")) == L10n.t("Steam looks for its update …"), "asking for the update")
        check(detail(log(good, through: " KB) ")) == L10n.t("Steam downloads update 1 of 2: %@",
              SetupDetail.transfer(done: kb(7991), total: kb(336_229), bytesPerSecond: nil)), "update 1 of 2, no speed yet: \(detail(log(good, through: " KB) ")))")
        // Real lines in a row (23.10.): the speed from 19:55:04 to 19:55:07.
        let progress = """
            [2026-10-23 19:55:01] Startup - updater built May 20 2024 14:26:54
            [2026-10-23 19:55:03] Downloaded new manifest: /client/steam_client_win32 version 1769731672, installed version 0, existing pending version 0
            [2026-10-23 19:55:04] Update wird heruntergeladen (7,991 von 336,229 KB) …
            [2026-10-23 19:55:04] Update wird heruntergeladen (22,650 von 336,229 KB) …
            [2026-10-23 19:55:07] Update wird heruntergeladen (73,629 von 336,229 KB) …
            [2026-10-23 19:55:07] Update wird heruntergeladen (78,791 von 336,229 KB) …
            """
        let speed = Double(78_791 - 22_650) * 1024 / 3
        check(detail(crlf(progress)) == L10n.t("Steam downloads update 1 of 2: %@",
              SetupDetail.transfer(done: kb(78_791), total: kb(336_229), bytesPerSecond: speed)), "with its speed: \(detail(progress))")
        check(detail(log(good, through: "uninstalled manifest found")) == L10n.t("Steam installs update 1 of 2 …"), "installing update 1")
        check(detail(log(good, through: "] Shutdown")) == L10n.t("Update installed – Steam starts again …"), "update 1 in, restarting")
        check(detail(log(good, through: " KB) ", 3)).hasPrefix(L10n.t("Steam downloads update 2 of 2, the 64-bit version: %@", "")),
              "update 2 of 2: \(detail(log(good, through: " KB) ", 3)))")
        check(detail(log(good, through: "uninstalled manifest found", 2)) == L10n.t("Steam installs update 2 of 2, the 64-bit version …"), "installing update 2")
        check(detail(log(good, through: "Verification complete", 3), client: true) == L10n.t("Steam starts for the first time …"), "the new client")
        check(detail(log(fixed, through: "Verification complete")) == L10n.t("Steam is starting …"), "a start without a client yet")
        check(detail(log(loop, through: "Bad NTFS transaction canary")) == L10n.t("Steam installs update 1 of 2 …"), "the loop's install, non-atomic")
        check(detail(loopEnd) == L10n.t("Steam installs update 2 of 2, the 64-bit version …"), "the loop's end: win64")
    }

    /// The browser caches the setup's restart clears before the sign-in: Steam's -cachedir under
    /// each Windows user of the prefix, nothing else.
    static func browserCaches() {
        let fm = FileManager.default
        let prefix = fm.temporaryDirectory.appendingPathComponent("steam-cache-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: prefix) }
        let users = prefix.appendingPathComponent("drive_c/users")
        let cache = users.appendingPathComponent("crossover/AppData/Local/Steam/htmlcache")
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try? fm.createDirectory(at: users.appendingPathComponent("Public/AppData/Local"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: users.appendingPathComponent("crossover/AppData/Local/Steam/config"), withIntermediateDirectories: true)
        let found = Engine.steamBrowserCaches(prefix: prefix).map(\.standardizedFileURL)
        check(found == [cache.standardizedFileURL], "the crossover user's htmlcache only: \(found)")
        check(Engine.steamBrowserCaches(prefix: prefix.appendingPathComponent("nothing")).isEmpty, "no prefix: nothing")
    }

    /// What the first start's watchdog makes of each state.
    static func decisions() {
        check(SteamBootstrap.idle.allowsHelperSwap && SteamBootstrap.updated.allowsHelperSwap, "idle and updated: swap allowed")
        check(!SteamBootstrap.downloading.allowsHelperSwap && !SteamBootstrap.installing.allowsHelperSwap, "downloading and installing: no swap")

        func stalled(_ state: SteamBootstrap, _ quiet: TimeInterval) -> Bool {
            state.stalled(quietFor: quiet, sinceRestart: 400, clientInstalled: true)
        }
        check(!stalled(.installing, 120), "a quiet install isn't stalled after 2 min")
        check(stalled(.installing, 301), "an install quiet for 5 min is")
        check(stalled(.idle, 91) && stalled(.downloading, 91), "otherwise 90 s, as before")
        check(!stalled(.downloading, 30), "a download that moves isn't stalled")
        check(!SteamBootstrap.installing.stalled(quietFor: 120, sinceRestart: 400, clientInstalled: false), "an install without a client yet isn't cut off after 15 s")
        check(!SteamBootstrap.idle.stalled(quietFor: 91, sinceRestart: 60, clientInstalled: true), "not within 90 s of a restart")

        check(!SteamBootstrap.updated.gone(steamRunning: false, sinceRestart: 30, quietFor: 20), "right after an update Steam restarts itself: not gone")
        check(SteamBootstrap.updated.gone(steamRunning: false, sinceRestart: 90, quietFor: 61), "a minute later it is")
        check(SteamBootstrap.installing.gone(steamRunning: false, sinceRestart: 20, quietFor: 5), "the bootstrapper died mid-install: gone")
        check(!SteamBootstrap.idle.gone(steamRunning: true, sinceRestart: 100, quietFor: 100), "running: not gone")
        check(!SteamBootstrap.idle.gone(steamRunning: false, sinceRestart: 10, quietFor: 100), "just started: not gone yet")
    }

    /// How Steam is started: verifying its files until the client is in place, then never again
    /// (that would put Valve's helper back over the wrapper) – Nightforge's quit script included.
    static func starting() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("steam-client-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let package = root.appendingPathComponent("package")
        try? fm.createDirectory(at: package, withIntermediateDirectories: true)
        check(!SteamBootstrap.clientInstalled(steamRoot: root), "a fresh Steam: no client")
        try? Data().write(to: package.appendingPathComponent("steam_client_win32.installed"))
        check(!SteamBootstrap.clientInstalled(steamRoot: root), "the 32-bit step alone: no client yet")
        try? Data().write(to: package.appendingPathComponent("steam_client_win64.installed"))
        check(SteamBootstrap.clientInstalled(steamRoot: root), "win64 in place: the client")

        check(!Engine.startArguments(clientInstalled: false).contains("-noverifyfiles"), "before the client: Steam verifies (and so fetches it)")
        check(Engine.startArguments(clientInstalled: true).contains("-noverifyfiles"), "with the client: never again")
        check(Engine.startArguments(clientInstalled: false).contains("-cef-disable-gpu"), "the browser's arguments stay")
        check(Engine.steamShutdownScript.contains("-noverifyfiles -shutdown"), "the quit script doesn't verify either")
    }

    /// Engine.installWebHelperWrapper on a Steam folder of its own: leaves Valve's helper alone
    /// before the client is there and while the log says it installs, swaps it once the new client
    /// runs; and the log's end is read even when the log is long.
    static func wrapperSwap() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("steam-bootstrap-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let cef = root.appendingPathComponent("bin/cef/cef.win7x64")
        let logs = root.appendingPathComponent("logs")
        try? fm.createDirectory(at: cef, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let helper = cef.appendingPathComponent("steamwebhelper.exe")
        let wrapper = root.appendingPathComponent("wrapper.exe")
        try? Data(count: 1_200_000).write(to: helper)  // Valve's helper: several MB
        try? Data(count: 150_000).write(to: wrapper)
        func size(_ url: URL) -> Int { (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1 }
        let logFile = logs.appendingPathComponent("bootstrap_log.txt")

        check(SteamBootstrap(steamRoot: root) == .idle, "no log yet: idle")
        check(!Engine.installWebHelperWrapper(steamRoot: root, wrapper: wrapper), "no client yet: no swap")
        try? fm.createDirectory(at: root.appendingPathComponent("package"), withIntermediateDirectories: true)
        try? Data().write(to: root.appendingPathComponent("package/steam_client_win64.installed"))

        // Older days in front: the newest block is past the 128 KB that are read.
        let filler = String(repeating: "[2026-10-22 10:00:00] Verification complete\n", count: 4000)
        try? crlf(filler + loop).write(to: logFile, atomically: true, encoding: .utf8)
        check(SteamBootstrap(steamRoot: root) == .installing, "a long log: its end counts")
        check(!Engine.installWebHelperWrapper(steamRoot: root, wrapper: wrapper), "installing: no swap")
        check(size(helper) == 1_200_000, "Valve's helper stays while it installs")

        try? crlf(log(good, through: "Verification complete", 3)).write(to: logFile, atomically: true, encoding: .utf8)
        check(Engine.installWebHelperWrapper(steamRoot: root, wrapper: wrapper), "the new client runs: swapped")
        check(size(helper) == 150_000 && size(cef.appendingPathComponent("steamwebhelper_real.exe")) == 1_200_000,
              "the wrapper in place, Valve's helper beside it")
        check(!Engine.installWebHelperWrapper(steamRoot: root, wrapper: wrapper), "once only")
    }

    /// Run 5 (29.10.2026, live): win64 went in at 21:36:34, and Steam's own restart checked its
    /// files ("Verifying file sizes only") – in a scratch prefix that check put Valve's helper back
    /// over a wrapper swapped in before it. Right after "Verification complete" it stays.
    static func swapMoment() {
        check(!SteamBootstrap.verified(log: log(run5, through: "Verifying file sizes only", 2)), "Steam's restart checks its files: not yet")
        check(SteamBootstrap.verified(log: log(run5, through: "Verification complete", 3)), "its check is through: now")
        check(SteamBootstrap.verified(log: crlf(log(run5, through: "Verification complete", 3))), "with Windows line ends too")
        check(SteamBootstrap.verified(log: log(run5, through: "Verification skipped")), "a start told not to check: now")
        check(!SteamBootstrap.verified(log: log(run5, through: "Paket wird extrahiert", 2)), "while win64 goes in: no")
        check(!SteamBootstrap.verified(log: log(run5, through: "] Shutdown", 2)), "win64 in, before the restart: no")
        check(!SteamBootstrap.verified(log: log(run5, through: "Downloaded new manifest")), "while it downloads: no")
        // The win64 step checks too, before its download – with no client yet, which the setup asks for as well.
        check(SteamBootstrap.verified(log: log(run5, through: "Verification complete", 2)), "the win64 step's own check")
        check(SteamBootstrap.verified(log: log(good, through: "Verification complete", 3)), "23.10.: the new client's check")
        check(!SteamBootstrap.verified(log: ""), "no log: nothing checked")
    }

    /// The 32-bit step's clean-up deletes every package file (a scratch prefix, 29.10.2026), and
    /// the next bootstrapper looks for its own a second after its "Shutdown": in between, the
    /// 64-bit client's packages go in. With them there, it fetched nothing (`prefetched`).
    static func clientPackagesMoment() {
        check(!SteamBootstrap.clientPackagesDue(log: log(run5, through: "Downloaded new manifest")), "the 32-bit step downloading: not yet")
        check(!SteamBootstrap.clientPackagesDue(log: log(run5, through: "Committing NTFS transaction")), "committed, the clean-up still to come: not yet")
        check(SteamBootstrap.clientPackagesDue(log: log(run5, through: "] Shutdown")), "its Shutdown: now")
        check(SteamBootstrap.clientPackagesDue(log: crlf(log(run5, through: "] Shutdown"))), "with Windows line ends too")
        check(SteamBootstrap.clientPackagesDue(log: log(run5, through: "Startup - updater built", 2)), "the next bootstrapper has begun: still")
        check(SteamBootstrap.clientPackagesDue(log: log(run5, through: "Verification complete", 2)), "it checked its files: still")
        check(!SteamBootstrap.clientPackagesDue(log: log(run5, through: "Downloaded new manifest", 2)), "it has its manifest: too late")
        check(!SteamBootstrap.clientPackagesDue(log: run5), "the log's end: over")
        check(SteamBootstrap.clientPackagesDue(log: log(good, through: "] Shutdown")), "23.10. as well")
        check(!SteamBootstrap.clientPackagesDue(log: ""), "no log: no")

        check(SteamBootstrap.clientPackagesDue(log: log(prefetched, through: "] Shutdown")), "fetched ahead: the same moment")
        check(!prefetched.contains("missing or incorrect size"), "fetched ahead, neither step had a package to fetch")
        check(SteamBootstrap.verified(log: log(prefetched, through: "Verification complete", 3)), "and the wrapper's moment came as before")
    }

    /// Run 5's browsers (webhelper.txt, cef_log.txt): Valve's (604, ended at once), the first
    /// wrapped one (404, 21:36:40), hung after Chrome began, and the next (404 again, 21:37:05),
    /// through in under a second. The pid comes back after every restart; the stamps tell them apart.
    static func browserHang() {
        let valve = SteamBrowser(webhelperLog: log(run5Webhelper, through: "Disabling GPU"), cefLog: "")
        check(valve.launch?.contains("pid: 604") == true && !valve.chromeStarted && !valve.running, "Valve's: launched, nothing more")
        check(!valve.hung(sinceLaunch: 10, sinceChrome: nil), "not hung after 10 s without Chrome")
        check(valve.hung(sinceLaunch: 16, sinceChrome: nil), "hung after 15 s")

        let hung = SteamBrowser(webhelperLog: log(run5Webhelper, through: "NVIDIA AA"), cefLog: log(run5Cef, through: "WSALookupServiceBegin"))
        check(hung.launch?.contains("pid: 404") == true && hung.chromeStarted && !hung.running, "21:36:40: Chrome began, no message loop")
        check(!hung.hung(sinceLaunch: 6, sinceChrome: 4), "not hung 4 s after Chrome began")
        check(hung.hung(sinceLaunch: 7, sinceChrome: 6), "hung 6 s after")
        let crlfHung = SteamBrowser(webhelperLog: crlf(log(run5Webhelper, through: "NVIDIA AA")), cefLog: crlf(log(run5Cef, through: "WSALookupServiceBegin")))
        check(crlfHung == hung, "with Windows line ends too")

        let next = SteamBrowser(webhelperLog: log(run5Webhelper, through: "NVIDIA AA", 2), cefLog: log(run5Cef, through: "WSALookupServiceBegin"))
        check(next.launch?.contains("21:37:05") == true && !next.chromeStarted, "21:37:05, same pid: the hung start's Chrome isn't its")
        let up = SteamBrowser(webhelperLog: run5Webhelper, cefLog: run5Cef)
        check(up.chromeStarted && up.running, "21:37:05: through to its message loop")
        check(!up.hung(sinceLaunch: 60, sinceChrome: 60), "a browser that's up isn't hung")
        check(SteamBrowser(webhelperLog: "", cefLog: "") == SteamBrowser(webhelperLog: "", cefLog: run5Cef), "no launch: nothing")

        // The setup's view: from when it saw each, and not the launch from before its own (re)start.
        let at = Date()
        var watch = SteamBrowser.Watch()
        watch.ignore(hung.launch)
        check(!watch.hung(hung, now: at.addingTimeInterval(60)), "the launch from before the restart doesn't count")
        watch = SteamBrowser.Watch()
        check(!watch.hung(hung, now: at), "first seen: not hung")
        check(!watch.hung(hung, now: at.addingTimeInterval(4)), "4 s later: not yet")
        check(watch.hung(hung, now: at.addingTimeInterval(6)), "6 s later: hung")
        check(!watch.hung(next, now: at.addingTimeInterval(7)), "a new launch starts over")
        check(!watch.hung(up, now: at.addingTimeInterval(30)), "up: never hung")
        var slow = SteamBrowser.Watch()
        check(!slow.hung(valve, now: at) && !slow.hung(valve, now: at.addingTimeInterval(14)), "no Chrome yet: 15 s")
        check(slow.hung(valve, now: at.addingTimeInterval(16)), "then hung")

        // Only the browser ends, and Steam's client starts the next ~8 s later (a scratch prefix, 30.10.):
        // the ended one doesn't count any more; 25 s without a next one is a client that won't.
        var ending = SteamBrowser.Watch()
        _ = ending.hung(hung, now: at)
        check(ending.seen, "a browser of this start: its client is up")
        ending.ended(hung, now: at.addingTimeInterval(6))
        check(!ending.hung(hung, now: at.addingTimeInterval(60)), "the ended browser doesn't count as hung again")
        check(!ending.relaunchOverdue(hung, now: at.addingTimeInterval(20)), "14 s after: the next can still come")
        check(ending.relaunchOverdue(hung, now: at.addingTimeInterval(32)), "26 s after with none: overdue")
        check(!ending.hung(next, now: at.addingTimeInterval(14)), "the client's next browser: watched from new")
        check(!ending.relaunchOverdue(next, now: at.addingTimeInterval(60)), "it came: nothing overdue")
        check(ending.seen, "and the client still counts as up")
        ending.ignore(next.launch)
        check(!ending.seen && !ending.relaunchOverdue(next, now: at.addingTimeInterval(90)), "Steam started again: nothing seen yet")

        // Wine shows the Windows command lines: Valve's helper with its children, or the wrapper and its real one.
        let processes: [(pid: pid_t, command: String)] = [
            (10, #"C:\Program Files (x86)\Steam\steam.exe -no-cef-sandbox -cef-single-process"#),
            (11, #"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe -nocrashdialog -lang=de_DE"#),
            (12, #"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe --type=gpu-process"#),
            (13, #"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper_real.exe --disable-gpu --single-process"#),
            (14, #"C:\windows\system32\winedevice.exe"#),
            (15, "/path/to/wineserver"),
        ]
        check(SteamBootstrap.webHelperProcesses(processes) == [11, 12, 13], "the browser's processes, not Steam's client: \(SteamBootstrap.webHelperProcesses(processes))")
    }
}
