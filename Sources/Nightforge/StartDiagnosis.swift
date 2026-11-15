import Foundation

/// What a start that didn't come to a picture left behind, gathered in one place: the game's own words,
/// its crash dumps, and what Wine's log says.
struct StartFinding: Equatable {
    /// The messages of its crash reports (GameLog.crashMessages).
    var messages: [String] = []
    var dumps: [CrashDump] = []
    /// winetricks verbs for DLLs Wine couldn't find (GameLog.missingRuntimes).
    var missingRuntimes: [String] = []
    var illegalInstruction = false
    /// The graphics layer said it can't draw (GameLog.graphicsFailed).
    var graphicsFailed = false
    /// DXVK got no device on a start that isn't DXVK's own: Direct3D 9 (GameLog.direct3D9Failed).
    var direct3D9Failed = false
    /// It ran without a picture and without work (PictureWatch).
    var hung = false
    /// The way the start was on, where a rule needs it.
    var layer: GraphicsLayer?
    /// What Wine's debug channels printed for the game, when the start carried them (CloserLook).
    var reading = CloserLook.Reading()
}

/// What can be changed about a start. Every one is a change to its recipe (StartRecipe).
enum StartRemedy: Equatable {
    /// Without the switches Nightforge added.
    case dropArguments
    case layer(GraphicsLayer)
    case nextLayer
    /// These DLLs stay unloaded (a DLL override "").
    case dllsOff([String])
    case runtimes([String])
    case noAVX
    /// This root certificate into the prefix's own store (WindowsRoots). Never by itself: each root needs
    /// the player's OK. nil: the chain named no root.
    case trustRoot(String?)
    /// Nothing known to change: the next way as it stands.
    case nextWay

    /// It is answered by another way of the ladder (NextStart.way), not by a change on the same one
    /// (StartRecipe.Learned.applying).
    var picksAWay: Bool {
        switch self {
        case .dropArguments, .layer, .nextLayer, .nextWay: return true
        case .dllsOff, .runtimes, .noAVX, .trustRoot: return false
        }
    }

    var label: String {
        switch self {
        case .dropArguments: return "start without the added switches"
        case .layer(let layer): return "start on \(layer.rawValue)"
        case .nextLayer: return "another graphics layer"
        case .dllsOff(let dlls): return "keep \(dlls.joined(separator: ", ")) unloaded"
        case .runtimes(let verbs): return "install \(verbs.joined(separator: ", "))"
        case .noAVX: return "start without AVX"
        case .trustRoot(let root): return "trust " + (root.map { "the root \"\($0)\"" } ?? "its root") + " in the prefix, with the player's OK"
        case .nextWay: return "the next way"
        }
    }
}

/// One thing a failed start showed, and what answers it. The table (`rules`) is the one place that
/// says which failure calls for which change; a remedy comes from it or from a reviewed profile, never
/// from a guess. The diagnosis is said (the log, the start's record, the problem report) and, since step
/// E3, acted on: NextStart.after reads it and changes the start's recipe or picks its way
/// (docs/ENTWURF-STARTREZEPT.md 3.3).
struct StartDiagnosis: Equatable {
    /// "physx-update-loader": stable, for the record.
    var id: String
    /// What was seen, in words.
    var because: String
    /// nil: seen, but nothing known that answers it.
    var remedy: StartRemedy?

    /// "physx-update-loader: 0xc0000005 at 0x0, from nvapi64.dll+0x1120 ← … → keep … unloaded"
    var line: String { "\(id): \(because)" + (remedy.map { " → \($0.label)" } ?? " → no remedy known") }

    /// The graphics layers' own DLLs, and Wine's that carry them.
    static let graphicsModules: Set<String> = [
        "d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll",
        "wined3d.dll", "winemetal.dll", "winevulkan.dll", "vulkan-1.dll", "opengl32.dll",
    ]
    /// NVIDIA's interface, which D3DMetal answers for the card it stands in for.
    static let nvidiaModules: Set<String> = ["nvapi64.dll", "nvapi.dll", "nvngx.dll", "_nvngx.dll"]

