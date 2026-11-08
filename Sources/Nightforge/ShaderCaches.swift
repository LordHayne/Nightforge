import Foundation

/// The shaders translated for this Mac: Steam's caches in each Windows library (DXVK state, Vulkan
/// pipelines), DXMT's and KosmicKrisp's own, and the Metal caches macOS keeps for games under Wine
/// (D3DMetal, MoltenVK, KosmicKrisp). All of it rebuilds itself – the next start of each game just
/// takes longer.
enum ShaderCaches {
    /// Processes whose Metal caches are the games': the Game Mode bundle and Wine's loaders.
    static let bundleIDs = ["io.github.lordhayne.nightforge.game", "org.winehq.wine", "com.codeweavers.CrossOver.wineloader"]
    static let metalFolders = ["com.apple.metal", "com.apple.metalfe", "com.apple.gpuarchiver"]

    /// The Mac's per-user cache folder (`getconf DARWIN_USER_CACHE_DIR`), where Metal keeps its caches.
    static var darwinUserCache: URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    /// The setting that turns early translation off; there's no switch in the app:
    /// `defaults write io.github.lordhayne.nightforge dxmtEarlyShaders -bool false`.
    static let earlyTranslationKey = "dxmtEarlyShaders"

    /// Programs DXMT doesn't translate early for. Overwatch: a change to the graphics layer can look
    /// suspicious to its anti-cheat and the player's account is at stake, so it waits for the user's OK.
    static let noEarlyTranslation: Set<String> = ["overwatch.exe"]

    /// Whether DXMT translates a game's shaders as soon as the game creates them, so that the first
    /// round waits less (`d3d11.prepareShaders`, engine/patches/dxmt-0.80-prepare-shaders.patch).
    /// A d3d11.dll from before that patch stores the unknown line in dxmt.conf and never asks for it.
    static func translatesEarly(programs: [URL], defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: earlyTranslationKey) as? Bool ?? true)
            && !programs.contains { noEarlyTranslation.contains($0.lastPathComponent.lowercased()) }
    }

    /// Above this the file all games share goes before the next start. Translating early writes every
    /// shader a game creates: Recall's file reached about 1 GB after one short session of Overwatch.
    static let translationLimit: Int64 = 4 * 1024 * 1024 * 1024

    /// Removes DXMT's translations when they've outgrown `limit`, and returns the bytes that went.
    /// A game still running keeps writing to its open file, which is simply gone when it ends.
    @discardableResult
    static func limitTranslations(in folder: URL = Engine.shaderCache, limit: Int64 = translationLimit,
                                  defaults: UserDefaults = .standard) -> Int64 {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("shaders_") }
        let bytes = files.reduce(Int64(0)) { $0 + ((try? fm.attributesOfItem(atPath: $1.path))?[.size] as? Int64 ?? 0) }
        guard bytes > limit else { return 0 }
        for file in files { try? fm.removeItem(at: file) }
        forgetPreparedGames(defaults)
        return bytes
    }

    /// `limitTranslations` before a game starts, with a line in the game log when it cleared the file.
    static func limitTranslationsBeforeStart() {
        let freed = limitTranslations()
        if freed > 0 { GameLog.note("DXMT's translated shaders had reached \(freed / (1024 * 1024)) MB and were cleared") }
    }

    /// Folders whose contents can go; only the ones there.
    static func folders(steamapps: [URL],
                        dxmt: URL = Engine.shaderCache,
                        mesa: URL = Engine.mesaShaderCache,
                        userCache: URL? = darwinUserCache) -> [URL] {
        var folders = steamapps.map { $0.appendingPathComponent("shadercache", isDirectory: true) } + [dxmt, mesa]
        if let userCache {
            for id in bundleIDs {
                folders += metalFolders.map { userCache.appendingPathComponent("\(id)/\($0)", isDirectory: true) }
            }
            // DXMT points Metal's cache to a folder per program, dxmt/<exe>/com.apple.metal
            // (Overwatch's held 25 MB on 7.11.); without it "Clear shaders" left those behind.
            folders.append(userCache.appendingPathComponent("dxmt", isDirectory: true))
        }
        return folders.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func size(_ folders: [URL]) -> Int64 {
        folders.reduce(0) { $0 + LibraryScanner.folderSize($1) }
    }

    /// Empties the folders (they stay, for whoever writes there next) and returns the bytes freed.
    @discardableResult
    static func clear(_ folders: [URL], defaults: UserDefaults = .standard) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        for folder in folders {
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                let bytes = LibraryScanner.folderSize(item) + fileSize(item)
                if (try? fm.removeItem(at: item)) != nil { freed += bytes }
            }
        }
        forgetPreparedGames(defaults)
        return freed
    }

    /// The next start of each game says again that it prepares shaders (1.1).
    private static func forgetPreparedGames(_ defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("shaders.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// A plain file's size (folderSize counts what's inside folders).
    private static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
              values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? 0)
    }
}
