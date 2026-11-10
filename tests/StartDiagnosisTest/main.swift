// Checks what a failed start is read from, with the crashes of 9. and 10.11.2026 as cases: minidumps made
// up byte by byte (and broken ones), the table from failure to remedy, where dumps are looked for, a game's
// sort, and a start's recipe in its record.
import Foundation

/// Bytes written little-endian, growing as needed.
struct Blob {
    var data = Data()

    mutating func room(_ end: Int) { if data.count < end { data.append(Data(count: end - data.count)) } }
    mutating func u16(_ value: UInt16, at: Int) { room(at + 2); for i in 0..<2 { data[at + i] = UInt8(value >> (8 * UInt16(i)) & 0xFF) } }
    mutating func u32(_ value: UInt32, at: Int) { room(at + 4); for i in 0..<4 { data[at + i] = UInt8(value >> (8 * UInt32(i)) & 0xFF) } }
    mutating func u64(_ value: UInt64, at: Int) { room(at + 8); for i in 0..<8 { data[at + i] = UInt8(value >> (8 * UInt64(i)) & 0xFF) } }
    mutating func bytes(_ bytes: Data, at: Int) { room(at + bytes.count); data.replaceSubrange(at..<at + bytes.count, with: bytes) }
    /// The next free place, on a boundary of 8.
    var end: Int { (data.count + 7) / 8 * 8 }
}

/// A minidump as Unreal writes it, with only what CrashDump reads.
struct MadeDump {
    var modules: [(path: String, base: UInt64, size: UInt32)]
    var code: UInt32 = CrashDump.accessViolation
    var address: UInt64 = 0
    /// What lies on the stack below the stack pointer (older frames' leftovers) and from it on.
    var below: [UInt64] = []
    var stack: [UInt64] = []
    var wide = true

    func data() -> Data {
        var blob = Blob()
        blob.u32(0x504D_444D, at: 0)
        blob.u32(4, at: 8)       // streams
        blob.u32(32, at: 12)     // the directory
        blob.room(32 + 4 * 12)
        func entry(_ index: Int, type: UInt32, at place: Int, in blob: inout Blob) {
            blob.u32(type, at: 32 + index * 12)
            blob.u32(UInt32(place), at: 32 + index * 12 + 8)
        }
        // System info: the processor.
        let system = blob.end
        blob.u16(wide ? 9 : 0, at: system)
        blob.room(system + 56)
        entry(0, type: 7, at: system, in: &blob)
        // The stack's memory.
        let width = wide ? 8 : 4
        let stackStart: UInt64 = wide ? 0xC9_E000 : 0x19_F000
        let memory = blob.end
        for (index, value) in (below + stack).enumerated() {
            if wide { blob.u64(value, at: memory + index * 8) } else { blob.u32(UInt32(truncatingIfNeeded: value), at: memory + index * 4) }
        }
        let memorySize = (below.count + stack.count) * width
        let pointer = stackStart + UInt64(below.count * width)
        // The crashed thread's context: only the stack pointer.
        let context = blob.end
        if wide { blob.u64(pointer, at: context + 0x98) } else { blob.u32(UInt32(pointer), at: context + 0xC4) }
        blob.room(context + (wide ? 1232 : 716))
        // The exception.
        let exception = blob.end
        blob.u32(77, at: exception)              // thread
        blob.u32(code, at: exception + 8)
        blob.u64(address, at: exception + 24)
        blob.u32(UInt32(context), at: exception + 8 + 152 + 4)
        blob.room(exception + 168)
        entry(1, type: 6, at: exception, in: &blob)
        // Two threads; the second is the crashed one.
        let threads = blob.end
        blob.u32(2, at: threads)
        blob.u32(11, at: threads + 4)
        blob.u32(77, at: threads + 4 + 48)
        blob.u64(stackStart, at: threads + 4 + 48 + 24)
        blob.u32(UInt32(memorySize), at: threads + 4 + 48 + 32)
        blob.u32(UInt32(memory), at: threads + 4 + 48 + 36)
        blob.room(threads + 4 + 2 * 48)
        entry(2, type: 3, at: threads, in: &blob)
        // The modules, their names behind them.
        let list = blob.end
        blob.u32(UInt32(modules.count), at: list)
        blob.room(list + 4 + modules.count * 108)
        for (index, module) in modules.enumerated() {
            let name = blob.end
            let text = module.path.data(using: .utf16LittleEndian)!
            blob.u32(UInt32(text.count), at: name)
            blob.bytes(text + Data(count: 2), at: name + 4)
            blob.u64(module.base, at: list + 4 + index * 108)
            blob.u32(module.size, at: list + 4 + index * 108 + 8)
            blob.u32(UInt32(name), at: list + 4 + index * 108 + 20)
        }
        entry(3, type: 4, at: list, in: &blob)
        return blob.data
    }
}

