import Foundation

/// How far a copy has got, read by the downloads panel every half second and written by the copy
/// as it goes; `cancel` stops it at the next piece.
final class CopyProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _done: Int64 = 0
    private var _current: Int64 = 0
    private var _cancelled = false
    /// What the whole move copies.
    var total: Int64 = 0

    var copied: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _done + _current
    }

    var fraction: Double? { total > 0 ? min(Double(copied) / Double(total), 1) : nil }

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    fileprivate func file(copied bytes: Int64) {
        lock.lock()
        _current = bytes
        lock.unlock()
    }

    fileprivate func fileDone(_ bytes: Int64) {
        lock.lock()
        _done += bytes
        _current = 0
        lock.unlock()
    }
}

/// Copies a game's folder to another drive with everything it needs – permissions, links, extended
/// attributes – and checks the copy against the original.
enum FolderCopy {
    /// What a folder holds: its files' and links' own sizes (not the blocks they take), the measure
    /// the copy reports in.
    static func size(of folder: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                         options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            var info = stat()
            guard lstat(item.path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR else { continue }
            total += Int64(info.st_size)
        }
        return total
    }

    /// Copies `source` to `destination`, which mustn't exist yet. Links stay links.
    static func copy(_ source: URL, to destination: URL, progress: CopyProgress) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DriveError.alreadyThere(destination.lastPathComponent)
        }
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, source, _, context in
            guard let context else { return COPYFILE_CONTINUE }
            let progress = Unmanaged<CopyProgress>.fromOpaque(context).takeUnretainedValue()
            if progress.cancelled { return COPYFILE_QUIT }
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                progress.file(copied: Int64(copied))
            } else if what == COPYFILE_RECURSE_FILE && stage == COPYFILE_FINISH {
                var info = stat()
                progress.fileDone(source.map { lstat($0, &info) == 0 ? Int64(info.st_size) : 0 } ?? 0)
            } else if stage == COPYFILE_ERR {
                return COPYFILE_QUIT
            }
            return COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(progress).toOpaque())
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW)
        guard copyfile(source.path, destination.path, state, flags) == 0 else {
            let code = errno
            if progress.cancelled { throw DriveError.cancelled }
            throw DriveError.copyFailed(reason(code))
        }
        if progress.cancelled { throw DriveError.cancelled }
    }

    /// Why a copy stopped, in the player's words for what usually happens on the way to a drive.
    static func reason(_ code: Int32) -> String {
        switch code {
        case ENOSPC: return L10n.t("The drive is full.")
        case EFBIG: return L10n.t("A file is too big for the drive's format.")
        case EIO, ENXIO, ENODEV: return L10n.t("The drive was unplugged or can't be read.")
        case EACCES, EPERM, EROFS: return L10n.t("Nightforge isn't allowed to write there.")
        default: return String(cString: strerror(code))
        }
    }

    /// The first thing in `source` that `copy` lacks or has differently: each file there with the
    /// same size, each link pointing the same way, each folder a folder. Extra files a drive keeps
    /// beside them (exFAT's "._" files) don't count. nil when the copy is whole.
    static func difference(_ source: URL, _ copy: URL) -> String? {
        let fm = FileManager.default
        guard let items = fm.enumerator(atPath: source.path) else { return source.lastPathComponent }
        for case let relative as String in items {
            var original = stat(), copied = stat()
            let from = source.appendingPathComponent(relative).path, to = copy.appendingPathComponent(relative).path
            guard lstat(from, &original) == 0 else { continue }  // gone meanwhile: nothing to compare
            guard lstat(to, &copied) == 0, original.st_mode & S_IFMT == copied.st_mode & S_IFMT else { return relative }
            switch original.st_mode & S_IFMT {
            case S_IFREG:
                if original.st_size != copied.st_size { return relative }
            case S_IFLNK:
                if (try? fm.destinationOfSymbolicLink(atPath: from)) != (try? fm.destinationOfSymbolicLink(atPath: to)) { return relative }
            default:
                break
            }
        }
        return nil
    }
}

