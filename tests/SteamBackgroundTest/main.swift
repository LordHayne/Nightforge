// Checks what the background Steam keeps from Nightforge for days:
// - DockHider: hide-steam-dock.dylib goes into the data folder, an update is renamed over the old
//   file (one a running process has loaded stays as it was), DYLD_INSERT_LIBRARIES never names a
//   file that isn't there, and a running Steam's start environment tells whether it needs a
//   restart (28./29.10.2026: Steam ran on with the path of a deleted build, and every new Wine
//   process died in dyld).
// - SteamGuideButton: "Guide button focuses Steam" goes off in localconfig.vdf, the rest of Steam's
//   file stays exactly as it was.
// tests/SteamBackgroundTest/run.sh
import Foundation

@main
struct SteamBackgroundTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let fm = FileManager.default
    static let temp = fm.temporaryDirectory.appendingPathComponent("SteamBackgroundTest-\(UUID().uuidString)", isDirectory: true)

    static func main() {
        // No real process list: a hanging ps on this Mac doesn't stop the series (tests/Shared/FakeProcesses.swift).
        FakeProcesses.installEmpty()
        // The child startEnvironment reads (not a system program: macOS hides their environment).
        if CommandLine.arguments.contains("--sleep") {
            Thread.sleep(forTimeInterval: 10)
            exit(0)
        }
        try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
        installsLibrary()
        steamState()
        startEnvironment()
        guideButton()
        guideButtonFiles()
        try? fm.removeItem(at: temp)
        print(failures == 0 ? "✓ SteamBackground" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func inode(_ url: URL) -> Int? { (try? fm.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int }

    static func installsLibrary() {
        let home = temp.appendingPathComponent("Nightforge", isDirectory: true)
        let installed = home.appendingPathComponent("hide-steam-dock.dylib")
        DockHider.home = home
        func library(_ name: String, _ text: String) -> URL {
            let url = temp.appendingPathComponent(name)
            try? Data(text.utf8).write(to: url)
            return url
        }

        DockHider.bundled = nil
        check(DockHider.path() == nil, "no library in the app: no path")
        check(Engine.environment(wine: URL(fileURLWithPath: "/usr/bin/true"))["DYLD_INSERT_LIBRARIES"] == nil,
              "no library: Wine starts without DYLD_INSERT_LIBRARIES, not with a path that isn't there")

        DockHider.bundled = library("v1.dylib", "first build")
        check(DockHider.path() == installed.path, "installed into the data folder")
        check((try? String(contentsOf: installed, encoding: .utf8)) == "first build", "with the app's library")
        check(Engine.environment(wine: URL(fileURLWithPath: "/usr/bin/true"))["DYLD_INSERT_LIBRARIES"] == installed.path,
              "Wine gets the data folder's library, not the one inside Nightforge.app")
        check((try? fm.contentsOfDirectory(atPath: home.path)) == ["hide-steam-dock.dylib"], "nothing else left in the folder")

        // A running Steam has the first build loaded; the update must not change that file.
        let loaded = try? FileHandle(forReadingFrom: installed)
        let firstInode = inode(installed)
        DockHider.bundled = library("v2.dylib", "second build")
        check(DockHider.path() == installed.path, "same place after an update")
        check((try? String(contentsOf: installed, encoding: .utf8)) == "second build", "the update is in place")
        check(inode(installed) != firstInode, "the update is a new file, renamed over the old one")
        let before = loaded.flatMap { try? $0.readToEnd() }.map { String(decoding: $0, as: UTF8.self) }
        check(before == "first build", "the file a running process has open is unchanged (got \(before ?? "nil"))")
        try? loaded?.close()
        check((try? fm.contentsOfDirectory(atPath: home.path)) == ["hide-steam-dock.dylib"], "no half-written file left behind")

        let secondInode = inode(installed)
        DockHider.bundled = library("v2-again.dylib", "second build")
        check(DockHider.path() == installed.path && inode(installed) == secondInode, "same library: left alone")

        try? fm.removeItem(at: installed)
        check(DockHider.path() == installed.path && fm.fileExists(atPath: installed.path), "removed meanwhile: put back")
    }

    static func steamState() {
        let gone = "/Users/x/Downloads/Nachtschicht/.claude/worktrees/gone/build/Nightforge.app/Contents/Resources/hide-steam-dock.dylib"
        let bundle = "/Applications/Nightforge.app/Contents/Resources/hide-steam-dock.dylib"
        let installed = "/Users/x/Library/Application Support/Nightforge/hide-steam-dock.dylib"
        let exists: (String) -> Bool = { $0 != gone }
        func state(_ started: String?, installed: String? = installed) -> DockHider.State {
            DockHider.state(started: started, installed: installed, exists: exists)
        }
        check(state(nil) == .current, "no Steam (or unreadable): nothing to do")
        check(state(gone, installed: nil) == .current, "nothing installed to move to: no restart")
        check(state(installed) == .current, "started with the data folder's library: current")
        check(state(bundle) == .outdated, "started with an app bundle's library that's still there: outdated")
        check(state("") == .outdated, "started without the library: outdated")
        check(state(gone) == .missing, "started with a deleted build's library: missing (28.10.2026)")
        check(state(installed + ":" + gone) == .missing, "any inserted library gone: missing")
    }

    static func procArgs(argc: Int32, _ strings: [String], padding: Int = 3) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc.littleEndian) { Array($0) }
        for (index, string) in strings.enumerated() {
            bytes += Array(string.utf8) + [0]
            if index == 0 { bytes += [UInt8](repeating: 0, count: padding) }
        }
        return bytes + [0, 0]
    }

    static func startEnvironment() {
        let key = "DYLD_INSERT_LIBRARIES"
        let path = "/Users/x/Library/Application Support/Nightforge/hide-steam-dock.dylib"
        // Steam under Wine (29.10.2026): argc 8, but Wine has moved the arguments down by one.
        let steam = procArgs(argc: 8, [
            "/Users/x/Library/Application Support/Nightforge/Components/winecx/4.7.3/Libraries/Wine/Nightforge Game.app/Contents/MacOS/wine",
            #"C:\Program Files (x86)\Steam\steam.exe"#, "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles",
            "-cef-disable-gpu", "-cef-disable-gpu-compositing", "-silent",
            "COMMAND_MODE=unix2003", "WINEPREFIX=/Users/x/Library/Application Support/Nightforge/Prefix", "\(key)=\(path)",
        ])
        check(DockHider.startValue(of: key, procArgs: steam) == path, "read from a Wine process's start environment")
        let first = procArgs(argc: 3, ["/x/wine", #"C:\Steam\steam.exe"#, "-silent", "\(key)=\(path)", "HOME=/Users/x"])
        check(DockHider.startValue(of: key, procArgs: first) == path, "found as the first variable, right after Wine's shortened arguments")
        let without = procArgs(argc: 2, ["/x/wine", #"C:\Steam\steam.exe"#, "-\(key)=/x", "HOME=/Users/x"])
        check(DockHider.startValue(of: key, procArgs: without) == "", "an argument isn't the variable; without it: \"\"")
        check(DockHider.startValue(of: key, procArgs: [1, 0]) == nil, "too short: unknown")

        // A real process (this test once more), started with a variable of its own.
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        sleeper.arguments = ["--sleep"]
        sleeper.environment = ["NIGHTFORGE_TEST_MARK": "dock-hider", "PATH": "/usr/bin:/bin"]
        guard (try? sleeper.run()) != nil else { return check(false, "couldn't start the test as a child") }
        defer { sleeper.terminate() }
        check(DockHider.startValue(of: "NIGHTFORGE_TEST_MARK", pid: sleeper.processIdentifier) == "dock-hider",
              "read from a running process's start environment")
        check(DockHider.startValue(of: key, pid: sleeper.processIdentifier) == "", "a variable it never had: \"\"")
    }

    // A localconfig.vdf as Steam writes it (cut down): JSON values with escaped quotes, a nested
    // key of the same name that isn't the setting.
    static let localconfig = """
        "UserLocalConfigStore"
        {
        \t"Broadcast"
        \t{
        \t\t"Permissions"\t\t"1"
        \t}
        \t"system"
        \t{
        \t\t"Controller_CheckGuideButton"\t\t"1"
        \t\t"JumplistSettingsKnown"\t\t"1"
        \t}
        \t"WebStorage"
        \t{
        \t\t"LibraryDisplaySize"\t\t"{\\"version\\":1,\\"name\\":\\"}\\"}"
        \t}
        \t"ControllerTypesUsed"\t\t"controller_ps5,controller_xbox360,"
        }

        """

    static func guideButton() {
        guard let off = SteamGuideButton.turnedOff(localconfig) else { return check(false, "the setting isn't added") }
        let config = VDF.parse(off)?["UserLocalConfigStore"]
        check(config?["Controller_CheckGuideButton"]?.string == "0", "added at the top of UserLocalConfigStore, off")
        check(config?["system"]?["Controller_CheckGuideButton"]?.string == "1", "the nested key of the same name is left as it was")
        check(config?["WebStorage"]?["LibraryDisplaySize"]?.string == #"{"version":1,"name":"}"}"#, "escaped quotes and braces stay")
        check(off.replacingOccurrences(of: "\n\t\"Controller_CheckGuideButton\"\t\t\"0\"", with: "") == localconfig,
              "only the one line added, everything else byte for byte")
        check(off.hasPrefix("\"UserLocalConfigStore\"\n{\n\t\"Controller_CheckGuideButton\"\t\t\"0\"\n\t\"Broadcast\""),
              "as its own line right after the opening brace")
        check(SteamGuideButton.turnedOff(off) == nil, "off already: nothing to write")

        let on = off.replacingOccurrences(of: "\"Controller_CheckGuideButton\"\t\t\"0\"", with: "\"Controller_CheckGuideButton\"\t\t\"1\"")
        check(SteamGuideButton.turnedOff(on) == off, "turned on again in Steam: off again, in place")
        let lower = off.replacingOccurrences(of: "\"Controller_CheckGuideButton\"\t\t\"0\"", with: "\"controller_checkguidebutton\"\t\t\"1\"")
        check(VDF.parse(SteamGuideButton.turnedOff(lower) ?? "")?["UserLocalConfigStore"]?["Controller_CheckGuideButton"]?.string == "0",
              "Steam's keys don't care about case")

        let crlf = localconfig.replacingOccurrences(of: "\n", with: "\r\n")
        check(VDF.parse(SteamGuideButton.turnedOff(crlf) ?? "")?["UserLocalConfigStore"]?["Controller_CheckGuideButton"]?.string == "0",
              "Windows line ends")
        check(SteamGuideButton.turnedOff("") == nil, "empty file: left alone")
        check(SteamGuideButton.turnedOff("\"UserLocalConfigStore\"\n{\n\t\"Broadcast\"\t\t\"1") == nil, "cut off mid-file: left alone")
    }

    static func guideButtonFiles() {
        let root = temp.appendingPathComponent("Steam", isDirectory: true)
        let account = root.appendingPathComponent("userdata/158043902/config", isDirectory: true)
        let anonymous = root.appendingPathComponent("userdata/0", isDirectory: true)
        try? fm.createDirectory(at: account, withIntermediateDirectories: true)
        try? fm.createDirectory(at: anonymous, withIntermediateDirectories: true)
        let file = account.appendingPathComponent("localconfig.vdf")
        try? localconfig.write(to: file, atomically: true, encoding: .utf8)

        SteamGuideButton.turnOff(steamRoot: root)
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check(VDF.parse(text)?["UserLocalConfigStore"]?["Controller_CheckGuideButton"]?.string == "0", "the account's file has it off")
        check(!fm.fileExists(atPath: anonymous.appendingPathComponent("config").path), "no file made for an account without one")
        let modified = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.01)
        SteamGuideButton.turnOff(steamRoot: root)
        check(((try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) == modified, "off already: not written again")
        SteamGuideButton.turnOff(steamRoot: temp.appendingPathComponent("no-steam"))
    }
}
