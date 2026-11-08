import CoreGraphics

/// How Nightforge's layout changes on a TV, without the views. Read from three metres away and
/// with a set that may cut off the outer 5 % (overscan can't be asked for on macOS), so: margins of
/// 5 %, the larger text by itself and a thicker highlight (docs/ENTWURF-KONSOLE.md, section 3).
enum TVRules {
    struct Margins: Equatable {
        var side: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    static let normal = Margins(side: 56, top: 36, bottom: 22)

    /// 5 % of the screen on a TV, never less than the normal margins.
    static func margins(onTV: Bool, screen: CGSize) -> Margins {
        guard onTV else { return normal }
        return Margins(side: max(normal.side, (screen.width * 0.05).rounded()),
                       top: max(normal.top, (screen.height * 0.05).rounded()),
                       bottom: max(normal.bottom, (screen.height * 0.05).rounded()))
    }

    static func usesLargerText(setting: Bool, onTV: Bool) -> Bool { setting || onTV }

    /// The pad's highlight, in points.
    static func ringWidth(onTV: Bool) -> CGFloat { onTV ? 5 : 3 }
}
