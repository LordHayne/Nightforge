import SwiftUI

/// "Reduce motion" for Nightforge's own animations (cover zoom, rail scrolling, toasts sliding in):
/// macOS's setting until the player changes it in Settings › General. SwiftUI's own
/// `accessibilityReduceMotion` can't be overridden, so the views read this one.
private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

/// "Larger text": how much larger Nightforge's text is, 1 at the normal size.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// Puts the settings into a window's environment.
struct AccessibilityFromSettings: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(Prefs.Keys.reduceMotion) private var stored = ""
    @AppStorage(Prefs.Keys.largerText) private var largerText = false

    func body(content: Content) -> some View {
        content
            // Text without a size of its own (Settings' rows, text fields) is macOS's 13 pt body.
            .font(size: 13)
            .environment(\.textScale, largerText ? TextScale.larger : 1)
            .environment(\.reduceMotion, Prefs.reduceMotion(system: system, stored: stored))
    }
}

/// "Larger text", one step up across Nightforge. The views set the design's fixed point sizes, so
/// every size goes through `.font(size:)` or `.displayFont(_:)` (tests/TextScaleTest checks it).
/// macOS has no text size for other makers' apps to follow (its per-app one in Accessibility ›
/// Display lists Apple's apps only), so it's a switch in Settings › General.
enum TextScale {
    /// 18 % larger: clearly bigger, and the layouts still hold.
    static let larger: CGFloat = 1.18

    /// Titles from 20 pt on grow by 20 pt's step, as with Dynamic Type on iOS: they're big already,
    /// and the stage's and the dialogs' lines are set by them.
    static func size(_ size: CGFloat, scale: CGFloat) -> CGFloat {
        size + min(size, 20) * (scale - 1)
    }
}

extension View {
    /// Nightforge's text at `size` points, a step larger with "Larger text". `scales: false` for a
    /// size that belongs to a drawing rather than to text: a symbol alone in a round button, a pad glyph.
    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, scales: Bool = true) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, display: false, scales: scales))
    }

    /// The wide, heavy display face for titles and the play button (`Theme.display`), scaled the same way.
    func displayFont(_ size: CGFloat) -> some View {
        modifier(ScaledFont(size: size, weight: .heavy, design: .default, display: true, scales: true))
    }
}

extension Font {
    /// A letter in a drawing (a button on the drawn pad): it belongs to the picture, so it keeps its size.
    static func drawing(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let display: Bool
    let scales: Bool

    func body(content: Content) -> some View {
        let size = scales ? TextScale.size(size, scale: scale) : size
        content.font(display ? Theme.display(size) : .system(size: size, weight: weight, design: design))
    }
}
