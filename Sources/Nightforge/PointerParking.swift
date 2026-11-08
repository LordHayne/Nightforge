import CoreGraphics
import Foundation

/// The mouse pointer over a game played with the pad. macOS gives no public way to hide it for
/// another app: `NSCursor.setHiddenUntilMouseMoves` and `CGDisplayHideCursor` work for the app in
/// front, a cursor rect needs the key window (`NSTrackingActiveAlways` is "not supported for
/// NSTrackingCursorUpdate"), and taking the keys for a moment makes Unity and Unreal games minimise
/// (GameStage). What's left, and touches nothing of the game's, is moving it out of the picture:
/// `CGWarpMouseCursorPosition` needs no permission and "moves … without generating events".
struct PointerParking {
    /// The mouse has to have lain still this long: whoever is using it keeps the pointer.
    static let mouseQuiet: TimeInterval = 2

    private var parkedAt: TimeInterval?

    var isParked: Bool { parkedAt != nil }

    /// The bottom edge, where only the arrow's very tip is left on screen (its point is its top
    /// left); away from the corner, which may be a hot corner (bottom right is Quick Note by
    /// default), and on the screen the pointer is on, so a game on the other screen is left alone.
    static func place(on display: CGRect) -> CGPoint {
        CGPoint(x: display.maxX - 48, y: display.maxY - 1)
    }

    /// Whether to move the pointer away now. `mouseAgo`: seconds since the mouse or trackpad itself
    /// was used. Once parked it stays so until the mouse is used, then the next use of the pad
    /// parks it again. `overGame` and `question` are looked up only when it would be parked.
    mutating func parksNow(padInUse: Bool, now: TimeInterval, mouseAgo: TimeInterval, pointerInUse: Bool, setting: Bool,
                           overGame: @autoclosure () -> Bool, question: @autoclosure () -> Bool) -> Bool {
        if let parkedAt, now - parkedAt > mouseAgo { self.parkedAt = nil }  // the mouse moved since
        guard setting, padInUse, parkedAt == nil, !pointerInUse, mouseAgo >= Self.mouseQuiet, overGame(), !question() else { return false }
        parkedAt = now
        return true
    }
}
