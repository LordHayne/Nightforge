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

    private(set) var sawPicture = false
    /// The player went elsewhere, or the tries ran out: nothing until the game is in front again.
    private(set) var left = false
    private(set) var tries = 0
    private var awaySince: Date?
    private var lastTry: Date?

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
