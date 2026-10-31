import GameController
import SwiftUI

/// The parts of a controller the first start's test knows, and what each does in Nightforge.
enum PadPart: String, CaseIterable {
    case a, b, x, y, l1, r1, l2, r2, select, start, l3, r3, up, down, left, right, home, touch, ls, rs

    /// The ones this controller has (no touchpad on an Xbox pad; some lack a Home or View button).
    @MainActor
    static func present(on pad: GCExtendedGamepad) -> Set<PadPart> {
        var parts: Set<PadPart> = [.a, .b, .x, .y, .l1, .r1, .l2, .r2, .start, .up, .down, .left, .right, .ls, .rs]
        if pad.buttonOptions != nil { parts.insert(.select) }
        if pad.leftThumbstickButton != nil { parts.insert(.l3) }
        if pad.rightThumbstickButton != nil { parts.insert(.r3) }
        if pad.buttonHome != nil { parts.insert(.home) }
        if pad is GCDualSenseGamepad || pad is GCDualShockGamepad { parts.insert(.touch) }
        return parts
    }

    /// What it does in Nightforge – the mapping in InputRouter. What it leaves alone says so.
    var meaning: String {
        switch self {
        case .a: return L10n.t("Selects – on Home it starts the game")
        case .b: return L10n.t("Back, one level up – like Esc")
        case .x: return L10n.t("Opens the selected game's page")
        case .y: return L10n.t("Options for the selected game")
        case .start: return L10n.t("Switches between Home and the library")
        case .l1: return L10n.t("Five games back")
        case .r1: return L10n.t("Five games on")
        case .l2: return L10n.t("Jumps to the first game")
        case .r2: return L10n.t("Jumps to the last game")
        case .up, .left, .right: return L10n.t("Moves the selection")
        case .down: return L10n.t("Moves the selection – on Home, down goes into the library")
        case .ls: return L10n.t("Moves the selection, like the d-pad")
        case .rs: return L10n.t("Works – in games it's mostly the camera")
        case .select, .l3, .r3: return L10n.t("Works – Nightforge doesn't need this button, games do")
        case .home: return L10n.t("Works – it belongs to macOS, Nightforge leaves it alone")
        case .touch: return L10n.t("Works – Nightforge doesn't need the touchpad, games do")
        }
    }

    /// Its name as the controller prints it (face buttons are shown as their symbol instead).
    func name(_ layout: PadLayout) -> String {
        let ps = layout == .playstation
        switch self {
        case .a: return ps ? "✕" : "A"
        case .b: return ps ? "○" : "B"
        case .x: return ps ? "□" : "X"
        case .y: return ps ? "△" : "Y"
        case .l1: return ps ? "L1" : "LB"
        case .r1: return ps ? "R1" : "RB"
        case .l2: return ps ? "L2" : "LT"
        case .r2: return ps ? "R2" : "RT"
        case .select: return ps ? "Create" : L10n.t("View")
        case .start: return ps ? "Options" : L10n.t("Menu")
        case .l3: return ps ? "L3" : "LS"
        case .r3: return ps ? "R3" : "RS"
        case .up, .down, .left, .right: return L10n.t("D-pad")
        case .home: return ps ? "PS" : "Xbox"
        case .touch: return "Touchpad"
        case .ls: return L10n.t("Left stick")
        case .rs: return L10n.t("Right stick")
        }
    }

    /// The face buttons' symbols, filled (✕ ○ □ △ or A B X Y).
    func symbol(_ layout: PadLayout) -> String? {
        switch self {
        case .a: return layout == .playstation ? "xmark.circle.fill" : "a.circle.fill"
        case .b: return layout == .playstation ? "circle.circle.fill" : "b.circle.fill"
        case .x: return layout == .playstation ? "square.circle.fill" : "x.circle.fill"
        case .y: return layout == .playstation ? "triangle.circle.fill" : "y.circle.fill"
        default: return nil
        }
    }
}

/// Which outline to draw: the DualSense (also for a DualShock 4) or the Xbox Wireless Controller.
enum PadLayout: Equatable {
    case playstation, xbox

    @MainActor
    init(_ pad: GCExtendedGamepad) {
        self = pad is GCDualSenseGamepad || pad is GCDualShockGamepad ? .playstation : .xbox
    }
}

/// How far each part is pressed (0…1) and where the sticks stand (-1…1, y down), read from the pad.
struct PadReading: Equatable {
    var values: [PadPart: Float] = [:]
    var left = CGPoint.zero
    var right = CGPoint.zero