    /// The table. Each rule looks at the whole finding and answers with what it saw, or nil. In order:
    /// the more exact a rule, the earlier.
    static let rules: [(id: String, read: (StartFinding) -> (because: String, remedy: StartRemedy?)?)] = [
        // Hogwarts Legacy, 9.11.2026: "-d3d12, -d3d11, -vulkan, -opengl mutually exclusive" with -dx11.
        ("refused-switch", { finding in
            StartFailure.read(finding.messages) == .refusedSwitch ? (said(finding, "mutually exclusive"), .dropArguments) : nil
        }),
        ("needs-d3d12", { finding in
            StartFailure.read(finding.messages) == .needsD3D12 ? (finding.messages.first ?? "", .layer(.d3dmetal)) : nil
        }),
        // Metal Gear Solid V, 11.11.2026: it checks steam_api64.dll's signature (Valve, 2015), whose root macOS
        // no longer carries, and says "Failed to load SteamAPI". Seen only by a start with the channels on.
        ("untrusted-root", { finding in
            finding.reading.signatures.first { $0.code == CloserLook.untrustedRootCode }.map { check in
                ((check.file ?? "a file") + "'s signature" + (check.signer.map { " (\($0))" } ?? "") + " leads to "
                    + (check.root.map { "the root \"\($0)\", which this Mac doesn't trust" } ?? "a root this Mac doesn't trust"),
                 .trustRoot(check.root))
            }
        }),
        ("signature", { finding in
            finding.reading.signatures.first { $0.code != CloserLook.untrustedRootCode }.map { check in
                ((check.file ?? "a file") + "'s signature check answered " + String(format: "%08x", check.code)
                    + (CloserLook.meaning(of: check.code).map { " (\($0))" } ?? ""), nil)
            }
        }),
        // It Takes Two, 10.11.2026: the PhysX System Software's update loader asks NVAPI, D3DMetal's
        // nvapi64 jumps to 0. Off for every game since 0df3c58; a profile can bring the loader back.
        ("physx-update-loader", { finding in
            finding.dumps.first { dump in
                let chain = dump.chain
                return chain.prefix(3).contains(where: nvidiaModules.contains)
                    && chain.prefix(6).contains { $0.hasPrefix("physxupdateloader") }
            }.map { ($0.summary, .dllsOff(["physxupdateloader", "physxupdateloader64"])) }
        }),
        // Overwatch, 7.11.2026: it ran once nvapi64 and nvngx stayed out.
        ("nvidia-interface", { finding in
            finding.dumps.first { dump in
                dump.chain.first.map(nvidiaModules.contains) == true && !dump.chain.prefix(6).contains { $0.hasPrefix("physxupdateloader") }
            }.map { ($0.summary, .dllsOff(["nvapi64", "nvngx"])) }
        }),
        ("illegal-instruction", { finding in
            if let dump = finding.dumps.first(where: { $0.code == CrashDump.illegalInstruction }) { return (dump.summary, .noAVX) }
            return finding.illegalInstruction ? ("Wine reports an illegal instruction", .noAVX) : nil
        }),
        ("graphics-crash", { finding in
            finding.dumps.first { $0.chain.first.map(graphicsModules.contains) == true }.map { ($0.summary, .nextLayer) }
        }),
        // Alan Wake, 11.11.2026: started on D3DMetal, where Direct3D 9 is DXVK's and gets no device.
        ("direct3d9", { finding in
            finding.direct3D9Failed ? ("DXVK got no device on a way that isn't DXVK's: the game draws with Direct3D 9", .layer(.wined3d)) : nil
        }),
        // The same without DXVK's own words: the game loaded Direct3D 9 and nothing newer.
        ("loads-direct3d9", { finding in
            guard !finding.direct3D9Failed, let layer = finding.layer, GameLog.direct3D9IsDXVKs(on: layer),
                  finding.reading.loadsOnlyDirect3D9 else { return nil }
            return ("the game loaded d3d9.dll and no newer Direct3D, on a way whose Direct3D 9 is DXVK's", .layer(.wined3d))
        }),
        ("graphics-failed", { finding in
            finding.graphicsFailed ? ("the graphics layer says it can't draw", .nextLayer) : nil
        }),
        ("missing-runtime", { finding in
            finding.missingRuntimes.isEmpty ? nil : ("Wine couldn't find a DLL of " + finding.missingRuntimes.joined(separator: ", "),
                                                    .runtimes(finding.missingRuntimes))
        }),
        ("hung", { finding in
            finding.hung ? ("it ran without a picture and without work", .nextWay) : nil
        }),
    ]

