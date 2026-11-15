// Checks the closer look at a start nothing explains: Wine's debug lines as they come with and without a
// process id, strings as Wine quotes them, Metal Gear Solid V's real signature check of 11.11.2026
// (fixtures/), what counts as the game's own (its processes, files in its folder), process ids handed out
// again, Alan Wake's real error box of 14.11.2026 and what tells a notice from a question, and the rule for
// when a start carries the channels.
import Foundation

@main
struct CloserLookTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let folder = "MGS_TPP"
    static let gamePath = #"Z:\\Volumes\\Games\\Nightforge Games\\steamapps\\common\\MGS_TPP\\"#

    /// A library's load as +loaddll with +pid prints it.
    static func load(_ pid: String, _ path: String, ntdll: Bool = false) -> String {
        "\(pid):0454:trace:loaddll:\(ntdll ? "build_ntdll_module" : "build_module") Loaded L\"\(path)\" at 0000000140000000: \(ntdll ? "builtin" : "native")"
    }

    /// A process as it begins: its program, ntdll, kernel32.
    static func begins(_ pid: String, program: String) -> [String] {
        [load(pid, program), load(pid, #"C:\\windows\\system32\\ntdll.dll"#, ntdll: true), load(pid, #"C:\\windows\\system32\\kernel32.dll"#)]
    }

    static func said(_ pid: String, _ text: String) -> String { "\(pid):0110:warn:debugstr:OutputDebugStringA \"\(text)\"" }

    static func main() throws {
        TestDefaults.useWorkFolder()

        // MARK: A line

        let plain = CloserLook.Line("0454:trace:wintrust:WinVerifyTrust returning 800b0109")
        check(plain?.pid == nil && plain?.thread == "0454" && plain?.channel == "wintrust" && plain?.function == "WinVerifyTrust"
              && plain?.text == "returning 800b0109", "a line without +pid: its thread, channel, function and text")
        let withPid = CloserLook.Line(#"0810:0804:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\kernel32.dll" at 00006FFFFFEB0000: builtin"#)
        check(withPid?.pid == "0810" && withPid?.thread == "0804" && withPid?.channel == "loaddll" && withPid?.function == "build_module",
              "with +pid: the process comes first")
        let timed = CloserLook.Line(#"253517.239:0810:0804:trace:loaddll:build_ntdll_module Loaded L"C:\\windows\\system32\\ntdll.dll" at 00006FFFFFF20000: builtin"#)
        check(timed?.pid == "0810" && timed?.thread == "0804" && timed?.function == "build_ntdll_module", "with +timestamp: a time before them")
        check(CloserLook.Line("  5.123:0810:0804:warn:debugstr:OutputDebugStringA \"early\"")?.pid == "0810", "… also one padded with spaces")
        check(CloserLook.Line("info:  [nightforge] Curtain watch for a game begins") == nil
              && CloserLook.Line("err:   DxvkAdapter: Failed to create device") == nil
              && CloserLook.Line("wine: Unhandled page fault on read access") == nil
              && CloserLook.Line("") == nil && CloserLook.Line("0454:trace:wintrust") == nil
              && CloserLook.Line("zzzz:trace:wintrust:WinVerifyTrust returning 0") == nil,
              "Nightforge's, DXVK's and Wine's other lines aren't debug lines")

        // MARK: Strings as Wine quotes them

        check(CloserLook.unquoted(#"Loaded L"C:\\Program Files (x86)\\Steam\\steam.exe" at 0000000140000000: native"#)
              == #"C:\Program Files (x86)\Steam\steam.exe"#, "a wide string: its backslashes single again")
        check(CloserLook.unquoted(#""[2026-11-11 20:10:29] Installation wird \xc3\xbcberpr\xc3\xbcft \xe2\x80\xa6\n""#)
              == "[2026-11-11 20:10:29] Installation wird überprüft …\n", "a narrow string: its bytes as UTF-8, \\n a line's end")
        check(CloserLook.unquoted(#""launched with: \"C:\\Steam\\steam.exe\" -silent\ttab\r""#) == "launched with: \"C:\\Steam\\steam.exe\" -silent\ttab\r",
              "quotes, backslashes, tabs and returns")
        check(CloserLook.unquoted(#""Gr\xfc\xdfe""#) == "Grüße", "bytes that aren't UTF-8: Windows' Western code page")
        check(CloserLook.unquoted(#"L"Fehler: Datei f\00fcr \201eSteam\201c fehlt \d83d\de00""#) == "Fehler: Datei für „Steam“ fehlt 😀",
              "a wide string's units past ASCII, a pair of them too")
        check(CloserLook.unquoted(#""cut off here"..."#) == "cut off here…" && CloserLook.unquoted(#"L"cut off here"..."#) == "cut off here…",
              "a string Wine cut off says so")
        check(CloserLook.unquoted(#""a \q b \x4"#) == #"a \q b \x4"#, "an escape that is none, and a string without its end: as they stand")
        check(CloserLook.unquoted("pgKnownSubject: (null)") == nil && CloserLook.unquoted("") == nil, "no string: nothing")

        // MARK: Metal Gear Solid V, 11.11.2026 – the log as it was, without +pid

        let real = try String(contentsOf: URL(fileURLWithPath: "tests/CloserLookTest/fixtures/wintrust-mgsv-2026-11-11.log"), encoding: .utf8)
        let valve = CloserLook.Signature(file: "steam_api64.dll", code: 0x800B_0109, signer: "Valve",
                                         root: "VeriSign Class 3 Public Primary Certification Authority - G5", untrustedRoot: true)
        let asItWas = CloserLook.read(real, gameFolder: folder)
        check(asItWas.signatures == [valve],
              "the check of steam_api64.dll: its answer, the signer and the root of the last chain – not Apple's before it, not the close call (\(asItWas.signatures))")
        check(!asItWas.channelsOn && asItWas.debugOutput.isEmpty && asItWas.boxes.isEmpty && asItWas.graphics.isEmpty && asItWas.lastLibraries.isEmpty,
              "without +pid nothing else is anyone's")
        check(CloserLook.read(real, gameFolder: "mgs_tpp").signatures == [valve], "the folder's name whatever its case")
        check(CloserLook.read(real, gameFolder: "Dishonored").signatures.isEmpty && CloserLook.read(real, gameFolder: "").signatures.isEmpty,
              "another game's start, or no folder: a check of this file isn't theirs")

        // MARK: The same with the channels on

        let game = "0810", steam = "07fc"
        let check32 = real.split(whereSeparator: \.isNewline).map { $0.hasPrefix("0454:") ? "\(game):\($0)" : String($0) }
        var lines = begins(steam, program: #"C:\\Program Files (x86)\\Steam\\steam.exe"#)
        lines += begins(game, program: gamePath + "mgsvtpp.exe")
        lines += [load(game, gamePath + "steam_api64.dll"), load(game, #"C:\\windows\\system32\\dxgi.dll"#), load(game, #"C:\\windows\\system32\\D3D11.dll"#)]
        lines += [said(steam, #"[2026-11-11 20:10:29] Startup - updater built Oct 21 2026 14:10:53\n"#),
                  said(game, #"Steam API: init\nloading steam_api64.dll\n\n"#)]
        lines += check32
        // A file of Windows' own, checked by the game: its process makes it the game's.
        lines += ["\(game):0454:trace:wintrust:WinVerifyTrust (0000000000000000, {00aac56b-cd44-11d0-8cc2-00c04fc295ee}, 0000000000103B90)",
                  "\(game):0454:trace:wintrust:dump_file_info pcwszFilePath: L\"C:\\\\windows\\\\system32\\\\xinput1_3.dll\"",
                  "\(game):0454:trace:wintrust:WinVerifyTrust returning 800b0100"]
        // Steam checks a file of its own: not the game's.
        lines += ["\(steam):0110:trace:wintrust:WinVerifyTrust (0000000000000000, {00aac56b-cd44-11d0-8cc2-00c04fc295ee}, 0000000000103B90)",
                  "\(steam):0110:trace:wintrust:dump_file_info pcwszFilePath: L\"C:\\\\Program Files (x86)\\\\Steam\\\\steamclient64.dll\"",
                  "\(steam):0110:trace:wintrust:WinVerifyTrust returning 800b0100"]
        lines += [said(game, #"Failed to load SteamAPI"#),
                  "\(steam):0110:trace:msgbox:MSGBOX_OnInit L\"Steam needs to be online to update.\"",
                  "\(game):0454:trace:msgbox:MSGBOX_OnInit L\"Failed to load SteamAPI.\\nPlease restart \\201eSteam\\201c.\"",
                  "\(steam):0110:warn:debugstr:OutputDebugStringW L\"only the A line is read\"",
                  "info:  [nightforge] Curtain look at METAL GEAR SOLID V: 1 processes"]
        let looked = CloserLook.read(lines.joined(separator: "\n"), gameFolder: folder)
        check(looked.channelsOn, "a library's load with its process: the channels were on")
        check(looked.signatures == [valve, CloserLook.Signature(file: "xinput1_3.dll", code: 0x800B_0100)],
              "the game's checks, by its process – Steam's of its own file stays out (\(looked.signatures))")
        check(looked.debugOutput == ["Steam API: init", "loading steam_api64.dll", "Failed to load SteamAPI"],
              "what the game put out for a debugger, line by line, without Steam's (\(looked.debugOutput))")
        check(looked.boxes == ["Failed to load SteamAPI. Please restart „Steam“."], "its message box's text in one line, not Steam's (\(looked.boxes))")
        check(looked.graphics == ["dxgi.dll", "d3d11.dll"] && !looked.loadsOnlyDirect3D9, "the graphics libraries it loaded (\(looked.graphics))")
        check(looked.lastLibraries == ["ntdll.dll", "kernel32.dll", "steam_api64.dll", "dxgi.dll", "d3d11.dll"],
              "the last libraries it loaded (\(looked.lastLibraries))")
        check(CloserLook.read(lines.joined(separator: "\n"), gameFolder: "Dishonored") == CloserLook.Reading(channelsOn: true),
              "for another game the same log says only that the channels were on")
        // With a time before each line.
        let timedLog = lines.map { $0.first?.isHexDigit == true ? "253517.239:" + $0 : $0 }.joined(separator: "\n")
        check(CloserLook.read(timedLog, gameFolder: folder) == looked, "with +timestamp the same")

        // MARK: Direct3D 9, and a lot of output

        var old = begins(game, program: gamePath + "game.exe") + [load(game, #"C:\\windows\\system32\\d3d9.dll"#)]
        old += (1...9).map { said(game, "line \($0)") } + [said(game, "line 2"), said(game, "line 9"), said(game, String(repeating: "x", count: 250))]
        let nine = CloserLook.read(old.joined(separator: "\n"), gameFolder: folder)
        check(nine.graphics == ["d3d9.dll"] && nine.loadsOnlyDirect3D9, "d3d9.dll and nothing newer")
        check(nine.debugOutput == ["line 6", "line 7", "line 8", "line 2", "line 9", String(repeating: "x", count: 200) + "…"],
              "the last six lines, each once where it came last, a long one cut (\(nine.debugOutput.map { $0.prefix(12) }))")
        check(!CloserLook.read((old + [load(game, #"C:\\windows\\system32\\d3d10core.dll"#)]).joined(separator: "\n"), gameFolder: folder).loadsOnlyDirect3D9,
              "with Direct3D 10 beside it: not Direct3D 9 alone")

        // MARK: A process id handed out again

        var reused = begins(game, program: #"C:\\Program Files (x86)\\Steam\\bin\\gldriverquery64.exe"#) + [said(game, "helper before the game")]
        reused += begins(game, program: gamePath + "mgsvtpp.exe") + [said(game, "the game itself"), load(game, #"C:\\windows\\system32\\d3d11.dll"#)]
        reused += begins(game, program: #"C:\\Program Files (x86)\\Steam\\steamerrorreporter64.exe"#) + [said(game, "helper after the game")]
        let again = CloserLook.read(reused.joined(separator: "\n"), gameFolder: folder)
        check(again.debugOutput == ["the game itself"], "a helper with the game's process id before and after it isn't the game (\(again.debugOutput))")
        check(again.lastLibraries == ["mgsvtpp.exe", "ntdll.dll", "kernel32.dll", "d3d11.dll"],
              "… and the game's libraries are its own, its program with them (\(again.lastLibraries))")

        // MARK: Nothing to read

        check(CloserLook.read("", gameFolder: folder) == CloserLook.Reading(), "an empty log")
        check(CloserLook.read("0124:err:module:import_dll Library XINPUT1_3.dll (which is needed by L\"Z:\\\\Game\\\\x.exe\") not found\n"
                              + "err:   DxvkAdapter: Failed to create device\nwine: Unhandled page fault\n", gameFolder: folder) == CloserLook.Reading(),
              "a log without the channels")
        // A check that never ends, a chain outside a check, an answer without a check: nothing, and no crash.
        let loose = ["0454:trace:chain:dump_element issued by L\"Someone\"", "0454:trace:chain:CertGetCertificateChain error status: 00000020",
                     "0454:trace:wintrust:WinVerifyTrust returning 800b0109",
                     "0454:trace:wintrust:WinVerifyTrust (0, {x}, 0)", "0454:trace:chain:dump_element issued to L\"Nobody\"",
                     "0454:trace:wintrust:WinVerifyTrust returning zzzz"]
        check(CloserLook.read(loose.joined(separator: "\n"), gameFolder: folder) == CloserLook.Reading(), "loose ends of a check")
        // A check that names no file, by the game's process.
        let nameless = begins(game, program: gamePath + "game.exe")
            + ["\(game):0454:trace:wintrust:WinVerifyTrust (0, {x}, 0)", "\(game):0454:trace:wintrust:WinVerifyTrust returning 80096010"]
        check(CloserLook.read(nameless.joined(separator: "\n"), gameFolder: folder).signatures == [CloserLook.Signature(file: nil, code: 0x8009_6010)],
              "a check without a file's name still counts for the process that made it")

        // MARK: Alan Wake, 14.11.2026 – a start with the channels as it was: its error box

        let wake = try String(contentsOf: URL(fileURLWithPath: "tests/CloserLookTest/fixtures/msgbox-alanwake-2026-11-14.log"), encoding: .utf8)
        let wakeBox = "Alan Wake could not initialize your 3D graphics card. Please see that your system conforms with the minimum "
            + "specification and ensure you have the latest graphics card drivers installed. Technical: DEVICE_CREATE_ERROR - Not available"
        let woke = CloserLook.read(wake, gameFolder: "AlanWake")
        check(woke.channelsOn && woke.boxes == [wakeBox], "the box's text as +msgbox printed it, in one line (\(woke.boxes))")
        check(woke.endedAtBox == wakeBox, "… and the game loaded nothing after it: the window it ended at")
        check(woke.graphics == ["opengl32.dll", "d3d9.dll", "vulkan-1.dll"] && woke.loadsOnlyDirect3D9, "it loaded Direct3D 9 and nothing newer (\(woke.graphics))")
        check(woke.debugOutput.last == "Loaded String table in 57 ms" && woke.debugOutput.count == 6, "the last of what it said for a debugger (\(woke.debugOutput))")
        check(woke.signatures.isEmpty, "no signature check in it")
        check(CloserLook.read(wake, gameFolder: "Dishonored") == CloserLook.Reading(channelsOn: true), "another game's reading of the same log: nothing")
        check(GameLog.direct3D9Failed(in: wake, layer: .d3dmetal) && !GameLog.direct3D9Failed(in: wake, layer: .dxvk),
              "DXVK's own words stand in it too: the rule that spoke on 14.11.")
        check(looked.endedAtBox == "Failed to load SteamAPI. Please restart „Steam“.", "Metal Gear Solid V's box was its last word as well")
        // A game that goes on after a box loads more; another process of the game's doesn't make it go on.
        let helper = "0820"
        var went = begins(game, program: gamePath + "game.exe")
        went += ["\(game):0454:trace:msgbox:MSGBOX_OnInit L\"No controller found.\"", load(game, #"C:\\windows\\system32\\d3d11.dll"#)]
        let wentOn = CloserLook.read(went.joined(separator: "\n"), gameFolder: folder)
        check(wentOn.boxes == ["No controller found."] && wentOn.endedAtBox == nil, "a box the game went on after isn't the one it ended at")
        went = begins(game, program: gamePath + "game.exe") + ["\(game):0454:trace:msgbox:MSGBOX_OnInit L\"Fatal error!\""]
        went += begins(helper, program: gamePath + "CrashReportClient.exe") + [load(helper, #"C:\\windows\\system32\\dbghelp.dll"#)]
        check(CloserLook.read(went.joined(separator: "\n"), gameFolder: folder).endedAtBox == "Fatal error!",
              "its crash reporter starting behind the box doesn't change that")
        went = begins(game, program: gamePath + "game.exe") + ["\(game):0454:trace:msgbox:MSGBOX_OnInit L\"First.\"",
                                                             "\(game):0454:trace:msgbox:MSGBOX_OnInit L\"Then this.\""]
        check(CloserLook.read(went.joined(separator: "\n"), gameFolder: folder).endedAtBox == "Then this.", "of two boxes the last")

        // MARK: A question or a notice

        check(CloserLook.box(wakeBox) == .notice && CloserLook.box("Failed to load SteamAPI") == .notice, "the two real ones: notices")
        check(CloserLook.box("DX12 is not supported on your system. Try running without the -dx12 or -d3d12 command line argument.") == .notice
              && CloserLook.box("Die Grafikkarte wird nicht unterstützt.") == .notice, "no question mark: nothing asked, in any language")
        check(CloserLook.box("Do you want to start in safe mode?") == .question && CloserLook.box("Möchtest du im Fenster starten?") == .question
              && CloserLook.box("セーフモードで起動しますか？") == .question, "a question the player can answer either way")
        check(CloserLook.box("The UE4 game has crashed and will close. Send a report?") == .notice
              && CloserLook.box("Fatal error! Would you like to send a crash report?") == .notice
              && CloserLook.box("Das Spiel ist abgestürzt. Bericht senden?") == .notice, "a failure that asks what to do about it is still a failure")
        check(CloserLook.everyStart == "+pid,+loaddll,+msgbox" && CloserLook.everyStart.split(separator: ",").allSatisfy { CloserLook.channels.contains($0) },
              "the channels of every start are a part of a closer look's")

        // MARK: Step E5 – every start carries +pid, +loaddll and +msgbox

        check(CloserLook.usualWineDebug == GameLog.wineDebug + ",+pid,+loaddll,+msgbox" && Engine.gameEnvironment["WINEDEBUG"] == CloserLook.usualWineDebug,
              "what Steam and every game start with")
        check(Engine.steamConfigVersion == 11, "a Steam started before gets its one restart for them")
        // With +pid every line of Wine's begins with the process: what reads the log for a start's failure
        // looks inside the line, not at its beginning.
        let pidLines = """
            0124:0128:err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\Games\\Night Game\\Game.exe") not found
            0124:0128:err:module:import_dll Library d3dx9_43.dll (which is needed by L"C:\\Games\\Night Game\\Game.exe") not found
            0124:0128:err:module:LdrInitializeThunk Importing dlls for L"C:\\Games\\Night Game\\Game.exe" failed, status c0000135
            0130:0134:err:seh:NtRaiseException Unhandled illegal instruction at 0x7b0123
            wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140001000 (thread 0128), starting debugger...
            0124:0128:err:mscoree:CLRRuntimeInfo_GetRuntimeHost Wine Mono is not installed
            """
        let missing = GameLog.missingRuntimes(in: pidLines, gameFolder: "Night Game")
        check(missing.contains(GameLog.wineMono) && missing.count >= 3, "missing runtimes are read from lines that begin with a process (\(missing))")
        check(GameLog.illegalInstruction(in: pidLines) && GameLog.crashed(in: pidLines), "… and an illegal instruction, and a crash")
        check(CloserLook.read(pidLines, gameFolder: "Night Game").boxes.isEmpty && !CloserLook.read(pidLines, gameFolder: "Night Game").channelsOn,
              "error lines alone are no reading")
        // Alan Wake's start of 14.11. carried the three and more: its box is read from them alone.
        let usualOnly = wake.split(whereSeparator: \.isNewline)
            .filter { $0.contains(":loaddll:") || $0.contains(":msgbox:") || !$0.contains(":trace:") && !$0.contains(":warn:") }.joined(separator: "\n")
        let usualReading = CloserLook.read(usualOnly, gameFolder: "AlanWake")
        check(usualReading.endedAtBox == woke.endedAtBox && usualReading.endedAtBox != nil && usualReading.loadsOnlyDirect3D9 && usualReading.signatures.isEmpty,
              "the usual channels alone give the box the game ended at and what it draws with")
        // The window a start ended at: a failure the table saw, or a message box that only says something, is no
        // choice of the player's; what describes a start – what it loaded, a signature – leaves it one.
        func found(_ id: String) -> StartDiagnosis { StartDiagnosis(id: id, because: "seen", remedy: nil) }
        check(StartDiagnosis.sawFailure([found("said"), found("direct3d9")]) && StartDiagnosis.sawFailure([found("missing-runtime")])
              && StartDiagnosis.sawFailure([found("nvidia-interface")]), "a failure the table saw")
        check(!StartDiagnosis.sawFailure([]) && !StartDiagnosis.sawFailure([found("loads-direct3d9"), found("signature"), found("untrusted-root")])
              && !StartDiagnosis.sawFailure([found("crash"), found("said"), found("debug-said"), found("hung")]),
              "what a start loaded or checked, and the fallbacks, aren't one")
        check(LaunchHealth.ownQuestionWasAChoice(explained: StartDiagnosis.sawFailure([found("loads-direct3d9")]), endedAtBox: nil, knownWindow: true),
              "a Direct3D 9 game quit at its own launcher window: still the player's choice")
        check(!LaunchHealth.ownQuestionWasAChoice(explained: false, endedAtBox: usualReading.endedAtBox, knownWindow: false),
              "Alan Wake's error box under the curtain, OK pressed: a failed start")

        // MARK: When a start carries the channels

        check(CloserLook.channels == "+pid,+loaddll,warn+debugstr,+wintrust,+chain,+msgbox"
              && CloserLook.wineDebug == GameLog.wineDebug + "," + CloserLook.channels, "the channels, on top of the usual ones")
        check(!CloserLook.always, "no engine test's switch here")
        func step(unexplained: Bool = true, antiCheat: Bool = false, carried: Bool = false, takenBefore: Bool = false,
                  canCarry: Bool = true, lastWay: Bool = false) -> CloserLook.Step {
            CloserLook.step(unexplained: unexplained, antiCheat: antiCheat, carried: carried, takenBefore: takenBefore,
                            canCarry: canCarry, lastWay: lastWay)
        }
        check(step() == .nextWay, "nothing explains the end and a way is left: the next ways carry the channels")
        check(step(lastWay: true) == .sameWayAgain, "no way left: the last one once more")
        check(step(unexplained: false) == .none && step(unexplained: false, lastWay: true) == .none, "an end that is explained: no closer look")
        check(step(antiCheat: true) == .none && step(antiCheat: true, lastWay: true) == .none, "never for a game with an anti-cheat")
        check(step(carried: true) == .none && step(carried: true, lastWay: true) == .none, "one look per Play: no start after one that had the channels")
        check(step(takenBefore: true) == .none && step(takenBefore: true, lastWay: true) == .none, "one look per game and engine build")
        check(step(canCarry: false) == .none && step(canCarry: false, lastWay: true) == .none, "not when the start to come can't have them")

        let defaults = TestDefaults.suite("closer-look")
        check(!CloserLook.taken(.steam(287700), engine: "winecx@4.7.3", defaults: defaults), "no look taken yet")
        CloserLook.noteTaken(.steam(287700), engine: "winecx@4.7.3", defaults: defaults)
        check(CloserLook.taken(.steam(287700), engine: "winecx@4.7.3", defaults: defaults), "taken: remembered for the game and its engine build")
        check(!CloserLook.taken(.steam(287700), engine: "winecx@4.7.4", defaults: defaults)
              && !CloserLook.taken(.steam(205100), engine: "winecx@4.7.3", defaults: defaults), "… a new engine build, or another game, gets its own")
        CloserLook.noteTaken(.steam(287700), engine: "winecx@4.7.4", defaults: defaults)
        check(CloserLook.taken(.steam(287700), engine: "winecx@4.7.4", defaults: defaults)
              && !CloserLook.taken(.steam(287700), engine: "winecx@4.7.3", defaults: defaults), "the newest build's look is the one kept")

        print(failures == 0 ? "✓ CloserLook" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
