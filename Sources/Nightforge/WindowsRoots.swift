import CryptoKit
import Foundation

/// Root certificates Windows trusts and macOS no longer carries. Wine takes its trusted roots from the
/// Mac's, so a signature that Windows accepts can count as untrusted here – and games check signatures:
/// Metal Gear Solid V verifies its steam_api64.dll (signed by Valve on 19.5.2015, up to VeriSign's
/// Class 3 root) and says "Failed to load SteamAPI" when that fails (WinVerifyTrust: 800b0109,
/// CERT_E_UNTRUSTEDROOT; 11.11.2026). Each root here goes into the prefix's own store, for the Windows
/// programs in it alone: nothing on the Mac or in its keychain changes. Only roots that Windows itself
/// carries, each held to its fingerprints. (The user's decision, 11.11.2026.)
enum WindowsRoots {
    struct Root {
        let name: String
        /// SHA-1 of the certificate, as Windows names it in the store: 40 hex digits, upper case.
        let sha1: String
        let sha256: String
        let base64: String

        var der: Data? { Data(base64Encoded: base64) }

        /// The certificate, if it is what its fingerprints say – a constant that no longer matches is left out.
        var verified: Data? {
            guard let der, WindowsRoots.hex(SHA256.hash(data: der)) == sha256, WindowsRoots.hex(Insecure.SHA1.hash(data: der)) == sha1
            else { return nil }
            return der
        }
    }

    /// VeriSign Class 3 Public Primary Certification Authority – G5 (2006–2036): the root under Valve's, and
    /// most other publishers', code signatures of about 2010 to 2016.
    static let verisignClass3G5 = Root(
        name: "VeriSign Class 3 Public Primary Certification Authority - G5",
        sha1: "4EB6D578499B1CCF5F581EAD56BE3D9B6744A5E5",
        sha256: "9ACFAB7E43C8D880D06B262A94DEEEE4B4659989C3D0CAF19BAF6405E41AB7DF",
        base64:
        "MIIE0zCCA7ugAwIBAgIQGNrRniZ96LtKIVjNzGs7SjANBgkqhkiG9w0BAQUFADCByjELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZl" +
        "cmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTowOAYDVQQLEzEoYykgMjAwNiBWZXJpU2lnbiwg" +
        "SW5jLiAtIEZvciBhdXRob3JpemVkIHVzZSBvbmx5MUUwQwYDVQQDEzxWZXJpU2lnbiBDbGFzcyAzIFB1YmxpYyBQcmltYXJ5IENl" +
        "cnRpZmljYXRpb24gQXV0aG9yaXR5IC0gRzUwHhcNMDYxMTA4MDAwMDAwWhcNMzYwNzE2MjM1OTU5WjCByjELMAkGA1UEBhMCVVMx" +
        "FzAVBgNVBAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTowOAYDVQQLEzEoYykgMjAw" +
        "NiBWZXJpU2lnbiwgSW5jLiAtIEZvciBhdXRob3JpemVkIHVzZSBvbmx5MUUwQwYDVQQDEzxWZXJpU2lnbiBDbGFzcyAzIFB1Ymxp" +
        "YyBQcmltYXJ5IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IC0gRzUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCvJAgI" +
        "KXo1nmAMqudLO07cfLw8RRy7K+D+KQL5VwijZIUVJ/XxrcgxiV0i6CqqpkKzj/i5Vbext0uz/o9+B1fs70PbZmIVYc9gDaTY3vjg" +
        "w2IIPVQT60nKWVSFJuUrjxuf6/WhkcIzSdhDY2pSS9KP6HBRTdGJaXvHcPaz3BJ023tdS1bTlr8Vd6Gw9KIl8q8ckmcY5fQGBO+Q" +
        "ueQA5N06tRn/Arr0PO7gi+s3i+z016zy9vA9r911kTMZHRxAy3QkGSGT2RT+rCpSx4/VBEnkjWNHiDxpg8v+R70rfk/Fla4OndTR" +
        "Q8Bnc+MUCH7lP59zuDMKz10/NIeWiu5T6CUVAgMBAAGjgbIwga8wDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwbQYI" +
        "KwYBBQUHAQwEYTBfoV2gWzBZMFcwVRYJaW1hZ2UvZ2lmMCEwHzAHBgUrDgMCGgQUj+XTGoasjY5rw8+AatRIGCx7GS4wJRYjaHR0" +
        "cDovL2xvZ28udmVyaXNpZ24uY29tL3ZzbG9nby5naWYwHQYDVR0OBBYEFH/TZafC3ey78DAJ80M5+gKvMzEzMA0GCSqGSIb3DQEB" +
        "BQUAA4IBAQCTJEowX2LP2BqYLz3q3JktvXf2pXkiOOzEp6B4Eq1iDkVwZMXnl2YtmAl+X6/WzChl8gGqCBpH3vn5fJJaCGkgDdk+" +
        "bW48DW7Y5gaRQBi5+MHt39tBquCWIMnNZBU4gcmU7qKEKQsTb47bDN0lAtukixlE0kF6BWlKWE9gyn6CagsCqiUXObXbf+eEZSqV" +
        "ir2G3l6BFoMtEMze/aiCKm0oHw0LxOXnGiYZ4fQRbxC1lfznQgUy286dUV4otp6F01vvpX1FQHKOtw5rDgb7MzVIcbidJ4vEZV8N" +
        "hnacRHr2lVz2XTIIM6RUthg/aFzyQkqFOFSDX9HoLPKsEdao7WNq")

