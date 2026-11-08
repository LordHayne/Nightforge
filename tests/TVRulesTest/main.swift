// Checks what changes on a TV (TVRules): tests/TVRulesTest/run.sh
import CoreGraphics
import Foundation

@main
struct TVRulesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        let full = CGSize(width: 1920, height: 1080)
        check(TVRules.margins(onTV: false, screen: full) == TVRules.normal, "not a TV: the usual margins")
        check(TVRules.margins(onTV: true, screen: full) == .init(side: 96, top: 54, bottom: 54), "1080p TV: 5 % all round")
        check(TVRules.margins(onTV: true, screen: CGSize(width: 3840, height: 2160)).side == 192, "4K points: still 5 %")
        check(TVRules.margins(onTV: true, screen: CGSize(width: 800, height: 400)) == TVRules.normal, "never less than usual")
        check(TVRules.usesLargerText(setting: false, onTV: true), "larger text comes by itself on a TV")
        check(TVRules.usesLargerText(setting: true, onTV: false), "and stays the player's switch elsewhere")
        check(!TVRules.usesLargerText(setting: false, onTV: false), "off otherwise")
        check(TVRules.ringWidth(onTV: true) > TVRules.ringWidth(onTV: false), "the highlight is thicker on a TV")
        print(failures == 0 ? "✓ TVRules" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
