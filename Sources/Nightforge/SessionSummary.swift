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
    /// "Didn't start": no picture, or it hung (`good` is false then).
    var didntStart: Bool?
    /// The way it ran: a `LaunchAttempt.id` ("dxmt -dx11", "d3dmetal"), or "mac" for its Mac version –
    /// what worked, or didn't, together with the answer.
    var way: String?

    /// The choice in "Welcome back": "With problems" with the chips picked, in their order; "Ran well"
    /// and "Didn't start" without.
    static func choice(good: Bool, issues: Set<Issue>, didntStart: Bool = false, way: String? = nil) -> GameRating {
        GameRating(good: good && !didntStart, issues: good || didntStart ? [] : Issue.allCases.filter(issues.contains),
                   didntStart: didntStart ? true : nil, way: way)
    }
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
    /// The way it started (`GameRating.way`).
    var way: String?
    var id: String { game.id }
}

struct SessionSummarySheet: View {
    let summary: SessionSummary
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Bool?
    @State private var issues: Set<GameRating.Issue> = []
    @State private var saved = false
    /// "Didn't start" moved the next start on to another way (LaunchHealth).
    @State private var nextWay = false
    /// "Use “Most compatible” next time" was pressed.
    @State private var compatibleNext = false
    @State private var cloud: CloudSaves.State?
    /// Steam took longer than a minute to confirm the upload: say it carries on by itself.
    @State private var cloudTookLong = false

    /// Steam may already have added this session when the library was read again.
    private var total: Int {
        let now = model.allGames.first { $0.id == summary.game.id }?.playtimeMinutes ?? 0
        return max(now, summary.totalBefore + summary.minutes)
    }

    var body: some View {
        GlassDialog(L10n.t("Welcome back"), id: "session", width: 520) {
            HStack(spacing: 16) {
                SessionCover(game: summary.game)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.game.name)
                        .displayFont(20)
                        .lineLimit(2)
                    Text(L10n.t("%@ this time · %@ in total", Format.playtime(summary.minutes), Format.playtime(total)))
                        .font(size: 14)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .monospacedDigit()
                }
            }

            if let cloud {
                saveLine(cloud)
                    .font(size: 13.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassWell()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("How did it run?"))
                    .font(size: 14, weight: .medium)
                if saved {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.runsGreat)
                        Text(compatibleNext
                             ? L10n.t("Thanks – noted on this Mac. Next time it starts with “Most compatible”; change it any time in its options.")
                             : nextWay ? L10n.t("Thanks – noted on this Mac. Next time Nightforge starts it another way.")
                             : L10n.t("Thanks – noted on this Mac. It shapes how Nightforge rates the game for you."))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(size: 13)
                    shareButton
                } else if rating == false {
                    issueButtons
                    HStack(spacing: 8) {
                        Button(L10n.t("Save")) { save(good: false) }
                            .buttonStyle(GlassTextButtonStyle(prominent: true))
                            .padFocus("session.saveIssues", cornerRadius: 21, activate: { save(good: false) })
                        if suggestsCompatible {
                            Button(L10n.t("Use “Most compatible” next time"), action: useCompatible)
                                .buttonStyle(GlassTextButtonStyle())
                                .help(GraphicsPreset.compatible.help)
                                .padFocus("session.compatible", cornerRadius: 21, activate: useCompatible)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        ratingButton(L10n.t("Ran well"), symbol: "hand.thumbsup", id: "session.good") { save(good: true) }
                        ratingButton(L10n.t("With problems"), symbol: "hand.thumbsdown", id: "session.bad") { keep(good: false) }
                        ratingButton(L10n.t("Didn't start"), symbol: "xmark.octagon", id: "session.noStart", action: didntStart)
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
                    .padFocus("session.done", cornerRadius: 21, preferred: true, activate: { dismiss() })
            }
            .padding(.top, 4)
        }
        .task { await followCloud() }
    }

    private func ratingButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(size: 14, weight: .medium)
                .foregroundStyle(Theme.ink.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
        .padFocus(id, cornerRadius: 20, activate: action)
    }

