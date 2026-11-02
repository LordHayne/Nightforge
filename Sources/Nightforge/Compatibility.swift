import SwiftUI

/// How well a game runs on a Mac – Nightforge's answer to Steam Deck Verified. Worked out on the
/// Mac from what's already there: the profile list, how the game's starts went, its files.
struct Compatibility: Equatable {
    enum Level: String, CaseIterable {
        case great, tweaks, no, untested
        /// Doesn't start on a Mac yet, and Nightforge is working on it (the profile's "notYet"): not the red of "no".
        case notYet

        var label: String {
            switch self {
            case .great: return L10n.t("Runs great")
            case .tweaks: return L10n.t("Runs with tweaks")
            case .no: return L10n.t("Doesn't run on a Mac")
            case .untested: return L10n.t("Not tested yet")
            case .notYet: return L10n.t("Doesn't start yet")
            }
        }

        var symbol: String {
            switch self {
            case .great: return "checkmark.circle.fill"
            case .tweaks: return "wrench.and.screwdriver.fill"
            case .no: return "xmark.circle.fill"
            case .untested: return "questionmark.circle.fill"
            case .notYet: return "hourglass"
            }
        }

        var color: Color {
            switch self {
            case .great: return Theme.runsGreat
            case .tweaks: return Theme.runsWithTweaks
            case .no: return Theme.runsNot
            case .untested: return Theme.muted
            case .notYet: return Theme.runsNotYet
            }
        }

        /// The game doesn't start on this Mac (for good, or not yet).
        var stopsGame: Bool { self == .no || self == .notYet }
    }

    var level: Level
    /// One line on what "tweaks" means for this game, or why it doesn't run.
    var note: String?
    /// Apple chips Nightforge tested it on ("M5"), from its own profile.
    var testedOn: [String] = []

    /// What the rating is worked out from.
    struct Facts {
        var platform = Platform.windows
        var vrOnly = false
        var antiCheatBlock: AntiCheatBlock?
        var profile: GameProfile?
        var analysis: GameAnalysis?
        /// Nightforge found something the game needs by itself (LearnedFixes).
        var learnedFixes = false
        /// Where the self-healing launch stands (LaunchHealth): nil before the first start.
        var launch: (index: Int, confirmed: Bool)?
        /// How it ran for the player ("Welcome back"): beats everything but what stops the game.
        var ownRating: GameRating?
        /// What AppleGamingWiki says (profiles/agw.json): others' tests on other versions, so only said
        /// for a game nothing else rates – it stays "Not tested yet".
        var reported: AGWEntry?
    }

    /// Worst first: what stops the game, then what it needs, then what shows it runs.
    static func rate(_ facts: Facts) -> Compatibility {
        let profile = facts.profile
        if facts.vrOnly {
            return .init(level: .no, note: L10n.t("Needs a VR headset."))
        }
        // Not yet: the profile says so, tested on a Mac – with the block at hand or from the profile alone.
        if facts.platform == .windows, let reason = facts.antiCheatBlock?.notYet ?? profile?.notYet {
            let cloud = (facts.antiCheatBlock?.geforceNow ?? profile?.geforceNow) != nil
            return .init(level: .notYet, note: [L10n.t(reason), cloud ? L10n.t("Playable on GeForce Now instead.") : nil]
                .compactMap { $0 }.joined(separator: " "), testedOn: chips(in: profile?.note))
        }
        if facts.platform == .windows, let block = facts.antiCheatBlock {
            return .init(level: .no, note: block.geforceNow == nil
                ? L10n.t("Its anti-cheat needs Windows itself.")
                : L10n.t("Its anti-cheat needs Windows – playable on GeForce Now instead."))
        }
        if let rating = facts.ownRating, rating.didntStart == true {
            return .init(level: .no, note: L10n.t("You said it didn't start."))
        }
        if let rating = facts.ownRating {
            return rating.good
                ? .init(level: .great, note: L10n.t("You said it runs well."))
                : .init(level: .tweaks, note: rating.issues.isEmpty ? L10n.t("You said it didn't run well.")
                        : L10n.t("You said: %@.", rating.issues.map(\.label).joined(separator: ", ")))
        }
        // Steam's own Mac version: nothing to translate.
        if facts.platform == .mac {
            return .init(level: .great)
        }
        let testedOn = chips(in: profile?.note)
        if let analysis = facts.analysis {
            if analysis.onlyD3D12 {
                return .init(level: .tweaks, note: L10n.t("DirectX 12 only: it runs through Apple's D3DMetal, which not every game likes."),
                             testedOn: testedOn)
            }
            // A Mac profile's empty list says the anti-cheat doesn't get in the way after all.
            if !analysis.antiCheat.isEmpty, profile?.antiCheat?.isEmpty != true {
                return .init(level: .tweaks, note: L10n.t("Online play with %@ doesn't work on a Mac.",
                                                          analysis.antiCheat.joined(separator: ", ")),
                             testedOn: testedOn)
            }
        }
        if profile?.fromNightforge == true {
            return .init(level: .great, testedOn: testedOn)
        }
        if profile?.hasFixes == true {
            return .init(level: .tweaks, note: L10n.t("Starts with fixes from umu-protonfixes, applied automatically."))
        }
        if facts.learnedFixes || (facts.launch?.index ?? 0) > 0 {
            return .init(level: .tweaks, note: L10n.t("Nightforge found what it needs by itself and applies it at every start."))
        }
        if facts.launch?.confirmed == true {
            return .init(level: .great)
        }
        if facts.platform == .windows, let reported = facts.reported, let said = reported.wineSummary {
            // Said before the download, honestly: a bad word from the wiki is a warning, never a block.
            let runs = reported.ways.contains { $0.way.throughWine && $0.report.rating.good }
            return .init(level: .untested, note: runs ? L10n.t("According to AppleGamingWiki: %@.", said)
                         : L10n.t("According to AppleGamingWiki it runs badly through CrossOver and Wine (%@) – it may not run here either.", said))
        }
        return .init(level: .untested)
    }

