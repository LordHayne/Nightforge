import AppKit

/// Quitting always works: ⌘Q, Quit in the menu or the Dock, `osascript … quit`, logging out, the
/// "quit after the game starts" setting, an update's restart. AppKit takes no quit while a window
/// shows a sheet – Settings, a game's options, the D3DMetal question, "Welcome back" – nor during
/// a panel's wait for a file: ⌘Q did nothing and `osascript … quit` got "User canceled" (-128)
/// back (27. and 28.10.). So the sheets close first, a sheet's own sheet before it, a panel's wait
/// is called off, and then it quits. Settings keep each change as it's made, and a question left
/// open is asked again the next time it matters; a game's options, the one sheet with Save, close
/// as with Cancel – the player chose to quit, not to keep what they were trying out.
/// The one wait: while Nightforge removes itself (CompleteRemoval), which quits by itself once
/// it's done – a quit halfway would leave half of it behind.
@MainActor
enum Quit {
    enum Answer: Equatable { case quit, wait }

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

    /// Asked to quit (`by`, for wine.log): the sheets close and Nightforge quits – false while it
    /// removes itself, which says so.
    @discardableResult
    static func now(by: String) -> Bool {
        guard answer(removing: CompleteRemoval.isRunning) == .quit else {
            GameLog.note("Quit by \(by) waits: Nightforge is removing itself and quits when that's done")
            return false
        }
        // A panel's wait for a file (D3DMetal's, the bottles folder): called off as with Cancel. Its
        // own loop asked (a key, an Apple Event), so stopModal, not abortModal.
        if NSApp.modalWindow != nil { NSApp.stopModal(withCode: .cancel) }
        for (window, sheet) in closingOrder(NSApp.windows, sheet: { $0.attachedSheet }) {
            window.endSheet(sheet)
        }
        Task {
            // Once the panel's wait is over and the sheets are gone, AppKit takes it – a second at most.
            for _ in 0..<20 where NSApp.modalWindow != nil || NSApp.windows.contains(where: { $0.attachedSheet != nil }) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
