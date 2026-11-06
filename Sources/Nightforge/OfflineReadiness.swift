import Foundation

/// Whether an installed game can be played without internet, as far as Nightforge can tell:
/// Steam's offline mode needs an account it remembers, and the game must not need anything online.
enum OfflineReadiness: Equatable {
    case ready
    /// Never started here: many games set themselves up online the first time.
    case startOnlineOnce
    /// An update is waiting, and Steam won't start the game offline until it's done.
    case updateFirst
    /// Steam lists no single-player mode.
    case onlineOnly
    /// It starts through another launcher that signs in online.
    case launcher(String)
    /// Steam doesn't remember the account, so it can't start offline at all.
    case signInRemembered
    /// Epic Games doesn't approve it for offline play.
    case epicOnline
    /// Epic Games signed the player out: without the account, no start at all.
    case epicSignedOut
    /// A GOG game: DRM-free, it needs no account and no internet to start.
    case drmFree
    /// A Battle.net game: the client has to run, signed in.
    case battleNet

    /// `accountRemembered`: for Epic games, that Nightforge is signed in to Epic.
    static func of(_ game: Game, analysis: GameAnalysis?, accountRemembered: Bool) -> OfflineReadiness {
        if game.provider == .gog { return analysis?.launcher.map { .launcher($0) } ?? .drmFree }
        if game.provider == .battlenet { return .battleNet }
        let epic = game.provider == .epic
        if !accountRemembered { return epic ? .epicSignedOut : .signInRemembered }
        if game.onlineOnly { return epic ? .epicOnline : .onlineOnly }
        if let launcher = analysis?.launcher { return .launcher(launcher) }
        // An Epic game starts offline with the version it has (legendary doesn't check then).
        if game.pendingUpdate != nil && !epic { return .updateFirst }
        if game.lastPlayed == nil { return .startOnlineOnce }
        return .ready
    }

    var label: String {
        switch self {
        case .ready, .drmFree: return L10n.t("Ready")
        case .startOnlineOnce: return L10n.t("Start online once")
        case .updateFirst: return L10n.t("Update first")
        case .onlineOnly, .launcher, .epicOnline, .battleNet: return L10n.t("Needs internet")
        case .signInRemembered, .epicSignedOut: return L10n.t("Not yet")
        }
    }

    var help: String {
        switch self {
        case .ready: return L10n.t("Plays without internet: Steam remembers your account and nothing in the game needs to be online.")
        case .startOnlineOnce: return L10n.t("Start it once while online – many games set themselves up the first time. After that it plays offline.")
        case .updateFirst: return L10n.t("An update is waiting; Steam won't start the game offline until it's downloaded.")
        case .onlineOnly: return L10n.t("Steam lists no single-player mode for it – it needs internet.")
        case .launcher(let name): return L10n.t("It starts through %@, which signs in online.", name)
        case .signInRemembered: return L10n.t("Steam doesn't remember your account: sign in once with “Remember me” so it can start offline.")
        case .epicOnline: return L10n.t("Epic Games doesn't approve it for offline play – it needs internet.")
        case .epicSignedOut: return L10n.t("Epic Games signed you out: sign in again in Settings › Stores, then it starts offline too.")
        case .drmFree: return L10n.t("GOG's games are DRM-free: it plays without internet and without signing in.")
        case .battleNet: return L10n.t("Battle.net has to run and be signed in to start it: it needs internet.")
        }
    }

    /// Steam remembers an account in this Steam (loginusers.vdf: "RememberPassword" 1).
    static func accountRemembered(steamRoot: URL) -> Bool {
        guard let users = VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        else { return false }
        return users.values.contains { $0["rememberpassword"]?.string == "1" }
    }
}
