import AppKit
import GameController

/// Keyboard, trackpad and gamepad navigation. The pad reaches Nightforge in a game too, for the
/// one thing it does there: both sticks held open the overlay (GameOverlay). Everything else waits
/// until Nightforge or the overlay is in front (`reach`).
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
    private var overlayHold = OverlayHold()
    private var holdTimer: Timer?
    /// A button was down at the last look (for waking Nightforge on a fresh press).
    private var anyDown = false
    private var lastWake: TimeInterval = 0
    /// When the pad last changed with Nightforge in front: a sheet opening soon after shows its highlight.
    private var lastPadUse: TimeInterval = 0
    /// The right stick scrolls what shows (a game's page, the grid, Settings), smoothly, as fast as
    /// it's pushed: points per second, and the timer that moves it while it's held.
    private var stickScroll: CGFloat = 0
    private var stickScrollTimer: Timer?
    /// What the right stick scrolled in the library and hasn't made a row yet (PadRules.stickRows).
    private var stickRows: CGFloat = 0

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
        // A sheet or dialog opened while the pad is in use shows its highlight at once, on its safe
        // default answer (PadFocus.Item.preferred), so the first A already answers.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self?.highlightDefault(in: window) }
        })
        // The pad last touched becomes current: its own button labels go into the hints.
        observers.append(center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        })

        GCController.controllers().forEach { attach($0) }
        refreshConnected()
    }

    /// Where the pad's presses go: Nightforge in front, the overlay over a game, or – a game in
    /// front – nowhere, as they belong to the game.
    private enum Reach { case app, overlay, none }

    private var reach: Reach {
        if GameOverlay.isOpen { return .overlay }
        return NSApp.isActive ? .app : .none
    }

    // MARK: - Keyboard

    private func handleKey(code: UInt16, chars: String, plain: Bool) -> Bool {
        guard plain, let model, !model.showingOptions, model.macSetup == nil else { return false }
        guard let window = NSApp.keyWindow, window.title == "Nightforge" else { return false }
        if window.firstResponder is NSText { return false }

        switch code {
        case 123 where model.lightbox != nil: model.lightbox?.step(-1); return true
        case 124 where model.lightbox != nil: model.lightbox?.step(1); return true
        case 123: model.move(-1); return true            // ←
        case 124: model.move(1); return true             // →
        case 126: model.moveRow(-1); return model.showingLibrary // ↑
        case 125: model.moveRow(1); return model.showingLibrary  // ↓
        case 115: model.jump(toStart: true); return true // Pos1
        case 119: model.jump(toStart: false); return true // Ende
        case 36, 76:                                     // Return / Enter
            // On a big screenshot: back to the page.
            if model.lightbox != nil { model.lightbox = nil } else { model.activate() }
            return true
        case 53:                                         // Esc
            if model.lightbox != nil { model.lightbox = nil; return true }
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
        // In a game too, for the hold that opens the overlay. Only once a controller is there:
        // SDL saw crashes when it was set before.
        if !GCController.shouldMonitorBackgroundEvents { GCController.shouldMonitorBackgroundEvents = true }

        // D-pad and left stick both move in all four directions, repeating while held.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.dpad, x: x, y: y) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.stick, x: x, y: y) }
        }
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, _, y in
            MainActor.assumeIsolated { self?.scrollWithStick(y) }
        }
        // X: the selected game's page (A on Home plays it).
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.levelsFree == true else { return }
                self?.model?.openDetail()
            }
        }
        // A presses the highlighted control (PadFocus). Otherwise, in a dialog or sheet, A and B
        // are its Return and Esc: confirm, or cancel and close.
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.reach != Reach.none else { return }
                // The overlay has A to itself, not the big screenshot under it.
                if self?.reach != .overlay, self?.model?.lightbox != nil, self?.dialog == nil {
                    self?.model?.lightbox = nil  // A on a big screenshot: back to the page
                } else if let key = GameOverlay.window ?? NSApp.keyWindow, let item = PadFocus.shared.focusedItem(in: key) {
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
                guard let self, let model = self.model, self.reach != .none else { return }
                let main = Self.mainWindow
                let highlight = NSApp.keyWindow.map { $0 === main && PadFocus.shared.focusedItem(in: $0) != nil } ?? false
                // One press, one level: the innermost thing open goes first.
                let open = PadRules.Open(overlay: self.reach == .overlay, sheet: self.dialog != nil, modal: NSApp.modalWindow != nil,
                                         lightbox: model.lightbox != nil, list: model.libraryMenu != nil,
                                         downloads: model.showingDownloads, options: model.showingOptions, highlight: highlight,
                                         gamePage: model.route.isDetail, awaitingSteam: model.awaitingSteam)
                switch PadRules.back(open) {
                case .overlay: GameOverlay.back()
                case .lightbox: model.lightbox = nil
                case .list: model.libraryMenu.map(model.closeLibraryMenu)
                case .downloads: model.closeDownloads()
                case .highlight: PadFocus.shared.clear()  // from the buttons back to the games
                case .options: model.showingOptions = false
                case .sheet:
                    guard let dialog = self.dialog else { return }
                    // A window of its own (Settings) closes; a sheet or alert cancels.
                    if dialog.sheetParent == nil, NSApp.modalWindow == nil {
                        dialog.performClose(nil)
                    } else {
                        Self.press(53, "\u{1B}", in: dialog)
                    }
                case .cancelLaunch: model.cancelLaunch()  // stop waiting for a game Steam hasn't started
                case .level: model.back()  // like Esc: a level up, a search dropped first
                }
            }
        }
        // Y: search, in the library's header (from Home too).
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.levelsFree == true, self?.model?.showsFirstStart == false else { return }
                self?.model?.focusSearch()
            }
        }
        // ☰: the selected game's options, as on Xbox and PlayStation.
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.openOptions() }
        }
        // L1 always to Home, R1 always to the library (the chips beside the top bar's switch).
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.goSection(.l1) }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.goSection(.r1) }
        }
        // L2/R2: first and last game, like Home and End on the keyboard.
        pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.jump(toStart: true) }
        }
        pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.jump(toStart: false) }
        }
        // Both sticks held for two seconds open the overlay over a game, and close it again.
        pad.valueChangedHandler = { [weak self] gamepad, _ in
            MainActor.assumeIsolated { self?.watchHold(gamepad) }
        }
    }

    private func watchHold(_ pad: GCExtendedGamepad) {
        let now = ProcessInfo.processInfo.systemUptime
        if reach == .app { lastPadUse = now }
        wakeIfIdle(pad, now: now)
        let pressed = OverlayHold.chord(leftStick: pad.leftThumbstickButton?.isPressed, rightStick: pad.rightThumbstickButton?.isPressed,
                                        menu: pad.buttonMenu.isPressed, view: pad.buttonOptions?.isPressed ?? false)
        if overlayHold.update(pressed: pressed, now: now) {
            if GameOverlay.isOpen { GameOverlay.resume() } else { openOverlay() }
        }
        // Nothing changes on the pad while buttons are only held: a look when two seconds are up.
        holdTimer?.invalidate()
        holdTimer = nil
        guard let due = overlayHold.due else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: max(0, due - now) + 0.01, repeats: false) {
            [weak self, weak pad] _ in
            MainActor.assumeIsolated {
                guard let self, let pad else { return }
                self.watchHold(pad)
            }
        }
    }

    private func goSection(_ shoulder: PadPart) {
        guard let model else { return }
        // Settings in front: its tabs.
        if reach == .app, model.showingSettings, NSApp.modalWindow == nil, let sheet = Self.mainWindow?.attachedSheet,
           NSApp.keyWindow === sheet {
            model.stepSettingsTab(shoulder)
            return
        }
        guard let target = Self.section(for: shoulder, route: model.route, inFront: reach == .app,
                                        dialog: dialog != nil || panelOpen, firstStart: model.showsFirstStart)
        else { return }
        target == .home ? model.goHome() : model.goLibrary()
    }

    /// L2/R2: the first and last game; on a game's page its top (Play) and its end.
    private func jump(toStart: Bool) {
        guard levelsFree, let model else { return }
        guard model.route.isDetail, let main = Self.mainWindow else { return model.jump(toStart: toStart) }
        PadFocus.shared.pageEnd(down: !toStart, in: main)
        if toStart { PadFocus.shared.focus("play") } else { PadFocus.shared.clear() }
    }

    /// Where L1 and R1 go: L1 always Home, R1 always the library – from a game's page too. Nowhere
    /// in a sheet, the downloads, the first start or a game, nor to where you are already.
    nonisolated static func section(for shoulder: PadPart, route: Route, inFront: Bool, dialog: Bool, firstStart: Bool) -> Route.Level? {
        guard inFront, !dialog, !firstStart, shoulder == .l1 || shoulder == .r1 else { return nil }
        let target: Route.Level = shoulder == .l1 ? .home : .library
        return route == (target == .home ? .home : .library) ? nil : target
    }

    /// No game, another app in front: a fresh press brings Nightforge, as Big Picture does from the
    /// sofa. Not while a game runs, nor over another app that's a game – the pad is the game's.
    private func wakeIfIdle(_ pad: GCExtendedGamepad, now: TimeInterval) {
        let down = [pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.buttonMenu, pad.leftShoulder, pad.rightShoulder]
            .contains { $0.isPressed }
            || abs(pad.dpad.xAxis.value) > 0.5 || abs(pad.dpad.yAxis.value) > 0.5
        defer { anyDown = down }
        guard down, !anyDown, now - lastWake > 2, let model,
              Self.wakes(inFront: NSApp.isActive, overlayOpen: GameOverlay.isOpen, gameOn: model.gameOnScreen,
                         frontIsGame: Self.frontAppIsGame())
        else { return }
        lastWake = now
        model.comeForward()
        NSApp.windows.first { $0.title == "Nightforge" }?.makeKeyAndOrderFront(nil)
    }

    nonisolated static func wakes(inFront: Bool, overlayOpen: Bool, gameOn: Bool, frontIsGame: Bool) -> Bool {
        !inFront && !overlayOpen && !gameOn && !frontIsGame
    }

    /// The app in front says it's a game (LSApplicationCategoryType), Wine's "Nightforge Game" too.
    private static func frontAppIsGame() -> Bool {
        guard let url = NSWorkspace.shared.frontmostApplication?.bundleURL,
              let category = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String
        else { return false }
        return category.contains("games")
    }

    private func highlightDefault(in window: NSWindow?) {
        guard let window, window !== Self.mainWindow, window !== GameOverlay.window, reach == .app,
              ProcessInfo.processInfo.systemUptime - lastPadUse < 60 else { return }
        DispatchQueue.main.async {  // its controls are on the map once it's laid out
            guard PadFocus.shared.focusedItem(in: window) == nil else { return }
            PadFocus.shared.move(dx: 0, dy: 1, in: window)
        }
    }

    private func openOverlay() {
        guard !GameOverlay.isOpen else { return }
        letGo()
        model?.openOverlay()
    }

    /// The window in front of the library when it's an alert or sheet (game options, Steam for
    /// Mac setup, a question): controller input belongs to it, not to the library behind.
    private var dialog: NSWindow? {
        if let overlay = GameOverlay.window { return overlay }
        guard let main = Self.mainWindow else { return nil }
        if let sheet = main.attachedSheet { return sheet }
        if let modal = NSApp.modalWindow { return modal }
        if let key = NSApp.keyWindow, key !== main, key.isVisible { return key }
        return nil
    }

    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    /// Nightforge in front with nothing over its levels: no sheet, no dialog, no downloads panel.
    /// X, Y, ☰ and L2/R2 act on the games only then, not behind something open.
    private var levelsFree: Bool {
        PadRules.actsOnGames(inFront: reach == .app, sheet: dialog != nil, panel: panelOpen)
    }

    /// Something over the main window's levels that keeps the pad: the downloads panel, a chip's list,
    /// a big screenshot.
    private var panelOpen: Bool {
        guard let model else { return false }
        return model.showingDownloads || model.libraryMenu != nil || model.lightbox != nil
    }

    /// The key window when its controls are on PadFocus's map (options, settings, setup sheets).
    private var padWindow: NSWindow? {
        if let overlay = GameOverlay.window { return overlay }
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
        scrollWithStick(0)
    }

    /// The right stick, up or down: scrolls at a speed that grows with how far it's pushed (a little
    /// for reading, fast for a long page), 60 times a second while it's held.
    private func scrollWithStick(_ y: Float) {
        // In a game or over the overlay the stick isn't Nightforge's.
        stickScroll = reach == .app ? Self.stickSpeed(y) : 0
        guard stickScroll != 0 else {
            stickRows = 0
            stickScrollTimer?.invalidate()
            stickScrollTimer = nil
            return
        }
        guard stickScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.stickScroll != 0, self.reach == .app, let model = self.model, model.lightbox == nil,
                      let window = self.padWindow ?? Self.mainWindow else { return }
                // The library's grid: the selection follows, a row at a time, and the grid with it.
                if model.route == .library, window === Self.mainWindow, !self.panelOpen {
                    let (rows, left) = PadRules.stickRows(self.stickRows + self.stickScroll / 60)
                    self.stickRows = left
                    if rows != 0 {
                        PadFocus.shared.clear()
                        model.moveRow(rows)
                    }
                    return
                }
                PadFocus.shared.scroll(by: self.stickScroll / 60, in: window)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        stickScrollTimer = timer
    }

    /// Points per second for the stick's position (up is +y, which scrolls up): nothing in the
    /// middle, then growing with the square, up to 1 600.
    static func stickSpeed(_ y: Float) -> CGFloat {
        let dead: Float = 0.18
        guard abs(y) > dead else { return 0 }
        let push = CGFloat((abs(y) - dead) / (1 - dead))
        return (y > 0 ? -1 : 1) * push * push * 1_600
    }

    private func primary() {
        guard let model, !model.showingOptions, model.macSetup == nil else { return }
        model.activate()
    }

    /// ☰: opens over the levels only; inside the sheet it does nothing (B cancels, A saves).
    private func openOptions() {
        guard levelsFree, let model, !model.showingOptions, let game = model.heroGame, game.install != .inStore else { return }
        model.showingOptions = true
    }

    private enum Source { case dpad, stick }

    /// A step on the grid: left/right within a row, up/down a whole row.
    private struct Step: Equatable {
        var dx = 0, dy = 0
        var isNone: Bool { dx == 0 && dy == 0 }
    }

    /// The stronger axis wins, so a slightly diagonal stick still moves straight.
    private func steer(_ source: Source, x: Float, y: Float) {
        guard reach != .none else { return }
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

    /// Home: up to the top bar, down to the game's buttons; up from the grid's top row enters the
    /// buttons above it, and on a game's page every direction moves between its buttons. Returns
    /// true when the view or the focus changed: holding on then mustn't run on through it.
    @discardableResult
    private func perform(_ step: Step) -> Bool {
        guard let model else { return false }
        // A screenshot shown big: left and right go through the others.
        if model.lightbox != nil, padWindow == nil || padWindow === Self.mainWindow {
            if step.dx != 0 { model.lightbox?.step(step.dx) }
            return true
        }
        // An open panel (downloads, a chip's list) keeps the pad: its controls only, entering it from
        // wherever the highlight was.
        if model.showingDownloads || model.libraryMenu != nil, let main = Self.mainWindow, padWindow === main {
            PadFocus.shared.move(dx: step.dx, dy: step.dy, in: main, within: .panel)
            return false
        }
        if let window = padWindow {
            let focus = PadFocus.shared
            if window !== Self.mainWindow {
                focus.move(dx: step.dx, dy: step.dy, in: window)
                return false
            }
            // Home in three parts (PadRules): the top bar, the games, the game's buttons – up and down
            // go from part to part as they lie on screen.
            if model.route == .home, !model.showsFirstStart, !model.allGames.isEmpty {
                if focus.focusedItem(in: window) != nil {
                    let zone = focus.focusedZone(in: window)
                    if !focus.move(dx: step.dx, dy: step.dy, in: window, within: zone), PadRules.homeLeaves(zone, dy: step.dy) {
                        focus.clear()
                        return true
                    }
                    return false
                }
                if let zone = PadRules.homeEntry(dy: step.dy) {
                    // The top bar on its "Home"; the game's buttons on Play.
                    if zone == .top { focus.focus("top.home") } else { focus.move(dx: 0, dy: -1, in: window, within: zone) }
                    return true
                }
            }
            // Elsewhere the games have the pad until up from the grid's top row (or a page's first
            // step) enters the buttons; down past the lowest button hands back to the games.
            if focus.focusedItem(in: window) != nil {
                if !focus.move(dx: step.dx, dy: step.dy, in: window), step.dy != 0 {
                    // A game's page goes on down (and back up) past its first and last control, to
                    // what has none: the description, the cards under the screenshots.
                    if model.route.isDetail {
                        focus.page(down: step.dy > 0, in: window)
                        return false  // held, it goes on
                    }
                    if step.dy > 0 {
                        focus.clear()
                        return true
                    }
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
    /// X: the selected game's page.
    var details = "x.circle.fill"
    /// Y: search.
    var search = "y.circle.fill"
    /// ☰: the selected game's options.
    var menu = "line.3.horizontal.circle.fill"
    var stick = "l.joystick.fill"
    /// The right stick: it scrolls.
    var scroll = "r.joystick.fill"
    /// The overlay's buttons (GameOverlay): both sticks pressed, or ☰ and ⧉ on a pad without stick buttons.
    var overlayChord = ["l.joystick.press.down.fill", "r.joystick.press.down.fill"]
    /// L1 and R1 as the controller prints them, for the chips beside Home | Library.
    var shoulders = ["LB", "RB"]

    init() {}

    /// Always one maker's labels, whatever controller is in use.
    init(style: Style) {
        guard style == .playstation else { return }
        shoulders = ["L1", "R1"]
        confirm = "xmark.circle.fill"
        back = "circle.circle.fill"
        details = "square.circle.fill"
        search = "triangle.circle.fill"
    }

    @MainActor
    init(_ pad: GCExtendedGamepad) {
        confirm = Self.filled(pad.buttonA.sfSymbolsName) ?? confirm
        back = Self.filled(pad.buttonB.sfSymbolsName) ?? back
        details = Self.filled(pad.buttonX.sfSymbolsName) ?? details
        search = Self.filled(pad.buttonY.sfSymbolsName) ?? search
        menu = Self.filled(pad.buttonMenu.sfSymbolsName) ?? menu
        stick = Self.filled(pad.leftThumbstick.sfSymbolsName) ?? stick
        scroll = Self.filled(pad.rightThumbstick.sfSymbolsName) ?? scroll
        if PadLayout(pad) == .playstation { shoulders = ["L1", "R1"] }
        if let left = pad.leftThumbstickButton, let right = pad.rightThumbstickButton {
            overlayChord = [Self.filled(left.sfSymbolsName) ?? overlayChord[0], Self.filled(right.sfSymbolsName) ?? overlayChord[1]]
        } else {
            overlayChord = [Self.filled(pad.buttonMenu.sfSymbolsName) ?? "line.3.horizontal.circle.fill",
                            Self.filled(pad.buttonOptions?.sfSymbolsName) ?? "rectangle.on.rectangle.circle.fill"]
        }
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
