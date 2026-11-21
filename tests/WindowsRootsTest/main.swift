// Checks the root certificates Nightforge adds to the prefix (WindowsRoots): each is the certificate its
// fingerprints name, a changed one is left out, and the registry text holds it the way Wine reads it back.
import CryptoKit
import Foundation
import Security

@main
struct WindowsRootsTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        let root = WindowsRoots.verisignClass3G5
        guard let der = root.der else {
            print("✗ the certificate isn't base64")
            exit(1)
        }

        // MARK: The certificate is the one meant
        check(der.count == 1239, "VeriSign's Class 3 G5 root: 1239 bytes (\(der.count))")
        check(SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined() == "9ACFAB7E43C8D880D06B262A94DEEEE4B4659989C3D0CAF19BAF6405E41AB7DF",
              "its SHA-256, as every root list names it")
        check(Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined() == "4EB6D578499B1CCF5F581EAD56BE3D9B6744A5E5",
              "its SHA-1, which Windows names it by")
        check(root.verified == der, "what its fingerprints say: taken")
        if let certificate = SecCertificateCreateWithData(nil, der as CFData) {
            let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
            check(summary == "VeriSign Class 3 Public Primary Certification Authority - G5", "the Mac reads it as that root (\(summary))")
            var error: Unmanaged<CFError>?
            let subject = SecCertificateCopyNormalizedSubjectSequence(certificate) as Data?
            let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) as Data?
            check(subject != nil && subject == issuer, "a root: issued by itself")
            let serial = (SecCertificateCopySerialNumberData(certificate, &error) as Data?)?.map { String(format: "%02X", $0) }.joined()
            check(serial == "18DAD19E267DE8BB4A2158CDCC6B3B4A", "its serial number (\(serial ?? "–"))")
        } else {
            check(false, "the Mac reads it as a certificate")
        }
        for each in WindowsRoots.all {
            check(each.sha1.count == 40 && each.sha256.count == 64 && each.sha1 == each.sha1.uppercased() && each.verified != nil,
                  "\(each.name): fingerprints as Wine spells them, and they hold")
        }
        check(Set(WindowsRoots.all.map(\.sha1)).count == WindowsRoots.all.count, "no root twice")

        // MARK: A constant that no longer matches is left out
        let other = WindowsRoots.Root(name: "changed", sha1: root.sha1, sha256: root.sha256, base64: Data(der.dropLast() + [0]).base64EncodedString())
        check(other.verified == nil, "one changed byte: not the certificate any more")
        check(WindowsRoots.Root(name: "broken", sha1: root.sha1, sha256: root.sha256, base64: "not base64 !").verified == nil, "no base64: nothing")
        check(WindowsRoots.registry([other]).isEmpty, "… and nothing of it reaches the registry")
        check(WindowsRoots.registry([]).isEmpty, "no roots, no text")

        // MARK: The registry text
        let blob = WindowsRoots.blob(der)
        check(Array(blob.prefix(12)) == [0x20, 0, 0, 0, 1, 0, 0, 0, 0xD7, 0x04, 0, 0] && blob.dropFirst(12) == der,
              "Wine's serialized certificate: property 32, a 1, the length, the certificate")
        let text = WindowsRoots.registrySection
        let lines = text.components(separatedBy: "\n")
        check(lines.first == #"[HKEY_CURRENT_USER\Software\Microsoft\SystemCertificates\Root\Certificates\4EB6D578499B1CCF5F581EAD56BE3D9B6744A5E5]"#,
              "the key: the current user's Root store, named by the SHA-1 (\(lines.first ?? "–"))")
        check(lines.count > 2 && lines[1].hasPrefix("\"Blob\"=hex:20,00,00,00,01,00,00,00,d7,04,00,00,30,82,"), "the value Wine reads: Blob, binary")
        check(lines.dropFirst().dropLast().allSatisfy { $0.hasSuffix(",\\") } && lines.last?.hasSuffix("\\") == false && lines.last?.hasSuffix(",") == false,
              "continued line by line, the last one ends the value")
        check(lines.dropFirst(2).allSatisfy { $0.hasPrefix("  ") } && lines.allSatisfy { $0.count <= 120 }, "continuation lines indented, none long")
        // Read back as regedit does: the bytes of all lines.
        let hex = lines.dropFirst().joined().replacingOccurrences(of: "\"Blob\"=hex:", with: "").replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: " ", with: "")
        let bytes = hex.split(separator: ",").compactMap { UInt8($0, radix: 16) }
        check(Data(bytes) == blob, "read back, it's the certificate's blob (\(bytes.count) of \(blob.count) bytes)")
        check(!text.contains("HKEY_LOCAL_MACHINE"), "never the machine's store, which Wine rewrites from the Mac's roots")
        check(GameRegistryRecord.Section(key: "WindowsRoots", text: text).digest.count == 32, "a section of the game settings' record")

        // MARK: Roots the player is asked about (step E6, 15.11.2026)
        let asked = TestDefaults.suite("windows-roots")
        check(WindowsRoots.onRequest.isEmpty, "no root waits for a yes yet: each one here needs the user's OK first")
        check(WindowsRoots.registrySection(defaults: asked) == WindowsRoots.registry(WindowsRoots.all)
              && !WindowsRoots.registrySection(defaults: asked).contains("[-"), "without the test switch: every root in, nothing taken out, as before")
        check(WindowsRoots.toAsk(named: root.name, defaults: asked) == nil, "… and nobody asked about VeriSign's, which is in every prefix")
        asked.set(true, forKey: WindowsRoots.testRootQuestionKey)
        let removal = #"[-HKEY_CURRENT_USER\Software\Microsoft\SystemCertificates\Root\Certificates\4EB6D578499B1CCF5F581EAD56BE3D9B6744A5E5]"#
        check(WindowsRoots.registrySection(defaults: asked) == removal, "the test switch: VeriSign's asked about, and out of the prefix until a yes")
        check(WindowsRoots.toAsk(named: root.name, defaults: asked)?.sha1 == root.sha1 && WindowsRoots.toAsk(named: "Some Other Root", defaults: asked) == nil,
              "asked about by the name a check's chain gives it, and only a root Nightforge knows")
        WindowsRoots.trust(root, defaults: asked)
        check(WindowsRoots.registrySection(defaults: asked) == WindowsRoots.registry([root]) && WindowsRoots.trusted(defaults: asked) == [root.sha1],
              "a yes: in the prefix as before, kept")
        check(WindowsRoots.toAsk(named: root.name, defaults: asked) == nil, "said yes to: not asked again")
        WindowsRoots.trust(root, defaults: asked)
        check(WindowsRoots.trusted(defaults: asked).count == 1, "a yes twice is one")
        check(GameRegistryRecord.Section(key: "WindowsRoots", text: WindowsRoots.registrySection(defaults: asked)).digest
              != GameRegistryRecord.Section(key: "WindowsRoots", text: removal).digest, "a yes changes the section: the next start imports it")
        let mgs = GameID.steam(287_700)
        check(WindowsRoots.needed(by: mgs, defaults: asked) == nil, "nothing needed yet")
        WindowsRoots.noteNeeded(root.name, by: mgs, defaults: asked)
        check(WindowsRoots.needed(by: mgs, defaults: asked) == root.name, "the root a game stopped at, kept with it")

        print(failures == 0 ? "✓ WindowsRoots" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
