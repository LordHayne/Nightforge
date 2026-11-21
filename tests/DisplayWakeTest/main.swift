// Checks when a press on the pad brings the picture back (DisplayWake.wakes). It never declares
// any use itself: tests/DisplayWakeTest/run.sh
import Foundation

@main
struct DisplayWakeTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(DisplayWake.wakes(freshPress: true, displayAsleep: true), "a press with the screen asleep brings it back")
        check(!DisplayWake.wakes(freshPress: false, displayAsleep: true), "a held button or a stick's noise doesn't")
        check(!DisplayWake.wakes(freshPress: true, displayAsleep: false), "with the screen on there's nothing to do")
        print(failures == 0 ? "✓ DisplayWake" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
