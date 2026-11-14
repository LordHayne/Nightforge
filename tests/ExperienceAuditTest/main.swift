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
        hintWords()
        saveLine()
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
