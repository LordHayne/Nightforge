import SwiftUI

// MARK: - A place a game can go

/// One place in a list of places (a drive, the Mac): its name, how much is free, and what's to know
/// about it – the whole row is the button that picks it, or says why it can't.
struct PlaceRow: View {
    let symbol: String
    let title: String
    let detail: String
    /// The format's caution, or why it can't go there.
    var note: String?
    var enabled = true
    let focusID: String
    var preferred = false
    /// Return picks it.
    var isDefault = false
    /// Not the first in its list: a line above it.
    var separated = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.sodium : Theme.muted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                    if let note {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(enabled ? Theme.warning : Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 3)
                }
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.ink.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if separated { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .disabled(!enabled)
        .padFocus(focusID, enabled: enabled, preferred: preferred, activate: action)
    }
}

extension DriveChoice {
    /// "62 GB free · Mac OS Extended"
    var detail: String { L10n.t("%@ free", Format.bytes(drive.free)) + " · " + drive.formatName }

    /// What's to know before the game goes there: why it can't, or exFAT's caution.
    var note: String? {
        if !drive.check.allowed { return drive.check.note(drive.name) }
        if !fits { return L10n.t("Not enough space – %@ needed.", Format.bytes(needed)) }
        return drive.check.note(drive.name)
    }
}

/// Places in one well.
private struct PlaceList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }.glassWell()
    }
}

// MARK: - Uninstalling

extension Game {
    /// The uninstall question's text for an installed game: where it goes from – the Mac or the
    /// drive it's on – what that frees, and that it stays in its store.
    var uninstallMessage: String {
        let size = Format.bytes(sizeOnDisk)
        if let drive = DriveLibrary.drive(of: installDir)?.lastPathComponent {
            return provider == .epic
                ? L10n.t("This removes the game from %@ and frees %@ there. It stays in your Epic Games library, so you can download it again any time. Saves in Epic's cloud are kept.", drive, size)
                : L10n.t("This removes the game from %@ and frees %@ there. It stays in your Steam library, so you can download it again any time. Saves in the Steam Cloud are kept.", drive, size)
        }
        return provider == .epic
            ? L10n.t("This removes the game from your Mac and frees %@. It stays in your Epic Games library, so you can download it again any time. Saves in Epic's cloud are kept.", size)
            : L10n.t("This removes the game from your Mac and frees %@. It stays in your Steam library, so you can download it again any time. Saves in the Steam Cloud are kept.", size)
    }
}

// MARK: - Install on a drive (the space sheet)

/// In the space sheet: the drives plugged in, to download the game there instead of making room.
struct DriveInstallChoices: View {
    let request: SpaceRequest
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if request.drives.isEmpty {
                Text(L10n.t("An external drive works too: plug one in, then press Download again."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t("Or install it on a drive:"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                PlaceList {
                    ForEach(Array(request.drives.enumerated()), id: \.element.id) { place, choice in
                        PlaceRow(symbol: "externaldrive", title: L10n.t("Install on %@", choice.drive.name), detail: choice.detail,
                                 note: choice.note, enabled: choice.usable, focusID: "space.drive.\(choice.drive.name)",
                                 separated: place > 0) {
                            model.download(request, on: choice)
                        }
                    }
                }
            }
        }
    }
}

/// Room on the Mac, and a drive with games of Nightforge's on it: where should this one go? Steam
/// asks the same with more than one library.
struct DestinationSheet: View {
    let request: SpaceRequest
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        GlassDialog(L10n.t("Where should %@ go?", request.game.name), id: "destination") {
            if request.needed > 0 {
                Text(L10n.t("It needs up to %@.", Format.bytes(request.needed)))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink.opacity(0.85))
            }
            PlaceList {
                PlaceRow(symbol: "laptopcomputer", title: L10n.t("This Mac"), detail: L10n.t("%@ free", Format.bytes(request.free)),
                         focusID: "destination.mac", preferred: true, isDefault: true) { model.downloadOnMac(request) }
                ForEach(request.drives) { choice in
                    PlaceRow(symbol: "externaldrive", title: choice.drive.name, detail: choice.detail, note: choice.note,
                             enabled: choice.usable, focusID: "destination.\(choice.drive.name)", separated: true) {
                        model.download(request, on: choice)
                    }
                }
            }
        }
    }
}

// MARK: - Move to …

/// Settings › Storage's "Move to …": the places the game can go, and what happens on the way.
struct MoveSheet: View {
    let game: Game
    let targets: [MoveTarget]
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        GlassDialog(L10n.t("Move %@", game.name), id: "move") {
            Text(game.provider == .steam
                 ? L10n.t("%@ is copied first and checked, then the old copy goes – if anything fails on the way, the game stays where it is. Steam closes meanwhile and starts again afterwards.", Format.bytes(game.sizeOnDisk))
                 : L10n.t("%@ is copied first and checked, then the old copy goes – if anything fails on the way, the game stays where it is.", Format.bytes(game.sizeOnDisk)))
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if targets.isEmpty {
                Text(L10n.t("Plug in an external drive to move the game there."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PlaceList {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { place, target in
                        if let choice = target.choice {
                            PlaceRow(symbol: "externaldrive", title: L10n.t("Move to %@", choice.drive.name), detail: choice.detail,
                                     note: choice.note, enabled: choice.usable, focusID: "move.\(choice.drive.name)",
                                     preferred: place == 0, separated: place > 0) { model.startMove(game, to: target) }
                        } else {
                            PlaceRow(symbol: "laptopcomputer", title: L10n.t("Move back to this Mac"),
                                     detail: L10n.t("%@ free", Format.bytes(target.macFree)),
                                     note: target.usable ? nil : L10n.t("Not enough space – %@ needed.", Format.bytes(target.needed)),
                                     enabled: target.usable, focusID: "move.mac", preferred: place == 0,
                                     separated: place > 0) { model.startMove(game, to: target) }
                        }
                    }
                }
            }
        }
    }
}
