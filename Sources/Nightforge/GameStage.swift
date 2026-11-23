import Foundation

/// The game's place on the screen from the curtain going down to its end. The curtain's watch looks
/// after the first seconds; this looks after the rest, and after what that watch can't see: an app
/// that stays in front while its window is gone.
///
/// How a game gets lost (The Forest 21:53 on 6.11., wine.log and winecx's source): a Windows game
/// that loses its keys hears it from Wine at once – windowDidResignKey in cocoa_window.m,
/// macdrv_window_lost_focus in window.c – and a Unity or Unreal game in full screen minimises
/// itself then. macOS keeps it the active app, so the menu bar says Nightforge Game while only
/// Nightforge's page shows, and activating it does nothing. Wine brings a minimised window back
/// when it *becomes* active, or at a click on the Dock (cocoa_app.m, applicationDidBecomeActive and
/// applicationShouldHandleReopen, both unminimizeWindowIfNoneVisible) – hence LibraryModel.handFocus
/// with `again`, which takes the front first and hands it back.
///
/// Never against the player: a ⌘ or a click just before it went away means they went themselves, and
/// the game is left alone until it's in front with its picture again. Nothing happens either while
/// no window of a picture's size is there at all – a game building its screen anew or ending – or
/// before it ever showed one.
struct GameStage {
    struct Look: Equatable {
        var gameFront: Bool
        var windowHere: Bool
        var windowAnywhere: Bool
        /// The overlay is open, or macOS asks the player something: they have the front for a reason.
        var handsOff = false
        /// A ⌘ or a click just now (LibraryModel.playerActed).
        var playerActed = false
        /// The curtain's watch still guards the front (it raises the curtain for another app).
        var guarded = false
        var now: Date
    }

    enum Step: Equatable { case wait, bringBack, gaveUp }

    /// How long the game stays away before it's brought back: a game building its window anew, or
    /// one that comes back by itself (The Forest did, once on 6.11.), needs no help.
    static let patience: TimeInterval = 3
    static let retryAfter: TimeInterval = 4
    static let maxTries = 3
    /// How long it stays in front after being brought back before the tries count from zero.
    static let settled: TimeInterval = 10

    /// How recent a ⌘ or a click must be to count as the player leaving when the picture goes. Leaving
    /// is ⌘-Tab or a click on another window, and the front moves within a moment of it. A click on the
    /// game's own Quit comes well before its window closes.
    static let leftWithin: TimeInterval = 0.5
    /// How long the curtain raised for a picture that went stays with the game's process still there.
    /// A game ending takes a few seconds; one still there after this runs on, and the stage has it.
    static let endingPatience: TimeInterval = 10

    /// The game's picture went and another app has the front, nobody having asked for it: what a game
    /// looks like as it ends, its process lingering (ABZU at 16:05 on 8.11.: Steam's Wine in front, the
    /// window off the screen, three seconds until a fetch, then "Back to Nightforge"). The curtain comes
    /// right then, not when the process has gone. What's shown is the curtain instead of whatever lay
    /// under the game, so a game that's only rebuilding its window costs a moment of curtain.
    func pictureWent(_ look: Look) -> Bool {
        sawPicture && !left && !look.handsOff && !look.playerActed && !look.guarded && !look.gameFront && !look.windowHere
    }

    /// Whether that curtain goes again: the game is back in front with its picture, or it has had its time.
    static func curtainEnds(cameBack: Bool, waited: TimeInterval) -> Bool {
        cameBack || waited >= endingPatience
    }

    /// How long the game may keep the front with no window of a picture's size anywhere before that counts as its
    /// picture gone (`wentDark`): longer than a game takes to build its window anew.
    static let darkPatience: TimeInterval = 3

