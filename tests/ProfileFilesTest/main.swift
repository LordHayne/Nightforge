// Checks iniSettings, fileEdits with a Windows root or `once`, the save folders a rule may name, the Retina mode a
// profile asks for, and the profile list Nightforge keeps (ProfileStore, in a home of the test's own, signed with a
// key of the test's own):
// tests/ProfileFilesTest/run.sh
import CryptoKit
import Foundation

@main
struct ProfileFilesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func profile(_ json: String) -> GameProfile? {
        try? JSONDecoder().decode(GameProfile.self, from: Data(json.utf8))
    }

    static func main() async {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("profile-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }

        // MARK: Decoding
        let decoded = profile("""
            {"retina": true,
             "iniSettings": [{"root": "WinAppDataLocal", "path": "Game/Engine.ini", "section": "SystemSettings", "values": {"r.Nanite": "0"}}],
             "fileEdits": [{"root": "WinAppDataLocal", "path": "Game/Settings.ini", "find": "A=1", "replace": "A=0", "once": true},
                           {"path": "b1/Settings.ini", "find": "B=1", "replace": "B=0"}]}
            """)
        check(decoded?.retina == true, "retina is read")
        let saved = profile(#"{"resolution": {"root": "WinAppDataLocal", "path": "2K Games/Mafia II/Saves/videoconfig.cfg", "fields": {"width": 2, "height": 3, "fullscreen": 4}}}"#)?.resolution
        check(saved?.root == "WinAppDataLocal" && saved?.fields?.width == 2 && saved?.fields?.fullscreen == 4 && saved?.keys == nil,
              "a resolution in a line of values is read")
        let savedIni = profile(#"{"resolution": {"path": "settings.ini", "section": "Video", "keys": {"width": "ResX", "height": "ResY"}, "fullscreenOn": ["true"]}}"#)?.resolution
        check(savedIni?.root == nil && savedIni?.keys?.height == "ResY" && savedIni?.keys?.fullscreen == nil && savedIni?.fullscreenOn == ["true"],
              "a resolution in an .ini is read")
        check(decoded?.iniSettings?.first?.values == ["r.Nanite": "0"], "iniSettings are read")
        check(decoded?.fileEdits?.first?.root == "WinAppDataLocal" && decoded?.fileEdits?.first?.once == true,
              "a file edit's root and once are read")
        check(decoded?.fileEdits?.last?.root == nil && decoded?.fileEdits?.last?.once == nil, "an edit without them keeps the game folder")
        check(decoded?.hasFixes == true, "these count as fixes")
        check(profile(#"{"retina": false}"#)?.hasFixes == false, "retina off changes nothing")

        // MARK: Merging into an .ini
        let fresh = Engine.mergingIni("", section: "SystemSettings", values: ["r.Shadow.Virtual.Enable": "0", "r.Nanite": "0"])
        check(fresh == "[SystemSettings]\nr.Nanite=0\nr.Shadow.Virtual.Enable=0\n", "a new file gets the section, keys sorted: \(fresh)")
        check(Engine.mergingIni(fresh, section: "SystemSettings", values: ["r.Nanite": "0", "r.Shadow.Virtual.Enable": "0"]) == fresh,
              "merging again changes nothing")
        let existing = "[Core.System]\r\nPaths=../x\r\n\r\n[SystemSettings]\r\nr.Nanite=1\r\nr.Other=5\r\n\r\n[Last]\r\nKey=1\r\n"
        let merged = Engine.mergingIni(existing, section: "systemsettings", values: ["r.Nanite": "0", "r.Tonemapper.Sharpen": "0.6"])
        check(merged == "[Core.System]\r\nPaths=../x\r\n\r\n[SystemSettings]\r\nr.Nanite=0\r\nr.Other=5\r\nr.Tonemapper.Sharpen=0.6\r\n\r\n[Last]\r\nKey=1\r\n",
              "a key is replaced, a new one goes at the section's end, other sections and line ends stay: \(merged.debugDescription)")
        let appended = Engine.mergingIni("[Other]\nA=1\n", section: "SystemSettings", values: ["r.Nanite": "0"])
        check(appended == "[Other]\nA=1\n\n[SystemSettings]\nr.Nanite=0\n", "a missing section is added at the end: \(appended.debugDescription)")
        // Names and values from a list go in plain: a line break, a bracket or "=" starts no line or section of its own.
        let injected = Engine.mergingIni("", section: "S]\n[Evil", values: ["a\n[Run]\nb": "1\n[Other]\nx=2", "c=d": "3\r\n", "e": "4\u{2028}5"])
        check(injected == "[SEvil]\naRunb=1[Other]x=2\ncd=3\ne=45\n", "section, keys and values made plain: \(injected.debugDescription)")
        check(Engine.mergingIni("[SEvil]\nk=1\n", section: "S\n[Evil]", values: ["k": "2"]) == "[SEvil]\nk=2\n",
              "and found again the next time")
        check(Engine.mergingIni("[A]\nx=1\n", section: "[]", values: ["k": "v"]) == "[A]\nx=1\n"
              && Engine.mergingIni("[A]\nx=1\n", section: "A", values: ["\n=": "v"]) == "[A]\nx=1\n",
              "a section or key that's nothing but those sets nothing")

        // MARK: Writing into the Windows user folder
        let places = SaveTransfer.Places(prefix: temp.appendingPathComponent("prefix", isDirectory: true), windowsUser: "tester")
        let local = places.prefix.appendingPathComponent("drive_c/users/tester/AppData/Local", isDirectory: true)
        try? fm.createDirectory(at: local, withIntermediateDirectories: true)
        let engineIni = local.appendingPathComponent("Voyage/Saved/Config/Windows/Engine.ini")
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "Voyage/Saved/Config/Windows/Engine.ini",
                                                        section: "SystemSettings", values: ["r.Nanite": "0"])], places: places)
        check((try? String(contentsOf: engineIni, encoding: .utf8)) == "[SystemSettings]\nr.Nanite=0\n",
              "the Engine.ini the game deleted is written again, folders and all")
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "../../../../escape.ini",
                                                        section: "S", values: ["a": "b"])], places: places)
        check(!fm.fileExists(atPath: places.prefix.appendingPathComponent("drive_c/escape.ini").path), "a path can't leave its root")
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinSomewhere", path: "x.ini", section: "S", values: ["a": "b"])], places: places)
        check((try? fm.contentsOfDirectory(atPath: local.path)) == ["Voyage"], "an unknown root writes nothing")

        // A link on the way that leads out (users\<name>\Documents once led to the Mac's own) isn't written through.
        let outside = temp.appendingPathComponent("outside", isDirectory: true)
        try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: local.appendingPathComponent("Linked"), withDestinationURL: outside)
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "Linked/Game/Engine.ini",
                                                        section: "S", values: ["a": "b"])], places: places)
        check((try? fm.contentsOfDirectory(atPath: outside.path)) == [], "no file and no folder behind a link out of the prefix")
        try? "[S]\na=1\n".write(to: outside.appendingPathComponent("existing.ini"), atomically: true, encoding: .utf8)
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "Linked/existing.ini",
                                                        section: "S", values: ["a": "b"])], places: places)
        check((try? String(contentsOf: outside.appendingPathComponent("existing.ini"), encoding: .utf8)) == "[S]\na=1\n",
              "nor is a file there changed")
        let linkedGame = temp.appendingPathComponent("linked-game", isDirectory: true)
        try? fm.createDirectory(at: linkedGame, withIntermediateDirectories: true)
        try? "B=1\n".write(to: outside.appendingPathComponent("Settings.ini"), atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: linkedGame.appendingPathComponent("Settings.ini"),
                                   withDestinationURL: outside.appendingPathComponent("Settings.ini"))
        check(!Engine.applyFileEdits([GameProfile.FileEdit(path: "Settings.ini", find: "B=1", replace: "B=0")], installDir: linkedGame)
              && (try? String(contentsOf: outside.appendingPathComponent("Settings.ini"), encoding: .utf8)) == "B=1\n",
              "an edit in the game folder doesn't follow a linked file out of it")
        try? fm.createSymbolicLink(at: local.appendingPathComponent("Gone"), withDestinationURL: temp.appendingPathComponent("gone"))
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "Gone/x.ini", section: "S", values: ["a": "b"])],
                                places: places)
        check(!fm.fileExists(atPath: temp.appendingPathComponent("gone").path), "a link that leads nowhere counts as outside")
        try? fm.createSymbolicLink(at: local.appendingPathComponent("Alias"), withDestinationURL: local.appendingPathComponent("Voyage"))
        Engine.applyIniSettings([GameProfile.IniSetting(root: "WinAppDataLocal", path: "Alias/Saved/Config/Windows/Engine.ini",
                                                        section: "SystemSettings", values: ["r.Other": "1"])], places: places)
        check((try? String(contentsOf: engineIni, encoding: .utf8))?.contains("r.Other=1") == true, "a link that stays inside is fine")
        check(Engine.isInside(local.appendingPathComponent("Voyage/new/x.ini"), local) && !Engine.isInside(local, local)
              && !Engine.isInside(local.appendingPathComponent("Linked/x.ini"), local), "inside, with what isn't there yet")
        for name in ["Linked", "Gone", "Alias"] { try? fm.removeItem(at: local.appendingPathComponent(name)) }
        // A user folder linked to a folder beside the prefix whose name starts the same isn't inside it.
        let beside = temp.appendingPathComponent("prefix-evil/Local", isDirectory: true)
        try? fm.createDirectory(at: beside, withIntermediateDirectories: true)
        let roaming = places.prefix.appendingPathComponent("drive_c/users/tester/AppData/Roaming")
        try? fm.createSymbolicLink(at: roaming, withDestinationURL: beside)
        check(SaveTransfer.windowsRoot("WinAppDataRoaming", places) == nil && SaveTransfer.windowsRoot("WinAppDataLocal", places)?.path == local.path,
              "\"prefix-evil\" beside the prefix isn't inside \"prefix\"; the real user folder is")
        try? fm.removeItem(at: roaming)

        // MARK: Edits in the user folder, once and every time
        let defaults = TestDefaults.suite("file-edits")
        let installDir = temp.appendingPathComponent("game", isDirectory: true)
        try? fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        let settings = local.appendingPathComponent("Voyage/Saved/Config/Windows/GameUserSettings.ini")
        let edits = [
            GameProfile.FileEdit(path: "Voyage/Saved/Config/Windows/GameUserSettings.ini", find: "UpscalingMethod=TSR",
                                 replace: "UpscalingMethod=FSR", root: "WinAppDataLocal", once: true),
            GameProfile.FileEdit(path: "Voyage/Saved/Config/Windows/GameUserSettings.ini", find: "bUseRayTracing=True",
                                 replace: "bUseRayTracing=False", root: "WinAppDataLocal"),
        ]
        func apply() -> Bool { Engine.applyFileEdits(edits, installDir: installDir, game: "steam.7", places: places, defaults: defaults) }
        func text() -> String { (try? String(contentsOf: settings, encoding: .utf8)) ?? "" }
        check(!apply(), "nothing to change before the game wrote its file")
        try? "CustomSettings=(UpscalingMethod=TSR,bUseRayTracing=True)\n".write(to: settings, atomically: true, encoding: .utf8)
        check(apply() && text() == "CustomSettings=(UpscalingMethod=FSR,bUseRayTracing=False)\n",
              "the first start that finds the file gets both: \(text())")
        try? "CustomSettings=(UpscalingMethod=TSR,bUseRayTracing=True)\n".write(to: settings, atomically: true, encoding: .utf8)
        check(apply() && text() == "CustomSettings=(UpscalingMethod=TSR,bUseRayTracing=False)\n",
              "after that the player's own upscaler stays, the fix applies every time: \(text())")
        let later = TestDefaults.suite("file-edits-later")
        try? "CustomSettings=(UpscalingMethod=DLSS)\n".write(to: settings, atomically: true, encoding: .utf8)
        _ = Engine.applyFileEdits(edits, installDir: installDir, game: "steam.8", places: places, defaults: later)
        try? "CustomSettings=(UpscalingMethod=TSR)\n".write(to: settings, atomically: true, encoding: .utf8)
        _ = Engine.applyFileEdits(edits, installDir: installDir, game: "steam.8", places: places, defaults: later)
        check(text() == "CustomSettings=(UpscalingMethod=TSR)\n",
              "a file found without the starting value still counts as the one chance: \(text())")
        let gameFile = installDir.appendingPathComponent("b1/Settings.ini")
        try? fm.createDirectory(at: gameFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "B=1\n".write(to: gameFile, atomically: true, encoding: .utf8)
        check(Engine.applyFileEdits([GameProfile.FileEdit(path: "b1/Settings.ini", find: "B=1", replace: "B=0")], installDir: installDir)
              && (try? String(contentsOf: gameFile, encoding: .utf8)) == "B=0\n", "edits in the game folder work as before")
        // One whose `replace` holds its `find` (a line added after it) is made once, not again at every start.
        try? "[Video]\nWidth=1\n".write(to: gameFile, atomically: true, encoding: .utf8)
        let adding = [GameProfile.FileEdit(path: "b1/Settings.ini", find: "[Video]\n", replace: "[Video]\nVSync=0\n")]
        check(Engine.applyFileEdits(adding, installDir: installDir)
              && (try? String(contentsOf: gameFile, encoding: .utf8)) == "[Video]\nVSync=0\nWidth=1\n", "the line goes in once")
        check(!Engine.applyFileEdits(adding, installDir: installDir) && !Engine.applyFileEdits(adding, installDir: installDir)
              && (try? String(contentsOf: gameFile, encoding: .utf8)) == "[Video]\nVSync=0\nWidth=1\n",
              "the next starts find it done: the file doesn't grow")
        check(Engine.editing("[Video]\nVSync=0\nA=1\n[Video]\nB=1\n", find: "[Video]\n", replace: "[Video]\nVSync=0\n")
              == "[Video]\nVSync=0\nA=1\n[Video]\nVSync=0\nB=1\n", "a place the game wrote since still gets it")
        check(Engine.editing("A=1\n", find: "A=1", replace: "A=1") == "A=1\n"
              && !Engine.applyFileEdits([GameProfile.FileEdit(path: "b1/Settings.ini", find: "Width=1", replace: "Width=1")], installDir: installDir),
              "an edit that changes nothing writes nothing")

        // MARK: Save folders a rule may name (SaveTransfer: rules from Steam's catalog and the profiles)
        saveFolders(temp)

        // MARK: Retina mode starts a new Steam session
        Engine.launchEnvironment = [:]
        Engine.launchRetina = false
        _ = Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true)
        let plain = Engine.steamConfigSignature
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, retina: true),
              "a game that wants Retina restarts a Steam without it")
        check(Engine.launchRetina && Engine.steamConfigSignature == plain + "-retina", "and Steam's signature says so")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, retina: true),
              "the next Retina game keeps it")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true),
              "a game without it restarts it again")
        check(!Engine.launchRetina && Engine.steamConfigSignature == plain, "and the signature is as before Retina")

        // MARK: D3DMetal profiles need the engine that carries it
        let components = temp.appendingPathComponent("Components", isDirectory: true)
        func engine(_ id: String, _ version: String, age: TimeInterval) -> URL {
            let wine = components.appendingPathComponent("\(id)/\(version)/Libraries/Wine/bin/wine")
            try? fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: wine.path, contents: Data(), attributes: [.posixPermissions: 0o755])
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)],
                                  ofItemAtPath: components.appendingPathComponent("\(id)/\(version)").path)
            return wine
        }
        let winecx = engine("winecx", "4.7.3", age: 3600).resolvingSymlinksInPath()
        let gcenx = engine("wine", "11.18", age: 60).resolvingSymlinksInPath()  // touched later, as on the test Mac
        func found(_ list: ComponentManifest?) -> URL? { Engine.installedWineNow(root: components, manifest: list)?.resolvingSymlinksInPath() }
        func manifest(_ ids: [String]) -> ComponentManifest? {
            let entries = ids.map { #"{"id": "\#($0)", "kind": "engine", "version": "1", "url": "https://example.com/e.tar.xz", "sha256": "", "size": 1, "license": "", "source": "https://example.com"}"# }
            return try? JSONDecoder().decode(ComponentManifest.self,
                                             from: Data(#"{"schemaVersion": 1, "generated": "", "components": [\#(entries.joined(separator: ","))]}"#.utf8))
        }
        check(found(manifest(["wine", "winecx"])) == winecx,
              "the list's engine wins over a younger folder of the old one")
        check(found(nil) == winecx, "without a list, winecx first")
        check(found(manifest(["wine"])) == gcenx, "a list with Gcenx's engine only keeps it")
        try? fm.removeItem(at: components.appendingPathComponent("winecx"))
        check(found(manifest(["wine", "winecx"])) == gcenx,
              "winecx not unpacked yet: the engine that is there")

        // MARK: Decoding what a newer or odd list holds
        let odd = profile(#"{"graphics": "metal5", "winetricks": "xact", "arguments": ["-dx11"], "frameLimit": "sixty"}"#)
        check(odd?.graphics == nil && odd?.winetricks == nil && odd?.frameLimit == nil && odd?.arguments == ["-dx11"],
              "an unknown layer or a wrong type is no preference; the rest stays")
        let saves = profile(#"{"saves": [{"root": "WinAppDataLocal", "path": "Game/Saved", "mac": "MacAppSupport"},"#
                            + #"{"root": "WinMyDocuments", "path": "My Games", "pattern": "*.sav", "recursive": false, "mac": "MacDocuments", "macPath": "Game"}]}"#)?.saves
        check(saves == [SaveRule(root: "WinAppDataLocal", path: "Game/Saved", pattern: "*", recursive: true, macRoot: "MacAppSupport", macAddPath: ""),
                        SaveRule(root: "WinMyDocuments", path: "My Games", pattern: "*.sav", recursive: false, macRoot: "MacDocuments", macAddPath: "Game")],
              "save folders: every file, all the way down, unless the list says otherwise")
        check(profile(#"{"saves": [{"root": "WinAppDataLocal"}]}"#)?.saves == nil, "a save folder without its path is none")

        // DLL overrides and arguments only as scripts/build-profiles.py lets them through: a list signed
        // without its CI meets the same rules (the expectations are what its functions say).
        func listed(_ object: [String: Any]) -> GameProfile? {
            profile(String(data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), encoding: .utf8) ?? "")
        }
        let overrides = listed(["dllOverrides": ["d3d9": "native", "*xinput1_3": "native,builtin", "nvapi64": "", "ntdll": "native",
                                                 "kernel32.dll": "builtin", "*user32": "native", "../x": "native", "D3D11": "native",
                                                 "dxgi": "n", "a b": "native", "x..y": "native", "winemac.drv": "native"]])?.dllOverrides
        check(overrides == ["d3d9": "native", "*xinput1_3": "native,builtin", "nvapi64": ""],
              "overrides: bare lowercase names with Wine's orders pass; Wine's core, paths, odd orders don't: \(overrides ?? [:])")
        check(listed(["dllOverrides": Dictionary(uniqueKeysWithValues: (0...32).map { ("dll\($0)", "native") })])?.dllOverrides == nil,
              "more overrides than the build ever makes: none")
        let plainArguments = ["-dx11", "--bundle-dir", "../bundle", "+r_renderAPI", "1", "/dx11", "-vomstyle=layer", "glide_fix.conf"]
        check(listed(["arguments": plainArguments])?.arguments == plainArguments, "plain arguments pass")
        for bad in ["/etc/passwd", "-log=/tmp/x/y", "C:\\x", "a b", "--data=../../x", "~/x", "//server/x", "-x=\"y\"", "a/../b", "",
                    String(repeating: "x", count: 65), "-\n"] {
            check(listed(["arguments": ["-windowed", bad]])?.arguments == nil, "arguments with \(bad.debugDescription): none of them")
        }
        check(listed(["arguments": Array(repeating: "-x", count: 17)])?.arguments == nil, "more arguments than the build ever makes: none")
        // A frame limit and a sampler count within what a game can use.
        check([30, 0, -5, 1000].map { listed(["frameLimit": $0])?.frameLimit } == [30, 0, nil, 240],
              "frame limit: 30 stays, 0 is none, below that no preference, above 240 it's 240")
        check([32, 0, -1, 4096].map { listed(["vulkanSamplers": $0])?.vulkanSamplers } == [32, nil, nil, 128],
              "samplers: 32 stays, below 1 no preference, above 128 it's 128")
        let stream = AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: "e1b2c3")
        check(stream.geforceNowURL?.absoluteString == "https://play.geforcenow.com/games?game-id=e1b2c3&utm_source=nightforge&utm_campaign=library",
              "GeForce Now's link to the game: \(stream.geforceNowURL?.absoluteString ?? "nil")")
        check(AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: nil).geforceNowURL == nil, "no game ID, no link")
        check(profile(#"{"notYet": "Hangs under Rosetta."}"#)?.notYet == "Hangs under Rosetta.", "the reason a game doesn't start yet is read")
        check(profile(#"{"notYet": ""}"#)?.notYet == nil && profile(#"{"notYet": 5, "note": "x"}"#)?.notYet == nil
              && profile(#"{"note": "x"}"#)?.notYet == nil, "an empty or odd reason is none; the rest of the entry stays")

        // MARK: The profile list Nightforge keeps
        // Only in a home of the test's own (run.sh): never the player's Application Support.
        let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        if Engine.supportDir.path.hasPrefix(realHome + "/") {
            check(false, "the profile list would be the player's own (\(Engine.supportDir.path)): run through run.sh")
        } else {
            await profileStore()
        }

        // MARK: The Last Caretaker Demo's profile
        let list = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        let games = list.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["games"] as? [String: Any]
        let demo = (games?["3916150"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(GameProfile.self, from: $0) }
        check(demo?.graphics == .d3dmetal && demo?.avx == false && demo?.retina == true, "the demo runs on D3DMetal without AVX, in Retina")
        check(demo?.iniSettings?.first?.values["r.Nanite"] == "0" && demo?.iniSettings?.first?.values["r.Shadow.Virtual.Enable"] == "0",
              "Nanite and virtual shadow maps go off")
        check(demo?.fileEdits?.contains { $0.find == "bUseRayTracing=True" && $0.once == nil } == true, "ray tracing stays off")
        check(demo?.fileEdits?.contains { $0.find == "UpscalingMethod=TSR" && $0.replace == "UpscalingMethod=FSR" && $0.once == true } == true,
              "FSR is where it starts")
        let unreal = GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal)
        check(LaunchHealth.attempts(for: unreal, profile: demo, d3dMetal: true).first == LaunchAttempt(graphics: .d3dmetal),
              "the demo starts on DirectX 12 through D3DMetal, without -dx11")
        check(demo.map { $0.fromNightforge && Compatibility.rate(.init(profile: $0, analysis: unreal)).level == .great } == true,
              "tested on a Mac: it runs great")

        // MARK: Mafia II, on Steam and on GOG
        let steamMafia = games?["50130"] as? [String: Any]
        check(steamMafia.map { NSDictionary(dictionary: $0).isEqual(to: games?["gog.1816059595"] as? [String: Any] ?? [:]) } == true,
              "the GOG version (1816059595) has the Steam version's profile")
        check(steamMafia?["gog"] == nil, "the twin list stays out of the profile itself")
        let mafia = list.flatMap { try? Data(contentsOf: $0) }.map(ProfileStore.decodeGOG)?["1816059595"]
        check(mafia?.graphics == .wined3d && mafia?.fromNightforge == true, "Mafia II on GOG: tested on a Mac, WineD3D")
        let d3d9 = GameAnalysis(apis: [.d3d9])
        check(LaunchHealth.attempts(for: d3d9, profile: mafia, vulkanLayer: false, kosmicKrisp: false).first == LaunchAttempt(graphics: .wined3d),
              "on winecx it starts with WineD3D, which MoltenVK's missing geometry shaders leave as the way")
        check(LaunchHealth.ladder(LaunchHealth.attempts(for: d3d9, profile: mafia, vulkanLayer: true, kosmicKrisp: false), preset: .compatible,
                                  profile: mafia).first == LaunchAttempt(graphics: .wined3d),
              "Most compatible starts with the tested way")

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The list in Application Support (the test's own home), as the online copy left it: with its
    /// signature beside it.
    static func profileStore() async {
        let fm = FileManager.default
        let cached = Engine.supportDir.appendingPathComponent("profiles.json")
        try? fm.createDirectory(at: Engine.supportDir, withIntermediateDirectories: true)
        let signer = Curve25519.Signing.PrivateKey()
        let keys = [signer.publicKey.rawRepresentation.base64EncodedString()]
        func keep(_ data: Data, signedBy key: Curve25519.Signing.PrivateKey? = nil) {
            try? data.write(to: cached)
            try? (key ?? signer).signature(for: data).base64EncodedString().write(to: Signature.file(for: cached), atomically: true, encoding: .utf8)
        }
        let list = #"""
            {"formatVersion": 1, "games": {
              "570": {"name": "Dota 2", "preferWindows": true},
              "730": {"antiCheat": ["VAC"], "geforceNow": "g730"},
              "440": {"antiCheatOnline": ["Easy Anti-Cheat"]},
              "100": {"antiCheat": [], "antiCheatOnline": []},
              "300": "an entry from a newer list",
              "Sugar": {"name": "not a Steam app ID"},
              "2357570": {"name": "Overwatch", "notYet": "Hangs under Rosetta.", "geforceNow": "gOw"},
              "2": {"notYet": "Both say it.", "antiCheat": ["BattlEye"]},
              "epic.Sugar": {"antiCheat": ["Easy Anti-Cheat"], "geforceNow": "gSugar"},
              "epic.Online": {"antiCheatOnline": ["BattlEye"]},
              "epic.Later": {"notYet": "Needs a newer engine."},
              "epic.Fine": {"note": "Tested on M5"}}}
            """#
        keep(Data(list.utf8))
        let store = ProfileStore(keys: keys)
        let known = await store.knownProfiles()
        check(Set(known.keys) == [570, 730, 440, 100, 2357570, 2], "Steam games by app ID; an odd entry costs only itself: \(known.keys.sorted())")
        check(await store.preferWindows() == [570], "kept on the Windows version")
        check(await store.antiCheatBlocks() == [730: AntiCheatBlock(antiCheat: ["VAC"], geforceNow: "g730"),
                                                440: AntiCheatBlock(antiCheat: ["Easy Anti-Cheat"], geforceNow: nil, onlineOnly: true),
                                                2357570: AntiCheatBlock(antiCheat: [], geforceNow: "gOw", notYet: "Hangs under Rosetta."),
                                                2: AntiCheatBlock(antiCheat: [], geforceNow: nil, notYet: "Both say it.")],
              "what anti-cheat stops, online only or not; an empty list stops nothing; a reason it doesn't start yet comes first")
        check(await store.epicAntiCheatBlocks() == ["Sugar": AntiCheatBlock(antiCheat: ["Easy Anti-Cheat"], geforceNow: "gSugar"),
                                                    "Online": AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: nil, onlineOnly: true),
                                                    "Later": AntiCheatBlock(antiCheat: [], geforceNow: nil, notYet: "Needs a newer engine.")],
              "Epic games by catalog namespace")
        let dota = await store.profile(for: 570), unknown = await store.profile(for: 1)
        check(dota?.name == "Dota 2" && unknown == nil, "a game's profile, with no online copy to ask (the test has no app bundle)")

        // A list too new for this Nightforge is no list: nothing, rather than a misread one.
        keep(Data(list.replacingOccurrences(of: #""formatVersion": 1"#, with: #""formatVersion": 2"#).utf8))
        check(await ProfileStore(keys: keys).knownProfiles().isEmpty, "a newer format isn't read")
        check(ProfileStore.decodeEpic(Data(list.replacingOccurrences(of: #""formatVersion": 1"#, with: #""formatVersion": 2"#).utf8)).isEmpty
              && ProfileStore.decodeEpic(Data("not json".utf8)).isEmpty, "nor its Epic entries, nor a broken file")
        keep(Data("{".utf8))
        check(await ProfileStore(keys: keys).antiCheatBlocks().isEmpty, "a broken file: nothing stopped")

        // The list bundled with the app against the one fetched before: the one built later counts.
        let bundled = Engine.supportDir.appendingPathComponent("bundled.json")
        func dated(_ generated: String?, _ name: String, format: Int = 1) -> Data {
            Data((#"{"formatVersion": \#(format), "# + (generated.map { #""generated": "\#($0)", "# } ?? "")
                  + #""games": {"50130": {"name": "\#(name)"}}}"#).utf8)
        }
        func mafia() async -> String? { await ProfileStore(bundledURL: bundled, keys: keys).knownProfiles()[50130]?.name }
        try? dated("2026-10-27T20:21:54Z", "bundled").write(to: bundled)
        keep(dated("2026-10-26T16:32:00Z", "cached"))
        check(await mafia() == "bundled", "an older cached list: the bundled one counts")
        keep(dated("2026-11-01T04:37:00Z", "cached"))
        check(await mafia() == "cached", "a newer cached list counts")
        keep(dated("2026-10-27T20:21:54Z", "cached"))
        check(await mafia() == "cached", "one from the same run too")
        // Only a signed list counts: one without its signature (fetched by 0.3.0), signed with another
        // key, or changed on disk after signing gives way to the bundled one.
        let newer = dated("2026-11-01T04:37:00Z", "cached")
        keep(newer)
        try? fm.removeItem(at: Signature.file(for: cached))
        check(await mafia() == "bundled", "a cached list without its signature: the bundled one counts")
        keep(newer, signedBy: Curve25519.Signing.PrivateKey())
        check(await mafia() == "bundled", "nor one signed with a stranger's key")
        keep(newer)
        try? dated("2026-11-01T04:37:00Z", "changed").write(to: cached)
        check(await mafia() == "bundled", "nor one changed after signing")
        keep(newer)
        check(await mafia() == "cached", "signed again, it counts again")
        keep(dated(nil, "cached"))
        check(await mafia() == "bundled", "a cached list without a date counts as older")
        keep(dated("2026-10-26T16:32:00Z", "cached"))
        try? dated("2026-12-01T00:00:00Z", "bundled", format: 2).write(to: bundled)
        check(await mafia() == "cached", "a bundled list this Nightforge can't read: the cached one still serves")
        try? fm.removeItem(at: bundled)
        try? fm.removeItem(at: cached)
        try? fm.removeItem(at: Signature.file(for: cached))
        check(await ProfileStore(keys: keys).preferWindows().isEmpty, "no list at all")
    }

    /// A save rule never names a root itself: `takeNewer` empties a save folder of what the other side lacks.
    static func saveFolders(_ temp: URL) {
        let fm = FileManager.default
        func rule(_ root: String, _ path: String, _ pattern: String = "*", recursive: Bool = true,
                  mac: String? = "MacAppSupport", macPath: String = "") -> SaveRule {
            SaveRule(root: root, path: path, pattern: pattern, recursive: recursive, macRoot: mac, macAddPath: macPath)
        }
        let all = rule("WinAppDataRoaming", "")
        check(!SaveTransfer.isSaveFolder("", root: "MacAppSupport", all) && !SaveTransfer.isSaveFolder("/", root: "MacCaches", all)
              && !SaveTransfer.isSaveFolder("./", root: "WinAppDataRoaming", all), "a root itself, never")
        check(SaveTransfer.isSaveFolder("/7DaysToDie/Saves", root: "MacAppSupport", all) && SaveTransfer.isSaveFolder("Game", root: "WinAppDataRoaming", all),
              "a folder below one")
        check(SaveTransfer.isSaveFolder("", root: "GameInstall", rule("GameInstall", "", "*.sav", recursive: false)),
              "the game's own folder, for its saves")
        check(!SaveTransfer.isSaveFolder("", root: "gameinstall", rule("GameInstall", "")) && !SaveTransfer.isSaveFolder("", root: "GameInstall", rule("GameInstall", "", "*.*")),
              "but not all of it")
        check(!SaveTransfer.isSaveFolder("Game/../..", root: "MacAppSupport", all), "nothing that climbs out")

        // The Windows version's saves are newer; Application Support holds other apps' files too.
        let prefix = temp.appendingPathComponent("saves-prefix", isDirectory: true)
        let home = temp.appendingPathComponent("saves-home", isDirectory: true)
        let roaming = prefix.appendingPathComponent("drive_c/users/player/AppData/Roaming", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        func write(_ text: String, _ url: URL, hoursAgo: Double) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-hoursAgo * 3600)], ofItemAtPath: url.path)
        }
        write("new", roaming.appendingPathComponent("loose.sav"), hoursAgo: 0)
        write("new", roaming.appendingPathComponent("Game/Saves/slot1.sav"), hoursAgo: 0)
        let others = [support.appendingPathComponent("OtherApp/library.db"), support.appendingPathComponent("loose.plist"),
                      home.appendingPathComponent("Library/Caches/cache.db")]
        for file in others { write("someone else's", file, hoursAgo: 5) }
        let oldSave = support.appendingPathComponent("Game/Saves/slot0.sav")
        write("old", oldSave, hoursAgo: 5)
        let places = SaveTransfer.Places(prefix: prefix, windowsUser: "player", windowsInstall: nil, macHome: home, macInstall: nil)
        let backup = temp.appendingPathComponent("saves-backup", isDirectory: true)
        for (dangerous, name) in [(all, "all of Roaming onto Application Support"),
                                  (rule("WinAppDataRoaming", "", recursive: false), "Roaming's files onto Application Support's"),
                                  (rule("WinAppDataRoaming", "", mac: "MacCaches"), "onto Caches"),
                                  (rule("WinAppDataRoaming", "", "*.*"), "with *.*")] {
            check(SaveTransfer.newerElsewhere(to: .mac, rules: [dangerous], places: places) == nil, "\(name): nothing to ask about")
            let taken = (try? SaveTransfer.takeNewer(to: .mac, rules: [dangerous], places: places, backup: backup)) ?? -1
            check(taken == 0, "\(name): nothing taken (\(taken))")
        }
        check((try? SaveTransfer.takeNewer(to: .windows, rules: [all], places: places, backup: backup)) == 0, "nor the other way round")
        check(others.allSatisfy { fm.fileExists(atPath: $0.path) } && fm.fileExists(atPath: oldSave.path) && !fm.fileExists(atPath: backup.path),
              "takeNewer deleted and backed up nothing at a root")

        // The same saves named below the root: the old ones go to the backup, the newer ones come over.
        let taken = (try? SaveTransfer.takeNewer(to: .mac, rules: [rule("WinAppDataRoaming", "Game/Saves")], places: places, backup: backup)) ?? -1
        check(taken == 1 && fm.fileExists(atPath: support.appendingPathComponent("Game/Saves/slot1.sav").path) && !fm.fileExists(atPath: oldSave.path)
              && fm.fileExists(atPath: backup.appendingPathComponent("WinAppDataRoaming/Game/Saves/slot0.sav").path)
              && others.allSatisfy { fm.fileExists(atPath: $0.path) }, "a save folder below the root still works: \(taken)")
    }
}
