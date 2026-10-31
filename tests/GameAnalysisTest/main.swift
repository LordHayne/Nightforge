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
    static func program(_ imports: [String], delayed: [String] = [], is64: Bool = true, oldDelay: Bool = false,
                        size: Int = 0) -> Data {
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
