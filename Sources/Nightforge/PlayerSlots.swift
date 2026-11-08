import Foundation
import GameController

/// Which controller is which player, as far as Nightforge goes: numbers 1 to 4, kept while a pad is
/// off. GameController has no lasting name for a pad, a pad switched on again is a new object, so
/// one that comes back is known only by its kind: it takes the empty seat of its own kind, the
/// lowest if several are empty. Two of the same kind both off can therefore swap (the first one
/// on is the lower number). The seats last as long as Nightforge runs.
///
/// Windows games don't see these numbers: Wine hands out XInput's places itself (docs/TODO.md).
struct PlayerSlots<Pad: Hashable> {
    private struct Seat {
        var pad: Pad?
        var kind: String
        /// When it was left, by the count of pads that left: the oldest empty seat goes first.
        var leftAt = 0
    }

    static var count: Int { 4 }

    private var seats = [Seat?](repeating: nil, count: Self.count)
    private var departures = 0

    /// The pads there are now, in macOS's order, and their numbers (1…4). A pad past the fourth has none.
    mutating func update(connected: [(pad: Pad, kind: String)]) -> [Pad: Int] {
        let here = Set(connected.map(\.pad))
        for index in seats.indices {
            if let pad = seats[index]?.pad, !here.contains(pad) {
                departures += 1
                seats[index]?.pad = nil
                seats[index]?.leftAt = departures
            }
        }
        for (pad, kind) in connected where !seats.contains(where: { $0?.pad == pad }) {
            guard let index = seat(for: kind) else { continue }
            seats[index] = Seat(pad: pad, kind: kind)
        }
        var numbers: [Pad: Int] = [:]
        for (index, seat) in seats.enumerated() {
            if let pad = seat?.pad { numbers[pad] = index + 1 }
        }
        return numbers
    }

    /// Its own kind's empty seat, else a free one, else the seat left the longest ago.
    private func seat(for kind: String) -> Int? {
        if let own = seats.firstIndex(where: { $0 != nil && $0?.pad == nil && $0?.kind == kind }) { return own }
        if let free = seats.firstIndex(where: { $0 == nil }) { return free }
        return seats.indices.filter { seats[$0]?.pad == nil }.min { seats[$0]?.leftAt ?? 0 < seats[$1]?.leftAt ?? 0 }
    }
}

/// The light bar's colour for a player, in the order PlayStation consoles use.
enum PlayerLight {
    static func color(player: Int) -> (red: Float, green: Float, blue: Float)? {
        switch player {
        case 1: return (0, 0.25, 1)
        case 2: return (1, 0, 0)
        case 3: return (0, 1, 0)
        case 4: return (1, 0, 0.5)
        default: return nil
        }
    }
}

/// The seats, for the controllers as they are now.
@MainActor
final class ControllerPlayers {
    static let shared = ControllerPlayers()

    private var slots = PlayerSlots<ObjectIdentifier>()
    /// What each pad was last told: only a change is written, and never over a running game's own.
    private var written: [ObjectIdentifier: Int] = [:]

    /// The numbers of `pads`, and a pad's number and light set where they've changed. While a game
    /// is on screen the pads are the game's: what's left to set is set when Nightforge is back.
    func seat(_ pads: [GCController], gameOnScreen: Bool) -> [ObjectIdentifier: Int] {
        let numbers = slots.update(connected: pads.map { (ObjectIdentifier($0), Self.kind($0)) })
        written = written.filter { id, _ in pads.contains { ObjectIdentifier($0) == id } }
        guard !gameOnScreen else { return numbers }
        for pad in pads {
            let id = ObjectIdentifier(pad)
            let number = numbers[id] ?? 0
            guard written[id] != number else { continue }
            written[id] = number
            pad.playerIndex = GCControllerPlayerIndex(rawValue: number - 1) ?? .indexUnset
            if let color = PlayerLight.color(player: number) {
                pad.light?.color = GCColor(red: color.red, green: color.green, blue: color.blue)
            }
        }
        return numbers
    }

    private static func kind(_ pad: GCController) -> String { pad.vendorName ?? pad.productCategory }
}