/// A Windows program with only a version resource, or without one.
func madeProgram(version: [UInt16]?, is64: Bool = true) -> Data {
    var blob = Blob()
    blob.u16(0x5A4D, at: 0)
    blob.u32(0x80, at: 0x3C)
    blob.u32(0x4550, at: 0x80)
    blob.u16(1, at: 0x80 + 6)                      // one section
    let optionalSize = is64 ? 240 : 224
    blob.u16(UInt16(optionalSize), at: 0x80 + 20)
    let optional = 0x80 + 24
    blob.u16(is64 ? 0x20B : 0x10B, at: optional)
    let table = optional + optionalSize
    blob.room(table + 40)
    blob.u32(0x1000, at: table + 8)                // virtual size
    blob.u32(0x2000, at: table + 12)               // address
    blob.u32(0x1000, at: table + 16)               // raw size
    blob.u32(0x400, at: table + 20)                // raw pointer
    blob.room(0x400 + 0x1000)
    if let version {
        let directories = optional + (is64 ? 112 : 96)
        blob.u32(0x2000, at: directories + 2 * 8)
        blob.u32(0x1000, at: directories + 2 * 8 + 4)
        // Icons first, then VS_FIXEDFILEINFO: signature, structure version, the file version's halves.
        let info = 0x400 + 0x321
        blob.u32(0xFEEF_04BD, at: info)
        blob.u32(0x0001_0000, at: info + 4)
        blob.u32(UInt32(version[0]) << 16 | UInt32(version[1]), at: info + 8)
        blob.u32(UInt32(version[2]) << 16 | UInt32(version[3]), at: info + 12)
    }
    return blob.data
}

