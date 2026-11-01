import Foundation

/// The pad's rules where they decide something (docs/ENTWURF-CONTROLLER.md, section 3), apart from
/// the windows and views they act on, so they can be tested. InputRouter asks them.
enum PadRules {
    /// What's open in front of the levels when B is pressed.
    struct Open: Equatable {
        var overlay = false
        /// A sheet, alert or window of Nightforge's own in front of the main window.
        var sheet = false
        /// An app-modal window (a question over a sheet).
        var modal = false
        var lightbox = false
        /// The list a library chip opened.
        var list = false
        var downloads = false
        var options = false
        /// A control highlighted in the main window.
        var highlight = false
        var gamePage = false
        var awaitingSteam = false
    }

    /// What B does: the innermost thing open goes, one per press.
    enum Back: Equatable { case overlay, lightbox, list, downloads, highlight, options, sheet, cancelLaunch, level }

    static func back(_ open: Open) -> Back {
        if open.overlay { return .overlay }
        let overLevels = !open.sheet && !open.modal
        if overLevels && open.lightbox { return .lightbox }
        if overLevels && open.list { return .list }
        if overLevels && open.downloads { return .downloads }
        // From a row of buttons back to the games. A game's page has no games: B goes back at once.
        if overLevels && open.highlight && !open.gamePage { return .highlight }
        if open.options && !open.modal { return .options }
        if open.sheet { return .sheet }
        if open.awaitingSteam { return .cancelLaunch }
        return .level
    }

    /// X, Y, ☰ and L2/R2 act on the games only with nothing in front of the levels: no sheet, and no
    /// panel (downloads, a chip's list, a big screenshot).
    static func actsOnGames(inFront: Bool, sheet: Bool, panel: Bool) -> Bool {
        inFront && !sheet && !panel
    }

    /// Home in three parts, top to bottom: the top bar, the games (no highlight), the game's buttons.
    /// From the games ↓ enters the buttons and ↑ the top bar; nil: the step moves the games.
    static func homeEntry(dy: Int) -> PadZone? {
        dy > 0 ? .game : dy < 0 ? .top : nil
    }

    /// A step that finds nothing more in its Home part: back to the games when it points at them.
    static func homeLeaves(_ zone: PadZone?, dy: Int) -> Bool {
        (zone == .game && dy < 0) || (zone == .top && dy > 0)
    }

    /// The pointer hides while the pad is used with Nightforge (or its overlay) in front, until the
    /// mouse moves; with a game in front it's the game's.
    static func hidesPointer(inFront: Bool, overlay: Bool, inUse: Bool) -> Bool {
        inUse && (inFront || overlay)
    }

    /// L1/R1 in Settings: the tab before or after `current`, nil at either end.
    static func settingsTab(_ shoulder: PadPart, current: Int, count: Int) -> Int? {
        let next = current + (shoulder == .l1 ? -1 : shoulder == .r1 ? 1 : 0)
        guard next != current, (0..<count).contains(next) else { return nil }
        return next
    }

    /// The right stick in the library: the selection follows a row at a time, so what A opens stays in
    /// sight. `points` scrolled so far (down is +) give whole rows and what's left for the next ones.
    static func stickRows(_ points: CGFloat, row: CGFloat = 220) -> (rows: Int, left: CGFloat) {
        let rows = Int(points / row)  // toward zero
        return (rows, points - CGFloat(rows) * row)
    }
}
