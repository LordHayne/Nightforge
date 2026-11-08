import Foundation

/// Where Apple's D3DMetal comes from, the layer that runs DirectX 12 on a Mac. It isn't fetched with
/// the engine: Apple's licence – to use it "for the sole purpose of developing, testing, or evaluating
/// video games", passed on only non-commercially – is shown first, once, and the player picks the way:
/// Nightforge's own download, or the Game Porting Toolkit from Apple, imported unchanged. A D3DMetal
/// an earlier Nightforge fetched stays in use without a question.
enum D3DMetalSupply {
    enum Source: String, Codable {
        case nightforge, apple
    }

    /// The one answer: Apple's licence was shown and accepted, and which way D3DMetal comes.
    struct Choice: Codable, Equatable {
        var source: Source
        /// Nightforge's download: the version a copy from before the question is kept at (nil: the
        /// component list's). Apple's: the version imported (nil until it has been).
        var version: String?
        var accepted: Date
    }

    /// What the engine gets D3DMetal from.
    struct Current: Equatable {
        enum Origin: Equatable {
            /// The component list's download.
            case download(Component)
            /// A copy an earlier Nightforge downloaded (…/Components/d3dmetal/<version>).
            case kept(URL)
            /// What the player imported from Apple's toolkit.
            case imported(URL)
        }

        let origin: Origin
        /// For the engine's stamps and build list: "3.0", "apple-3.0".
        let version: String
    }

    enum Failure: LocalizedError, Equatable {
        case notAToolkit, notSignedByApple, cannotOpen, copyFailed
        /// A version whose Windows files Nightforge has no list of (`windowsFiles`).
        case unknownVersion(String)
        /// Its Windows files, or what lies beside Apple's, aren't as Apple ships that version.
        case changed(String)

        var errorDescription: String? {
            switch self {
            case .notAToolkit:
                return L10n.t("This isn't Apple's Game Porting Toolkit: Nightforge found no D3DMetal in it.")
            case .notSignedByApple:
                return L10n.t("Apple didn't sign this D3DMetal, so Nightforge doesn't use it.")
            case .unknownVersion(let version):
                return L10n.t("Nightforge doesn't know D3DMetal %@ yet, so it can't check the toolkit's Windows files and doesn't import it. Apple's toolkit %@ can be imported.",
                              displayVersion(version), finishedVersion)
            case .changed(let version):
                return L10n.t("The Windows files in this toolkit aren't the ones Apple ships with D3DMetal %@, so Nightforge doesn't import it. Download it from Apple again.",
                              displayVersion(version))
            case .cannotOpen:
                return L10n.t("Nightforge couldn't open this download. Try downloading it again.")
            case .copyFailed:
                return L10n.t("Nightforge couldn't copy D3DMetal. Check that your Mac has room.")
            }
        }
    }

    /// Apple's licence for the toolkit, the License.rtf that comes with it (the same file in every version
    /// since 2023), ships inside the app so that nobody else decides which text the player accepts.
    /// Resources/Apple-GPTK-License.rtf is byte for byte the one in Apple's toolkit 3.0:
    static let licenseSHA256 = "5abb2d059be217663b00e8fd37e14411d374e11d17e3b744eebd49b8d17118c8"
    static let licenseFileName = "Apple-GPTK-License"

    /// The licence file to show, if it is the one it should be (a copy that doesn't match isn't shown as Apple's).
    static func licenseDocument(at file: URL? = Bundle.main.url(forResource: licenseFileName, withExtension: "rtf")) -> URL? {
        guard let file, (try? ComponentStore.sha256(of: file)) == licenseSHA256 else { return nil }
        return file
    }

    /// Apple's page on the toolkit, where the licence can be read too (the download itself needs an Apple Account).
    static let toolkitPageURL = URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!
    /// Where Apple hands out the toolkit (a free Apple Account is enough).
    static let appleDownloadURL = URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!

    static var folder: URL { Engine.supportDir.appendingPathComponent("D3DMetal", isDirectory: true) }

    private static func choiceFile(_ folder: URL) -> URL { folder.appendingPathComponent("choice.json") }
    /// The toolkits the player imported, a folder per version.
    static func importedFolder(in folder: URL = D3DMetalSupply.folder) -> URL {
        folder.appendingPathComponent("Apple", isDirectory: true)
    }

    // MARK: The answer

    static func choice(in folder: URL = D3DMetalSupply.folder) -> Choice? {
        guard let data = try? Data(contentsOf: choiceFile(folder)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Choice.self, from: data)
    }

