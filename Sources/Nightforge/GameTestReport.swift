import Foundation

/// What a game test writes: report.json for tools – each game's entry carries compat-report.yml's
/// fields under the same names and words (CompatReport), so the compatibility list can count it
/// like a player's report – and report.md, a short German summary for people. Both go into the
/// repository (docs/spieletest, scripts/import-game-test.py): no paths, no account names.
extension GameTest {
    struct Entry: Codable, Equatable {
        // compat-report.yml's fields.
        var game: String
        /// steam, epic, gog
        var store: String
        /// The store's ID: Steam's app ID, Epic's app name, GOG's product ID.
        var storeID: String
        /// windows, mac
        var platform: String
        /// good, problems, no-start; nil when it wasn't tried.
        var result: String?
        /// The way it last started with (`LaunchAttempt.id`), "mac" for a Mac version.
        var way: String?
        /// GameRating.Issue's words: crashed, lowFrameRate.
        var issues: [String] = []

        // What the run saw.
        var outcome: Outcome
        var skip: Skip?
        var ways: [Way] = []
        var notYet: Bool?
        var startedAt: Date?
        var secondsToProcess: Double?
        var secondsToPicture: Double?
        var frames: Frames?
        /// wine.log's error lines since the start (GameLog.errors), when it had no picture or ended.
        var errors: [String]?
        /// Where it hung (`topOfStack`).
        var stack: [String]?
        /// In German, for people: what else came up.
        var notes: [String]?
        /// Files in the run's folder with more: the log since the start, the sample.
        var files: [String]?

        init(_ candidate: Candidate, outcome: Outcome, skip: Skip? = nil) {
            game = candidate.name
            store = candidate.store.rawValue
            storeID = candidate.storeID
            platform = candidate.platform.rawValue
            self.outcome = outcome
            self.skip = skip
            notYet = candidate.notYet ? true : nil
            if skip != nil, let note = candidate.skipNote { notes = [note] }
        }

        static func skipped(_ candidate: Candidate, _ skip: Skip) -> Entry {
            Entry(candidate, outcome: .skipped, skip: skip)
        }

        /// Every text in it without what identifies the player (GameLog.redacted).
        func redacted(home: String = NSHomeDirectory(), user: String = NSUserName()) -> Entry {
            func clean(_ text: String) -> String { GameLog.redacted(text, home: home, user: user) }
            var entry = self
            entry.game = clean(game)
            entry.errors = errors?.map(clean)
            entry.stack = stack?.map(clean)
            entry.notes = notes?.map(clean)
            return entry
        }
    }

    struct Report: Codable, Equatable {
        static let format = 1

        var formatVersion = Report.format
        var started: Date
        var finished: Date?
        /// Ended early by `gameTest.stop`.
        var stopped = false
        var nightforge: String
        /// The engine's parts (EngineBuild.parts): "winecx@4.7.3", "dxmt@…".
        var engine: [String]?
        /// Chip and macOS.
        var mac: String
        var pictureWait: Double
        var playSeconds: Double
        /// Minutes the run waited for a locked screen.
        var waitedLocked: Int?
        var games: [Entry] = []
    }

