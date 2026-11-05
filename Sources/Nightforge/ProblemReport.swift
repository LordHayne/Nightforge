import AppKit
import Foundation

/// What Nightforge knows about an installed game before starting it.
struct GameInsight: Equatable {
    let analysis: GameAnalysis
    /// The ways "Automatic" tries, in order (LaunchHealth).
    let attempts: [LaunchAttempt]
    /// The layer `attempts` put first because other sources report it working (`LaunchHealth.hinted`).
    var hint: GraphicsLayer?
}

/// A game that ended right after starting with every way Nightforge knows.
struct FailedLaunch: Identifiable {
    let game: Game
    let tried: [String]
    var id: String { game.id }
}

/// "Doesn't run?": a GitHub issue filled in with what Nightforge knows about the game, opened in
/// the player's browser. The link carries only fixed facts (game, versions, the Mac, what was
/// detected and tried) – GitHub and the browser's history get those as the page opens, it's public
/// once the player submits it. Lines that can hold something personal the redaction misses (wine.log
/// errors, gogdl's, launch options) never go into the link: they're put on the clipboard, for the
/// player to paste if they want (security audit M3, 3.11.2026).
@MainActor
enum ProblemReport {
    /// `tried`: the ways a start that failed every time went through, in order.
    static func open(game: Game, insight: GameInsight?, profile: GameProfile? = nil, tried: [String] = []) {
        let report = report(game: game, insight: insight, profile: profile, tried: tried)
        if let clipboard = report.clipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboard, forType: .string)
        }
        if let url = report.url { NSWorkspace.shared.open(url) }
        if report.clipboard != nil {
            Toasts.shared.show(L10n.t("The error lines from the last start are on your clipboard – paste them into the report if you want to share them."))
        }
    }

    /// Which game it is: Steam's links to its store page; Epic's and GOG's say store and ID (there's
    /// no page Nightforge knows by ID – a Steam link with app ID 0 led nowhere).
    static func storeReference(_ game: Game) -> String {
        switch game.provider {
        case .steam: return "[\(game.appID)](https://store.steampowered.com/app/\(game.appID))"
        case .epic, .gog: return "\(game.provider.label) \(game.gameID.id)"
        }
    }

    static func report(game: Game, insight: GameInsight?, profile: GameProfile? = nil, tried: [String] = []) -> ProblemReportText {
        // English in the report, whatever the app's language: it's read on GitHub.
        let options = GameOptionsStore.load(game.gameID).resolved(refreshRate: GameDisplay.screen?.maximumFramesPerSecond ?? 60,
                                                                  profile: profile)
        var graphics = "\(options.preset.rawValue) · " + options.graphics.label
        let attempts = LaunchHealth.ladder(insight?.attempts ?? [], preset: options.preset, profile: profile, hint: insight?.hint)
        if options.graphics == .automatic, !attempts.isEmpty {
            let (index, confirmed) = LaunchHealth.current(game.gameID, attempts)
            graphics += " → " + attempts[index].label + (confirmed ? "" : " (not confirmed yet)")
            if let hint = insight?.hint { graphics += " · \(hint.shortLabel) first from AppleGamingWiki" }
        }
        var detected = insight?.analysis.summary ?? "–"
        if let analysis = insight?.analysis {
            detected += analysis.antiCheat.map { " · " + $0 }.joined()
            if let launcher = analysis.launcher { detected += " · " + launcher }
            if analysis.usesWebView2 { detected += " · WebView2" }
        }
        var facts = [
            ("Game", "\(game.name) (\(storeReference(game)))"),
            ("Nightforge", Updater.currentVersion),
            ("Mac", "\(chip) · macOS \(osVersion)"),
            ("Detected", detected),
            ("Graphics", graphics),
            ("Frame limit / MetalFX", "\(options.frameLimit.map(String.init) ?? "automatic") / \(options.upscaling.rawValue)"),
        ]
        if !tried.isEmpty { facts.append(("Tried, each ended right away", tried.joined(separator: " → "))) }
        let learned = LearnedFixes.winetricks(game.gameID)
        if !learned.isEmpty { facts.append(("Installed by itself", learned.joined(separator: ", "))) }

        let errors = GameLog.errors(since: LearnedFixes.lastLaunchMark(game.gameID) ?? GameLog.mark())
        // A GOG download that stopped: how gogdl ended it.
        var downloadFailure: [String] = []
        if game.provider == .gog, let text = try? String(contentsOf: GOGDL.failedLog(for: game.gameID.id), encoding: .utf8) {
            downloadFailure = GOGDL.failureLines(inLog: text)
        }
        return ProblemReportText(gameName: game.name, facts: facts, errors: errors, downloadFailure: downloadFailure,
                                 launchOptions: options.extraArgs)
    }

    static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        let name = String(cString: bytes)
        return name.isEmpty ? "Mac" : name
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}