    /// Takes the answer back (a question that was cancelled halfway).
    static func forget(in folder: URL = D3DMetalSupply.folder) {
        try? FileManager.default.removeItem(at: choiceFile(folder))
    }

    static func save(_ choice: Choice, in folder: URL = D3DMetalSupply.folder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? encoder.encode(choice).write(to: choiceFile(folder), options: .atomic)
    }

    /// What the engine installs, or nil: nothing is asked yet, or the way chosen has nothing to give
    /// (an import that's gone, a download the component list no longer offers).
    static func current(manifest: ComponentManifest?, componentsRoot: URL,
                        folder: URL = D3DMetalSupply.folder) -> Current? {
        var answer = choice(in: folder)
        if answer == nil, let kept = earlierInstall(in: componentsRoot) {
            // The player has been using it: it stays, and nothing is asked.
            let adopted = Choice(source: .nightforge, version: kept, accepted: Date())
            save(adopted, in: folder)
            answer = adopted
        }
        guard let choice = answer else { return nil }
        switch choice.source {
        case .apple:
            guard let version = choice.version else { return nil }
            let dir = importedFolder(in: folder).appendingPathComponent(version, isDirectory: true)
            guard Engine.d3dMetalPayloadRoot(in: dir) != nil else { return nil }
            return Current(origin: .imported(dir), version: "apple-" + version)
        case .nightforge:
            if let version = choice.version, let dir = keptFolder(version, in: componentsRoot) {
                return Current(origin: .kept(dir), version: version)
            }
            guard let component = manifest?.component(Engine.d3dMetalID) else { return nil }
            return Current(origin: .download(component), version: component.version)
        }
    }

