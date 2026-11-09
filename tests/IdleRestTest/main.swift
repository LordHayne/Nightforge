import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        print("✗ \(message)")
    }
}

func lookPauses() {
    func pause(ending: Bool = false, game: Bool = false, download: Bool = false, front: Bool = false, away: Bool = false) -> Int {
        IdleRest.lookPause(gameEnding: ending, gameOrStart: game, downloading: download, inFront: front, nobodyThere: away)
    }
    check(!IdleRest.nobodyThere(idle: 299) && IdleRest.nobodyThere(idle: 300), "nobody there after five minutes without input")
    check(pause(front: true) == 3 && pause() == 10, "someone there: the pace as ever")
    check(pause(away: true) == 30, "nobody there: it rests")
    check(pause(front: true, away: true) == 30, "also with Nightforge left in front, the console's case")
    check(pause(download: true, away: true) == 10 && pause(download: true, front: true, away: true) == 3, "a download keeps its pace")
    check(pause(game: true, away: true) == 3, "a game keeps its pace: nobody touches a pad in a cut scene")
    check(pause(ending: true, game: true, away: true) == 1, "a game that just ended comes first")
}

@main
struct IdleRestTest {
    static func main() async {
        lookPauses()
        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ IdleRest")
    }
}
