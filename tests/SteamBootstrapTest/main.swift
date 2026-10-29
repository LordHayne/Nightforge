// Checks SteamBootstrap against Steam's own bootstrap logs: the first update on 23.10.2026 that went
// through (win32, win64, then the new client) and the loop of 29.10.2026, where Nightforge swapped
// in its steamwebhelper wrapper and restarted Steam in the middle of every install – its first four
// starts and its last four, of 131. Also that the wrapper isn't swapped in while an update goes in:
// tests/SteamBootstrapTest/run.sh
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
        check(!good.isEmpty && !loop.isEmpty && !loopEnd.isEmpty, "the logs are there")
        goodRun()
        theLoop()
        decisions()
        wrapperSwap()
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

    /// What the first start's watchdog makes of each state.
    static func decisions() {
        check(SteamBootstrap.idle.allowsHelperSwap && SteamBootstrap.updated.allowsHelperSwap, "idle and updated: swap allowed")
        check(!SteamBootstrap.downloading.allowsHelperSwap && !SteamBootstrap.installing.allowsHelperSwap, "downloading and installing: no swap")

        check(!SteamBootstrap.installing.stalled(quietFor: 120), "a quiet install isn't stalled after 2 min")
        check(SteamBootstrap.installing.stalled(quietFor: 301), "an install quiet for 5 min is")
        check(SteamBootstrap.idle.stalled(quietFor: 91) && SteamBootstrap.downloading.stalled(quietFor: 91), "otherwise 90 s, as before")
        check(!SteamBootstrap.downloading.stalled(quietFor: 30), "a download that moves isn't stalled")

        check(!SteamBootstrap.updated.gone(steamRunning: false, sinceRestart: 30, quietFor: 20), "right after an update Steam restarts itself: not gone")
        check(SteamBootstrap.updated.gone(steamRunning: false, sinceRestart: 90, quietFor: 61), "a minute later it is")
        check(SteamBootstrap.installing.gone(steamRunning: false, sinceRestart: 20, quietFor: 5), "the bootstrapper died mid-install: gone")
        check(!SteamBootstrap.idle.gone(steamRunning: true, sinceRestart: 100, quietFor: 100), "running: not gone")
        check(!SteamBootstrap.idle.gone(steamRunning: false, sinceRestart: 10, quietFor: 100), "just started: not gone yet")
    }

    /// Engine.installWebHelperWrapper on a Steam folder of its own: leaves Valve's helper alone
    /// while the log says it installs, swaps it once the new client runs; and the log's end is read
    /// even when the log is long.
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
}