@main
struct StartDiagnosisTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func profile(_ json: String) -> GameProfile? { try? JSONDecoder().decode(GameProfile.self, from: Data(json.utf8)) }

    static let game: UInt64 = 0x1_4000_0000, nvapi: UInt64 = 0x7FF0_0000_0000, loader: UInt64 = 0x7FF1_0000_0000
    static let ntdll: UInt64 = 0x7FF2_0000_0000, d3d11: UInt64 = 0x7FF3_0000_0000
    static let modules: [(path: String, base: UInt64, size: UInt32)] = [
        ("Z:\\Games\\ItTakesTwo\\Nuts\\Binaries\\Win64\\ItTakesTwo.exe", game, 0x800_0000),
        ("C:\\windows\\system32\\nvapi64.dll", nvapi, 0x20_0000),
        ("C:\\Program Files (x86)\\NVIDIA Corporation\\PhysX\\Common\\PhysXUpdateLoader64.dll", loader, 0x2_0000),
        ("C:\\windows\\system32\\ntdll.dll", ntdll, 0x10_0000),
        ("C:\\windows\\system32\\d3d11.dll", d3d11, 0x40_0000),
    ]

    static func main() throws {
        TestDefaults.useWorkFolder()
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-start-diagnosis-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // MARK: Crash dumps

        // It Takes Two, 10.11.2026: a jump to 0 out of nvapi64, called by the PhysX update loader. Below the
        // stack pointer lies an older frame's address, on it a module's base (a handle) and loose numbers.
        let physx = MadeDump(modules: modules, below: [game + 0x99, 7],
                             stack: [1, 0xDEAD_BEEF, nvapi + 0x1120, 0, loader, loader + 0x113C, loader + 0xBDE9, ntdll + 0x53158])
        let dump = CrashDump.read(physx.data())
        check(dump?.code == CrashDump.accessViolation && dump?.address == 0 && dump?.module == nil, "a jump to 0: no module of its own")
        check(dump?.stack == [CrashDump.Frame(module: "nvapi64.dll", offset: 0x1120),
                              CrashDump.Frame(module: "physxupdateloader64.dll", offset: 0x113C),
                              CrashDump.Frame(module: "physxupdateloader64.dll", offset: 0xBDE9),
                              CrashDump.Frame(module: "ntdll.dll", offset: 0x53158)],
              "the stack from the pointer on: addresses in modules, without a base and what lies below (\(dump?.stack ?? []))")
        check(dump?.chain == ["nvapi64.dll", "physxupdateloader64.dll", "ntdll.dll"], "the chain names each module once in a row")
        check(dump?.summary == "0xc0000005 at 0x0, from nvapi64.dll+0x1120 ← physxupdateloader64.dll+0x113c ← ntdll.dll+0x53158",
              "the summary (\(dump?.summary ?? "–"))")
        check(dump?.modules.contains("ittakestwo.exe") == true && dump?.modules.count == 5, "module names without their folders, lower-cased")

        // A 32-bit game crashing inside Direct3D 9.
        let old = MadeDump(modules: [("C:\\Game\\game.exe", 0x40_0000, 0x10_0000), ("C:\\windows\\system32\\d3d9.dll", 0x7000_0000, 0x10_0000)],
                           address: 0x7000_1234, below: [0x7000_0005], stack: [3, 0x40_2222, 0x7000_0000], wide: false)
        let old32 = CrashDump.read(old.data())
        check(old32?.module == CrashDump.Frame(module: "d3d9.dll", offset: 0x1234), "32-bit: the module the address lies in")
        check(old32?.stack == [CrashDump.Frame(module: "game.exe", offset: 0x2222)], "32-bit: four-byte stack slots (\(old32?.stack ?? []))")
        check(old32?.summary == "0xc0000005 at 0x70001234, in d3d9.dll+0x1234 ← game.exe+0x2222", "… and its summary (\(old32?.summary ?? "–"))")

        // Broken files never crash the reader.
        check(CrashDump.read(Data()) == nil && CrashDump.read(Data("MDMP".utf8)) == nil, "empty and cut-off files: nothing")
        check(CrashDump.read(Data(repeating: 0x41, count: 4096)) == nil, "not a minidump: nothing")
        let whole = physx.data()
        for length in stride(from: 0, to: whole.count, by: 13) { _ = CrashDump.read(whole.prefix(length)) }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return seed
        }
        for _ in 0..<400 {
            var broken = whole
            for _ in 0..<(1 + Int(random() % 6)) { broken[Int(random() % UInt64(broken.count))] = UInt8(truncatingIfNeeded: random()) }
            _ = CrashDump.read(broken)
            _ = CrashDump.read(broken.dropFirst(Int(random() % 9)))  // a slice that doesn't start at 0
        }
        let file = work.appendingPathComponent("UE4Minidump.dmp")
        try whole.write(to: file)
        check(CrashDump.read(file) == dump, "read from a file")
        check(CrashDump.read(work.appendingPathComponent("none.dmp")) == nil, "no file: nothing")

        // MARK: The table

        func ids(_ finding: StartFinding) -> [String] { StartDiagnosis.diagnose(finding).map(\.id) }
        let physxDiagnosis = StartDiagnosis.diagnose(StartFinding(
            messages: ["Unhandled Exception: EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000000"], dumps: [dump!]))
        check(physxDiagnosis.map(\.id) == ["physx-update-loader"], "It Takes Two: the update loader, and only that (\(physxDiagnosis.map(\.id)))")
        check(physxDiagnosis.first?.remedy == .dllsOff(["physxupdateloader", "physxupdateloader64"]), "… answered by leaving it unloaded")
        check(physxDiagnosis.first?.line.hasPrefix("physx-update-loader: 0xc0000005 at 0x0, from nvapi64.dll+0x1120") == true
              && physxDiagnosis.first?.line.hasSuffix("→ keep physxupdateloader, physxupdateloader64 unloaded") == true,
              "its line names what was seen and what answers it")

        let nvidia = CrashDump.read(MadeDump(modules: modules, stack: [nvapi + 0x1120, game + 0x500]).data())!
        check(StartDiagnosis.diagnose(StartFinding(dumps: [nvidia])).map(\.remedy) == [.dllsOff(["nvapi64", "nvngx"])],
              "a crash out of nvapi64 without the loader: NVIDIA's interface stays out")
        let graphics = CrashDump.read(MadeDump(modules: modules, address: d3d11 + 0x77, stack: [game + 0x500]).data())!
        check(StartDiagnosis.diagnose(StartFinding(dumps: [graphics])).map(\.remedy) == [.nextLayer], "a crash inside d3d11.dll: another layer")
        check(ids(StartFinding(dumps: [old32!])) == ["graphics-crash"], "… and inside d3d9.dll")
        let illegal = CrashDump.read(MadeDump(modules: modules, code: CrashDump.illegalInstruction, address: game + 0x10).data())!
        check(StartDiagnosis.diagnose(StartFinding(dumps: [illegal])).map(\.remedy) == [.noAVX], "an illegal instruction: without AVX")
        check(ids(StartFinding(illegalInstruction: true)) == ["illegal-instruction"], "… also when only Wine's log says so")
        let own = CrashDump.read(MadeDump(modules: modules, address: game + 0x4242, stack: [game + 0x500, ntdll + 0x10]).data())!
        let unknown = StartDiagnosis.diagnose(StartFinding(messages: ["Fatal error!"], dumps: [own]))
        check(unknown.map(\.id) == ["crash"] && unknown.first?.remedy == nil, "a crash in the game's own code: said, nothing known to answer it")
        check(unknown.first?.line == "crash: 0xc0000005 at 0x140004242, in ittakestwo.exe+0x4242 ← ntdll.dll+0x10 → no remedy known",
              "… with where it came from (\(unknown.first?.line ?? "–"))")
        // A stale address deep in the stack doesn't make a crash in the game's code NVIDIA's.
        let stale = CrashDump.read(MadeDump(modules: modules, address: game + 1, stack: [game + 2, ntdll + 3, game + 4, ntdll + 5, nvapi + 6]).data())!
        check(ids(StartFinding(dumps: [stale])) == ["crash"], "nvapi64 far up the stack isn't the cause")

        // Hogwarts Legacy, 9.11.2026.
        let refused = StartDiagnosis.diagnose(StartFinding(messages: [
            "Assertion failed: bSingleRHI [File:WindowsDynamicRHI.cpp] -d3d12, -d3d11, -vulkan, and -opengl are mutually exclusive options"]))
        check(refused.map(\.id) == ["refused-switch"] && refused.first?.remedy == .dropArguments, "a refused switch: without the added ones")
        check(StartDiagnosis.diagnose(StartFinding(messages: ["This game requires DirectX 12."])).map(\.remedy) == [.layer(.d3dmetal)],
              "DirectX 12 asked for: D3DMetal")
        check(StartDiagnosis.diagnose(StartFinding(missingRuntimes: ["xact", "d3dx9"])).map(\.remedy) == [.runtimes(["xact", "d3dx9"])],
              "a missing DLL: its runtime")
        check(ids(StartFinding(graphicsFailed: true)) == ["graphics-failed"], "the layer said it can't draw")
        check(StartDiagnosis.diagnose(StartFinding(hung: true)).map(\.remedy) == [.nextWay], "no picture and no work: the next way")
        check(ids(StartFinding(messages: ["Fatal error!"])) == ["said"], "words no rule knows are still said")
        check(ids(StartFinding(messages: ["Fatal error!"], hung: true)) == ["hung"], "… unless something else explains the start")
        check(ids(StartFinding()).isEmpty, "nothing found, nothing said")
        check(ids(StartFinding(dumps: [dump!], missingRuntimes: ["xact"], hung: true)) == ["physx-update-loader", "missing-runtime", "hung"],
              "several things at once, the most exact first")
        check(Set(StartDiagnosis.rules.map(\.id)).count == StartDiagnosis.rules.count, "every rule has a name of its own")

        // MARK: Where a start's dumps are

        let prefix = work.appendingPathComponent("prefix", isDirectory: true)
        let install = work.appendingPathComponent("Game", isDirectory: true)
        try fm.createDirectory(at: install, withIntermediateDirectories: true)
        let started = Date(timeIntervalSinceNow: -60)
        func write(_ data: Data, _ path: String, age: TimeInterval = 0) throws {
            let file = prefix.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: file.path)
        }
        let crashes = "drive_c/users/someone/AppData/Local/ItTakesTwo/Saved/Crashes"
        func report(_ type: String) -> Data {
            Data("<Root><CrashType>\(type)</CrashType><ErrorMessage>Unhandled Exception: EXCEPTION_ACCESS_VIOLATION</ErrorMessage></Root>".utf8)
        }
        try write(report("Crash"), crashes + "/New/CrashContext.runtime-xml")
        try write(whole, crashes + "/New/UE4Minidump.dmp")
        try write(Data("log".utf8), crashes + "/New/Game.log")
        try write(report("Crash"), crashes + "/Old/CrashContext.runtime-xml", age: 600)
        try write(whole, crashes + "/Old/UE4Minidump.dmp", age: 600)
        try write(report("Ensure"), crashes + "/Ensure/CrashContext.runtime-xml")
        try write(whole, crashes + "/Ensure/UE4Minidump.dmp")
        try write(old.data(), "drive_c/users/someone/AppData/Local/Temp/Studio/Game/Crashes/Crash_2026-11-10_010203/crash.dmp")
        try write(old.data(), "drive_c/users/someone/AppData/Local/Temp/Studio/Game/Crashes/Crash_2026-11-01_010203/crash.dmp", age: 600)
        let found = GameLog.crashDumps(installDir: install, since: started, prefix: prefix).map { $0.deletingLastPathComponent().lastPathComponent }
        check(found.sorted() == ["Crash_2026-11-10_010203", "New"],
              "this start's dumps: beside Unreal's report and in Unity's folder – not older ones, not an ensure's (\(found))")
        let finding = StartDiagnosis.finding(logText: "0124:err:module:import_dll Library XINPUT1_3.dll (which is needed by L\"Z:\\\\Game\\\\x.exe\") not found",
                                             installDir: install, gameFolder: "Game", since: started, layer: .dxmt, hung: false, prefix: prefix)
        check(finding.dumps.count == 2 && finding.messages == ["Unhandled Exception: EXCEPTION_ACCESS_VIOLATION"],
              "a start's finding gathers its dumps and its words")
        check(StartDiagnosis.diagnose(finding).first?.id == "physx-update-loader", "… and the table reads it")

        // MARK: Kept for the problem report

        let defaults = TestDefaults.suite("diagnosis")
        StartDiagnosis.remember(["crash: somewhere → no remedy known"], for: .steam(1), defaults: defaults)
        check(StartDiagnosis.remembered(.steam(1), defaults: defaults) == ["crash: somewhere → no remedy known"]
              && StartDiagnosis.remembered(.steam(2), defaults: defaults).isEmpty, "the last start's diagnosis, per game")
        StartDiagnosis.remember([], for: .steam(1), defaults: defaults)
        check(StartDiagnosis.remembered(.steam(1), defaults: defaults).isEmpty, "a new start forgets it")

        // MARK: A game's sort

        check(GameKind.middleware(in: ["physx3_x64.dll", "physx3common_x64.dll", "steam_api64.dll", "bink2w64.dll", "binkies.png",
                                       "fmod.pak", "gfsdk_aftermath_lib.x64.dll", "wwise", "kernel32.dll", "galaxy_map.dll", "sl.interposer.dll"])
              == ["aftermath", "bink", "physx3", "steamworks", "streamline", "wwise"],
              "libraries by their DLLs and folders – a picture or a pack named alike isn't one")
        check(GameKind.middleware(in: ["physxloader.dll", "galaxy64.dll", "eossdk-win64-shipping.dll"]) == ["eos", "galaxy", "physx2"],
              "PhysX 2 apart from PhysX 3")
        check(GameKind.middleware(in: []).isEmpty, "nothing found, nothing named")
        check(GameKind.unrealVersion([4, 26, 0, 0]) == "4.26" && GameKind.unrealVersion([5, 4, 4, 0]) == "5.4", "Unreal's version, major and minor")
        check(GameKind.unrealVersion([1, 0, 2153, 883]) == nil && GameKind.unrealVersion(nil) == nil && GameKind.unrealVersion([4]) == nil,
              "a version that's the game's own isn't the engine's")
        check(GameKind.unityVersion(inHead: Data([0, 0, 0, 22, 0, 0]) + Data("2017.4.30f1\0\u{13}".utf8)) == "2017.4"
              && GameKind.unityVersion(inHead: Data("UnityFS\0\0\0\0\u{8}5.x.x\06000.3.10f1\0".utf8)) == "6000.3",
              "Unity's version from the head of its data")
        check(GameKind.unityVersion(inHead: Data("no version 1.2 here".utf8)) == nil && GameKind.unityVersion(inHead: Data()) == nil,
              "… or none")
        var analysis = GameAnalysis()
        analysis.engine = .unreal
        analysis.engineVersion = "4.26"
        analysis.apis = [.d3d12, .d3d11]
        analysis.middleware = ["steamworks", "physx3"]
        analysis.is64Bit = true
        check(analysis.kind.coarse == "unreal4|d3d11+d3d12", "the coarse sort (\(analysis.kind.coarse))")
        check(analysis.kind.fine == "unreal4.26|d3d11+d3d12|physx3+steamworks", "the fine sort (\(analysis.kind.fine))")
        check(analysis.kind.bits == 64 && !analysis.kind.antiCheat, "width and anti-cheat with it")
        check(GameAnalysis().kind.coarse == "other|" && GameAnalysis().kind.bits == nil, "a game nothing is known of")

        let program = work.appendingPathComponent("Game.exe")
        try madeProgram(version: [4, 27, 2, 0]).write(to: program)
        check(PEImports.facts(of: program)?.is64Bit == true && PEImports.facts(of: program)?.fileVersion == [4, 27, 2, 0],
              "a program's version resource (\(String(describing: PEImports.facts(of: program))))")
        try madeProgram(version: [1, 0, 0, 7], is64: false).write(to: program)
        check(PEImports.facts(of: program)?.is64Bit == false && PEImports.facts(of: program)?.fileVersion == [1, 0, 0, 7], "a 32-bit program's")
        try madeProgram(version: nil).write(to: program)
        check(PEImports.facts(of: program)?.is64Bit == true && PEImports.facts(of: program)?.fileVersion == nil, "no version resource: only its width")
        try Data("MZ, but nothing more".utf8).write(to: program)
        check(PEImports.facts(of: program) == nil, "not a program: nothing")
        let valid = madeProgram(version: [4, 27, 2, 0])
        for length in stride(from: 0, to: valid.count, by: 97) {
            try valid.prefix(length).write(to: program)
            _ = PEImports.facts(of: program)
        }

        // MARK: A start's recipe and its record

        let tested = profile(#"{"graphics": "d3dmetal", "arguments": ["-dx12"], "winetricks": ["xact"], "windowsVersion": "win10"}"#)
        let recipe = StartRecipe.of(layer: .d3dmetal, arguments: ["-nolauncher"], profile: tested, learnedRuntimes: ["d3dx9", "xact"],
                                    avx: true, d3dMetalEngine: true)
        check(recipe.graphics == "d3dmetal" && recipe.arguments == ["-nolauncher", "-dx12"], "a recipe: the layer, the way's arguments and the profile's")
        check(recipe.runtimes == ["d3dx9", "xact"] && recipe.avx && recipe.windowsVersion == "win10", "… its runtimes once each, AVX, the Windows version")
        check(recipe.dllOverrides["physxupdateloader64"] == "" && recipe.dllOverrides["d3d12"] == "builtin", "… and every DLL override the start gets")
        let other = StartRecipe.of(layer: .dxmt, arguments: ["-dx11"], profile: tested, learnedRuntimes: [], avx: false, d3dMetalEngine: true)
        check(other.arguments == ["-dx11"] && other.dllOverrides["d3d11"] == "native" && !other.avx,
              "on another layer the profile's arguments stay out")

        let record = work.appendingPathComponent("evidence.jsonl")
        StartEvidence.note(.started, game: .steam(1426210), way: "d3dmetal", engine: "winecx@4.7.3", known: false,
                           kind: analysis.kind, recipe: recipe, to: record)
        StartEvidence.note(.failed, game: .steam(1426210), way: "d3dmetal", reason: "Unhandled Exception",
                           diagnosis: physxDiagnosis.map(\.line), to: record)
        StartEvidence.note(.worked, game: .steam(1426210), way: "dxmt -dx11", diagnosis: [], to: record)
        let entries = StartEvidence.load(from: record)
        check(entries.count == 3 && entries[0].kind == analysis.kind && entries[0].recipe == recipe, "a start is recorded with its sort and its recipe")
        check(entries[1].diagnosis?.first?.hasPrefix("physx-update-loader:") == true && entries[1].kind == nil, "a failure with its diagnosis")
        check(entries[2].diagnosis == nil, "no diagnosis, no field")
        // A line from before 10.11.2026 still reads.
        let before = #"{"at":"2026-11-09T21:58:47Z","engine":"winecx@4.7.3","event":"started","game":"steam.1426210","known":false,"mac":"Apple M5 · macOS 27.0","way":"d3dmetal"}"#
        try Data((before + "\n").utf8).write(to: record)
        let earlier = StartEvidence.load(from: record)
        check(earlier.count == 1 && earlier[0].kind == nil && earlier[0].recipe == nil && earlier[0].way == "d3dmetal", "a record from before reads as it was")

        print(failures == 0 ? "✓ StartDiagnosis" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