    init() {}

    @MainActor
    init(_ pad: GCExtendedGamepad) {
        // In steps of 2 %, so a resting pad doesn't redraw for noise.
        func q(_ value: Float) -> Float { (value * 50).rounded() / 50 }
        func axis(_ value: Float) -> CGFloat { abs(value) < 0.1 ? 0 : CGFloat(q(value)) }
        var v: [PadPart: Float] = [
            .a: pad.buttonA.value, .b: pad.buttonB.value, .x: pad.buttonX.value, .y: pad.buttonY.value,
            .l1: pad.leftShoulder.value, .r1: pad.rightShoulder.value, .l2: pad.leftTrigger.value, .r2: pad.rightTrigger.value,
            .start: pad.buttonMenu.value,
            .up: pad.dpad.up.value, .down: pad.dpad.down.value, .left: pad.dpad.left.value, .right: pad.dpad.right.value,
        ]
        v[.select] = pad.buttonOptions?.value
        v[.l3] = pad.leftThumbstickButton?.value
        v[.r3] = pad.rightThumbstickButton?.value
        v[.home] = pad.buttonHome?.value
        if let dualSense = pad as? GCDualSenseGamepad {
            v[.touch] = dualSense.touchpadButton.value
        } else if let dualShock = pad as? GCDualShockGamepad {
            v[.touch] = dualShock.touchpadButton.value
        }
        values = v.mapValues(q)
        left = CGPoint(x: axis(pad.leftThumbstick.xAxis.value), y: -axis(pad.leftThumbstick.yAxis.value))
        right = CGPoint(x: axis(pad.rightThumbstick.xAxis.value), y: -axis(pad.rightThumbstick.yAxis.value))
    }

    func value(_ part: PadPart) -> Float { values[part] ?? 0 }
    func pressed(_ part: PadPart) -> Bool { value(part) > 0.5 }

    /// Pressed buttons, and the sticks pushed more than halfway.
    var pressedParts: Set<PadPart> {
        var parts = Set(values.filter { $0.value > 0.5 }.keys)
        if hypot(left.x, left.y) > 0.5 { parts.insert(.ls) }
        if hypot(right.x, right.y) > 0.5 { parts.insert(.rs) }
        return parts
    }
}

/// SVG path data as the pad's outlines are written (absolute M L H V C Q Z), into a Path.
enum SVGPath {
    private static let tokens = try! NSRegularExpression(pattern: "[MLHVCQZ]|-?(?:\\d+\\.?\\d*|\\.\\d+)")

    static func path(_ data: String) -> Path {
        let parts = tokens.matches(in: data, range: NSRange(data.startIndex..., in: data)).compactMap {
            Range($0.range, in: data).map { String(data[$0]) }
        }
        var path = Path()
        var i = 0
        var command = "M"
        var point = CGPoint.zero
        func number() -> CGFloat {
            defer { i += 1 }
            return i < parts.count ? CGFloat(Double(parts[i]) ?? 0) : 0
        }
        func next() -> CGPoint { CGPoint(x: number(), y: number()) }
        while i < parts.count {
            if parts[i].first?.isLetter == true {
                command = parts[i]
                i += 1
                if command == "Z" { path.closeSubpath() }
                continue
            }
            switch command {
            case "M": point = next(); path.move(to: point); command = "L"
            case "L": point = next(); path.addLine(to: point)
            case "H": point.x = number(); path.addLine(to: point)
            case "V": point.y = number(); path.addLine(to: point)
            case "C":
                let (c1, c2) = (next(), next())
                point = next()
                path.addCurve(to: point, control1: c1, control2: c2)
            case "Q":
                let control = next()
                point = next()
                path.addQuadCurve(to: point, control: control)
            default: i += 1
            }
        }
        return path
    }
}

/// The controller from the front, in glass, on a 520 × 330 grid: pressed parts light up in sodium,
/// the sticks move, the triggers aren't drawn (the chips above show them). Without a controller a
/// calm outline. One Canvas, redrawn only when a reading changes.
struct PadDrawing: View {
    let layout: PadLayout?
    let reading: PadReading

    static let size = CGSize(width: 520, height: 330)

