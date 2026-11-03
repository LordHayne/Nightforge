import AppKit
import Foundation

/// A newer Nightforge release on GitHub.
struct AppUpdate: Equatable {
    let version: String
    let archive: URL
    /// The zip's Ed25519 signature (`Nightforge-<version>.zip.sig`), see `Signature`.
    let signature: URL
    let page: URL
}

/// Keeps Nightforge itself current: one look at the newest GitHub release per app start, and a
/// one-click install that downloads the zip, checks it against the maintainer's signature, swaps the
/// app and restarts it.
enum Updater {
    private static let releases = "https://api.github.com/repos/LordHayne/Nightforge/releases/"

    /// Names a test release for this Mac to update to (docs/SICHERHEIT-0.3.md › Test-Release):
    /// `defaults write io.github.lordhayne.nightforge UpdateTestRelease v0.3.1-rc.2`. Test releases
    /// are prereleases, which the newest-release address leaves out, so no one else is offered them.
    /// The signature counts for them as for any release.
    static let testReleaseKey = "UpdateTestRelease"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The newest release, or the test release this Mac is set to.
    static func releaseURL(testRelease: String? = UserDefaults.standard.string(forKey: testReleaseKey)) -> URL {
        if let tag = testRelease, !tag.isEmpty, tag.count <= 64,
           tag.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) }) {
            return URL(string: releases + "tags/" + tag)!
        }
        return URL(string: releases + "latest")!
    }

    /// The newest release when it's newer than this copy, else nil (also when offline).
    static func check() async -> AppUpdate? {
        var request = URLRequest(url: releaseURL())
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return release(from: data)
    }

    /// The release in a GitHub API answer when it's newer than `current`. One without the zip's
    /// signature isn't offered: it couldn't be installed (from 0.3.1 on, every release is signed
    /// before it's published).
    static func release(from data: Data, newerThan current: String = currentVersion) -> AppUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        let addresses = assets.compactMap { $0["browser_download_url"] as? String }
        guard let zip = addresses.first(where: { $0.hasSuffix(".zip") && $0.contains("Nightforge-") }),
              let archive = URL(string: zip)
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: current) else { return nil }
        guard addresses.contains(zip + ".sig"), let signature = URL(string: zip + ".sig") else {
            GameLog.note("Nightforge \(version) has no signature (\(archive.lastPathComponent).sig), so it isn't offered")
            return nil
        }
        return AppUpdate(version: version, archive: archive, signature: signature, page: page)
    }

    /// "0.2.0" > "0.1.10" > "0.1.4"; a version with a suffix ("0.2.0-dev") comes before the plain one,
    /// and of two with a suffix the later one counts ("0.3.1-rc.10" > "0.3.1-rc.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func split(_ version: String) -> (numbers: [Int], suffix: String?) {
            let parts = version.split(separator: "-", maxSplits: 1)
            return ((parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }, parts.count > 1 ? String(parts[1]) : nil)
        }
        let (a, aSuffix) = split(candidate)
        let (b, bSuffix) = split(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        switch (aSuffix, bSuffix) {
        case let (ours?, theirs?): return ours.compare(theirs, options: .numeric) == .orderedDescending
        case (nil, _?): return true
        default: return false
        }
    }

    enum Failure: LocalizedError {
        case download, unpack, signature, notWritable, protectedPlace
        /// The zip holds a Nightforge no newer than this one: an older signed release passed off as new.
        case notNewer
        /// The zip holds another version than its release names: a signed zip put under another tag.
        case otherVersion(found: String, named: String)
        /// The new version needs a newer macOS than this Mac has: it would not open after the swap.
        case needsNewerMac(required: String)

        var errorDescription: String? {
            switch self {
            case .download: return L10n.t("The update could not be downloaded. Check your internet connection.")
            case .unpack: return L10n.t("The update download is damaged. Please try again.")
            case .signature: return L10n.t("The update isn't signed correctly, so it wasn't installed.")
            case .notNewer: return L10n.t("The update holds an older Nightforge than the one you have, so it wasn't installed.")
            case .otherVersion(let found, let named):
                return L10n.t("The update says it's Nightforge %@ but holds %@, so it wasn't installed.", named, found)
            case .notWritable: return L10n.t("Nightforge can't replace itself in this folder. Download the update from the release page instead.")
            case .needsNewerMac(let required):
                let running = ProcessInfo.processInfo.operatingSystemVersion
                return L10n.t("This version of Nightforge needs macOS %@ or newer, and this Mac runs macOS %@. Nightforge stays on the version you have.",
                              required.hasSuffix(".0") ? String(required.dropLast(2)) : required, "\(running.majorVersion).\(running.minorVersion)")
            case .protectedPlace:
                return L10n.t("Nightforge runs from a protected place (macOS does that to an app opened straight from a download or a disk image), so it can't update itself. Drag Nightforge into the Applications folder, open it from there and update again.")
            }
        }
    }

    /// macOS starts an app that was opened straight from its download or a disk image from a read-only
    /// copy (App Translocation, …/AppTranslocation/<id>/d/Nightforge.app) or from the read-only image
    /// itself. Neither can be replaced, and the release page is no help: the app has to move first.
    static func runsFromProtectedPlace(_ app: URL) -> Bool {
        isTranslocated(app.path) || (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    static func isTranslocated(_ path: String) -> Bool { path.contains("/AppTranslocation/") }

    /// Whether a macOS older than `minimum` ("26.0", an app's LSMinimumSystemVersion) is what runs.
    static func needsNewerMac(minimum: String?, running: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard let minimum else { return false }
        let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        let needed = (parts.first ?? 0, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0)
        return needed > (running.majorVersion, running.minorVersion, running.patchVersion)
    }

    /// Downloads and installs `update` over the running app, then restarts it.
    static func install(_ update: AppUpdate) async throws {
        let fm = FileManager.default
        let app = Bundle.main.bundleURL
        guard !runsFromProtectedPlace(app) else { throw Failure.protectedPlace }
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else { throw Failure.notWritable }

        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        guard let (signature, signatureResponse) = try? await URLSession.shared.data(from: update.signature),
              (signatureResponse as? HTTPURLResponse)?.statusCode == 200,
              let (download, response) = try? await URLSession.shared.download(from: update.archive),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { throw Failure.download }
        let zip = work.appendingPathComponent("Nightforge.zip")
        try fm.moveItem(at: download, to: zip)
        // Nothing of the download is opened before the maintainer's signature holds for it.
        guard isSigned(zip, signature: signature) else {
            GameLog.note("The download of Nightforge \(update.version) doesn't match its signature: not installed")
            throw Failure.signature
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else { throw Failure.unpack }
        let fresh = unpacked.appendingPathComponent("Nightforge.app", isDirectory: true)
        guard Bundle(url: fresh)?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw Failure.unpack }
        let freshVersion = Bundle(url: fresh)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        try Self.check(freshVersion, named: update.version)
        // Ad hoc signed (build.sh): this shows the bundle arrived whole. Who built it, the Ed25519
        // signature above says; a requirement (-R) needs a Developer ID.
        guard run("/usr/bin/codesign", ["--verify", "--deep", fresh.path]) else { throw Failure.signature }
        // A release that raises the macOS it needs would not open after the swap: this copy stays.
        let minimum = Bundle(url: fresh)?.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        if needsNewerMac(minimum: minimum) { throw Failure.needsNewerMac(required: minimum ?? "") }

        // Swap in one step; the running copy keeps working from memory until the restart.
        _ = try fm.replaceItemAt(app, withItemAt: fresh)
        // Detached, or this Nightforge would stay in the Dock beside the new one while it waits; it
        // opens the new one once this one is gone (opened before, it would only bring this one up).
        let relaunch = DetachedProcess()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", #"for i in $(seq 1 50); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done; /usr/bin/open "$0""#,
                              app.path, String(getpid())]
        try relaunch.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    /// The version in the downloaded app against its release. Older releases are signed too: one passed
    /// off as new would take back its fixes, and a signed zip under another tag (an old one as "v9.9.9")
    /// would hold the update back. So it has to be exactly the version its release names (review C).
    static func check(_ found: String, named: String, current: String = currentVersion) throws {
        guard found == named else { throw Failure.otherVersion(found: found, named: named) }
        guard isNewer(found, than: current) else { throw Failure.notNewer }
    }

    /// Whether `signature` (the `.sig` file's text) holds for the downloaded zip.
    static func isSigned(_ zip: URL, signature: Data, keys: [String] = SigningKeys.trusted) -> Bool {
        guard let data = try? Data(contentsOf: zip, options: .mappedIfSafe) else { return false }
        return Signature.isValid(signature, of: data, keys: keys)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
