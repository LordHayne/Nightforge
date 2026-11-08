// FAILS on staging-032 c475580: LaunchWatcher.poll (Launcher.swift:415-420) reads to the end of Steam's log and moves
// its offset past it, also when the last line isn't finished. The rest of that line then lands in the next poll
// without its first half, so an event split over two polls is lost: a Steam question ("waiting for user
// response") that only shows half when polled is never reported. tests/BugLaunchWatcherPartialLineTest/run.sh
import Foundation

@main
struct BugLaunchWatcherPartialLineTest {
    static func main() {
        let steam = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bug-watch-\(UUID().uuidString)", isDirectory: true)
        let log = steam.appendingPathComponent("logs/console_log.txt")
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: log)
        defer { try? FileManager.default.removeItem(at: steam) }
        var watcher = LaunchWatcher(steamRoot: steam, appID: 730)

        func append(_ text: String) {
            guard let handle = try? FileHandle(forWritingTo: log) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        }
        append("[2026] GameAction [AppID 730, ActionID 9] : LaunchApp waiting for user resp")
        let first = watcher.poll()
        append("onse to CloudSync\n")
        let second = watcher.poll()
        guard first == .needsConfirmation || second == .needsConfirmation else {
            print("✗ a line written in two parts is lost: \(String(describing: first)), then \(String(describing: second))")
            exit(1)
        }
        print("✓ A log line that arrives in parts is still read")
    }
}
