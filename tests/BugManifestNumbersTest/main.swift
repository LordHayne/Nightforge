// FAILS (crashes) on staging-032 c475580: UpdateState.pending does `Int64(max(0, toDownload - downloaded))` on doubles
// taken as they are from a Steam manifest (Library.swift:818, read at Library.swift:521-522 and 561). A number too big
// for Int64 traps while the library is scanned, so Nightforge crashes at every start until the manifest is
// repaired or removed. Befunde in docs/TESTABDECKUNG.md: tests/BugManifestNumbersTest/run.sh
import Foundation

@main
struct BugManifestNumbersTest {
    static func main() {
        for bytes in [1e19, 1e300, Double.infinity] {
            // Exits at the first trap; a bad number is "Steam hasn't worked it out" or a clamped size.
            let pending = UpdateState(flags: 2, toDownload: bytes, downloaded: 0).pending
            print("toDownload \(bytes): \(String(describing: pending))")
        }
        let odd = UpdateState(flags: 2, toDownload: 1e300, downloaded: 1e300).fraction
        if let odd, !(0...1).contains(odd) {
            print("✗ the fraction left 0…1: \(odd)")
            exit(1)
        }
        print("✓ Manifest numbers too big for Int64 don't crash")
    }
}
