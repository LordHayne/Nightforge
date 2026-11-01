import Foundation

/// Searches the Steam store, without login or API key. Two public endpoints together: the store's
/// own search with the "games only" filter decides which hits are games (no DLC, soundtracks or
/// tools), and the store search API adds price, platforms and Metacritic score where it has them.
/// Games the filter doesn't list (Black Myth: Wukong Benchmark Tool) come from the search API once
/// appdetails says they're games. Both are undocumented; if either fails, the library search simply
/// shows no store hits.
actor StoreSearch {
    static let shared = StoreSearch()

    struct Hit: Hashable {
        let appID: Int
        let name: String
        var price: String?
        var macNative: Bool?
        var metascore: Int?
        var controller: ControllerSupport?
        /// What appdetails calls it: "game", "dlc", "music", "demo" …; nil from the searches.
        var type: String?
        /// Costs nothing (appdetails' is_free): Steam adds its licence when asked to install it.
        var free = false
    }

    private var results: [String: [Hit]] = [:]
    private var details: [Int: Hit] = [:]

    private static let maxHits = 12
    /// appdetails asked per search at most, about hits the "games only" search left out.
    private static let maxChecks = 3

    func search(_ term: String) async -> [Hit] {
        let key = term.lowercased()
        if let cached = results[key] { return cached }

        async let gamesOnly = Self.gameHits(await Self.json(Self.url("search/results/", term: term, ["category1": "998", "json": "1"])))  // 998: games
        async let withDetails = Self.detailedHits(await Self.json(Self.url("api/storesearch/", term: term)))
        let (found, detailedFound) = await (gamesOnly, withDetails)
        guard let games = found else { return [] }  // offline or changed: no store hits, nothing breaks
        let detailed = detailedFound ?? []

        let checked = await withTaskGroup(of: Hit?.self) { group in
            for hit in Self.unlisted(term, games: games, detailed: detailed) {
                group.addTask { await self.details(for: hit.appID) }
            }
            var found: [Int: Hit] = [:]
            for await hit in group { if let hit { found[hit.appID] = hit } }
            return found
        }
        let hits = Self.merged(term, games: games, detailed: detailed, checked: checked)
        results[key] = hits
        return hits
    }

    /// Price, platforms, score and type for one game, for hits the search API didn't cover.
    func details(for appID: Int) async -> Hit? {
        if let cached = details[appID] { return cached }
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [
            URLQueryItem(name: "appids", value: String(appID)),
            URLQueryItem(name: "filters", value: "basic,price_overview,platforms,metacritic,release_date"),
        ] + Self.regionItems
        guard let hit = Self.detailsHit(await Self.json(components.url), appID: appID) else { return nil }
        details[appID] = hit
        return hit
    }

    // MARK: - Choosing the hits

    /// The search API's hits that the "games only" search left out but whose name holds the whole
    /// search: appdetails says whether they're games, a request each. Not when enough listed games
    /// match as well, as they'd come after those and miss the list anyway.
    static func unlisted(_ term: String, games: [Hit], detailed: [Hit]) -> [Hit] {
        guard games.filter({ Search.rank(name: $0.name, query: term) == 0 }).count < maxHits else { return [] }
        let listed = Set(games.map(\.appID))
        return Array(detailed.filter { !listed.contains($0.appID) && Search.rank(name: $0.name, query: term) != nil }
            .prefix(maxChecks))
    }

    /// What the library shows for `term`: the "games only" hits with what the search API knows of
    /// them, then the games it left out that appdetails confirmed (`checked`). Hits that share no
    /// word with the search go ("Automat" for "Black Myth: Wukong Benchmark Tool") – unless none
    /// does, which leaves a typo the store's own guesses. The rest in the library's order: every
    /// word starts one of the name's, then initials, then words inside it, then some words; the
    /// store's order within each.
    static func merged(_ term: String, games: [Hit], detailed: [Hit], checked: [Int: Hit]) -> [Hit] {
        let known = Dictionary(detailed.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = Set(games.map(\.appID))
        let confirmed = detailed.filter { !listed.contains($0.appID) }.compactMap { checked[$0.appID] }.filter { $0.type == "game" }
        let found = (games.map { known[$0.appID] ?? $0 } + confirmed).map { ($0, fit($0.name, term)) }
        let fitting = found.contains { $0.1 < unrelated } ? found.filter { $0.1 < unrelated } : found
        return fitting.enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .prefix(maxHits).map(\.element.0)
    }

    /// No word of the search starts one of the name's.
    private static let unrelated = 4

    /// `Search.rank` (0–2), 3 for a name that has some of the search's words, else `unrelated`.
    private static func fit(_ name: String, _ term: String) -> Int {
        if let rank = Search.rank(name: name, query: term) { return rank }
        let words = Search.words(name)
        return Search.words(term).contains { term in words.contains { $0.hasPrefix(term) } } ? 3 : unrelated
    }

    // MARK: - Reading the answers

    /// The "games only" search: names and app IDs, in the store's relevance order.
    static func gameHits(_ json: Any?) -> [Hit]? {
        guard let items = (json as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
        // Only apps (bundles and packages have no app ID); the ID sits in the image URL.
        return items.compactMap { item in
            guard let name = item["name"] as? String, let logo = item["logo"] as? String,
                  let range = logo.range(of: #"/apps/(\d+)/"#, options: .regularExpression)
            else { return nil }
            let digits = logo[range].dropFirst("/apps/".count).dropLast()
            // The store writes names with HTML's entities ("Optimierungs- &amp; Infrastruktur").
            return Int(digits).map { Hit(appID: $0, name: HTMLText.plain(name)) }
        }
    }

    /// The search API: up to ten hits of any type, with price, platforms and score.
    static func detailedHits(_ json: Any?) -> [Hit]? {
        guard let items = (json as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            var hit = Hit(appID: id, name: HTMLText.plain(name))
            if let price = item["price"] as? [String: Any], let cents = price["final"] as? Int,
               let currency = price["currency"] as? String {
                hit.price = (Double(cents) / 100).formatted(.currency(code: currency).locale(L10n.locale))
            }
            hit.macNative = (item["platforms"] as? [String: Any])?["mac"] as? Bool
            hit.metascore = (item["metascore"] as? String).flatMap { Int($0) }
            return hit
        }
    }

    /// appdetails for `appID`.
    static func detailsHit(_ json: Any?, appID: Int) -> Hit? {
        guard let entry = (json as? [String: Any])?[String(appID)] as? [String: Any],
              entry["success"] as? Bool == true,
              let data = entry["data"] as? [String: Any],
              let name = data["name"] as? String
        else { return nil }

        var hit = Hit(appID: appID, name: HTMLText.plain(name))
        hit.type = data["type"] as? String
        if data["is_free"] as? Bool == true {
            hit.price = L10n.t("Free")
            hit.free = true
        } else if let price = data["price_overview"] as? [String: Any] {
            hit.price = price["final_formatted"] as? String
        } else if (data["release_date"] as? [String: Any])?["coming_soon"] as? Bool == true {
            hit.price = L10n.t("Coming soon")
        }
        hit.macNative = (data["platforms"] as? [String: Any])?["mac"] as? Bool
        hit.metascore = (data["metacritic"] as? [String: Any])?["score"] as? Int
        hit.controller = (data["controller_support"] as? String).flatMap { ControllerSupport(rawValue: $0.lowercased()) } ?? ControllerSupport.none
        return hit
    }

    // MARK: - Requests

    private static func url(_ path: String, term: String, _ extra: KeyValuePairs<String, String> = [:]) -> URL? {
        var components = URLComponents(string: "https://store.steampowered.com/" + path)!
        components.queryItems = [URLQueryItem(name: "term", value: term)]
            + extra.map { URLQueryItem(name: $0.key, value: $0.value) } + regionItems
        return components.url
    }

    /// Prices for the Mac's region, texts in the app's language.
    private static var regionItems: [URLQueryItem] {
        [
            URLQueryItem(name: "cc", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "l", value: AppLanguage.current.resolved == .german ? "german" : "english"),
        ]
    }

    private static func json(_ url: URL?) async -> Any? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