    /// A D3DMetal Nightforge downloaded as a component before it asked (the newest, if several).
    static func earlierInstall(in componentsRoot: URL) -> String? {
        let fm = FileManager.default
        let dir = componentsRoot.appendingPathComponent(Engine.d3dMetalID, isDirectory: true)
        let versions = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func touched(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return versions.filter { keptFolder($0.lastPathComponent, in: componentsRoot) != nil }
            .max { touched($0) < touched($1) }?.lastPathComponent
    }

    private static func keptFolder(_ version: String, in componentsRoot: URL) -> URL? {
        let dir = componentsRoot.appendingPathComponent(Engine.d3dMetalID, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        // The marker a finished download leaves (ComponentStore), and the files themselves.
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(".sha256").path),
              Engine.d3dMetalPayloadRoot(in: dir) != nil else { return nil }
        return dir
    }

    /// The version of Apple's toolkit that is no beta, which the Settings line points a beta's owner to
    /// (components/sources.json pins Nightforge's download to the same).
    static let finishedVersion = "3.0"

    /// A pre-release: "4.0b3", "4.0 beta 3".
    static func isBeta(_ version: String) -> Bool {
        version.range(of: #"(?i)((beta|alpha|rc) ?\d*|\d[ab]\d+)$"#, options: .regularExpression) != nil
    }

    /// For people: "4.0b3" is "4.0 beta 3".
    static func displayVersion(_ version: String) -> String {
        version.replacingOccurrences(of: #"(\d)b(\d+)$"#, with: "$1 beta $2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)a(\d+)$"#, with: "$1 alpha $2", options: .regularExpression)
    }

    /// Takes the answer, the imported toolkits and the copies Nightforge downloaded away: no copy of
    /// Apple's D3DMetal is left in Nightforge's own places (the engine's is `Engine.removeD3DMetal`).
    static func removeAll(componentsRoot: URL, folder: URL = D3DMetalSupply.folder) {
        let fm = FileManager.default
        try? fm.removeItem(at: componentsRoot.appendingPathComponent(Engine.d3dMetalID, isDirectory: true))
        try? fm.removeItem(at: importedFolder(in: folder))
        forget(in: folder)
    }

    /// The imported toolkits but the one in use: an import that has taken over leaves the older ones no use.
    static func pruneImports(keeping version: String?, in folder: URL = D3DMetalSupply.folder) {
        let fm = FileManager.default
        let imported = importedFolder(in: folder)
        for old in (try? fm.contentsOfDirectory(atPath: imported.path)) ?? [] where old != version {
            try? fm.removeItem(at: imported.appendingPathComponent(old))
        }
    }

    /// Nightforge's download is on offer: the component list has a D3DMetal (a final one; the list
    /// leaves it out while there is none).
    static func canDownload(_ manifest: ComponentManifest?) -> Bool {
        manifest?.component(Engine.d3dMetalID) != nil
    }

    /// A game that can't draw without D3DMetal: DirectX 12 and nothing else, or the player picked it
    /// for the game, or its profile names it for a game with a DirectX 12 program of its own
    /// (Control: its DirectX 11 program crashes on DXMT and DXVK). A profile that only prefers it
    /// for a game that draws both with one program isn't asked about: that game runs without.
    /// `game`: one on `needsRosettaLibrary` needs Apple's files whatever it draws with.
    static func needed(by analysis: GameAnalysis?, picked: GraphicsLayer, profile: GameProfile? = nil, game: GameID? = nil) -> Bool {
        game.map(needsRosettaLibrary.contains) == true || picked == .d3dmetal || analysis?.onlyD3D12 == true
            || (analysis?.d3d12Program != nil && profile?.graphics == .d3dmetal)
    }

    /// Games that hang at the start without CX_APPLEGPTK_LIBD3DSHARED_PATH (Engine.environment), even on
    /// DXMT: the variable names Apple's libd3dshared.dylib, which comes with D3DMetal. Overwatch through
    /// Steam (7.11.); without D3DMetal set up it would hang with no window and no question.
    static let needsRosettaLibrary: Set<GameID> = [.steam(2_357_570)]

    // MARK: Importing Apple's toolkit

    /// Apple's toolkit as it lies on a disk image or in a folder: `redist/lib` with external/ (the
    /// framework and libd3dshared.dylib) and wine/ (the Windows front ends), and the notices beside redist/.
    struct Toolkit: Equatable {
        let lib: URL
        let notices: [URL]
    }

    static let noticeNames = ["License.rtf", "Acknowledgements.rtf", "Read Me.rtf"]

    static func findToolkit(in root: URL, maxDepth: Int = 5) -> Toolkit? {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsPackageDescendants]) else { return nil }
        for case let url as URL in files {
            if files.level > maxDepth { files.skipDescendants(); continue }
            guard url.lastPathComponent == "lib", url.deletingLastPathComponent().lastPathComponent == "redist",
                  fm.fileExists(atPath: url.appendingPathComponent("external/libd3dshared.dylib").path),
                  fm.fileExists(atPath: url.appendingPathComponent("external/D3DMetal.framework").path),
                  fm.fileExists(atPath: url.appendingPathComponent("wine/x86_64-windows/d3d12.dll").path)
            else { continue }
            let toolkit = url.deletingLastPathComponent().deletingLastPathComponent()
            return Toolkit(lib: url, notices: noticeNames.map { toolkit.appendingPathComponent($0) }
                .filter { fm.fileExists(atPath: $0.path) })
        }
        return nil
    }

    /// The framework's version ("3.0", "4.0b3"), as the package script reads it; a plain name only,
    /// since it becomes a folder's.
    static func version(ofFramework framework: URL) -> String? {
        for path in ["Versions/A/Resources/Info.plist", "Resources/Info.plist", "Info.plist"] {
            if let info = NSDictionary(contentsOf: framework.appendingPathComponent(path)),
               let version = info["CFBundleShortVersionString"] as? String, isPlainVersion(version) {
                return version
            }
        }
        return nil
    }

    static func isPlainVersion(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32 && !text.hasPrefix(".")
            && text.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "._+-".unicodeScalars.contains($0) }
    }

