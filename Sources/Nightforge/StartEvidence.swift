import Foundation

/// What happened to each start, one line per event, never rewritten: which way, on which engine, on
/// which Mac, and what the game said. It stays on this Mac. It's what a better choice can be made from
/// later, and the number that says whether the choices get better: how many games Nightforge had never
/// seen came up on their first way.
enum StartEvidence {
    enum Event: String, Codable {
        /// `ended`: the start came to an end that is neither: the player quit, closed the game's own question, or
        /// it ended before it counted as working – with `picture` when it had drawn one. Every start that was
        /// recorded gets one of worked, failed or ended, so that what's learned by sort isn't learned from half.
        case started, worked, failed, gaveUp, ended
    }

    struct Entry: Codable, Equatable {
        var at: Date
        var game: String
        var event: Event
        var way: String?
        var engine: String?
        var mac: String?
        /// The way had already proven itself when this start began: no first start.
        var known: Bool?
        /// The game's own words, without what identifies the player.
        var reason: String?
        /// With a start: the game's sort and all the start was made of, so that what one game taught can be
        /// asked for by sort later.
        var kind: GameKind?
        var recipe: StartRecipe?
        /// With a failure: what the diagnosis made of it (StartDiagnosis.line).
        var diagnosis: [String]?
        /// With an end: whether the game had drawn a picture, and how long the start had run.
        var picture: Bool?
        var seconds: Int?
        /// With a start: a profile shaped it (GameProfile.shapesStart) – what it proves is the profile's, not its sort's.
        var profiled: Bool?
        /// With a start: the state it ran on – Nightforge's version and when it was built (Updater.currentBuilt:
        /// test builds share a version), the engine's parts (EngineBuild.parts) – and what the game is called, so
        /// that a list of games that run can say what a start was seen on (scripts/laeuft-liste.py). Missing in
        /// lines from before 14.11.2026.
        var nightforge: String?
        var built: Date?
        var parts: [String]?
        var name: String?
        /// With a start: it carried Wine's debug channels, after one nothing explained (CloserLook).
        var closerLook: Bool?
    }

    /// Games Nightforge had never seen, by how their first start went (`worked`: it drew a picture,
    /// LaunchHealth.verdict).
    struct Summary: Equatable {
        var firstWay = 0
        var laterWay = 0
        var noWay = 0
        var open = 0
    }

    static var url: URL { Engine.supportDir.appendingPathComponent("start-evidence.jsonl") }

    static func note(_ event: Event, game: GameID, way: String, engine: String? = nil, known: Bool? = nil,
                     reason: String? = nil, kind: GameKind? = nil, recipe: StartRecipe? = nil, diagnosis: [String]? = nil,
                     picture: Bool? = nil, seconds: Int? = nil, profiled: Bool? = nil, closerLook: Bool? = nil,
                     name: String? = nil, parts: [String]? = nil, to file: URL = url) {
        var entry = Entry(at: Date(), game: game.key, event: event, way: way, engine: engine, known: known)
        entry.profiled = profiled == true ? true : nil
        entry.closerLook = closerLook == true ? true : nil
        entry.kind = kind
        entry.recipe = recipe
        entry.picture = picture
        entry.seconds = seconds
        entry.diagnosis = diagnosis.flatMap { $0.isEmpty ? nil : $0.map { GameLog.redacted(String($0.prefix(240))) } }
        if event == .started {
            entry.mac = "\(ProblemReport.chip) · macOS \(ProblemReport.osVersion)"
            entry.nightforge = Updater.currentVersion
            entry.built = Updater.currentBuilt
            entry.parts = parts.flatMap { $0.isEmpty ? nil : $0 }
            entry.name = name.flatMap { $0.isEmpty ? nil : $0 }
        }
        entry.reason = reason.map { GameLog.redacted(String($0.prefix(240))) }
        append(entry, to: file)
        if event == .worked || event == .gaveUp {
            let so = summary(load(from: file))
            GameLog.note("First starts so far: \(so.firstWay) on the first way, \(so.laterWay) on a later one, "
                         + "\(so.noWay) on none, \(so.open) still open")
        }
    }

    private static func append(_ entry: Entry, to file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard let line = try? encoder.encode(entry) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        try? FileHandle(fileDescriptor: descriptor, closeOnDealloc: true).write(contentsOf: line + Data([0x0A]))
    }

