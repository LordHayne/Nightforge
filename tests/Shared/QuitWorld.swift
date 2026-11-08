// One run's world for Nightforge's quit script (Engine.steamShutdownScript): stand-ins for ps, pgrep, open,
// osascript, lsof, sleep, wine and wineserver in a folder of the test's own, and every argument the script
// takes – nothing real is asked or ended. Compiled into tests/QuitDrivesTest and tests/BugQuitExternalLibrariesTest.
import Foundation

struct QuitWorld {
    let root: URL
    let app: String
    var bin: URL { root.appendingPathComponent("bin") }
    var log: URL { root.appendingPathComponent("calls.log") }
    var processList: URL { root.appendingPathComponent("processes.tsv") }
    var wine: URL { root.appendingPathComponent("engine/bin/wine") }
    var prefix: URL { root.appendingPathComponent("Prefix") }
    var steamapps: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps") }
    var macSteamapps: URL { root.appendingPathComponent("Library/Application Support/Steam/steamapps") }
    var script: URL { root.appendingPathComponent("steam-shutdown.sh") }

    /// `folder`: the name of the world's own folder, under the system's temporary one.
    init(folder: String = "quit-\(UUID().uuidString)", app appName: String = "Applications/Nightforge.app") {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        app = root.appendingPathComponent(appName).path
        let record = "echo \"$(basename \"$0\") $*\" >> \"$FAKE_LOG\""
        write("""
            #!/bin/sh
            case "$*" in
              *pid=*) awk -F'\\t' '{ printf "%s %s\\n", $1, $2 }' "$FAKE_PS" ;;
              *) awk -F'\\t' '{ print $2 }' "$FAKE_PS" ;;
            esac
            """, to: bin.appendingPathComponent("ps"), executable: true)
        // `pgrep -qx steam_osx` answers yes only when the test says Steam for Mac runs.
        write("#!/bin/sh\n[ -n \"$FAKE_MAC_STEAM\" ]\n", to: bin.appendingPathComponent("pgrep"), executable: true)
        write("#!/bin/sh\nexit 0\n", to: bin.appendingPathComponent("lsof"), executable: true)
        write("#!/bin/sh\nexit 0\n", to: bin.appendingPathComponent("sleep"), executable: true)
        write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("open"), executable: true)
        write("#!/bin/sh\n\(record)\n", to: bin.appendingPathComponent("osascript"), executable: true)
        write("#!/bin/sh\n\(record)\n", to: wine, executable: true)
        write("#!/bin/sh\n\(record)\n", to: wine.deletingLastPathComponent().appendingPathComponent("wineserver"), executable: true)
        write(Engine.steamShutdownScript, to: script)
        try? FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: macSteamapps, withIntermediateDirectories: true)
    }

    func write(_ text: String, to url: URL, executable: Bool = false) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
        if executable { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    /// The processes the stand-in `ps` lists: pid and command.
    func processes(_ list: [(Int, String)]) {
        write(list.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n") + "\n", to: processList)
    }

    /// A download in `library` (a steamapps folder): its folder in downloading/ and, unless nil, its manifest.
    func download(_ appID: Int, flags: Int?, in library: URL) {
        try? FileManager.default.createDirectory(at: library.appendingPathComponent("downloading/\(appID)"),
                                                 withIntermediateDirectories: true)
        if let flags {
            write("\"AppState\"\n{\n\t\"appid\"\t\t\"\(appID)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n}\n",
                  to: library.appendingPathComponent("appmanifest_\(appID).acf"))
        }
    }

    /// Runs the script; what the stand-ins were asked, one call a line.
    func run(limit: Int? = nil, macLibrary: String = "", quitMac: Bool = false, macSteamRuns: Bool = false,
             restart: Bool = false, app: String? = nil) -> (calls: [String], status: Int32, timedOut: Bool) {
        try? FileManager.default.removeItem(at: log)
        var environment = ["PATH": bin.path + ":/usr/bin:/bin:/usr/sbin", "FAKE_PS": processList.path, "FAKE_LOG": log.path,
                           "HOME": root.path]
        if let limit { environment["NIGHTFORGE_QUIT_LIMIT"] = String(limit) }
        if macSteamRuns { environment["FAKE_MAC_STEAM"] = "1" }
        let outcome = Subprocess.run("/bin/bash", [script.path, wine.path, prefix.path, macLibrary, quitMac ? "1" : "0", app ?? self.app,
                                                   "", "1", "0", "", "", restart ? "1" : "0"],
                                     environment: environment, timeout: 60)
        let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return (calls, outcome.status, outcome.timedOut)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    static let steam = #"C:\Program Files (x86)\Steam\steam.exe -silent"#

    static func endedSteam(_ calls: [String]) -> Bool {
        calls.contains { $0.hasPrefix("wine ") && $0.contains("-shutdown") } && calls.contains("wineserver -k")
    }
}
