// Checks the first start: its pages from the welcome to the reveal, what Return/A and Esc/B do on
// each, the note on Steam's QR code before and while its window is open, which window is Steam's
// sign-in, how the library check waits for Steam and paces its count, and the replay's own texts:
// tests/FirstStartTest/run.sh
import CoreGraphics
import Foundation

@main
struct FirstStartTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor
    static func main() {
        actions()
        signInNote()
        signInWindow()
        libraryCheck()
        replay()
        replayTexts()

        print(failures == 0 ? "✓ FirstStart" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Return/A and Esc/B on each page: the setup itself can't be skipped, the check and the replay can.
    static func actions() {
        typealias S = SetupModel
        check(S.confirmAction(stage: .welcome, phase: .idle) == .begin, "welcome: Return is Let's Go")
        check(S.backAction(stage: .welcome, replay: false) == nil, "welcome: Esc does nothing on the real first start")
        check(S.backAction(stage: .welcome, replay: true) == .skip, "welcome: Esc skips the replay")

        check(S.confirmAction(stage: .checklist, phase: .running(.engine)) == nil, "checklist: nothing to press while it runs")
        check(S.confirmAction(stage: .checklist, phase: .needsRosetta) == .installRosetta, "checklist: Return installs Rosetta")
        check(S.confirmAction(stage: .checklist, phase: .waitingForSignIn) == .showSteam, "checklist: Return brings Steam's window back")
        check(S.confirmAction(stage: .checklist, phase: .failed(.steam, "x")) == .retry, "checklist: Return tries again")
        check(S.backAction(stage: .checklist, replay: false) == nil, "checklist: Esc doesn't leave the setup")

        let checking = SetupModel.Stage.checking(LibraryCheck(total: 10, checked: 3))
        check(S.confirmAction(stage: checking, phase: .done) == nil, "checking: nothing to press")
        check(S.backAction(stage: checking, replay: false) == .skip, "checking: Esc skips")

        let reveal = SetupModel.Stage.reveal(LibraryReveal(great: 3))
        check(S.confirmAction(stage: reveal, phase: .done) == .play, "reveal: Return is Let's Play")
        check(S.backAction(stage: reveal, replay: false) == .play, "reveal: Esc is Let's Play too")
        check(SetupModel.Action.play.label == L10n.t("Let's Play"), "the hint says what the button says")
    }

    /// The QR code is mentioned before Steam's window opens (while Steam updates itself), and again
    /// while it's open – not while Steam is still being downloaded and installed.
    static func signInNote() {
        let before = SetupModel.signInNote(phase: .running(.steam), steamStarting: true)
        check(before?.contains("QR") == true, "before the window: the QR note")
        check(before != nil && before != SetupModel.signInNote(phase: .waitingForSignIn, steamStarting: false),
              "before and while open: two different lines")
        check(SetupModel.signInNote(phase: .waitingForSignIn, steamStarting: false)?.contains("QR") == true, "window open: the QR note")
        check(SetupModel.signInNote(phase: .running(.steam), steamStarting: false) == nil, "installing Steam: no note yet")
        check(SetupModel.signInNote(phase: .running(.engine), steamStarting: false) == nil, "the engine: no note")
        check(SetupModel.signInNote(phase: .done, steamStarting: false) == nil, "signed in: no note")
    }

    /// Steam's sign-in opened behind Nightforge (29.10.): the window to bring forward is the front
    /// one of Steam's browser processes, not its tiny menu windows nor another app's.
    static func signInWindow() {
        func window(_ pid: Int, _ width: Double, _ height: Double, layer: Int = 0) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: ["X": 406.0, "Y": 239.0, "Width": width, "Height": height]]
        }
        let helpers: Set<pid_t> = [501, 502]
        let windows = [window(10, 1512, 853),           // Nightforge, in front
                       window(501, 1, 1),               // the browser's tiny menu window
                       window(502, 700, 440, layer: 3), // not a normal window
                       window(502, 700, 440)]           // "Bei Steam anmelden", behind Nightforge
        check(SteamWindow.owner(of: windows, helpers: helpers) == 502, "the sign-in's process: \(String(describing: SteamWindow.owner(of: windows, helpers: helpers)))")
        check(SteamWindow.owner(of: [window(10, 1512, 853), window(501, 1, 1)], helpers: helpers) == nil, "no window of Steam's yet")
    }

    /// Steam sends the library a moment after the sign-in: the check scans until two scans agree.
    static func libraryCheck() {
        check(LibraryCheck.waitsForSteam(previous: nil, now: 0, waited: 0, replay: false), "nothing yet: wait")
        check(LibraryCheck.waitsForSteam(previous: nil, now: 40, waited: 3, replay: false), "the first scan with games: once more")
        check(LibraryCheck.waitsForSteam(previous: 40, now: 98, waited: 6, replay: false), "still growing: wait")
        check(!LibraryCheck.waitsForSteam(previous: 98, now: 98, waited: 9, replay: false), "two scans agree: go on")
        check(LibraryCheck.waitsForSteam(previous: 0, now: 0, waited: 60, replay: false), "still empty after a minute: wait")
        check(!LibraryCheck.waitsForSteam(previous: 0, now: 0, waited: LibraryCheck.patience, replay: false), "patience is up: go on")
        check(!LibraryCheck.waitsForSteam(previous: nil, now: 0, waited: 0, replay: true), "the replay counts what's there")

        check(LibraryCheck().fraction == nil, "no bar while Steam sends the library")
        check(LibraryCheck(total: 4, checked: 1).fraction == 0.25, "1 of 4 is a quarter")
        check(LibraryCheck(total: 0).fraction == 1, "an empty library is checked at once")
        check(LibraryCheck.pause(total: 5) == .milliseconds(90), "a few games: 90 ms each")
        check(LibraryCheck.pause(total: 105) * 105 <= .milliseconds(2500), "a big library is counted within 2.5 s")
        check(LibraryCheck.pause(total: 0) == .zero, "nothing to count, no pause")
    }

    /// The replay comes long after the setup and the sign-in: its welcome and check say so.
    static func replayTexts() {
        check(SetupModel.welcomeText(replay: true) != SetupModel.welcomeText(replay: false), "the replay's welcome has its own line")
        check(SetupModel.welcomeText(replay: false).contains("Steam"), "the first start's welcome mentions the Steam sign-in")
        let first = SetupModel.checkingTexts(LibraryCheck(), replay: false)
        let again = SetupModel.checkingTexts(LibraryCheck(), replay: true)
        check(first.headline != again.headline && first.line != again.line, "the replay doesn't wait for Steam's sign-in")
        check(again.line == SetupModel.checkingTexts(LibraryCheck(total: 4, checked: 1), replay: true).line, "the replay only looks things up")
        check(SetupModel.checkingTexts(LibraryCheck(total: 4, checked: 1), replay: false).headline == L10n.t("%ld of %ld games", 1, 4), "1 of 4 games")
        check(SetupModel.checkingTexts(LibraryCheck(total: 1, checked: 1), replay: true).headline == L10n.t("%ld of 1 game", 1), "1 of 1 game")
    }

    /// Settings › About: the welcome, then straight to the check (the setup is done), the reveal,
    /// Let's Play.
    @MainActor
    static func replay() {
        let setup = SetupModel()
        var checks = 0
        setup.onFinished = { checks += 1 }

        setup.replay(setupDone: false)
        check(!setup.isActive, "no replay before the setup is done")
        setup.checking(LibraryCheck(total: 1))
        check(setup.stage == .welcome, "nothing changes while the first start isn't shown")

        setup.replay(setupDone: true)
        check(setup.isActive && setup.isReplay && setup.stage == .welcome, "the replay starts on the welcome")
        setup.primary()
        check(setup.stage == .checking(LibraryCheck()) && checks == 1, "Let's Go in the replay: the check, not the setup")
        check(setup.phase == .idle, "the setup itself doesn't run again")

        setup.checking(LibraryCheck(total: 3, checked: 2))
        check(setup.stage == .checking(LibraryCheck(total: 3, checked: 2)), "the count goes up")
        setup.reveal(LibraryReveal(great: 2, no: 1))
        check(setup.stage == .reveal(LibraryReveal(great: 2, no: 1)), "then the reveal")
        setup.primary()
        check(!setup.isActive && !setup.isReplay && setup.stage == .welcome, "Let's Play closes it")

        setup.replay(setupDone: true)
        check(setup.back() && !setup.isActive, "Esc on the replay's welcome closes it")

        setup.replay(setupDone: true)
        setup.begin()
        setup.reveal(LibraryReveal(great: 1))
        check(setup.back() && !setup.isActive, "Esc on the reveal is Let's Play")
        check(!setup.back(), "closed: Esc is the library's again")
    }
}
