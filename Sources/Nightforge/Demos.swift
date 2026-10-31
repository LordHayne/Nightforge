import SwiftUI

/// On a demo's page: the full game isn't the player's, and where to get it.
struct DemoNote: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    /// Side by side where there's room (a game's page); the button under the line in Home's column.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                line
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                line.fixedSize(horizontal: false, vertical: true)
                button
            }
        }
    }

    private var line: some View {
        Label(L10n.t("Free demo – the full game isn't in your Steam library."), systemImage: "gift")
            .font(size: 13, weight: .medium)
            .foregroundStyle(Theme.muted)
    }

    private var button: some View {
        Button(L10n.t("Full Game in Steam Store")) { model.openStorePage(game) }
            .buttonStyle(GlassTextButtonStyle(small: true))
            .padFocus("detail.fullGame", activate: { model.openStorePage(game) })
    }
}

/// A cover's tag for a game the player doesn't own, offered as its demo: beside the MAC tag when
/// there is one.
struct DemoTag: View {
    let game: Game

    var body: some View {
        if game.demoOf != nil {
            let mac = game.platform == .mac || (game.install == .inStore && game.macNative)
            Text("DEMO")
                .displayFont(9.5)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.night.opacity(0.78), in: Capsule())
                .padding(.top, 7)
                .padding(.trailing, mac ? 50 : 7)
                .help(L10n.t("Free demo"))
        }
    }
}

/// On the page of a download Steam won't fetch: why, and the way out.
struct RefusedDownloadNote: View {
    var body: some View {
        Label(L10n.t("Steam won't download this game: it isn't in your Steam library. Cancel the download to take the request back."),
              systemImage: "xmark.circle")
            .font(size: 13, weight: .medium)
            .foregroundStyle(Theme.muted)
            .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Before a demo's first download: Steam adds its free licence to the account, which takes one
/// click in Steam's own install window. Said once, before that window comes up.
struct DemoLicenseSheet: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        GlassQuestion(L10n.t("Add the free demo"),
                      message: L10n.t("%@ is free. Steam adds it to your Steam library once: confirm the installation in the Steam window that opens next. After that, Nightforge downloads and starts it like any other game.", game.name),
                      id: "demo") {
            Button(L10n.t("Cancel")) { model.pendingDemoLicense = nil }
                .buttonStyle(GlassTextButtonStyle())
                .padFocus("demo.cancel", cornerRadius: 21, activate: { model.pendingDemoLicense = nil })
            Button(L10n.t("Open Steam")) { model.addDemoLicense(game) }
                .buttonStyle(GlassTextButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .padFocus("demo.openSteam", cornerRadius: 21, preferred: true, activate: { model.addDemoLicense(game) })
        }
    }
}
