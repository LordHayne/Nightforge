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
        func takes(exists: Bool = true, active: Bool = true, overlay: Bool = false, gameOn: Bool = false, allowed: Bool = true, asked: Bool = false) -> Bool {
            HomeButtonSetup.takesButton(exists: exists, active: active, overlay: overlay, gameOn: gameOn, allowed: allowed, asked: asked)
        }
        check(takes(), "macOS 27, allowed, Nightforge in front: Nightforge's")
        check(!takes(exists: false), "macOS 26: everything as before")
        check(!takes(active: false), "a game in front: macOS's")
        check(!takes(overlay: true), "the overlay over a game: macOS's")
        check(!takes(gameOn: true), "while a game runs or starts, even with Nightforge in front")
        check(!takes(allowed: false), "never asks by itself: macOS's question would stand over the next game")
        check(takes(allowed: false, asked: true), "the player asked for it in Settings: then it may ask")
        check(!takes(gameOn: true, allowed: false, asked: true), "and not over a game even then")
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
