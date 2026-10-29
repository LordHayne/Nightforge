import Foundation

/// Steam's first start downloads its client twice while nothing else happens: the old
/// bootstrapper SteamSetup installs fetches the 32-bit step (19 packages, ~250 MB), the one that
/// step brings fetches the 64-bit client (14 more, ~230 MB) – about 13 s each in the live run of
/// 29.10.2026. The same packages come down while wineboot builds Windows (SteamPrefetch) and go
/// where the bootstrapper looks for them: a file in Steam's package folder with the right name
/// and size isn't fetched again ("Package file … missing or incorrect size" names only the
/// others). In a scratch prefix (29.10.2026) neither step had anything left to fetch. Whatever
/// doesn't fit – a newer manifest by the time Steam asks, a variant Steam picks differently, a
/// download that failed – Steam fetches itself, as before.
enum SteamPackages {
    struct Package: Equatable, Sendable {
        let name: String
        let size: Int64
        /// SHA-256 from the manifest, where it has one.
        let sha256: String?
    }

    /// The two steps of Steam's first update, in order, and where each bootstrapper fetches from
    /// (its bootstrap_log.txt: "Downloading manifest: …", "Add pending download: …").
    enum Client: String, CaseIterable, Sendable {
        case win32, win64

        var server: URL {
            switch self {
            case .win32: return URL(string: "https://cdn.steamstatic.com/client/")!
            case .win64: return URL(string: "https://client-update.steamstatic.com/")!
            }
        }

        var manifest: URL { server.appendingPathComponent("steam_client_" + rawValue) }
    }

    /// The packages a client manifest names, as the bootstrapper picks them under Nightforge's
    /// Wine: of a package with a variant for 64-bit Windows ("win7-64") both – it asked for that
    /// one alone in one live run and for both in the next (29.10.2026, 21:35 and 23:27) – of one
    /// with variants by realm the global one ("steamrow"); its compressed file ("zipvz", its size
    /// after the last "_") where there is one. Nothing usable: empty.
    static func packages(manifest text: String) -> [Package] {
        guard let root = VDF.parse(text)?.object,
              let client = root.first(where: { $0.key.hasPrefix("win") })?.value.object
        else { return [] }
        return client.keys.sorted().flatMap { key -> [Package] in
            guard let entry = client[key]?.object else { return [] }  // "version", "ostype"
            if let realm = entry["steamrow"]?.object { return package(realm).map { [$0] } ?? [] }
            return ([entry] + (entry["win7-64"]?.object.map { [$0] } ?? [])).compactMap(package)
        }
    }

    private static func package(_ fields: [String: VDF]) -> Package? {
        let package: Package
        if let vz = fields["zipvz"]?.string, let size = vz.split(separator: "_").last.flatMap({ Int64($0) }) {
            package = Package(name: vz, size: size, sha256: fields["sha2vz"]?.string)
        } else if let file = fields["file"]?.string, let size = fields["size"]?.string.flatMap({ Int64($0) }) {
            package = Package(name: file, size: size, sha256: fields["sha2"]?.string)
        } else {
            return nil
        }
        // A file name, nothing that leads out of the folder it goes into.
        guard !package.name.isEmpty, !package.name.contains("/"), !package.name.contains("\\"),
              !package.name.hasPrefix("."), package.size > 0 else { return nil }
        return package
    }
}

/// The downloads ahead of Steam, from the environment step on: Steam's installer, then the 32-bit
/// step's packages, then the 64-bit client's, each checked (size, SHA-256) and kept in `folder`
/// until the setup lays them into Steam's package folder – as hard links, so nothing is copied.
final class SteamPrefetch: @unchecked Sendable {
    static var defaultFolder: URL { Engine.supportDir.appendingPathComponent("Steam packages", isDirectory: true) }

    let folder: URL
    private let lock = NSLock()
    private var work: Task<Void, Never>?
    private var expected: [SteamPackages.Client: [SteamPackages.Package]] = [:]
    private var received: [String: Int64] = [:]
    private var over: Set<SteamPackages.Client> = []
    private var installerFile: URL?
    private var installerOver = false

    init(folder: URL = SteamPrefetch.defaultFolder) {
        self.folder = folder
    }

