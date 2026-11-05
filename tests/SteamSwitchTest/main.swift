// Checks which of the two Steams runs (SteamSwitch), their sign-in as they log it (SteamLogin),
// Steam for Mac in the first start (MacSteamPrep, its lines, the reveal's Mac count) and its test
// home: tests/SteamSwitchTest/run.sh. Nothing here starts, stops or reads a real Steam.
import Foundation

@main
struct SteamSwitchTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ lines: [String], to url: URL, modified: Date? = nil) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }

    @MainActor
    static func main() async {
        TestDefaults.useWorkFolder()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--test-home"), arguments.count > index + 1 {
            await testHome(arguments[index + 1])
        } else {
            await everything()
        }
        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print(arguments.contains("--test-home") ? "✓ Steam for Mac stays in a test home" : "✓ SteamSwitch")
    }

    /// Run in a home of its own (HOME and CFFIXED_USER_HOME): the player's Steam for Mac – in
    /// /Applications on the dev Mac, maybe running – is none of its business, and Valve's never runs
    /// there: it would start itself again in the real home (TestSteam). The stand-in goes through a
    /// whole first start, and no Steam for Mac from the real home starts meanwhile.
    @MainActor
    static func testHome(_ home: String) async {
        let fm = FileManager.default
        let began = Date()
        let path = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        let realHome = TestSteam.realHome ?? ""
        let realLog = realHome + "/Library/Application Support/Steam/logs/connection_log.txt"
        let realLogBefore = try? fm.attributesOfItem(atPath: realLog)[.modificationDate] as? Date
        check(MacSteam.isTestHome, "a home of its own is a test home")
        check(path(MacSteam.root.path).hasPrefix(path(home) + "/"), "Steam for Mac's folder is in the test home: \(MacSteam.root.path)")
        check(MacSteam.app == nil, "the player's Steam.app doesn't count there: \(MacSteam.app?.path ?? "none")")
        check(!MacSteam.isInstalled && !MacSteam.isReady, "so Steam for Mac isn't set up there")
        check(MacSteam.running.isEmpty && !MacSteam.isRunning, "nor does a Steam for Mac running outside it")
        check(!MacSteam.endsWithNightforge(), "the shutdown script never quits one by bundle ID from there")

        // MARK: Valve's never starts there
        let valve = ["/Applications/Steam.app/Contents/MacOS/steam_osx",
                     realHome + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx",
                     home + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx"]
        for program in valve {
            check(!TestSteam.mayLaunch(URL(fileURLWithPath: program)), "never Valve's: \(program)")
        }
        // A copy of Valve's Steam.app in the test home (an earlier test left one in build/f2): not Steam for Mac there.
        let copy = URL(fileURLWithPath: home).appendingPathComponent("Applications/Steam.app/Contents", isDirectory: true)
        try? fm.createDirectory(at: copy.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        _ = (["CFBundleIdentifier": "com.valvesoftware.steam", "CFBundleExecutable": "steam_osx"] as NSDictionary)
            .write(to: copy.appendingPathComponent("Info.plist"), atomically: true)
        check(MacSteam.app == nil && !MacSteam.isInstalled, "a copy of Valve's Steam.app in the test home isn't used")
        check(!TestSteam.mayLaunch(copy.appendingPathComponent("MacOS/steam_osx")), "nor started")

        // MARK: The stand-in's first start
        defer { TestSteam.terminate() }
        do { try await MacSteam.install() } catch { check(false, "the stand-in installs: \(error)") }
        check(MacSteam.app == TestSteam.app && TestSteam.isStandIn(TestSteam.app), "the stand-in is Steam for Mac there")
        check(TestSteam.mayLaunch(TestSteam.executable), "and the one program it may start")
        // The stand-in itself won't run without HOME or in the real home – there under a sandbox that
        // keeps the real Steam folder read-only, should it ever get past that.
        func standIn(home: String?, sandboxed: Bool) -> Int32 {
            let process = Process()
            let realSteam = realHome + "/Library/Application Support/Steam"
            let profile = "(version 1)(allow default)(deny file-write* (subpath \"\(realSteam)\"))"
            process.executableURL = URL(fileURLWithPath: sandboxed ? "/usr/bin/sandbox-exec" : "/bin/bash")
            process.arguments = (sandboxed ? ["-p", profile, "/bin/bash"] : []) + [TestSteam.executable.path, "-silent"]
            process.environment = home.map { ["HOME": $0, "PATH": "/usr/bin:/bin"] } ?? ["PATH": "/usr/bin:/bin"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }
        check(standIn(home: nil, sandboxed: false) == 1, "the stand-in won't run without HOME")
        if fm.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            check(standIn(home: realHome, sandboxed: true) == 1, "nor in the real home")
            check(!fm.fileExists(atPath: realHome + "/Library/Application Support/Steam/nightforge-test-steam.pid"),
                  "and leaves nothing there")
        }
        var reports: [MacSteam.Preparation] = []
        let preparing = Task { @MainActor in try? await MacSteam.prepare { reports.append($0) } }
        let deadline = Date().addingTimeInterval(30)
        while reports.last != .waitingForSignIn, Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        preparing.cancel()
        check(reports.last == .waitingForSignIn, "it updates, then its sign-in waits: \(reports.suffix(3))")
        check(reports.contains { if case .updating = $0 { return true } else { return false } }, "its update is followed")
        check(MacSteam.isRunning && !MacSteam.signedIn && !MacSteam.hasSignedIn, "running, signed out")
        MacSteam.open("run/275850")
        fm.createFile(atPath: TestSteam.signInTrigger.path, contents: nil)
        while !(MacSteam.signedIn && MacSteam.hasSignedIn && MacSteam.startupFinished), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        check(MacSteam.signedIn && MacSteam.hasSignedIn && MacSteam.startupFinished, "the scan signs it in, and it remembers the account")
        check(MacSteam.account == "76561190000000001", "its account: \(MacSteam.account ?? "none")")
        let console = (try? String(contentsOf: MacSteam.root.appendingPathComponent("logs/console_log.txt"), encoding: .utf8)) ?? ""
        check(console.contains("ExecuteSteamURL: \"steam://run/275850\""), "a steam:// command reaches the running one")
        await MacSteam.quit()
        check(!MacSteam.isRunning, "it quits")

        // MARK: Nothing of the real Steam for Mac meanwhile
        let leaked = TestSteam.leaks(TestSteam.processes(), since: began, realHome: TestSteam.realHome, testHome: path(home))
        check(leaked.isEmpty, "no Steam for Mac from the real home started: \(leaked)")
        let realLogAfter = try? fm.attributesOfItem(atPath: realLog)[.modificationDate] as? Date
        check(realLogAfter == realLogBefore, "the real Steam for Mac's connection log is untouched")
    }

    @MainActor
    static func everything() async {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("steam-switch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        check(!MacSteam.isTestHome, "the real home isn't a test home")

        // MARK: Sign-in state (steamui_login.txt, Steam for Mac on 26./27.10.2026)
        let waiting = [
            "[2026-10-26 10:29:48] Client version: 1792618285",
            "[2026-10-26 10:29:48] [ None ] SetLoginState: WaitingForCredentials - OK",
            "[2026-10-26 10:29:48] [ WaitingForCredentials ] UI Request: connect",
            "[2026-10-26 10:30:56] [ WaitingForCredentials ] Received logon failure response",
        ]
        let silent = [
            "[2026-10-27 22:33:36] Client version: 1792618285",
            "[2026-10-27 22:33:36] [ None ] Starting login",
            "[2026-10-27 22:33:36] [ None ] SetLoginState: WaitingForNetwork - OK",
            "[2026-10-27 22:33:36] [ WaitingForNetwork ] Initiating LogOn via state machine transition",
            "[2026-10-27 22:33:36] [ WaitingForNetwork ] SetLoginState: WaitingForServerResponse - OK",
            "[2026-10-27 22:33:37] [ WaitingForServerResponse ] Received logon success response",
            "[2026-10-27 22:33:37] [ WaitingForServerResponse ] SetLoginState: WaitingForLibraryReady - OK",
            "[2026-10-27 22:33:38] [ WaitingForLibraryReady ] SetLoginState: Success - OK",
        ]
        func state(_ lines: [String]) -> String? { SteamLogin.state(log: lines.joined(separator: "\r\n")) }
        check(state(waiting) == "WaitingForCredentials", "the first start waits for a sign-in")
        check(state(waiting + silent) == "Success", "a later start signs in by itself: \(state(waiting + silent) ?? "nil")")
        check(state(silent + ["[2026-10-28 09:00:00] Client version: 1792618285"]) == nil, "a start that hasn't got far yet has no state")
        check(state(silent + Array(waiting)) == "WaitingForCredentials", "a remembered sign-in that ran out asks again")
        check(state([]) == nil, "no log, no state")

        let root = work.appendingPathComponent("Steam", isDirectory: true)
        let login = root.appendingPathComponent("logs/steamui_login.txt")
        let now = Date()
        write(waiting, to: login, modified: now)
        check(SteamLogin.waitingForCredentials(steamRoot: root, since: now.addingTimeInterval(-5)), "its window waits since the start")
        check(!SteamLogin.waitingForCredentials(steamRoot: root, since: now.addingTimeInterval(5)), "an older wait isn't this start's")
        write(waiting + silent, to: login, modified: now)
        check(!SteamLogin.waitingForCredentials(steamRoot: root, since: now.addingTimeInterval(-5)), "signed in: no wait")

        // MARK: The account a Steam remembers (loginusers.vdf)
        func account(_ text: String) -> String? { SteamLogin.rememberedAccount(users: VDF.parse(text)?["users"]) }
        check(account(#""users" { "76561198118309630" { "AccountName" "a" "RememberPassword" "1" "AutoLogin" "1" "timestamp" "1793225799" } }"#)
              == "76561198118309630", "the one account, as Steam writes it today")
        check(account(#""users" { "1" { "MostRecent" "0" "timestamp" "9" } "2" { "MostRecent" "1" "timestamp" "1" } }"#) == "2",
              "the most recent one")
        check(account(#""users" { "1" { "AutoLogin" "0" "timestamp" "9" } "2" { "AutoLogin" "1" "timestamp" "1" } }"#) == "2",
              "else the one Steam signs in by itself")
        check(account(#""users" { "1" { "timestamp" "5" } "2" { "timestamp" "9" } }"#) == "2", "else the newest")
        check(account(#""users" { }"#) == nil && account("") == nil, "nobody")
        write([#""users" { "76561198118309630" { "AutoLogin" "1" } }"#], to: root.appendingPathComponent("config/loginusers.vdf"))
        check(SteamLogin.rememberedAccount(steamRoot: root) == "76561198118309630", "read from a Steam's folder")

        // MARK: The test home's guard
        let start = Date()
        let real = "/Users/player"
        let found = TestSteam.leaks([
            (1, real + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx", start.addingTimeInterval(37)),
            (2, "/Applications/Steam.app/Contents/MacOS/steam_osx", start.addingTimeInterval(1)),
            (3, real + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/ipcserver", start.addingTimeInterval(-3600)),
            (4, "/tmp/fh/Applications/Nightforge Test Steam.app/Contents/MacOS/nightforge-test-steam", start.addingTimeInterval(2)),
            (5, "/tmp/fh/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx", start.addingTimeInterval(3)),
            (6, "/bin/bash", start.addingTimeInterval(4)),
        ], since: start, realHome: real, testHome: "/tmp/fh")
        check(found == [1, 2, 5], "Valve's Steam for Mac started since is a leak, from wherever; older ones and the stand-in aren't: \(found)")
        check(!TestSteam.mayLaunch(URL(fileURLWithPath: "/Applications/Steam.app/Contents/MacOS/steam_osx")),
              "outside a test home nothing goes through the stand-in")

        // MARK: The rules
        typealias Facts = SteamSwitch.Facts
        let afterGame = Facts(macSteamRunning: true, macSteamOurs: true, windowsSteamRunning: false)
        check(SteamSwitch.switchesBackAfterMac(afterGame), "after a Mac version, Steam for Mac goes")
        var facts = afterGame
        facts.macSteamOurs = false
        check(!SteamSwitch.switchesBackAfterMac(facts), "not one the player opened")
        facts = afterGame
        facts.macGameBusy = true
        check(!SteamSwitch.switchesBackAfterMac(facts), "not while another Mac version runs or starts")
        facts = afterGame
        facts.macDownload = true
        check(!SteamSwitch.switchesBackAfterMac(facts), "not while a Mac download has its turn")
        facts = afterGame
        facts.macSteamRunning = false
        check(!SteamSwitch.switchesBackAfterMac(facts), "nothing to do when it's gone already")
        facts = afterGame
        facts.moving = true
        check(!SteamSwitch.switchesBackAfterMac(facts), "not while a game moves to another drive (it starts its Steam itself)")

        check(SteamSwitch.stopsWindowsForMac(Facts(windowsSteamRunning: true)), "a Mac version: the Windows Steam goes")
        check(!SteamSwitch.stopsWindowsForMac(Facts(windowsSteamRunning: true, windowsGameBusy: true)), "not under a Windows game")
        check(!SteamSwitch.stopsWindowsForMac(Facts()), "nor when it doesn't run")

        check(SteamSwitch.quitsMacForWindows(Facts(macSteamRunning: true, macSteamOurs: true)), "a Windows game: Nightforge's Steam for Mac goes")
        check(!SteamSwitch.quitsMacForWindows(Facts(macSteamRunning: true)), "the player's own stays (Windows signs it out)")
        check(!SteamSwitch.quitsMacForWindows(Facts(macSteamRunning: true, macSteamOurs: true, macGameBusy: true)),
              "not under a Mac version")

        check(SteamSwitch.restartsWindows(stoppedByNightforge: true, running: false, replaced: false), "quit for Steam for Mac: back again")
        check(!SteamSwitch.restartsWindows(stoppedByNightforge: true, running: true, replaced: false), "unless it's back already")
        check(SteamSwitch.restartsWindows(stoppedByNightforge: false, running: true, replaced: true), "signed out: signs in again")
        check(!SteamSwitch.restartsWindows(stoppedByNightforge: false, running: true, replaced: false), "signed in: stays")
        check(!SteamSwitch.restartsWindows(stoppedByNightforge: false, running: false, replaced: true),
              "one that isn't running and Nightforge didn't quit isn't the switch's to start")

        // MARK: Saves on their way to the cloud (remotecache.vdf, CloudSaves)
        let macRoot = work.appendingPathComponent("SteamForMac", isDirectory: true)
        let bottle = Bottle(name: "Steam for Mac", url: macRoot)
        var nms = Game(appID: 275850, name: "No Man's Sky", bottle: bottle, steamRoot: macRoot, steamExeWindowsPath: "",
                       installDir: macRoot.appendingPathComponent("steamapps/common/No Man's Sky", isDirectory: true), sizeOnDisk: 0)
        nms.platform = .mac
        let record = macRoot.appendingPathComponent("userdata/158043902/275850/remotecache.vdf")
        func cache(_ syncstate: String, modified: Date) {
            write([#""275850" { "ChangeNumber" "12" "st_76561198118309630/save.hg" { "size" "4096" "syncstate" "\#(syncstate)" } }"#],
                  to: record, modified: modified)
        }
        let switcher = SteamSwitch()
        let ended = Date().addingTimeInterval(-20)
        check(await !switcher.savesPending(.mac), "no game ended yet")
        cache("1", modified: ended.addingTimeInterval(-600))
        switcher.ended(nms, at: ended)
        check(await switcher.savesPending(.mac), "the record from before the game: the save isn't confirmed")
        check(await !switcher.savesPending(.windows), "the other side has nothing on its way")
        cache("2", modified: Date())
        check(await switcher.savesPending(.mac), "rewritten but not in step yet")
        cache("1", modified: Date())
        check(await !switcher.savesPending(.mac), "in step since the game ended: up")
        cache("2", modified: Date())
        check(await !switcher.savesPending(.mac, now: ended.addingTimeInterval(SteamSwitch.backgroundPatience + 1)),
              "after the patience it's Steam's business at its next start")
        try? fm.removeItem(at: record)
        check(await !switcher.savesPending(.mac), "a game without Steam Cloud has nothing to wait for")
        let epic = Game(gameID: .epic("Sugar"), name: "Rocket League", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                        steamExeWindowsPath: "", installDir: work, sizeOnDisk: 0)
        let fresh = SteamSwitch()
        fresh.ended(epic, at: ended)
        check(fresh.lastSession.isEmpty, "games of other stores don't go through Steam")
        let started = Date()
        cache("2", modified: Date())
        await switcher.waitForSaves(.mac, limit: 60) { Date().timeIntervalSince(started) < 1 }
        check(Date().timeIntervalSince(started) < 10, "waiting stops when it's no longer wanted")

        // MARK: The first start
        check(MacSteamPrep.decide(macAccount: nil, windowsAccount: "1", macVersions: 12) == .signIn, "Mac versions: the second code")
        check(MacSteamPrep.decide(macAccount: nil, windowsAccount: "1", macVersions: 0) == .notNeeded, "none: no second code")
        check(MacSteamPrep.decide(macAccount: "1", windowsAccount: "1", macVersions: 12) == .alreadySignedIn, "the same account: done")
        check(MacSteamPrep.decide(macAccount: "2", windowsAccount: "1", macVersions: 12) == .otherAccount, "another account: left alone")
        check(MacSteamPrep.decide(macAccount: "2", windowsAccount: nil, macVersions: 0) == .otherAccount, "even without Mac versions")

        let update = [
            "[2026-10-26 10:28:55] Startup - updater built Mar  2 2026 12:16:40",
            "[2026-10-26 10:28:56] Startup - updater built Mar  2 2026 12:16:40",
            "[2026-10-26 10:28:57] Downloading update (8,160 of 289,112 KB)...",
            "[2026-10-26 10:29:02] Downloading update (85,851 of 289,112 KB)...",
            "[2026-10-26 10:29:03] Downloading update (102,358 of 289,112 KB)...",
        ].joined(separator: "\n")
        let updating = SetupDetail.macSteam(.preparing(.updating(0.35)), log: update) ?? ""
        let amount = SetupDetail.transfer(done: 102_358 * 1024, total: 289_112 * 1024, bytesPerSecond: (102_358 - 8_160) * 1024 / 6)
        check(updating == L10n.t("Steam for Mac updates itself: %@", amount), "its update from its own log: \(updating)")
        check(SetupDetail.macSteam(.preparing(.updating(nil)), log: "") == L10n.t("Steam for Mac updates itself …"), "before it says how much")
        check(SetupDetail.macSteam(.preparing(.installing), log: "") == L10n.t("Downloading Steam for Mac …"), "Valve's installer")
        check(SetupDetail.macSteam(.ready(.waitingForSignIn), log: "") == L10n.t("Ready – you sign in right after Steam"), "ready")
        check(SetupDetail.macSteam(.ready(.remembered), log: "") == L10n.t("Already signed in on this Mac"), "the player's own")
        check(SetupDetail.macSteam(.done(.notNeeded), log: "") == L10n.t("Not needed – none of your games has a Mac version"), "not needed")
        check(SetupDetail.macSteam(.idle, log: "") == nil, "nothing before it starts")
        check(MacSteamPrep.signInNote(macVersions: 12).contains("12"), "the second code says how many games it is for")
        let prep = MacSteamPrep()
        check(!prep.primary() && !prep.back(), "Return and Esc are the setup's until its code is up")
        check(!prep.secondCodeFollows && prep.detail == nil, "nothing said before it starts")
        prep.abandon()
        check(prep.state == .idle && !prep.isGettingReady, "a first start that closes before it started leaves it alone")

        // MARK: The reveal's Mac versions
        func card(_ id: Int, mac: Bool = false, pending: Bool = false) -> Game {
            var game = Game(appID: id, name: "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                            installDir: Engine.bottle.url, sizeOnDisk: 0)
            game.install = .installed
            if mac { game.platform = .mac }
            if pending { game.macPending = .notInstalled }
            return game
        }
        var store = card(4, mac: true)
        store.install = .inStore
        let reveal = LibraryReveal([(card(1, mac: true), .great), (card(2, pending: true), .great), (card(3), .tweaks), (store, .great)])
        check(reveal.mac == 2, "Mac versions counted, played or on their way, own games only: \(reveal.mac)")
        check(reveal.macLine(later: false) == L10n.t("%ld of them play as their Mac version – without any Windows translation.", 2), "the line")
        check(reveal.macLine(later: true) == L10n.t("%ld have a Mac version – Nightforge sets it up the first time you play one.", 2), "after Later")
        check(LibraryReveal(great: 3).macLine(later: false) == nil, "no Mac versions, no line")
        check(LibraryReveal(great: 1, mac: 1) != LibraryReveal(great: 1), "the Mac count is part of the reveal")
    }
}
