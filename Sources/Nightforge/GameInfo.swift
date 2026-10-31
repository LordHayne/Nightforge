import Foundation
import NaturalLanguage

/// How a game is played, as its store says.
enum PlayMode: String, Codable, CaseIterable, Hashable {
    case single, onlineCoop, localCoop, splitScreen, versus
    /// A store that only says "co-op" or "multiplayer" (GOG), without online or on one Mac.
    case coop, multi

    var label: String {
        switch self {
        case .single: return L10n.t("Single-player")
        case .onlineCoop: return L10n.t("Online co-op")
        case .localCoop: return L10n.t("Local co-op")
        case .splitScreen: return L10n.t("Split screen")
        case .versus: return L10n.t("Versus")
        case .coop: return L10n.t("Co-op")
        case .multi: return L10n.t("Multiplayer")
        }
    }

    var symbol: String {
        switch self {
        case .single: return "person.fill"
        case .onlineCoop: return "globe"
        case .localCoop: return "sofa.fill"
        case .splitScreen: return "rectangle.split.2x1.fill"
        case .versus: return "flag.2.crossed.fill"
        case .coop: return "person.2.fill"
        case .multi: return "person.3.fill"
        }
    }

    /// Two people on one Mac: the library's "Two on one Mac" filter.
    static let couch: Set<PlayMode> = [.localCoop, .splitScreen]

    /// What a game's page lists: the general "co-op" and "multiplayer" only when nothing more exact says it.
    static func shown(_ modes: Set<PlayMode>) -> [PlayMode] {
        allCases.filter { mode in
            guard modes.contains(mode) else { return false }
            switch mode {
            case .coop: return modes.isDisjoint(with: [.onlineCoop, .localCoop])
            case .multi: return modes.isDisjoint(with: [.onlineCoop, .localCoop, .splitScreen, .versus, .coop])
            default: return true
            }
        }
    }

    /// Steam's player categories (store category IDs).
    static func steam(_ categories: Set<Int>) -> Set<PlayMode> {
        var modes = Set<PlayMode>()
        if categories.contains(2) { modes.insert(.single) }
        if categories.contains(38) { modes.insert(.onlineCoop) }
        if categories.contains(39) { modes.insert(.localCoop) }
        if !categories.isDisjoint(with: [24, 37, 39]) { modes.insert(.splitScreen) }
        if !categories.isDisjoint(with: [36, 37, 47, 49]) { modes.insert(.versus) }
        if categories.contains(9) { modes.insert(.coop) }
        if categories.contains(1) { modes.insert(.multi) }
        return modes
    }
}

extension ControllerSupport: Codable {
    /// Steam's controller categories: 28 full support, 18 partial; neither, made for mouse and keyboard.
    static func steam(_ categories: Set<Int>) -> ControllerSupport {
        categories.contains(28) ? .full : categories.contains(18) ? .partial : .none
    }
}

/// Text and speech in the Mac's language.
struct LanguageSupport: Codable, Hashable {
    var text: Bool
    var audio: Bool
}

/// Who rated the game for which age: "USK 12", "PEGI 16".
struct AgeRating: Codable, Hashable {
    let system: String
    let age: Int
}

struct Screenshot: Codable, Hashable {
    let thumbnail: URL
    let full: URL
}

/// What a game is, for its page and the library's filters: from its store, or from the same game on
/// Steam for Epic and GOG, whose own data says little (GameInfoStore).
struct GameInfo: Codable, Hashable {
    /// A few plain sentences, in the language asked for – or English, where a store has no other.
    var summary: String? {
        didSet { summaryLanguage = summary.flatMap(Self.language(of:)) }
    }
    /// What `summary` is written in ("de", "en"), so a German one from the other store can stand in.
    private(set) var summaryLanguage: String?
    /// The language it was asked in ("german", "english"): another one is asked again.
    var language: String
    var genres: [String] = []
    var developers: [String] = []
    var publishers: [String] = []
    var released: Date?
    var modes: Set<PlayMode> = []
    /// nil: the store doesn't say.
    var controller: ControllerSupport?
    /// German text and speech on a German Mac; nil when the store doesn't say or the Mac is English.
    var macLanguage: LanguageSupport?
    var age: AgeRating?
    var screenshots: [Screenshot] = []
    /// Steam's art for it, at the addresses with a hash that newer games only have.
    var cover: URL?
    var hero: URL?
    var wideCover: URL?
    /// Where it came from: "steam.728880" for Overcooked! 2 from Epic.
    var source: String
    var asked: Date
    /// What Nightforge read from the answer then (`GameInfo.format`): an older one is asked again.
    var format: Int? = GameInfo.format

