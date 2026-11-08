// Every state a game can be in against what the card's menu may offer (GameMenu.actions), rather than the
// examples tests/GameMenuTest picks: nothing twice, the destructive entry last, Home's and the library's entries
// apart, no entry without its words in either language. And GameMenuPlacement against every card position in
// many window sizes: tests/GameMenuMatrixTest/run.sh
import AppKit

@main
struct GameMenuMatrixTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let installs: [InstallState] = [.installed, .notInstalled, .downloading(0.4), .downloading(nil), .inStore]
    static let blocks: [AntiCheatBlock?] = [nil, AntiCheatBlock(antiCheat: ["EAC"], geforceNow: nil), AntiCheatBlock(antiCheat: ["EAC"], geforceNow: "abc"),
                                            AntiCheatBlock(antiCheat: [], geforceNow: nil, notYet: "Not yet")]

    static func main() {
        TestDefaults.useWorkFolder()
        var combinations = 0
        for install in installs {
            for block in blocks {
                for vr in [false, true] {
                    for free in [false, true] {
                        for state in states() {
                            var game = Game(gameID: .steam(4000), name: "G", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                                            steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 1)
                            game.install = install
                            game.antiCheatBlock = block
                            game.isVROnly = vr
                            game.storeFree = free
                            combinations += 1
                            rules(GameMenu.actions(for: game, state), game: game, state: state)
                        }
                    }
                }
            }
        }
        words()
        placement()
        print(failures == 0 ? "✓ Game menu matrix (\(combinations) states)" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func states() -> [GameMenu.State] {
        var all: [GameMenu.State] = []
        for bits in 0..<(1 << 9) {
            var state = GameMenu.State()
            state.running = bits & 1 != 0
            state.later = bits & 2 != 0
            state.canMarkLater = bits & 4 != 0
            state.pinned = bits & 8 != 0
            state.canPin = bits & 16 != 0
            state.onHome = bits & 32 != 0
            state.hidden = bits & 64 != 0
            state.canMove = bits & 128 != 0
            state.canUninstall = bits & 256 != 0
            all.append(state)
        }
        return all
    }

    static func rules(_ list: [GameAction], game: Game, state: GameMenu.State) {
        let name = "\(game.install) block \(String(describing: game.antiCheatBlock)) \(state)"
        check(Set(list).count == list.count, "nothing twice: \(list) – \(name)")
        if let first = list.firstIndex(where: \.destructive) {
            check(first == list.count - 1 || list[first...].allSatisfy(\.destructive), "what takes something away comes last: \(list) – \(name)")
        }
        check(list.filter(\.destructive).count <= 1, "one destructive entry at most: \(list) – \(name)")
        check(!(list.contains(.play) && list.contains(.switchToGame)), "Play or Switch, not both: \(list)")
        if list.contains(.play) { check(!state.running, "no Play on a game that runs: \(name)") }
        if list.contains(.switchToGame) { check(state.running, "no Switch to a game that doesn't run: \(name)") }
        if game.isVROnly { check(!list.contains(.download), "a VR-only game can't be downloaded here: \(name)") }
        if game.antiCheatBlock != nil && !game.playsInCloud && !state.running {
            check(!list.contains(.play) && !list.contains(.download), "what anti-cheat stops has no Play or Download: \(list) – \(name)")
        }
        if state.onHome {
            check(list.contains(.removeFromHome) && !list.contains(.pin) && !list.contains(.unpin), "on Home only taking it off: \(list) – \(name)")
        } else {
            check(!list.contains(.removeFromHome), "off Home nothing to take off: \(list) – \(name)")
        }
        if list.contains(.pin) { check(state.canPin && !state.pinned, "Pin only where it can be pinned: \(name)") }
        if list.contains(.unpin) { check(state.pinned, "Unpin only what's pinned: \(name)") }
        check(!(list.contains(.addLater) && list.contains(.removeLater)), "Add or Remove from Play Later: \(list)")
        if list.contains(.move) { check(state.canMove, "Move only where it can: \(name)") }
        if game.install == .inStore {
            check(!list.contains(.hide) && !list.contains(.unhide), "a store hit isn't the player's to hide: \(list) – \(name)")
            check(!list.contains(.play) && !list.contains(.download), "a store hit isn't owned: \(list) – \(name)")
        }
        if list.contains(.reveal) { check(game.install != .notInstalled && game.install != .inStore, "a folder only for what's here: \(name)") }
        if state.canUninstall {
            check(list.contains(game.isInstalled ? .uninstall : .cancelDownload), "the way to remove it: \(list) – \(name)")
        } else {
            check(!list.contains(where: \.destructive), "no removing what can't be removed: \(list) – \(name)")
        }
    }

    /// Every entry has words and a symbol, in both languages, and no placeholder left in them.
    static func words() {
        let game = Game(gameID: .epic("Foo"), name: "G", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 1)
        var padNames = Set<String>()
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            for action in GameAction.allCases {
                let title = action.title(game)
                check(!title.isEmpty && !title.contains("%"), "\(action) in \(language): “\(title)”")
                check(!action.symbol.isEmpty, "\(action): no symbol")
                padNames.insert(GameMenu.padID(action))
            }
        }
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        check(padNames.count == GameAction.allCases.count, "a pad name per entry")
        let once = GameAction.allCases.filter(\.destructive)
        check(Set(once) == [.uninstall, .cancelDownload], "the destructive entries: \(once)")
    }

    static func placement() {
        let margin = GameMenuPlacement.margin, gap = GameMenuPlacement.gap
        for window in [CGSize(width: 1000, height: 640), CGSize(width: 1512, height: 982), CGSize(width: 760, height: 480), CGSize(width: 3840, height: 2160)] {
            for menu in [CGSize(width: 260, height: 120), CGSize(width: 260, height: 420), CGSize(width: 320, height: 300)] {
                for x in stride(from: -40.0, to: window.width, by: 37.0) {
                    for y in stride(from: -40.0, to: window.height, by: 53.0) {
                        let card = CGRect(x: x, y: y, width: 180, height: 240)
                        let origin = GameMenuPlacement.origin(card: card, menu: menu, window: window)
                        check(origin.x >= margin - 0.001 && origin.y >= margin - 0.001, "inside the left and top margin: \(origin) card \(card) window \(window)")
                        check(origin.x + menu.width <= window.width - margin + 0.001 && origin.y + menu.height <= window.height - margin + 0.001,
                              "inside the right and bottom margin: \(origin) card \(card) menu \(menu) window \(window)")
                        let side = origin.x >= card.maxX + gap - 0.001 || origin.x + menu.width <= card.minX - gap + 0.001
                        let fits = card.maxX + gap + menu.width <= window.width - margin || card.minX - gap - menu.width >= margin
                        if fits { check(side, "beside its card when there's room: \(origin) card \(card) window \(window)") }
                    }
                }
            }
        }
        let middle = GameMenuPlacement.origin(card: nil, menu: CGSize(width: 200, height: 100), window: CGSize(width: 1000, height: 600))
        check(middle == CGPoint(x: 400, y: 250), "no card in sight: the middle (\(middle))")
    }
}
