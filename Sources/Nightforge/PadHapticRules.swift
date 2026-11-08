import Foundation

/// Which moments the pad's motors answer, and how: few, and short. PadHaptics plays them.
enum PadHapticRules {
    enum Moment: Equatable {
        /// A pressed where Nightforge has the pad.
        case confirm
        case gameStart
        /// The overlay's buttons held: it builds towards the two seconds, which until now passed without a sign.
        case overlayHold
        case overlayOpens
    }

    struct Tap: Equatable {
        var time: TimeInterval
        var intensity: Float
        var sharpness: Float
    }

    /// Whether this moment is felt now. A game has the motors except for the overlay's own buttons,
    /// and a game started with the mouse doesn't shake a pad lying on the table.
    static func plays(_ moment: Moment, setting: Bool, inFront: Bool, overlay: Bool, padUsedLast: Bool) -> Bool {
        guard setting else { return false }
        switch moment {
        case .confirm: return inFront || overlay
        case .gameStart: return padUsedLast
        case .overlayHold, .overlayOpens: return true
        }
    }

    static func taps(_ moment: Moment) -> [Tap] {
        switch moment {
        case .confirm:
            return [Tap(time: 0, intensity: 0.35, sharpness: 0.7)]
        case .gameStart:
            return [Tap(time: 0, intensity: 0.55, sharpness: 0.4), Tap(time: 0.12, intensity: 0.8, sharpness: 0.4)]
        case .overlayHold:
            // Nothing for the first moment: both sticks pressed in passing, in a game, feel like nothing.
            return [Tap(time: 0.4, intensity: 0.25, sharpness: 0.5), Tap(time: 0.9, intensity: 0.4, sharpness: 0.5),
                    Tap(time: 1.4, intensity: 0.55, sharpness: 0.5)]
        case .overlayOpens:
            return [Tap(time: 0, intensity: 0.9, sharpness: 0.8)]
        }
    }
}
