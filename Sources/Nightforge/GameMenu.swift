import Foundation

/// What can be done with a game from its card: one list for the right-click menu and the quick menu
/// (GameMenuLayer), so mouse and controller can't drift apart. A new entry is a case here, its line
/// in `GameMenu.actions`, its title and symbol, and what it does in `LibraryModel.perform`.
enum GameAction: String, CaseIterable {
    case geforceNow, switchToGame, play, download, addForFree, storePage, tryAnyway
    case addLater, removeLater, pin, unpin, removeFromHome, move, reveal, hide, unhide
    case uninstall, cancelDownload

    func title(_ game: Game) -> String {
        let demo = game.demoOf != nil
        switch self {
        case .geforceNow: return L10n.t("Play on GeForce Now")
        case .switchToGame: return L10n.t("Switch to Game")
        case .play: return demo ? L10n.t("Play Demo") : L10n.t("Play")
        case .download: return demo ? L10n.t("Download Demo") : L10n.t("Download")
        case .addForFree: return L10n.t("Add for Free")
        case .storePage: return game.provider.viewInStore
        case .tryAnyway: return game.install == .installed ? L10n.t("Play Anyway") : L10n.t("Download Anyway")
        case .addLater: return L10n.t("Add to Play Later")
        case .removeLater: return L10n.t("Remove from Play Later")
        case .pin: return L10n.t("Pin to Home")
        case .unpin: return L10n.t("Unpin from Home")
        case .removeFromHome: return L10n.t("Remove from Home")
        case .move: return L10n.t("Move to …")
        case .reveal: return L10n.t("Show game folder in Finder")
        case .hide: return L10n.t("Hide from library")
        case .unhide: return L10n.t("Show in library again")
        case .uninstall: return L10n.t("Uninstall …")
        case .cancelDownload: return L10n.t("Cancel Download")
        }
    }

    var symbol: String {
        switch self {
        case .geforceNow: return "cloud.fill"
        case .switchToGame, .play: return "play.fill"
        case .download, .addForFree: return "arrow.down"
        case .storePage: return "cart"
        case .tryAnyway: return "exclamationmark.triangle"
        case .addLater: return "bookmark"
        case .removeLater: return "bookmark.slash"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .removeFromHome: return "minus.circle"
        case .move: return "externaldrive"
        case .reveal: return "folder"
        case .hide: return "eye.slash"
        case .unhide: return "eye"
        case .uninstall: return "trash"
        case .cancelDownload: return "xmark"
        }
    }

    /// Takes something away: last in the list, set apart by a line.
    var destructive: Bool { self == .uninstall || self == .cancelDownload }
}

enum GameMenu {
    /// What the list needs to know besides the game: LibraryModel's answers.
    struct State: Equatable {
        var running = false
        var later = false
        var canMarkLater = false
        var pinned = false
        var canPin = false
        /// Opened on Home, on a game of its rail: it can be taken off there (until it's played again),
        /// and pinning it is what the library offers.
        var onHome = false
        var hidden = false
        var canMove = false
        var canUninstall = false
    }

    /// The entries for `game`, each only where it applies: what the big button does first, the
    /// uninstall last.
    static func actions(for game: Game, _ state: State) -> [GameAction] {
        var list: [GameAction] = []
        switch game.install {
        case _ where game.playsInCloud:
            list.append(.geforceNow)
        case .installed where game.antiCheatBlock == nil || state.running:
            list.append(state.running ? .switchToGame : .play)
        case .notInstalled where !game.isVROnly && game.antiCheatBlock == nil && game.missingDrive == nil:
            list.append(.download)
        case .inStore:
            if game.storeFree { list.append(.addForFree) }
            list.append(.storePage)
        default:
            break
        }
        if game.antiCheatBlock?.notYet != nil, !state.running, game.missingDrive == nil,
           game.install == .installed || game.install == .notInstalled {
            list.append(.tryAnyway)
        }
        if state.later { list.append(.removeLater) } else if state.canMarkLater { list.append(.addLater) }
        // On Home the game is already there: only taking it off makes sense (a pinned one comes off too).
        if state.onHome {
            list.append(.removeFromHome)
        } else if state.pinned {
            list.append(.unpin)
        } else if state.canPin {
            list.append(.pin)
        }
        if state.canMove { list.append(.move) }
        if game.hasFolder { list.append(.reveal) }
        if game.install != .inStore { list.append(state.hidden ? .unhide : .hide) }
        if state.canUninstall { list.append(game.isInstalled ? .uninstall : .cancelDownload) }
        return list
    }
}

