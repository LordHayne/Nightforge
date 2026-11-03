import Foundation

/// Before a download: is there room for it, and if not, which games could make room. Nothing is
/// downloaded that would stop halfway for lack of space.
enum SpaceCheck {
    /// Room Steam needs beyond the download itself (unpacking, updates on the way).
    static let margin: Int64 = 1 << 30
    /// What the Mac's own disk keeps free besides: macOS slows down, can't update and starts to warn
    /// when it runs lower (CleanMyMac and the system both did at 6 GB). A drive holding only games doesn't need it.
    static let macReserve: Int64 = 10 << 30
    /// A download that fits but leaves less than this on the Mac says so first (and goes ahead if the player wants).
    static let tight: Int64 = 20 << 30
    /// Played within this many days, a game isn't offered for removal.
    static let staleDays = 30
    static let candidateLimit = 8

    /// How much is missing for a download of `needed` bytes with `free` bytes free, with `committed`
    /// bytes still to come from other downloads on the same volume and `margin` kept over; nil when it
    /// fits (or the size isn't known).
    static func shortfall(needed: Int64, free: Int64, committed: Int64 = 0, margin: Int64 = SpaceCheck.margin) -> Int64? {
        guard needed > 0 else { return nil }
        let missing = needed + committed + margin - free
        return missing > 0 ? missing : nil
    }

    /// What stays free once this download and the others have come down.
    static func kept(needed: Int64, free: Int64, committed: Int64) -> Int64 {
        free - committed - max(needed, 0)
    }

    /// Whether a download that fits leaves the Mac with so little that the player should hear it first.
    static func isTight(kept: Int64) -> Bool { kept < tight }

    /// The room to keep: the Mac's own disk needs more than a drive.
    static func margin(for folder: URL) -> Int64 {
        isMacDisk(folder) ? macReserve : margin
    }

    static func isMacDisk(_ folder: URL) -> Bool {
        sameVolume(folder, FileManager.default.homeDirectoryForCurrentUser)
    }

    /// What a game's download or update has still to bring: the rest of the download (all of it while
    /// Steam hasn't counted yet), or what's left of an update. A download counts at what it takes on
    /// disk, not at what comes down (1.11.: Control from Epic and The Evil Within 2 from GOG at once).
    static func remaining(_ game: Game) -> Int64 {
        guard game.downloadNeedsSpace == nil, !game.downloadRefused else { return 0 }
        switch game.install {
        case .downloading(let fraction):
            let size = max(game.sizeOnDisk, game.installedSize ?? 0, 0)
            return Int64(Double(size) * (1 - min(max(fraction ?? 0, 0), 1)))
        case .installed:
            return max(game.pendingUpdate ?? 0, 0)
        case .notInstalled, .inStore:
            return 0
        }
    }

    /// What the other running and waiting downloads (and Steam's updates) still need on the same volume
    /// as `game` (`onSameVolume` says which are).
    static func committed(by games: [Game], except game: Game, onSameVolume: (Game) -> Bool) -> Int64 {
        games.filter { $0.id != game.id && remaining($0) > 0 && onSameVolume($0) }.reduce(0) { $0 + remaining($1) }
    }

    /// A volume that holds games, for the notice that it is running low.
    struct Place: Equatable {
        let name: String
        let free: Int64
        let floor: Int64
        let isMac: Bool
    }

    /// The place with the least left among those below their floor; nil when all have room.
    static func lowest(in places: [Place]) -> Place? {
        places.filter { $0.free < $0.floor }.min { $0.free < $1.free }
    }

    /// Installed games not played for a month (or never), biggest first – what's offered to remove.
    static func candidates(_ games: [Game], except game: Game, now: Date = Date()) -> [Game] {
        let since = now.addingTimeInterval(-Double(staleDays) * 86_400)
        return games
            .filter { $0.isInstalled && $0.id != game.id && $0.sizeOnDisk > 0 && ($0.lastPlayed.map { $0 < since } ?? true) }
            .sorted { $0.sizeOnDisk > $1.sizeOnDisk }
            .prefix(candidateLimit)
            .map { $0 }
    }

    /// The first candidates that together free `shortfall` (all of them when even that isn't enough).
    static func preselect(_ candidates: [Game], shortfall: Int64) -> Set<String> {
        var picked: Set<String> = [], freed: Int64 = 0
        for game in candidates where freed < shortfall {
            picked.insert(game.id)
            freed += game.sizeOnDisk
        }
        return picked
    }

    /// The nearest folder that exists, for asking its volume about space (a game's own folder
    /// doesn't exist before it's downloaded).
    static func existingFolder(for url: URL) -> URL {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        return folder
    }

    /// Whether two folders are on the same volume (removing a game there makes room here).
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let one = try? existingFolder(for: a).resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let other = try? existingFolder(for: b).resourceValues(forKeys: key).volumeIdentifier as? NSObject
        else { return false }
        return one.isEqual(other)
    }
}

/// A download waiting for room: shown as a sheet with games to remove and drives to put it on. With
/// room on the Mac (no shortfall) and a drive with games of Nightforge's on it, the sheet asks where
/// the game goes.
struct SpaceRequest: Identifiable {
    let game: Game
    /// What the download needs on disk.
    let needed: Int64
    let free: Int64
    let shortfall: Int64
    let candidates: [Game]
    /// External drives plugged in, to download onto instead (ExternalDrive).
    var drives: [DriveChoice] = []
    /// What other downloads on the volume still need, and the room kept over (the Mac's own disk keeps more).
    var committed: Int64 = 0
    var margin: Int64 = SpaceCheck.margin
    /// It fits but leaves this little free on the Mac: said before it starts (SpaceCheck.isTight).
    var kept: Int64?
    var id: String { game.id }
    /// The player picks the place: a drive with games of Nightforge's on it is plugged in.
    var asksWhere: Bool { drives.contains { $0.usable && $0.drive.hasLibrary } }
    /// What the volume must have free for the download: it, the others, and the room kept.
    var required: Int64 { needed + committed + margin }
}
