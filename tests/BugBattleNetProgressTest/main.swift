// FAILS on staging-032 c475580: ProductDB takes `progress` as the file's raw double, and BattleNetLibrary.games
// only drops what isn't above 0. "+Infinity" or 1e300 becomes `.downloading(x)`, and `Int(fraction * 100)` in
// LibraryView.swift:1845 and Downloads.swift:219 traps on it: Nightforge crashes with every library
// refresh until the file is rewritten. The file's other numbers are clamped; BattleNetLibrary.folder says of this
// file that a Windows program can write it. Befunde in docs/TESTABDECKUNG.md: tests/BugBattleNetProgressTest/run.sh
import Foundation

@main
struct BugBattleNetProgressTest {
    static func main() {
        var failures = 0
        for bad in [Double.infinity, 1e300, 1e30, 5] {
            var install = ProductDB.Install()
            install.code = "hsb"
            install.installPath = "/Applications/Hearthstone"
            install.operation = .update
            install.progress = bad
            let card = BattleNetLibrary.games([install], client: .mac) { _ in true }.first
            guard case .downloading(let fraction)? = card?.install else {
                print("✗ \(bad): no card at all")
                failures += 1
                continue
            }
            if let fraction, !(0...1).contains(fraction) {
                print("✗ progress \(bad) reaches the views as \(fraction), outside 0…1 (`Int(fraction * 100)` traps on the huge ones)")
                failures += 1
            }
        }
        print(failures == 0 ? "✓ A file's progress stays between 0 and 1" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