    /// The Windows front ends of each version of Apple's toolkit, by SHA-256. They run in every DirectX
    /// 11 and 12 game, and Apple signs only the framework and libd3dshared.dylib – not these, nor its
    /// disk images – so a toolkit is imported only with exactly these files. Taken from Apple's images
    /// (Game_Porting_Toolkit_3.0.dmg, Game_Porting_Toolkit_4.0_beta_3.dmg) with
    /// `shasum -a 256 redist/lib/wine/x86_64-windows/*.dll`; a new version of the toolkit needs its list here.
    static let windowsFiles: [String: [String: String]] = [
        "3.0": [
            "atidxx64.dll": "bd004dd9e41415b0e1395d51a2ded762a02c7731491e74ed6076f3648ae9ea7f",
            "d3d10.dll": "d316848cc78301829e6031b60c6f558716cdc74c440df72935968160253c03a5",
            "d3d11.dll": "05fa6f700fb5ee5561dc3a46d98f0aed845d4fa8ab274bff1dc604b0b3f6edd1",
            "d3d12.dll": "27dcf69bedb20ed557a83953e356ab2477b688c2a2c631f880b7583f30ff0705",
            "dxgi.dll": "249711d3d786a9b0bb7c3558f36e472ab07ee21b8dbf118e34c975046832f9a2",
            "nvapi64.dll": "8e1e6cde85551360d7a061a09445500f3c38805651502f3be65049d937c6960c",
            "nvngx-on-metalfx.dll": "d7c0df74d9bb4de5e2a3cc357b2309148fd3fdc824fe7941e4d789dbd072ff99",
        ],
        "4.0b3": [
            "d3d10.dll": "8509cd61f4e25e20fa6c4444b3dea062f026d672f441e82402702fa1faf6676b",
            "d3d11.dll": "a5de9738b3f89f1d8cdfb9103e82f9231ae543ce3c46134ed761c146a2f2d3e1",
            "d3d12.dll": "02aa673497ff8694b41f976e194a920468e54897f3546ed1cd4c1b3a97179735",
            "d3d12core.dll": "1034f5989c8c69496add15f79c04e56ae47cdf2a861098e8b4323bc8835b9e29",
            "dxgi.dll": "124015390b8527033bcd6e65af6376fde8fb3923450b63a9dbe0bbef05e63f10",
            "nvapi64.dll": "60ceaeb697b5141702c372da33861f499931397b43febb9be9f087f18276d772",
            "nvngx-on-metalfx.dll": "2e522873d2dec412c29f73096f1c1dc6bd8016dc40fd76fbeddd2eb7e226d3cb",
        ],
    ]

