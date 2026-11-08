// FAILS on staging-032 3288f58: SaveTransfer.takeNewer (SaveTransfer.swift:166) renames the other version's file
// into place and then removes `Set(ours).subtracting(theirs)`, comparing names exactly. On the Mac's usual
// case-insensitive volume, the Mac version's "Save1.dat" and the Windows version's "SAVE1.DAT" are one file:
// the rename replaced it, and the removal then deletes it. The version starting after the switch finds no save.
// `same` compares the same way. The other version's copy and the backup survive. Befunde in
// docs/TESTABDECKUNG.md. A Finder's .DS_Store is the other half (SaveTransfer.files, pattern "*" matches it): a
// folder holding only that counts as having saves, so carryOver leaves it empty. tests/BugSaveNamesTest/run.sh
import Foundation

@main
struct BugSaveNamesTest {
    static func main() {
        TestDefaults.useWorkFolder()
        finderFile()
        caseOnly()
        print(failures == 0 ? "✓ Save names" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static var failures = 0

    static func finderFile() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        world.write("finder", to: world.mac.appendingPathComponent(".DS_Store"))
        world.write("win", to: world.windows.appendingPathComponent("slot.sav"))
        if SaveTransfer.carryOver(to: .mac, rules: world.rules, places: world.places) == 0 {
            print("✗ a folder holding only Finder's .DS_Store counts as having saves: the save isn't carried over")
            failures += 1
        }
    }

    static func caseOnly() {
        let world = SaveWorld()
        defer { world.cleanUp() }
        guard world.caseInsensitive() else {
            print("(not a case-insensitive volume: the case check doesn't apply)")
            return
        }
        world.write("mac old", to: world.mac.appendingPathComponent("Save1.dat"), age: 500)
        world.write("windows new", to: world.windows.appendingPathComponent("SAVE1.DAT"))
        do {
            _ = try SaveTransfer.takeNewer(to: .mac, rules: world.rules, places: world.places, backup: world.backup)
        } catch {
            print("✗ takeNewer threw: \(error)")
            failures += 1
            return
        }
        let found = (try? FileManager.default.contentsOfDirectory(atPath: world.mac.path)) ?? []
        guard world.read(world.mac.appendingPathComponent("SAVE1.DAT")) == "windows new" else {
            print("✗ the newer save is gone after takeNewer: the folder holds \(found)")
            failures += 1
            return
        }
    }
}
