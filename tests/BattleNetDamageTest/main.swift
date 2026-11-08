// What Battle.net's files can look like after a crash, a half-written product.db or an unusual installation: the
// reader neither crashes nor believes what isn't there. Cut-off and flipped bytes from the fixtures of
// tests/BattleNetTest, files of odd size and kind, folders with spaces and umlauts, and the client's logs
// with bytes that aren't text: tests/BattleNetDamageTest/run.sh
import Foundation

/// A generator with a seed, so a failing byte pattern comes back the same.
struct Mixer: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@main
struct BattleNetDamageTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bn-damage-\(UUID().uuidString)", isDirectory: true)

    static func main() {
        TestDefaults.useWorkFolder()
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        cutOff()
        flippedBytes()
        fileKinds()
        folders()
        waitingForDrive()
        logs()
        print(failures == 0 ? "✓ Battle.net against damaged files" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath: "tests/BattleNetTest/fixtures/\(name)"))) ?? Data()
    }

    static let prefix = URL(fileURLWithPath: "/tmp/fake-bn-prefix", isDirectory: true)

    /// Whatever parses reaches the library code: a card can't come of it that lies about what it is.
    static func survives(_ data: Data) {
        guard let installs = ProductDB.parse(data) else { return }
        for client in [BattleNetLibrary.Client.mac, .windows(prefix: prefix)] {
            for answer in [true, false] {
                for game in BattleNetLibrary.games(installs, client: client, exists: { _ in answer }) {
                    check(!game.name.isEmpty && game.gameID.provider == .battlenet && BattleNetLibrary.titles[game.gameID.id] != nil,
                          "only known titles come from a file, however damaged: \(game.gameID)")
                    check(game.sizeOnDisk >= 0, "a size can't be negative: \(game.sizeOnDisk)")
                }
            }
        }
    }

    /// The Agent is in the middle of writing it, at any byte.
    static func cutOff() {
        for name in ["product-installed.db", "product-installing.db"] {
            let good = fixture(name)
            check(!good.isEmpty, "\(name) is there")
            for length in 0..<good.count { survives(good.prefix(length)) }
            check(ProductDB.parse(good) != nil, "\(name) as it is parses")
        }
    }

    static func flippedBytes() {
        var mixer = Mixer(state: 0xBA77_1E7E)
        for name in ["product-installed.db", "product-installing.db"] {
            let good = [UInt8](fixture(name))
            guard !good.isEmpty else { continue }
            for round in 0..<3000 {
                var bytes = good
                for _ in 0..<(round % 8 + 1) {
                    let at = Int.random(in: 0..<bytes.count, using: &mixer)
                    bytes[at] = UInt8.random(in: 0...255, using: &mixer)
                }
                survives(Data(bytes))
            }
        }
    }

    static func fileKinds() {
        let huge = work.appendingPathComponent("huge.db")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: huge) {
            try? handle.truncate(atOffset: UInt64(17 << 20))
            try? handle.close()
        }
        check(BattleNetLibrary.read(huge) == nil, "a file over 16 MB isn't a product.db and isn't read")
        let folder = work.appendingPathComponent("folder.db", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        check(BattleNetLibrary.read(folder) == nil, "a folder in its place: nothing, no crash")
        let empty = work.appendingPathComponent("empty.db")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        check(BattleNetLibrary.read(empty) == nil, "an empty file isn't “nothing installed”")
        check(BattleNetLibrary.read(work.appendingPathComponent("no such file")) == nil, "no file: nil")
        let hole = work.appendingPathComponent("zeros.db")
        FileManager.default.createFile(atPath: hole.path, contents: Data(count: 4096))
        check(BattleNetLibrary.read(hole) == nil, "a file of zeros (power loss): refused")
    }

    static func folders() {
        func mac(_ path: String) -> String? { BattleNetLibrary.folder(path, client: .mac)?.path }
        func win(_ path: String) -> String? { BattleNetLibrary.folder(path, client: .windows(prefix: prefix))?.path }
        check(mac("/Users/Jörg Müller/Spiele für alle/StarCraft II") == "/Users/Jörg Müller/Spiele für alle/StarCraft II", "a Mac folder with spaces and umlauts")
        check(win("C:/Spiele für alle/Überwatch 2") == prefix.path + "/drive_c/Spiele für alle/Überwatch 2", "a Windows one too")
        check(win(#"z:\Volumes\Mein Laufwerk\Spiele\Diablo IV\"#) == "/Volumes/Mein Laufwerk/Spiele/Diablo IV", "Z:, an external drive with a space, backslashes and a trailing one")
        check(mac("/Applications/A..B/World of Warcraft") == "/Applications/A..B/World of Warcraft", "two dots in a name aren't climbing")
        check(mac("/a/../b") == nil && win("C:/a/../b") == nil && win(#"C:\a\..\b"#) == nil, "“..” anywhere isn't followed")
        check(win("D:/Games") == nil && win("Q:/") == nil, "drives Wine isn't known to have")
        check(win("C:/") == nil && win("Z:") == nil && win("C:") == nil, "a drive alone isn't a folder")
        check(mac("") == nil && win("") == nil, "no folder at all")
        check(mac("Applications/x") == nil, "a Mac path has to start at the root")
        // A card of a Windows game keeps the Windows path for `ps`, whichever slashes the file used.
        var install = ProductDB.Install()
        install.code = "pro"
        install.installPath = "C:/Program Files (x86)/Über watch"
        install.installed = true
        install.playable = true
        let cards = BattleNetLibrary.games([install], client: .windows(prefix: prefix)) { _ in true }
        check(cards.first?.installDirName == #"Program Files (x86)\Über watch"#, "what ps shows of it: \(cards.first?.installDirName ?? "none")")
    }

    static func waitingForDrive() {
        var install = ProductDB.Install()
        install.code = "wow"
        install.installPath = "/Volumes/Mein T7/Spiele/World of Warcraft"
        install.installed = true
        install.playable = true
        let waiting = BattleNetLibrary.games([install], client: .mac) { _ in false }
        check(waiting.count == 1 && waiting.first?.missingDrive == "Mein T7" && waiting.first?.install == .notInstalled,
              "the folder and its drive gone: waits for the drive: \(waiting.map(\.missingDrive))")
        let uninstalled = BattleNetLibrary.games([install], client: .mac) { $0.path == "/Volumes/Mein T7" }
        check(uninstalled.isEmpty, "the drive there and the folder not: uninstalled, no card")
        var onTheMac = install
        onTheMac.installPath = "/Applications/World of Warcraft"
        check(BattleNetLibrary.games([onTheMac], client: .mac) { _ in false }.isEmpty, "gone from the Mac itself: no card, nothing waits")
    }

    static func logs() {
        let folder = work.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func put(_ name: String, _ data: Data) { try? data.write(to: folder.appendingPathComponent(name)) }
        check(!BattleNetClient.isSignedIn(logs: folder.appendingPathComponent("no such folder")), "no logs folder: not signed in")
        check(!BattleNetClient.isSignedIn(logs: folder), "an empty folder: not signed in")
        put("battle.net-20261108T100000.log", Data())
        check(!BattleNetClient.isSignedIn(logs: folder), "an empty log says nothing")
        var bytes = Data((0..<256).map { UInt8($0) })
        bytes.append(Data(BattleNetClient.accountReady.utf8))
        bytes.append(Data((0..<256).map { UInt8($0) }))
        put("battle.net-20261108T100000.log", bytes)
        check(BattleNetClient.isSignedIn(logs: folder), "bytes that aren't text don't hide the sign-in")
        put("battle.net-20261108T110000.log", Data(BattleNetClient.pageAsks.utf8))
        check(!BattleNetClient.isSignedIn(logs: folder), "the newest log with something to say wins")
        put("battle.net-20261108T120000.log", Data("a start that hasn't got that far".utf8))
        check(!BattleNetClient.isSignedIn(logs: folder), "a newer log that says nothing is passed over")
        put("agent-20261108T130000.log", Data(BattleNetClient.accountReady.utf8))
        put("battle.net-20261108T130000.txt", Data(BattleNetClient.accountReady.utf8))
        check(!BattleNetClient.isSignedIn(logs: folder), "only battle.net-*.log counts")
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("battle.net-20261108T140000.log", isDirectory: true), withIntermediateDirectories: true)
        check(!BattleNetClient.isSignedIn(logs: folder), "a folder with a log's name doesn't either")
    }
}
