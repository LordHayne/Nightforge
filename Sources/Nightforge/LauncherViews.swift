import SwiftUI

/// "Your launchers": four large cards side by side, in the first start and where Settings › Stores
/// leads. Left and right choose, A does what the card's button says.
struct LauncherPage: View {
    /// In the first start the page leads on to the library check.
    var firstStart = false
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if firstStart {
            content  // the first start's page scrolls already (HomeLevel)
        } else {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    content
                        .padding(.horizontal, Theme.gutter)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.t("Your launchers"))
                        .displayFont(36)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.t("Choose where you sign in. After that, the launchers stay in the background and all your games are in one library."))
                        .font(size: 15)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if firstStart {
                    Button(L10n.t("Continue")) { model.setup.leaveLaunchers() }
                        .buttonStyle(GlassTextButtonStyle())
                        .padFocus("launcher.continue", cornerRadius: 21, activate: { model.setup.leaveLaunchers() })
                }
            }
            // As high as drawn; larger text makes all four grow together.
            HStack(alignment: .top, spacing: 24) {
                ForEach(model.launchers) { LauncherCard(state: $0) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padZone(.panel)
        .onAppear { model.focusLauncherCards() }
    }
}

/// One store. The lit card is the one selected: its ring and its button are the page's one lamp.
private struct LauncherCard: View {
    let state: LauncherState
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var focus = PadFocus.shared

    private var padID: String { LauncherState.cardID(state.provider) }
    private var lit: Bool { focus.focused == padID }

    private func act() {
        if let action = state.action { model.perform(action, on: state.provider) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LauncherTile(state: state, size: 72, font: 30)
            Text(state.provider.label)
                .displayFont(19)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)
            Text(state.status)
                .font(size: 13, weight: .medium)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.detail)
                .font(size: 13, weight: .medium)
                .lineSpacing(3)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            button
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 340, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // The glow belongs to the card's shape: on the stack it would light every word too.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom))
                .shadow(color: lit ? Theme.sodium.opacity(0.5) : .clear, radius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(lit ? Theme.sodium : Theme.ink.opacity(0.08), lineWidth: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { if $0 { focus.focus(padID) } }
        .padFocus(padID, cornerRadius: 10, ring: false, activate: act)
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.provider.label)
    }

