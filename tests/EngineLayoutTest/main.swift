// Checks the Direct3D layouts of both engines: tests/EngineLayoutTest/run.sh [D3DMetal payload folder]
import Foundation

@main
struct EngineLayoutTest {
    static var failures = 0
    static let fm = FileManager.default

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A DLL-sized file, builtin-marked like Wine's own when `builtin`.
    static func dll(_ tag: String, builtin: Bool = false) -> Data {
        var bytes = Data(count: 0x100)
        bytes[0] = 0x4D; bytes[1] = 0x5A
        if builtin { bytes.replaceSubrange(0x40..<0x50, with: Data("Wine builtin DLL".utf8)) }
        bytes.append(Data(tag.utf8))
        return bytes
    }

    /// A minimal Windows program header: PE32+ (64-bit) or PE32.
    static func writeExe(_ url: URL, bits64: Bool) {
        var bytes = [UInt8](repeating: 0, count: 0x200)
        bytes[0] = 0x4D; bytes[1] = 0x5A; bytes[0x3C] = 0x40
        bytes.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0, 0])
        bytes[0x40 + 24] = 0x0B; bytes[0x40 + 25] = bits64 ? 0x02 : 0x01  // 0x20B PE32+, 0x10B PE32
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data(bytes))
    }

    static func write(_ data: Data, _ url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func main() {
        TestDefaults.useWorkFolder()
        let work = fm.temporaryDirectory.appendingPathComponent("elt-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }

        // MARK: Which copy of each DLL a layer takes
        check(Engine.layerOverrides(.dxmt, d3dMetalEngine: false) == ["dxgi": "builtin", "d3d11": "builtin", "d3d10core": "builtin"],
              "Gcenx: DXMT is the builtin")
        check(Engine.layerOverrides(.dxvk, d3dMetalEngine: false).isEmpty, "Gcenx: DXVK is the default native")
        check(Engine.layerOverrides(.dxmt, d3dMetalEngine: true) == ["dxgi": "native", "d3d11": "native", "d3d10core": "native",
                                                                    "d3d12": "native", "d3d12core": "native"],
              "winecx: DXMT is the native in system32, and D3DMetal's d3d12 stays away from it")
        check(Engine.layerOverrides(.dxvk, d3dMetalEngine: true)["d3d11"] == "native", "winecx: DXVK is native (next to the game)")
        let metal = Engine.layerOverrides(.d3dmetal, d3dMetalEngine: true)
        check(["dxgi", "d3d11", "d3d12", "d3d12core"].allSatisfy { metal[$0] == "builtin" }, "D3DMetal takes the builtins")
        check(Engine.layerOverrides(.wined3d, d3dMetalEngine: true) == ["d3d9": "builtin"], "WineD3D unchanged")
        check(Engine.defaultLoadOrder("dxgi", d3dMetalEngine: true) == "builtin"
              && Engine.defaultLoadOrder("d3d9", d3dMetalEngine: true) == "native,builtin",
              "winecx: programs without a choice (Steam's browser) don't get DXMT")
        check(Engine.defaultLoadOrder("dxgi", d3dMetalEngine: false) == "native,builtin", "Gcenx: DXVK stays the default")
        check(GraphicsLayer.d3dmetal.upscales, "D3DMetal upscales with MetalFX (a game's DLSS)")

        // MARK: Builtin marker
        let marked = work.appendingPathComponent("marked.dll")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        try? Engine.writeAsNative(dll("dxmt", builtin: true), to: marked)
        let written = (try? Data(contentsOf: marked)) ?? Data()
        check(written.count == dll("dxmt", builtin: true).count && written.subdata(in: 0x40..<0x50) == Data(count: 16),
              "the builtin marker is cleared")
        check(written.suffix(4) == Data("dxmt".utf8), "the rest of the DLL is kept")
        let plain = work.appendingPathComponent("plain.dll")
        try? Engine.writeAsNative(dll("dxvk"), to: plain)
        check((try? Data(contentsOf: plain)) == dll("dxvk"), "a native DLL is copied as it is")

        // MARK: DXMT natives in the prefix
        let graphics = work.appendingPathComponent("graphics/v0.80", isDirectory: true)
        for name in ["dxgi", "d3d11", "d3d10core", "winemetal", "nvapi64"] {
            write(dll("64-\(name)", builtin: true), graphics.appendingPathComponent("x86_64-windows/\(name).dll"))
        }
        for name in ["dxgi", "d3d11", "winemetal"] {
            write(dll("32-\(name)", builtin: true), graphics.appendingPathComponent("i386-windows/\(name).dll"))
        }
        let windows = work.appendingPathComponent("prefix/drive_c/windows", isDirectory: true)
        for folder in ["system32", "syswow64"] {
            try? fm.createDirectory(at: windows.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try? Engine.installDXMTNatives(work.appendingPathComponent("graphics"), windows: windows)
        let d3d11 = (try? Data(contentsOf: windows.appendingPathComponent("system32/d3d11.dll"))) ?? Data()
        check(d3d11.suffix(8) == Data("64-d3d11".utf8),
              "64-bit DXMT goes to system32")
        check(d3d11.count > 0x50 && d3d11.subdata(in: 0x40..<0x50) == Data(count: 16), "…as a native")
        check(fm.fileExists(atPath: windows.appendingPathComponent("syswow64/dxgi.dll").path), "32-bit DXMT goes to syswow64")
        check(!fm.fileExists(atPath: windows.appendingPathComponent("system32/winemetal.dll").path),
              "winemetal stays a builtin in the engine")

        let engineLib = work.appendingPathComponent("wcx/Libraries/Wine/lib/wine/x86_64-windows", isDirectory: true)
        write(dll("wine's d3d12", builtin: true), engineLib.appendingPathComponent("d3d12.dll.wine"))
        try? Engine.installWineD3D12Natives(wine: work.appendingPathComponent("wcx/Libraries/Wine/bin/wine"), windows: windows)
        let wineD3D12 = (try? Data(contentsOf: windows.appendingPathComponent("system32/d3d12.dll"))) ?? Data()
        check(wineD3D12.suffix(12) == Data("wine's d3d12".utf8) && wineD3D12.subdata(in: 0x40..<0x50) == Data(count: 16),
              "Wine's own d3d12 waits in system32 as a native for games on DXMT and DXVK")

        // MARK: DXVK next to the game
        let dxvk = work.appendingPathComponent("dxvk/dxvk-1.10.3", isDirectory: true)
        for arch in ["x64", "x32"] {
            for name in Engine.dxvkGameLibraries + ["d3d9.dll"] { write(dll("\(arch)-\(name)"), dxvk.appendingPathComponent("\(arch)/\(name)")) }
        }
        let game = work.appendingPathComponent("common/Game", isDirectory: true)
        writeExe(game.appendingPathComponent("Game.exe"), bits64: true)
        writeExe(game.appendingPathComponent("Old/Launcher.exe"), bits64: false)
        write(dll("the game's own"), game.appendingPathComponent("Old/dxgi.dll"))
        check(Engine.isPE32Plus(game.appendingPathComponent("Game.exe")) == true, "a 64-bit program is recognised")
        check(Engine.isPE32Plus(game.appendingPathComponent("Old/Launcher.exe")) == false, "a 32-bit program is recognised")
        Engine.placeDXVK(true, dxvkDir: work.appendingPathComponent("dxvk"), installDir: game)
        check((try? Data(contentsOf: game.appendingPathComponent("d3d11.dll"))) == dll("x64-d3d11.dll"), "64-bit DXVK next to the 64-bit program")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/d3d11.dll"))) == dll("x32-d3d11.dll"), "32-bit DXVK next to the 32-bit one")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/dxgi.dll"))) == dll("the game's own"), "a DLL the game ships stays")
        check(!fm.fileExists(atPath: game.appendingPathComponent("d3d9.dll").path), "d3d9 stays in system32")
        Engine.placeDXVK(false, dxvkDir: work.appendingPathComponent("dxvk"), installDir: game)
        check(!fm.fileExists(atPath: game.appendingPathComponent("d3d11.dll").path)
              && !fm.fileExists(atPath: game.appendingPathComponent("Old/d3d11.dll").path), "another layer takes DXVK away again")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/dxgi.dll"))) == dll("the game's own"), "…but not the game's own DLL")

        writeExe(game.appendingPathComponent("b1/Binaries/Win64/b1-Win64-Shipping.exe"), bits64: true)
        check(Engine.executables(in: game).contains("b1-Win64-Shipping.exe"), "Unreal's program four levels down is found")
        try? fm.removeItem(at: game.appendingPathComponent("b1"))

        // MARK: Engine trees
        let winecx = work.appendingPathComponent("winecx/4.7.3", isDirectory: true)
        let wine = winecx.appendingPathComponent("Libraries/Wine/bin/wine")
        write(Data("#!/bin/sh\n".utf8), wine)
        _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        check(Engine.wineBinary(in: winecx) == wine, "winecx's Libraries/Wine tree is found")
        check(!Engine.isGPTKCapable(wine: wine), "no version file: not D3DMetal-capable")
        let plist = try? PropertyListSerialization.data(fromPropertyList: ["gptkCapable": true], format: .xml, options: 0)
        write(plist ?? Data(), winecx.appendingPathComponent("Libraries/WhiskyWineVersion.plist"))
        check(Engine.isGPTKCapable(wine: wine), "gptkCapable in the version file")
        check(!Engine.isD3DMetalDeployed(wine: wine), "no D3DMetal before installing it")

        // MARK: D3DMetal
        let fake = work.appendingPathComponent("fake-gptk/lib", isDirectory: true)
        write(Data("not apple".utf8), fake.appendingPathComponent("external/libd3dshared.dylib"))
        try? fm.createDirectory(at: fake.appendingPathComponent("external/D3DMetal.framework"), withIntermediateDirectories: true)
        write(dll("apple d3d12", builtin: true), fake.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))
        check(Engine.d3dMetalPayloadRoot(in: work.appendingPathComponent("fake-gptk")) == fake.standardizedFileURL
              || Engine.d3dMetalPayloadRoot(in: work.appendingPathComponent("fake-gptk"))?.resolvingSymlinksInPath() == fake.resolvingSymlinksInPath(),
              "the payload is found inside its download")
        check((try? Engine.installD3DMetal(work.appendingPathComponent("fake-gptk"), into: wine)) == nil,
              "a payload Apple didn't sign is refused")
        check(!Engine.isD3DMetalDeployed(wine: wine), "…and nothing of it installed")
        if let real = CommandLine.arguments.dropFirst().first {
            let lib = winecx.appendingPathComponent("Libraries/Wine/lib/wine", isDirectory: true)
            write(dll("wine's d3d12", builtin: true), lib.appendingPathComponent("x86_64-windows/d3d12.dll"))
            try? fm.createDirectory(at: lib.appendingPathComponent("x86_64-unix"), withIntermediateDirectories: true)
            do {
                try Engine.installD3DMetal(URL(fileURLWithPath: real), into: wine)
                check(Engine.isD3DMetalDeployed(wine: wine), "Apple's D3DMetal is installed")
                if fm.fileExists(atPath: lib.appendingPathComponent("x86_64-windows/nvngx-on-metalfx.dll").path) {
                    check(fm.contentsEqual(atPath: lib.appendingPathComponent("x86_64-windows/nvngx.dll").path,
                                           andPath: lib.appendingPathComponent("x86_64-windows/nvngx-on-metalfx.dll").path)
                          && (try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("x86_64-unix/nvngx.so").path)) != nil,
                          "DLSS → MetalFX under NVIDIA's name, as Apple's readme says")
                }
                check((try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("x86_64-unix/dxgi.so").path))
                      == "../../external/libd3dshared.dylib", "unix bridges link to libd3dshared")
                check((try? Data(contentsOf: lib.appendingPathComponent("x86_64-windows/d3d12.dll.wine"))) == dll("wine's d3d12", builtin: true),
                      "Wine's own d3d12 is kept")
                try Engine.installD3DMetal(URL(fileURLWithPath: real), into: wine)
                check((try? Data(contentsOf: lib.appendingPathComponent("x86_64-windows/d3d12.dll.wine"))) == dll("wine's d3d12", builtin: true),
                      "installing again keeps Wine's original, not Apple's copy")
            } catch {
                check(false, "the real payload installs (\(error))")
            }
        }

        // MARK: Gamepad package
        let pad = work.appendingPathComponent("gamepad/nightforge-gamepad-winecx-4.7.3-1", isDirectory: true)
        write(Data("sdl winebus".utf8), pad.appendingPathComponent("x86_64-unix/winebus.so"))
        write(Data("sdl2".utf8), pad.appendingPathComponent("lib/libSDL2-2.0.0.dylib"))
        let unixDir = winecx.appendingPathComponent("Libraries/Wine/lib/wine/x86_64-unix", isDirectory: true)
        write(Data("plain winebus".utf8), unixDir.appendingPathComponent("winebus.so"))
        try? Engine.installGamepad(work.appendingPathComponent("gamepad"), into: wine)
        check((try? String(contentsOf: unixDir.appendingPathComponent("winebus.so"), encoding: .utf8)) == "sdl winebus",
              "winebus.so with SDL goes into the engine")
        check((try? String(contentsOf: unixDir.appendingPathComponent("winebus.so.engine"), encoding: .utf8)) == "plain winebus",
              "the engine's own is kept")
        check(fm.fileExists(atPath: winecx.appendingPathComponent("Libraries/Wine/lib/libSDL2-2.0.0.dylib").path),
              "SDL2 sits in the engine's lib, where winebus.so's rpath looks")
        try? Engine.installGamepad(work.appendingPathComponent("gamepad"), into: wine)
        check((try? String(contentsOf: unixDir.appendingPathComponent("winebus.so.engine"), encoding: .utf8)) == "plain winebus",
              "installing again keeps the engine's original")

        // MARK: Engine fix package (.github/workflows/enginefix.yml)
        func text(_ name: String) -> String? { try? String(contentsOf: unixDir.appendingPathComponent(name), encoding: .utf8) }
        func sha256(_ text: String) -> String {
            let file = work.appendingPathComponent("hash-\(UUID().uuidString)")
            write(Data(text.utf8), file)
            defer { try? fm.removeItem(at: file) }
            return (try? ComponentStore.sha256(of: file)) ?? ""
        }
        write(Data("winecx ntdll".utf8), unixDir.appendingPathComponent("ntdll.so"))
        write(Data("winecx coreaudio".utf8), unixDir.appendingPathComponent("winecoreaudio.so"))
        let fixRoot = work.appendingPathComponent("enginefix", isDirectory: true)
        let fix = fixRoot.appendingPathComponent("nightforge-enginefix-winecx-4.7.3-1", isDirectory: true)
        write(Data("fixed ntdll".utf8), fix.appendingPathComponent("x86_64-unix/ntdll.so"))
        write(Data("downmix coreaudio".utf8), fix.appendingPathComponent("x86_64-unix/winecoreaudio.so"))
        write(Data("\(sha256("winecx ntdll"))  ntdll.so\n\(sha256("winecx coreaudio")) *winecoreaudio.so\n\(sha256("x"))  ../../evil.so\n".utf8),
              fix.appendingPathComponent("originals.sha256"))
        check(Engine.engineFixPackage(in: fixRoot)?.lastPathComponent == fix.lastPathComponent, "the package folder is found in the download")
        check(Engine.engineFixOriginals(in: fix) == ["ntdll.so": sha256("winecx ntdll"), "winecoreaudio.so": sha256("winecx coreaudio")],
              "originals.sha256 as shasum writes it; names outside the engine fix's files don't count")
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == true, "the fix fits the runtime it was built for")
        check(text("ntdll.so") == "fixed ntdll" && text("winecoreaudio.so") == "downmix coreaudio", "both modules go into the engine")
        check(text("ntdll.so.engine") == "winecx ntdll" && text("winecoreaudio.so.engine") == "winecx coreaudio", "the engine's own are kept")
        check(!fm.fileExists(atPath: unixDir.appendingPathComponent("../../evil.so").standardizedFileURL.path), "nothing outside goes anywhere")
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == true && text("ntdll.so.engine") == "winecx ntdll",
              "installing again checks the kept original, and keeps it")
        // The graphics package of the Gcenx engine brings an msync pair, which winecx doesn't take:
        // its msync step mustn't count the engine fix's *.engine copies as its own.
        let graphicsWithMsync = work.appendingPathComponent("graphics-msync/v0.80", isDirectory: true)
        write(Data("gcenx ntdll".utf8), graphicsWithMsync.appendingPathComponent("msync/x86_64-unix/ntdll.so"))
        write(Data("gcenx wineserver".utf8), graphicsWithMsync.appendingPathComponent("msync/bin/wineserver"))
        write(dll("winemetal", builtin: true), graphicsWithMsync.appendingPathComponent("x86_64-windows/winemetal.dll"))
        try? Engine.installGraphics(work.appendingPathComponent("graphics-msync"), into: wine, matchesEngine: false, nativeInPrefix: true)
        check(text("ntdll.so") == "fixed ntdll", "winecx's graphics install leaves the engine fix's ntdll.so in place")
        check((try? Engine.installEngineFix(nil, into: wine)) == false, "without a package…")
        check(text("ntdll.so") == "winecx ntdll" && text("winecoreaudio.so") == "winecx coreaudio", "…the engine's own come back")
        // Another runtime's files: a fix built for 4.7.3 mustn't go over them.
        write(Data("other ntdll".utf8), unixDir.appendingPathComponent("ntdll.so"))
        try? fm.removeItem(at: unixDir.appendingPathComponent("ntdll.so.engine"))
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == false, "files other than the ones it was built against: not in")
        check(text("ntdll.so") == "other ntdll" && text("winecoreaudio.so") == "winecx coreaudio", "both stay the engine's own")
        write(Data("winecx ntdll".utf8), unixDir.appendingPathComponent("ntdll.so"))
        // A later package with ntdll.so alone: the downmix it no longer has goes back to the engine's own.
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == true, "in again")
        write(Data("\(sha256("winecx ntdll"))  ntdll.so\n".utf8), fix.appendingPathComponent("originals.sha256"))
        try? fm.removeItem(at: fix.appendingPathComponent("x86_64-unix/winecoreaudio.so"))
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == true, "a package with ntdll.so alone")
        check(text("ntdll.so") == "fixed ntdll" && text("winecoreaudio.so") == "winecx coreaudio", "only what it carries stays replaced")
        write(Data("not a hash list".utf8), fix.appendingPathComponent("originals.sha256"))
        check((try? Engine.installEngineFix(fixRoot, into: wine)) == false && text("ntdll.so") == "winecx ntdll",
              "a package that names no originals changes nothing but taking the fix out")

        // MARK: Engine test switches (docs/TODO.md › Engine-Tests)
        check(Engine.msync && Engine.environment(wine: wine)["WINEMSYNC"] == "1", "msync is on unless an engine test turns it off")
        check(!Engine.steamConfigSignature.contains("nomsync"), "…and Steam's settings don't mention it then")
        check(Engine.msyncSessionEnds(wanted: false, session: nil) && Engine.msyncSessionEnds(wanted: true, session: false)
              && !Engine.msyncSessionEnds(wanted: true, session: nil) && !Engine.msyncSessionEnds(wanted: false, session: false),
              "a session started with msync the other way ends; one from before the switch had it")
        // Starting Steam from the window's side takes seconds (ps, an engine held back, the helper app; extra review,
        // 3.11.): nothing outside Engine calls the synchronous startSteam – the callers on the main actor wait for the
        // off-main one – and the window variant is awaited.
        let sources = URL(fileURLWithPath: "Sources/Nightforge", isDirectory: true)
        var startLines = 0
        for file in ((try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? [])
        where file.pathExtension == "swift" && file.lastPathComponent != "Engine.swift" {
            for (number, line) in ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n").enumerated() {
                if line.contains("Engine.startSteam(") {
                    check(false, "\(file.lastPathComponent):\(number + 1) starts Steam synchronously: Engine.startSteamOffMain")
                }
                if line.contains("Engine.showSteamWindow(") || line.contains("Engine.startSteamOffMain(") {
                    startLines += 1
                    check(line.contains("await"), "\(file.lastPathComponent):\(number + 1) doesn't wait for the off-main start")
                }
            }
        }
        check(startLines >= 5, "the callers of the off-main start were found: \(startLines)")
        // Steam's last start is written off the main thread and read on it (review N12): never half of one value.
        let engines = (0..<4).map { URL(fileURLWithPath: "/engine/\($0)/bin/wine") }
        let torn = LockedValue(0)
        DispatchQueue.concurrentPerform(iterations: 4000) { index in
            let which = index % 4
            Engine.lastSteamStart = (engines[which], Date(timeIntervalSince1970: Double(which)))
            if let start = Engine.lastSteamStart, engines.firstIndex(of: start.wine).map(Double.init) != start.at.timeIntervalSince1970 {
                torn.withLock { $0 += 1 }
            }
        }
        check(torn.withLock { $0 } == 0 && Engine.lastSteamStart != nil, "lastSteamStart under concurrent writes: always one start's engine and time")
        Engine.lastSteamStart = nil
        // No process list (review N7): whether a session runs is not known – none is ended, and the switch isn't
        // noted as if one had been; with a list that says "none", it is noted.
        let msyncSession = TestDefaults.suite("msync-session")
        msyncSession.set(false, forKey: "msyncSession")
        FakeProcesses.installDown()
        Engine.applyMsyncMode(URL(fileURLWithPath: "/nonexistent/bin/wine"), defaults: msyncSession)
        check(msyncSession.object(forKey: "msyncSession") as? Bool == false, "msync switch without a process list: not noted, the next start looks again")
        FakeProcesses.installEmpty()
        Engine.applyMsyncMode(URL(fileURLWithPath: "/nonexistent/bin/wine"), defaults: msyncSession)
        check(msyncSession.object(forKey: "msyncSession") as? Bool == true, "… with a list that shows no process: noted")
        check(Engine.steamShutdownScript.contains(#"MSYNC="${7:-1}""#) && Engine.steamShutdownScript.contains(#"WINEMSYNC="$MSYNC""#),
              "the quit script's Wine agrees with the session (msync on when it isn't told)")
        check(GameLog.extraChannels("+loaddll,+timestamp,warn+msync") == "+loaddll,+timestamp,warn+msync"
              && GameLog.extraChannels("+loaddll; rm -rf ~") == nil && GameLog.extraChannels("") == nil,
              "extra Wine debug channels: channel lists only")
        check(GameLog.wineDebug == "-all,err+module,err+mscoree", "Wine stays quiet without an engine test")

        // MARK: A game's Wine switches (GameEnvironment: profile "environment", test switch gameEnvironment.<key>)
        check(GameEnvironment.sanitized(["WINE_SIMULATE_WRITECOPY": "1", "DYLD_INSERT_LIBRARIES": "/tmp/x.dylib",
                                         "CX_ACTIVE_GRAPHICS_BACKEND": "../dxmt", "CX_HACK_FILESYSTEM_TYPE": "1 2",
                                         "CX_GRAPHICS_BACKEND": ""]) == ["WINE_SIMULATE_WRITECOPY": "1"],
              "only the allowed names, with plain short values")
        let withSwitches = try? JSONDecoder().decode(GameProfile.self, from: Data(
            #"{"environment": {"WINE_SIMULATE_WRITECOPY": "1", "DYLD_INSERT_LIBRARIES": "/x", "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"}}"#.utf8))
        check(withSwitches?.environment == ["WINE_SIMULATE_WRITECOPY": "1", "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"],
              "a profile's environment, without what isn't allowed")
        let onlyBad = try? JSONDecoder().decode(GameProfile.self, from: Data(#"{"environment": {"DYLD_INSERT_LIBRARIES": "/x"}}"#.utf8))
        check(onlyBad != nil && onlyBad?.environment == nil, "nothing allowed: no environment, and the profile still reads")
        do {
            let test = TestDefaults.suite("game-environment")
            let overwatch = GameID.steam(2357570)
            check(GameEnvironment.wanted(for: overwatch, profile: withSwitches, defaults: test)
                  == ["WINE_SIMULATE_WRITECOPY": "1", "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"], "without a test switch: the profile's")
            test.set(["WINE_SIMULATE_WRITECOPY": "0", "CX_HACK_FILESYSTEM_TYPE": NSNumber(value: 1), "DYLD_FRAMEWORK_PATH": "/x"],
                     forKey: GameEnvironment.testKey(overwatch))
            check(GameEnvironment.testKey(overwatch) == "gameEnvironment.steam.2357570", "the test switch is keyed by the game")
            check(GameEnvironment.wanted(for: overwatch, profile: withSwitches, defaults: test)
                  == ["WINE_SIMULATE_WRITECOPY": "0", "CX_HACK_FILESYSTEM_TYPE": "1", "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"],
                  "the test switch wins over the profile, numbers as `defaults` writes them count, the rest stays out")
            check(GameEnvironment.wanted(for: .steam(550), profile: nil, defaults: test).isEmpty, "another game gets none of it")
        }
        // MARK: The prefix's registry: nothing in HKCU\Environment any more (Wine never hands it to games)
        let registry = Engine.prefixRegistry
        check(Engine.formerRegistryEnvironment.allSatisfy { registry.contains("\"\($0)\"=-") },
              "the values earlier versions wrote there are taken away")
        check(!registry.contains("=\"") && registry.contains("[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus]"),
              "nothing is set in the user environment; the controller setting stays")
        check(Set(Engine.gameEnvironment.keys).isSubset(of: Set(Engine.formerRegistryEnvironment)),
              "every game setting earlier versions could have left there is on the list")
        check(Set(Engine.gameEnvironment.keys).isSubset(of: Set(Engine.steamEnvironment.keys)),
              "and each of them comes with Steam's own environment")

        // MARK: Direct3D 9 on DXVK through the Vulkan loader (engine test switch vulkanLoader, off)
        do {
            let switches = TestDefaults.suite("vulkan-loader")
            let loader = work.appendingPathComponent("loader/libvulkan.1.dylib")
            write(Data("loader".utf8), loader)
            check(Engine.vulkanLoader(for: wine, defaults: switches) == nil, "off unless an engine test turns it on")
            switches.set(loader.path, forKey: "vulkanLoader")
            check(Engine.vulkanLoader(for: wine, defaults: switches)?.path == loader.path, "a loader named by its path")
            let plain = work.appendingPathComponent("plain/bin/wine")
            write(Data("#!/bin/sh\n".utf8), plain)
            check(Engine.vulkanLoader(for: plain, defaults: switches) == nil, "only for winecx: the Gcenx engine has a loader of its own")
            let env = Engine.vulkanLoaderEnvironment(layer: .dxvk, d3d9: true, wine: wine, defaults: switches)
            let bundle = winecx.appendingPathComponent("Libraries/Wine/Nightforge Game.app/Contents/Resources/vulkan").path
            check(env == ["CX_LIBVULKAN": loader.path, "CX_ACTIVE_GRAPHICS_BACKEND": "wined3d",
                          "VK_DRIVER_FILES": bundle + "/icd.d/MoltenVK_icd.json", "VK_ADD_IMPLICIT_LAYER_PATH": bundle + "/implicit_layer.d"],
                  "Direct3D 9 on DXVK: the loader, wined3d for CW Hack 25909, MoltenVK and the layer from the game bundle")
            check(Engine.vulkanLoaderEnvironment(layer: .dxvk, d3d9: false, wine: wine, defaults: switches).isEmpty
                  && Engine.vulkanLoaderEnvironment(layer: .dxmt, d3d9: true, wine: wine, defaults: switches).isEmpty,
                  "Direct3D 11 on DXVK (OxyRail draws without) and other layers: nothing")
            switches.set("/nowhere/libvulkan.1.dylib", forKey: "vulkanLoader")
            check(Engine.vulkanLoader(for: wine, defaults: switches) == nil, "a path that isn't there: off")
            let before = Engine.launchEnvironment
            Engine.launchEnvironment = [:]
            check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false,
                                                  environment: ["CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"], vulkanLoader: env)
                  && Engine.steamEnvironment["CX_LIBVULKAN"] == loader.path && Engine.steamEnvironment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d",
                  "through Steam: the loader's variables, and wined3d over a profile's backend")
            // With KosmicKrisp (vulkanDriver): a start that draws without Vulkan leaves Steam's driver as it is.
            check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false)
                  && Engine.steamEnvironment["CX_LIBVULKAN"] == loader.path && Engine.steamEnvironment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d",
                  "a game without Vulkan after it (DXMT): no restart, the loader stays")
            let kosmicKrisp = URL(fileURLWithPath: "/kk")
            check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false, vulkan: .kosmicKrisp(kosmicKrisp))
                  && Engine.steamEnvironment["CX_LIBVULKAN"] == "/kk/libvulkan.1.dylib"
                  && Engine.steamEnvironment["VK_DRIVER_FILES"] == "/kk/kosmickrisp_icd.json"
                  && Engine.steamEnvironment["MESA_SHADER_CACHE_DIR"] == Engine.mesaShaderCache.path
                  && Engine.steamEnvironment["VK_ADD_IMPLICIT_LAYER_PATH"] == nil,
                  "KosmicKrisp after it, the loader off: its own variables, none of the loader's left")
            check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false, vulkan: .moltenVK, vulkanLoader: env)
                  && Engine.steamEnvironment["CX_LIBVULKAN"] == loader.path && Engine.steamEnvironment["MESA_SHADER_CACHE_DIR"] == nil,
                  "the loader again (it wins over KosmicKrisp): its variables, KosmicKrisp's cache folder gone")
            check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false, vulkan: .moltenVK)
                  && Engine.vulkanLoaderNames.allSatisfy { Engine.steamEnvironment[$0] == nil }
                  && Engine.steamEnvironment["CX_ACTIVE_GRAPHICS_BACKEND"] == nil,
                  "a DirectX 11 game on DXVK (MoltenVK) after it: Steam restarts without them")
            Engine.launchEnvironment = before
        }
        // Through Steam they go into its environment; the next game without them takes them away again.
        let launchBefore = Engine.launchEnvironment
        Engine.launchEnvironment = [:]
        _ = Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false)
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false,
                                              environment: ["WINE_SIMULATE_WRITECOPY": "1"])
              && Engine.steamEnvironment["WINE_SIMULATE_WRITECOPY"] == "1", "a game with a switch: Steam restarts with it")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false)
              && Engine.steamEnvironment["WINE_SIMULATE_WRITECOPY"] == nil, "the next game without it: Steam restarts without it")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: false),
              "and one more game without it: no restart")
        Engine.launchEnvironment = launchBefore

        // MARK: CrossOver's user folder
        let users = work.appendingPathComponent("prefix/drive_c/users", isDirectory: true)
        try? fm.createDirectory(at: users.appendingPathComponent("thomas"), withIntermediateDirectories: true)
        Engine.linkCrossOverProfile(users: users, userName: "thomas")
        check((try? fm.destinationOfSymbolicLink(atPath: users.appendingPathComponent("crossover").path)) == "thomas",
              "crossover points at the existing user folder")
        Engine.linkCrossOverProfile(users: users, userName: "thomas")
        check((try? fm.destinationOfSymbolicLink(atPath: users.appendingPathComponent("crossover").path)) == "thomas", "repeating is harmless")

        // MARK: AVX
        // GameLog's file lies in Application Support: only ever in the test's own home (run.sh).
        let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        guard !GameLog.url.path.hasPrefix(realHome + "/") else {
            check(false, "wine.log would be the player's own (\(GameLog.url.path)): run through run.sh")
            finish()
        }
        gameLog()
        check(GameLog.illegalInstruction(in: "wine: Unhandled illegal instruction at address 0000000140123456"),
              "Wine's crash line is read")
        check(!GameLog.illegalInstruction(in: "err:module:import_dll Library foo.dll not found"), "other errors aren't")
        let crash = game.appendingPathComponent("b1/Saved/Crashes/UECC-1/CrashContext.runtime-xml")
        write(Data("<ErrorMessage>Unhandled Exception: EXCEPTION_ILLEGAL_INSTRUCTION</ErrorMessage>".utf8), crash)
        check(GameLog.illegalInstruction(since: UInt64.max, installDir: game, startedAt: Date().addingTimeInterval(-60)),
              "Unreal's crash report is read")
        check(!GameLog.illegalInstruction(since: UInt64.max, installDir: game, startedAt: Date().addingTimeInterval(60)),
              "an older crash report doesn't count")
        let noAVXProfile = try? JSONDecoder().decode(GameProfile.self, from: Data(#"{"avx": false}"#.utf8))
        let app = GameID.steam(990_002)
        UserDefaults.standard.removeObject(forKey: "learned.noAVX.\(app.key)")
        check(LearnedFixes.avx(app, profile: nil), "AVX is advertised by default")
        check(!LearnedFixes.avx(app, profile: noAVXProfile), "a profile turns it off")
        LearnedFixes.setNoAVX(app)
        check(!LearnedFixes.avx(app, profile: nil), "a learned crash turns it off")
        UserDefaults.standard.removeObject(forKey: "learned.noAVX.\(app.key)")

        // MARK: Steam's environment
        Engine.launchEnvironment = [:]
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true),
              "a DXMT game with AVX needs no restart")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: true, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["D3DM_MAX_FPS"] == "60" && Engine.steamEnvironment["D3DM_ENABLE_METALFX"] == "1",
              "a D3DMetal game brings its frame limit and MetalFX into Steam's environment")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: true, frameLimit: 60, upscaling: true),
              "the next D3DMetal game with the same settings needs no restart")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 40, upscaling: false),
              "a DXMT game in between leaves D3DMetal's settings alone")
        check(Engine.prepareLaunchEnvironment(avx: false, d3dMetal: true, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["ROSETTA_ADVERTISE_AVX"] == nil, "a game without AVX gets a Steam without the hint")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["ROSETTA_ADVERTISE_AVX"] == "1", "…and the next one gets it back")
        check(Engine.steamConfigSignature.contains("D3DM_MAX_FPS=60"), "Steam restarts when these change")
        Engine.launchEnvironment = [:]

        // MARK: KosmicKrisp for DXVK's Direct3D 9 (winecx)
        let kk = URL(fileURLWithPath: "/kk")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, vulkan: .kosmicKrisp(kk))
              && Engine.steamEnvironment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d"
              && Engine.steamEnvironment["CX_LIBVULKAN"] == "/kk/libvulkan.1.dylib"
              && Engine.steamEnvironment["VK_DRIVER_FILES"] == "/kk/kosmickrisp_icd.json"
              && Engine.steamEnvironment["MESA_SHADER_CACHE_DIR"] == Engine.mesaShaderCache.path,
              "a DirectX 9 game on DXVK brings KosmicKrisp into Steam's environment")
        check(Engine.steamConfigSignature.contains("CX_LIBVULKAN=/kk/libvulkan.1.dylib"), "Steam restarts for it")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, vulkan: .kosmicKrisp(kk)),
              "the next one needs no restart")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 40, upscaling: false)
              && Engine.steamEnvironment["CX_LIBVULKAN"] != nil, "a game without Vulkan in between (DXMT) leaves it alone")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, vulkan: .moltenVK)
              && Engine.kosmicKrispVariables.allSatisfy { Engine.steamEnvironment[$0] == nil },
              "a game on MoltenVK gets a Steam without it")
        Engine.launchEnvironment = [:]
        let direct = Engine.directLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, vulkan: .kosmicKrisp(kk))
        check(direct["VK_DRIVER_FILES"] == "/kk/kosmickrisp_icd.json" && direct["DXVK_ASYNC"] == "1",
              "GOG and Epic games get it straight, on top of the game environment")
        check(Engine.kosmicKrispVariables.allSatisfy {
            Engine.directLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true, vulkan: .moltenVK)[$0] == nil
        }, "…and on MoltenVK nothing of it")

        let d3d9 = GameAnalysis(apis: [.d3d9])
        check(Engine.vulkanDriver(layer: .dxvk, analysis: d3d9, winecx: true, kosmicKrisp: kk) == .kosmicKrisp(kk),
              "winecx: DXVK's Direct3D 9 draws on KosmicKrisp")
        check(Engine.vulkanDriver(layer: .dxvk, analysis: d3d9, winecx: true, kosmicKrisp: nil) == .moltenVK, "without it on MoltenVK")
        check(Engine.vulkanDriver(layer: .dxvk, analysis: d3d9, winecx: false, kosmicKrisp: kk) == nil,
              "Gcenx: its own loader, never VK_DRIVER_FILES")
        check(Engine.vulkanDriver(layer: .wined3d, analysis: d3d9, winecx: true, kosmicKrisp: kk) == nil, "WineD3D draws without Vulkan")
        check(Engine.vulkanDriver(layer: .dxvk, analysis: GameAnalysis(apis: [.d3d11]), winecx: true, kosmicKrisp: kk) == .moltenVK,
              "DXVK for DirectX 11 stays on MoltenVK")
        check(Engine.vulkanDriver(layer: .dxvk, analysis: GameAnalysis(apis: [.d3d9, .d3d11]), winecx: true, kosmicKrisp: kk) == .moltenVK,
              "so does a game with DirectX 11 as well")
        check(Engine.vulkanDriver(layer: .dxmt, analysis: GameAnalysis(apis: [.vulkan]), winecx: true, kosmicKrisp: kk) == .moltenVK,
              "Vulkan games: MoltenVK")
        check(Engine.vulkanDriver(layer: .dxmt, analysis: GameAnalysis(), winecx: true, kosmicKrisp: kk) == .moltenVK
              && Engine.vulkanDriver(layer: .dxmt, analysis: nil, winecx: true, kosmicKrisp: kk) == .moltenVK,
              "nothing known about the game: MoltenVK, to be safe")
        check(Engine.vulkanDriver(layer: .dxmt, analysis: GameAnalysis(apis: [.d3d11]), winecx: true, kosmicKrisp: kk) == nil
              && Engine.vulkanDriver(layer: .d3dmetal, analysis: GameAnalysis(apis: [.d3d12]), winecx: true, kosmicKrisp: kk) == nil,
              "DXMT and D3DMetal: no Vulkan, Steam keeps what it has")

        let unpacked = work.appendingPathComponent("kosmickrisp/27.0.0-devel-44989e5a", isDirectory: true)
        let staged = unpacked.appendingPathComponent("nightforge-kosmickrisp-27.0.0-devel-44989e5a", isDirectory: true)
        write(Data("loader".utf8), staged.appendingPathComponent("libvulkan.1.dylib"))
        write(Data("driver".utf8), staged.appendingPathComponent("libvulkan_kosmickrisp.dylib"))
        check(Engine.kosmicKrispFolder(in: unpacked) == nil, "without its manifest it's no driver")
        write(Data("{}".utf8), staged.appendingPathComponent("kosmickrisp_icd.json"))
        check(Engine.kosmicKrispFolder(in: unpacked)?.lastPathComponent == staged.lastPathComponent, "the archive's folder is found")
        check(Engine.kosmicKrispFolder(in: staged)?.lastPathComponent == staged.lastPathComponent, "and the folder itself")

        check(GameLog.graphicsFailed(in: "warn:  DXVK: No adapters found. Please check your device filter settings"),
              "upstream DXVK without a device it can use counts as a graphics failure")
        check(GameLog.graphicsFailed(in: "err:   Failed to create Vulkan device: VK_ERROR_FEATURE_NOT_PRESENT"), "so does a failed device")
        check(!GameLog.graphicsFailed(in: "info:  Found device: Apple M5 (KosmicKrisp 27.0.0)"), "a device found doesn't")

        // MARK: Layer configs
        let configs = work.appendingPathComponent("configs/Game", isDirectory: true)
        try? fm.createDirectory(at: configs, withIntermediateDirectories: true)
        Engine.writeGameConfigs(installDir: configs, frameLimit: 60, upscaling: false)
        let dxvkConf = (try? String(contentsOf: configs.appendingPathComponent("dxvk.conf"), encoding: .utf8)) ?? ""
        check(dxvkConf.contains("dxgi.maxFrameRate = 60") && dxvkConf.contains("d3d9.maxFrameRate = 60"),
              "the frame limit reaches DXVK's Direct3D 9 as well as its DirectX 10/11")

        // MARK: Settings files
        let settings = game.appendingPathComponent("b1/Saved/Config/Windows/GameUserSettings.ini")
        let edits = (try? JSONDecoder().decode(GameProfile.self, from: Data(#"""
            {"fileEdits": [{"path": "b1/Saved/Config/Windows/GameUserSettings.ini",
                            "find": "(\"InsertFrame\", \"1\")", "replace": "(\"InsertFrame\", \"0\")"},
                           {"path": "../../escape.txt", "find": "a", "replace": "b"}]}
            """#.utf8)))?.fileEdits ?? []
        check(edits.count == 2, "a profile's file edits are read")
        check(!Engine.applyFileEdits(edits, installDir: game), "no settings file yet: nothing to change")
        write(Data(#"UISettingData=(("Dlss", "1"),("InsertFrame", "1"),("Rtx", "0"))"#.utf8), settings)
        let escape = game.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("escape.txt")
        write(Data("a".utf8), escape)
        check(Engine.applyFileEdits(edits, installDir: game), "the game's settings file is changed")
        check((try? String(contentsOf: settings, encoding: .utf8)) == #"UISettingData=(("Dlss", "1"),("InsertFrame", "0"),("Rtx", "0"))"#,
              "frame generation goes off, everything else stays")
        check((try? String(contentsOf: escape, encoding: .utf8)) == "a", "nothing outside the game folder is touched")
        check(!Engine.applyFileEdits(edits, installDir: game), "a second time there's nothing left to change")

        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "✓ all checks passed" : "\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// wine.log as Steam and its games write it: where a start begins, what came after, a fresh one.
    static func gameLog() {
        check(GameLog.mark() == 0 && GameLog.text(since: 0).isEmpty, "no log yet: nothing to read")
        guard let steam = GameLog.handleForSteam() else { return check(false, "Steam gets the log to write to") }
        steam.write(Data("[Steam] starting\n".utf8))
        let start = GameLog.mark()
        check(start == 17, "the mark is where the log ends: \(start)")
        steam.write(Data("""
            err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\Games\\Odd\\odd.exe") not found
            err:   DxvkAdapter: Failed to create device
            wine: Unhandled illegal instruction at address 0000000140123456

            """.utf8))
        try? steam.close()
        check(GameLog.text(since: start).hasPrefix("err:module") && !GameLog.text(since: start).contains("[Steam] starting"),
              "a start reads only what came after it")
        check(GameLog.missingRuntimes(since: start, gameFolder: #"C:\Games\Odd"#) == ["vcrun2013"], "the runtime its program missed")
        check(GameLog.graphicsFailed(since: start, layer: .dxvk) && !GameLog.graphicsFailed(since: GameLog.mark(), layer: .dxvk),
              "DXVK gave up, since that start only")
        check(!GameLog.graphicsFailed(since: start, layer: .wined3d), "which isn't a WineD3D start failing")
        // Before every start: Wine's debugger ends a crashed game at once, with no "Program Error" window
        // (Control 1.11.2026 ran on behind it, so its next start was turned away as "already running").
        check(Engine.crashDialogOff == "[HKEY_CURRENT_USER\\Software\\Wine\\WineDbg]\n\"ShowCrashDialog\"=dword:00000000",
              "Wine's crash window off, as a .reg section")
        check(GameLog.errors(since: start).contains { $0.contains("DxvkAdapter") }, "the errors for a problem report")
        check(GameLog.illegalInstruction(since: start, installDir: FileManager.default.temporaryDirectory, startedAt: Date()),
              "the crash Rosetta's AVX hint causes")
        check(GameLog.text(since: GameLog.mark() + 1_000).contains("[Steam] starting"), "a mark past the end: a fresh log, read whole")

        // Grown past 8 MB: the next Steam starts a fresh log and keeps the last one beside it.
        if let handle = FileHandle(forWritingAtPath: GameLog.url.path) { try? handle.truncate(atOffset: 8_000_001); try? handle.close() }
        let fresh = GameLog.handleForSteam()
        try? fresh?.close()
        let previous = GameLog.url.deletingLastPathComponent().appendingPathComponent("wine.previous.log")
        check(GameLog.mark() == 0 && FileManager.default.fileExists(atPath: previous.path), "a fresh log, the old one kept as wine.previous.log")
        try? FileManager.default.removeItem(at: GameLog.url.deletingLastPathComponent())
    }
}
