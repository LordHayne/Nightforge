// FAILS on staging-032 c475580: a game installed on an external drive that isn't plugged in is `.notInstalled` with
// `missingDrive`, and GameMenu.actions (GameMenu.swift:85) offers it "Download". The entry then does nothing
// (LibraryModel.primaryAction returns for a game on an unplugged drive), and Game.missingDrive says it "must not be
// downloaded again meanwhile". The Battle.net store's waiting games take the same way. Befunde in
// docs/TESTABDECKUNG.md: tests/BugMenuMissingDriveTest/run.sh
import AppKit

@main
struct BugMenuMissingDriveTest {
    static func main() {
        var game = Game(gameID: .steam(4000), name: "G", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: URL(fileURLWithPath: "/Volumes/T7/Nightforge Games/steamapps/common/G", isDirectory: true), sizeOnDisk: 1)
        game.install = .notInstalled
        game.missingDrive = "T7"
        let list = GameMenu.actions(for: game, GameMenu.State(canMarkLater: true))
        if list.contains(.download) {
            print("✗ a game on an unplugged drive is offered Download: \(list)")
            exit(1)
        }
        print("✓ No Download for a game on an unplugged drive")
    }
}
