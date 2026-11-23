import Foundation

/// What a start is busy with, for the Play button, with a line underneath that says why it takes
/// a moment: no wait without an explanation.
enum LaunchPhase: Equatable {
    case startingSteam
    case startingSteamForMac
    /// Waiting while Steam signs in by itself.
    case signingIn
    /// The other Steam (for Mac, or the Windows one) had the account meanwhile: this one signs in afresh, or the game
    /// would start without its cloud saves.
    case signingInAgain
    /// Steam finishes its first Steam Cloud sync before the game starts.
    case steamCloudSync
    case signInInSteamWindow
    /// A Steam that signed in by itself before asks for a fresh sign-in (its remembered one ran out).
    case signInAgain
    /// The other Steam is still putting the last game's save into the Steam Cloud (SteamSwitch).
    case savingToCloud
    case settingUp
    case settingUpDotNet
    /// Steam got stuck starting or signing in: it's restarted.
    case restartingSteam
    /// A planned restart, not a fault: the game takes settings from Steam's environment (Engine.prepareLaunchEnvironment),
    /// and Steam runs with another game's.
    case restartingSteamForGame
    /// The signed-in Steam stopped taking commands (SteamCommands): it's restarted.
    case steamNotResponding
    /// It ended at once: the next way, by its name.
    case retrying(String)
    /// Steam updates the game before it starts it: how far, when known.
    case updating(Double?)
    /// Epic gives the game a fresh sign-in (legendary).
    case signingInEpic
    /// The newest save comes down from the store's cloud first (Epic, GOG).
    case syncingSaves
    /// The newest engine crashed a game that ran well on the one before: it starts again with that one.
    case rollingBack
    /// A game held back on the previous engine: Steam moves over to that one first.
    case heldEngine
    /// A GOG game's Windows parts (GOG Galaxy's redistributables), before its first start: the
    /// part being installed (nil while they come from GOG), named in the line below the button.
    case settingUpWindowsParts(String?)
    /// Blizzard's client isn't up yet: it starts hidden.
    case startingBattleNet
    /// The client wants the player's sign-in: its window is open.
    case signInInBattleNetWindow
    /// The client hasn't started the game and may be asking something: its window is open.
    case battleNetAsks
    /// The player said yes to Steam's licence; the game starts now.
    case licenceAnswered

    var title: String {
        switch self {
        case .startingSteam: return L10n.t("Starting Steam …")
        case .startingSteamForMac: return L10n.t("Starting Steam for Mac …")
        case .signingIn, .signingInAgain: return L10n.t("Signing in to Steam …")
        case .steamCloudSync: return L10n.t("Getting your save …")
        case .signInInSteamWindow, .signInAgain: return L10n.t("Sign in in the Steam window")
        case .savingToCloud: return L10n.t("Saving to Steam Cloud …")
        case .settingUp: return L10n.t("Setting up the game …")
        case .settingUpDotNet: return L10n.t("Setting up .NET for the game …")
        case .restartingSteam: return L10n.t("Restarting Steam …")
        case .restartingSteamForGame: return L10n.t("Getting Steam ready for the game …")
        case .steamNotResponding: return L10n.t("Steam isn't responding – restarting it …")
        case .retrying(let way): return L10n.t("Starting again with %@ …", way)
        case .updating(let fraction?): return L10n.t("Updating … %ld %%", Int(fraction * 100))
        case .updating(nil): return L10n.t("Updating …")
        case .signingInEpic: return L10n.t("Signing in to Epic Games …")
        case .syncingSaves: return L10n.t("Getting your save …")
        case .rollingBack: return L10n.t("Trying the previous engine …")
        case .heldEngine: return L10n.t("Starting with the previous engine …")
        case .settingUpWindowsParts: return L10n.t("Setting up the game …")
        case .startingBattleNet: return L10n.t("Starting Battle.net …")
        case .signInInBattleNetWindow: return L10n.t("Sign in in the Battle.net window")
        case .battleNetAsks: return L10n.t("Battle.net is waiting for you")
        case .licenceAnswered: return L10n.t("Thanks. The game is starting …")
        }
    }

    var hint: String {
        switch self {
        case .startingSteam: return L10n.t("Steam runs invisibly in the background – it only has to start once.")
        case .startingSteamForMac: return L10n.t("The Mac version starts through Steam for Mac, which runs in the background.")
        case .signingIn: return L10n.t("Steam signs in with your account.")
        case .signingInAgain: return L10n.t("Steam signs in again, so your cloud saves come along.")
        case .steamCloudSync: return L10n.t("Steam brings your newest save from Steam Cloud first.")
        case .signInInSteamWindow: return L10n.t("Steam needs you to sign in – its window is open.")
        case .signInAgain: return L10n.t("Steam asks you to sign in again – it does that every few months. Its window is open.")
        case .savingToCloud: return L10n.t("The last game's save goes up to Steam Cloud first, so it's there wherever you play next.")
        case .settingUp: return L10n.t("Installing what the game needs from Windows. Only the first time.")
        case .settingUpDotNet: return L10n.t("Installing .NET, which this game needs. Only the first time.")
        case .restartingSteam: return L10n.t("Steam got stuck while starting – a fresh start fixes that.")
        case .restartingSteamForGame: return L10n.t("Steam starts again with the settings this game needs.")
        case .steamNotResponding: return L10n.t("Steam stopped taking requests. A fresh start fixes that – the game starts right after.")
        case .retrying: return L10n.t("It closed right away – Nightforge starts it the next way and remembers what works.")
        case .updating: return L10n.t("Steam updates the game first – it starts by itself when the update is done.")
        case .signingInEpic: return L10n.t("The game gets a fresh sign-in from Epic, so it starts online with your account.")
        case .syncingSaves: return L10n.t("Your newest save comes from Epic's cloud first, so you go on where you stopped.")
        case .rollingBack:
            return L10n.t("The newest engine crashed this game, so Nightforge starts it with the previous one – nothing to do. It tries the new one again after the next update.")
        case .heldEngine:
            return L10n.t("The newest engine crashed this game, so it runs with the previous one – Steam starts again with that one first.")
        case .settingUpWindowsParts(let part?):
            return L10n.t("Windows part: %@ – the game needs it. Only the first time.", part)
        case .settingUpWindowsParts(nil):
            return L10n.t("The Windows parts the game needs come from GOG. Only the first time.")
        case .startingBattleNet: return L10n.t("Blizzard's games start through Battle.net, which runs in the background.")
        case .signInInBattleNetWindow: return L10n.t("Battle.net needs you to sign in. Its window is open.")
        case .battleNetAsks: return L10n.t("Its window is open: answer there, or press Play in it.")
        case .licenceAnswered: return L10n.t("Steam won't ask again.")
        }
    }

