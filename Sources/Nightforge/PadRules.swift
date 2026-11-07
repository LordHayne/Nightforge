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
        /// Nightforge's curtain is up (GameBackdrop): a game starting, or one that ended on its way back.
        var curtain = false
        /// A game's quick menu.
        var quickMenu = false
        /// The small launcher menu.
        var launcherMenu = false
        /// A store's sign-in on the curtain (SignInStage).
        var signIn = false
    }

    /// What B does: the innermost thing open goes, one per press.
    enum Back: Equatable { case overlay, signIn, quickMenu, launcherMenu, lightbox, list, downloads, highlight, options, sheet, cancelLaunch, level, nothing }

    static func back(_ open: Open) -> Back {
        if open.overlay { return .overlay }
        // The curtain: B does nothing, only "Not starting?" over it (the overlay) takes it. Calling
        // the start off there took the curtain away (1.11.) and stopped only Nightforge's wait –
        // the store had the game already and started it, with nobody watching – and otherwise B
        // changed the page hidden under it.
        if open.curtain { return .nothing }
        let overLevels = !open.sheet && !open.modal
        if overLevels && open.signIn { return .signIn }
        if overLevels && open.quickMenu { return .quickMenu }
        if overLevels && open.launcherMenu { return .launcherMenu }
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

    /// ⧉ (View, on a DualSense Create), let go: the small launcher menu opens or closes. Not as part of
    /// ☰ + ⧉ (the overlay's buttons on a pad without stick buttons), not over a sheet or another panel,
    /// and not where the four cards or the first start are anyway.
    enum ViewButton: Equatable { case open, close, nothing }

    static func viewButton(menuOpen: Bool, levelsFree: Bool, firstStart: Bool, cards: Bool, chorded: Bool) -> ViewButton {
        if chorded { return .nothing }
        if menuOpen { return .close }
        return levelsFree && !firstStart && !cards ? .open : .nothing
    }

    /// Whether Nightforge takes ⧉ from macOS: a DualSense's Create takes screenshots, a gesture of the
    /// system's. Only while Nightforge itself is in front – Nightforge hears the pad in a game too
    /// (for the overlay), and there the button stays the system's and the game's.
    static func takesViewButton(active: Bool, overlay: Bool) -> Bool { active && !overlay }

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

    /// The pad was used last, not the mouse: `padAgo` seconds since a press, `mouseAgo` since the
    /// mouse or trackpad itself last moved, clicked or scrolled. Hidden while Nightforge or its
    /// overlay still has the front, the pointer stays hidden over the game that gets it, until the
    /// mouse moves (1.11.) – only the app in front can hide it. No time limit, and not where the
    /// pointer is: a start longer than a minute, a TV becoming the main screen (which moves every
    /// point) or a game moving the pointer left it showing in Overcooked 2 (1.11.).
    static func padUsedLast(padAgo: TimeInterval?, mouseAgo: TimeInterval) -> Bool {
        guard let padAgo else { return false }
        return padAgo < mouseAgo
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

/// ☰ with a game's card selected: a short press opens the game's options as ever, held it opens the
/// card's quick menu. Which of the two only shows later, so there the options open when ☰ comes up.
/// ☰ acts on the press where there's no card (a game's page). No other button is free for this: A, B,
/// X and Y act the moment they're pressed, in dialogs too, and consoles keep a card's menu on ☰.
struct MenuHold {
    static let seconds: TimeInterval = 0.45

    enum Result: Equatable { case none, options, quickMenu }

    /// When ☰ went down, while that press is undecided.
    private(set) var since: TimeInterval?

    mutating func press(now: TimeInterval) { since = now }

    /// Forgets the press: Nightforge lost the front.
    mutating func cancel() { since = nil }

    /// A look at the press, when ☰ comes up (`down` false) or its time is up. `chord`: ☰ is part of
    /// the overlay's buttons being held (a pad without stick buttons), then it's neither.
    mutating func update(down: Bool, now: TimeInterval, chord: Bool) -> Result {
        guard let since else { return .none }
        let long = now - since >= Self.seconds
        guard long || !down else { return .none }
        self.since = nil
        return chord ? .none : long ? .quickMenu : .options
    }
}
