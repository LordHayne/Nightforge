import AppKit

/// Quitting always works: ⌘Q, Quit in the menu or the Dock, `osascript … quit`, logging out, the
/// "quit after the game starts" setting, an update's restart. AppKit takes no quit while a window
/// shows a sheet – Settings, a game's options, the D3DMetal question, "Welcome back" – nor during
/// a panel's wait for a file: ⌘Q did nothing and `osascript … quit` got "User canceled" (-128)
/// back (27. and 28.10.), and `NSApp.terminate` with a sheet attached does nothing at all, not
/// even ask its delegate. So the sheets close first, a panel's wait is called off, and then it
/// quits. SwiftUI's close through the model (`closeModelSheets`): it holds a sheet by its binding,
/// and one AppKit ended came back with the next redraw of the library – with Settings open nothing
/// quit Nightforge (3.11.). AppKit's own sheets end through AppKit, a sheet's own sheet before it.
/// Settings keep each change as it's made, and a question left open is asked again the next time
/// it matters; a game's options, the one sheet with Save, close as with Cancel – the player chose
/// to quit, not to keep what they were trying out.
/// The one wait: while Nightforge removes itself (CompleteRemoval), which quits by itself once
/// it's done – a quit halfway would leave half of it behind.
@MainActor
enum Quit {
    enum Answer: Equatable { case quit, wait }

    /// Every sheet of the model's closed through its state (LibraryModel.closeAllSheets).
    static var closeModelSheets: (() -> Void)?

    nonisolated static func answer(removing: Bool) -> Answer { removing ? .wait : .quit }

    /// The sheets to end before quitting, as (window, its sheet): a sheet's own sheet before it,
    /// each once – sheets are windows of their own too.
    nonisolated static func closingOrder<Window: Equatable>(_ windows: [Window], sheet: (Window) -> Window?) -> [(Window, Window)] {
        let sheets = windows.compactMap(sheet)
        var order: [(Window, Window)] = []
        for root in windows where !sheets.contains(root) {
            var chain: [(Window, Window)] = []
            var window = root
            while let next = sheet(window), !chain.contains(where: { $0.1 == next }) {
                chain.append((window, next))
                window = next
            }
            order += chain.reversed()
        }
        return order
    }

    /// Whether the quit waits a moment once the sheets are told to close: a panel's loop ends only
    /// after the event that called it off, and a sheet still attached closes a moment later.
    /// Otherwise it quits at once, as AppKit does itself.
    nonisolated static func waits(panelWaiting: Bool, sheetsLeft: Bool) -> Bool { panelWaiting || sheetsLeft }

    /// How long the quit waits for the sheets, in seconds: SwiftUI's go within a fraction, AppKit's
    /// own are ended after `endSheetsAfter`, and after `giveUpAfter` it quits all the same. By the
    /// clock: a main thread busy redrawing made 50 ms steps take twice as long.
    static let endSheetsAfter: TimeInterval = 1
    static let giveUpAfter: TimeInterval = 2

    /// Why a quit didn't go through, for wine.log.
    nonisolated static func reason(sheetsLeft: [String], panelWaiting: Bool) -> String {
        if !sheetsLeft.isEmpty { return "a sheet is still open (\(sheetsLeft.joined(separator: ", ")))" }
        return panelWaiting ? "a panel still waits for a file" : "AppKit didn't take it"
    }

    /// Asked to quit (`by`, for wine.log): the sheets close and Nightforge quits – at once, or once
    /// they're gone. `beforeQuitting` answers an Apple Event right before: whoever sent it – logging
    /// out, restarting, `osascript` – hears yes only as Nightforge really goes (an answer first and
    /// the quit a second later can count as a cancelled logout, review M7, 3.11.). False while it
    /// removes itself, which says so. A quit AppKit doesn't take says why in wine.log.
    @discardableResult
    static func now(by: String, beforeQuitting: (() -> Void)? = nil, on stage: QuitStage = AppKitQuitStage()) -> Bool {
        guard answer(removing: CompleteRemoval.isRunning) == .quit else {
            stage.note("Quit by \(by) waits: Nightforge is removing itself and quits when that's done")
            return false
        }
        // A panel's wait for a file (D3DMetal's, the bottles folder): called off as with Cancel. Its
        // own loop asked (a key, an Apple Event), so stopModal, not abortModal.
        if stage.panelWaiting { stage.stopPanel() }
        stage.closeSheets()
        func quit() {
            beforeQuitting?()
            guard !stage.terminate() else { return }
            // Still here: AppKit didn't take it.
            stage.note("Quit by \(by) didn't go through: \(reason(sheetsLeft: stage.sheetsLeft, panelWaiting: stage.panelWaiting))")
        }
        func waiting() -> Bool { waits(panelWaiting: stage.panelWaiting, sheetsLeft: !stage.sheetsLeft.isEmpty) }
        guard waiting() else {
            quit()
            return true
        }
        Task {
            let start = Date()
            var ended = false
            while waiting(), Date().timeIntervalSince(start) < giveUpAfter {
                if !ended, Date().timeIntervalSince(start) >= endSheetsAfter {
                    ended = true
                    stage.endSheets()
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            quit()
        }
        return true
    }
}

/// What a quit acts on: AppKit and the model's sheets – or a test's stand-in (CompleteRemovalTest).
@MainActor
protocol QuitStage {
    /// The model's sheets closed through their state, as with Cancel.
    func closeSheets()
    /// The windows that still show a sheet, by the sheet's name.
    var sheetsLeft: [String] { get }
    /// What's left ended through AppKit, a sheet's own sheet before it: sheets of AppKit's own.
    func endSheets()
    var panelWaiting: Bool { get }
    func stopPanel()
    /// Quits; false when it's still here – AppKit didn't take it.
    func terminate() -> Bool
    func note(_ line: String)
}

@MainActor
struct AppKitQuitStage: QuitStage {
    nonisolated init() {}  // nothing of its own: a default argument makes one anywhere

    func closeSheets() { Quit.closeModelSheets?() }

    var sheetsLeft: [String] {
        NSApp.windows.compactMap(\.attachedSheet).map { $0.title.isEmpty ? String(describing: type(of: $0)) : $0.title }
    }

    func endSheets() {
        for (window, sheet) in Quit.closingOrder(NSApp.windows, sheet: { $0.attachedSheet }) {
            window.endSheet(sheet)
        }
    }

    var panelWaiting: Bool { NSApp.modalWindow != nil }
    func stopPanel() { NSApp.stopModal(withCode: .cancel) }

    func terminate() -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func note(_ line: String) { GameLog.note(line) }
}
