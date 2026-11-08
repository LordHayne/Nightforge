// Checks when macOS's question about notifications is put (NotificationMoment): tests/NotificationMomentTest/run.sh
import Foundation

@main
struct NotificationMomentTest {
    static func main() {
        var failures = 0
        func asks(asked: Bool = false, setting: Bool = true, inFront: Bool = true, gameOn: Bool = false, firstStart: Bool = false, pad: Bool = false) -> Bool {
            NotificationMoment.asksNow(alreadyAsked: asked, setting: setting, inFront: inFront, gameOn: gameOn, firstStart: firstStart, padUsedLast: pad)
        }
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(asks(), "Nightforge in front, the mouse in hand: now")
        check(!asks(asked: true), "once per run")
        check(!asks(setting: false), "not if the player turned the notifications off")
        check(!asks(inFront: false), "not from the background")
        check(!asks(gameOn: true), "not with a game on or starting")
        check(!asks(firstStart: true), "after the first start, not in the middle of it")
        check(!asks(pad: true), "not on the sofa: the pad can't answer macOS")
        print(failures == 0 ? "✓ NotificationMoment" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
