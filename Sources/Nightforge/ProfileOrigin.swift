import Foundation

/// Where a game's known fixes come from – Nightforge's own test on a Mac, or umu-protonfixes – for
/// its options and its page.
struct ProfileOrigin: Equatable {
    let text: String
    let symbol: String
    /// What the test found, shown when the pointer rests on the line.
    let note: String?

    init?(_ profile: GameProfile?, now: Date = Date()) {
        guard let profile else { return nil }
        if profile.fromNightforge {
            let chips = Compatibility.chips(in: profile.note)
            var text = chips.isEmpty ? L10n.t("Tested by Nightforge") : L10n.t("Tested by Nightforge on %@", chips.joined(separator: ", "))
            if let tested = Self.testDay(in: profile.note) { text += " · " + Self.daysAgo(tested, now: now) }
            self.init(text: text, symbol: "checkmark.seal", note: profile.note)
        } else if profile.hasFixes {
            // The list keeps no date per game for these, only when it was built as a whole.
            self.init(text: L10n.t("Community fix · from umu-protonfixes"), symbol: "person.2", note: nil)
        } else {
            return nil
        }
    }

    private init(text: String, symbol: String, note: String?) {
        self.text = text
        self.symbol = symbol
        self.note = note
    }

    /// The day in "Tested 2026-10-26 on M5: …", the start of every note Nightforge's own profiles carry.
    static func testDay(in note: String?) -> Date? {
        guard let note, let range = note.range(of: #"Tested \d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(note[range].dropFirst("Tested ".count)))
    }

    /// "today", "yesterday", "5 days ago" – counted in whole days.
    static func daysAgo(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(from: DateComponents(day: -max(days, 0)))
    }
}
