// Checks what a game's card offers (GameMenu: which entries for which game, one list for mouse and
// pad), the Play Later list (saved and loaded, a game in several stores, a game that leaves the
// library), where the quick menu opens and ☰ held: tests/GameMenuTest/run.sh
import AppKit

@main
struct GameMenuTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ name: String, _ install: InstallState, _ change: (inout Game) -> Void = { _ in }) -> Game {
        var game = Game(appID: id, name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 1)
        game.install = install
        change(&game)
        return game
    }

    static func epic(_ appName: String, _ name: String, _ install: InstallState) -> Game {
        var game = Game(gameID: .epic(appName), name: name, bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 1)
        game.install = install
        return game
    }

    static func main() {
        TestDefaults.useWorkFolder()
        savedAndLoaded()
        severalStores()
        leavesTheLibrary()
        theFilter()
        entries()
        everyEntryShows()
        placement()
        heldMenuButton()
        print(failures == 0 ? "✓ GameMenu" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func savedAndLoaded() {
        let defaults = TestDefaults.suite("later")
        check(GameMarks.load(.later, from: defaults).isEmpty, "nothing on the list at first")
        check(GameMarks.key(.later) == "marks.later", "kept beside hidden and pinned")
        GameMarks.save([.steam(570), .epic("Fortnite"), .gog("1207658924")], .later, to: defaults)
        check(GameMarks.load(.later, from: defaults) == [.steam(570), .epic("Fortnite"), .gog("1207658924")], "the list comes back, from any store")
        check(GameMarks.load(.pinned, from: defaults).isEmpty && GameMarks.load(.hidden, from: defaults).isEmpty, "it's a mark of its own")
        GameMarks.save([.steam(10)], .pinned, to: defaults)
        check(GameMarks.load(.later, from: defaults).count == 3, "pinning leaves the list alone")
    }

    static func severalStores() {
        let onSteam = game(1, "ARC Raiders", .notInstalled)
        let onEpic = epic("Pioneer", "ARC Raiders", .notInstalled)
        let other = game(2, "Valheim", .installed)
        let cards = DuplicateGames.merge([onSteam, onEpic, other], chosen: { _ in nil })
        guard let arc = cards.first(where: { $0.name == "ARC Raiders" }) else { return check(false, "one card for both stores") }
        check(cards.count == 2 && arc.gameIDs.count == 2, "one card for both stores")

        var list = Set<GameID>()
        GameMarks.set(arc.gameIDs, true, in: &list)
        check(list == [.steam(1), .epic("Pioneer")], "marked under each store")
        check(arc.isMarked(in: list) && !other.isMarked(in: list), "the card is on the list, the other game isn't")

        // Marked before the second store was there: one of its stores has it, the card shows it.
        let early: Set<GameID> = [.epic("Pioneer")]
        check(arc.isMarked(in: early), "a mark from one store holds for the card")
        check(DuplicateGames.count(cards, hidden: [], on: early) == 1, "counted once")
        check(DuplicateGames.count(cards, hidden: [], in: .steam, on: early) == 1 && DuplicateGames.count(cards, hidden: [], in: .epic, on: early) == 1,
              "a game from several stores counts in each")
        check(DuplicateGames.count(cards, hidden: [], in: .gog, on: early) == 0, "not in a store it isn't in")

        var taken = early
        GameMarks.set(arc.gameIDs, false, in: &taken)
        check(taken.isEmpty && !arc.isMarked(in: taken), "off the list under every store")
    }

    static func leavesTheLibrary() {
        let defaults = TestDefaults.suite("later-gone")
        let kept = game(1, "Valheim", .installed), gone = game(2, "Anno 2070", .notInstalled)
        var list = Set<GameID>()
        GameMarks.set(kept.gameIDs + gone.gameIDs, true, in: &list)
        GameMarks.save(list, .later, to: defaults)

        // A scan without it: the card's gone, the mark stays.
        let left = [kept]
        let loaded = GameMarks.load(.later, from: defaults)
        check(loaded.contains(.steam(2)), "the mark stays while the game is gone")
        check(DuplicateGames.count(left, hidden: [], on: loaded) == 1, "the chip counts the games that are there")
        check(DuplicateGames.count([], hidden: [], on: loaded) == 0, "nothing there, nothing counted: the chip goes")
        let filter = LibraryFilters(later: true)
        check(left.filter { filter.admits($0, laterGames: loaded) { _ in .great } }.map(\.name) == ["Valheim"], "the list shows what's left")

        // It's back: on the list again.
        check(gone.isMarked(in: loaded) && DuplicateGames.count([kept, gone], hidden: [], on: loaded) == 2, "back in the library, back on the list")
        // Hidden: out of the library, the mark stays for when it returns.
        check(DuplicateGames.count([kept, gone], hidden: [.steam(2)], on: loaded) == 1, "a hidden game doesn't count")
    }

    static func theFilter() {
        let marked = game(1, "Valheim", .installed), plain = game(2, "Palworld", .installed), far = game(3, "Anno 2070", .notInstalled)
        let list: Set<GameID> = [.steam(1), .steam(3)]
        let all = [marked, plain, far]
        func names(_ filter: LibraryFilters) -> [String] { all.filter { filter.admits($0, laterGames: list) { _ in .great } }.map(\.name) }

        check(names(LibraryFilters()) == ["Valheim", "Palworld", "Anno 2070"], "off: every game")
        check(names(LibraryFilters(later: true)) == ["Valheim", "Anno 2070"], "on: the marked ones, installed or not")
        check(names(LibraryFilters(on: [.onMac], later: true)) == ["Valheim"], "together with a filter")
        check(names(LibraryFilters(store: .epic, later: true)).isEmpty, "together with a store")

        let on = LibraryFilters(sort: .name, later: true)
        check(on.narrows && LibraryFilters.clearable(on, search: ""), "it narrows the games, so it can be cleared")
        check(on.cleared == LibraryFilters(sort: .name), "Clear filters takes it off")
        check(LibraryFilters(store: .steam, on: [.mac], later: true).switchesOff == LibraryFilters(store: .steam, later: true),
              "the panel's All filters off leaves it: it isn't in the panel")
        check(!LibraryFilters.Filter.allCases.map(\.label).contains(L10n.t("Play Later")), "one place for it, the chip")
    }

    static func entries() {
        let usual = GameMenu.State(canMarkLater: true, canPin: true, canUninstall: true)
        func list(_ game: Game, _ state: GameMenu.State = usual) -> [GameAction] { GameMenu.actions(for: game, state) }
        let installed = game(1, "Valheim", .installed)
        let missing = game(2, "Anno 2070", .notInstalled)

        check(list(installed) == [.play, .addLater, .pin, .reveal, .hide, .uninstall], "installed: \(list(installed))")
        var onHome = usual
        onHome.onHome = true
        check(list(installed, onHome) == [.play, .addLater, .pin, .removeFromHome, .reveal, .hide, .uninstall],
              "on Home: taken off there right after pinning: \(list(installed, onHome))")
        var everything = usual
        everything.canMove = true
        check(list(installed, everything) == [.play, .addLater, .pin, .move, .reveal, .hide, .uninstall], "the order: \(list(installed, everything))")

        var state = usual
        state.running = true
        check(list(installed, state).first == .switchToGame && !list(installed, state).contains(.play), "running: back to the game")
        state = usual
        state.later = true
        check(list(installed, state).contains(.removeLater) && !list(installed, state).contains(.addLater), "on the list: take it off")
        state.canMarkLater = false
        check(list(installed, state).contains(.removeLater), "on the list and hidden since: it can still come off")
        state = usual
        state.pinned = true
        check(list(installed, state).contains(.unpin) && !list(installed, state).contains(.pin), "pinned: unpin")
        state = GameMenu.State(hidden: true)
        check(list(installed, state) == [.play, .reveal, .unhide], "hidden: bring it back, no marks: \(list(installed, state))")

        let notThere = GameMenu.State(canMarkLater: true)
        check(list(missing, notThere) == [.download, .addLater, .hide], "not installed: \(list(missing, notThere))")
        check(GameAction.download.title(game(3, "A Demo", .notInstalled) { $0.demoOf = 9 }) == L10n.t("Download Demo"), "a demo says so")
        check(GameAction.play.title(game(3, "A Demo", .installed) { $0.demoOf = 9 }) == L10n.t("Play Demo"), "a demo says so when it's there")

        let downloading = game(4, "Palworld", .downloading(0.4))
        check(list(downloading) == [.addLater, .pin, .reveal, .hide, .cancelDownload], "downloading: \(list(downloading))")

        check(list(game(5, "On Sale", .inStore), GameMenu.State()) == [.storePage], "a store hit: its page and nothing of the player's")
        check(list(game(5, "Free", .inStore) { $0.storeFree = true }, GameMenu.State()) == [.addForFree, .storePage], "free in the store")

        let cloud = game(6, "Fortnite", .notInstalled) { $0.antiCheatBlock = AntiCheatBlock(antiCheat: ["EAC"], geforceNow: "123") }
        check(list(cloud, notThere) == [.geforceNow, .addLater, .hide], "GeForce Now instead of a download: \(list(cloud, notThere))")
        let blocked = game(7, "Blocked", .installed) { $0.antiCheatBlock = AntiCheatBlock(antiCheat: ["EAC"], geforceNow: nil) }
        check(!list(blocked).contains(.play) && !list(blocked).contains(.tryAnyway), "anti-cheat stops it: no Play")
        state = usual
        state.running = true
        check(list(blocked, state).first == .switchToGame, "but a running game can be gone back to")

        var waiting = AntiCheatBlock(antiCheat: [], geforceNow: nil)
        waiting.notYet = "not yet"
        let soon = game(8, "Soon", .notInstalled) { $0.antiCheatBlock = waiting }
        check(list(soon, notThere).first == .tryAnyway, "doesn't start yet: try anyway")
        check(GameAction.tryAnyway.title(soon) == L10n.t("Download Anyway"), "… by downloading it")
        check(!list(game(8, "Soon", .notInstalled) { $0.antiCheatBlock = waiting; $0.missingDrive = "T7" }, notThere).contains(.tryAnyway),
              "not with its drive unplugged")
        check(!list(game(9, "VR", .notInstalled) { $0.isVROnly = true }, notThere).contains(.download), "VR only: no download")

        check(list(installed).last?.destructive == true && list(installed).dropLast().allSatisfy { !$0.destructive }, "uninstall last, the only one set apart")
        check(list(downloading).last?.destructive == true, "cancelling a download too")
    }

    static func everyEntryShows() {
        let installed = game(1, "Valheim", .installed)
        for action in GameAction.allCases {
            check(!action.title(installed).isEmpty, "\(action) has a title")
            check(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil, "\(action): \(action.symbol) is a symbol")
        }
        check(Set(GameAction.allCases.map(GameMenu.padID)).count == GameAction.allCases.count, "one id per entry for the pad")
        let row = PadGuideRow.all(PadSymbols(style: .xbox)).first { $0.id == "start" }
        check(row?.meaning == L10n.t("Options for the selected game – held, its quick menu"), "the pad guide tells about the long press")
    }

    static func placement() {
        let window = CGSize(width: 1_200, height: 800), menu = CGSize(width: 280, height: 300)
        let place = { (card: CGRect?) in GameMenuPlacement.origin(card: card, menu: menu, window: window) }
        let card = CGRect(x: 100, y: 200, width: 154, height: 231)
        check(place(card) == CGPoint(x: card.maxX + GameMenuPlacement.gap, y: 200), "right of the card, level with its top")
        let last = CGRect(x: 1_000, y: 200, width: 154, height: 231)
        check(place(last) == CGPoint(x: 1_000 - GameMenuPlacement.gap - 280, y: 200), "no room on the right: left of it")
        let low = CGRect(x: 100, y: 700, width: 154, height: 231)
        check(place(low).y == 800 - GameMenuPlacement.margin - 300, "a card low in the window: pushed up")
        let high = CGRect(x: 100, y: -120, width: 154, height: 231)
        check(place(high).y == GameMenuPlacement.margin, "a card half scrolled out: pushed down")
        let narrow = GameMenuPlacement.origin(card: CGRect(x: 150, y: 100, width: 200, height: 300), menu: menu, window: CGSize(width: 480, height: 800))
        check(narrow.x + menu.width <= 480 && narrow.x >= GameMenuPlacement.margin, "a narrow window: inside it, over the card")
        check(place(nil) == CGPoint(x: 460, y: 250), "no card in sight: the middle, never nowhere")
    }

    static func heldMenuButton() {
        var hold = MenuHold()
        check(hold.update(down: false, now: 1, chord: false) == .none, "☰ up without a press on a card: nothing")

        hold.press(now: 10)
        check(hold.update(down: true, now: 10.2, chord: false) == .none && hold.since == 10, "still undecided")
        check(hold.update(down: false, now: 10.3, chord: false) == .options, "a short press: the options, as ever")
        check(hold.since == nil && hold.update(down: false, now: 10.4, chord: false) == .none, "once")

        hold.press(now: 20)
        check(hold.update(down: true, now: 20.46, chord: false) == .quickMenu, "held: the quick menu")
        check(hold.update(down: false, now: 21, chord: false) == .none, "letting go after it opens nothing else")

        hold.press(now: 30)
        check(hold.update(down: false, now: 30.6, chord: false) == .quickMenu, "a timer late: held is held")

        hold.press(now: 40)
        check(hold.update(down: true, now: 40.5, chord: true) == .none && hold.since == nil, "☰ + ⧉, the overlay's buttons without stick buttons: neither")
        check(hold.update(down: false, now: 41, chord: false) == .none, "nor when it's let go")

        hold.press(now: 50)
        hold.cancel()
        check(hold.update(down: false, now: 50.1, chord: false) == .none, "Nightforge lost the front: forgotten")
    }
}
