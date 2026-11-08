import CoreGraphics
import Foundation

/// The touchpad of a DualSense or DualShock 4 as a mouse, for what only a mouse answers: Steam's
/// windows, a macOS question. One finger moves the pointer, pressing the pad clicks, two fingers
/// scroll, pressing with two fingers is the right click. Only the rules: what the pad's samples mean.
/// PadPointer reads the pad, PointerDriver carries the actions out.
struct TouchpadPointer {
    /// -1…1 on both axes, +y up, as GameController gives them. A lifted finger is exactly the middle
    /// (SDL reads it the same way), so a finger resting there for one sample only pauses the pointer.
    struct Finger: Equatable {
        var x: Float = 0
        var y: Float = 0
        var isDown: Bool { x != 0 || y != 0 }
    }

    struct Sample: Equatable {
        var primary = Finger()
        var secondary = Finger()
        var clicked = false
        var now: TimeInterval = 0
    }

    enum Button: Equatable { case left, right }

    enum Action: Equatable {
        /// Points, y down.
        case move(dx: CGFloat, dy: CGFloat)
        /// Points; a finger moving down gives +dy, the page follows the finger.
        case scroll(dx: CGFloat, dy: CGFloat)
        case press(Button, clicks: Int)
        case release(Button)
    }

    /// The pad reports -1…1 on both axes but is about half as high as wide (1920 × 1080 on the
    /// DualSense): without this the pointer would run twice as fast up and down.
    static let aspect: CGFloat = 0.5625
    /// Below this a resting thumb's noise, in pad units. It adds up, so a slow movement still moves.
    static let noise: CGFloat = 0.002
    /// Pressing the pad rocks the thumb: a click stays where it is until the finger really travels.
    static let clickSlop: CGFloat = 0.05
    /// After letting go the same, briefly.
    static let settle: TimeInterval = 0.08
    static let doubleClickGap: TimeInterval = 0.4
    /// Points the pointer may have moved between two clicks of a double click.
    static let doubleClickDrift: CGFloat = 6
    static let scrollGain: CGFloat = 900

    /// Wider screens get more points per finger's travel (a 4K TV as much as a 1080p one gets by eye).
    var screenScale: CGFloat = 1

    private var fingers = 0
    private var base: Finger?
    private var baseTime: TimeInterval = 0
    private var wasClicked = false
    private var held: Button?
    private var dragging = false
    private var slop: CGFloat = 0
    private var quietUntil: TimeInterval = 0
    private var lastPress: TimeInterval = -.infinity
    private var lastButton: Button?
    private var clicksSoFar = 0
    private var travel: CGFloat = 0

    var isIdle: Bool { fingers == 0 && held == nil }

    /// Points per pad unit at this speed (pad units per second): slowly for small targets, faster for
    /// crossing the screen, so one sweep reaches the far corner.
    static func gain(speed: CGFloat) -> CGFloat {
        let slow: CGFloat = 260, fast: CGFloat = 1_100, atSpeed: CGFloat = 4
        return min(fast, slow + (fast - slow) * speed / atSpeed)
    }

    mutating func feed(_ sample: Sample) -> [Action] {
        var actions: [Action] = []
        let down = [sample.primary, sample.secondary].filter(\.isDown)
        if down.count != fingers {
            // A finger came or went: no jump from one finger's place to the other's.
            fingers = down.count
            base = down.first
            baseTime = sample.now
        } else if let lead = down.first, let from = base {
            actions += movement(from: from, to: lead, now: sample.now)
        }
        if sample.clicked != wasClicked {
            wasClicked = sample.clicked
            if sample.clicked {
                actions.append(press(down.count >= 2 ? .right : .left, now: sample.now))
            } else if let button = held {
                actions.append(.release(button))
                held = nil
                dragging = false
                quietUntil = sample.now + Self.settle
            }
        }
        return actions
    }

    /// The pad stopped being the pointer's (a game took over, the controller left): a held button
    /// mustn't stay down.
    mutating func reset() -> [Action] {
        let release = held.map { [Action.release($0)] } ?? []
        self = TouchpadPointer(screenScale: screenScale)
        return release
    }

