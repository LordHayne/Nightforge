// Checks what "Remove Nightforge completely" deletes, keeps and copies first – on fake folders:
// tests/CompleteRemovalTest/run.sh
import Foundation

@main
struct CompleteRemovalTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ url: URL, _ text: String = "data") {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    /// Whether the work came back without throwing (its result may well be nil: no saves).
    static func works(_ work: () throws -> URL?) -> Bool {
        do { _ = try work(); return true } catch { return false }
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Collects the phases the removal reports (it reports from another thread).
    final class Phases: @unchecked Sendable {
        private let lock = NSLock()
        private var phases: [CompleteRemoval.Phase] = []
        func add(_ phase: CompleteRemoval.Phase) { lock.lock(); phases.append(phase); lock.unlock() }
        var list: [CompleteRemoval.Phase] { lock.lock(); defer { lock.unlock() }; return phases }
    }

    /// Fake folders in `base`, with a save in the Windows environment, a cache and a shortcut folder.
    static func fixture(_ base: URL) -> (places: CompleteRemoval.Places, defaults: UserDefaults) {
        let library = base.appendingPathComponent("Library", isDirectory: true)
        var places = CompleteRemoval.Places()
        places.support = library.appendingPathComponent("Application Support/Nightforge", isDirectory: true)
        places.caches = library.appendingPathComponent("Caches/Nightforge", isDirectory: true)
        places.userCache = nil
        places.library = library
        places.shortcuts = base.appendingPathComponent("Applications/Nightforge Games", isDirectory: true)
        places.documents = base.appendingPathComponent("Documents", isDirectory: true)
        places.bundleID = "io.github.lordhayne.nightforge"
        places.settingsDomain = TestDefaults.domain("removal-\(UUID().uuidString)")
        write(places.support.appendingPathComponent("Components/wine/bin/wine"))
        write(places.prefix.appendingPathComponent("drive_c/users/crossover/AppData/Roaming/Hades/Profile1.sav"), "save")
        write(places.caches.appendingPathComponent("Artwork/550.jpg"))
        write(places.shortcuts.appendingPathComponent("Valheim.app/Contents/Info.plist"))
        return (places, UserDefaults(suiteName: places.settingsDomain)!)
    }

    /// A copy of this program run as `--standin` sleeps: a process whose file lies where the test wants one.
    static func standIn(_ file: URL) -> Process? {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let me = URL(fileURLWithPath: CommandLine.arguments[0])
        guard (try? FileManager.default.copyItem(at: me, to: file)) != nil else { return nil }
        let process = Process()
        process.executableURL = file
        process.arguments = ["--standin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return (try? process.run()) != nil ? process : nil
    }

    static func gone(_ pid: pid_t) -> Bool {
        for _ in 0..<100 {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            usleep(20_000)
        }
        return false
    }

    static func main() async {
        // No real process list: a hanging ps on this Mac doesn't stop the series (tests/Shared/FakeProcesses.swift).
        FakeProcesses.installEmpty()
        if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--standin" {
            sleep(120)
            exit(0)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("removal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Library", isDirectory: true)
        var places = CompleteRemoval.Places()
        places.support = library.appendingPathComponent("Application Support/Nightforge", isDirectory: true)
        places.caches = library.appendingPathComponent("Caches/Nightforge", isDirectory: true)
        places.userCache = root.appendingPathComponent("C", isDirectory: true)
        places.library = library
        places.shortcuts = root.appendingPathComponent("Applications/Nightforge Games", isDirectory: true)
        places.documents = root.appendingPathComponent("Documents", isDirectory: true)
        places.bundleID = "io.github.lordhayne.nightforge"

        // Nightforge's things …
        let user = places.prefix.appendingPathComponent("drive_c/users/crossover", isDirectory: true)
        let game = places.steam.appendingPathComponent("steamapps/common/Left 4 Dead 2/left4dead2.exe")
        write(game)
        write(places.support.appendingPathComponent("Components/wine/bin/wine"))
        write(places.caches.appendingPathComponent("Artwork/550.jpg"))
        write(places.shortcuts.appendingPathComponent("Valheim.app/Contents/Info.plist"))
        write(library.appendingPathComponent("HTTPStorages/io.github.lordhayne.nightforge/httpstorages.sqlite"))
        write(places.userCache!.appendingPathComponent("io.github.lordhayne.nightforge.game/com.apple.metal/x.data"))
        write(places.userCache!.appendingPathComponent("org.winehq.wine/com.apple.metal/y.data"))
        // … saves in the Windows environment …
        write(user.appendingPathComponent("AppData/Roaming/Hades/Profile1.sav"), "hades save")
        write(user.appendingPathComponent("AppData/Local/Pal/Saved/SaveGames/0/World.sav"), "palworld world")
        write(user.appendingPathComponent("Documents/My Games/Skyrim/Saves/quick.ess"), "skyrim save")
        write(places.steam.appendingPathComponent("userdata/158043902/550/remote/cfg/config.cfg"), "l4d2 config")
        // … and caches beside them that aren't saves.
        write(user.appendingPathComponent("AppData/Local/Temp/huge.tmp"))
        write(user.appendingPathComponent("AppData/Local/Steam/htmlcache/index"))
        write(user.appendingPathComponent("AppData/Local/UnrealEngine/ShaderCache/a.bin"))
        write(user.appendingPathComponent("AppData/Local/D3DSCache/b.bin"))
        write(places.steam.appendingPathComponent("userdata/158043902/7/remote/sharedconfig.vdf"))
        write(places.prefix.appendingPathComponent("drive_c/users/Public/Documents/x.txt"))
        // What isn't Nightforge's.
        let steamForMac = library.appendingPathComponent("Application Support/Steam/steamapps/common/Valheim/valheim.app")
        let crossOver = library.appendingPathComponent("Application Support/CrossOver/Bottles/Games/system.reg")
        let otherCache = places.userCache!.appendingPathComponent("com.apple.Safari/com.apple.metal/z.data")
        let wineOther = places.userCache!.appendingPathComponent("org.winehq.wine/Cache.db")
        let oldDocs = places.documents.appendingPathComponent("Letter.pages")
        for file in [steamForMac, crossOver, otherCache, wineOther, oldDocs] { write(file) }

        let names = Set(CompleteRemoval.saveSources(places).map(\.name))
        check(names == ["crossover/Documents", "crossover/AppData/Roaming", "crossover/AppData/Local/Pal",
                        "Steam userdata/158043902/550"], "the saves, no caches or Steam's own: \(names.sorted())")
        check(CompleteRemoval.targets(places).count == 6, "six things to remove: \(CompleteRemoval.targets(places).map(\.lastPathComponent))")

        places.settingsDomain = TestDefaults.domain("settings")
        let defaults = UserDefaults(suiteName: places.settingsDomain)!
        defaults.set(true, forKey: "library.hidden")
        let saves = try? CompleteRemoval.remove(places, defaults: defaults)

        check(saves != nil, "the saves were copied")
        if let saves {
            check((try? String(contentsOf: saves.appendingPathComponent("crossover/AppData/Roaming/Hades/Profile1.sav"), encoding: .utf8)) == "hades save", "Hades' save is in Documents")
            check((try? String(contentsOf: saves.appendingPathComponent("crossover/AppData/Local/Pal/Saved/SaveGames/0/World.sav"), encoding: .utf8)) == "palworld world", "Palworld's world is in Documents")
            check(exists(saves.appendingPathComponent("crossover/Documents/My Games/Skyrim/Saves/quick.ess")), "Skyrim's save is in Documents")
            check(exists(saves.appendingPathComponent("Steam userdata/158043902/550/remote/cfg/config.cfg")), "Steam's per-game folder is in Documents")
            check(!exists(saves.appendingPathComponent("crossover/AppData/Local/Temp")), "no temp files copied")
            check(saves.path.contains("/Documents/Nightforge Saves/"), "under Documents/Nightforge Saves: \(saves.path)")
        }
        check(!exists(places.support) && !exists(places.caches) && !exists(places.shortcuts), "Nightforge's folders are gone")
        check(!exists(library.appendingPathComponent("HTTPStorages/io.github.lordhayne.nightforge")), "its web cache is gone")
        check(!exists(places.userCache!.appendingPathComponent("io.github.lordhayne.nightforge.game")), "the game bundle's caches are gone")
        check(!exists(game), "the Windows games went with the Windows environment")
        check(!exists(places.userCache!.appendingPathComponent("org.winehq.wine/com.apple.metal")), "Wine's shader cache is gone")
        check([steamForMac, crossOver, otherCache, wineOther, oldDocs].allSatisfy(exists),
              "Steam for Mac, CrossOver, other apps' caches, Wine's other files and your documents stay")
        check(defaults.object(forKey: "library.hidden") == nil, "the settings are gone")

        // Nothing to copy: no folder in Documents.
        var empty = places
        empty.support = root.appendingPathComponent("nothing", isDirectory: true)
        check((try? CompleteRemoval.copySaves(empty)) == .some(nil), "no saves, no folder")

        // What the question says about the games: where they stay, in every store they come from.
        let one = CompleteRemoval.gamesNote(count: 1, size: 2_000_000_000, stores: [.gog])
        check(one?.contains("GOG") == true && one?.contains("Steam") == false, "a GOG game stays in the library on GOG: \(one ?? "–")")
        let three = CompleteRemoval.gamesNote(count: 3, size: 1, stores: [.gog, .steam, .epic])
        check(three?.contains("Steam, Epic Games") == true && three.map { $0.range(of: "Epic")!.lowerBound < $0.range(of: "GOG")!.lowerBound } == true,
              "every store, in the stores' order: \(three ?? "–")")
        check(CompleteRemoval.gamesNote(count: 0, size: 0, stores: []) == nil, "no games, no line about them")

        // A test program is not the app: what `Places()` says without being told otherwise is nowhere near the
        // player's things, and the settings are a domain no one has – a test that forgets to point one place
        // elsewhere removes nothing real.
        do {
            let inert = CompleteRemoval.Places()
            let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
            check(!CompleteRemoval.isTheApp, "the test program is not the app")
            check(inert.settingsDomain != CompleteRemoval.appBundleID && inert.bundleID != CompleteRemoval.appBundleID,
                  "outside the app the settings domain isn't the app's: \(inert.settingsDomain)")
            check(inert.userCache == nil, "… no shader caches of the Mac's user folder")
            let places = [inert.support, inert.caches, inert.library, inert.shortcuts, inert.documents]
            check(places.allSatisfy { !$0.path.hasPrefix(home + "/") }, "… no place is in the real home: \(places.map(\.path))")
            check(inert.support != Engine.supportDir && inert.caches.lastPathComponent == "Nightforge", "… and not Nightforge's folder")
            check(CompleteRemoval.targets(inert).isEmpty && CompleteRemoval.saveSources(inert).isEmpty, "… nothing to remove, nothing to copy")
            do {
                try CompleteRemoval.requireApp()
                check(false, "the whole job refuses to run outside the app")
            } catch {
                if let failure = error as? CompleteRemoval.RemovalError, case .notTheApp = failure {
                    check(!failure.localizedDescription.isEmpty, "… with notTheApp, before anything is stopped")
                } else {
                    check(false, "… with notTheApp, not \(error)")
                }
            }
            let probe = UserDefaults(suiteName: TestDefaults.domain("probe"))!
            probe.set(true, forKey: "kept")
            check(works { try CompleteRemoval.remove(defaults: probe) } && probe.bool(forKey: "kept"),
                  "remove() on the default places does nothing and leaves other settings alone")
        }

        // The phases, in order, and the settings go only at the very end.
        do {
            let scenario = fixture(root.appendingPathComponent("phases", isDirectory: true))
            let phases = Phases()
            let saves = try? CompleteRemoval.remove(scenario.places, defaults: scenario.defaults, phase: { phases.add($0) })
            check(saves != nil && phases.list == [.copyingSaves, .deleting], "phases: copying saves, then deleting: \(phases.list)")
        }

        // A folder without write permission (some installers leave one) doesn't stop the removal.
        do {
            let scenario = fixture(root.appendingPathComponent("readonly", isDirectory: true))
            let locked = scenario.places.prefix.appendingPathComponent("drive_c/Program Files/Locked", isDirectory: true)
            write(locked.appendingPathComponent("inner/file.dat"))
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.appendingPathComponent("inner").path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            check(works { try CompleteRemoval.remove(scenario.places, defaults: scenario.defaults) }, "a read-only folder is made writable and deleted")
            check(!exists(scenario.places.support), "… and the Windows environment is gone")
        }

        // One thing that can't be deleted: the rest goes, the settings stay, and the error says which.
        do {
            let scenario = fixture(root.appendingPathComponent("stuck", isDirectory: true))
            let stuck = scenario.places.caches.appendingPathComponent("Artwork/550.jpg")
            write(stuck)
            try? FileManager.default.setAttributes([.immutable: true], ofItemAtPath: stuck.path)
            scenario.defaults.set(true, forKey: "library.hidden")
            var thrown: Error?
            do { try CompleteRemoval.remove(scenario.places, defaults: scenario.defaults) } catch { thrown = error }
            check(!exists(scenario.places.support), "one target stuck: the others are deleted all the same")
            check(exists(scenario.places.caches), "… the stuck one is still there")
            check(scenario.defaults.object(forKey: "library.hidden") != nil, "… and the settings stay, for the second try")
            if let failure = thrown as? CompleteRemoval.RemovalError, case .notDeleted(let names) = failure {
                check(names == ["Nightforge"], "the error names what is left: \(names)")
                check(failure.localizedDescription.contains("Nightforge"), "… in the message: \(failure.localizedDescription)")
                check(failure.localizedDescription != CompleteRemoval.RemovalError.savesNotCopied("x").localizedDescription,
                      "… which doesn't blame the copying of the saves")
            } else {
                check(false, "a stuck target throws notDeleted, not \(String(describing: thrown))")
            }
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: stuck.path)
            check(works { try CompleteRemoval.remove(scenario.places, defaults: scenario.defaults) }, "second try: everything goes")
            check(!exists(scenario.places.caches) && scenario.defaults.object(forKey: "library.hidden") == nil, "… the settings with it")
        }

        // Saves that can't be copied: nothing is deleted, and the error says so.
        do {
            let scenario = fixture(root.appendingPathComponent("nocopy", isDirectory: true))
            var places = scenario.places
            write(root.appendingPathComponent("nocopy/NotAFolder"))
            places.documents = root.appendingPathComponent("nocopy/NotAFolder")  // a file where Documents should be
            var thrown: Error?
            do { try CompleteRemoval.remove(places, defaults: scenario.defaults) } catch { thrown = error }
            if let failure = thrown as? CompleteRemoval.RemovalError, case .savesNotCopied = failure {
                check(!failure.localizedDescription.isEmpty, "saves not copied: the error has its words")
            } else {
                check(false, "saves that can't be copied throw savesNotCopied, not \(String(describing: thrown))")
            }
            check(exists(places.support) && exists(places.caches), "… and nothing was deleted")
        }

        // Ending what runs from Nightforge's folder: its programs and its quit script, nothing else. The quit script
        // is found by the pid it wrote beside itself – no ps.
        do {
            let scenario = fixture(root.appendingPathComponent("stop", isDirectory: true))
            let support = scenario.places.support
            let inside = standIn(support.appendingPathComponent("Components/winecx/bin/wineserver"))
            let outside = standIn(root.appendingPathComponent("stop/elsewhere/other-program"))
            let script = support.appendingPathComponent("steam-shutdown.sh")
            let elsewhere = root.appendingPathComponent("stop/elsewhere/steam-shutdown.sh")
            for file in [script, elsewhere] { write(file, "#!/bin/bash\nwhile true; do sleep 1; done\n") }
            func bash(_ file: URL) -> Process {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [file.path, "a", "b"]
                try? process.run()
                return process
            }
            let quitScript = bash(script), otherScript = bash(elsewhere)
            usleep(300_000)
            write(support.appendingPathComponent("steam-shutdown.pid"), "\(quitScript.processIdentifier)\n")
            check(inside != nil && outside != nil, "the stand-in programs started")
            if let inside, let outside {
                check(CompleteRemoval.processes(under: support).contains(inside.processIdentifier), "a program run from the folder is found")
                check(!CompleteRemoval.processes(under: support).contains(outside.processIdentifier), "… one run from elsewhere is not")
                await CompleteRemoval.stop(scenario.places, scriptsByCommandLine: false, polite: nil)
                check(gone(inside.processIdentifier), "stop: the program from the folder is ended")
                check(gone(quitScript.processIdentifier), "stop: the quit script named in steam-shutdown.pid is ended")
                check(!exists(support.appendingPathComponent("steam-shutdown.pid")), "… and its pid file is gone")
                check(outside.isRunning, "stop: a program from elsewhere keeps running")
                check(otherScript.isRunning, "stop: a quit script of another folder keeps running")

                // A pid that went to another program since is left alone, and so is a pid file from long ago.
                let pidFile = support.appendingPathComponent("steam-shutdown.pid")
                write(pidFile, "\(outside.processIdentifier)\n")
                CompleteRemoval.endScripts(under: support, byCommandLine: false)
                check(outside.isRunning, "a pid file naming a program that isn't a bash: not killed")
                write(pidFile, "\(otherScript.processIdentifier)\n")
                try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: pidFile.path)
                CompleteRemoval.endScripts(under: support, byCommandLine: false)
                check(otherScript.isRunning, "a pid file written long before that bash began: not killed")
                check(!exists(pidFile), "… the stale file is removed")
                outside.terminate()
            }
            otherScript.terminate()
        }

        // A script of a Nightforge from before the pid file is found by its command line – here in the list
        // of a stand-in ps (a real one lists every process on the Mac).
        do {
            let scenario = fixture(root.appendingPathComponent("oldscript", isDirectory: true))
            let support = scenario.places.support
            let script = support.appendingPathComponent("steam-shutdown.sh")
            write(script, "#!/bin/bash\nwhile true; do sleep 1; done\n")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            try? process.run()
            let bystander = Process()
            bystander.executableURL = URL(fileURLWithPath: "/bin/sleep")
            bystander.arguments = ["60"]
            try? bystander.run()
            // A shell of the player's that has the script's path in its command line (a `tail -f` on it).
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/bash")
            shell.arguments = ["-c", "sleep 60; true"]
            try? shell.run()
            usleep(300_000)
            // The list of a stand-in: the bash with the script's path in its command, and a bystander that only names the script.
            FakeProcesses.install {
                [FakeProcesses.Row(pid: process.processIdentifier, command: "/bin/bash \(script.path)"),
                 FakeProcesses.Row(pid: bystander.processIdentifier, command: "/bin/sleep 60 \(script.path)"),
                 FakeProcesses.Row(pid: shell.processIdentifier, command: "/bin/bash -c tail -f \(script.path)")]
            }
            CompleteRemoval.endScripts(under: support)
            check(gone(process.processIdentifier), "a quit script without a pid file is found by its command line")
            check(bystander.isRunning, "… a program that only names the script is not a bash, and stays")
            check(shell.isRunning, "… nor is a bash that only names it (as Migration's pkill -f once hit)")
            bystander.terminate()
            shell.terminate()
            FakeProcesses.installEmpty()
        }

        // The polite way is given its time and no more.
        do {
            let scenario = fixture(root.appendingPathComponent("polite", isDirectory: true))
            let start = Date()
            await CompleteRemoval.stop(scenario.places, politeFor: 0.3, scriptsByCommandLine: false,
                                       polite: { try? await Task.sleep(for: .seconds(30)) })
            check(Date().timeIntervalSince(start) < 5, "a polite shutdown that takes forever is not waited for")
        }

        quit()
        print(failures == 0 ? "✓ CompleteRemoval" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// Quitting always works: with a sheet open ⌘Q did nothing and `osascript … quit` got -128
    /// (27./28.10.); only a removal under way makes it wait, as that quits by itself.
    static func quit() {
        check(Quit.answer(removing: false) == .quit, "a sheet or not: it quits")
        check(Quit.answer(removing: true) == .wait, "removing itself: it waits, the removal quits by itself")
        // Logging out with Settings open (review M7): the sheets closed, it quits right in the Apple Event,
        // as AppKit does, and answers it only then – no "yes" first and the quit a second later.
        check(!Quit.waits(panelWaiting: false, sheetsLeft: false), "the sheets closed, no panel: it quits at once")
        check(Quit.waits(panelWaiting: true, sheetsLeft: false), "a panel's loop ends after the event: a moment's wait")
        check(Quit.waits(panelWaiting: false, sheetsLeft: true), "a sheet still closing: a moment's wait")
        MainActor.assumeIsolated {
            check(!CompleteRemoval.isRunning, "no removal under way to begin with")
        }

        // The sheets to end first, a sheet's own before it: Settings over the window, the removal's
        // question over Settings; a game's options over another window.
        struct Window: Equatable { let name: String }
        let main = Window(name: "Nightforge"), settings = Window(name: "Settings"), removal = Window(name: "Remove?")
        let other = Window(name: "Other"), options = Window(name: "Options"), plain = Window(name: "Plain")
        let sheets = ["Nightforge": settings, "Settings": removal, "Other": options]
        func order(_ windows: [Window]) -> [String] {
            Quit.closingOrder(windows, sheet: { sheets[$0.name] }).map { "\($0.0.name)>\($0.1.name)" }
        }
        // AppKit lists sheets among the windows too, in any order.
        check(order([removal, main, settings, plain, other, options]) == ["Settings>Remove?", "Nightforge>Settings", "Other>Options"],
              "innermost first, each once, a window without a sheet left alone: \(order([removal, main, settings, plain, other, options]))")
        check(order([plain]).isEmpty, "no sheet open: nothing to end")
        check(order([]).isEmpty, "no windows: nothing")
        let loop = ["A": Window(name: "B"), "B": Window(name: "A")]
        check(Quit.closingOrder([Window(name: "A"), Window(name: "B")], sheet: { loop[$0.name] }).count <= 2,
              "a sheet listed as its own window's parent can't make it go round forever")
    }
}
