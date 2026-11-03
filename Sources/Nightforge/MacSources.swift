import AppKit
import Foundation

/// A way to start a game that another source's reports point to (`source`: "agw" for
/// AppleGamingWiki). Others tested other versions, so a hint only orders the ways LaunchHealth tries
/// (`LaunchHealth.hinted`): Nightforge's own profiles, anti-cheat and what a game's starts on this Mac
/// showed always come first.
struct SourceHint: Equatable {
    let graphics: GraphicsLayer
    /// The DirectX version the reports ran it with ("12"), when they say one.
    var directX: String?
    var source = "agw"
}

/// What AppleGamingWiki says about one game on a Mac (profiles/agw.json, built nightly by
/// scripts/fetch-agw.py): its editors' rating for each way to run it, the note shortened, and what
/// their reports name. The file is CC BY-NC-SA 3.0, a work apart from Nightforge's GPL code: it is
/// downloaded, never bundled, and wherever it shows, the wiki is named and linked.
struct AGWEntry: Equatable {
    enum Way: String, CaseIterable {
        case native, rosetta, crossover, wine

        var label: String {
            switch self {
            case .native: return L10n.t("Mac version")
            case .rosetta: return L10n.t("Mac version (Intel)")
            case .crossover: return "CrossOver"
            case .wine: return L10n.t("Wine / Game Porting Toolkit")
            }
        }

        /// A Windows game's way: through Wine, as Nightforge runs it.
        var throughWine: Bool { self == .crossover || self == .wine }
    }

    enum Rating: String {
        case perfect, playable, runs, menu, unplayable

        var label: String {
            switch self {
            case .perfect: return L10n.t("perfect")
            case .playable: return L10n.t("playable")
            case .runs: return L10n.t("runs, with big flaws")
            case .menu: return L10n.t("only to the menu")
            case .unplayable: return L10n.t("unplayable")
            }
        }

        var good: Bool { self == .perfect || self == .playable }
    }

    struct Report: Equatable {
        let rating: Rating
        /// In English, as the wiki has it, shortened.
        var note: String?
        var versions: [String] = []
        var graphics: [GraphicsLayer] = []
        var directX: [String] = []
        var chips: [String] = []
        /// The newest report's day, "2023-10-13".
        var date: String?

        /// "CrossOver 23.5 · D3DMetal · DirectX 12 · M1 Pro · 2023": what the reports name.
        var basis: String {
            var parts = versions + graphics.map(\.shortLabel) + directX.map { "DirectX " + $0 } + chips
            if let year = date?.prefix(4) { parts.append(String(year)) }
            return parts.joined(separator: " · ")
        }
    }

    /// The page's title on the wiki.
    let page: String
    /// "wikidata" or "name": the IDs come from Wikidata by the page's title, not from the page.
    var ids: String?
    /// CodeWeavers' name for the game, from the page.
    var codeweavers: String?
    var reports: [Way: Report] = [:]
    var hint: SourceHint?

    var pageURL: URL? { MacSources.wikiPage(page) }

    /// The ways that say something, in the table's order.
    var ways: [(way: Way, report: Report)] { Way.allCases.compactMap { way in reports[way].map { (way, $0) } } }