    private mutating func movement(from: Finger, to: Finger, now: TimeInterval) -> [Action] {
        let dx = CGFloat(to.x - from.x), dy = CGFloat(from.y - to.y) * Self.aspect
        let distance = hypot(dx, dy)
        guard distance >= Self.noise else { return [] }
        let elapsed = min(max(now - baseTime, 1.0 / 250), 0.1)
        base = to
        baseTime = now
        guard now >= quietUntil else { return [] }
        if held != nil, !dragging {
            slop += distance
            guard slop >= Self.clickSlop else { return [] }
            dragging = true
            return []
        }
        if fingers >= 2, held == nil {
            return [.scroll(dx: dx * Self.scrollGain * screenScale, dy: dy * Self.scrollGain * screenScale)]
        }
        let gain = Self.gain(speed: distance / CGFloat(elapsed)) * screenScale
        travel += distance * gain
        return [.move(dx: dx * gain, dy: dy * gain)]
    }

    private mutating func press(_ button: Button, now: TimeInterval) -> Action {
        let again = button == lastButton && now - lastPress <= Self.doubleClickGap && travel <= Self.doubleClickDrift
        clicksSoFar = again ? min(clicksSoFar + 1, 3) : 1
        lastPress = now
        lastButton = button
        held = button
        dragging = false
        slop = 0
        travel = 0
        return .press(button, clicks: clicksSoFar)
    }
}

/// When the pad is the mouse, and how a click gets to where the pointer is.
enum PadPointerRules {
    /// The pad belongs to the player's pointer unless a game is using it: in Nightforge and its
    /// overlay, under the curtain (a question before the picture comes), in another app. With a game
    /// on screen the touchpad is the game's and a moved pointer would turn its camera; only a question
    /// from macOS (the microphone in Left 4 Dead 2, 8.11.) comes first. Never while the keyboard is
    /// open: the touchpad types there.
    static func works(setting: Bool, keyboardOpen: Bool, inFront: Bool, overlay: Bool, curtain: Bool, gamePlaying: Bool,
                      frontIsGame: Bool, macOSAsks: @autoclosure () -> Bool, windowOverGame: Bool = false) -> Bool {
        guard setting, !keyboardOpen else { return false }
        if inFront || overlay || curtain || windowOverGame { return true }
        return !gamePlaying && !frontIsGame || macOSAsks()
    }

    /// Another app's window standing over the game's picture: Steam's store, opened from a game's
    /// menu (Tomb Raider's downloadable content, 8.11.).
    struct OverGame: Equatable {
        var owner: pid_t
        var number: Int
        var size: CGSize
    }

    /// The topmost ordinary window, if it's another app's and the game's picture lies under it.
    /// `windows`: front to back, as CGWindowList gives them. `ignoring`: Nightforge's own.
    static func windowOverGame(_ windows: [[String: Any]], game: Set<pid_t>, ignoring: Set<pid_t>) -> OverGame? {
        let highest = Int(CGWindowLevelForKey(.modalPanelWindow))
        let ordinary = windows.compactMap { window -> OverGame? in
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, !ignoring.contains(owner),
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  (0...highest).contains((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 200, frame.height >= 100
            else { return nil }
            return OverGame(owner: owner, number: number, size: frame.size)
        }
        guard let top = ordinary.first, !game.contains(top.owner), ordinary.contains(where: { game.contains($0.owner) }) else { return nil }
        return top
    }

    /// Whether that window's app gets the front: while the game has it, its hold on the mouse makes the
    /// window out of reach, for the real mouse too. A big window at once, a small one (which may be
    /// only a notice) when the player puts a finger on the touchpad. Once per window.
    static func handsFront(over: OverGame?, gameFront: Bool, alreadyHanded: Int?, touched: Bool) -> Bool {
        guard let over, gameFront, over.number != alreadyHanded else { return false }
        return touched || (over.size.width >= 600 && over.size.height >= 400)
    }

    /// Pads without a touchpad use the right stick and R2, but only where Nightforge doesn't need
    /// them itself: with Nightforge in front the stick scrolls and R2 goes to the last game.
    static func stickIsPointer(works: Bool, hasTouchpad: Bool, inFront: Bool, overlay: Bool, curtain: Bool) -> Bool {
        works && !hasTouchpad && !overlay && (!inFront || curtain)
    }

    enum ClickRoute: Equatable {
        /// The real thing, for every window: needs the Accessibility permission.
        case post
        /// A click Nightforge hands to its own window: needs no permission.
        case ownWindow
        /// A window of another app and no permission: it can't be reached, so say how.
        case explain
    }

    static func clickRoute(hasAccess: Bool, overOwnWindow: Bool) -> ClickRoute {
        if hasAccess { return .post }
        return overOwnWindow ? .ownWindow : .explain
    }

    /// The note about the permission, not at every click.
    static let explainGap: TimeInterval = 20

    /// `point` where it is if a display shows it, else the nearest point any display shows.
    static func clamped(_ point: CGPoint, to displays: [CGRect]) -> CGPoint {
        guard !displays.isEmpty, !displays.contains(where: { $0.contains(point) }) else { return point }
        let candidates = displays.map { rect in
            CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 1), y: min(max(point.y, rect.minY), rect.maxY - 1))
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
    }

    /// Points per second for the right stick as a mouse: nothing in the middle, growing with the
    /// square, for careful aiming and fast crossing.
    static func stickVelocity(x: Float, y: Float, screenScale: CGFloat = 1) -> CGVector {
        let dead: CGFloat = 0.16, top: CGFloat = 1_400
        let push = hypot(CGFloat(x), CGFloat(y))
        guard push > dead else { return .zero }
        let amount = min(1, (push - dead) / (1 - dead))
        let speed = amount * amount * top * screenScale / push
        return CGVector(dx: CGFloat(x) * speed, dy: -CGFloat(y) * speed)
    }

    /// 1 on a screen 1920 points wide, in steps with the width, within reason.
    static func screenScale(width: CGFloat) -> CGFloat { min(max(width / 1920, 0.75), 2) }
}

/// What PointerDriver needs from the Mac; a stand-in in the tests.
@MainActor
protocol PointerDesk: AnyObject {
    var hasAccess: Bool { get }
    var location: CGPoint { get }
    var displays: [CGRect] { get }
    var now: TimeInterval { get }
    func isOwnWindow(at point: CGPoint) -> Bool
    func postMove(to point: CGPoint, dragging: TouchpadPointer.Button?)
    func warp(to point: CGPoint)
    func postScroll(dx: CGFloat, dy: CGFloat)
    func postButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint)
    func ownButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint)
    func ownScroll(dx: CGFloat, dy: CGFloat, at point: CGPoint)
    func explainAccess()
}

