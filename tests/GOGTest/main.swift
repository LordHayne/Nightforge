// Checks GOG without GOG Galaxy: what Nightforge reads from GOG's API and gogdl, the games' info
// files, cloud-save folders, the sign-in code, Mac first, merging with other stores, and the store
// offline with the library from last time: tests/GOGTest/run.sh
import Foundation

@main
struct GOGTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// Which gogdl downloads run, without a process list (extra review, 3.11.): not known is not "none" –
    /// the first look with `ps` down says nothing, and a look that was made before stands.
    static func runningDownloads() {
        let memory = LockedValue<Set<String>?>(nil)
        defer { FakeProcesses.installEmpty() }
        FakeProcesses.installDown()
        check(GOGDL.runningDownloads(remembered: memory) == nil, "no list and no earlier look: not known – a second download of the game must not start")
        FakeProcesses.installEmpty()
        check(GOGDL.runningDownloads(remembered: memory) == [], "a list without a download: none")
        FakeProcesses.installDown()
        check(GOGDL.runningDownloads(remembered: memory) == [], "no list after that look: the look stands")
    }

    @MainActor
    static func main() async {
        // No real process list: a hanging ps on this Mac doesn't stop the series (tests/Shared/FakeProcesses.swift).
        FakeProcesses.installEmpty()
        // A stand-in program for `leftovers` (a copy of this one): it only waits.
        if CommandLine.arguments.dropFirst().first == "--stand-in" {
            try? await Task.sleep(for: .seconds(30))
            exit(0)
        }
        guard FileManager.default.homeDirectoryForCurrentUser.path.contains("/home") else {
            print("✗ runs only in its own home (tests/GOGTest/run.sh)")
            exit(1)
        }
        runningDownloads()
        await profiles()
        gameIDs()
        owned()
        releases()
        auth()
        sizes()
        builds()
        gameInfo()
        saves()
        machO()
        progress()
        signIn()
        macFirst()
        merging()
        await store()
        await refresh()
        await drives()
        await playing()
        redistFormats()
        await redistSetUp()
        leftovers()
        await realProgram()

        print(failures == 0 ? "✓ GOG" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A GOG game starts with the profile the list keeps under its product ID (mac.json's "gog"
    /// twins); Epic's entries stay out of a start. First, before anything else reads the list.
    static func profiles() async {
        let json = #"{"formatVersion": 1, "games": {"50130": {"name": "Mafia II (Classic)", "graphics": "wined3d"},"#
            + #""gog.1816059595": {"name": "Mafia II (Classic)", "graphics": "wined3d", "source": "mac"},"#
            + #""epic.fn": {"name": "Fortnite", "antiCheat": ["Easy Anti-Cheat"]}}}"#
        // As the app's own copy: one fetched online counts only with its signature (ProfileFilesTest).
        let list = Engine.supportDir.appendingPathComponent("bundled-profiles.json")
        try? FileManager.default.createDirectory(at: Engine.supportDir, withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: list)
        let store = ProfileStore(bundledURL: list)
        check(await store.profile(for: .gog("1816059595"))?.graphics == .wined3d, "a GOG game's profile, by its product ID")
        check(await store.profile(for: .steam(50130))?.graphics == .wined3d, "the Steam version's, by app ID as before")
        check(await store.profile(for: .gog("50130")) == nil, "a GOG ID is not a Steam app ID")
        check(await store.profile(for: .gog("1207658924")) == nil, "a GOG game the list doesn't know has none")
        check(await store.profile(for: .epic("fn")) == nil, "an Epic game starts without: its entry only blocks it")
        check(ProfileStore.decodeGOG(Data(json.utf8)).keys.sorted() == ["1816059595"], "only gog.<id> keys are GOG's")
        try? FileManager.default.removeItem(at: list)
    }

    // MARK: - Fixtures (formats as gogdl and Heroic read them)

    /// GOG's dependencies repository as gogdl keeps it (.gogdl-redist-manifest), entries as GOG
    /// serves them (content-system.gog.com/dependencies/repository, 31.10.2026), cut down.
    static let redistRepository = #"""
    {"depots": [
      {"dependencyId": "ISI", "readableName": "Install Script Interpreter", "executable": {"arguments": "", "path": "__redist/ISI/scriptinterpreter.exe"}},
      {"dependencyId": "DirectX", "readableName": "DirectX 9.0c", "executable": {"arguments": "/silent", "path": "__redist/DirectX/DXSETUP.exe"}},
      {"dependencyId": "MSVC2005", "readableName": "Visual C++ Redist 2005", "executable": {"arguments": "/q:a /c:\"VCREDI~3.EXE /q:a /c:\"\"msiexec /i vcredist.msi /qb\"\" \"", "path": "__redist/MSVC2005/vcredist_x86.exe"}},
      {"dependencyId": "MSVC2017", "readableName": "Visual C++ Redist 2017", "executable": {"arguments": "/install /quiet /norestart", "path": "__redist/MSVC2017/VC_redist.x86.exe"}},
      {"dependencyId": "PHYSX", "readableName": "NVIDIA PhysX (9.17.0524)", "executable": {"arguments": "-s", "path": "__redist/PHYSX/PhysX-9.17.0524-SystemSoftware.exe"}},
      {"dependencyId": "PHYSXLEGACY", "readableName": "NVIDIA PhysX Legacy (9.13.0604)", "executable": {"arguments": "/passive /norestart", "path": "__redist/PHYSXLEGACY/PhysX-9.13.0604-SystemSoftware-Legacy.msi"}},
      {"dependencyId": "UE4REDIST", "readableName": "UE4 Prerequisites (x64)", "executable": {"arguments": "/passive /norestart", "path": "__redist/UE4REDIST/UE4PrereqSetup_x64.exe"}},
      {"dependencyId": "ScummVM", "readableName": "Scumm VM", "executable": {"arguments": "", "path": ""}},
      {"dependencyId": "dotNet4", "readableName": ".NET 4.0", "executable": {"arguments": "/q /norestart", "path": "__redist/dotNet4/dotNetFx40_Full_x86_x64.exe"}}],
     "build_id": "60163282911088704", "HGLInstalled": ["MSVC2010"]}
    """#

    /// Mafia II (Classic)'s build manifest as gogdl keeps it (GOG's, cut down, without its client secret).
    static let mafiaManifest = #"""
    {"baseProductId": "1816059595", "buildId": "51277443195366142", "clientId": "51014162722881154",
     "dependencies": ["DirectX", "MSVC2017", "PHYSXLEGACY", "PHYSX"], "installDirectory": "Mafia II", "platform": "windows",
     "products": [{"name": "Mafia II", "productId": "1816059595", "temp_arguments": "", "temp_executable": ""}],
     "scriptInterpreter": true, "tags": ["csb_10_4_0_w_28", "galaxy"], "version": 2,
     "depots": [{"compressedSize": 10490560, "languages": ["*"], "productId": "1816059595", "size": 10630200, "manifest": "x"}],
     "HGLInstallLanguage": "de-DE", "HGLdlcs": []}
    """#

    /// Two pages of galaxy-library: GOG's own products, a game linked from Steam, one not owned.
    static let ownedPage1 = #"""
    {"total_count": 5, "limit": 3, "next_page_token": "abc",
     "items": [{"platform_id": "gog", "external_id": "1453375253", "owned": true, "certificate": "x"},
               {"platform_id": "steam", "external_id": "570", "owned": true},
               {"platform_id": "gog", "external_id": "1207660413", "owned": true}]}
    """#
    static let ownedPage2 = #"""
    {"total_count": 5, "limit": 3, "page_token": "abc",
     "items": [{"platform_id": "gog", "external_id": 1207664663, "owned": true},
               {"platform_id": "gog", "external_id": "1111", "owned": false},
               {"platform_id": "gog", "external_id": "../evil", "owned": true},
               {"platform_id": "gog", "external_id": "1999999999", "owned": true},
               {"platform_id": "gog", "external_id": "1888888888", "owned": true}]}
    """#

    static func gamesDB(_ id: String, _ title: String, type: String = "game", mac: Bool = false, dlcs: [String] = [],
                        visible: Bool = true, cover: String = "https://images.gog.com/cover-ID{formatter}.{ext}") -> String {
        let systems = (["windows"] + (mac ? ["osx"] : [])).map { #"{"slug": "\#($0)", "name": "\#($0)"}"# }.joined(separator: ", ")
        let dlcList = dlcs.map { #"{"id": "r\#($0)", "platform_id": "gog", "external_id": "\#($0)", "release_per_platform_id": "gog_\#($0)"}"# }
            .joined(separator: ", ")
        return #"""
        {"id": "gog_\#(id)", "game_id": "5\#(id)", "platform_id": "gog", "external_id": "\#(id)", "dlcs_ids": [], "dlcs": [\#(dlcList)],
         "title": {"*": "\#(title) ", "en-US": "\#(title)"}, "type": "\#(type)", "supported_operating_systems": [\#(systems)],
         "logo": {"url_format": "https://images.gog.com/tile-\#(id){formatter}.{ext}"},
         "game": {"title": {"*": "\#(title)"}, "visible_in_library": \#(visible),
                  "vertical_cover": {"url_format": "\#(cover.replacingOccurrences(of: "ID", with: id))"},
                  "background": {"url_format": "https://images.gog.com/bg-\#(id){formatter}.{ext}"},
                  "logo": {"url_format": "https://images.gog.com/tile-\#(id){formatter}.{ext}"}}}
        """#
    }

    static let stardew = gamesDB("1453375253", "Stardew Valley", mac: true)
    static let witcher = gamesDB("1207664663", "The Witcher 3: Wild Hunt", dlcs: ["1207660413", "1207660414"])
    static let heartsOfStone = gamesDB("1207660413", "The Witcher 3 – Hearts of Stone", type: "dlc")
    static let spam = gamesDB("1999999999", "Goodies Pack", type: "spam")

    /// `gogdl info 1207664663 --platform windows --with-dlcs`.
    static let info = #"""
    {"size": {"*": {"download_size": 30000000000, "disk_size": 45000000000},
              "en-US": {"download_size": 1000000000, "disk_size": 2000000000},
              "de-DE": {"download_size": 1500000000, "disk_size": 2500000000}},
     "dlcs": [{"title": "Hearts of Stone", "id": "1207660413",
               "size": {"*": {"download_size": 3000000000, "disk_size": 4000000000}, "de-DE": {"download_size": 100, "disk_size": 200}}},
              {"title": "Bad", "id": "../x", "size": {}}],
     "buildId": "56258405493426547", "languages": ["en-US", "de-DE", "fr-FR"], "folder_name": "The Witcher 3 Wild Hunt GOTY",
     "dependencies": ["MSVC2017"], "versionEtag": "\"abc\"", "versionName": "4.04", "available_branches": [null],
     "builds": {"items": [], "total_count": 1}}
    """#

    // MARK: - Tests

    static func gameIDs() {
        check(GameID.gog("1207664663").key == "gog.1207664663", "GOG games are kept under gog.<product ID>")
        check(GameID(key: "gog.1207664663") == .gog("1207664663"), "and a link with that key finds the game")
        check(GameID(key: "gog.../evil") == nil, "an ID that would climb out of a folder isn't one")
        check(Provider.gog.label == "GOG" && Provider.gog.short == "GOG", "GOG's name")
        check(Array(Provider.allCases.prefix(3)) == [.steam, .epic, .gog], "GOG is the third store, after Steam and Epic")
        check(GameShortcut.url(play: .gog("1207664663")).absoluteString == "nightforge://play/gog.1207664663", "links: nightforge://play/gog.<id>")
        check(GameShortcut.action(from: GameShortcut.url(play: .gog("1207664663"), key: String(repeating: "a", count: 32)),
                                  key: String(repeating: "a", count: 32)) == .play(.gog("1207664663")), "and they lead to the game")
    }

    static func owned() {
        let first = GOGOwned.page(fromJSON: Data(ownedPage1.utf8))
        check(first?.ids == ["1453375253", "1207660413"], "GOG's products, not the Steam game linked to the account: \(String(describing: first?.ids))")
        check(first?.next == "abc", "and the next page")
        let second = GOGOwned.page(fromJSON: Data(ownedPage2.utf8))
        check(second?.ids == ["1207664663", "1999999999", "1888888888"], "numbers as numbers, nothing not owned, no odd IDs: \(String(describing: second?.ids))")
        check(second?.next == nil, "the last page")
        check(GOGOwned.page(fromJSON: Data("<html>".utf8)) == nil, "no page, no list (the old one stays)")
    }

    static func releases() {
        let release = GOGRelease.from(gamesDB: Data(stardew.utf8))
        check(release?.id == "1453375253" && release?.title == "Stardew Valley", "the title, trimmed")
        check(release?.mac == true && release?.type == "game", "a game with a Mac version")
        check(release?.cover?.absoluteString == "https://images.gog.com/cover-1453375253.jpg", "the portrait cover as a JPEG")
        check(release?.hero?.absoluteString == "https://images.gog.com/bg-1453375253.jpg", "the background as hero art")
        let witcherRelease = GOGRelease.from(gamesDB: Data(witcher.utf8))
        check(witcherRelease?.mac == false && witcherRelease?.dlcs == ["1207660413", "1207660414"], "Windows only, and its add-ons")
        let noBackground = GOGRelease.from(gamesDB: Data(stardew.replacingOccurrences(of: #""background""#, with: #""x""#).utf8))
        check(noBackground?.hero?.absoluteString == "https://images.gog.com/tile-1453375253.jpg", "without a background: the store's tile")
        let insecure = GOGRelease.from(gamesDB: Data(gamesDB("1", "X", cover: "http://images.gog.com/c{formatter}.{ext}").utf8))
        check(insecure?.cover == nil, "images only over https")
        check(GOGRelease.from(gamesDB: Data(#"{"external_id": "1", "title": {"*": ""}}"#.utf8)) == nil, "no title, no game")

        let all = [stardew, witcher, heartsOfStone, spam, gamesDB("1888888888", "Hidden", visible: false)]
            .compactMap { GOGRelease.from(gamesDB: Data($0.utf8)) }
        let games = GOGLibrary.games(from: all)
        check(games.map(\.title) == ["Stardew Valley", "The Witcher 3: Wild Hunt"],
              "games only, sorted – no add-ons, goodies or hidden products: \(games.map(\.title))")
        check(games.last?.dlcs == [GOGDLC(id: "1207660413", title: "The Witcher 3 – Hearts of Stone")],
              "the add-ons the player owns, not the ones they don't")
    }

    static func auth() {
        let credentials = #"{"access_token": "tok", "expires_in": 3600, "token_type": "bearer", "refresh_token": "r", "user_id": "4815", "loginTime": 1}"#
        check(GOGAuth.from(output: Data(credentials.utf8), log: "") == .signedIn(token: "tok", user: "4815"), "gogdl's credentials")
        check(GOGAuth.from(output: Data("null\n".utf8), log: "[AUTH] ERROR: Failed to refresh credentials") == .offline,
              "no answer from GOG: offline, not signed out")
        check(GOGAuth.from(output: Data("null\n".utf8), log: "") == .signedOut, "GOG turned the refresh down: signed out")
        check(GOGAuth.from(output: Data(#"{"error": true}"#.utf8), log: "") == .signedOut, "a sign-in code GOG didn't take")
        check(GOGAuth.from(output: Data(#"{"error": true}"#.utf8), log: "", status: 1) == .signedOut, "also with an error code")
        let refused = "[PYI-45608:ERROR] Security validation failure: unexpected name of application's home directory!\n"
        check(GOGAuth.from(output: Data(), log: refused, status: 255) == .helperFailed, "gogdl didn't run: not GOG's no")
        check(GOGAuth.from(output: Data(), log: "", status: 0) == .signedOut, "no answer but no error either: signed out")

        // gogdl's auth.json: what `gogdl auth` hands out without asking GOG while it's good.
        let stored = #"{"46899977096215655": {"access_token": "tok", "expires_in": 3600, "refresh_token": "r", "user_id": "4815", "loginTime": 1000.5}}"#
        check(GOGAuth.stored(Data(stored.utf8), now: Date(timeIntervalSince1970: 1000.5 + 1800)) == .signedIn(token: "tok", user: "4815"),
              "a token that's still good is read, without gogdl")
        check(GOGAuth.stored(Data(stored.utf8), now: Date(timeIntervalSince1970: 1000.5 + 3400)) == nil, "one about to run out goes to gogdl")
        check(GOGAuth.stored(Data(stored.utf8), now: Date(timeIntervalSince1970: 1000.5 + 7200)) == nil, "and one that ran out")
        check(GOGAuth.stored(Data(#"{"1234": {"access_token": "game", "expires_in": 3600, "user_id": "4815", "loginTime": 1000}}"#.utf8),
                             now: Date(timeIntervalSince1970: 1500)) == nil, "a game's own token isn't the account's")
        check(GOGAuth.stored(Data("{}".utf8)) == nil && GOGAuth.stored(Data("not json".utf8)) == nil, "nothing stored")

        let log = """
            [AUTH] INFO: Exchanging code 0a1b2c3d for tokens
            [AUTH] DEBUG: https://auth.gog.com/token?client_id=46899977096215655&code=0a1b2c3d&grant_type=authorization_code
            [AUTH] DEBUG: {"access_token": "secret-access", "refresh_token": "secret-refresh", "user_id": "4815"}
            [AUTH] ERROR: something else
            """
        let credentials2 = #"{"access_token": "secret-access", "refresh_token": "secret-refresh", "user_id": "4815"}"#
        let text = GOGDL.authLogText(Legendary.Output(status: 0, output: Data(credentials2.utf8), log: log),
                                     command: "auth --code", hiding: ["0a1b2c3d"], at: Date(timeIntervalSince1970: 0))
        check(!text.contains("0a1b2c3d") && !text.contains("secret-access") && !text.contains("secret-refresh"),
              "the auth log has neither the code nor a token: \(text)")
        check(text.hasPrefix("1970-01-01T00:00:00Z gogdl auth --code ended with 0\nanswer: credentials\n"), "but how it ended")
        check(text.contains("[AUTH] ERROR: something else") && text.contains("\"user_id\": \"4815\""), "and the rest of gogdl's log")
        let failed = GOGDL.authLogText(Legendary.Output(status: 255, output: Data(), log: refused), command: "auth --code", hiding: ["x"])
        check(failed.contains("ended with 255\nanswer: none (0 bytes, not JSON)") && failed.contains("Security validation failure"),
              "a gogdl that didn't run: its code and message")
        check(GOGDL.authLogText(Legendary.Output(status: 0, output: Data(#"{"error": true}"#.utf8), log: ""), command: "auth --code",
                                hiding: []).contains("answer: JSON with error"), "GOG's no")
    }

    /// GOG Galaxy's redistributables: what a manifest asks for, what runs and how, what's left out.
    static func redistFormats() {
        let needs = GOGRedist.Needs.from(manifest: Data(mafiaManifest.utf8))
        check(needs?.dependencies == ["DirectX", "MSVC2017", "PHYSXLEGACY", "PHYSX"] && needs?.scriptInterpreter == true
              && needs?.products.map(\.id) == ["1816059595"] && needs?.build == "51277443195366142", "Mafia II's needs from its manifest")
        let v1 = GOGRedist.Needs.from(manifest: Data(#"{"version": 1, "product": {"depots": [{"redist": "DirectX"}, {"size": "1"}, {"redist": "MSVC2008"}, {"redist": "DirectX"}]}}"#.utf8))
        check(v1?.dependencies == ["DirectX", "MSVC2008"] && v1?.scriptInterpreter == false, "an old (v1) build: its redist depots")
        let repository = GOGRedist.Repository.from(json: Data(redistRepository.utf8))
        check(repository?.depots.count == 9 && repository?.fetched == ["MSVC2010"], "the repository as gogdl keeps it")
        guard let needs, let repository else { return }

        let record = GOGRedist.Record()
        check(GOGRedist.wanted(needs, record: record) == ["MSVC2017", "PHYSXLEGACY", "PHYSX"],
              "DirectX is left out (winecx has it built in): \(GOGRedist.wanted(needs, record: record))")
        check(GOGRedist.idsToFetch(wanted: ["MSVC2017", "PHYSXLEGACY", "PHYSX"], script: true, repository: repository)
              == ["ISI", "MSVC2010", "MSVC2017", "PHYSX", "PHYSXLEGACY"], "fetched: what's wanted, the interpreter, and what was there (gogdl would delete it)")
        let dotNet = GOGRedist.Needs(dependencies: ["dotNet4", "MSVC2010"])
        check(GOGRedist.wanted(dotNet, record: record) == ["MSVC2010"] && GOGRedist.needsWineMono(dotNet), ".NET Framework: Wine Mono instead")

        let folder = GOGRedist.folder
        let legacy = GOGRedist.command(for: repository.depots["PHYSXLEGACY"]!, in: folder)
        check(legacy == ["msiexec", "/i", Engine.windowsPath(of: folder.appendingPathComponent("__redist/PHYSXLEGACY/PhysX-9.13.0604-SystemSoftware-Legacy.msi")),
                         "/norestart", "/qn"], "an .msi: through msiexec, without a window: \(legacy)")
        check(GOGRedist.command(for: repository.depots["MSVC2017"]!, in: folder).dropFirst() == ["/install", "/quiet", "/norestart"],
              "an installer with GOG's arguments")
        check(GOGRedist.command(for: repository.depots["UE4REDIST"]!, in: folder).dropFirst() == ["/quiet", "/norestart"], "/passive becomes /quiet")
        check(GOGRedist.split(repository.depots["MSVC2005"]!.arguments) == ["/q:a", "/c:VCREDI~3.EXE /q:a /c:msiexec /i vcredist.msi /qb "],
              "quotes group, as shlex splits them: \(GOGRedist.split(repository.depots["MSVC2005"]!.arguments))")
        check(GOGRedist.split("") == [] && GOGRedist.split("-s") == ["-s"] && GOGRedist.split(#"a "" b"#) == ["a", "", "b"], "and the plain cases")
        check(GOGRedist.succeeded(0) && GOGRedist.succeeded(3010 & 0xFF) && GOGRedist.succeeded(1638 & 0xFF) && !GOGRedist.succeeded(1),
              "done, done with a restart wanted, a newer one there – not an error")

        let install = GOGInstall(id: "1816059595", path: GOGDL.windowsGamesDir.appendingPathComponent("Mafia II", isDirectory: true),
                                 platform: .windows, build: "51277443195366142", language: "de-DE", size: 1)
        let script = GOGRedist.productCommand(needs.products[0], needs: needs, install: install, versionName: "update5A")
        check(script.first == Engine.windowsPath(of: GOGRedist.interpreter) && script.contains("/VERYSILENT")
              && script.contains(#"/DIR=C:\Program Files\GOG Games\Mafia II"#) && script.contains("/Language=German")
              && script.contains("/ProductId=1816059595") && script.contains("/buildId=51277443195366142")
              && script.contains("/versionName=update5A") && script.contains("/lang-code=de-DE") && script.contains("/nodesktopshorctut"),
              "GOG's install script, started as Galaxy starts it: \(script)")
        check(GOGRedist.productsDue(needs, install: install, record: record) == ["1816059595"], "the install script is due")
        var ran = record
        ran.products["1816059595"] = "51277443195366142"
        check(GOGRedist.productsDue(needs, install: install, record: ran).isEmpty, "once per build")
        var updated = needs
        updated.build = "99"
        check(GOGRedist.productsDue(updated, install: install, record: ran) == ["1816059595"], "and again after an update")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var failing = GOGRedist.Record()
        failing.failed("PHYSX", now: now)
        check(failing.gaveUp("PHYSX", now: now.addingTimeInterval(60)), "not again within the same start")
        check(!failing.gaveUp("PHYSX", now: now.addingTimeInterval(11 * 60)), "but at a later one")
        failing.failed("PHYSX", now: now.addingTimeInterval(11 * 60))
        check(failing.gaveUp("PHYSX", now: now.addingTimeInterval(3600)), "and not after twice: each start would wait for it")
    }

    /// The whole setup, with a stand-in for Wine that notes what it's asked to run.
    static func redistSetUp() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: Engine.prefix, withIntermediateDirectories: true)
        try? fm.createDirectory(at: GOGDL.manifest(for: "1816059595").deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(mafiaManifest.utf8).write(to: GOGDL.manifest(for: "1816059595"))
        try? fm.createDirectory(at: GOGRedist.folder, withIntermediateDirectories: true)
        try? Data(redistRepository.utf8).write(to: GOGRedist.repositoryFile)
        for path in ["__redist/ISI/scriptinterpreter.exe", "__redist/MSVC2017/VC_redist.x86.exe", "__redist/PHYSX/PhysX-9.17.0524-SystemSoftware.exe",
                     "__redist/PHYSXLEGACY/PhysX-9.13.0604-SystemSoftware-Legacy.msi"] {
            let file = GOGRedist.folder.appendingPathComponent(path)
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: file.path, contents: Data("MZ".utf8))
        }
        let calls = fm.temporaryDirectory.appendingPathComponent("wine-calls-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: calls) }
        let wine = fm.temporaryDirectory.appendingPathComponent("fake-wine-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: wine) }
        // PhysX 9.17 fails; everything else is done.
        try? Data("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"\(calls.path)\"\ncase \"$*\" in *PhysX-9.17*) exit 1;; esac\nexit 0\n".utf8).write(to: wine)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)

        let install = GOGInstall(id: "1816059595", path: GOGDL.windowsGamesDir.appendingPathComponent("Mafia II", isDirectory: true),
                                 platform: .windows, build: "51277443195366142", language: "de-DE", size: 1)
        try? fm.createDirectory(at: install.path, withIntermediateDirectories: true)
        check(GOGRedist.hasWork(install), "a game installed before: its setup is still to do")
        var parts: [String?] = []
        let outcome = await GOGRedist.setUp(install, versionName: "update5A", wine: wine) { parts.append($0) }
        let lines = ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        check(lines.count == 4 && lines[0].contains("VC_redist.x86.exe /install /quiet /norestart")
              && lines[1].hasPrefix("msiexec /i ") && lines[1].hasSuffix("/norestart /qn") && lines[2].contains("PhysX-9.17.0524")
              && lines[3].contains("scriptinterpreter.exe /VERYSILENT"), "three installers in the manifest's order, then the script: \(lines)")
        check(!lines.contains { $0.contains("DXSETUP") }, "not DirectX")
        check(parts.contains("Visual C++ Redist 2017") && parts.contains("NVIDIA PhysX Legacy (9.13.0604)"), "each part is named as it goes: \(parts)")
        check(outcome.failed == ["NVIDIA PhysX (9.17.0524)"] && outcome.retried, "what failed is said, and tried again later: \(outcome)")
        let record = GOGRedist.loadRecord()
        check(record.installed == ["MSVC2017", "PHYSXLEGACY"] && record.products["1816059595"] == "51277443195366142",
              "noted in the environment: \(record)")
        check(!GOGRedist.hasWork(install), "right after: nothing to do (PhysX waits for a later start)")

        // A second game with the same needs costs nothing.
        try? fm.removeItem(at: calls)
        let other = GOGInstall(id: "42", path: install.path, platform: .windows, build: "1", language: "en-US", size: 1)
        try? Data(#"{"version": 2, "buildId": "1", "dependencies": ["MSVC2017", "DirectX"], "products": [{"productId": "42"}]}"#.utf8)
            .write(to: GOGDL.manifest(for: "42"))
        check(!GOGRedist.hasWork(other), "another game with the same parts: nothing to do")
        _ = await GOGRedist.setUp(other, versionName: nil, wine: wine) { _ in }
        check(!fm.fileExists(atPath: calls.path), "and nothing runs")
    }

    /// After `wineserver -k` the sweep ends Wine's programs in the prefix only: a downloader working
    /// there (gogdl into Program Files\GOG Games) carries on – The Evil Within 2 was ended at 84 %
    /// (code 137) by a GOG game's fresh Wine session on 1.11.2026.
    static func leftovers() {
        let fm = FileManager.default
        let engines = Engine.engineFolders.map { $0.path }, components = ComponentStore.shared.root.path
        func wine(_ path: String) -> Bool { Engine.isWineProgram(path, engines: engines, components: components) }
        check(wine(Engine.engineFolders[1].appendingPathComponent("4.7.3/Libraries/Wine/bin/wine64-preloader").path)
              && wine(Engine.engineFolders[1].appendingPathComponent("4.7.3/Libraries/Wine/Nightforge Game.app/Contents/MacOS/wine").path),
              "the engine's programs and its game-mode loader are Wine's")
        check(!wine(ComponentStore.shared.root.appendingPathComponent("gogdl/1.4.0/gogdl_macos_arm64").path)
              && !wine(ComponentStore.shared.root.appendingPathComponent("legendary/0.21.1/legendary_macOS_arm64").path),
              "gogdl and legendary aren't")
        check(wine(ComponentStore.shared.root.appendingPathComponent("wine-devel/9.0/bin/wineserver").path)
              && !wine("/opt/homebrew/bin/wineserver") && !wine("/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
              "a Wine binary by its name only in Nightforge's components, not another app's")

        // Two stand-ins (copies of this test, which wait – macOS won't run a moved /bin/sleep)
        // working in the game's folder in the prefix.
        let folder = GOGDL.windowsGamesDir.appendingPathComponent("The Evil Within 2", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        func start(_ program: URL, in cwd: URL? = nil) -> Process {
            try? fm.createDirectory(at: program.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: program)
            if let me = Bundle.main.executableURL { try? fm.copyItem(at: me, to: program) }
            let process = Process()
            process.executableURL = program
            process.arguments = ["--stand-in"]
            process.currentDirectoryURL = cwd ?? folder
            try? process.run()
            return process
        }
        // A folder of its own without .sha256: never taken for the installed gogdl, which run.sh may
        // have copied in for `realProgram` (overwriting that made it run this test instead, c1eeaac).
        let download = start(ComponentStore.shared.root.appendingPathComponent("gogdl/0.0.0-stand-in/gogdl_macos_arm64"))
        let leftover = start(Engine.engineFolders[1].appendingPathComponent("4.7.3/Libraries/Wine/bin/wine"))
        // A Wine program in a folder beside the prefix whose name starts the same ("Prefix-backup").
        let backup = Engine.prefix.deletingLastPathComponent().appendingPathComponent(Engine.prefix.lastPathComponent + "-backup", isDirectory: true)
        try? fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let beside = start(Engine.engineFolders[1].appendingPathComponent("4.7.3/Libraries/Wine/bin/wineserver"), in: backup)
        Thread.sleep(forTimeInterval: 0.5)
        check(download.isRunning && leftover.isRunning && beside.isRunning, "all three run before the sweep")
        // The sweep's second look is at the programs started from the engine: the two stand-ins, by their own pids.
        FakeProcesses.install { FakeProcesses.rows(of: [download.processIdentifier, leftover.processIdentifier]) }
        Engine.killLeftovers()
        FakeProcesses.installEmpty()
        Thread.sleep(forTimeInterval: 0.5)
        check(download.isRunning, "a download working in the prefix outlives the sweep")
        check(!leftover.isRunning, "a Wine program left there doesn't")
        check(beside.isRunning, "nor is one in \"\(backup.lastPathComponent)\" beside the prefix ended")
        download.terminate()
        beside.terminate()
        if leftover.isRunning { leftover.terminate() }
        try? fm.removeItem(at: backup)
    }

    /// The real gogdl, when run.sh found it installed on this Mac: started the way Nightforge starts
    /// it, from an unpacked copy first – gogdl 1.4.0 refuses that and runs as it comes.
    static func realProgram() async {
        guard let binary = GOGDL.programNow() else {
            print("– gogdl isn't installed on this Mac: the check with the real program is skipped")
            return
        }
        _ = try? PackedApp.unpackOnce(binary)
        let started = Date()
        let result = try? await GOGDL.run(["--version"], timeout: 120)
        let seconds = Date().timeIntervalSince(started)
        check(result?.status == 0, "the real gogdl runs: code \(result.map { String($0.status) } ?? "none"), \(result?.log.suffix(300) ?? "")")
        check(result.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).first?.isNumber == true } == true,
              "and says its version: \(result?.text ?? "nothing")")
        let mode = PackedApp.refusesUnpacked(binary) ? "as it comes (it refuses the unpacked copy)" : "from the unpacked copy"
        print(String(format: "– the real gogdl %@ ran %@ in %.1f s", result?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?", mode, seconds))
    }

    static func sizes() {
        let german = GOGSize.from(info: Data(info.utf8), preferred: ["de-DE", "en-US"])
        check(german?.language == "de-DE", "the Mac's language when GOG has the game in it")
        check(german?.download == 30_000_000_000 + 1_500_000_000 + 3_000_000_000 + 100
              && german?.install == 45_000_000_000 + 2_500_000_000 + 4_000_000_000 + 200,
              "the game in that language plus the add-ons: \(String(describing: german))")
        check(german?.dlcs == [GOGDLC(id: "1207660413", title: "Hearts of Stone")], "the add-ons that come along, no odd IDs")
        check(german?.folder == "The Witcher 3 Wild Hunt GOTY" && german?.build == "56258405493426547", "its folder and build")
        let english = GOGSize.from(info: Data(info.utf8), preferred: ["ja-JP"])
        check(english?.language == "en-US" && english?.download == 30_000_000_000 + 1_000_000_000 + 3_000_000_000,
              "a language GOG doesn't have: English")
        check(GOGSize.language(available: ["en-US", "de-DE"], preferred: ["de"]) == "de-DE", "\"de\" finds de-DE")
        check(GOGSize.language(available: ["fr-FR"], preferred: ["de-DE"]) == "fr-FR", "no English either: what GOG has")
        let odd = GOGSize.from(info: Data(info.replacingOccurrences(of: "The Witcher 3 Wild Hunt GOTY", with: "../..").utf8))
        check(odd?.folder == "", "a folder name that would climb out isn't taken")
        check(GOGSize.from(info: Data(#"{"size": {}}"#.utf8)) == nil, "no size, no answer")
    }

    static func builds() {
        let json = #"""
        {"total_count": 3, "items": [{"build_id": "999", "branch": "beta", "generation": 2},
                                     {"build_id": "56258405493426547", "branch": null, "generation": 2, "legacy_build_id": "51"},
                                     {"build_id": "1", "branch": null}]}
        """#
        let latest = GOGBuild.latest(fromJSON: Data(json.utf8))
        check(latest?.id == "56258405493426547", "the newest build without a branch (no betas)")
        check(latest?.matches("51") == true && latest?.matches("1") == false, "an old game's legacy ID counts as the same build")
        let install = GOGInstall(id: "7", path: URL(fileURLWithPath: "/x"), platform: .windows, build: "56258405493426547",
                                 language: "en-US", size: 1, dlcs: ["8"])
        check(!GOGStore.needsUpdate(install, latest: latest, owned: ["8"]), "the newest build with every add-on: up to date")
        check(GOGStore.needsUpdate(install, latest: GOGBuild(id: "6"), owned: ["8"]), "a newer build waits")
        check(GOGStore.needsUpdate(install, latest: latest, owned: ["8", "9"]), "an add-on bought since comes with an update")
        check(!GOGStore.needsUpdate(install, latest: nil, owned: []), "nothing known: nothing to say")
    }

    static func gameInfo() {
        let json = #"""
        {"version": 1, "gameId": "1207664663", "rootGameId": "1207664663", "buildId": "56258405493426547", "clientId": "46755278331571209",
         "name": "The Witcher 3: Wild Hunt", "language": "English",
         "playTasks": [{"category": "document", "isPrimary": false, "name": "Manual", "path": "manual.pdf", "type": "FileTask"},
                       {"category": "launcher", "isPrimary": false, "link": "https://gog.com", "type": "URLTask"},
                       {"category": "game", "isPrimary": true, "name": "The Witcher 3", "path": "bin\\x64\\witcher3.exe",
                        "arguments": "-net \"two words\" -debugscripts", "workingDir": "bin\\x64", "type": "FileTask"}]}
        """#
        let parsed = GOGGameInfo.from(json: Data(json.utf8))
        check(parsed?.path == "bin/x64/witcher3.exe", "the primary task's program: \(String(describing: parsed?.path))")
        check(parsed?.arguments == ["-net", "two words", "-debugscripts"], "its arguments, quotes kept together")
        check(parsed?.workingDir == "bin/x64" && parsed?.clientID == "46755278331571209" && parsed?.build == "56258405493426547",
              "its folder, client ID (for cloud saves) and build")
        let folder = URL(fileURLWithPath: "/G/The Witcher 3", isDirectory: true)
        let command = parsed?.command(in: folder)
        check(command?.executable.path == "/G/The Witcher 3/bin/x64/witcher3.exe" && command?.workingDirectory.path == "/G/The Witcher 3/bin/x64",
              "started from its folder")
        check(Engine.windowsPath(of: GOGDL.windowsGamesDir.appendingPathComponent("X/x.exe")) == #"C:\Program Files\GOG Games\X\x.exe"#,
              "Wine sees a Windows version under C:\\Program Files\\GOG Games")
        let noDir = GOGGameInfo.from(json: Data(#"{"playTasks": [{"isPrimary": true, "path": "game.exe"}]}"#.utf8))
        check(noDir?.command(in: folder).workingDirectory.path == "/G/The Witcher 3", "no folder named: the game folder, as gogdl does")
        check(GOGGameInfo.from(json: Data(#"{"playTasks": [{"isPrimary": true, "path": "..\\..\\evil.exe"}]}"#.utf8)) == nil,
              "a program outside the game folder isn't started")
        check(GOGGameInfo.from(json: Data(#"{"playTasks": [{"isPrimary": true, "path": "C:\\Windows\\x.exe"}]}"#.utf8)) == nil,
              "nor one on a drive of its own")
        let firstFile = GOGGameInfo.from(json: Data(#"{"playTasks": [{"type": "URLTask", "link": "x"}, {"type": "FileTask", "path": "a.exe"}]}"#.utf8))
        check(firstFile?.path == "a.exe", "no primary task: the first program")

        // Where the file lies: the game folder (Windows), an app's Resources (Mac).
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("gog-info-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let windows = dir.appendingPathComponent("Game", isDirectory: true)
        let mac = dir.appendingPathComponent("Game.app/Contents/Resources", isDirectory: true)
        try? fm.createDirectory(at: windows, withIntermediateDirectories: true)
        try? fm.createDirectory(at: mac, withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: windows.appendingPathComponent("goggame-1207664663.info"))
        try? Data(#"{"name": "Stardew Valley", "playTasks": [{"isPrimary": true, "path": "Contents/MacOS/Stardew Valley"}]}"#.utf8)
            .write(to: mac.appendingPathComponent("goggame-1453375253.info"))
        check(GOGGameInfo.read(id: "1207664663", in: windows)?.name == "The Witcher 3: Wild Hunt", "read from the Windows game's folder")
        check(GOGGameInfo.read(id: "1453375253", in: dir.appendingPathComponent("Game.app"))?.path == "Contents/MacOS/Stardew Valley",
              "and from the Mac app's Resources")
        check(GOGStore.installFolder(id: "1453375253", preferred: "Other", in: dir)?.lastPathComponent == "Game.app",
              "a download's folder is found by its info file when GOG's name for it isn't there")
        check(GOGStore.installFolder(id: "1207664663", preferred: "Game", in: dir)?.lastPathComponent == "Game", "GOG's name first")
        check(GOGStore.installFolder(id: "5", preferred: nil, in: dir) == nil, "nothing for a game that isn't there")
    }

    static func saves() {
        let user = URL(fileURLWithPath: "/P/drive_c/users/crossover", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let install = URL(fileURLWithPath: "/G/Game", isDirectory: true)
        let config = #"""
        {"version": "2.0", "content": {
          "Windows": {"overlay": {"supported": true}, "cloudStorage": {"enabled": true, "locations": [
              {"name": "__default", "location": "<?SAVED_GAMES?>/CD Projekt Red/Cyberpunk 2077"},
              {"name": "settings", "location": "<?APPLICATION_DATA_LOCAL?>\\CD Projekt Red\\Cyberpunk 2077"},
              {"name": "evil", "location": "<?INSTALL?>/../../etc"},
              {"name": "odd", "location": "<?SOMETHING?>/x"}]}},
          "MacOS": {"overlay": {"supported": false}, "cloudStorage": {"enabled": true, "locations": []}},
          "cloudStorage": {"quota": 200}}}
        """#
        let windows = GOGSaves.locations(fromConfig: Data(config.utf8), platform: .windows, clientID: "c1", installDir: install,
                                         windowsUser: user, home: home)
        check(windows?.map(\.name) == ["__default", "settings"], "named save folders, without ones that climb out or GOG's unknowns")
        check(windows?.first?.folder.path == "/P/drive_c/users/crossover/Saved Games/CD Projekt Red/Cyberpunk 2077",
              "Saved Games in the Windows user's folder")
        check(windows?.last?.folder.path == "/P/drive_c/users/crossover/AppData/Local/CD Projekt Red/Cyberpunk 2077", "AppData\\Local, backslashes too")
        let mac = GOGSaves.locations(fromConfig: Data(config.utf8), platform: .mac, clientID: "c1", installDir: install, windowsUser: user, home: home)
        check(mac?.map(\.name) == ["__default"]
              && mac?.first?.folder.path == "/Users/me/Library/Application Support/GOG.com/Galaxy/Applications/c1/Storage/Shared/Files",
              "no folders named: GOG Galaxy's own, in the Mac's Application Support: \(String(describing: mac))")
        let off = config.replacingOccurrences(of: #""enabled": true"#, with: #""enabled": false"#)
        check(GOGSaves.locations(fromConfig: Data(off.utf8), platform: .windows, clientID: "c1", installDir: install, windowsUser: user) == nil,
              "no cloud saves: nothing to sync")
        check(GOGSaves.resolve("<?INSTALL?>/saves", platform: .windows, installDir: install, windowsUser: user, home: home)?.path == "/G/Game/saves",
              "the game's own folder")
        check(GOGSaves.resolve("<?APPLICATION_SUPPORT?>/x", platform: .windows, installDir: install, windowsUser: user, home: home) == nil,
              "a Mac folder isn't one for a Windows version")
    }

    static func machO() {
        func bytes(_ values: [UInt32], littleEndian: Bool = false) -> Data {
            values.reduce(into: Data()) { data, value in
                withUnsafeBytes(of: littleEndian ? value.littleEndian : value.bigEndian) { data.append(contentsOf: $0) }
            }
        }
        check(MachO.runsHere(bytes([0xFEED_FACF, 0x0100_000C], littleEndian: true)) == true, "a 64-bit program runs")
        check(MachO.runsHere(bytes([0xFEED_FACE, 7], littleEndian: true)) == false, "a 32-bit one doesn't (since macOS 10.15)")
        check(MachO.runsHere(bytes([0xCAFE_BABE, 2, 7, 3, 0, 0, 12, MachO.x86_64, 3, 0, 0, 12])) == true, "universal with Intel 64-bit")
        check(MachO.runsHere(bytes([0xCAFE_BABE, 2, 7, 3, 0, 0, 12, 18, 0, 0, 0, 12])) == false, "universal with i386 and PowerPC only")
        check(MachO.runsHere(Data("#!/bin/sh\nexec x\n".utf8)) == nil, "a script runs as it is")
        check(MachO.runsHere(bytes([0xCAFE_BABE, 52, 0])) == nil, "a Java class (same magic) isn't taken for a Mac program")
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent("gog-\(UUID().uuidString).app", isDirectory: true)
        defer { try? fm.removeItem(at: app) }
        try? fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        (["CFBundleExecutable": "Old Game"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        try? bytes([0xFEED_FACE, 7, 3], littleEndian: true).write(to: app.appendingPathComponent("Contents/MacOS/Old Game"))
        check(MachO.runsHere(file: app) == false, "an app is judged by its own program (Info.plist)")
    }

    static func progress() {
        let running = """
        [GENERIC DOWNLOAD_MANAGER] INFO: Depot version: 2
        [V2] INFO: Initialized V2 Download Manager
        [PROGRESS] INFO: = Progress: 12.50 125000000/1000000000, Running for: 00:00:10, ETA: 00:01:10
        [PROGRESS] INFO: = Downloaded: 110.00 MiB, Written: 119.21 MiB
        [PROGRESS] INFO:  + Download\t- 11.50 MiB/s (raw) / 13.00 MiB/s (decompressed)
        [PROGRESS] INFO:  + Disk\t- 12.00 MiB/s (write) / 0.00 MiB/s (read)
        [TASK_EXECUTOR] WARNING: Chunk download failed, reason x
        """
        let state = GOGDL.progress(inLog: running)
        check(state.fraction == 0.125 && state.total == 1_000_000_000, "how far, of how much: \(state)")
        check(state.speed == 11.5 * 1_048_576 && state.secondsLeft == 70, "speed and time left")
        check(state.exitCode == nil && state.failure == nil && !state.finished, "still running: no verdict yet (a warning isn't one)")
        let done = GOGDL.progress(inLog: running + "\n" + GOGDL.endMark + "0\n")
        check(done.finished && done.fraction == 1 && done.failure == nil, "ended with 0: done")
        let upToDate = GOGDL.progress(inLog: "[V2] INFO: Nothing to do\n\(GOGDL.endMark)0")
        check(upToDate.finished, "nothing to do is done too")
        let full = GOGDL.progress(inLog: "1.5 GiB 1610612736\nUnable to proceed, Not enough disk space\n\(GOGDL.endMark)2")
        check(full.exitCode == 2 && full.failure == L10n.t("there isn't enough space on the Mac"), "no room: says so")
        let failed = GOGDL.progress(inLog: "[GENERIC DOWNLOAD_MANAGER] ERROR: Game doesn't support content system api, unable to proceed using platform osx\n\(GOGDL.endMark)1")
        check(failed.failure == "Game doesn't support content system api, unable to proceed using platform osx", "gogdl's own reason: \(String(describing: failed.failure))")
        check(GOGDL.progress(inLog: "\(GOGDL.endMark)9").failure == L10n.t("gogdl stopped (code %d)", 9), "no reason given: its code")

        check(GOGStore.updateOutcome(done) == .updated, "an update that finished")
        check(GOGStore.updateOutcome(GOGDL.progress(inLog: "\(GOGDL.endMark)1")) == .skipped(.offline),
              "an update that fetched nothing: the game starts as it is")
        check(GOGStore.updateOutcome(full) == .failed(L10n.t("there isn't enough space on the Mac")), "no room for the update: the player hears of it")
        let halfway = GOGDL.progress(inLog: running + "\n" + GOGDL.endMark + "1")
        if case .failed = GOGStore.updateOutcome(halfway) {} else { check(false, "an update that stopped halfway doesn't start the game") }
    }

    static func signIn() {
        check(GOGSignIn.signInURL.absoluteString.hasPrefix("https://auth.gog.com/auth?client_id=46899977096215655"), "GOG Galaxy's sign-in page")
        check(GOGSignIn.signInURL.query?.contains("redirect_uri=https://embed.gog.com/on_login_success?origin%3Dclient") == true
              || GOGSignIn.signInURL.query?.contains("on_login_success") == true, "which sends the code to GOG's own page")
        check(GOGSignIn.code(from: URL(string: "https://embed.gog.com/on_login_success?origin=client&code=Ab-12_c.D")!) == "Ab-12_c.D", "the code")
        check(GOGSignIn.code(from: URL(string: "https://evil.example/on_login_success?code=abc")!) == nil, "only from GOG")
        check(GOGSignIn.code(from: URL(string: "http://embed.gog.com/on_login_success?code=abc")!) == nil, "only over https")
        check(GOGSignIn.code(from: URL(string: "https://embed.gog.com/on_login_success?origin=client")!) == nil, "no code, nothing")
        check(GOGSignIn.code(from: URL(string: "https://embed.gog.com/on_login_success?code=a%20b")!) == nil, "nothing odd in it")
        check(GOGSignIn.code(from: URL(string: "https://embed.gog.com/account?code=abc")!) == nil, "only the page the sign-in ends on")
    }

    static func macFirst() {
        check(GOGStore.version(mac: true, unfit: false, choice: .automatic) == .mac, "GOG has a Mac version: it comes first")
        check(GOGStore.version(mac: false, unfit: false, choice: .automatic) == .windows, "none: the Windows version")
        check(GOGStore.version(mac: true, unfit: true, choice: .automatic) == .windows, "one too old for this Mac: Windows")
        check(GOGStore.version(mac: true, unfit: false, choice: .windows) == .windows, "Windows picked in the options")
        check(GOGStore.version(mac: false, unfit: false, choice: .mac) == .windows, "Mac picked, but there's none")
        check(GOGStore.folderName("Baldur's Gate: Enhanced Edition") == "Baldur's Gate Enhanced Edition" && GOGStore.folderName("..") == "Game",
              "a folder name from a title")
    }

    static func game(_ id: GameID, _ name: String, _ install: InstallState = .notInstalled, platform: Platform = .windows,
                     daysAgo: Double? = nil) -> Game {
        var game = Game(gameID: id, name: name, bottle: Engine.bottle, steamRoot: Engine.steamRoot, steamExeWindowsPath: "",
                        installDir: Engine.prefix, sizeOnDisk: 1, lastPlayed: daysAgo.map { Date().addingTimeInterval(-$0 * 86_400) })
        game.install = install
        game.platform = platform
        return game
    }

    static func merging() {
        let steam = game(.steam(292030), "The Witcher® 3: Wild Hunt")
        let gog = game(.gog("1207664663"), "The Witcher 3: Wild Hunt")
        let epic = game(.epic("Daisy"), "The Witcher 3: Wild Hunt")
        let cards = DuplicateGames.merge([steam, gog, epic, game(.gog("1"), "Gwent")], chosen: { _ in nil })
        check(cards.count == 2 && cards.first?.providers == [.steam, .epic, .gog], "one card for all three stores, Steam first: \(cards.map(\.providers))")
        let macCard = DuplicateGames.merge([steam, game(.gog("1207664663"), "The Witcher 3: Wild Hunt", platform: .mac)], chosen: { _ in nil })
        check(macCard.first?.provider == .gog, "a store with its Mac version comes before Steam's Windows version (Mac first)")
        let installed = DuplicateGames.merge([game(.steam(292030), "The Witcher 3: Wild Hunt", .installed),
                                              game(.gog("1207664663"), "The Witcher 3: Wild Hunt", platform: .mac)], chosen: { _ in nil })
        check(installed.first?.provider == .steam, "but the copy on the Mac comes before a download")
        let chosen = DuplicateGames.merge([steam, game(.gog("1207664663"), "The Witcher 3: Wild Hunt", platform: .mac)], chosen: { _ in .steam })
        check(chosen.first?.provider == .steam, "and the store picked on the page before both")
    }

    // MARK: - The store

    static var gogFolder: URL { Engine.supportDir.appendingPathComponent("GOG", isDirectory: true) }

    @MainActor
    static func store() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: gogFolder, withIntermediateDirectories: true)
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        let releases = [stardew, witcher, heartsOfStone].compactMap { GOGRelease.from(gamesDB: Data($0.utf8)) }
        try? JSONEncoder().encode(GOGLibrary(games: GOGLibrary.games(from: releases), loaded: threeDaysAgo))
            .write(to: gogFolder.appendingPathComponent("library.json"))
        // The Witcher on the Mac (Windows version), with GOG having a newer build since.
        let witcherDir = GOGDL.windowsGamesDir.appendingPathComponent("The Witcher 3 Wild Hunt GOTY", isDirectory: true)
        try? fm.createDirectory(at: witcherDir.appendingPathComponent("bin/x64"), withIntermediateDirectories: true)
        try? Data(#"{"name": "The Witcher 3", "buildId": "1", "clientId": "c", "playTasks": [{"isPrimary": true, "path": "bin\\x64\\witcher3.exe"}]}"#.utf8)
            .write(to: witcherDir.appendingPathComponent("goggame-1207664663.info"))
        fm.createFile(atPath: witcherDir.appendingPathComponent("bin/x64/witcher3.exe").path, contents: Data("MZ".utf8))
        try? JSONEncoder().encode(["1207664663": GOGInstall(id: "1207664663", path: witcherDir, platform: .windows, build: "1",
                                                            language: "de-DE", size: 50_000, dlcs: ["1207660413"])])
            .write(to: gogFolder.appendingPathComponent("installed.json"))
        try? JSONEncoder().encode(["1207664663": GOGBuild(id: "2")]).write(to: gogFolder.appendingPathComponent("builds.json"))
        try? JSONEncoder().encode(["1453375253.mac": GOGSize(build: "9", download: 500, install: 900, language: "en-US", folder: "Stardew Valley.app")])
            .write(to: gogFolder.appendingPathComponent("sizes.json"))

        let store = GOGStore()
        check(await store.library().isEmpty, "not connected: no GOG games")
        try? Data(#"{"username": "Geralt"}"#.utf8).write(to: gogFolder.appendingPathComponent("account.json"))
        check(store.isConnected && store.accountName == "Geralt" && !store.isSignedIn, "connected as Geralt, gogdl holds no tokens yet")

        let games = await store.library()
        check(games.count == 2, "the library from last time is there at once: \(games.map(\.name))")
        let witcherGame = games.first { $0.gameID == .gog("1207664663") }
        check(witcherGame?.install == .installed && witcherGame?.installDir == witcherDir && witcherGame?.sizeOnDisk == 50_000,
              "The Witcher is installed")
        check(witcherGame?.platform == .windows && witcherGame?.provider == .gog && witcherGame?.appID == 0, "its Windows version, through Wine")
        check(witcherGame?.pendingUpdate != nil, "GOG has a newer build: Update & Play")
        check(witcherGame?.addOns == ["The Witcher 3 – Hearts of Stone"], "the game page names its add-on")
        check(witcherGame?.windowsFolderMarker == #"\GOG Games\The Witcher 3 Wild Hunt GOTY\"#, "its running process is recognised")
        check(witcherGame?.art?.cover?.absoluteString == "https://images.gog.com/cover-1207664663.jpg" && witcherGame?.art?.logo == nil,
              "GOG's cover, and no tile as a logo")
        check(witcherGame.map { OfflineReadiness.of($0, analysis: nil, accountRemembered: false) } == .drmFree,
              "DRM-free: plays offline, signed in or not")
        let command = witcherGame.flatMap { try? store.launchCommand(for: $0) }
        check(command?.executable.path == witcherDir.appendingPathComponent("bin/x64/witcher3.exe").path, "it starts from GOG's info file")
        check(GOGStore.executable(of: "1207664663", in: witcherDir) == "bin/x64/witcher3.exe", "which also says what its files reveal")

        let stardewGame = games.first { $0.gameID == .gog("1453375253") }
        check(stardewGame?.install == .notInstalled && stardewGame?.platform == .mac, "Stardew Valley: not on the Mac, its Mac version first")
        check(stardewGame?.installDir == GOGDL.macGamesDir.appendingPathComponent("Stardew Valley.app", isDirectory: true),
              "it goes into Nightforge's GOG folder, as an app")
        check(stardewGame?.sizeOnDisk == 900 && stardewGame?.downloadSize == 500, "its size is known before the download")
        check(stardewGame?.bottle.isBuiltIn == false && stardewGame?.inNightforgeFolder == true,
              "a Mac version runs outside Wine (no graphics presets), from Nightforge's folder")
        check(stardewGame?.id == "\(Engine.bottle.name)#gog.1453375253", "and keeps its place in the list whichever version it is")
        check(stardewGame.map { store.downloadArguments(GOGJob(id: $0.gameID.id, platform: .mac), folder: nil) }
              == ["download", "1453375253", "--platform", "osx", "--path", GOGDL.macGamesDir.path,
                  "--support", GOGDL.supportDir(for: "1453375253").path, "--with-dlcs", "--lang", "en-US"],
              "downloaded by gogdl, its Mac version with every add-on")
        check(store.downloadArguments(GOGJob(id: "1207664663", platform: .windows, update: true), folder: witcherDir)
              == ["update", "1207664663", "--platform", "windows", "--path", witcherDir.path,
                  "--support", GOGDL.supportDir(for: "1207664663").path, "--with-dlcs", "--lang", "de-DE"],
              "an update in the game's folder, in the language it has")

        // A download that ended while Nightforge was away: recorded once the library is looked at.
        let stardewApp = GOGDL.macGamesDir.appendingPathComponent("Stardew Valley.app", isDirectory: true)
        try? fm.createDirectory(at: stardewApp.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try? Data(#"{"name": "Stardew Valley", "buildId": "9", "playTasks": [{"isPrimary": true, "path": "Contents/MacOS/Stardew Valley"}]}"#.utf8)
            .write(to: stardewApp.appendingPathComponent("Contents/Resources/goggame-1453375253.info"))
        try? JSONEncoder().encode([GOGJob(id: "1453375253", platform: .mac)]).write(to: gogFolder.appendingPathComponent("downloads.json"))
        try? fm.createDirectory(at: GOGDL.logsDir, withIntermediateDirectories: true)
        try? Data("[PROGRESS] INFO: = Progress: 100.00 900/900, Running for: 00:00:10, ETA: 00:00:00\n\(GOGDL.endMark)0\n".utf8)
            .write(to: GOGDL.log(for: "1453375253"))
        let later = GOGStore()
        let afterDownload = await later.library()
        let stardewNow = afterDownload.first { $0.gameID == .gog("1453375253") }
        check(stardewNow?.install == .installed && stardewNow?.platform == .mac && stardewNow?.installDir == stardewApp,
              "the finished download is on the Mac, as its Mac version: \(String(describing: stardewNow?.install))")
        check(stardewNow?.sizeOnDisk == 900 && stardewNow?.pendingUpdate == nil, "with its size, and up to date")
        check(!fm.fileExists(atPath: GOGDL.log(for: "1453375253").path), "its log is gone")

        // A download that failed while Nightforge was away: said once, and out of the line.
        try? JSONEncoder().encode([GOGJob(id: "1999", platform: .windows)]).write(to: gogFolder.appendingPathComponent("downloads.json"))
        try? Data("[V2] ERROR: Failed to get secure link\n\(GOGDL.endMark)1\n".utf8).write(to: GOGDL.log(for: "1999"))
        let third = GOGStore()
        var failed: [String] = []
        third.downloadFailed = { name, reason in failed.append("\(name): \(reason)") }
        _ = await third.library()
        check(failed == ["1999: Failed to get secure link"], "a stopped download says why: \(failed)")
        check(!fm.fileExists(atPath: GOGDL.log(for: "1999").path), "once: its log goes, so a new try isn't taken for this one")
        let kept = (try? String(contentsOf: GOGDL.failedLog(for: "1999"), encoding: .utf8)) ?? ""
        check(GOGDL.failureLines(inLog: kept) == ["[V2] ERROR: Failed to get secure link", "\(GOGDL.endMark)1"],
              "but it's kept as 1999.failed.log for a problem report: \(GOGDL.failureLines(inLog: kept))")
        _ = await third.library()
        check(failed.count == 1, "and it isn't said again")

        // Uninstalling: the folder goes, the game stays in the library.
        if let stardewNow { try? await later.uninstall(stardewNow) }
        check(!fm.fileExists(atPath: stardewApp.path), "uninstalled: the app is gone")
        let afterUninstall = await later.library().first { $0.gameID == .gog("1453375253") }
        check(afterUninstall?.install == .notInstalled, "and the game is back to download")
        check(afterUninstall?.hasFolder == false && stardewNow?.hasFolder == true, "no \"Show game folder in Finder\" once its folder is gone")
        let outside = fm.temporaryDirectory.appendingPathComponent("gog-keep-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        var stray = game(.gog("424242"), "Stray")
        stray = Game(gameID: stray.gameID, name: stray.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot, steamExeWindowsPath: "",
                     installDir: outside, sizeOnDisk: 0)
        try? await later.uninstall(stray)
        check(fm.fileExists(atPath: outside.path), "a folder outside GOG's games folders is never removed")
        // A folder that won't go (in use, no permission) is said, as for a Steam game; gogdl's files for it still go.
        let stuck = GOGDL.windowsGamesDir.appendingPathComponent("Stuck", isDirectory: true)
        let locked = stuck.appendingPathComponent("Saved", isDirectory: true)
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        fm.createFile(atPath: locked.appendingPathComponent("save.dat").path, contents: Data("mine".utf8))
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        try? fm.createDirectory(at: GOGDL.manifest(for: "515151").deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: GOGDL.manifest(for: "515151"))
        let stuckGame = Game(gameID: .gog("515151"), name: "Stuck", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                             steamExeWindowsPath: "", installDir: stuck, sizeOnDisk: 0)
        do {
            try await later.uninstall(stuckGame)
            check(false, "a folder that stays isn't taken for a removed game")
        } catch {
            check(fm.fileExists(atPath: locked.appendingPathComponent("save.dat").path), "the folder stayed, and that's said: \(error.localizedDescription)")
        }
        check(!fm.fileExists(atPath: GOGDL.manifest(for: "515151").path), "gogdl's manifest for it still goes")
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        do {
            try await later.uninstall(stuckGame)
            check(!fm.fileExists(atPath: stuck.path), "once it can go, it goes")
        } catch { check(false, "and without a word: \(error)") }
        // An installed game whose folder stays isn't forgotten: it stays installed, so it can be removed again (outside
        // review of 9c45b18). Once the folder can go, the game goes with it.
        let keptFolder = GOGDL.windowsGamesDir.appendingPathComponent("Kept", isDirectory: true)
        let keptLocked = keptFolder.appendingPathComponent("Saved", isDirectory: true)
        try? fm.createDirectory(at: keptLocked, withIntermediateDirectories: true)
        fm.createFile(atPath: keptLocked.appendingPathComponent("save.dat").path, contents: Data("mine".utf8))
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: keptLocked.path)
        let installsFile = gogFolder.appendingPathComponent("installed.json")
        func installed() -> [String: GOGInstall] {
            (try? JSONDecoder().decode([String: GOGInstall].self, from: Data(contentsOf: installsFile))) ?? [:]
        }
        var withKept = installed()
        withKept["626262"] = GOGInstall(id: "626262", path: keptFolder, platform: .windows, build: "1", language: "en-US", size: 1)
        try? JSONEncoder().encode(withKept).write(to: installsFile)
        try? Data("{}".utf8).write(to: GOGDL.manifest(for: "626262"))
        let keptGame = Game(gameID: .gog("626262"), name: "Kept", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                            steamExeWindowsPath: "", installDir: keptFolder, sizeOnDisk: 0)
        let afresh = GOGStore()
        do {
            try await afresh.uninstall(keptGame)
            check(false, "an installed game whose folder stays isn't taken for removed")
        } catch {
            check(installed()["626262"] != nil, "it stays installed, so it can be removed again: \(error.localizedDescription)")
            check(fm.fileExists(atPath: GOGDL.manifest(for: "626262").path), "with gogdl's manifest for the game that's still there")
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: keptLocked.path)
        do {
            try await afresh.uninstall(keptGame)
            check(!fm.fileExists(atPath: keptFolder.path) && installed()["626262"] == nil && !fm.fileExists(atPath: GOGDL.manifest(for: "626262").path),
                  "once it can go, the game goes with it")
        } catch { check(false, "and without a word: \(error)") }

        // GOG can't be asked: no tokens (signed out) – the games stay.
        await later.refresh()
        check(later.sync.state == .signedOut && later.sync.lastSuccess.map { abs($0.timeIntervalSince(threeDaysAgo)) < 1 } == true,
              "no tokens: signed out, the library from three days ago stays")
        check(await later.library().count == 2, "and nothing has gone from it")
        check(StoreSyncText.text(provider: .gog, sync: later.sync)?.contains("GOG") == true, "the library's banner says so")
    }

    @MainActor
    static func refresh() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: GOGDL.configDir, withIntermediateDirectories: true)
        try? Data(#"{"46899977096215655": {"access_token": "tok"}}"#.utf8).write(to: GOGDL.authFile)
        let store = GOGStore()

        // GOG out of reach: the games stay, and the store says since when they are.
        store.authenticate = { .offline }
        await store.refresh()
        check(store.sync.failed && store.sync.state == .failed(L10n.t("Couldn't reach GOG")), "GOG not reached")
        check(await store.library().count == 2, "the games from last time stay")

        // GOG answers: two pages of products, what each is, the newest build of what's on the Mac.
        store.authenticate = { .signedIn(token: "tok", user: "4815") }
        let answers: [String: String] = [
            "https://galaxy-library.gog.com/users/4815/releases": ownedPage1,
            "https://galaxy-library.gog.com/users/4815/releases?page_token=abc": ownedPage2,
            "https://gamesdb.gog.com/platforms/gog/external_releases/1453375253": stardew,
            "https://gamesdb.gog.com/platforms/gog/external_releases/1207664663": witcher,
            "https://gamesdb.gog.com/platforms/gog/external_releases/1207660413": heartsOfStone,
            "https://gamesdb.gog.com/platforms/gog/external_releases/1999999999": spam,
            "https://content-system.gog.com/products/1207664663/os/windows/builds?generation=2": #"{"items": [{"build_id": "1", "branch": null}]}"#,
        ]
        let asked = Asked()
        store.fetch = { url, token in
            await asked.add(url.absoluteString, token: token)
            guard let answer = answers[url.absoluteString] else { throw GOGFetchError.status(404) }
            return Data(answer.utf8)
        }
        await store.refresh()
        check(store.sync.state == .ok && store.sync.lastSuccess.map { Date().timeIntervalSince($0) < 60 } == true, "up to date now")
        check(store.catalog.games.map(\.title) == ["Stardew Valley", "The Witcher 3: Wild Hunt"], "the games: \(store.catalog.games.map(\.title))")
        check(await asked.tokens["https://galaxy-library.gog.com/users/4815/releases"] == "tok", "the library is asked with the account's token")
        check(await asked.tokens["https://content-system.gog.com/products/1207664663/os/windows/builds?generation=2"] == .some(nil),
              "GOG's builds without it")
        let witcher = await store.library().first { $0.gameID == .gog("1207664663") }
        check(witcher?.pendingUpdate == nil, "the installed build is the newest now: no update waiting")

        // A second look asks only for what's new.
        await asked.reset()
        await store.refresh()
        check(await asked.urls.filter { $0.contains("gamesdb") }.isEmpty, "products known from last time aren't asked again")
        // A week later: all of them again (GOG may have added a Mac version).
        var known = (try? JSONDecoder().decode(GOGReleases.self, from: Data(contentsOf: gogFolder.appendingPathComponent("releases.json")))) ?? GOGReleases()
        check(known.checked != nil && known.items.count == 5, "what each product is, kept (a 404 too): \(known.items.count)")
        known.checked = Date().addingTimeInterval(-8 * 86_400)
        try? JSONEncoder().encode(known).write(to: gogFolder.appendingPathComponent("releases.json"))
        await asked.reset()
        let weekLater = GOGStore()
        weekLater.authenticate = store.authenticate
        weekLater.fetch = store.fetch
        await weekLater.refresh()
        check(await asked.urls.filter { $0.contains("gamesdb") }.count == 5, "a week later every product is asked again")
        check(weekLater.catalog.games.count == 2 && weekLater.sync.state == .ok, "with the same library")
    }

    // MARK: - External drives

    @MainActor
    static func drives() async {
        let fm = FileManager.default
        let drive = URL(fileURLWithPath: "/Volumes/T7", isDirectory: true)
        let onDrive = DriveLibrary.gog(on: drive)
        check(onDrive.path == "/Volumes/T7/Nightforge Games/GOG Games", "GOG's games on a drive: Nightforge Games/GOG Games")
        check(GOGStore.gamesFolders(of: onDrive.appendingPathComponent("Game")).map(\.path).contains(onDrive.path)
              && GOGStore.gamesFolders(of: GOGDL.windowsGamesDir.appendingPathComponent("Game")).count == 2,
              "a game on a drive may be removed from that drive's GOG folder, one on the Mac only from the Mac's")
        let store = GOGStore()
        check(store.downloadArguments(GOGJob(id: "1207664663", platform: .windows, base: onDrive.path), folder: nil)
              .contains(onDrive.path), "Install on T7: gogdl downloads into the drive's GOG folder")
        let old = try? JSONDecoder().decode([GOGJob].self, from: Data(#"[{"id": "1", "platform": "windows", "update": false}]"#.utf8))
        check(old?.first?.base == nil && old?.first?.folder == GOGDL.windowsGamesDir, "a download from before drives goes to the Mac")

        // The game page's question, on the Mac and on a drive.
        var witcher = Game(gameID: .gog("1207664663"), name: "The Witcher 3", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                           steamExeWindowsPath: "", installDir: GOGDL.windowsGamesDir.appendingPathComponent("W"), sizeOnDisk: 2_000_000)
        check(witcher.uninstallMessage == L10n.t("This removes the game from your Mac and frees %@. It stays in your %@ library, so you can download it again any time. Saves in its cloud are kept.", Format.bytes(2_000_000), "GOG"),
              "uninstalling names GOG, not Steam: \(witcher.uninstallMessage)")
        witcher = Game(gameID: witcher.gameID, name: witcher.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                       steamExeWindowsPath: "", installDir: onDrive.appendingPathComponent("W"), sizeOnDisk: 2_000_000)
        check(witcher.uninstallMessage == L10n.t("This removes the game from %@ and frees %@ there. It stays in your %@ library, so you can download it again any time. Saves in its cloud are kept.", "T7", Format.bytes(2_000_000), "GOG"),
              "and the drive it's on: \(witcher.uninstallMessage)")
        check(!witcher.inNightforgeFolder, "a game on a drive stays when Nightforge is removed")

        // On a drive that's unplugged: still the player's, "Connect … to Play".
        let gone = "NightforgeGone-\(UUID().uuidString.prefix(8))"
        let goneFolder = URL(fileURLWithPath: "/Volumes/\(gone)/Nightforge Games/GOG Games/The Witcher 3 Wild Hunt GOTY", isDirectory: true)
        let installedFile = gogFolder.appendingPathComponent("installed.json")
        let before = try? Data(contentsOf: installedFile)
        defer { if let before { try? before.write(to: installedFile) } }
        try? JSONEncoder().encode(["1207664663": GOGInstall(id: "1207664663", path: goneFolder, platform: .windows, build: "1",
                                                            language: "en-US", size: 50_000)]).write(to: installedFile)
        let unplugged = await GOGStore().library().first { $0.gameID == .gog("1207664663") }
        check(unplugged?.install == .notInstalled && unplugged?.missingDrive == gone, "unplugged: not playable, and which drive to connect")
        check(unplugged?.installDir == goneFolder && unplugged?.pendingUpdate == nil, "its place is kept, nothing to update meanwhile")
        check(unplugged?.onUnpluggedDrive == true && unplugged?.sizeOnDisk == 50_000 && unplugged?.downloadSize == nil,
              "the game page says \"On <drive>\" with what it takes there, no download size")
        check(unplugged?.hasFolder == false, "and offers no folder to show")
        if let unplugged {
            check(ProblemReport.storeReference(unplugged) == "GOG 1207664663", "a problem report names store and ID, no Steam link with app ID 0")
        }

        // Moved: the record follows, the game plays from its new place.
        let moved = GOGStore()
        let here = GOGDL.windowsGamesDir.appendingPathComponent("The Witcher 3 Wild Hunt GOTY", isDirectory: true)
        if let unplugged { moved.recordMove(unplugged, to: here) }
        let back = await moved.library().first { $0.gameID == .gog("1207664663") }
        check(back?.install == .installed && back?.installDir == here && back?.missingDrive == nil, "after a move it's installed where it went")
        check(!fm.fileExists(atPath: goneFolder.path), "(the drive really isn't there)")

        // A drive that's gone: its games leave Nightforge's list with gogdl's manifest and the support files, the
        // Mac's stay (and so does everything in the Windows environment: saves).
        let installed = gogFolder.appendingPathComponent("installed.json"), wantedFile = gogFolder.appendingPathComponent("downloads.json")
        let macFolder = GOGDL.windowsGamesDir.appendingPathComponent("Mafia II", isDirectory: true)
        let driveBase = "/Volumes/\(gone)/Nightforge Games/GOG Games"
        func setUp() {
            try? JSONEncoder().encode([
                "111": GOGInstall(id: "111", path: URL(fileURLWithPath: driveBase + "/Gone One", isDirectory: true), platform: .windows,
                                  build: "1", language: "en-US", size: 5),
                "112": GOGInstall(id: "112", path: URL(fileURLWithPath: driveBase + "/Gone Two", isDirectory: true), platform: .mac,
                                  build: "1", language: "en-US", size: 5),
                "222": GOGInstall(id: "222", path: macFolder, platform: .windows, build: "1", language: "en-US", size: 5),
            ]).write(to: installed)
            try? JSONEncoder().encode([GOGJob(id: "333", platform: .windows, base: driveBase), GOGJob(id: "444", platform: .windows)]).write(to: wantedFile)
            for id in ["111", "112", "222"] {
                try? fm.createDirectory(at: GOGDL.manifest(for: id).deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data("m".utf8).write(to: GOGDL.manifest(for: id))
                try? fm.createDirectory(at: GOGDL.supportDir(for: id), withIntermediateDirectories: true)
                try? Data("s".utf8).write(to: GOGDL.supportDir(for: id).appendingPathComponent("setup.exe"))
            }
        }
        func ids() -> [String] {
            ((try? JSONDecoder().decode([String: GOGInstall].self, from: Data(contentsOf: installed))) ?? [:]).keys.sorted()
        }
        func jobs() -> [String] { ((try? JSONDecoder().decode([GOGJob].self, from: Data(contentsOf: wantedFile))) ?? []).map(\.id) }
        let save = macFolder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("users/save.dat")
        try? fm.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("save".utf8).write(to: save)

        setUp()
        check(GOGStore().forgetDrive(gone, only: "222") == 0 && ids() == ["111", "112", "222"], "a game that isn't on the drive isn't forgotten")
        check(GOGStore().forgetDrive(gone, only: "111") == 1, "one game forgotten")
        check(ids() == ["112", "222"], "Nightforge's list without it: \(ids())")
        check(!fm.fileExists(atPath: GOGDL.manifest(for: "111").path) && !fm.fileExists(atPath: GOGDL.supportDir(for: "111").path), "its manifest and support files go")
        check(fm.fileExists(atPath: GOGDL.manifest(for: "112").path) && fm.fileExists(atPath: GOGDL.supportDir(for: "112").path), "the other game's stay")
        check(jobs() == ["333", "444"], "downloads waiting are other games': \(jobs())")

        setUp()
        check(GOGStore().forgetDrive(gone) == 2, "the whole drive")
        check(ids() == ["222"], "only the Mac's game is left: \(ids())")
        check(jobs() == ["444"], "a download waiting for the drive is dropped, the one for the Mac stays: \(jobs())")
        check(fm.fileExists(atPath: GOGDL.manifest(for: "222").path) && fm.fileExists(atPath: GOGDL.supportDir(for: "222").appendingPathComponent("setup.exe").path),
              "the Mac game's manifest and support files stay")
        check((try? String(contentsOf: save, encoding: .utf8)) == "save" && fm.fileExists(atPath: macFolder.deletingLastPathComponent().path),
              "nothing in the Windows environment is touched, saves included")
        check(GOGStore().forgetDrive(gone) == 0, "nothing is left to forget")
        for id in ["111", "112", "222"] {
            try? fm.removeItem(at: GOGDL.manifest(for: id))
            try? fm.removeItem(at: GOGDL.supportDir(for: id))
        }
        try? fm.removeItem(at: wantedFile)
    }
}

extension GOGTest {
    /// The store between GOG's answers: how a refresh that doesn't get through says so, play time,
    /// what a start and the Windows parts' setup are given, and games on the Mac that aren't in the list.
    @MainActor
    static func playing() async {
        let fm = FileManager.default
        let store = GOGStore()
        store.authenticate = { .signedOut }
        await store.refresh()
        check(store.sync.state == .signedOut, "GOG ended the sign-in: signed out")
        store.authenticate = { .helperFailed }
        await store.refresh()
        check(store.sync.state == .failed(L10n.t("Nightforge's GOG helper didn't start")), "gogdl didn't run: says so")
        store.authenticate = { .signedIn(token: "tok", user: "4815") }
        store.fetch = { _, _ in throw GOGFetchError.status(503) }
        await store.refresh()
        check(store.sync.state == .failed(L10n.t("Couldn't reach GOG")) && store.catalog.games.count == 2,
              "GOG signed in but not answering: out of reach, the library stays")

        // Play time Nightforge counts itself, kept between starts.
        guard let witcher = await store.library().first(where: { $0.gameID == .gog("1207664663") }) else {
            return check(false, "The Witcher is in the library")
        }
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        store.recordStart(witcher, at: started)
        check(await store.library().first { $0.gameID == witcher.gameID }?.lastPlayed == started, "a start counts as played")
        store.recordSession(witcher, minutes: 42, endedAt: started.addingTimeInterval(3600))
        store.recordSession(witcher, minutes: -5, endedAt: started.addingTimeInterval(7200))
        let played = await GOGStore().library().first { $0.gameID == witcher.gameID }
        check(played?.playtimeMinutes == 42 && played?.lastPlayed == started.addingTimeInterval(7200),
              "sessions add up (a clock gone backwards adds nothing), and stay: \(played?.playtimeMinutes ?? -1)")

        // What a start and the Windows parts' setup are given.
        check(store.setupFacts(of: witcher)?.install.id == "1207664663" && store.setupFacts(of: witcher)?.install.platform == .windows,
              "the Windows version's install record for its setup")
        let stardew = Game(gameID: .gog("1453375253"), name: "Stardew Valley", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                           steamExeWindowsPath: "", installDir: GOGDL.macGamesDir.appendingPathComponent("Stardew Valley.app"), sizeOnDisk: 0)
        check(store.setupFacts(of: stardew) == nil, "nothing to set up for a game that isn't on the Mac")
        check(store.hasCloudSaves(witcher) == nil, "cloud saves unknown until they were synced")
        let bare = fm.temporaryDirectory.appendingPathComponent("gog-bare-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: bare, withIntermediateDirectories: true)
        let lost = Game(gameID: .gog("31337"), name: "Lost Game", bottle: Engine.bottle, steamRoot: Engine.steamRoot,
                        steamExeWindowsPath: "", installDir: bare, sizeOnDisk: 0)
        let missing = L10n.t("%@ is missing GOG's start information. Download it again.", "Lost Game")
        do { _ = try store.launchCommand(for: lost); check(false, "a game without GOG's info file can't start") } catch {
            check(error.localizedDescription == missing, "without GOG's info file it says what to do: \(error.localizedDescription)")
        }
        try? Data(#"{"name": "Lost Game", "playTasks": [{"isPrimary": true, "path": "game.exe"}]}"#.utf8)
            .write(to: bare.appendingPathComponent("goggame-31337.info"))
        do { _ = try store.launchCommand(for: lost); check(false, "a program that isn't there can't start") } catch {
            check(error.localizedDescription == missing, "nor when the program it names is gone")
        }
        try? fm.removeItem(at: bare)

        // On the Mac but not in the list here: by the name in its info file, else its folder's.
        let installedFile = gogFolder.appendingPathComponent("installed.json")
        let before = try? Data(contentsOf: installedFile)
        let named = GOGDL.windowsGamesDir.appendingPathComponent("Lone", isDirectory: true)
        let unnamed = GOGDL.windowsGamesDir.appendingPathComponent("Nameless Folder", isDirectory: true)
        try? fm.createDirectory(at: named, withIntermediateDirectories: true)
        try? fm.createDirectory(at: unnamed, withIntermediateDirectories: true)
        try? Data(#"{"name": "Lone Wolf", "playTasks": [{"isPrimary": true, "path": "lone.exe"}]}"#.utf8)
            .write(to: named.appendingPathComponent("goggame-777.info"))
        var installs = (before.flatMap { try? JSONDecoder().decode([String: GOGInstall].self, from: $0) }) ?? [:]
        installs["777"] = GOGInstall(id: "777", path: named, platform: .windows, build: "1", language: "en-US", size: 10)
        installs["778"] = GOGInstall(id: "778", path: unnamed, platform: .windows, build: "1", language: "en-US", size: 10)
        try? JSONEncoder().encode(installs).write(to: installedFile)
        let extra = await GOGStore().library()
        check(extra.first { $0.gameID == .gog("777") }?.name == "Lone Wolf" && extra.first { $0.gameID == .gog("778") }?.name == "Nameless Folder",
              "installed games outside the list keep a name: \(extra.map(\.name))")
        check(extra.first { $0.gameID == .gog("777") }?.install == .installed, "and stay playable")
        if let before { try? before.write(to: installedFile) }
        try? fm.removeItem(at: named)
        try? fm.removeItem(at: unnamed)

        // What a failed sign-in leaves for a problem report: gogdl's log without the secrets.
        let output = Legendary.Output(status: 255, output: Data(), log: "[AUTH] ERROR: code sekret123 refused\n")
        GOGDL.writeAuthLog(output, command: "auth --code", hiding: ["sekret123"])
        let written = (try? String(contentsOf: GOGDL.authLog, encoding: .utf8)) ?? ""
        check(written.contains("gogdl auth --code ended with 255") && written.contains("[AUTH] ERROR") && !written.contains("sekret123"),
              "the sign-in's log is kept, the code left out: \(written)")

        let messages = [GOGError.unavailable, .signInFailed, .helperFailed, .failed("disk full")].map(\.errorDescription)
        check(Set(messages.compactMap { $0 }).count == 4 && messages[3] == "disk full", "every failure says what happened")
        let needs = GOGRedist.Needs(dependencies: ["MSVC2017"], scriptInterpreter: true, products: [("1", "setup.exe")], build: "5")
        var other = needs
        other.products = [("1", "other.exe")]
        check(needs == GOGRedist.Needs(dependencies: ["MSVC2017"], scriptInterpreter: true, products: [("1", "setup.exe")], build: "5")
              && needs != other, "a build's needs compare by their products' installers too")
    }
}

/// What the store asked GOG for, with which token.
actor Asked {
    var urls: [String] = []
    var tokens: [String: String?] = [:]

    func add(_ url: String, token: String?) {
        urls.append(url)
        tokens[url] = token
    }

    func reset() {
        urls = []
        tokens = [:]
    }
}
