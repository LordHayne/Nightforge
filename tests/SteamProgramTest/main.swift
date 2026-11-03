// Checks which program starts a Steam game (SteamProgram), with Steam's files made up in a
// temporary folder – never the localconfig.vdf of a real Steam:
// - appinfo's launch options: Rocket League's without anti-cheat starts another program
//   (RocketLeague.exe, type option1) and goes by steam://launch; 7 Days to Die's keeps its program
//   and only adds arguments (antiCheatOffArguments, as before).
// - The program choice of the options, a profile's and D3DMetal's DirectX 12 program (GameProgram)
//   reach Steam as LaunchOptions "\"…\" %command%" – or as Steam's own launch option when it has one.
// - localconfig.vdf: the LaunchOptions line comes and goes, the rest stays as Steam wrote it, and
//   the player's own LaunchOptions are never touched.
// tests/SteamProgramTest/run.sh
import Foundation

@main
struct SteamProgramTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let fm = FileManager.default
    static let temp = fm.temporaryDirectory.appendingPathComponent("SteamProgramTest-\(UUID().uuidString)", isDirectory: true)
    static let steam = temp.appendingPathComponent("Steam", isDirectory: true)
    static let common = steam.appendingPathComponent("steamapps/common", isDirectory: true)

    static func main() {
        try? fm.createDirectory(at: steam.appendingPathComponent("appcache"), withIntermediateDirectories: true)
        try? appinfo(apps).write(to: steam.appendingPathComponent("appcache/appinfo.vdf"))
        launchEntries()
        routes()
        launchOptionsValue()
        editing()
        accounts()
        steamCommands()
        try? fm.removeItem(at: temp)
        print(failures == 0 ? "✓ SteamProgram" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Binary KeyValues as Steam writes them (as in StoreFactsTest)

    indirect enum KV {
        case object([(String, KV)])
        case string(String)
        case int(Int32)
    }

    static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) } }
    static func le64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(value >> (8 * UInt64($0)) & 0xFF) } }

    static func encode(_ pairs: [(String, KV)], table: inout [String]) -> [UInt8] {
        var out: [UInt8] = []
        for (key, value) in pairs {
            switch value {
            case .object: out.append(0)
            case .string: out.append(1)
            case .int: out.append(2)
            }
            if let index = table.firstIndex(of: key) {
                out += le32(UInt32(index))
            } else {
                table.append(key)
                out += le32(UInt32(table.count - 1))
            }
            switch value {
            case .object(let children): out += encode(children, table: &table)
            case .string(let text): out += Array(text.utf8) + [0]
            case .int(let number): out += le32(UInt32(bitPattern: number))
            }
        }
        return out + [8]
    }

    static func appinfo(_ apps: [(Int, [(String, KV)])]) -> Data {
        var table: [String] = []
        var body: [UInt8] = []
        for (appID, info) in apps {
            let kv = encode([("appinfo", .object(info))], table: &table)
            let header = [UInt8](repeating: 0, count: 60)
            body += le32(UInt32(appID)) + le32(UInt32(header.count + kv.count)) + header + kv
        }
        body += le32(0)
        let tableOffset = 16 + body.count
        var strings = le32(UInt32(table.count))
        for key in table { strings += Array(key.utf8) + [0] }
        return Data(le32(0x0756_4429) + le32(1) + le64(UInt64(tableOffset)) + body + strings)
    }

    /// One launch option of config/launch.
    static func option(_ executable: String, type: String = "default", os: String = "windows", arguments: String = "",
                       description: String = "", betaKey: String = "") -> KV {
        var config: [(String, KV)] = os.isEmpty ? [] : [("oslist", .string(os))]
        if !betaKey.isEmpty { config.append(("betakey", .string(betaKey))) }
        var pairs: [(String, KV)] = [("executable", .string(executable)), ("type", .string(type))]
        if !arguments.isEmpty { pairs.append(("arguments", .string(arguments))) }
        if !description.isEmpty { pairs.append(("description", .string(description))) }
        pairs.append(("config", .object(config)))
        return .object(pairs)
    }

    static func game(_ name: String, _ installdir: String, _ launch: [(String, KV)]) -> [(String, KV)] {
        [("common", .object([("name", .string(name)), ("type", .string("Game"))])),
         ("config", .object([("installdir", .string(installdir)), ("launch", .object(launch))]))]
    }

    static let rocketLeague = 252950, sevenDays = 251570, control = 870780, cyberpunk = 1091500, twin = 9001

    /// Launch options as Steam's catalog has them (api.steamcmd.net, 3.11.2026) – Twin is made up:
    /// two options of the same type.
    static let apps: [(Int, [(String, KV)])] = [
        (rocketLeague, game("Rocket League", "rocketleague", [
            ("0", option("Binaries/Win64/RocketLeague_EAC.exe")),
            ("1", option("RocketLeague.app/Contents/MacOS/TAGame", os: "macos")),
            ("2", option("Binaries/Linux/RocketLeague", os: "linux")),
            ("4", option("Binaries/Win64/RocketLeague.exe", type: "option1",
                         description: "Rocket League with Anti-Cheat Disabled (Mods and Limited Online Play)")),
        ])),
        (sevenDays, game("7 Days to Die", "7 Days To Die", [
            ("0", option("7dLauncher.exe", type: "none", arguments: "-from-steam", description: "Launch game")),
            ("2", option("7dLauncher.app", type: "none", os: "macos", arguments: "-from-steam")),
            ("6", option("7dLauncher.exe", type: "none", arguments: "-show-launcher -from-steam", description: "Show game launcher")),
            ("9", option("7dLauncher.exe", type: "", arguments: "-from-steam -forceeac off", description: "Launch game without EAC")),
        ])),
        (control, game("Control", "Control", [
            ("0", option("Control.exe", type: "none")),
            ("1", option("Game.app", os: "macos")),
        ])),
        (cyberpunk, game("Cyberpunk 2077", "Cyberpunk 2077", [
            ("1", option("redprelauncher.exe")),
            ("2", option("bin\\x64\\Cyberpunk2077.exe", os: "", description: "Cyberpunk2077 early access", betaKey: "pc_preview_a")),
            ("3", option("Cyberpunk2077.app", os: "macos")),
        ])),
        (twin, game("Twin", "Twin", [
            ("0", option("Game.exe")),
            ("1", option("Game_DX12.exe", type: "option1", description: "DirectX 12")),
            ("2", option("Game_Vulkan.exe", type: "option1", description: "Vulkan")),
        ])),
    ]

    /// A game folder with empty programs.
    static func folder(_ name: String, _ programs: [String]) -> URL {
        let dir = common.appendingPathComponent(name, isDirectory: true)
        for program in programs {
            let file = dir.appendingPathComponent(program)
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: file.path, contents: Data())
        }
        return dir
    }

    static func entries(_ appID: Int) -> [SteamCatalog.LaunchEntry] { SteamCatalog.launchEntries(appID: appID, steamRoot: steam) }

    static func launchEntries() {
        let rl = entries(rocketLeague)
        check(rl.map(\.executable) == ["Binaries/Win64/RocketLeague_EAC.exe", "Binaries/Win64/RocketLeague.exe"],
              "Rocket League: its two Windows options, default first: \(rl.map(\.executable))")
        check(rl.map(\.type) == ["default", "option1"], "with their types")
        check(SteamCatalog.antiCheatOff(rl)?.executable == "Binaries/Win64/RocketLeague.exe", "its option without anti-cheat")
        check(SteamCatalog.antiCheatOffArguments(rl).isEmpty, "another program: no arguments added to the default option")
        check(SteamProgram.storeProgram(rl) == "Binaries/Win64/RocketLeague.exe", "counted as the store's program")
        check(SteamCatalog.antiCheatOffArguments(appID: sevenDays, steamRoot: steam) == ["-forceeac", "off"],
              "7 Days to Die: the same program, its option's arguments as before")
        check(SteamProgram.storeProgram(entries(sevenDays)) == "7dLauncher.exe", "7 Days to Die keeps its program")
        check(SteamProgram.storeProgram(entries(control)) == "Control.exe" && SteamCatalog.antiCheatOff(entries(control)) == nil,
              "Control: Steam's one Windows program")
        check(entries(cyberpunk).last?.betaKey == "pc_preview_a", "an option for a beta branch says so")
        check(entries(424242).isEmpty && SteamProgram.storeProgram([]) == nil, "a game Steam doesn't know: nothing")
    }

    static func route(_ appID: Int, _ dir: URL, _ layer: GraphicsLayer = .dxmt, chosen: String = "", profile: String? = nil)
        -> SteamProgram.Route {
        SteamProgram.route(entries: entries(appID), installDir: dir, layer: layer, chosen: chosen, profile: profile)
    }

    static func routes() {
        let rlDir = folder("rocketleague", ["Binaries/Win64/RocketLeague.exe", "Binaries/Win64/RocketLeague_EAC.exe"])
        let withoutEAC = SteamProgram.Route.option(type: "Option1", executable: "Binaries/Win64/RocketLeague.exe")
        check(route(rocketLeague, rlDir) == withoutEAC, "Rocket League: Steam's option without anti-cheat: \(route(rocketLeague, rlDir))")
        check(route(rocketLeague, rlDir, .d3dmetal) == withoutEAC, "on any layer")
        check(route(rocketLeague, common.appendingPathComponent("gone")) == withoutEAC, "Steam's own option needs no check of the folder")
        check(route(rocketLeague, rlDir, chosen: "Binaries/Win64/RocketLeague_EAC.exe") == .standard,
              "the player picks the one with anti-cheat: Steam's default")
        check(SteamProgram.url(appID: rocketLeague, type: "Option1") == "steam://launch/252950/Option1", "steam://launch/<id>/<type>")

        let sevenDir = folder("7 Days To Die", ["7dLauncher.exe", "7DaysToDie.exe"])
        check(route(sevenDays, sevenDir) == .standard, "7 Days to Die: -applaunch with its arguments, as before")

        let controlDir = folder("Control", ["Control.exe", "Control_DX11.exe", "Control_DX12.exe"])
        check(route(control, controlDir) == .standard, "Control on DXMT: Steam's program")
        check(route(control, controlDir, .d3dmetal) == .program("Control_DX12.exe"), "on D3DMetal its DirectX 12 program")
        check(route(control, controlDir, chosen: "Control_DX11.exe") == .program("Control_DX11.exe"), "the options' pick")
        check(route(control, controlDir, .d3dmetal, chosen: "Control.exe") == .standard, "picking Steam's own beats D3DMetal's")
        check(route(control, controlDir, .dxvk, profile: "Control_DX12.exe") == .program("Control_DX12.exe"), "a profile's program")
        check(route(control, controlDir, chosen: "../rocketleague/Binaries/Win64/RocketLeague.exe") == .standard,
              "a pick outside the game folder counts as none")
        check(route(control, controlDir, chosen: "Control_DX10.exe") == .standard, "a pick that isn't there counts as none")

        let cyberDir = folder("Cyberpunk 2077", ["redprelauncher.exe", "bin/x64/Cyberpunk2077.exe"])
        check(route(cyberpunk, cyberDir, chosen: "bin\\x64\\Cyberpunk2077.exe") == .program("bin/x64/Cyberpunk2077.exe"),
              "Cyberpunk's game without its launcher: the option for a beta branch isn't Steam's way to it")

        let twinDir = folder("Twin", ["Game.exe", "Game_DX12.exe", "Game_Vulkan.exe"])
        check(route(twin, twinDir, chosen: "Game_DX12.exe") == .program("Game_DX12.exe"),
              "two options of one type: Steam would take the first, so the LaunchOptions")
        check(route(twin, twinDir, chosen: "Game.exe") == .standard, "Steam's default picked: -applaunch")

        // The convenience a start uses: the game's own Steam and folder.
        let bottle = Bottle(name: "Nightforge", url: temp, isBuiltIn: true)
        let game = Game(appID: control, name: "Control", bottle: bottle, steamRoot: steam, steamExeWindowsPath: "C:\\steam.exe",
                        installDir: controlDir, sizeOnDisk: 0)
        var options = GameOptions()
        options.program = "Control_DX11.exe"
        check(SteamProgram.route(game, layer: .dxmt, options: options, profile: nil) == .program("Control_DX11.exe"),
              "a Game's start reads its Steam's catalog")
    }

    static func launchOptionsValue() {
        let dir = common.appendingPathComponent("Control", isDirectory: true)
        let value = SteamProgram.launchOptions(.program("Control_DX12.exe"), installDir: dir)
        check(value == "\"" + Engine.windowsPath(of: dir.appendingPathComponent("Control_DX12.exe")) + "\" %command%",
              "the program's Windows path before Steam's command: \(value ?? "nil")")
        check(value?.hasPrefix("\"Z:\\") == true && value?.contains("/") == false, "a Windows path (here outside the prefix: Z:)")
        check(SteamProgram.launchOptions(.standard, installDir: dir) == nil
              && SteamProgram.launchOptions(.option(type: "Option1", executable: "a.exe"), installDir: dir) == nil,
              "no LaunchOptions for Steam's own options")
        check(SteamProgram.isOurs(value ?? ""), "recognised as Nightforge's")
        for own in ["-novid", "", "\"C:\\Tools\\loader.exe\" %command% -novid", "%command% -dx11", "\"C:\\a.exe\" \"x\" %command%"] {
            check(!SteamProgram.isOurs(own), "the player's own: \(own)")
        }
    }

    // A localconfig.vdf as Steam writes it (cut down): JSON values with escaped quotes and
    // backslashes, a game with the player's own LaunchOptions.
    static let localconfig = """
        "UserLocalConfigStore"
        {
        \t"Broadcast"
        \t{
        \t\t"Permissions"\t\t"1"
        \t}
        \t"Software"
        \t{
        \t\t"Valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        \t\t\t\t"apps"
        \t\t\t\t{
        \t\t\t\t\t"870780"
        \t\t\t\t\t{
        \t\t\t\t\t\t"LastPlayed"\t\t"1761900000"
        \t\t\t\t\t\t"Playtime"\t\t"42"
        \t\t\t\t\t}
        \t\t\t\t\t"251570"
        \t\t\t\t\t{
        \t\t\t\t\t\t"LaunchOptions"\t\t"-novid"
        \t\t\t\t\t}
        \t\t\t\t}
        \t\t\t\t"FriendsUI"\t\t"{\\"bSignIntoFriends\\":true}"
        \t\t\t}
        \t\t}
        \t}
        \t"WebStorage"
        \t{
        \t\t"Key"\t\t"{\\"path\\":\\"C:\\\\\\\\Games\\"}"
        \t}
        }

        """

    static let value = #""C:\Program Files (x86)\Steam\steamapps\common\Control\Control_DX12.exe" %command%"#

    static func launchOptions(_ text: String?, _ appID: Int) -> String? {
        VDF.parse(text ?? "")?["UserLocalConfigStore"]?["Software"]?["Valve"]?["Steam"]?["apps"]?[String(appID)]?["LaunchOptions"]?.string
    }

    static func editing() {
        check(launchOptions(localconfig, sevenDays) == "-novid", "the sample reads as Steam's")
        // A game Steam has an entry for: the line goes in first thing after its brace.
        let set = SteamProgram.edited(localconfig, appID: control, value: value)
        check(launchOptions(set, control) == value, "set, quotes and backslashes as written: \(launchOptions(set, control) ?? "nil")")
        let line = "\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"\\\"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Control\\\\Control_DX12.exe\\\" %command%\""
        check(set?.replacingOccurrences(of: line, with: "") == localconfig, "the rest exactly as Steam wrote it")
        check(set?.contains("\t\t\t\t\t{" + line + "\n\t\t\t\t\t\t\"LastPlayed\"") == true, "indented as Steam's own lines")
        check(launchOptions(set, sevenDays) == "-novid", "the other game's stay")
        check(SteamProgram.edited(set ?? "", appID: control, value: value) == nil, "the same again: no change")
        let other = value.replacingOccurrences(of: "DX12", with: "DX11")
        let replaced = SteamProgram.edited(set ?? "", appID: control, value: other)
        check(launchOptions(replaced, control) == other && replaced?.components(separatedBy: "LaunchOptions").count == 3,
              "Nightforge's own replaced in place")
        check(SteamProgram.edited(replaced ?? "", appID: control, value: nil) == localconfig, "and taken away: Steam's file as it was")
        check(SteamProgram.edited(localconfig, appID: control, value: nil) == nil, "nothing of Nightforge's: nothing to take away")

        // The player's own stay, whatever Nightforge wants.
        check(SteamProgram.edited(localconfig, appID: sevenDays, value: value) == nil, "the player's own LaunchOptions aren't replaced")
        check(SteamProgram.edited(localconfig, appID: sevenDays, value: nil) == nil, "nor taken away")
        let empty = localconfig.replacingOccurrences(of: "\"-novid\"", with: "\"\"")
        check(launchOptions(SteamProgram.edited(empty, appID: sevenDays, value: value), sevenDays) == value,
              "empty LaunchOptions are no one's")

        // A game Steam has no entry for yet, and an account that has played nothing.
        let added = SteamProgram.edited(localconfig, appID: rocketLeague, value: value)
        check(launchOptions(added, rocketLeague) == value, "a new entry under apps")
        check(launchOptions(added, sevenDays) == "-novid" && VDF.parse(added ?? "")?["UserLocalConfigStore"]?["Software"]?["Valve"]?["Steam"]?["apps"]?["870780"]?["Playtime"]?.string == "42",
              "the other entries intact")
        let gone = SteamProgram.edited(added ?? "", appID: rocketLeague, value: nil)
        check(gone != nil && launchOptions(gone, rocketLeague) == nil
              && VDF.parse(gone ?? "")?["UserLocalConfigStore"]?["Software"]?["Valve"]?["Steam"]?["apps"]?[String(rocketLeague)] != nil,
              "taken away again, its entry stays (as Steam keeps them)")
        let noApps = """
            "UserLocalConfigStore"
            {
            \t"Software"
            \t{
            \t\t"Valve"
            \t\t{
            \t\t\t"Steam"
            \t\t\t{
            \t\t\t\t"FriendsUI"\t\t"1"
            \t\t\t}
            \t\t}
            \t}
            }

            """
        check(launchOptions(SteamProgram.edited(noApps, appID: control, value: value), control) == value, "no apps yet: made")
        let bare = "\"UserLocalConfigStore\"\n{\n\t\"Broadcast\"\t\t\"1\"\n}\n"
        let fromBare = SteamProgram.edited(bare, appID: control, value: value)
        check(launchOptions(fromBare, control) == value, "only the root: every level made")
        check(VDF.parse(fromBare ?? "")?["UserLocalConfigStore"]?["Broadcast"]?.string == "1", "beside what was there")

        // Windows line ends, as Steam on Windows may write them.
        let crlf = localconfig.replacingOccurrences(of: "\n", with: "\r\n")
        let crlfSet = SteamProgram.edited(crlf, appID: control, value: value)
        check(launchOptions(crlfSet, control) == value && crlfSet?.contains("{\r\n\t\t\t\t\t\t\"LaunchOptions\"") == true,
              "CRLF: its own line ends")
        check(SteamProgram.edited(crlfSet ?? "", appID: control, value: nil) == crlf, "and away again, as it was")

        // Not a localconfig.vdf: left alone.
        check(SteamProgram.edited(String(localconfig.prefix(200)), appID: control, value: value) == nil, "cut off: left alone")
        check(SteamProgram.edited("not a config", appID: control, value: value) == nil, "not KeyValues: left alone")
        check(SteamProgram.edited("\"InstallConfigStore\"\n{\n}\n", appID: control, value: value) == nil, "another file: left alone")
        check(SteamProgram.edited("", appID: control, value: value) == nil, "empty: left alone")
    }

    static func accounts() {
        // Two accounts signed in to this Steam; the second set its own LaunchOptions for Control.
        let first = steam.appendingPathComponent("userdata/111/config/localconfig.vdf")
        let second = steam.appendingPathComponent("userdata/222/config/localconfig.vdf")
        let own = localconfig.replacingOccurrences(of: "\"Playtime\"\t\t\"42\"", with: "\"Playtime\"\t\t\"42\"\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-windowed\"")
        for (file, text) in [(first, localconfig), (second, own)] {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        try? fm.createDirectory(at: steam.appendingPathComponent("userdata/333"), withIntermediateDirectories: true)  // no config yet
        func read(_ file: URL) -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }

        check(SteamProgram.prepare(appID: control, value: value, steamRoot: steam), "a new program: Steam has to restart")
        check(read(first) == localconfig, "prepare writes nothing (Steam may be running)")
        SteamProgram.apply(steamRoot: steam)
        check(launchOptions(read(first), control) == value, "written with Steam down")
        check(read(second) == own, "the account with its own LaunchOptions: untouched")
        check(!fm.fileExists(atPath: steam.appendingPathComponent("userdata/333/config/localconfig.vdf").path),
              "an account without a config gets none")
        check(!SteamProgram.prepare(appID: control, value: value, steamRoot: steam), "the same again: no restart")
        SteamProgram.apply(steamRoot: steam)
        check(launchOptions(read(first), control) == value && read(second) == own, "applying again changes nothing")

        check(SteamProgram.prepare(appID: control, value: nil, steamRoot: steam), "back to Steam's program: a restart")
        SteamProgram.apply(steamRoot: steam)
        check(read(first) == localconfig && read(second) == own, "Nightforge's LaunchOptions gone, the player's kept")
        check(!SteamProgram.prepare(appID: control, value: nil, steamRoot: steam), "and then nothing more to do")
    }

    static func steamCommands() {
        let url: Substring = #"[2026-11-03 01:00:00] ExecCommandLine: ""C:\Program Files (x86)\Steam\steam.exe" -silent steam://launch/252950/Option1""#
        check(SteamCommands.isLaunch(url, appID: rocketLeague), "Steam took the start of its own launch option")
        check(!SteamCommands.isLaunch(url, appID: 25295), "not another game's")
        let applaunch: Substring = #"[2026-11-03 01:00:00] ExecCommandLine: ""C:\Program Files (x86)\Steam\steam.exe" -silent -applaunch 870780""#
        check(SteamCommands.isLaunch(applaunch, appID: control), "-applaunch as before")
    }
}
