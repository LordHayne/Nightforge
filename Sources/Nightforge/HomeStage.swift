import SwiftUI

/// Home's stage (design 2d): the rail's games as covers in depth – the chosen one big in front, the
/// next ones turned away into the dark, one or two behind it on the left – and "All games" last.
/// ← →, the pad and two fingers sideways move it (LibraryModel.move, InputRouter); a click on a
/// cover behind picks it, on the front one opens its page. Nothing on it moves while it rests.
struct HomeStage: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var glow = Theme.sodium

    /// Per step from the front: how far (in cover widths), how small, how dark, how visible.
    private static let offsets: [CGFloat] = [0, 0.79, 1.16, 1.54]
    private static let scales: [CGFloat] = [1, 0.92, 0.87, 0.82]
    private static let shades: [Double] = [0, 0.6, 0.68, 0.74]
    private static let seen: [Double] = [1, 0.85, 0.5, 0.25]
    /// How many show on each side of the front one.
    private static let before = 2
    private static let after = 3

    var body: some View {
        GeometryReader { geo in
            let height = max(240, min(480, geo.size.height - 150))
            let width = height / 1.5
            let center = geo.size.width * 0.44
            let top = max(16, (geo.size.height - height - 110) / 2)
            let place = model.homePlace
            let count = model.homeRail.count + 1
            ZStack(alignment: .topLeading) {
                floor(center: center, y: top + height, width: width, span: geo.size.width)
                ForEach(places(around: place, count: count), id: \.self) { item in
                    cover(item, at: item.place - place, width: width, height: height)
                        .offset(x: center - width / 2 + offset(item.place - place, width: width), y: top)
                        .zIndex(Double(100 - abs(item.place - place)))
                        .transition(.opacity)
                }
                indicator(place: place, count: count)
                    .frame(width: 420)
                    .position(x: center, y: top + height + 62)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // The far covers fade out at the edges instead of being cut off.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .modifier(SwipeArea(kind: .stage))
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: model.homePlace)
        .task(id: model.heroGame?.id) {
            guard let game = model.heroGame else { glow = Theme.sodium; return }
            if let light = await ArtworkStore.shared.stageBackdrop(for: game) { glow = Color(nsColor: light.glow) }
        }
    }

    /// One place on the stage: a game of the rail, or the "All games" tile after them.
    private struct Item: Hashable {
        let place: Int
        let id: String
    }

    private func places(around place: Int, count: Int) -> [Item] {
        let range = max(0, place - Self.before)...min(count - 1, place + Self.after)
        return range.map { place in
            Item(place: place, id: place < model.homeRail.count ? model.games[model.homeRail[place]].id : "stage.allGames")
        }
    }

    private func offset(_ distance: Int, width: CGFloat) -> CGFloat {
        CGFloat(distance.signum()) * Self.offsets[min(abs(distance), 3)] * width
    }

    @ViewBuilder private func cover(_ item: Item, at distance: Int, width: CGFloat, height: CGFloat) -> some View {
        let step = min(abs(distance), 3)
        let front = distance == 0
        // A cover behind is picked; the front one opens its page, the last tile the library.
        let press = {
            if model.quickMenu != nil {
                // A long click that opened it, let go.
            } else if !front {
                model.selectOnHome(place: item.place)
            } else if item.place == model.homeRail.count {
                model.goLibrary()
            } else {
                model.openDetail()
            }
        }
        Group {
            if item.place < model.homeRail.count {
                let index = model.homeRail[item.place]
                let game = model.games[index]
                StageCover(game: game, front: front, width: width, shade: Self.shades[step],
                           progress: { if case .downloading(let fraction) = game.shown.install { return fraction ?? 0 } else { return nil } }())
                    .modifier(CardMenuButton(shown: front) { model.openQuickMenu(at: index) })
                    .modifier(GameCardMenu(game: game))
            } else {
                AllGamesStageTile(count: model.visibleCount, front: front, width: width)
            }
        }
        .rotation3DEffect(.degrees(front ? 0 : Double(-distance.signum()) * 56), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .scaleEffect(Self.scales[step])
        .opacity(Self.seen[step])
        .contentShape(Rectangle())
        .onTapGesture(perform: press)
        .modifier(LongClick {
            if item.place < model.homeRail.count { model.openQuickMenu(at: model.homeRail[item.place]) }
        })
        // VoiceOver and AXPress do what a click does.
        .accessibilityAction(.default, press)
    }

    /// The cover's colour pools on the floor under it – a soft shimmer, no mirror image – and a
    /// faint line where the covers stand.
    private func floor(center: CGFloat, y: CGFloat, width: CGFloat, span: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.4), glow.opacity(0)], center: .center, startRadius: 0, endRadius: width * 0.9))
                .frame(width: width * 1.75, height: 84)
                .position(x: center, y: y + 16)
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.3), glow.opacity(0)], center: .center, startRadius: 0, endRadius: width * 0.45))
                .frame(width: width * 0.9, height: 48)
                .position(x: center, y: y + 30)
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: span * 0.84, height: 1)
                .position(x: span / 2, y: y + 4)
        }
        .allowsHitTesting(false)
    }

    /// "To start with · 2 of 11" between two arrows.
    private func indicator(place: Int, count: Int) -> some View {
        HStack(spacing: 16) {
            StageArrow(symbol: "chevron.left", help: L10n.t("Previous game"), disabled: place == 0) { model.move(-1) }
            Text(L10n.t("%@ · %ld of %ld", section, place + 1, count))
                .font(size: 13, weight: .medium).monospacedDigit()
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(minWidth: 220)
            StageArrow(symbol: "chevron.right", help: L10n.t("Next game"), disabled: place >= count - 1) { model.move(1) }
        }
    }

    private var section: String {
        switch model.homeStartersFrom {
        case nil: return L10n.t("Continue playing")
        case 0?: return L10n.t("To start with")
        case _?: return L10n.t("Continue playing, then to start with")
        }
    }
}

