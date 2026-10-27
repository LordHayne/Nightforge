import SwiftUI

/// On a demo's page: the full game isn't the player's, and where to get it.
struct DemoNote: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 10) {
            Label(L10n.t("Free demo – the full game isn't in your Steam library."), systemImage: "gift")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Button(L10n.t("Full Game in Steam Store")) { model.openStorePage(game) }
                .buttonStyle(GlassTextButtonStyle(small: true))
                .padFocus("detail.fullGame", activate: { model.openStorePage(game) })
        }
    }
}

/// Before a demo's first download: Steam adds its free licence to the account, which takes one
/// click in Steam's own install window. Said once, before that window comes up.
struct DemoLicenseSheet: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("Add the free demo"))
                .font(Theme.display(22))
            Text(L10n.t("%@ is free. Steam adds it to your Steam library once: confirm the installation in the Steam window that opens next. After that, Nightforge downloads and starts it like any other game.", game.name))
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .buttonStyle(GlassTextButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padFocus("demo.cancel", cornerRadius: 21, activate: { dismiss() })
                Button(L10n.t("Open Steam")) { model.addDemoLicense(game) }
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("demo.openSteam", cornerRadius: 21, activate: { model.addDemoLicense(game) })
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Theme.ink)
        .padding(28)
        .frame(width: 480)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .presentationBackground(.clear)
    }
}
