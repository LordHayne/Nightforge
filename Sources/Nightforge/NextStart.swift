import Foundation

/// What comes after a start that ended without a picture: the same way once more with its recipe changed,
/// another way of the ladder, or no start at all. One decision for what the start loop does today in
/// branches of its own, each with its own memory – the engine before, a missing runtime, a settings file
/// fixed, no AVX, a closer look, the next way (docs/ENTWURF-STARTREZEPT.md 3.3, step E). It only reads
/// and answers; the loop starts, saves and says.
///
/// The measure is It Takes Two, 10.11.2026: it crashed the same way on all three graphics layers
/// (PhysXUpdateLoader64 → nvapi64 → 0), the ladder could only change the layer, and its crash dump named
/// the module all along. Here the first failure answers with the same way and the loader off, and the
/// player notices a longer wait.
///
/// LibraryModel's loop goes by it (step E2): it gathers what is known about the failed start, asks here, and
/// does what the answer says. Since step E3 every remedy of the table acts, for a game without an anti-cheat.
enum NextStart {
    /// The start that failed and what is known about it.
    struct Failed {
        /// The ways to try (empty: the layer was chosen by hand, or nothing is known about the game) and
        /// the one the start was on.
        var ladder: [LaunchAttempt] = []
        var index = 0
        /// The way had worked before this start.
        var proven = false
        /// What its recipe carried from the table already (LearnedFixes.learned).
        var learned = StartRecipe.Learned()
        /// What the start was made of. What it had already is no change: a start that didn't offer Rosetta's
        /// AVX – its profile's choice – isn't started again without it. nil: not known, every remedy counts.
        var recipe: StartRecipe?
        /// What the table read from the start (StartDiagnosis.diagnose). For a game with an anti-cheat: from
        /// Wine's log alone, as before – its files aren't looked into.
        var found: [StartDiagnosis] = []
        /// No DLL of such a game is ever switched off, whatever was found: what its programs load stays
        /// as the game ships it.
        var antiCheat = false
        /// Starts on the same way again so far in this Play.
        var againSoFar = 0
        /// The game ran on this way with the engine before and ended at once on the newest: the next start
        /// uses the one before (EngineRollback.afterFailedStart said so, and holds it).
        var engineBefore = false
        /// The profile's edits just changed a settings file the game wrote at this start (Engine.applyFileEdits).
        var filesFixed = false
        /// What a closer look asks for (CloserLook.step).
        var look = CloserLook.Step.none
    }

    enum Step: Equatable {
        /// The same way once more. `learned`: what the game's recipe carries from now on, changed or not.
        /// `why`: the rules of the table that asked for it, or one of the reasons below.
        case again(StartRecipe.Learned, why: [String])
        /// On to this way of the ladder. `why`: the rule that picked it; nil for simply the next.
        case way(Int, why: String?)
        /// A way that had worked keeps its place and is watched again at the next Play.
        case keepsItsPlace
        /// No ladder: nothing to switch to.
        case noOtherWay
        /// Every way tried.
        case giveUp
    }

    /// Reasons for the same way again that aren't rules of the table.
    static let engineBefore = "engine-before"
    static let fileEdits = "file-edits"
    static let closerLook = "closer-look"

    /// Starts on the same way again in one Play, at most. Each costs the player the time of a start, and
    /// the cap holds whatever a rule keeps finding. The start on the engine before doesn't count: that one
    /// is held by EngineRollback already and comes once.
    static let againLimit = 3

    /// In order: the engine before; all the table changes about the recipe, at once, with the profile's
    /// file edits; then the ladder – a closer look at the last way, a proven way's place, the way the
    /// findings point to.
    static func after(_ failed: Failed) -> Step {
        if failed.engineBefore { return .again(failed.learned, why: [engineBefore]) }
        let mayRepeat = failed.againSoFar < againLimit

        // What the table knows to change on the same way: every finding's remedy in one start, not one
        // start each – the player waits for starts, not for certainty about which of them it was.
        var learned = failed.learned
        var why: [String] = []
        for diagnosis in failed.found {
            guard var remedy = diagnosis.remedy else { continue }
            if failed.antiCheat, case .dllsOff = remedy { continue }
            if remedy == .noAVX, failed.recipe?.avx == false { continue }
            // A DLL the failed start had off already – its profile's, or Nightforge's for every game – isn't
            // what a start without it would change.
            if case .dllsOff(let dlls) = remedy, let recipe = failed.recipe {
                remedy = .dllsOff(dlls.filter { recipe.dllOverrides[StartRecipe.Learned.dllName($0)] != "" })
            }
            if let changed = learned.applying(remedy, rule: diagnosis.id) {
                learned = changed
                why.append(diagnosis.id)
            }
        }
        if failed.filesFixed { why.append(fileEdits) }
        if !why.isEmpty, mayRepeat { return .again(learned, why: why) }

        guard failed.ladder.indices.contains(failed.index) else { return .noOtherWay }
        // Nothing explains it and no way is left to carry the channels – the last way, or one that had worked
        // before and keeps its place (step E6): this one again, with them.
        if failed.look == .sameWayAgain, mayRepeat { return .again(failed.learned, why: [closerLook]) }
        if failed.proven, !StartDiagnosis.layerRefused(failed.found) { return .keepsItsPlace }
        let pointer = pointer(in: failed.found)
        guard let next = way(answering: pointer?.remedy, after: failed.index, in: failed.ladder) else { return .giveUp }
        return .way(next, why: pointer?.id)
    }

