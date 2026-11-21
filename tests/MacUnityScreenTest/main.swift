// Checks a Unity Mac version's first start in full screen (MacUnityScreen): Valheim came up in a small window on
// a new Mac (21.11.2026), and a mode the game keeps stays its own: tests/MacUnityScreenTest/run.sh
import Foundation

@main
struct MacUnityScreenTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias S = MacUnityScreen

    /// What's kept, and what goes along.
    static func rule() {
        let valheim = ["com.coffeestain.valheim-steam"]
        check(S.decide(unity: false, domains: valheim, saved: [:], playerArguments: "") == .notUnity, "not Unity: nothing")
        check(S.decide(unity: true, domains: valheim, saved: [:], playerArguments: "") == .fullScreen(domain: "com.coffeestain.valheim-steam"),
              "Unity with no mode of its own yet (a new Mac): full screen")
        check(S.decide(unity: true, domains: valheim, saved: ["com.coffeestain.valheim-steam": 3], playerArguments: "")
              == .kept(domain: "com.coffeestain.valheim-steam", mode: 3), "a window the game keeps (the player's pick): it stays")
        check(S.decide(unity: true, domains: valheim, saved: ["com.coffeestain.valheim-steam": 2], playerArguments: "")
              == .kept(domain: "com.coffeestain.valheim-steam", mode: 2), "any mode it keeps: it stays")
        let both = ["com.blizzard.hs", "unity.Blizzard Entertainment.Hearthstone"]
        check(S.decide(unity: true, domains: both, saved: ["unity.Blizzard Entertainment.Hearthstone": 1], playerArguments: "")
              == .kept(domain: "unity.Blizzard Entertainment.Hearthstone", mode: 1), "kept under the older domain: it stays")
        for own in ["-screen-fullscreen 0", "-window-mode borderless", "-popupwindow", "-SCREEN-WIDTH 1280 -screen-height 720"] {
            check(S.decide(unity: true, domains: valheim, saved: [:], playerArguments: own) == .playersOwn, "the player's own \(own): theirs")
        }
        check(S.decide(unity: true, domains: valheim, saved: [:], playerArguments: "-nolog -force-metal") == .fullScreen(domain: valheim[0]),
              "other arguments of the player's: the switch beside them")
        check(S.arguments("", .fullScreen(domain: "x")) == "-screen-fullscreen 1", "alone")
        check(S.arguments("-nolog", .fullScreen(domain: "x")) == "-nolog -screen-fullscreen 1", "after the player's")
        check(S.arguments("-nolog", .kept(domain: "x", mode: 3)) == "-nolog" && S.arguments("", .notUnity) == ""
              && S.arguments("-popupwindow", .playersOwn) == "-popupwindow", "otherwise the player's as they are")
        let set = S.note(.fullScreen(domain: "com.coffeestain.valheim-steam"), game: "Valheim") ?? ""
        let kept = S.note(.kept(domain: "com.coffeestain.valheim-steam", mode: 3), game: "Valheim") ?? ""
        check(set.contains("Valheim") && set.contains("-screen-fullscreen 1") && set.contains("com.coffeestain.valheim-steam"), "the log says it sets it: \(set)")
        check(kept.contains("Screenmanager Fullscreen mode 3") && kept.contains("no switch"), "and when it leaves it: \(kept)")
        check(S.note(.notUnity, game: "Dying Light") == nil, "nothing about other engines")
    }

    /// Where Unity keeps it: the bundle identifier, or "unity.<company>.<product>".
    static func domains() {
        let files = ["unity.Blizzard Entertainment.Hearthstone.plist", "unity.Other.Game.plist", "com.coffeestain.valheim-steam.plist"]
        check(S.domains(bundleID: "com.blizzard.hs", product: "Hearthstone", preferenceFiles: files)
              == ["com.blizzard.hs", "unity.Blizzard Entertainment.Hearthstone"], "the bundle's, then the older one by the product's name")
        check(S.domains(bundleID: "com.coffeestain.valheim-steam", product: "Valheim", preferenceFiles: files) == ["com.coffeestain.valheim-steam"],
              "Valheim: its bundle identifier only")
        check(S.domains(bundleID: nil, product: nil, preferenceFiles: files).isEmpty, "nothing known: none")
    }

    /// A Unity app by its files, and the whole look on a made-up app (only reading the real preferences, then a
    /// test domain of its own, removed again).
    static func recognition() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-unity-screen-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        func app(_ name: String, bundleID: String, files: [String]) -> URL {
            let app = root.appendingPathComponent("\(name)/\(name).app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try? fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleExecutable": name]
            try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            for file in files {
                let url = app.appendingPathComponent(file)
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: Data())
            }
            return app
        }
        let player = app("Newer", bundleID: "x.newer", files: ["Contents/Frameworks/UnityPlayer.dylib"])
        let data = app("Older", bundleID: "x.older", files: ["Contents/Resources/Data/globalgamemanagers"])
        let other = app("Other", bundleID: "x.other", files: ["Contents/Frameworks/libsteam_api.dylib"])
        check(S.isUnity(player) && S.isUnity(data), "Unity's player library, or its data folder: Unity")
        check(!S.isUnity(other), "another engine: not Unity")
        check(S.apps(in: player) == [player], "a folder that is an app (GOG): that one")

        let domain = "nightforge.test.unity-screen.\(UUID().uuidString)"
        let game = app("Game", bundleID: domain, files: ["Contents/Resources/Data/globalgamemanagers"])
        let folder = game.deletingLastPathComponent()
        let empty = root.appendingPathComponent("prefs", isDirectory: true)
        try? fm.createDirectory(at: empty, withIntermediateDirectories: true)
        check(S.look(installDir: folder, playerArguments: "", preferences: empty) == .fullScreen(domain: domain),
              "a Unity game's folder, no mode of its own: full screen")
        check(S.look(installDir: other.deletingLastPathComponent(), playerArguments: "", preferences: empty) == .notUnity,
              "another engine's folder: nothing")
        CFPreferencesSetAppValue(S.modeKey as CFString, 3 as CFNumber, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        check(S.look(installDir: folder, playerArguments: "", preferences: empty) == .kept(domain: domain, mode: 3),
              "once it keeps a mode: that")
        CFPreferencesSetAppValue(S.modeKey as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        try? fm.removeItem(at: fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist"))
    }

    static func main() {
        rule()
        domains()
        recognition()
        print(failures == 0 ? "✓ MacUnityScreen" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