/// A cover on the stage. In front: in full colour with its badges and the selection ring; behind:
/// darkened and muted, so only the front one counts.
private struct StageCover: View {
    let game: Game
    let front: Bool
    let width: CGFloat
    let shade: Double
    /// A download's progress, along the bottom edge.
    let progress: Double?
    @State private var cover: NSImage?

    var body: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)
                if front {
                    Text(game.name)
                        .displayFont(22)
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .saturation(front ? 1 : 0.45)
        .overlay(Color.black.opacity(shade))
        .overlay(alignment: .topTrailing) {
            if front && game.platform == .mac {
                Text("MAC")
                    .displayFont(10.5)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.night.opacity(0.8), in: Capsule())
                    .padding(12)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if front && game.controller != .none {
                Image(systemName: game.controller == .full ? "gamecontroller.fill" : "gamecontroller")
                    .font(size: 16, weight: .bold, scales: false)
                    .foregroundStyle(game.controller == .full ? Theme.sodium : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Theme.night.opacity(0.82), in: Capsule())
                    .padding(12)
                    .help(game.controller.help)
            }
        }
        .overlay(alignment: .bottom) {
            if front, let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.night.opacity(0.75))
                        Rectangle().fill(Theme.sodium).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.sodium, lineWidth: front ? 3 : 0))
        .shadow(color: .black.opacity(front ? 0.6 : 0.3), radius: front ? 34 : 10, y: front ? 20 : 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(front ? [.isButton, .isSelected] : .isButton)
        .task(id: game.id) {
            cover = await ArtworkStore.shared.image(for: game, kind: .cover)
        }
    }
}

/// The stage's last place: every game, one step away.
private struct AllGamesStageTile: View {
    let count: Int
    let front: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "square.grid.2x2")
                .font(size: 34, weight: .semibold, scales: false)
                .foregroundStyle(Theme.ink.opacity(0.85))
            Spacer()
            Text(L10n.t("All %ld games", count))
                .displayFont(26)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(L10n.t("In your library"))
                Image(systemName: "chevron.right").font(size: 11, weight: .bold)
            }
            .font(size: 14, weight: .medium)
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: width, height: width * 1.5, alignment: .leading)
        .background(GlassBackground(glass: .regular, shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.sodium, lineWidth: front ? 3 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("All games, %ld in your library", count))
        .accessibilityAddTraits(front ? [.isButton, .isSelected] : .isButton)
    }
}

/// The arrows beside the stage's counter: for the mouse (the pad and keys move the stage themselves).
private struct StageArrow: View {
    let symbol: String
    let help: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(size: 12, weight: .bold, scales: false)
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(GlassButtonStyle(shape: Circle()))
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
