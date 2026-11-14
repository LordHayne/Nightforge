// The experience audit of 0.3.3 (docs/AUDIT-ERLEBNIS-0.3.3.md): one check per finding, each red before its fix.
// tests/ExperienceAuditTest/run.sh
import AppKit
import Foundation

@main
@MainActor
struct ExperienceAuditTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() async {
        TestDefaults.useWorkFolder()
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        _ = NSApplication.shared  // a message asks NSApp for the main window; no window, no Dock icon without run()
        hintWords()
        saveLine()
        overlayAfterItsGame()
        keysUnderAPanel()
        await messageAfterAClick()
        print(failures == 0 ? "✓ Experience audit" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func game(_ install: InstallState, _ change: (inout Game) -> Void = { _ in }) -> Game {
        var game = Game(gameID: .steam(4000), name: "G", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 1)
        game.install = install
        change(&game)
        return game
    }

    /// With the downloads panel or a chip's list open, the keyboard reached the games behind it (the pad never did).
    static func keysUnderAPanel() {
        check(PadRules.panelHasKeys(downloads: true, list: false, lightbox: false), "the open downloads have the keys")
        check(PadRules.panelHasKeys(downloads: false, list: true, lightbox: false), "a chip's open list has the keys")
        check(!PadRules.panelHasKeys(downloads: false, list: false, lightbox: false), "nothing open: the keys are the games'")
        check(!PadRules.panelHasKeys(downloads: true, list: false, lightbox: true), "a big screenshot over it has the keys first")
        // The same order as the pad's B: what's innermost goes first.
        check(PadRules.back(.init(lightbox: true, downloads: true)) == .lightbox, "B and the keys agree on the screenshot first")
    }

    /// A game that ends by itself under the overlay's side bar (it isn't stopped: it only plays online) left
    /// the bar standing over Nightforge: LibraryModel.watchForGameEnd only cleared the late controller's note.
    static func overlayAfterItsGame() {
        check(OverlayRules.goesWithGame(open: true, openedFor: .menu, leaving: false), "the side bar goes with its game")
        check(!OverlayRules.goesWithGame(open: false, openedFor: .menu, leaving: false), "nothing to close when it isn't up (Quit Game closed it already)")
        check(!OverlayRules.goesWithGame(open: true, openedFor: .menu, leaving: true), "on its way to Nightforge it closes by itself")
        check(!OverlayRules.goesWithGame(open: true, openedFor: .notStarting, leaving: false), "\"Not starting?\" is the curtain's watch's to take away")
        check(!OverlayRules.goesWithGame(open: true, openedFor: .stuck, leaving: false), "the way out of a curtain belongs to the next start, not to a game that ended")
        // Not open in a test: the call stays what it was, and takes the late controller's note.
        GameOverlay.lateController = true
        GameOverlay.gameEnded()
        check(!GameOverlay.lateController && !GameOverlay.isOpen, "the late controller's note ends with its game")
    }

    /// A click on a message's button takes the message away under the pointer, and SwiftUI then never reports
    /// the pointer gone: the next message waited for it to leave, for good.
    static func messageAfterAClick() async {
        let toasts = Toasts.shared
        var undone = false
        toasts.show("Hidden from your library", action: .init(label: "Undo") { undone = true })
        toasts.setHovering(true)  // the pointer on it, as for a click
        toasts.runAction()
        check(undone && toasts.current == nil, "the button does its action and the message goes")
        toasts.show("Back in your library")
        try? await Task.sleep(for: .seconds(3.4))  // a message without a button goes after 2.8 s
        check(toasts.current == nil, "the message after a clicked one still stands after 3.4 s: it waits for a pointer that left with the last one")
        // One replaced under the pointer is the same case.
        toasts.show("First")
        toasts.setHovering(true)
        toasts.show("Second")
        try? await Task.sleep(for: .seconds(3.4))
        check(toasts.current == nil, "a message that replaced one under the pointer still stands after 3.4 s")
        // And the pointer on a message still holds it.
        toasts.show("Held")
        toasts.setHovering(true)
        try? await Task.sleep(for: .seconds(3.4))
        check(toasts.current != nil, "the pointer on a message no longer holds it")
        toasts.dismiss()
    }

    /// "Welcome back" after a Battle.net game said its save was uploading: every store but Steam counted as one
    /// Nightforge uploads for, and nothing ever answers for Battle.net (LibraryModel.storeSaves stays empty).
    static func saveLine() {
        check(CloudSaves.watch(for: .battlenet) == .none, "Battle.net: no line about a save Nightforge doesn't move")
        check(CloudSaves.watch(for: .steam) == .steamRecord, "Steam: its own cloud record")
        check(CloudSaves.watch(for: .epic) == .storeUpload && CloudSaves.watch(for: .gog) == .storeUpload, "Epic and GOG: Nightforge's upload")
    }

    /// The hint bar said "Play" under every game on Home's stage, and under a download on a game's page: the word
    /// is the big button's (LibraryModel.primaryAction), and there's none where the press does nothing.
    static func hintWords() {
        func word(_ game: Game, running: Bool = false, busy: Bool = false) -> String? {
            PrimaryHint.word(for: game, running: running, busy: busy)
        }
        check(word(game(.installed)) == "Play", "an installed game: Play")
        check(word(game(.notInstalled)) == "Download", "a game still to download (a new library's first starts, Play Later): \(word(game(.notInstalled)) ?? "nil")")
        check(word(game(.downloading(0.4))) == nil, "a download under way: the press does nothing, so no word")
        check(word(game(.downloading(0.4)) { $0.downloadNeedsSpace = 1 }) == "Continue Download", "a download stopped for room: the press carries on")
        check(word(game(.installed), running: true) == "Switch to Game", "a running game: the press switches to it")
        check(word(game(.installed), busy: true) == nil, "starting or being uninstalled: no word")
        check(word(game(.notInstalled) { $0.missingDrive = "Games" }) == nil, "on an unplugged drive: the press does nothing")
        check(word(game(.notInstalled) { $0.isVROnly = true }) == nil, "VR only: the press does nothing")
        let blocked = AntiCheatBlock(antiCheat: ["EAC"], geforceNow: nil)
        check(word(game(.installed) { $0.antiCheatBlock = blocked }) == nil, "anti-cheat with no way round: no word")
        check(word(game(.notInstalled) { $0.antiCheatBlock = blocked }) == nil, "the same, not downloaded")
        let streamed = AntiCheatBlock(antiCheat: ["EAC"], geforceNow: "123")
        check(word(game(.notInstalled) { $0.antiCheatBlock = streamed }) == "Play", "GeForce Now plays it without a download")
        check(word(game(.inStore)) == nil, "a store's hit keeps its page's button")
    }
}
