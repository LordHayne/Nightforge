import SwiftUI

/// Settings › Home: what the stage is made of, and the order of the pinned games. It only shows what
/// it's given, the model decides (LibraryModel.setHomeSource, movePin).
struct HomeSettingsForm: View {
    let sources: HomeSources
    /// The pinned games, in their order.
    let pinned: [Game]
    let set: (HomeSources.Source, Bool) -> Void
    /// Moves the game a place up (-1) or down (1).
    let move: (Game, Int) -> Void

    private func binding(_ source: HomeSources.Source) -> Binding<Bool> {
        Binding(get: { sources.isOn(source) }, set: { set(source, $0) })
    }

    var body: some View {
        Form {
            Section {
                ForEach(HomeSources.Source.allCases) { source in
                    Toggle(isOn: binding(source)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.title)
                            if let note = source.note {
                                Text(note)
                                    .font(size: 10)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padFocus("settings.home.\(source.rawValue)", toggle: binding(source))
                }
            }
            if sources.isOn(.pinned) {
                Section {
                    if pinned.isEmpty {
                        Text(L10n.t("Nothing pinned yet: a game's quick menu pins it."))
                            .font(size: 12)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { place, game in
                        LabeledContent {
                            if pinned.count > 1 {
                                HStack(spacing: 6) {
                                    arrow(game, up: true, atEnd: place == 0)
                                    arrow(game, up: false, atEnd: place == pinned.count - 1)
                                }
                            }
                        } label: {
                            Text(game.name).lineLimit(1)
                        }
                    }
                } header: {
                    Text(pinned.count > 1 ? L10n.t("Pinned · change the order with ↑ ↓") : L10n.t("Pinned"))
                        .font(size: 11, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// At the end of the list the mouse finds it dimmed. The pad's highlight stays on it, and moving a
    /// game on takes the highlight along: its ID goes with the game, not the row.
    private func arrow(_ game: Game, up: Bool, atEnd: Bool) -> some View {
        let press = { if !atEnd { move(game, up ? -1 : 1) } }
        return Button(action: press) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(size: 12, weight: .semibold, scales: false)
                .frame(width: 24, height: 18)
        }
        .disabled(atEnd)
        .accessibilityLabel(up ? L10n.t("Move %@ up", game.name) : L10n.t("Move %@ down", game.name))
        .padFocus("settings.home.pin.\(game.id).\(up ? "up" : "down")", cornerRadius: 12, activate: press)
    }
}
