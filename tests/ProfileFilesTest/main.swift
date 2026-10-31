// Checks iniSettings, fileEdits with a Windows root or `once`, and the Retina mode a profile asks
// for: tests/ProfileFilesTest/run.sh
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

    static func main() {
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

        // MARK: Edits in the user folder, once and every time
        let defaults = UserDefaults(suiteName: "ProfileFilesTest-\(UUID().uuidString)")!
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
        let later = UserDefaults(suiteName: "ProfileFilesTest-\(UUID().uuidString)")!
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
        check(LaunchHealth.attempts(for: d3d9, profile: mafia, vulkanLayer: false).first == LaunchAttempt(graphics: .wined3d),
              "on winecx it starts with WineD3D, which MoltenVK's missing geometry shaders leave as the way")
        check(LaunchHealth.ladder(LaunchHealth.attempts(for: d3d9, profile: mafia, vulkanLayer: true), preset: .compatible,
                                  profile: mafia).first == LaunchAttempt(graphics: .wined3d),
              "Most compatible starts with the tested way")

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
