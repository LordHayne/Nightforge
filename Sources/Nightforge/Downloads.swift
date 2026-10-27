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

/// The top bar's download ring: how far the downloads have got and how many there are (D).
struct DownloadsButton: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        let downloads = model.downloads
        Button { model.showingDownloads.toggle() } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, Self.progress(downloads)))
                    .stroke(Theme.sodium, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(downloads.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(GlassGroupButtonStyle())
        .help(downloads.count == 1 ? L10n.t("1 download (D)") : L10n.t("%ld downloads (D)", downloads.count))
        .accessibilityLabel(downloads.count == 1 ? L10n.t("1 download") : L10n.t("%ld downloads", downloads.count))
        .padFocus("top.downloads", cornerRadius: 15, activate: { model.showingDownloads.toggle() })
    }

    static func progress(_ downloads: [Game]) -> Double {
        let fractions = downloads.map { game -> Double in
            if case .downloading(let fraction) = game.install { return fraction ?? 0 }
            return 0
        }
        return fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
    }
}

/// What's downloading, how far, and a way to stop each one: the design's glass panel under the
/// top bar (LibraryView lays it out).
struct DownloadsPanel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("Downloads"))
                    .font(Theme.display(16))
                Spacer()
                Button { model.showingDownloads = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(shape: Circle()))
                .help(L10n.t("Close"))
                .padFocus("downloads.close", cornerRadius: 14, activate: { model.showingDownloads = false })
            }
            if model.downloads.isEmpty {
                Text(L10n.t("Nothing is downloading."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 6)
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
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .frame(width: 380)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 12) {
            DownloadCover(game: game)
            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                DownloadBar(fraction: fraction(game))
                Text(line(game))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
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

    private func fraction(_ game: Game) -> Double? {
        if game.downloadNeedsSpace != nil { return nil }
        if case .downloading(let fraction?) = game.install { return fraction }
        return nil
    }

    /// "37 % of 12 GB · 12 MB/s · 25 min left" – as much as is known.
    private func line(_ game: Game) -> String {
        if game.downloadNeedsSpace != nil { return L10n.t("Paused – not enough space") }
        guard case .downloading(let fraction?) = game.install else { return L10n.t("Preparing …") }
        let done = game.sizeOnDisk > 0
            ? L10n.t("%ld %% of %@", Int(fraction * 100), Format.bytes(game.sizeOnDisk))
            : "\(Int(fraction * 100)) %"
        guard let speed = model.downloadRates[game.appID]?.label(total: Double(game.sizeOnDisk)) else { return done }
        return done + " · " + speed
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
