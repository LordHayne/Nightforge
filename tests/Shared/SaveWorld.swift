// A made-up Mac with both versions of a game's save folder, for the SaveTransfer series. Folders of the test's
// own, with spaces and umlauts in them.
import Foundation

struct SaveWorld {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("saves-Jörg Müller \(UUID().uuidString)", isDirectory: true)
    var places: SaveTransfer.Places {
        var places = SaveTransfer.Places()
        places.prefix = root.appendingPathComponent("Prefix", isDirectory: true)
        places.windowsUser = "Jörg"
        places.macHome = root.appendingPathComponent("Home", isDirectory: true)
        places.windowsInstall = nil
        places.macInstall = nil
        return places
    }
    var windows: URL { places.prefix.appendingPathComponent("drive_c/users/Jörg/AppData/Roaming/Spiel ü/Saves", isDirectory: true) }
    var mac: URL { places.macHome.appendingPathComponent("Library/Application Support/Spiel ü/Saves", isDirectory: true) }
    var backup: URL { root.appendingPathComponent("Backups/x/Mac version", isDirectory: true) }
    let rules = [SaveRule(root: "WinAppDataRoaming", path: "Spiel ü/Saves", pattern: "*", recursive: true, macRoot: "MacAppSupport", macAddPath: "")]

    func write(_ text: String, to file: URL, age: TimeInterval = 0) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: file)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    func read(_ file: URL) -> String? { (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) } }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// Whether the volume of the temporary folder is case-insensitive (macOS's default).
    func caseInsensitive() -> Bool {
        let probe = root.appendingPathComponent("CaseProbe")
        write("x", to: probe)
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("caseprobe").path)
    }
}
