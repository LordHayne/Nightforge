import Foundation

/// What a start is busy with, for the Play button, with a line underneath that says why it takes
/// a moment: no wait without an explanation.
enum LaunchPhase: Equatable {
    case startingSteam
    case startingSteamForMac
    case signingIn
    case signInInSteamWindow
    /// A Steam that signed in by itself before asks for a fresh sign-in (its remembered one ran out).
    case signInAgain
    /// The other Steam is still putting the last game's save into the Steam Cloud (SteamSwitch).
    case savingToCloud
    case settingUp
    case settingUpDotNet
    case restartingSteam
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

    var title: String {
        switch self {
        case .startingSteam: return L10n.t("Starting Steam …")
        case .startingSteamForMac: return L10n.t("Starting Steam for Mac …")
        case .signingIn: return L10n.t("Signing in to Steam …")
        case .signInInSteamWindow, .signInAgain: return L10n.t("Sign in in the Steam window")
        case .savingToCloud: return L10n.t("Saving to Steam Cloud …")
        case .settingUp: return L10n.t("Setting up the game …")
        case .settingUpDotNet: return L10n.t("Setting up .NET for the game …")
        case .restartingSteam: return L10n.t("Restarting Steam …")
        case .steamNotResponding: return L10n.t("Steam isn't responding – restarting it …")
        case .retrying(let way): return L10n.t("Starting again with %@ …", way)
        case .updating(let fraction?): return L10n.t("Updating … %ld %%", Int(fraction * 100))
        case .updating(nil): return L10n.t("Updating …")
        case .signingInEpic: return L10n.t("Signing in to Epic Games …")
        case .syncingSaves: return L10n.t("Getting your save …")
        case .rollingBack: return L10n.t("Trying the previous engine …")
        case .heldEngine: return L10n.t("Starting with the previous engine …")
        case .settingUpWindowsParts: return L10n.t("Setting up the game …")
        }
    }

    var hint: String {
        switch self {
        case .startingSteam: return L10n.t("Steam runs invisibly in the background – it only has to start once.")
        case .startingSteamForMac: return L10n.t("The Mac version starts through Steam for Mac, which runs in the background.")
        case .signingIn: return L10n.t("Steam signs in again, so your cloud saves come along.")
        case .signInInSteamWindow: return L10n.t("Steam needs you to sign in – its window is open.")
        case .signInAgain: return L10n.t("Steam asks you to sign in again – it does that every few months. Its window is open.")
        case .savingToCloud: return L10n.t("The last game's save goes up to Steam Cloud first, so it's there wherever you play next.")
        case .settingUp: return L10n.t("Installing what the game needs from Windows. Only the first time.")
        case .settingUpDotNet: return L10n.t("Installing .NET, which this game needs. Only the first time.")
        case .restartingSteam: return L10n.t("Steam got stuck while starting – a fresh start fixes that.")
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
        }
    }

    /// While Steam starts the game itself, the first time with new graphics: shaders are built then.
    static var shaderHint: String { L10n.t("First start with this graphics version: shaders are prepared, so it can take a minute. Next time it's quicker.") }
    /// `updating` for an Epic or GOG game: legendary or gogdl fetches the update, not Steam.
    static func storeUpdateHint(_ provider: Provider) -> String {
        L10n.t("The update comes from %@ first – the game starts by itself when it's done.", provider.label)
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

    static func isFirstStart(_ game: GameID, signature: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: shaderKey(game)) != signature
    }

    static func recordStart(_ game: GameID, signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: shaderKey(game))
    }
}
