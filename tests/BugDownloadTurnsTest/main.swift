import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        print("✗ \(message)")
    }
}

func game(_ provider: Provider, platform: Platform = .windows, builtIn: Bool = true) -> Game {
    let bottle = Bottle(name: "x", url: URL(fileURLWithPath: "/tmp/x"), isBuiltIn: builtIn)
    var game: Game
    switch provider {
    case .steam: game = Game(appID: 1, name: "A", bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
    case .epic: game = Game(gameID: .epic("a"), name: "A", bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
    case .gog: game = Game(gameID: .gog("1"), name: "A", bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
    case .battlenet: game = Game(gameID: .battlenet("a"), name: "A", bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
    }
    game.platform = platform
    return game
}

@main struct Main {
    static func main() async {
        // One Mac download went 0.9 of the way, and finished: the next one starts at 0.
        check(!SteamSwitch.macDownloadsStalled(["b": 0.1], since: ["a": 0.9]), "a new download isn't stuck because the last one got further")
        check(!SteamSwitch.macDownloadsStalled(["b": 0], since: ["a": 0.9]), "… nor at its very start")
        check(!SteamSwitch.macDownloadsStalled(["a": 0.5, "b": 0], since: ["a": 0.5]), "one new among the stuck has a turn")
        check(SteamSwitch.macDownloadsStalled(["a": 0.5], since: ["a": 0.5]), "the same progress is stuck")
        check(SteamSwitch.macDownloadsStalled(["a": 0.4], since: ["a": 0.5]), "less is stuck (Steam verifying)")
        check(!SteamSwitch.macDownloadsStalled(["a": 0.51], since: ["a": 0.5]), "any progress goes on")
        check(!SteamSwitch.macDownloadsStalled(["a": 0.5, "b": 0.31], since: ["a": 0.5, "b": 0.3]), "progress in one of two goes on")
        check(SteamSwitch.macDownloadsStalled(["a": 0.5, "b": 0.3], since: ["a": 0.5, "b": 0.3, "c": 0.9]), "a finished one doesn't help the rest")
        check(!SteamSwitch.macDownloadsStalled(["a": 0], since: nil), "the first turn is never stuck")

        check(SteamSwitch.usesWindowsSteam(game(.steam)), "a Windows game of Nightforge's Steam")
        check(!SteamSwitch.usesWindowsSteam(game(.steam, builtIn: false)), "a CrossOver bottle has its own Steam")
        check(!SteamSwitch.usesWindowsSteam(game(.steam, platform: .mac)), "a Mac version comes through Steam for Mac")
        check(!SteamSwitch.usesWindowsSteam(game(.epic)), "an Epic game needs no Steam, though it lives in that bottle")
        check(!SteamSwitch.usesWindowsSteam(game(.gog)), "a GOG game neither")

        typealias Facts = SteamSwitch.DownloadFacts
        // Every state: the rules hold whatever else is true.
        var states = 0
        for bits in 0..<512 {
            func on(_ n: Int) -> Bool { bits >> n & 1 == 1 }
            let facts = Facts(macDownload: on(0), windowsDownload: on(1), macReady: on(2), macSignedIn: on(3), windowsSignedIn: on(4),
                              macStalled: on(5), windowsRunning: on(6), windowsReplaced: on(7), windowsStopped: on(8))
            states += 1
            let turn = SteamSwitch.downloadTurn(facts)
            if !facts.macDownload && !facts.windowsDownload { check(turn == nil, "nothing to download, no switch: \(facts)") }
            if turn == .mac {
                check(facts.macDownload && facts.macReady && !facts.macSignedIn && !facts.macStalled, "Steam for Mac's turn only for what it can do: \(facts)")
                check(!(facts.windowsDownload && facts.windowsSignedIn), "a signed-in Windows Steam finishes first: \(facts)")
            }
            if turn == .windows {
                check(facts.windowsDownload, "the Windows Steam's turn needs its download: \(facts)")
                check(!(facts.macDownload && facts.macSignedIn), "a signed-in Steam for Mac finishes first: \(facts)")
                check(facts.windowsRunning ? facts.windowsReplaced : facts.windowsStopped, "only a Windows Steam that's out comes back: \(facts)")
            }
        }
        check(states == 512, "every state seen")

        // Text of the page Epic ends with, whatever it holds: the closing brace before the opening one is a crash when it's a range.
        check(EpicSignIn.code(fromPage: "} {") == nil, "a closing brace before the opening one")
        check(EpicSignIn.code(fromPage: "}") == nil && EpicSignIn.code(fromPage: "{") == nil && EpicSignIn.code(fromPage: "") == nil, "half a page")
        check(EpicSignIn.code(fromPage: "{") == nil, "one brace is no range")
        check(EpicSignIn.code(fromPage: #"x {"authorizationCode":"abc123"} y"#) == "abc123", "the code from the page")
        check(EpicSignIn.code(fromPage: #"{"authorizationCode":"a/b"}"#) == nil, "only letters and digits")

        print(failures == 0 ? "✓ Whose downloads go on (512 states), Epic's page" : "✗ \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
