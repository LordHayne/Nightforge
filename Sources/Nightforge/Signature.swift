import CryptoKit
import Foundation

/// Ed25519 signatures (CryptoKit) over what Nightforge takes from the internet and acts on: the update
/// zip, components/manifest.json, profiles/profiles.json and profiles/agw.json. Each has a `.sig` file
/// beside it: one line per signature, the 64 bytes in base64, and one line that holds is enough (after
/// a key change a file carries the new key's signature and the spare's, for Macs that only know the
/// spare). Only the maintainer can make one (scripts/sign-release.sh, scripts/sign-lists.sh); GitHub
/// holds neither private key, so a taken-over account or workflow can change the files but not sign
/// them.
///
/// Self-contained (Foundation and CryptoKit only): scripts/signing-tool.swift is built from this file
/// and SigningKeys.swift, so the scripts check exactly what the app checks.
enum Signature {
    /// Whether `signature` (a `.sig` file's text) signs `data` with one of `keys`.
    static func isValid(_ signature: Data, of data: Data, keys: [String] = SigningKeys.trusted) -> Bool {
        signer(of: data, signature: signature, keys: keys) != nil
    }

    /// The key in `keys` that one of the lines of `signature` comes from, if any.
    static func signer(of data: Data, signature: Data, keys: [String]) -> String? {
        let publicKeys = keys.compactMap { key -> (String, Curve25519.Signing.PublicKey)? in
            guard let bytes = Data(base64Encoded: key),
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes)
            else { return nil }
            return (key, publicKey)
        }
        let lines = String(decoding: signature, as: UTF8.self).split(whereSeparator: \.isNewline).prefix(8)
        for line in lines {
            guard let raw = Data(base64Encoded: line.trimmingCharacters(in: .whitespaces)), raw.count == 64 else { continue }
            if let (key, _) = publicKeys.first(where: { $0.1.isValidSignature(raw, for: data) }) { return key }
        }
        return nil
    }

    /// Where the signature of `file` (a local file or a download address) lies: `manifest.json.sig`.
    static func file(for file: URL) -> URL { file.appendingPathExtension("sig") }

    /// A file on disk with its signature beside it, or nil when either is missing or they don't match.
    static func signedContents(of file: URL, keys: [String] = SigningKeys.trusted) -> Data? {
        guard let data = try? Data(contentsOf: file),
              let signature = try? Data(contentsOf: self.file(for: file)),
              isValid(signature, of: data, keys: keys)
        else { return nil }
        return data
    }

    enum Fetched {
        /// The file and the signature that holds for it, to keep both.
        case signed(Data, signature: Data)
        /// The file came, its signature didn't, or not one that holds.
        case refused
        /// Offline, or nothing at that address.
        case unavailable
    }

    /// How a download is made: URLSession's, or a test's slow or failing one.
    typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Downloads `url` and its `.sig` side by side.
    static func fetch(_ url: URL, keys: [String] = SigningKeys.trusted, timeout: TimeInterval = 15,
                      load: @escaping Load = { try await URLSession.shared.data(for: $0) }) async -> Fetched {
        async let file = download(url, timeout: timeout, load: load)
        async let signature = download(self.file(for: url), timeout: timeout, load: load)
        guard let data = await file else { return .unavailable }
        guard let signature = await signature, isValid(signature, of: data, keys: keys) else { return .refused }
        return .signed(data, signature: signature)
    }

    private static func download(_ url: URL, timeout: TimeInterval, load: Load) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData  // a fix published minutes ago should arrive
        guard let (data, response) = try? await load(request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 == 200
        else { return nil }
        return data
    }
}

/// The online lists turned away in this run for a missing or wrong signature, for the calm line in
/// Settings › About. Nightforge goes on with the list at hand: the last signed one, else its own.
enum SignedLists {
    static let components = "components"
    static let profiles = "profiles"
    static let agw = "agw"

    private static let lock = NSLock()
    private static var turnedAway: Set<String> = []
    private static var outdated: Set<String> = []

    static func note(_ list: String, refused: Bool) {
        lock.withLock {
            if refused { turnedAway.insert(list) } else { turnedAway.remove(list) }
        }
    }

    static var refused: Set<String> { lock.withLock { turnedAway } }

    /// A signed list older than the one at hand, turned away too: an earlier signed state put back
    /// by someone who can write the repository but can't sign (review M1).
    static func note(_ list: String, older: Bool) {
        lock.withLock {
            if older { outdated.insert(list) } else { outdated.remove(list) }
        }
    }

    static var older: Set<String> { lock.withLock { outdated } }

    /// Whether `fresh` was built before `kept`, by the "generated" stamp each list carries in its
    /// signed bytes (ISO 8601), compared as dates: a day alone is its midnight in UTC, an offset or a
    /// fraction of a second counts (review F); stamps that don't read as dates as text. One without a
    /// stamp is older than one with it; with no kept stamp nothing is older. The same stamp counts: a
    /// list signed again.
    /// A kept stamp more than two days ahead of `now` counts as none (review N5): one wrong clock or
    /// typo would otherwise turn away every right list after it until that day came.
    static func isOlder(_ fresh: Data, than kept: Data?, now: Date = Date()) -> Bool {
        guard let theirs = kept.flatMap(stamp), !theirs.isEmpty else { return false }
        let theirDate = date(of: theirs)
        if let theirDate, theirDate > now.addingTimeInterval(2 * 86_400) { return false }
        guard let ours = stamp(fresh) else { return true }
        if let ourDate = date(of: ours), let theirDate { return ourDate < theirDate }
        return ours < theirs
    }

    /// A stamp as a date: to the second ("2026-11-03T04:17:00Z", an offset too), with a fraction of a
    /// second, or the day ("2026-10-27").
    static func date(of stamp: String) -> Date? {
        let full = ISO8601DateFormatter()
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return full.date(from: stamp) ?? fraction.date(from: stamp) ?? day.date(from: stamp)
    }

    private static func stamp(_ data: Data) -> String? {
        struct Stamp: Decodable { let generated: String? }
        return (try? JSONDecoder().decode(Stamp.self, from: data))?.generated
    }
}