    /// "CrossOver: perfect, Wine / Game Porting Toolkit: playable" – the Windows ways, for a badge's help.
    var wineSummary: String? {
        let parts = ways.filter(\.way.throughWine).map { "\($0.way.label): \($0.report.rating.label)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// profiles/agw.json as read: entries by key ("870780", "gog.<id>") and the other IDs leading to them.
struct AGWIndex: Equatable {
    var games: [String: AGWEntry] = [:]
    var steamAliases: [String: String] = [:]
    var gogAliases: [String: String] = [:]

    var isEmpty: Bool { games.isEmpty }

    /// By the game's Steam app ID (its own, or that of the same game on Steam), else by its GOG product ID.
    func entry(steamAppID: Int?, gogID: String?) -> AGWEntry? {
        if let steamAppID {
            let key = String(steamAppID)
            if let entry = games[key] ?? steamAliases[key].flatMap({ games[$0] }) { return entry }
        }
        if let gogID {
            return games["gog." + gogID] ?? gogAliases[gogID].flatMap { games[$0] }
        }
        return nil
    }

    func entry(for game: Game) -> AGWEntry? {
        entry(steamAppID: game.steamAppID, gogID: game.provider == .gog ? game.gameID.id : nil)
    }

    static func decode(_ data: Data) -> AGWIndex? {
        guard let document = try? JSONDecoder().decode(AGWDocument.self, from: data),
              document.formatVersion <= AGWStore.supportedFormat
        else { return nil }
        return AGWIndex(games: document.games.compactMapValues(\.entry),
                        steamAliases: document.aliases?["steam"] ?? [:], gogAliases: document.aliases?["gog"] ?? [:])
    }
}

/// The file's shape. Lenient like the profile list: an odd entry, a way or a layer this Nightforge
/// doesn't know cost only themselves.
private struct AGWDocument: Decodable {
    let formatVersion: Int
    let games: [String: Lenient]
    let aliases: [String: [String: String]]?

    struct Lenient: Decodable {
        let entry: AGWEntry?
        init(from decoder: Decoder) throws { entry = (try? RawEntry(from: decoder))?.entry }
    }

    struct RawEntry: Decodable {
        let page: String
        var ids: String?
        var codeweavers: String?
        var paths: [String: RawReport]?
        var hint: RawHint?

        var entry: AGWEntry {
            var reports: [AGWEntry.Way: AGWEntry.Report] = [:]
            for (key, raw) in paths ?? [:] {
                guard let way = AGWEntry.Way(rawValue: key), let rating = AGWEntry.Rating(rawValue: raw.rating) else { continue }
                reports[way] = AGWEntry.Report(rating: rating, note: raw.note, versions: raw.versions ?? [],
                                               graphics: (raw.graphics ?? []).compactMap(GraphicsLayer.init(rawValue:)),
                                               directX: raw.directX ?? [], chips: raw.chips ?? [], date: raw.date)
            }
            let sourceHint = self.hint.flatMap { raw in
                GraphicsLayer(rawValue: raw.graphics).map { SourceHint(graphics: $0, directX: raw.directX, source: raw.source ?? "agw") }
            }
            return AGWEntry(page: page, ids: ids, codeweavers: codeweavers, reports: reports, hint: sourceHint)
        }
    }

    struct RawReport: Decodable {
        let rating: String
        var note: String?
        var versions: [String]?
        var graphics: [String]?
        var directX: [String]?
        var chips: [String]?
        var date: String?
    }

    struct RawHint: Decodable {
        let graphics: String
        var directX: String?
        var source: String?
    }
}

/// Keeps profiles/agw.json at hand: the online copy (`NightforgeAGWURL`) once per app run, else the
/// last one fetched. There's no copy in the app – the wiki's licence keeps it apart from the app –
/// so before the first download there's simply nothing to show. Like the other online lists it counts
/// only with the maintainer's signature beside it (`Signature`), online and on disk: it orders the
/// ways a game is tried.
actor AGWStore {
    static let shared = AGWStore()
    static let supportedFormat = 1

    private let remoteURL: URL?
    private let cachedURL: URL
    private let keys: [String]
    private let load: Signature.Load
    private var index: AGWIndex?
    /// This run's fetch: callers that come while it's under way wait for it rather than going without.
    private var refreshing: Task<Void, Never>?
    /// It has ended, with the list or without (offline, an error).
    private var fetched = false
    /// A game's start has waited for it once this run (`beforeFirstStart`).
    private var waitedForStart = false

    /// `load`: how the online copy and its signature are fetched; a test hands in a slow or failing one.
    init(remoteURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "NightforgeAGWURL") as? String)
             .flatMap { $0.isEmpty ? nil : URL(string: $0) },
         cachedURL: URL = Engine.supportDir.appendingPathComponent("agw.json"),
         keys: [String] = SigningKeys.trusted,
         load: @escaping Signature.Load = { try await URLSession.shared.data(for: $0) }) {
        self.remoteURL = remoteURL
        self.cachedURL = cachedURL
        self.keys = keys
        self.load = load
    }

    /// What the copy at hand says, without waiting for the online one (like `ProfileStore.knownProfiles`).
    func current() -> AGWIndex {
        if index == nil { index = Signature.signedContents(of: cachedURL, keys: keys).flatMap(AGWIndex.decode) ?? AGWIndex() }
        return index ?? AGWIndex()
    }

    /// Fetches the online copy once per run; keeps what's there when offline or when the file is too
    /// new for this Nightforge. It only orders the ways a game is tried and shows what the wiki
    /// says – it can't change how a game is set up.
    func refresh() async {
        startFetch()
        await refreshing?.value
    }

    /// Before a game's start while there's no copy yet (the first run): this run's fetch, waited for
    /// once per run and `seconds` at most – a slow, missing or stuck network mustn't hold up a start,
    /// let alone every one. That start goes without the wiki's word; the list arrives in the
    /// background for the next.
    func beforeFirstStart(waitingAtMost seconds: TimeInterval = 4) async {
        guard !waitedForStart else { return }
        waitedForStart = true
        startFetch()
        let deadline = Date().addingTimeInterval(seconds)
        while !fetched, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
    }

    private func startFetch() {
        guard refreshing == nil else { return }
        guard let remoteURL else {
            fetched = true
            return
        }
        refreshing = Task { await self.fetch(remoteURL) }
    }

    private func fetch(_ remoteURL: URL) async {
        defer { fetched = true }
        switch await Signature.fetch(remoteURL, keys: keys, timeout: 20, load: load) {
        case .signed(let data, let signature):
            SignedLists.note(SignedLists.agw, refused: false)
            // Older than the copy kept: an earlier one put back.
            let older = SignedLists.isOlder(data, than: Signature.signedContents(of: cachedURL, keys: keys))
            SignedLists.note(SignedLists.agw, older: older)
            guard !older, let fresh = AGWIndex.decode(data), !fresh.isEmpty else { return }
            index = fresh
            try? FileManager.default.createDirectory(at: cachedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cachedURL, options: .atomic)
            try? signature.write(to: Signature.file(for: cachedURL), options: .atomic)
        case .refused:
            SignedLists.note(SignedLists.agw, refused: true)
        case .unavailable:
            return
        }
    }
}

/// Where to read more about a game on a Mac: AppleGamingWiki, CodeWeavers' compatibility center and
/// MacGamingDB. Links only – nothing is fetched from the last two.
enum MacSources {
    static let wikiLicense = URL(string: "https://creativecommons.org/licenses/by-nc-sa/3.0/")!