/// Where the quick menu opens: beside its card, on the side with room (right first), level with the
/// card's top and pushed in to stay in the window. With no card in sight, in the middle.
enum GameMenuPlacement {
    static let gap: CGFloat = 14
    static let margin: CGFloat = 16

    /// The menu's top left corner, in the coordinates of `window`.
    static func origin(card: CGRect?, menu: CGSize, window: CGSize) -> CGPoint {
        guard let card else {
            return CGPoint(x: (window.width - menu.width) / 2, y: (window.height - menu.height) / 2)
        }
        let right = card.maxX + gap, left = card.minX - gap - menu.width
        let x: CGFloat
        if right + menu.width <= window.width - margin {
            x = right
        } else if left >= margin {
            x = left
        } else {
            x = max(margin, window.width - margin - menu.width)  // over the card: a narrow window
        }
        let y = max(margin, min(card.minY, window.height - margin - menu.height))
        return CGPoint(x: x, y: y)
    }
}

extension LibraryModel {
    /// What the list shows for `game` right now.
    func menuState(for game: Game) -> GameMenu.State {
        GameMenu.State(running: isRunning(game), later: isLater(game), canMarkLater: canMarkLater(game),
                       pinned: isPinned(game), canPin: canPin(game), onHome: route == .home && isOnHome(game), hidden: isHidden(game),
                       canMove: canMove(game), canUninstall: canUninstall(game))
    }

    func menuActions(for game: Game) -> [GameAction] { GameMenu.actions(for: game, menuState(for: game)) }

    /// The game whose quick menu is open.
    var quickMenuGame: Game? { quickMenu.flatMap { id in games.first { $0.holds(id) } } }

    /// The quick menu of the game at `index`. By pad the highlight starts on its first entry and
    /// stays inside; by mouse there's none, and the menu closes to what was highlighted before.
    func openQuickMenu(at index: Int, byPad: Bool = false) {
        guard quickMenu == nil, games.indices.contains(index) else { return }
        select(index)
        let game = games[index], focus = PadFocus.shared
        quickMenuReturn = focus.focused
        quickMenu = game.id
        if byPad, let first = menuActions(for: game).first {
            focus.focus(GameMenu.padID(first))
        } else {
            focus.clear()
        }
    }

    /// Esc, B, a click beside it – or a choice in it.
    func closeQuickMenu() {
        guard quickMenu != nil else { return }
        quickMenu = nil
        if let back = quickMenuReturn { PadFocus.shared.focus(back) } else { PadFocus.shared.clear() }
        quickMenuReturn = nil
    }

    /// An entry of the list, from either menu.
    func perform(_ action: GameAction, on game: Game) {
        closeQuickMenu()
        // What works on the selection: the game clicked, without having to select it first.
        func pick() {
            if let index = games.firstIndex(where: { $0.holds(game.id) }) { select(index) }
        }
        switch action {
        case .geforceNow, .switchToGame, .play, .download, .addForFree:
            pick()
            primaryAction()
        case .tryAnyway:
            pick()
            tryAnyway()
        case .reveal:
            pick()
            revealSelected()
        case .storePage: openStorePage(game)
        case .addLater, .removeLater: toggleLater(game)
        case .pin, .unpin: togglePinned(game)
        case .removeFromHome: removeFromHome(game)
        case .move: requestMove(game)
        case .hide, .unhide: toggleHidden(game)
        case .uninstall, .cancelDownload: requestUninstall(game)
        }
    }
}

extension GameMenu {
    /// The pad's name for an entry of the open menu.
    static func padID(_ action: GameAction) -> String { "gamemenu.\(action.rawValue)" }
}
