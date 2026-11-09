// Checks the touchpad as a mouse (TouchpadPointer, PadPointerRules, PointerDriver) against a stand-in
// for the Mac: tests/TouchpadPointerTest/run.sh
import CoreGraphics
import Foundation

@MainActor
final class StandInDesk: PointerDesk {
    var hasAccess = false
    var location = CGPoint(x: 100, y: 100)
    var displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    var now: TimeInterval = 100
    var own = false
    var log: [String] = []

    func isOwnWindow(at point: CGPoint) -> Bool { own }
    func postMove(to point: CGPoint, dragging: TouchpadPointer.Button?) {
        location = point
        log.append(dragging == nil ? "post move" : "post drag")
    }
    func warp(to point: CGPoint) {
        location = point
        log.append("warp")
    }
    func postScroll(dx: CGFloat, dy: CGFloat) { log.append("post scroll") }
    func postButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) {
        log.append("post \(button) \(down ? "down" : "up") \(clicks)")
    }
    func ownButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) {
        log.append("own \(button) \(down ? "down" : "up") \(clicks)")
    }
    func ownScroll(dx: CGFloat, dy: CGFloat, at point: CGPoint) { log.append("own scroll") }
    func explainAccess() { log.append("explain") }
}

@main
struct TouchpadPointerTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Finger = TouchpadPointer.Finger
    typealias Sample = TouchpadPointer.Sample

    static func finger(_ x: Float, _ y: Float) -> Finger { Finger(x: x, y: y) }

    @MainActor
    /// Two pads without a touchpad and one pointer.
    static func hands() {
        var hands = PointerHands<String>()
        check(hands.moveStick("a", moving: true) && hands.stickHolder == "a", "the first stick out of its middle has the pointer")
        check(!hands.moveStick("b", moving: false) && hands.stickHolder == "a", "a second pad's resting stick doesn't stop it")
        check(!hands.moveStick("b", moving: true) && hands.stickHolder == "a", "nor does its pushed one take over")
        check(hands.moveStick("a", moving: false) && hands.stickHolder == nil, "back in the middle: free")
        check(hands.moveStick("b", moving: true) && hands.stickHolder == "b", "and the other may have it")

        var buttons = PointerHands<String>()
        check(buttons.press(.left, by: "a") && !buttons.press(.left, by: "b"), "one pad holds a button")
        check(buttons.press(.right, by: "b"), "the other button is free")
        check(!buttons.release(.left, by: "b") && buttons.triggers[.left] == "a", "only the one who pressed lets go")
        check(buttons.release(.left, by: "a") && buttons.triggers[.left] == nil, "and then it is up")

        var leaving = PointerHands<String>()
        _ = leaving.moveStick("a", moving: true)
        _ = leaving.press(.left, by: "a")
        _ = leaving.press(.right, by: "b")
        let first = leaving.padsLeft(connected: ["a"])
        check(!first.stick && first.triggers == [.right], "b left: only its button is let go of")
        check(leaving.stickHolder == "a" && leaving.triggers == [.left: "a"], "a holds on")
        let second = leaving.padsLeft(connected: [])
        check(second.stick && second.triggers == [.left] && leaving.stickHolder == nil && leaving.triggers.isEmpty, "a left too: all of it goes")
        check(leaving.padsLeft(connected: []) == (stick: false, triggers: []), "nothing held, nothing to let go of")

        let source = (try? String(contentsOfFile: "Sources/Nightforge/PadPointer.swift", encoding: .utf8)) ?? ""
        check(source.contains("hands.moveStick(id, moving: true)") && source.contains("hands.press(button, by: id)") && source.contains("hands.padsLeft(connected: connected)")
              && !source.contains("heldTriggers"), "PadPointer goes by who holds what")
        check(source.contains("if let owner, !connected.contains(owner) {"), "a finger stays on its touchpad when another controller leaves")
    }

    static func main() {
        hands()
        movement()
        fingers()
        clicks()
        rules()
        overGame()
        driver()
        print(failures == 0 ? "✓ TouchpadPointer" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func movement() {
        var pad = TouchpadPointer()
        check(pad.feed(Sample(primary: finger(0.5, 0.5), now: 1)).isEmpty, "landing moves nothing, wherever the finger lands")
        guard case let .move(dx, dy)? = pad.feed(Sample(primary: finger(0.6, 0.4), now: 1.02)).first else {
            return check(false, "a sliding finger moves the pointer")
        }
        check(dx > 0 && dy > 0, "right and down on the pad is right and down on the screen")
        check(abs(dy / dx - TouchpadPointer.aspect) < 0.001, "the pad is half as high as wide, the pointer moves the same both ways")

        var rest = TouchpadPointer()
        _ = rest.feed(Sample(primary: finger(0.5, 0.5), now: 1))
        check(rest.feed(Sample(primary: finger(0.5005, 0.5), now: 1.01)).isEmpty, "a resting thumb's noise doesn't move it")
        check(!rest.feed(Sample(primary: finger(0.5035, 0.5), now: 1.02)).isEmpty, "a slow movement adds up past the noise")

        check(TouchpadPointer.gain(speed: 0.1) < TouchpadPointer.gain(speed: 2), "slow is fine, fast covers ground")
        check(TouchpadPointer.gain(speed: 100) == 1_100, "and it has a top speed")

        var big = TouchpadPointer(screenScale: 2)
        _ = big.feed(Sample(primary: finger(0.1, 0.1), now: 1))
        var small = TouchpadPointer(screenScale: 1)
        _ = small.feed(Sample(primary: finger(0.1, 0.1), now: 1))
        if case let .move(wide, _)? = big.feed(Sample(primary: finger(0.2, 0.1), now: 1.02)).first,
           case let .move(narrow, _)? = small.feed(Sample(primary: finger(0.2, 0.1), now: 1.02)).first {
            check(abs(wide - narrow * 2) < 0.001, "a screen twice as wide gets twice the points")
        } else {
            check(false, "both move")
        }
    }

    static func fingers() {
        var pad = TouchpadPointer()
        _ = pad.feed(Sample(primary: finger(-0.8, 0), now: 1))
        check(pad.feed(Sample(primary: finger(-0.8, 0), secondary: finger(0.8, 0), now: 1.01)).isEmpty, "a second finger landing is no jump")
        guard case let .scroll(_, dy)? = pad.feed(Sample(primary: finger(-0.8, -0.2), secondary: finger(0.8, -0.2), now: 1.02)).first else {
            return check(false, "two fingers scroll")
        }
        check(dy > 0, "fingers down: the page follows them down")
        check(pad.feed(Sample(secondary: finger(0.8, -0.2), now: 1.03)).isEmpty, "the first finger lifting is no jump to the second")
        check(pad.feed(Sample(now: 1.04)).isEmpty && pad.isIdle, "all fingers up: idle")
        check(pad.feed(Sample(primary: finger(0.9, 0.9), now: 1.05)).isEmpty, "landing somewhere else is no jump either")
    }

    static func clicks() {
        var pad = TouchpadPointer()
        _ = pad.feed(Sample(primary: finger(0.1, 0.1), now: 1))
        check(pad.feed(Sample(primary: finger(0.1, 0.1), clicked: true, now: 1.05)) == [.press(.left, clicks: 1)], "pressing the pad is a left click")
        check(pad.feed(Sample(primary: finger(0.12, 0.1), clicked: true, now: 1.07)).isEmpty, "the thumb rocking in the click doesn't drag")
        check(pad.feed(Sample(primary: finger(0.12, 0.1), now: 1.1)) == [.release(.left)], "and letting go releases it")
        check(pad.feed(Sample(primary: finger(0.14, 0.1), now: 1.12)).isEmpty, "the thumb rocking back moves nothing either")

        var again = TouchpadPointer()
        _ = again.feed(Sample(primary: finger(0.1, 0.1), now: 1))
        _ = again.feed(Sample(primary: finger(0.1, 0.1), clicked: true, now: 1.05))
        _ = again.feed(Sample(primary: finger(0.1, 0.1), now: 1.1))
        check(again.feed(Sample(primary: finger(0.1, 0.1), clicked: true, now: 1.3)) == [.press(.left, clicks: 2)], "twice in a moment is a double click")
        _ = again.feed(Sample(primary: finger(0.1, 0.1), now: 1.35))
        check(again.feed(Sample(primary: finger(0.1, 0.1), clicked: true, now: 2.5)) == [.press(.left, clicks: 1)], "later it's a new click")

        var right = TouchpadPointer()
        _ = right.feed(Sample(primary: finger(-0.5, 0.1), secondary: finger(0.5, 0.1), now: 1))
        check(right.feed(Sample(primary: finger(-0.5, 0.1), secondary: finger(0.5, 0.1), clicked: true, now: 1.05)) == [.press(.right, clicks: 1)],
              "pressing with two fingers is the right click")
        check(right.feed(Sample(primary: finger(-0.5, 0.1), clicked: true, now: 1.08)).isEmpty, "a finger leaving while it's down lets nothing go")
        check(right.feed(Sample(primary: finger(-0.5, 0.1), now: 1.1)) == [.release(.right)], "letting go of the pad releases the right button")
        check(right.feed(Sample(primary: finger(-0.5, 0.1), now: 1.2)).isEmpty, "and only once")

        var drag = TouchpadPointer()
        _ = drag.feed(Sample(primary: finger(0.1, 0.1), now: 1))
        _ = drag.feed(Sample(primary: finger(0.1, 0.1), clicked: true, now: 1.05))
        check(drag.feed(Sample(primary: finger(0.2, 0.1), clicked: true, now: 1.1)).isEmpty, "the first real travel only starts the drag")
        if case .move? = drag.feed(Sample(primary: finger(0.3, 0.1), clicked: true, now: 1.15)).first {} else {
            check(false, "held and moved, it drags")
        }
        check(drag.reset() == [.release(.left)], "the pad taken away mid-drag lets the button go")
        check(drag.isIdle && drag.reset().isEmpty, "and only once")
    }

    static func rules() {
        func works(setting: Bool = true, keyboard: Bool = false, inFront: Bool = false, overlay: Bool = false, curtain: Bool = false,
                   playing: Bool = false, frontIsGame: Bool = false, asks: Bool = false) -> Bool {
            PadPointerRules.works(setting: setting, keyboardOpen: keyboard, inFront: inFront, overlay: overlay, curtain: curtain,
                                  gamePlaying: playing, frontIsGame: frontIsGame, macOSAsks: asks)
        }
        check(works(), "another app in front, no game: Steam's window, a question")
        check(works(inFront: true), "in Nightforge")
        check(works(overlay: true, playing: true), "over a game with the overlay open")
        check(works(curtain: true, playing: true), "under the curtain: a question before the picture")
        check(!works(playing: true), "a game on screen has its touchpad")
        check(!works(frontIsGame: true), "so has a game Nightforge didn't start")
        check(works(playing: true, asks: true), "unless macOS asks something over it")
        check(PadPointerRules.works(setting: true, keyboardOpen: false, inFront: false, overlay: false, curtain: false, gamePlaying: true,
                                    frontIsGame: true, macOSAsks: false, windowOverGame: true), "Steam's window over a game: the pointer works")
        check(!works(setting: false, inFront: true), "the switch in Settings turns it off")
        check(!works(keyboard: true, inFront: true), "with the keyboard open the touchpad types")
        var asked = false
        _ = PadPointerRules.works(setting: true, keyboardOpen: false, inFront: true, overlay: false, curtain: false, gamePlaying: false,
                                  frontIsGame: false, macOSAsks: { asked = true; return true }())
        check(!asked, "the window list is only read when the answer depends on it")

        check(!PadPointerRules.stickReaches(windowOver: true, gameFront: true), "a small notice over the game: the stick and R2 stay the game's")
        check(PadPointerRules.stickReaches(windowOver: true, gameFront: false), "the window's app has the front: they are the mouse")
        check(!PadPointerRules.stickReaches(windowOver: false, gameFront: false), "no window over the game: nothing to reach")
        let router = (try? String(contentsOfFile: "Sources/Nightforge/InputRouter.swift", encoding: .utf8)) ?? ""
        check(router.contains("works: pointerWorks(windowOverGame: PadPointerRules.stickReaches("), "the stick goes by that, the touchpad doesn't")
        func overRunning(asks: Bool) -> Bool {
            PadPointerRules.works(setting: true, keyboardOpen: false, inFront: false, overlay: true, curtain: false, gamePlaying: true,
                                  frontIsGame: true, macOSAsks: asks, gameRunsUnderOverlay: true)
        }
        check(!overRunning(asks: false), "a game running on under the overlay: the pointer stays out of it")
        check(overRunning(asks: true), "unless macOS asks something, which only a pointer answers")
        check(PadPointerRules.works(setting: true, keyboardOpen: false, inFront: false, overlay: true, curtain: false, gamePlaying: true,
                                    frontIsGame: true, macOSAsks: false), "a game stopped under the overlay: the pointer is free")
        check(PadPointerRules.stickIsPointer(works: true, hasTouchpad: false, inFront: false, overlay: false, curtain: false), "Xbox pad, Steam in front: the right stick is the mouse")
        check(!PadPointerRules.stickIsPointer(works: true, hasTouchpad: true, inFront: false, overlay: false, curtain: false), "with a touchpad it stays free")
        check(!PadPointerRules.stickIsPointer(works: true, hasTouchpad: false, inFront: true, overlay: false, curtain: false), "in Nightforge the stick scrolls")
        check(PadPointerRules.stickIsPointer(works: true, hasTouchpad: false, inFront: true, overlay: false, curtain: true), "under the curtain there's nothing to scroll")
        check(!PadPointerRules.stickIsPointer(works: false, hasTouchpad: false, inFront: false, overlay: false, curtain: false), "not in a game")

        check(PadPointerRules.clickRoute(hasAccess: true, overOwnWindow: false) == .post, "allowed: every window")
        check(PadPointerRules.clickRoute(hasAccess: false, overOwnWindow: true) == .ownWindow, "not allowed: Nightforge's own windows still work")
        check(PadPointerRules.clickRoute(hasAccess: false, overOwnWindow: false) == .explain, "another app's window: say how")

        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 500, height: 400)]
        check(PadPointerRules.clamped(CGPoint(x: 1200, y: 300), to: screens) == CGPoint(x: 1200, y: 300), "the second screen is reachable")
        check(PadPointerRules.clamped(CGPoint(x: 1200, y: 700), to: screens) == CGPoint(x: 999, y: 700), "below the smaller screen: the nearest edge")
        check(PadPointerRules.clamped(CGPoint(x: -50, y: -50), to: screens) == CGPoint(x: 0, y: 0), "past the corner: the corner")

        check(PadPointerRules.stickVelocity(x: 0.1, y: 0.1) == .zero, "a resting stick's noise")
        let fast = PadPointerRules.stickVelocity(x: 1, y: 0), slow = PadPointerRules.stickVelocity(x: 0.5, y: 0)
        check(fast.dx > slow.dx * 3, "growing with the square")
        check(PadPointerRules.stickVelocity(x: 0, y: 1).dy < 0, "stick up is pointer up")
        check(PadPointerRules.screenScale(width: 3840) == 2 && PadPointerRules.screenScale(width: 800) == 0.75, "within reason")
    }

    static func window(_ owner: pid_t, number: Int, width: CGFloat = 1000, height: CGFloat = 700, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: owner), kCGWindowNumber as String: NSNumber(value: number),
         kCGWindowLayer as String: NSNumber(value: layer), kCGWindowAlpha as String: NSNumber(value: alpha),
         kCGWindowBounds as String: CGRect(x: 0, y: 0, width: width, height: height).dictionaryRepresentation]
    }

    static func overGame() {
        let game: Set<pid_t> = [10]
        func over(_ windows: [[String: Any]]) -> PadPointerRules.OverGame? {
            PadPointerRules.windowOverGame(windows, game: game, ignoring: [1])
        }
        check(over([window(20, number: 5), window(10, number: 6)])?.owner == 20, "Steam's window above the game's picture")
        check(over([window(10, number: 6), window(20, number: 5)]) == nil, "under the game: nothing to reach")
        check(over([window(20, number: 5)]) == nil, "no picture of the game under it: not over a game")
        check(over([window(1, number: 2), window(10, number: 6), window(20, number: 5)]) == nil, "Nightforge's own panels don't count")
        check(over([window(30, number: 4, width: 100, height: 50), window(10, number: 6)]) == nil, "a sliver isn't a window to answer")
        check(over([window(30, number: 4, layer: 25), window(10, number: 6)]) == nil, "the menu bar's level isn't a window")
        check(over([window(30, number: 4, alpha: 0), window(10, number: 6)]) == nil, "an invisible one neither")
        check(PadPointerRules.windowOverGame([window(20, number: 5), window(10, number: 6)], game: [], ignoring: []) == nil, "the game not known: nothing assumed")

        typealias Over = PadPointerRules.OverGame
        let big = Over(owner: 20, number: 5, size: CGSize(width: 1000, height: 700)), small = Over(owner: 20, number: 7, size: CGSize(width: 300, height: 150))
        check(PadPointerRules.handsFront(over: big, gameFront: true, alreadyHanded: nil, touched: false), "a big window gets the front at once: the mouse works then")
        check(!PadPointerRules.handsFront(over: small, gameFront: true, alreadyHanded: nil, touched: false), "a small one may be only a notice")
        check(PadPointerRules.handsFront(over: small, gameFront: true, alreadyHanded: nil, touched: true), "unless the player reaches for it")
        check(!PadPointerRules.handsFront(over: big, gameFront: true, alreadyHanded: 5, touched: true), "once per window, no fight with the player")
        check(!PadPointerRules.handsFront(over: big, gameFront: false, alreadyHanded: nil, touched: true), "it has the front already")
        check(!PadPointerRules.handsFront(over: nil, gameFront: true, alreadyHanded: nil, touched: true), "nothing over the game")
        check(!PadPointerRules.handsFront(over: big, gameFront: true, alreadyHanded: nil, touched: true, overlay: true), "the overlay is up: nothing moves under it")
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        let watch = model.components(separatedBy: "private func watchStage(").last?.components(separatedBy: "while !Task.isCancelled").first ?? ""
        check(watch.contains("defer {") && watch.contains("overGame = nil") && watch.contains("overGameFront = false") && watch.contains("overGameHanded = nil"),
              "the stage watch's end forgets the window: a touch in Nightforge later mustn't give its app the front")
        check(model.contains("overlay: GameOverlay.isOpen),"), "the model says whether the overlay is up")
    }

    @MainActor
    static func driver() {
        let desk = StandInDesk()
        let driver = PointerDriver(desk: desk)
        driver.apply([.move(dx: 50, dy: 0)])
        check(desk.log == ["warp"] && desk.location.x == 150, "without the permission the pointer still moves")

        desk.log = []
        driver.apply([.press(.left, clicks: 1), .release(.left)])
        check(desk.log == ["explain"], "over another app, no permission: one note and no click")
        driver.apply([.press(.left, clicks: 1), .release(.left)])
        check(desk.log == ["explain"], "not at every click")
        desk.now += PadPointerRules.explainGap
        driver.apply([.press(.left, clicks: 1), .release(.left)])
        check(desk.log == ["explain", "explain"], "again after a while")

        desk.log = []
        desk.own = true
        driver.apply([.press(.left, clicks: 2), .release(.left), .scroll(dx: 0, dy: 5)])
        check(desk.log == ["own left down 2", "own left up 2", "own scroll"], "Nightforge's own window needs no permission")

        desk.log = []
        desk.hasAccess = true
        driver.apply([.move(dx: 1, dy: 1), .press(.right, clicks: 1), .move(dx: 1, dy: 1), .release(.right), .scroll(dx: 1, dy: 0)])
        check(desk.log == ["post move", "post right down 1", "post drag", "post right up 1", "post scroll"], "allowed: real events, held means dragged")

        desk.log = []
        desk.hasAccess = false
        desk.own = true
        driver.apply([.press(.left, clicks: 1)])
        desk.hasAccess = true
        desk.own = false
        driver.apply([.release(.left)])
        check(desk.log == ["own left down 1", "own left up 1"], "a release goes where its press went")

        desk.location = CGPoint(x: 1915, y: 500)
        desk.log = []
        driver.apply([.move(dx: 100, dy: 0)])
        check(desk.location.x == 1919, "the pointer stops at the screen's edge")
    }
}
