/// The public halves of the two Ed25519 keys that sign Nightforge's releases and online lists
/// (base64 of the 32 raw bytes). A signature from either one counts (`Signature`).
///
/// scripts/make-signing-keys.sh writes these lines; nothing else should. The main key's private half
/// lives in the maintainer's Keychain, the spare's only offline (password manager, paper). When the
/// main key is lost, the spare signs the release that brings a new main key, and the release after
/// that brings a new spare (docs/SICHERHEIT-0.3.md › Signierte Releases).
enum SigningKeys {
    static let main = ""
    static let spare = ""

    static var trusted: [String] { [main, spare].filter { !$0.isEmpty } }
}
