// Checks which screen GameDisplay picks to play on and which ones count as TVs:
// tests/GameDisplayTest/run.sh
import CoreGraphics
import Foundation

@main
struct GameDisplayTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func screen(_ id: UInt32, _ name: String, builtIn: Bool = false, _ width: Int = 1920, _ height: Int = 1080)
        -> GameDisplay.Candidate {
        GameDisplay.Candidate(id: id, name: name, builtIn: builtIn, pixels: width * height)
    }

    static func main() {
        let macBook = screen(1, "Built-in Retina Display", builtIn: true, 3024, 1964)

        check(GameDisplay.pick([macBook]) == nil, "a MacBook alone stays on its own screen")
        check(GameDisplay.pick([]) == nil, "no screens, no pick")
        check(GameDisplay.pick([macBook, screen(2, "LG TV SSCR2", 3840, 2160)]) == 2, "a TV next to a MacBook")
        check(GameDisplay.pick([screen(3, "DELL U2720Q", 3840, 2160)]) == 3, "a Mac mini's only monitor")
        check(GameDisplay.pick([macBook, screen(4, "DELL U2720Q", 3840, 2160), screen(5, "SONY TV  *00")]) == 5,
              "a TV wins over a bigger monitor")
        check(GameDisplay.pick([macBook, screen(6, "DELL P2419H"), screen(7, "LG UltraFine", 5120, 2880)]) == 7,
              "of two monitors the bigger one")

        // Mirroring: the MacBook shows the TV's picture (the TV is master), or the other way round.
        var mirroredMacBook = macBook
        mirroredMacBook.mirrors = true
        check(GameDisplay.pick([mirroredMacBook, screen(2, "LG TV SSCR2")]) == 2, "a TV the MacBook mirrors")
        var mirroringTV = screen(2, "LG TV SSCR2")
        mirroringTV.mirrors = true
        check(GameDisplay.pick([macBook, mirroringTV]) == nil, "a TV that mirrors the MacBook is no place of its own")

        // Which display becomes main for a game: 1 MacBook, 2 TV, 3 monitor; in a mirror set 2 is master.
        let separate: (CGDirectDisplayID) -> CGDirectDisplayID = { $0 }
        let mirrored: (CGDirectDisplayID) -> CGDirectDisplayID = { $0 == 1 ? 2 : $0 }
        check(GameDisplay.newMain(for: 2, main: 1, primary: separate) == 2, "extended: the TV becomes main")
        check(GameDisplay.newMain(for: 2, main: 2, primary: separate) == nil, "extended: the TV is main already")
        check(GameDisplay.newMain(for: 2, main: 2, primary: mirrored) == nil, "mirrored: the TV master is main, nothing to do")
        check(GameDisplay.newMain(for: 1, main: 2, primary: mirrored) == nil, "mirrored: the MacBook's screen is the TV's, nothing to do")
        check(GameDisplay.newMain(for: 2, main: 1, primary: mirrored) == nil, "mirrored: main is the set either way")
        check(GameDisplay.newMain(for: 3, main: 1, primary: mirrored) == 3, "a monitor beside a mirror set becomes main")
        check(GameDisplay.newMain(for: 1, main: 3, primary: mirrored) == 2, "back to the mirror set: its master becomes main")

        for name in ["LG TV SSCR2", "SAMSUNG", "SONY TV  *00", "Hisense", "TCL TV", "VIZIO M55", "BRAVIA 4K"] {
            check(screen(9, name).isTV, "\(name) is a TV")
        }
        for name in ["DELL U2720Q", "LG UltraFine", "Studio Display", "Built-in Retina Display", "PHL 276E8V", "Odyssey G7"] {
            check(!screen(9, name).isTV, "\(name) is no TV")
        }

        if failures == 0 { print("✓ GameDisplay: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}
