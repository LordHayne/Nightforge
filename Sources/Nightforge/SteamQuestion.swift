import Foundation

/// Steam's question on the start's curtain, by kind: its heading there, one line, and nothing more. Steam's window
/// has the question itself; Nightforge never answers it and never picks an answer – not even which save wins.
enum SteamQuestion {
    enum Kind: Equatable {
        /// The game's licence (ShowEula, SteamLicence).
        case licence
        /// Which of the game's launch options to start (ShowGameArgs; seen in Steam for Mac's log, 22.11.2026).
        case launchOption
        /// The Steam Cloud: a sync that failed or saves that disagree (MacSteam.waitsInDialog).
        case cloud
        /// Steam's sign-in window (LaunchPhase.signInInSteamWindow, .signInAgain).
        case signIn
        /// Anything else Steam waits on: said as before, "Steam is asking something".
        case other
    }

    /// Steam's name for the step in a "waiting for user response to <task> \"…\"" line; nil without one.
    static func task(in line: Substring) -> String? {
        let marker = "waiting for user response to "
        guard let range = line.range(of: marker) else { return nil }
        let name = line[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// The kind from what the start knows: the licence as LaunchWatcher saw it, the step's name, the phase.
    static func kind(licence: Bool, task: String?, phase: LaunchPhase?) -> Kind {
        if phase == .signInInSteamWindow || phase == .signInAgain { return .signIn }
        if licence || task == "ShowEula" { return .licence }
        guard let task else { return .other }
        if task == "ShowGameArgs" { return .launchOption }
        if task.localizedCaseInsensitiveContains("cloud") { return .cloud }
        return .other
    }

    /// The heading's second half, after the game's name.
    static func title(_ kind: Kind) -> String {
        switch kind {
        case .licence: return L10n.t("The licence, just once")
        case .launchOption: return L10n.t("How the game should start")
        case .cloud: return L10n.t("Which save counts")
        case .signIn: return L10n.t("Sign in in the Steam window")
        case .other: return L10n.t("Steam is asking something")
        }
    }

    /// The line under the heading, where there's something the player can't see in Steam's window.
    static func note(_ kind: Kind) -> String? {
        switch kind {
        case .licence: return L10n.t("Steam only asks this at the first start.")
        // Both Steams' sign-in windows show a QR code beside the password: Setup.signInNote says so at the first start,
        // the fresh-setup test saw it in the Windows Steam (docs/LIVETEST-LAUFWERK.md, step 4), and Steam for Mac kept
        // its QR open for 40 minutes on 26.10. (docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md).
        case .signIn: return L10n.t("Scan the QR code with the Steam app on your phone.")
        case .launchOption, .cloud, .other: return nil
        }
    }
}