    /// Starts the downloads in the background.
    static func start(in folder: URL = defaultFolder) -> SteamPrefetch {
        let prefetch = SteamPrefetch(folder: folder)
        let work = Task.detached(priority: .utility) { await prefetch.fetchAll() }
        prefetch.lock.withLock { prefetch.work = work }
        return prefetch
    }

    /// Steam's installer once its download is over; nil when it failed (the setup fetches it itself then).
    func installer() async -> URL? {
        while !Task.isCancelled {
            if let file = lock.withLock({ installerOver ? Optional(installerFile) : nil }) { return file }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// How far `client`'s packages are: bytes in, bytes in all, and whether their downloads are
    /// over (all through, or given up).
    func progress(_ client: SteamPackages.Client) -> (done: Int64, total: Int64, over: Bool) {
        lock.withLock {
            let packages = expected[client] ?? []
            return (packages.reduce(0) { $0 + (received[$1.name] ?? 0) }, packages.reduce(0) { $0 + $1.size },
                    over.contains(client))
        }
    }

    /// Ends the downloads still under way; what came down stays for `place`. Steam fetches the rest.
    func stop() {
        lock.withLock { work }?.cancel()
    }

    /// Lays `client`'s finished packages into Steam's package folder as hard links. A file that's
    /// already there stays as it is, and one that can't be linked is left to Steam. Returns how
    /// many went in.
    @discardableResult
    func place(_ client: SteamPackages.Client, into package: URL) -> Int {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent(client.rawValue, isDirectory: true)
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        guard !names.isEmpty, (try? fm.createDirectory(at: package, withIntermediateDirectories: true)) != nil else { return 0 }
        return names.filter { name in
            guard !name.hasSuffix(".part") else { return false }
            return (try? fm.linkItem(at: dir.appendingPathComponent(name), to: package.appendingPathComponent(name))) != nil
        }.count
    }

    /// Ends the downloads and removes what's left of them (what went into Steam's folder stays there).
    func discard() {
        stop()
        try? FileManager.default.removeItem(at: folder)
    }

    private func fetchAll() async {
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let installer = folder.appendingPathComponent("SteamSetup.exe")
        let fetched = (try? await Downloader.download(Engine.steamSetupURL, to: installer, expectedSize: 0) { _ in }) != nil
        lock.withLock {
            installerFile = fetched ? installer : nil
            installerOver = true
        }
        for client in SteamPackages.Client.allCases { await fetch(client) }
    }

    private func fetch(_ client: SteamPackages.Client) async {
        defer { lock.withLock { _ = over.insert(client) } }
        guard !Task.isCancelled,
              let (data, response) = try? await URLSession.shared.data(from: client.manifest),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return }
        let packages = SteamPackages.packages(manifest: String(decoding: data, as: UTF8.self))
        let dir = folder.appendingPathComponent(client.rawValue, isDirectory: true)
        guard !packages.isEmpty, (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
        else { return }
        lock.withLock { expected[client] = packages }
        // Six at a time (Steam asks for all of them at once), the biggest first: it would hold Steam up longest.
        var queue = packages.sorted { $0.size > $1.size }.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                guard let package = queue.next() else { break }
                group.addTask { await self.download(package, from: client.server, into: dir) }
            }
            while await group.next() != nil {
                guard let package = queue.next() else { continue }
                group.addTask { await self.download(package, from: client.server, into: dir) }
            }
        }
    }

    private func download(_ package: SteamPackages.Package, from server: URL, into dir: URL) async {
        let fm = FileManager.default
        let partial = dir.appendingPathComponent(package.name + ".part")
        do {
            try? fm.removeItem(at: partial)
            try await Downloader.download(server.appendingPathComponent(package.name), to: partial, expectedSize: package.size) { fraction in
                self.lock.withLock { self.received[package.name] = Int64(fraction * Double(package.size)) }
            }
            let size = (try fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value
            let sha256 = try package.sha256.map { _ in try ComponentStore.sha256(of: partial) }
            guard size == package.size, sha256 == package.sha256?.lowercased() else { throw URLError(.cannotDecodeContentData) }
            try fm.moveItem(at: partial, to: dir.appendingPathComponent(package.name))
            lock.withLock { received[package.name] = package.size }
        } catch {
            try? fm.removeItem(at: partial)
            lock.withLock { received[package.name] = 0 }
        }
    }
}
