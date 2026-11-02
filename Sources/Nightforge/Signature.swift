import CryptoKit
import Foundation

/// Ed25519 signatures (CryptoKit) over what Nightforge takes from the internet and acts on: the update
/// zip, components/manifest.json and profiles/profiles.json. Each has a `.sig` file beside it: one
/// line per signature, the 64 bytes in base64, and one line that holds is enough (after a key change a
/// file carries the new key's signature and the spare's, for Macs that only know the spare). Only the
/// maintainer can make one (scripts/sign-release.sh, scripts/sign-lists.sh); GitHub holds neither
/// private key, so a taken-over account or workflow can change the files but not sign them.
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

    /// Downloads `url` and its `.sig` side by side.
    static func fetch(_ url: URL, keys: [String] = SigningKeys.trusted) async -> Fetched {
        async let file = download(url)
        async let signature = download(self.file(for: url))
        guard let data = await file else { return .unavailable }
        guard let signature = await signature, isValid(signature, of: data, keys: keys) else { return .refused }
        return .signed(data, signature: signature)
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData  // a fix published minutes ago should arrive
        guard let (data, response) = try? await URLSession.shared.data(for: request),
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

    private static let lock = NSLock()
    private static var turnedAway: Set<String> = []

    static func note(_ list: String, refused: Bool) {
        lock.withLock {
            if refused { turnedAway.insert(list) } else { turnedAway.remove(list) }
        }
    }

    static var refused: Set<String> { lock.withLock { turnedAway } }
}
