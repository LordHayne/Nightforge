import SwiftUI

/// What becomes of a game while the overlay is up. The player's rule (8.11.): it gets no controller
/// input then. macOS can't take the pad from the app in front, so the game is stopped – all but a
/// Mac version that only runs online, which would lose its connection. There the overlay says so.
enum OverlayStillness: Equatable {
    case paused
    /// Not stopped, and the pad still reaches it.
    case hearsPad
    /// Not stopped, and our Wine driver keeps the pad from it (PadSilence).
    case silenced
}

/// What the overlay's blocks are given: looked up once as it opens, only values.
struct OverlayContext: Equatable {
    var stillness: OverlayStillness?
    /// When the game's process started; nil where that can't be told.
    var startedAt: Date?
    var pads: [ControllerStatus] = []
    /// A Windows game: our Wine driver can keep the pad from it.
    var silencesPad = false
    /// A Windows game that only runs online: it isn't stopped if the driver answers.
    var runsOnIfSilent = false
}

/// Whether a block has something to offer for this game on this Mac. Never a question from macOS on
/// the sofa: what needs a permission says so in a sentence.
enum OverlayAvailability: Equatable {
    case ready
    /// Works from the game's next start.
    case nextStart(String)
    /// Needs a permission only a real mouse can give.
    case needsRight(String)
    /// Means nothing here: not shown at all.
    case hidden
}

/// Where a block goes in the side bar, top to bottom. The ways out (Continue Playing, Quit Game, Go to
/// Nightforge) aren't blocks: if a block fails, they are still there.
enum OverlayZone: Int, Comparable {
    /// Beside the game's name.
    case corner
    /// Under the game's name.
    case head
    /// Above the ways out.
    case status
    /// Under the ways out: what changes something in the game.
    case control
    case tool

    static func < (a: OverlayZone, b: OverlayZone) -> Bool { a.rawValue < b.rawValue }
}

/// The overlay's measures, drawn for a 1920×1080 screen and scaled to the one the game is on: the
/// same picture on the TV and the MacBook, and sizes rather than a transformation, which PadFocus's
/// frames couldn't follow.
struct OverlayMetrics: Equatable {
    let unit: CGFloat

    init(height: CGFloat) { unit = min(max(height / 1080, 0.7), 2) }

    func callAsFunction(_ points: CGFloat) -> CGFloat { points * unit }
}

/// One thing the overlay can show. A new one is a new type and an entry in `OverlayTiles.all`.
protocol OverlayTile {
    var id: String { get }
    var zone: OverlayZone { get }
    /// Its name, for the line that says why it can't be used now.
    var title: String { get }
    func availability(in context: OverlayContext) -> OverlayAvailability
    @MainActor func view(in context: OverlayContext, metrics: OverlayMetrics) -> AnyView
}

enum OverlayTiles {
    static let all: [any OverlayTile] = [OverlayClockTile(), OverlaySessionTile(), OverlayPadsTile()]

    /// The blocks to show, by zone; within one in the order of `tiles`.
    static func visible(_ tiles: [any OverlayTile] = all, in context: OverlayContext) -> [any OverlayTile] {
        tiles.enumerated()
            .filter { $0.element.availability(in: context) != .hidden }
            .sorted { ($0.element.zone, $0.offset) < ($1.element.zone, $1.offset) }
            .map(\.element)
    }
}

/// The overlay's rules that need no screen.
enum OverlayRules {
    /// How long a game stays stopped for the fingers to come off the pad, at most.
    nonisolated static let releaseLimit: TimeInterval = 1

    nonisolated static func stillness(platform: Platform, onlineOnly: Bool) -> OverlayStillness {
        platform == .mac && onlineOnly ? .hearsPad : .paused
    }

    /// A Windows game that only runs online would lose its connection if it stood: it runs on, if our
    /// Wine driver answers that it keeps the pad from it. Without an answer it's stopped like the rest.
    nonisolated static func runsOnIfSilent(platform: Platform, onlineOnly: Bool) -> Bool {
        platform == .windows && onlineOnly
    }

    /// Whether a stopped game may run on: nothing is held any more – or it has waited long enough,
    /// for a stick the player keeps pushed.
    nonisolated static func mayRunOn(padIdle: Bool, waited: TimeInterval) -> Bool {
        padIdle || waited >= releaseLimit
    }

