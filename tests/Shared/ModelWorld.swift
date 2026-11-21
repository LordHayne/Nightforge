// The real LibraryModel on a made-up Mac: an empty home with Nightforge's Steam folders and a GOG library in it,
// no window, no network. What the model can then do is everything that decides from what its stores found:
// the selection, the pages, the marks, the downloads, the questions it asks.
//
// Never from here: launch, startInput, connecting a store, anything with Steam for Mac. The model would go on to
// the real processes of this Mac. The run.sh sets HOME and CFFIXED_USER_HOME; `begin` stops the test if it's the
// real home all the same.
import AppKit
import Foundation

/// Every address fails at once: nothing leaves the test, and a scan doesn't wait for a server.
final class NoNetwork: URLProtocol {
    nonisolated(unsafe) static var asked: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.asked.append(request.url?.absoluteString ?? "")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@MainActor
enum ModelWorld {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// First thing in main().
    static func begin() {
        guard let real = getpwuid(getuid()).flatMap({ String(cString: $0.pointee.pw_dir) }), real != home.path else {
            print("✗ the run.sh didn't give the test a home of its own")
            exit(1)
        }
        TestDefaults.useWorkFolder()
        URLProtocol.registerClass(NoNetwork.self)
        _ = NSApplication.shared  // the model asks NSApp whether it's in front; no window, no Dock icon without run()
        try? FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Engine.steamRoot.appendingPathComponent("steam.exe").path, contents: Data())
    }

    static var steamapps: URL { Engine.steamRoot.appendingPathComponent("steamapps", isDirectory: true) }
    static var gogFolder: URL { Engine.supportDir.appendingPathComponent("GOG", isDirectory: true) }

    /// A game in Nightforge's Steam. `flags` as Steam writes them: 4 installed, 1026 waiting for its download.
    static func steamGame(_ appID: Int, _ name: String, flags: Int = 4, size: Int64 = 1_000_000_000, toDownload: Int64 = 0,
                          downloaded: Int64 = 0, lastPlayed: Int = 0, updateResult: Int = 0) {
        let folder = name.replacingOccurrences(of: ":", with: "")
        let dir = steamapps.appendingPathComponent("common/\(folder)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("\(folder).exe").path, contents: Data("MZ".utf8))
        let manifest = """
        "AppState"
        {
        \t"appid"\t\t"\(appID)"
        \t"name"\t\t"\(name)"
        \t"StateFlags"\t\t"\(flags)"
        \t"installdir"\t\t"\(folder)"
        \t"LastPlayed"\t\t"\(lastPlayed)"
        \t"SizeOnDisk"\t\t"\(size)"
        \t"BytesToDownload"\t\t"\(toDownload)"
        \t"BytesDownloaded"\t\t"\(downloaded)"
        \t"UpdateResult"\t\t"\(updateResult)"
        \t"buildid"\t\t"1"
        }

        """
        try? manifest.write(to: steamapps.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
    }

    /// Steam has forgotten it: manifest and folder gone.
    static func removeSteamGame(_ appID: Int, _ name: String) {
        try? FileManager.default.removeItem(at: steamapps.appendingPathComponent("appmanifest_\(appID).acf"))
        try? FileManager.default.removeItem(at: steamapps.appendingPathComponent("common/\(name.replacingOccurrences(of: ":", with: ""))"))
    }

    /// GOG connected, with these games in the account (not on the Mac). A model reads it once: before its first scan.
    static func gogLibrary(_ games: [(id: String, title: String)]) {
        try? FileManager.default.createDirectory(at: gogFolder, withIntermediateDirectories: true)
        try? Data(#"{"username":"tester"}"#.utf8).write(to: gogFolder.appendingPathComponent("account.json"))
        var library = GOGLibrary()
        library.games = games.map { GOGGame(id: $0.id, title: $0.title) }
        try? JSONEncoder().encode(library).write(to: gogFolder.appendingPathComponent("library.json"))
    }

    /// A scan asked for and done, the way ⌘R's is.
    static func scan(_ model: LibraryModel) async {
        let before = model.lastScan
        model.reload()
        for _ in 0..<1200 {
            if model.lastScan != before, !model.isScanning { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        print("✗ a scan didn't finish within 30 s")
        exit(1)
    }

    /// Lets what the model started by itself (a look at a game, a question to its store) run.
    static func settle(_ milliseconds: Int = 30) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// The same numbers on every Mac; the seed that failed is in the message.
struct WorldRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ limit: Int) -> Int { limit <= 0 ? 0 : Int(next() % UInt64(limit)) }
    mutating func pick<T>(_ list: [T]) -> T { list[below(list.count)] }
}