    private static let psBody = SVGPath.path("M260 60L372 60C420 60 452 66 470 80C492 96 500 130 502 170C506 220 504 268 488 296C472 322 436 322 420 300C404 280 394 260 378 248C354 232 302 230 260 230C218 230 166 232 142 248C126 260 116 280 100 300C84 322 48 322 32 296C16 268 14 220 18 170C20 130 28 96 50 80C68 66 100 60 148 60Z")
    private static let psCore = SVGPath.path("M100 76L420 76C448 78 470 100 474 140C478 176 462 204 438 220C424 230 406 238 390 244C364 230 304 226 260 226C216 226 156 230 130 244C114 238 96 230 82 220C58 204 42 176 46 140C50 100 72 78 100 76Z")
    private static let psTouchpad = SVGPath.path("M185 66L335 66Q344 66 343 75L338 146Q337 156 327 156L193 156Q183 156 182 146L177 75Q176 66 185 66Z")
    private static let psLightBar = [SVGPath.path("M171 76L176 148Q177 160 189 162"), SVGPath.path("M349 76L344 148Q343 160 331 162")]
    private static let xbBody = SVGPath.path("M260 66C300 66 336 58 372 58C420 58 458 70 478 100C498 130 506 176 504 218C502 262 488 300 456 308C430 314 410 300 396 278C384 258 372 246 352 238C324 230 292 232 260 232C228 232 196 230 168 238C148 246 136 258 124 278C110 300 90 314 64 308C32 300 18 262 16 218C14 176 22 130 42 100C62 70 100 58 148 58C184 58 220 66 260 66Z")

    private struct Places {
        let dpad: CGPoint, face: CGPoint, ls: CGPoint, rs: CGPoint, home: CGPoint, homeRadius: CGFloat, select: CGPoint, start: CGPoint
    }
    private static let ps = Places(dpad: CGPoint(x: 118, y: 126), face: CGPoint(x: 402, y: 126), ls: CGPoint(x: 196, y: 192), rs: CGPoint(x: 324, y: 192),
                                   home: CGPoint(x: 260, y: 190), homeRadius: 10, select: CGPoint(x: 160, y: 86), start: CGPoint(x: 360, y: 86))
    private static let xb = Places(dpad: CGPoint(x: 196, y: 188), face: CGPoint(x: 398, y: 122), ls: CGPoint(x: 122, y: 124), rs: CGPoint(x: 324, y: 188),
                                   home: CGPoint(x: 260, y: 94), homeRadius: 15, select: CGPoint(x: 224, y: 132), start: CGPoint(x: 296, y: 132))

