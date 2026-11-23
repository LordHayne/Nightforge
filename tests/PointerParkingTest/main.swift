// Checks when the pointer leaves a game's picture (PointerParking). It never moves the real one: tests/PointerParkingTest/run.sh
import CoreGraphics
import Foundation

@main
struct PointerParkingTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        func parks(_ parking: inout PointerParking, pad: Bool = true, now: TimeInterval = 100, mouse: TimeInterval = 60, pointer: Bool = false,
                   setting: Bool = true, overGame: Bool = true, question: Bool = false) -> Bool {
            parking.parksNow(padInUse: pad, now: now, mouseAgo: mouse, pointerInUse: pointer, setting: setting, overGame: overGame, question: question)
        }

        var a = PointerParking()
        check(parks(&a), "the pad in use over a game: out of the picture")
        check(a.isParked && !parks(&a, now: 101, mouse: 61), "and once is enough: a game never sees it moved again and again")
        check(!parks(&a, now: 102, mouse: 0.5), "the mouse used: it's the player's again")
        check(!a.isParked, "and it counts as back")
        check(!parks(&a, now: 102.5, mouse: 1), "right after the mouse: the pad doesn't take it away")
        check(parks(&a, now: 110, mouse: 8), "the mouse lay still and the pad is used: away again")

        var b = PointerParking()
        check(!parks(&b, pad: false), "nobody on the pad: nothing")
        check(!parks(&b, mouse: 1), "the mouse just used: nothing")
        check(!parks(&b, pointer: true), "the touchpad as the pointer: it stays")
        check(!parks(&b, setting: false), "the way out in the settings")
        check(!parks(&b, overGame: false), "no game with the front: nothing")
        check(!parks(&b, question: true), "a question that wants the pointer: it stays")
        check(!b.isParked, "none of those counts as parked")

        // Over the game: the curtain lowered counts, though it still fades (23.11.2026: the pointer stayed till the next press).
        check(PointerParking.overGame(gameInFront: true, playing: true, curtainUp: false, curtainGoing: false), "a game in front, no curtain: over it")
        check(!PointerParking.overGame(gameInFront: true, playing: true, curtainUp: true, curtainGoing: false),
              "the curtain up (Steam's question on it, the pointer brought there): left alone")
        check(PointerParking.overGame(gameInFront: true, playing: true, curtainUp: true, curtainGoing: true),
              "the curtain just lowered, still fading: the pointer goes at once, not at the next press")
        check(!PointerParking.overGame(gameInFront: false, playing: true, curtainUp: false, curtainGoing: true), "another app in front: nothing")
        check(!PointerParking.overGame(gameInFront: true, playing: false, curtainUp: false, curtainGoing: false), "no game of Nightforge's: nothing")
        let router = (try? String(contentsOfFile: "Sources/Nightforge/InputRouter.swift", encoding: .utf8)) ?? ""
        check(router.contains("parkPointerIfDue(padInUse: Self.padUsedLast, curtainGoing: true)"), "the curtain's going says so")

        var c = PointerParking()
        var looked = false
        _ = c.parksNow(padInUse: false, now: 1, mouseAgo: 60, pointerInUse: false, setting: true, overGame: { looked = true; return true }(), question: false)
        check(!looked, "the front app isn't looked up for nothing: this runs beside a game")

        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let place = PointerParking.place(on: screen)
        check(screen.contains(place), "it stays on the screen it was on")
        check(place.y == 1079, "at the very bottom, where only the arrow's tip shows")
        check(screen.maxX - place.x > 16, "away from the corner, which may be a hot corner")
        let second = CGRect(x: 1920, y: -200, width: 2560, height: 1440)
        check(second.contains(PointerParking.place(on: second)), "on a second screen too")

        print(failures == 0 ? "✓ PointerParking" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
