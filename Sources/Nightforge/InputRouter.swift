import AppKit
import GameController

/// Keyboard, trackpad and gamepad navigation. GameController only delivers input while the
/// launcher is the active app, so it never reacts while you're in a game.
@MainActor
final class InputRouter {
    private weak var model: LibraryModel?
    private var keyMonitor: Any?
    private var gestureMonitor: Any?
    private var swipe = SwipeRecognizer()
    /// Two fingers sideways over Home's stage, counted in games.
    private var stageScroll = StageScroll()
    /// A scroll's events while it isn't clear yet whether it's a swipe (SwipeRecognizer).
    private var heldScroll: [NSEvent] = []
    private var pinch = PinchSteps()
    private var observers: [NSObjectProtocol] = []
    private var repeatTimer: Timer?
    private var held = Step()
    private var dpadStep = Step()
    private var stickStep = Step()

    func start(model: LibraryModel) {
        self.model = model

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let command = event.modifierFlags.intersection([.command, .control, .option]) == .command
            let handled = MainActor.assumeIsolated {
                if command, chars.lowercased() == "f" {
                    self?.model?.focusSearch()
                    return true
                }
                // ⌘⌫ like "Move to Trash" in Finder – asks before removing anything.
                if command, code == 51, NSApp.keyWindow?.firstResponder is NSText == false {
                    self?.model?.requestUninstall()
                    return true
                }
                return self?.handleKey(code: code, chars: chars, plain: plain) ?? false
            }
            return handled ? nil : event
        }

        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe, .magnify]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleGesture(event) ?? false }
            return handled ? nil : event
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.letGo()
                self?.refreshConnected()
            }
        })
        // In the background (a game in front) GameController delivers nothing, not even the
        // release of a held stick – without this the selection would run on by itself.
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGo() }
        })
        // The pad last touched becomes current: its own button labels go into the hints.
        observers.append(center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        })

        GCController.controllers().forEach { attach($0) }
        refreshConnected()
    }

    // MARK: - Keyboard

    private func handleKey(code: UInt16, chars: String, plain: Bool) -> Bool {
        guard plain, let model, !model.showingOptions, model.macSetup == nil else { return false }
        guard let window = NSApp.keyWindow, window.title == "Nightforge" else { return false }
        if window.firstResponder is NSText { return false }

        switch code {
        case 123: model.move(-1); return true            // ←
        case 124: model.move(1); return true             // →
        case 126: model.moveRow(-1); return model.showingLibrary // ↑
        case 125: model.moveRow(1); return model.showingLibrary  // ↓
        case 115: model.jump(toStart: true); return true // Pos1
        case 119: model.jump(toStart: false); return true // Ende
        case 36, 76:                                     // Return / Enter
            model.activate()
            return true
        case 53:                                         // Esc
            if model.showingDownloads { model.showingDownloads = false; return true }
            if let menu = model.libraryMenu { model.closeLibraryMenu(menu); return true }
            if model.awaitingSteam { model.cancelLaunch(); return true }
            return model.back()
        default: break
        }
        switch chars.lowercased() {
        case "o" where model.heroGame.map { $0.install != .inStore } ?? false:
            model.showingOptions = true
            return true
        case "l":
            model.toggleLibrary()
            return true
        case "i" where !model.route.isDetail && model.heroGame != nil:
            model.openDetail()
            return true
        case "h" where model.route.isDetail:
            if let game = model.selected { model.toggleHidden(game) }
            return true
        case "p" where model.route.isDetail:
            if let game = model.selected { model.togglePinned(game) }
            return true
        case "/":
            model.focusSearch()
            return true
        case "d" where !model.downloads.isEmpty:
            model.showingDownloads.toggle()
            return true
        default:
            return false
        }
    }

    // MARK: - Trackpad

    /// Two fingers sideways go back and forward like in Safari (when System Settings › Trackpad
    /// has "Swipe between pages" on), three fingers too if it's set to them, and pinching in the
    /// library changes the cover size. True for an event it took.
    private func handleGesture(_ event: NSEvent) -> Bool {
        switch event.type {
        case .scrollWheel: return scrollWheel(event)
        case .swipe: return threeFingerSwipe(event)
        case .magnify: magnify(event); return false
        default: return false
        }
    }

    private func scrollWheel(_ event: NSEvent) -> Bool {
        // Over Home's stage two fingers sideways go through its covers, one game per step; the
        // momentum after them stays there too.
        if let model, model.route == .home, !model.showsFirstStart, event.hasPreciseScrollingDeltas,
           SwipeStage.shared.pointer(Self.topLeft(event), isOn: .stage), mayGesture(event) {
            if event.phase == .began { stageScroll.begin() }
            if event.phase == .began || event.phase == .changed, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                let step = stageScroll.add(event.scrollingDeltaX)
                if step != 0 { model.move(step) }
            }
            return true
        }
        let phase: SwipeRecognizer.Phase
        switch event.phase {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended, .cancelled: phase = .ended
        default: return false  // momentum after the fingers left, a resting finger, a mouse wheel
        }
        if phase == .began {
            heldScroll = []
            guard event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled, mayGesture(event) else {
                swipe = SwipeRecognizer()
                return false
            }
        }
        let verdict = swipe.feed(phase, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) { [weak self] direction in
            self?.swipeAllows(direction, event) ?? false
        }
        switch verdict {
        case .wait:
            heldScroll.append(event)
            return true
        case .scroll:
            guard !heldScroll.isEmpty else { return false }
            // Scrolling after all: what was held back goes on, in order, to what scrolls.
            let held = heldScroll + [event]
            heldScroll = []
            held.forEach { $0.window?.sendEvent($0) }
            return true
        case .swipe(let direction):
            heldScroll = []
            trackSwipe(event, direction)
            return true
        }
    }

    /// Whether a swipe that way may go anywhere now (TrackpadSwipe.allows), Home's rail included.
    private func swipeAllows(_ direction: TrackpadSwipe.Direction, _ event: NSEvent) -> Bool {
        guard let model, mayGesture(event) else { return false }
        let stage = SwipeStage.shared
        let onRail = model.route == .home && stage.pointer(Self.topLeft(event), isOn: .rail)
        return TrackpadSwipe.allows(direction, canGoBack: model.route != .home, canGoForward: model.forwardTarget != nil,
                                    rail: onRail ? stage.railEdges : nil)
    }

    /// Gestures belong to the main window's levels: never to a sheet, a dialog or the downloads
    /// panel, nor to the library's search field under the pointer.
    private func mayGesture(_ event: NSEvent) -> Bool {
        guard let model, let main = Self.mainWindow, event.window === main, dialog == nil,
              !model.showingDownloads, !model.showingOptions, model.macSetup == nil else { return false }
        return !(model.route == .library && SwipeStage.shared.pointer(Self.topLeft(event), isOn: .search))
    }

    /// Where the pointer is, in SwiftUI's global coordinates (from the window content's top left).
    private static func topLeft(_ event: NSEvent) -> CGPoint {
        guard let content = event.window?.contentView else { return .zero }
        let point = content.convert(event.locationInWindow, from: nil)
        return content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
    }

    /// The page follows the fingers until they let go; then the system decides (by how far and
    /// how fast) whether it goes on out and the level changes, or snaps back.
    private func trackSwipe(_ event: NSEvent, _ direction: TrackpadSwipe.Direction) {
        guard let model else { return }
        let from = model.route
        let stage = SwipeStage.shared
        let id = stage.begin(from: from, to: direction == .back ? model.backTarget : model.forwardTarget, direction: direction)
        var completes = false
        // The way is already decided and locked; only how far counts (either sign).
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, phase, isComplete, stop in
            MainActor.assumeIsolated {
                // Esc, the pad or a dialog got there first: the swipe lets go.
                guard let self, let model = self.model, model.route == from, self.dialog == nil else {
                    stop.pointee = true
                    stage.end(id)
                    return
                }
                stage.move(id, to: abs(amount))
                if phase == .ended { completes = true } else if phase == .cancelled { completes = false }
                guard isComplete else { return }
                if completes { self.finishSwipe(id, direction, from: from) } else { stage.end(id) }
            }
        }
    }

    private func finishSwipe(_ id: Int, _ direction: TrackpadSwipe.Direction, from: Route) {
        guard let model else { return }
        let stage = SwipeStage.shared
        let moved = direction == .back ? model.back() : model.forward()
        if !moved || model.route == from {
            // Back stayed on this level (it dropped the search): the page slides back in.
            stage.slideBack(id)
        }
        // The page left is out of sight; it lets go of the swipe once its fade-out is over.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            stage.end(id)
        }
    }

    /// Three fingers, when System Settings has swiping between pages on them: straight to the
    /// level, without following the fingers.
    private func threeFingerSwipe(_ event: NSEvent) -> Bool {
        guard let model, event.deltaX != 0, mayGesture(event) else { return false }
        return event.deltaX > 0 ? model.back() : model.forward()
    }

    /// Pinching in the library: the covers a size bigger or smaller per step, and it's remembered.
    private func magnify(_ event: NSEvent) {
        guard let model, model.route == .library, mayGesture(event) else { return }
        if event.phase == .began { pinch.begin() }
        let step = pinch.add(event.magnification)
        if step != 0 { CoverSize.current = CoverSize.current.stepped(step) }
    }

    // MARK: - Gamepad

    func refreshConnected() {
        let pads = GCController.controllers().compactMap(\.extendedGamepad)
        model?.controllerConnected = !pads.isEmpty
        let current = GCController.current?.extendedGamepad ?? pads.first
        let symbols = Prefs.padGlyphs == .automatic ? current.map { PadSymbols($0) } : PadSymbols(style: Prefs.padGlyphs)
        if let symbols, model?.padSymbols != symbols { model?.padSymbols = symbols }
        refreshBattery()
    }

    /// The controller in use and its battery, for the hint bar ("DualSense · 80 %").
    func refreshBattery() {
        let controller = GCController.current ?? GCController.controllers().first { $0.extendedGamepad != nil }
        let status = controller.map { pad -> ControllerStatus in
            let battery = pad.battery.flatMap { $0.batteryState == .unknown ? nil : $0 }
            return ControllerStatus(name: pad.vendorName ?? pad.productCategory, battery: battery?.batteryLevel,
                                    charging: battery?.batteryState == .charging)
        }
        if model?.controllerStatus != status { model?.controllerStatus = status }
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }
        refreshConnected()

        // D-pad and left stick both move in all four directions, repeating while held.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.dpad, x: x, y: y) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.stick, x: x, y: y) }
        }
        // X: the selected game's page (A on Home plays it).
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.openDetail()
            }
        }
        // A presses the highlighted control (PadFocus). Otherwise, in a dialog or sheet, A and B
        // are its Return and Esc: confirm, or cancel and close.
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                if let key = NSApp.keyWindow, let item = PadFocus.shared.focusedItem(in: key) {
                    item.activate()
                } else if let window = self?.padWindow, window !== Self.mainWindow {
                    // Nothing highlighted yet: the first press shows where you are, it doesn't save.
                    PadFocus.shared.move(dx: 0, dy: 1, in: window)
                } else if let dialog = self?.dialog {
                    Self.press(36, "\r", in: dialog)
                } else {
                    self?.primary()
                }
            }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return }
                let main = Self.mainWindow
                if let menu = model.libraryMenu, NSApp.modalWindow == nil, self.dialog == nil {
                    model.closeLibraryMenu(menu)
                } else if let key = NSApp.keyWindow, key === main, PadFocus.shared.focusedItem(in: key) != nil {
                    PadFocus.shared.clear()  // from the buttons back to the games
                } else if model.showingDownloads, NSApp.modalWindow == nil, self.dialog == nil {
                    model.showingDownloads = false
                } else if model.showingOptions, NSApp.modalWindow == nil {
                    model.showingOptions = false
                } else if let dialog = self.dialog {
                    // A window of its own (Settings) closes; a sheet or alert cancels.
                    if dialog.sheetParent == nil, NSApp.modalWindow == nil {
                        dialog.performClose(nil)
                    } else {
                        Self.press(53, "\u{1B}", in: dialog)
                    }
                } else if model.awaitingSteam {
                    model.cancelLaunch()  // stop waiting for a game Steam hasn't started
                } else {
                    model.back()  // like Esc: a level up, a search dropped first
                }
            }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.toggleOptions() }
        }
        // ☰: between Home and the library, like L.
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil, self?.model?.showsFirstStart == false else { return }
                self?.model?.toggleLibrary()
            }
        }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.move(-5)
            }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.move(5)
            }
        }
        // L2/R2: first and last game, like Home and End on the keyboard.
        pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.jump(toStart: true)
            }
        }
        pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.jump(toStart: false)
            }
        }
    }

    /// The window in front of the library when it's an alert or sheet (game options, Steam for
    /// Mac setup, a question): controller input belongs to it, not to the library behind.
    private var dialog: NSWindow? {
        guard let main = Self.mainWindow else { return nil }
        if let sheet = main.attachedSheet { return sheet }
        if let modal = NSApp.modalWindow { return modal }
        if let key = NSApp.keyWindow, key !== main, key.isVisible { return key }
        return nil
    }

    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    /// The key window when its controls are on PadFocus's map (options, settings, setup sheets).
    private var padWindow: NSWindow? {
        guard let key = NSApp.keyWindow, PadFocus.shared.hasItems(in: key) else { return nil }
        return key
    }

    /// One key press (down and up) into `window`, as if typed.
    private static func press(_ keyCode: UInt16, _ characters: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Forgets every held direction and stops the repeat.
    private func letGo() {
        dpadStep = Step()
        stickStep = Step()
        setHeld(Step())
    }

    private func primary() {
        guard let model, !model.showingOptions, model.macSetup == nil else { return }
        model.activate()
    }

    private func toggleOptions() {
        guard let model, let game = model.heroGame, game.install != .inStore else { return }
        // Opens over the library only; closes its own sheet but never one behind a question.
        guard model.showingOptions ? NSApp.modalWindow == nil : dialog == nil else { return }
        model.showingOptions.toggle()
    }

    private enum Source { case dpad, stick }

    /// A step on the grid: left/right within a row, up/down a whole row.
    private struct Step: Equatable {
        var dx = 0, dy = 0
        var isNone: Bool { dx == 0 && dy == 0 }
    }

    /// The stronger axis wins, so a slightly diagonal stick still moves straight.
    private func steer(_ source: Source, x: Float, y: Float) {
        var step = Step()
        if abs(x) >= abs(y) {
            step.dx = x > 0.55 ? 1 : (x < -0.55 ? -1 : 0)
        } else {
            step.dy = y > 0.55 ? -1 : (y < -0.55 ? 1 : 0)  // stick up is +y, a row up is -1
        }
        switch source {
        case .dpad: dpadStep = step
        case .stick: stickStep = step
        }
        // The one just moved leads; letting go of it hands over to the other if that's still held.
        setHeld(step.isNone ? (source == .dpad ? stickStep : dpadStep) : step)
    }

    /// Down on Home opens the library; up from Home's rail or the grid's top row enters the
    /// buttons above, and on a game's page every direction moves between its buttons. Returns
    /// true when the view or the focus changed: holding on then mustn't run on through it.
    @discardableResult
    private func perform(_ step: Step) -> Bool {
        guard let model else { return false }
        if let window = padWindow {
            let focus = PadFocus.shared
            if window !== Self.mainWindow {
                focus.move(dx: step.dx, dy: step.dy, in: window)
                return false
            }
            // Main window: the games have the pad until up on the start page enters the buttons
            // above them; down past the lowest button hands back to the games.
            if focus.focusedItem(in: window) != nil {
                if !focus.move(dx: step.dx, dy: step.dy, in: window), step.dy > 0 {
                    focus.clear()
                    return true
                }
                return false
            }
            // A game's page has no covers: the pad starts on its Play button.
            if model.route.isDetail || (step.dy < 0 && (model.route == .home || model.selectionInTopGridRow)) {
                focus.move(dx: 0, dy: -1, in: window)
                return true
            }
        }
        if model.route.isDetail { return false }
        // The first start has nothing to move through (its controller test reads the pad itself).
        if model.showsFirstStart { return false }
        if step.dx != 0 { model.move(step.dx) }
        if step.dy > 0, model.route == .home {
            model.goLibrary()
            return true
        }
        if step.dy != 0 { model.moveRow(step.dy) }
        return false
    }

    /// First step immediately, then a short pause, then fast repeat while held.
    private func setHeld(_ step: Step) {
        guard step != held else { return }
        held = step
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard !step.isNone, model != nil, dialog == nil || padWindow != nil else { return }

        guard !perform(step) else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFastRepeat() }
        }
    }

    private func startFastRepeat() {
        guard !held.isNone else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.held.isNone else { return }
                if self.perform(self.held) {
                    self.repeatTimer?.invalidate()
                    self.repeatTimer = nil
                }
            }
        }
    }
}

