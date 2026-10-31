import IOKit.pwr_mgt
import SwiftUI

/// Keeps the Mac awake while games download: an idle Mac would otherwise sleep and stop Steam.
/// The display may still turn off; only system sleep waits.
@MainActor
enum KeepAwake {
    private static var assertion: IOPMAssertionID = 0
    private static var holding = false

    static func update(downloading names: [String]) {
        if names.isEmpty {
            guard holding else { return }
            IOPMAssertionRelease(assertion)
            holding = false
        } else if !holding {
            let reason = L10n.t("Nightforge is downloading %@", names.joined(separator: ", ")) as CFString
            holding = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                  IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess
        }
    }
}

/// The top bar's download ring: how far the downloads (and a game moving to another drive) have
/// got and how many there are (D).
struct DownloadsButton: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        let downloads = model.downloads
        let count = downloads.count + (model.move == nil ? 0 : 1)
        Button { model.showingDownloads.toggle() } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, Self.progress(downloads, move: model.move)))
                    .stroke(Theme.sodium, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(count)")
                    .font(size: 10, weight: .bold, scales: false).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(GlassGroupButtonStyle())
        .help(count == 1 ? L10n.t("1 download (D)") : L10n.t("%ld downloads (D)", count))
        .accessibilityLabel(count == 1 ? L10n.t("1 download") : L10n.t("%ld downloads", count))
        .padFocus("top.downloads", cornerRadius: 15, activate: { model.showingDownloads.toggle() })
    }

    static func progress(_ downloads: [Game], move: GameMove? = nil) -> Double {
        let fractions = downloads.map { game -> Double in
            if case .downloading(let fraction) = game.install { return fraction ?? 0 }
            return 0
        } + (move.map { [$0.phase == .finishing ? 1 : $0.fraction ?? 0] } ?? [])
        return fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
    }
}

