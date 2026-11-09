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
        check(ids(GameAnalysis()) == ["d3dmetal", "dxmt", "dxvk"], "files that say nothing: D3DMetal runs DirectX 11 and 12")
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
        check(entries.first(where: { $0.event == .failed })?.reason?.contains("abc") == false, "what the game said, without secrets")
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("not json\n".utf8))
            try? handle.close()
        }
        check(StartEvidence.load(from: file).count == entries.count, "a broken line costs only itself")
        check(StartEvidence.load(from: file.appendingPathExtension("none")).isEmpty, "no record yet")

        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ StartRulesTest")
    }
}
