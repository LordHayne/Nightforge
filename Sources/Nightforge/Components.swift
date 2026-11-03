import CryptoKit
import Foundation

/// One downloadable building block (Wine engine, graphics layer, tool) from components/manifest.json.
struct Component: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case engine, graphics, tool
    }

    let id: String
    let kind: Kind
    let version: String
    let url: URL
    let sha256: String
    let size: Int64
    let license: String
    let source: URL

    /// id, version and the file name become paths under Application Support and the url is
    /// downloaded: a changed list may not point them elsewhere (`..`) or at a plain-HTTP or local file.
    var isSafeToInstall: Bool {
        func plainName(_ text: String) -> Bool {
            !text.isEmpty && !text.hasPrefix(".") && text.count <= 128
                && text.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "._+-".unicodeScalars.contains($0) }
        }
        return url.scheme == "https" && plainName(id) && plainName(version) && plainName(url.lastPathComponent)
    }
}

struct ComponentManifest: Codable {
    static let supportedSchema = 1

    let schemaVersion: Int
    let generated: String
    let components: [Component]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generated, components
    }

    /// One entry this version doesn't understand (a new kind, a changed field) or can't install safely
    /// is left out; the rest of the list still counts.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generated = (try? container.decode(String.self, forKey: .generated)) ?? ""
        components = try container.decode([Lenient<Component>].self, forKey: .components)
            .compactMap(\.value).filter(\.isSafeToInstall)
    }

    func component(_ id: String) -> Component? {
        components.first { $0.id == id }
    }
}

/// A list element that decodes to nil instead of failing the whole list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum ComponentError: LocalizedError {
    case unsupportedSchema(Int)
    case noManifest
    case checksumMismatch(String)
    case extractFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return L10n.t("Component list version %ld needs a newer Nightforge.", version)
        case .noManifest:
            return L10n.t("No component list available. Check your internet connection.")
        case .checksumMismatch(let id):
            return L10n.t("The download of %@ is damaged. Please try again.", id)
        case .extractFailed(let id, let status):
            return L10n.t("%@ could not be unpacked (tar exit %d).", id, status)
        }
    }
}

