// Checks the automatic engine rollback (roadmap 3.3) with fake engines and folders:
// tests/EngineRollbackTest/run.sh (runs in an empty home of its own)
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

    /// A build of winecx `engine` with Nightforge's graphics package `graphics` and DXVK `dxvk`.
    static func build(_ engine: String, _ graphics: String, dxvk: String = "1.10") -> EngineBuild {
        EngineBuild(engine: component("winecx", engine, .engine),
                    graphics: [component("graphics", graphics), component("dxvk-macos", dxvk)],
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
    }

    /// What `Engine.ensureEngine` does for an update to `next`: the build so far is held back if a
    /// game needs it, the new parts are installed (the engine folder gets the new graphics), older
    /// versions are removed, and the new build settles.
    static func update(_ rollback: EngineRollback, to next: EngineBuild, seed: [GameID: String] = [:],
                       inUse: (URL) -> Bool = { _ in false }, now: Date = Date()) {
        rollback.holdBack(before: next, copying: [Engine.graphicsID, Engine.upstreamGraphicsID, Engine.dxvkID], isIntact: { current, folder in
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
        let suite = UserDefaults(suiteName: "nightforge.engine-rollback-test-\(UUID().uuidString)")!
        let ladder = [LaunchAttempt(graphics: .dxmt, arguments: ["-dx11"]), LaunchAttempt(graphics: .dxvk, arguments: ["-dx11"])]
        let state = #"{"ladder":["dxmt -dx11","dxvk -dx11"],"index":1,"confirmed":true}"#
        suite.set(Data(state.utf8), forKey: "launchHealth.steam.42")
        suite.set(Data(#"{"ladder":["dxmt"],"index":0,"confirmed":false}"#.utf8), forKey: "launchHealth.steam.43")
        suite.set(Data(state.utf8), forKey: "launchHealth.epic.Sugar")
        // The copy under the bare app ID GameIDMigration left for older builds doesn't count twice.
        suite.set(Data(#"{"ladder":["dxmt"],"index":0,"confirmed":true}"#.utf8), forKey: "launchHealth.42")
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
        try? FileManager.default.removeItem(at: older)

        // MARK: The prefix follows the build a game starts with
        await prefixSwitch()
        finish()
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
