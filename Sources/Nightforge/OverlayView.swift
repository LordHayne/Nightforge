import SwiftUI

/// The overlay over a game: a side bar on the right, the game left in view – no dimming and no blur,
/// nothing that moves. "Not starting?" has no picture to keep, so it stays a question in the middle.
struct OverlayView: View {
    @ObservedObject var state: GameOverlay.State

    var body: some View {
        GeometryReader { geometry in
            let m = OverlayMetrics(height: geometry.size.height)
            ZStack(alignment: .topTrailing) {
                if state.centered {
                    centered
                } else {
                    sideBar(m)
                        .padding(.top, m(54))
                        .padding(.trailing, m(96))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea()
    }

    // MARK: - Side bar

    private func sideBar(_ m: OverlayMetrics) -> some View {
        VStack(alignment: .leading, spacing: m(20)) {
            switch state.step {
            case .confirmQuit: question(title: m(32), detail: m(24), metrics: m)
            case .quitting: Text(L10n.t("Quitting %@ …", state.game)).font(size: m(30), weight: .semibold)
            default: menu(m)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, m(34))
        .padding(.vertical, m(32))
        .frame(width: m(600), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: m(28), style: .continuous).fill(Theme.night.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: m(28), style: .continuous).strokeBorder(.white.opacity(0.14)))
    }

    @ViewBuilder private func menu(_ m: OverlayMetrics) -> some View {
        let tiles = OverlayTiles.visible(in: state.context)
        VStack(alignment: .leading, spacing: m(8)) {
            HStack(alignment: .firstTextBaseline, spacing: m(16)) {
                Text(state.game)
                    .displayFont(m(44))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                zone(.corner, tiles, m)
            }
            zone(.head, tiles, m)
        }
        // Wine keeps the device it opened: a change in the menu bar reaches the game's next start.
        if let device = state.soundStaysOn {
            Text(L10n.t("The game plays its sound on %@ until it starts again.", device))
                .font(size: m(24))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        // A controller came after the start: many games only look for one then (Left 4 Dead 2, 7.11.).
        if state.lateController {
            VStack(alignment: .leading, spacing: m(6)) {
                Label(L10n.t("Controller connected after the start"), systemImage: "gamecontroller.fill")
                    .font(size: m(26), weight: .semibold)
                    .foregroundStyle(Theme.sodium)
                Text(L10n.t("Some games only look for controllers when they start. A restart takes about a minute; your progress stays where the game saves it."))
                    .font(size: m(24))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        zone(.status, tiles, m)
        VStack(spacing: m(18)) {
            if state.lateController {
                choice("overlay.restart", L10n.t("Restart Game"), tint: Theme.sodium, preferred: true, m) { GameOverlay.restart() }
            }
            choice("overlay.continue", L10n.t("Continue Playing"), tint: state.lateController ? nil : Theme.sodium,
                   preferred: !state.lateController, m) { GameOverlay.resume() }
            choice("overlay.quit", L10n.t("Quit Game"), m) { GameOverlay.askQuit() }
            choice("overlay.nightforge", L10n.t("Go to Nightforge"), m) { GameOverlay.toNightforge() }
        }
        if tiles.contains(where: { $0.zone >= .control }) {
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            zone(.control, tiles, m)
            zone(.tool, tiles, m)
        }
        // How it closes, and how it opens next time.
        HStack(spacing: m(18)) {
            HStack(spacing: m(8)) {
                Image(systemName: state.symbols.back)
                Text(L10n.t("Continue Playing"))
            }
            Spacer(minLength: 0)
            HStack(spacing: m(8)) {
                OverlayChord(symbols: state.symbols)
                Text(L10n.t("Hold: this menu"))
            }
        }
        .font(size: m(24), weight: .medium)
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The blocks of one zone, or the sentence for one that can't be used now.
    @ViewBuilder private func zone(_ zone: OverlayZone, _ tiles: [any OverlayTile], _ m: OverlayMetrics) -> some View {
        ForEach(tiles.filter { $0.zone == zone }, id: \.id) { tile in
            switch tile.availability(in: state.context) {
            case .ready:
                tile.view(in: state.context, metrics: m)
            case .nextStart(let reason), .needsRight(let reason):
                VStack(alignment: .leading, spacing: m(4)) {
                    Text(tile.title).font(size: m(26), weight: .semibold)
                    Text(reason).font(size: m(24)).foregroundStyle(Theme.muted)
                }
            case .hidden:
                EmptyView()
            }
        }
    }

    // MARK: - In the middle

    /// The game runs but has shown nothing for a minute (LibraryModel's curtain).
    private var centered: some View {
        ZStack {
            // Dimmed, not blurred: a live blur over the whole picture would cost the game frames.
            Color.black.opacity(0.62)
            VStack(spacing: 14) {
                switch state.step {
                case .notStarting: notStarting
                case .confirmQuit: question(title: 22, detail: 14, metrics: nil)
                case .quitting: Text(L10n.t("Quitting %@ …", state.game)).font(size: 20, weight: .semibold)
                default: EmptyView()
                }
            }
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(36)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14)))
        }
    }

    @ViewBuilder private var notStarting: some View {
        Text(L10n.t("%@ isn't starting?", state.game))
            .font(size: 22, weight: .semibold)
        Text(L10n.t("It runs, but hasn't shown a picture yet. Some games take long the first time."))
            .font(size: 14)
            .foregroundStyle(Theme.muted)
        VStack(spacing: 12) {
            choice("overlay.wait", L10n.t("Keep Waiting"), tint: Theme.sodium, preferred: true, nil) { GameOverlay.resume() }
            choice("overlay.nightforge", L10n.t("Go to Nightforge"), nil) { GameOverlay.toNightforge() }
            choice("overlay.quit", L10n.t("Quit Game"), nil) { GameOverlay.askQuit() }
        }
        .padding(.top, 10)
    }

    @ViewBuilder private func question(title: CGFloat, detail: CGFloat, metrics m: OverlayMetrics?) -> some View {
        Text(L10n.t("Quit %@?", state.game))
            .font(size: title, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
        Text(L10n.t("What wasn't saved is lost. A game that no longer responds ends as well."))
            .font(size: detail)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: m.map { $0(12) } ?? 12) {
            choice("overlay.cancel", L10n.t("Cancel"), preferred: true, m) { GameOverlay.back() }
            choice("overlay.confirmQuit", L10n.t("Quit Game"), tint: Theme.danger, m) { GameOverlay.quit() }
        }
        .padding(.top, m.map { $0(10) } ?? 10)
    }

    /// `metrics`: the side bar's sizes, nil for the question in the middle.
    private func choice(_ id: String, _ title: String, tint: Color? = nil, preferred: Bool = false, _ metrics: OverlayMetrics?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(OverlayButtonStyle(tint: tint, metrics: metrics))
            .padFocus(id, preferred: preferred, ring: false, activate: action)
            .modifier(OverlayFocusRing(id: id, width: metrics.map { $0(6) } ?? 3, gap: metrics.map { $0(5) } ?? 5))
    }
}

/// The highlight, thicker than elsewhere: it has to be seen from the sofa.
private struct OverlayFocusRing: ViewModifier {
    let id: String
    let width: CGFloat
    let gap: CGFloat
    @ObservedObject private var focus = PadFocus.shared

    func body(content: Content) -> some View {
        content.overlay {
            if focus.focused == id {
                Capsule(style: .circular)
                    .stroke(Theme.sodium, lineWidth: width)
                    .padding(-gap)
                    .shadow(color: Theme.sodium.opacity(0.5), radius: 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Solid, without the glass's frosted backdrop, which would blur the game behind live.
private struct OverlayButtonStyle: ButtonStyle {
    var tint: Color?
    var metrics: OverlayMetrics?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size: metrics.map { $0(28) } ?? 16, weight: .semibold)
            .foregroundStyle(tint != nil ? Theme.night : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.map { $0(72) } ?? 46)
            .background(Capsule(style: .circular).fill(tint ?? .white.opacity(0.1)))
            .overlay(Capsule(style: .circular).strokeBorder(.white.opacity(tint != nil ? 0.3 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