/// A problem report's text, apart from where it comes from: `body` for the link – fixed facts only –
/// and `clipboard` for the lines that could hold something personal, never in the link.
struct ProblemReportText: Equatable {
    let title: String
    let body: String
    /// Errors from the last start, a stopped download's, the launch options – each through
    /// GameLog.redacted; nil when there are none.
    let clipboard: String?

    /// `facts`: label and value, all of them fixed things Nightforge knows (the store's game name,
    /// versions, labels – no log line, path or option the player typed); they're redacted all the
    /// same, but keep a word like the account's name ("Thomas Was Alone"). `home` and `user`: for
    /// the redaction, a test hands in its own.
    init(gameName: String, facts: [(String, String)], errors: [String], downloadFailure: [String], launchOptions: String,
         home: String = NSHomeDirectory(), user: String = NSUserName()) {
        func clean(_ text: String) -> String { GameLog.redacted(text, home: home, user: user) }
        var extra: [String] = []
        if !errors.isEmpty {
            // An issue holds 65,536 characters; the newest errors matter most.
            var kept = errors.map(clean)
            while kept.count > 1, kept.joined(separator: "\n").count > 20_000 { kept.removeFirst() }
            extra += ["<details><summary>Errors from the last start</summary>", "", "```"] + kept + ["```", "</details>"]
        }
        if !downloadFailure.isEmpty {
            extra += (extra.isEmpty ? [] : [""]) + ["<details><summary>Its last download stopped</summary>", "", "```"]
                + downloadFailure.map(clean) + ["```", "</details>"]
        }
        if !launchOptions.isEmpty {
            extra += (extra.isEmpty ? [] : [""]) + ["Launch options: `\(clean(launchOptions))`"]
        }
        // Blank lines around it: pasted at the end of a line of text (the live test put it right after
        // the bold "From the last start:"), <details> and ``` still start a line of their own.
        clipboard = extra.isEmpty ? nil : "\n" + extra.joined(separator: "\n") + "\n"
        func fact(_ text: String) -> String { GameLog.redacted(text, home: home, user: "") }
        title = fact("\(gameName): doesn't run properly")
        var lines = [
            "**What happens:** <!-- e.g. black window, crash after the logo, low FPS, no sound -->",
            "",
            "",
            "| | |",
            "|---|---|",
        ] + facts.map { "| \($0.0) | \(fact($0.1).replacingOccurrences(of: "|", with: "\\|")) |" }
        // The heading and the hint on lines of their own, the empty last line to paste into: a click
        // below the text puts the cursor there, outside any formatting or comment.
        if clipboard != nil {
            lines += ["", "### From the last start",
                      "<!-- Nightforge put the error lines and launch options on your clipboard: "
                      + "paste them below (⌘V) if you want to share them, or leave this out. -->", "", ""]
        }
        body = lines.joined(separator: "\n")
    }

    /// The new-issue page filled in with `title` and `body` – nothing else goes into the link.
    var url: URL? {
        var components = URLComponents(string: "https://github.com/LordHayne/Nightforge/issues/new")
        components?.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return components?.url
    }
}

