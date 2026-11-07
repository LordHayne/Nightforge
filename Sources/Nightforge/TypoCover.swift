import SwiftUI

/// A game without cover art: its name set big and heavy at the bottom left, on a night-blue card
/// with a warm light in Nightforge's own colour at the top left (canvas 7.11., "Typo-Karte"). No
/// picture of anyone else's – Blizzard allows its art to no launcher, and some games have none.
/// It scales with the card: the canvas's 252-point card is the measure.
struct TypoCover: View {
    /// nil where the name already shows big beside the card (Home's front cover, under the hero's title).
    var name: String?
    /// What Nightforge really knows about it (`line(_:)`); nil leaves the line out.
    var line: String?
    let width: CGFloat
    /// Room kept free at the bottom for the cover's own badges there (controller, download, update).
    var bottomRoom: CGFloat = 0

    static let top = Color(red: 0x23 / 255, green: 0x30 / 255, blue: 0x44 / 255)  // #233044

    static func nameSize(width: CGFloat) -> CGFloat { (width * 34 / 252).rounded() }
    static func lineSize(width: CGFloat) -> CGFloat { max(10, (width * 13 / 252).rounded()) }
    static func inset(width: CGFloat) -> CGFloat { (width * 22 / 252).rounded() }

    /// Developer and genre where Nightforge has them ("Blizzard · Card game"); nil with neither.
    static func line(_ info: GameInfo?) -> String? {
        let parts = [info?.developers.first, info?.genres.first].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Self.background(width: width)
            if name != nil || line != nil {
                VStack(alignment: .leading, spacing: (width * 8 / 252).rounded()) {
                    if let name {
                        Text(name)
                            .font(Theme.display(Self.nameSize(width: width)))
                            .lineSpacing(-Self.nameSize(width: width) * 0.12)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(4)
                            .minimumScaleFactor(0.55)  // a long word shrinks instead of breaking
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let line {
                        Text(line)
                            .font(.system(size: Self.lineSize(width: width), weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
                .padding(Self.inset(width: width))
                .padding(.bottom, bottomRoom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: width, height: width * 1.5)
    }

    /// `linear-gradient(160deg, #233044, night 70%)` under `radial-gradient(circle at 30% 20%,
    /// sodium 16 %, transparent 55%)`: both drawn once, nothing moves. Alone for the small covers
    /// beside a name (downloads, Welcome back).
    static func background(width: CGFloat) -> some View {
        let height = width * 1.5
        // The farthest corner from the light, as CSS measures a circle's 55 %.
        let reach = hypot(width * 0.7, height * 0.8) * 0.55
        return ZStack {
            LinearGradient(stops: [.init(color: top, location: 0), .init(color: Theme.night, location: 0.7)],
                           startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97))
            RadialGradient(colors: [Theme.sodium.opacity(0.16), Theme.sodium.opacity(0)], center: UnitPoint(x: 0.3, y: 0.2),
                           startRadius: 0, endRadius: reach)
        }
    }
}