    /// The rules that explain a crash dump.
    private static let fromDumps: Set<String> = ["physx-update-loader", "nvidia-interface", "illegal-instruction", "graphics-crash"]

    /// Everything the table reads from a finding. A crash no rule knows is still said, with where it
    /// came from: that's how the next rule gets found.
    static func diagnose(_ finding: StartFinding) -> [StartDiagnosis] {
        var found = rules.compactMap { rule in
            rule.read(finding).map { StartDiagnosis(id: rule.id, because: $0.because, remedy: $0.remedy) }
        }
        if !found.contains(where: { fromDumps.contains($0.id) }), let dump = finding.dumps.first {
            found.append(StartDiagnosis(id: "crash", because: dump.summary, remedy: nil))
        } else if found.isEmpty, let said = finding.messages.first {
            found.append(StartDiagnosis(id: "said", because: said, remedy: nil))
        } else if found.isEmpty, !finding.reading.debugOutput.isEmpty {
            // What the game put out for a debugger last, newest at the end.
            found.append(StartDiagnosis(id: "debug-said", because: finding.reading.debugOutput.suffix(3).joined(separator: " | "), remedy: nil))
        }
        return found
    }

    /// What says that something happened, not why: a crash or words no rule knows, and a start that hung.
    private static let fallbacks: Set<String> = ["crash", "said", "debug-said", "hung"]

    /// Nothing in `found` explains the start – also when nothing was found at all. Then a closer look is
    /// worth a start (CloserLook.step).
    static func unexplained(_ found: [StartDiagnosis]) -> Bool {
        found.allSatisfy { fallbacks.contains($0.id) }
    }

    /// The rules that saw the start fail: the game's own refusal, a crash at a place the table knows, Wine's
    /// or the layer's own error. Not what only describes a start – what it loaded, a signature it checked –
    /// and not the fallbacks. Since every start carries +loaddll (step E5), "loads-direct3d9" is found for
    /// any Direct3D 9 game on DXMT or D3DMetal, also one that ran and was quit at its own launcher window.
    private static let failuresSeen: Set<String> = [
        "refused-switch", "needs-d3d12", "physx-update-loader", "nvidia-interface", "illegal-instruction", "graphics-crash",
        "direct3d9", "graphics-failed", "missing-runtime",
    ]

    /// Something in `found` says the start failed, whatever window it ended at: then its end wasn't the
    /// player's choice (LaunchHealth.ownQuestionWasAChoice).
    static func sawFailure(_ found: [StartDiagnosis]) -> Bool {
        found.contains { failuresSeen.contains($0.id) }
    }

    /// The graphics layer itself said it can't draw (GameLog.graphicsFailed): the one finding that moves a
    /// way on that had worked before. Anything else leaves a proven way its place (LaunchHealth.earlyEnd).
    static func layerRefused(_ found: [StartDiagnosis]) -> Bool {
        found.contains { $0.id == "graphics-failed" }
    }

    private static func said(_ finding: StartFinding, _ part: String) -> String {
        finding.messages.first { $0.lowercased().contains(part) } ?? finding.messages.first ?? ""
    }

    // MARK: - A start's finding, from its files