    /// A toolkit's lib/ as Apple ships `version`, and nothing else in it: external/ holds the framework and
    /// libd3dshared.dylib (their signature is checked apart), wine/x86_64-windows exactly the version's
    /// front ends as plain files, byte for byte, and wine/x86_64-unix only their halves (the engine makes
    /// its own links for those). A file more could become a front end, a link could change after the check.
    static func checkWindowsFiles(in lib: URL, version: String, known: [String: [String: String]] = windowsFiles) throws {
        guard let expected = known[version] else { throw Failure.unknownVersion(version) }
        let fm = FileManager.default
        func names(_ path: String) -> Set<String> {
            Set(((try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent(path).path)) ?? []).filter { $0 != ".DS_Store" })
        }
        func type(_ path: String) -> FileAttributeType? {
            (try? fm.attributesOfItem(atPath: lib.appendingPathComponent(path).path))?[.type] as? FileAttributeType
        }
        let halves = Set(expected.keys.map { ($0 as NSString).deletingPathExtension + ".so" })
        guard names("") == ["external", "wine"],
              names("external") == ["D3DMetal.framework", "libd3dshared.dylib"],
              type("external/D3DMetal.framework") == .typeDirectory, type("external/libd3dshared.dylib") == .typeRegular,
              names("wine").isSubset(of: ["x86_64-windows", "x86_64-unix"]),
              names("wine/x86_64-windows") == Set(expected.keys),
              names("wine/x86_64-unix").isSubset(of: halves),
              expected.allSatisfy({ name, sha256 in
                  let path = "wine/x86_64-windows/" + name
                  return type(path) == .typeRegular && (try? ComponentStore.sha256(of: lib.appendingPathComponent(path))) == sha256
              })
        else { throw Failure.changed(version) }
    }

    /// Copies Apple's D3DMetal out of `root` (a disk image's contents, or a folder) into
    /// `folder/Apple/<version>`, byte for byte, with Apple's notices. Only what Apple signed and the
    /// Windows files of a known version are taken (`checkWindowsFiles`), checked at the source and
    /// again on the copy. Returns the version.
    static func importToolkit(from root: URL, into folder: URL = D3DMetalSupply.folder,
                              verify: (URL) -> Bool = Engine.isAppleSigned,
                              known: [String: [String: String]] = D3DMetalSupply.windowsFiles) throws -> String {
        let fm = FileManager.default
        guard let toolkit = findToolkit(in: root) else { throw Failure.notAToolkit }
        let external = toolkit.lib.appendingPathComponent("external", isDirectory: true)
        let codes = ["libd3dshared.dylib", "D3DMetal.framework"]
        guard let version = version(ofFramework: external.appendingPathComponent("D3DMetal.framework")) else { throw Failure.notAToolkit }
        guard codes.allSatisfy({ verify(external.appendingPathComponent($0)) }) else { throw Failure.notSignedByApple }
        try checkWindowsFiles(in: toolkit.lib, version: version, known: known)

        let imported = importedFolder(in: folder)
        let staging = imported.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            // A copy keeps links as links (the unix halves of Apple's front ends are links).
            try fm.copyItem(at: toolkit.lib, to: staging.appendingPathComponent("lib", isDirectory: true))
            for notice in toolkit.notices { try fm.copyItem(at: notice, to: staging.appendingPathComponent(notice.lastPathComponent)) }
        } catch {
            throw Failure.copyFailed
        }
        let copied = staging.appendingPathComponent("lib/external", isDirectory: true)
        guard codes.allSatisfy({ verify(copied.appendingPathComponent($0)) }) else { throw Failure.notSignedByApple }
        try checkWindowsFiles(in: staging.appendingPathComponent("lib", isDirectory: true), version: version, known: known)

        let target = imported.appendingPathComponent(version, isDirectory: true)
        do {
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
        } catch {
            throw Failure.copyFailed
        }
        return version
    }

    /// Opens a downloaded disk image read-only (not shown in Finder), imports from it – the image
    /// inside it too, where Apple nests one – and closes it again.
    static func importDiskImage(_ image: URL, into folder: URL = D3DMetalSupply.folder,
                                verify: (URL) -> Bool = Engine.isAppleSigned,
                                known: [String: [String: String]] = D3DMetalSupply.windowsFiles) throws -> String {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-d3dmetal-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let outer = work.appendingPathComponent("image", isDirectory: true)
        try? fm.createDirectory(at: outer, withIntermediateDirectories: true)
        guard attach(image, at: outer) else { throw Failure.cannotOpen }
        defer { detach(outer) }

        if findToolkit(in: outer) != nil { return try importToolkit(from: outer, into: folder, verify: verify, known: known) }
        for (index, inner) in diskImages(in: outer).enumerated() {
            let mountpoint = work.appendingPathComponent("inner\(index)", isDirectory: true)
            try? fm.createDirectory(at: mountpoint, withIntermediateDirectories: true)
            guard attach(inner, at: mountpoint) else { continue }
            defer { detach(mountpoint) }
            if findToolkit(in: mountpoint) != nil { return try importToolkit(from: mountpoint, into: folder, verify: verify, known: known) }
        }
        throw Failure.notAToolkit
    }

    /// The disk images lying in a mounted one (a few levels down, a few at most).
    static func diskImages(in root: URL, maxDepth: Int = 3, limit: Int = 4) -> [URL] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                         options: [.skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in files {
            if files.level > maxDepth { files.skipDescendants(); continue }
            if url.pathExtension.lowercased() == "dmg" { found.append(url) }
            if found.count == limit { break }
        }
        return found
    }

    private static func attach(_ image: URL, at mountpoint: URL) -> Bool {
        // No Finder window, no write access, no prompt (an image asking to agree to a licence fails).
        run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-quiet",
                                 "-mountpoint", mountpoint.path, image.path])
    }

    private static func detach(_ mountpoint: URL) {
        if !run("/usr/bin/hdiutil", ["detach", "-quiet", mountpoint.path]) {
            _ = run("/usr/bin/hdiutil", ["detach", "-force", "-quiet", mountpoint.path])
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: Waiting for Apple's download

    /// Names the toolkit's downloads go by (Game_Porting_Toolkit_3.0.dmg, Evaluation_environment_for_Windows_games_3.0.dmg).
    static let downloadNames = ["game_porting", "game porting", "game-porting", "gptk", "evaluation_environment",
                                "evaluation environment", "d3dmetal"]

    /// A finished download of the toolkit in `folder` that came after `since` (a partial one has
    /// another ending until the browser is done), the newest if several.
    static func newToolkitDownload(in folder: URL, since: Date) -> URL? {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        func touched(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: keys)
            return max(values?.creationDate ?? .distantPast, values?.contentModificationDate ?? .distantPast)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return files.filter { file in
            let name = file.lastPathComponent.lowercased()
            return file.pathExtension.lowercased() == "dmg" && downloadNames.contains { name.contains($0) } && touched(file) >= since
        }.max { touched($0) < touched($1) }
    }

    /// Waits for the toolkit to arrive in `folder`; nil when the time is up or the task is cancelled.
    /// A file counts once its size has stopped changing.
    static func waitForToolkit(in folder: URL, since: Date, timeout: TimeInterval = 30 * 60,
                               poll: TimeInterval = 2) async -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSize: [URL: Int] = [:]
        while Date() < deadline, !Task.isCancelled {
            if let file = newToolkitDownload(in: folder, since: since),
               let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                if lastSize[file] == size { return file }
                lastSize[file] = size
            }
            try? await Task.sleep(for: .seconds(poll))
        }
        return nil
    }
}
