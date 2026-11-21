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
        rosetta()
        rosettaBeforeIntelCode()
        signInNote()
        signInWindow()
        libraryCheck()
        replay()
        replayTexts()
        details()

        print(failures == 0 ? "✓ FirstStart" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Without Rosetta: through macOS 27 exactly as before, past it a plain notice that promises nothing.
    static func rosetta() {
        typealias S = SetupModel
        for major in [14, 26, 27] {
            check(S.phaseWithoutRosetta(macOSMajor: major) == .needsRosetta, "macOS \(major): Rosetta is offered for install")
            check(!RosettaSupport.isGone(macOSMajor: major, translates: {
                check(false, "macOS \(major): nothing is probed")
                return false
            }), "macOS \(major): Rosetta doesn't count as gone")
        }
        check(S.phaseWithoutRosetta(macOSMajor: 28) == .rosettaGone, "macOS 28 without Rosetta: the notice, no install")
        check(S.confirmAction(stage: .checklist, phase: .rosettaGone) == nil, "the notice has nothing to press")
        check(RosettaSupport.isGone(macOSMajor: 28, translates: { false }), "macOS 28, x86_64 doesn't run: gone")
        check(!RosettaSupport.isGone(macOSMajor: 28, translates: { true }), "macOS 28, x86_64 runs: nothing changes")
    }

    /// Rosetta before x86_64 code (21.11.2026): a new Mac without it signed in through the launcher cards, never saw
    /// the first start's step, and Windows Steam failed with "Bad CPU type in executable".
    static func rosettaBeforeIntelCode() {
        typealias R = RosettaSupport
        // The rule: the probe, and macOS past 27.
        check(R.state(macOSMajor: 26, installed: { true }) == .ready && R.state(macOSMajor: 28, installed: { true }) == .ready,
              "Rosetta there: ready, whatever macOS")
        check(R.state(macOSMajor: 26, installed: { false }) == .missing && R.state(macOSMajor: 27, installed: { false }) == .missing,
              "missing through macOS 27: offered for install")
        check(R.state(macOSMajor: 28, installed: { false }) == .gone, "past macOS 27: gone, the notice")
        // Once a session while it's there, again after a "Bad CPU type", at each ask while it's missing.
        R.forget()
        check(R.stateHere(probe: { true }) == .ready, "probed: there")
        check(R.stateHere(probe: {
            check(false, "not probed again in the same session")
            return false
        }) == .ready, "seen once: ready")
        R.forget()
        check(R.stateHere(probe: { false }) != .ready, "after a Bad CPU type: probed again, missing")
        check(R.stateHere(probe: { true }) == .ready, "while missing every ask probes: the install counts at once")
        R.forget()
        // The hidden test switch: "missing" on a Mac with Rosetta, until Install Rosetta is pressed this session.
        let switched = UserDefaults(suiteName: "first-start-rosetta-\(UUID().uuidString)")!
        switched.set(true, forKey: R.testMissingRosettaKey)
        check(R.stateHere(probe: { true }, defaults: switched) == .missing, "the switch: missing, though Rosetta is there")
        check(R.stateHere(probe: { true }) == .ready, "without it: as the probe says")
        R.noteInstallAsked()
        check(R.stateHere(probe: { true }, defaults: switched) == .ready, "Install Rosetta pressed: as the probe says again")
        check(R.testMissingRosettaKey.utf8.count > 15, "the key is text in an optimized build, for the release check")
        R.forget()
        // Error 86 in every shape it comes in, and never in the system's words for the player.
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EBADARCH))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSUnderlyingErrorKey: posix])
        check(EBADARCH == 86 && R.isBadCPUType(posix) && R.isBadCPUType(POSIXError(.EBADARCH)) && R.isBadCPUType(wrapped)
              && R.isBadCPUType(R.Missing()), "error 86: from Process, from the helper, wrapped, and our own")
        check(!R.isBadCPUType(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))) && !R.isBadCPUType(CocoaError(.fileNoSuchFile)),
              "another error: not Rosetta")
        let text = R.playerText(posix)
        check(text.contains("Rosetta") && !text.contains("CPU") && text == R.missingText(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
              "error 86 for the player: Rosetta is missing (\(text))")
        let other = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        check(R.playerText(other) == other.localizedDescription, "any other error as it says itself")
        check(R.missingText(macOSMajor: 28) == R.notice && R.missingText(macOSMajor: 27) != R.notice, "past macOS 27: the notice instead")
        // The first start's decision: asked once a library is there and the first start doesn't ask itself.
        typealias M = LibraryModel
        check(M.asksAboutRosetta(.missing, setupActive: false, needsSetup: false),
              "games in the list through the launcher cards, the first start never ran: asked")
        check(!M.asksAboutRosetta(.missing, setupActive: true, needsSetup: false), "the first start runs: its own step asks")
        check(!M.asksAboutRosetta(.missing, setupActive: false, needsSetup: true), "no games yet: the first start is still to come")
        check(!M.asksAboutRosetta(.ready, setupActive: false, needsSetup: false) && !M.asksAboutRosetta(.gone, setupActive: false, needsSetup: false),
              "there, or gone past macOS 27: no install question")
        // Which starts run x86_64 code.
        check(M.startNeedsRosetta(platform: .windows, provider: .epic, macAppleSilicon: false)
              && M.startNeedsRosetta(platform: .windows, provider: .steam, macAppleSilicon: true), "every Windows game: Wine")
        check(M.startNeedsRosetta(platform: .mac, provider: .steam, macAppleSilicon: false), "a Mac version Steam says is for Intel")
        check(!M.startNeedsRosetta(platform: .mac, provider: .steam, macAppleSilicon: true)
              && !M.startNeedsRosetta(platform: .mac, provider: .gog, macAppleSilicon: false)
              && !M.startNeedsRosetta(platform: .mac, provider: .battlenet, macAppleSilicon: false),
              "Apple silicon, or a store that doesn't say: no question")
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

        check(S.confirmAction(stage: .launchers, phase: .done) == nil, "cards: the selected card has Return")
        check(S.backAction(stage: .launchers, replay: false) == .leaveLaunchers, "cards: Esc leads on, there's nothing behind them")

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

    /// The checklist's lines (SetupDetail): finished steps, downloads, the components' names, Windows.
    static func details() {
        check(SetupDetail.duration(0.3) == L10n.t("was already there"), "a step that was done before")
        check(SetupDetail.duration(25) == L10n.t("in %ld s", 25), "25 s")
        check(SetupDetail.duration(72) == L10n.t("in %ld min %ld s", 1, 12), "1 min 12 s")
        check(SetupDetail.mac(freeBytes: 120_000_000_000) == L10n.t("Rosetta is there · %@ free", Format.bytes(120_000_000_000)), "the Mac")

        let amount = L10n.t("%@ of %@", Format.bytes(142_000_000), Format.bytes(461_131_598))
        check(SetupDetail.transfer(done: 142_000_000, total: 461_131_598, bytesPerSecond: nil) == amount, "no speed yet: \(amount)")
        check(SetupDetail.transfer(done: 142_000_000, total: 461_131_598, bytesPerSecond: 15_000_000) == amount + " · " + Format.bytes(15_000_000) + "/s",
              "with its speed")

        func component(_ id: String, _ version: String, size: Int64 = 1_000_000) -> Component {
            Component(id: id, kind: .tool, version: version, url: URL(string: "https://example.invalid/\(id).tar.xz")!, sha256: "",
                      size: size, license: "", source: URL(string: "https://example.invalid")!)
        }
        let wine = component("winecx", "4.7.3", size: 461_131_598)
        check(SetupDetail.name(of: wine) == L10n.t("Wine %@ (CrossOver)", "4.7.3"), "winecx")
        check(SetupDetail.name(of: component("wine", "11.18")) == "Wine 11.18", "Wine")
        check(SetupDetail.name(of: component("graphics", "11.18-dxmt0.80-13")) == "DXMT 0.80", "the graphics package: DXMT's version")
        check(SetupDetail.name(of: component("d3dmetal", "4.0b3")) == "D3DMetal 4.0b3", "D3DMetal")
        check(SetupDetail.name(of: component("dxvk-macos", "1.10.3-20230507")) == "DXVK 1.10.3", "DXVK")
        check(SetupDetail.name(of: component("moltenvk", "1.4.2")) == "MoltenVK 1.4.2", "MoltenVK")
        check(SetupDetail.name(of: component("gamepad", "4.7.3-7")) == L10n.t("Controller support"), "the controller package")
        check(SetupDetail.name(of: component("enginefix", "4.7.3-1")) == L10n.t("Engine fixes (sound, stability)"), "the engine fixes")
        check(SetupDetail.component(wine, fraction: 0.5, bytesPerSecond: nil)
              == L10n.t("%@: %@", L10n.t("Wine %@ (CrossOver)", "4.7.3"), SetupDetail.transfer(done: 230_565_799, total: 461_131_598, bytesPerSecond: nil)),
              "halfway: \(SetupDetail.component(wine, fraction: 0.5, bytesPerSecond: nil))")
        check(SetupDetail.component(wine, fraction: 1, bytesPerSecond: 1) == L10n.t("Unpacking %@ …", L10n.t("Wine %@ (CrossOver)", "4.7.3")),
              "all there: unpacking")
        check(SetupDetail.engine(.graphics) == L10n.t("Setting up the graphics layers …"), "the graphics layers")
        check(SetupDetail.engine(.gameEnvironment) == L10n.t("Setting up the game environment …"), "the game environment")
        check(SetupDetail.windows(systemFiles: 0) == L10n.t("Creating Windows …"), "Windows, before its files")
        check(SetupDetail.windows(systemFiles: 412) == L10n.t("Creating Windows · %ld system files", 412), "Windows, 412 files")
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
