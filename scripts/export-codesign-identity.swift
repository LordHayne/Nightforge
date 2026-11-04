// Exports only Nightforge's code signing identity – the certificate pinned in
// scripts/codesign-certificate.sha1 and its private key – as a .p12 for the backup
// (scripts/export-codesign-identity.sh builds and runs it). macOS asks for the .p12's password in a
// dialog of its own, so it never passes through here, and whether the key may be exported: Allow.
// It reads the keychain and changes nothing in it.
import CryptoKit
import Foundation
import Security

@main
struct ExportCodesignIdentity {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { fail("usage: export-codesign-identity <SHA-1> <file.p12>") }
        let pinned = arguments[1].uppercased(), output = URL(fileURLWithPath: arguments[2])

        let query: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecMatchLimit: kSecMatchLimitAll, kSecReturnRef: true]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let identities = found as? [SecIdentity] else {
            fail("✗ No identities in your keychains.")
        }
        // Only the one whose certificate has the pinned SHA-1, the hash codesign and find-identity show.
        let identity = identities.first { identity in
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return false }
            let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
            return digest.map { String(format: "%02X", $0) }.joined() == pinned
        }
        guard let identity else { fail("✗ The certificate \(pinned) isn't in your keychains.") }

        var parameters = SecItemImportExportKeyParameters()
        parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        parameters.flags = .securePassphrase
        parameters.alertTitle = Unmanaged.passRetained("Nightforge Code Signing" as CFString)
        parameters.alertPrompt = Unmanaged.passRetained("A password for the backup (.p12)" as CFString)
        var exported: CFData?
        let status = SecItemExport(identity, .formatPKCS12, [], &parameters, &exported)
        guard status == errSecSuccess, let data = exported as Data? else {
            fail("✗ macOS didn't export it (\(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")). Nothing written.")
        }
        guard FileManager.default.createFile(atPath: output.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            fail("✗ Couldn't write \(output.path).")
        }
        print("✓ \(output.path): the certificate \(pinned) with its key, readable only by you.")
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
