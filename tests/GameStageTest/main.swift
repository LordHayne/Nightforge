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

    static func main() {
        stage()
        page()
        print(failures == 0 ? "GameStageTest: all good" : "GameStageTest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