    private static let lit = Color(red: 1, green: 0.835, blue: 0.604)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / Self.size.width, y: size.height / Self.size.height)
            draw(in: &context)
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(layout == nil ? L10n.t("Outline of a controller") : L10n.t("Your controller – pressed buttons light up"))
    }

    private func draw(in context: inout GraphicsContext) {
        let outline = layout == nil
        let playstation = layout != .xbox
        let places = playstation ? Self.ps : Self.xb
        let body = playstation ? Self.psBody : Self.xbBody

        if !outline {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 12))
                layer.fill(Path(ellipseIn: CGRect(x: 60, y: 317, width: 400, height: 18)), with: .color(.black.opacity(0.55)))
            }
            context.fill(body, with: .linearGradient(Gradient(colors: [.white.opacity(0.13), .white.opacity(0.035)]),
                                                     startPoint: CGPoint(x: 0, y: 56), endPoint: CGPoint(x: 0, y: 322)))
            context.stroke(body, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.55), location: 0), .init(color: .white.opacity(0.14), location: 0.35),
                                                                        .init(color: .white.opacity(0.06), location: 0.65), .init(color: .white.opacity(0.22), location: 1)]),
                                                       startPoint: CGPoint(x: 0, y: 56), endPoint: CGPoint(x: 0, y: 322)), lineWidth: 1.5)
            if playstation {
                context.fill(Self.psCore, with: .linearGradient(Gradient(colors: [.black.opacity(0.5), .black.opacity(0.32)]),
                                                                startPoint: CGPoint(x: 0, y: 76), endPoint: CGPoint(x: 0, y: 244)))
                context.stroke(Self.psCore, with: .color(.white.opacity(0.1)), lineWidth: 1)
            }
            // The upper half catches the light, like all glass in the app.
            context.drawLayer { layer in
                layer.clip(to: body)
                layer.fill(Path(CGRect(x: 0, y: 56, width: 520, height: 130)),
                           with: .linearGradient(Gradient(colors: [.white.opacity(0.1), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: 56), endPoint: CGPoint(x: 0, y: 115)))
            }
        } else {
            context.fill(body, with: .color(.white.opacity(0.015)))
            context.stroke(body, with: .color(.white.opacity(0.26)), lineWidth: 1.5)
        }

        if playstation {
            element(Self.psTouchpad, lit: reading.pressed(.touch), in: &context, rest: .white.opacity(0.09), restStroke: .white.opacity(0.28))
            if !outline {
                for bar in Self.psLightBar {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Theme.sodium.opacity(0.75), radius: 5))
                        layer.stroke(bar, with: .color(Theme.sodium.opacity(0.85)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    }
                }
            }
            context.stroke(Path(roundedRect: CGRect(x: 248, y: 212, width: 24, height: 5), cornerRadius: 2.5),
                           with: .color(.white.opacity(outline ? 0.12 : 0.22)), lineWidth: 1)
        } else {
            context.stroke(Path(roundedRect: CGRect(x: 253, y: 138, width: 14, height: 9), cornerRadius: 4.5),
                           with: .color(.white.opacity(outline ? 0.12 : 0.22)), lineWidth: 1.2)
        }

        dpad(places.dpad, in: &context)
        faceButtons(places.face, playstation: playstation, in: &context)
        stick(places.ls, axis: reading.left, pressed: reading.pressed(.l3), in: &context)
        stick(places.rs, axis: reading.right, pressed: reading.pressed(.r3), in: &context)

        for (part, center) in [(PadPart.select, places.select), (.start, places.start)] {
            let shape = playstation ? Path(roundedRect: CGRect(x: center.x - 5, y: center.y - 10, width: 10, height: 20), cornerRadius: 5)
                : Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
            element(shape, lit: reading.pressed(part), in: &context)
            if !playstation && !outline {
                let ink = glyphInk(reading.pressed(part))
                var mark = Path()
                if part == .select {
                    mark.addRect(CGRect(x: center.x - 4, y: center.y - 2, width: 5, height: 5))
                    mark.move(to: CGPoint(x: center.x - 1, y: center.y - 2))
                    mark.addLine(to: CGPoint(x: center.x - 1, y: center.y - 5))
                    mark.addLine(to: CGPoint(x: center.x + 4, y: center.y - 5))
                    mark.addLine(to: CGPoint(x: center.x + 4, y: center.y))
                    mark.addLine(to: CGPoint(x: center.x + 1, y: center.y))
                } else {
                    for dy in [-3.0, 0, 3] {
                        mark.move(to: CGPoint(x: center.x - 4, y: center.y + dy))
                        mark.addLine(to: CGPoint(x: center.x + 4, y: center.y + dy))
                    }
                }
                context.stroke(mark, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }

        let home = places.home
        element(Path(ellipseIn: CGRect(x: home.x - places.homeRadius, y: home.y - places.homeRadius,
                                       width: places.homeRadius * 2, height: places.homeRadius * 2)),
                lit: reading.pressed(.home), in: &context)
    }

    /// A button: glass at rest, sodium with its glow when pressed, only a line without a controller.
    private func element(_ shape: Path, lit: Bool, in context: inout GraphicsContext,
                         rest: Color = .white.opacity(0.07), restStroke: Color = .white.opacity(0.3)) {
        if layout == nil {
            context.stroke(shape, with: .color(.white.opacity(0.18)), lineWidth: 1.3)
        } else if lit {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Theme.sodium.opacity(0.75), radius: 5))
                layer.fill(shape, with: .color(Theme.sodium))
            }
            context.stroke(shape, with: .color(Self.lit), lineWidth: 1.3)
        } else {
            context.fill(shape, with: .color(rest))
            context.stroke(shape, with: .color(restStroke), lineWidth: 1.3)
        }
    }

    private func glyphInk(_ lit: Bool) -> Color { lit ? Theme.night : Theme.ink.opacity(0.82) }

    private func dpad(_ c: CGPoint, in context: inout GraphicsContext) {
        let arms: [(PadPart, CGRect, [CGPoint])] = [
            (.up, CGRect(x: c.x - 11, y: c.y - 34, width: 22, height: 25), [CGPoint(x: c.x - 4, y: c.y - 18), CGPoint(x: c.x, y: c.y - 23), CGPoint(x: c.x + 4, y: c.y - 18)]),
            (.down, CGRect(x: c.x - 11, y: c.y + 9, width: 22, height: 25), [CGPoint(x: c.x - 4, y: c.y + 18), CGPoint(x: c.x, y: c.y + 23), CGPoint(x: c.x + 4, y: c.y + 18)]),
            (.left, CGRect(x: c.x - 34, y: c.y - 11, width: 25, height: 22), [CGPoint(x: c.x - 18, y: c.y - 4), CGPoint(x: c.x - 23, y: c.y), CGPoint(x: c.x - 18, y: c.y + 4)]),
            (.right, CGRect(x: c.x + 9, y: c.y - 11, width: 25, height: 22), [CGPoint(x: c.x + 18, y: c.y - 4), CGPoint(x: c.x + 23, y: c.y), CGPoint(x: c.x + 18, y: c.y + 4)]),
        ]
        for (part, rect, tip) in arms {
            let lit = reading.pressed(part)
            element(Path(roundedRect: rect, cornerRadius: 6), lit: lit, in: &context)
            if layout != nil {
                var chevron = Path()
                chevron.addLines(tip)
                context.stroke(chevron, with: .color(glyphInk(lit)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func faceButtons(_ c: CGPoint, playstation: Bool, in context: inout GraphicsContext) {
        for (part, dx, dy) in [(PadPart.y, 0.0, -28.0), (.b, 28, 0), (.a, 0, 28), (.x, -28, 0)] {
            let center = CGPoint(x: c.x + dx, y: c.y + dy)
            let lit = reading.pressed(part)
            element(Path(ellipseIn: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)), lit: lit, in: &context)
            guard layout != nil else { continue }
            let ink = glyphInk(lit)
            if playstation {
                let s: CGFloat = 5.4
                var glyph = Path()
                switch part {
                case .a:
                    glyph.move(to: CGPoint(x: center.x - s, y: center.y - s)); glyph.addLine(to: CGPoint(x: center.x + s, y: center.y + s))
                    glyph.move(to: CGPoint(x: center.x + s, y: center.y - s)); glyph.addLine(to: CGPoint(x: center.x - s, y: center.y + s))
                case .b: glyph.addEllipse(in: CGRect(x: center.x - s * 1.05, y: center.y - s * 1.05, width: s * 2.1, height: s * 2.1))
                case .x: glyph.addRoundedRect(in: CGRect(x: center.x - s * 0.95, y: center.y - s * 0.95, width: s * 1.9, height: s * 1.9), cornerSize: CGSize(width: 0.6, height: 0.6))
                default:
                    glyph.move(to: CGPoint(x: center.x, y: center.y - s * 1.05))
                    glyph.addLine(to: CGPoint(x: center.x + s * 1.1, y: center.y + s * 0.85))
                    glyph.addLine(to: CGPoint(x: center.x - s * 1.1, y: center.y + s * 0.85))
                    glyph.closeSubpath()
                }
                context.stroke(glyph, with: .color(ink), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            } else {
                context.draw(Text(part.rawValue.uppercased()).font(.drawing(size: 14, weight: .heavy)).foregroundColor(ink), at: center)
            }
        }
    }

    private func stick(_ c: CGPoint, axis: CGPoint, pressed: Bool, in context: inout GraphicsContext) {
        let outline = layout == nil
        let base = Path(ellipseIn: CGRect(x: c.x - 31, y: c.y - 31, width: 62, height: 62))
        context.fill(base, with: .color(outline ? .clear : .black.opacity(0.22)))
        context.stroke(base, with: .color(.white.opacity(outline ? 0.18 : 0.2)), lineWidth: 1.3)
        let moved = hypot(axis.x, axis.y) > 0.25
        if !outline && moved {
            let dot = CGPoint(x: c.x + axis.x * 22, y: c.y + axis.y * 22)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Theme.sodium.opacity(0.75), radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(Theme.sodium))
            }
        }
        let cap = CGPoint(x: c.x + axis.x * 10, y: c.y + axis.y * 10)
        let capPath = Path(ellipseIn: CGRect(x: cap.x - 21, y: cap.y - 21, width: 42, height: 42))
        if pressed || outline {
            element(capPath, lit: pressed, in: &context)
        } else {
            context.fill(capPath, with: .color(.white.opacity(0.1)))
            context.stroke(capPath, with: .color(moved ? Theme.sodium : .white.opacity(0.38)), lineWidth: moved ? 2 : 1.3)
        }
        if !outline {
            context.stroke(Path(ellipseIn: CGRect(x: cap.x - 13, y: cap.y - 13, width: 26, height: 26)),
                           with: .color(pressed ? Theme.night.opacity(0.35) : .white.opacity(0.1)), lineWidth: 1)
        }
    }
}
