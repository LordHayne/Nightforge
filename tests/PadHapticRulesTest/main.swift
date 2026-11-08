// Checks which moments the pad answers with its motors (PadHapticRules): tests/PadHapticRulesTest/run.sh
import Foundation

@main
struct PadHapticRulesTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        typealias Rules = PadHapticRules
        func plays(_ moment: Rules.Moment, setting: Bool = true, inFront: Bool = false, overlay: Bool = false, pad: Bool = false) -> Bool {
            Rules.plays(moment, setting: setting, inFront: inFront, overlay: overlay, padUsedLast: pad)
        }
        check(plays(.confirm, inFront: true), "A in Nightforge")
        check(plays(.confirm, overlay: true), "A in the overlay")
        check(!plays(.confirm), "A in a game is the game's")
        check(plays(.gameStart, pad: true), "started with the pad")
        check(!plays(.gameStart), "started with the mouse: the pad may lie on the table")
        check(plays(.overlayHold) && plays(.overlayOpens), "the overlay's buttons are Nightforge's, in a game too")
        for moment in [Rules.Moment.confirm, .gameStart, .overlayHold, .overlayOpens] {
            check(!plays(moment, setting: false, inFront: true, overlay: true, pad: true), "the switch turns \(moment) off")
            check(Rules.taps(moment).allSatisfy { (0...1).contains($0.intensity) && (0...1).contains($0.sharpness) }, "\(moment): valid values")
        }
        let hold = Rules.taps(.overlayHold)
        check(hold.first!.time > 0.2, "both sticks pressed in passing feel like nothing")
        check(hold.last!.time < 2, "it's over before the two seconds are up")
        check(zip(hold, hold.dropFirst()).allSatisfy { $0.intensity < $1.intensity && $0.time < $1.time }, "it builds")
        check(Rules.taps(.overlayOpens)[0].intensity > hold.last!.intensity, "the overlay opening is the firmest")
        check(Rules.taps(.confirm).count == 1, "a confirmation is one short tap")
        print(failures == 0 ? "✓ PadHapticRules" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
