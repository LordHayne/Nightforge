// Checks SpaceCheck: when a download doesn't fit, which games are offered to make room, which are
// picked first, and the volume helpers: tests/SpaceCheckTest/run.sh
import Foundation

@main
struct SpaceCheckTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let gb: Int64 = 1 << 30

    static func game(_ id: Int, _ install: InstallState, gb size: Int64, playedDaysAgo: Double? = nil) -> Game {
        var game = Game(appID: id, name: "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: size * gb)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func main() {
        check(SpaceCheck.shortfall(needed: 40 * gb, free: 100 * gb) == nil, "fits with room to spare")
        check(SpaceCheck.shortfall(needed: 40 * gb, free: 40 * gb) == SpaceCheck.margin, "exactly the size isn't enough: Steam needs a little more")
        check(SpaceCheck.shortfall(needed: 50 * gb, free: 20 * gb) == 30 * gb + SpaceCheck.margin, "how much is missing")
        check(SpaceCheck.shortfall(needed: 0, free: 0) == nil, "an unknown size doesn't stop a download")

        // Other downloads on the same volume still need what they have left (1.11.: Control and The Evil Within 2 at once).
        let control = game(10, .downloading(0.1), gb: 28)
        let waiting = game(11, .downloading(nil), gb: 35)
        let updating: Game = { var game = game(12, .installed, gb: 60); game.pendingUpdate = 2 * gb; return game }()
        var stuck = game(13, .downloading(0.2), gb: 50); stuck.downloadNeedsSpace = 50 * gb
        check(SpaceCheck.remaining(control) == Int64(Double(28 * gb) * 0.9), "a tenth is down, the rest to come: \(SpaceCheck.remaining(control))")
        check(SpaceCheck.remaining(waiting) == 35 * gb, "not started counting: all of it")
        check(SpaceCheck.remaining(updating) == 2 * gb && SpaceCheck.remaining(game(14, .installed, gb: 9)) == 0, "an update's rest; nothing for a game that's done")
        check(SpaceCheck.remaining(stuck) == 0 && SpaceCheck.remaining(game(15, .notInstalled, gb: 20)) == 0, "a download Steam stopped and a game not on the Mac add nothing")
        // A download counts at what it takes on disk: Epic's and GOG's files come compressed, Steam unpacks into more.
        var packed = game(17, .downloading(0.1), gb: 28); packed.installedSize = 42 * gb
        check(SpaceCheck.remaining(packed) == Int64(Double(42 * gb) * 0.9), "the rest of what it unpacks to, not of what comes down: \(SpaceCheck.remaining(packed))")
        var odd = game(18, .downloading(nil), gb: 28); odd.installedSize = 20 * gb
        check(SpaceCheck.remaining(odd) == 28 * gb, "never less than what comes down")
        var installed = game(19, .installed, gb: 30); installed.installedSize = 99 * gb
        check(SpaceCheck.remaining(installed) == 0, "an installed game's size isn't counted again")
        let others = [control, waiting, updating, stuck, game(16, .installed, gb: 80)]
        let all = SpaceCheck.committed(by: others, except: game(99, .notInstalled, gb: 10)) { _ in true }
        check(all == SpaceCheck.remaining(control) + 35 * gb + 2 * gb, "the others' rests add up: \(all)")
        check(SpaceCheck.committed(by: others, except: control) { _ in true } == 37 * gb, "a game's own download isn't counted against itself")
        check(SpaceCheck.committed(by: others, except: game(99, .notInstalled, gb: 10)) { $0.appID == 12 } == 2 * gb, "only the same volume counts")

        // 44 GB free, Control still bringing 27.8 GB, The Evil Within 2 wants 35.2: the Mac keeps 10 GB over.
        let free: Int64 = 44 * gb, running = Int64(27.8 * Double(gb)), wanted = Int64(35.2 * Double(gb))
        check(SpaceCheck.shortfall(needed: wanted, free: free) == nil, "alone it would have fitted (as before)")
        check(SpaceCheck.shortfall(needed: wanted, free: free, committed: running, margin: SpaceCheck.macReserve) == wanted + running + SpaceCheck.macReserve - free,
              "with Control still to come it doesn't")
        check(SpaceCheck.shortfall(needed: 20 * gb, free: free, committed: 10 * gb, margin: SpaceCheck.macReserve) == nil, "20 + 10 GB and the reserve fit in 44")
        check(SpaceCheck.shortfall(needed: 24 * gb, free: free, margin: SpaceCheck.macReserve) == nil
              && SpaceCheck.shortfall(needed: 34 * gb, free: free, margin: SpaceCheck.macReserve) == nil
              && SpaceCheck.shortfall(needed: 34 * gb + 1, free: free, margin: SpaceCheck.macReserve) == 1, "the reserve is 10 GB: 34 GB fit in 44, one byte more doesn't")
        check(SpaceCheck.macReserve == 10 * gb && SpaceCheck.margin == gb, "10 GB on the Mac, Steam's 1 GB on a drive")
        // The same evening as Epic and GOG report it: Control comes down as 27.8 GB but unpacks to more; with
        // what that takes, a second download that seemed to fit with room over doesn't.
        var control2 = Game(gameID: .epic("Calluna"), name: "Control", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                            steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: running)
        control2.install = .downloading(0.25)
        let byDownload = SpaceCheck.remaining(control2)
        control2.installedSize = 42 * gb
        let byDisk = SpaceCheck.remaining(control2)
        check(SpaceCheck.shortfall(needed: 12 * gb, free: free, committed: byDownload, margin: SpaceCheck.macReserve) == nil
              && SpaceCheck.shortfall(needed: 12 * gb, free: free, committed: byDisk, margin: SpaceCheck.macReserve) != nil,
              "counted by what comes down it would fit, by what it takes on disk it doesn't: \(byDownload) / \(byDisk)")
        check(SpaceCheck.kept(needed: 27 * gb, free: free, committed: 5 * gb) == 12 * gb, "what stays free after all of them")
        check(SpaceCheck.isTight(kept: 12 * gb) && SpaceCheck.isTight(kept: 20 * gb - 1) && !SpaceCheck.isTight(kept: 20 * gb), "tight below 20 GB")
        check(SpaceCheck.margin(for: FileManager.default.homeDirectoryForCurrentUser) == SpaceCheck.macReserve, "the Mac's own disk keeps the reserve")

        // The note that a drive with games runs low: the one with least left, and only below its floor.
        let mac = SpaceCheck.Place(name: "Mac", free: 6 * gb, floor: SpaceCheck.macReserve, isMac: true)
        let tight = SpaceCheck.Place(name: "T7", free: gb / 2, floor: SpaceCheck.margin, isMac: false)
        let roomy = SpaceCheck.Place(name: "Big", free: 400 * gb, floor: SpaceCheck.margin, isMac: false)
        check(SpaceCheck.lowest(in: [roomy, mac, tight]) == tight, "the lowest of those below their floor")
        check(SpaceCheck.lowest(in: [roomy, mac]) == mac && SpaceCheck.lowest(in: [roomy]) == nil && SpaceCheck.lowest(in: []) == nil, "none low, no note")
        check(SpaceCheck.lowest(in: [SpaceCheck.Place(name: "Mac", free: 10 * gb, floor: SpaceCheck.macReserve, isMac: true)]) == nil, "exactly the reserve is still fine")

        let target = game(0, .notInstalled, gb: 50)
        let games = [
            target,
            game(1, .installed, gb: 30, playedDaysAgo: 2),     // played lately: kept
            game(2, .installed, gb: 12, playedDaysAgo: 200),
            game(3, .installed, gb: 45),                        // never played
            game(4, .installed, gb: 8, playedDaysAgo: 40),
            game(5, .notInstalled, gb: 60),                     // not on the Mac
            game(6, .downloading(0.3), gb: 20, playedDaysAgo: 400),
        ]
        let candidates = SpaceCheck.candidates(games, except: target)
        check(candidates.map(\.appID) == [3, 2, 4], "installed, unplayed for a month or never, biggest first: \(candidates.map(\.appID))")
        check(SpaceCheck.preselect(candidates, shortfall: 10 * gb) == ["Nightforge#3"], "the biggest alone is enough")
        check(SpaceCheck.preselect(candidates, shortfall: 50 * gb) == ["Nightforge#3", "Nightforge#2"], "then the next")
        check(SpaceCheck.preselect(candidates, shortfall: 500 * gb).count == 3, "all when even that isn't enough")
        check(SpaceCheck.preselect([], shortfall: gb).isEmpty, "nothing to offer, nothing picked")
        let many = (10..<30).map { game($0, .installed, gb: Int64($0)) }
        check(SpaceCheck.candidates(many, except: target).count == SpaceCheck.candidateLimit, "a short list")

        // A folder that doesn't exist yet is asked about through the nearest one that does.
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-space-test/steamapps/common/Game")
        check(SpaceCheck.existingFolder(for: missing) == FileManager.default.temporaryDirectory.standardizedFileURL
              || SpaceCheck.existingFolder(for: missing).path == FileManager.default.temporaryDirectory.path.replacingOccurrences(of: "/$", with: "", options: .regularExpression),
              "the nearest existing folder: \(SpaceCheck.existingFolder(for: missing).path)")
        check(SpaceCheck.sameVolume(missing, FileManager.default.temporaryDirectory), "a folder and its parent share a volume")

        clones()

        print(failures == 0 ? "✓ SpaceCheck" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func randomFile(_ url: URL, bytes: Int) {
        var data = [UInt8](repeating: 0, count: bytes)
        arc4random_buf(&data, bytes)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(data).write(to: url)
    }

    /// Settings › Storage: the held engine is an APFS clone of the engine (Components/.held) and costs
    /// nothing while the two are the same. Real clones, made the way the engine's are.
    static func clones() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("space-clones-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let engine = root.appendingPathComponent("winecx/4.7.3", isDirectory: true)
        randomFile(engine.appendingPathComponent("lib/wine/ntdll.so"), bytes: 3 << 20)
        randomFile(engine.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), bytes: 1 << 20)
        let alone = LibraryScanner.folderSize(root)
        check(alone >= 4 << 20, "the engine's own size: \(alone)")

        let held = root.appendingPathComponent(".held/winecx-4.7.3/winecx", isDirectory: true)
        try? fm.createDirectory(at: held.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ComponentStore.cloneFolder(engine, to: held)
        let keys: Set<URLResourceKey> = [.mayShareFileContentKey]
        guard (try? held.appendingPathComponent("lib/wine/ntdll.so").resourceValues(forKeys: keys))?.mayShareFileContent == true else {
            print("– no APFS clones in \(fm.temporaryDirectory.path), the clone checks are skipped")
            return
        }
        check(LibraryScanner.folderSize(root) == alone, "a clone the engine hasn't changed costs nothing: \(LibraryScanner.folderSize(root)) for \(alone)")
        check(LibraryScanner.folderSize(held) == alone, "on its own it is the whole engine")

        // The engine's DLL is replaced (an update, D3DMetal): the held copy keeps the old one, which counts now.
        let dll = engine.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")
        let oldDLL = Int64((try? held.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")
            .resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? -1)
        try? fm.removeItem(at: dll)
        randomFile(dll, bytes: 1 << 20)
        check(LibraryScanner.folderSize(root) == alone + oldDLL, "a file replaced in the engine: the held one's old file counts")

        // A copy that isn't a clone counts in full, as before.
        let copy = root.appendingPathComponent("copy/ntdll.so")
        if let bytes = try? Data(contentsOf: engine.appendingPathComponent("lib/wine/ntdll.so")) {
            try? fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? bytes.write(to: copy)
        }
        check(LibraryScanner.folderSize(root) == alone + oldDLL + LibraryScanner.folderSize(copy.deletingLastPathComponent()),
              "a plain copy of the same bytes is counted in full")
        try? fm.removeItem(at: copy.deletingLastPathComponent())

        // The engine goes (a new one came): the held copy's blocks are its own.
        try? fm.removeItem(at: engine)
        check(LibraryScanner.folderSize(root) == LibraryScanner.folderSize(held) && LibraryScanner.folderSize(held) == alone,
              "without the engine the held copy is the whole size")
    }
}