/// Moves a game's folders to a library on another drive: copy, check, then tell its store where the
/// game is now (`commit`), and only then delete the original. Whatever fails before the store
/// knows leaves the original as it was and takes the copy away again.
enum GameMover {
    /// One folder to move. An optional one (Steam's workshop items, the shader cache) may be missing.
    struct Part {
        let from: URL
        let to: URL
        var optional = false
    }

    /// The copy goes under a hidden name next to its place and is renamed once it's checked: an
    /// unfinished copy never looks like a game.
    static func staging(_ url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".nightforge-moving-" + url.lastPathComponent, isDirectory: true)
    }

    /// What the move copies, before it starts (for the space check and the progress).
    static func size(_ parts: [Part]) -> Int64 {
        parts.reduce(0) { $0 + (FileManager.default.fileExists(atPath: $1.from.path) ? FolderCopy.size(of: $1.from) : 0) }
    }

    /// Moves the parts; `commit` makes the move known (or throws, undoing its own steps). Returns
    /// the originals that couldn't be deleted afterwards – the game is in its new place by then.
    static func move(_ parts: [Part], progress: CopyProgress, commit: () async throws -> Void) async throws -> [URL] {
        let fm = FileManager.default
        let parts = try parts.filter { part in
            if fm.fileExists(atPath: part.from.path) { return true }
            if part.optional { return false }
            throw DriveError.gone(part.from.lastPathComponent)
        }
        for part in parts {
            if let existing = try? fm.contentsOfDirectory(atPath: part.to.path) {
                guard existing.isEmpty else { throw DriveError.alreadyThere(part.to.lastPathComponent) }
                try fm.removeItem(at: part.to)  // an empty folder left behind: nothing to lose
            } else if fm.fileExists(atPath: part.to.path) {
                throw DriveError.alreadyThere(part.to.lastPathComponent)
            }
        }
        progress.total = await Task.detached(priority: .userInitiated) { size(parts) }.value

        var placed: [URL] = []
        func undo() {
            for part in parts { try? fm.removeItem(at: staging(part.to)) }
            for url in placed { try? fm.removeItem(at: url) }
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                for part in parts {
                    try fm.createDirectory(at: part.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.removeItem(at: staging(part.to))  // left by a move that was cut off
                    try FolderCopy.copy(part.from, to: staging(part.to), progress: progress)
                }
                for part in parts {
                    if let differs = FolderCopy.difference(part.from, staging(part.to)) { throw DriveError.copyDiffers(differs) }
                }
            }.value
            for part in parts {
                try fm.moveItem(at: staging(part.to), to: part.to)
                placed.append(part.to)
            }
            try await commit()
        } catch {
            undo()
            throw error
        }
        return await Task.detached(priority: .utility) {
            let fm = FileManager.default
            return parts.compactMap { part in
                try? fm.removeItem(at: part.from)
                return fm.fileExists(atPath: part.from.path) ? part.from : nil
            }
        }.value
    }

    // MARK: - Steam

    /// What belongs to a Steam game in its library (`steamapps`): its folder, its workshop items
    /// and its shader cache.
    static func steamParts(appID: Int, installDirName: String, from source: URL, to destination: URL) -> [Part] {
        [Part(from: source.appendingPathComponent("common/\(installDirName)", isDirectory: true),
              to: destination.appendingPathComponent("common/\(installDirName)", isDirectory: true)),
         Part(from: source.appendingPathComponent("workshop/content/\(appID)", isDirectory: true),
              to: destination.appendingPathComponent("workshop/content/\(appID)", isDirectory: true), optional: true),
         Part(from: source.appendingPathComponent("shadercache/\(appID)", isDirectory: true),
              to: destination.appendingPathComponent("shadercache/\(appID)", isDirectory: true), optional: true)]
    }

    /// Moves a Steam game from one library of a Steam to another (`steamapps` folders), with that
    /// Steam stopped: the files, then its manifest, and the list of libraries says where it is.
    /// `steamRunning` is asked once more before the manifest moves – a Steam that started meanwhile
    /// would write its own list over the change, so the move is undone instead.
    static func moveSteamGame(appID: Int, installDirName: String, from source: URL, to destination: URL,
                              steamRoot: URL, bottle: Bottle, progress: CopyProgress,
                              steamRunning: @escaping () -> Bool) async throws -> [URL] {
        let fm = FileManager.default
        let manifests = ["appmanifest_\(appID).acf", "workshop/appworkshop_\(appID).acf"]
        let size = (VDF.parse(contentsOf: source.appendingPathComponent(manifests[0]))?["appstate"]?["sizeondisk"]?.string)
            .flatMap { Int64($0) } ?? 0
        guard fm.fileExists(atPath: source.appendingPathComponent(manifests[0]).path) else { throw DriveError.gone(manifests[0]) }
        guard !fm.fileExists(atPath: destination.appendingPathComponent(manifests[0]).path) else {
            throw DriveError.alreadyThere(manifests[0])
        }
        return try await move(steamParts(appID: appID, installDirName: installDirName, from: source, to: destination), progress: progress) {
            guard !steamRunning() else { throw DriveError.steamStarted }
            let lists = SteamLibraries.snapshot(steamRoot: steamRoot)
            var written: [URL] = []
            do {
                for name in manifests where fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                    let target = destination.appendingPathComponent(name)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: source.appendingPathComponent(name), to: target)
                    written.append(target)
                }
                try SteamLibraries.record(appID: appID, size: size, inLibrary: destination.deletingLastPathComponent(),
                                          steamRoot: steamRoot, bottle: bottle)
                for name in manifests where fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                    try fm.removeItem(at: source.appendingPathComponent(name))
                }
            } catch {
                for name in manifests where !fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                    try? fm.copyItem(at: destination.appendingPathComponent(name), to: source.appendingPathComponent(name))
                }
                for file in written { try? fm.removeItem(at: file) }
                SteamLibraries.restore(lists)
                throw error
            }
        }
    }

    // MARK: - Epic

    /// legendary's entries (the game and its add-ons) installed in `folder`.
    static func epicEntries(inFolder folder: URL, installedJSON: Data) -> [String] {
        guard let items = try? JSONSerialization.jsonObject(with: installedJSON) as? [String: [String: Any]] else { return [] }
        let path = folder.standardizedFileURL.path
        return items.compactMap { appName, item in
            (item["install_path"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == path ? appName : nil
        }
        .sorted()
    }

    /// Moves an Epic game's folder into `base` (another "Epic Games" folder); legendary then notes
    /// the new place of the game and its add-ons (`legendary move --skip-move`, as legendary itself
    /// can't move across drives). `note` runs legendary with those arguments.
    static func moveEpicGame(folder: URL, to base: URL, installedJSON: Data, progress: CopyProgress,
                             note: @escaping ([String]) async throws -> Void) async throws -> [URL] {
        let entries = epicEntries(inFolder: folder, installedJSON: installedJSON)
        guard !entries.isEmpty else { throw DriveError.gone(folder.lastPathComponent) }
        let oldBase = folder.deletingLastPathComponent()
        let part = Part(from: folder, to: base.appendingPathComponent(folder.lastPathComponent, isDirectory: true))
        return try await move([part], progress: progress) {
            var noted: [String] = []
            do {
                for appName in entries {
                    try await note(["move", appName, base.path, "--skip-move"])
                    noted.append(appName)
                }
            } catch {
                for appName in noted { try? await note(["move", appName, oldBase.path, "--skip-move"]) }
                throw error
            }
        }
    }
}
