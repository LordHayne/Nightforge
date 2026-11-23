// Checks the watch over a game once the curtain is down (GameStage): a game that shrank into the Dock
// or lost the front comes back, a player who went elsewhere is left alone, and Nightforge's page
// never stays over a picture: tests/GameStageTest/run.sh
import AppKit

@main
struct GameStageTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let start = Date(timeIntervalSince1970: 1_000_000)

    static func look(_ at: TimeInterval, front: Bool = true, here: Bool = false, anywhere: Bool = true, handsOff: Bool = false,
                     acted: Bool = false, guarded: Bool = false) -> GameStage.Look {
        GameStage.Look(gameFront: front, windowHere: here, windowAnywhere: anywhere || here, handsOff: handsOff, playerActed: acted,
                       guarded: guarded, now: start.addingTimeInterval(at))
    }

    /// In front with its picture once: what a stage starts from.
    static func playing() -> GameStage {
        var stage = GameStage()
        _ = stage.step(look(0, here: true))
        return stage
    }

    static func stage() {
        var never = GameStage()
        check(never.step(look(0)) == .wait && never.step(look(100)) == .wait, "no picture yet: the start's business, not the stage's")

        // The Forest on 6.11.: in front for macOS, its window in the Dock.
        var shrunk = playing()
        check(shrunk.step(look(1)) == .wait, "just gone: it may come back by itself")
        check(shrunk.step(look(1 + GameStage.patience - 0.5)) == .wait, "a moment more")
        check(shrunk.step(look(1 + GameStage.patience)) == .bringBack, "still gone: fetched back, though it counts as in front")
        check(shrunk.step(look(1 + GameStage.patience + 1)) == .wait, "not at every look")
        check(shrunk.step(look(1 + GameStage.patience + GameStage.retryAfter)) == .bringBack, "again after a while")
        check(shrunk.tries == 2, "tries counted")

        var hopeless = playing()
        var at = 1.0
        _ = hopeless.step(look(at))
        var fetched = 0
        var last = GameStage.Step.wait
        while at < 60, last != .gaveUp {
            at += 1
            last = hopeless.step(look(at))
            if last == .bringBack { fetched += 1 }
        }
        check(fetched == GameStage.maxTries && last == .gaveUp, "it won't come: a few tries, then no more flipping of the front")
        check(hopeless.step(look(at + 100)) == .wait, "and left alone")
        hopeless.again()
        _ = hopeless.step(look(at + 101))
        check(hopeless.step(look(at + 105)) == .bringBack, "Switch to Game or Continue Playing: all tries again")

        // The tries count anew once it stayed.
        var back = playing()
        _ = back.step(look(1))
        _ = back.step(look(1 + GameStage.patience))
        _ = back.step(look(5, here: true))
        check(back.tries == 1, "back in front, the try still counts")
        _ = back.step(look(5 + GameStage.settled, here: true))
        check(back.tries == 0, "it stayed: the tries count from zero")

        // Who has the front.
        var stolen = playing()
        _ = stolen.step(look(1, front: false, here: true))
        check(stolen.step(look(1 + GameStage.patience, front: false, here: true)) == .bringBack, "another app took the front by itself: the game gets it back")

        var player = playing()
        _ = player.step(look(1, front: false, here: true, acted: true))
        check(player.left, "⌘-Tab or a click: the player went")
        check(player.step(look(30, front: false, here: true)) == .wait, "and stays gone as long as they like")
        _ = player.step(look(31, here: true))
        check(!player.left, "back in the game: looked after again")

        var quit = playing()
        quit.playerLeft()
        check(quit.step(look(30, front: false)) == .wait, "Go to Nightforge: left alone, without any key or click (the pad)")

        // What holds it.
        var ending = playing()
        _ = ending.step(look(1, front: false, anywhere: false))
        check(ending.step(look(30, front: false, anywhere: false)) == .wait, "no window of a picture's size anywhere: ending or building its screen")
        var overlay = playing()
        _ = overlay.step(look(1, handsOff: true))
        check(overlay.step(look(30, handsOff: true)) == .wait, "the overlay or a question of macOS's has the front")
        var guarded = playing()
        _ = guarded.step(look(1, front: false, here: true, guarded: true))
        check(guarded.step(look(30, front: false, here: true, guarded: true)) == .wait, "another app in the curtain's guard time: its watch raises the curtain")
        var shrunkGuarded = playing()
        _ = shrunkGuarded.step(look(1, guarded: true))
        check(shrunkGuarded.step(look(1 + GameStage.patience, guarded: true)) == .bringBack, "shrunk in the guard time: that watch can't see it, this one does")
        var seen = GameStage()
        seen.pictureSeen()
        _ = seen.step(look(1))
        check(seen.step(look(1 + GameStage.patience)) == .bringBack, "gone right as the curtain sank, before any look of its own")
    }

    static func window(_ number: Int, owner: pid_t, _ width: Int = 1512, _ height: Int = 949, layer: Int = 0) -> [String: Any] {
        [kCGWindowNumber as String: number as NSNumber, kCGWindowOwnerPID as String: owner as NSNumber,
         kCGWindowLayer as String: layer as NSNumber, kCGWindowAlpha as String: 1.0 as NSNumber,
         kCGWindowBounds as String: ["X": 0 as NSNumber, "Y": 0 as NSNumber, "Width": width as NSNumber, "Height": height as NSNumber]]
    }

    /// Valheim on 7.11.: a Mac version's windows lie at the page's level.
    static func page() {
        let game: Set<pid_t> = [7]
        let over = [window(10, owner: 1), window(20, owner: 7), window(30, owner: 1, 2000, 1000)]
        check(GameProcesses.pageCovers(over, page: 10, pids: game), "the page in front of the game's picture")
        check(!GameProcesses.pageCovers(over, page: 30, pids: game), "behind it, as it should be")
        check(!GameProcesses.pageCovers(over, page: 99, pids: game), "not on this Space")
        check(!GameProcesses.pageCovers([window(10, owner: 1), window(20, owner: 7, 400, 300)], page: 10, pids: game), "over a small window of the game's: no picture")
        check(!GameProcesses.pageCovers([window(20, owner: 7, layer: 27), window(10, owner: 1), window(21, owner: 7)], page: 10, pids: game),
              "its full-screen window above the page, an old one under it: all well")
    }

    /// The page right under a game over the whole screen, and nowhere near one in a window.
    static func underGame() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let game: Set<pid_t> = [7]
        let shieldLevel = Int(CGShieldingWindowLevel())
        check(GameProcesses.pictureLevel([window(20, owner: 7, 1512, 982, layer: 26)], pids: game, screen: screen) == 26, "ABZU's window over the screen, L26")
        check(GameProcesses.pictureLevel([window(20, owner: 7, 1512, 982, layer: shieldLevel + 2), window(21, owner: 7, 1512, 982, layer: shieldLevel)],
                                         pids: game, screen: screen) == shieldLevel + 2, "Overwatch over its shield: its window's level, not the shield's")
        check(GameProcesses.pictureLevel([window(21, owner: 7, 1512, 982, layer: shieldLevel)], pids: game, screen: screen) == nil, "only the shield: no picture to lie under")
        check(GameProcesses.pictureLevel([window(20, owner: 7, 900, 500, layer: 26)], pids: game, screen: screen) == nil, "a small window doesn't cover the screen")
        check(GameProcesses.pictureLevel([window(20, owner: 9, 1512, 982, layer: 26)], pids: game, screen: screen) == nil, "another program's window says nothing")
        let statusBar = NSWindow.Level.statusBar.rawValue
        check(GameBackdrop.pageLevel(underGameAt: 26) == statusBar, "right under Wine's full-screen level, over every normal window")
        check(GameBackdrop.pageLevel(underGameAt: shieldLevel + 2) == statusBar, "the same with a shield: there when the shield goes")
        check(GameBackdrop.pageLevel(underGameAt: 0) == nil, "a Mac game or a window at the normal level: the page stays out of it")
        check(GameBackdrop.pageLevel(underGameAt: statusBar) == nil, "not at the game's own level")
        check(GameBackdrop.pageLevel(underGameAt: nil) == nil, "no window over the screen: nothing changes")
    }

    /// A game ending: ABZU at 16:05 on 8.11. and the ways that look like it and aren't.
    static func ending() {
        let on = playing()
        func went(front: Bool = false, here: Bool = false, handsOff: Bool = false, acted: Bool = false, guarded: Bool = false) -> Bool {
            on.pictureWent(look(1, front: front, here: here, handsOff: handsOff, acted: acted, guarded: guarded))
        }
        check(went(), "Steam's Wine in front, the picture gone: the curtain comes")
        check(!went(front: true), "still the active app with its window gone (The Forest minimised): it gets fetched, no curtain")
        check(!went(here: true), "another app in front, the picture still there: nothing ended")
        check(!went(acted: true), "⌘-Tab or a click elsewhere: the player went")
        check(!went(handsOff: true), "the overlay is open: the player has the front for a reason")
        check(!went(guarded: true), "the curtain's watch still guards the front")
        check(!GameStage().pictureWent(look(1, front: false)), "no picture yet: no end of one")
        var left = playing()
        left.playerLeft()
        check(!left.pictureWent(look(1, front: false)), "Go to Nightforge: the game is left alone")

        check(GameStage.curtainEnds(cameBack: true, waited: 1), "back with its picture: the curtain goes at once")
        check(!GameStage.curtainEnds(cameBack: false, waited: GameStage.endingPatience - 1), "still ending: the curtain stays")
        check(GameStage.curtainEnds(cameBack: false, waited: GameStage.endingPatience), "not ending after all: never stuck")
        // No window left after 10 s, only a process ending in its own time (the Wukong benchmark's helper, 22.11.2026):
        // Nightforge comes back, the end is followed in the background.
        check(GameStage.endingPatience == 10, "10 s, the user's choice")
        check(GameStage.endsInBackground(cameBack: false, windowAnywhere: false, waited: GameStage.endingPatience),
              "no window anywhere after 10 s: back to Nightforge")
        check(!GameStage.endsInBackground(cameBack: false, windowAnywhere: false, waited: GameStage.endingPatience - 1),
              "before that the curtain stays")
        check(!GameStage.endsInBackground(cameBack: false, windowAnywhere: true, waited: 60),
              "a window of the game's somewhere (minimised, another Space): it runs on, Nightforge stays behind it")
        check(!GameStage.endsInBackground(cameBack: true, windowAnywhere: true, waited: 60), "back with its picture")

        func exit(curtainUp: Bool = false, sawPicture: Bool = true, judged: Bool = false, others: Bool = false) -> Bool {
            LibraryModel.exitRaisesCurtain(curtainUp: curtainUp, sawPicture: sawPicture, judged: judged, othersRunning: others)
        }
        check(exit(), "the game's process ended behind the page: the curtain at once")
        check(!exit(curtainUp: true), "the curtain is up already, its stage stays what it is")
        check(!exit(sawPicture: false), "before its first picture: a launcher handing over, the start's own curtain")
        check(!exit(judged: true), "an early end is the start's to tell")
        check(!exit(others: true), "another game still runs")
    }

    /// The game's own full screen hides its picture after the curtain went (Overwatch, 21.11.2026).
    static func ownFullScreen() {
        let wait = GameStage.hiddenPatience
        var hidden = playing()
        check(!hidden.hiddenByOwnFullScreen(look(30), onlyOwnShield: true), "only its shield: not at once")
        check(!hidden.hiddenByOwnFullScreen(look(30 + wait - 1), onlyOwnShield: true), "not yet")
        check(hidden.hiddenByOwnFullScreen(look(30 + wait), onlyOwnShield: true), "its shield alone for \(wait) s, the game in front: said")
        check(hidden.hiddenByOwnFullScreen(look(30 + wait + 5), onlyOwnShield: true), "and as long as it stands")

        var proper = playing()
        check(!proper.hiddenByOwnFullScreen(look(40, here: true), onlyOwnShield: false)
              && !proper.hiddenByOwnFullScreen(look(40 + wait, here: true), onlyOwnShield: false),
              "proper full screen: its window over its shield, picture here – never")
        var away = playing()
        check(!away.hiddenByOwnFullScreen(look(40, front: false), onlyOwnShield: true)
              && !away.hiddenByOwnFullScreen(look(40 + wait, front: false), onlyOwnShield: true),
              "the player sent it away (⌘-Tab, another app in front): never")
        var acted = playing()
        _ = acted.hiddenByOwnFullScreen(look(40), onlyOwnShield: true)
        check(!acted.hiddenByOwnFullScreen(look(45, acted: true), onlyOwnShield: true)
              && !acted.hiddenByOwnFullScreen(look(40 + wait), onlyOwnShield: true)
              && !acted.hiddenByOwnFullScreen(look(45 + wait), onlyOwnShield: true)
              && acted.hiddenByOwnFullScreen(look(40 + 2 * wait), onlyOwnShield: true), "a ⌘ or a click: the count starts again at the next look")
        var blink = playing()
        _ = blink.hiddenByOwnFullScreen(look(40), onlyOwnShield: true)
        _ = blink.hiddenByOwnFullScreen(look(44, here: true), onlyOwnShield: false)
        check(!blink.hiddenByOwnFullScreen(look(40 + wait), onlyOwnShield: true), "its picture back in between: from the start again")
        var guarded = playing()
        check(!guarded.hiddenByOwnFullScreen(look(40, guarded: true), onlyOwnShield: true)
              && !guarded.hiddenByOwnFullScreen(look(40 + wait, guarded: true), onlyOwnShield: true),
              "the curtain's watch still guards the front: it says it itself")
        var overlay = playing()
        check(!overlay.hiddenByOwnFullScreen(look(40 + wait, handsOff: true), onlyOwnShield: true), "under the overlay: nothing")
        var never = GameStage()
        check(!never.hiddenByOwnFullScreen(look(0), onlyOwnShield: true) && !never.hiddenByOwnFullScreen(look(wait), onlyOwnShield: true),
              "no picture yet: the curtain's watch has it")
    }

    /// The game in front with no window left (the Wukong benchmark, 22.11.2026 19:36): the curtain after 3 s.
    static func dark() {
        var stage = playing()
        func gone(_ at: TimeInterval, shield: Bool = false, acted: Bool = false, handsOff: Bool = false, anywhere: Bool = false) -> Bool {
            stage.wentDark(look(at, anywhere: anywhere, handsOff: handsOff, acted: acted), onlyOwnShield: shield)
        }
        check(!gone(1) && !gone(3.5), "in front with no window: not before 3 s")
        check(gone(4), "3 s: its picture counts as gone, the curtain comes")
        check(!gone(5), "once, then it starts over")
        var other = playing()
        check(!other.wentDark(look(1, anywhere: false, acted: true), onlyOwnShield: false)
              && other.wentDark(look(4.5, anywhere: false, acted: true), onlyOwnShield: false), "the game's own Quit, a click, doesn't hold it back")
        var shielded = playing()
        check(!shielded.wentDark(look(1, anywhere: false), onlyOwnShield: true) && !shielded.wentDark(look(20, anywhere: false), onlyOwnShield: true),
              "its own full screen's shield: that's hiddenByOwnFullScreen's, not an end")
        var minimised = playing()
        check(!minimised.wentDark(look(1), onlyOwnShield: false) && !minimised.wentDark(look(20), onlyOwnShield: false),
              "a window of its somewhere (minimised): not gone")
        var asked = playing()
        check(!asked.wentDark(look(1, anywhere: false, handsOff: true), onlyOwnShield: false)
              && !asked.wentDark(look(20, anywhere: false, handsOff: true), onlyOwnShield: false), "the overlay or a question: hands off")
        var away = playing()
        check(!away.wentDark(look(1, front: false, anywhere: false), onlyOwnShield: false)
              && !away.wentDark(look(20, front: false, anywhere: false), onlyOwnShield: false), "another app in front: pictureWent's case")
        var never = GameStage()
        check(!never.wentDark(look(1, anywhere: false), onlyOwnShield: false) && !never.wentDark(look(20, anywhere: false), onlyOwnShield: false),
              "before its first picture: the start's curtain has it")
        var back = playing()
        _ = back.wentDark(look(1, anywhere: false), onlyOwnShield: false)
        _ = back.wentDark(look(2, here: true), onlyOwnShield: false)
        check(!back.wentDark(look(3.5, anywhere: false), onlyOwnShield: false), "its window back in between: the count starts again")
    }

    static func main() {
        stage()
        page()
        underGame()
        ending()
        ownFullScreen()
        dark()
        print(failures == 0 ? "GameStageTest: all good" : "GameStageTest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
