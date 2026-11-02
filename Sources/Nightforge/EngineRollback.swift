import CryptoKit
import Foundation

/// An engine as Nightforge set it up: the engine component and every graphics build that went into
/// it or into the prefix. A new version of any of them is an engine update.
struct EngineBuild: Codable, Equatable {
    /// "winecx@4.7.3" – the engine component itself.
    var engine: String
    /// The graphics builds, by id: "dxvk-macos@1.10.3-20230507", "graphics@11.18-dxmt0.80-17", …
    var graphics: [String]
    /// What the engine's folder says it holds (`.nightforge-graphics`): a copy is only taken of a
    /// folder that still holds this build.
    var stamp: String

    /// `d3dMetal`: the version of Apple's D3DMetal in it, which isn't always a component (D3DMetalSupply).
    init(engine: Component, graphics: [Component], d3dMetal: String? = nil, stamp: String) {
        self.engine = "\(engine.id)@\(engine.version)"
        self.graphics = (graphics.map { "\($0.id)@\($0.version)" } + (d3dMetal.map { ["\(Engine.d3dMetalID)@\($0)"] } ?? [])).sorted()
        self.stamp = stamp
    }

    var id: String { ([engine] + graphics).joined(separator: " ") }
    var parts: [String] { [engine] + graphics }
    var engineID: String { Self.split(engine).id }
    var engineVersion: String { Self.split(engine).version }

    func version(of id: String) -> String? {
        parts.map(Self.split).first { $0.id == id }?.version
    }

    /// "winecx@4.7.3" → ("winecx", "4.7.3"). Ids never hold an "@" (`Component.isSafeToInstall`).
    static func split(_ part: String) -> (id: String, version: String) {
        let pieces = part.split(separator: "@", maxSplits: 1).map(String.init)
        return (pieces.first ?? part, pieces.count > 1 ? pieces[1] : "")
    }
}

/// An older build kept as a copy for games that last ran well on it.
struct HeldBuild: Codable, Equatable {
    var build: EngineBuild
    /// Its folder in `.held`: one copy per part it needs (the engine, the graphics the prefix takes).
    var folder: String
    /// When it was set up – what the player sees: "the previous engine from 20 Oct".
    var setUp: Date
    /// When a newer build took its place.
    var heldSince: Date
}

/// What Nightforge remembers about engine builds (Components/engine-history.json).
struct EngineHistory: Codable, Equatable {
    /// The build set up now: the newest.
    var current: EngineBuild?
    var currentSetUp: Date?
    var held: [HeldBuild] = []
    /// Per game (`GameID.key`, "steam.570"): the build and way (`LaunchAttempt.id`) it last started well with.
    var lastGood: [String: GoodStart] = [:]
    /// Per game: the held build it starts with, because the newest crashed it.
    var pinned: [String: String] = [:]

    struct GoodStart: Codable, Equatable {
        var build: String
        var way: String
    }
}

