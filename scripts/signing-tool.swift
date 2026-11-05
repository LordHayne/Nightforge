// The command-line half of Nightforge's signatures. scripts/signing-lib.sh builds it together with the
// app's own Sources/Nightforge/Signature.swift and SigningKeys.swift, so it checks exactly what the
// app checks, with the keys the app has.
//
//   generate            a new private key (base64) on stdout, only ever into a pipe
//   public              the public key of the private key on stdin
//   which               whether the private key on stdin is the main or the spare key
//   sign [--add] FILE…  FILE.sig beside each file, with the private key on stdin; a key that isn't
//                       in SigningKeys.swift is refused. --add keeps the signatures already there that
//                       hold (one per line, see Signature) and adds this key's.
//   verify FILE…        whether each FILE.sig holds, and with which key
//   keys                the public keys in SigningKeys.swift; fails when one is missing
//   ahead FILE          exit 0 when FILE's "generated" lies more than a day ahead, 1 when not, 2 when
//                       it has none that reads as a date (SignedLists.isAhead)
//   newer FILE BEFORE   exit 0 when FILE's "generated" is newer than BEFORE's by the app's own rules
//                       (SignedLists.isNewer), 1 when not
//
// Error messages never repeat what came in on stdin.
import CryptoKit
import Foundation

@main
struct SigningTool {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else { fail("usage: signing-tool generate|public|which|sign|verify|keys …") }
        let command = arguments.removeFirst()
        switch command {
        case "generate":
            print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
        case "public":
            print(privateKeyFromInput().publicKey.rawRepresentation.base64EncodedString())
        case "which":
            let key = privateKeyFromInput().publicKey.rawRepresentation.base64EncodedString()
            guard let role = role(of: key) else { fail("✗ This isn't the main or the spare key in SigningKeys.swift.") }
            print(role)
        case "sign":
            let add = arguments.first == "--add"
            if add { arguments.removeFirst() }
            sign(arguments, add: add)
        case "verify":
            verify(arguments)
        case "keys":
            keys()
        case "ahead":
            guard arguments.count == 1, let data = FileManager.default.contents(atPath: arguments[0]) else {
                fail("usage: signing-tool ahead FILE")
            }
            exit(SignedLists.isAhead(data).map { $0 ? 0 : 1 } ?? 2)
        case "newer":
            guard arguments.count == 2, let data = FileManager.default.contents(atPath: arguments[0]) else {
                fail("usage: signing-tool newer FILE BEFORE")
            }
            exit(SignedLists.isNewer(data, than: FileManager.default.contents(atPath: arguments[1])) ? 0 : 1)
        default:
            fail("unknown command \(command)")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    static func role(of publicKey: String) -> String? {
        publicKey == SigningKeys.main ? "main" : publicKey == SigningKeys.spare ? "spare" : nil
    }

    static func privateKeyFromInput() -> Curve25519.Signing.PrivateKey {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("✗ No private key came in (the Keychain said no, or the clipboard is empty).") }
        guard let raw = Data(base64Encoded: text), raw.count == 32,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        else { fail("✗ That isn't a Nightforge private key (44 characters of base64).") }
        return key
    }

    static func sign(_ files: [String], add: Bool) {
        guard !files.isEmpty else { fail("usage: signing-tool sign [--add] FILE…") }
        let key = privateKeyFromInput()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        guard let role = role(of: publicKey) else {
            fail("✗ This key isn't the main or the spare key in SigningKeys.swift, so Nightforge wouldn't take its signature.")
        }
        for path in files {
            let file = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: file) else { fail("✗ Can't read \(path)") }
            guard let signature = try? key.signature(for: data) else { fail("✗ Signing \(path) failed") }
            let line = signature.base64EncodedString()
            var lines = [line]
            if add, let existing = try? String(contentsOf: Signature.file(for: file), encoding: .utf8) {
                // Lines that still hold for this file stay; an old file's or a stranger's go.
                let holding = existing.split(whereSeparator: \.isNewline).map(String.init).filter {
                    $0 != line && Signature.isValid(Data($0.utf8), of: data, keys: SigningKeys.trusted)
                }
                lines = holding + [line]
            }
            let text = lines.joined(separator: "\n") + "\n"
            guard (try? Data(text.utf8).write(to: Signature.file(for: file), options: .atomic)) != nil,
                  Signature.isValid(Data(text.utf8), of: data, keys: [publicKey])
            else { fail("✗ Couldn't write \(path).sig") }
            print("✓ \(file.lastPathComponent) signed with the \(role) key" + (lines.count > 1 ? " (\(lines.count) signatures)" : ""))
        }
    }

    static func verify(_ files: [String]) {
        guard !files.isEmpty else { fail("usage: signing-tool verify FILE…") }
        guard !SigningKeys.trusted.isEmpty else { fail("✗ SigningKeys.swift has no keys yet (scripts/make-signing-keys.sh).") }
        var failed = false
        for path in files {
            let file = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: file) else { print("✗ \(path): can't read it"); failed = true; continue }
            guard let signature = try? Data(contentsOf: Signature.file(for: file)) else {
                print("✗ \(path): not signed (no \(file.lastPathComponent).sig)")
                failed = true
                continue
            }
            if let key = Signature.signer(of: data, signature: signature, keys: SigningKeys.trusted) {
                print("✓ \(path) (\(role(of: key) ?? "?") key)")
            } else {
                print("✗ \(path): the signature doesn't hold (changed after signing, or signed with another key)")
                failed = true
            }
        }
        if failed { exit(1) }
    }

    static func keys() {
        var missing = false
        for (role, key) in [("main", SigningKeys.main), ("spare", SigningKeys.spare)] {
            if let raw = Data(base64Encoded: key), raw.count == 32, (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil {
                print("\(role) \(key)")
            } else {
                FileHandle.standardError.write(Data("✗ SigningKeys.swift has no \(role) key\n".utf8))
                missing = true
            }
        }
        if SigningKeys.main == SigningKeys.spare, !SigningKeys.main.isEmpty {
            FileHandle.standardError.write(Data("✗ The main and the spare key are the same\n".utf8))
            missing = true
        }
        if missing { exit(1) }
    }
}