    private var button: some View {
        Button(action: act) {
            Group {
                if lit {
                    Text(state.actionLabel).displayFont(15)
                } else {
                    Text(state.actionLabel).font(size: 13, weight: .semibold)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(lit ? Theme.night : Theme.ink)
            .background {
                Capsule()
                    .fill(lit ? Theme.sodium : Theme.ink.opacity(0.1))
                    .shadow(color: lit ? Theme.sodium.opacity(0.3) : .clear, radius: 14)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.action == nil)
    }
}

/// The store's tile: plain type, as the app has none of their marks.
private struct LauncherTile: View {
    let state: LauncherState
    let size: CGFloat
    let font: CGFloat

    var body: some View {
        Text(verbatim: state.letter)
            .displayFont(font)
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.night, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "Launchers 3/4" in the top bar: it opens the small menu, and is lit while that's open.
struct LauncherPill: View {
    @EnvironmentObject private var model: LibraryModel

    private func toggle() {
        model.launcherMenuOpen ? model.closeLauncherMenu() : model.openLauncherMenu()
    }

    var body: some View {
        let open = model.launcherMenuOpen
        Button(action: toggle) {
            Text(L10n.t("Launchers %ld/%ld", model.signedInLaunchers, model.launchers.count))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .font(size: 13, weight: .semibold)
                .foregroundStyle(open ? Theme.night : Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
        }
        .buttonStyle(GlassButtonStyle(glass: open ? .tinted(Theme.sodium) : .regular, shape: Capsule(), fadesWhenDisabled: false))
        .padFocus("top.launchers", cornerRadius: 17, activate: { model.openLauncherMenu(byPad: true) })
        .help(L10n.t("Your launchers (M)"))
    }
}

/// The small menu at the top right, for quick access. A solid card, not glass: it may lie over the
/// library for a while, and blurs nothing behind it.
struct LauncherMenu: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.launchers) { LauncherRow(state: $0) }
        }
        .padding(16)
        .frame(width: 400 * textScale)
        .background(Theme.slate.opacity(0.97), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Launchers"))
    }
}

private struct LauncherRow: View {
    let state: LauncherState
    @EnvironmentObject private var model: LibraryModel

    /// A store to sign in to does that; a signed-in one leads to its card.
    private func act() {
        if let action = state.quickAction {
            model.perform(action, on: state.provider)
        } else if state.isSignedIn {
            model.showLauncher(state.provider)
        }
    }

    var body: some View {
        Button(action: act) {
            HStack(spacing: 12) {
                LauncherTile(state: state, size: 44, font: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.provider.label)
                        .font(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    Text(state.menuStatus)
                        .font(size: 12, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let action = state.quickAction {
                    Text(state.shortLabel(action))
                        .lineLimit(1)
                        .fixedSize()
                        .font(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.ink.opacity(0.12), in: Capsule())
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(state.quickAction != nil ? Theme.ink.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padFocus(LauncherState.rowID(state.provider), cornerRadius: 10, activate: act)
    }
}

/// What the hint bar says on the four cards.
struct LauncherHints: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var focus = PadFocus.shared

    private var selected: LauncherState? {
        model.launchers.first { LauncherState.cardID($0.provider) == focus.focused }
    }

    var body: some View {
        let pad = model.padSymbols
        let controller = model.controllerConnected
        Hint(controller ? .pad(pad.stick) : .key("← →"), text: L10n.t("Choose launcher"))
        if let selected, let action = selected.action {
            Hint(controller ? .pad(pad.confirm) : .key("↵"), text: selected.shortLabel(action))
        }
        Hint(controller ? .pad(pad.back) : .key("esc"),
             text: model.route == .launchers ? L10n.t("Back") : L10n.t("Continue"))
    }
}

/// "Manage" on a signed-in store: its client, and the way out.
struct ManageLauncherSheet: View {
    let provider: Provider
    @EnvironmentObject private var model: LibraryModel

    private var state: LauncherState? { model.launchers.first { $0.provider == provider } }
    private var hasClient: Bool { provider == .steam || provider == .battlenet }

    private func close() { model.managedLauncher = nil }

    private func retry() {
        close()
        model.refreshStores(force: true)
    }

    private func openClient() {
        close()
        model.openClient(provider)
    }

    private func disconnect() {
        close()
        model.disconnect(provider)
    }

    private var message: String {
        guard let state else { return "" }
        if provider == .steam { return "\(state.status) · \(state.detail)" }
        return "\(state.status) · \(state.detail)\n\n" + L10n.t("The games on this Mac stay and come back with the next sign-in.")
    }

    var body: some View {
        GlassQuestion(provider.label, message: message, id: "manageLauncher") {
            if provider != .steam {
                Button(L10n.t("Disconnect"), action: disconnect)
                    .buttonStyle(GlassTextButtonStyle())
                    .padFocus("manage.disconnect", cornerRadius: 21, activate: disconnect)
            }
            if case .unreachable = state?.account {
                Button(L10n.t("Try Again"), action: retry)
                    .buttonStyle(GlassTextButtonStyle())
                    .padFocus("manage.retry", cornerRadius: 21, activate: retry)
            }
            if hasClient {
                Button(L10n.t("Open %@", provider.label), action: openClient)
                    .buttonStyle(GlassTextButtonStyle())
                    .padFocus("manage.client", cornerRadius: 21, activate: openClient)
            }
            Button(L10n.t("Done"), action: close)
                .buttonStyle(GlassTextButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .padFocus("manage.done", cornerRadius: 21, preferred: true, activate: close)
        }
    }
}