/// Carries a TouchpadPointer's actions out on the Mac: posted events where it may, its own window
/// and a warped pointer where it needn't ask, and otherwise a note on how to allow it.
@MainActor
final class PointerDriver {
    private let desk: PointerDesk
    /// How the press of a held button went: its release has to go the same way.
    private var pressRoute: PadPointerRules.ClickRoute?
    private var heldButton: TouchpadPointer.Button?
    private var clicks = 1
    private var explained: TimeInterval = -.infinity

    init(desk: PointerDesk) { self.desk = desk }

    func apply(_ actions: [TouchpadPointer.Action]) { actions.forEach(apply) }

    private func apply(_ action: TouchpadPointer.Action) {
        switch action {
        case let .move(dx, dy): move(dx, dy)
        case let .scroll(dx, dy): scroll(dx, dy)
        case let .press(button, count): press(button, count)
        case let .release(button): release(button)
        }
    }

    private func move(_ dx: CGFloat, _ dy: CGFloat) {
        let from = desk.location
        let to = PadPointerRules.clamped(CGPoint(x: from.x + dx, y: from.y + dy), to: desk.displays)
        // Moving needs no permission, only a posted event does.
        if desk.hasAccess { desk.postMove(to: to, dragging: heldButton) } else { desk.warp(to: to) }
    }

    private func scroll(_ dx: CGFloat, _ dy: CGFloat) {
        let at = desk.location
        switch PadPointerRules.clickRoute(hasAccess: desk.hasAccess, overOwnWindow: desk.isOwnWindow(at: at)) {
        case .post: desk.postScroll(dx: dx, dy: dy)
        case .ownWindow: desk.ownScroll(dx: dx, dy: dy, at: at)
        case .explain: break  // only a click says why, scrolling comes up too easily
        }
    }

    private func press(_ button: TouchpadPointer.Button, _ count: Int) {
        let at = desk.location
        let route = PadPointerRules.clickRoute(hasAccess: desk.hasAccess, overOwnWindow: desk.isOwnWindow(at: at))
        pressRoute = route
        heldButton = button
        clicks = count
        switch route {
        case .post: desk.postButton(button, down: true, clicks: count, at: at)
        case .ownWindow: desk.ownButton(button, down: true, clicks: count, at: at)
        case .explain:
            guard desk.now - explained >= PadPointerRules.explainGap else { return }
            explained = desk.now
            desk.explainAccess()
        }
    }

    private func release(_ button: TouchpadPointer.Button) {
        let at = desk.location
        switch pressRoute {
        case .post: desk.postButton(button, down: false, clicks: clicks, at: at)
        case .ownWindow: desk.ownButton(button, down: false, clicks: clicks, at: at)
        case .explain, nil: break
        }
        pressRoute = nil
        heldButton = nil
    }
}