    /// 2: PEGI ratings too; 3: GOG's description without its edition notes, the summary's language (31.10.2026).
    static let format = 3

    /// The language a text is written in, as macOS recognizes it ("de", "en").
    static func language(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    /// The Mac's language as `summaryLanguage` writes it.
    static func code(_ language: String) -> String { language == "german" ? "de" : "en" }

    /// One game's info from two stores: the same game on Steam (`self`) and its own store (`own`).
    /// Steam's facts stay; what Steam doesn't have, or has only in another language than the
    /// Mac's, comes from the own store – GOG's German description, its screenshots where Steam
    /// shows only ones for adults.
    func filled(from own: GameInfo?) -> GameInfo {
        guard let own else { return self }
        var info = self
        let wanted = Self.code(language)
        if summary == nil || (summaryLanguage != wanted && own.summaryLanguage == wanted && own.summary != nil) {
            info.summary = own.summary ?? summary
        }
        if screenshots.isEmpty { info.screenshots = own.screenshots }
        if genres.isEmpty { info.genres = own.genres }
        if developers.isEmpty { info.developers = own.developers }
        if publishers.isEmpty { info.publishers = own.publishers }
        if modes.isEmpty { info.modes = own.modes }
        info.released = released ?? own.released
        info.controller = controller ?? own.controller
        info.macLanguage = macLanguage ?? own.macLanguage
        info.age = age ?? own.age
        return info
    }

    /// Up to this many screenshots are kept.
    static let maxScreenshots = 12

    // MARK: - Steam's store-browse API

    /// `IStoreBrowseService/GetItems` with assets, basic info, tags, release, ratings, screenshots and
    /// supported languages: one entry per app it knows, by app ID.
    static func steam(fromItems json: Data, language: String, now: Date = Date()) -> [Int: GameInfo] {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let items = (object["response"] as? [String: Any])?["store_items"] as? [[String: Any]] else { return [:] }
        var found: [Int: GameInfo] = [:]
        for item in items {
            guard let appID = item["appid"] as? Int, item["success"] as? Int ?? 1 == 1, item["name"] != nil else { continue }
            var info = GameInfo(language: language, source: GameID.steam(appID).key, asked: now)
            let basic = item["basic_info"] as? [String: Any] ?? [:]
            info.summary = (basic["short_description"] as? String).map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 }
            info.developers = names(basic["developers"])
            info.publishers = names(basic["publishers"])
            let release = item["release"] as? [String: Any] ?? [:]
            if let seconds = (release["steam_release_date"] ?? release["original_release_date"]) as? Int, seconds > 0 {
                info.released = Date(timeIntervalSince1970: TimeInterval(seconds))
            }
            let tags = (item["tagids"] as? [Int]) ?? []
            info.genres = Array(orderedUnique(tags.compactMap(StoreFacts.tagName)).prefix(4))
            if let categories = item["categories"] as? [String: Any] {
                let players = Set(categories["supported_player_categoryids"] as? [Int] ?? [])
                info.modes = PlayMode.steam(players)
                info.controller = .steam(Set(categories["controller_categoryids"] as? [Int] ?? []))
            }
            info.macLanguage = steamLanguage(item["supported_languages"], language: language)
            // The rating for the country asked for: the USK in Germany (agency 4), PEGI in most of Europe
            // (2). ESRB's letters (1) and Steam's own rating (17) aren't shown.
            if let rating = item["game_rating"] as? [String: Any], let age = (rating["rating"] as? String).flatMap({ Int($0) }),
               let system = [4: "USK", 2: "PEGI"][rating["agency"] as? Int ?? 0] {
                info.age = AgeRating(system: system, age: age)
            }
            let screenshots = (item["screenshots"] as? [String: Any])?["all_ages_screenshots"] as? [[String: Any]] ?? []
            info.screenshots = screenshots.prefix(maxScreenshots).compactMap { shot in
                guard let file = shot["filename"] as? String else { return nil }
                let base = "https://shared.akamai.steamstatic.com/store_item_assets/"
                let thumbnail = file.replacingOccurrences(of: ".jpg", with: ".600x338.jpg")
                guard let small = URL(string: base + thumbnail), let big = URL(string: base + file.replacingOccurrences(of: ".jpg", with: ".1920x1080.jpg"))
                else { return nil }
                return Screenshot(thumbnail: small, full: big)
            }
            if let assets = item["assets"] as? [String: Any], let format = assets["asset_url_format"] as? String {
                func asset(_ names: String...) -> URL? {
                    guard let file = names.lazy.compactMap({ assets[$0] as? String }).first else { return nil }
                    return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/"
                               + format.replacingOccurrences(of: "${FILENAME}", with: file))
                }
                info.cover = asset("library_capsule_2x", "library_capsule")
                info.hero = asset("library_hero_2x", "library_hero")
                info.wideCover = asset("main_capsule_2x", "main_capsule", "header_2x", "header")
            }
            found[appID] = info
        }
        return found
    }

    /// Steam's language numbers (ELanguage): 0 English, 1 German.
    private static func steamLanguage(_ value: Any?, language: String) -> LanguageSupport? {
        guard language == "german", let languages = value as? [[String: Any]] else { return nil }
        guard let german = languages.first(where: { $0["elanguage"] as? Int == 1 }) else {
            return languages.isEmpty ? nil : LanguageSupport(text: false, audio: false)
        }
        return LanguageSupport(text: german["supported"] as? Bool ?? true, audio: german["full_audio"] as? Bool ?? false)
    }

    // MARK: - GOG

    /// `api.gog.com/v2/games/<id>?locale=de-DE`: GOG's own page of the game.
    static func gog(fromJSON json: Data, id: String, language: String, now: Date = Date()) -> GameInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let embedded = object["_embedded"] as? [String: Any] else { return nil }
        var info = GameInfo(language: language, source: GameID.gog(id).key, asked: now)
        info.summary = (object["overview"] as? String ?? object["description"] as? String).map { summary(HTMLText.plain(gogDescription($0))) }
        info.developers = names(embedded["developers"])
        info.publishers = names(embedded["publisher"].map { [$0] })
        if let date = (embedded["product"] as? [String: Any])?["globalReleaseDate"] as? String {
            info.released = ISO8601DateFormatter().date(from: date)
        }
        info.genres = Array(names(embedded["tags"]).prefix(4))
        let features = Set((embedded["features"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        if features.contains("single") { info.modes.insert(.single) }
        if features.contains("coop") { info.modes.insert(.coop) }
        if features.contains("multi") { info.modes.insert(.multi) }
        // GOG says "controller support" or nothing – nothing isn't "none".
        info.controller = features.contains("controller_support") ? .full : nil
        if language == "german" {
            let german = (embedded["localizations"] as? [[String: Any]] ?? []).compactMap { entry -> String? in
                let inner = entry["_embedded"] as? [String: Any]
                guard (inner?["language"] as? [String: Any])?["code"] as? String == "de" else { return nil }
                return (inner?["localizationScope"] as? [String: Any])?["type"] as? String
            }
            info.macLanguage = LanguageSupport(text: german.contains("text"), audio: german.contains("audio"))
        }
        if let pegi = (embedded["pegiRating"] as? [String: Any])?["ageRating"] as? Int {
            info.age = AgeRating(system: "PEGI", age: pegi)
        }
        info.screenshots = (embedded["screenshots"] as? [[String: Any]] ?? []).prefix(maxScreenshots).compactMap { shot in
            guard let template = ((shot["_links"] as? [String: Any])?["self"] as? [String: Any])?["href"] as? String,
                  let small = URL(string: template.replacingOccurrences(of: "{formatter}", with: "product_card_screenshot_748")),
                  let big = URL(string: template.replacingOccurrences(of: "{formatter}", with: "1600")),
                  small.scheme == "https" else { return nil }
            return Screenshot(thumbnail: small, full: big)
        }
        return info
    }

    /// GOG's overview without what isn't the game's description: the edition's notes in a "module"
    /// box ("Mafia II Complete enthält Mafia II und die folgenden DLCs …") and the feature lists.
    static func gogDescription(_ html: String) -> String {
        html.replacingOccurrences(of: #"<p[^>]*class="[^"]*module[^"]*"[^>]*>[\s\S]*?</p>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<(ul|ol)[^>]*>[\s\S]*?</\1>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<h[1-6][^>]*>[\s\S]*?</h[1-6]>"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    // MARK: - Epic (legendary's catalog data)

    /// legendary's `metadata/<AppName>.json`: the developer, and a description where Epic has a real
    /// one (most only repeat the title), in English.
    static func epic(fromMetadata json: Data, appName: String, language: String, now: Date = Date()) -> GameInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let metadata = object["metadata"] as? [String: Any] else { return nil }
        var info = GameInfo(language: language, source: GameID.epic(appName).key, asked: now)
        let title = (metadata["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let text = metadata["description"] as? String {
            let plain = HTMLText.plain(text)
            if plain.count > 40, plain.caseInsensitiveCompare(title) != .orderedSame { info.summary = summary(plain) }
        }
        if let developer = metadata["developer"] as? String, !developer.isEmpty { info.developers = [developer] }
        return info
    }

    // MARK: - The same game on Steam

    /// GOG's GamesDB (`gamesdb.gog.com/platforms/<epic|gog>/external_releases/<id>`): the game's
    /// releases on every platform, among them its Steam app ID.
    static func steamTwin(fromGamesDB json: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        return steamTwin(gamesDBGame: object["game"])
    }

    static func steamTwin(gamesDBGame value: Any?) -> Int? {
        let releases = (value as? [String: Any])?["releases"] as? [[String: Any]] ?? []
        return releases.lazy.compactMap { release -> Int? in
            guard release["platform_id"] as? String == "steam" else { return nil }
            let id = (release["external_id"] as? String) ?? (release["external_id"] as? NSNumber)?.stringValue
            return id.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        }.first
    }

    // MARK: - Helpers

    private static func names(_ value: Any?) -> [String] {
        orderedUnique((value as? [[String: Any]] ?? []).compactMap {
            ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
    }

    private static func orderedUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// A long description cut to its first paragraph, and that to whole sentences within about 320 characters.
    static func summary(_ text: String) -> String {
        let first = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        guard first.count > 320 else { return first }
        var kept = ""
        first.enumerateSubstrings(in: first.startIndex..., options: .bySentences) { sentence, _, _, stop in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty else { return }
            if kept.count + sentence.count + 1 > 320 { stop = true; return }
            kept += (kept.isEmpty ? "" : " ") + sentence
        }
        return kept.isEmpty ? String(first.prefix(317)) + "…" : kept
    }
}

/// Store texts come as HTML or with HTML's entities ("Rock &amp; Roll"): plain text for the views.
enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let named = ["&amp;": "&", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                     "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&reg;": "®", "&trade;": "™", "&copy;": "©"]
        for (entity, character) in named { text = text.replacingOccurrences(of: entity, with: character) }
        // Numbered ones: &#8217; and &#x2019;.
        while let range = text.range(of: "&#(x[0-9a-fA-F]+|[0-9]+);", options: .regularExpression) {
            let code = text[range].dropFirst(2).dropLast()
            let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            text.replaceSubrange(range, with: value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        return text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
