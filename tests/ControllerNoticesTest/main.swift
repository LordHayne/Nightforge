// Checks what's said when a controller comes, goes or runs low (ControllerNotices): tests/ControllerNoticesTest/run.sh
import Foundation

final class Box {}

@main
struct ControllerNoticesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Pad = ControllerNotices.Pad

    static func main() {
        let one = Box(), two = Box(), again = Box()
        func pad(_ box: Box, battery: Float? = 0.65, charging: Bool = false, name: String = "DualSense") -> Pad {
            Pad(id: ObjectIdentifier(box), name: name, battery: battery, charging: charging)
        }

        var notices = ControllerNotices(started: 0)
        check(notices.update([pad(one)], now: 1).isEmpty, "found while Nightforge starts: no news")
        check(notices.update([pad(one)], now: 20).isEmpty, "no change, nothing to say")
        check(notices.update([pad(one), pad(two, name: "Xbox")], now: 30) == [.connected("Xbox", battery: 65)], "a second pad: named, with its battery")
        check(notices.update([pad(one)], now: 40) == [.lost("Xbox")], "one leaves: named")

        // Bluetooth dropping out for a moment.
        var flicker = ControllerNotices(started: 0)
        _ = flicker.update([pad(one)], now: 10)
        check(flicker.update([], now: 20) == [.lost("DualSense")], "gone")
        check(flicker.update([pad(again)], now: 22).isEmpty, "back within a moment: no second note")
        _ = flicker.update([], now: 30)
        check(flicker.update([pad(two)], now: 40) == [.connected("DualSense", battery: 65)], "back much later: news again")

        // Without a battery reading.
        var silent = ControllerNotices(started: 0)
        _ = silent.update([], now: 10)
        check(silent.update([pad(one, battery: nil)], now: 11) == [.connected("DualSense", battery: nil)], "a pad that doesn't say")

        // The battery.
        var low = ControllerNotices(started: 0)
        _ = low.update([pad(one, battery: 0.5)], now: 10)
        check(low.update([pad(one, battery: 0.16)], now: 100).isEmpty, "above 15 %: quiet")
        check(low.update([pad(one, battery: 0.15)], now: 200) == [.low("DualSense", percent: 15)], "at 15 %: once")
        check(low.update([pad(one, battery: 0.1)], now: 300).isEmpty, "and not again as it sinks")
        check(low.update([pad(one, battery: 0.1, charging: true)], now: 400).isEmpty, "on the cable: nothing to warn of")
        check(low.update([pad(one, battery: 0.1)], now: 500) == [.low("DualSense", percent: 10)], "off it and still low: once more")
        _ = low.update([pad(one, battery: 0.3)], now: 600)
        check(low.update([pad(one, battery: 0.14)], now: 700) == [.low("DualSense", percent: 14)], "charged and low again: a new warning")

        var early = ControllerNotices(started: 0)
        check(early.update([pad(one, battery: 0.1)], now: 1) == [.low("DualSense", percent: 10)], "a low pad at the start is said, that is news")

        print(failures == 0 ? "✓ ControllerNotices" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
