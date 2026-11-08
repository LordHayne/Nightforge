// Moving saves between a game's two versions where it's easy to get wrong: folders with spaces and umlauts, a
// step that fails halfway, a backup folder that's already there. tests/MacVersionTest and tests/ProfileFilesTest
// hold the everyday cases. tests/SaveTransferEdgeTest/run.sh
import Foundation

@main
struct SaveTransferEdgeTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()
        oddFolders()
        backupInTheWay()
        fileWhereAFolderIs()
        firstAndLaterStarts()
        print(failures == 0 ? "✓ Saves in odd places" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func oddFolders() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        world.write("slot", to: world.windows.appendingPathComponent("Unterordner ä/slot 1.sav"))
        world.write("cfg", to: world.windows.appendingPathComponent("settings.cfg"))
        let copied = SaveTransfer.carryOver(to: .mac, rules: world.rules, places: world.places)
        check(copied == 2, "both files, the one in a folder with an umlaut too: \(copied)")
        check(world.read(world.mac.appendingPathComponent("Unterordner ä/slot 1.sav")) == "slot", "the save arrives at its place")
        check(SaveTransfer.carryOver(to: .mac, rules: world.rules, places: world.places) == 0, "a folder that has saves isn't filled again")
    }

    static func backupInTheWay() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        world.write("mine", to: world.mac.appendingPathComponent("a.sav"), age: 500)
        world.write("newer", to: world.windows.appendingPathComponent("a.sav"))
        world.write("earlier run", to: world.backup.appendingPathComponent("WinAppDataRoaming/Spiel ü/Saves/a.sav"))
        var failed = false
        do { _ = try SaveTransfer.takeNewer(to: .mac, rules: world.rules, places: world.places, backup: world.backup) } catch { failed = true }
        check(failed, "a backup that can't be written stops it")
        check(world.read(world.mac.appendingPathComponent("a.sav")) == "mine", "and this version's save stays as it was")
        check(world.read(world.backup.appendingPathComponent("WinAppDataRoaming/Spiel ü/Saves/a.sav")) == "earlier run", "the earlier backup too")
    }

    /// The other side has a file where this one has a folder: it stops, and says where the old saves are.
    static func fileWhereAFolderIs() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        world.write("inner", to: world.mac.appendingPathComponent("data/inner.sav"), age: 500)
        world.write("other", to: world.windows.appendingPathComponent("data"))
        do {
            _ = try SaveTransfer.takeNewer(to: .mac, rules: world.rules, places: world.places, backup: world.backup)
            check(false, "a file over a folder can't just work")
        } catch let error as SaveTransfer.PartlyTaken {
            check(error.backup == world.backup, "it says where the saves from before are")
        } catch {
            check(false, "the wrong error: \(error)")
        }
        check(world.read(world.backup.appendingPathComponent("WinAppDataRoaming/Spiel ü/Saves/data/inner.sav")) == "inner", "this version's save is in the backup")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: world.mac.deletingLastPathComponent().path)) ?? []
        check(!leftovers.contains { $0.contains(".nightforge-") }, "nothing of the attempt lies around: \(leftovers)")
    }

    static func firstAndLaterStarts() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        let defaults = TestDefaults.suite("saves-start")
        world.write("win", to: world.windows.appendingPathComponent("a.sav"))
        check(SaveTransfer.isSwitch(appID: 7, platform: .mac, defaults: defaults), "Nightforge hasn't seen it: counts as a switch")
        check(SaveTransfer.beforeStart(appID: 7, platform: .mac, rules: world.rules, places: world.places, defaults: defaults) == 1, "the first start takes the save along")
        check(!SaveTransfer.isSwitch(appID: 7, platform: .mac, defaults: defaults), "then it's the version last played")
        world.write("win2", to: world.windows.appendingPathComponent("b.sav"))
        check(SaveTransfer.beforeStart(appID: 7, platform: .mac, rules: world.rules, places: world.places, defaults: defaults) == 0, "the next start of the same version copies nothing")
        check(SaveTransfer.isSwitch(appID: 7, platform: .windows, defaults: defaults), "the other version is a switch")
    }
}
