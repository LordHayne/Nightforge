// Checks step E's own logic (docs/ENTWURF-STARTREZEPT.md 3.3), before the start loop goes by it: what a remedy
// changes about a recipe, what comes after a failed start – with It Takes Two (10.11.2026), Hogwarts Legacy
// (9.11.), Alan Wake and Metal Gear Solid V (11.11.) as cases, and Plays made up at random that must all come
// to an end –, proofs that hold for a recipe, and a game's error box against a question of its own.
import Foundation

@main
struct StartRecipeTest {
    typealias Learned = StartRecipe.Learned

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

    static func found(_ id: String, _ remedy: StartRemedy?) -> StartDiagnosis {
        StartDiagnosis(id: id, because: "seen", remedy: remedy)
    }

    /// A Play as the loop would run it: a start, and after each that fails what NextStart says, until one
    /// works (`finds` answers nil) or the decision ends it. `engineBefore`: the engine before is there for
    /// the first failure.
    static func play(ladder: [LaunchAttempt], proven: Bool = false, antiCheat: Bool = false, learned: Learned = Learned(),
                     engineBefore: Bool = false, filesFixedAt: Int? = nil, looks: Bool = false,
                     finds: (_ start: Int, _ way: Int, _ learned: Learned) -> [StartDiagnosis]?)
        -> (steps: [NextStart.Step], starts: Int, way: Int, learned: Learned) {
        var index = 0, learned = learned, again = 0, starts = 0, carried = false
        var steps: [NextStart.Step] = []
        while starts < 100 {
            starts += 1
            guard let found = finds(starts, index, learned) else { break }
            let look = !looks || ladder.isEmpty ? CloserLook.Step.none
                : CloserLook.step(unexplained: StartDiagnosis.unexplained(found), antiCheat: antiCheat, carried: carried,
                                  takenBefore: false, canCarry: true, lastWay: index + 1 >= ladder.count, proven: proven && index == 0)
            if look != .none { carried = true }
            let step = NextStart.after(NextStart.Failed(ladder: ladder, index: index, proven: proven && index == 0, learned: learned,
                                                        found: found, antiCheat: antiCheat, againSoFar: again,
                                                        engineBefore: engineBefore && starts == 1, filesFixed: filesFixedAt == starts, look: look))
            steps.append(step)
            switch step {
            case .again(let changed, let why):
                learned = changed
                if why != [NextStart.engineBefore] { again += 1 }
            case .way(let next, _):
                index = next
            case .keepsItsPlace, .noOtherWay, .giveUp:
                return (steps, starts, index, learned)
            }
        }
        return (steps, starts, index, learned)
    }