    /// "M5", "M3 Pro" in a profile's test note, each once, in order.
    static func chips(in note: String?) -> [String] {
        guard let note, let pattern = try? NSRegularExpression(pattern: #"\bM[1-9][0-9]?(?: (?:Pro|Max|Ultra))?\b"#) else { return [] }
        var found: [String] = []
        for match in pattern.matches(in: note, range: NSRange(note.startIndex..., in: note)) {
            guard let range = Range(match.range, in: note) else { continue }
            let chip = String(note[range])
            if !found.contains(chip) { found.append(chip) }
        }
        return found
    }
}

extension Compatibility {
    /// For a game in the library, from the profile list and what this Mac learned about it. `insight`:
    /// the ways the game starts by (a source's hint included), else they're worked out again.
    static func of(_ game: Game, profile: GameProfile?, analysis: GameAnalysis?, insight: GameInsight? = nil,
                   reported: AGWEntry? = nil) -> Compatibility {
        var facts = Facts(platform: game.platform, vrOnly: game.isVROnly, antiCheatBlock: game.antiCheatBlock,
                          profile: profile, analysis: analysis)
        facts.learnedFixes = !LearnedFixes.winetricks(game.gameID).isEmpty || LearnedFixes.noAVX(game.gameID)
        facts.ownRating = GameRatings.load(game.gameID)
        facts.reported = reported
        if let analysis {
            let attempts = insight?.attempts ?? LaunchHealth.attempts(for: analysis, profile: profile)
            facts.launch = LaunchHealth.peek(game.gameID, LaunchHealth.ladder(attempts, preset: GameOptionsStore.load(game.gameID).preset,
                                                                              profile: profile, hint: insight?.hint))
        }
        return rate(facts)
    }
}

extension GameProfile {
    /// Nightforge's own profile, tested on a Mac (alone or on top of umu-protonfixes).
    var fromNightforge: Bool {
        source?.split(separator: "+").contains("mac") == true
    }

    /// Changes something about how the game starts (save folders and anti-cheat facts don't).
    var hasFixes: Bool {
        graphics != nil || arguments?.isEmpty == false || dllOverrides?.isEmpty == false
            || registry?.isEmpty == false || windowsVersion != nil || winetricks?.isEmpty == false
            || metalFX == false || frameLimit != nil || vulkanSamplers != nil || avx == false
            || fileEdits?.isEmpty == false || iniSettings?.isEmpty == false || retina == true
    }
}

/// "Runs great": always an icon and a word, never the colour alone.
struct CompatibilityBadge: View {
    let compatibility: Compatibility
    var small = false

    var body: some View {
        let level = compatibility.level
        HStack(spacing: 6) {
            Image(systemName: level.symbol)
                .font(size: small ? 11 : 12, weight: .semibold)
            Text(level.label)
                .font(size: small ? 11.5 : 12.5, weight: .semibold)
                .lineLimit(1)
        }
        .foregroundStyle(level.color)
        .padding(.horizontal, small ? 8 : 10)
        .padding(.vertical, small ? 2 : 4)
        .background(level.color.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(level.color.opacity(0.3), lineWidth: 1))
        .help(compatibility.note ?? level.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([level.label, compatibility.note].compactMap { $0 }.joined(separator: ". "))
    }
}