    @ViewBuilder private func saveLine(_ state: CloudSaves.State) -> some View {
        // Epic's and GOG's saves go up through Nightforge; Steam's through Steam.
        let store = summary.game.provider == .steam ? nil : summary.game.provider.label
        switch state {
        case .synced:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud").font(size: 18).foregroundStyle(Theme.runsGreat)
                Text("\(Text(store.map { L10n.t("Your save is with %@.", $0) } ?? L10n.t("Your save is in the Steam Cloud.")).fontWeight(.semibold)) \(L10n.t("You can close your Mac."))")
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .syncing where cloudTookLong:
            Label(store.map { L10n.t("Your save goes up to %@ in the background.", $0) } ?? L10n.t("Steam syncs your save in the background."),
                  systemImage: "icloud")
                .foregroundStyle(Theme.ink.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .syncing:
            HStack(spacing: 10) {
                GlassSpinner()
                Text(store.map { L10n.t("Uploading your save to %@ …", $0) } ?? L10n.t("Steam is syncing your save with the Steam Cloud …"))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .noCloud:
            Label(store.map { L10n.t("No %@ cloud saves for this game – its saves are on this Mac.", $0) }
                      ?? L10n.t("No Steam Cloud for this game – its saves are on this Mac."), systemImage: "internaldrive")
                .foregroundStyle(Theme.ink.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Label(L10n.t("%@ couldn't take your save just now. It's safe on this Mac and goes up after your next session.",
                         store ?? summary.game.provider.label),
                  systemImage: "exclamationmark.icloud")
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Asks Steam's cloud record every two seconds for a minute, until it confirms. Epic and GOG
    /// games: how the upload Nightforge started after the session is going.
    private func followCloud() async {
        if summary.game.provider != .steam {
            for _ in 0..<90 {
                cloud = model.storeSaves[summary.game.gameID] ?? .syncing
                if cloud != .syncing { return }
                try? await Task.sleep(for: .seconds(1))
            }
            cloudTookLong = true
            return
        }
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
                    keep(good: false)
                }
            }
        }
    }

    /// Saves and says thanks ("Ran well", "Save").
    private func save(good: Bool) {
        keep(good: good)
        saved = true
    }

    /// A choice is kept the moment it's made – "With problems" too, and again with each chip – so
    /// however the sheet closes (Done, ×, Esc, B), nothing chosen is lost. With the way it ran.
    private func keep(good: Bool) {
        GameRatings.save(GameRating.choice(good: good, issues: issues, way: summary.way), for: summary.game.gameID)
        rating = good
    }

    /// No picture, or it hung: noted, and with "Automatic" the next start goes the next way.
    private func didntStart() {
        GameRatings.save(GameRating.choice(good: false, issues: [], didntStart: true, way: summary.way), for: summary.game.gameID)
        rating = false
        saved = true
        Task { nextWay = await model.wayDidntWork(summary.game) }
    }

    /// Opens the report form in the browser, filled in; the player sends it there, or doesn't.
    @ViewBuilder private var shareButton: some View {
        if let rating = GameRatings.load(summary.game.gameID) {
            let share = { model.shareReport(summary.game, rating: rating) }
            Button(L10n.t("Share Report …"), action: share)
                .buttonStyle(GlassTextButtonStyle(small: true))
                .help(L10n.t("Opens a GitHub form in your browser, filled in with the game, your answer and the way it ran – no paths, account names or logs. GitHub gets these values as the page opens; the report is public only once you submit it, with your GitHub name on it."))
                .padFocus("session.share", cornerRadius: 16, activate: share)
        }
    }

    /// Crashes, glitches and stutters are what "Most compatible" is for – in Nightforge's own Windows games.
    private var suggestsCompatible: Bool {
        let game = summary.game
        return game.bottle.isBuiltIn && game.platform == .windows && !issues.isDisjoint(with: [.crashed, .glitches, .stutters])
            && GameOptionsStore.load(game.gameID).preset != .compatible
    }

    private func useCompatible() {
        GameOptionsStore.choose(.compatible, for: summary.game.gameID)
        compatibleNext = true
        save(good: false)
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