extension EngineHistory {
    /// Written before games had store and ID (0.2), games were Steam app IDs ("570"): those read as "steam.570".
    mutating func useGameKeys() {
        func rekeyed<V>(_ entries: [String: V]) -> [String: V] {
            Dictionary(entries.map { (GameID(key: $0.key)?.key ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        lastGood = rekeyed(lastGood)
        pinned = rekeyed(pinned)
    }
}

/// Automatic engine rollback (roadmap 3.3). Every game remembers the engine build and the way it
/// last started well with. When an update brings a new build, the one before stays as a copy while
/// games still depend on it. A game that ran well on it and ends at once on the new build starts
/// with the copy instead – by itself – until the next update, when the newest gets another try.
struct EngineRollback {
    /// A held build nobody started with for this long after it was replaced goes, even if a game
    /// that hasn't been played since still names it.
    static let keepDays: Double = 30
    /// Each held build can be a whole engine (1.3 GB for winecx): no more than this many.
    static let maxHeld = 2

    /// The components folder (Application Support/Nightforge/Components).
    let root: URL

    static var shared: EngineRollback { EngineRollback(root: ComponentStore.shared.root) }

    var heldRoot: URL { root.appendingPathComponent(".held", isDirectory: true) }
    private var file: URL { root.appendingPathComponent("engine-history.json") }

    private static let lock = NSLock()
    /// Read once per change of the file: the game page asks on every redraw.
    private static var cache: [String: (modified: Date?, history: EngineHistory)] = [:]

    func history() -> EngineHistory {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return load()
    }

    private func load() -> EngineHistory {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached = Self.cache[file.path], cached.modified == modified { return cached.history }
        var history = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(EngineHistory.self, from: $0) }
            ?? EngineHistory()
        history.useGameKeys()
        Self.cache[file.path] = (modified, history)
        return history
    }

    @discardableResult
    private func change<T>(_ body: (inout EngineHistory) -> T) -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var history = load()
        let before = history
        let result = body(&history)
        if history != before {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(history), (try? data.write(to: file, options: .atomic)) != nil {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                Self.cache[file.path] = (modified, history)
            }
        }
        return result
    }

    func folder(of held: HeldBuild, part id: String) -> URL {
        heldRoot.appendingPathComponent(held.folder, isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    /// Where the newest build's part is installed: Components/<id>/<version>.
    func installedFolder(of build: EngineBuild, part id: String) -> URL? {
        build.version(of: id).map { root.appendingPathComponent(id, isDirectory: true).appendingPathComponent($0, isDirectory: true) }
    }

    /// Engine folders of the held builds, so a Steam session running on one can be found and ended.
    func heldEngineFolders() -> [URL] {
        history().held.map { folder(of: $0, part: $0.build.engineID) }
    }

    // MARK: - Updates

    /// Right before an update changes the engine to `next`: the build set up so far is copied away
    /// when a game last ran well on it. `copying`: the parts besides the engine whose folders the
    /// prefix takes files from. `isIntact`: whether the engine folder still holds that build.
    /// The copies are APFS clones, so they cost space only once the originals change or go.
    @discardableResult
    func holdBack(before next: EngineBuild, copying ids: Set<String>, isIntact: (EngineBuild, URL) -> Bool,
                  now: Date = Date()) -> HeldBuild? {
        let history = history()
        guard let current = history.current, current != next,
              !history.held.contains(where: { $0.build == current }),
              history.lastGood.values.contains(where: { $0.build == current.id }),
              let engineFolder = installedFolder(of: current, part: current.engineID), isIntact(current, engineFolder)
        else { return nil }
        let parts = current.parts.map(EngineBuild.split).filter { $0.id == current.engineID || ids.contains($0.id) }
        let fm = FileManager.default
        let name = "\(current.engineID)-\(current.engineVersion)-" + SHA256.hash(data: Data(current.id.utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        let staging = heldRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for part in parts {
                let source = root.appendingPathComponent(part.id, isDirectory: true).appendingPathComponent(part.version, isDirectory: true)
                try ComponentStore.cloneFolder(source, to: staging.appendingPathComponent(part.id, isDirectory: true))
            }
            let target = heldRoot.appendingPathComponent(name, isDirectory: true)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
        } catch {
            try? fm.removeItem(at: staging)
            return nil
        }
        let held = HeldBuild(build: current, folder: name, setUp: history.currentSetUp ?? now, heldSince: now)
        change { $0.held.append(held) }
        return held
    }

    /// `build` is the one set up now. A new one ends every game's pin – the newest gets another try –
    /// and copies no game needs any more go. The first time, games whose way is already confirmed
    /// (`seed`: app ID → way) count as running well on it. `inUse`: a folder something still runs from.
    func settle(_ build: EngineBuild, seed: [GameID: String] = [:], inUse: (URL) -> Bool = { _ in false },
                now: Date = Date()) {
        let removed: [HeldBuild] = change { history in
            if history.current == nil {
                for (game, way) in seed where history.lastGood[game.key] == nil {
                    history.lastGood[game.key] = .init(build: build.id, way: way)
                }
            }
            if history.current != build {
                history.current = build
                history.currentSetUp = now
                history.pinned = [:]
            }
            let gone = Self.unneeded(history, now: now).filter { !inUse(folder(of: $0, part: $0.build.engineID)) }
            history.held.removeAll { held in gone.contains(held) }
            let kept = Set(history.held.map(\.build.id) + [build.id])
            history.lastGood = history.lastGood.filter { kept.contains($0.value.build) }
            history.pinned = history.pinned.filter { kept.contains($0.value) }
            return gone
        }
        let fm = FileManager.default
        for held in removed {
            try? fm.removeItem(at: heldRoot.appendingPathComponent(held.folder, isDirectory: true))
        }
        // Left over from a copy that was cut off, or from a history that was lost.
        let known = Set(history().held.map(\.folder))
        for folder in (try? fm.contentsOfDirectory(atPath: heldRoot.path)) ?? [] where !known.contains(folder) {
            let url = heldRoot.appendingPathComponent(folder, isDirectory: true)
            if !inUse(url) { try? fm.removeItem(at: url) }
        }
    }

    /// Held builds no game needs: none last ran well on it, or it was replaced over `keepDays`
    /// ago and no game is pinned to it; past `maxHeld`, the oldest go (pinned ones last).
    static func unneeded(_ history: EngineHistory, now: Date) -> [HeldBuild] {
        let pinned = Set(history.pinned.values)
        let needed = Set(history.lastGood.values.map(\.build)).union(pinned)
        let keep = history.held
            .filter { held in
                needed.contains(held.build.id) && held.build != history.current
                    && (pinned.contains(held.build.id) || now.timeIntervalSince(held.heldSince) < keepDays * 86_400)
            }
            .sorted { a, b in
                let (pa, pb) = (pinned.contains(a.build.id), pinned.contains(b.build.id))
                return pa != pb ? pa : a.heldSince > b.heldSince
            }
            .prefix(maxHeld)
        return history.held.filter { !keep.contains($0) }
    }

    // MARK: - Starts

    /// The held build the game starts with because the newest crashed it, while its copy is there.
    func pinnedBuild(_ game: GameID) -> HeldBuild? {
        let history = history()
        guard let id = history.pinned[game.key], let held = history.held.first(where: { $0.build.id == id }),
              FileManager.default.fileExists(atPath: folder(of: held, part: held.build.engineID).path)
        else { return nil }
        return held
    }

    /// The first seconds of this start are watched: the game hasn't started well with this build
    /// and way yet (a new engine, another way, or never watched).
    func needsWatch(_ game: GameID, build: EngineBuild, way: String) -> Bool {
        history().lastGood[game.key] != .init(build: build.id, way: way)
    }

    /// The game kept running past its first seconds with this build and way.
    func recordGood(_ game: GameID, build: EngineBuild, way: String) {
        change { $0.lastGood[game.key] = .init(build: build.id, way: way) }
    }

    enum Verdict: Equatable {
        /// The newest build broke a game that ran well with the same way on this held one: start with it.
        case rollBack(HeldBuild)
        /// It ended at once on the held build too: not the engine's doing. The pin is gone.
        case heldFailed
        /// Nothing to do with an engine update.
        case none
    }

    /// The game ended within its first seconds on `build` with `way`.
    func afterFailedStart(_ game: GameID, build: EngineBuild, way: String) -> Verdict {
        let key = game.key
        return change { history in
            if history.pinned[key] == build.id {
                history.pinned[key] = nil
                // It doesn't run well there any more either: no rollback to it from now on.
                if history.lastGood[key]?.build == build.id { history.lastGood[key] = nil }
                return .heldFailed
            }
            guard build == history.current, let good = history.lastGood[key], good.build != build.id, good.way == way,
                  let held = history.held.first(where: { $0.build.id == good.build }),
                  FileManager.default.fileExists(atPath: folder(of: held, part: held.build.engineID).path)
            else { return .none }
            history.pinned[key] = held.build.id
            // Watched again on the held build: should it end at once there too, that's noticed.
            history.lastGood[key] = nil
            return .rollBack(held)
        }
    }

    /// "Try the newest now": the next start uses the newest build. Should it crash again,
    /// `afterFailedStart` brings the held one back by itself.
    func tryNewest(_ game: GameID) {
        change { $0.pinned[game.key] = nil }
    }

    // MARK: - Labels

    /// How a build is named to the player: its engine version, plus the day it was set up when the
    /// two builds share that version (only their graphics differ).
    static func label(_ build: EngineBuild, setUp: Date?, other: EngineBuild?) -> String {
        guard let setUp, other.map({ $0.engine == build.engine }) ?? false else { return build.engineVersion }
        return "\(build.engineVersion) · \(day(setUp))"
    }

    /// "20 Oct" / "20. Okt."
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}
