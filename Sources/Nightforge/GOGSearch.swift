import Foundation

/// Searches GOG's catalog, the public one its own store pages use: no sign-in, and Nightforge says
/// who it is. The numeric ID is the one gogdl goes by, so a game the player owns is recognised
/// exactly – except that GOG sells many games under a "pack" of their own (Cyberpunk 2077, The
/// Witcher 3), whose ID is not the game's: those go by title (`OwnedGames`). If the catalog can't
/// be reached or changes, GOG simply adds no hits.
actor GOGSearch {
    static let shared = GOGSearch()

    private var results: [String: [StoreHit]] = [:]

    private static let maxHits = 12
    /// Asked for more than are shown: many go, for not fitting the search.
    private static let asked = 24

    func search(_ term: String) async -> [StoreHit] {
        let key = term.lowercased()
        if let cached = results[key] { return cached }
        guard let hits = Self.hits(await Self.json(Self.url(term)), term: term) else { return [] }
        results[key] = hits
        return hits
    }

    // MARK: - Reading the answer

    /// The products that are games and fit the search, best first; nil when it's no answer. GOG's
    /// search also guesses ("Creature Kitchen" for "witcher"): unlike Steam's, those aren't shown,
    /// as a search of the player's is mostly for a game GOG doesn't have.
    static func hits(_ json: Any?, term: String) -> [StoreHit]? {
        guard let products = (json as? [String: Any])?["products"] as? [[String: Any]] else { return nil }
        let kept = products.compactMap { product -> (hit: StoreHit, pack: Bool)? in
            guard let hit = hit(product) else { return nil }
            switch product["productType"] as? String {
            case "game": return (hit, false)
            case "pack": return (hit, true)
            default: return nil  // add-ons, soundtracks, extras
            }
        }
        // Editions and collections of a game that's listed too, and anything that calls itself a bundle.
        let games = kept.filter { !$0.pack }.map { DuplicateGames.titleKey($0.hit.name) }
        let wanted = kept.filter { item in
            guard item.pack else { return true }
            let key = DuplicateGames.titleKey(item.hit.name)
            return !key.hasSuffix(" bundle") && !games.contains { key == $0 || key.hasPrefix($0 + " ") }
        }
        let fitting = wanted.map { ($0.hit, StoreSearch.fit($0.hit.name, term)) }.filter { $0.1 < StoreSearch.unrelated }
        return fitting.enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .prefix(maxHits).map(\.element.0)
    }

    private static func hit(_ product: [String: Any]) -> StoreHit? {
        guard let id = product["id"] as? String, GOGRelease.isProductID(id),
              let name = product["title"] as? String, !name.isEmpty,
              let page = page(product["storeLink"] as? String)
        else { return nil }
        var hit = StoreHit(gameID: .gog(id), name: name, page: page)
        hit.price = price(product["price"] as? [String: Any], state: product["productState"] as? String)
        hit.macNative = (product["operatingSystems"] as? [String])?.contains("osx") ?? false
        hit.art = StoreArt(cover: image(product["coverVertical"] as? String), hero: image(product["coverHorizontal"] as? String), logo: nil)
        return hit
    }

    /// As GOG writes it in the language asked for; nothing yet for a game that isn't out.
    private static func price(_ price: [String: Any]?, state: String?) -> String? {
        if let amount = (price?["finalMoney"] as? [String: Any])?["amount"] as? String, Double(amount) == 0 { return L10n.t("Free") }
        return price?["final"] as? String ?? (state == "coming-soon" ? L10n.t("Coming soon") : nil)
    }

    /// The answer decides what opens in the player's browser: only GOG's own pages.
    private static func page(_ link: String?) -> URL? {
        guard let url = link.flatMap(URL.init(string:)), url.scheme == "https",
              url.host == "www.gog.com" || url.host == "gog.com" else { return nil }
        return url
    }

    private static func image(_ link: String?) -> URL? {
        guard let url = link.flatMap(URL.init(string:)), url.scheme == "https" else { return nil }
        return url
    }

    // MARK: - Requests

    static func url(_ term: String, region: String = Locale.current.region?.identifier ?? "US",
                    german: Bool = AppLanguage.current.resolved == .german) -> URL? {
        var components = URLComponents(string: "https://catalog.gog.com/v1/catalog")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "like:" + term),
            URLQueryItem(name: "productType", value: "in:game,pack"),
            URLQueryItem(name: "countryCode", value: region),
            URLQueryItem(name: "locale", value: german ? "de-DE" : "en-US"),
            URLQueryItem(name: "currencyCode", value: "EUR"),
            URLQueryItem(name: "limit", value: String(asked)),
            URLQueryItem(name: "page", value: "1"),
        ]
        return StoreHits.withPlusEscaped(components).url
    }

    /// Who's asking, so GOG can tell: no browser's or launcher's name.
    static var userAgent: String { "Nightforge/\(Updater.currentVersion) (+https://github.com/LordHayne/Nightforge)" }

    private static func json(_ url: URL?) async -> Any? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
