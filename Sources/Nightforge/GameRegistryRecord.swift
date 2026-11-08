import CryptoKit
import Foundation

/// What `Engine.applyGameSettings` last put into the prefix's registry, so that a start with nothing
/// new runs no regedit (a Wine program of its own, at every Play).
///
/// Per key, not per game: games share program names (UnityCrashHandler64.exe, launcher.exe), and the
/// game that started last decides what such a name holds. The record lives in the prefix, so a new
/// prefix starts without one. A wineserver saves the registry half a minute after a change at most: one
/// ended the hard way before that loses what regedit wrote. So the record only counts once the
/// prefix's user.reg is at least as new as it is.
enum GameRegistryRecord {
    /// One key's whole text in a .reg file. `key` as Windows compares it: without regard to case.
    struct Section: Equatable {
        let key: String
        let text: String

        init(key: String, text: String) {
            self.key = key.lowercased()
            self.text = text
        }

        var digest: String {
            SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Whether every section stands in the record as it's wanted now.
    static func holds(_ sections: [Section], recorded: [String: String]) -> Bool {
        sections.allSatisfy { recorded[$0.key] == $0.digest }
    }

    /// Imports `sections` and `unrecorded` together when something differs from the record, or there
    /// are `unrecorded` ones: values in a game's own keys, which the game may have changed since, so
    /// they are set again at every start. A failed import isn't noted: the next start tries again.
    /// True when the import ran.
    @discardableResult
    static func importIfChanged(_ sections: [Section], unrecorded: [String] = [], record: URL, userRegistry: URL,
                                importer: (String) -> Bool) -> Bool {
        var recorded = trusted(record: record, userRegistry: userRegistry) ?? [:]
        guard !holds(sections, recorded: recorded) || !unrecorded.isEmpty else { return false }
        guard importer((sections.map(\.text) + unrecorded).joined(separator: "\n\n")) else { return true }
        for section in sections { recorded[section.key] = section.digest }
        if let data = try? JSONEncoder().encode(recorded) { try? data.write(to: record, options: .atomic) }
        return true
    }

    /// The record, unless the registry on disk is older than it or there's no telling.
    private static func trusted(record: URL, userRegistry: URL) -> [String: String]? {
        func modified(_ file: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        }
        guard let written = modified(record), let saved = modified(userRegistry), saved >= written,
              let data = try? Data(contentsOf: record) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
