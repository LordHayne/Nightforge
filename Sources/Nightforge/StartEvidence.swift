import Foundation

/// What happened to each start, one line per event, never rewritten: which way, on which engine, on
/// which Mac, and what the game said. It stays on this Mac. It's what a better choice can be made from
/// later, and the number that says whether the choices get better: how many games Nightforge had never
/// seen came up on their first way.
enum StartEvidence {
    enum Event: String, Codable {
        case started, worked, failed, gaveUp
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
                     to file: URL = url) {
        var entry = Entry(at: Date(), game: game.key, event: event, way: way, engine: engine, known: known)
        entry.kind = kind
        entry.recipe = recipe
        entry.diagnosis = diagnosis.flatMap { $0.isEmpty ? nil : $0.map { GameLog.redacted(String($0.prefix(240))) } }
        if event == .started { entry.mac = "\(ProblemReport.chip) · macOS \(ProblemReport.osVersion)" }
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