    /// The curtain's line for it: none while Nightforge only waits – "at a console nobody wants to know what happens
    /// technically" (the user, 22.11.2026); the light running along the seam says it's under way. A line only where
    /// the player has something to do, and for an update, whose real figures are what a console shows as well.
    /// What the phase is goes to the log (`kind`); the Play button keeps `title`.
    var curtainTitle: String? {
        switch self {
        case .signInInSteamWindow, .signInAgain, .signInInBattleNetWindow, .battleNetAsks, .updating: return title
        default: return nil
        }
    }

    /// The short sentence under the curtain's line: only where the player has a window to answer in. What `hint`
    /// says is in the log as the phase begins.
    var curtainSentence: String? {
        switch self {
        case .signInInSteamWindow, .signInAgain, .signInInBattleNetWindow: return L10n.t("Its window is open.")
        case .battleNetAsks: return hint
        default: return nil
        }
    }

    /// Something done once per game, which can take minutes (Windows parts, .NET): after `firstTimeAfter` the
    /// curtain says quietly that the first time takes longer.
    var onlyTheFirstTime: Bool {
        switch self {
        case .settingUp, .settingUpDotNet, .settingUpWindowsParts: return true
        default: return false
        }
    }

    /// How long a first start's wait goes without a word: the one sentence comes only at a wait this long.
    static let firstTimeAfter: TimeInterval = 60
    /// That sentence.
    static var firstTimeSentence: String { L10n.t("The first time takes a little longer.") }

    /// For the log, once a phase begins: an update's figures don't make a new one.
    var kind: String {
        if case .updating = self { return "updating" }
        return "\(self)"
    }

    /// While Steam starts the game itself, the first time with new graphics: shaders are built then.
    static var shaderHint: String { L10n.t("First start with this graphics version: shaders are prepared, so it can take a minute. Next time it's quicker.") }
    /// `updating` for an Epic or GOG game: legendary or gogdl fetches the update, not Steam.
    static func storeUpdateHint(_ provider: Provider, speed: String? = nil) -> String {
        guard let speed else { return L10n.t("The update comes from %@ first – the game starts by itself when it's done.", provider.label) }
        return L10n.t("%@ – the update comes from %@ first, the game starts by itself when it's done.", speed, provider.label)
    }
    /// `updating` through Steam once its speed is known (`UpdateProgress`).
    static func steamUpdateHint(speed: String) -> String {
        L10n.t("%@ – Steam updates the game first, it starts by itself when the update is done.", speed)
    }
    /// `syncingSaves` for a GOG game.
    static var gogSavesHint: String { L10n.t("Your newest save comes from GOG's cloud first, so you go on where you stopped.") }
    static var confirmHint: String { L10n.t("Steam asks something before the game starts – answer it in its window.") }

    // MARK: - First start with new graphics

    private static func shaderKey(_ game: GameID) -> String { "shaders.\(game.key)" }

    /// What the shaders depend on: the engine, the layer and the graphics builds in the component list.
    static func graphicsSignature(runner: String?, layer: GraphicsLayer, components: [Component]) -> String {
        let builds = components.filter { $0.kind == .graphics }.map { "\($0.id)@\($0.version)" }.sorted()
        return ([runner ?? "", layer.rawValue] + builds).joined(separator: "|")
    }

    /// How many signatures a game keeps: the ways it changes between and back, and the engine and graphics updates.
    static let signaturesKept = 12

    /// Every signature the game has started with, the newest last. An entry from before 15.11.2026 holds only the
    /// last one, as a string: it's taken over, so the update brings no "Preparing shaders …" at each game's next start.
    static func seenSignatures(_ game: GameID, defaults: UserDefaults = .standard) -> [String] {
        let value = defaults.object(forKey: shaderKey(game))
        if let list = value as? [String] { return list }
        return (value as? String).map { [$0] } ?? []
    }

    /// Shaders are built at a start with a signature the game never had. Kept was only the last one: MGS V, changing
    /// between D3DMetal and DXMT on 15.11.2026, said "Preparing shaders …" at almost every start.
    static func isFirstStart(_ game: GameID, signature: String, defaults: UserDefaults = .standard) -> Bool {
        !seenSignatures(game, defaults: defaults).contains(signature)
    }

    static func recordStart(_ game: GameID, signature: String, defaults: UserDefaults = .standard) {
        let seen = seenSignatures(game, defaults: defaults).filter { $0 != signature } + [signature]
        defaults.set(Array(seen.suffix(signaturesKept)), forKey: shaderKey(game))
    }
}