/// The SF Symbols a controller gives its own buttons: ✕ ○ □ △ on a PlayStation pad, A B X Y on
/// Xbox, the Nintendo layout on a Switch pad. The defaults are Xbox's.
struct PadSymbols: Equatable {
    /// What Settings › Controller › Button labels asks for.
    enum Style: String, CaseIterable {
        case automatic, xbox, playstation

        var label: String {
            switch self {
            case .automatic: return L10n.t("Like my controller")
            case .xbox: return "Xbox"
            case .playstation: return "PlayStation"
            }
        }
    }

    var confirm = "a.circle.fill"
    var back = "b.circle.fill"
    var library = "x.circle.fill"
    var options = "y.circle.fill"
    var stick = "l.joystick.fill"

    init() {}

    /// Always one maker's labels, whatever controller is in use.
    init(style: Style) {
        guard style == .playstation else { return }
        confirm = "xmark.circle.fill"
        back = "circle.circle.fill"
        library = "square.circle.fill"
        options = "triangle.circle.fill"
    }

    @MainActor
    init(_ pad: GCExtendedGamepad) {
        confirm = Self.filled(pad.buttonA.sfSymbolsName) ?? confirm
        back = Self.filled(pad.buttonB.sfSymbolsName) ?? back
        library = Self.filled(pad.buttonX.sfSymbolsName) ?? library
        options = Self.filled(pad.buttonY.sfSymbolsName) ?? options
        stick = Self.filled(pad.leftThumbstick.sfSymbolsName) ?? stick
    }

    /// The filled variant where one exists (they read better at hint size), else the symbol itself.
    private static func filled(_ name: String?) -> String? {
        guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
        let fill = name.hasSuffix(".fill") ? name : name + ".fill"
        return NSImage(systemSymbolName: fill, accessibilityDescription: nil) != nil ? fill : name
    }
}

/// The controller in use, as the hint bar shows it.
struct ControllerStatus: Equatable {
    let name: String
    /// 0…1; nil when the controller doesn't say.
    let battery: Float?
    var charging = false

    /// "DualSense · 80 %" – the name shortened to its last word for the long ones Apple reports
    /// ("DualSense Wireless Controller" → "DualSense").
    var label: String {
        let short = Self.shortName(name)
        guard let battery else { return short }
        return "\(short) · \(Int((battery * 100).rounded())) %"
    }

    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " Wireless Controller", with: "").replacingOccurrences(of: " Controller", with: "")
    }

    var symbol: String {
        if charging { return "battery.100.bolt" }
        switch battery ?? 1 {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Low enough to say so in the accent colour.
    var isLow: Bool { (battery ?? 1) < 0.2 && !charging }
}
