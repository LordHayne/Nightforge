import AppKit

/// Nightforge's brand art, drawn with CoreGraphics: the N in brushed metal with its blue light
/// seam, and the night it stands on. One source for the loading screen (GameBackdrop) and for
/// scripts/render-brand.swift (the app icon, the README banner, the DMG window).
enum BrandArt {
    static let seamBlue = NSColor(srgbRed: 0.18, green: 0.48, blue: 1.0, alpha: 1)
    /// The wordmark's light grey and the blue-grey of the line under it ("EVERY GAME. ONE PLACE.").
    static let wordmark = NSColor(white: 0.9, alpha: 1)
    static let tagline = NSColor(srgbRed: 0.55, green: 0.66, blue: 0.86, alpha: 1)

    /// The three pieces of the N in a 332 × 440 box (origin top left), from the original design.
    static let pieces: [[CGPoint]] = [
        // diagonal slab, with the upper half of the left stem
        [CGPoint(x: 0, y: 0), CGPoint(x: 332, y: 308), CGPoint(x: 332, y: 440), CGPoint(x: 49, y: 170), CGPoint(x: 0, y: 128)],
        // lower part of the left stem
        [CGPoint(x: 0, y: 170), CGPoint(x: 82, y: 236), CGPoint(x: 82, y: 338), CGPoint(x: 0, y: 432)],
        // right stem
        [CGPoint(x: 249, y: 100), CGPoint(x: 332, y: 24), CGPoint(x: 332, y: 280), CGPoint(x: 249, y: 204)],
    ]
    /// The light seam runs along the slab's lower edge.
    static let seam = (CGPoint(x: 49, y: 170), CGPoint(x: 332, y: 440))
    static let glyphSize = CGSize(width: 332, height: 440)
    /// How far the shadow and the seam's glow reach beyond the N, in the design's units.
    static let reach: CGFloat = 80

    /// Same streaks on every run, so re-rendering doesn't change images that didn't change.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {  // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// The N with its top left corner at `origin`, `scale` × the design size. `seam: false` leaves
    /// its light out, for a seam of its own on top (`drawSeam`) that can pulse. `glow`: the shadow's
    /// and the light's reach × their design size – CoreGraphics draws them in pixels, whatever the scale.
    static func drawMark(_ context: CGContext, origin: CGPoint, scale: CGFloat, seam: Bool = true, glow: CGFloat = 1) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for (index, points) in pieces.enumerated() {
            let shape = path(points)
            // Drop shadow for depth.
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 10 * glow), blur: 28 * glow, color: NSColor.black.withAlphaComponent(0.7).cgColor)
            context.addPath(shape)
            context.setFillColor(NSColor(white: 0.35, alpha: 1).cgColor)
            context.fillPath()
            context.restoreGState()

            // Brushed metal: a cool diagonal gradient plus fine streaks.
            context.saveGState()
            context.addPath(shape)
            context.clip()
            let metal = CGGradient(colorsSpace: colorSpace, colors: [
                NSColor(srgbRed: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor,
                NSColor(srgbRed: 0.55, green: 0.58, blue: 0.63, alpha: 1).cgColor,
                NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 0.55, 1])!
            let box = shape.boundingBox
            context.drawLinearGradient(metal, start: CGPoint(x: box.minX, y: box.minY - (index == 0 ? 0 : 60)),
                                       end: CGPoint(x: box.maxX, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            var generator = SeededGenerator(seed: UInt64(index) + 1)
            for _ in 0..<260 {
                let y = CGFloat.random(in: -440...880, using: &generator)
                context.setStrokeColor(NSColor(white: Bool.random(using: &generator) ? 1 : 0, alpha: CGFloat.random(in: 0.02...0.07, using: &generator)).cgColor)
                context.setLineWidth(CGFloat.random(in: 0.5...1.6, using: &generator))
                context.move(to: CGPoint(x: -40, y: y))
                context.addLine(to: CGPoint(x: 372, y: y + 345))
                context.strokePath()
            }
            context.restoreGState()

            // Bevel: light top edge, dark outline.
            context.addPath(shape)
            context.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor)
            context.setLineWidth(2)
            context.strokePath()
        }
        if seam { seamLight(context, glow: glow) }
        context.restoreGState()
    }

    /// The N's light seam alone, where `drawMark` would draw it.
    static func drawSeam(_ context: CGContext, origin: CGPoint, scale: CGFloat, glow: CGFloat = 1) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        seamLight(context, glow: glow)
        context.restoreGState()
    }

    /// The light seam: a wide blue glow, then a bright core.
    private static func seamLight(_ context: CGContext, glow: CGFloat) {
        context.setLineCap(.round)
        for (width, alpha, blur) in [(14.0, 0.35, 40.0), (6.0, 0.8, 18.0), (2.2, 1.0, 6.0)] {
            context.saveGState()
            context.setShadow(offset: .zero, blur: blur * glow, color: seamBlue.cgColor)
            context.setStrokeColor(seamBlue.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width)
            context.move(to: seam.0)
            context.addLine(to: seam.1)
            context.strokePath()
            context.restoreGState()
        }
        context.setStrokeColor(NSColor(srgbRed: 0.75, green: 0.87, blue: 1, alpha: 0.95).cgColor)
        context.setLineWidth(1.1)
        context.move(to: seam.0)
        context.addLine(to: seam.1)
        context.strokePath()
    }

    static func nightBackground(_ context: CGContext, in rect: CGRect) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1).cgColor,
            NSColor(srgbRed: 0.025, green: 0.03, blue: 0.045, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        // A faint blue haze behind the mark.
        let haze = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            seamBlue.withAlphaComponent(0.16).cgColor, seamBlue.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(haze, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                                   endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: min(rect.width, rect.height) * 0.55, options: [])
    }

    /// A picture of `size` points at `scale` pixels per point, drawn with the origin top left like
    /// the design's coordinates.
    static func image(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(context)
        return context.makeImage()
    }
}