    static let all = [verisignClass3G5]

    // MARK: - Roots the player is asked about

    /// Roots that go into the prefix only on the player's yes: the question on the curtain when a game's
    /// signature check stops at one (step E6 of docs/ENTWURF-STARTREZEPT.md 3.3, the player's decision of
    /// 15.11.2026). Each needs the user's OK to be here, as every root does. None so far: VeriSign's went into
    /// every prefix with the user's OK of 11.11.2026, before there was a question.
    static let onRequest: [Root] = []

    /// The roots the player said yes to, by their SHA-1: for every Windows game, as the prefix is shared.
    static let trustedKey = "windowsRoots.trusted"

    static func trusted(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: trustedKey) ?? [])
    }

    static func trust(_ root: Root, defaults: UserDefaults = .standard) {
        defaults.set(Array(trusted(defaults: defaults).union([root.sha1])).sorted(), forKey: trustedKey)
    }

    /// The roots in every prefix, and those the player is asked about – with the test switch, all of them asked.
    static func always(defaults: UserDefaults = .standard) -> [Root] { testsQuestion(defaults: defaults) ? [] : all }
    static func askable(defaults: UserDefaults = .standard) -> [Root] {
        onRequest + (testsQuestion(defaults: defaults) ? all : [])
    }

    /// A root the player can be asked about, by the name a signature check's chain gives it ("VeriSign Class 3
    /// Public Primary Certification Authority - G5", CloserLook.Signature.root): one on request, not said yes to yet.
    static func toAsk(named name: String, defaults: UserDefaults = .standard) -> Root? {
        let yes = trusted(defaults: defaults)
        return askable(defaults: defaults).first { $0.name == name && !yes.contains($0.sha1) && $0.verified != nil }
    }

    /// The root a game's check stopped at, kept with the game: its next Play can ask without a closer look,
    /// which comes once per game and engine build (CloserLook.taken).
    private static func neededKey(_ game: GameID) -> String { "windowsRoots.needed.\(game.key)" }
    static func needed(by game: GameID, defaults: UserDefaults = .standard) -> String? { defaults.string(forKey: neededKey(game)) }
    static func noteNeeded(_ root: String, by game: GameID, defaults: UserDefaults = .standard) { defaults.set(root, forKey: neededKey(game)) }

    /// Nightforge's own test switch for the question (`defaults write io.github.lordhayne.nightforge testRootQuestion
    /// -bool true`): the roots in every prefix are asked about instead, and while the player hasn't said yes their key
    /// is taken out of the prefix – Metal Gear Solid V then fails as on 11.11.2026, and the question can be seen. No
    /// entry in the interface; `defaults delete … testRootQuestion` and `… windowsRoots.trusted` end it. A build made
    /// with NIGHTFORGE_RELEASE has no such switch at all (as GameTest.measuresPlay).
    #if NIGHTFORGE_RELEASE
    static func testsQuestion(defaults: UserDefaults = .standard) -> Bool { false }
    #else
    static let testRootQuestionKey = "testRootQuestion"
    static func testsQuestion(defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: testRootQuestionKey) }
    #endif

    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02X", $0) }.joined()
    }

    /// A certificate as Wine keeps it in the registry: its properties one after another, each headed by its
    /// ID, a 1 and its length. The certificate itself (CERT_CERT_PROP_ID, 32) is enough: Wine works out the rest.
    static func blob(_ der: Data) -> Data {
        func word(_ value: UInt32) -> Data { Data((0..<4).map { UInt8(value >> (8 * UInt32($0)) & 0xFF) }) }
        return word(32) + word(1) + word(UInt32(der.count)) + der
    }

    /// The .reg text that puts the roots into the current user's Root store – which Wine reads beside the
    /// machine's, and doesn't rewrite when it takes the Mac's roots again. The key is the SHA-1, which Wine
    /// compares with the certificate's own. Those in every prefix and those the player said yes to; the key of a
    /// root on request without a yes is taken out, so the prefix holds what the player said.
    static func registrySection(defaults: UserDefaults = .standard) -> String {
        let yes = trusted(defaults: defaults)
        let asked = askable(defaults: defaults)
        let removed = asked.filter { !yes.contains($0.sha1) }
            .map { "[-HKEY_CURRENT_USER\\Software\\Microsoft\\SystemCertificates\\Root\\Certificates\\\($0.sha1)]" }
        return ([registry(always(defaults: defaults) + asked.filter { yes.contains($0.sha1) })].filter { !$0.isEmpty } + removed)
            .joined(separator: "\n\n")
    }

    static var registrySection: String { registrySection() }

    static func registry(_ roots: [Root]) -> String {
        roots.compactMap { root in
            root.verified.map { der in
                let bytes = blob(der).map { String(format: "%02x", $0) }
                let lines = stride(from: 0, to: bytes.count, by: 24).map { bytes[$0..<min($0 + 24, bytes.count)].joined(separator: ",") }
                return "[HKEY_CURRENT_USER\\Software\\Microsoft\\SystemCertificates\\Root\\Certificates\\\(root.sha1)]\n\"Blob\"=hex:"
                    + lines.joined(separator: ",\\\n  ")
            }
        }.joined(separator: "\n\n")
    }
}
