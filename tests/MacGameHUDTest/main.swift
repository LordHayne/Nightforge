// Checks that the HUD reaches Mac versions and leaves again cleanly: tests/MacGameHUDTest/run.sh
import Foundation

@main
struct MacGameHUDTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A minimal app bundle with an Info.plist naming its bundle ID.
    static func app(_ url: URL, id: String) {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
        (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
    }

    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-hud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appendingPathComponent("Valheim", isDirectory: true)
        app(game.appendingPathComponent("valheim.app"), id: "test.nightforge.valheim")
        app(game.appendingPathComponent("Tools/Editor.app"), id: "test.nightforge.editor")
        app(game.appendingPathComponent("a/b/Deep.app"), id: "test.nightforge.deep")

        check(MacGameHUD.bundleIDs(in: game) == ["test.nightforge.editor", "test.nightforge.valheim"],
              "the apps in the folder and one folder down, not deeper: \(MacGameHUD.bundleIDs(in: game))")
        check(MacGameHUD.bundleIDs(in: game.appendingPathComponent("valheim.app")) == ["test.nightforge.valheim"],
              "a folder that is the app itself")

        // Each game's defaults domain is a test suite of its own.
        var domains: [String: UserDefaults] = [:]
        let domain: (String) -> UserDefaults? = { id in
            if let known = domains[id] { return known }
            let made = TestDefaults.suite("hud-\(id)")
            domains[id] = made
            return made
        }
        let defaults = TestDefaults.suite("hud")
        domain("test.nightforge.editor")?.set(false, forKey: MacGameHUD.key)  // the player's own choice

        MacGameHUD.prepare(folder: game, on: true, defaults: defaults, domain: domain)
        check(domain("test.nightforge.valheim")?.bool(forKey: MacGameHUD.key) == true, "HUD on: the game gets Apple's switch")
        check(domain("test.nightforge.editor")?.bool(forKey: MacGameHUD.key) == false, "a value the player set stays theirs")
        check(defaults.stringArray(forKey: MacGameHUD.setKey) == ["test.nightforge.valheim"], "noted what Nightforge set")

        MacGameHUD.prepare(folder: game, on: false, defaults: defaults, domain: domain)
        check(domain("test.nightforge.valheim")?.object(forKey: MacGameHUD.key) == nil, "HUD off: taken back")
        check(domain("test.nightforge.editor")?.object(forKey: MacGameHUD.key) != nil, "the player's own value still stays")
        check((defaults.stringArray(forKey: MacGameHUD.setKey) ?? []).isEmpty, "nothing noted any more")

        print(failures == 0 ? "✓ MacGameHUD" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
