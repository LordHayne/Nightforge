import AppKit
import SwiftUI

/// Where the open quick menu's card sits.
struct GameMenuAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// A game's card: the list (GameMenu) as a right-click menu, and where its quick menu opens.
struct GameCardMenu: ViewModifier {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    func body(content: Content) -> some View {
        content
            .contextMenu {
                ForEach(model.menuActions(for: game), id: \.self) { action in
                    if action.destructive { Divider() }
                    Button(action.title(game), role: action.destructive ? .destructive : nil) {
                        model.perform(action, on: game)
                    }
                }
            }
            .anchorPreference(key: GameMenuAnchor.self, value: .bounds) { model.quickMenu.map(game.holds) == true ? $0 : nil }
    }
}

/// A long click on a card opens its quick menu. Goes outside the card's own tap, which it leaves
/// alone: a card's tap does nothing with the menu open, when the mouse comes up after a long click.
struct LongClick: ViewModifier {
    let action: () -> Void
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($pressed) { value, state, _ in
                    // Control-click is the right-click menu's.
                    state = hypot(value.translation.width, value.translation.height) < 6 && !NSEvent.modifierFlags.contains(.control)
                }
            )
            .task(id: pressed) {
                guard pressed else { return }
                try? await Task.sleep(for: .seconds(MenuHold.seconds))
                if !Task.isCancelled { action() }
            }
    }
}

/// A small, quiet button on a cover while the pointer is on it, the quick menu's way for one click.
/// In the middle of the cover's lower edge: the corners have their badges.
struct CardMenuButton: ViewModifier {
    var shown = true
    let open: () -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                if hovering && shown {
                    Button(action: open) {
                        Image(systemName: "ellipsis")
                            .font(size: 12, weight: .bold, scales: false)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 20)
                            .background(Theme.night.opacity(0.78), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 9)
                    .help(L10n.t("Quick menu"))
                    .accessibilityLabel(L10n.t("Quick menu"))
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Over everything in the window while a game's quick menu is open: a click beside it closes it, the
/// menu itself sits beside its card and keeps the pad.
struct GameMenuLayer: View {
    let anchor: Anchor<CGRect>?
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if let game = model.quickMenuGame {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeQuickMenu() }
                    BesideCard(card: anchor.map { geo[$0] }) {
                        GameMenuPanel(game: game)
                            .fixedSize()
                            .padZone(.panel)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

/// Places its one view by GameMenuPlacement, measured as it is.
private struct BesideCard: Layout {
    let card: CGRect?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let menu = subviews.first else { return }
        let size = menu.sizeThatFits(.unspecified)
        let origin = GameMenuPlacement.origin(card: card, menu: size, window: bounds.size)
        menu.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: .unspecified)
    }
}

private struct GameMenuPanel: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        MenuGlass(width: 300) {
            ForEach(model.menuActions(for: game), id: \.self) { action in
                if action.destructive {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                GameMenuRow(action: action, title: action.title(game)) { model.perform(action, on: game) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(game.name)
    }
}

private struct GameMenuRow: View {
    let action: GameAction
    let title: String
    let perform: () -> Void
    @State private var hovering = false

    private var color: Color { action.destructive ? Theme.errorText : Theme.ink }

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .font(size: 12.5, weight: .semibold)
                    .frame(width: 20)
                Text(title)
                    .font(size: 13.5, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hovering ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padFocus(GameMenu.padID(action), cornerRadius: 10, activate: perform)
    }
}
