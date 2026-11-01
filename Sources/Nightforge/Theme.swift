import SwiftUI

/// "Nightforge": a deep night-blue room lit by a single sodium-vapour lamp.
enum Theme {
    static let night = Color(red: 0x0F / 255, green: 0x14 / 255, blue: 0x1C / 255)   // #0F141C
    static let sodium = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x47 / 255)  // #FFB347
    static let ink = Color(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255)     // #F3F1EC
    static let muted = Color(red: 0x9A / 255, green: 0xA3 / 255, blue: 0xAF / 255)   // #9AA3AF
    static let slate = Color(red: 0x1C / 255, green: 0x24 / 255, blue: 0x30 / 255)   // #1C2430

    // How well a game runs (Compatibility). Never on their own: an icon and a word go with them.
    // "With tweaks" is a paler amber than sodium, which stays for the one main action and focus.
    static let runsGreat = Color(red: 0x7E / 255, green: 0xE2 / 255, blue: 0xA0 / 255)       // #7EE2A0
    static let runsWithTweaks = Color(red: 0xE8 / 255, green: 0xC6 / 255, blue: 0x8A / 255)  // #E8C68A
    static let runsNot = Color(red: 0xFF / 255, green: 0x9E / 255, blue: 0x94 / 255)         // #FF9E94
    /// "Doesn't start yet": a warmer amber than "with tweaks", calmer than the red of a game that never runs.
    static let runsNotYet = Color(red: 0xF2 / 255, green: 0xA6 / 255, blue: 0x5A / 255)      // #F2A65A

    /// Nightforge's own share in the storage bar, beside the games in sodium (as in the design).
    static let storageNightforge = Color(red: 0x8C / 255, green: 0xA8 / 255, blue: 0xDB / 255)  // #8CA8DB

    /// A button that deletes something (Uninstall, Remove Everything), the design's `dangerBtn`.
    static let danger = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255)  // #FF6B5E
    /// A warning sign in a dialog: the paler amber, so sodium stays the main action's.
    static let warning = runsWithTweaks
    /// Text that says something failed: paler than `danger`, readable on the night blue.
    static let errorText = Color(red: 0xFF / 255, green: 0x9E / 255, blue: 0x94 / 255)  // #FF9E94

    /// Wide, heavy display face for titles and the play button. Views take it through `.displayFont(_:)`,
    /// which adds "Larger text".
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.expanded) }

    static let gutter: CGFloat = 56
}

/// The N beside the name in the top bar: the app icon's three pieces in brushed silver, with the
/// blue light seam along the slab (scripts/render-brand.swift draws the big one). Bigger, on the
/// loading screen (GameBackdrop), the seam is wider and glows further.
struct NightforgeMark: View {
    var seamWidth: CGFloat = 1
    var seamGlow: CGFloat = 2
    /// The seam's light alone, so it can pulse without the pieces being drawn again.
    var seamOpacity: Double = 1
    /// How a change of `seamOpacity` goes – for the seam only.
    var seamAnimation: Animation?

    static let seamColor = Color(red: 0.18, green: 0.48, blue: 1)

    var body: some View {
        ZStack {
            NightforgeMarkShape()
                .fill(LinearGradient(colors: [Theme.ink, Theme.muted], startPoint: .top, endPoint: .bottom))
            NightforgeMarkShape.Seam()
                .stroke(Self.seamColor, style: StrokeStyle(lineWidth: seamWidth, lineCap: .round))
                .shadow(color: Self.seamColor.opacity(0.8), radius: seamGlow)
                .opacity(seamOpacity)
                .animation(seamAnimation, value: seamOpacity)
        }
        .aspectRatio(332 / 440, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct NightforgeMarkShape: Shape {
    /// In a 332 × 440 box, origin top left.
    private static let pieces: [[CGPoint]] = [
        [CGPoint(x: 0, y: 0), CGPoint(x: 332, y: 308), CGPoint(x: 332, y: 440), CGPoint(x: 49, y: 170), CGPoint(x: 0, y: 128)],
        [CGPoint(x: 0, y: 170), CGPoint(x: 82, y: 236), CGPoint(x: 82, y: 338), CGPoint(x: 0, y: 432)],
        [CGPoint(x: 249, y: 100), CGPoint(x: 332, y: 24), CGPoint(x: 332, y: 280), CGPoint(x: 249, y: 204)],
    ]

    static func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x / 332 * rect.width, y: rect.minY + p.y / 440 * rect.height)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for piece in Self.pieces {
            path.addLines(piece.map { Self.point($0, in: rect) })
            path.closeSubpath()
        }
        return path
    }

    /// The light seam along the slab's lower edge.
    struct Seam: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: NightforgeMarkShape.point(CGPoint(x: 49, y: 170), in: rect))
            path.addLine(to: NightforgeMarkShape.point(CGPoint(x: 332, y: 440), in: rect))
            return path
        }
    }
}

enum Format {
    static func bytes(_ bytes: Int64) -> String {
        bytes > 0 ? bytes.formatted(.byteCount(style: .file).locale(L10n.locale)) : "–"
    }

    static func relative(_ date: Date) -> String { relative(date, now: Date()) }

    /// "2 hours ago" – and "just now" within a minute either way: a date a moment ahead of the clock
    /// (a game that has just ended) would otherwise say "in 0 seconds".
    static func relative(_ date: Date, now: Date) -> String {
        if abs(date.timeIntervalSince(now)) < 60 { return L10n.t("just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func playtime(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) " + L10n.t("min") }
        let hours = Double(minutes) / 60
        let amount = hours.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
        return amount + " " + (amount == "1" ? L10n.t("hr") : L10n.t("hrs"))
    }
}
