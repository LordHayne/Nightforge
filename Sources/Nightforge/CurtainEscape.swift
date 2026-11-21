import Foundation

/// The way out of a curtain that has no game under it yet: Steam hanging, or Steam's update, which has
/// no time limit. B took the curtain away once (1.11.), and the store started the game anyway with nobody
/// watching, so B does nothing on a curtain over a game that's on its way. With no process of the game's
/// for a while there's nothing to break: Nightforge stops waiting and goes back, Steam and its update are
/// left as they are, and a game Steam still starts is followed to its end.
enum CurtainEscape {
    enum Reason: Equatable {
        case storeQuiet, updating, updateStuck
        /// Epic's or GOG's update or save, which Nightforge runs itself: nothing is with a store yet, so B
        /// ends the start at once, as it does from the Play button.
        case ownUpdate, ownSaves
        /// Steam's question stands on the curtain: B goes back at once, the bar says so.
        case steamAsks

        var atOnce: Bool { self == .ownUpdate || self == .ownSaves || self == .steamAsks }
    }

    struct Words: Equatable {
        let title: String
        let text: String
    }

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
        /// Nightforge's own work for Epic or GOG (`Reason.ownUpdate`, `ownSaves`).
        var ownUpdate = false
        var ownSaves = false
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
        guard !look.gameRuns, look.startGoesOn, !look.questionUp else { return nil }
        if look.ownUpdate { return .ownUpdate }
        if look.ownSaves { return .ownSaves }
        guard look.waited >= openAfter else { return nil }
        guard look.updating else { return .storeQuiet }
        return (look.updateStillFor ?? 0) >= updateStuckAfter ? .updateStuck : .updating
    }

    /// Whether the question comes up by itself. An update that moves doesn't ask: B is there for that.
    static func asks(_ look: Look) -> Bool {
        guard (look.askedAgo ?? .infinity) >= askAgainAfter else { return false }
        switch reason(look) {
        case .storeQuiet?: return look.waited >= askAfter
        case .updateStuck?: return true
        case .updating?, .ownUpdate?, .ownSaves?, .steamAsks?, nil: return false
        }
    }

    /// The line on the curtain: B on the controller drawn, or Esc without one.
    static func tip(_ reason: Reason, pad: PadSymbols?) -> LaunchTip {
        let symbols = pad.map { [$0.back] } ?? []
        switch reason {
        case .ownUpdate:
            return LaunchTip(symbols: symbols, text: pad == nil ? L10n.t("Esc stops for now, the update carries on next time")
                                                                : L10n.t("Stop for now, the update carries on next time"))
        case .ownSaves, .steamAsks:
            return LaunchTip(symbols: symbols, text: pad == nil ? L10n.t("Esc takes you back to Nightforge") : L10n.t("Back to Nightforge"))
        case .storeQuiet, .updating, .updateStuck:
            return LaunchTip(symbols: symbols, text: pad == nil ? L10n.t("Stuck? Esc takes you back to Nightforge") : L10n.t("Stuck? Back to Nightforge"))
        }
    }

    /// What the question says; `store`: whose start it is.
    static func words(_ reason: Reason, game: String, store: String) -> Words {
        Words(title: title(reason, game: game, store: store), text: text(reason, game: game))
    }

    static func title(_ reason: Reason, game: String, store: String) -> String {
        switch reason {
        case .storeQuiet, .ownUpdate, .ownSaves, .steamAsks: return L10n.t("%@ isn't answering", store)
        case .updating: return L10n.t("Steam is updating %@", game)
        case .updateStuck: return L10n.t("The update of %@ isn't moving", game)
        }
    }

    static func text(_ reason: Reason, game: String) -> String {
        switch reason {
        case .storeQuiet, .ownUpdate, .ownSaves, .steamAsks:
            return L10n.t("Going back breaks nothing.")
        case .updating:
            return L10n.t("Steam keeps updating and starts the game afterwards.")
        case .updateStuck:
            return L10n.t("The update carries on once Steam can, your saves stay as they are.")
        }
    }
}

/// A curtain nobody will take away. Tomb Raider, 8.11. at 22:28: quit through the overlay, Nightforge back
/// in front with "Welcome back", and then Steam Helper coming forward looked like the game's picture going.
/// The curtain came up for a game that had ended, and stayed: B did nothing, the player had to go to the Mac.
extension CurtainEscape {
    /// Who is going to take a raised curtain away.
    struct Owners: Equatable {
        /// A start is in progress, or is judged by its first seconds.
        var starting = false
        /// The curtain's watch runs.
        var watching = false
        /// A game Nightforge follows: its end brings Nightforge back (`playingOwns`).
        var playing = false
        /// Nightforge is on its way back, and takes the curtain with it.
        var comingBack = false

        var anyone: Bool { starting || watching || playing || comingBack }
    }

    /// How long a raised curtain stands with nobody to take it away: longer than the moment one hands it to
    /// the next, short enough that nobody goes looking for the Mac.
    static let orphanAfter: TimeInterval = 5
    /// A game still running holds a curtain over it only this long: longer than a game takes to end.
    static let playingHoldsFor: TimeInterval = 30
    /// Nightforge's way back takes a few seconds at most, however macOS hands over the front.
    static let comingBackHoldsFor: TimeInterval = 12

    static func playingOwns(gamePlaying: Bool, upFor: TimeInterval) -> Bool { gamePlaying && upFor < playingHoldsFor }

    /// Sees how long a raised curtain has been without an owner.
    struct Orphan {
        private var since: Date?

        /// True at the look where it has stood long enough and should go.
        mutating func look(raised: Bool, owners: Owners, now: Date) -> Bool {
            guard raised, !owners.anyone else {
                since = nil
                return false
            }
            guard let since else {
                self.since = now
                return false
            }
            guard now.timeIntervalSince(since) >= orphanAfter else { return false }
            self.since = nil
            return true
        }
    }

    /// Whether a game's picture going or its process ending may still raise the curtain: only for a game
    /// being played, and not once Nightforge is on its way back.
    static func mayRaiseForEnd(gamePlaying: Bool, comingBack: Bool) -> Bool { gamePlaying && !comingBack }

    /// Whether B and Esc lead out: a way out offered for this start, or a curtain nobody owns, at once.
    static func wayOutOpen(raised: Bool, offered: Bool, owners: Owners) -> Bool { raised && (offered || !owners.anyone) }
}