    /// "24 min", "1 h 24 min", "2 h".
    nonisolated static func sessionLength(seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds) / 60)
        guard minutes >= 60 else { return "\(minutes) " + L10n.t("min") }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) " + L10n.t("min")
    }

    /// "Paused · 1 h 24 min".
    nonisolated static func sessionLine(_ stillness: OverlayStillness?, startedAt: Date?, now: Date) -> String {
        let state: String?
        switch stillness {
        case .paused: state = L10n.t("Paused")
        case .hearsPad, .silenced: state = L10n.t("Keeps running")
        case nil: state = nil
        }
        let length = startedAt.map { sessionLength(seconds: now.timeIntervalSince($0)) }
        return [state, length].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct OverlayClockTile: OverlayTile {
    let id = "clock"
    let zone = OverlayZone.corner
    var title: String { "" }

    func availability(in context: OverlayContext) -> OverlayAvailability { .ready }

    @MainActor func view(in context: OverlayContext, metrics m: OverlayMetrics) -> AnyView {
        AnyView(TimelineView(.everyMinute) { time in
            Text(time.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))
                .font(size: m(34), weight: .bold)
        })
    }
}

private struct OverlaySessionTile: OverlayTile {
    let id = "session"
    let zone = OverlayZone.head
    var title: String { "" }

    func availability(in context: OverlayContext) -> OverlayAvailability { .ready }

    @MainActor func view(in context: OverlayContext, metrics m: OverlayMetrics) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: m(10)) {
            TimelineView(.everyMinute) { time in
                Text(OverlayRules.sessionLine(context.stillness, startedAt: context.startedAt, now: time.date))
                    .font(size: m(26))
                    .foregroundStyle(Theme.muted)
            }
            if context.stillness == .hearsPad {
                Text(L10n.t("This game still gets your controller input."))
                    .font(size: m(24), weight: .medium)
                    .foregroundStyle(Theme.sodium)
                    .fixedSize(horizontal: false, vertical: true)
            }
        })
    }
}

private struct OverlayPadsTile: OverlayTile {
    let id = "pads"
    let zone = OverlayZone.status
    var title: String { L10n.t("Controller") }

    func availability(in context: OverlayContext) -> OverlayAvailability { context.pads.isEmpty ? .hidden : .ready }

    @MainActor func view(in context: OverlayContext, metrics m: OverlayMetrics) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: m(12)) {
            ForEach(Array(context.pads.enumerated()), id: \.offset) { _, pad in
                OverlayPadRow(pad: pad, metrics: m)
            }
        })
    }
}

private struct OverlayPadRow: View {
    let pad: ControllerStatus
    let metrics: OverlayMetrics

    private var low: Bool { (pad.battery ?? 1) < 0.2 && !pad.charging }

    var body: some View {
        let m = metrics
        HStack(spacing: m(14)) {
            Image(systemName: "gamecontroller.fill")
                .font(size: m(24))
                .foregroundStyle(Theme.muted)
            Text(ControllerStatus.shortName(pad.name))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let battery = pad.battery {
                if pad.charging {
                    Image(systemName: "bolt.fill")
                        .font(size: m(22))
                        .foregroundStyle(Theme.sodium)
                }
                OverlayBattery(level: CGFloat(battery), low: low, metrics: m)
                Text("\(Int((battery * 100).rounded())) %")
                    .frame(minWidth: m(78), alignment: .trailing)
                    .foregroundStyle(low ? Theme.sodium : Theme.ink)
            }
        }
        .font(size: m(26), weight: .semibold)
        .accessibilityElement(children: .combine)
    }
}

private struct OverlayBattery: View {
    let level: CGFloat
    let low: Bool
    let metrics: OverlayMetrics

    var body: some View {
        let m = metrics
        let shape = RoundedRectangle(cornerRadius: m(7), style: .continuous)
        Color.clear
            .frame(width: m(62), height: m(26))
            .overlay(alignment: .leading) {
                (low ? Theme.sodium : Theme.ink)
                    .frame(width: m(62) * max(0, min(level, 1)))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.ink.opacity(0.55), lineWidth: m(2)))
            .accessibilityHidden(true)
    }
}
