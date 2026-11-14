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
/// A quit keeps at it (14.11.): a sheet may come after the closing – "Welcome back" once a game's
/// curtain has gone, what a start that failed has to say, the full-screen offer the moment nothing
/// else is open – so the sheets are closed again while one is up, and Nightforge goes the moment
/// none is left. It used to try once after two seconds, under whatever was still open, and then
/// stayed: twice an `osascript … quit` after a game test left Nightforge running.
@MainActor
enum Quit {
    enum Answer: Equatable { case quit, wait }

    /// Every sheet of the model's closed through its state (LibraryModel.closeAllSheets).
    static var closeModelSheets: (() -> Void)?
    /// The model's sheets that are up, by name (LibraryModel.openSheets), for wine.log.
    static var modelSheets: (() -> [String])?

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

    /// How long the quit waits for the sheets, in seconds: SwiftUI's go within a fraction, and while one
    /// is up the model closes them again every `closeAgainEvery` (one may have come since); AppKit's own
    /// are ended after `endSheetsAfter`; after `saysWhyAfter` wine.log hears what it waits for; and after
    /// `giveUpAfter` it tries all the same, once, and stays if AppKit doesn't take it. By the clock: a
    /// main thread busy redrawing made 50 ms steps take twice as long.
    static let closeAgainEvery: TimeInterval = 0.5
    static let endSheetsAfter: TimeInterval = 1
    static let saysWhyAfter: TimeInterval = 2
    static let giveUpAfter: TimeInterval = 10

    /// Why a quit didn't go through, for wine.log.
    nonisolated static func reason(sheetsLeft: [String], panelWaiting: Bool) -> String {
        if !sheetsLeft.isEmpty { return "a sheet is still open (\(sheetsLeft.joined(separator: ", ")))" }
        return panelWaiting ? "a panel still waits for a file" : "AppKit didn't take it"
    }

    /// Asked to quit (`by`, for wine.log): the sheets close and Nightforge quits – at once, or the moment
    /// they're gone, for up to `patience` seconds. `beforeQuitting` answers an Apple Event right before:
    /// whoever sent it – logging out, restarting, `osascript` – hears yes only as Nightforge really goes
    /// (an answer first and the quit a second later can count as a cancelled logout, review M7, 3.11.).
    /// False while it removes itself, which says so. A quit that waits, and one AppKit doesn't take, say
    /// why in wine.log.
    @discardableResult
    static func now(by: String, beforeQuitting: (() -> Void)? = nil, on stage: QuitStage = AppKitQuitStage(),
                    patience: TimeInterval = giveUpAfter) -> Bool {
        guard answer(removing: CompleteRemoval.isRunning) == .quit else {
            stage.note("Quit by \(by) waits: Nightforge is removing itself and quits when that's done")
            return false
        }
        // A panel's wait for a file (D3DMetal's, the bottles folder): called off as with Cancel. Its
        // own loop asked (a key, an Apple Event), so stopModal, not abortModal.
        if stage.panelWaiting { stage.stopPanel() }
        stage.closeSheets()
        let attempt = Attempt()
        /// One try. The sender hears yes before the first one; false when Nightforge is still here.
        func tryQuit() -> Bool {
            if !attempt.answered {
                attempt.answered = true
                stage.note("Quit by \(by)")
                beforeQuitting?()
            }
            return stage.terminate()
        }
        func waiting() -> Bool { waits(panelWaiting: stage.panelWaiting, sheetsLeft: !stage.sheetsLeft.isEmpty) }
        func why() -> String { reason(sheetsLeft: stage.sheetsLeft, panelWaiting: stage.panelWaiting) }
        if !waiting(), tryQuit() { return true }
        Task {
            let start = Date()
            var endedSheets = false, said = attempt.answered
            var closeAgain = closeAgainEvery, nextTry = closeAgainEvery
            // Still here with nothing in the way: AppKit didn't take it. Said, and tried again below.
            if attempt.answered { stage.note("Quit by \(by) didn't go through: \(why())") }
            while true {
                try? await Task.sleep(for: .milliseconds(50))
                let elapsed = Date().timeIntervalSince(start)
                guard elapsed < patience else { break }
                if waiting() {
                    if elapsed >= closeAgain {
                        closeAgain = elapsed + closeAgainEvery
                        stage.closeSheets()  // one that came since the first closing
                    }
                    if !endedSheets, elapsed >= endSheetsAfter {
                        endedSheets = true
                        stage.endSheets()
                    }
                    if !said, elapsed >= saysWhyAfter {
                        said = true
                        stage.note("Quit by \(by) waits: \(why()). It goes the moment that's gone")
                    }
                } else if elapsed >= nextTry || !attempt.answered {
                    if tryQuit() { return }
                    nextTry = elapsed + closeAgainEvery
                    if !said {
                        said = true
                        stage.note("Quit by \(by) didn't go through: \(why())")
                    }
                }
            }
            // The last try, under whatever is still open: AppKit may take it all the same.
            if tryQuit() { return }
            stage.note("Quit by \(by) didn't go through: \(why())")
        }
        return true
    }
}

/// One quit's tries: whether its sender has been answered.
@MainActor
private final class Attempt {
    var answered = false
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

    /// SwiftUI's sheets have no title and one class: with them, what the model says is up.
    var sheetsLeft: [String] {
        let model = Quit.modelSheets?() ?? []
        return NSApp.windows.compactMap(\.attachedSheet).map { sheet in
            if !sheet.title.isEmpty { return sheet.title }
            let kind = String(describing: type(of: sheet))
            return model.isEmpty ? kind : "\(kind): \(model.joined(separator: ", "))"
        }
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
