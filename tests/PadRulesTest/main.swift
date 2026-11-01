// Checks the pad's rules from docs/ENTWURF-CONTROLLER.md (PadRules): tests/PadRulesTest/run.sh
import Foundation

@main
struct PadRulesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        typealias Open = PadRules.Open

        // B: one press, one level, the innermost first.
        check(PadRules.back(Open()) == .level, "nothing open: a level up")
        check(PadRules.back(Open(awaitingSteam: true)) == .cancelLaunch, "a start waiting for Steam is called off first")
        check(PadRules.back(Open(lightbox: true, list: true, downloads: true)) == .lightbox, "the big screenshot is innermost")
        check(PadRules.back(Open(list: true, downloads: true, highlight: true)) == .list, "a chip's list before the downloads")
        check(PadRules.back(Open(downloads: true, highlight: true)) == .downloads,
              "the downloads panel closes in one press, also with its highlight")
        check(PadRules.back(Open(highlight: true)) == .highlight, "Home and the library: from the buttons back to the games")
        check(PadRules.back(Open(highlight: true, gamePage: true)) == .level, "a game's page goes back at once, highlight or not")
        check(PadRules.back(Open(sheet: true, lightbox: true)) == .sheet, "a sheet over the big screenshot closes first")
        check(PadRules.back(Open(sheet: true, options: true)) == .options, "the game's options close as a sheet of their own")
        check(PadRules.back(Open(sheet: true, modal: true, options: true)) == .sheet,
              "a question over the options answers B, not the options behind it")
        check(PadRules.back(Open(overlay: true, sheet: true, downloads: true)) == .overlay, "over a game the overlay has B")

        // X, Y, ☰ and L2/R2 only with nothing in front of the levels.
        check(PadRules.actsOnGames(inFront: true, sheet: false, panel: false), "the levels free: they act")
        check(!PadRules.actsOnGames(inFront: true, sheet: false, panel: true), "not behind the downloads panel, a list or a big screenshot")
        check(!PadRules.actsOnGames(inFront: true, sheet: true, panel: false), "not behind a sheet")
        check(!PadRules.actsOnGames(inFront: false, sheet: false, panel: false), "not with a game in front")

        // Home: ↓ to the game's buttons, ↑ to the top bar, sideways the games; back the way it came.
        check(PadRules.homeEntry(dy: 1) == .game, "down on Home: the game's buttons, not the library")
        check(PadRules.homeEntry(dy: -1) == .top, "up on Home: the top bar")
        check(PadRules.homeEntry(dy: 0) == nil, "sideways: the games move")
        check(PadRules.homeLeaves(.game, dy: -1) && !PadRules.homeLeaves(.game, dy: 1), "up from the buttons back to the games, down stays")
        check(PadRules.homeLeaves(.top, dy: 1) && !PadRules.homeLeaves(.top, dy: -1), "down from the top bar back to the games, up stays")
        check(!PadRules.homeLeaves(.game, dy: 0) && !PadRules.homeLeaves(nil, dy: -1), "sideways stays; nothing else leaves")

        // Settings: L1/R1 step through the tabs and stop at either end.
        check(PadRules.settingsTab(.r1, current: 1, count: 5) == 2 && PadRules.settingsTab(.l1, current: 1, count: 5) == 0, "L1/R1: the tab before and after")
        check(PadRules.settingsTab(.l1, current: 0, count: 5) == nil && PadRules.settingsTab(.r1, current: 4, count: 5) == nil, "no wrap at the ends")
        check(PadRules.settingsTab(.a, current: 2, count: 5) == nil, "other buttons don't change tabs")

        // The right stick in the library: whole rows, the rest kept for the next ones.
        let half = PadRules.stickRows(110)
        check(half.rows == 0 && half.left == 110, "less than a row: nothing yet")
        let two = PadRules.stickRows(500)
        check(two.rows == 2 && two.left == 60, "two rows down, 60 points kept: \(two)")
        let up = PadRules.stickRows(-230)
        check(up.rows == -1 && up.left == -10, "up works the same: \(up)")

        // L1/R1 in the main window stay as they were.
        check(InputRouter.section(for: .r1, route: .home, inFront: true, dialog: false, firstStart: false) == .library,
              "R1 on Home: the library")
        check(InputRouter.section(for: .l1, route: .library, inFront: true, dialog: true, firstStart: false) == nil,
              "not behind a panel or sheet")

        print(failures == 0 ? "✓ PadRules" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
