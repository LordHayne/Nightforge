// Checks which Unity games get "Play!" pressed in Unity's configuration window (UnityDialog), from their
// files: the window's picture, app.info, the Unity version in the data's first bytes; the switch, the
// profile field and the starts that bring the program along: tests/UnityDialogTest/run.sh
// (The program itself under Wine: tests/UnityDialogTest/dialog.sh.)
import Foundation

@main
struct UnityDialogTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("unity-dialog-\(UUID().uuidString)")

    static func main() {
        defer { try? FileManager.default.removeItem(at: root) }
        appInfo()
        versions()
        folders()
        arguments()
        switchAndProfile()
        starts()
        if failures == 0 { print("✓ UnityDialog: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }

    static func appInfo() {
        check(UnityDialog.product(appInfo: "SKS\nTheForest") == "TheForest", "The Forest's app.info: its product")
        check(UnityDialog.product(appInfo: "Team17\r\nOvercooked 2\r\n") == "Overcooked 2", "Windows line ends, spaces kept")
        check(UnityDialog.product(appInfo: "SKS") == nil, "no second line")
        check(UnityDialog.product(appInfo: "SKS\n  \n") == nil, "an empty product")
        check(UnityDialog.product(appInfo: "SKS\nThe\u{1}Forest") == nil, "a control character")
        check(UnityDialog.product(appInfo: "SKS\n" + String(repeating: "x", count: 201)) == nil, "a very long one")
        check(UnityDialog.product(appInfo: "Studio\nゲーム") == "ゲーム", "a product in another script")
    }

    static func header(_ before: [UInt8], _ version: String, _ after: [UInt8] = [0x13, 0, 0, 0]) -> Data {
        Data(before) + Data(version.utf8) + Data([0]) + Data(after)
    }

    static func versions() {
        // The Forest's TheForest_Data/globalgamemanagers, its first 32 bytes (format 17).
        let forest = header([0, 0, 7, 14, 0, 0x5d, 0xdc, 0x7c, 0, 0, 0, 0x11, 0, 0, 0x10, 0, 0, 0, 0, 0], "5.6.5p4")
        check(UnityDialog.unityVersion(header: forest).map { [$0.major, $0.minor] } == [5, 6], "The Forest: Unity 5.6")
        let vr = header([0, 0, 7, 18, 0, 0x5e, 0x6b, 0x54, 0, 0, 0, 0x11, 0, 0, 0x10, 0, 0, 0, 0, 0], "2017.4.30f1")
        check(UnityDialog.unityVersion(header: vr).map { [$0.major, $0.minor] } == [2017, 4], "its VR version: 2017.4")
        // Format 22 (Unity 2020.1 on): the version 48 bytes in.
        let newer = header(Array(repeating: 0, count: 48), "2022.3.10f1")
        check(UnityDialog.unityVersion(header: newer).map { [$0.major, $0.minor] } == [2022, 3], "a newer header: 2022.3")
        // A data.unity3d bundle: "UnityFS", its format, "5.x.x", then the version.
        let bundle = Data("UnityFS".utf8) + Data([0, 0, 0, 0, 6]) + Data("5.x.x".utf8) + Data([0]) + Data("2019.4.1f1".utf8) + Data([0])
        check(UnityDialog.unityVersion(header: bundle).map { [$0.major, $0.minor] } == [2019, 4], "a bundle: past its 5.x.x")
        check(UnityDialog.unityVersion(header: Data("MZ\u{90}\0This program".utf8)) == nil, "no version in it")
        check(UnityDialog.unityVersion(header: Data()) == nil, "an empty file")

        check(UnityDialog.hasWindow((5, 6)) && UnityDialog.hasWindow((2017, 4)) && UnityDialog.hasWindow((2019, 2)),
              "up to 2019.2 the window can come up")
        check(!UnityDialog.hasWindow((2019, 3)) && !UnityDialog.hasWindow((2020, 1)) && !UnityDialog.hasWindow((6000, 0)),
              "2019.3 dropped it")
    }

    /// A Unity program in `folder`: <name>.exe beside <name>_Data with what's given.
    static func program(_ name: String, in folder: URL, picture: Bool = true, exe: Bool = true,
                        appInfo: String? = "SKS\nTheForest", version: String? = "5.6.5p4") {
        let fm = FileManager.default
        let data = folder.appendingPathComponent(name + "_Data", isDirectory: true)
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        if exe { try? Data("MZ".utf8).write(to: folder.appendingPathComponent(name + ".exe")) }
        if picture { try? Data("BM".utf8).write(to: data.appendingPathComponent("ScreenSelector.bmp")) }
        if let appInfo { try? Data(appInfo.utf8).write(to: data.appendingPathComponent("app.info")) }
        if let version {
            try? header(Array(repeating: 0, count: 20), version).write(to: data.appendingPathComponent("globalgamemanagers"))
        }
    }

    static func folders() {
        // The Forest: three programs, each with the window's picture; the VR one is Unity 2017.4.
        let forest = root.appendingPathComponent("The Forest", isDirectory: true)
        program("TheForest", in: forest)
        program("TheForest32", in: forest)
        program("TheForestVR", in: forest, version: "2017.4.30f1")
        try? Data().write(to: forest.appendingPathComponent("UnityPlayer.dll"))
        let found = UnityDialog.programs(installDir: forest)
        check(found.map(\.executable) == ["TheForest.exe", "TheForest32.exe", "TheForestVR.exe"],
              "The Forest: all three programs (\(found.map(\.executable)))")
        check(found.allSatisfy { $0.product == "TheForest" }, "with app.info's product")

        // Oxygen Train: newer Unity, no picture.
        let train = root.appendingPathComponent("Oxygen Train", isDirectory: true)
        program("OxygenTrain", in: train, picture: false, version: "2022.3.21f1")
        check(UnityDialog.programs(installDir: train).isEmpty, "no picture: no window")

        let newer = root.appendingPathComponent("Newer", isDirectory: true)
        program("Newer", in: newer, version: "2019.4.40f1")
        check(UnityDialog.programs(installDir: newer).isEmpty, "a picture left over from 2019.4: no window")

        let unknown = root.appendingPathComponent("Unknown", isDirectory: true)
        program("Unknown", in: unknown, appInfo: "Studio\nUnknown", version: nil)
        check(UnityDialog.programs(installDir: unknown) == [UnityDialog.Program(executable: "Unknown.exe", product: "Unknown")],
              "a version that can't be read: the picture decides")

        let noProgram = root.appendingPathComponent("No program", isDirectory: true)
        program("Gone", in: noProgram, exe: false)
        check(UnityDialog.programs(installDir: noProgram).isEmpty, "no program beside the data")

        let noInfo = root.appendingPathComponent("No info", isDirectory: true)
        program("NoInfo", in: noInfo, appInfo: nil)
        check(UnityDialog.programs(installDir: noInfo).isEmpty, "no app.info: no title to look for")

        // One folder down, where some games keep their program.
        let deeper = root.appendingPathComponent("Deeper", isDirectory: true)
        program("Deep", in: deeper.appendingPathComponent("Bin", isDirectory: true), appInfo: "Studio\nDeep Game")
        check(UnityDialog.programs(installDir: deeper) == [UnityDialog.Program(executable: "Deep.exe", product: "Deep Game")],
              "a program one folder down")

        check(UnityDialog.programs(installDir: root.appendingPathComponent("Missing")).isEmpty, "a folder that isn't there")
        // GameResolution's registry keys still come from the same folders.
        check(GameResolution.unityKeys(installDir: forest) == [#"Software\SKS\TheForest"#], "GameResolution's key for The Forest")
        check(GameResolution.unityKeys(installDir: deeper) == [#"Software\Studio\Deep Game"#], "and one folder down")
    }

    static func arguments() {
        let programs = [UnityDialog.Program(executable: "TheForest.exe", product: "TheForest"),
                        UnityDialog.Program(executable: "TheForestVR.exe", product: "TheForest")]
        check(UnityDialog.arguments(programs, seconds: 180) == ["180", "TheForest.exe", "TheForest", "TheForestVR.exe", "TheForest"],
              "seconds, then program and product in pairs")
        // Only the programs' names: with the game's folder in it, its command line would count as the game's own.
        check(!UnityDialog.arguments(programs, seconds: 180).contains { $0.contains("\\") || $0.contains("/") },
              "no folders in its command line")
    }

    static func profile(_ json: String) -> GameProfile? {
        try? JSONDecoder().decode(GameProfile.self, from: Data(json.utf8))
    }

    static func switchAndProfile() {
        check(UnityDialog.switchKey == "unityDialogPlay", "the switch's name, as docs/TODO.md gives it")
        // On for everyone since the live test (3.11.), with a way out.
        // In the test's work folder (TestDefaults): a named suite left a plist in ~/Library/Preferences after every run.
        do {
            let defaults = TestDefaults.suite("unity-dialog")
            check(UnityDialog.enabled(in: defaults), "on unless switched off")
            defaults.set(false, forKey: UnityDialog.switchKey)
            check(!UnityDialog.enabled(in: defaults), "`defaults write … unityDialogPlay -bool false` turns it off")
            defaults.set(true, forKey: UnityDialog.switchKey)
            check(UnityDialog.enabled(in: defaults), "and true keeps it on")
        }
        check(profile(#"{"skipUnityDialog": false}"#)?.skipUnityDialog == false, "a profile keeps the window")
        check(profile(#"{"skipUnityDialog": true}"#)?.skipUnityDialog == true, "or says so")
        check(profile(#"{"name": "Game"}"#)?.skipUnityDialog == nil, "nothing said")
        check(profile(#"{"skipUnityDialog": "no"}"#)?.skipUnityDialog == nil, "something odd is nothing said")

        let forest = root.appendingPathComponent("The Forest", isDirectory: true)
        let game = Game(appID: 242_760, name: "The Forest", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: forest, sizeOnDisk: 0)
        check(UnityDialog.programs(for: game, profile: nil, enabled: false).isEmpty, "switch off: nothing")
        check(UnityDialog.programs(for: game, profile: nil, enabled: true).count == 3, "switch on: The Forest's programs")
        check(UnityDialog.programs(for: game, profile: profile(#"{"skipUnityDialog": true}"#), enabled: true).count == 3,
              "a profile that says so changes nothing")
        check(UnityDialog.programs(for: game, profile: profile(#"{"skipUnityDialog": false}"#), enabled: true).isEmpty,
              "a profile that keeps the window: nothing")
        let crossOver = Game(appID: 242_760, name: "The Forest", bottle: Bottle(name: "Games", url: URL(fileURLWithPath: "/tmp/Games")),
                             steamRoot: URL(fileURLWithPath: "/tmp/Games"), steamExeWindowsPath: "", installDir: forest, sizeOnDisk: 0)
        check(UnityDialog.programs(for: crossOver, profile: nil, enabled: true).isEmpty, "a CrossOver bottle: not Nightforge's session")
    }

    /// Both starts of a Windows game bring the program along, after the game's own start.
    static func starts() {
        let launcher = (try? String(contentsOf: URL(fileURLWithPath: "Sources/Nightforge/Launcher.swift"), encoding: .utf8)) ?? ""
        let starts = launcher.components(separatedBy: "try process.run()\n").dropFirst()
        check(starts.count == 2, "Launcher has two starts (\(starts.count))")
        check(starts.allSatisfy { $0.contains("UnityDialog.start(for: game, profile: profile, wine: runner)\n        return process") },
              "each starts the program right after the game")
    }
}
