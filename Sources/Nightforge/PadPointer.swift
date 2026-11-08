import AppKit
import GameController

/// The pad as the Mac's pointer (TouchpadPointer has the rules): the touchpad of a DualSense or
/// DualShock 4, on any other pad the right stick with R2 and L2 as the buttons. Moving the pointer
/// needs no permission and clicks in Nightforge's own windows neither. Clicks in another app's window
/// do: macOS calls it Accessibility (event posting), and only a real mouse or trackpad can turn it
/// on, once – so Nightforge asks in Settings, not on the sofa (PadPointerAccess).
@MainActor
final class PadPointer {
    /// Asked when a finger lands: whether the pad is the pointer's now (PadPointerRules.works).
    var works: () -> Bool = { false }
    /// The same for a pad without a touchpad, whose stick and triggers have other jobs in Nightforge.
    var stickWorks: () -> Bool = { false }

    private var tracker = TouchpadPointer()
    /// The right trigger's button, double clicks included.
    private var triggerButton = TouchpadPointer()
    private let desk = SystemPointerDesk()
    private lazy var driver = PointerDriver(desk: desk)
    /// The controller whose finger is down: a second player's touchpad waits.
    private var owner: ObjectIdentifier?
    private var active = false
    private var stickVelocity = CGVector.zero
    private var stickTimer: Timer?
    private var heldTriggers: Set<PadPart> = []
    /// Whether the stick, out of its middle, is the mouse: settled once per push. In a game it's
    /// asked otherwise at every sample, and the answer reads the window list.
    private var stickDecided: Bool?

    /// The stick or a trigger is working the pointer now: the pad's "in use" mustn't hide it.
    var isMouse: Bool { stickTimer != nil || !heldTriggers.isEmpty }

    func attach(_ pad: GCExtendedGamepad) {
        guard let touchpad = Touchpad(pad) else { return }
        touchpad.primary.valueChangedHandler = { [weak self, weak pad] _, _, _ in
            MainActor.assumeIsolated { self?.changed(pad) }
        }
        touchpad.secondary.valueChangedHandler = { [weak self, weak pad] _, _, _ in
            MainActor.assumeIsolated { self?.changed(pad) }
        }
        touchpad.button.pressedChangedHandler = { [weak self, weak pad] _, _, _ in
            MainActor.assumeIsolated { self?.changed(pad) }
        }
    }

    /// A controller left: a button held with it mustn't stay down.
    func controllerLeft() {
        driver.apply(tracker.reset())
        owner = nil
        active = false
        stickDecided = nil
        setStick(.zero)
        driver.apply(heldTriggers.map { $0 == .r2 ? .release(.left) : .release(.right) })
        heldTriggers = []
        triggerButton = TouchpadPointer()
    }

    private func changed(_ pad: GCExtendedGamepad?) {
        guard let pad, let touchpad = Touchpad(pad) else { return }
        let id = ObjectIdentifier(pad)
        guard owner == nil || owner == id else { return }
        let sample = touchpad.sample(now: desk.now)
        let touches = sample.primary.isDown || sample.secondary.isDown || sample.clicked
        if touches, owner == nil {
            owner = id
            active = works()
            if active {
                tracker.screenScale = desk.screenScale
                desk.fingerLanded()
            }
        }
        if active { driver.apply(tracker.feed(sample)) }
        if !touches {
            owner = nil
            active = false
        }
    }

    // MARK: Pads without a touchpad

    /// The right stick moved. Whether it's the mouse is settled when it leaves the middle.
    func stick(x: Float, y: Float, on pad: GCExtendedGamepad) {
        guard Touchpad(pad) == nil else { return }
        let velocity = PadPointerRules.stickVelocity(x: x, y: y)
        guard velocity != .zero else {
            stickDecided = nil
            return setStick(.zero)
        }
        let decided = stickDecided ?? stickWorks()
        stickDecided = decided
        guard decided else { return }
        let scale = desk.screenScale
        setStick(CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale))
    }

    private func setStick(_ velocity: CGVector) {
        stickVelocity = velocity
        guard velocity != .zero else {
            stickTimer?.invalidate()
            stickTimer = nil
            return
        }
        guard stickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.driver.apply([.move(dx: self.stickVelocity.dx / 60, dy: self.stickVelocity.dy / 60)])
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        stickTimer = timer
    }

    /// R2 (left button) or L2 (right button). True when it was the mouse's, so it does nothing else.
    func trigger(_ part: PadPart, pressed: Bool, on pad: GCExtendedGamepad) -> Bool {
        guard Touchpad(pad) == nil else { return false }
        if pressed {
            guard stickWorks() else { return false }
            heldTriggers.insert(part)
        } else if heldTriggers.remove(part) == nil {
            return false
        }
        if part == .r2 {
            driver.apply(triggerButton.feed(TouchpadPointer.Sample(clicked: pressed, now: desk.now)))
        } else {
            driver.apply([pressed ? .press(.right, clicks: 1) : .release(.right)])
        }
        return true
    }

    /// A window of macOS itself asking something (GameProcesses.macOSAskers). By the program's path
    /// and not by the window list's owner name, which is translated.
    static var macOSAsks: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let owners = Set(windows.compactMap { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value })
        let askers = owners.filter { pid in
            guard let path = NSRunningApplication(processIdentifier: pid)?.executableURL?.path else { return false }
            return GameProcesses.macOSAskers.contains { path.hasPrefix($0) }
        }
        return !GameProcesses.macOSQuestions(windows, askers: askers).isEmpty
    }
}