    /// Gathers what a start since `startedAt` left: its crash reports and dumps, and Wine's log from
    /// `logText` – with what a closer look's channels printed, when the start carried them. A message box's
    /// text counts as the game's own words, behind its crash reports'. An illegal instruction is Wine's word
    /// or a crash report's (Unreal catches it itself), as GameLog.illegalInstruction reads it. The caller
    /// leaves games with an anti-cheat out: their files aren't looked into.
    static func finding(logText: String, installDir: URL, gameFolder: String, since startedAt: Date, layer: GraphicsLayer,
                        hung: Bool, prefix: URL = Engine.prefix) -> StartFinding {
        let reading = CloserLook.read(logText, gameFolder: gameFolder)
        let reported = GameLog.crashReports(installDir: installDir, since: startedAt, prefix: prefix).contains {
            ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains("EXCEPTION_ILLEGAL_INSTRUCTION")
        }
        return StartFinding(messages: GameLog.crashMessages(installDir: installDir, since: startedAt, prefix: prefix) + reading.boxes,
                     dumps: GameLog.crashDumps(installDir: installDir, since: startedAt, prefix: prefix).compactMap(CrashDump.read),
                     missingRuntimes: GameLog.missingRuntimes(in: logText, gameFolder: gameFolder),
                     illegalInstruction: GameLog.illegalInstruction(in: logText) || reported,
                     graphicsFailed: GameLog.graphicsFailed(in: logText, layer: layer),
                     direct3D9Failed: GameLog.direct3D9Failed(in: logText, layer: layer),
                     hung: hung, layer: layer, reading: reading)
    }

    // MARK: - A finding for Nightforge's own tests

    /// The hidden switch that gives a start which really ended without a picture a finding of the table's,
    /// so that what follows it – the decision, what's learned, the recipe, the prefix, the record, and the
    /// curtain saying so – can be seen on a real game (step E3). It Takes Two stopped crashing over PhysX's
    /// update loader by 15.11.2026, and no real start on this Mac had a dump a rule knows. For Nightforge's
    /// own tests: no entry in the interface, off unless someone sets it
    /// (`defaults write io.github.lordhayne.nightforge testFinding -string nvidia-interface`; the other value
    /// is physx-update-loader). It never makes a start fail, never acts on a game with an anti-cheat (whose
    /// files and DLLs are left alone), and changes nothing a start had already. Read at every failed start,
    /// so `defaults delete io.github.lordhayne.nightforge testFinding` ends it without a restart.
    ///
    /// A build made with NIGHTFORGE_RELEASE has no such switch at all, not even its name (as GameTest.measuresPlay).
    #if NIGHTFORGE_RELEASE
    static func testFinding(defaults: UserDefaults = .standard) -> StartDiagnosis? { nil }
    #else
    static let testFindingKey = "testFinding"

    static func testFinding(defaults: UserDefaults = .standard) -> StartDiagnosis? {
        let because = "set by the engine test's switch testFinding, not read from the game"
        switch defaults.string(forKey: testFindingKey) {
        case "nvidia-interface"?:
            return StartDiagnosis(id: "nvidia-interface", because: because, remedy: .dllsOff(["nvapi64", "nvngx"]))
        case "physx-update-loader"?:
            return StartDiagnosis(id: "physx-update-loader", because: because, remedy: .dllsOff(["physxupdateloader", "physxupdateloader64"]))
        default:
            return nil
        }
    }
    #endif

    /// What the table read, with the test switch's finding on top when it's on and the table hasn't found it.
    static func withTestFinding(_ found: [StartDiagnosis], defaults: UserDefaults = .standard) -> [StartDiagnosis] {
        guard let test = testFinding(defaults: defaults), !found.contains(where: { $0.id == test.id }) else { return found }
        return found + [test]
    }

    // MARK: - The last start's diagnosis, for the problem report

    private static func key(_ game: GameID) -> String { "startDiagnosis.\(game.key)" }

    static func remember(_ lines: [String], for game: GameID, defaults: UserDefaults = .standard) {
        if lines.isEmpty { defaults.removeObject(forKey: key(game)) } else { defaults.set(lines, forKey: key(game)) }
    }

    static func remembered(_ game: GameID, defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key(game)) ?? []
    }
}
