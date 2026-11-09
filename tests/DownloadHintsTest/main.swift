// Checks what the ring, the Downloads panel and the proof line may say (board DownloadHinweise, A1 and C2):
// never anything that isn't so at that moment. tests/DownloadHintsTest/run.sh
import Foundation

@main
struct DownloadHintsTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func same<T: Equatable>(_ got: T, _ wanted: T, _ message: String) {
        check(got == wanted, "\(message): \(got), wanted \(wanted)")
    }

    typealias D = KeepAwake.Download
    typealias Proof = DownloadProof

    static func download(_ provider: Provider = .steam, paused: Bool = false, builtIn: Bool = true, platform: Platform = .windows) -> D {
        D(name: "Control", provider: provider, platform: platform, builtIn: builtIn, paused: paused)
    }

    static func standing(listed: Bool = true, fetching: Bool = true, holding: Bool = true, _ downloads: [D] = [download()], lid: Bool = false) -> DownloadStanding {
        DownloadStanding.of(listed: listed, fetching: fetching, holding: holding, downloads: downloads, lidMatters: lid)
    }

    static func game(_ name: String, _ install: InstallState, size: Int64) -> Game {
        var game = Game(appID: name.utf8.reduce(1) { ($0 * 31 + Int($1)) % 1_000_003 }, name: name, bottle: Engine.bottle, steamRoot: URL(fileURLWithPath: "/x"), steamExeWindowsPath: "",
                        installDir: URL(fileURLWithPath: "/x/\(name)"), sizeOnDisk: size)
        game.install = install
        return game
    }

    static func testStanding() {
        same(standing(listed: false), .silent, "nothing listed: no word (a game only being moved doesn't hold the Mac)")
        same(standing(), .awake, "fetching and held")
        same(standing(lid: true), .awakeLidOpen, "fetching and held, and the lid could end it")
        same(standing(holding: false), .silent, "the hold couldn't be taken: nothing may claim the Mac stays awake")
        same(standing(holding: false, lid: true), .silent, "nor ask for the lid")

        same(standing(fetching: false, [download(paused: true), download(paused: true)]), .paused, "all paused")
        same(standing(fetching: false, []), .paused, "listed, but only waiting for room: the same")
        same(standing(fetching: false, [download()]), .storeStopped("Steam"), "Steam gone")
        same(standing(fetching: false, [download(.battlenet)]), .storeStopped("Battle.net"), "Battle.net gone, by its name")
        same(standing(fetching: false, [download(paused: true), download(.battlenet)]), .storeStopped("Battle.net"), "one paused beside a store that's gone")
        same(standing([download(paused: true), download()]), .awake, "one still loading beside a paused one: awake")

        check(!DownloadStanding.silent.mayDoze && !DownloadStanding.awake.mayDoze && !DownloadStanding.awakeLidOpen.mayDoze, "the ring stays lit while it's held")
        check(DownloadStanding.paused.mayDoze && DownloadStanding.storeStopped("Steam").mayDoze, "and goes grey when nothing fetches")
    }

    /// Against the real hold rules: the five minutes a store may be away, and the stores that can't be looked at.
    static func testAgainstTheHold() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let list = [download()]
        func after(_ seconds: TimeInterval, steam: Bool, seen: Date?) -> (names: [String], storeSeen: Date?) {
            KeepAwake.held(list, steamRunning: steam, macSteamRunning: false, battleNetRunning: false, storeSeen: seen, now: clock.addingTimeInterval(seconds))
        }
        let up = after(0, steam: true, seen: nil)
        same(standing(fetching: !up.names.isEmpty, list), .awake, "Steam running")
        let changing = after(93, steam: false, seen: up.storeSeen)  // 1 min 33 s on 8.11.
        same(standing(fetching: !changing.names.isEmpty, list), .awake, "the Steams changing over: nobody says Steam is gone")
        let almost = after(KeepAwake.storeAwayGrace - 1, steam: false, seen: up.storeSeen)
        same(standing(fetching: !almost.names.isEmpty, list), .awake, "up to five minutes it stays awake")
        let gone = after(KeepAwake.storeAwayGrace, steam: false, seen: up.storeSeen)
        same(standing(fetching: !gone.names.isEmpty, list), .storeStopped("Steam"), "after five minutes it's said")
        same(KeepAwake.storeAwayGrace, 300, "five minutes, as on the board")

        func fetches(_ one: D) -> Bool {
            !KeepAwake.held([one], steamRunning: false, macSteamRunning: false, battleNetRunning: false, storeSeen: nil, now: clock).names.isEmpty
        }
        check(fetches(download(builtIn: false)), "a Steam in the player's own bottle can't be looked at: never said to be gone")
        check(fetches(download(.epic)) && fetches(download(.gog)), "Epic and GOG are Nightforge's own: never said to be gone")
    }

    static func testLid() {
        func lid(_ battery: Bool, builtIn: Bool, external: Bool, unplugged: Bool) -> Bool {
            DownloadStanding.lidMatters(hasBattery: battery, builtInDisplay: builtIn, externalDisplay: external, onBattery: unplugged)
        }
        check(lid(true, builtIn: true, external: false, unplugged: false), "MacBook alone, plugged in")
        check(lid(true, builtIn: true, external: false, unplugged: true), "MacBook alone, on battery")
        check(!lid(true, builtIn: true, external: true, unplugged: false), "with a screen and the mains it runs on shut: no lid sentence")
        check(lid(true, builtIn: true, external: true, unplugged: true), "with a screen on battery the lid still ends it")
        check(!lid(true, builtIn: false, external: true, unplugged: false), "already shut and running")
        check(!lid(false, builtIn: false, external: true, unplugged: false), "Mac mini: no lid")
        check(!lid(false, builtIn: true, external: false, unplugged: false), "iMac: own screen, no lid")
        check(!lid(true, builtIn: false, external: false, unplugged: false), "screens can't be read: no word about the lid")
    }

    static let gb: Int64 = 1_000_000_000
    static let clock = Date(timeIntervalSince1970: 1_800_000_000)

    static func mark(_ fraction: Double?, size: Int64 = 12 * gb, name: String = "Control", finished: Bool = false) -> Proof.Mark {
        Proof.Mark(name: name, fraction: fraction, size: size, finished: finished)
    }

    static func outcome(_ before: [String: Proof.Mark], _ after: [String: Proof.Mark], dark: TimeInterval = 3600, slept: TimeInterval = 0) -> Proof? {
        let stretch = Proof.Stretch(began: clock, awakeAtStart: 1000, before: before)
        return Proof.outcome(stretch, ended: clock.addingTimeInterval(dark), awakeAtEnd: 1000 + dark - slept, after: after)
    }

    static func testProof() {
        let half = ["a": mark(0.5)], most = ["a": mark(0.75)]
        same(outcome(half, most), Proof(kind: .ranOn, bytes: 3 * gb), "a quarter of 12 GB came down")

        // When it doesn't come.
        check(outcome(half, most, dark: 119) == nil, "under two minutes dark: nobody missed anything")
        check(outcome(half, most, dark: 120) != nil, "two minutes: it counts")
        check(outcome(half, most, slept: 31) == nil, "the Mac slept in between: the sentence would be false")
        check(outcome(half, most, slept: 3000) == nil, "lid shut for most of it")
        check(outcome(half, most, slept: 29) != nil, "a clock nudged by a few seconds isn't sleep")
        check(outcome(half, half) == nil, "nothing came: never says it kept going")
        check(outcome(half, ["a": mark(0.2)]) == nil, "fell back (a verify): no claim")
        check(outcome(half, [:]) == nil, "cancelled meanwhile")
        check(outcome(half, ["a": mark(nil)]) == nil, "back to preparing")
        check(outcome(half, ["b": mark(0.9)]) == nil, "only a download that wasn't there at the start")
        check(outcome(["a": mark(0.5, size: 100_000_000 * 2)], ["a": mark(0.5 + 0.49, size: 100_000_000 * 2)]) == nil, "98 MB: under the 100 MB")
        check(outcome(["a": mark(0.5, size: 100_000_000 * 2)], ["a": mark(1, size: 100_000_000 * 2)])?.bytes == 100_000_000, "100 MB: enough")

        // The kinds.
        same(outcome(half, ["a": mark(1, finished: true)]), Proof(kind: .finished("Control"), bytes: 6 * gb), "finished in the dark: only what came down in it")
        let two = ["a": mark(0.5), "b": mark(0, size: 8 * gb, name: "Valheim")]
        same(outcome(two, ["a": mark(1, finished: true), "b": mark(0.25, size: 8 * gb, name: "Valheim")]), Proof(kind: .severalRanOn, bytes: 8 * gb), "two moved: both counted")
        same(outcome(two, ["a": mark(1, finished: true), "b": mark(0, size: 8 * gb, name: "Valheim")]), Proof(kind: .finished("Control"), bytes: 6 * gb), "only one moved")
        same(outcome(["a": mark(nil)], ["a": mark(0.5)]), Proof(kind: .ranOn, bytes: 6 * gb), "queued as preparing: nothing was down yet")

        // Size not known.
        same(outcome(["a": mark(0.5, size: 0)], ["a": mark(0.75, size: 0)]), Proof(kind: .ranOn, bytes: nil), "no size: the sentence without a number")
        same(outcome(["a": mark(0.5, size: 0)], ["a": mark(1, size: 0, finished: true)]), Proof(kind: .finished("Control"), bytes: nil), "finished, no size")
        check(outcome(["a": mark(0.5, size: 0)], ["a": mark(0.5, size: 0)]) == nil, "no size and nothing moved")
        same(outcome(["a": mark(0.5, size: 0), "b": mark(0.5, size: 100)], ["a": mark(0.75, size: 0), "b": mark(1, size: 100, finished: true)]),
             Proof(kind: .severalRanOn, bytes: nil), "a few bytes and one without a size: no made-up number")
    }

    static func testMarks() {
        let control = game("Control", .downloading(0.5), size: 12 * gb)
        let queued = game("Valheim", .downloading(nil), size: 3 * gb)
        let installed = game("Hades", .installed, size: 9 * gb)
        let before = Proof.marks(of: [control, queued, installed])
        same(Set(before.keys), Set([control.id, queued.id]), "only what's listed as downloading")
        same(before[control.id], mark(0.5), "how far and how big")

        let dark = Proof.Stretch(began: clock, awakeAtStart: 0, before: before)
        let done = game("Control", .installed, size: 40 * gb)  // unpacked it takes more than came down
        let after = Proof.marks(after: dark, games: [done, queued, installed])
        same(after[control.id], mark(1, finished: true), "finished: with the size that came down, not what it takes on disk")
        check(after[installed.id] == nil, "a game that was installed all along doesn't count as finished")
        check(after[queued.id]?.finished == false, "still queued")
    }

    static func testMoment() {
        func moment(game: Bool = false, curtain: Bool = false, overlay: Bool = false, first: Bool = false, locked: Bool = false, front: Bool = true) -> Proof.Moment {
            Proof.moment(gameOn: game, curtain: curtain, overlay: overlay, firstStart: first, locked: locked, inFront: front)
        }
        same(moment(), .show, "unlocked, in front, no game")
        same(moment(locked: true), .wait, "locked: waits for the password")
        same(moment(front: false), .wait, "another app in front: waits, or it'd be up with nobody seeing it")
        same(moment(first: true), .wait, "the first start has the window")
        same(moment(game: true), .drop, "a game on its way or running: gone for good")
        same(moment(curtain: true), .drop, "the curtain")
        same(moment(overlay: true), .drop, "the overlay")
        same(moment(game: true, locked: true, front: false), .drop, "a game wins over waiting")

        check(!Proof.touched(idle: 12, shownFor: 5), "what brought the screen back was before the line: doesn't count")
        check(Proof.touched(idle: 1, shownFor: 5), "a press since the line came")
        check(!Proof.touched(idle: 5, shownFor: 5), "the same moment isn't since")
        same(Proof.staysAfterTouch, 4, "first touch plus four seconds, as on the board")
        same(Proof.shortestDark, 120, "two minutes, as on the board")
        same(Proof.leastBytes, 100_000_000, "100 MB, as on the board")
    }

    static func language(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    static func testWords() {
        language(.german)
        same(DownloadStanding.silent.ringWord, nil, "silent: no word")
        same(DownloadStanding.silent.sentence, nil, "silent: no sentence")
        same(DownloadStanding.awake.ringWord, "Mac bleibt wach", "ring")
        same(DownloadStanding.awakeLidOpen.ringWord, "Deckel offen lassen", "ring, lid")
        same(DownloadStanding.paused.ringWord, "Mac darf schlafen", "ring, paused")
        same(DownloadStanding.storeStopped("Steam").ringWord, "Steam läuft nicht", "ring, Steam gone")
        let awake = "Der Mac bleibt wach, solange geladen wird. Der Bildschirm darf ausgehen."
        same(DownloadStanding.awake.sentence?.whole, awake, "panel")
        same(DownloadStanding.awakeLidOpen.sentence?.whole, awake + " Lass den Deckel offen.", "panel, lid")
        same(DownloadStanding.awakeLidOpen.sentence?.action, "Lass den Deckel offen.", "the lid is what stands out")
        same(DownloadStanding.paused.sentence?.whole, "Pausiert: Der Mac darf schlafen.", "panel, paused")
        same(DownloadStanding.storeStopped("Battle.net").sentence?.whole, "Battle.net läuft nicht, der Download steht. Der Mac darf schlafen.", "panel, store gone")
        check(DownloadStanding.awake.sentence?.action == nil && DownloadStanding.paused.sentence?.action == nil, "only the lid asks for something")

        same(Proof(kind: .ranOn, bytes: nil).message, "Der Download lief weiter, während der Bildschirm aus war.", "no number")
        same(Proof(kind: .severalRanOn, bytes: nil).message, "Die Downloads liefen weiter, während der Bildschirm aus war.", "several, no number")
        same(Proof(kind: .finished("Control"), bytes: nil).message, "Control ist fertig geworden, während der Bildschirm aus war.", "finished, no number")
        let amount = Format.bytes(12 * gb)
        same(Proof(kind: .ranOn, bytes: 12 * gb).message, "Der Download lief weiter: \(amount), während der Bildschirm aus war.", "with a number")
        same(Proof(kind: .severalRanOn, bytes: 12 * gb).message, "Die Downloads liefen weiter: \(amount), während der Bildschirm aus war.", "several")
        same(Proof(kind: .finished("Control"), bytes: 12 * gb).message, "Control ist fertig: \(amount), während der Bildschirm aus war.", "finished")
        same(amount.replacingOccurrences(of: "\u{A0}", with: " "), "12 GB", "a whole number reads as on the board")

        language(.english)
        same(DownloadStanding.awake.ringWord, "Mac stays awake", "English ring")
        same(DownloadStanding.storeStopped("Steam").ringWord, "Steam isn't running", "English, store gone")
        same(DownloadStanding.awakeLidOpen.sentence?.whole, "Your Mac stays awake while games download. The display can still turn off. Keep the lid open.", "English panel")
        same(DownloadStanding.storeStopped("Steam").sentence?.whole, "Steam isn't running, so the download has stopped. Your Mac may sleep.", "English, store gone")
        same(Proof(kind: .ranOn, bytes: 12 * gb).message, "The download kept going: 12 GB while the display was off.", "English proof")
        same(Proof(kind: .finished("Control"), bytes: 12 * gb).message, "Control finished: 12 GB while the display was off.", "English, finished")
    }

    /// The promise that the line takes neither focus nor a key is in how it's built: it has no way of doing either.
    static func testLineTakesNothing() {
        guard let source = try? String(contentsOfFile: "Sources/Nightforge/DownloadHints.swift", encoding: .utf8) else {
            return check(false, "DownloadHints.swift not found")
        }
        check(!source.contains("padFocus"), "the line has no place for the pad's highlight")
        check(!source.contains("addLocalMonitor") && !source.contains("addGlobalMonitor") && !source.contains("keyboardShortcut"), "and listens to no key")
        check(!source.contains("Button"), "and has no button")
        check(source.contains(".allowsHitTesting(false)"), "a click goes through it")
    }

    static func main() {
        TestDefaults.useWorkFolder()
        testStanding()
        testAgainstTheHold()
        testLid()
        testProof()
        testMarks()
        testMoment()
        testWords()
        testLineTakesNothing()
        print(failures == 0 ? "✓ DownloadHintsTest" : "✗ DownloadHintsTest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
