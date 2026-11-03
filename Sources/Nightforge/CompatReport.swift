import Foundation

/// "Share report …" after "How did it run?": the issue form .github/ISSUE_TEMPLATE/compat-report.yml,
/// filled in with the player's answer and the way the game ran, opened in their browser. The values
/// are in the link, so GitHub and the browser's history get them as the page opens; the report is
/// public once the player submits it, under their GitHub name. That's why only fixed values go in –
/// no paths, account names, launch options or log lines – and each still passes GameLog.redacted. A nightly workflow could count the valid ones into profiles/reports.json
/// (docs/ENTWURF-BERICHTE.md).
enum CompatReport {
    static let form = "compat-report.yml"

    /// "good", "problems" or "no-start": the form's fixed words for the three answers.
    static func result(_ rating: GameRating) -> String {
        rating.didntStart == true ? "no-start" : rating.good ? "good" : "problems"
    }

    /// The store and its ID for the game: "steam" and "870780"; Epic's and GOG's IDs are their own.
    static func store(_ game: Game) -> (store: String, id: String) {
        (game.provider.rawValue, game.gameID.id)
    }

    /// The form's fields by id, as the link fills them in.
    static func fields(game: Game, rating: GameRating, preset: GraphicsPreset?, engine: EngineBuild?,
                       chip: String, macOS: String, nightforge: String, home: String = NSHomeDirectory(),
                       user: String = NSUserName()) -> [(id: String, value: String)] {
        let (store, id) = Self.store(game)
        var setup = ["Nightforge " + nightforge]
        if let preset { setup.append("preset " + preset.rawValue) }
        if let engine { setup.append(engine.parts.joined(separator: ", ")) }
        let fields: [(String, String)] = [
            ("game", game.name),
            ("store", store),
            ("store-id", id),
            ("result", result(rating)),
            ("way", rating.way ?? (game.platform == .mac ? "mac" : "unknown")),
            ("issues", rating.issues.map(\.rawValue).joined(separator: ", ")),
            ("setup", setup.joined(separator: " · ")),
            ("mac", "\(chip) · macOS \(macOS)"),
        ]
        return fields.filter { !$0.1.isEmpty }.map { ($0.0, GameLog.redacted($0.1, home: home, user: user)) }
    }

    static func url(game: Game, rating: GameRating, preset: GraphicsPreset?, engine: EngineBuild?, chip: String,
                    macOS: String, nightforge: String, home: String = NSHomeDirectory(), user: String = NSUserName()) -> URL? {
        let filled = Self.fields(game: game, rating: rating, preset: preset, engine: engine, chip: chip, macOS: macOS,
                                 nightforge: nightforge, home: home, user: user)
        var components = URLComponents(string: "https://github.com/LordHayne/Nightforge/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: form),
            URLQueryItem(name: "title", value: GameLog.redacted("\(game.name): \(result(rating))", home: home, user: user)),
        ] + filled.map { URLQueryItem(name: $0.id, value: $0.value) }
        return components?.url
    }
}
