import Foundation

/// The way out of a curtain that has no game under it yet: Steam hanging, or Steam's update, which has
/// no time limit. B took the curtain away once (1.11.), and the store started the game anyway with nobody
/// watching, so B does nothing on a curtain over a game that's on its way. With no process of the game's
/// for a while there's nothing to break: Nightforge stops waiting and goes back, Steam and its update are
/// left as they are, and a game Steam still starts is followed to its end.
enum CurtainEscape {
    enum Reason: Equatable { case steamQuiet, updating, updateStuck }

    struct Look: Equatable {
        /// A process of the game's is there, or its curtain has come down.
        var gameRuns: Bool
        /// The start is still Nightforge's to wait for.
        var startGoesOn: Bool
        /// macOS asks something the start waits for: that comes first.
        var questionUp = false
        /// How long the curtain has stood without a process of the game's.
        var waited: TimeInterval
        var updating = false
        /// How long the update's progress hasn't moved; nil while Steam gives no figures to go by.
        var updateStillFor: TimeInterval?
        /// When the player was last asked, whether by this or by pressing B.
        var askedAgo: TimeInterval?
    }

    /// From here on B and Esc lead out, and the curtain says so: a cold Steam takes about this long.
    static let openAfter: TimeInterval = 30
    /// A silent Steam gets the question by itself after this, before Nightforge's own limit of 2 min.
    static let askAfter: TimeInterval = 90
    /// An update whose figures don't move for this long: stuck, with room for Steam's pauses between steps.
    static let updateStuckAfter: TimeInterval = 180
    /// After "Keep Waiting". Steam updating itself on a first start can take minutes.
    static let askAgainAfter: TimeInterval = 120

    /// Why the player may want out; nil while there's no way out to offer.
    static func reason(_ look: Look) -> Reason? {
        guard !look.gameRuns, look.startGoesOn, !look.questionUp, look.waited >= openAfter else { return nil }
        guard look.updating else { return .steamQuiet }
        return (look.updateStillFor ?? 0) >= updateStuckAfter ? .updateStuck : .updating
    }

    /// Whether the question comes up by itself. An update that moves doesn't ask: B is there for that.
    static func asks(_ look: Look) -> Bool {
        guard (look.askedAgo ?? .infinity) >= askAgainAfter else { return false }
        switch reason(look) {
        case .steamQuiet?: return look.waited >= askAfter
        case .updateStuck?: return true
        case .updating?, nil: return false
        }
    }

    /// The line on the curtain: B on the controller drawn, or Esc without one.
    static func tip(pad: PadSymbols?) -> LaunchTip {
        guard let pad else { return LaunchTip(symbols: [], text: L10n.t("Stuck? Esc takes you back to Nightforge")) }
        return LaunchTip(symbols: [pad.back], text: L10n.t("Stuck? Back to Nightforge"))
    }

    static func title(_ reason: Reason, game: String) -> String {
        switch reason {
        case .steamQuiet: return L10n.t("Steam isn't answering")
        case .updating: return L10n.t("Steam is updating %@", game)
        case .updateStuck: return L10n.t("The update of %@ isn't moving", game)
        }
    }

    static func text(_ reason: Reason, game: String) -> String {
        switch reason {
        case .steamQuiet:
            return L10n.t("%@ hasn't started yet. You can keep waiting or go back to Nightforge. Going back breaks nothing.", game)
        case .updating:
            return L10n.t("That can take a while. You can go back to Nightforge: Steam keeps updating and starts the game by itself afterwards.")
        case .updateStuck:
            return L10n.t("Steam hasn't got any further for a while. You can go back to Nightforge: the update carries on once Steam can, and your saves stay as they are.")
        }
    }
}