    static func main() throws {
        TestDefaults.useWorkFolder()
        let none = Learned()
        let loader = ["physxupdateloader", "physxupdateloader64"]

        // MARK: A remedy changes what a recipe carries

        let loaderOff = none.applying(.dllsOff(["PhysXUpdateLoader.dll", "physxupdateloader64"]), rule: "physx-update-loader")
        check(loaderOff == Learned(dllsOff: loader, steps: ["physx-update-loader"]), "DLLs off: by Wine's names, with the rule that asked (\(String(describing: loaderOff)))")
        check(loaderOff?.applying(.dllsOff(["physxupdateloader64.dll"]), rule: "physx-update-loader") == nil, "in already: nothing changes")
        check(none.applying(.dllsOff(["d3d11", "DXGI.dll", "winemetal"]), rule: "x") == nil
              && none.applying(.dllsOff(["nvapi64", "D3D11.dll"]), rule: "nvidia-interface")?.dllsOff == ["nvapi64"],
              "a Direct3D DLL is never switched off: which copy loads is the way's")
        let runtime = none.applying(.runtimes(["vcrun2019", "d3dx9"]), rule: "missing-runtime")
        check(runtime == Learned(runtimes: ["vcrun2019", "d3dx9"], steps: ["missing-runtime"]), "runtimes")
        check(runtime?.applying(.runtimes(["d3dx9", "xact"]), rule: "missing-runtime") == Learned(runtimes: ["vcrun2019", "d3dx9", "xact"], steps: ["missing-runtime"]),
              "… one more later: added once, the rule named once")
        check(runtime?.applying(.runtimes(["d3dx9"]), rule: "missing-runtime") == nil && none.applying(.runtimes([]), rule: "x") == nil, "nothing new: no change")
        let noAVX = runtime?.applying(.noAVX, rule: "illegal-instruction")
        check(noAVX == Learned(runtimes: ["vcrun2019", "d3dx9"], noAVX: true, steps: ["missing-runtime", "illegal-instruction"]) && noAVX?.applying(.noAVX, rule: "illegal-instruction") == nil,
              "without AVX, once; the rules in the order they came")
        for remedy in [StartRemedy.dropArguments, .layer(.wined3d), .nextLayer, .nextWay, .trustRoot("VeriSign"), .trustRoot(nil)] {
            check(none.applying(remedy, rule: "x") == nil && (remedy.picksAWay || remedy == .trustRoot("VeriSign") || remedy == .trustRoot(nil)),
                  "\(remedy.label): not a change on the same way")
        }
        check(!StartRemedy.dllsOff([]).picksAWay && !StartRemedy.runtimes([]).picksAWay && !StartRemedy.noAVX.picksAWay, "… and those that are don't pick a way")

        // MARK: The recipe of a way with what was learned

        let d3dmetal = LaunchAttempt(graphics: .d3dmetal)
        let plain = StartRecipe.of(way: d3dmetal, learned: none, profile: nil, d3dMetalEngine: true)
        check(plain == StartRecipe.of(layer: .d3dmetal, arguments: [], profile: nil, learnedRuntimes: [], avx: true, d3dMetalEngine: true) && plain.steps == nil,
              "nothing learned: the recipe as it is recorded today")
        let nvidiaOff = none.applying(.dllsOff(["nvapi64", "nvngx"]), rule: "nvidia-interface")!
        let withoutNvidia = StartRecipe.of(way: d3dmetal, learned: nvidiaOff, profile: nil, d3dMetalEngine: true)
        check(plain.dllOverrides["nvapi64"] == "builtin" && withoutNvidia.dllOverrides["nvapi64"] == "" && withoutNvidia.dllOverrides["nvngx"] == ""
              && withoutNvidia.dllOverrides["d3d11"] == "builtin" && withoutNvidia.dllOverrides["dxgi"] == "builtin",
              "what was learned goes over the layer's own DLLs; its Direct3D stays (\(withoutNvidia.dllOverrides))")
        check(withoutNvidia.steps == ["nvidia-interface"] && !withoutNvidia.startsLike(plain), "the recipe names the rule, and it is another start")
        var renamed = withoutNvidia
        renamed.steps = nil
        renamed.runtimes = renamed.runtimes.reversed()
        check(renamed.startsLike(withoutNvidia) && renamed != withoutNvidia, "the same start whatever led to it")
        let dxmt11 = LaunchAttempt(graphics: .dxmt, arguments: ["-dx11"])
        check(StartRecipe.of(way: dxmt11, learned: none, profile: nil, launcherSwitch: "-nolauncher", d3dMetalEngine: true).arguments == ["-dx11", "-nolauncher"]
              && StartRecipe.of(way: LaunchAttempt(graphics: .dxmt, arguments: ["-NoLauncher"]), learned: none, profile: nil, launcherSwitch: "-nolauncher", d3dMetalEngine: true)
              .arguments == ["-NoLauncher"], "the switch past the game's launcher window, once")
        let shaped = profile(#"{"graphics": "d3dmetal", "arguments": ["-dx12"], "winetricks": ["vcrun2022"], "windowsVersion": "win10"}"#)
        let onProfile = StartRecipe.of(way: d3dmetal, learned: noAVX!, profile: shaped, d3dMetalEngine: true)
        check(onProfile.arguments == ["-dx12"] && onProfile.runtimes == ["d3dx9", "vcrun2019", "vcrun2022"] && !onProfile.avx && onProfile.windowsVersion == "win10",
              "the profile's parts and the learned ones together (\(onProfile))")
        check(StartRecipe.of(way: dxmt11, learned: none, profile: shaped, d3dMetalEngine: true).arguments == ["-dx11"], "the profile's arguments only on its layer")
        check(!StartRecipe.of(way: d3dmetal, learned: none, profile: profile(#"{"avx": false}"#), d3dMetalEngine: true).avx, "a profile's AVX off stands without anything learned")
        // In the record: a line from before `steps` reads on, one with them comes back whole.
        let oldLine = #"{"graphics":"d3dmetal","arguments":["-dx12"],"dllOverrides":{"dxgi":"builtin"},"runtimes":[],"avx":true}"#
        let old = try JSONDecoder().decode(StartRecipe.self, from: Data(oldLine.utf8))
        check(old.steps == nil && old.windowsVersion == nil && old.arguments == ["-dx12"], "a recipe recorded before 14.11. reads as before")
        check(try JSONDecoder().decode(StartRecipe.self, from: JSONEncoder().encode(withoutNvidia)) == withoutNvidia, "one with steps, written and read")

        // MARK: Step E1 – a start is made of its recipe

        // The game gets the profile's arguments, then the way's, then the switch past its launcher window: the
        // order Launcher.launch handed them over in before the recipe carried them.
        let forced = LaunchAttempt(graphics: .d3dmetal, arguments: ["-force-d3d12"])
        let made = StartRecipe.of(way: forced, learned: none, profile: shaped, launcherSwitch: "-nolauncher", d3dMetalEngine: true)
        check(made.arguments == ["-dx12", "-force-d3d12", "-nolauncher"], "the arguments in the order the game gets them (\(made.arguments))")
        check(StartRecipe.pastLauncher(["-dx11"], switch: nil) == ["-dx11"] && StartRecipe.pastLauncher([], switch: "-nolauncher") == ["-nolauncher"],
              "the switch past the launcher window stands in one place")
        // A line recorded up to 14.11. has the profile's last: the same start, and a proof from then holds.
        var recorded = made
        recorded.arguments = ["-force-d3d12", "-nolauncher", "-dx12"]
        check(recorded.startsLike(made) && recorded != made, "the same arguments in the record's old order are the same start")
        var otherSwitch = made
        otherSwitch.arguments = ["-dx12", "-force-d3d11", "-nolauncher"]
        check(!otherSwitch.startsLike(made), "… other arguments aren't")
        check(StartEvidence.Proof(worked: [forced.id], workedWith: [forced.id: recorded]).holds(for: made, on: forced.id),
              "a proof recorded in the old order holds for the start of today")
        // The prefix gets the recipe's DLL overrides and Windows version (Engine.applyGameSettings): with nothing
        // learned exactly what the layer and the profile gave before, with something learned that on top.
        let unshaped = StartRecipe.of(way: d3dmetal, learned: none, profile: shaped, d3dMetalEngine: true)
        check(Engine.appDefaults("Game.exe", dllOverrides: unshaped.dllOverrides, windowsVersion: unshaped.windowsVersion)
              == Engine.appDefaults("Game.exe", dllOverrides: Engine.gameDllOverrides(.d3dmetal, profile: shaped, d3dMetalEngine: true), windowsVersion: "win10"),
              "with nothing learned the prefix gets what it got before")
        for layer in [GraphicsLayer.dxmt, .dxvk, .d3dmetal, .wined3d] {
            for engine in [true, false] {
                let plainRecipe = StartRecipe.of(way: LaunchAttempt(graphics: layer, arguments: []), learned: none, profile: nil, d3dMetalEngine: engine)
                check(plainRecipe.dllOverrides == Engine.gameDllOverrides(layer, profile: nil, d3dMetalEngine: engine) && plainRecipe.windowsVersion == nil,
                      "\(layer.rawValue): a recipe without anything learned has the layer's overrides")
            }
        }
        let section = Engine.appDefaults("Game.exe", dllOverrides: withoutNvidia.dllOverrides, windowsVersion: withoutNvidia.windowsVersion)
        check(withoutNvidia.dllOverrides.allSatisfy { section.contains("\"\($0.key)\"=\"\($0.value)\"") }
              && section.split(separator: "\n").filter { $0.hasPrefix("\"") && !$0.hasPrefix("\"Version\"") }.count == withoutNvidia.dllOverrides.count,
              "every DLL override of the recipe goes into the prefix, and no other")
        check(section.contains("\"nvapi64\"=\"\"") && section.hasPrefix("[-HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\Game.exe\\DllOverrides]")
              && section.hasSuffix("\"Version\"=-"), "a DLL learned to stay out is written as off, the old ones cleared first, no Windows version without one")
        check(Engine.appDefaults("Game.exe", dllOverrides: onProfile.dllOverrides, windowsVersion: onProfile.windowsVersion).hasSuffix("\"Version\"=\"win10\""),
              "the recipe's Windows version")

        // MARK: What was learned, kept with the game

        let defaults = TestDefaults.suite("start-recipe")
        let twoGame = GameID.steam(1_426_210)
        check(LearnedFixes.learned(twoGame, defaults: defaults) == none, "nothing learned yet")
        defaults.set(["vcrun2019"], forKey: "learned.winetricks.\(twoGame.key)")
        defaults.set(true, forKey: "learned.noAVX.\(twoGame.key)")
        check(LearnedFixes.learned(twoGame, defaults: defaults) == Learned(runtimes: ["vcrun2019"], noAVX: true),
              "what earlier versions learned – runtimes, no AVX – is part of it")
        let grown = Learned(dllsOff: ["nvapi64", "nvngx"], runtimes: ["vcrun2019", "xact"], noAVX: true, steps: ["missing-runtime", "nvidia-interface"])
        LearnedFixes.keep(grown, for: twoGame, defaults: defaults)
        check(LearnedFixes.learned(twoGame, defaults: defaults) == grown && defaults.stringArray(forKey: "learned.winetricks.\(twoGame.key)") == ["vcrun2019", "xact"],
              "kept and read back, the runtimes under the key they always had")
        check(LearnedFixes.learned(.steam(1), defaults: defaults) == none, "another game: its own")
        LearnedFixes.keep(none, for: twoGame, defaults: defaults)
        check(LearnedFixes.learned(twoGame, defaults: defaults) == none && defaults.object(forKey: "learned.noAVX.\(twoGame.key)") == nil
              && defaults.object(forKey: "learned.dllsOff.\(twoGame.key)") == nil, "nothing to keep: nothing left behind")
        // Through the app's own settings, the functions from before answer the same.
        let taught = GameID.steam(993_001)
        LearnedFixes.addWinetricks(["d3dx9"], for: taught)
        LearnedFixes.keep(LearnedFixes.learned(taught).applying(.noAVX, rule: "illegal-instruction")!, for: taught)
        check(LearnedFixes.winetricks(taught) == ["d3dx9"] && LearnedFixes.noAVX(taught) && !LearnedFixes.avx(taught, profile: nil)
              && LearnedFixes.learned(taught).steps == ["illegal-instruction"], "what the table teaches is what `winetricks` and `noAVX` say")

        // MARK: The way that answers a remedy – as the ladder picks today

        let both = GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal, engineVersion: "4.27")
        let hogwarts = LaunchHealth.attempts(for: both, profile: nil, d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        check(hogwarts.map(\.id) == ["dxmt -dx11", "dxvk -dx11", "d3dmetal"], "Unreal with DirectX 11 and 12, by its files")
        let unknown32 = LaunchHealth.attempts(for: GameAnalysis(apis: [], is64Bit: false), profile: nil, d3dMetal: true, vulkanLayer: false, kosmicKrisp: false)
        let unknown = [LaunchAttempt(graphics: .d3dmetal), LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .dxvk), LaunchAttempt(graphics: .wined3d)]
        let noD3DMetal = LaunchHealth.attempts(for: both, profile: nil, d3dMetal: false, vulkanLayer: true, kosmicKrisp: false)
        check(noD3DMetal.map(\.id) == ["dxmt -dx11", "dxvk -dx11", "dxmt"] && unknown32.first?.graphics == .wined3d, "two more ladders as they come")
        check(NextStart.way(answering: .dropArguments, after: 0, in: hogwarts) == 2, "Hogwarts Legacy, 9.11.: -dx11 refused on DXMT → straight to the way without a switch")
        check(NextStart.way(answering: .layer(.wined3d), after: 0, in: unknown) == 3, "Alan Wake, 11.11.: Direct3D 9 on D3DMetal → Wine's own Direct3D, past DXMT and DXVK")
        check(NextStart.way(answering: .layer(.d3dmetal), after: 0, in: hogwarts) == 2 && NextStart.way(answering: .layer(.d3dmetal), after: 0, in: noD3DMetal) == 1,
              "needs DirectX 12 → D3DMetal; where the ladder has none, simply the next")
        check(NextStart.way(answering: .nextLayer, after: 0, in: hogwarts) == 1 && NextStart.way(answering: .nextLayer, after: 1, in: noD3DMetal) == 2
              && NextStart.way(answering: .nextLayer, after: 0, in: [dxmt11, LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .dxvk)]) == 2,
              "another layer: the next way on one")
        check(NextStart.way(answering: .nextWay, after: 1, in: hogwarts) == 2 && NextStart.way(answering: nil, after: 0, in: hogwarts) == 1
              && NextStart.way(answering: .trustRoot(nil), after: 0, in: hogwarts) == 1 && NextStart.way(answering: .noAVX, after: 0, in: hogwarts) == 1,
              "nothing that names a way: the next")
        check(NextStart.way(answering: .dropArguments, after: 2, in: hogwarts) == nil && NextStart.way(answering: nil, after: 0, in: []) == nil
              && NextStart.way(answering: .layer(.dxmt), after: 1, in: hogwarts) == 2, "no way left: none; a way before the failed one isn't gone back to")
        // The same pick as LaunchHealth.advance(answering:), for every failure a game can say, on every way.
        var number = 994_000
        for ladder in [hogwarts, unknown, unknown32, noD3DMetal, [d3dmetal]] {
            for index in ladder.indices {
                for failure in [StartFailure?.none, .refusedSwitch, .needsD3D12, .needsD3D9] {
                    number += 1
                    let game = GameID.steam(number)
                    LaunchHealth.recordStart(game, ladder)
                    LaunchHealth.advance(game, ladder, to: index)
                    check(LaunchHealth.current(game, ladder).index == index, "the ladder set to a way picked for it")
                    let moved = LaunchHealth.advance(game, ladder, answering: failure)
                    let picked = NextStart.way(answering: failure.map(NextStart.remedy), after: index, in: ladder)
                    check(moved == (picked != nil) && (picked == nil || LaunchHealth.current(game, ladder).index == picked),
                          "\(ladder.map(\.id)) after \(index), \(String(describing: failure)): \(String(describing: picked)) as the ladder moves today")
                    LaunchHealth.reset(game)
                }
            }
        }
        let moving = GameID.steam(993_002)
        LaunchHealth.confirm(moving, hogwarts)
        LaunchHealth.advance(moving, hogwarts, to: 2)
        check(LaunchHealth.current(moving, hogwarts) == (2, false), "a way picked isn't a way proven")
        LaunchHealth.advance(moving, hogwarts, to: 7)
        check(LaunchHealth.current(moving, hogwarts).index == 2, "a way that isn't there: nothing changes")
        LaunchHealth.reset(moving)

        // MARK: After a failed start – the cases

        // It Takes Two as it was before the loader was off for every game (a profile bringing it back stands for that).
        let itTakesTwo = profile(#"{"graphics": "d3dmetal", "arguments": ["-dx12"], "dllOverrides": {"physxupdateloader": "native,builtin", "physxupdateloader64": "native,builtin"}}"#)
        let twoLadder = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal, engineVersion: "4.26"), profile: itTakesTwo,
                                              d3dMetal: true, vulkanLayer: true, kosmicKrisp: false)
        check(twoLadder.map(\.id) == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"], "its ladder")
        let physxCrash = CrashDump(code: CrashDump.accessViolation, address: 0, module: nil,
                                   stack: [CrashDump.Frame(module: "nvapi64.dll", offset: 0x1120), CrashDump.Frame(module: "physxupdateloader64.dll", offset: 0x113C),
                                           CrashDump.Frame(module: "ntdll.dll", offset: 0x53158)],
                                   modules: ["ittakestwo.exe", "nvapi64.dll", "physxupdateloader64.dll", "ntdll.dll"])
        let physx = StartDiagnosis.diagnose(StartFinding(dumps: [physxCrash]))
        check(physx.map(\.id) == ["physx-update-loader"] && physx.first?.remedy == .dllsOff(loader), "its dump, read by the table")
        func crashesWithLoader(_ way: Int, _ learned: Learned) -> [StartDiagnosis]? {
            StartRecipe.of(way: twoLadder[way], learned: learned, profile: itTakesTwo, d3dMetalEngine: true).dllOverrides["physxupdateloader64"] == "" ? nil : physx
        }
        let healed = play(ladder: twoLadder) { _, way, learned in crashesWithLoader(way, learned) }
        check(healed.steps == [.again(Learned(dllsOff: loader, steps: ["physx-update-loader"]), why: ["physx-update-loader"])] && healed.starts == 2 && healed.way == 0,
              "It Takes Two heals at its first Play: one more start, on the same way, with the loader off (\(healed.steps))")
        // … where the ladder alone went through every layer and gave up (9.11.).
        let ladderOnly = play(ladder: twoLadder) { _, _, _ in [] }
        check(ladderOnly.steps == [.way(1, why: nil), .way(2, why: nil), .giveUp] && ladderOnly.starts == 3, "with nothing found the ladder moves as before")
        // The next Play begins with what was learned: no failed start at all.
        check(play(ladder: twoLadder, learned: healed.learned) { _, way, learned in crashesWithLoader(way, learned) }.starts == 1, "and stays healed")

        func after(_ found: [StartDiagnosis], ladder: [LaunchAttempt] = [], index: Int = 0, proven: Bool = false, learned: Learned = Learned(),
                   antiCheat: Bool = false, againSoFar: Int = 0, engineBefore: Bool = false, filesFixed: Bool = false,
                   look: CloserLook.Step = .none) -> NextStart.Step {
            NextStart.after(NextStart.Failed(ladder: ladder, index: index, proven: proven, learned: learned, found: found, antiCheat: antiCheat,
                                             againSoFar: againSoFar, engineBefore: engineBefore, filesFixed: filesFixed, look: look))
        }
        check(after([found("refused-switch", .dropArguments)], ladder: hogwarts) == .way(2, why: "refused-switch"), "Hogwarts Legacy: the way without a switch, and why")
        let direct3D9 = StartDiagnosis.diagnose(StartFinding(direct3D9Failed: true, layer: .d3dmetal))
        check(after(direct3D9, ladder: unknown) == .way(3, why: "direct3d9"), "Alan Wake: straight to Wine's own Direct3D")
        let untrusted = [found("untrusted-root", .trustRoot("VeriSign Class 3 Public Primary Certification Authority - G5"))]
        check(after(untrusted, ladder: hogwarts) == .way(1, why: nil) && after(untrusted, ladder: hogwarts, index: 2) == .giveUp,
              "Metal Gear Solid V: a root needs the player's OK – nothing is changed for it, the ladder goes on")
        let twoThings = [found("illegal-instruction", .noAVX), found("missing-runtime", .runtimes(["vcrun2019"])), found("graphics-failed", .nextLayer)]
        check(after(twoThings, ladder: hogwarts) == .again(Learned(runtimes: ["vcrun2019"], noAVX: true, steps: ["illegal-instruction", "missing-runtime"]),
                                                          why: ["illegal-instruction", "missing-runtime"]),
              "two things to change on the same way: both in one start, before any other way")
        let known = Learned(runtimes: ["vcrun2019"], noAVX: true, steps: ["illegal-instruction", "missing-runtime"])
        check(after(twoThings, ladder: hogwarts, learned: known) == .way(1, why: "graphics-failed"), "the same findings with all of it in already: the way they point to")
        check(after([found("signature", nil), found("crash", nil)], ladder: hogwarts, index: 1) == .way(2, why: nil), "findings without a remedy: the next way")
        check(after([found("hung", .nextWay)], ladder: hogwarts) == .way(1, why: "hung"), "hung: the next way")
        check(after([], ladder: hogwarts, index: 2) == .giveUp, "the last way failed: given up")

        // Outside the table: the engine before, the profile's file edits, a closer look.
        check(after(twoThings, ladder: hogwarts, engineBefore: true) == .again(none, why: ["engine-before"]), "the engine before goes first, with nothing else changed")
        check(after([], ladder: hogwarts, filesFixed: true) == .again(none, why: ["file-edits"]), "a settings file fixed: the same way again")
        check(after([found("missing-runtime", .runtimes(["xact"]))], ladder: hogwarts, filesFixed: true)
              == .again(Learned(runtimes: ["xact"], steps: ["missing-runtime"]), why: ["missing-runtime", "file-edits"]), "… together with what the table changes")
        check(after([], ladder: hogwarts, index: 2, look: .sameWayAgain) == .again(none, why: ["closer-look"]), "nothing explains the last way's end: once more with the channels")
        check(after([], ladder: hogwarts, look: .nextWay) == .way(1, why: nil), "a way left to carry them: no start of its own")

        // A way that had worked.
        check(after(physx, ladder: twoLadder, proven: true) == .again(Learned(dllsOff: loader, steps: ["physx-update-loader"]), why: ["physx-update-loader"]),
              "a proven way gets what the table changes too")
        check(after([found("crash", nil)], ladder: hogwarts, proven: true) == .keepsItsPlace && after([], ladder: hogwarts, proven: true) == .keepsItsPlace
              && after([found("graphics-crash", .nextLayer)], ladder: hogwarts, proven: true) == .keepsItsPlace,
              "… and keeps its place otherwise, as before")
        check(after(StartDiagnosis.diagnose(StartFinding(graphicsFailed: true)), ladder: hogwarts, proven: true) == .way(1, why: "graphics-failed"),
              "only its layer saying it can't draw moves it on")
        check(after([], ladder: hogwarts, proven: true, look: .sameWayAgain) == .again(none, why: ["closer-look"]),
              "should it get a closer look (the player's decision, 3.3), that comes before giving in")

        // No ladder: the layer chosen by hand.
        check(after([found("missing-runtime", .runtimes(["d3dx9"]))]) == .again(Learned(runtimes: ["d3dx9"], steps: ["missing-runtime"]), why: ["missing-runtime"])
              && after([found("graphics-failed", .nextLayer)]) == .noOtherWay && after([], look: .sameWayAgain) == .noOtherWay,
              "a way chosen by hand: what changes on it applies, nothing switches, no closer look")

        // An anti-cheat: what Wine's log asked for stays as before, no DLL is ever switched off.
        check(after(physx + [found("nvidia-interface", .dllsOff(["nvapi64", "nvngx"]))], ladder: hogwarts, antiCheat: true) == .way(1, why: nil),
              "with an anti-cheat no DLL is switched off, whatever was found")
        check(after([found("missing-runtime", .runtimes(["vcrun2019"])), found("nvidia-interface", .dllsOff(["nvapi64"]))], ladder: hogwarts, antiCheat: true)
              == .again(Learned(runtimes: ["vcrun2019"], steps: ["missing-runtime"]), why: ["missing-runtime"]), "a runtime Wine missed still comes")

        // The cap.
        check(NextStart.againLimit == 3, "three more starts on the same way in a Play, at most")
        check(after(twoThings, ladder: hogwarts, againSoFar: 3) == .way(1, why: "graphics-failed") && after([], ladder: hogwarts, againSoFar: 3, filesFixed: true) == .way(1, why: nil)
              && after([], ladder: hogwarts, index: 2, againSoFar: 3, look: .sameWayAgain) == .giveUp && after(twoThings, againSoFar: 3) == .noOtherWay,
              "past the cap nothing starts the same way again")
        check(after([], ladder: hogwarts, againSoFar: 3, engineBefore: true) == .again(none, why: ["engine-before"]), "… but the engine before, which is held already")

        // A Play with a closer look at its end: every way once, the last one twice.
        let looked = play(ladder: hogwarts, looks: true) { _, _, _ in [] }
        check(looked.steps == [.way(1, why: nil), .way(2, why: nil), .giveUp] && looked.starts == 3,
              "nothing explained on the first way: the ways after it carry the channels, no start more")
        let lastOnly = play(ladder: [d3dmetal], looks: true) { _, _, _ in [] }
        check(lastOnly.steps == [.again(none, why: ["closer-look"]), .giveUp] && lastOnly.starts == 2, "one way only: it starts once more with them, then that's it")

        // MARK: Every Play ends

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random(_ below: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(below))
        }
        let pool = [found("physx-update-loader", .dllsOff(loader)), found("nvidia-interface", .dllsOff(["nvapi64", "nvngx", "d3d11"])),
                    found("missing-runtime", .runtimes(["vcrun2019"])), found("illegal-instruction", .noAVX), found("refused-switch", .dropArguments),
                    found("needs-d3d12", .layer(.d3dmetal)), found("direct3d9", .layer(.wined3d)), found("graphics-crash", .nextLayer),
                    found("graphics-failed", .nextLayer), found("hung", .nextWay), found("untrusted-root", .trustRoot("X")), found("signature", nil),
                    found("crash", nil), found("said", nil)]
        let ways = [d3dmetal, dxmt11, LaunchAttempt(graphics: .dxvk, arguments: ["-dx11"]), LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .dxvk),
                    LaunchAttempt(graphics: .wined3d)]
        var endings: [String: Int] = [:]
        for round in 0..<3000 {
            let ladder = (0..<random(5)).map { _ in ways[random(ways.count)] }
            let proven = random(4) == 0, antiCheat = random(5) == 0, engine = random(6) == 0, looks = random(2) == 0
            let fixAt = random(3) == 0 ? 1 + random(3) : nil
            // It never works, and Wine misses another runtime at every start.
            let result = play(ladder: ladder, proven: proven, antiCheat: antiCheat, engineBefore: engine, filesFixedAt: fixAt, looks: looks) { start, _, _ in
                pool.filter { _ in random(3) == 0 } + (random(2) == 0 ? [found("missing-runtime", .runtimes(["verb\(start)"]))] : [])
            }
            let again = result.steps.filter { if case .again(_, let why) = $0 { return why != [NextStart.engineBefore] } else { return false } }.count
            let moved = result.steps.compactMap { step -> Int? in if case .way(let index, _) = step { return index } else { return nil } }
            let last = result.steps.last
            let ended = last == .giveUp || last == .keepsItsPlace || last == .noOtherWay
            check(ended && result.starts == result.steps.count, "round \(round): a Play that never works ends (\(result.steps.count) steps)")
            check(again <= NextStart.againLimit && result.starts <= ladder.count + NextStart.againLimit + 2,
                  "round \(round): at most \(NextStart.againLimit) starts on the same way again, \(result.starts) starts on \(ladder.count) ways")
            check(moved == moved.sorted() && Set(moved).count == moved.count && moved.allSatisfy(ladder.indices.contains), "round \(round): the ladder only moves on (\(moved))")
            check(ladder.isEmpty == (last == .noOtherWay), "round \(round): no ladder, no other way – and only then")
            check(!antiCheat || result.learned.dllsOff.isEmpty, "round \(round): no DLL off for a game with an anti-cheat")
            check(!result.learned.dllsOff.contains("d3d11") && Set(result.learned.steps).count == result.learned.steps.count, "round \(round): no Direct3D DLL off, each rule named once")
            endings[String(describing: last!), default: 0] += 1
        }
        check(endings.count == 3 && endings.values.allSatisfy { $0 > 100 }, "all three ends came up often (\(endings))")

        // MARK: Step E2 – the one decision does what the loop's branches did

        // The branches of LibraryModel.launch as they stood before step E2 (e9e0656), in their order: the engine
        // before, a missing runtime, a settings file fixed, no AVX, no ladder, a proven way's place, a closer
        // look, the next way that answers what the game said, giving up.
        enum Before: Equatable { case engineBefore, runtime([String]), files, noAVX, noOtherWay, keepsItsPlace, look, way(Int), giveUp }
        func before(ladder: [LaunchAttempt], index: Int, proven: Bool, learnedRuntimes: [String], avx: Bool, engineBefore: Bool,
                    finding: StartFinding, filesFixed: Bool, look: CloserLook.Step) -> Before {
            if engineBefore { return .engineBefore }
            let needed = finding.missingRuntimes.filter { !learnedRuntimes.contains($0) }
            if !needed.isEmpty { return .runtime(needed) }
            if filesFixed { return .files }
            if avx, finding.illegalInstruction { return .noAVX }
            guard !ladder.isEmpty else { return .noOtherWay }
            if proven && !finding.graphicsFailed { return .keepsItsPlace }
            if look == .sameWayAgain { return .look }
            let failure = StartFailure.read(finding.messages) ?? (finding.direct3D9Failed ? .needsD3D9 : nil)
            let following = Array(ladder.indices.dropFirst(index + 1))
            let next = following.first { failure?.answered(by: ladder[$0]) ?? true } ?? following.first
            return next.map { .way($0) } ?? .giveUp
        }
        let words = ["-d3d12, -d3d11, -vulkan, -opengl mutually exclusive", "This game requires DirectX 12.", "Unhandled Exception: EXCEPTION_ACCESS_VIOLATION",
                     "Fatal error!"]
        var kinds: [String: Int] = [:]
        for round in 0..<4000 {
            let ladder = (0..<random(5)).map { _ in ways[random(ways.count)] }
            let index = ladder.isEmpty ? 0 : random(ladder.count)
            let proven = random(4) == 0, engine = random(8) == 0, fixed = random(6) == 0, profileAVX = random(5) != 0
            var known = Learned(runtimes: random(3) == 0 ? ["vcrun2019"] : [], noAVX: random(6) == 0)
            if random(4) == 0 { known = known.applying(.runtimes(["xact"]), rule: "missing-runtime")! }
            let layer = ladder.indices.contains(index) ? ladder[index].graphics : GraphicsLayer.dxmt
            let recipe = StartRecipe.of(way: LaunchAttempt(graphics: layer, arguments: []), learned: known,
                                        profile: profileAVX ? nil : profile(#"{"avx": false}"#), d3dMetalEngine: true)
            // What the loop reads for the decision: the game's words, Wine's log. An illegal instruction is only
            // looked for when the start offered AVX, as before.
            let finding = StartFinding(messages: (0..<random(3)).map { _ in words[random(words.count)] },
                                       missingRuntimes: [[], [], ["vcrun2019"], ["vcrun2019", "d3dx9"], ["xact"]][random(5)],
                                       illegalInstruction: recipe.avx && random(4) == 0,
                                       graphicsFailed: layer == .dxvk && random(3) == 0,
                                       direct3D9Failed: GameLog.direct3D9IsDXVKs(on: layer) && random(4) == 0, layer: layer)
            let unexplained = random(2) == 0
            let look = ladder.isEmpty || (proven && !finding.graphicsFailed) ? CloserLook.Step.none
                : CloserLook.step(unexplained: unexplained, antiCheat: false, carried: random(3) == 0, takenBefore: random(3) == 0, canCarry: true,
                                  lastWay: index + 1 >= ladder.count)
            let old = before(ladder: ladder, index: index, proven: proven, learnedRuntimes: known.runtimes, avx: recipe.avx, engineBefore: engine,
                             finding: finding, filesFixed: fixed, look: look)
            let new = NextStart.after(NextStart.Failed(ladder: ladder, index: index, proven: proven, learned: known, recipe: recipe,
                                                       found: NextStart.asBefore(StartDiagnosis.diagnose(finding)), antiCheat: random(5) == 0,
                                                       againSoFar: 0, engineBefore: engine, filesFixed: fixed, look: look))
            let same: Bool
            switch (old, new) {
            case (.engineBefore, .again(let learned, let why)):
                same = why == [NextStart.engineBefore] && learned == known
            case (.runtime(let needed), .again(let learned, let why)):
                // All that can be changed on the same way comes in this one start: the runtime, and with it a
                // settings file fixed or no AVX, which took a start each before.
                same = why.contains("missing-runtime") && learned.runtimes == known.runtimes + needed
            case (.files, .again(let learned, let why)):
                same = why.contains(NextStart.fileEdits) && learned.runtimes == known.runtimes
            case (.noAVX, .again(let learned, let why)):
                same = why == ["illegal-instruction"] && learned.noAVX && learned.runtimes == known.runtimes && learned.dllsOff.isEmpty
            case (.look, .again(let learned, let why)):
                same = why == [NextStart.closerLook] && learned == known
            case (.noOtherWay, .noOtherWay), (.keepsItsPlace, .keepsItsPlace), (.giveUp, .giveUp):
                same = true
            case (.way(let was), .way(let now, _)):
                same = was == now
            default:
                same = false
            }
            check(same, "round \(round): the branches said \(old), the decision says \(new) (ladder \(ladder.map(\.id)) at \(index), \(finding))")
            if case .again(let learned, _) = new { check(learned.dllsOff.isEmpty, "round \(round): no DLL is switched off in step E2") }
            kinds[String(describing: old).prefix { $0 != "(" }.description, default: 0] += 1
        }
        check(kinds.count == 9 && kinds.values.allSatisfy { $0 >= 20 }, "every branch came up (\(kinds))")
        // What the table reads beyond that changes nothing yet: the layer's own crash and a load of Direct3D 9
        // alone don't pick a way, a dump at NVIDIA's interface switches no DLL off.
        let beyond = [found("nvidia-interface", .dllsOff(["nvapi64", "nvngx"])), found("physx-update-loader", .dllsOff(loader)),
                      found("graphics-crash", .nextLayer), found("loads-direct3d9", .layer(.wined3d)), found("graphics-failed", .nextLayer),
                      found("hung", .nextWay), found("untrusted-root", .trustRoot("X"))]
        check(NextStart.asBefore(beyond).allSatisfy { $0.remedy == nil } && NextStart.asBefore(beyond).map(\.id) == beyond.map(\.id),
              "what didn't act before step E is still seen, and changes nothing")
        let wined3dLast = [dxmt11, LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .wined3d)]
        check(NextStart.after(NextStart.Failed(ladder: wined3dLast, index: 0, found: NextStart.asBefore(beyond))) == .way(1, why: nil),
              "… the next way as it stands")
        check(NextStart.after(NextStart.Failed(ladder: wined3dLast, index: 0, proven: true, found: NextStart.asBefore(beyond))) == .way(1, why: nil)
              && NextStart.after(NextStart.Failed(ladder: wined3dLast, index: 0, proven: true, found: NextStart.asBefore(Array(beyond.dropLast(3))))) == .keepsItsPlace,
              "the layer's own failure still moves a proven way on, nothing else does")
        // A start that didn't offer AVX isn't started again without it.
        let noAVXProfile = StartRecipe.of(way: d3dmetal, learned: none, profile: profile(#"{"avx": false}"#), d3dMetalEngine: true)
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, recipe: noAVXProfile, found: [found("illegal-instruction", .noAVX)])) == .way(1, why: nil)
              && NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, recipe: plain, found: [found("illegal-instruction", .noAVX)]))
              == .again(Learned(noAVX: true, steps: ["illegal-instruction"]), why: ["illegal-instruction"]),
              "an illegal instruction without the AVX hint on: nothing to take away")

        // MARK: Step E3 – every remedy of the table acts

        // A dump at NVIDIA's interface: the same way once more with nvapi64 and nvngx kept out – D3DMetal has
        // them on as its own (Engine.layerOverrides) – and the start made of that has them off in the prefix.
        let nvidiaFound = [found("nvidia-interface", .dllsOff(["nvapi64", "nvngx"]))]
        let withNvidia = NextStart.after(NextStart.Failed(ladder: hogwarts, index: 2, recipe: plain, found: nvidiaFound))
        check(withNvidia == .again(nvidiaOff, why: ["nvidia-interface"]), "a crash in NVIDIA's interface: the same way without it (\(withNvidia))")
        check(plain.dllOverrides["nvapi64"] == "builtin" && withoutNvidia.dllOverrides["nvapi64"] == "" && withoutNvidia.dllOverrides["nvngx"] == "",
              "… which the start's recipe then carries")
        // The same finding once more changes nothing: the next way, or none.
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 2, learned: nvidiaOff, recipe: withoutNvidia, found: nvidiaFound)) == .giveUp
              && NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, learned: nvidiaOff, recipe: withoutNvidia, found: nvidiaFound)) == .way(1, why: nil),
              "what the start had already isn't tried again")
        // A DLL that is off for every game, or by the game's profile, was off at the failed start: no start for it.
        check(plain.dllOverrides["physxupdateloader64"] == ""
              && NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, recipe: plain, found: physx)) == .way(1, why: nil),
              "the PhysX update loader is off for every game: nothing to switch off")
        let loaderBack = StartRecipe.of(way: twoLadder[0], learned: none, profile: itTakesTwo, d3dMetalEngine: true)
        check(NextStart.after(NextStart.Failed(ladder: twoLadder, index: 0, recipe: loaderBack, found: physx))
              == .again(Learned(dllsOff: loader, steps: ["physx-update-loader"]), why: ["physx-update-loader"]),
              "It Takes Two with the loader back: the same way with it off")
        let halfOff = profile(#"{"dllOverrides": {"nvngx": ""}}"#)
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 2, recipe: StartRecipe.of(way: dxmt11, learned: none, profile: halfOff, d3dMetalEngine: true),
                                               found: nvidiaFound)) == .again(Learned(dllsOff: ["nvapi64"], steps: ["nvidia-interface"]), why: ["nvidia-interface"]),
              "only the DLLs that were on")
        // The way to come: a finding that names it goes before one that only rules this layer out.
        let nineLadder = [d3dmetal, dxmt11, LaunchAttempt(graphics: .wined3d)]
        let crashInD3D9 = found("graphics-crash", .nextLayer), drawsD3D9 = found("direct3d9", .layer(.wined3d))
        check(NextStart.after(NextStart.Failed(ladder: nineLadder, found: [crashInD3D9, drawsD3D9])) == .way(2, why: "direct3d9"),
              "Alan Wake with a crash in d3d9.dll too: Wine's own Direct3D, not DXMT on the way")
        check(NextStart.after(NextStart.Failed(ladder: nineLadder, found: [crashInD3D9])) == .way(1, why: "graphics-crash")
              && NextStart.after(NextStart.Failed(ladder: [dxmt11, LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .dxvk)], found: [crashInD3D9]))
              == .way(2, why: "graphics-crash"), "a crash in the layer's own DLL: the next way on another layer")
        check(NextStart.pointer(in: [found("hung", .nextWay), found("graphics-failed", .nextLayer), found("loads-direct3d9", .layer(.wined3d)),
                                     found("refused-switch", .dropArguments)])?.id == "loads-direct3d9"
              && NextStart.pointer(in: [found("hung", .nextWay), found("crash", nil), found("nvidia-interface", .dllsOff(["nvapi64"]))])?.id == "hung"
              && NextStart.pointer(in: [found("crash", nil), found("untrusted-root", .trustRoot("X"))]) == nil,
              "among findings that name the way the table's order, then another layer, then the next way")
        // A game with an anti-cheat: only what acted before step E, whatever else Wine's log says.
        let guarded = NextStart.asBefore(StartDiagnosis.diagnose(StartFinding(messages: ["Fatal error!"], missingRuntimes: ["vcrun2019"], graphicsFailed: true, layer: .dxvk)))
        check(guarded.map(\.id) == ["graphics-failed", "missing-runtime"] && guarded.first?.remedy == nil,
              "a game with an anti-cheat: its layer's failure is seen, not acted on (\(guarded.map(\.line)))")
        let dxvkFirst = [LaunchAttempt(graphics: .dxvk, arguments: ["-dx11"]), LaunchAttempt(graphics: .dxvk), d3dmetal]
        check(NextStart.after(NextStart.Failed(ladder: dxvkFirst, found: guarded, antiCheat: true))
              == .again(Learned(runtimes: ["vcrun2019"], steps: ["missing-runtime"]), why: ["missing-runtime"])
              && NextStart.after(NextStart.Failed(ladder: dxvkFirst, learned: Learned(runtimes: ["vcrun2019"]), found: guarded, antiCheat: true)) == .way(1, why: nil),
              "… its runtime as before, then simply the next way")
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 2, recipe: plain, found: nvidiaFound, antiCheat: true)) == .giveUp,
              "… and never a DLL off")

        // Which games that is (NextStart.handsOff): one with an anti-cheat, and one that brings a cheat protection of
        // its own – Overwatch, whose profile says so and whose folder holds no file of Easy Anti-Cheat or BattlEye.
        // Up to 15.11.2026 only the first kind counted in the start loop: Overwatch's dumps were read, a rule could
        // have switched a DLL of its off, and it got the closer look.
        let fm = FileManager.default
        let folders = fm.temporaryDirectory.appendingPathComponent("hands-off-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folders) }
        let plainFolder = folders.appendingPathComponent("Plain", isDirectory: true)
        let guardedFolder = folders.appendingPathComponent("Guarded", isDirectory: true)
        try fm.createDirectory(at: plainFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: guardedFolder.appendingPathComponent("EasyAntiCheat", isDirectory: true), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: plainFolder.appendingPathComponent("Game.exe"))
        let own = profile(#"{"ownAntiCheat": true, "graphics": "dxmt", "dllOverrides": {"nvapi64": "", "nvngx": ""}}"#)
        check(own?.ownAntiCheat == true && own?.antiCheat == nil && !ShaderCaches.hasAntiCheat(profile: own, block: nil, installDir: plainFolder),
              "a cheat protection of its own is no anti-cheat for the shader cache, as before")
        check(NextStart.handsOff(profile: own, block: nil, installDir: plainFolder), "… and one for the start loop: its failed start is read as before step E")
        check(!NextStart.handsOff(profile: nil, block: nil, installDir: plainFolder)
              && !NextStart.handsOff(profile: profile(#"{"graphics": "dxmt"}"#), block: nil, installDir: plainFolder)
              && !NextStart.handsOff(profile: profile(#"{"ownAntiCheat": false}"#), block: nil, installDir: plainFolder),
              "a game without either is read through the whole table")
        check(NextStart.handsOff(profile: profile(#"{"antiCheat": ["Vanguard"]}"#), block: nil, installDir: plainFolder)
              && NextStart.handsOff(profile: profile(#"{"antiCheatOnline": ["BattlEye"]}"#), block: nil, installDir: plainFolder)
              && NextStart.handsOff(profile: nil, block: AntiCheatBlock(antiCheat: ["RICOCHET"], geforceNow: nil), installDir: plainFolder)
              && NextStart.handsOff(profile: nil, block: nil, installDir: guardedFolder),
              "an anti-cheat by its profile, a block or its files, as before")
        // What follows from it in the loop, with Overwatch's own recipe: a crash the table knows changes nothing it
        // loads, nothing is looked at closer, and its way moves on as before step E.
        let overwatch = StartRecipe.of(way: hogwarts[0], learned: Learned(), profile: own, d3dMetalEngine: true)
        let crashFound = [found("physx-update-loader", .dllsOff(["physxupdateloader", "physxupdateloader64"])), found("crash", nil)]
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, recipe: overwatch, found: NextStart.asBefore(crashFound), antiCheat: true)) == .way(1, why: nil),
              "hands off: no DLL of its is switched off, whatever a dump would have said")
        check(CloserLook.step(unexplained: true, antiCheat: true, carried: false, takenBefore: false, canCarry: true, lastWay: true) == .none
              && CloserLook.step(unexplained: true, antiCheat: true, carried: false, takenBefore: false, canCarry: true, lastWay: false, proven: true) == .none,
              "… and no start of its carries the closer look's channels")

        // MARK: Step E6 – a closer look for a way that had worked, and a root the player is asked about

        // A proven way that ends again with nothing that says why: once more on it with the channels, quietly,
        // and it keeps its place whatever that start shows.
        let lookedAt = play(ladder: hogwarts, proven: true, looks: true) { _, _, _ in [found("crash", nil)] }
        check(lookedAt.steps == [.again(none, why: [NextStart.closerLook]), .keepsItsPlace] && lookedAt.starts == 2 && lookedAt.way == 0,
              "a proven way gets one start more for a closer look, then keeps its place (\(lookedAt.steps))")
        check(play(ladder: hogwarts, proven: true, looks: true) { start, _, _ in start == 1 ? [found("crash", nil)] : nil }.starts == 2,
              "… and where that start works, the Play is a start longer")
        check(play(ladder: hogwarts, proven: true, looks: true) { _, _, _ in [found("graphics-crash", .nextLayer)] }.steps == [.keepsItsPlace],
              "a failure the table explains needs no look: the place is kept at once")
        check(play(ladder: hogwarts, proven: true, antiCheat: true, looks: true) { _, _, _ in [] }.steps == [.keepsItsPlace],
              "never for a game with an anti-cheat")
        check(CloserLook.step(unexplained: true, antiCheat: false, carried: false, takenBefore: false, canCarry: true, lastWay: false, proven: true) == .sameWayAgain
              && CloserLook.step(unexplained: true, antiCheat: false, carried: false, takenBefore: true, canCarry: true, lastWay: false, proven: true) == .none
              && CloserLook.step(unexplained: true, antiCheat: false, carried: true, takenBefore: false, canCarry: true, lastWay: false, proven: true) == .none
              && CloserLook.step(unexplained: true, antiCheat: false, carried: false, takenBefore: false, canCarry: false, lastWay: false, proven: true) == .none
              && CloserLook.step(unexplained: true, antiCheat: false, carried: false, takenBefore: false, canCarry: true, lastWay: false) == .nextWay,
              "once per game and engine build, once per Play, only where the start can carry the channels; a way not proven as before")
        // The root a signature check stopped at: asked about only when it is one that can go into the prefix.
        let verisign = "VeriSign Class 3 Public Primary Certification Authority - G5"
        let rootFound = [found("said", nil), found("untrusted-root", .trustRoot(verisign))]
        check(NextStart.rootToAskAbout(rootFound, known: { $0 == verisign }) == verisign, "a root that is known: the player can be asked")
        check(NextStart.rootToAskAbout(rootFound, known: { _ in false }) == nil
              && NextStart.rootToAskAbout([found("untrusted-root", .trustRoot(nil))], known: { _ in true }) == nil
              && NextStart.rootToAskAbout([found("signature", nil), found("crash", nil)], known: { _ in true }) == nil,
              "an unknown root, a chain that named none, another finding: only said, as before")
        check(NextStart.rootToAskAbout(rootFound, known: { $0 == verisign }, askedBefore: [verisign]) == nil, "asked once per Play")
        check(NextStart.rootToAskAbout([found("said", nil)], known: { $0 == verisign }, needed: verisign) == verisign,
              "a root the game needed before: asked at a failed start without a closer look")
        check(NextStart.rootToAskAbout([found("said", nil)], known: { _ in false }, needed: verisign) == nil
              && NextStart.rootToAskAbout([found("said", nil)], known: { $0 == verisign }, askedBefore: [verisign], needed: verisign) == nil,
              "… unless it's in the prefix since, or asked in this Play")
        check(NextStart.after(rootTrusted: true, againSoFar: 0) == .again(why: ["untrusted-root"])
              && NextStart.after(rootTrusted: true, againSoFar: NextStart.againLimit) == .ends, "yes: the same way once more, within the cap")
        check(NextStart.after(rootTrusted: false, againSoFar: 0) == .ends, "no: the start ends here, the other ways aren't gone through")
        // Until the question is built, a root changes nothing by itself: the decision goes on as without it.
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, found: rootFound)) == .way(1, why: nil), "the finding alone moves nothing")
        check(WindowsRoots.all.contains { $0.name == verisign }, "the one root Nightforge knows is in every prefix already: nothing waits for a yes today")

        // MARK: The test switch's finding (step E3, live)

        let switchOff = TestDefaults.suite("test-finding")
        let dxmtStart = StartRecipe.of(way: hogwarts[0], learned: none, profile: nil, d3dMetalEngine: true)
        check(StartDiagnosis.testFinding(defaults: switchOff) == nil && StartDiagnosis.withTestFinding(physx, defaults: switchOff) == physx,
              "no switch: no finding, the table's as it is")
        switchOff.set("nvidia-interface", forKey: StartDiagnosis.testFindingKey)
        let given = StartDiagnosis.withTestFinding([found("crash", nil)], defaults: switchOff)
        check(given.map(\.id) == ["crash", "nvidia-interface"] && given.last?.remedy == .dllsOff(["nvapi64", "nvngx"])
              && given.last?.because.contains("switch") == true, "on: NVIDIA's interface, said as the switch's (\(given.map(\.line)))")
        // What follows it is what follows a real one: the same way, the DLLs off in the recipe, the rule in its steps.
        let afterSwitch = NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, recipe: dxmtStart, found: given))
        check(afterSwitch == .again(nvidiaOff, why: ["nvidia-interface"]), "… the same way once more without them (\(afterSwitch))")
        let switched = StartRecipe.of(way: hogwarts[0], learned: nvidiaOff, profile: nil, d3dMetalEngine: true)
        check(switched.dllOverrides["nvapi64"] == "" && switched.dllOverrides["nvngx"] == "" && switched.steps == ["nvidia-interface"],
              "… which the next start's recipe carries into the prefix")
        let nvidiaCrash = CrashDump(code: CrashDump.accessViolation, address: 0, module: nil,
                                    stack: [CrashDump.Frame(module: "nvapi64.dll", offset: 0x10)], modules: ["game.exe", "nvapi64.dll"])
        check(StartDiagnosis.withTestFinding(StartDiagnosis.diagnose(StartFinding(dumps: [nvidiaCrash])), defaults: switchOff)
              .filter { $0.id == "nvidia-interface" }.count == 1, "the table found it already: not twice")
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, learned: nvidiaOff, recipe: switched, found: given)) == .way(1, why: nil),
              "the DLLs off already: nothing more to change, on as without the switch")
        check(NextStart.after(NextStart.Failed(ladder: hogwarts, index: 0, recipe: dxmtStart, found: given, antiCheat: true)) == .way(1, why: nil),
              "a game with an anti-cheat: never a DLL off, switch or not")
        switchOff.set("physx-update-loader", forKey: StartDiagnosis.testFindingKey)
        check(StartDiagnosis.testFinding(defaults: switchOff)?.remedy == .dllsOff(loader), "the other value: the PhysX update loader")
        switchOff.set("graphics-failed", forKey: StartDiagnosis.testFindingKey)
        check(StartDiagnosis.testFinding(defaults: switchOff) == nil, "any other value: nothing")

        // MARK: Proofs hold for a recipe

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("start-recipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = folder.appendingPathComponent("evidence.jsonl")
        let ue426 = GameKind(engine: "unreal", engineVersion: "4.26", apis: ["d3d11", "d3d12"], middleware: ["physx3"], launcher: nil, antiCheat: false, bits: 64)
        // It Takes Two's Play above, as its record would read.
        let withLoader = StartRecipe.of(way: twoLadder[0], learned: none, profile: itTakesTwo, d3dMetalEngine: true)
        let withoutLoader = StartRecipe.of(way: twoLadder[0], learned: healed.learned, profile: itTakesTwo, d3dMetalEngine: true)
        StartEvidence.note(.started, game: twoGame, way: "d3dmetal", known: false, kind: ue426, recipe: withLoader, profiled: true, to: record)
        StartEvidence.note(.failed, game: twoGame, way: "d3dmetal", diagnosis: physx.map(\.line), to: record)
        StartEvidence.note(.started, game: twoGame, way: "d3dmetal", known: false, kind: ue426, recipe: withoutLoader, profiled: true, to: record)
        StartEvidence.note(.worked, game: twoGame, way: "d3dmetal", to: record)
        // A game without a profile that needed a runtime on its first way, and one recorded before recipes were.
        let dxmtPlain = StartRecipe.of(way: dxmt11, learned: none, profile: nil, d3dMetalEngine: true)
        let dxmtRuntime = StartRecipe.of(way: dxmt11, learned: runtime!, profile: nil, d3dMetalEngine: true)
        StartEvidence.note(.started, game: .steam(31), way: "dxmt -dx11", known: false, kind: ue426, recipe: dxmtPlain, to: record)
        StartEvidence.note(.failed, game: .steam(31), way: "dxmt -dx11", to: record)
        StartEvidence.note(.started, game: .steam(31), way: "dxmt -dx11", known: false, kind: ue426, recipe: dxmtRuntime, to: record)
        StartEvidence.note(.worked, game: .steam(31), way: "dxmt -dx11", to: record)
        StartEvidence.note(.started, game: .steam(32), way: "dxvk -dx11", known: false, to: record)
        StartEvidence.note(.worked, game: .steam(32), way: "dxvk -dx11", to: record)
        // One whose recipe failed, then failed again the same, then moved on.
        StartEvidence.note(.started, game: .steam(33), way: "dxmt -dx11", known: false, kind: ue426, recipe: dxmtPlain, to: record)
        StartEvidence.note(.failed, game: .steam(33), way: "dxmt -dx11", to: record)
        StartEvidence.note(.started, game: .steam(33), way: "dxmt -dx11", known: false, kind: ue426, recipe: dxmtPlain, to: record)
        StartEvidence.note(.failed, game: .steam(33), way: "dxmt -dx11", to: record)
        StartEvidence.note(.started, game: .steam(33), way: "d3dmetal", known: false, kind: ue426, recipe: plain, to: record)
        StartEvidence.note(.ended, game: .steam(33), way: "d3dmetal", picture: true, seconds: 70, to: record)
        let proofs = StartEvidence.proofs(StartEvidence.load(from: record))
        // A way started again with its recipe changed is still the game's first way.
        let firstStarts = StartEvidence.summary(StartEvidence.load(from: record))
        check(firstStarts == StartEvidence.Summary(firstWay: 3, laterWay: 0, noWay: 0, open: 1),
              "It Takes Two and the game that needed a runtime came up on their first way, at its second start (\(firstStarts))")

        let two = proofs[twoGame.key]
        check(two?.workedWith["d3dmetal"] == withoutLoader && two?.failedWith["d3dmetal"] == [withLoader],
              "It Takes Two: D3DMetal worked with the loader off and failed with it on – one way, two recipes")
        check(two?.holds(for: withoutLoader, on: "d3dmetal") == true && two?.holds(for: withLoader, on: "d3dmetal") == false && two?.holds(for: withoutLoader, on: "dxmt -dx11") == false,
              "its proof holds for the recipe that worked, not for the way with any recipe")
        check(two?.steps(on: "d3dmetal") == ["physx-update-loader"] && two?.steps(on: "dxmt -dx11") == [], "… and says what the table had changed for it")
        check(two?.worked.isEmpty == true && two?.failed.isEmpty == true, "a profile's start still proves nothing about D3DMetal for its sort")
        let needed = proofs["steam.31"]
        check(needed?.worked == ["dxmt -dx11"] && needed?.failed.isEmpty == true && needed?.workedWith["dxmt -dx11"] == dxmtRuntime && needed?.failedWith["dxmt -dx11"] == [dxmtPlain],
              "without a profile the way counts for its sort as before, and the recipe says with what")
        check(needed?.holds(for: dxmtRuntime, on: "dxmt -dx11") == true && needed?.holds(for: dxmtPlain, on: "dxmt -dx11") == false, "… its own proof is the recipe's")
        let before = proofs["steam.32"]
        check(before?.worked == ["dxvk -dx11"] && before?.workedWith.isEmpty == true && before?.holds(for: dxmtPlain, on: "dxvk -dx11") == true
              && before?.holds(for: dxmtPlain, on: "dxmt -dx11") == false, "a line from before recipes were recorded keeps its worth: it stands for its way")
        let stuck = proofs["steam.33"]
        check(stuck?.failedWith["dxmt -dx11"] == [dxmtPlain] && stuck?.failed == ["dxmt -dx11"] && stuck?.picture == ["d3dmetal"] && stuck?.workedWith.isEmpty == true,
              "the same recipe failing twice is one failure; a picture alone proves no recipe")
        check(StartEvidence.sortScores(for: ue426, excluding: "steam.99", proofs: proofs)["dxmt -dx11"] == StartEvidence.SortScore(points: 8, games: 1),
              "for its sort a way that worked with a changed recipe counts as the way it is: an order only")
        // A later bad start doesn't undo a recipe that worked.
        StartEvidence.note(.started, game: .steam(31), way: "dxmt -dx11", known: true, kind: ue426, recipe: dxmtRuntime, to: record)
        StartEvidence.note(.failed, game: .steam(31), way: "dxmt -dx11", reason: "a proven way ended in its first seconds again", to: record)
        let later = StartEvidence.proofs(StartEvidence.load(from: record))["steam.31"]
        check(later?.workedWith["dxmt -dx11"] == dxmtRuntime && later?.failedWith["dxmt -dx11"] == [dxmtPlain] && later?.worked == ["dxmt -dx11"],
              "a proven recipe's bad start later leaves the proof as it was")

        // MARK: An error box or a question of its own

        check(LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: nil, knownWindow: true),
              "The Forest, 3.11.: Unity's window, Quit – no message box, a window it's known to show: the player's choice as before")
        check(!LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: nil, knownWindow: false),
              "Metal Gear Solid V, 15.11.: a window of its own, no message box, no window of its own known – a failed start")
        check(LaunchHealth.showsOwnWindow(GameAnalysis(engine: .unity)) && LaunchHealth.showsOwnWindow({ var a = GameAnalysis(); a.launcherSwitch = "-nolauncher"; return a }())
              && LaunchHealth.showsOwnWindow({ var a = GameAnalysis(); a.launcher = "Ubisoft Connect"; return a }()),
              "Unity's configuration window, its own launcher window, another store's launcher: windows it's known to show")
        check(!LaunchHealth.showsOwnWindow(GameAnalysis(engine: .other)) && !LaunchHealth.showsOwnWindow(GameAnalysis(engine: .unreal)) && !LaunchHealth.showsOwnWindow(nil),
              "a game with none known, or nothing known of it: none")
        check(!LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: "Alan Wake could not initialize your 3D graphics card. Technical: DEVICE_CREATE_ERROR - Not available", knownWindow: false),
              "Alan Wake, 14.11.: its error box had only OK to press – not a choice")
        check(!LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: "Failed to load SteamAPI", knownWindow: false), "Metal Gear Solid V, 11.11.: the same")
        check(LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: "Start in safe mode?", knownWindow: false), "a message box that asks: the answer can be the end")
        check(!LaunchHealth.ownQuestionWasAChoice(explained: true, endedAtBox: nil, knownWindow: false) && !LaunchHealth.ownQuestionWasAChoice(explained: true, endedAtBox: "Start in safe mode?", knownWindow: false),
              "an end the table explains failed, whatever window stood there")
        check(!StartDiagnosis.unexplained(direct3D9) && !LaunchHealth.ownQuestionWasAChoice(explained: !StartDiagnosis.unexplained(direct3D9), endedAtBox: nil, knownWindow: false),
              "Alan Wake's Direct3D 9 on D3DMetal is explained without any channel")
        check(StartDiagnosis.unexplained([found("said", nil)]) && LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: nil, knownWindow: true)
              && !LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: nil, knownWindow: false),
              "no words read and nothing explained: a window the game is known to show stays the player's, any other is a failed start")
        // Alan Wake's start of 14.11. as its log was, through the whole chain: read, diagnosed, decided.
        let wake = try String(contentsOf: URL(fileURLWithPath: "tests/CloserLookTest/fixtures/msgbox-alanwake-2026-11-14.log"), encoding: .utf8)
        func wakeFinding(on layer: GraphicsLayer) -> StartFinding {
            StartDiagnosis.finding(logText: wake, installDir: folder.appendingPathComponent("AlanWake"), gameFolder: "AlanWake", since: Date(),
                                   layer: layer, hung: false, prefix: folder.appendingPathComponent("prefix"))
        }
        let onD3DMetal = wakeFinding(on: .d3dmetal), wakeFound = StartDiagnosis.diagnose(onD3DMetal)
        check(wakeFound.map(\.id) == ["direct3d9"] && onD3DMetal.messages.count == 1 && onD3DMetal.messages[0].hasPrefix("Alan Wake could not initialize your 3D graphics card."),
              "its log on D3DMetal: DXVK's Direct3D 9 got no device, and the box's text is the game's word (\(wakeFound.map(\.id)))")
        check(after(wakeFound, ladder: unknown) == .way(3, why: "direct3d9")
              && !LaunchHealth.ownQuestionWasAChoice(explained: !StartDiagnosis.unexplained(wakeFound), endedAtBox: onD3DMetal.reading.endedAtBox, knownWindow: false),
              "… so the next start is on Wine's own Direct3D, and the box was no choice of the player's")
        // The same box where no rule knows the cause: the box alone says it wasn't a choice.
        let onWine = wakeFinding(on: .wined3d), wineFound = StartDiagnosis.diagnose(onWine)
        check(wineFound.map(\.id) == ["said"] && StartDiagnosis.unexplained(wineFound)
              && !LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: onWine.reading.endedAtBox, knownWindow: false),
              "an error box with nothing else found: said, unexplained, and still a failed start (\(wineFound.map(\.id)))")

        print(failures == 0 ? "✓ StartRecipe" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
