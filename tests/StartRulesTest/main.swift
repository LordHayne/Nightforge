// Checks how a start is chosen and what it learns, with the games of the test evening of 9.11.2026 as
// cases: what the files decide, reports, what a game says when it crashes, and the record of first starts.
import Foundation

@main
struct StartRulesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func profile(_ json: String?) -> GameProfile? {
        json.flatMap { try? JSONDecoder().decode(GameProfile.self, from: Data($0.utf8)) }
    }

    static func ids(_ analysis: GameAnalysis, hint: SourceHint? = nil, profile json: String? = nil, d3dMetal: Bool = true) -> [String] {
        LaunchHealth.attempts(for: analysis, profile: profile(json), hint: hint, d3dMetal: d3dMetal, vulkanLayer: true,
                              kosmicKrisp: false).map(\.id)
    }

    static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("start-rules-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func crashReport(_ type: String, _ message: String, in folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let xml = "<FGenericCrashContext><RuntimeProperties><CrashType>\(type)</CrashType>"
            + "<ErrorMessage>\(message)</ErrorMessage></RuntimeProperties></FGenericCrashContext>"
        try? Data(xml.utf8).write(to: folder.appendingPathComponent("CrashContext.runtime-xml"))
    }

    static func main() {
        TestDefaults.useWorkFolder()
        let highballD3DMetal = SourceHint(graphics: .d3dmetal, source: "highball")
        let unreal = GameAnalysis(apis: [.d3d9, .d3d11, .d3d12, .openGL], engine: .unreal)  // Hogwarts Legacy, ABZU, REANIMAL
        let bothNoSwitch = GameAnalysis(apis: [.d3d11, .d3d12])  // Guardians of the Galaxy, Control, Overwatch

        // MARK: The files decide where nothing else does
        check(ids(bothNoSwitch) == ["d3dmetal", "dxmt", "dxvk"], "DirectX 12 and no known switch: the game picks 12 by itself, D3DMetal first")
        check(ids(GameAnalysis()) == ["d3dmetal", "dxmt", "dxvk", "wined3d"],
              "files that say nothing: D3DMetal runs DirectX 11 and 12 – and Wine's own Direct3D is the last way, should it be DirectX 9")
        // Alan Wake, 11.11.2026: 32-bit, nothing detected, and it draws with Direct3D 9.
        let old = GameAnalysis(is64Bit: false)
        check(ids(old) == ["dxvk", "wined3d", "dxmt", "d3dmetal"], "… a 32-bit game's ways in Direct3D 9's order (\(ids(old)))")
        check(LaunchHealth.attempts(for: old, profile: nil, d3dMetal: true, vulkanLayer: false, kosmicKrisp: false).map(\.id)
              == ["wined3d", "dxmt", "dxvk", "d3dmetal"], "… under winecx, where DXVK gets no Direct3D 9 device: Wine's own first")
        check(ids(old, profile: #"{"graphics": "dxmt"}"#) == ["dxmt", "dxvk", "d3dmetal", "wined3d"], "a profile's layer still goes first")
        check(LaunchHealth.attempts(for: old, profile: nil, d3dMetal: true, vulkanLayer: false, kosmicKrisp: false, filesDecide: false)
              .map(\.id) == ["dxmt", "dxvk", "d3dmetal", "wined3d"], "the list from before the files decided only grows at its end")
        check(ids(GameAnalysis(apis: [.d3d11], is64Bit: false)) == ["dxmt", "dxvk", "d3dmetal"], "a 32-bit game that shows DirectX 11: as before")
        check(LaunchHealth.plan("Old", attempts: LaunchHealth.attempts(for: old, profile: nil, d3dMetal: true, vulkanLayer: false, kosmicKrisp: false),
                                index: 0, confirmed: false, analysis: old, profile: nil, hint: nil, source: nil)
              .hasSuffix("now wined3d, its files show nothing, and a 32-bit game mostly draws with DirectX 9"), "… and the plan says why")
        check(ids(GameAnalysis(apis: [.d3d12])) == ["d3dmetal"], "DirectX 12 only (GTA V Enhanced): D3DMetal alone")
        check(ids(GameAnalysis(apis: [.d3d11])) == ["dxmt", "dxvk", "d3dmetal"], "DirectX 11 only: as before")
        check(ids(unreal).first == "dxmt -dx11", "Unreal: held to DirectX 11, as measured with ABZU and REANIMAL")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity)).first == "dxmt -force-d3d11", "Unity: held to DirectX 11")
        check(ids(bothNoSwitch, d3dMetal: false) == ["dxmt", "dxvk"], "an engine without D3DMetal: the usual ways")

        // MARK: Profiles and reports come before the files
        check(ids(bothNoSwitch, profile: #"{"graphics": "dxmt"}"#).first == "dxmt", "Overwatch's profile keeps it on DXMT")
        check(ids(bothNoSwitch, hint: SourceHint(graphics: .dxmt, source: "highball")) == ["dxmt", "dxvk", "d3dmetal"],
              "Just Cause 4: Highball's report goes before what the files suggest")
        check(ids(unreal, hint: highballD3DMetal) == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"], "Hogwarts Legacy: Highball's D3DMetal goes before -dx11")
        check(ids(unreal, hint: SourceHint(graphics: .d3dmetal)).first == "dxmt -dx11", "the wiki's reports don't overrule the measured switch")
        check(LaunchHealth.hinted(highballD3DMetal, analysis: GameAnalysis(apis: [.d3d9])) == nil, "a report doesn't fit DirectX 9")

        // MARK: What's proven stays
        let proven = GameID.steam(991_001)
        LaunchHealth.reset(proven)
        func listed(_ hint: SourceHint? = nil) -> (attempts: [LaunchAttempt], hint: GraphicsLayer?) {
            LaunchHealth.attempts(for: bothNoSwitch, profile: nil, hint: hint, game: proven, preset: .automatic, d3dMetal: true,
                                  vulkanLayer: true, kosmicKrisp: false)
        }
        check(listed().attempts.first?.graphics == .d3dmetal, "never started: the new list")
        let older = LaunchHealth.attempts(for: bothNoSwitch, profile: nil, d3dMetal: true, vulkanLayer: true, kosmicKrisp: false, filesDecide: false)
        LaunchHealth.confirm(proven, older)
        check(listed().attempts == older && LaunchHealth.current(proven, older) == (0, true), "a way proven on the old list isn't given up")
        check(listed(highballD3DMetal).attempts == older, "…nor for a report")
        LaunchHealth.reset(proven)
        LaunchHealth.recordStart(proven, older)
        check(listed().attempts.first?.graphics == .d3dmetal, "still looking for its way: the new list")
        LaunchHealth.reset(proven)

        // MARK: What the game says
        let refused = "LowLevelFatalError [File:Unknown] [Line: 192] -d3d12, -d3d11, -vulkan, and -opengl are mutually exclusive options, but more than one was specified on the command-line."
        check(StartFailure.read([refused]) == .refusedSwitch, "Hogwarts Legacy's crash text")
        check(StartFailure.read(["This game requires DirectX 12."]) == .needsD3D12, "a game that says it needs DirectX 12")
        check(StartFailure.read(["Access violation at 0x0"]) == nil, "other crashes say nothing about the way")
        check(StartFailure.read([]) == nil, "nothing said")
        // Direct3D 9 on a way whose Direct3D 9 is DXVK's.
        let noDevice = "[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice()\nerr:   DxvkAdapter: Failed to create device\n"
        check(GameLog.direct3D9Failed(in: noDevice, layer: .d3dmetal) && GameLog.direct3D9Failed(in: noDevice, layer: .dxmt),
              "DXVK without a device on D3DMetal or DXMT: the game draws with Direct3D 9")
        check(!GameLog.direct3D9Failed(in: noDevice, layer: .dxvk) && !GameLog.direct3D9Failed(in: noDevice, layer: .wined3d)
              && !GameLog.direct3D9Failed(in: "all fine", layer: .d3dmetal), "not on DXVK's own way, not on Wine's, not without the lines")
        check(StartFailure.needsD3D9.answered(by: LaunchAttempt(graphics: .wined3d))
              && !StartFailure.needsD3D9.answered(by: LaunchAttempt(graphics: .dxvk)), "answered by Wine's own Direct3D only")
        let alanWake = GameID.steam(991_003)
        let unknownWays = LaunchHealth.attempts(for: GameAnalysis(), profile: nil, d3dMetal: true, vulkanLayer: false, kosmicKrisp: false)
        LaunchHealth.reset(alanWake)
        check(LaunchHealth.advance(alanWake, unknownWays, answering: .needsD3D9)
              && unknownWays[LaunchHealth.current(alanWake, unknownWays).index].id == "wined3d", "… and the ladder goes straight to it, past DXMT and DXVK")
        LaunchHealth.reset(alanWake)
        let hogwarts = GameID.steam(991_002)
        let ways = LaunchHealth.attempts(for: unreal, profile: nil, d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        LaunchHealth.reset(hogwarts)
        check(LaunchHealth.advance(hogwarts, ways, answering: .refusedSwitch), "there is a way without the switch")
        check(ways[LaunchHealth.current(hogwarts, ways).index].id == "d3dmetal", "…and it skips DXVK, which has the same switch")
        LaunchHealth.reset(hogwarts)
        check(LaunchHealth.advance(hogwarts, ways, answering: nil) && LaunchHealth.current(hogwarts, ways).index == 1, "nothing said: simply the next way")
        LaunchHealth.reset(hogwarts)
        let noD3DMetal = LaunchHealth.attempts(for: unreal, profile: nil, d3dMetal: false, vulkanLayer: true, kosmicKrisp: false)
        check(LaunchHealth.advance(hogwarts, noD3DMetal, answering: .needsD3D12) && LaunchHealth.current(hogwarts, noD3DMetal).index == 1,
              "no way answers it: the next one all the same")
        LaunchHealth.reset(hogwarts)

        // MARK: Crash reports, wherever they are
        let prefix = folder(), game = folder()
        let before = Date().addingTimeInterval(-5)
        let local = prefix.appendingPathComponent("drive_c/users/player/AppData/Local/HogwartsLegacy/Saved/Crashes")
        crashReport("Assert", refused, in: local.appendingPathComponent("A"))
        crashReport("Ensure", "Ensure condition failed", in: local.appendingPathComponent("B"))
        check(GameLog.crashMessages(installDir: game, since: before, prefix: prefix) == [refused], "the report in AppData counts, the ensure doesn't")
        check(GameLog.crashReports(installDir: game, since: Date().addingTimeInterval(60), prefix: prefix).isEmpty, "an older report isn't this start's")
        crashReport("Crash", "in the game's folder", in: game.appendingPathComponent("Saved/Crashes/C"))
        check(GameLog.crashMessages(installDir: game, since: before, prefix: prefix).contains("in the game's folder"), "the game's own folder counts too")
        check(GameLog.crashContext("<CrashType>Assert</CrashType>").message == nil, "no message: nil")
        check(GameLog.crashContext("nothing").type == nil, "no report: nil")

        // MARK: A question on a way that can't draw the game
        check(LaunchHealth.layerCannotDraw(bothNoSwitch, layer: .dxmt), "\"no suitable adapter\" on DXMT is no choice of the player's")
        check(!LaunchHealth.layerCannotDraw(bothNoSwitch, layer: .d3dmetal), "on D3DMetal the player's answer stands")
        check(!LaunchHealth.layerCannotDraw(GameAnalysis(apis: [.d3d11]), layer: .dxmt), "a game without DirectX 12: it stands")
        check(!LaunchHealth.layerCannotDraw(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity), layer: .dxmt), "Unity's window: Quit means quit")
        check(!LaunchHealth.layerCannotDraw(nil, layer: .dxmt), "nothing known: it stands")

        // MARK: The reports: all that say how
        func report(_ rating: AGWEntry.Rating, _ graphics: [GraphicsLayer], date: String?, versions: [String] = []) -> AGWEntry.Report {
            AGWEntry.Report(rating: rating, versions: versions, graphics: graphics, date: date)
        }
        var entry = AGWEntry(page: "It Takes Two")
        entry.reports = [.crossover: report(.perfect, [.dxvk], date: "2026-02-23", versions: ["CrossOver 23.71"]),
                         .wine: report(.playable, [.d3dmetal], date: "2023-07-15", versions: ["GPTK"])]
        check(entry.weightedHint?.graphics == .dxvk, "the newer report decides")
        entry.reports = [.crossover: report(.perfect, [.dxvk], date: "2023-01-01", versions: ["CrossOver 22.1"])]
        check(entry.weightedHint == nil, "DXVK from before DXMT existed says nothing against DXMT")
        entry.reports = [.crossover: report(.perfect, [.dxvk], date: "2023-01-01", versions: ["CrossOver 24.0"])]
        check(entry.weightedHint?.graphics == .dxvk, "…from a CrossOver that had DXMT it does")
        entry.reports = [.crossover: report(.perfect, [.d3dmetal], date: "2025-01-01"), .wine: report(.unplayable, [.d3dmetal], date: "2025-06-01")]
        check(entry.weightedHint == nil, "a newer bad report takes the layer out")
        entry.reports = [.crossover: report(.perfect, [.d3dmetal], date: "2025-01-01"), .wine: report(.perfect, [.dxmt], date: "2025-01-01")]
        check(entry.weightedHint == nil, "a tie says nothing")
        entry.reports = [.crossover: report(.perfect, [.d3dmetal], date: "2025-01-01"), .wine: report(.playable, [.dxmt], date: "2025-01-01")]
        check(entry.weightedHint?.graphics == .d3dmetal, "same day: perfect before playable")
        entry.reports = [.native: report(.perfect, [.d3dmetal], date: "2026-01-01")]
        check(entry.weightedHint == nil, "only ways through Wine count")
        entry.hint = SourceHint(graphics: .dxmt)
        check(entry.weightedHint?.graphics == .dxmt, "the wiki's clear reading stays first")

        let list = Data(#"{"formatVersion":1,"games":{},"reported":{"1088850":{"graphics":"d3dmetal","status":"verified-local"},"x":{"graphics":"dxmt"},"7":{"graphics":"odd"}}}"#.utf8)
        let reported = ProfileStore.decodeReported(list)
        check(reported.count == 1 && reported[1_088_850] == SourceHint(graphics: .d3dmetal, source: "highball"), "the list's reports: odd ones cost only themselves")
        check(ProfileStore.decodeReported(Data(#"{"formatVersion":1,"games":{}}"#.utf8)).isEmpty, "a list without them")

        // MARK: What PCGamingWiki lists
        var wiki = AGWIndex()
        wiki.directX = ["990080": ["12"], "870780": ["11", "12"]]
        check(wiki.directXHint(steamAppID: 990_080) == SourceHint(graphics: .d3dmetal, directX: "12", source: "pcgw"), "only DirectX 12: D3DMetal")
        check(wiki.directXHint(steamAppID: 870_780) == nil, "DirectX 11 as well: it says nothing about the way")
        check(wiki.directXHint(steamAppID: 1) == nil && wiki.directXHint(steamAppID: nil) == nil, "not listed: nothing")
        check(ids(unreal, hint: wiki.directXHint(steamAppID: 990_080)) == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"], "it goes before the Unreal switch")
        check(SourceHint.name(of: "pcgw") == "PCGamingWiki" && SourceHint.name(of: "agw") == "AppleGamingWiki", "the sources by name")
        let decoded = AGWIndex.decode(Data(#"{"formatVersion":1,"games":{},"directX":{"990080":["12"]}}"#.utf8))
        check(decoded?.directX["990080"] == ["12"], "the wiki list brings them along")
        check(AGWIndex.decode(Data(#"{"formatVersion":1,"games":{}}"#.utf8))?.directX.isEmpty == true, "a list without them still reads")

        // MARK: Runtimes before the first start (Mafia II and PhysX)
        var known = AGWIndex()
        known.runtimes = ["50130": ["physx"], "gog.1816059595": ["physx"]]
        check(known.runtimes(steamAppID: 50130, gogID: nil) == ["physx"], "the Steam version")
        check(known.runtimes(steamAppID: nil, gogID: "1816059595") == ["physx"], "the GOG version by its own ID")
        check(known.runtimes(steamAppID: 50130, gogID: "1816059595") == ["physx"], "both: once")
        check(known.runtimes(steamAppID: 1, gogID: nil).isEmpty, "a game without: nothing")
        check(AGWIndex.decode(Data(#"{"formatVersion":1,"games":{},"runtimes":{"50130":["physx"]}}"#.utf8))?.runtimes(steamAppID: 50130, gogID: nil) == ["physx"],
              "the wiki list brings them along")

        // MARK: A program that hides what it links
        let hidden = folder()
        var bytes = Data(count: 64)
        bytes += Data("...D3D12CreateDevice...d3d11.dll...d3d9.dll...vulkan-1.dll...".utf8)
        try? bytes.write(to: hidden.appendingPathComponent("Game.exe"))
        check(GameAnalysis.analyze(installDir: hidden, launchExecutable: nil).apis == [.d3d11, .d3d12],
              "text names DirectX 11 and 12: those, not what overlays and tools need")
        let dx9 = folder()
        try? Data("Direct3DCreate9".utf8).write(to: dx9.appendingPathComponent("Old.exe"))
        check(GameAnalysis.analyze(installDir: dx9, launchExecutable: nil).apis == [.d3d9], "only DirectX 9 named: DirectX 9")
        let split = folder().appendingPathComponent("Big.exe")
        var across = Data(count: (16 << 20) - 5)  // the name lies across two pieces
        across += Data("D3D12CreateDevice".utf8)
        try? across.write(to: split)
        check(ProgramText.apis(in: split) == [.d3d12], "a name across two pieces is found")
        check(ProgramText.apis(in: hidden.appendingPathComponent("none.exe")).isEmpty, "no file: nothing")

        // MARK: Past the game's own launcher window
        // Guardians of the Galaxy (9.11.2026): Play, Options, YouTube in a window of its own, out of the pad's
        // reach; its gotg.exe holds "-nolauncher" and "-NoLauncher".
        let guardians = folder()
        try? Data("..UseLauncher..-NoLauncher..-nolauncher..d3d12.dll..".utf8).write(to: guardians.appendingPathComponent("gotg.exe"))
        check(GameAnalysis.analyze(installDir: guardians, launchExecutable: "gotg.exe").launcherSwitch == "-nolauncher", "the switch the program knows")
        let camel = folder()
        try? Data("..-NoLauncher..".utf8).write(to: camel.appendingPathComponent("Game.exe"))
        check(ProgramText.launcherSwitch(in: camel.appendingPathComponent("Game.exe")) == "-NoLauncher", "as the program spells it")
        let plain = folder()
        try? Data("..UseLauncher..launcher_play..".utf8).write(to: plain.appendingPathComponent("Game.exe"))
        check(GameAnalysis.analyze(installDir: plain, launchExecutable: "Game.exe").launcherSwitch == nil, "a launcher's words without the switch: none")
        check(LibraryModel.argumentsPastLauncher(["-dx12"], switch: "-nolauncher") == ["-dx12", "-nolauncher"], "after the way's own")
        check(LibraryModel.argumentsPastLauncher(["-NOLAUNCHER"], switch: "-nolauncher") == ["-NOLAUNCHER"], "never twice")
        check(LibraryModel.argumentsPastLauncher([], switch: nil) == [], "none without")

        // MARK: The log says why
        let plan = LaunchHealth.plan("Guardians", attempts: [LaunchAttempt(graphics: .d3dmetal), LaunchAttempt(graphics: .dxmt)], index: 0, confirmed: false,
                                     analysis: bothNoSwitch, profile: nil, hint: nil, source: nil)
        check(plan.contains("d3dmetal, dxmt") && plan.contains("no switch"), "the plan names the ways and why: \(plan)")
        func why(_ analysis: GameAnalysis, index: Int = 0, confirmed: Bool = false, profile json: String? = nil, hint: GraphicsLayer? = nil, highball: Bool = false,
                 way: LaunchAttempt = LaunchAttempt(graphics: .d3dmetal)) -> String {
            LaunchHealth.plan("X", attempts: [way, way], index: index, confirmed: confirmed, analysis: analysis, profile: profile(json), hint: hint, source: highball ? "highball" : "agw")
        }
        check(why(bothNoSwitch, confirmed: true).contains("worked on this Mac"), "proven")
        check(why(bothNoSwitch, index: 1).contains("before it didn't work"), "a later way")
        check(why(bothNoSwitch, profile: #"{"graphics": "d3dmetal"}"#).contains("profile"), "a profile")
        check(why(bothNoSwitch, hint: .d3dmetal, highball: true).contains("Highball"), "Highball")
        check(why(bothNoSwitch, hint: .d3dmetal).contains("AppleGamingWiki"), "the wiki")
        check(why(GameAnalysis(apis: [.d3d12])).contains("DirectX 12 only"), "only 12")
        check(why(GameAnalysis()).contains("show nothing"), "nothing known")
        check(why(unreal, way: LaunchAttempt(graphics: .dxmt, arguments: ["-dx11"])).contains("held to DirectX 11"), "the switch")
        check(why(GameAnalysis(apis: [.d3d11]), way: LaunchAttempt(graphics: .dxmt)).contains("usual first way"), "the usual way")

        // MARK: A Steam restart doesn't take a store's game with it (Guardians, ABZU, 9.11.2026)
        check(Engine.gameKeepsSession([#"z:\\volumes\\games\\nightforge games\\epic games\\marvelgotg\\retail\\gotg.exe"#.replacingOccurrences(of: #"\\"#, with: #"\"#)]), "an Epic game keeps the session")
        check(Engine.gameKeepsSession([#"c:\gog games\mafia ii\mafia2.exe"#]), "a GOG game too")
        check(Engine.gameKeepsSession([#"z:\x\steamapps\common\game\game.exe"#]), "a Steam game too")
        check(!Engine.gameKeepsSession([#"c:\program files (x86)\steam\bin\cef\steamwebhelper.exe"#, "/path/wineserver"]), "only Steam's own: nothing keeps it")
        let began = Date()
        check(!Engine.steamHadTimeToHang(began: began, quietFor: 45, now: began.addingTimeInterval(25)), "25 s after its start, quiet logs are the last session's")
        check(Engine.steamHadTimeToHang(began: began, quietFor: 45, now: began.addingTimeInterval(45)), "after 45 s they say something")

        // MARK: No picture means it didn't start (It Takes Two, 9.11.2026)
        var quiet = PictureWatch()
        var cpu: TimeInterval = 10
        func run(_ watch: inout PictureWatch, seconds: Int, cpuPerLook: TimeInterval, asked: Bool = false) -> PictureWatch.Step {
            var last = PictureWatch.Step.wait
            for _ in stride(from: 0, to: seconds, by: 5) where last == .wait {
                cpu += cpuPerLook
                last = watch.look(span: 5, cpu: cpu, playerAsked: asked)
            }
            return last
        }
        check(run(&quiet, seconds: 85, cpuPerLook: 0) == .wait, "85 s of nothing: still waiting")
        check(run(&quiet, seconds: 15, cpuPerLook: 0) == .hung, "after 90 s of nothing it's a hang")
        var shaders = PictureWatch()
        check(run(&shaders, seconds: 265, cpuPerLook: 4) == .wait, "building shaders: it waits")
        check(run(&shaders, seconds: 10, cpuPerLook: 4) == .hung, "…but not for ever")
        var pausing = PictureWatch()
        check(run(&pausing, seconds: 60, cpuPerLook: 0) == .wait && run(&pausing, seconds: 20, cpuPerLook: 4) == .wait, "work again")
        check(run(&pausing, seconds: 85, cpuPerLook: 0) == .wait, "the idle time starts over after work")
        var asked = PictureWatch()
        check(run(&asked, seconds: 600, cpuPerLook: 0, asked: true) == .wait, "a question stands: the time isn't the game's")
        check(run(&asked, seconds: 85, cpuPerLook: 0) == .wait, "…and doesn't count afterwards")
        var unknown = PictureWatch()
        var result = PictureWatch.Step.wait
        for _ in 0..<200 where result == .wait { result = unknown.look(span: 5, cpu: nil, playerAsked: false) }
        check(result == .wait, "no process to ask: nothing is ended")
        check(PictureWatch.isPicture(windowSize: "1512×982") && PictureWatch.isPicture(windowSize: "790×445"), "a window that size is a picture")
        check(!PictureWatch.isPicture(windowSize: "98×108") && !PictureWatch.isPicture(windowSize: nil), "It Takes Two's speck isn't")
        check(GameProcesses.cpuSeconds([]) == nil, "no process: no figure")
        check((GameProcesses.cpuSeconds([getpid()]) ?? -1) > 0, "this process has used some")

        // MARK: First starts, the number that counts
        let file = folder().appendingPathComponent("evidence.jsonl")
        func started(_ id: Int, _ way: String, known: Bool = false) {
            StartEvidence.note(.started, game: .steam(id), way: way, engine: "winecx@4.7.3", known: known, to: file)
        }
        started(1, "d3dmetal")
        StartEvidence.note(.worked, game: .steam(1), way: "d3dmetal", to: file)
        started(2, "dxmt -dx11")
        StartEvidence.note(.failed, game: .steam(2), way: "dxmt -dx11", reason: "crash in C:\\users\\someone\\x, token=abc", to: file)
        started(2, "d3dmetal")
        StartEvidence.note(.worked, game: .steam(2), way: "d3dmetal", to: file)
        started(3, "dxmt")
        StartEvidence.note(.gaveUp, game: .steam(3), way: "dxmt", to: file)
        started(4, "dxmt")
        started(5, "dxmt", known: true)
        StartEvidence.note(.worked, game: .steam(5), way: "dxmt", to: file)
        started(1, "d3dmetal", known: true)
        let entries = StartEvidence.load(from: file)
        check(StartEvidence.summary(entries) == StartEvidence.Summary(firstWay: 1, laterWay: 1, noWay: 1, open: 1),
              "one on the first way, one later, one on none, one open; a game already proven doesn't count: \(StartEvidence.summary(entries))")
        check(entries.first?.engine == "winecx@4.7.3" && entries.first?.mac?.contains("macOS") == true, "a start says on what it ran")
        // … and on which state: Nightforge's version, the engine's parts, the game's name (the list of games that run).
        do {
            let stated = folder().appendingPathComponent("stated.jsonl")
            StartEvidence.note(.started, game: .steam(35140), way: "wined3d", engine: "winecx@4.7.3", known: false,
                               name: "Batman: Arkham Asylum GOTY Edition", parts: ["winecx@4.7.3", "graphics@11.18-dxmt0.80-17"], to: stated)
            StartEvidence.note(.worked, game: .steam(35140), way: "wined3d", name: "Batman: Arkham Asylum GOTY Edition", parts: ["winecx@4.7.3"], to: stated)
            let old = #"{"at":"2026-11-09T22:45:04Z","engine":"winecx@4.7.3","event":"started","game":"steam.1","known":false,"mac":"Apple M5 · macOS 27.0","way":"dxmt"}"#
            if let handle = try? FileHandle(forWritingTo: stated) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data((old + "\n").utf8))
                try? handle.close()
            }
            let read = StartEvidence.load(from: stated)
            check(read.count == 3 && read[0].name == "Batman: Arkham Asylum GOTY Edition" && read[0].nightforge == Updater.currentVersion
                  && read[0].parts == ["winecx@4.7.3", "graphics@11.18-dxmt0.80-17"], "a start names the game, the version and the engine's parts: \(read.first.map(String.init(describing:)) ?? "-")")
            check(read[0].built != nil && abs((read[0].built ?? .distantPast).timeIntervalSince(Updater.currentBuilt ?? .distantFuture)) <= 1,
                  "… and when this Nightforge was built, to the second")
            check(read[1].name == nil && read[1].parts == nil && read[1].nightforge == nil && read[1].built == nil, "only a start says them")
            check(read[2].way == "dxmt" && read[2].nightforge == nil && read[2].name == nil && read[2].parts == nil,
                  "a line from before 14.11. reads as it did")
            let text = (try? String(contentsOf: stated, encoding: .utf8)) ?? ""
            check(!text.contains(NSHomeDirectory()) && !text.contains(NSUserName() + "/"), "nothing of the player in it")
        }
        check(entries.first(where: { $0.event == .failed })?.reason?.contains("abc") == false, "what the game said, without secrets")
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("not json\n".utf8))
            try? handle.close()
        }
        check(StartEvidence.load(from: file).count == entries.count, "a broken line costs only itself")
        check(StartEvidence.load(from: file.appendingPathExtension("none")).isEmpty, "no record yet")

        // MARK: Every recorded start gets an outcome
        let outcomes = file.deletingLastPathComponent().appendingPathComponent("outcomes-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: outcomes) }
        StartEvidence.note(.started, game: .steam(7), way: "wined3d", known: false, to: outcomes)
        StartEvidence.note(.ended, game: .steam(7), way: "wined3d", reason: "ended before it counted as working", picture: true, seconds: 74, to: outcomes)
        StartEvidence.note(.started, game: .steam(8), way: "d3dmetal", known: false, to: outcomes)
        StartEvidence.note(.ended, game: .steam(8), way: "d3dmetal", reason: "closed at a question of its own", diagnosis: ["said: Failed to load SteamAPI"],
                           picture: false, seconds: 12, to: outcomes)
        let ended = StartEvidence.load(from: outcomes)
        check(ended.count == 4 && ended[1].event == .ended && ended[1].picture == true && ended[1].seconds == 74, "an end with a picture, and how long it ran")
        check(ended[3].picture == false && ended[3].diagnosis == ["said: Failed to load SteamAPI"] && ended[3].reason == "closed at a question of its own",
              "an end at the game's own question, with what was found")
        check(StartEvidence.summary(ended) == StartEvidence.Summary(firstWay: 0, laterWay: 0, noWay: 0, open: 2), "an end is neither worked nor given up")

        // MARK: What a sort of game has proven (docs/ENTWURF-STARTREZEPT.md, stage 4)
        func kind(_ engine: String, _ version: String?, _ apis: [String], _ middleware: [String] = []) -> GameKind {
            GameKind(engine: engine, engineVersion: version, apis: apis, middleware: middleware, launcher: nil, antiCheat: false, bits: 64)
        }
        let both = ["d3d11", "d3d12"]
        let ue427 = kind("unreal", "4.27", both)
        check(StartEvidence.kinship(ue427, ue427) == 4, "the same sort in full")
        check(StartEvidence.kinship(ue427, kind("unreal", "4.27", both, ["physx3"])) == 3, "the same engine version and interfaces, other libraries")
        check(StartEvidence.kinship(ue427, kind("unreal", "4.26", both)) == 2, "the same generation and interfaces")
        check(StartEvidence.kinship(ue427, kind("unreal", "4.12", ["d3d9", "d3d11"])) == 1, "the same generation")
        check(StartEvidence.kinship(ue427, kind("unreal", "5.4", both)) == 0 && StartEvidence.kinship(ue427, kind("unity", "4.27", both)) == 0,
              "another generation or another engine: no kin")
        check(StartEvidence.kinship(kind("other", nil, ["d3d11"]), kind("other", nil, ["d3d11"])) == 0, "an engine nobody knows is no sort")
        check(StartEvidence.kinship(kind("unreal", nil, both), kind("unreal", nil, both)) == 0, "nor is one whose version isn't known")
        check(kind("unreal", "4.27", both).generation == "unreal4" && kind("unity", "2017.4", []).generation == "unity2017" && kind("unreal", nil, []).generation == nil,
              "the generation: engine and major version")

        let sorts = file.deletingLastPathComponent().appendingPathComponent("sorts-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: sorts) }
        // Hogwarts Legacy as it went: -dx11 refused, D3DMetal worked.
        StartEvidence.note(.started, game: .steam(11), way: "dxmt -dx11", known: false, kind: ue427, to: sorts)
        StartEvidence.note(.failed, game: .steam(11), way: "dxmt -dx11", reason: "mutually exclusive", to: sorts)
        StartEvidence.note(.started, game: .steam(11), way: "d3dmetal", known: false, kind: ue427, to: sorts)
        StartEvidence.note(.worked, game: .steam(11), way: "d3dmetal", to: sorts)
        // A game on its proven way: one more time it worked.
        StartEvidence.note(.started, game: .steam(12), way: "d3dmetal", known: true, kind: kind("unreal", "4.26", both), to: sorts)
        // One that reached a picture and was quit.
        StartEvidence.note(.started, game: .steam(13), way: "dxmt -dx11", known: false, kind: kind("unreal", "4.12", ["d3d9", "d3d11"]), to: sorts)
        StartEvidence.note(.ended, game: .steam(13), way: "dxmt -dx11", picture: true, seconds: 80, to: sorts)
        // Another engine, and a start from before sorts were recorded.
        StartEvidence.note(.started, game: .steam(14), way: "dxmt", known: false, kind: kind("unity", "2017.4", ["d3d11"]), to: sorts)
        StartEvidence.note(.worked, game: .steam(14), way: "dxmt", to: sorts)
        StartEvidence.note(.started, game: .steam(15), way: "dxvk -dx11", known: false, to: sorts)
        StartEvidence.note(.worked, game: .steam(15), way: "dxvk -dx11", to: sorts)
        let proofs = StartEvidence.proofs(StartEvidence.load(from: sorts))
        check(proofs["steam.11"] == StartEvidence.Proof(kind: ue427, worked: ["d3dmetal"], failed: ["dxmt -dx11"]), "a game's proof: what worked and what failed")
        check(proofs["steam.12"]?.worked == ["d3dmetal"] && proofs["steam.13"]?.picture == ["dxmt -dx11"] && proofs["steam.15"]?.kind == nil,
              "a proven way started again counts, a picture counts as one, a start without its sort has none")
        let scores = StartEvidence.sortScores(for: ue427, excluding: "steam.99", proofs: proofs)
        check(scores["d3dmetal"] == StartEvidence.SortScore(points: 12, games: 2), "D3DMetal: the same sort (2×4) and its generation (2×2) (\(String(describing: scores["d3dmetal"])))")
        check(scores["dxmt -dx11"] == StartEvidence.SortScore(points: 1, games: 1),
              "DXMT held to 11: a picture for a cousin (+1) – that it failed for the same sort doesn't count against it")
        check(scores["dxmt"] == nil && scores["dxvk -dx11"] == nil, "Unity's proof and one without a sort say nothing about it")
        check(StartEvidence.sortScores(for: ue427, excluding: "steam.11", proofs: proofs)["d3dmetal"] == StartEvidence.SortScore(points: 4, games: 1),
              "a game's own starts aren't its sort's")
        check(StartEvidence.sortScores(for: kind("other", nil, both), excluding: "x", proofs: proofs).isEmpty, "nothing for a game without a sort")
        check(StartEvidence.sortScores(for: ue427, excluding: "steam.99", file: sorts) == scores
              && StartEvidence.sortScores(for: ue427, excluding: "steam.99", file: sorts) == scores, "read from the record, and again from memory")
        StartEvidence.note(.started, game: .steam(16), way: "dxvk -dx11", known: true, kind: ue427, to: sorts)
        check(StartEvidence.sortScores(for: ue427, excluding: "steam.99", file: sorts)["dxvk -dx11"]?.games == 1, "a record that grew is read again")

        // The ladder by those points: an order only.
        let unrealBoth = GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal, engineVersion: "4.27")
        let ladder = LaunchHealth.attempts(for: unrealBoth, profile: nil, d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        check(ladder.map(\.id) == ["dxmt -dx11", "dxvk -dx11", "d3dmetal"], "Unreal with both, by its files")
        let points = scores.mapValues(\.points)
        check(LaunchHealth.ordered(ladder, bySort: points).map(\.id) == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"],
              "what its sort proved goes first, the rest as it was – none left out")
        // A start a profile shaped proves the profile, not the way (It Takes Two: D3DMetal with -dx12).
        let shaped = file.deletingLastPathComponent().appendingPathComponent("shaped-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: shaped) }
        let dx12 = StartRecipe(graphics: "d3dmetal", arguments: ["-dx12"], dllOverrides: [:], runtimes: [], avx: true, windowsVersion: nil)
        StartEvidence.note(.started, game: .steam(21), way: "d3dmetal", known: true, kind: ue427, recipe: dx12, to: shaped)
        StartEvidence.note(.started, game: .steam(22), way: "dxmt -dx11", known: false, kind: ue427,
                           recipe: StartRecipe(graphics: "dxmt", arguments: ["-dx11", "-nolauncher"], dllOverrides: [:], runtimes: [], avx: true, windowsVersion: nil),
                           to: shaped)
        StartEvidence.note(.worked, game: .steam(22), way: "dxmt -dx11", to: shaped)
        StartEvidence.note(.started, game: .steam(23), way: "dxvk -dx11", known: true, kind: ue427, profiled: true, to: shaped)
        let shapedProofs = StartEvidence.proofs(StartEvidence.load(from: shaped))
        check(shapedProofs["steam.21"]?.worked.isEmpty == true && shapedProofs["steam.21"]?.kind == ue427, "arguments beyond the way's own: no proof for the sort")
        check(shapedProofs["steam.22"]?.worked == ["dxmt -dx11"], "the way's own arguments and a launcher switch: a proof")
        check(shapedProofs["steam.23"]?.worked.isEmpty == true, "a start marked as a profile's: none")
        check(profile(#"{"graphics": "d3dmetal"}"#)?.shapesStart == true && profile(#"{"dllOverrides": {"nvapi64": ""}}"#)?.shapesStart == true
              && profile(#"{"name": "X", "note": "n", "metalFX": false, "frameLimit": 60}"#)?.shapesStart == false,
              "a profile shapes a start by its layer, arguments, DLLs and the like – not by a note or a frame limit")
        check(LaunchHealth.ordered(ladder, bySort: [:]) == ladder && LaunchHealth.ordered(ladder, bySort: ["wined3d": 9]) == ladder,
              "no points for its ways: the list as it was")
        func bySort(_ game: GameID, _ points: [String: Int], profile json: String? = nil, preset: GraphicsPreset = .automatic)
            -> (attempts: [LaunchAttempt], hint: GraphicsLayer?, bySort: Bool) {
            LaunchHealth.attempts(for: unrealBoth, profile: profile(json), hint: nil, game: game, preset: preset, sort: points,
                                  d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        }
        let fresh = GameID.steam(991_010)
        LaunchHealth.reset(fresh)
        let first = bySort(fresh, points)
        check(first.attempts.map(\.id) == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"] && first.bySort, "a game never started takes its sort's order")
        check(bySort(fresh, [:]).attempts == ladder && !bySort(fresh, [:]).bySort, "… and the usual one where its sort has proven nothing")
        check(bySort(fresh, points, profile: #"{"graphics": "dxvk"}"#).attempts.first?.graphics == .dxvk && !bySort(fresh, points, profile: #"{"graphics": "dxvk"}"#).bySort,
              "a profile's layer stands")
        check(!bySort(fresh, points, preset: .compatible).bySort, "Most compatible keeps its own order")
        // Started on its sort's order, it keeps it – whatever the sort learns later.
        LaunchHealth.recordStart(fresh, first.attempts)
        _ = LaunchHealth.advance(fresh, first.attempts)
        check(bySort(fresh, [:]).attempts == first.attempts && bySort(fresh, ["dxmt -dx11": 50]).attempts == first.attempts,
              "its state stays with the order it started on")
        check(LaunchHealth.current(fresh, bySort(fresh, [:]).attempts).index == 1, "… and so does how far it got")
        LaunchHealth.reset(fresh)
        // One that has started on the list as it was keeps that.
        let earlier = GameID.steam(991_011)
        LaunchHealth.reset(earlier)
        LaunchHealth.recordStart(earlier, ladder)
        check(bySort(earlier, points).attempts == ladder && !bySort(earlier, points).bySort, "a game's own state goes before its sort's proofs")
        LaunchHealth.reset(earlier)
        let single = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d12]), profile: nil, hint: nil, game: fresh, preset: .automatic, sort: ["d3dmetal": 8],
                                           d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        check(single.attempts.map(\.id) == ["d3dmetal"] && !single.bySort, "one way: nothing to order")
        check(LaunchHealth.plan("New", attempts: first.attempts, index: 0, confirmed: false, analysis: unrealBoth, profile: nil, hint: nil, source: nil, sortGames: 2)
              .hasSuffix("now d3dmetal, 2 games of its sort (unreal4) run on it on this Mac"), "the plan names its sort's proof")
        check(LaunchHealth.plan("New", attempts: first.attempts, index: 0, confirmed: false, analysis: unrealBoth, profile: nil, hint: nil, source: nil, sortGames: 1)
              .hasSuffix("a game of its sort (unreal4) runs on it on this Mac"), "… also a single one")
        check(LaunchHealth.plan("New", attempts: first.attempts, index: 0, confirmed: true, analysis: unrealBoth, profile: nil, hint: nil, source: nil, sortGames: 2)
              .hasSuffix("it has worked on this Mac"), "its own proof is named before its sort's")

        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ StartRulesTest")
    }
}
