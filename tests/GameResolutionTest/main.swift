// Checks how Nightforge fits a Unity or Unreal game's remembered resolution to the screen it plays on,
// with a Wine registry file and GameUserSettings.ini files as fixtures: tests/GameResolutionTest/run.sh
import Foundation

@main
struct GameResolutionTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

    static func fixture(_ name: String) -> String {
        (try? String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    static func main() {
        screens()
        registry()
        unity()
        unreal()
        ownFormat()
        folders()
        if failures == 0 { print("✓ GameResolution: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }

    typealias Size = GameResolution.Size
    static let tv = Size(width: 1920, height: 1080)
    static let macBook = Size(width: 1512, height: 982)

    /// What Wine shows a game: points without Retina mode, pixels with it.
    static func screens() {
        let retinaScreen = (points: macBook, pixels: Size(width: 3024, height: 1964))
        check(GameResolution.wineSize(points: retinaScreen.points, pixels: retinaScreen.pixels, retina: false) == macBook,
              "MacBook without Retina mode: 1512×982, as Unity games stored it")
        check(GameResolution.wineSize(points: retinaScreen.points, pixels: retinaScreen.pixels, retina: true) == Size(width: 3024, height: 1964),
              "MacBook with Retina mode: its pixels")
        check(GameResolution.wineSize(points: tv, pixels: tv, retina: false) == tv, "a 1080p TV: 1920×1080")
        check(GameResolution.wineSize(points: tv, pixels: tv, retina: true) == tv, "a 1080p TV has no Retina pixels")
        check(GameResolution.wineSize(points: tv, pixels: Size(width: 3840, height: 2160), retina: true) == Size(width: 3840, height: 2160),
              "a 4K TV looking like 1080p, with Retina mode: 3840×2160")
    }

    /// Reading user.reg: the right key, its DWORDs only, Wine's escapes.
    static func registry() {
        let reg = fixture("user.reg")
        check(!reg.isEmpty, "user.reg fixture is there")
        let overcooked = GameResolution.dwordValues(inRegistry: reg, key: #"Software\Team17\Overcooked2"#)
        check(overcooked.count == 8, "Overcooked 2: its 8 DWORDs, not the hex values (\(overcooked.count))")
        check(overcooked["Screenmanager Resolution Width_h182942802"] == 1512, "Overcooked 2 remembers 1512 wide")
        check(overcooked["Screenmanager Resolution Height_h2627697771"] == 945, "Overcooked 2 remembers 945 high")
        check(overcooked["Screenmanager Fullscreen mode_h3630240806"] == 1, "Overcooked 2 is set to a full-screen window")
        check(GameResolution.dwordValues(inRegistry: reg, key: #"software\team17\overcooked2"#) == overcooked,
              "registry keys ignore case")
        check(GameResolution.dwordValues(inRegistry: reg, key: #"Software\Team17"#).isEmpty, "a parent key has its own values")
        check(GameResolution.dwordValues(inRegistry: reg, key: #"Software\Team17\Overcooked2\Telemetry"#).count == 1,
              "a subkey's values stay its own")
        check(GameResolution.dwordValues(inRegistry: reg, key: #"Software\Nobody\Nothing"#).isEmpty, "a missing key: nothing")
        let escaped = GameResolution.dwordValues(inRegistry: reg, key: "Software\\Studio [X]\\Caf\u{e9}")
        check(escaped == [#"Quoted "name"_h1"#: 42], "Wine's escapes in keys and names (\(escaped))")
    }

    static func unity() {
        let reg = fixture("user.reg")
        func values(_ key: String) -> [String: UInt32] { GameResolution.dwordValues(inRegistry: reg, key: key) }

        // Overcooked 2, first played on the MacBook, now on the TV.
        let overcooked = values(#"Software\Team17\Overcooked2"#)
        let changes = GameResolution.unityChanges(overcooked, size: tv)
        check(changes == ["Screenmanager Resolution Width_h182942802": 1920,
                          "Screenmanager Resolution Height_h2627697771": 1080,
                          "Screenmanager Resolution Use Native_h1405027254": 1],
              "Overcooked 2 on the TV: 1920×1080 and the screen's own size, Defaults untouched (\(changes))")
        check(GameResolution.unitySize(overcooked) == Size(width: 1512, height: 945), "the size it remembered, for the log")
        check(GameResolution.registryImport(key: #"Software\Team17\Overcooked2"#, values: changes) == """
            [HKEY_CURRENT_USER\\Software\\Team17\\Overcooked2]
            "Screenmanager Resolution Height_h2627697771"=dword:00000438
            "Screenmanager Resolution Use Native_h1405027254"=dword:00000001
            "Screenmanager Resolution Width_h182942802"=dword:00000780
            """, "the .reg section for regedit")
        var applied = overcooked
        applied.merge(changes) { _, new in new }
        check(GameResolution.unityChanges(applied, size: tv).isEmpty, "once fitted, the next start changes nothing")
        check(GameResolution.unityChanges(applied, size: macBook).count == 2, "back on the MacBook: width and height again")

        // The player's own choices of a window stay.
        for (mode, fits) in [(0, true), (1, true), (2, false), (3, false)] as [(UInt32, Bool)] {
            var game = overcooked
            game["Screenmanager Fullscreen mode_h3630240806"] = mode
            check(GameResolution.unityChanges(game, size: tv).isEmpty != fits, "Unity full-screen mode \(mode): \(fits ? "fitted" : "left alone")")
        }
        check(GameResolution.unityChanges(values(#"Software\Some Studio\Windowed Game"#), size: tv).isEmpty, "a windowed game stays a window")

        // Native already: only what differs.
        let minutes = values(#"Software\Flanne\MinutesTillDawn"#)
        check(GameResolution.unityChanges(minutes, size: macBook).isEmpty, "a game at the MacBook's size on the MacBook: nothing to do")
        check(Set(GameResolution.unityChanges(minutes, size: tv).keys) == ["Screenmanager Resolution Width_h182942802",
                                                                         "Screenmanager Resolution Height_h2627697771"],
              "Use Native already on: only width and height")

        // Unity before 2018: "Is Fullscreen mode", no Use Native.
        let door = values(#"Software\Saucisson\Hold the door!"#)
        check(GameResolution.unityChanges(door, size: tv) == ["Screenmanager Resolution Width_h182942802": 1920,
                                                               "Screenmanager Resolution Height_h2627697771": 1080],
              "old Unity in full screen: width and height, nothing invented")
        var doorWindow = door
        doorWindow["Screenmanager Is Fullscreen mode_h3981298716"] = 0
        check(GameResolution.unityChanges(doorWindow, size: tv).isEmpty, "old Unity in a window stays")

        check(GameResolution.unityChanges(["Screenmanager Resolution Width_h182942802": 1512], size: tv).isEmpty,
              "no full-screen mode stored: nothing to go by")
        check(GameResolution.unityChanges(overcooked, size: Size(width: 0, height: 0)).isEmpty, "no screen size: nothing")

        // Names and keys.
        check(GameResolution.unityBase("Screenmanager Resolution Width_h182942802") == "Screenmanager Resolution Width", "hash goes")
        check(GameResolution.unityBase("Screenmanager Fullscreen mode Default_h401710285") == "Screenmanager Fullscreen mode Default",
              "a Default stays a Default")
        check(GameResolution.unityBase("Screenmanager Resolution Width") == "Screenmanager Resolution Width", "no hash, the name")
        check(GameResolution.unityBase("high_hscore") == "high_hscore", "no number behind _h, the name")
        check(GameResolution.unityKey(appInfo: "Team17\nOvercooked2") == #"Software\Team17\Overcooked2"#, "app.info names the key")
        check(GameResolution.unityKey(appInfo: "Saucisson\r\nHold the door!\r\n") == #"Software\Saucisson\Hold the door!"#,
              "Windows line ends, spaces and ! in names")
        check(GameResolution.unityKey(appInfo: "Team17") == nil, "only a company: no key")
        check(GameResolution.unityKey(appInfo: "Microsoft\nGame") == nil, "Microsoft's part of the registry stays closed")
        check(GameResolution.unityKey(appInfo: "Wine\nMac Driver") == nil, "Wine's settings stay closed")
        check(GameResolution.unityKey(appInfo: "Studio]\nGame") == nil, "a bracket would break the .reg file")
        check(GameResolution.unityKey(appInfo: "Caf\u{e9}\nGame") == nil, "regedit reads REGEDIT4 as ANSI: ASCII only")
    }

    static func unreal() {
        let ue5 = fixture("GameUserSettings-UE5.ini")
        guard let fitted = GameResolution.unrealFitted(ue5, size: tv) else {
            check(false, "a UE5 game in a full-screen window gets the TV's size")
            return
        }
        let before = ue5.components(separatedBy: "\r\n"), after = fitted.components(separatedBy: "\r\n")
        check(before.count == after.count, "same lines, Windows line ends kept (\(before.count) → \(after.count))")
        let changed = zip(before, after).filter { $0 != $1 }.map(\.1)
        check(changed == ["ResolutionSizeX=1920", "ResolutionSizeY=1080",
                          "LastUserConfirmedResolutionSizeX=1920", "LastUserConfirmedResolutionSizeY=1080"],
              "only the four resolution lines change (\(changed))")
        check(GameResolution.unrealFitted(fitted, size: tv) == nil, "fitted once, the next start changes nothing")
        check(GameResolution.unrealFitted(ue5, size: macBook) == nil, "already the MacBook's size on the MacBook")

        // A game's own settings class, in exclusive full screen, with DesiredScreenHeight on.
        let subclass = fixture("GameUserSettings-subclass.ini")
        if let fitted = GameResolution.unrealFitted(subclass, size: tv) {
            let lines = fitted.components(separatedBy: "\r\n")
            let voyage = lines.drop { $0 != "[/Script/Voyage.VoyageGameUserSettings]" }
            check(voyage.contains("ResolutionSizeX=1920") && voyage.contains("LastUserConfirmedResolutionSizeY=1080"),
                  "the game's own section gets the TV's size")
            check(voyage.contains("bUseDesiredScreenHeight=False") && !voyage.contains("bUseDesiredScreenHeight=True"),
                  "DesiredScreenHeight off, so the resolution counts")
            check(voyage.contains("DesiredScreenWidth=1280") && voyage.contains("PreferredFullscreenMode=1"), "the rest stays")
            check(lines.first == ";METADATA=(Diff=true, UseCommands=true)" && lines[1] == "[/Script/Engine.GameUserSettings]"
                  && lines[2] == "bUseDesiredScreenHeight=False", "the engine's section and the header stay")
            check(!fitted.contains("ResolutionSizeX=1512"), "no old size left")
        } else {
            check(false, "a game's own settings section gets the TV's size")
        }
        // ABZU (Epic, Unreal 4.8): its own class with "Fullscreen=ON" and DesiredScreenWidth/Height, no
        // FullscreenMode – its file from the game test of 3.11.2026, when it came up 1920×1200 on the MacBook.
        let abzu = fixture("GameUserSettings-abzu.ini")
        if let fitted = GameResolution.unrealFitted(abzu, size: macBook) {
            let lines = fitted.components(separatedBy: .newlines)
            // Its full screen at 1512×982 crashed before the first window, a window that size started
            // (live test, 3.11.2026 evening).
            check(lines.contains("Fullscreen=OFF") && lines.contains("DesiredScreenWidth=1512") && lines.contains("DesiredScreenHeight=982"),
                  "ABZU: a window at the screen's size, Nightforge's full screen does the rest")
            // Its pak's defaults, which the saved file leaves out, are 1920×1080 in exclusive full screen
            // (switched the Mac to 1920×1200 after the intro); Unreal's sizes at 1512×982 died at the
            // start (live tests 4.11.2026). Only the mode: a window without a frame over the screen.
            check(lines.contains("FullscreenMode=1") && lines.contains("LastConfirmedFullscreenMode=1") && !fitted.contains("ResolutionSize"),
                  "…and Unreal's mode a full-screen window, its sizes unwritten")
            check(lines.contains("PreferredFullscreenMode=0") && lines.contains("bUseDesktopResolutionForFullscreen=False")
                  && lines.contains("Shadows=HIGH") && lines.contains("sg.ShadowQuality=3")
                  && !fitted.contains("DesiredScreenWidth=1280") && !fitted.contains("Fullscreen=ON"), "the rest stays, the old size goes")
            check(fitted.utf8.filter { $0 == 13 }.count == fitted.utf8.filter { $0 == 10 }.count
                  && fitted.utf8.filter { $0 == 10 }.count == abzu.utf8.filter { $0 == 10 }.count + 2,
                  "CRLF kept, Unreal's two mode keys added")
            check(GameResolution.unrealFitted(fitted, size: macBook) == nil, "fitted once, the next start changes nothing")
            if let tvFitted = GameResolution.unrealFitted(fitted, size: tv, screens: [tv, macBook]) {
                check(tvFitted.contains("DesiredScreenWidth=\(tv.width)") && tvFitted.contains("Fullscreen=OFF")
                      && tvFitted.contains("FullscreenMode=1") && !tvFitted.contains("=1512"),
                      "the window written for the MacBook grows to the TV")
            } else {
                check(false, "the window written for the MacBook grows to the TV")
            }
        } else {
            check(false, "ABZU's older settings get a window at the MacBook's size")
        }
        // What 65e2983 left behind: full screen at the screen's size, the desktop's resolution.
        let crashed = abzu.replacingOccurrences(of: "DesiredScreenWidth=1280", with: "DesiredScreenWidth=1512")
            .replacingOccurrences(of: "DesiredScreenHeight=720", with: "DesiredScreenHeight=982")
            .replacingOccurrences(of: "bUseDesktopResolutionForFullscreen=False", with: "bUseDesktopResolutionForFullscreen=True")
        check(GameResolution.unrealFitted(crashed, size: macBook)?.contains("Fullscreen=OFF") == true,
              "a file already at the screen's size in full screen becomes a window")
        check(GameResolution.olderFitted(["Fullscreen": "True", "DesiredScreenWidth": "1512", "DesiredScreenHeight": "982",
                                          "FullscreenMode": "1", "LastConfirmedFullscreenMode": "1"],
                                         size: macBook) == ["Fullscreen": "False"], "True becomes False, the game's own word")
        check(GameResolution.unrealFitted(abzu.replacingOccurrences(of: "VSync=ON", with: "VSync=ON\r\nFullscreenMode=0"), size: macBook)?
                .contains("FullscreenMode=1") == true, "ABZU's kind with FullscreenMode 0 gets the full-screen window too, not the exclusive mode")
        check(GameResolution.olderFitted(["Fullscreen": "Borderless", "DesiredScreenWidth": "1280", "DesiredScreenHeight": "720"], size: macBook) == nil,
              "a word it doesn't know: left alone")
        let windowed = abzu.replacingOccurrences(of: "Fullscreen=ON", with: "Fullscreen=OFF")
        check(GameResolution.unrealFitted(windowed, size: macBook, screens: [macBook]) == nil
              && GameResolution.unrealFitted(windowed, size: tv, screens: [tv, macBook]) == nil,
              "a window the player chose (1280×720) stays as it is")
        check(GameResolution.unrealFitted("[/Script/Game.Settings]\nFullscreen=ON\nShadows=HIGH\n", size: tv) == nil,
              "the older kind without a stored size: nothing invented")
        check(GameResolution.unrealFitted(fixture("GameUserSettings-windowed.ini"), size: tv) == nil, "a windowed Unreal game stays a window")
        check(GameResolution.unrealFitted("[/Script/Engine.GameUserSettings]\nbUseVSync=False\n", size: tv) == nil,
              "no FullscreenMode yet (before the game's first start): nothing to go by")
        check(GameResolution.unrealFitted("[/Script/Engine.GameUserSettings]\nFullscreenMode=1\n", size: tv) == nil,
              "nothing invented: no resolution stored, none written")
    }

    /// A profile's own format (`GameProfile.resolution`): Mafia II's videoconfig.cfg and an .ini.
    static func ownFormat() {
        typealias Saved = GameProfile.SavedResolution
        let mafia = Saved(root: "WinAppDataLocal", path: "2K Games/Mafia II/Saves/videoconfig.cfg",
                          fields: .init(width: 2, height: 3, fullscreen: 4))

        // The live test on 1.11.: full screen at the MacBook's size, now on the 1080p TV alone.
        check(GameResolution.savedFitted(fixture("videoconfig-macbook.cfg"), mafia, size: tv) == "0 0 1920 1080 1 0 0 1",
              "Mafia II full screen at 1512×982 on the TV: 1920×1080, the other values kept")
        check(GameResolution.savedFitted(fixture("videoconfig-macbook.cfg"), mafia, size: macBook) == nil,
              "on the MacBook its own size stays")
        check(GameResolution.savedFitted(fixture("videoconfig-window.cfg"), mafia, size: tv) == nil,
              "in a window: left as the player chose")
        check(GameResolution.savedFitted(fixture("videoconfig-720p.cfg"), mafia, size: tv) == "0 0 1920 1080 1 0 0 1\r\n",
              "full screen at 1280×720, which the TV has: the TV's too – Wine gives a mode back when the game loses the front")
        // The monitor test on 1.11.: the TV's size left in the file, the game in a corner of the 2560×1440 monitor.
        check(GameResolution.savedFitted("0 0 1920 1080 1 0 0 1", mafia, size: Size(width: 2560, height: 1440)) == "0 0 2560 1440 1 0 0 1",
              "Mafia II after the TV, on a 2560×1440 monitor: the monitor's size")
        check(GameResolution.savedFitted("0 0 3024 1964 1 0 0 1\r\n", mafia, size: tv) == "0 0 1920 1080 1 0 0 1\r\n",
              "the Retina size from a stale session: fitted, the Windows line end kept")
        check(GameResolution.savedFitted("0 0 1512", mafia, size: tv) == nil, "too few values: nothing touched")
        check(GameResolution.savedFitted("", mafia, size: tv) == nil, "an empty file: nothing")
        check(GameResolution.savedFitted("0 0 wide 982 1 0 0 1", mafia, size: tv) == nil, "not a number: nothing")
        let alwaysFull = Saved(path: "res.txt", fields: .init(width: 0, height: 1))
        check(GameResolution.savedFitted("1512 982", alwaysFull, size: tv) == "1920 1080",
              "no full-screen value: a full-screen game")

        // An .ini file, with true/false.
        let ini = Saved(path: "settings.ini", section: "Video", keys: .init(width: "ResX", height: "ResY", fullscreen: "Fullscreen"),
                        fullscreenOn: ["true"])
        let text = fixture("settings-ini.ini")
        if let fitted = GameResolution.savedFitted(text, ini, size: tv) {
            let lines = fitted.components(separatedBy: "\r\n")
            check(lines.contains("ResX=1920") && lines.contains("ResY=1080"), "the .ini's width and height")
            check(lines.contains("Fullscreen=true") && lines.contains("VSync=1") && lines.contains("Volume=80"), "everything else stays")
            check(!fitted.contains("1512"), "no old size left")
        } else {
            check(false, "an .ini set to full screen at a size the TV lacks gets the TV's")
        }
        check(GameResolution.savedFitted(text.replacingOccurrences(of: "Fullscreen=true", with: "Fullscreen=false"), ini, size: tv) == nil,
              "an .ini set to a window stays")
    }

    /// Where the settings are found: app.info next to a Unity program, GameUserSettings.ini in the prefix.
    static func folders() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("game-resolution-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String = "") {
            let file = root.appendingPathComponent(path)
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }

        write("Overcooked2/Overcooked2.exe")
        write("Overcooked2/Overcooked2_Data/app.info", "Team17\nOvercooked2")
        write("Overcooked2/Overcooked2_Data/Managed/Assembly-CSharp.dll")
        check(GameResolution.unityKeys(installDir: root.appendingPathComponent("Overcooked2")) == [#"Software\Team17\Overcooked2"#],
              "Overcooked 2's key from its app.info")
        write("Nested/Game/Nested_Data/app.info", "Studio\nNested")
        check(GameResolution.unityKeys(installDir: root.appendingPathComponent("Nested")) == [#"Software\Studio\Nested"#],
              "a Unity program one folder down")
        check(GameResolution.unityKeys(installDir: root.appendingPathComponent("Missing")).isEmpty, "no Unity, no key")

        let prefix = root.appendingPathComponent("Prefix")
        let places = SaveTransfer.Places(prefix: prefix, windowsUser: "tester")
        let local = "Prefix/drive_c/users/tester/AppData/Local"
        write("Palworld/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe")
        write("Palworld/Engine/Binaries/Win64/CrashReportClient.exe")
        write("\(local)/Pal/Saved/Config/Windows/GameUserSettings.ini", "[/Script/Engine.GameUserSettings]")
        write("\(local)/Pal/Saved/Config/CrashReportClient/UECC-Windows-1/GameUserSettings.ini")
        write("\(local)/Engine/Saved/Config/Windows/GameUserSettings.ini")
        let pal = GameResolution.unrealSettings(installDir: root.appendingPathComponent("Palworld"), places: places)
        check(pal.map(\.path) == [prefix.appendingPathComponent("drive_c/users/tester/AppData/Local/Pal/Saved/Config/Windows/GameUserSettings.ini").path],
              "UE5: the project folder's settings, not the engine's or the crash reporter's (\(pal.map(\.lastPathComponent)))")

        write("Old Game/OldGame/Binaries/Win64/OldGame-Win64-Shipping.exe")
        write("Prefix/drive_c/users/tester/Documents/My Games/OldGame/Saved/Config/WindowsNoEditor/GameUserSettings.ini")
        check(GameResolution.unrealSettings(installDir: root.appendingPathComponent("Old Game"), places: places).count == 1,
              "UE4 in Documents\\My Games, WindowsNoEditor")
        write("Flat/Flat-Win64-Shipping.exe")
        write("\(local)/Flat/Saved/Config/Windows/GameUserSettings.ini")
        check(GameResolution.unrealSettings(installDir: root.appendingPathComponent("Flat"), places: places).count == 1,
              "the project named after its program")
        check(GameResolution.unrealSettings(installDir: root.appendingPathComponent("Overcooked2"), places: places).isEmpty,
              "a Unity game has no GameUserSettings.ini")

        // A folder the game links elsewhere isn't written through: the atomic write would land at its end.
        write("Outside/Saved/Config/Windows/GameUserSettings.ini", "[/Script/Engine.GameUserSettings]")
        write("Linked/Linked/Binaries/Win64/Linked-Win64-Shipping.exe")
        try? fm.createSymbolicLink(at: prefix.appendingPathComponent("drive_c/users/tester/AppData/Local/Linked"),
                                   withDestinationURL: root.appendingPathComponent("Outside"))
        check(GameResolution.unrealSettings(installDir: root.appendingPathComponent("Linked"), places: places).isEmpty,
              "Unreal's settings behind a project folder linked out of the prefix: left alone")
        typealias Saved = GameProfile.SavedResolution
        let mafia = Saved(root: "WinAppDataLocal", path: "2K Games/Mafia II/Saves/videoconfig.cfg", fields: .init(width: 2, height: 3))
        check(GameResolution.savedFile(mafia, installDir: root, places: places)?.path
              == prefix.appendingPathComponent("drive_c/users/tester/AppData/Local/2K Games/Mafia II/Saves/videoconfig.cfg").path,
              "a profile's file in its root")
        let linked = Saved(root: "WinAppDataLocal", path: "Linked/Saved/Config/Windows/GameUserSettings.ini", section: "S",
                           keys: .init(width: "W", height: "H"))
        check(GameResolution.savedFile(linked, installDir: root, places: places) == nil, "and none behind a link out of it")
        write("Game/settings.ini")
        try? fm.createSymbolicLink(at: root.appendingPathComponent("Game/Config"), withDestinationURL: root.appendingPathComponent("Outside"))
        let inGame = Saved(path: "settings.ini", section: "Video", keys: .init(width: "W", height: "H"))
        let throughLink = Saved(path: "Config/Saved/Config/Windows/GameUserSettings.ini", section: "Video", keys: .init(width: "W", height: "H"))
        check(GameResolution.savedFile(inGame, installDir: root.appendingPathComponent("Game"), places: places) != nil
              && GameResolution.savedFile(throughLink, installDir: root.appendingPathComponent("Game"), places: places) == nil,
              "in the game folder the same: its own file yes, one behind a link out no")
    }
}
