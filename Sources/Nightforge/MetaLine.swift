import SwiftUI

/// Above a game's title: how it runs, what kind of game it is, when it came out and where it's
/// from – "Runs great  RPG / 2023  STEAM". What Steam doesn't know is left out.
struct MetaLine: View {
    let compatibility: Compatibility
    let facts: StoreFacts?
    /// The stores it's in ("Steam"), the one it starts through first.
    var stores = ["Steam"]
    /// What its store or the same game on Steam says (GameInfo), where Steam's catalog on the Mac
    /// doesn't have it: Epic's and GOG's games, store hits.
    var info: GameInfo?

    private var genre: String? { facts?.genre ?? info?.genres.first }
    private var year: Int? { facts?.year ?? info?.released.map { Self.calendar.component(.year, from: $0) } }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var body: some View {
        HStack(spacing: 8) {
            CompatibilityBadge(compatibility: compatibility, small: true)
                .padding(.trailing, 4)
            if let genre {
                caps(genre.uppercased(with: L10n.locale))
                    .lineLimit(1)
            }
            if genre != nil, year != nil {
                caps("/")
                    .foregroundStyle(Color.white.opacity(0.2))
                    .accessibilityHidden(true)
            }
            if let year {
                caps(String(year))
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                ForEach(stores, id: \.self) { StoreBadge(store: $0) }
            }
            .padding(.leading, 4)
        }
        .foregroundStyle(Theme.muted)
        .accessibilityElement(children: .combine)
    }

    /// 12 pt capitals, spaced out.
    private func caps(_ text: String) -> some View {
        Text(text)
            .tracking(1.9)
            .font(size: 12, weight: .semibold)
    }
}

/// The store a game is from, small: "STEAM", "EPIC GAMES".
struct StoreBadge: View {
    let store: String

    var body: some View {
        Text(store.uppercased())
            .font(size: 10.5, weight: .semibold)
            .tracking(1.3)
            .foregroundStyle(Theme.ink.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .accessibilityLabel(store)
    }
}
