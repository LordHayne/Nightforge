import Foundation

/// A Unity Mac version's very first start in full screen. Unity keeps the screen mode in the game's preferences
/// ("Screenmanager Fullscreen mode", 0 exclusive, 1 full-screen window, 2 maximised window, 3 window) and starts
/// with the build's own default until there is one ("… Default" beside it). Valheim's default is a window of
/// 1366×768 (com.coffeestain.valheim-steam: "Screenmanager Fullscreen mode Default" = 3): on the user's new Mac on
/// 21.11.2026 it came up small, with a title bar, over Nightforge's page, menu bar and Dock showing.
///
/// Unity's own switch for it, `-screen-fullscreen 1`, goes along only while the game has no mode of its own yet.
/// Unity keeps what it ran with when it quits, so from the second start on the game's own value rules, and a
/// player who picks a window in the game keeps it. Not its preferences written beforehand: Unity resets a saved
/// mode whose "… Default" differs from the build's, which Nightforge can't read, and older Unity keeps its
/// preferences under "unity.<company>.<product>" (Hearthstone) rather than the bundle identifier. The switch
/// isn't a way of the start ladder's either: Mac versions have none (LaunchHealth is Wine's).
enum MacUnityScreen {
    static let modeKey = "Screenmanager Fullscreen mode"
    static let argument = "-screen-fullscreen 1"

    /// Switches of a player's own that set the screen: then theirs rule.
    static let screenSwitches = ["-screen-fullscreen", "-window-mode", "-popupwindow", "-screen-width", "-screen-height"]

    enum Decision: Equatable {
        /// No Unity app in the folder: nothing to do.
        case notUnity
        /// The game keeps its mode already (`domain`, `mode`).
        case kept(domain: String, mode: Int)
        /// The player's own arguments set the screen.
        case playersOwn
        /// No mode of its own yet: the switch goes along.
        case fullScreen(domain: String)
    }

    /// For one Unity app: its preference domains and what each holds for the mode (`saved`), and the player's own
    /// arguments for the game.
    static func decide(unity: Bool, domains: [String], saved: [String: Int], playerArguments: String) -> Decision {
        guard unity else { return .notUnity }
        if let domain = domains.first(where: { saved[$0] != nil }), let mode = saved[domain] { return .kept(domain: domain, mode: mode) }
        let words = playerArguments.lowercased().split(separator: " ").map(String.init)
        if words.contains(where: { word in screenSwitches.contains(word) }) { return .playersOwn }
        return .fullScreen(domain: domains.first ?? "?")
    }

    /// The arguments the start goes with: the player's, and the switch where it's decided so.
    static func arguments(_ playerArguments: String, _ decision: Decision) -> String {
        guard case .fullScreen = decision else { return playerArguments }
        return playerArguments.isEmpty ? argument : playerArguments + " " + argument
    }

    /// Where a Unity Mac player keeps its preferences: its bundle identifier (Valheim), or – older Unity –
    /// "unity.<company>.<product>" (Hearthstone: "unity.Blizzard Entertainment.Hearthstone"), found among the
    /// preference files by the product's name.
    static func domains(bundleID: String?, product: String?, preferenceFiles: [String]) -> [String] {
        let legacy = product.map { name in
            preferenceFiles.filter { $0.hasPrefix("unity.") && $0.hasSuffix(".\(name).plist") }.map { String($0.dropLast(6)) }.sorted()
        } ?? []
        return (bundleID.map { [$0] } ?? []) + legacy
    }

    /// Whether an app is a Unity player: its player library (Unity 2019.3 and later), or its data folder's files.
    static func isUnity(_ app: URL) -> Bool {
        let fm = FileManager.default
        return ["Contents/Frameworks/UnityPlayer.dylib", "Contents/Resources/Data/globalgamemanagers",
                "Contents/Resources/Data/mainData", "Contents/Resources/Data/data.unity3d",
                "Contents/Resources/Data/Managed/UnityEngine.dll", "Contents/Resources/unity default resources"]
            .contains { fm.fileExists(atPath: app.appendingPathComponent($0).path) }
    }

    /// The apps a game's folder holds; a folder that is an app (a GOG Mac version) is the one.
    static func apps(in folder: URL) -> [URL] {
        folder.pathExtension == "app" ? [folder] : ControllerCompatibility.apps(in: folder)
    }

    /// Before a Mac version starts (only reading): what its Unity apps keep, and with that the decision. Several
    /// apps: the first Unity one without a mode of its own decides for the switch, else the first one that has one.
    /// `kept`: the mode a domain keeps (`modeKey`), read through CFPreferences; tests hand in their own instead of writing
    /// a game's domain into the Mac's preferences.
    static func look(installDir: URL, playerArguments: String,
                     preferences: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences"),
                     kept: (String) -> Int? = { CFPreferencesCopyAppValue(modeKey as CFString, $0 as CFString) as? Int }) -> Decision {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
        var first: Decision = .notUnity
        for app in apps(in: installDir) where isUnity(app) {
            let info = Bundle(url: app)?.infoDictionary
            let product = (info?["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent
            let domains = domains(bundleID: info?["CFBundleIdentifier"] as? String, product: product, preferenceFiles: files)
            var saved: [String: Int] = [:]
            for domain in domains {
                if let mode = kept(domain) { saved[domain] = mode }
            }
            let decision = decide(unity: true, domains: domains, saved: saved, playerArguments: playerArguments)
            if case .fullScreen = decision { return decision }
            if first == .notUnity { first = decision }
        }
        return first
    }

    /// The log's line for it; nil without a Unity app.
    static func note(_ decision: Decision, game: String) -> String? {
        switch decision {
        case .notUnity: return nil
        case .kept(let domain, let mode):
            return "Mac version of \(game): its screen mode as the game keeps it (\(domain): \(modeKey) \(mode)), no switch"
        case .playersOwn:
            return "Mac version of \(game): the player's own arguments set its screen, no switch"
        case .fullScreen(let domain):
            return "Mac version of \(game): a Unity app with no screen mode of its own yet (\(domain)) – it starts in full screen (\(argument))"
        }
    }
}
