// Checks what the on/off entries offer (PowerMenu). It never puts the Mac to sleep: tests/PowerMenuTest/run.sh
import Foundation

@main
struct PowerMenuTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(PowerMenu.entries(gameOn: false, downloading: false) == [.sleepMac, .quitNightforge], "nothing going on: both")
        check(PowerMenu.entries(gameOn: true, downloading: false).isEmpty, "with a game on: neither, the overlay ends games")
        check(PowerMenu.entries(gameOn: false, downloading: true) == [.quitNightforge], "a download keeps the Mac awake")
        check(PowerMenu.sleepCommand.path == "/usr/bin/pmset" && PowerMenu.sleepArguments == ["sleepnow"], "the Mac's own way to sleep")
        check(FileManager.default.isExecutableFile(atPath: PowerMenu.sleepCommand.path), "and it's there")
        print(failures == 0 ? "✓ PowerMenu" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