/// Downloads, verifies and unpacks components into Application Support.
///
/// The manifest comes from `NightforgeManifestURL` in Info.plist when set, falls back to the last
/// copy that was fetched, and finally to the one bundled with the app, so a fresh install works offline.
/// An online copy counts only with the maintainer's signature (`Signature`), and is kept with it: a
/// cached copy without one (fetched by 0.3.0, or changed on disk) is passed over for the bundled one.
actor ComponentStore {
    static let shared = ComponentStore()

    let root: URL
    private let remoteManifestURL: URL?
    private let bundledManifestURL: URL?
    private let keys: [String]

    /// `keys`: the public keys a signature must come from; a test hands in its own.
    init(
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Components", isDirectory: true),
        remoteManifestURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "NightforgeManifestURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) },
        bundledManifestURL: URL? = Bundle.main.url(forResource: "manifest", withExtension: "json"),
        keys: [String] = SigningKeys.trusted
    ) {
        self.root = root
        self.remoteManifestURL = remoteManifestURL
        self.bundledManifestURL = bundledManifestURL
        self.keys = keys
    }

    private var cachedManifestURL: URL { root.appendingPathComponent("manifest.json") }
    /// The online list is fetched once per app run. Asking again for every engine lookup would
    /// make each launch wait for the network – up to a minute when offline.
    private var fetched: ComponentManifest?
    private var triedRemote = false
    private var installing: [String: Task<URL, Error>] = [:]
    /// Whether the list `manifest()` gave last carries the maintainer's signature (online, or the copy
    /// kept with its .sig) rather than being only the app's own. Only then may installed components it
    /// doesn't name go (`Engine.removeUnusedComponents`): with the online list turned away and 0.3.0's
    /// unsigned copy not counting, the app's list can be older and would take a newer engine away.
    private(set) var manifestIsSigned = false

    func manifest() async throws -> ComponentManifest {
        if let fetched { return fetched }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if !triedRemote, let remote = remoteManifestURL {
            triedRemote = true
            switch await Signature.fetch(remote, keys: keys) {
            case .signed(let data, let signature):
                SignedLists.note(SignedLists.components, refused: false)
                // Older than the list kept: an earlier one put back. The kept one stays (below).
                let older = SignedLists.isOlder(data, than: Signature.signedContents(of: cachedManifestURL, keys: keys))
                SignedLists.note(SignedLists.components, older: older)
                // Older than the app's own list just means an app newer than main's list: its own counts
                // (below), as with the profiles (review N6).
                let olderThanOwn = SignedLists.isOlder(data, than: bundledManifestURL.flatMap { try? Data(contentsOf: $0) })
                if !older, !olderThanOwn, let manifest = try? decode(data) {
                    try? data.write(to: cachedManifestURL, options: .atomic)
                    try? signature.write(to: Signature.file(for: cachedManifestURL), options: .atomic)
                    fetched = manifest
                    manifestIsSigned = true
                    return manifest
                }
            case .refused:
                SignedLists.note(SignedLists.components, refused: true)
            case .unavailable:
                break
            }
        }
        // The newer of the kept copy and the app's own first, by their stamps; a damaged or too-new one
        // mustn't hide the other.
        var failure: Error = ComponentError.noManifest
        for (data, signed) in Self.newerFirst(kept: Signature.signedContents(of: cachedManifestURL, keys: keys),
                                              own: bundledManifestURL.flatMap { try? Data(contentsOf: $0) }) {
            guard let data else { continue }
            do {
                let manifest = try decode(data)
                manifestIsSigned = signed
                return manifest
            } catch {
                failure = error
            }
        }
        throw failure
    }

    /// The list at hand without asking the network (Settings › About): the last one fetched (with its
    /// signature), else the one bundled with the app.
    static func localManifest(keys: [String] = SigningKeys.trusted) -> ComponentManifest? {
        let cached = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Components/manifest.json")
        for (data, _) in newerFirst(kept: Signature.signedContents(of: cached, keys: keys),
                                    own: Bundle.main.url(forResource: "manifest", withExtension: "json").flatMap { try? Data(contentsOf: $0) }) {
            if let data, let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: data) {
                return manifest
            }
        }
        return nil
    }

    /// The kept, signed list and the app's own, the newer first (the kept one when they're alike);
    /// with it whether it's the signed one.
    static func newerFirst(kept: Data?, own: Data?) -> [(Data?, Bool)] {
        kept.map { SignedLists.isOlder($0, than: own) } == true ? [(own, false), (kept, true)] : [(kept, true), (own, false)]
    }

    /// The list that came with the app. A component it names that the online list doesn't yet (an
    /// app newer than the list) is taken from here.
    static func bundledManifest() -> ComponentManifest? {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ComponentManifest.self, from: data)
    }

    private func decode(_ data: Data) throws -> ComponentManifest {
        let manifest = try JSONDecoder().decode(ComponentManifest.self, from: data)
        guard manifest.schemaVersion <= ComponentManifest.supportedSchema else {
            throw ComponentError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }

    /// Folder of an installed component, or nil when this exact version isn't installed yet.
    func installedPath(for component: Component) -> URL? {
        let dir = directory(for: component)
        let marker = dir.appendingPathComponent(".sha256")
        guard (try? String(contentsOf: marker, encoding: .utf8)) == component.sha256 else { return nil }
        return dir
    }

    /// Installs `component` unless it's already there. `progress` reports 0...1 while downloading.
    /// A second request for the same component while it downloads waits for that download.
    func install(_ component: Component, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let dir = installedPath(for: component) { return dir }
        let key = "\(component.id)@\(component.version)"
        if let running = installing[key] { return try await running.value }
        let task = Task { try await self.download(component, progress: progress) }
        installing[key] = task
        defer { installing[key] = nil }
        return try await task.value
    }

    private func download(_ component: Component, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {

        let fm = FileManager.default
        let downloads = root.appendingPathComponent(".downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let archive = downloads.appendingPathComponent(component.url.lastPathComponent)
        try? fm.removeItem(at: archive)

        try await Downloader.download(component.url, to: archive, expectedSize: component.size, progress: progress)
        defer { try? fm.removeItem(at: archive) }

        guard try Self.sha256(of: archive) == component.sha256 else {
            throw ComponentError.checksumMismatch(component.id)
        }

        // Unpack into a staging folder first so a half-extracted component is never picked up.
        let dir = directory(for: component)
        let staging = downloads.appendingPathComponent("\(component.id)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        if Self.isArchive(archive) {
            let status = try Self.untar(archive, into: staging)
            guard status == 0 else { throw ComponentError.extractFailed(component.id, status) }
        } else {
            let file = staging.appendingPathComponent(archive.lastPathComponent)
            try fm.copyItem(at: archive, to: file)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }

        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: dir)
        try component.sha256.write(to: dir.appendingPathComponent(".sha256"), atomically: true, encoding: .utf8)
        progress(1)
        return dir
    }

    private func directory(for component: Component) -> URL {
        root.appendingPathComponent(component.id, isDirectory: true)
            .appendingPathComponent(component.version, isDirectory: true)
    }

    /// Copies a folder as an APFS clone: instant, and it takes space only for what later changes in
    /// either copy. Elsewhere (another file system) an ordinary copy.
    static func cloneFolder(_ source: URL, to target: URL) throws {
        if clonefile(source.path, target.path, 0) == 0 { return }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func isArchive(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        return [".tar.gz", ".tgz", ".tar.xz", ".tar.zst", ".tar"].contains { name.hasSuffix($0) }
    }

    private static func untar(_ archive: URL, into dir: URL) throws -> Int32 {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", dir.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        return tar.terminationStatus
    }
}

/// URLSession download with progress, written to a fixed destination. Cancelling the task that
/// awaits it ends the download (SteamPrefetch hands what's left to Steam that way).
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    private init(destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    static func download(_ url: URL, to destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) async throws {
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }
        let delegate = Downloader(destination: destination, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                let task = session.downloadTask(with: url)
                let go = delegate.lock.withLock { () -> Bool in
                    guard !delegate.cancelled else { return false }
                    delegate.task = task
                    return true
                }
                if go {
                    task.resume()
                } else {
                    delegate.continuation = nil
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            delegate.lock.withLock { () -> URLSessionDownloadTask? in
                delegate.cancelled = true
                return delegate.task
            }?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        let expected = total > 0 ? total : expectedSize
        if expected > 0 { progress(min(Double(written) / Double(expected), 1)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        do {
            guard status == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
