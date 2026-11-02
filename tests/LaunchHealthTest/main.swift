// Checks GameAnalysis, LaunchHealth, GameLog and FramePacing: tests/LaunchHealthTest/run.sh [Steam folder]
import AppKit
import Foundation

@main
struct LaunchHealthTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A minimal 64-bit Windows program whose only content is an import table naming `imports`.
    static func writePE(_ url: URL, imports: [String]) {
        var bytes = [UInt8](repeating: 0, count: 0x400)
        func put16(_ value: Int, _ at: Int) { bytes[at] = UInt8(value & 0xFF); bytes[at + 1] = UInt8(value >> 8 & 0xFF) }
        func put32(_ value: Int, _ at: Int) { put16(value & 0xFFFF, at); put16(value >> 16, at + 2) }
        bytes[0] = 0x4D; bytes[1] = 0x5A                                    // "MZ"
        put32(0x40, 0x3C)                                                   // → PE header
        bytes.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0, 0])        // "PE\0\0"
        put16(0x8664, 0x44); put16(1, 0x46); put16(240, 0x54)               // x86-64, 1 section, PE32+ header
        let optional = 0x58
        put16(0x20B, optional)                                              // PE32+
        put32(0x1000, optional + 112 + 8); put32(20 * (imports.count + 1), optional + 112 + 12)  // import directory
        let section = optional + 240
        put32(0x200, section + 8); put32(0x1000, section + 12); put32(0x200, section + 16); put32(0x200, section + 20)
        var name = 0x200 + 20 * (imports.count + 1)
        for (index, dll) in imports.enumerated() {
            put32(0x1000 + name - 0x200, 0x200 + index * 20 + 12)           // descriptor → name
            bytes.replaceSubrange(name..<name + dll.utf8.count, with: Array(dll.utf8))
            name += dll.utf8.count + 1
        }
        FileManager.default.createFile(atPath: url.path, contents: Data(bytes))
    }

    /// The ladder on an engine as asked – not the one installed on this Mac.
    static func ids(_ analysis: GameAnalysis, _ profileJSON: String? = nil, d3dMetal: Bool = false, vulkanLayer: Bool = true) -> [String] {
        let profile = profileJSON.flatMap { try? JSONDecoder().decode(GameProfile.self, from: Data($0.utf8)) }
        return LaunchHealth.attempts(for: analysis, profile: profile, d3dMetal: d3dMetal, vulkanLayer: vulkanLayer).map(\.id)
    }

    static func main() {
        // MARK: Ladders
        check(ids(GameAnalysis(apis: [.d3d11])) == ["dxmt", "dxvk"], "DirectX 11: DXMT, then DXVK")
        check(ids(GameAnalysis(apis: [.d3d11]), #"{"graphics": "dxvk"}"#) == ["dxvk", "dxmt"], "a profile's layer goes first")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity)) == ["dxmt -force-d3d11", "dxvk -force-d3d11", "dxmt"],
              "Unity with DirectX 12 is held to 11, 12 comes last")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal)).first == "dxmt -dx11", "Unreal is held to DirectX 11")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12])) == ["dxmt", "dxvk"], "unknown engine: no switch to guess")
        check(ids(GameAnalysis(apis: [.d3d9])) == ["dxvk", "wined3d"], "DirectX 9: DXVK, then WineD3D")
        check(ids(GameAnalysis(apis: [.vulkan])) == ["dxmt"], "Vulkan has one way")
        check(ids(GameAnalysis(apis: [.d3d12])) == ["dxmt"] && GameAnalysis(apis: [.d3d12]).onlyD3D12, "DirectX 12 only")
        check(ids(GameAnalysis()) == ["dxmt", "dxvk"], "nothing detected: the DirectX 11 ladder")

        // With D3DMetal in the engine, DirectX 12 has a way to run; DirectX 11 keeps DXMT first.
        check(ids(GameAnalysis(apis: [.d3d12]), d3dMetal: true) == ["d3dmetal"], "DirectX 12 only: D3DMetal")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal), d3dMetal: true) == ["dxmt -dx11", "dxvk -dx11", "d3dmetal"],
              "Unreal: DirectX 11 on DXMT first, DirectX 12 on D3DMetal last")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12]), d3dMetal: true) == ["dxmt", "dxvk", "d3dmetal"],
              "unknown engine with DirectX 12: D3DMetal after the DirectX 11 ladder")
        check(ids(GameAnalysis(apis: [.d3d11]), d3dMetal: true) == ["dxmt", "dxvk"], "DirectX 11 only: unchanged")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal), #"{"graphics": "d3dmetal"}"#, d3dMetal: true)
              == ["d3dmetal", "dxmt -dx11", "dxvk -dx11"], "a profile that measured DirectX 12 better starts there, without -dx11")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal), #"{"graphics": "d3dmetal"}"#, d3dMetal: false).first == "dxmt -dx11",
              "…but not on an engine without D3DMetal")
        check(ids(GameAnalysis(apis: [.d3d9]), d3dMetal: true) == ["dxvk", "wined3d"], "DirectX 9: unchanged")
        check(ids(GameAnalysis(apis: [.d3d12]), #"{"graphics": "dxvk"}"#, d3dMetal: true) == ["d3dmetal"],
              "a DirectX 11 layer in a profile doesn't apply to a DirectX 12 game")

        // MARK: State
        let appID = 990_001
        let app = GameID.steam(appID)
        let ladder = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11]), profile: nil)
        LaunchHealth.reset(app)
        check(LaunchHealth.current(app, ladder) == (0, false), "starts at the first way")
        LaunchHealth.recordStart(app, ladder)
        check(LaunchHealth.advance(app, ladder), "there is a second way")
        check(LaunchHealth.current(app, ladder) == (1, false), "moved to DXVK")
        // The note says it was handled in plain words; which layer it is shows in the game's options.
        check(LaunchHealth.note(app, ladder) != nil, "a game on another way gets a note")
        LaunchHealth.confirm(app, ladder)
        check(LaunchHealth.current(app, ladder) == (1, true), "DXVK confirmed")
        check(!LaunchHealth.advance(app, ladder) && LaunchHealth.current(app, ladder) == (0, false), "after the last way it starts over")
        let longer = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity), profile: nil)
        _ = LaunchHealth.advance(app, ladder)
        check(LaunchHealth.current(app, longer) == (0, false), "a different ladder starts over")
        LaunchHealth.reset(app)
        UserDefaults.standard.set(true, forKey: "health.dxmtFailed.\(app.key)")
        check(LaunchHealth.current(app, ladder).index == 1, "0.2's \"DXMT failed\" carries over")
        check(UserDefaults.standard.object(forKey: "health.dxmtFailed.\(app.key)") == nil, "the old key is gone")

        // MARK: What a game taught Nightforge (kept under a game ID no store has, removed again)
        let taught = GameID.steam(990_003)
        LearnedFixes.addWinetricks(["vcrun2019", "d3dx9"], for: taught)
        LearnedFixes.addWinetricks(["d3dx9", "xact"], for: taught)
        check(LearnedFixes.winetricks(taught) == ["vcrun2019", "d3dx9", "xact"], "runtimes it needed, each once, in the order found")
        check(LearnedFixes.lastLaunchMark(taught) == nil, "no start noted yet")
        LearnedFixes.setLastLaunch(taught, logMark: 123_456_789_012)
        check(LearnedFixes.lastLaunchMark(taught) == 123_456_789_012, "where its last start begins in the log, past 32 bits too")
        for key in ["learned.winetricks.\(taught.key)", "learned.logMark.\(taught.key)"] { UserDefaults.standard.removeObject(forKey: key) }
        let dx11 = LaunchAttempt(graphics: .dxvk, arguments: ["-dx11"])
        check(dx11.label == GraphicsLayer.dxvk.label + " -dx11" && dx11.shortLabel == GraphicsLayer.dxvk.shortLabel + " -dx11"
              && LaunchAttempt(graphics: .dxmt).label == GraphicsLayer.dxmt.label, "a way's name says its layer and what's added")

        // MARK: Review from Steam's log
        let steam = FileManager.default.temporaryDirectory.appendingPathComponent("lht-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: steam.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func session(seconds: TimeInterval, startedAt start: Date) {
            let lines = [
                "[\(formatter.string(from: start.addingTimeInterval(2)))] Game process added : AppID \(appID) \"C:\\game.exe\", ProcID 100, IP 0.0.0.0:0",
                "[\(formatter.string(from: start.addingTimeInterval(2 + seconds)))] Game process removed: AppID \(appID) \"C:\\game.exe\", ProcID 100",
            ]
            // Steam writes Windows line ends.
            try? (lines.joined(separator: "\r\n") + "\r\n").write(to: steam.appendingPathComponent("logs/console_log.txt"), atomically: true, encoding: .utf8)
        }
        LaunchHealth.reset(app)
        let now = Date().addingTimeInterval(-300)
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 6, startedAt: now)
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (1, false), "a 6 s session moves on")
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 600, startedAt: now)
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (1, true), "a 10 min session confirms")

        // Quit Game in the overlay is the player's end, however short (Sonic Mania on 1.11.).
        LaunchHealth.reset(app)
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 6, startedAt: now)
        check(!LaunchHealth.quitByPlayer(app, since: now), "not quit by the player yet")
        LaunchHealth.playerQuit(app, at: now.addingTimeInterval(8))
        check(LaunchHealth.quitByPlayer(app, since: now), "quit in the overlay 8 s after its start")
        check(!LaunchHealth.quitByPlayer(app, since: now.addingTimeInterval(60)), "that was an earlier start")
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (0, false), "a 6 s session the player quit: the way stays")
        LaunchHealth.reset(app)
        check(!LaunchHealth.quitByPlayer(app, since: now), "reset forgets it")

        // The curtain sank, then the player quit a few seconds in (OxyRail on 1.11., started again on DXVK).
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 6, startedAt: now)
        check(!LaunchHealth.showedPicture(app, since: now), "no picture yet")
        LaunchHealth.pictureShown(app, at: now.addingTimeInterval(4))
        check(LaunchHealth.showedPicture(app, since: now), "the curtain sank 4 s after its start")
        check(!LaunchHealth.showedPicture(app, since: now.addingTimeInterval(60)), "that was an earlier start's picture")
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (0, true), "a 6 s session after a picture: it started, the way is confirmed")
        LaunchHealth.reset(app)
        check(!LaunchHealth.showedPicture(app, since: now), "reset forgets the picture")
        LaunchHealth.recordStart(app, ladder, at: now)
        LaunchHealth.pictureShown(app, at: now.addingTimeInterval(-30))
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (1, false), "a picture from a start before doesn't count: 6 s moves on")
        LaunchHealth.reset(app)

        // MARK: Confirmations from before frames counted (Mafia II's, as it stood in the defaults on 31.10.2026)
        let mafia = GameID.gog("1816059595")
        let d3d9 = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d9]), profile: nil, vulkanLayer: true)
        check(d3d9.map(\.id) == ["dxvk", "wined3d"], "DirectX 9 with Nightforge's Vulkan layer: DXVK, then WineD3D")
        check(LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d9]), profile: nil, vulkanLayer: false).map(\.id) == ["wined3d"],
              "under winecx (no layer, DXVK never gets a device – L4D2, Mafia II): WineD3D only, nothing to move on to")
        // Mafia II's WineD3D start, 1.11.2026: two of DXVK's lines in the shared log ended it and moved it on to DXVK.
        let dxvkLines = "Failed to load ADL library\n[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice(): …\nerr:   DxvkAdapter: Failed to create device\n"
        check(!GameLog.graphicsFailed(in: dxvkLines, layer: .wined3d), "DXVK's failure isn't a WineD3D start failing")
        check(GameLog.graphicsFailed(in: dxvkLines, layer: .dxvk), "on DXVK it is")
        check(!GameLog.graphicsFailed(in: dxvkLines, layer: .dxmt) && !GameLog.graphicsFailed(in: dxvkLines, layer: .d3dmetal),
              "nor on DXMT or D3DMetal")
        UserDefaults.standard.set(Data(#"{"ladder":["dxvk","wined3d"],"confirmed":true,"index":0}"#.utf8), forKey: "launchHealth.gog.1816059595")
        check(LaunchHealth.current(mafia, d3d9) == (0, false), "an old confirmation is checked again at the next start, on the same way")
        check(LaunchHealth.peek(mafia, d3d9).map { $0.confirmed } == false, "and is no \"Runs great\" until then")
        check(LaunchHealth.confirmedWays()[mafia] == nil, "nor a way that ran well for the engine rollback")
        LaunchHealth.confirm(mafia, d3d9)
        check(LaunchHealth.current(mafia, d3d9) == (0, true) && LaunchHealth.confirmedWays()[mafia] == "dxvk", "confirmed anew: it counts")
        LaunchHealth.unconfirm(mafia, d3d9)
        check(LaunchHealth.current(mafia, d3d9) == (0, false), "a confirmed way that ended without a picture: unconfirmed, same way")
        LaunchHealth.confirm(mafia, d3d9)
        check(LaunchHealth.advance(mafia, d3d9) && LaunchHealth.current(mafia, d3d9) == (1, false), "a graphics error: on to WineD3D")
        LaunchHealth.reset(mafia)

        // MARK: A confirmed way loses its confirmation only on evidence
        // The player quits after 20 s (OxyRail after 22 s) on a layer that logs no frames.
        check(LaunchHealth.earlyEnd(trusted: true, graphicsFailed: false, crashed: false, drew: false, shortEndsBefore: 0) == .keep,
              "one short start without a picture: kept")
        check(LaunchHealth.earlyEnd(trusted: true, graphicsFailed: false, crashed: false, drew: false, shortEndsBefore: 1) == .unconfirm,
              "the second in a row: unconfirmed")
        check(LaunchHealth.earlyEnd(trusted: true, graphicsFailed: false, crashed: false, drew: true, shortEndsBefore: 1) == .confirm,
              "one that drew was quit by the player: confirmed, the count starts over")
        check(LaunchHealth.earlyEnd(trusted: true, graphicsFailed: false, crashed: true, drew: false, shortEndsBefore: 0) == .unconfirm,
              "a crash in the log: unconfirmed")
        check(LaunchHealth.earlyEnd(trusted: true, graphicsFailed: true, crashed: false, drew: false, shortEndsBefore: 0) == .nextWay,
              "a graphics error: the next way")
        check(LaunchHealth.earlyEnd(trusted: false, graphicsFailed: false, crashed: false, drew: false, shortEndsBefore: 0) == .nextWay,
              "a way not confirmed yet without a picture moves on, as before")
        // A picture – the curtain sank, or frame lines in the log – then the end within 30 s (OxyRail, Mafia II, 1.11.).
        check(LaunchHealth.earlyEnd(trusted: false, graphicsFailed: false, crashed: false, drew: true, shortEndsBefore: 0) == .confirm,
              "a way not confirmed yet that showed a picture: confirmed, no start again")
        check(LaunchHealth.earlyEnd(trusted: false, graphicsFailed: false, crashed: true, drew: true, shortEndsBefore: 0) == .confirm,
              "an end after the picture isn't a start that didn't take")
        check(LaunchHealth.earlyEnd(trusted: false, graphicsFailed: true, crashed: false, drew: true, shortEndsBefore: 0) == .nextWay,
              "a graphics error still moves on, picture or not")
        check(LaunchHealth.earlyEnd(trusted: false, graphicsFailed: false, crashed: true, drew: false, shortEndsBefore: 0) == .nextWay,
              "a crash without a picture moves on, as before")

        // MARK: A Play while a start before still runs (Valheim started while OxyRail's first seconds were watched, 1.11.)
        check(LibraryModel.mayStart(launching: false, startsAgain: false), "nothing starting: Play starts")
        check(!LibraryModel.mayStart(launching: true, startsAgain: false), "the player's own start in progress: one at a time")
        check(LibraryModel.mayStart(launching: true, startsAgain: true), "Nightforge starting a game again another way gives way to a Play")
        // The player plays 2 minutes on D3DMetal (no frame lines), then quits.
        check(LaunchHealth.afterFirstSeconds(LaunchHealth.verdict(drewFrames: false, running: false, ranFor: 120)) == .keep,
              "two minutes without a frame line: the confirmation stays")
        check(LaunchHealth.afterFirstSeconds(.working) == .confirm && LaunchHealth.afterFirstSeconds(.watching) == .keep, "drew: confirmed")
        LaunchHealth.confirm(mafia, d3d9)
        LaunchHealth.noteStart(mafia, d3d9, short: true)
        check(LaunchHealth.current(mafia, d3d9) == (0, true) && LaunchHealth.shortEnds(mafia, d3d9) == 1, "a short start is counted, the way stays")
        LaunchHealth.noteStart(mafia, d3d9, short: false)
        check(LaunchHealth.shortEnds(mafia, d3d9) == 0, "a normal one in between starts the count over")
        LaunchHealth.reset(mafia)
        check(GameLog.crashed(in: "wine: Unhandled page fault on read access to 00000000 at address 7B00B1A2 (thread 0024), starting debugger..."),
              "Wine's crash line")
        check(!GameLog.crashed(in: "Failed to load ADL library\nerr:   DxvkAdapter: Failed to create device"), "other errors aren't a crash")

        // MARK: Steam that stopped taking commands (OxyRail, 31.10.2026, console_log as Steam wrote it)
        let took = #"[2026-10-31 16:36:11] ExecCommandLine: ""C:\Program Files (x86)\Steam\steam.exe" -no-cef-sandbox -cef-single-process -noverifyfiles -cef-disable-gpu -cef-disable-gpu-compositing -silent -applaunch 3907790""#
        check(SteamCommands.isLaunch(took[...], appID: 3907790), "Steam took the start")
        check(!SteamCommands.isLaunch(took[...], appID: 390779), "not another game's")
        // Helper runs from macOS's log: the client ran 0.22 s, and Steam logged the start in the same second.
        check(!SteamCommands.hung(steamWasReady: true, received: true, sentAgo: 0.223), "16:36:10.854–11.077: taken at once")
        check(!SteamCommands.hung(steamWasReady: true, received: false, sentAgo: 5), "not yet: Steam has its 15 s")
        // 16:52:32 and 17:21:24: the client ended as quickly, and console_log stayed at
        // "[16:46:43] STARTUP SlowJSMethodCall Messaging.PostMessage took 3.0ms".
        check(SteamCommands.hung(steamWasReady: true, received: false, sentAgo: 15), "a ready Steam that took nothing in 15 s: hung, signed in or not")
        check(!SteamCommands.hung(steamWasReady: false, received: false, sentAgo: 60),
              "a Steam still starting may lose a request: that's resent, not a hang")
        let oxyRail = steam.appendingPathComponent("oxyrail", isDirectory: true)
        try? FileManager.default.createDirectory(at: oxyRail.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let oxyLog = oxyRail.appendingPathComponent("logs/console_log.txt")
        try? "[2026-10-31 16:39:34] Game process removed: AppID 3907790 \"\"C:\\Oxygen Train.exe\"\", ProcID 2828 \r\n".write(to: oxyLog, atomically: true, encoding: .utf8)
        var oxyWatcher = LaunchWatcher(steamRoot: oxyRail, appID: 3907790)
        func oxyAppend(_ text: String) {
            let handle = try? FileHandle(forWritingTo: oxyLog)
            _ = try? handle?.seekToEnd()
            try? handle?.write(contentsOf: Data((text + "\r\n").utf8))
            try? handle?.close()
        }
        oxyAppend("[2026-10-31 16:46:43] STARTUP SlowJSMethodCall Messaging.PostMessage took 3.0ms")
        _ = oxyWatcher.poll()
        check(!oxyWatcher.steamReceivedLaunch, "the hung Steam's last line isn't the start")
        oxyAppend(took)
        oxyAppend("[2026-10-31 16:36:11] GameAction [AppID 3907790, ActionID 3] : LaunchApp changed task to CheckShaderDepotManifest with \"\"")
        _ = oxyWatcher.poll()
        check(oxyWatcher.steamReceivedLaunch, "a working Steam's ExecCommandLine is")

        // MARK: Launch watcher on Steam's log
        let console = steam.appendingPathComponent("logs/console_log.txt")
        func write(_ lines: [String]) {
            try? (lines.map { "[2026-10-25 23:11:51] " + $0 }.joined(separator: "\r\n") + "\r\n")
                .write(to: console, atomically: true, encoding: .utf8)
        }
        func append(_ lines: [String]) {
            let handle = try? FileHandle(forWritingTo: console)
            _ = try? handle?.seekToEnd()
            try? handle?.write(contentsOf: Data((lines.map { "[2026-10-25 23:12:00] " + $0 }.joined(separator: "\r\n") + "\r\n").utf8))
            try? handle?.close()
        }
        let action = "GameAction [AppID \(appID), ActionID 1] : LaunchApp"
        write(["\(action) waiting for user response to CreatingProcess \"\"", "\(action) continues with user response \"CreatingProcess\"",
               "\(action) changed task to Completed with \"\""])
        var watcher = LaunchWatcher(steamRoot: steam, appID: appID)
        check(watcher.poll() == nil, "a finished launch earlier in the log isn't an open question")
        append(["ExecCommandLine: \"\"C:\\Steam\\steam.exe\" -silent -applaunch \(appID)\"", "\(action) waiting for user response to ShowEula \"\""])
        check(watcher.poll() == .needsConfirmation, "a new question is seen")
        check(watcher.steamReceivedLaunch, "Steam took the launch request")
        append(["\(action) continues with user response \"ShowEula\"", "Game process added : AppID \(appID) \"C:\\game.exe\", ProcID 7, IP 0.0.0.0:0"])
        check(watcher.poll() == .running, "then the game runs")
        write(["\(action) waiting for user response to ShowEula \"\""])
        watcher = LaunchWatcher(steamRoot: steam, appID: appID)
        check(watcher.poll() == .needsConfirmation, "a question still open from before is seen")

        try? FileManager.default.removeItem(at: steam)
        LaunchHealth.reset(app)

        // MARK: Log
        let log = """
        0124:err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Some Game\\\\Game.exe") not found
        0124:err:module:import_dll Library d3dx9_43.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Some Game\\\\Game.exe") not found
        0130:err:module:import_dll Library steamclient.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe") not found
        wine: Call from 00006FFFFFC2E3A4 to unimplemented function msvcp140.dll.?_Xbad_alloc@std@@YAXXZ, aborting
        [mvk-error] VK_ERROR_OUT_OF_DEVICE_MEMORY: vkCreateQueryPool(): Each occlusion query pool can support a maximum of 32768 queries.
        [mvk-error] VK_ERROR_OUT_OF_DEVICE_MEMORY: vkCreateQueryPool(): Each occlusion query pool can support a maximum of 32768 queries.
        err:   DXGI: Failed to create swap chain
        info:  Game: Game.exe
        """
        check(GameLog.missingRuntimes(in: log, gameFolder: "Some Game") == ["vcrun2013", "d3dx9", "vcrun2022"],
              "runtimes: \(GameLog.missingRuntimes(in: log, gameFolder: "Some Game"))")
        let errors = GameLog.errors(in: log)
        check(errors.count == 6, "errors without repeats: \(errors.count)")
        check(errors.first?.hasPrefix("err:module") == true, "thread ids dropped: \(errors.first ?? "")")
        check(errors.contains("err:   DXGI: Failed to create swap chain"), "DXVK's own error lines kept")

        // MARK: Programs that get the Direct3D layer
        let unreal = FileManager.default.temporaryDirectory.appendingPathComponent("lht-unreal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: unreal.appendingPathComponent("Pal/Binaries/Win64"), withIntermediateDirectories: true)
        for path in ["Palworld.exe", "Pal/Binaries/Win64/Palworld-Win64-Shipping.exe"] {
            FileManager.default.createFile(atPath: unreal.appendingPathComponent(path).path, contents: Data())
        }
        check(Engine.executables(in: unreal) == ["Palworld-Win64-Shipping.exe", "Palworld.exe"],
              "Unreal's game program four levels down gets the layer: \(Engine.executables(in: unreal))")
        try? FileManager.default.removeItem(at: unreal)

        // MARK: Analysis of a made-up game folder
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lht-game-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder.appendingPathComponent("EasyAntiCheat"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: folder.appendingPathComponent("__Installer"), withIntermediateDirectories: true)
        writePE(folder.appendingPathComponent("Game.exe"), imports: ["KERNEL32.dll", "mscoree.dll"])
        writePE(folder.appendingPathComponent("__Installer/Touchup.exe"), imports: ["d3d12.dll"])
        for name in ["uplay_r1_loader64.dll", "WebView2Loader.dll"] { fm.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data()) }
        check(PEImports.dlls(of: folder.appendingPathComponent("Game.exe")) == ["kernel32.dll", "mscoree.dll"], "the PE reader reads imports")
        var analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: "Game.exe")
        check(analysis.usesDotNet, ".NET recognised")
        check(analysis.launcher == "Ubisoft Connect", "Ubisoft Connect recognised: \(analysis.launcher ?? "none")")
        check(analysis.usesWebView2, "WebView2 recognised")
        check(analysis.antiCheat == ["Easy Anti-Cheat"], "anti-cheat recognised")
        check(!analysis.apis.contains(.d3d12), "programs in __Installer don't count")
        try? fm.removeItem(at: folder.appendingPathComponent("uplay_r1_loader64.dll"))
        fm.createFile(atPath: folder.appendingPathComponent("__Installer/installerdata.xml").path, contents: Data())
        writePE(folder.appendingPathComponent("Game.exe"), imports: ["d3d9.dll"])
        analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: "Game.exe")
        check(analysis.launcher == "EA app" && analysis.usesD3D9 && !analysis.usesDotNet, "EA app and DirectX 9: \(analysis)")
        try? fm.removeItem(at: folder)
        // A Source game: the program imports no graphics library, the renderer sits in bin/.
        try? fm.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        writePE(folder.appendingPathComponent("left4dead2.exe"), imports: ["KERNEL32.dll"])
        fm.createFile(atPath: folder.appendingPathComponent("bin/shaderapidx9.dll").path, contents: Data())
        analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: "left4dead2.exe")
        check(analysis.apis == [.d3d9] && ids(analysis) == ["dxvk", "wined3d"], "Source game: DirectX 9 ladder: \(analysis)")
        try? fm.removeItem(at: folder)
        check(GameLog.graphicsFailed(in: "warn:  DXVK: No state cache file found\nerr:   DxvkBuffer: Failed to create buffer:\nerr:     size:  65536"),
              "DXVK's failed buffer counts as a failed start")
        check(GameLog.graphicsFailed(in: "err:   DxvkAdapter: Failed to create device"), "DXVK's failed device counts as a failed start")
        check(!GameLog.graphicsFailed(in: "warn:  DXVK: No state cache file found\nerr:   DXGI: Failed to create swap chain"),
              "other DXVK errors don't end a game")
        check(GameLog.missingRuntimes(in: "0040:err:mscoree:CLRRuntimeInfo_GetRuntimeHost Wine Mono is not installed", gameFolder: "x")
              == [GameLog.wineMono], "missing Mono recognised")

        // MARK: Frame pacing
        let paceLog = """
        info:  [nightforge-dxmt] Game: 41.0 FPS over 10 s, frames 24.4 ms on average, slowest 60 ms
        info:  [nightforge-dxmt] Game: 52.5 FPS over 60 s, frames 19.0 ms on average, slowest 48 ms
        [nightforge-vulkan] GAME.EXE: 55.0 FPS over 60 s, frames 18.2 ms on average, slowest 40 ms
        [nightforge-vulkan] Other.exe: 120.0 FPS over 60 s, frames 8.3 ms on average, slowest 9 ms
        [nightforge-vulkan] swapchain 1512x982 format 44 colour space 0
        """
        check(FramePacing.rates(in: paceLog, programs: ["Game.exe"]) == [52.5, 55.0],
              "frame rates: full minutes of the game's own programs, DXMT without .exe")
        check(FramePacing.periods(in: paceLog, programs: ["Game.exe"]).map(\.seconds) == [10, 60, 60], "every period of the game, 10 s ones too")

        // MARK: Confirmed once it draws
        // Mafia II behind "PhysX SDK not initialized" for a minute (31.10.2026): its whole part of wine.log.
        let errorBox = "Failed to load ADL library\n"
        check(!LaunchHealth.drewFrames(in: errorBox, programs: ["mafia2.exe", "launcher.exe"]), "an error box draws no frames")
        check(LaunchHealth.drewFrames(in: "[nightforge-vulkan] mafia2.exe: 60.0 FPS over 10 s, frames 16.7 ms on average, slowest 30 ms",
                                      programs: ["mafia2.exe"]), "DXVK through Nightforge's Vulkan layer: drawing")
        check(LaunchHealth.drewFrames(in: "info:  [nightforge-dxmt] Overcooked2: 55.0 FPS over 10 s, frames 18.2 ms on average, slowest 788 ms",
                                      programs: ["Overcooked2.exe"]), "DXMT: drawing")
        check(!LaunchHealth.drewFrames(in: "info:  [nightforge-dxmt] Overcooked2: 55.0 FPS over 10 s, frames 18.2 ms on average, slowest 788 ms",
                                       programs: ["mafia2.exe"]), "another game's frames don't count")
        check(LaunchHealth.verdict(drewFrames: true, running: true, ranFor: 35) == .working, "frames: confirmed")
        check(LaunchHealth.verdict(drewFrames: false, running: true, ranFor: 60) == .watching, "running without a frame yet: still watching")
        check(LaunchHealth.verdict(drewFrames: false, running: false, ranFor: 62) == .ended, "ended after a minute without a frame: not confirmed")
        check(LaunchHealth.verdict(drewFrames: false, running: true, ranFor: LaunchHealth.drawingWindow) == .working,
              "nothing logs frames (wined3d, D3DMetal): three minutes of running count")
        LaunchHealth.reset(app)
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 70, startedAt: now)
        let unwatched = LaunchHealth.current(app, ladder)
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == unwatched && unwatched == (0, false),
              "unwatched, 70 s in Steam's log: neither confirmed nor moved on")

        check(FramePacing.candidates(refreshRate: 120, upTo: 60) == [60, 40, 30], "120 Hz: 60, 40, 30")
        check(FramePacing.candidates(refreshRate: 60, upTo: 60) == [60, 30], "60 Hz: 60, 30")
        check(FramePacing.Context(refreshRate: 120, upscaling: true, graphics: .dxmt)
              != FramePacing.Context(refreshRate: 120, upscaling: true, graphics: .d3dmetal),
              "a limit learned on one layer doesn't carry over to another")
        let context = FramePacing.Context(refreshRate: 120, upscaling: true)
        var pacing = FramePacing.State(context: context, ranWith: 60)
        check(FramePacing.next(pacing, rates: [59.8, 60], standard: 60) == pacing, "two minutes say nothing")
        pacing = FramePacing.next(pacing, rates: [50, 52, 55, 58, 59], standard: 60)
        check(pacing.limit == 40, "can't hold 60 → 40")
        pacing.ranWith = 40
        for _ in 0..<2 { pacing = FramePacing.next(pacing, rates: [40, 40, 39.9], standard: 60) }
        check(pacing.limit == 40 && !pacing.trying, "holding 40 keeps it for a while")
        pacing = FramePacing.next(pacing, rates: [40, 40, 39.9], standard: 60)
        check(pacing.limit == nil && pacing.trying, "after three sessions, 60 is tried again")
        pacing.ranWith = 60
        pacing = FramePacing.next(pacing, rates: [50, 51, 53, 60], standard: 60)
        check(pacing.limit == 40 && pacing.waitBeforeTrying == 6, "the try failed: back to 40, next try later")
        var steady = FramePacing.State(context: context, ranWith: 60)
        steady = FramePacing.next(steady, rates: [59.6, 60, 60, 45], standard: 60)
        check(steady.limit == nil, "a short dip doesn't lower the limit")
        steady = FramePacing.next(FramePacing.State(context: context, ranWith: 60), rates: [33, 34, 35], standard: 60)
        check(steady.limit == 30, "far below 40 → 30")

        // MARK: Hardware
        check(GameOptions.standardFrameLimit(120, lowPower: false) == 60 && GameOptions.standardFrameLimit(120, lowPower: true) == 40,
              "120 Hz: 60, in Low Power Mode 40")
        check(GameOptions.standardFrameLimit(60, lowPower: false) == 60 && GameOptions.standardFrameLimit(60, lowPower: true) == 30,
              "60 Hz: 60, in Low Power Mode 30")
        check(GameOptions.standardFrameLimit(0, lowPower: true) == 0, "unknown refresh rate: no limit")
        Hardware.set(.init(retina: false, lowPower: false))
        check(!GameOptions().effectiveUpscaling() || !Prefs.sharpAndSmooth, "no MetalFX on a screen without Retina")
        var forced = GameOptions()
        forced.upscaling = .on
        check(forced.effectiveUpscaling(), "MetalFX switched on stays on without Retina")
        Hardware.set(.init(retina: true, lowPower: true))
        check(GameOptions().effectiveFrameLimit(displayRefreshRate: 120) == (Prefs.sharpAndSmooth ? 40 : 0),
              "Low Power Mode starts one share lower")
        check(FramePacing.Context(refreshRate: 120, upscaling: true, graphics: .dxmt, lowPower: true)
              != FramePacing.Context(refreshRate: 120, upscaling: true, graphics: .dxmt),
              "Low Power Mode learns apart from normal play")
        Hardware.set(.init())

        // MARK: Installed games
        // Registry keys from the online fixes: a game's own settings and drive letters, nothing that
        // reaches every program in the prefix, and no key that could start lines of its own.
        for key in [#"HKEY_CURRENT_USER\Software\Sierra On-Line\Gabriel Knight 3"#,
                    #"HKEY_LOCAL_MACHINE\Software\Wow6432Node\Ubisoft\Launcher"#,
                    #"HKEY_LOCAL_MACHINE\System\MountedDevices"#] {
            check(Engine.isAllowedRegistryKey(key), "registry key \(key) allowed")
        }
        for key in [#"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"#,
                    #"HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce"#,
                    #"HKEY_CURRENT_USER\Software\Classes\exefile\shell"#, #"HKEY_CURRENT_USER\Software\Wine\Drivers"#,
                    #"HKEY_CLASSES_ROOT\exefile"#, #"HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services"#,
                    "HKEY_CURRENT_USER\\Software\\Game]\n[HKEY_CURRENT_USER\\Software\\Microsoft", #"HKEY_CURRENT_USER\Software\"#] {
            check(!Engine.isAllowedRegistryKey(key), "registry key \(key.debugDescription) refused")
        }

        // Migration from Nachtschicht into a Nightforge folder that already exists: the prefix it lacks
        // comes over, what it has stays its own.
        let migration = fm.temporaryDirectory.appendingPathComponent("nf-migration-\(UUID().uuidString)")
        let oldFolder = migration.appendingPathComponent("Nachtschicht"), newFolder = migration.appendingPathComponent("Nightforge")
        for folder in [oldFolder.appendingPathComponent("Prefix/drive_c"), oldFolder.appendingPathComponent("Components"),
                       newFolder.appendingPathComponent("Components")] {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try? "old".write(to: oldFolder.appendingPathComponent("Components/manifest.json"), atomically: true, encoding: .utf8)
        try? "new".write(to: newFolder.appendingPathComponent("Components/manifest.json"), atomically: true, encoding: .utf8)
        check(LegacyMigration.moveContents(of: oldFolder, into: newFolder), "migration into an existing folder succeeds")
        check(fm.fileExists(atPath: newFolder.appendingPathComponent("Prefix/drive_c").path), "the old prefix comes over")
        check((try? String(contentsOf: newFolder.appendingPathComponent("Components/manifest.json"), encoding: .utf8)) == "new",
              "what the new folder has stays")
        try? fm.removeItem(at: migration)

        // A problem report leaves out who the player is.
        let line = GameLog.redacted(#"err:module:open C:\users\Thomas\Documents\x.dll and /Users/thomas/Library/y, drive_c/users/thomas/z, [U:1:158043902] 76561198118309630"#,
                                    home: "/Users/thomas", user: "thomas")
        check(!line.lowercased().contains("thomas"), "the account name is gone: \(line)")
        check(!line.contains("158043902") && !line.contains("76561198118309630"), "Steam ids are gone: \(line)")
        check(line.contains(#"C:\users\<user>\Documents"#) && line.contains("~/Library"), "the rest of the path stays: \(line)")
        // Wine prints paths with doubled backslashes, and a game's command line carries Epic's sign-in
        // (an exchange code that works as a password for a few minutes) and the account's name.
        let wineLine = GameLog.redacted(#"err:module:import_dll Library X.dll (which is needed by L"C:\\users\\thomas\\AppData\\x.exe -AUTH_LOGIN=unused -AUTH_PASSWORD=0a1b2c3d4e5f -AUTH_TYPE=exchangecode -epicapp=Potoo -epicusername=thomas -epicuserid=9f8e7d6c5b4a -epicovt=Z:\\Users\\thomas\\ovt") not found"#,
                                        home: "/Users/thomas", user: "thomas")
        check(!wineLine.lowercased().contains("thomas"), "the account name is gone from Wine's doubled paths: \(wineLine)")
        check(!wineLine.contains("0a1b2c3d4e5f") && !wineLine.contains("9f8e7d6c5b4a"), "Epic's sign-in arguments are gone: \(wineLine)")
        check(wineLine.contains("-AUTH_TYPE=exchangecode") && wineLine.contains("-epicapp=Potoo") && wineLine.contains("Library X.dll"),
              "what helps stays: \(wineLine)")
        let quoted = GameLog.redacted(#"start "-epicusername=Jane Doe" -epicusername="Jane Doe" -epicuserid=abc123 end"#, home: "/Users/thomas", user: "thomas")
        check(!quoted.contains("Jane") && !quoted.contains("Doe") && !quoted.contains("abc123") && quoted.hasSuffix(" end"), "names with a space too: \(quoted)")
        let secrets = GameLog.redacted(#"{"access_token":"eyJabc.def","refresh_token": "r3fr3sh"} Authorization: Bearer abcdef0123456789 write to me@example.com, userdata\\158043902\\config"#,
                                       home: "/Users/thomas", user: "thomas")
        for secret in ["eyJabc", "r3fr3sh", "abcdef0123456789", "me@example.com", "158043902"] {
            check(!secret.isEmpty && !secrets.contains(secret), "\(secret) is gone: \(secrets)")
        }
        check(GameLog.redacted(#"users\thomasine\x C:\users\tom\x"#, home: "/Users/thomas", user: "thomas") == #"users\thomasine\x C:\users\tom\x"#,
              "another name that starts the same stays")
        check(GameLog.errors(in: "0124:err:module:foo L\"C:\\\\users\\\\thomas\\\\x.exe -AUTH_PASSWORD=zzzz1111\"", limit: 5).joined().contains("zzzz1111") == false,
              "error lines for a report are redacted")

        // Winetricks verbs from the online fixes: install verbs pass, commands and options don't.
        for verb in ["vcrun2019", "d3dcompiler_47", "xact_x64"] {
            check(Engine.isSafeWinetricksVerb(verb), "winetricks verb \(verb) allowed")
        }
        for verb in ["annihilate", "list", "--self-update", "-q", "../x.verb", "a b", "VCRUN", ""] {
            check(!Engine.isSafeWinetricksVerb(verb), "winetricks verb \(verb) refused")
        }

        // Covers are kept at the size they're drawn, other art as it is.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 1800, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        func pixels(_ image: NSImage?) -> (Int, Int)? {
            image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { ($0.width, $0.height) }
        }
        let cover = pixels(ArtworkStore.decode(jpeg, kind: .cover))
        check(cover.map { $0 == (427, 640) } == true, "a cover comes down to 427×640: \(String(describing: cover))")
        check(pixels(ArtworkStore.decode(jpeg, kind: .hero)).map { $0 == (1200, 1800) } == true, "hero art keeps its size")

        if CommandLine.arguments.count > 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let common = root.appendingPathComponent("steamapps/common")
            for folder in (try? FileManager.default.contentsOfDirectory(at: common, includingPropertiesForKeys: nil)) ?? [] {
                let analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: nil)
                guard !analysis.apis.isEmpty || analysis.engine != .other else { continue }
                print("  \(folder.lastPathComponent): \(analysis.summary) → " +
                      LaunchHealth.attempts(for: analysis, profile: nil).map(\.label).joined(separator: " → "))
            }
        }

        // The first start with new graphics says shaders are being built; the second doesn't.
        let shaderDefaults = UserDefaults(suiteName: "nightforge.launch-phase-test")!
        shaderDefaults.removePersistentDomain(forName: "nightforge.launch-phase-test")
        func component(_ id: String, _ version: String, _ kind: Component.Kind) -> Component {
            try! JSONDecoder().decode(Component.self, from: Data("""
                {"id":"\(id)","kind":"\(kind.rawValue)","version":"\(version)","url":"https://x/\(id).tar","sha256":"","size":1,"license":"MIT","source":"https://x"}
                """.utf8))
        }
        let before = [component("dxmt", "0.80", .graphics), component("winetricks", "1", .tool)]
        let signature = LaunchPhase.graphicsSignature(runner: "/wine/4.7.3/bin/wine", layer: .dxmt, components: before)
        check(LaunchPhase.isFirstStart(.steam(570), signature: signature, defaults: shaderDefaults), "a game never started builds shaders")
        LaunchPhase.recordStart(.steam(570), signature: signature, defaults: shaderDefaults)
        check(!LaunchPhase.isFirstStart(.steam(570), signature: signature, defaults: shaderDefaults), "the second start doesn't")
        let toolUpdate = LaunchPhase.graphicsSignature(runner: "/wine/4.7.3/bin/wine", layer: .dxmt,
                                                       components: [component("dxmt", "0.80", .graphics), component("winetricks", "2", .tool)])
        check(toolUpdate == signature, "a tool update doesn't touch the shaders")
        let graphicsUpdate = LaunchPhase.graphicsSignature(runner: "/wine/4.7.3/bin/wine", layer: .dxmt,
                                                           components: [component("dxmt", "0.81", .graphics)])
        check(LaunchPhase.isFirstStart(.steam(570), signature: graphicsUpdate, defaults: shaderDefaults), "a graphics update does")
        let otherLayer = LaunchPhase.graphicsSignature(runner: "/wine/4.7.3/bin/wine", layer: .dxvk, components: before)
        check(LaunchPhase.isFirstStart(.steam(570), signature: otherLayer, defaults: shaderDefaults), "so does another layer")
        let otherEngine = LaunchPhase.graphicsSignature(runner: "/wine/4.8/bin/wine", layer: .dxmt, components: before)
        check(LaunchPhase.isFirstStart(.steam(570), signature: otherEngine, defaults: shaderDefaults), "and a new engine")
        shaderDefaults.removePersistentDomain(forName: "nightforge.launch-phase-test")
        check(Set([LaunchPhase.startingSteam, .signingIn, .settingUp, .settingUpDotNet, .restartingSteam, .retrying("DXVK"),
                   .startingSteamForMac, .signInInSteamWindow].map(\.hint)).count == 8, "every phase explains itself differently")

        // "Save battery when unplugged": 30 FPS on battery, nothing changes plugged in or with the setting off.
        check(PowerSource.cappedLimit(60, onBattery: true, saveBattery: true) == 30, "60 becomes 30 on battery")
        check(PowerSource.cappedLimit(24, onBattery: true, saveBattery: true) == 24, "a lower limit stays")
        check(PowerSource.cappedLimit(0, onBattery: true, saveBattery: true) == 30, "no limit becomes 30")
        check(PowerSource.cappedLimit(60, onBattery: false, saveBattery: true) == 60, "plugged in: as it was")
        check(PowerSource.cappedLimit(60, onBattery: true, saveBattery: false) == 60, "setting off: as it was")
        let power = PowerSource.current()
        check(power.level.map { (0...1).contains($0) } ?? true, "battery level reads as 0…1: \(String(describing: power.level))")

        // A too weak charger (3.5), with the values of the real case from 27.10.: 18 W, −1236 mA while "charging".
        let weak = PowerSource(onBattery: false, level: 0.41, adapterWatts: 18)
        var charger = ChargerCheck()
        check(charger.add(weak, batteryCurrent: -1236) == .weak(watts: 18), "an 18 W charger warns at once")
        charger = ChargerCheck()
        check(charger.add(weak, batteryCurrent: 0) == .weak(watts: 18), "also when nothing flows yet: 18 W is too little for games")
        let strong = PowerSource(onBattery: false, level: 0.8, adapterWatts: 96)
        charger = ChargerCheck()
        check(charger.add(strong, batteryCurrent: 0) == nil, "96 W at the charge limit: no warning")
        check(charger.add(strong, batteryCurrent: 2400) == nil, "96 W charging: no warning")
        check((0..<5).map { _ in charger.add(strong, batteryCurrent: -40) }.allSatisfy { $0 == nil }, "a trickle around 0 is no drain")
        charger = ChargerCheck()
        check(charger.add(strong, batteryCurrent: -1500) == nil && charger.add(strong, batteryCurrent: -1500) == nil,
              "one or two draining readings are no warning yet (a short peak)")
        check(charger.add(strong, batteryCurrent: -1500) == .draining, "three in a row: the charger can't keep up")
        check(charger.add(strong, batteryCurrent: 300) == .draining && charger.add(strong, batteryCurrent: 300) == .draining,
              "the warning stays over a short charge (no flicker)")
        check(charger.add(strong, batteryCurrent: 300) == nil, "three good readings: gone again")
        let unknown = PowerSource(onBattery: false, level: 0.5, adapterWatts: nil)
        charger = ChargerCheck()
        _ = charger.add(unknown, batteryCurrent: -900); _ = charger.add(unknown, batteryCurrent: -900)
        check(charger.add(unknown, batteryCurrent: -900) == .draining, "without the watts the drain alone warns")
        check(charger.add(PowerSource(onBattery: true, level: 0.5), batteryCurrent: -900) == nil, "on battery: that's the battery pill's job")
        check(charger.add(unknown, batteryCurrent: -900) == nil, "plugged in again: counting starts over")
        charger = ChargerCheck()
        check(charger.add(PowerSource(onBattery: false, level: nil, adapterWatts: 18), batteryCurrent: nil) == nil,
              "no battery (desktop Mac): nothing to warn about")
        let live = PowerSource.reading()
        check(live.source.adapterWatts.map { $0 > 0 } ?? true, "adapter watts read as a positive number: \(String(describing: live.source.adapterWatts))")

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
