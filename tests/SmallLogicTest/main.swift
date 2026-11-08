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
        ratings()
        testDays()
        moving()
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