    static func wikiPage(_ title: String) -> URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: wikiTitle) else { return nil }
        return URL(string: "https://www.applegamingwiki.com/wiki/" + encoded)
    }

    /// The wiki's search, for a game it has no page for that Nightforge knows of.
    static func wikiSearch(_ name: String) -> URL? {
        var link = URLComponents(string: "https://www.applegamingwiki.com/w/index.php")
        link?.queryItems = [URLQueryItem(name: "search", value: name)]
        return link?.url
    }

    /// The page the wiki links for the game (`AGWEntry.codeweavers`), else CodeWeavers' search.
    static func codeWeavers(name: String, entry: AGWEntry?) -> URL? {
        if let slug = entry?.codeweavers, let encoded = slug.addingPercentEncoding(withAllowedCharacters: wikiTitle) {
            return URL(string: "https://www.codeweavers.com/compatibility/crossover/" + encoded)
        }
        var link = URLComponents(string: "https://www.codeweavers.com/compatibility")
        link?.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "search", value: "app")]
        return link?.url
    }

    /// MacGamingDB finds a game by its Steam app ID (it forwards to the game's page); without one,
    /// its front page and search field – it has no search link.
    static func macGamingDB(steamAppID: Int?) -> URL? {
        URL(string: "https://macgamingdb.app/" + (steamAppID.map { "games/\($0)" } ?? ""))
    }

    /// Letters, digits and the punctuation wiki titles keep in a path.
    private static let wikiTitle: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%/")
        return allowed
    }()
}
