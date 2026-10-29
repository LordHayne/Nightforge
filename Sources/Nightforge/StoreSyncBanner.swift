import SwiftUI

/// A store whose library couldn't be brought up to date (7.5): above the library it says so, how
/// old its games are – they still play – and offers the way out (try again, sign in again).
/// Nothing goes quietly; everything that's up to date says nothing.
struct StoreSyncBanner<Store: AccountStore>: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject var store: Store
    /// Opens the store's sign-in.
    let connect: () -> Void
    /// "Try Again" was pressed: while the store is asked, the banner says so instead of going away.
    @State private var retrying = false

    var body: some View {
        if store.isConnected, let text = shown {
            HStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    if store.sync.state == .syncing {
                        GlassSpinner()
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.sodium)
                    }
                    Text(text)
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13, weight: .medium))
                if store.sync.state == .signedOut {
                    actionButton(L10n.t("Sign In Again"), symbol: "person.crop.circle.badge.checkmark", action: connect)
                } else if store.sync.failed {
                    actionButton(L10n.t("Try Again"), symbol: "arrow.clockwise") {
                        retrying = true
                        model.refreshStores(force: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.sodium.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.sodium.opacity(0.25)))
            .accessibilityElement(children: .combine)
            .onChange(of: store.sync.state) { _, state in
                if state != .syncing { retrying = false }
            }
        }
    }

    private var shown: String? {
        if store.sync.state == .syncing { return retrying ? L10n.t("Updating %@ …", store.provider.label) : nil }
        return StoreSyncText.text(provider: store.provider, sync: store.sync)
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.sodium)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padFocus("library.sync.\(store.provider.rawValue)", cornerRadius: 10, activate: action)
    }
}

/// What the banner says for a store's state.
enum StoreSyncText {
    /// nil while all is well.
    static func text(provider: Provider, sync: StoreSync) -> String? {
        switch sync.state {
        case .ok, .syncing:
            return nil
        case .failed(let reason):
            guard let last = sync.lastSuccess else {
                return L10n.t("%@ – your %@ games show up as soon as it answers.", reason, provider.label)
            }
            return L10n.t("%@ – your %@ games are from %@ and still play.", reason, provider.label, Format.relative(last))
        case .signedOut:
            return L10n.t("%@ signed you out – your games stay here. Sign in again to download and to play online.", provider.label)
        }
    }
}
