// Checks the automatic engine rollback (roadmap 3.3) with fake engines and folders:
// tests/EngineRollbackTest/run.sh (runs in an empty home of its own; --without-processes leaves out
// the part that reads the process list)
import Foundation

@main
struct EngineRollbackTest {
    static var failures = 0
    static let fm = FileManager.default

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func write(_ text: String, _ url: URL, executable: Bool = false) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        if executable { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    static func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    static func component(_ id: String, _ version: String, _ kind: Component.Kind = .graphics) -> Component {
        Component(id: id, kind: kind, version: version, url: URL(string: "https://example.com/\(id).tar.gz")!,
                  sha256: "", size: 0, license: "", source: URL(string: "https://example.com")!)
    }

    /// A build of winecx `engine` with Nightforge's graphics package `graphics` and DXVK `dxvk`;
    /// `kosmicKrisp`: upstream DXVK of that version and KosmicKrisp come along.
    static func build(_ engine: String, _ graphics: String, dxvk: String = "1.10", kosmicKrisp upstream: String? = nil) -> EngineBuild {
        EngineBuild(engine: component("winecx", engine, .engine),
                    graphics: [component("graphics", graphics), component("dxvk-macos", dxvk)]
                        + (upstream.map { [component("dxvk", $0), component("kosmickrisp", "27.0.0")] } ?? []),
                    stamp: "graphics \(graphics) engine-match false moltenvk engine d3dmetal - gamepad -")
    }

    /// The folder of one part of a build as an update installs it: a winecx-style engine (fake wine
    /// that does nothing, the plist that makes it D3DMetal-capable, the stamp of its graphics), the
    /// graphics package with a d3d11.dll naming its version, DXVK with a d3d9.dll.
    static func install(_ build: EngineBuild, root: URL) {
        let engine = root.appendingPathComponent("winecx/\(build.engineVersion)/Libraries")
        for tool in ["wine", "wineserver"] { write("#!/bin/sh\nexit 0\n", engine.appendingPathComponent("Wine/bin/\(tool)"), executable: true) }
        write("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>gptkCapable</key><true/></dict></plist>
            """, engine.appendingPathComponent("WhiskyWineVersion.plist"))
        try? fm.createDirectory(at: engine.appendingPathComponent("Wine/lib/wine/x86_64-windows"), withIntermediateDirectories: true)
        write(build.stamp, engine.appendingPathComponent("Wine/lib/wine/.nightforge-graphics"))
        if let graphics = build.version(of: "graphics") {
            write("dxmt \(graphics)", root.appendingPathComponent("graphics/\(graphics)/v0.80/x86_64-windows/d3d11.dll"))
        }
        if let dxvk = build.version(of: "dxvk-macos") {
            write("dxvk \(dxvk)", root.appendingPathComponent("dxvk-macos/\(dxvk)/x64/d3d9.dll"))
        }
        if let upstream = build.version(of: "dxvk") {
            write("dxvk \(upstream)", root.appendingPathComponent("dxvk/\(upstream)/dxvk-\(upstream)/x64/d3d9.dll"))
        }
    }

    /// What `Engine.ensureEngine` does for an update to `next`: the build so far is held back if a
    /// game needs it, the new parts are installed (the engine folder gets the new graphics), older
    /// versions are removed, and the new build settles.
    static func update(_ rollback: EngineRollback, to next: EngineBuild, seed: [GameID: String] = [:],
                       inUse: (URL) -> Bool = { _ in false }, now: Date = Date()) {
        rollback.holdBack(before: next, copying: [Engine.graphicsID, Engine.upstreamGraphicsID, Engine.dxvkID, Engine.dxvkUpstreamID],
                          isIntact: { current, folder in
            Engine.wineBinary(in: folder).map { read(Engine.graphicsStampFile(wine: $0)) == current.stamp } ?? false
        }, now: now)
        install(next, root: rollback.root)
        for part in next.parts.map(EngineBuild.split) {
            for version in (try? fm.contentsOfDirectory(atPath: rollback.root.appendingPathComponent(part.id).path)) ?? []
            where version != part.version {
                try? fm.removeItem(at: rollback.root.appendingPathComponent("\(part.id)/\(version)"))
            }
        }
        rollback.settle(next, seed: seed, inUse: inUse, now: now)
    }

    /// Mirrors the start loop in `LibraryModel.launch`: the game starts with the build held back for
    /// it, else the newest; a start with a new build or way is watched; one that ends at once may
    /// roll back and start again. Returns the build it ended up running on (nil: it didn't start).
    static func play(_ rollback: EngineRollback, _ game: GameID, way: String = "dxmt",
                     broken: Set<String>) -> (ranOn: EngineBuild?, rolledBack: Bool) {
        var rolledBack = false
        for _ in 0..<4 {
            guard let current = rollback.history().current else { return (nil, rolledBack) }
            let build = rollback.pinnedBuild(game)?.build ?? current
            let watched = rollback.needsWatch(game, build: build, way: way)
            if !broken.contains(build.id) {
                if watched { rollback.recordGood(game, build: build, way: way) }
                return (build, rolledBack)
            }
            guard watched, case .rollBack = rollback.afterFailedStart(game, build: build, way: way) else { return (nil, rolledBack) }
            rolledBack = true
        }
        return (nil, rolledBack)
    }

    static func main() async {
        TestDefaults.useWorkFolder()
        UserDefaults.standard.set("english", forKey: AppLanguage.storageKey)
        let work = fm.temporaryDirectory.appendingPathComponent("ert-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }

        let a = build("4.7.3", "11.18-dxmt0.80-13")
        let b = build("4.7.3", "11.18-dxmt0.80-17")  // a graphics update: same engine folder
        let c = build("4.7.4", "11.18-dxmt0.80-17")  // an engine update: a new engine folder
        let d = build("4.7.5", "11.18-dxmt0.80-18")
        let game = GameID.steam(100), other = GameID.steam(200), rare = GameID.steam(300)

        // MARK: Builds
        check(a.id == "winecx@4.7.3 dxvk-macos@1.10 graphics@11.18-dxmt0.80-13", "a build is named by all its parts: \(a.id)")
        check(a.engineID == "winecx" && a.engineVersion == "4.7.3" && a.version(of: "graphics") == "11.18-dxmt0.80-13",
              "a build knows its parts' versions")
        check(a != b && b != c, "a new graphics or engine version is a new build")

        // MARK: First setup: what already runs well counts as running well on it
        let root = work.appendingPathComponent("Components", isDirectory: true)
        let rollback = EngineRollback(root: root)
        install(a, root: root)
        rollback.settle(a, seed: [game: "dxmt", other: "dxvk"])
        check(rollback.history().current == a, "the first setup records its build")
        check(!rollback.needsWatch(game, build: a, way: "dxmt"), "a confirmed game isn't watched again on the build it was seeded with")
        check(rollback.needsWatch(rare, build: a, way: "dxmt"), "a game never watched is watched once")
        check(play(rollback, game, broken: []).ranOn == a, "it plays on the newest build")
        check(play(rollback, rare, broken: []).ranOn == a, "and the never-watched game is good on it from now on")

        // MARK: A broken graphics update
        update(rollback, to: b)
        var history = rollback.history()
        check(history.current == b && history.held.count == 1 && history.held.first?.build == a,
              "the build games ran well on is held back when the update comes")
        guard let heldA = history.held.first else { return finish() }
        let heldEngine = rollback.folder(of: heldA, part: "winecx")
        check(Engine.wineBinary(in: heldEngine) != nil, "the held copy has its own engine")
        check(read(heldEngine.appendingPathComponent("Libraries/Wine/lib/wine/.nightforge-graphics")) == a.stamp
              && read(root.appendingPathComponent("winecx/4.7.3/Libraries/Wine/lib/wine/.nightforge-graphics")) == b.stamp,
              "the copy keeps the graphics the engine had; the engine folder itself has the new ones")
        check(read(rollback.folder(of: heldA, part: "graphics").appendingPathComponent("v0.80/x86_64-windows/d3d11.dll")) == "dxmt 11.18-dxmt0.80-13"
              && !fm.fileExists(atPath: root.appendingPathComponent("graphics/11.18-dxmt0.80-13").path),
              "the old graphics package stays in the copy after the update removed it")
        check(fm.fileExists(atPath: rollback.folder(of: heldA, part: "dxvk-macos").path), "DXVK, which the prefix takes from, is in the copy too")

        // LaunchHealth's ladder and the game's own options must come through a rollback untouched.
        let attempts = [LaunchAttempt(graphics: .dxmt), LaunchAttempt(graphics: .dxvk)]
        LaunchHealth.reset(game)
        LaunchHealth.confirm(game, attempts)
        var options = GameOptions()
        options.frameLimit = 60
        GameOptionsStore.save(options, for: game)
        let ladderBefore = LaunchHealth.peek(game, attempts)

        let broken = play(rollback, game, broken: [b.id])
        check(broken.ranOn == a && broken.rolledBack,
              "a game the new build crashes starts with the held build, without anyone doing anything")
        check(rollback.pinnedBuild(game)?.build == a, "and stays with it")
        check(LaunchHealth.peek(game, attempts)?.index == ladderBefore?.index && LaunchHealth.peek(game, attempts)?.confirmed == true,
              "the graphics ladder isn't moved on: the engine was to blame, not the way")
        check(GameOptionsStore.load(game) == options, "the game's own settings stay as they were")
        let again = play(rollback, game, broken: [b.id])
        check(again.ranOn == a && !again.rolledBack, "the next start goes straight to the held build")
        check(play(rollback, other, way: "dxvk", broken: []).ranOn == b, "other games use the new build")

        // MARK: Not the engine's doing
        check(play(rollback, rare, way: "dxvk", broken: [b.id]).ranOn == nil && rollback.pinnedBuild(rare) == nil,
              "a game started another way than it ran well with is left to the graphics ladder")
        let fresh = GameID.steam(400)
        check(play(rollback, fresh, broken: [b.id]).ranOn == nil && rollback.pinnedBuild(fresh) == nil,
              "a game that never ran well has nothing to roll back to")

        // MARK: Try the newest now
        rollback.tryNewest(game)
        check(rollback.pinnedBuild(game) == nil, "“Try the newest now” takes the pin away")
        let retry = play(rollback, game, broken: [b.id])
        check(retry.ranOn == a && retry.rolledBack, "if the newest crashes it again, Nightforge switches back by itself")
        rollback.tryNewest(game)
        check(play(rollback, game, broken: []).ranOn == b && rollback.pinnedBuild(game) == nil,
              "if the newest works after all, the game stays on it")
        let pinAgain = play(rollback, game, broken: [b.id])
        check(pinAgain.ranOn == nil && !pinAgain.rolledBack, "once good on the newest, the held build is no fallback any more")

        // MARK: The held build fails too
        let twice = GameID.steam(500)
        rollback.recordGood(twice, build: a, way: "dxmt")
        check(play(rollback, twice, broken: [a.id, b.id]).ranOn == nil, "crashing on both builds: no start")
        check(rollback.pinnedBuild(twice) == nil && rollback.history().lastGood["steam.500"] == nil,
              "the pin goes, and the held build no longer counts as good for it – no rollback loop")

        // MARK: The next update tries the newest again
        rollback.recordGood(twice, build: a, way: "dxmt")
        _ = play(rollback, twice, broken: [b.id])
        check(rollback.pinnedBuild(twice)?.build == a, "pinned before the next update")
        update(rollback, to: c)
        history = rollback.history()
        check(history.pinned.isEmpty, "an engine update ends every pin: the newest gets another try")
        check(Set(history.held.map(\.build.id)) == [a.id, b.id],
              "both older builds stay while games last ran well on them: \(history.held.map(\.build.id))")
        check(Engine.wineBinary(in: rollback.folder(of: history.held.first { $0.build == b }!, part: "winecx")) != nil
              && !fm.fileExists(atPath: root.appendingPathComponent("winecx/4.7.3").path),
              "the engine folder of a replaced version goes, its held copy stays")
        check(play(rollback, twice, broken: []).ranOn == c, "the game held back before plays on the new engine if it can")

        // MARK: Tidying up
        check(play(rollback, other, way: "dxvk", broken: []).ranOn == c, "the last games that needed the graphics update move on")
        check(play(rollback, game, broken: []).ranOn == c, "…")
        _ = play(rollback, rare, broken: [])
        rollback.settle(c)
        history = rollback.history()
        check(history.held.isEmpty, "a held build no game needs goes: \(history.held.map(\.build.id))")
        check(((try? fm.contentsOfDirectory(atPath: rollback.heldRoot.path)) ?? []).isEmpty, "and its folder with it")

        // In use: a Steam session still running from a held copy keeps it until it ends.
        rollback.recordGood(rare, build: c, way: "dxmt")
        update(rollback, to: d)
        check(rollback.history().held.map(\.build) == [c], "the build before is held on update to d")
        for app in [game, other, rare, twice] { rollback.recordGood(app, build: d, way: "dxmt") }
        let cFolder = rollback.folder(of: rollback.history().held[0], part: "winecx")
        rollback.settle(d, inUse: { $0 == cFolder })
        check(rollback.history().held.count == 1 && fm.fileExists(atPath: cFolder.path), "a copy something runs from stays")
        rollback.settle(d)
        check(rollback.history().held.isEmpty && !fm.fileExists(atPath: cFolder.path), "and goes once nothing runs from it")

        // A copy cut off halfway and a folder no history names are cleared away.
        write("x", rollback.heldRoot.appendingPathComponent(".staging-1234/winecx/file"))
        write("x", rollback.heldRoot.appendingPathComponent("winecx-0.0-orphan/winecx/file"))
        rollback.settle(d)
        check(((try? fm.contentsOfDirectory(atPath: rollback.heldRoot.path)) ?? []).isEmpty, "leftover copies are removed")

        // Nothing is held when no game ran well on the build, or when its folder has changed already.
        rollback.recordGood(game, build: d, way: "dxmt")
        let e = build("4.7.5", "11.18-dxmt0.80-19")
        write("something else", root.appendingPathComponent("winecx/4.7.5/Libraries/Wine/lib/wine/.nightforge-graphics"))
        update(rollback, to: e)
        check(rollback.history().held.isEmpty, "an engine folder that no longer holds its build isn't copied")
        update(rollback, to: build("4.7.5", "11.18-dxmt0.80-20"))
        check(rollback.history().held.isEmpty, "a build no game ran well on isn't kept")

        // MARK: Limits: two held builds at most, 30 days unless pinned
        let now = Date()
        func held(_ build: EngineBuild, daysAgo: Double) -> HeldBuild {
            HeldBuild(build: build, folder: build.id, setUp: now.addingTimeInterval(-90 * 86_400),
                      heldSince: now.addingTimeInterval(-daysAgo * 86_400))
        }
        var many = EngineHistory(current: d, currentSetUp: now, held: [held(a, daysAgo: 20), held(b, daysAgo: 10), held(c, daysAgo: 2)])
        many.lastGood = ["1": .init(build: a.id, way: "dxmt"), "2": .init(build: b.id, way: "dxmt"), "3": .init(build: c.id, way: "dxmt")]
        check(EngineRollback.unneeded(many, now: now).map(\.build) == [a], "past two held builds the oldest goes")
        many.pinned = ["1": a.id]
        check(EngineRollback.unneeded(many, now: now).map(\.build) == [b], "a pinned build is kept before newer ones")
        many.pinned = [:]
        many.held = [held(a, daysAgo: 40), held(c, daysAgo: 2)]
        check(EngineRollback.unneeded(many, now: now).map(\.build) == [a], "a build replaced over 30 days ago goes")
        many.pinned = ["1": a.id]
        check(EngineRollback.unneeded(many, now: now).isEmpty, "unless a game is pinned to it")
        many.held = [held(d, daysAgo: 1)]
        many.lastGood = ["1": .init(build: d.id, way: "dxmt")]
        check(EngineRollback.unneeded(many, now: now).map(\.build) == [d], "a held build the list went back to is the newest again, not held")

        // MARK: Labels
        check(EngineRollback.label(c, setUp: now, other: d) == "4.7.4", "another engine version is named by its version")
        let october = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 20, hour: 12).date!
        check(EngineRollback.label(a, setUp: october, other: b) == "4.7.3 · \(EngineRollback.day(october))"
              && EngineRollback.day(october).contains("20") && EngineRollback.day(october).contains("Oct"),
              "two builds of the same engine are told apart by the day: \(EngineRollback.label(a, setUp: october, other: b))")

        // MARK: Seeds from what already runs
        let suite = TestDefaults.suite("seeds")
        let ladder = [LaunchAttempt(graphics: .dxmt, arguments: ["-dx11"]), LaunchAttempt(graphics: .dxvk, arguments: ["-dx11"])]
        let state = #"{"ladder":["dxmt -dx11","dxvk -dx11"],"index":1,"confirmed":true,"proof":2}"#
        suite.set(Data(state.utf8), forKey: "launchHealth.steam.42")
        suite.set(Data(#"{"ladder":["dxmt"],"index":0,"confirmed":false}"#.utf8), forKey: "launchHealth.steam.43")
        suite.set(Data(state.utf8), forKey: "launchHealth.epic.Sugar")
        // Confirmed before frames counted (no proof): an error box ran 30 s too – it doesn't count.
        suite.set(Data(#"{"ladder":["dxvk","wined3d"],"confirmed":true,"index":0}"#.utf8), forKey: "launchHealth.gog.1816059595")
        // The copy under the bare app ID GameIDMigration left for older builds doesn't count twice.
        suite.set(Data(#"{"ladder":["dxmt"],"index":0,"confirmed":true,"proof":2}"#.utf8), forKey: "launchHealth.42")
        check(LaunchHealth.confirmedWays(suite) == [.steam(42): ladder[1].id, .epic("Sugar"): ladder[1].id],
              "confirmed ways are read from LaunchHealth, by store and ID: \(LaunchHealth.confirmedWays(suite))")

        // A history from before store keys: "570" reads as "steam.570".
        let older = FileManager.default.temporaryDirectory.appendingPathComponent("rollback-keys-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try? Data(#"{"held":[],"lastGood":{"570":{"build":"x","way":"dxmt"}},"pinned":{"570":"x"}}"#.utf8)
            .write(to: older.appendingPathComponent("engine-history.json"))
        let keys = EngineRollback(root: older).history()
        check(keys.lastGood["steam.570"] == .init(build: "x", way: "dxmt") && keys.pinned["steam.570"] == "x" && keys.lastGood["570"] == nil,
              "a history written with app IDs reads with store keys")
        // Both, after a build from before 0.2 ran again: the entry under the store key is the newer one,
        // whatever order the file has them in; keys that aren't games stay as they were.
        for json in [#"{"held":[],"lastGood":{"570":{"build":"old","way":"dxvk"},"steam.570":{"build":"new","way":"dxmt"},"0":{"build":"z","way":"w"}},"pinned":{"steam.570":"new","570":"old"}}"#,
                     #"{"held":[],"lastGood":{"steam.570":{"build":"new","way":"dxmt"},"0":{"build":"z","way":"w"},"570":{"build":"old","way":"dxvk"}},"pinned":{"570":"old","steam.570":"new"}}"#] {
            try? Data(json.utf8).write(to: older.appendingPathComponent("engine-history.json"))
            let both = EngineRollback(root: older).history()
            check(both.lastGood["steam.570"] == .init(build: "new", way: "dxmt") && both.pinned["steam.570"] == "new",
                  "the store key's entry wins over the app ID's: \(both.lastGood)")
            check(both.lastGood.count == 2 && both.lastGood["0"]?.build == "z", "nothing else goes")
        }
        // Rewritten with store keys at the next change, the learned ways kept.
        EngineRollback(root: older).recordGood(.epic("Sugar"), build: build("4.7", "a"), way: "dxmt")
        let rewritten = read(older.appendingPathComponent("engine-history.json")) ?? ""
        check(rewritten.contains("\"steam.570\"") && !rewritten.contains("\"570\"") && rewritten.contains("\"epic.Sugar\""),
              "written back under store keys")
        try? FileManager.default.removeItem(at: older)

        // MARK: Steam itself doesn't come up on a new engine
        steamStartCheck(work)
        steamItself(work)

        // MARK: The day a build was set up
        setUpDays(work)

        // MARK: The prefix follows the build a game starts with
        // It reads the process list (Engine.sessionWine): left out with --without-processes, for a
        // Mac whose process list hangs.
        if CommandLine.arguments.contains("--without-processes") {
            print("- prefix switch left out (--without-processes)")
        } else {
            await prefixSwitch()
        }
        finish()
    }

    /// The parts of `build` installed under `root` as if downloaded on `date`: their markers
    /// (.sha256, as ComponentStore writes them) and the engine's graphics stamp carry that date.
    static func date(_ build: EngineBuild, root: URL, _ date: Date) {
        for part in build.parts.map(EngineBuild.split) {
            let folder = root.appendingPathComponent("\(part.id)/\(part.version)", isDirectory: true)
            guard fm.fileExists(atPath: folder.path) else { continue }
            let marker = folder.appendingPathComponent(".sha256")
            write("0000", marker)
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: marker.path)
        }
        let stamp = root.appendingPathComponent("winecx/\(build.engineVersion)/Libraries/Wine/lib/wine/.nightforge-graphics")
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: stamp.path)
    }

    /// The day the player sees for a build ("the previous engine from 20 Oct") is the day it came
    /// together – from its folders – not the day Nightforge with 3.3 first saw it.
    static func setUpDays(_ work: URL) {
        let root = work.appendingPathComponent("setup-days", isDirectory: true)
        let rollback = EngineRollback(root: root)
        let a = build("4.7.3", "11.18-dxmt0.80-17"), b = build("4.7.4", "11.18-dxmt0.80-18")
        let day: TimeInterval = 86_400
        let firstRun = Date().addingTimeInterval(-5 * day)       // Nightforge with 3.3 first ran
        let arrived = firstRun.addingTimeInterval(-10 * day)      // engine a had come ten days before
        func same(_ x: Date?, _ y: Date) -> Bool { x.map { abs($0.timeIntervalSince(y)) < 1 } ?? false }

        install(a, root: root)
        date(a, root: root, arrived)
        check(same(rollback.setUpDate(of: a), arrived), "the folders say when a came")
        rollback.settle(a, now: firstRun)
        check(same(rollback.history().currentSetUp, arrived), "the first time: the day it came, not the day 3.3 first ran")
        rollback.recordGood(.steam(100), build: a, way: "dxmt")
        update(rollback, to: b, now: firstRun.addingTimeInterval(day))
        guard let held = rollback.history().held.first(where: { $0.build == a }) else { return check(false, "a is held back") }
        check(same(held.setUp, arrived), "held back with that day: \(EngineRollback.day(held.setUp))")
        check(same(rollback.setUpDate(of: a, held: held), arrived), "the copy still knows it")
        check(same(rollback.history().currentSetUp, firstRun.addingTimeInterval(day)), "b: the day it came, as before")

        // A history from that first run kept its day: the next start puts the right one in.
        var wrong = rollback.history()
        wrong.held[0].setUp = firstRun
        wrong.currentSetUp = firstRun.addingTimeInterval(2 * day)
        write(String(decoding: (try? JSONEncoder().encode(wrong)) ?? Data(), as: UTF8.self), root.appendingPathComponent("engine-history.json"))
        date(b, root: root, firstRun.addingTimeInterval(day))
        rollback.settle(b, now: Date())
        check(same(rollback.history().held.first?.setUp, arrived), "a held build's day put right from its copy")
        check(same(rollback.history().currentSetUp, firstRun.addingTimeInterval(day)), "the current build's too")
        rollback.settle(b, now: Date())
        check(same(rollback.history().held.first?.setUp, arrived), "and it stays")

        // What the folders don't say isn't guessed.
        let c = build("4.7.5", "11.18-dxmt0.80-19")
        let other = EngineRollback(root: work.appendingPathComponent("setup-days-2", isDirectory: true))
        install(c, root: other.root)
        let stamp = other.root.appendingPathComponent("winecx/4.7.5/Libraries/Wine/lib/wine/.nightforge-graphics")
        write("graphics something else", stamp)
        try? fm.setAttributes([.modificationDate: arrived], ofItemAtPath: stamp.path)
        check(other.setUpDate(of: c) == nil, "no markers, and a stamp of another build: no day from the folders")
        other.settle(c, now: firstRun)
        check(same(other.history().currentSetUp, firstRun), "then the day it was first seen")
    }

    /// When a Steam start counts as not come up (SteamStartCheck): never while Steam updates itself
    /// or within its first 90 s, and only log lines written since the start are signs of life.
    static func steamStartCheck(_ work: URL) {
        var quiet = SteamStartCheck.Signs()
        quiet.sinceStart = 200
        quiet.quietFor = 120
        check(SteamStartCheck.judge(quiet) == .failed, "200 s after the start, two minutes quiet, no update: not come up")
        for (change, name) in [({ (s: inout SteamStartCheck.Signs) in s.signedIn = true }, "signed in"),
                               ({ (s: inout SteamStartCheck.Signs) in s.sessionReplaced = true }, "signed out by Steam for Mac"),
                               ({ (s: inout SteamStartCheck.Signs) in s.askingForAccount = true }, "asking for the account"),
                               ({ (s: inout SteamStartCheck.Signs) in s.startupFinished = true }, "done starting")] {
            var signs = quiet
            change(&signs)
            check(SteamStartCheck.judge(signs) == .cameUp, "\(name): it came up")
        }
        for state in [SteamBootstrap.downloading, .installing, .updated] {
            var signs = quiet
            signs.bootstrap = state
            check(SteamStartCheck.judge(signs) == .undecided, "Steam updating itself (\(state)) is never a failure")
        }
        var early = quiet
        early.sinceStart = 80
        early.running = false
        check(SteamStartCheck.judge(early) == .undecided, "within its first 90 s: undecided, even without its process")
        var busy = quiet
        busy.quietFor = 10
        check(SteamStartCheck.judge(busy) == .undecided, "still writing its logs: only slow")
        busy.running = false
        check(SteamStartCheck.judge(busy) == .failed, "its process gone: not come up")
        // No process list (ps doesn't answer): not known, so not a failure – whatever the logs say.
        var unknown = quiet
        unknown.running = nil
        check(SteamStartCheck.judge(unknown) == .undecided, "no process list, logs quiet: undecided, not come up")
        unknown.signedIn = true
        check(SteamStartCheck.judge(unknown) == .cameUp, "no process list, signed in: it came up all the same")

        // From the logs: the last session's "Logged On" doesn't count for a start that wrote nothing.
        let steam = work.appendingPathComponent("steam-check", isDirectory: true)
        let logs = steam.appendingPathComponent("logs", isDirectory: true)
        let start = Date()
        let before = start.addingTimeInterval(-600)
        let connection = logs.appendingPathComponent("connection_log.txt")
        write("[2026-11-03 00:50:00] Client version: 1761609000\n[2026-11-03 00:50:20] [Logged On, 0,0] Logged on\n", connection)
        write("[2026-11-03 00:50:00] Client version: 1761609000\n[2026-11-03 00:50:20] System startup time: 20 seconds\n",
              logs.appendingPathComponent("console_log.txt"))
        for file in [connection, logs.appendingPathComponent("console_log.txt")] {
            try? fm.setAttributes([.modificationDate: before], ofItemAtPath: file.path)
        }
        var signs = SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: start.addingTimeInterval(200))
        check(!signs.signedIn && !signs.startupFinished, "the last session's lines aren't this start's")
        check(signs.sinceStart == 200 && signs.quietFor == 200, "nothing written since the start: quiet since then")
        check(SteamStartCheck.judge(signs) == .failed, "and so not come up")
        write("[2026-11-03 01:00:00] Startup - updater built Oct 22 2026 00:15:00\n[2026-11-03 01:00:01] Downloading manifest: client\n",
              logs.appendingPathComponent("bootstrap_log.txt"))
        signs = SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: Date().addingTimeInterval(200))
        check(signs.bootstrap == .downloading && SteamStartCheck.judge(signs) == .undecided, "looking for its update: undecided")
        write("[2026-11-03 01:00:05] Client version: 1761609000\n[2026-11-03 01:00:30] [Logged On, 0,0] Logged on\n", connection)
        signs = SteamStartCheck.signs(steamRoot: steam, start: start, running: true, now: Date().addingTimeInterval(200))
        check(signs.signedIn && SteamStartCheck.judge(signs) == .cameUp, "signed in since the start: came up")
    }

    /// Steam that doesn't come up on the newest build twice goes back to the held build it ran on,
    /// and its games with it; Epic's and GOG's don't need Steam and stay on the newest.
    static func steamItself(_ work: URL) {
        let root = work.appendingPathComponent("steam-rollback", isDirectory: true)
        let rollback = EngineRollback(root: root)
        let a = build("4.7.3", "11.18-dxmt0.80-17")
        let b = build("4.7.4", "11.18-dxmt0.80-18")
        let c = build("4.7.5", "11.18-dxmt0.80-19")
        let steamGame = GameID.steam(570), epicGame = GameID.epic("Sugar")
        let day: TimeInterval = 86_400
        let t0 = Date().addingTimeInterval(-10 * day)
        install(a, root: root)
        rollback.settle(a, now: t0)
        rollback.recordGood(steamGame, build: a, way: "dxmt")
        update(rollback, to: b, now: t0.addingTimeInterval(day))
        guard let heldA = rollback.history().held.first(where: { $0.build == a }) else {
            return check(false, "the build Steam's games ran on is held back")
        }

        check(rollback.build(running: Engine.wineBinary(in: root.appendingPathComponent("winecx/4.7.4"))!) == b,
              "the newest build is known by its engine")
        check(rollback.build(running: Engine.wineBinary(in: rollback.folder(of: heldA, part: "winecx"))!) == a,
              "a held one by its copy")
        check(rollback.build(running: URL(fileURLWithPath: "/somewhere/else/bin/wine")) == nil, "another wine: none")

        check(rollback.afterFailedSteamStart(b) == .none, "Steam didn't come up once: only counted (a slow Steam)")
        check(rollback.steamPinnedBuild() == nil && rollback.pinnedBuild(steamGame) == nil, "nothing changes yet")
        check(rollback.afterFailedSteamStart(b) == .rollBack(heldA), "twice in a row: back to the build Steam's games ran on")
        check(rollback.steamPinnedBuild() == heldA, "Steam starts with it")
        check(rollback.pinnedBuild(steamGame) == heldA && rollback.pinnedForSteam(steamGame), "Steam's games with it, because of Steam")
        check(rollback.pinnedBuild(.steam(730)) == heldA, "every Steam game, also one never played")
        check(rollback.pinnedBuild(epicGame) == nil && !rollback.pinnedForSteam(epicGame), "Epic's games need no Steam: newest")
        check(rollback.afterFailedSteamStart(b) == .none, "further failures on the newest change nothing")
        check(EngineRollback.unneeded(rollback.history(), now: t0.addingTimeInterval(60 * day)).isEmpty,
              "the copy Steam starts with stays past the 30 days")

        // Not up on the held build either: not the engine's doing.
        check(rollback.afterFailedSteamStart(a) == .none, "once on the held build: counted")
        check(rollback.afterFailedSteamStart(a) == .heldFailed && rollback.steamPinnedBuild() == nil,
              "twice: the pin goes, Steam starts with the newest")
        check(rollback.afterFailedSteamStart(b) == .none && rollback.afterFailedSteamStart(b) == .none,
              "and the newest isn't rolled back from again before the next update")

        // A build Steam came up on once isn't rolled back from: a later hang is Steam's own.
        update(rollback, to: c, now: t0.addingTimeInterval(2 * day))
        rollback.recordSteamStarted(c)
        check(rollback.afterFailedSteamStart(c) == .none && rollback.afterFailedSteamStart(c) == .none
              && rollback.steamPinnedBuild() == nil, "Steam came up on it before: no rollback")

        // A failure, then Steam comes up: the count starts over.
        let root2 = work.appendingPathComponent("steam-rollback-2", isDirectory: true)
        let second = EngineRollback(root: root2)
        install(a, root: root2)
        second.settle(a, now: t0)
        second.recordSteamStarted(a)
        second.recordGood(epicGame, build: a, way: "dxmt")
        update(second, to: b, now: t0.addingTimeInterval(day))
        _ = second.afterFailedSteamStart(b)
        check(second.history().steamFailures?[b.id] == 1, "one failure counted")
        second.recordSteamStarted(b)
        check(second.history().steamFailures?[b.id] == nil && second.afterFailedSteamStart(b) == .none,
              "Steam came up after all: the count is gone, and so is the rollback for this build")

        // Held only for an Epic game, the build Steam came up on still serves Steam.
        let root3 = work.appendingPathComponent("steam-rollback-3", isDirectory: true)
        let third = EngineRollback(root: root3)
        install(a, root: root3)
        third.settle(a, now: t0)
        third.recordSteamStarted(a)
        third.recordGood(epicGame, build: a, way: "dxmt")
        update(third, to: b, now: t0.addingTimeInterval(day))
        _ = third.afterFailedSteamStart(b)
        guard case .rollBack(let held) = third.afterFailedSteamStart(b) else { return check(false, "Steam came up on the held build: rolled back") }
        check(held.build == a, "to the build Steam came up on")
        third.tryNewest(steamGame)
        check(third.steamPinnedBuild() == nil && third.history().steamFailures == nil,
              "Try the Newest Now on a Steam game: Steam tries the newest again, counting from zero")
        _ = third.afterFailedSteamStart(b)
        _ = third.afterFailedSteamStart(b)
        check(third.steamPinnedBuild()?.build == a, "and goes back again after two more")
        update(third, to: c, now: t0.addingTimeInterval(2 * day))
        check(third.steamPinnedBuild() == nil && third.history().steamFailures == nil, "the next update: the newest gets another try")

        // No held build Steam ran on: nothing to go back to.
        let root4 = work.appendingPathComponent("steam-rollback-4", isDirectory: true)
        let fourth = EngineRollback(root: root4)
        install(a, root: root4)
        fourth.settle(a, now: t0)
        fourth.recordGood(epicGame, build: a, way: "dxmt")
        update(fourth, to: b, now: t0.addingTimeInterval(day))
        check(fourth.afterFailedSteamStart(b) == .none && fourth.afterFailedSteamStart(b) == .none && fourth.steamPinnedBuild() == nil,
              "a build only Epic's games ran on isn't Steam's way back")

        // A history from before reads, without Steam's fields.
        let root5 = work.appendingPathComponent("steam-rollback-5", isDirectory: true)
        write(#"{"held":[],"lastGood":{},"pinned":{}}"#, root5.appendingPathComponent("engine-history.json"))
        let older = EngineRollback(root: root5).history()
        check(older.steamPinned == nil && older.steamStarted == nil && older.steamFailures == nil, "a history from before reads")
    }

    /// With the real `Engine.engineForStart` and the real (here: empty, temporary) Application
    /// Support folder: a held-back game gets the held graphics DLLs in the prefix, the next game the
    /// newest ones again. No Steam runs here, so there's no session to switch.
    static func prefixSwitch() async {
        let rollback = EngineRollback.shared
        let root = rollback.root
        guard root.path.hasPrefix(fm.temporaryDirectory.resolvingSymlinksInPath().path)
                || !root.path.hasPrefix(NSHomeDirectoryForUser(NSUserName()) ?? "/Users")
        else {
            print("✗ skipped the prefix check: not running in an empty home (use run.sh)")
            failures += 1
            return
        }
        let system32 = Engine.prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        try? fm.createDirectory(at: system32, withIntermediateDirectories: true)

        let a = build("4.7.3", "11.18-dxmt0.80-13")
        let b = build("4.7.3", "11.18-dxmt0.80-17")
        let game = GameID.steam(700), other = GameID.steam(800)
        install(a, root: root)
        rollback.settle(a, seed: [game: "dxmt", other: "dxmt"])
        let gptk = Engine.isGPTKCapable(wine: Engine.wineBinary(in: root.appendingPathComponent("winecx/4.7.3"))!)
        check(gptk, "the fake engine counts as winecx")
        // Before 3.3 the stamp was built the same way: an existing prefix isn't set up again.
        let legacy = "4.7.3 1.10 11.18-dxmt0.80-13 d3dmetal - "
            + Engine.gameEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        check(Engine.prefixStampText(a, gptk: true) == legacy, "the prefix stamp of the newest build is unchanged")

        update(rollback, to: b)
        guard let newest = Engine.wineBinary(in: root.appendingPathComponent("winecx/4.7.3")) else {
            check(false, "the fake engine has a wine")
            return
        }
        _ = play(rollback, game, broken: [b.id])
        check(rollback.pinnedBuild(game)?.build == a, "the game is held back on a")

        var switched = false
        let start = await Engine.engineForStart(game: game, newest: newest) { switched = true }
        check(start.build == a && start.held?.build == a, "a held-back game starts with the held build")
        check(start.wine.path.contains("/.held/"), "with the held copy's wine: \(start.wine.path)")
        check(read(system32.appendingPathComponent("d3d11.dll")) == "dxmt 11.18-dxmt0.80-13",
              "the prefix gets the held build's DXMT")
        check(read(system32.appendingPathComponent("d3d9.dll")) == "dxvk 1.10", "and its DXVK")
        check(read(Engine.prefix.appendingPathComponent(".nightforge-setup")) == Engine.prefixStampText(a, gptk: true),
              "the prefix stamp says so")

        let next = await Engine.engineForStart(game: other, newest: newest) { switched = true }
        check(next.build == b && next.held == nil && next.wine == newest, "another game starts with the newest build")
        check(read(system32.appendingPathComponent("d3d11.dll")) == "dxmt 11.18-dxmt0.80-17", "and the prefix gets the newest DXMT back")
        check(!switched, "without a Steam session there's nothing to stop")

        // MARK: DXVK's Direct3D 9 for KosmicKrisp
        let c = build("4.7.3", "11.18-dxmt0.80-17", kosmicKrisp: "3.1.1")
        check(Engine.prefixStampText(c, gptk: true).contains(" d3d9 3.1.1 "), "upstream DXVK is part of the prefix stamp")
        check(Engine.prefixStampText(c, gptk: false) == Engine.prefixStampText(b, gptk: false), "…on winecx only")
        update(rollback, to: c)
        let third = await Engine.engineForStart(game: GameID.steam(900), newest: newest) { switched = true }
        check(third.build == c, "a game starts with the build that has KosmicKrisp")
        check(read(system32.appendingPathComponent("d3d9.dll")) == "dxvk 3.1.1", "and the prefix's d3d9 is upstream DXVK's")
        check(read(system32.appendingPathComponent("d3d11.dll")) == "dxmt 11.18-dxmt0.80-17", "DirectX 10/11 stays as it was")
    }

    static func finish() {
        if failures == 0 {
            print("✓ Engine rollback")
        } else {
            print("\(failures) failed")
            exit(1)
        }
    }
}
