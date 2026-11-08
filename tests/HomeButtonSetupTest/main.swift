// Checks the home button's setup (HomeButtonSetup) against what macOS offers. Only looks whether the
// class answers to the names; it never reads or opens anything: tests/HomeButtonSetupTest/run.sh
import Foundation
import GameController

@main
struct HomeButtonSetupTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(HomeButtonSetup.state(systemAction: 1) == .opensNightforge, "1 opens the current app")
        check(HomeButtonSetup.state(systemAction: -1) == .unavailable, "-1: not allowed to read it")
        check(HomeButtonSetup.state(systemAction: 0) == .somethingElse, "0: another action")
        check(HomeButtonSetup.state(systemAction: Int.max) == .somethingElse, "the button switched off counts as something else")

        if #available(macOS 27, *) {
            let known = NSClassFromString(HomeButtonSetup.className)
            check(known != nil, "macOS 27 has the class")
            check(known?.instancesRespond(to: HomeButtonSetup.readSelector) == true, "the name for reading is right")
            check(known?.instancesRespond(to: HomeButtonSetup.openSelector) == true, "the name for opening is right")
        }
        print(failures == 0 ? "✓ HomeButtonSetup" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
