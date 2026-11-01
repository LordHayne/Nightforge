import AppKit
import GameController

/// Settings › Controller › Every button: each button of the pad and what it does in Nightforge, in
/// the controller's own symbols like the hints.
struct PadGuideRow: Equatable {
    enum Glyph: Equatable {
        /// SF Symbols or PadGlyph's own, side by side; `chord`: pressed together, "+" between.
        case symbols([String], chord: Bool = false)
        /// The name printed on it where no symbol shows it ("Create", "View", "Touchpad").
        case label(String)
    }

    let id: String
    let glyph: Glyph
    let meaning: String

    /// The rows for `pad`'s labels; `present`: the buttons the connected controller has (nil: all a
    /// pad of its layout has).
    static func all(_ pad: PadSymbols, present: Set<PadPart>? = nil) -> [PadGuideRow] {
        let ps = pad.layout == .playstation
        let has = present ?? Set(PadPart.allCases).subtracting(ps ? [] : [.touch])
        func row(_ part: PadPart, _ glyph: Glyph) -> PadGuideRow? {
            has.contains(part) ? PadGuideRow(id: part.rawValue, glyph: glyph, meaning: part.meaning) : nil
        }
        func shoulder(_ name: String, top: Bool) -> String { "\(name).rectangle.rounded\(top ? "top" : "bottom").fill" }
        let sticks = has.contains(.l3) && has.contains(.r3)
            ? PadGuideRow(id: "l3r3", glyph: .symbols(pad.overlayChord, chord: true), meaning: PadPart.l3.meaning) : nil
        return [
            row(.a, .symbols([pad.confirm])),
            row(.b, .symbols([pad.back])),
            row(.x, .symbols([pad.details])),
            row(.y, .symbols([pad.search])),
            row(.start, .symbols([pad.menu])),
            row(.l1, .symbols([shoulder(ps ? "l1" : "lb", top: false)])),
            row(.r1, .symbols([shoulder(ps ? "r1" : "rb", top: false)])),
            row(.l2, .symbols([shoulder(ps ? "l2" : "lt", top: true)])),
            row(.r2, .symbols([shoulder(ps ? "r2" : "rt", top: true)])),
            row(.up, .symbols(["dpad.up.filled"])),
            row(.down, .symbols(["dpad.down.filled"])),
            row(.left, .symbols(["dpad.left.filled", "dpad.right.filled"])),
            row(.ls, .symbols([pad.stick])),
            row(.rs, .symbols([pad.scroll])),
            sticks,
            row(.select, .label(PadPart.select.name(pad.layout))),
            row(.home, .symbols([ps ? "logo.playstation" : "logo.xbox"])),
            row(.touch, .label(PadPart.touch.name(pad.layout))),
        ].compactMap { $0 }
    }
}

/// The tip a game's loading screen (GameBackdrop) shows for the first starts with a controller:
/// how Nightforge's menu opens in a game.
struct LaunchTip: Equatable {
    /// The buttons to draw (PadGlyph), "+" between.
    let symbols: [String]
    let text: String

    /// How many starts show it.
    static let starts = 3

    /// "L3 + R3" or "LS + RS": the overlay's buttons by name.
    static func chord(_ layout: PadLayout) -> String {
        [PadPart.l3, .r3].map { $0.name(layout) }.joined(separator: " + ")
    }

    /// The tip for a start after `shown` starts that showed it; nil without a controller (`pad`)
    /// or once it's been shown on enough starts.
    static func pick(shown: Int, pad: PadSymbols?) -> LaunchTip? {
        guard let pad, shown < starts else { return nil }
        return LaunchTip(symbols: pad.overlayChord, text: L10n.t("Tip: hold %@ to open the menu in a game", chord(pad.layout)))
    }

    /// For GameBackdrop, once per start: the tip, counted as shown – or nil.
    @MainActor
    static func take(_ pad: PadSymbols, defaults: UserDefaults = .standard) -> LaunchTip? {
        let connected = GCController.controllers().contains { $0.extendedGamepad != nil }
        let shown = defaults.integer(forKey: Prefs.Keys.launchTipShown)
        guard let tip = pick(shown: shown, pad: connected ? pad : nil) else { return nil }
        defaults.set(shown + 1, forKey: Prefs.Keys.launchTipShown)
        return tip
    }
}
