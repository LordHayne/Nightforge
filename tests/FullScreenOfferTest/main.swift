// Checks when full screen is offered (FullScreenOffer): tests/FullScreenOfferTest/run.sh
import Foundation

@main
struct FullScreenOfferTest {
    static func main() {
        var failures = 0
        func offers(offered: Bool = false, pad: Bool = true, inFront: Bool = true, full: Bool = false, builtIn: Bool = true,
                    firstStart: Bool = false, gameOn: Bool = false, open: Bool = false) -> Bool {
            FullScreenOffer.offers(alreadyOffered: offered, padConnected: pad, inFront: inFront, fullScreen: full, onBuiltInScreen: builtIn,
                                   firstStart: firstStart, gameOn: gameOn, somethingOpen: open)
        }
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(offers(), "a controller at the MacBook, in a window: yes")
        check(!offers(offered: true), "once per start")
        check(!offers(pad: false), "without a controller: no")
        check(!offers(inFront: false), "not from the background")
        check(!offers(full: true), "already full screen: nothing to offer")
        check(!offers(builtIn: false), "a TV goes full screen by itself, a monitor is a desk")
        check(!offers(firstStart: true), "not in the first start")
        check(!offers(gameOn: true), "not with a game on")
        check(!offers(open: true), "not over a question or a menu")
        print(failures == 0 ? "✓ FullScreenOffer" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
