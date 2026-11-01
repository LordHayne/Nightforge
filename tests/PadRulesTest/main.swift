// Checks the pad's rules from docs/ENTWURF-CONTROLLER.md (PadRules) and the hints' button symbols
// (PadSymbols): tests/PadRulesTest/run.sh
import AppKit

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

        // The pointer: hidden while the pad is used in front of Nightforge or its overlay, never over a game.
        check(PadRules.hidesPointer(inFront: true, overlay: false, inUse: true), "the pad in Nightforge: the pointer hides")
        check(PadRules.hidesPointer(inFront: false, overlay: true, inUse: true), "over a game in the overlay too")
        check(!PadRules.hidesPointer(inFront: false, overlay: false, inUse: true), "a game in front: the pointer is the game's")
        check(!PadRules.hidesPointer(inFront: true, overlay: false, inUse: false), "a resting pad doesn't hide it")

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

        // The hints' symbols: each shows its button's mark – a real symbol that isn't a bare shape, or
        // the drawn Options capsule – in every style.
        func shows(_ name: String) -> Bool {
            name == PadSymbols.optionsCapsule
                || (NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil && !PadSymbols.isBare(name))
        }
        for style in PadSymbols.Style.allCases {
            let pad = PadSymbols(style: style)
            for name in [pad.confirm, pad.back, pad.details, pad.search, pad.menu, pad.stick, pad.scroll] + pad.overlayChord {
                check(shows(name), "\(style): \(name) shows a mark")
            }
        }
        check(PadSymbols(style: .playstation).menu == PadSymbols.optionsCapsule, "PlayStation: ☰ is the Options capsule")
        check(PadSymbols(style: .xbox).menu == "line.3.horizontal.circle.fill", "Xbox: ☰ is the menu button's lines")

        // What a DualSense reports (1.11.): ☰ and ⧉ as a bare capsule, the rest with their marks.
        check(PadSymbols.menuSymbol("capsule.portrait") == PadSymbols.optionsCapsule, "a DualSense's ☰: the drawn capsule, not a blank")
        check(PadSymbols.filled("capsule.portrait") == nil, "a bare capsule is no symbol for a hint")
        for name in ["xmark.circle", "circle.circle", "square.circle", "triangle.circle", "l.joystick", "r.joystick"] {
            check(PadSymbols.filled(name).map(shows) == true, "a DualSense's \(name) is used, filled")
        }
        check(PadSymbols.menuSymbol(nil) == "line.3.horizontal.circle.fill", "no symbol for ☰: Xbox's")
        check(PadSymbols.menuSymbol("line.3.horizontal.circle") == "line.3.horizontal.circle.fill", "an Xbox pad's own ☰")
        check(PadSymbols.isBare("circle.fill") && !PadSymbols.isBare("circle.circle") && !PadSymbols.isBare("l1.rectangle.roundedbottom"),
              "one shape is bare, a shape with a mark isn't")

        print(failures == 0 ? "✓ PadRules" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
