// Checks GameShortcut: which links it understands, the file name of a game's app, and what the app
// it writes contains (into a temporary folder): tests/GameShortcutTest/run.sh
import AppKit

@main
struct GameShortcutTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func action(_ link: String, key: String = key) -> GameShortcut.Action? {
        GameShortcut.action(from: URL(string: link)!, key: key)
    }

    static let key = "0123456789abcdef0123456789abcdef"

    static func main() {
        check(action("nightforge://play/1086940?key=\(key)") == .play(.steam(1086940)), "play link with the key")
        check(action("nightforge://show/570") == .show(.steam(570)), "show link")
        check(action("nightforge://delete/570") == nil, "nothing else")
        check(action("nightforge://play/abc?key=\(key)") == nil, "a bare ID is a Steam app ID, a number")
        check(action("nightforge://play/epic.Fortnite?key=\(key)") == .play(.epic("Fortnite")), "other stores carry their key")
        check(action("nightforge://play/epic.a%20b") == nil, "only plain IDs")
        check(action("https://play/570") == nil, "only Nightforge's own links")
        check(GameShortcut.url(play: .steam(570)).absoluteString == "nightforge://play/570", "a link without the key, as before")
        check(GameShortcut.url(play: .epic("Fortnite"), key: key).absoluteString == "nightforge://play/epic.Fortnite?key=\(key)",
              "the link a game's app opens")

        // Any web page can open a link: without the key, or with another, it only shows the game's page.
        check(action("nightforge://play/570") == .show(.steam(570)), "a play link without the key shows the page")
        check(action("nightforge://play/570?key=ffffffffffffffffffffffffffffffff") == .show(.steam(570)), "with another key too")
        check(action("nightforge://play/570?key=") == .show(.steam(570)) && action("nightforge://play/570?key=", key: "") == .show(.steam(570)),
              "an empty key is no key")
        check(action("nightforge://play/570?other=1&key=\(key)") == .play(.steam(570)), "the key among other parts")
        check(action(GameShortcut.url(play: .gog("1207664663"), key: key).absoluteString) == .play(.gog("1207664663")),
              "a link Nightforge writes leads back to its game")

        var game = Game(appID: 1086940, name: "Baldur's Gate 3: Deluxe/Edition", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = .installed
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-shortcut-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        check(GameShortcut.appURL(for: game, in: folder).lastPathComponent == "Baldur's Gate 3 – Deluxe-Edition.app",
              "a file name without / and : \(GameShortcut.appURL(for: game, in: folder).lastPathComponent)")

        let cover = NSImage(size: NSSize(width: 60, height: 90), flipped: false) { rect in NSColor.orange.setFill(); rect.fill(); return true }
        do {
            let app = try GameShortcut.create(for: game, icon: cover, in: folder, key: key)
            let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            check(plist?["CFBundleExecutable"] as? String == "play", "Info.plist names the script")
            check(plist?["CFBundleIdentifier"] as? String == "io.github.lordhayne.nightforge.game.1086940", "an identifier of its own")
            check(plist?["LSUIElement"] as? Bool == true, "no Dock icon while it hands over")
            let script = app.appendingPathComponent("Contents/MacOS/play")
            let text = (try? String(contentsOf: script, encoding: .utf8)) ?? ""
            check(text.contains("open \"nightforge://play/1086940?key=\(key)\""), "the script opens the game's link with the key: \(text)")
            check(FileManager.default.isExecutableFile(atPath: script.path), "the script can run")
            check(NSWorkspace.shared.icon(forFile: app.path).size.width > 0, "it has an icon")
            // Adding it again replaces it instead of failing.
            _ = try GameShortcut.create(for: game, icon: nil, in: folder, key: key)
            check(FileManager.default.fileExists(atPath: script.path), "adding again replaces the app")
        } catch {
            check(false, "writing the app failed: \(error)")
        }

        keys(folder)
        concurrentKeys(folder)
        strangeLinks(folder)
        olderApps(folder)

        print(failures == 0 ? "✓ GameShortcut" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The key: made once, kept, readable only by the player.
    static func keys(_ folder: URL) {
        let home = folder.appendingPathComponent("support", isDirectory: true)
        let first = GameShortcut.key(in: home)
        check(first.count == 32 && first.allSatisfy(\.isHexDigit), "a key of 128 bits: \(first)")
        check(GameShortcut.key(in: home) == first, "the same key the next time")
        let file = home.appendingPathComponent("shortcut-key")
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(mode == 0o600, "only the player can read it: \(String(describing: mode))")
        try? Data("cut".utf8).write(to: file)
        let replaced = GameShortcut.key(in: home)
        check(replaced != first && replaced.count == 32 && GameShortcut.key(in: home) == replaced, "a file that holds no key gets a new one")
        let other = GameShortcut.key(in: folder.appendingPathComponent("other", isDirectory: true))
        check(other != replaced, "each Mac its own")
    }

    /// "Add to Applications" and the start's addKey at once: every one gets the key the file holds, never a key of
    /// its own that was not kept (outside review, item 4). The window is microseconds wide: many rounds.
    static func concurrentKeys(_ folder: URL) {
        var splits = 0
        var stray = 0
        var modes = Set<Int>()
        for round in 0..<300 {
            let home = folder.appendingPathComponent("support-race-\(round)", isDirectory: true)
            let keys = LockedValue<[String]>([])
            DispatchQueue.concurrentPerform(iterations: 16) { _ in
                let key = GameShortcut.key(in: home)
                keys.withLock { $0.append(key) }
            }
            let file = home.appendingPathComponent("shortcut-key")
            let kept = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let all = keys.withLock { $0 }
            if all.count != 16 || Set(all) != [kept] || kept.count != 32 { splits += 1 }
            modes.insert(((try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int) ?? -1)
            stray += ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0 != "shortcut-key" }.count
            try? FileManager.default.removeItem(at: home)
        }
        check(splits == 0, "300 rounds of 16 at once: one key for all, the one in the file (\(splits) rounds split)")

        // The same where a file without a key is in the way (cut short by an older Nightforge, or empty): every one
        // replaces it – and the later rename must not leave the earlier one with a key the file no longer holds.
        for leftover in ["", "cut"] {
            var split = 0
            for round in 0..<300 {
                let home = folder.appendingPathComponent("support-leftover-\(round)", isDirectory: true)
                try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                try? Data(leftover.utf8).write(to: home.appendingPathComponent("shortcut-key"))
                let keys = LockedValue<[String]>([])
                DispatchQueue.concurrentPerform(iterations: 16) { _ in
                    let key = GameShortcut.key(in: home)
                    keys.withLock { $0.append(key) }
                }
                let kept = (try? String(contentsOf: home.appendingPathComponent("shortcut-key"), encoding: .utf8)) ?? ""
                let all = keys.withLock { $0 }
                if all.count != 16 || Set(all) != [kept] || kept.count != 32 { split += 1 }
                let mode = ((try? FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("shortcut-key").path))?[.posixPermissions] as? Int) ?? -1
                if mode != 0o600 { split += 1 }
                try? FileManager.default.removeItem(at: home)
            }
            check(split == 0, "300 rounds of 16 at once over a leftover file \(leftover.debugDescription): one key, the file's, mode 600 (\(split) rounds split)")
        }
        check(modes == [0o600], "…readable by the player alone: \(modes)")
        check(stray == 0, "…and nothing left beside it: \(stray) files")
    }

    /// Links and IDs that aren't what they look like (outside review, items 2 and 3).
    static func strangeLinks(_ folder: URL) {
        // Exactly one segment after the host.
        check(action("nightforge://play/anything/else/570?key=\(key)") == nil, "a path of several segments isn't a game's link")
        check(action("nightforge://show/x/570") == nil, "…nor is a show link")
        check(action("nightforge://play/570/?key=\(key)") == .play(.steam(570)), "a slash at the end is no second segment")
        check(action("nightforge://play?key=\(key)") == nil && action("nightforge://play/") == nil, "no game in it")
        // IDs that GameID(provider:id:) takes but a link can't carry: no crash, and no app.
        for id in ["a b", "a%b", "a?b", "a#b", "é", "a/b", ""] {
            let game = GameID.gog(id)
            let link = GameShortcut.url(play: game, key: key)
            check(link.scheme == "nightforge" && !GameShortcut.isUsable(game) && GameShortcut.action(from: link, key: key) == nil,
                  "ID \(id.debugDescription): a link that is nobody's game, not a crash (\(link.absoluteString))")
        }
        check(GameShortcut.isUsable(.steam(570)) && GameShortcut.isUsable(.epic("Fortnite")) && GameShortcut.isUsable(.gog("1207664663")),
              "plain IDs are usable")
        var strange = Game(gameID: .gog("a b"), name: "Strange", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                           steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        strange.install = .installed
        do {
            _ = try GameShortcut.create(for: strange, icon: nil, in: folder.appendingPathComponent("strange", isDirectory: true), key: key)
            check(false, "an app for an ID that can't be in a link")
        } catch {
            check(error is GameShortcut.UnusableID && !error.localizedDescription.isEmpty, "no app for it: \(error)")
        }
        check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("strange").path), "…and nothing written")
    }

    /// Apps an older Nightforge wrote open their link without the key: at the start their script gets it.
    static func olderApps(_ folder: URL) {
        let fm = FileManager.default
        let apps = folder.appendingPathComponent("Nightforge Games", isDirectory: true)
        func app(_ name: String, _ script: String) -> URL {
            let file = apps.appendingPathComponent("\(name).app/Contents/MacOS/play")
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? script.write(to: file, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file
        }
        func text(_ file: URL) -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
        let old = app("Hades", "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/1145360\"\n")
        let epic = app("Fortnite", "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/epic.Fortnite\"\n")
        let stale = app("Valheim", "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/892970?key=ffffffffffffffffffffffffffffffff\"\n")
        let foreign = app("Mine", "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/570\"\necho more\n")
        let odd = app("Odd", "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/epic.a b\"\n")
        let notAnApp = apps.appendingPathComponent("notes/Contents/MacOS/play")
        try? fm.createDirectory(at: notAnApp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "#!/bin/sh\nexec /usr/bin/open \"nightforge://play/570\"\n".write(to: notAnApp, atomically: true, encoding: .utf8)

        GameShortcut.addKey(key, in: apps)
        check(text(old) == GameShortcut.script(.steam(1145360), key: key), "an older app's link gets the key: \(text(old))")
        check(fm.isExecutableFile(atPath: old.path), "and still runs")
        check(text(epic) == GameShortcut.script(.epic("Fortnite"), key: key), "an Epic game's too")
        check(text(stale) == GameShortcut.script(.steam(892970), key: key), "one with another key gets this one")
        check(text(foreign).hasSuffix("echo more\n") && text(odd).contains("epic.a b") && text(notAnApp).hasSuffix("/570\"\n"),
              "a script Nightforge didn't write that way, or outside an app, stays as it is")
        let before = (try? fm.attributesOfItem(atPath: old.path))?[.modificationDate] as? Date
        GameShortcut.addKey(key, in: apps)
        check((try? fm.attributesOfItem(atPath: old.path))?[.modificationDate] as? Date == before, "one that has the key isn't written again")
        GameShortcut.addKey(key, in: folder.appendingPathComponent("missing", isDirectory: true))
    }
}