/// A controller's touchpad, if it has one.
private struct Touchpad {
    let primary: GCControllerDirectionPad
    let secondary: GCControllerDirectionPad
    let button: GCControllerButtonInput

    init?(_ pad: GCExtendedGamepad) {
        if let dualSense = pad as? GCDualSenseGamepad {
            (primary, secondary, button) = (dualSense.touchpadPrimary, dualSense.touchpadSecondary, dualSense.touchpadButton)
        } else if let dualShock = pad as? GCDualShockGamepad {
            (primary, secondary, button) = (dualShock.touchpadPrimary, dualShock.touchpadSecondary, dualShock.touchpadButton)
        } else {
            return nil
        }
    }

    func sample(now: TimeInterval) -> TouchpadPointer.Sample {
        TouchpadPointer.Sample(primary: .init(x: primary.xAxis.value, y: primary.yAxis.value),
                               secondary: .init(x: secondary.xAxis.value, y: secondary.yAxis.value),
                               clicked: button.isPressed, now: now)
    }
}

/// The permission to click in other apps' windows, from Settings › Controller.
@MainActor
enum PadPointerAccess {
    private static let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var granted: Bool { CGPreflightPostEventAccess() }

    /// macOS asks by itself the first time, and that also lists Nightforge there. It never asks
    /// twice, and then the switch itself is the way.
    static func ask() {
        guard !granted else { return }
        _ = CGRequestPostEventAccess()
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !PadPointer.macOSAsks { NSWorkspace.shared.open(pane) }
        }
    }
}

/// The real Mac behind a PointerDriver.
@MainActor
private final class SystemPointerDesk: PointerDesk {
    private let source: CGEventSource?
    private var access = false
    private var checked: TimeInterval = -.infinity
    private var scrollRest = CGSize.zero
    /// Where a press went that Nightforge handed to its own window: the release goes after it.
    private var ownPress: NSWindow?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        // A warped or posted pointer mustn't make the real mouse wait a quarter of a second.
        source?.localEventsSuppressionInterval = 0
    }

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Looked up at most once a second: a pointer moves far more often than a permission changes.
    var hasAccess: Bool {
        if now - checked > 1 {
            access = CGPreflightPostEventAccess()
            checked = now
        }
        return access
    }

    var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    var displays: [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    var screenScale: CGFloat {
        let at = location
        let display = displays.first { $0.contains(at) } ?? CGDisplayBounds(CGMainDisplayID())
        return PadPointerRules.screenScale(width: display.width)
    }

    /// A finger landed: the permission may have just come, and a pointer hidden for the pad comes back.
    func fingerLanded() {
        checked = -.infinity
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    /// AppKit's coordinates (from the main screen's bottom left) of a point in CoreGraphics' (from its top left).
    private func appKit(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    private func ownWindow(at point: CGPoint) -> NSWindow? {
        let number = NSWindow.windowNumber(at: appKit(point), belowWindowWithWindowNumber: 0)
        return NSApp.windows.first { $0.windowNumber == number }
    }

    func isOwnWindow(at point: CGPoint) -> Bool { ownWindow(at: point) != nil }

    func postMove(to point: CGPoint, dragging: TouchpadPointer.Button?) {
        let type: CGEventType = dragging == nil ? .mouseMoved : (dragging == .right ? .rightMouseDragged : .leftMouseDragged)
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: dragging == .right ? .right : .left)?
            .post(tap: .cghidEventTap)
    }

    func warp(to point: CGPoint) { CGWarpMouseCursorPosition(point) }

    /// Whole pixels leave for the event, what's left over goes with the next.
    func postScroll(dx: CGFloat, dy: CGFloat) {
        scrollRest.width += dx
        scrollRest.height += dy
        let wholeX = scrollRest.width.rounded(.towardZero), wholeY = scrollRest.height.rounded(.towardZero)
        scrollRest.width -= wholeX
        scrollRest.height -= wholeY
        guard wholeX != 0 || wholeY != 0 else { return }
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(wholeY), wheel2: Int32(wholeX), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    func postButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) {
        let type: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button == .left ? .left : .right)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        event?.post(tap: .cghidEventTap)
    }

    func ownButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) {
        if down { ownPress = ownWindow(at: point) }
        guard let window = ownPress else { return }
        let type: NSEvent.EventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let event = NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: appKit(point)), modifierFlags: [],
                                       timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: clicks, pressure: down ? 1 : 0)
        if let event { NSApp.postEvent(event, atStart: false) }
        if !down { ownPress = nil }
    }

    func ownScroll(dx: CGFloat, dy: CGFloat, at point: CGPoint) {
        guard let window = ownWindow(at: point) else { return }
        PadFocus.shared.scroll(by: -dy, in: window)  // fingers down bring what's above
    }

    func explainAccess() {
        GameHint.show(title: L10n.t("One click needs your OK first"),
                      detail: L10n.t("Allow it once in Settings › Controller, with a mouse or trackpad."), on: nil)
    }
}
