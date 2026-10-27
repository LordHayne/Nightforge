// Checks a download's speed and time left from the progress Nightforge reads every few seconds:
// tests/DownloadRateTest/run.sh
import Foundation

@main
struct DownloadRateTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let mb = 1_000_000.0

        // One look says nothing; a few seconds of progress do.
        var rate = DownloadRate()
        rate.add(bytes: 0, at: start)
        check(rate.bytesPerSecond == nil, "one look: no speed yet")
        rate.add(bytes: 30 * mb, at: start.addingTimeInterval(3))
        check(rate.bytesPerSecond == nil, "3 s are too short to tell")
        rate.add(bytes: 60 * mb, at: start.addingTimeInterval(6))
        check(rate.bytesPerSecond == 10 * mb, "10 MB/s: \(rate.bytesPerSecond ?? -1)")
        check(rate.secondsLeft(total: 660 * mb) == 60, "600 MB at 10 MB/s is a minute: \(rate.secondsLeft(total: 660 * mb) ?? -1)")

        // Only the last half minute counts: a slower stretch shows soon.
        for second in stride(from: 9, through: 60, by: 3) {
            rate.add(bytes: 60 * mb + Double(second - 6) * 2 * mb, at: start.addingTimeInterval(Double(second)))
        }
        check(abs((rate.bytesPerSecond ?? 0) - 2 * mb) < 1, "slowed to 2 MB/s: \(rate.bytesPerSecond ?? -1)")
        check(rate.samples.first.map { start.addingTimeInterval(60).timeIntervalSince($0.date) <= DownloadRate.window } == true,
              "nothing older than the window is kept")

        // Starting over (less than before) forgets the old speed; standing still says nothing.
        rate.add(bytes: 5 * mb, at: start.addingTimeInterval(63))
        check(rate.samples.count == 1 && rate.bytesPerSecond == nil, "a restart begins again")
        var stuck = DownloadRate()
        stuck.add(bytes: 50 * mb, at: start)
        stuck.add(bytes: 50 * mb, at: start.addingTimeInterval(10))
        check(stuck.bytesPerSecond == nil && stuck.label(total: 100 * mb) == nil, "no progress: no speed, no label")

        // What the panel says.
        var steady = DownloadRate()
        steady.add(bytes: 0, at: start)
        steady.add(bytes: 120 * mb, at: start.addingTimeInterval(10))
        let label = steady.label(total: 120 * mb + 12 * mb * 1500) ?? ""
        check(label.hasPrefix("12 MB/s · ") && label.hasSuffix(" left"), "speed and time: \(label)")
        check(DownloadRate.duration(30) == "under a minute", "under a minute")
        check(DownloadRate.duration(61) == "2 min", "rounded up to whole minutes: \(DownloadRate.duration(61))")
        check(DownloadRate.duration(5400) == "1 hr, 30 min", "hours and minutes: \(DownloadRate.duration(5400))")
        check(steady.label(total: 100 * mb) == "12 MB/s", "nothing left to wait for: the speed alone: \(steady.label(total: 100 * mb) ?? "nil")")

        print(failures == 0 ? "✓ DownloadRate" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