    /// The finding that picks the way to come: one that names what the way has to be (a layer, no switches)
    /// before one that only rules this layer out, before one that knows nothing better than the next. Among
    /// equals the table's order. Alan Wake on D3DMetal (11.11.2026) draws with Direct3D 9: should its d3d9.dll
    /// crash too, "another layer" would send it to DXMT, where Direct3D 9 is DXVK's just the same.
    static func pointer(in found: [StartDiagnosis]) -> StartDiagnosis? {
        func rank(_ remedy: StartRemedy?) -> Int? {
            switch remedy {
            case .dropArguments?, .layer?: return 0
            case .nextLayer?: return 1
            case .nextWay?: return 2
            default: return nil
            }
        }
        return found.enumerated().compactMap { place, finding in rank(finding.remedy).map { (rank: $0, place: place, finding: finding) } }
            .min { ($0.rank, $0.place) < ($1.rank, $1.place) }?.finding
    }

    /// The way of `ladder` after `index` that answers `remedy`, and the next one where none does or the
    /// remedy names none – as LaunchHealth.advance(answering:) picks for what a game said. Only ways still
    /// to come: the ones before had their start. nil: no way is left.
    static func way(answering remedy: StartRemedy?, after index: Int, in ladder: [LaunchAttempt]) -> Int? {
        let following = ladder.indices.dropFirst(index + 1)
        let answers: ((LaunchAttempt) -> Bool)?
        switch remedy {
        case .dropArguments?: answers = { $0.arguments.isEmpty }
        case .layer(let layer)?: answers = { $0.graphics == layer }
        case .nextLayer?:
            let now = ladder.indices.contains(index) ? ladder[index].graphics : nil
            answers = { $0.graphics != now }
        default: answers = nil
        }
        return answers.flatMap { answers in following.first { answers(ladder[$0]) } } ?? following.first
    }

    // MARK: - A root the player is asked about

    // Step E6, the player's decision of 14.11.2026: "untrusted-root" becomes a question, for a root
    // WindowsRoots knows by fixed fingerprints; any other is only said, as before. Asked on the curtain since
    // 15.11.2026 (LibraryModel.askToTrust, board "Vorhang bei Fehlstart"), for the roots WindowsRoots holds
    // only on a yes (`onRequest`) – none so far: all it knows go into every prefix, each with the user's OK.

    static let untrustedRoot = "untrusted-root"

    /// The root a failed start's signature check stopped at, when the player can be asked about it: the
    /// finding names it, `known` says it can be put into the prefix (by fingerprint, and it isn't there yet),
    /// and this Play hasn't asked about it. `needed`: the root an earlier start of the game stopped at
    /// (WindowsRoots.needed) – asked about at a failed start without a closer look, which came once already.
    /// A game with an anti-cheat has no such finding: its files aren't read, and nothing is asked for it.
    static func rootToAskAbout(_ found: [StartDiagnosis], known: (String) -> Bool, askedBefore: Set<String> = [],
                               needed: String? = nil) -> String? {
        for finding in found where finding.id == untrustedRoot {
            if case .trustRoot(let name?) = finding.remedy, known(name), !askedBefore.contains(name) { return name }
        }
        if let needed, known(needed), !askedBefore.contains(needed) { return needed }
        return nil
    }

    enum AfterRoot: Equatable {
        /// The root is in the prefix: the same way once more, noted as the rule's.
        case again(why: [String])
        /// No start comes after this one in this Play.
        case ends
    }

    /// What comes after the player's answer. Yes – the caller has put the root into the prefix: the same way
    /// once more, within the cap on such starts (past it the next Play starts with the root in place). No:
    /// the start ends here – the game checks the same file on every way, so going through the others would
    /// only take the player's time – and the ladder stays where it is.
    static func after(rootTrusted: Bool, againSoFar: Int) -> AfterRoot {
        rootTrusted && againSoFar < againLimit ? .again(why: [untrustedRoot]) : .ends
    }

    /// Whether a failed start of the game is read as before step E and its recipe left as it is: it carries an
    /// anti-cheat (ShaderCaches.hasAntiCheat: its profile's, a block, the files of one in its folder) or brings a
    /// cheat protection of its own (GameProfile.ownAntiCheat: Overwatch). The user's rule for such games – the
    /// player's account is at stake: nothing changes what they load, no tool attaches to their process, their
    /// files aren't looked into. So no crash dump of theirs is read, no DLL is switched off, no closer look is
    /// taken and no root is asked about (LibraryModel.launch); what acted before step E still does (`asBefore`).
    /// Up to 15.11.2026 only the first kind counted here, and Overwatch went through the loop as any game.
    static func handsOff(profile: GameProfile?, block: AntiCheatBlock?, installDir: URL) -> Bool {
        profile?.ownAntiCheat == true || ShaderCaches.hasAntiCheat(profile: profile, block: block, installDir: installDir)
    }

    /// The rules whose remedies changed a start before step E: the three things a game says that point to a
    /// way, and what Wine's log says of a missing runtime and an illegal instruction.
    static let actedBefore: Set<String> = ["refused-switch", "needs-d3d12", "direct3d9", "missing-runtime", "illegal-instruction"]

    /// `found` with only the remedies that acted before step E. All a game with an anti-cheat gets: its
    /// starts change the way they always did, and no further. The other findings stay as what was seen –
    /// the layer's own failure still moves a proven way on (StartDiagnosis.layerRefused) – and change nothing.
    static func asBefore(_ found: [StartDiagnosis]) -> [StartDiagnosis] {
        found.map { actedBefore.contains($0.id) ? $0 : StartDiagnosis(id: $0.id, because: $0.because, remedy: nil) }
    }

    /// What a game said, as the remedy the table gives for it (StartDiagnosis.rules).
    static func remedy(for failure: StartFailure) -> StartRemedy {
        switch failure {
        case .refusedSwitch: return .dropArguments
        case .needsD3D12: return .layer(.d3dmetal)
        case .needsD3D9: return .layer(.wined3d)
        }
    }
}
