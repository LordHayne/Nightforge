import SwiftUI

/// A volume with games that has run low on room (LibraryModel.lowSpace): one calm line with the way to
/// Settings › Storage, where games move to a drive or go. Nothing says anything while there's room.
struct LowSpaceNote: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if let place = model.lowSpace {
            HStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(Theme.sodium)
                    Text(Self.text(place))
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(size: 13, weight: .medium)
                Button { model.makeRoom() } label: {
                    Label(L10n.t("Make Room"), systemImage: "arrow.right.circle")
                        .font(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.sodium)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .padFocus("space.low", cornerRadius: 10, activate: { model.makeRoom() })
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.sodium.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.sodium.opacity(0.25)))
            .accessibilityElement(children: .combine)
        }
    }

    static func text(_ place: SpaceCheck.Place) -> String {
        place.isMac
            ? L10n.t("Your Mac has only %@ free – macOS slows down and can't update when it runs this low.", Format.bytes(place.free))
            : L10n.t("%@ has only %@ free.", place.name, Format.bytes(place.free))
    }
}
