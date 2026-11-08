import AppKit
import Foundation

@MainActor var failures = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        print("✗ \(message)")
    }
}

@MainActor func clean() {
    try? FileManager.default.removeItem(at: ModelWorld.steamapps)
    try? FileManager.default.createDirectory(at: ModelWorld.steamapps, withIntermediateDirectories: true)
    for key in UserDefaults.standard.dictionaryRepresentation().keys { UserDefaults.standard.removeObject(forKey: key) }
    Toasts.shared.dismiss()
}

@MainActor func game(_ model: LibraryModel, _ name: String) -> Game? { model.allGames.first { $0.name == name } }

@MainActor func downloads() async {
    clean()
    let model = LibraryModel()
    ModelWorld.steamGame(10, "Finished Soon", flags: 1026, size: 1000, toDownload: 1000, downloaded: 500)
    ModelWorld.steamGame(11, "Second One", flags: 1026, size: 1000, toDownload: 1000, downloaded: 100)
    ModelWorld.steamGame(12, "Installed", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    check(model.downloads.map(\.name).sorted() == ["Finished Soon", "Second One"], "what downloads is listed: \(model.downloads.map(\.name))")
    if case .downloading(let fraction?)? = game(model, "Finished Soon")?.install {
        check(abs(fraction - 0.5) < 0.001, "its progress: \(fraction)")
    } else {
        check(false, "a game on its way shows as downloading: \(String(describing: game(model, "Finished Soon")?.install))")
    }
    check(model.canUninstall(game(model, "Finished Soon")!), "a download can be cancelled")
    model.showingDownloads = true

    // One done: the panel stays for the other, the player hears of it.
    ModelWorld.steamGame(10, "Finished Soon")
    await ModelWorld.scan(model)
    check(model.downloads.map(\.name) == ["Second One"], "the finished one leaves the list")
    check(model.showingDownloads, "the panel stays while another downloads")
    check(Toasts.shared.current?.message.contains("Finished Soon") == true, "the finished game is announced: \(String(describing: Toasts.shared.current?.message))")
    check(Toasts.shared.current?.action != nil, "with a Play button")

    // A later scan says nothing new.
    Toasts.shared.dismiss()
    await ModelWorld.scan(model)
    check(Toasts.shared.current == nil, "announced once")

    // The last one: the panel goes with it.
    ModelWorld.steamGame(11, "Second One")
    await ModelWorld.scan(model)
    check(model.downloads.isEmpty && !model.showingDownloads, "the panel goes with the last download")

    // Two at once are one message.
    ModelWorld.steamGame(20, "One", flags: 1026, size: 1000, toDownload: 1000, downloaded: 1)
    ModelWorld.steamGame(21, "Two", flags: 1026, size: 1000, toDownload: 1000, downloaded: 1)
    await ModelWorld.scan(model)
    ModelWorld.steamGame(20, "One")
    ModelWorld.steamGame(21, "Two")
    Toasts.shared.dismiss()
    await ModelWorld.scan(model)
    check(Toasts.shared.current?.message.contains("2") == true, "two finished: a count: \(String(describing: Toasts.shared.current?.message))")

    // Cancelled from Steam: it just goes, no message that it's ready.
    ModelWorld.steamGame(30, "Cancelled", flags: 1026, size: 1000, toDownload: 1000, downloaded: 1)
    await ModelWorld.scan(model)
    ModelWorld.removeSteamGame(30, "Cancelled")
    Toasts.shared.dismiss()
    await ModelWorld.scan(model)
    check(Toasts.shared.current == nil, "a cancelled download isn't announced as ready")
    check(game(model, "Cancelled") == nil, "and is gone")
}

@MainActor func staysOnItsGame() async {
    clean()
    let model = LibraryModel()
    ModelWorld.steamGame(40, "Alpha", lastPlayed: 1_700_000_300)
    ModelWorld.steamGame(41, "Beta", lastPlayed: 1_700_000_200)
    ModelWorld.steamGame(42, "Gamma", lastPlayed: 1_700_000_100)
    await ModelWorld.scan(model)
    model.goLibrary()
    model.filters.sort = .recent
    guard let index = model.games.firstIndex(where: { $0.name == "Gamma" }) else { return check(false, "Gamma is shown") }
    model.select(index)
    model.openDetail()
    guard case .detail = model.route else { return check(false, "its page opens") }

    // Another game was just played: the order changes under the page.
    ModelWorld.steamGame(42, "Gamma", lastPlayed: 1_700_000_100)
    ModelWorld.steamGame(41, "Beta", lastPlayed: 1_700_000_900)
    await ModelWorld.scan(model)
    check(model.selected?.name == "Gamma", "the page stays on its game when the order changes: \(String(describing: model.selected?.name))")
    check(model.route.isDetail, "and stays open")
    model.back()
    check(model.route == .library && model.selected?.name == "Gamma", "back in the library on the same game")
    check(model.forwardTarget?.isDetail == true, "forward leads to the page again")
    model.forward()
    check(model.route.isDetail && model.selected?.name == "Gamma", "forward reopens its page")

    // The game goes while its page is open.
    ModelWorld.removeSteamGame(42, "Gamma")
    await ModelWorld.scan(model)
    check(model.route == .library, "its game gone, the page leaves to where it came from: \(model.route)")
    check(model.selected != nil, "with something selected")
    check(model.forwardTarget == nil, "and nothing to go forward to")

    // From Home.
    model.goHome()
    model.selectOnHome(place: 0)
    let first = model.selected
    model.openDetail()
    check(model.route == .detail(gameID: first?.id ?? "", from: .home), "a page opened from Home says so")
    model.back()
    check(model.route == .home && model.selected?.id == first?.id, "and goes back there")

    // The search: Home opens the library for it, and comes back without it.
    model.searchText = "bet"
    check(model.route == .library && model.games.map(\.name) == ["Beta"], "a search shows in the library: \(model.games.map(\.name))")
    check(model.backTarget == nil, "back first drops the search")
    model.back()
    check(model.searchText.isEmpty && model.route == .library, "and stays in the library")
    model.back()
    check(model.route == .home, "then Home")

    // A search that finds nothing, then a detail isn't reachable.
    model.searchText = "zzzz"
    check(model.games.isEmpty && model.selected == nil, "nothing found, nothing selected")
    model.openDetail()
    check(model.route == .library, "no page without a game")
    model.searchText = ""
}

@MainActor func marks() async {
    clean()
    let model = LibraryModel()
    ModelWorld.steamGame(50, "Marked", lastPlayed: 1_700_000_500)
    ModelWorld.steamGame(51, "Other", lastPlayed: 1_700_000_400)
    await ModelWorld.scan(model)
    let marked = game(model, "Marked")!

    model.togglePinned(marked)
    check(model.isPinned(marked), "pinned")
    model.toggleHidden(marked)
    check(model.isHidden(marked) && !model.isPinned(marked), "hiding takes the pin away")
    check(!model.games.contains { $0.id == marked.id }, "and out of what's shown")
    // Undo.
    Toasts.shared.current?.action?.run()
    check(!model.isHidden(marked) && model.isPinned(marked), "Undo brings the game and its pin back")

    // Hidden, the list of hidden games shows it; the last one brought back closes the list.
    model.toggleHidden(marked)
    model.goLibrary()
    model.toggleShowingHidden()
    check(model.showingHidden && model.games.map(\.name) == ["Marked"], "the hidden list: \(model.games.map(\.name))")
    model.toggleHidden(model.games[0])
    check(!model.showingHidden && !model.hiddenGames.contains(marked.gameID), "the last one back closes it")

    // Off Home until played; a pin brings it back.
    model.goHome()
    await ModelWorld.scan(model)
    let onHome = game(model, "Marked")!
    check(model.isOnHome(onHome), "on Home to begin with")
    model.removeFromHome(onHome)
    check(!model.isOnHome(onHome), "off Home")
    check(model.games.contains { $0.id == onHome.id }, "the collection keeps it")
    Toasts.shared.current?.action?.run()
    check(model.isOnHome(onHome), "Undo puts it back")
    model.removeFromHome(onHome)
    model.togglePinned(onHome)
    check(model.isOnHome(onHome) && model.offHome.isEmpty, "a pin brings it back: \(model.offHome)")

    // Play Later: the list's last game gone, the library is back.
    model.goLibrary()
    model.toggleLater(onHome)
    check(model.isLater(onHome) && model.laterCount == 1, "on the list")
    model.filters.later = true
    check(model.games.map(\.name) == ["Marked"], "the list shows it")
    model.toggleLater(onHome)
    check(!model.filters.later && model.games.count == 2, "its last game gone, the whole library")

    // They stay.
    model.toggleHidden(game(model, "Other")!)
    let later = LibraryModel()
    await ModelWorld.scan(later)
    check(later.isPinned(game(later, "Marked")!), "a pin is there at the next start")
    check(later.isHidden(game(later, "Other")!), "as is what's hidden")
    check(!later.games.contains { $0.name == "Other" }, "and it's not shown")
}

@MainActor func twoStores() async {
    clean()
    ModelWorld.gogLibrary([("1207658924", "Twin Game"), ("1207658925", "Only On GOG")])
    let model = LibraryModel()
    ModelWorld.steamGame(60, "Twin Game", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    check(model.allGames.filter { $0.name == "Twin Game" }.count == 2, "each store's entry: \(model.allGames.map(\.name))")
    let cards = model.cards.filter { $0.name == "Twin Game" }
    check(cards.count == 1, "one card")
    guard let card = cards.first else { return }
    check(card.provider == .steam && card.isInstalled, "the card is the copy on the Mac: \(card.provider)")
    check(card.providers.contains(.gog) && card.providers.contains(.steam), "it knows both stores")
    check(model.visibleCount == 2, "counted once: \(model.visibleCount)")

    // A mark holds for both stores.
    model.toggleHidden(card)
    check(model.isHidden(model.allGames.first { $0.name == "Twin Game" && $0.provider == .gog }!), "hidden in every store")
    Toasts.shared.current?.action?.run()

    // Pick the store: the page stays on the card.
    model.goLibrary()
    guard let index = model.games.firstIndex(where: { $0.name == "Twin Game" }) else { return check(false, "the card is shown") }
    model.select(index)
    model.openDetail()
    model.chooseStore(.gog, for: card)
    check(model.selected?.provider == .gog, "the store picked: \(String(describing: model.selected?.provider))")
    check(model.route.isDetail && model.selected?.name == "Twin Game", "the page stays on its card")
    // Picked store isn't installed; a store it doesn't have can't be picked.
    model.chooseStore(.epic, for: model.selected!)
    check(model.selected?.provider == .gog, "a store it isn't in")

    // A game on GOG only downloads through GOG, whose sign-in has run out here: nothing starts, the store's asked for.
    check(!model.canUninstall(game(model, "Only On GOG")!), "nothing to remove of a game that isn't on the Mac")
}

@MainActor func rules() async {
    clean()
    let model = LibraryModel()
    ModelWorld.steamGame(70, "Safe", lastPlayed: 1_700_000_000)
    ModelWorld.steamGame(71, "Folder Gone")
    await ModelWorld.scan(model)
    let safe = game(model, "Safe")!

    check(model.canMove(safe), "an installed game can move")
    check(model.canUninstall(safe), "and go")
    check(model.canForgetDrive, "nothing's going on")

    // A game moving: what Steam would be stopped for has to wait, and nothing else moves or goes.
    let progress = CopyProgress()
    model.move = GameMove(game: safe, drive: "T7", progress: progress)
    check(model.waitsForMove(safe), "the moving game waits")
    check(model.waitsForMove(game(model, "Folder Gone")!), "another game of the same Steam too: Steam is closed")
    check(!model.canMove(game(model, "Folder Gone")!), "one move at a time")
    check(!model.canUninstall(safe), "no uninstall meanwhile")
    check(!model.canForgetDrive, "no drive forgotten meanwhile")
    model.cancelMove()
    check(progress.cancelled, "Cancel reaches the copy")
    model.move?.phase = .finishing
    let again = CopyProgress()
    model.move = GameMove(game: safe, drive: "T7", phase: .finishing, progress: again)
    model.cancelMove()
    check(!again.cancelled, "once the store has been told, it can't be called off")
    model.move = nil

    // The folder is gone behind Steam's back.
    try? FileManager.default.removeItem(at: game(model, "Folder Gone")!.installDir)
    check(!model.canMove(game(model, "Folder Gone")!), "no move without its folder")

    // Questions: the same way out from each.
    model.requestUninstall(safe)
    check(model.pendingUninstall?.id == safe.id, "the question is asked")
    model.closeAllSheets()
    check(model.pendingUninstall == nil, "and closes with the rest")
    model.answerSaveChoice(takeNewer: true)  // no question open: nothing happens
    check(model.saveChoice == nil, "an answer without a question")
    model.showingSettings = true
    model.openLaunchers()
    check(!model.showingSettings && model.route == .launchers, "the launchers come out of Settings")
    model.goHome()

    // Nothing a Play can do while the sheet is gone: the state a start leaves.
    check(model.launchHint == nil && !model.gameOnScreen, "no start under way")
}

@MainActor func unpluggedAndFull() async {
    clean()
    let model = LibraryModel()
    // A library on a drive that isn't plugged in, knowing one game.
    let list = """
    "libraryfolders"
    {
    \t"0"
    \t{
    \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
    \t\t"apps" { }
    \t}
    \t"1"
    \t{
    \t\t"path"\t\t"/Volumes/NightforgeNoSuchDrive/SteamLibrary"
    \t\t"apps"
    \t\t{
    \t\t\t"80"\t\t"1000"
    \t\t}
    \t}
    }

    """
    try? list.write(to: ModelWorld.steamapps.appendingPathComponent("libraryfolders.vdf"), atomically: true, encoding: .utf8)
    ModelWorld.steamGame(81, "Here", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    check(game(model, "Here") != nil, "the games on the Mac are read with a drive missing")

    // Steam stopped the download for lack of room, and there's enough now.
    let disk = LibraryModel.freeSpace(at: ModelWorld.steamapps)
    ModelWorld.steamGame(82, "Paused For Room", flags: 1026 | 512, size: 4096, toDownload: 4096, downloaded: 1, updateResult: 12)
    // A library's first download: Steam stopped before it made any folder for it.
    try? FileManager.default.removeItem(at: ModelWorld.steamapps.appendingPathComponent("common"))
    await ModelWorld.scan(model)
    guard let paused = game(model, "Paused For Room") else { return check(false, "the paused download is listed") }
    if let needed = paused.downloadNeedsSpace {
        check(needed > 0 && needed <= disk, "it says what it needs: \(needed)")
        model.goLibrary()
        guard let index = model.games.firstIndex(where: { $0.id == paused.id }) else { return check(false, "it's shown") }
        model.select(index)
        model.primaryAction()  // resumes: there's room
        let manifest = (try? String(contentsOf: ModelWorld.steamapps.appendingPathComponent("appmanifest_82.acf"), encoding: .utf8)) ?? ""
        check(manifest.contains("\"StateFlags\"\t\t\"1026\""), "unpaused in Steam's manifest")
        check(manifest.contains("\"UpdateResult\"\t\t\"0\""), "with the error gone")
        check(model.errorMessage == nil, "without a word: \(String(describing: model.errorMessage))")
    } else {
        check(false, "a download Steam stopped for room says so: \(paused.install)")
    }
    await ModelWorld.settle(100)
}

@MainActor func gogGames() async {
    clean()
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
    let big: Int64 = 400_000_000_000_000  // more than any Mac has
    let onDrive = URL(fileURLWithPath: "/Volumes/NightforgeNoSuchDrive/Nightforge Games/GOG/Far Away", isDirectory: true)
    ModelWorld.gogLibrary([("1207700001", "Enormous"), ("1207700002", "Far Away")])
    try? FileManager.default.createDirectory(at: GOGDL.configDir, withIntermediateDirectories: true)
    try? Data("{}".utf8).write(to: GOGDL.authFile)  // signed in
    let sizes = ["1207700001.windows": GOGSize(build: "1", download: big, install: big, language: "en-US", folder: "Enormous")]
    try? JSONEncoder().encode(sizes).write(to: ModelWorld.gogFolder.appendingPathComponent("sizes.json"))
    let installs = ["1207700002": GOGInstall(id: "1207700002", path: onDrive, platform: .windows, build: "1", language: "en-US", size: 1000)]
    try? JSONEncoder().encode(installs).write(to: ModelWorld.gogFolder.appendingPathComponent("installed.json"))

    let model = LibraryModel()
    ModelWorld.steamGame(90, "Removable", size: 5_000_000)
    await ModelWorld.scan(model)
    model.goLibrary()

    func open(_ name: String) -> Game? {
        guard let index = model.games.firstIndex(where: { $0.name == name }) else { check(false, "\(name) is shown: \(model.games.map(\.name))"); return nil }
        model.select(index)
        return model.games[index]
    }

    // A game that doesn't fit: nothing starts, the player picks what makes room.
    guard open("Enormous") != nil else { return }
    model.primaryAction()
    await ModelWorld.settle(50)
    guard let request = model.pendingSpace else { return check(false, "a game that doesn't fit asks first") }
    check(request.game.name == "Enormous" && request.needed == big && request.shortfall > 0, "it says how much: \(request.needed), \(request.shortfall)")
    check(!model.gog.isBusy, "and nothing downloads")
    check(request.candidates.allSatisfy { model.canUninstall($0) }, "only what can go is offered")
    // No game picked: it still doesn't fit, and says so with both sizes.
    model.freeUpAndDownload([])
    check(model.pendingSpace == nil, "the sheet closes")
    for _ in 0..<80 where model.errorMessage == nil { await ModelWorld.settle(25) }
    check(model.errorMessage?.contains("Enormous") == true, "it says it's still too little: \(String(describing: model.errorMessage))")
    check(!model.gog.isBusy, "and still nothing downloads")
    model.errorMessage = nil

    // Unplugged: "Connect … to Play", never a second copy.
    guard let away = open("Far Away") else { return }
    check(away.missingDrive == "NightforgeNoSuchDrive" && away.install == .notInstalled, "a game on an unplugged drive says which: \(String(describing: away.missingDrive)) \(away.install)")
    check(!model.canUninstall(away) && !model.canMove(away), "it can't be removed or moved from here")
    model.primaryAction()
    await ModelWorld.settle(50)
    check(model.pendingSpace == nil && !model.gog.isBusy, "Download doesn't start beside the copy on the drive")

    // A move that can't start says why, and nothing changes.
    let removable = model.allGames.first { $0.name == "Removable" }!
    let tooBig = MoveTarget(choice: nil, macFree: 0, needed: big)
    model.startMove(removable, to: tooBig)
    check(model.move == nil && model.errorMessage != nil, "not enough room on the Mac: said, and no move: \(String(describing: model.errorMessage))")
    model.errorMessage = nil
    let gone = ExternalDrive(name: "Gone", url: URL(fileURLWithPath: "/Volumes/NightforgeNoSuchDrive"), format: "apfs", readOnly: false, free: big, total: big)
    model.startMove(removable, to: MoveTarget(choice: DriveChoice(drive: gone, needed: 1)))
    check(model.move == nil && model.errorMessage?.contains("Gone") == true, "a drive gone meanwhile: said: \(String(describing: model.errorMessage))")
    model.errorMessage = nil
    model.download(SpaceRequest(game: removable, needed: 1, free: 0, shortfall: 1, candidates: [], drives: [], committed: 0, margin: 0), on: DriveChoice(drive: gone, needed: 1))
    check(model.pendingSpace == nil && model.errorMessage?.contains("Gone") == true, "a download onto a drive gone meanwhile: \(String(describing: model.errorMessage))")
    model.errorMessage = nil

    // A drive forgotten: its games count as not on the Mac and can come down again.
    let forgotten = await model.forgetDrive("NightforgeNoSuchDrive", only: away)
    check(forgotten, "the drive is forgotten: \(String(describing: model.errorMessage))")
    await ModelWorld.scan(model)
    let fresh = model.allGames.first { $0.name == "Far Away" }
    check(fresh?.missingDrive == nil && fresh?.install == .notInstalled, "and the game can be downloaded: \(String(describing: fresh?.missingDrive))")
    let record = (try? Data(contentsOf: ModelWorld.gogFolder.appendingPathComponent("installed.json"))) ?? Data()
    check(!String(decoding: record, as: UTF8.self).contains("1207700002"), "its record goes")
    try? FileManager.default.removeItem(at: GOGDL.authFile)
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
}

/// A manifest whose sizes are nonsense (a bad write, a damaged disk): whatever adds sizes up goes on working. Every
/// download press adds up what the others still need, and Settings › Storage adds up all games.
@MainActor func hugeSizes() async {
    clean()
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
    ModelWorld.gogLibrary([("1207700005", "Sane GOG Game")])
    try? FileManager.default.createDirectory(at: GOGDL.configDir, withIntermediateDirectories: true)
    try? Data("{}".utf8).write(to: GOGDL.authFile)
    let sizes = ["1207700005.windows": GOGSize(build: "1", download: 400_000_000_000_000, install: 400_000_000_000_000, language: "en-US", folder: "Sane")]
    try? JSONEncoder().encode(sizes).write(to: ModelWorld.gogFolder.appendingPathComponent("sizes.json"))
    let model = LibraryModel()
    func damaged(_ appID: Int, _ name: String, _ size: String, downloading: Bool) {
        let dir = ModelWorld.steamapps.appendingPathComponent("common/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = """
        "AppState"
        {
        \t"appid"\t\t"\(appID)"
        \t"name"\t\t"\(name)"
        \t"StateFlags"\t\t"\(downloading ? 1026 : 4)"
        \t"installdir"\t\t"\(name)"
        \t"SizeOnDisk"\t\t"\(size)"
        \t"BytesToDownload"\t\t"\(downloading ? size : "0")"
        \t"BytesDownloaded"\t\t"0"
        }

        """
        try? text.write(to: ModelWorld.steamapps.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
    }
    damaged(100, "Huge One", "9223372036854775807", downloading: false)
    damaged(101, "Huge Two", "9223372036854775000", downloading: false)
    damaged(102, "Huge Down", "9223372036854775807", downloading: true)
    damaged(103, "Huge Exp", "1e300", downloading: true)
    damaged(104, "Below Zero", "-5", downloading: false)
    await ModelWorld.scan(model)
    check(model.allGames.count >= 5, "the damaged ones are listed: \(model.allGames.map(\.name))")
    let total = model.allGames.reduce(Int64(0)) { $0 + $1.sizeOnDisk }  // what Settings › Storage does
    check(total > 0, "adding every game up")
    check(model.allGames.allSatisfy { $0.sizeOnDisk >= 0 }, "no size below zero: \(model.allGames.map(\.sizeOnDisk))")
    for game in model.allGames { _ = SpaceCheck.remaining(game) }
    _ = SpaceCheck.committed(by: model.allGames, except: model.allGames[0]) { _ in true }

    model.goLibrary()
    guard let index = model.games.firstIndex(where: { $0.name == "Sane GOG Game" }) else { return check(false, "the sane game is shown") }
    model.select(index)
    model.primaryAction()
    await ModelWorld.settle(50)
    check(model.pendingSpace != nil, "Download still asks: \(String(describing: model.errorMessage))")
    if let request = model.pendingSpace {
        _ = SpaceCheck.preselect(request.candidates, shortfall: request.shortfall)
        _ = request.required
    }
    model.closeAllSheets()
    check(!Format.bytes(total).isEmpty, "and they can be shown")
    try? FileManager.default.removeItem(at: GOGDL.authFile)
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
}

/// Removing a game for good, the keys on each level, and "Download Again" for a game on a drive that's gone.
@MainActor func removingAndKeys() async {
    clean()
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
    let folder = GOGDL.windowsGamesDir.appendingPathComponent("On The Mac", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? Data("game".utf8).write(to: folder.appendingPathComponent("game.exe"))
    ModelWorld.gogLibrary([("1207700010", "On The Mac"), ("1207700011", "Enormous Later")])
    try? FileManager.default.createDirectory(at: GOGDL.configDir, withIntermediateDirectories: true)
    try? Data("{}".utf8).write(to: GOGDL.authFile)
    let big: Int64 = 400_000_000_000_000
    let sizes = ["1207700011.windows": GOGSize(build: "1", download: big, install: big, language: "en-US", folder: "Enormous Later")]
    try? JSONEncoder().encode(sizes).write(to: ModelWorld.gogFolder.appendingPathComponent("sizes.json"))
    let drive = URL(fileURLWithPath: "/Volumes/NightforgeNoSuchDrive/Nightforge Games/GOG/Enormous Later", isDirectory: true)
    let installs = ["1207700010": GOGInstall(id: "1207700010", path: folder, platform: .windows, build: "1", language: "en-US", size: 1000),
                    "1207700011": GOGInstall(id: "1207700011", path: drive, platform: .windows, build: "1", language: "en-US", size: big)]
    try? JSONEncoder().encode(installs).write(to: ModelWorld.gogFolder.appendingPathComponent("installed.json"))

    let model = LibraryModel()
    ModelWorld.steamGame(110, "Next To It", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    guard let onMac = game(model, "On The Mac"), onMac.isInstalled else { return check(false, "the GOG game is on the Mac") }

    // The keys: the library's A opens the page, Home's last tile the library.
    model.goLibrary()
    model.activate()
    check(model.route.isDetail, "A in the library opens the game's page, it doesn't start it")
    model.back()
    model.goHome()
    model.selectOnHome(place: model.homeRail.count)
    check(model.homeOnAllGames && model.heroGame == nil, "the All games tile selects no game")
    model.openDetail()
    check(model.route == .home, "and has no page")
    model.activate()
    check(model.route == .library, "A on it opens the library")

    // Removing asks first, then the folder and the record go; the game stays in the account.
    model.requestUninstall(onMac)
    check(model.pendingUninstall?.id == onMac.id, "asked first")
    check(FileManager.default.fileExists(atPath: folder.path), "and nothing's gone yet")
    model.confirmUninstall()
    for _ in 0..<120 where FileManager.default.fileExists(atPath: folder.path) { await ModelWorld.settle(25) }
    await ModelWorld.settle(100)
    check(!FileManager.default.fileExists(atPath: folder.path), "the folder goes")
    check(model.uninstallingID == nil, "and it's over")
    await ModelWorld.scan(model)
    check(game(model, "On The Mac")?.install == .notInstalled, "still in the account, to download again: \(String(describing: game(model, "On The Mac")?.install))")
    check(model.errorMessage == nil, "without a word: \(String(describing: model.errorMessage))")

    // Download Again: forgotten on the drive, then asked like any download.
    guard let away = game(model, "Enormous Later"), away.onUnpluggedDrive else { return check(false, "the game on the drive that's gone") }
    model.redownload(away)
    for _ in 0..<200 where model.pendingSpace == nil { await ModelWorld.settle(25) }
    check(model.pendingSpace?.game.name == "Enormous Later", "Download Again ends in the same question as any download: \(String(describing: model.errorMessage))")
    model.closeAllSheets()
    try? FileManager.default.removeItem(at: GOGDL.authFile)
    try? FileManager.default.removeItem(at: ModelWorld.gogFolder)
}

/// The question about Apple's D3DMetal: left unanswered it takes back what it recorded, and says why the game doesn't start.
@MainActor func d3dMetalQuestion() async {
    clean()
    D3DMetalSupply.forget()
    let model = LibraryModel()
    ModelWorld.steamGame(120, "Needs DirectX 12", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    let game = game(model, "Needs DirectX 12")!
    Toasts.shared.dismiss()

    model.askAboutD3DMetal(for: game)
    check(model.d3dMetalDialog?.step == .choose && model.d3dMetalDialog?.game?.id == game.id, "the question is put for its game")
    check(model.d3dMetalDialog?.licenseAccepted == false, "with Apple's licence, the first time")
    model.askAboutD3DMetal(for: game)  // a second press
    let dialog = model.d3dMetalDialog?.id
    model.askAboutD3DMetal(for: game)
    check(model.d3dMetalDialog?.id == dialog, "one question at a time")

    // Answered, and it can't be set up here: it stays open and says so.
    model.downloadD3DMetal()
    check(D3DMetalSupply.choice()?.source == .nightforge, "the answer is recorded")
    for _ in 0..<400 {
        if case .failed? = model.d3dMetalDialog?.step { break }
        await ModelWorld.settle(25)
    }
    guard case .failed? = model.d3dMetalDialog?.step else { return check(false, "no network, no engine: it says so: \(String(describing: model.d3dMetalDialog?.step))") }

    // Closed like that: the answer goes again, the game says why it didn't start.
    model.d3dMetalDialog = nil
    model.d3dMetalDismissed()
    check(D3DMetalSupply.choice() == nil, "what it recorded is taken back")
    check(Toasts.shared.current?.message.contains("Needs DirectX 12") == true, "the player hears why: \(String(describing: Toasts.shared.current?.message))")
    Toasts.shared.dismiss()

    // A question only for what isn't there: asked for nothing, it closes without a word about a game.
    model.askAboutD3DMetal(for: nil)
    model.askToRemoveD3DMetal()
    check(model.d3dMetalDialog?.step == .confirmRemoval, "Remove asks once more")
    model.d3dMetalDialog = nil
    model.d3dMetalDismissed()
    check(Toasts.shared.current == nil, "from Settings no game is spoken of")
    await ModelWorld.settle(100)
}

/// Saves on their way to the cloud hold a switch of the Steams up, not longer than they have to.
@MainActor func savesBeforeSwitch() async {
    clean()
    let model = LibraryModel()
    ModelWorld.steamGame(95, "Saved", lastPlayed: 1_700_000_000)
    await ModelWorld.scan(model)
    let game = game(model, "Saved")!
    let record = Engine.steamRoot.appendingPathComponent("userdata/123/95/remotecache.vdf")
    try? FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
    func write(state: String) {
        try? "\"95\"\n{\n\t\"save.dat\"\n\t{\n\t\t\"syncstate\"\t\t\"\(state)\"\n\t}\n}\n".write(to: record, atomically: true, encoding: .utf8)
    }
    let steamSwitch = SteamSwitch()
    write(state: "2")
    var pending = await steamSwitch.savesPending(.windows)
    check(!pending, "nothing ended yet, nothing pending")

    steamSwitch.ended(game, at: Date())
    pending = await steamSwitch.savesPending(.windows)
    check(pending, "a game just ended and its file out of step: pending")
    pending = await steamSwitch.savesPending(.mac)
    check(!pending, "that's the Windows Steam's, not Steam for Mac's")
    pending = await steamSwitch.savesPending(.windows, now: Date().addingTimeInterval(SteamSwitch.backgroundPatience + 1))
    check(!pending, "not waited for past its patience")

    // The wait ends as soon as the cloud has it.
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(1200))
        write(state: "1")
    }
    let began = Date()
    var phases: [LaunchPhase] = []
    await steamSwitch.makeWayForMac(facts: SteamSwitch.Facts(), phase: { phases.append($0) })
    let waited = Date().timeIntervalSince(began)
    check(phases.contains(.savingToCloud), "the start says it waits for the cloud: \(phases)")
    check(waited >= 1 && waited < 8, "and goes on once it's up: \(waited) s")
    check(!steamSwitch.windowsStopped, "a Steam that doesn't run isn't stopped")

    // Another game's end doesn't reach Steam for Epic: only Steam's games have that wait.
    let bystander = SteamSwitch()
    let epic = Game(gameID: .epic("x"), name: "E", bottle: game.bottle, steamRoot: game.steamRoot, steamExeWindowsPath: "", installDir: game.installDir, sizeOnDisk: 0)
    bystander.ended(epic, at: Date())
    check(bystander.lastSession.isEmpty, "only Steam's games wait for Steam's cloud")
    await bystander.waitForSaves(.windows, limit: 5)  // returns at once
    try? FileManager.default.removeItem(at: record.deletingLastPathComponent())
}

/// Scans run one at a time: only the three places that keep to that may start one.
func scansInLine() {
    let source = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
    let starts = source.components(separatedBy: "await rescan()").count - 1
    MainActor.assumeIsolated {
        check(starts == 3, "await rescan() only from reload, a scan's own tail and scanInLine: \(starts)")
    }
}

@main struct Main {
    static func main() async {
        await ModelWorld.begin()
        await downloads()
        await staysOnItsGame()
        await marks()
        await twoStores()
        await rules()
        await unpluggedAndFull()
        await gogGames()
        await savesBeforeSwitch()
        await hugeSizes()
        await removingAndKeys()
        await d3dMetalQuestion()
        scansInLine()
        await MainActor.run {
            if failures == 0 { print("✓ The model's flows: downloads, marks, two stores, moves, questions") } else { print("✗ \(failures) failures") }
            exit(failures == 0 ? 0 : 1)
        }
    }
}
