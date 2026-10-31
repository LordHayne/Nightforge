import SwiftUI

/// On a game's page, beside its title: what is set for this game – store, version, graphics, HUD,
/// launch options, engine, offline – and where it comes from, with the way back to the profile.
struct ThisGameCard: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @State private var profile: GameProfile?

    var body: some View {
        let options = GameOptionsStore.load(game.gameID)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(L10n.t("This game"))
                Spacer()
                Button(L10n.t("Change …"), action: change)
                    .buttonStyle(CardLinkStyle(color: Theme.sodium))
                    .help(L10n.t("Options for this game (O)"))
                    .padFocus("detail.thisGame.change", cornerRadius: 8, activate: change)
            }
            VStack(spacing: 10) {
                row(L10n.t("Store"), game.provider.label)
                row(L10n.t("Version"), version(options))
                row(L10n.t("Graphics"), graphics(options))
                row(L10n.t("Performance HUD"), hud(options))
                row(L10n.t("Launch options"), options.extraArgs.isEmpty ? "–" : options.extraArgs, monospaced: !options.extraArgs.isEmpty)
                row(L10n.t("Engine"), engine)
                if let offline {
                    row(L10n.t("Offline"), offline.label)
                        .help(offline.help)
                        .accessibilityHint(offline.help)
                } else {
                    row(L10n.t("Offline"), "–")
                }
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            footer(options)
        }
        .padding(20)
        .frame(width: 310)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Options for this game"))
        .task(id: game.id) { profile = await ProfileStore.shared.profile(for: game.gameID) }
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Text(value)
                .font(size: monospaced ? 12 : 13, weight: .semibold, design: monospaced ? .monospaced : .default)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(size: 13)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func footer(_ options: GameOptions) -> some View {
        if options != GameOptions() {
            VStack(alignment: .leading, spacing: 6) {
                Text(origin == nil ? L10n.t("Your own settings.") : L10n.t("Your own settings, on top of the profile."))
                    .font(size: 12.5)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(origin == nil ? L10n.t("Back to Automatic") : L10n.t("Back to the Profile"), action: backToProfile)
                    .buttonStyle(CardLinkStyle(color: Theme.ink, underlined: true))
                    .padFocus("detail.thisGame.reset", cornerRadius: 8, activate: backToProfile)
            }
        } else {
            Label(origin?.text ?? L10n.t("No profile yet – Nightforge uses its automatic settings."),
                  systemImage: origin?.symbol ?? "wand.and.stars")
                .font(size: 12.5)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .help(origin?.note ?? "")
        }
    }

    private var origin: ProfileOrigin? { ProfileOrigin(profile) }

    private func version(_ options: GameOptions) -> String {
        let version = game.platform == .mac ? "Mac" : "Windows"
        return game.switchable && options.version == .automatic ? L10n.t("%@ (automatic)", version) : version
    }

    /// The preset and the layer it draws with now: "Automatic · DXMT", "Most compatible · DXVK".
    private func graphics(_ options: GameOptions) -> String {
        if game.platform == .mac { return L10n.t("In the game") }
        guard game.bottle.isBuiltIn else { return "–" }
        if options.preset == .custom, options.graphics != .automatic {
            return options.preset.label + " · " + options.graphics.shortLabel
        }
        let attempts = LaunchHealth.ladder(model.insights[game.gameID]?.attempts ?? [], preset: options.preset, profile: profile)
        guard !attempts.isEmpty else { return options.preset.label }
        return options.preset.label + " · " + attempts[LaunchHealth.current(game.gameID, attempts).index].graphics.shortLabel
    }

    /// Nightforge's own games get the HUD from Settings; CrossOver's from their options.
    private func hud(_ options: GameOptions) -> String {
        guard game.platform == .windows else { return "–" }
        return (game.bottle.isBuiltIn ? Prefs.performanceHUD : options.metalHUD) ? L10n.t("On") : L10n.t("Off")
    }

    private var engine: String {
        guard game.platform == .windows else { return "–" }
        guard game.bottle.isBuiltIn else { return game.bottle.name }
        if let held = model.heldEngine(of: game) {
            let label = EngineRollback.label(held.build, setUp: held.setUp, other: EngineRollback.shared.history().current)
            return L10n.t("%@ (held back)", "Wine " + label)
        }
        return EngineRollback.shared.history().current.map { "Wine " + $0.engineVersion } ?? "–"
    }

    private var offline: OfflineReadiness? {
        guard game.isInstalled else { return nil }
        return OfflineReadiness.of(game, analysis: model.insights[game.gameID]?.analysis,
                                   accountRemembered: game.provider == .epic ? model.epic.isSignedIn
                                       : OfflineReadiness.accountRemembered(steamRoot: game.steamRoot))
    }

    private func change() { model.showingOptions = true }

    /// Like the options sheet's "Back to the Profile": everything set for this game goes.
    private func backToProfile() {
        let version = GameOptionsStore.load(game.gameID).version
        GameOptionsStore.save(GameOptions(), for: game.gameID)
        if version != .automatic { MacHealth.reset(game.appID) }
        // A changed version moves the game to another Steam: scan again (this redraws the card, too).
        model.reload(quiet: true)
    }
}

/// A link in a card: text only, brighter or underlined under the pointer.
private struct CardLinkStyle: ButtonStyle {
    let color: Color
    var underlined = false

    func makeBody(configuration: Configuration) -> some View {
        CardLink(label: configuration.label, color: color, underlined: underlined, pressed: configuration.isPressed)
    }

    private struct CardLink<Label: View>: View {
        let label: Label
        let color: Color
        let underlined: Bool
        let pressed: Bool
        @State private var hovering = false

        var body: some View {
            label
                .font(size: 13, weight: .semibold)
                .foregroundStyle(hovering && underlined ? Theme.sodium : color)
                .underline(underlined || hovering)
                .opacity(pressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
