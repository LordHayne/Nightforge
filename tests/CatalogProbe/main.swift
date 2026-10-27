// Prints the owned games Nightforge reads from a Steam install: tests/CatalogProbe/run.sh <Steam folder>
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let start = Date()
let games = SteamCatalog.ownedGames(steamRoot: root)
print("\(games.count) owned games in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
for game in games where CommandLine.arguments.count < 3 ? games.firstIndex(of: game)! < 8 : String(game.appID) == CommandLine.arguments[2] {
    let mac = !game.macNative ? "" : String(format: "  Mac %@%@ %.0f MB", game.mac64 ? "64-bit" : "32-bit/unknown",
                                                   game.macAppleSilicon ? " Apple silicon" : "", Double(game.macSize) / 1e6)
    print(String(format: "%8d  %8.0f MB  %@  [%@]%@", game.appID, Double(game.size) / 1e6, game.name, game.installDir, mac))
}
let unowned = SteamCatalog.unownedGames(steamRoot: root)
print("\(unowned.count) known but not owned (licence list \(SteamCatalog.owns(7, steamRoot: root) == nil ? "unreadable" : "read"))")
for app in unowned {
    let what = app.demoOf.map { "demo of \($0)\(app.owned ? "" : ", needs its free licence")" } ?? "store"
    print(String(format: "%8d  %8.0f MB  %@  (%@)", app.appID, Double(app.size) / 1e6, app.name, what))
}
if CommandLine.arguments.count > 2, let appID = Int(CommandLine.arguments[2]) {
    for rule in SteamCatalog.saveRules(appID: appID, steamRoot: root) {
        print("  saves: \(rule.root)/\(rule.path)\(rule.pattern)\(rule.recursive ? " (with subfolders)" : "") → Mac: \(rule.macRoot.map { $0 + "/" + rule.macAddPath + rule.path } ?? "none")")
    }
}
