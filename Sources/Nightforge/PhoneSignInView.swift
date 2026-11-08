import SwiftUI

/// The stage's slot while GOG signs in from the phone. The door is open as long as this is on screen.
struct PhoneSignInSlot: View {
    @ObservedObject var phone: PhoneSignIn
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        PhoneSignInCard(state: phone.state, picture: phone.picture,
                        confirm: model.controllerConnected ? model.padSymbols.confirm : nil,
                        renew: { model.openPhoneSignIn() })
            .onAppear { model.openPhoneSignIn() }
            .onDisappear { phone.close() }
    }
}

/// What the slot shows in each state. A still picture: nothing here redraws, and there's no countdown.
struct PhoneSignInCard: View {
    let state: PhoneSignIn.State
    let picture: CGImage?
    /// The pad's confirm button, when there's a controller.
    let confirm: String?
    let renew: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            switch state {
            case .closed, .opening:
                GlassSpinner(size: 22)
            case .open:
                if let picture {
                    Image(decorative: picture, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 290, height: 290)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(L10n.t("QR code for signing in on your phone"))
                }
                Text(L10n.t("Valid for %ld minutes, and only on this network.", Int(PhoneSignInDoor.lifetime / 60)))
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
            case .expired:
                Text(L10n.t("The code has run out."))
                    .displayFont(19)
                    .foregroundStyle(Theme.ink)
                Button(action: renew) {
                    HStack(spacing: 7) {
                        if let confirm { Image(systemName: confirm) }
                        Text(L10n.t("New Code"))
                    }
                }
                .buttonStyle(GlassTextButtonStyle(small: true))
            case .unavailable:
                Text(L10n.t("Your phone can't reach this Mac: it isn't on a home or office network. You can still sign in here with a keyboard."))
                    .font(size: 14, weight: .medium)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 320)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.night.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
