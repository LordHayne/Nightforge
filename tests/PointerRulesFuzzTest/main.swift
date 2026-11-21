// The pointer's rules under random use: parking it out of a game's picture, windows standing over a game, which pad works it
// and which clicks can arrive. It never moves the real one: tests/PointerRulesFuzzTest/run.sh
import CoreGraphics
import Foundation

@main
struct PointerRulesFuzzTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func parking() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<3_000 {
            var parking = PointerParking()
            var now: TimeInterval = 1_000
            var mouseAt: TimeInterval = now - .random(in: 0...30, using: &random)
            var parkedAt: TimeInterval?
            for _ in 0..<60 {
                now += .random(in: 0.5...4, using: &random)
                if Int.random(in: 0...4, using: &random) == 0 { mouseAt = now - .random(in: 0...1, using: &random) }
                let mouseAgo = now - mouseAt
                let pad = Bool.random(using: &random), pointer = Int.random(in: 0...5, using: &random) == 0
                let setting = Int.random(in: 0...9, using: &random) != 0
                let overGame = Int.random(in: 0...4, using: &random) != 0, question = Int.random(in: 0...6, using: &random) == 0
                var lookedOver = false, lookedQuestion = false
                let wasParked = parkedAt
                if let at = parkedAt, now - at > mouseAgo { parkedAt = nil }
                let parks = parking.parksNow(padInUse: pad, now: now, mouseAgo: mouseAgo, pointerInUse: pointer, setting: setting,
                                             overGame: { lookedOver = true; return overGame }(), question: { lookedQuestion = true; return question }())
                let wanted = setting && pad && parkedAt == nil && !pointer && mouseAgo >= PointerParking.mouseQuiet && overGame && !question
                check(parks == wanted, "parks \(parks), wanted \(wanted): pad \(pad) parked \(String(describing: wasParked)) mouse \(mouseAgo) over \(overGame) question \(question)")
                if parks { parkedAt = now }
                check(parking.isParked == (parkedAt != nil), "parked in its own eyes and in fact differ")
                if !(setting && pad && parkedAt == now || setting && pad && wasParked == nil && !pointer && mouseAgo >= PointerParking.mouseQuiet) {
                    check(!lookedOver || wasParked != nil, "the front app looked up for nothing")
                }
                if !overGame { check(!lookedQuestion, "the window list read after the answer was already no") }
                if failures > 0 { return }
            }
        }
        var random2 = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            let screen = CGRect(x: .random(in: -4000...4000, using: &random2), y: .random(in: -2000...2000, using: &random2),
                                width: .random(in: 640...6016, using: &random2), height: .random(in: 480...3384, using: &random2))
            let place = PointerParking.place(on: screen)
            check(screen.contains(place), "it leaves the screen it was on: \(place) of \(screen)")
            check(screen.maxY - place.y <= 1 && screen.maxX - place.x >= 16, "not at the bottom edge away from the corner: \(place) of \(screen)")
        }
    }

    static func window(_ owner: pid_t, _ number: Int, layer: Int = 0, alpha: Double? = 1, width: CGFloat = 1000, height: CGFloat = 700) -> [String: Any] {
        var info: [String: Any] = [kCGWindowOwnerPID as String: NSNumber(value: owner), kCGWindowNumber as String: NSNumber(value: number),
                                   kCGWindowLayer as String: NSNumber(value: layer),
                                   kCGWindowBounds as String: CGRect(x: 10, y: 10, width: width, height: height).dictionaryRepresentation]
        if let alpha { info[kCGWindowAlpha as String] = NSNumber(value: alpha) }
        return info
    }

    static func overGame() {
        let game: pid_t = 10, steam: pid_t = 20, mine: pid_t = 30, other: pid_t = 40
        func over(_ windows: [[String: Any]]) -> PadPointerRules.OverGame? {
            PadPointerRules.windowOverGame(windows, game: [game], ignoring: [mine])
        }
        check(over([window(steam, 1), window(game, 2)]) == .init(owner: steam, number: 1, size: CGSize(width: 1000, height: 700)), "Steam's store over the game")
        check(over([window(game, 2), window(steam, 1)]) == nil, "the game on top: nothing stands over it")
        check(over([window(steam, 1)]) == nil, "no game under it: nothing to hand over")
        check(over([]) == nil, "no windows")
        check(over([window(mine, 9), window(steam, 1), window(game, 2)])?.number == 1, "Nightforge's own don't count: its curtain or overlay")
        check(over([window(mine, 9), window(game, 2)]) == nil, "only Nightforge's over the game")
        check(over([window(steam, 1, layer: 25), window(game, 2)]) == nil, "the menu bar's and the Dock's level isn't a window over the game")
        check(over([window(steam, 1, layer: -1), window(game, 2)]) == nil, "below normal windows")
        check(over([window(steam, 1, alpha: 0), window(game, 2)]) == nil, "an invisible window")
        check(over([window(steam, 1, alpha: nil), window(game, 2)])?.number == 1, "no alpha given: a window like any")
        check(over([window(steam, 1, width: 150), window(game, 2)]) == nil, "too narrow to be one")
        check(over([window(steam, 1, height: 80), window(game, 2)]) == nil, "too low to be one")
        check(over([window(steam, 1, width: 150), window(other, 3), window(game, 2)])?.number == 3, "the topmost that counts")
        check(over([[kCGWindowOwnerPID as String: NSNumber(value: steam)], window(game, 2)]) == nil, "a window with nothing else known")

        var random = SystemRandomNumberGenerator()
        for _ in 0..<20_000 {
            let list = (0..<Int.random(in: 0...6, using: &random)).map { number in
                window([game, steam, mine, other].randomElement(using: &random)!, number, layer: [0, 0, 0, 3, 8, 9, 25, -1].randomElement(using: &random)!,
                       alpha: [1, 1, 0, 0.5, nil].randomElement(using: &random)!, width: [100, 300, 1000].randomElement(using: &random)!, height: [50, 150, 800].randomElement(using: &random)!)
            }
            let found = over(list)
            guard let found else { continue }
            check(found.owner != game && found.owner != mine, "\(found.owner) isn't another app's")
            let at = list.firstIndex { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == found.number }!
            check(list[(at + 1)...].contains { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == game }, "no game's window under the one found")
            if failures > 0 { return }
        }
    }

    static func handing() {
        let big = PadPointerRules.OverGame(owner: 2, number: 7, size: CGSize(width: 1000, height: 700))
        let small = PadPointerRules.OverGame(owner: 2, number: 8, size: CGSize(width: 400, height: 300))
        let wide = PadPointerRules.OverGame(owner: 2, number: 9, size: CGSize(width: 1000, height: 300))
        func hands(_ over: PadPointerRules.OverGame?, front: Bool = true, handed: Int? = nil, touched: Bool = false) -> Bool {
            PadPointerRules.handsFront(over: over, gameFront: front, alreadyHanded: handed, touched: touched)
        }
        check(hands(big), "a big window at once")
        check(!hands(small), "a small one may be only a notice")
        check(!hands(wide), "wide but low is small too")
        check(hands(small, touched: true), "a finger on the touchpad asks for it")
        check(!hands(big, handed: 7) && !hands(small, handed: 8, touched: true), "once per window")
        check(hands(big, handed: 6), "another window")
        check(!hands(big, front: false), "the game doesn't have the front: nothing to take from it")
        check(!hands(nil, touched: true), "no window")
    }

    static func working() {
        let flags = [false, true]
        for setting in flags { for keyboard in flags { for inFront in flags { for overlay in flags { for curtain in flags {
            for playing in flags { for frontIsGame in flags { for asks in flags { for over in flags {
                var askedMacOS = false
                let works = PadPointerRules.works(setting: setting, keyboardOpen: keyboard, inFront: inFront, overlay: overlay, curtain: curtain, gamePlaying: playing,
                                                  frontIsGame: frontIsGame, macOSAsks: { askedMacOS = true; return asks }(), windowOverGame: over)
                if !setting || keyboard { check(!works, "switched off, or typing, and the pad is the pointer") }
                if works, !inFront, !overlay, !curtain, !over, playing || frontIsGame { check(asks, "the pointer turning a game's camera") }
                if setting, !keyboard, inFront || overlay || curtain || over { check(works && !askedMacOS, "the window list read for nothing") }
                if setting, !keyboard, !playing, !frontIsGame { check(works && !askedMacOS, "no game: the window list read for nothing") }
                for touchpad in flags {
                    let stick = PadPointerRules.stickIsPointer(works: works, hasTouchpad: touchpad, inFront: inFront, overlay: overlay, curtain: curtain)
                    if stick { check(works && !touchpad && !overlay, "the stick as the pointer where it has another job") }
                }
            } } } }
        } } } } }
        check(PadPointerRules.clickRoute(hasAccess: true, overOwnWindow: true) == .post && PadPointerRules.clickRoute(hasAccess: true, overOwnWindow: false) == .post, "with the permission: the real thing")
        check(PadPointerRules.clickRoute(hasAccess: false, overOwnWindow: true) == .ownWindow, "without it Nightforge's windows still work")
        check(PadPointerRules.clickRoute(hasAccess: false, overOwnWindow: false) == .explain, "and another app's says how")

        var random = SystemRandomNumberGenerator()
        for _ in 0..<20_000 {
            let x = Float.random(in: -1...1, using: &random), y = Float.random(in: -1...1, using: &random)
            let scale = PadPointerRules.screenScale(width: .random(in: 0...20_000, using: &random))
            check((0.75...2).contains(scale), "a scale out of its range: \(scale)")
            let velocity = PadPointerRules.stickVelocity(x: x, y: y, screenScale: scale)
            check(velocity.dx.isFinite && velocity.dy.isFinite, "a speed that isn't a number at \(x), \(y)")
            check(hypot(velocity.dx, velocity.dy) <= 1_400 * scale + 1, "faster than the top speed at \(x), \(y)")
            if hypot(x, y) <= 0.16 { check(velocity == .zero, "the middle of the stick moves it") }
            if velocity != .zero {
                check(x == 0 || (velocity.dx > 0) == (x > 0), "the wrong way across")
                check(y == 0 || (velocity.dy < 0) == (y > 0), "the wrong way up and down")
            }
            if failures > 0 { return }
        }
    }

    static func main() {
        parking()
        overGame()
        handing()
        working()
        print(failures == 0 ? "✓ The pointer's rules" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