    static func load(from file: URL = url) -> [Entry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(whereSeparator: \.isNewline).compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    // MARK: - What a sort of game has proven

    /// What one game's starts on this Mac say: its sort, and its ways by how they went.
    struct Proof: Equatable {
        var kind: GameKind?
        var worked: Set<String> = []
        /// Reached a picture and ended before that counted as working (LaunchHealth.verdict).
        var picture: Set<String> = []
        var failed: Set<String> = []
    }

    /// Whether a start speaks for its way as such: not shaped by a profile, and started with the way's own
    /// arguments, give or take the switch past a launcher window. It Takes Two runs on D3DMetal with its profile's
    /// -dx12 (10.11.2026): that proves the profile's recipe, not D3DMetal for the next Unreal 4 game.
    static func speaksForItsWay(_ entry: Entry) -> Bool {
        guard entry.profiled != true, let way = entry.way else { return false }
        guard let recipe = entry.recipe else { return true }
        let own = Set(way.split(separator: " ").dropFirst().map(String.init)).union(ProgramText.launcherSwitches)
        return recipe.arguments.allSatisfy(own.contains)
    }

    /// Each game's proof, read from the record in order. A start on a way already proven counts as one more
    /// time it worked; a way that worked isn't made a failure by a later bad start. Starts that don't speak for
    /// their way (`speaksForItsWay`) leave no proof.
    static func proofs(_ entries: [Entry]) -> [String: Proof] {
        var proofs: [String: Proof] = [:]
        var speaks: [String: Bool] = [:]
        for entry in entries {
            guard let way = entry.way else { continue }
            var proof = proofs[entry.game] ?? Proof()
            if entry.event == .started {
                speaks[entry.game] = speaksForItsWay(entry)
                if let kind = entry.kind { proof.kind = kind }
            }
            if speaks[entry.game] ?? true {
                switch entry.event {
                case .started:
                    if entry.known == true { proof.worked.insert(way) }
                case .worked:
                    proof.worked.insert(way)
                    proof.failed.remove(way)
                case .failed:
                    if !proof.worked.contains(way) { proof.failed.insert(way) }
                case .ended:
                    if entry.picture == true { proof.picture.insert(way) }
                case .gaveUp:
                    break
                }
            }
            proofs[entry.game] = proof
        }
        return proofs
    }

    /// How much one game's proof says about another: the same sort in full (4), the same engine version and
    /// interfaces (3), the same engine generation and interfaces (2), the same engine generation (1). Nothing
    /// between games whose engine isn't known – "other" is no sort – or of different engines.
    static func kinship(_ a: GameKind, _ b: GameKind) -> Int {
        guard a.engine != "other", a.engine == b.engine, let generation = a.generation, generation == b.generation else { return 0 }
        if a.fine == b.fine { return 4 }
        if a.engineVersion == b.engineVersion, a.apis == b.apis { return 3 }
        if a.apis == b.apis { return 2 }
        return 1
    }

    /// What the proofs of games of the same sort say about a way: points to order by, and how many games stand
    /// behind it with a picture.
    struct SortScore: Equatable {
        var points = 0
        var games = 0
    }

    /// The ways' scores for a game of `kind`, from every other game's proof: a way that worked counts twice a
    /// way that only reached a picture, each times the kinship. What failed for a kin doesn't count against a
    /// way: the cause is too often not the way (It Takes Two failed on DXMT and DXVK over PhysX's update loader,
    /// 10.11.2026), and an order built on that would keep the next game from a way that suits it.
    static func sortScores(for kind: GameKind, excluding game: String, proofs: [String: Proof]) -> [String: SortScore] {
        var scores: [String: SortScore] = [:]
        for (other, proof) in proofs where other != game {
            guard let otherKind = proof.kind else { continue }
            let kin = kinship(kind, otherKind)
            guard kin > 0 else { continue }
            for way in proof.worked {
                scores[way, default: SortScore()].points += 2 * kin
                scores[way, default: SortScore()].games += 1
            }
            for way in proof.picture.subtracting(proof.worked) {
                scores[way, default: SortScore()].points += kin
                scores[way, default: SortScore()].games += 1
            }
        }
        return scores
    }

    /// … from this Mac's record, read again only when the file has changed.
    static func sortScores(for kind: GameKind, excluding game: String, file: URL = url) -> [String: SortScore] {
        guard kind.engine != "other" else { return [:] }
        return sortScores(for: kind, excluding: game, proofs: knownProofs(file))
    }

    private static let cacheLock = NSLock()
    private static var cache: (path: String, modified: Date?, size: Int?, proofs: [String: Proof])?

    /// Asked of the file system each time: a URL keeps the values it was first asked for.
    static func knownProofs(_ file: URL = url) -> [String: Proof] {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attributes?[.modificationDate] as? Date, size = (attributes?[.size] as? NSNumber)?.intValue
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache, cache.path == file.path, cache.modified == modified, cache.size == size { return cache.proofs }
        let proofs = proofs(load(from: file))
        cache = (file.path, modified, size, proofs)
        return proofs
    }

    /// Only games whose first entry is a start on a way not yet proven: the ones logged after they already worked don't count.
    static func summary(_ entries: [Entry]) -> Summary {
        var byGame: [String: [Entry]] = [:]
        for entry in entries { byGame[entry.game, default: []].append(entry) }
        var summary = Summary()
        for list in byGame.values where list.first?.known != true {
            var ways = 0
            var outcome: Event?
            for entry in list {
                if entry.event == .started { ways += 1 }
                if entry.event == .worked || entry.event == .gaveUp {
                    outcome = entry.event
                    break
                }
            }
            switch outcome {
            case .worked? where ways <= 1: summary.firstWay += 1
            case .worked?: summary.laterWay += 1
            case .gaveUp?: summary.noWay += 1
            default: summary.open += 1
            }
        }
        return summary
    }
}
