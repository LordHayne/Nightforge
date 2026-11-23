// The start's small parts against odd input: the launch options a player types, Steam's console log
// (empty, rotated, another game's lines) and SteamStartCheck, which decides whether a Steam that started
// counts as failed: tests/LaunchEdgeTest/run.sh
import Foundation

@main
struct LaunchEdgeTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("launch-edge-\(UUID().uuidString)", isDirectory: true)

    static func main() {
        TestDefaults.useWorkFolder()
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        launchOptions()
        watcher()
        startCheck()
        startPhases()
        print(failures == 0 ? "✓ The start against odd input" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func launchOptions() {
        func split(_ text: String) -> [String] { Launcher.splitArguments(text) }
        check(split("").isEmpty && split("   \t ").isEmpty, "nothing typed: no arguments")
        check(split(#"-foo "bar baz" -x"#) == ["-foo", "bar baz", "-x"], "quotes hold spaces together")
        check(split(#"-path="C:\Program Files\Spiel" -y"#) == [#"-path=C:\Program Files\Spiel"#, "-y"], "and work inside a word: \(split(#"-path="C:\Program Files\Spiel" -y"#))")
        check(split("  -a   -b\t-c\n") == ["-a", "-b", "-c"], "any white space separates")
        check(split("-name Jörg -städte") == ["-name", "Jörg", "-städte"], "umlauts as they are")
        check(split(#"-a "unfinished quote"#) == ["-a", "unfinished quote"], "a quote that never ends runs to the end")
    }

    static func log(_ steam: URL) -> URL { steam.appendingPathComponent("logs/console_log.txt") }

    static func append(_ text: String, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }

    static func watcher() {
        let steam = work.appendingPathComponent("steam folder ü", isDirectory: true)
        var nothing = LaunchWatcher(steamRoot: steam, appID: 730)
        check(nothing.poll() == nil && !nothing.steamReceivedLaunch, "no log yet: nothing, no crash")

        append("[2026] Game process added : AppID 730\n", to: log(steam))
        var past = LaunchWatcher(steamRoot: steam, appID: 730)
        check(past.poll() == nil, "what the log already said isn't news")
        append("[2026] GameAction [AppID 1730, ActionID 3] : Game process added\n", to: log(steam))
        check(past.poll() == nil, "another game's line (AppID 1730) isn't this one's (730)")
        append("[2026] Game process added : AppID 730\n", to: log(steam))
        check(past.poll() == .running, "a new line of this game is")

        var rotated = LaunchWatcher(steamRoot: steam, appID: 730)
        try? Data("[2026] Game process added : AppID 730\n".utf8).write(to: log(steam))
        check(rotated.poll() == .running, "Steam starting a fresh, shorter log: it's read from its start")

        try? Data().write(to: log(steam))
        var empty = LaunchWatcher(steamRoot: steam, appID: 730)
        append(String(decoding: [0xFF, 0xFE, 0x00, 0x0A], as: UTF8.self), to: log(steam))
        check(empty.poll() == nil, "bytes that aren't text are nothing")

        append("[2026] GameAction [AppID 730, ActionID 9] : LaunchApp waiting for user response to CloudSync\n", to: log(steam))
        var questioned = LaunchWatcher(steamRoot: steam, appID: 730)
        check(questioned.poll() == .needsConfirmation, "a question open before the start is told at once")
        check(questioned.poll() == nil, "and only once")
        check(questioned.questionTask == "CloudSync", "… with Steam's name for it")
        questions(steam)
        licence()
    }

    /// What Steam asks, by its name for the step: only the heading on the curtain goes by it, never an answer.
    static func questions(_ steam: URL) {
        let line = "[2026] GameAction [AppID 730, ActionID 11] : LaunchApp"
        append("\(line) continues with user response \"CloudSync\"\n", to: log(steam))  // nothing left open from before
        var watcher = LaunchWatcher(steamRoot: steam, appID: 730)
        append("\(line) waiting for user response to ShowGameArgs \"\"\n", to: log(steam))
        check(watcher.poll() == .needsConfirmation && watcher.questionTask == "ShowGameArgs", "the launch option's question, by name (Steam for Mac, 22.11.)")
        append("\(line) continues with user response \"ShowGameArgs\"\n", to: log(steam))
        _ = watcher.poll()
        append("\(line) waiting for user response to SynchronizingCloud \"\"\n", to: log(steam))
        check(watcher.poll() == .needsConfirmation && watcher.questionTask == "SynchronizingCloud", "the next question: its own name")
        append("\(line) waiting for user response\n", to: log(steam))
        check(watcher.poll() == .needsConfirmation && watcher.questionTask == "SynchronizingCloud", "a line without a name keeps the one before")

        check(SteamQuestion.task(in: "x : LaunchApp waiting for user response to ShowEula \"\"") == "ShowEula", "the name ends at the quotes")
        check(SteamQuestion.task(in: "x : LaunchApp waiting for user response to CloudSync") == "CloudSync", "or at the line's end")
        check(SteamQuestion.task(in: "x : LaunchApp waiting for user response to ") == nil
              && SteamQuestion.task(in: "x : LaunchApp changed task to ShowEula") == nil, "no name, or no question: none")

        typealias Q = SteamQuestion
        check(Q.kind(licence: true, task: "ShowInterstitials", phase: nil) == .licence, "the licence as the watcher saw it")
        check(Q.kind(licence: false, task: "ShowEula", phase: nil) == .licence, "or by its name")
        check(Q.kind(licence: false, task: "ShowGameArgs", phase: nil) == .launchOption, "the launch option")
        check(Q.kind(licence: false, task: "CloudSync", phase: nil) == .cloud && Q.kind(licence: false, task: "SynchronizingCloud", phase: nil) == .cloud,
              "the cloud, whatever Steam calls the step")
        check(Q.kind(licence: false, task: "ShowInterstitials", phase: nil) == .other && Q.kind(licence: false, task: nil, phase: nil) == .other,
              "anything else: \"Steam is asking something\", as before")
        check(Q.kind(licence: false, task: nil, phase: .signInAgain) == .signIn && Q.kind(licence: false, task: "CloudSync", phase: .signInInSteamWindow) == .signIn,
              "Steam's sign-in window, whatever step was last")
        check(Q.title(.other) == L10n.t("Steam is asking something") && Q.title(.licence) == L10n.t("The licence, just once"),
              "the two headings from before stay as they were")
        check(Q.note(.licence) == L10n.t("Steam only asks this at the first start.") && Q.note(.cloud) == nil && Q.note(.launchOption) == nil
              && Q.note(.other) == nil, "a second line only where there's something Steam's window doesn't say")
        check(Q.note(.signIn)?.contains("QR") == true, "the sign-in: the QR code, never a password")
        check([Q.Kind.licence, .launchOption, .cloud, .signIn, .other].allSatisfy { !Q.title($0).isEmpty && !Q.title($0).contains("\n") },
              "one line each")
    }

    /// Steam's licence: a question from its first word, and how its end shows in each Steam.
    static func licence() {
        let steam = work.appendingPathComponent("steam-licence", isDirectory: true)
        let line = "[2026] GameAction [AppID 1426210, ActionID 1] : LaunchApp"
        func say(_ text: String) { append("\(line) \(text)\n", to: log(steam)) }
        append("", to: log(steam))

        var watcher = LaunchWatcher(steamRoot: steam, appID: 1_426_210)
        check(!watcher.licenceAsked, "nothing asked yet")
        say("changed task to ShowEula with \"\"")
        check(watcher.poll() == .licence && watcher.licenceAsked, "the licence from its first word on")
        say("waiting for user response to ShowEula \"\"")
        check(watcher.poll() == .licence, "and the wait for it")
        check(watcher.poll() == nil && !watcher.wentOnAfterLicence, "the Windows Steam stays there after a yes, without a word")

        say("waiting for user response to ShowInterstitials \"\"")
        check(watcher.poll() == .needsConfirmation, "the routine step stays what it was")
        check(watcher.wentOnAfterLicence, "and Steam has moved on")

        say("continues with user response \"ShowInterstitials\"")  // nothing left open for the next one to find
        var mac = LaunchWatcher(steamRoot: steam, appID: 1_426_210)
        say("changed task to ShowEula with \"\"")
        check(mac.poll() == .licence, "Steam for Mac asks the same")
        say("continues with user response \"ShowEula\"")
        check(mac.poll() == .continued && mac.wentOnAfterLicence && mac.licenceContinued, "and goes on by itself, which says yes")

        // Asked in an earlier start, whether or not it still stands: not new, so no frame at once.
        say("waiting for user response to ShowEula \"\"")
        var earlier = LaunchWatcher(steamRoot: steam, appID: 1_426_210)
        check(earlier.licenceAsked, "known to have been asked")
        check(earlier.poll() == .needsConfirmation, "an old line isn't a new licence")
        say("changed task to CheckShaderDepotManifest with \"\"")
        check(earlier.poll() == .continued && !earlier.licenceContinued, "a new start going past it ends that wait, and says nothing of a yes")

        // The game's own installers: Steam says nothing more until they're done, however long that takes.
        say("continues with user response \"ShowEula\"")
        var install = LaunchWatcher(steamRoot: steam, appID: 1_426_210)
        check(!install.runningInstallScript, "nothing running yet")
        say("changed task to CheckShaderDepotManifest with \"\"")
        _ = install.poll()
        check(!install.runningInstallScript, "another step")
        say("changed task to RunningInstallScript with \"\"")
        check(install.poll() == nil && install.runningInstallScript, "the install script: no event, but Steam is busy")
        check(install.poll() == nil && install.runningInstallScript, "and stays so while nothing is written")
        append("[2026] GameAction [AppID 142621, ActionID 1] : LaunchApp changed task to SynchronizingStats with \"\"\n", to: log(steam))
        _ = install.poll()
        check(install.runningInstallScript, "another game's step changes nothing")
        say("changed task to SynchronizingStats with \"\"")
        _ = install.poll()
        check(!install.runningInstallScript, "the next step ends it")

        let interfaceLog = steam.appendingPathComponent("logs/webhelper_js.txt")
        append("SteamUI: INFO: accepted eula 1426210_eula_1\nSteamUI: INFO: eulas complete 1426210_eula_1\n", to: interfaceLog)
        var answers = SteamLicenceLog(steamRoot: steam, appID: 1_426_210)
        check(!answers.answered(), "a yes from before this start isn't this start's")
        append("SteamUI: INFO: prompt for eula 1426210_eula_1\n", to: interfaceLog)
        check(!answers.answered(), "being asked")
        append("SteamUI: INFO: accepted eula 1426210_eula_1\nSteamUI: INFO: eulas complete 1426210_eula_1\n", to: interfaceLog)
        check(answers.answered() && answers.answered(), "the yes, and it stays one")
        answers.askedAgain()
        check(!answers.answered(), "Steam asking again needs another")

        // The frame comes before Steam's window does: that wait is longer than the usual one.
        func step(_ since: TimeInterval, licence: Bool) -> LibraryModel.SteamOnCurtain {
            LibraryModel.steamOnCurtainStep(lowest: nil, sinceSeen: since, savesToChoose: false,
                                            patience: licence ? LibraryModel.licenceWindowPatience : LibraryModel.steamWindowPatience)
        }
        check(step(9, licence: false) == .giveUp && step(9, licence: true) == .wait, "9 s without a window: over for a question, not for the licence")
        check(step(LibraryModel.licenceWindowPatience, licence: true) == .giveUp, "but not for ever")
    }

    static func startCheck() {
        let steam = work.appendingPathComponent("steam-check", isDirectory: true)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let signs = SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: start.addingTimeInterval(120))
        check(!signs.signedIn && !signs.startupFinished && signs.quietFor == 120, "no logs folder at all: nothing signed in, quiet since the start")
        check(SteamStartCheck.judge(signs) == .failed, "that long with its process and no log: failed")

        // A log from the session before says nothing of this start.
        let connection = steam.appendingPathComponent("logs/connection_log.txt")
        append("[2026-11-08 10:00:00] Logged On\n", to: connection)
        try? FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(-600)], ofItemAtPath: connection.path)
        check(!SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: start.addingTimeInterval(120)).signedIn,
              "an old log's “Logged On” isn't this start's")

        // Never failed early, whatever else is wrong.
        for since in stride(from: 0.0, to: SteamStartCheck.patience, by: 13.0) {
            for running: Bool? in [true, false, nil] {
                let judged = SteamStartCheck.judge(.init(running: running, quietFor: 10_000, sinceStart: since))
                check(judged == .undecided, "before its patience is up: undecided (\(since), \(String(describing: running)))")
            }
        }
        // Not knowing isn't failing.
        check(SteamStartCheck.judge(.init(running: nil, quietFor: 10_000, sinceStart: 500)) == .undecided, "no process list: not judged")
        // A sign of life wins over everything.
        check(SteamStartCheck.judge(.init(askingForAccount: true, running: false, quietFor: 10_000, sinceStart: 500)) == .cameUp, "its window asking counts as up")
        // An update takes as long as it takes.
        check(SteamStartCheck.judge(.init(bootstrap: .downloading, running: false, quietFor: 10_000, sinceStart: 5000)) == .undecided, "while it updates itself: never judged")
    }

    /// The start's phases in the log (docs/ENTWURF-STARTZEIT.md): one line each, the time of day to a tenth and the
    /// seconds since Play – only with the test switch gameTest.startPhases (the finished build measures nothing).
    static func startPhases() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second, parts.nanosecond) = (2026, 11, 22, 19, 34, 26, 400_000_000)
        let play = Calendar.current.date(from: parts)!
        check(GameLog.clock(play) == "19:34:26" && GameLog.clock(play, tenths: true) == "19:34:26.4", "the time of day, to a tenth when asked")

        let off = TestDefaults.suite("start-phases-off")
        check(!GameTest.notesStartPhases(defaults: off), "the switch is off unless set")
        check(LibraryModel.phaseLine("Hades", "Play", at: play, since: play, defaults: off) == nil
              && LibraryModel.phaseLine("Hades", "to Steam", at: play.addingTimeInterval(1), since: play, defaults: off) == nil,
              "without the switch: no line at all")

        let on = TestDefaults.suite("start-phases-on")
        on.set(true, forKey: GameTest.startPhasesKey)
        check(GameTest.startPhasesKey == "gameTest.startPhases" && GameTest.notesStartPhases(defaults: on), "the switch, by its name")
        check(LibraryModel.phaseLine("Hades", "Play", at: play, since: play, defaults: on) == "Start phases of Hades: Play at 19:34:26.4",
              "Play itself: no seconds since")
        check(LibraryModel.phaseLine("Hades", "to Steam", at: play.addingTimeInterval(1.04), since: play, defaults: on)
              == "Start phases of Hades: to Steam at 19:34:27.4, 1.0 s after Play", "a phase: the time, and the seconds since Play")
        check(LibraryModel.phaseLine("Hades", "curtain down", at: play.addingTimeInterval(29.96), since: play, defaults: on)?.hasSuffix("30.0 s after Play") == true,
              "rounded to a tenth")
        check(LibraryModel.phaseLine("Hades", "x", at: play, since: play.addingTimeInterval(5), defaults: on)?.hasSuffix(", 0.0 s after Play") == true,
              "never before Play")
        check(LibraryModel.phaseLine("Hades", "Play", at: play, since: play, defaults: on)?.contains("Curtain down for") == false,
              "a line of its own: GameTestMeasure reads \"Curtain down for\" by its exact words")
        // The model writes these lines through phaseLine only, so the switch holds for each of them.
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(model.components(separatedBy: "Start phases of").count == 3, "\"Start phases of\" only in phaseLine (and its comment)")
    }
}
