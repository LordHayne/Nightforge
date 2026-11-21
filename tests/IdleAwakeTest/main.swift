// Checks how long Nightforge may keep the Mac awake (IdleAwake.holds). It takes no real hold: tests/IdleAwakeTest/run.sh
import Foundation

@main
struct IdleAwakeTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(IdleAwake.choices.first == 0, "the first choice is leaving the Mac alone")
        check(IdleAwake.minutes(stored: 0) == 0, "and that's the default: nothing stored reads as 0")
        check(!IdleAwake.holds(minutes: 0, onBattery: false, idle: 0), "off: never, even right after the last input")
        check(IdleAwake.holds(minutes: 30, onBattery: false, idle: 60), "within the time: held")
        check(!IdleAwake.holds(minutes: 30, onBattery: false, idle: 30 * 60), "after it: the Mac may sleep")
        check(!IdleAwake.holds(minutes: 120, onBattery: true, idle: 0), "on battery: never")
        check(IdleAwake.minutes(stored: 7) == 0, "a number that's no choice counts as off")
        check(IdleAwake.minutes(stored: 60) == 60, "a choice is kept")
        print(failures == 0 ? "✓ IdleAwake" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
