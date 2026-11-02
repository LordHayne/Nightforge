// Checks the library header's "up to date 2 min ago" (when the last scan finished) and
// "Scanning …" while one runs: tests/ScanFreshnessTest/run.sh
import Foundation

@main
struct ScanFreshnessTest {
    static var failures = 0

    static func check(_ actual: String?, _ expected: String?, _ message: String) {
        if actual != expected {
            failures += 1
            print("✗ \(message): \(actual ?? "nil") (expected \(expected ?? "nil"))")
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func text(_ last: Date?, scanning: Bool = false) -> String? {
            ScanFreshness.text(lastScan: last, scanning: scanning, now: now)
        }

        check(text(nil), nil, "never scanned: nothing")
        check(text(nil, scanning: true), "Scanning …", "first scan running")
        check(text(ago(5), scanning: true), "Scanning …", "a scan running wins over the last one")
        check(text(ago(0.5)), "up to date just now", "under a minute")
        check(text(ago(2)), "up to date 2 min ago", "2 minutes")
        check(text(ago(2.9)), "up to date 2 min ago", "whole minutes only")
        check(text(ago(59)), "up to date 59 min ago", "59 minutes")
        check(text(ago(60)), "up to date 1 h ago", "an hour")
        check(text(ago(150)), "up to date 3 h ago", "2½ hours round to 3")
        check(text(ago(26 * 60)), "up to date since yesterday", "a day")
        check(text(ago(3 * 1440 + 30)), "up to date 3 days ago", "3 days")
        check(text(now.addingTimeInterval(120)), "up to date just now", "a clock that went back: just now")

        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        check(text(ago(2)), "aktuell vor 2 Min.", "German minutes")
        check(text(ago(180)), "aktuell vor 3 Std.", "German hours")
        check(text(nil, scanning: true), "Wird eingelesen …", "German while scanning")
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)

        print(failures == 0 ? "✓ ScanFreshness" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
