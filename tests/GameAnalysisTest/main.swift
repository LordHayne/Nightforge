// Checks GameAnalysis on game folders made up of small Windows programs: the graphics interfaces
// read from their import tables, Unity, Unreal and Source, anti-cheat, .NET, other launchers, and
// what it leaves out (installers, crash reporters, upscalers, files too deep): tests/GameAnalysisTest/run.sh
import Foundation

@main
struct GameAnalysisTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A Windows program that imports `imports` at start and `delayed` on first use. 32-bit
    /// programs from old linkers (`oldDelay`) name their delay-loaded DLLs by address, not offset.
    /// `nx`: IMAGE_DLLCHARACTERISTICS_NX_COMPAT in its header, as linkers set it since Visual Studio 2008.
    static func program(_ imports: [String], delayed: [String] = [], is64: Bool = true, oldDelay: Bool = false,
                        size: Int = 0, nx: Bool = true) -> Data {
        let sectionRVA: UInt32 = 0x1000, sectionFile: UInt32 = 0x200
        let imageBase: UInt64 = is64 ? 0x1_4000_0000 : 0x40_0000
        let delayedAt = (imports.count + 1) * 20
        let namesAt = delayedAt + (delayed.count + 1) * 32
        var section = Data(count: namesAt)
        var names = Data()
        for (index, name) in (imports + delayed).enumerated() {
            let rva = sectionRVA + UInt32(namesAt + names.count)
            names += Data(name.utf8) + [0]
            if index < imports.count {
                section.put32(rva, at: index * 20 + 12)
            } else {
                let at = delayedAt + (index - imports.count) * 32
                section.put32(oldDelay ? 0 : 1, at: at)
                section.put32(oldDelay ? UInt32(UInt64(rva) + imageBase) : rva, at: at + 4)
            }
        }
        section += names
        section += Data(count: (0x200 - section.count % 0x200) % 0x200)

        let optionalSize = is64 ? 240 : 224
        var header = Data(count: 0x200)
        header[0] = 0x4D; header[1] = 0x5A  // "MZ"
        header.put32(0x40, at: 0x3C)
        header.put32(0x4550, at: 0x40)  // "PE\0\0"
        header.put16(is64 ? 0x8664 : 0x14C, at: 0x44)
        header.put16(1, at: 0x46)
        header.put16(UInt16(optionalSize), at: 0x54)
        let optional = 0x58
        header.put16(is64 ? 0x20B : 0x10B, at: optional)
        if is64 { header.put64(imageBase, at: optional + 24) } else { header.put32(UInt32(imageBase), at: optional + 28) }
        if nx { header.put16(0x0100, at: optional + 70) }
        let directories = optional + (is64 ? 112 : 96)
        if !imports.isEmpty { header.put32(sectionRVA, at: directories + 8) }
        if !delayed.isEmpty { header.put32(sectionRVA + UInt32(delayedAt), at: directories + 13 * 8) }
        let table = optional + optionalSize
        header.replaceSubrange(table ..< table + 8, with: Data(".idata\0\0".utf8))
        header.put32(UInt32(section.count), at: table + 8)
        header.put32(sectionRVA, at: table + 12)
        header.put32(UInt32(section.count), at: table + 16)
        header.put32(sectionFile, at: table + 20)
        let file = header + section
        return file.count < size ? file + Data(count: size - file.count) : file
    }

    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nightforge-game-analysis-test-\(UUID().uuidString)", isDirectory: true)

    /// A game folder with these files (path → contents) in it.
    static func folder(_ name: String, _ files: [String: Data]) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        for (path, data) in files {
            let file = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func analyze(_ name: String, _ files: [String: Data], launch: String? = "Game.exe") throws -> GameAnalysis {
        GameAnalysis.analyze(installDir: try folder(name, files), launchExecutable: launch)
    }

    static func main() throws {
        let fm = FileManager.default
        let empty = Data()
        let big = 3_100_000

        // MARK: Import tables
        func dlls(_ data: Data) throws -> [String]? {
            let file = root.appendingPathComponent("pe-\(UUID().uuidString).exe")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file)
            return PEImports.dlls(of: file)
        }
        check(try dlls(program(["KERNEL32.dll", "d3d11.dll"])) == ["kernel32.dll", "d3d11.dll"], "imports, lower-cased")
        check(try dlls(program(["user32.dll"], delayed: ["XInput1_4.dll"])) == ["user32.dll", "xinput1_4.dll"], "delay-loaded too")
        check(try dlls(program(["d3d9.dll"], is64: false)) == ["d3d9.dll"], "32-bit programs")
        check(try dlls(program([], delayed: ["d3d9.dll"], is64: false, oldDelay: true)) == ["d3d9.dll"],
              "old linkers' delay-loads by address")
        check(try dlls(program(["winspool.drv", "game.exe", "d3d11.dll"])) == ["winspool.drv", "d3d11.dll"],
              "only libraries and drivers count")
        check(try dlls(program([])) == [], "a program that imports nothing")
        check(try dlls(Data("#!/bin/sh\necho hi\n".utf8)) == nil, "a script is no Windows program")
        var notPE = program(["d3d11.dll"])
        notPE.put32(0x1234, at: 0x40)
        check(try dlls(notPE) == nil, "MZ without a PE header (a DOS program)")
        check(try dlls(program(["d3d11.dll"]).prefix(0x60)) == nil, "a program cut off in its headers")
        var tiny = program(["d3d11.dll"])
        tiny.put16(64, at: 0x54)
        check(try dlls(tiny) == nil, "an optional header too small for the directories")
        check(PEImports.dlls(of: root.appendingPathComponent("missing.exe")) == nil, "a missing file")

        // MARK: Graphics interfaces and engines
        let d3d11 = try analyze("dx11", ["Game.exe": program(["kernel32.dll", "d3d11.dll", "dxgi.dll"])])
        check(d3d11.apis == [.d3d11] && d3d11.engine == .other && d3d11.usesD3D11 && !d3d11.usesD3D9, "a DirectX 11 game")
        check(d3d11.summary == "DirectX 11" && d3d11.preferD3D11Arguments.isEmpty, "summary: \(d3d11.summary)")

        let backslash = try analyze("backslash", ["Bin/Win64/game.exe": program(["d3d10_1.dll"])], launch: #"Bin\Win64\game.exe"#)
        check(backslash.apis == [.d3d10] && backslash.usesD3D11, "Steam's Windows path to the program: \(backslash.apis)")

        let unity = try analyze("unity", [
            "Game.exe": program(["kernel32.dll", "unityplayer.dll"]),
            "UnityPlayer.dll": program(["d3d11.dll", "opengl32.dll", "vulkan-1.dll"]),
            "UnityCrashHandler64.exe": program(["d3d9.dll"], size: big),
        ])
        check(unity.engine == .unity && unity.apis == [.d3d11], "Unity: Direct3D 11, not the crash reporter's: \(unity.apis)")
        check(unity.summary == "DirectX 11 · Unity" && unity.preferD3D11Arguments.isEmpty, "Unity summary: \(unity.summary)")
        let unity12 = try analyze("unity12", [
            "Game.exe": program(["kernel32.dll"]), "UnityPlayer.dll": empty, "D3D12/D3D12Core.dll": empty,
        ])
        check(unity12.apis == [.d3d11, .d3d12] && unity12.preferD3D11Arguments == ["-force-d3d11"],
              "a Unity build with Direct3D 12 is told to use 11: \(unity12.apis)")

        let unreal = try analyze("unreal", [
            "Game.exe": program(["kernel32.dll"]),
            "Game/Binaries/Win64/Game-Win64-Shipping.exe": program(["d3d11.dll", "d3d12.dll", "sl.interposer.dll"]),
        ])
        check(unreal.engine == .unreal && unreal.apis == [.d3d11, .d3d12], "Unreal's real program behind its starter: \(unreal.apis)")
        check(unreal.preferD3D11Arguments == ["-dx11"] && !unreal.onlyD3D12, "Unreal is told to use Direct3D 11")
        check(unreal.summary == "DirectX 11, DirectX 12 · Unreal Engine", "Unreal summary: \(unreal.summary)")
        let unreal12 = try analyze("unreal12", ["Game.exe": program(["d3d12.dll"]), "Engine/Binaries/ThirdParty/x.txt": empty])
        check(unreal12.engine == .unreal && unreal12.onlyD3D12 && unreal12.preferD3D11Arguments.isEmpty,
              "Direct3D 12 only, an Engine folder: Unreal")
        let other12 = try analyze("other12", ["Game.exe": program(["d3d11.dll", "d3d12.dll"])])
        check(other12.preferD3D11Arguments.isEmpty, "no switch for an engine Nightforge doesn't know")
        let agility = try analyze("agility", ["Game.exe": program(["d3d11.dll"]), "D3D12Core.dll": empty])
        check(agility.apis == [.d3d11, .d3d12], "Direct3D 12's Agility SDK next to the program")

        let source = try analyze("source", ["hl2.exe": program(["kernel32.dll"]), "bin/shaderapidx9.dll": empty], launch: "hl2.exe")
        check(source.apis == [.d3d9] && source.usesD3D9, "Source loads Direct3D 9 at run time: \(source.apis)")
        let legacy = try analyze("legacy", ["Game.exe": program(["ddraw.dll"], is64: false)])
        check(legacy.apis == [.legacy] && legacy.usesD3D9 && legacy.summary == "DirectX 7/8", "DirectDraw is DirectX 7/8")
        let gl = try analyze("gl", ["Game.exe": program(["opengl32.dll", "vulkan-1.dll"])])
        check(gl.apis == [.vulkan, .openGL] && gl.summary == "Vulkan, OpenGL", "Vulkan and OpenGL: \(gl.summary)")

        // The game's own big libraries can be where it draws; upscalers and SDKs don't count.
        let engineDLL = try analyze("enginedll", [
            "Game.exe": program(["engine.dll", "nvngx_dlss.dll", "steam_api64.dll", "api-ms-win-crt-runtime-l1-1-0.dll", "small.dll"]),
            "engine.dll": program(["d3d9.dll"], size: big),
            "nvngx_dlss.dll": program(["d3d12.dll", "vulkan-1.dll"], size: big),
            "steam_api64.dll": program(["d3d11.dll"], size: big),
            "small.dll": program(["opengl32.dll"]),
        ])
        check(engineDLL.apis == [.d3d9], "the engine's library, not DLSS, Steam's or a small one: \(engineDLL.apis)")
        // Overwatch: the program links only its loader, the loader Direct3D 11; the Agility SDK next to
        // it adds 12. Not a pure DirectX 12 game, so DXMT comes first (it ran on D3DMetal alone, 1.11.2026).
        let overwatch = try analyze("overwatch", [
            "Overwatch.exe": program(["Overwatch_loader.dll"], delayed: ["dbghelp.dll"]),
            "Overwatch_loader.dll": program(["kernel32.dll", "d3d11.dll", "dxgi.dll", "bink2w64.dll"], size: big),
            "D3D12/D3D12Core.dll": empty,
        ], launch: "Overwatch.exe")
        check(overwatch.apis == [.d3d11, .d3d12] && !overwatch.onlyD3D12 && overwatch.usesD3D11,
              "a loader that links Direct3D 11, plus the Agility SDK: \(overwatch.apis)")
        // Control: Control.exe hands over to Control_DX11.exe; the renderers sit in DLLs this look doesn't reach.
        let control = try analyze("control", [
            "Control.exe": program([]), "Control_DX11.exe": program(["kernel32.dll", "renderer_rmdwin7_f.dll"], size: 50_000),
            "Control_DX12.exe": program(["kernel32.dll", "renderer_rmdwin10_f.dll"], size: 50_001), "VC_redist.x64.exe": program(["d3d9.dll"]),
        ], launch: "Control.exe")
        check(control.apis == [.d3d11, .d3d12] && control.d3d12Program == "Control_DX12.exe" && !control.onlyD3D12,
              "programs of its own for DirectX 11 and 12: both, and which one is 12 (\(control.apis), \(control.d3d12Program ?? "-"))")
        check(try analyze("nodx12", ["Game.exe": program(["d3d11.dll"]), "dx12setup.exe": program([])]).d3d12Program == nil,
              "a name that only starts with dx12 isn't the game's DirectX 12 program")
        let agilityOnly = try analyze("agilityonly", ["Game.exe": program(["kernel32.dll"]), "D3D12/D3D12Core.dll": empty])
        check(agilityOnly.onlyD3D12, "the Agility SDK and nothing else linked: DirectX 12 only (\(agilityOnly.apis))")

        // A launcher that draws nothing: the biggest program is the game; one that draws is the game itself.
        let launcher = try analyze("launcher", [
            "Launcher.exe": program(["kernel32.dll"]),
            "Game/Game.exe": program(["d3d11.dll"], size: 50_000),
            "Tools/Editor.exe": program(["opengl32.dll"], size: 20_000),
        ], launch: "Launcher.exe")
        check(launcher.apis == [.d3d11], "behind a launcher, the biggest program: \(launcher.apis)")
        let drawing = try analyze("drawing", [
            "Launcher.exe": program(["d3d9.dll"]), "Game/Game.exe": program(["d3d12.dll"], size: 50_000),
        ], launch: "Launcher.exe")
        check(drawing.apis == [.d3d9], "a launcher that draws is what starts: \(drawing.apis)")
        let missing = try analyze("missing", ["Game/Game.exe": program(["d3d11.dll"])], launch: "Gone.exe")
        check(missing.apis == [.d3d11], "a launch program that's gone: the biggest one: \(missing.apis)")
        let noLaunch = try analyze("nolaunch", ["Game.exe": program(["d3d9.dll"])], launch: nil)
        check(noLaunch.apis == [.d3d9], "no launch program known: the biggest one")

        // What isn't the game: installers, redistributables, crash reporters, files too deep.
        let helpers = try analyze("helpers", [
            "Game.exe": program(["kernel32.dll"]),
            "_CommonRedist/DirectX/DXSETUP.exe": program(["d3d9.dll"], size: 90_000),
            "vcredist_x64.exe": program(["d3d9.dll"], size: 90_000),
            "unins000.exe": program(["d3d9.dll"], size: 90_000),
            "CrashReportClient.exe": program(["d3d11.dll"], size: 90_000),
            "a/b/c/d/Deep.exe": program(["d3d12.dll"], size: 90_000),
        ])
        check(helpers.apis.isEmpty && helpers.summary.isEmpty, "installers, crash reporters, deep files left out: \(helpers.apis)")

        // MARK: Anti-cheat, .NET, other launchers, WebView2
        let guarded = try analyze("guarded", [
            "Game.exe": program(["d3d11.dll"]),
            "BattlEye/BEService_x64.exe": program([]),
            "EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe": program([]),
        ])
        check(guarded.antiCheat == ["Easy Anti-Cheat", "BattlEye"], "both anti-cheats, in a fixed order: \(guarded.antiCheat)")
        check(guarded.launcher == nil && !guarded.usesDotNet && !guarded.usesWebView2, "nothing else")
        let dotnet = try analyze("dotnet", ["Game.exe": program(["mscoree.dll"]), "WebView2Loader.dll": empty])
        check(dotnet.usesDotNet && dotnet.usesWebView2 && dotnet.summary == ".NET", ".NET and WebView2: \(dotnet.summary)")
        let ubisoft = try analyze("ubisoft", ["Game.exe": program(["d3d11.dll"]), "bin/x64/uplay_r2_loader64.dll": empty])
        check(ubisoft.launcher == "Ubisoft Connect", "Ubisoft Connect, anywhere in the folder")
        let ea = try analyze("ea", ["Game.exe": program(["d3d11.dll"]), "__Installer/installerdata.xml": empty])
        check(ea.launcher == "EA app", "the EA app by its installer folder")
        let eaElsewhere = try analyze("ea-elsewhere", ["Game.exe": program(["d3d11.dll"]), "docs/__installer/installerdata.xml": empty])
        check(eaElsewhere.launcher == nil, "a path with a folder must be at the top")
        let rockstar = try analyze("rockstar", ["GTA5.exe": program(["d3d11.dll"], size: 60_000), "PlayGTAV.exe": program([])], launch: "PlayGTAV.exe")
        check(rockstar.launcher == "Rockstar Games Launcher" && rockstar.apis == [.d3d11], "Rockstar's starter: \(rockstar.apis)")
        let paradox = try analyze("paradox", ["Game.exe": program(["d3d11.dll"]), "launcher/launcher-settings.json": empty])
        check(paradox.launcher == "Paradox Launcher", "the Paradox Launcher")

        // An empty folder, and one that isn't there.
        check(try analyze("empty", [:]) == GameAnalysis(), "an empty folder says nothing")
        check(GameAnalysis.analyze(installDir: root.appendingPathComponent("gone"), launchExecutable: "Game.exe") == GameAnalysis(),
              "a folder that isn't there says nothing")

        // MARK: The type itself
        check(GameAnalysis.API.allCases.sorted() == GameAnalysis.API.allCases && GameAnalysis.API.d3d9 < .d3d12, "interfaces oldest first")
        check(Set(GameAnalysis.API.allCases.map(\.label)).count == GameAnalysis.API.allCases.count, "every interface has its own name")
        let kept = try JSONDecoder().decode(GameAnalysis.self, from: JSONEncoder().encode(unreal))
        check(kept == unreal, "kept and read back unchanged")

        try? fm.removeItem(at: root)
        // MARK: A renderer in a small library of the game's own (Alan Wake, 11.11.2026)
        // As Alan Wake is: the program links D3DX 9 and its own libraries, none links d3d9.dll.
        let alanWake = try analyze("alanwake", [
            "alanwake.exe": program(["d3dx9_43.dll", "kernel32.dll", "renderer_f_win32.dll", "d3d_f_win32.dll"], is64: false),
            "renderer_f_Win32.dll": program(["d3dx9_43.dll", "d3d_f_win32.dll"], is64: false),
            "d3d_f_Win32.dll": program(["d3dx9_43.dll", "kernel32.dll"], is64: false) + Data("D3D9.DLL\0Direct3DCreate9\0".utf8),
            "fmodex.dll": program(["d3d11.dll"], is64: false),
        ], launch: "alanwake.exe")
        check(alanWake.apis == [.d3d9], "D3DX 9 linked: the game draws with Direct3D 9 (\(alanWake.apis))")
        check(alanWake.is64Bit == false && alanWake.kind.fine == "other|d3d9|fmod", "… and its sort (\(alanWake.kind.fine))")
        check(try analyze("d3dx11", ["Game.exe": program(["d3dx11_43.dll", "d3dx10_43.dll"])]).apis == [.d3d10, .d3d11], "D3DX 10 and 11 likewise")
        // A renderer in a library beside the program, linked or only named there.
        let beside = try analyze("beside", [
            "Game.exe": program(["kernel32.dll", "render.dll"], is64: false),
            "render.dll": program(["d3d9.dll"], is64: false),
            "fmodex.dll": program(["d3d11.dll"], is64: false),          // an SDK that links what it supports
            "d3d11.dll": program(["vulkan-1.dll"], is64: false),         // DXVK's copy beside the game
            "dxgi.dll": program(["vulkan-1.dll"], is64: false),
            "tools/editor.dll": program(["opengl32.dll"], is64: false),  // not beside the program
        ])
        check(beside.apis == [.d3d9], "Direct3D 9 linked by a small library beside the program (\(beside.apis))")
        let byName = try analyze("byname", [
            "Game.exe": program(["kernel32.dll"]),
            "gfx.dll": program(["kernel32.dll"]) + Data("LoadLibrary d3d11.dll D3D11CreateDevice".utf8),
            "bink2w64.dll": program(["kernel32.dll"]) + Data("d3d9.dll Direct3DCreate9".utf8),
        ])
        check(byName.apis == [.d3d11], "… or only named in one, and not by an SDK (\(byName.apis))")
        let silent = try analyze("silent", ["Game.exe": program(["kernel32.dll"]), "helper.dll": program(["user32.dll"])])
        check(silent.apis.isEmpty, "libraries that link no graphics: still nothing")
        let named = try analyze("named", ["Game.exe": program(["d3d11.dll"]), "old_d3d9.dll": program(["d3d9.dll"])])
        check(named.apis == [.d3d11], "what the program itself links stands: the libraries beside it aren't asked")

        // MARK: Unreal Engine 3 (Batman: Arkham Asylum, Dishonored; 11.11.2026)
        let batman = try analyze("batman", [
            "Binaries/ShippingPC-BmGame.exe": program(["d3d9.dll", "physxloader.dll"], is64: false),
            "Engine/Config/BaseEngine.ini": empty, "BmGame/CookedPC/Startup.upk": empty,
        ], launch: "Binaries/ShippingPC-BmGame.exe")
        check(batman.engine == .unreal && batman.engineVersion == "3" && batman.kind.coarse == "unreal3|d3d9",
              "Unreal Engine 3 by its folders (\(batman.kind.coarse))")
        check(batman.preferD3D11Arguments.isEmpty, "… and no switch added to it")
        let dishonored = try analyze("dishonored", [
            "Binaries/Win64/Dishonored.exe": program(["d3d9.dll"]),
            "Engine/Config/BaseEngine.ini": empty, "DishonoredGame/CookedPCConsole/x.upk": empty,
        ], launch: "Binaries/Win64/Dishonored.exe")
        check(dishonored.kind.fine == "unreal3|d3d9|" && dishonored.is64Bit == true, "… also with CookedPCConsole (\(dishonored.kind.fine))")
        let notUnreal = try analyze("notunreal", ["Binaries/Game.exe": program(["d3d9.dll"]), "Engine/Config/x.ini": empty])
        check(notUnreal.engine == .other && notUnreal.engineVersion == nil, "an Engine folder alone isn't Unreal's")

        // MARK: The game's sort (GameKind)
        let sort = try analyze("sort", [
            "Game.exe": program(["d3d11.dll", "steam_api64.dll"], delayed: ["physx3_x64.dll"]),
            "Engine/Binaries/ThirdParty/PhysX3/Win64/VS2015/PhysX3_x64.dll": empty,
            "Engine/Binaries/ThirdParty/Steamworks/x.txt": empty,
            "bink2w64.dll": empty, "binkies.png": empty, "nvngx_dlss.dll": empty,
        ])
        check(sort.middleware == ["bink", "dlss", "physx3", "steamworks"],
              "what a game brings along: from its imports, its DLLs and Unreal's ThirdParty folders (\(sort.middleware))")
        check(sort.is64Bit == true && sort.engine == .unreal && sort.engineVersion == nil, "its width; no version resource, no engine version")
        check(sort.kind.coarse == "unreal|d3d11" && sort.kind.fine == "unreal|d3d11|bink+dlss+physx3+steamworks", "its sort (\(sort.kind.fine))")
        let old32 = try analyze("sort32", ["Game.exe": program(["d3d9.dll", "physxloader.dll"], is64: false)])
        check(old32.is64Bit == false && old32.middleware == ["physx2"] && old32.kind.bits == 32, "a 32-bit game with PhysX 2")
        func unityData(_ version: String) -> Data { Data([0, 0, 0, 0, 0, 0, 0, 22]) + Data((version + "\0").utf8) + Data(count: 64) }
        let forest = try analyze("forest", [
            "TheForest.exe": program(["kernel32.dll"]), "UnityPlayer.dll": program(["d3d11.dll"]),
            "TheForest_Data/globalgamemanagers": unityData("5.6.5p4"),
            "TheForestVR_Data/globalgamemanagers": unityData("2017.4.30f1"),
        ], launch: "TheForest.exe")
        check(forest.engine == .unity && forest.engineVersion == "5.6", "Unity's version from the started program's own data (\(forest.engineVersion ?? "–"))")
        let packed = try analyze("packed", [
            "Game.exe": program(["kernel32.dll"]), "UnityPlayer.dll": program(["d3d11.dll"]),
            "Other_Data/data.unity3d": Data("UnityFS\0\0\0\0\u{8}5.x.x\06000.3.10f1\0".utf8),
        ])
        check(packed.engineVersion == "6000.3" && packed.kind.coarse == "unity6000|d3d11", "… or from whatever data folder there is (\(packed.kind.coarse))")
        check(try analyze("plain", ["Game.exe": program(["d3d11.dll"])]).kind.fine == "other|d3d11|", "a game that brings nothing along")

        // MARK: NX_COMPAT: Wine turns DEP off for a 32-bit process that loads a module without it
        func nxCompat(_ data: Data) throws -> Bool? {
            let file = root.appendingPathComponent("nx-\(UUID().uuidString).dll")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file)
            return PEImports.nxCompat(of: file)
        }
        check(try nxCompat(program(["kernel32.dll"])) == true && nxCompat(program(["kernel32.dll"], is64: false)) == true,
              "the flag read in PE32+ and PE32")
        check(try nxCompat(program(["kernel32.dll"], is64: false, nx: false)) == false, "an old linker's program: without it")
        check(try nxCompat(Data("#!/bin/sh\n".utf8)) == nil && nxCompat(program([]).prefix(0x60)) == nil,
              "no PE image, or one cut off in its headers: nothing said")
        let classic = try analyze("classic", [
            "Bin/Classic.exe": program(["d3d9.dll", "kernel32.dll"], is64: false, nx: false),
            "Bin/binkw32.dll": program(["kernel32.dll"], is64: false, nx: false),
            "Bin/fmod.dll": program(["kernel32.dll"], is64: false),
            "Bin/readme.txt": Data("not a program".utf8),
            "Tools/old.dll": program(["kernel32.dll"], is64: false, nx: false),  // not beside the program
        ], launch: "Bin/Classic.exe")
        check(classic.withoutNXCompat == ["Classic.exe", "binkw32.dll"],
              "a 32-bit game: its program and the libraries beside it without the flag (\(classic.withoutNXCompat ?? []))")
        check(classic.depLine == "32-bit, Classic.exe, binkw32.dll without NX_COMPAT: Wine turns DEP off for the whole process (Rosetta: slow first writes)",
              "the log's line (\(classic.depLine ?? "–"))")
        check(classic.depNote?.hasPrefix("32 Bit, ohne NX_COMPAT: Classic.exe, binkw32.dll – Wine schaltet DEP") == true, "the game test's note, in German")
        let modern32 = try analyze("modern32", ["Game.exe": program(["d3d9.dll"], is64: false), "x.dll": program([], is64: false)])
        check(modern32.withoutNXCompat == [] && modern32.depLine == nil, "a 32-bit game whose modules all have it: nothing to say")
        let old64 = try analyze("old64", ["Game.exe": program(["d3d11.dll"], nx: false)])
        check(old64.withoutNXCompat == nil && old64.depLine == nil, "a 64-bit game isn't looked at: Wine keeps DEP on there")
        check(GameAnalysis.listed(["a", "b", "c", "d", "e", "f"]) == "a, b, c, d and 2 more", "long lists shortened")
        let manyDir = root.appendingPathComponent("many", isDirectory: true)
        try fm.createDirectory(at: manyDir, withIntermediateDirectories: true)
        for index in 0..<5 { try program([], is64: false, nx: false).write(to: manyDir.appendingPathComponent("m\(index).dll")) }
        try program([], is64: false).write(to: manyDir.appendingPathComponent("Game.exe"))
        check(GameAnalysis.withoutNXCompat(programs: [manyDir.appendingPathComponent("Game.exe")], limit: 3) == ["m0.dll", "m1.dll", "m2.dll"],
              "at most `limit` libraries a folder are read")
        let kept32 = try JSONDecoder().decode(GameAnalysis.self, from: JSONEncoder().encode(classic))
        check(kept32 == classic, "kept and read back with the new field")
        let older = try JSONDecoder().decode(GameAnalysis.self, from: Data(#"{"apis":["d3d9"],"engine":"other","antiCheat":[],"usesDotNet":false,"usesWebView2":false,"usesDLSS":false,"middleware":[]}"#.utf8))
        check(older.withoutNXCompat == nil, "an analysis kept before the field reads as not looked at")

        try? fm.removeItem(at: root)
        print(failures == 0 ? "✓ GameAnalysis" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

private extension Data {
    mutating func put16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func put32(_ value: UInt32, at offset: Int) {
        put16(UInt16(value & 0xFFFF), at: offset)
        put16(UInt16(value >> 16), at: offset + 2)
    }

    mutating func put64(_ value: UInt64, at offset: Int) {
        put32(UInt32(value & 0xFFFF_FFFF), at: offset)
        put32(UInt32(value >> 32), at: offset + 4)
    }
}
