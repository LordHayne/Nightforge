// Small logic no other series reaches, with the values that hurt: the download lines (nothing known, the whole file,
// no size), every launch phase's words in both languages, a damaged rating, a test day in a profile's note,
// and the move of Nightforge's data folder when the new one already exists: tests/SmallLogicTest/run.sh
import Foundation

@main
struct SmallLogicTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()
        downloadLines()
        phases()
        repairs()
        errorBox()
        ratings()
        testDays()
        moving()
        damagedLogNumbers()
        print(failures == 0 ? "✓ Small logic" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func game(_ install: InstallState) -> Game {
        var game = Game(gameID: .steam(4000), name: "G", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 1)
        game.install = install
        return game
    }

    static func downloadLines() {
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        check(DownloadsPanel.status(fraction: 0.37, total: 0, rate: nil).progress == "37 %", "no size known: the percent alone")
        let sized = DownloadsPanel.status(fraction: 0.5, total: 2_000_000_000, rate: nil)
        check(sized.progress.hasPrefix("50 % of ") && sized.speed == nil, "with a size: \(sized)")
        check(DownloadsPanel.status(fraction: 0, total: 1, rate: nil).progress.hasPrefix("0 %"), "just begun")
        check(DownloadsPanel.status(fraction: 1, total: 1, rate: nil).progress.hasPrefix("100 %"), "the end")
        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        check(!DownloadsPanel.status(fraction: 0.5, total: 2_000_000_000, rate: nil).progress.contains("%@"), "in German too, with no placeholder left")
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)

        check(DownloadsButton.progress([]) == 0, "nothing downloading: 0, not a division by nothing")
        check(DownloadsButton.progress([game(.downloading(nil))]) == 0, "one without a share yet: 0")
        check(abs(DownloadsButton.progress([game(.downloading(0.5)), game(.downloading(1))]) - 0.75) < 0.0001, "the average")
    }

    static func phases() {
        let all: [LaunchPhase] = [.startingSteam, .startingSteamForMac, .signingIn, .signInInSteamWindow, .signInAgain, .savingToCloud, .settingUp, .settingUpDotNet,
                                  .restartingSteam, .steamNotResponding, .retrying("DXVK"), .updating(0.42), .updating(nil), .signingInEpic, .syncingSaves,
                                  .rollingBack, .heldEngine, .settingUpWindowsParts(nil), .settingUpWindowsParts("vcredist")]
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            for phase in all {
                check(!phase.title.isEmpty && !phase.title.contains("%@") && !phase.title.contains("%ld"), "\(phase) in \(language): “\(phase.title)”")
                check(!phase.hint.isEmpty && !phase.hint.contains("%@"), "\(phase)'s line under it, in \(language): “\(phase.hint)”")
            }
        }
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        check(LaunchPhase.updating(0.42).title == "Updating … 42 %", "how far an update is: \(LaunchPhase.updating(0.42).title)")
        check(LaunchPhase.retrying("DXVK").title.contains("DXVK"), "which way it tries next")
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
    }

    /// What the curtain says while Nightforge mends a start (LaunchRepair, board B of 15.11.2026).
    static func repairs() {
        let all: [LaunchRepair] = [.looking, .again, .onceMore, .otherWay, .settingUp, .closerLook, .gaveUp]
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            for repair in all {
                check(!repair.title.isEmpty && !repair.detail.isEmpty && repair.steps.count == 3, "\(repair) in \(language): a line, a sentence, three steps")
                check(repair.steps.allSatisfy { !$0.label.isEmpty } && Set(repair.steps.map(\.label)).count == 3, "\(repair) in \(language): three different steps")
                // Done first, then the one at work, then what's still to come: never a step marked done after one not done.
                let marks = repair.steps.map(\.mark)
                let order: [LaunchRepair.Step.Mark: Int] = [.done: 0, .now: 1, .next: 2]
                check(marks == marks.sorted { order[$0]! < order[$1]! } && marks.first == .done, "\(repair): \(marks) in order, starting from the start")
                check(marks.filter { $0 == .now }.count == (repair == .gaveUp ? 0 : 1), "\(repair): one step at work, none at the end")
            }
        }
        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        // The board's words (B, the player's pick).
        check(LaunchRepair.again.title == "Noch ein Versuch …" && LaunchRepair.looking.title == "Einen Moment …"
              && LaunchRepair.otherWay.title == "Noch ein Versuch, auf anderem Weg …" && LaunchRepair.gaveUp.title == "Das hat nicht geklappt.",
              "the lines as the board has them")
        check(LaunchRepair.again.steps.map(\.label) == ["Gestartet", "Ursache gefunden", "Startet noch einmal"]
              && LaunchRepair.looking.steps.map(\.label) == ["Gestartet", "Sieht nach", "Neuer Versuch"],
              "the steps as the board has them")
        check(LaunchRepair.gaveUp.detail == "Nightforge hat alles versucht, was es kennt. Gleich bist du zurück in der Bibliothek.", "the honest end")
        // Nothing technical on the curtain: no way, no DLL, no layer.
        let technical = ["DXVK", "DXMT", "D3DMetal", "Wine", "DLL", "nvapi", "PhysX", "AVX", "Direct3D"]
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            for repair in all {
                let words = ([repair.title, repair.detail] + repair.steps.map(\.label)).joined(separator: " ")
                check(!technical.contains { words.contains($0) }, "\(repair) in \(language) says nothing technical: \(words)")
            }
        }
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        // What the decision after a failed start puts on the curtain.
        let learned = StartRecipe.Learned()
        check(LaunchRepair.after(.again(learned, why: ["nvidia-interface"])) == .again
              && LaunchRepair.after(.again(learned, why: [NextStart.fileEdits])) == .again, "the recipe changed: one more try")
        check(LaunchRepair.after(.again(learned, why: ["missing-runtime"])) == .settingUp
              && LaunchRepair.after(.again(learned, why: ["illegal-instruction", "missing-runtime"])) == .settingUp, "a runtime: setting up")
        check(LaunchRepair.after(.again(learned, why: [NextStart.closerLook])) == .closerLook, "a closer look")
        check(LaunchRepair.after(.again(learned, why: [NextStart.engineBefore])) == nil, "the engine before has its own line")
        check(LaunchRepair.after(.way(2, why: nil)) == .otherWay && LaunchRepair.after(.way(1, why: "refused-switch")) == .otherWay, "another way")
        check(LaunchRepair.after(.giveUp) == .gaveUp, "the honest end")
        check(LaunchRepair.after(.keepsItsPlace) == nil && LaunchRepair.after(.noOtherWay) == nil, "a start that just ends says nothing of its own")
        check(LaunchRepair.endStands >= 2 && LaunchRepair.endStands <= 5, "the end stands long enough to read, not longer")
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
    }

    /// The game's own error box under the curtain (board way 1, 15.11.2026).
    static func errorBox() {
        let wake = "Alan Wake could not initialize your 3D graphics card. Technical: DEVICE_CREATE_ERROR - Not available"
        check(CloserLook.errorNotice(wake) && CloserLook.errorNotice("Failed to load SteamAPI")
              && CloserLook.errorNotice("Das Spiel konnte nicht gestartet werden."), "a box that reports a failure and asks nothing")
        check(!CloserLook.errorNotice("Fatal error! Would you like to send a crash report?") && !CloserLook.errorNotice("Start in safe mode?")
              && !CloserLook.errorNotice("Your graphics driver is older than recommended.") && !CloserLook.errorNotice(""),
              "one that asks, even after a failure, or only says something: not one")
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            let line = LibraryModel.curtainStatus(phase: nil, shaders: false, gameRuns: true, asks: true, errorBox: true, padAnswers: ("A", "B"))
            check(line == L10n.t("The game reports an error") && line?.isEmpty == false, "the line over an error box, in \(language): \(line ?? "nil")")
            let withPad = LibraryModel.curtainDetail(launchHint: "hint", asks: true, errorBox: true, padOK: "A", macOSOpen: false)
            let withoutPad = LibraryModel.curtainDetail(launchHint: "hint", asks: true, errorBox: true, padOK: nil, macOSOpen: false)
            check(withPad?.contains("A") == true && withPad?.contains("OK") == true && withoutPad?.contains("OK") == true && withPad != withoutPad,
                  "under it what to press, with the pad's button where it answers, in \(language): \(withPad ?? "nil") / \(withoutPad ?? "nil")")
        }
        UserDefaults.standard.set("german", forKey: AppLanguage.storageKey)
        check(LibraryModel.curtainStatus(phase: nil, shaders: false, gameRuns: true, asks: true, errorBox: true) == "Das Spiel meldet einen Fehler"
              && LibraryModel.curtainDetail(launchHint: nil, asks: true, errorBox: true, macOSOpen: false) == "Drück OK – Nightforge kümmert sich um den Rest.",
              "the board's words")
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        // A question, macOS's question, or no box read: as before.
        check(LibraryModel.curtainStatus(phase: nil, shaders: false, gameRuns: true, asks: true, padAnswers: ("A", "B"))?.contains("asking") == true
              && LibraryModel.curtainDetail(launchHint: "hint", asks: true, macOSOpen: false) == nil, "the game's question: as before, no second line")
        check(LibraryModel.curtainStatus(phase: nil, shaders: false, gameRuns: true, asks: true, errorBox: true, macOSAsks: true)?.contains("macOS") == true,
              "macOS's question comes first")
        check(LibraryModel.curtainStatus(phase: nil, shaders: false, gameRuns: true, asks: false, errorBox: true) == L10n.t("Waiting for the first picture …"),
              "no question on screen: no box said")
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
    }

    static func ratings() {
        let defaults = TestDefaults.suite("ratings")
        let id = GameID.steam(4242)
        check(GameRatings.load(id, from: defaults) == nil, "not rated: nil")
        defaults.set(Data("not json".utf8), forKey: "rating.\(id.key)")
        check(GameRatings.load(id, from: defaults) == nil, "a damaged rating is none")
        defaults.set("a string", forKey: "rating.\(id.key)")
        check(GameRatings.load(id, from: defaults) == nil, "so is one of another type")
        GameRatings.save(.choice(good: false, issues: [.crashed], way: "dxmt -dx11"), for: id, to: defaults)
        check(GameRatings.load(id, from: defaults)?.issues == [.crashed] && GameRatings.load(id, from: defaults)?.way == "dxmt -dx11", "written, and read back")
    }

    static func testDays() {
        check(ProfileOrigin.testDay(in: nil) == nil && ProfileOrigin.testDay(in: "no date") == nil, "no note, no day")
        check(ProfileOrigin.testDay(in: "Tested 2026-99-99 on M5") == nil, "a date that doesn't exist: none")
        let day = ProfileOrigin.testDay(in: "Tested 2026-10-26 on M5: fine")
        check(day != nil, "the day of a note")
        if let day {
            UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
            let calendar = Calendar.current
            check(ProfileOrigin.daysAgo(day, now: day) == "today", "the same day: \(ProfileOrigin.daysAgo(day, now: day))")
            check(ProfileOrigin.daysAgo(day, now: calendar.date(byAdding: .day, value: 1, to: day)!) == "yesterday", "a day later")
            check(ProfileOrigin.daysAgo(calendar.date(byAdding: .day, value: 3, to: day)!, now: day) == "today", "a day ahead of the clock: not “in 3 days”")
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
    }

    /// Numbers in Steam's logs as a damaged file holds them: read, not a crash at the next look.
    static func damagedLogNumbers() {
        let digits = String(repeating: "9", count: 400)
        let now = Date()
        func stamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }
        let line = "[\(stamp(now.addingTimeInterval(-30)))] Current download rate: \(digits) Mbps"
        check(MacSteamProgress.received(since: now.addingTimeInterval(-60), log: line, now: now) >= 0, "a download rate past any number")
        let run = "[\(stamp(now))] AppID 7 update started : download 9223372036854775807/9223372036854775807, x\n[\(stamp(now))] AppID 7 App update changed : Downloading,"
        let found = MacSteamProgress.currentRun(appID: 7, log: run)
        check((found?.done ?? 0) + 9_000_000 > 0, "a run's numbers leave room to add to them: \(String(describing: found))")
        check(found?.total == Game.largestSize, "and stay what they are otherwise: \(String(describing: found))")
        check(Double.infinity.clampedBytes == Game.largestSize || Double.infinity.clampedBytes == 0, "inf")
        check(Double.nan.clampedBytes == 0, "nan")
        check((-1.0).clampedBytes == 0, "below zero")
        check(1e30.clampedBytes == Game.largestSize, "past the ceiling")
        check(Legendary.progress(inLog: "Download size: \(digits) MiB").downloadSize != nil, "legendary's size past any number is read")
        check(Legendary.progress(inLog: "Download size: 99999999999999999999 MiB").downloadSize == Game.largestSize, "and one past Int64 stops at the ceiling")
    }

    static func moving() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("move-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("Nachtschicht", isDirectory: true), new = root.appendingPathComponent("Nightforge", isDirectory: true)
        try? fm.createDirectory(at: old.appendingPathComponent("Prefix"), withIntermediateDirectories: true)
        try? Data("old list".utf8).write(to: old.appendingPathComponent("components.json"))
        try? Data("the game".utf8).write(to: old.appendingPathComponent("Prefix/game.bin"))
        check(LegacyMigration.moveContents(of: old, into: new) && fm.fileExists(atPath: new.appendingPathComponent("Prefix/game.bin").path) && !fm.fileExists(atPath: old.path),
              "no new folder yet: the old one simply moves")

        try? fm.createDirectory(at: old.appendingPathComponent("Prefix2"), withIntermediateDirectories: true)
        try? Data("from before".utf8).write(to: old.appendingPathComponent("components.json"))
        try? Data("new list".utf8).write(to: new.appendingPathComponent("components.json"))
        check(LegacyMigration.moveContents(of: old, into: new), "a new folder exists: what it lacks still comes over")
        check(fm.fileExists(atPath: new.appendingPathComponent("Prefix2").path), "the prefix, above all")
        check((try? String(contentsOf: new.appendingPathComponent("components.json"), encoding: .utf8)) == "new list", "and the new copy wins")
    }
}
