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

        check(HomeButtonSetup.appMayHave(inAppAction: 1), "the app decides: the short press can be Nightforge's")
        check(HomeButtonSetup.appMayHave(inAppAction: Int.max), "the button switched off for the system reaches the app too")
        check(!HomeButtonSetup.appMayHave(inAppAction: 0), "macOS's own handling stays macOS's")
        check(!HomeButtonSetup.appMayHave(inAppAction: -1), "can't be read: not assumed")
        check(HomeButtonSetup.takesButton(exists: true, active: true, overlay: false), "macOS 27, Nightforge in front: Nightforge's")
        check(!HomeButtonSetup.takesButton(exists: false, active: true, overlay: false), "macOS 26: everything as before")
        check(!HomeButtonSetup.takesButton(exists: true, active: false, overlay: false), "a game in front: macOS's")
        check(!HomeButtonSetup.takesButton(exists: true, active: true, overlay: true), "the overlay over a game: macOS's")
        check(HomeButtonSetup.isShortPress(held: 0.2) && !HomeButtonSetup.isShortPress(held: 0.6), "short, and held")
        check(HomeButtonSetup.Page.longPress.rawValue == 1 && HomeButtonSetup.Page.shortPress.rawValue == 2, "the pages' numbers from the header")

        if #available(macOS 27, *) {
            let known = NSClassFromString(HomeButtonSetup.className)
            check(known != nil, "macOS 27 has the class")
            check(known?.instancesRespond(to: HomeButtonSetup.readSelector) == true, "the name for reading is right")
            check(known?.instancesRespond(to: HomeButtonSetup.openSelector) == true, "the name for opening is right")
            check(known?.instancesRespond(to: HomeButtonSetup.readInAppSelector) == true, "the name for the in-app action is right")
        }
        print(failures == 0 ? "✓ HomeButtonSetup" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
