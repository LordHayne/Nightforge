import AppKit
import Foundation

/// What Nightforge knows about an installed game before starting it.
struct GameInsight: Equatable {
    let analysis: GameAnalysis
    /// The ways "Automatic" tries, in order (LaunchHealth).
    let attempts: [LaunchAttempt]
}

/// A game that ended right after starting with every way Nightforge knows.
struct FailedLaunch: Identifiable {
    let game: Game
    let tried: [String]
    var id: String { game.id }
}

/// "Doesn't run?": a GitHub issue filled in with what Nightforge knows about the game, opened in
/// the player's browser. Nothing leaves the Mac unless the player submits it there.
@MainActor
enum ProblemReport {
    /// `tried`: the ways a start that failed every time went through, in order.
    static func open(game: Game, insight: GameInsight?, profile: GameProfile? = nil, tried: [String] = []) {
        if let url = url(game: game, insight: insight, profile: profile, tried: tried) { NSWorkspace.shared.open(url) }
    }

    /// Which game it is: Steam's links to its store page; Epic's and GOG's say store and ID (there's
    /// no page Nightforge knows by ID – a Steam link with app ID 0 led nowhere).
    static func storeReference(_ game: Game) -> String {
        switch game.provider {
        case .steam: return "[\(game.appID)](https://store.steampowered.com/app/\(game.appID))"
        case .epic, .gog: return "\(game.provider.label) \(game.gameID.id)"
        }
    }

    static func url(game: Game, insight: GameInsight?, profile: GameProfile? = nil, tried: [String] = []) -> URL? {
        // English in the report, whatever the app's language: it's read on GitHub.
        let options = GameOptionsStore.load(game.gameID).resolved(refreshRate: GameDisplay.screen?.maximumFramesPerSecond ?? 60,
                                                                  profile: profile)
        var graphics = "\(options.preset.rawValue) · " + options.graphics.label
        let attempts = LaunchHealth.ladder(insight?.attempts ?? [], preset: options.preset, profile: profile)
        if options.graphics == .automatic, !attempts.isEmpty {
            let (index, confirmed) = LaunchHealth.current(game.gameID, attempts)
            graphics += " → " + attempts[index].label + (confirmed ? "" : " (not confirmed yet)")
        }
        var detected = insight?.analysis.summary ?? "–"
        if let analysis = insight?.analysis {
            detected += analysis.antiCheat.map { " · " + $0 }.joined()
            if let launcher = analysis.launcher { detected += " · " + launcher }
            if analysis.usesWebView2 { detected += " · WebView2" }
        }
        var lines = [
            "**What happens:** <!-- e.g. black window, crash after the logo, low FPS, no sound -->",
            "",
            "",
            "| | |",
            "|---|---|",
            "| Game | \(game.name) (\(storeReference(game))) |",
            "| Nightforge | \(Updater.currentVersion) |",
            "| Mac | \(chip) · macOS \(osVersion) |",
            "| Detected | \(detected) |",
            "| Graphics | \(graphics) |",
            "| Frame limit / MetalFX | \(options.frameLimit.map(String.init) ?? "automatic") / \(options.upscaling.rawValue) |",
        ]
        if !tried.isEmpty { lines.append("| Tried, each ended right away | \(tried.joined(separator: " → ")) |") }
        if !options.extraArgs.isEmpty { lines.append("| Launch options | `\(GameLog.redacted(options.extraArgs))` |") }
        let learned = LearnedFixes.winetricks(game.gameID)
        if !learned.isEmpty { lines.append("| Installed by itself | \(learned.joined(separator: ", ")) |") }

        var errors = GameLog.errors(since: LearnedFixes.lastLaunchMark(game.gameID) ?? GameLog.mark())
        // GitHub cuts off long links; the newest errors matter most.
        while !errors.isEmpty, errors.joined(separator: "\n").count > 3500 { errors.removeFirst() }
        if !errors.isEmpty {
            lines += ["", "<details><summary>Errors from the last start</summary>", "", "```"] + errors + ["```", "</details>"]
        }

        // A GOG download that stopped: how gogdl ended it.
        if game.provider == .gog, let text = try? String(contentsOf: GOGDL.failedLog(for: game.gameID.id), encoding: .utf8) {
            let failure = GOGDL.failureLines(inLog: text)
            if !failure.isEmpty {
                lines += ["", "<details><summary>Its last download stopped</summary>", "", "```"] + failure + ["```", "</details>"]
            }
        }

        var components = URLComponents(string: "https://github.com/LordHayne/Nightforge/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "\(game.name): doesn't run properly"),
            URLQueryItem(name: "body", value: lines.joined(separator: "\n")),
        ]
        return components?.url
    }

    private static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        let name = String(cString: bytes)
        return name.isEmpty ? "Mac" : name
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}