    static func json(_ report: Report) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(report)) ?? Data()
    }

    static func report(from data: Data) -> Report? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Report.self, from: data)
    }

    /// Whether `text` gives away whose Mac it ran on: the home folder, or the account name in a
    /// path (/Users/<name>, C:\users\<name>).
    static func leaks(_ text: String, home: String = NSHomeDirectory(), user: String = NSUserName()) -> Bool {
        if !home.isEmpty, text.contains(home) { return true }
        guard !user.isEmpty else { return false }
        let path = #"(?i)users(\\{1,2}|/)"# + NSRegularExpression.escapedPattern(for: user) + #"(?![\p{L}\p{N}_])"#
        return text.range(of: path, options: .regularExpression) != nil
    }

    /// The run's folder, and its date for docs/spieletest: "2026-11-03-0112".
    static func folderName(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    /// A file name for a game's log or sample: its key without anything a path could make of it.
    static func fileName(_ key: String, _ suffix: String) -> String {
        String(key.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "_" }) + "." + suffix
    }

    // MARK: - The German summary

    static func summary(_ report: Report, timeZone: TimeZone = .current) -> String {
        func time(_ date: Date, _ format: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        let tried = report.games.filter { $0.outcome != .skipped && $0.outcome != .needsPlayer }
        let pictures = tried.filter { $0.outcome == .picture }
        let without = tried.filter { $0.outcome != .picture }
        let calledOff = report.games.filter { $0.outcome == .needsPlayer }
        let skipped = report.games.filter { $0.outcome == .skipped }

        var lines = ["# Spieletest vom \(time(report.started, "d.M.yyyy"))", ""]
        lines.append((["Nightforge \(report.nightforge)"] + (report.engine ?? []) + [report.mac]).joined(separator: " · "))
        let end = report.finished.map { ", Ende \(time($0, "HH:mm"))" } ?? ", noch nicht fertig"
        lines.append("Start \(time(report.started, "HH:mm"))\(end)\(report.stopped ? " (angehalten)" : ""). "
                     + "Je Spiel bis \(Int(report.pictureWait)) s auf das erste Bild gewartet, mit Bild \(Int(report.playSeconds)) s laufen lassen.")
        if let locked = report.waitedLocked, locked > 0 {
            lines.append("Der Bildschirm war gesperrt: \(locked) min gewartet.")
        }
        lines.append("")
        var counts = "**\(tried.count) gestartet: \(pictures.count) mit Bild"
        if !without.isEmpty {
            let kinds: [(Outcome, String)] = [(.crash, "abgestürzt"), (.hang, "hängt"), (.noWindow, "ohne Fenster"), (.noStart, "nicht gestartet")]
            let parts = kinds.compactMap { kind, word in
                let count = without.filter { $0.outcome == kind }.count
                return count > 0 ? "\(count) \(word)" : nil
            }
            counts += ", \(without.count) ohne (\(parts.joined(separator: ", ")))"
        }
        if !calledOff.isEmpty { counts += ". \(calledOff.count) abgebrochen" }
        if !skipped.isEmpty { counts += ". \(skipped.count) nicht gestartet" }
        lines += [counts + ".**", ""]

        if !tried.isEmpty || !calledOff.isEmpty {
            lines += ["| Spiel | Laden | Fassung | Weg | Ergebnis | Bild nach | FPS Ø / tief |", "|---|---|---|---|---|---|---|"]
            for entry in tried + calledOff {
                let cells = [cell(entry.game), storeLabel(entry.store), entry.platform == "mac" ? "Mac" : "Windows",
                             cell(waysText(entry)), cell(german(entry)),
                             entry.secondsToPicture.map { "\(Int($0.rounded())) s" } ?? "–", framesText(entry)]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
            lines.append("")
        }

        let troubled = report.games.filter { entry in
            entry.outcome != .skipped && (entry.outcome != .picture || !entry.issues.isEmpty || entry.notes != nil)
        }
        if !troubled.isEmpty {
            lines += ["## Genauer", ""]
            for entry in troubled {
                lines += ["### \(entry.game) (\(storeLabel(entry.store)), \(entry.platform == "mac" ? "Mac" : "Windows"))", ""]
                lines.append("\(german(entry)). Wege: \(waysText(entry)).")
                for note in entry.notes ?? [] { lines.append("- \(note)") }
                if let stack = entry.stack, !stack.isEmpty {
                    lines += ["", "Wo es hängt (sample):", "", "```"] + stack + ["```"]
                }
                if let errors = entry.errors, !errors.isEmpty {
                    lines += ["", "Fehler im wine.log:", "", "```"] + errors + ["```"]
                }
                if let files = entry.files, !files.isEmpty {
                    lines += ["", "Mehr im Ordner des Laufs: " + files.joined(separator: ", ")]
                }
                lines.append("")
            }
        }

        if !skipped.isEmpty {
            lines += ["## Nicht gestartet", ""]
            for entry in skipped {
                let note = entry.notes.map { " (" + $0.joined(separator: "; ") + ")" } ?? ""
                lines.append("- \(entry.game) (\(storeLabel(entry.store))): \(entry.skip?.german ?? "–")\(note)")
            }
            lines.append("")
        }
        lines.append("Für die Kompatibilitätsliste: report.json (Format \(report.formatVersion)), je Spiel game, store, storeID, result, way, issues wie im Meldeformular.")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func storeLabel(_ store: String) -> String {
        Provider(rawValue: store)?.label ?? store
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func waysText(_ entry: Entry) -> String {
        if entry.ways.isEmpty { return entry.way ?? "–" }
        return entry.ways.map(\.way).joined(separator: " → ")
    }

    private static func german(_ entry: Entry) -> String {
        var text: String
        switch entry.outcome {
        case .picture: text = "Bild"
        case .noWindow: text = "kein Fenster, beendet"
        case .crash: text = "abgestürzt ohne Bild"
        case .hang: text = "hängt ohne Bild"
        case .noStart: text = "nicht gestartet"
        case .needsPlayer: text = "abgebrochen: " + (entry.skip?.german ?? "brauchte den Spieler")
        case .skipped: text = "nicht gestartet: " + (entry.skip?.german ?? "–")
        }
        if entry.issues.contains("crashed") { text += ", danach von selbst beendet" }
        if entry.issues.contains("lowFrameRate") { text += ", wenig FPS" }
        if entry.notYet == true { text += " (laut Profil „noch nicht“)" }
        return text
    }

    private static func framesText(_ entry: Entry) -> String {
        if let frames = entry.frames { return "\(Int(frames.average.rounded())) / \(Int(frames.low.rounded()))" }
        guard entry.outcome == .picture else { return "–" }
        let way = entry.way ?? ""
        if way.hasPrefix("d3dmetal") { return "– (D3DMetal meldet keine)" }
        if way == "mac" { return "– (Mac-Fassung meldet keine)" }
        if way.hasPrefix("dxmt") { return "– (keine im Log)" }
        return "– (meldet keine)"
    }
}