    /// The game's picture went with the game itself still in front: no window of its anywhere, not even one its own
    /// full screen's shield hides (`onlyOwnShield`, hiddenByOwnFullScreen has that one), for `darkPatience`. The
    /// Wukong benchmark on 22.11.2026 (19:36): its window closed, a helper of its started and ran on in front, and the
    /// page behind it stood there with the Dock over it until the process ended – `pictureWent` waits for another app
    /// in front. A click of the player's doesn't hold it back: the game's own Quit is one.
    mutating func wentDark(_ look: Look, onlyOwnShield: Bool) -> Bool {
        guard sawPicture, look.gameFront, !look.windowHere, !look.windowAnywhere, !onlyOwnShield, !look.handsOff, !look.guarded else {
            darkSince = nil
            return false
        }
        guard let since = darkSince else {
            darkSince = look.now
            return false
        }
        guard look.now.timeIntervalSince(since) >= Self.darkPatience else { return false }
        darkSince = nil
        return true
    }

    private var darkSince: Date?

    /// Whether, as that curtain's time runs out, Nightforge comes back instead: no window of the game's left anywhere,
    /// only a process ending in its own time. The Wukong benchmark on 22.11.2026 left a helper running for 1–2 min, and
    /// the page stood there all along. Nothing is ended for it: the process goes when it goes, followed in the background.
    static func endsInBackground(cameBack: Bool, windowAnywhere: Bool, waited: TimeInterval) -> Bool {
        !cameBack && !windowAnywhere && waited >= endingPatience
    }

    private(set) var sawPicture = false
    /// The player went elsewhere, or the tries ran out: nothing until the game is in front again.
    private(set) var left = false
    private(set) var tries = 0
    private var awaySince: Date?
    private var lastTry: Date?
    /// Since when the game has had the front with only its own capture's shield on the screen.
    private var shieldOnlySince: Date?

    /// How long only the game's own shield stands, the game in front, before the curtain says its full screen hides it.
    static let hiddenPatience: TimeInterval = 10

    /// The game's own full screen hides its picture after the curtain went down (`onlyOwnShield`: its capture's shield
    /// on the screen and no window of its over it, GameProcesses.onlyShield). Overwatch on 21.11.2026 switched to
    /// 60 Hz about 25 s after the curtain sank, and its picture never came; the curtain's watch had ended, and the
    /// stage fetched it once and said nothing (LibraryModel.fullScreenWords then, as under the curtain).
    /// Not a game in proper full screen: its window lies over its shield (windowHere). Not one the player sent away:
    /// it isn't in front then, and a ⌘ or a click starts the count again. Not while the curtain's watch still
    /// guards the front, which says it itself, nor under the overlay or a question.
    mutating func hiddenByOwnFullScreen(_ look: Look, onlyOwnShield: Bool) -> Bool {
        guard sawPicture, look.gameFront, !look.windowHere, onlyOwnShield, !look.handsOff, !look.playerActed, !look.guarded else {
            shieldOnlySince = nil
            return false
        }
        let since = shieldOnlySince ?? look.now
        shieldOnlySince = since
        return look.now.timeIntervalSince(since) >= Self.hiddenPatience
    }

    /// The curtain sank over the game's picture.
    mutating func pictureSeen() { sawPicture = true }

    /// Go to Nightforge.
    mutating func playerLeft() { left = true }

    /// The player asks for the game (Switch to Game, Continue Playing): all tries again.
    mutating func again() {
        left = false
        tries = 0
        lastTry = nil
    }

    mutating func step(_ look: Look) -> Step {
        if look.gameFront, look.windowHere {
            sawPicture = true
            left = false
            awaySince = nil
            if let lastTry, look.now.timeIntervalSince(lastTry) >= Self.settled {
                tries = 0
                self.lastTry = nil
            }
            return .wait
        }
        guard sawPicture, !left, !look.handsOff, look.windowAnywhere, look.gameFront || !look.guarded else {
            awaySince = nil
            return .wait
        }
        guard let since = awaySince else {
            if look.playerActed { left = true } else { awaySince = look.now }
            return .wait
        }
        guard look.now.timeIntervalSince(since) >= Self.patience,
              lastTry.map({ look.now.timeIntervalSince($0) >= Self.retryAfter }) ?? true
        else { return .wait }
        guard tries < Self.maxTries else {
            left = true
            return .gaveUp
        }
        tries += 1
        lastTry = look.now
        return .bringBack
    }
}