/// What's downloading, how far, and a way to stop each one: the design's glass panel under the
/// top bar (LibraryView lays it out).
struct DownloadsPanel: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("Downloads"))
                    .displayFont(16)
                Spacer()
                Button { model.showingDownloads = false } label: {
                    Image(systemName: "xmark")
                        .font(size: 11, weight: .bold, scales: false)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(shape: Circle()))
                .help(L10n.t("Close"))
                .padFocus("downloads.close", cornerRadius: 14, activate: { model.showingDownloads = false })
            }
            if model.downloads.isEmpty && model.move == nil {
                Text(L10n.t("Nothing is downloading."))
                    .font(size: 13)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 6)
            }
            if let move = model.move {
                moveRow(move)
            }
            ForEach(model.downloads) { game in
                row(game)
            }
            if !model.downloads.isEmpty {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "moon.zzz")
                    Text(L10n.t("Your Mac stays awake while games download. The display can still turn off."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(size: 12)
                .foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .frame(width: 380 * textScale)  // grows with the text, so the names keep their room
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 12) {
            DownloadCover(game: game)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(game.name)
                        .font(size: 13.5, weight: .semibold)
                        .lineLimit(1)
                    // A game the player has in several stores: which one this download comes from.
                    if model.card(holding: game.id)?.others.isEmpty == false {
                        StoreBadge(store: game.provider.label)
                    }
                }
                DownloadBar(fraction: fraction(game))
                statusLines(line(game))
            }
            if model.canUninstall(game) {
                Button(L10n.t("Cancel")) { model.requestUninstall(game) }
                    .buttonStyle(GlassTextButtonStyle(small: true))
                    .padFocus("downloads.cancel.\(game.id)", cornerRadius: 15, activate: { model.requestUninstall(game) })
            }
        }
        .padding(10)
        .glassWell()
    }

    /// A game moving to another drive: how far the copy is, and Cancel until it's copied.
    private func moveRow(_ move: GameMove) -> some View {
        HStack(spacing: 12) {
            DownloadCover(game: move.game)
            VStack(alignment: .leading, spacing: 6) {
                // "Hades → Spiele test": where it goes stays readable, the name gives way.
                HStack(spacing: 6) {
                    Text(move.game.name)
                        .font(size: 13.5, weight: .semibold)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(size: 10.5, weight: .bold)
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    Text(move.drive ?? L10n.t("This Mac"))
                        .font(size: 12.5, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel(move.drive.map { L10n.t("Moving to %@", $0) } ?? L10n.t("Moving back to your Mac"))
                }
                DownloadBar(fraction: move.phase == .copying ? move.fraction : move.phase == .finishing ? 1 : nil)
                statusLines(moveLine(move))
            }
            if move.phase != .finishing {
                Button(L10n.t("Cancel")) { model.cancelMove() }
                    .buttonStyle(GlassTextButtonStyle(small: true))
                    .padFocus("downloads.cancelMove", cornerRadius: 15, activate: { model.cancelMove() })
            }
        }
        .padding(10)
        .glassWell()
    }

    /// How far, and below it how fast and how long still: on one line the panel cut off the time left.
    private func statusLines(_ status: (progress: String, speed: String?)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.progress)
            if let speed = status.speed { Text(speed) }
        }
        .font(size: 11.5).monospacedDigit()
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
    }

    /// "37 % of 12 GB" and "25 MB/s · 8 min left" once the speed is known.
    private func moveLine(_ move: GameMove) -> (progress: String, speed: String?) {
        switch move.phase {
        case .stoppingSteam:
            return (move.game.provider == .steam ? L10n.t("Closing Steam for the move …") : L10n.t("Preparing …"), nil)
        case .copying:
            guard let fraction = move.fraction else { return (L10n.t("Moving …"), nil) }
            return Self.status(fraction: fraction, total: move.progress.total, rate: move.rate)
        case .finishing:
            return (L10n.t("Checked – finishing the move …"), nil)
        }
    }

    private func fraction(_ game: Game) -> Double? {
        if game.downloadNeedsSpace != nil { return nil }
        if case .downloading(let fraction?) = game.install { return fraction }
        return nil
    }

    /// "37 % of 12 GB" and "12 MB/s · 25 min left" – as much as is known.
    private func line(_ game: Game) -> (progress: String, speed: String?) {
        if game.downloadNeedsSpace != nil { return (L10n.t("Paused – not enough space"), nil) }
        guard case .downloading(let fraction?) = game.install else { return (L10n.t("Preparing …"), nil) }
        return Self.status(fraction: fraction, total: game.sizeOnDisk, rate: model.downloadRates[game.gameID])
    }

    /// "37 % of 12 GB" (or "37 %" while the size isn't known), and the speed and time left once
    /// they are – in what the store downloads, as the game page says it.
    nonisolated static func status(fraction: Double, total: Int64, rate: DownloadRate?) -> (progress: String, speed: String?) {
        let percent = Int(fraction * 100)
        let progress = total > 0 ? L10n.t("%ld %% of %@", percent, Format.bytes(total)) : "\(percent) %"
        return (progress, rate?.label(total: Double(total)))
    }
}

/// The game's cover in a download row.
private struct DownloadCover: View {
    let game: Game
    @State private var cover: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)
            if let cover {
                Image(nsImage: cover).resizable().scaledToFill()
            }
        }
        .frame(width: 36, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .task(id: game.id) { cover = await ArtworkStore.shared.image(for: game, kind: .cover) }
    }
}

/// A thin sodium bar; without a known share, a short piece sweeps across while Steam prepares.
private struct DownloadBar: View {
    let fraction: Double?
    @State private var sweep = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                if let fraction {
                    Capsule().fill(Theme.sodium)
                        .frame(width: max(5, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                } else {
                    Capsule().fill(Theme.sodium.opacity(0.7))
                        .frame(width: geo.size.width * 0.25)
                        .offset(x: sweep ? geo.size.width * 0.75 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: sweep)
                        .onAppear { sweep = true }
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
