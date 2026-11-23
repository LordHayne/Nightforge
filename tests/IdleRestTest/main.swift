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

/// Steam's start after Nightforge's waits for the first look at the running games that knows the games (S3, 23.11.2026:
/// 23 and 31 s from opening to Steam, with nobody at the Mac the pause between looks is 30 s).
func firstCountingLook() {
    check(!IdleRest.pausesBeforeNextLook(gamesKnown: true, lookCounted: false), "the games just became known: the next look comes at once")
    check(IdleRest.pausesBeforeNextLook(gamesKnown: false, lookCounted: false), "the library still being read: the usual pause, no spinning")
    check(IdleRest.pausesBeforeNextLook(gamesKnown: true, lookCounted: true), "once a look counted: the usual pause")
    let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
    check(model.contains("guard IdleRest.pausesBeforeNextLook(gamesKnown: libraryLoaded, lookCounted: runningScanned) else { continue }\n                nap = Task"),
          "the look at the running games asks before its pause")
    check(model.contains("libraryLoaded = true\n        // The look at the running games that Steam's start waits for comes now")
          && model.contains("if !runningScanned { lookNow() }"), "the library read: a pause under way is cut short")
}

func downloadLooks() {
    check(IdleRest.downloadLookPause(fetching: true, nobodyThere: true) == 3, "one really coming down keeps its pace, nobody there or not")
    check(IdleRest.downloadLookPause(fetching: false, nobodyThere: false) == 3, "paused with someone there: a resume shows at once")
    check(IdleRest.downloadLookPause(fetching: false, nobodyThere: true) == 30, "paused and nobody there: it rests")
}

func windowGuard() {
    check(IdleRest.windowGuardPause(steamRunning: true, testHome: false) == 1, "Steam for Mac there: its windows are watched every second")
    check(IdleRest.windowGuardPause(steamRunning: false, testHome: false) == 30, "none there: macOS says when one starts")
    check(IdleRest.windowGuardPause(steamRunning: false, testHome: true) == 1, "a test home's stand-in is no app macOS tells about")
}

func wakeCatchUp() {
    let start = Date()
    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    let night = WakeCatchUp.every + 60
    func ready(_ wake: TimeInterval) -> TimeInterval { wake + WakeCatchUp.settle + 1 }

    var nap = WakeCatchUp(now: start)
    nap.woke(now: at(600))
    check(!nap.take(gameOrStart: false, nobodyThere: false, now: at(700)), "a short nap asks nothing new")

    var morning = WakeCatchUp(now: start)
    check(!morning.take(gameOrStart: false, nobodyThere: false, now: at(night)), "no wake, no update")
    morning.woke(now: at(night))
    check(!morning.take(gameOrStart: false, nobodyThere: false, now: at(night + 5)), "the network gets its moment first")
    check(!morning.take(gameOrStart: true, nobodyThere: false, now: at(ready(night))), "a game or a start comes first")
    check(!morning.take(gameOrStart: false, nobodyThere: true, now: at(ready(night))), "a wake nobody's at does nothing")
    check(morning.take(gameOrStart: false, nobodyThere: false, now: at(ready(night) + 60)), "once it's free it runs")
    check(!morning.take(gameOrStart: false, nobodyThere: false, now: at(ready(night) + 90)), "once")

    morning.woke(now: at(ready(night) + 120))
    check(!morning.take(gameOrStart: false, nobodyThere: false, now: at(ready(night) + 200)), "not again soon after")
    morning.again(now: at(ready(night) + 300))
    check(morning.take(gameOrStart: false, nobodyThere: false, now: at(ready(ready(night) + 300))), "called off by a start: once more afterwards")

    var apply = WakeCatchUp(now: start)
    check(!apply.takeApply(gameOrStart: false), "nothing fetched, nothing goes in")
    apply.fetched()
    check(!apply.takeApply(gameOrStart: true) && apply.applyDue, "fetched, it waits while a game or a start is on")
    check(apply.takeApply(gameOrStart: false) && !apply.applyDue, "and goes in once it's free, once")
}

func component(_ id: String, _ version: String) -> String {
    #"{"id": "\#(id)", "kind": "graphics", "version": "\#(version)", "url": "https://example.invalid/\#(id).tar.gz", "sha256": "00", "size": 1, "license": "MIT", "source": "https://example.invalid"}"#
}

func wantedAhead() {
    func wanted(_ extra: [String]) -> Set<String>? {
        let list = ([component(Engine.winecxEngineID, "4.7.3"), component(Engine.graphicsID, "4.7.3-1")] + extra).joined(separator: ",")
        guard let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: Data(#"{"schemaVersion": 1, "generated": "now", "components": [\#(list)]}"#.utf8)) else { return nil }
        return Set(Engine.wantedAhead(manifest).map(\.id))
    }
    check(wanted([])?.contains(Engine.winecxEngineID) == true && wanted([])?.contains(Engine.graphicsID) == true, "the engine and its graphics")
    check(wanted([component(Engine.d3dMetalID, "3.0")])?.contains(Engine.d3dMetalID) == false, "never Apple's D3DMetal: the player decides that")
    check(wanted([component(Engine.gamepadID, "4.7.3-15"), component(Engine.dxvkID, "1")])?.isSuperset(of: [Engine.gamepadID, Engine.dxvkID]) == true,
          "the components the engine takes")
    check(wanted([component(Engine.engineFixID, "4.7.3-2")])?.contains(Engine.engineFixID) == true, "the engine fix for this engine")
    check(wanted([component(Engine.engineFixID, "4.7.2-2")])?.contains(Engine.engineFixID) == false, "not one built for another engine")
}

@main
struct IdleRestTest {
    static func main() async {
        lookPauses()
        firstCountingLook()
        downloadLooks()
        windowGuard()
        wakeCatchUp()
        wantedAhead()
        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ IdleRest")
    }
}
