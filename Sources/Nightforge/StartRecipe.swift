import Foundation

/// All that decides how a game starts, as one value: the graphics layer, the arguments, the DLLs it
/// gets or doesn't, the runtimes set up for it. It comes together from the ladder's way, the profile and
/// what earlier starts taught (LaunchHealth, LearnedFixes, Engine.gameDllOverrides), once per start
/// (LibraryModel.launch), and is what the start is made of and what it is recorded with (StartEvidence):
/// the prefix's settings for the game's programs, its arguments and Rosetta's AVX are read from it, so
/// that what worked can be told from what was only tried (docs/ENTWURF-STARTREZEPT.md 3.3, step E1).
struct StartRecipe: Codable, Equatable {
    var graphics: String
    var arguments: [String]
    var dllOverrides: [String: String]
    var runtimes: [String]
    /// Rosetta's AVX is offered to the game.
    var avx: Bool
    var windowsVersion: String?
    /// The rules of the diagnosis table whose remedies it carries ("nvidia-interface"), in the order they
    /// came: what sets it apart from its way's and its profile's own. nil where there are none, and in
    /// every line recorded before 14.11.2026.
    var steps: [String]?

    /// The recipe of a start on `layer`. `arguments`: the way's own and the switch past the game's
    /// launcher window; the profile's go before them where they belong to this layer – the order the game
    /// gets them in (Launcher.launch). Lines recorded before 14.11.2026 have the profile's last (`startsLike`).
    static func of(layer: GraphicsLayer, arguments: [String], profile: GameProfile?, learnedRuntimes: [String],
                   avx: Bool, d3dMetalEngine: Bool) -> StartRecipe {
        StartRecipe(graphics: layer.rawValue,
                    arguments: (profile?.arguments(on: layer) ?? []) + arguments,
                    dllOverrides: Engine.gameDllOverrides(layer, profile: profile, d3dMetalEngine: d3dMetalEngine),
                    runtimes: Array(Set((profile?.winetricks ?? []) + learnedRuntimes)).sorted(),
                    avx: avx,
                    windowsVersion: profile?.windowsVersion)
    }

    /// The recipe of a start on `way` with what the diagnosis has taught about the game (`learned`).
    /// `launcherSwitch`: the switch past the game's own launcher window (ProgramText.launcherSwitch), which
    /// goes with every start and isn't part of the way. What was learned goes over the profile's and the
    /// layer's DLLs: it answers a failure seen in this game on this Mac.
    static func of(way: LaunchAttempt, learned: Learned, profile: GameProfile?, launcherSwitch: String? = nil,
                   d3dMetalEngine: Bool) -> StartRecipe {
        var recipe = of(layer: way.graphics, arguments: pastLauncher(way.arguments, switch: launcherSwitch), profile: profile,
                        learnedRuntimes: learned.runtimes,
                        avx: profile?.avx != false && !learned.noAVX, d3dMetalEngine: d3dMetalEngine)
        for dll in learned.dllsOff { recipe.dllOverrides[dll] = "" }
        recipe.steps = learned.steps.isEmpty ? nil : learned.steps
        return recipe
    }

    /// A start's arguments with the switch past the game's own launcher window, once: straight into the
    /// game, as on a console (Guardians of the Galaxy, 9.11.2026). Not part of the way.
    static func pastLauncher(_ arguments: [String], switch launcherSwitch: String?) -> [String] {
        guard let launcherSwitch, !arguments.contains(where: { $0.caseInsensitiveCompare(launcherSwitch) == .orderedSame }) else { return arguments }
        return arguments + [launcherSwitch]
    }

    /// The same start, whatever led to it: all that reaches Wine, not which rule asked for it (`steps`).
    /// The arguments count whatever their order: the profile's stood behind the way's in the record up to
    /// 14.11.2026 and stand before them since, as the game gets them – the same start both times.
    func startsLike(_ other: StartRecipe) -> Bool {
        graphics == other.graphics && arguments.sorted() == other.arguments.sorted() && dllOverrides == other.dllOverrides
            && Set(runtimes) == Set(other.runtimes) && avx == other.avx && windowsVersion == other.windowsVersion
    }

    /// What the diagnosis has changed about a game's starts, kept with the game (LearnedFixes.learned): the
    /// part of its recipe that is neither its way's nor its profile's. Every entry answers a failure the
    /// table knows (StartDiagnosis.rules) – nothing gets in here by a guess. Runtimes and the AVX hint have
    /// been learned this way since 0.2; DLLs kept unloaded and the rules' names are step E's.
    struct Learned: Codable, Equatable {
        /// DLLs that stay unloaded: lower case, without ".dll".
        var dllsOff: [String] = []
        /// winetricks verbs (and GameLog.wineMono).
        var runtimes: [String] = []
        var noAVX = false
        /// The rules that asked for a change, each once, in the order they came.
        var steps: [String] = []

        /// With what `remedy` asks for, noted as `rule`'s. nil when the remedy isn't a change to the recipe
        /// on the same way – another layer, other arguments and the next way are the ladder's
        /// (NextStart.way), a root needs the player's OK – or when it changes nothing: it's all in already.
        /// A Direct3D DLL is never switched off here: which copy of those loads is the way's.
        func applying(_ remedy: StartRemedy, rule: String) -> Learned? {
            var changed = self
            switch remedy {
            case .dllsOff(let dlls):
                for dll in dlls.map(Self.dllName) where !dll.isEmpty && !StartDiagnosis.graphicsModules.contains(dll + ".dll")
                    && !changed.dllsOff.contains(dll) {
                    changed.dllsOff.append(dll)
                }
            case .runtimes(let verbs):
                for verb in verbs where !verb.isEmpty && !changed.runtimes.contains(verb) { changed.runtimes.append(verb) }
            case .noAVX:
                changed.noAVX = true
            case .dropArguments, .layer, .nextLayer, .trustRoot, .nextWay:
                return nil
            }
            guard changed != self else { return nil }
            if !changed.steps.contains(rule) { changed.steps.append(rule) }
            return changed
        }

        /// For the log: "DLLs off nvapi64, nvngx; runtimes vcrun2019; without AVX (nvidia-interface, missing-runtime)".
        var summary: String {
            var parts: [String] = []
            if !dllsOff.isEmpty { parts.append("DLLs off " + dllsOff.joined(separator: ", ")) }
            if !runtimes.isEmpty { parts.append("runtimes " + runtimes.joined(separator: ", ")) }
            if noAVX { parts.append("without AVX") }
            return parts.joined(separator: "; ") + (steps.isEmpty ? "" : " (" + steps.joined(separator: ", ") + ")")
        }

        /// "NVAPI64.dll" → "nvapi64": a DLL as Wine's overrides name it.
        static func dllName(_ name: String) -> String {
            let lower = name.lowercased()
            return lower.hasSuffix(".dll") ? String(lower.dropLast(4)) : lower
        }
    }
}
