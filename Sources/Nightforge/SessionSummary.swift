import SwiftUI

/// How a game ran for the player, from the "Welcome back" sheet. Kept on this Mac only; it beats
/// the profile list in the compatibility rating – your own experience counts most.
struct GameRating: Codable, Equatable {
    enum Issue: String, Codable, CaseIterable {
        case stutters, crashed, lowFrameRate, glitches, controller, sound

        var label: String {
            switch self {
            case .stutters: return L10n.t("Stutters")
            case .crashed: return L10n.t("Crashed")
            case .lowFrameRate: return L10n.t("Low frame rate")
            case .glitches: return L10n.t("Graphics glitches")
            case .controller: return L10n.t("Controller")
            case .sound: return L10n.t("Sound")
            }
        }
    }

    var good: Bool
    var issues: [Issue] = []
    var date = Date()
}

enum GameRatings {
    private static func key(_ game: GameID) -> String { "rating.\(game.key)" }

    static func load(_ game: GameID, from defaults: UserDefaults = .standard) -> GameRating? {
        defaults.data(forKey: key(game)).flatMap { try? JSONDecoder().decode(GameRating.self, from: $0) }
    }

    static func save(_ rating: GameRating, for game: GameID, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rating) { defaults.set(data, forKey: key(game)) }
    }
}

/// A game Nightforge started has ended after a real session: how long, and how it ran.
struct SessionSummary: Identifiable {
    let game: Game
    let minutes: Int
    /// Play time Steam had counted before this session.
    let totalBefore: Int
    /// When the game's processes were gone: Steam's cloud record has to be newer than that.
    var endedAt = Date()
    var id: String { game.id }
}

struct SessionSummarySheet: View {
    let summary: SessionSummary
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Bool?
    @State private var issues: Set<GameRating.Issue> = []
    @State private var saved = false
    @State private var cloud: CloudSaves.State?
    /// Steam took longer than a minute to confirm the upload: say it carries on by itself.
    @State private var cloudTookLong = false

    /// Steam may already have added this session when the library was read again.
    private var total: Int {
        let now = model.allGames.first { $0.id == summary.game.id }?.playtimeMinutes ?? 0
        return max(now, summary.totalBefore + summary.minutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(L10n.t("Welcome back"))
                    .font(Theme.display(22))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(GlassButtonStyle(shape: Circle()))
                .keyboardShortcut(.cancelAction)
                .help(L10n.t("Close"))
                .padFocus("session.close", cornerRadius: 16, activate: { dismiss() })
                .padding(.top, -4)
                .padding(.trailing, -8)
            }

            HStack(spacing: 16) {
                SessionCover(game: summary.game)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.game.name)
                        .font(Theme.display(20))
                        .lineLimit(2)
                    Text(L10n.t("%@ this time · %@ in total", Format.playtime(summary.minutes), Format.playtime(total)))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .monospacedDigit()
                }
            }

            if let cloud {
                saveLine(cloud)
                    .font(.system(size: 13.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("How did it run?"))
                    .font(.system(size: 14, weight: .medium))
                if saved {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.runsGreat)
                        Text(L10n.t("Thanks – noted on this Mac. It shapes how Nightforge rates the game for you."))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 13))
                } else if rating == false {
                    issueButtons
                    Button(L10n.t("Save")) { save(good: false) }
                        .buttonStyle(GlassTextButtonStyle(prominent: true))
                        .padFocus("session.saveIssues", cornerRadius: 21, activate: { save(good: false) })
                } else {
                    HStack(spacing: 10) {
                        ratingButton(L10n.t("Well"), symbol: "hand.thumbsup", id: "session.good") { save(good: true) }
                        ratingButton(L10n.t("Not well"), symbol: "hand.thumbsdown", id: "session.bad") { rating = false }
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button { playAgain() } label: {
                    Label(L10n.t("Play Again"), systemImage: "play.fill")
                }
                .buttonStyle(GlassTextButtonStyle())
                .padFocus("session.again", cornerRadius: 21, activate: playAgain)
                Button(L10n.t("Done")) { dismiss() }
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("session.done", cornerRadius: 21, activate: { dismiss() })
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Theme.ink)
        .padding(28)
        .frame(width: 520)
        // The design's dialog: thick glass over the dimmed library, not the system's sheet panel.
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .presentationBackground(.clear)
        .task { await followCloud() }
    }

    private func ratingButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
        .padFocus(id, cornerRadius: 20, activate: action)
    }

    @ViewBuilder private func saveLine(_ state: CloudSaves.State) -> some View {
        switch state {
        case .synced:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud").font(.system(size: 18)).foregroundStyle(Theme.runsGreat)
                Text("\(Text(L10n.t("Your save is in the Steam Cloud.")).fontWeight(.semibold)) \(L10n.t("You can close your Mac."))")
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .syncing where cloudTookLong:
            Label(L10n.t("Steam syncs your save in the background."), systemImage: "icloud")
                .foregroundStyle(Theme.ink.opacity(0.85))
        case .syncing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Steam is syncing your save with the Steam Cloud …")).foregroundStyle(Theme.ink.opacity(0.85))
            }
        case .noCloud:
            Label(L10n.t("No Steam Cloud for this game – its saves are on this Mac."), systemImage: "internaldrive")
                .foregroundStyle(Theme.ink.opacity(0.85))
        }
    }

    /// Asks Steam's cloud record every two seconds for a minute, until it confirms.
    private func followCloud() async {
        for _ in 0..<30 {
            let game = summary.game, ended = summary.endedAt
            let state = await Task.detached(priority: .utility) {
                CloudSaves.state(appID: game.appID, steamRoot: game.steamRoot, endedAt: ended)
            }.value
            cloud = state
            if state != .syncing { return }
            try? await Task.sleep(for: .seconds(2))
        }
        cloudTookLong = true
    }

    private var issueButtons: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(GameRating.Issue.allCases, id: \.self) { issue in
                let on = issues.contains(issue)
                FilterToggle(title: issue.label, symbol: on ? "checkmark" : "circle", on: on, id: "session.issue.\(issue.rawValue)") {
                    if on { issues.remove(issue) } else { issues.insert(issue) }
                }
            }
        }
    }

    private func save(good: Bool) {
        GameRatings.save(GameRating(good: good, issues: good ? [] : GameRating.Issue.allCases.filter(issues.contains)), for: summary.game.gameID)
        rating = good
        saved = true
    }

    private func playAgain() {
        dismiss()
        model.play(summary.game)
    }
}

/// The game's cover beside its name: small, with the hairline the design gives it.
private struct SessionCover: View {
    let game: Game
    @State private var cover: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)
            if let cover {
                Image(nsImage: cover).resizable().scaledToFill()
            }
        }
        .frame(width: 64, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .accessibilityHidden(true)
        .task(id: game.id) { cover = await ArtworkStore.shared.image(for: game, kind: .cover) }
    }
}
