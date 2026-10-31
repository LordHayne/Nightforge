// Checks which screen GameDisplay picks to play on, which ones count as TVs and when a game
// counts as ended:
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

        // Where the window goes and when it's full screen. The live test on 31.10.: a mirrored DENON-AVR
        // was the only screen, the window already on it – and it stayed a window.
        let denon = screen(4, "DENON-AVR")
        check(GameDisplay.placement(picked: denon, windowOn: 4, declined: nil, fullScreen: false)
              == GameDisplay.Placement(move: false, fullScreen: true), "a mirrored TV: full screen where the window is")
        check(GameDisplay.placement(picked: denon, windowOn: 4, declined: nil, fullScreen: true) == nil, "full screen already: nothing")
        check(GameDisplay.placement(picked: screen(2, "LG TV SSCR2"), windowOn: 1, declined: nil, fullScreen: false)
              == GameDisplay.Placement(move: true, fullScreen: true), "a TV beside the MacBook: over there, full screen")
        check(GameDisplay.placement(picked: screen(2, "LG TV SSCR2"), windowOn: 1, declined: nil, fullScreen: true)
              == GameDisplay.Placement(move: true, fullScreen: true), "full screen on the MacBook: out, over, in again")
        check(GameDisplay.placement(picked: screen(3, "DELL U2720Q"), windowOn: 1, declined: nil, fullScreen: false)
              == GameDisplay.Placement(move: true, fullScreen: false), "a monitor: moved, as a window")
        check(GameDisplay.placement(picked: screen(3, "DELL U2720Q"), windowOn: 3, declined: nil, fullScreen: false) == nil,
              "on the monitor already: nothing")
        check(GameDisplay.placement(picked: denon, windowOn: 4, declined: 4, fullScreen: false) == nil,
              "the player moved it away from the TV before: left alone")
        check(GameDisplay.placement(picked: denon, windowOn: 1, declined: 4, fullScreen: false) == nil, "declined, from elsewhere too")
        check(GameDisplay.placement(picked: nil, windowOn: 1, declined: nil, fullScreen: false) == nil, "no screen to play on")
        // And back out when the TV goes.
        check(GameDisplay.leavesFullScreen(madeFullScreen: true, fullScreen: true, windowOn: macBook), "TV unplugged: a window again")
        check(GameDisplay.leavesFullScreen(madeFullScreen: true, fullScreen: true, windowOn: nil), "TV going, no screen yet: a window again")
        check(!GameDisplay.leavesFullScreen(madeFullScreen: true, fullScreen: true, windowOn: denon), "still on the TV: stays")
        check(!GameDisplay.leavesFullScreen(madeFullScreen: false, fullScreen: true, windowOn: macBook), "the player's own full screen stays")
        check(!GameDisplay.leavesFullScreen(madeFullScreen: true, fullScreen: false, windowOn: macBook), "not full screen: nothing")

        // Wine keeps the screens its session began with: a fresh session when they changed since.
        typealias W = GameDisplay.WineScreen
        let alone = GameDisplay.wineSignature([W(id: 1, main: true, points: CGSize(width: 1512, height: 982),
                                                 pixels: CGSize(width: 3024, height: 1964))])
        let mirrorSet = GameDisplay.wineSignature([W(id: 4, main: true, points: CGSize(width: 1920, height: 1080),
                                                    pixels: CGSize(width: 1920, height: 1080))])
        let extended = GameDisplay.wineSignature([W(id: 4, main: false, points: CGSize(width: 1920, height: 1080), pixels: CGSize(width: 1920, height: 1080)),
                                                  W(id: 1, main: true, points: CGSize(width: 1512, height: 982), pixels: CGSize(width: 3024, height: 1964))])
        let extendedTVMain = GameDisplay.wineSignature([W(id: 1, main: false, points: CGSize(width: 1512, height: 982), pixels: CGSize(width: 3024, height: 1964)),
                                                        W(id: 4, main: true, points: CGSize(width: 1920, height: 1080), pixels: CGSize(width: 1920, height: 1080))])
        check(alone == "1*:1512x982@3024x1964", "the MacBook alone (\(alone))")
        check(Set([alone, mirrorSet, extended, extendedTVMain]).count == 4, "alone, mirrorSet, extended and the TV made main all differ")
        let session = GameDisplay.WineSession(server: 500, screens: alone)
        var result = GameDisplay.wineSessionCheck(stored: nil, server: 500, now: alone)
        check(!result.stale && result.store == session, "a session seen for the first time: what's there now")
        result = GameDisplay.wineSessionCheck(stored: session, server: 500, now: alone)
        check(!result.stale && result.store == session, "nothing changed: no restart")
        result = GameDisplay.wineSessionCheck(stored: session, server: 500, now: mirrorSet)
        check(result.stale && result.store == session, "the live test: begun on the MacBook, now the TV mirrorSet – a fresh session")
        result = GameDisplay.wineSessionCheck(stored: session, server: 500, now: extendedTVMain)
        check(result.stale, "a TV made main for the game: a fresh session, so it's Wine's primary too")
        result = GameDisplay.wineSessionCheck(stored: session, server: 777, now: mirrorSet)
        check(!result.stale && result.store == GameDisplay.WineSession(server: 777, screens: mirrorSet), "a new session: fresh, remembered as such")
        result = GameDisplay.wineSessionCheck(stored: session, server: nil, now: mirrorSet)
        check(!result.stale && result.store == nil, "no session: nothing to restart, nothing kept")

        // Which TV shows Nightforge, for its sound: false = an external display in the mirror set.
        let tv = screen(2, "LG TV SSCR2"), avr = screen(4, "DENON-AVR"), monitor = screen(3, "DELL U2720Q")
        check(GameDisplay.soundScreen(tv, mirroredWith: []) == "LG TV SSCR2", "on a TV: its sound")
        check(GameDisplay.soundScreen(avr, mirroredWith: [true]) == "DENON-AVR", "the live test: the receiver's screen, the MacBook mirroring it")
        check(GameDisplay.soundScreen(monitor, mirroredWith: []) == nil, "a desk monitor keeps the Mac's sound")
        check(GameDisplay.soundScreen(monitor, mirroredWith: [true]) == "DELL U2720Q", "mirrored with the MacBook: the big screen")
        check(GameDisplay.soundScreen(macBook, mirroredWith: [false]) == "", "the MacBook mirrored onto an external screen")
        check(GameDisplay.soundScreen(macBook, mirroredWith: []) == nil, "the MacBook alone")
        check(GameDisplay.soundScreen(nil, mirroredWith: []) == nil, "no window yet")
        check(screen(9, "DENON-AVR").isTV && screen(9, "marantz AVR").isTV, "an AV receiver in front of a TV counts as one")

        // When a game whose processes are gone counts as ended, and Nightforge comes back.
        check(!LibraryModel.gameEnded(looksGone: 1, goneFor: 0, ranFor: 1800), "the look its end woke: not yet")
        check(LibraryModel.gameEnded(looksGone: 2, goneFor: 1, ranFor: 1800), "after a session, a second later")
        check(LibraryModel.gameEnded(looksGone: 2, goneFor: 1, ranFor: 60), "a minute is a session")
        check(!LibraryModel.gameEnded(looksGone: 2, goneFor: 1, ranFor: 8), "early on, a launcher may still hand over")
        check(!LibraryModel.gameEnded(looksGone: 3, goneFor: 2, ranFor: 8), "early on: not before three seconds")
        check(LibraryModel.gameEnded(looksGone: 4, goneFor: 3, ranFor: 8), "early on: after three seconds")
        check(!LibraryModel.gameEnded(looksGone: 1, goneFor: 5, ranFor: 8), "one look is never enough")

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
