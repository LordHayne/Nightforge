import AppKit

/// How a store's library stands: loaded, being loaded, or not reachable – and when the games shown
/// were last loaded, so a failure can say how old they are (they still play).
struct StoreSync: Equatable {
    enum State: Equatable {
        case ok
        case syncing
        /// Why the last try failed, in words for the player.
        case failed(String)
        /// The store ended the sign-in (it expired): signing in again brings the library up to date.
        case signedOut
    }

    var state = State.ok
    /// When the library was last loaded from the store; nil before the first time.
    var lastSuccess: Date?

    /// Not up to date and the player can do something about it (try again, sign in again).
    var failed: Bool {
        switch state {
        case .failed, .signedOut: return true
        case .ok, .syncing: return false
        }
    }
}

/// What a store's games need from the rest of Nightforge while it installs or removes one.
struct StoreContext {
    /// A game runs or starts right now: whatever would cut it off waits.
    var busy = false
    /// The store has taken the request: the library can show the download before the slow part
    /// (a restart, a first look at the files) is through.
    var requested: @MainActor () -> Void = {}
    /// The external drive to install on (/Volumes/<name>, DriveLibrary); nil: the Mac.
    var drive: URL?
}

/// How a game from another store starts under Wine, as its store hands it over (Epic through
/// legendary, GOG from the game's own info file): Nightforge starts it with its own engine.
struct StoreLaunchCommand: Equatable {
    var executable: URL
    var workingDirectory: URL
    var arguments: [String]
    var environment: [String: String]
}

/// One store Nightforge brings games in from (Steam, Epic Games, GOG, Battle.net). Its library comes
/// from the Mac first – as it was last loaded – and is brought up to date in the background; a store
/// that can't be reached keeps its games, which still play. Nightforge downloads, starts and removes
/// Epic's and GOG's games itself; Steam and Battle.net do that in their own clients.
@MainActor
protocol StoreProvider: AnyObject {
    var provider: Provider { get }
    /// Set up and signed in: its games belong in the library.
    var isConnected: Bool { get }
    /// How the last update of the library went.
    var sync: StoreSync { get }
    /// The games as they are on this Mac now: what was loaded last plus what's installed or
    /// downloading. No network – it answers at once, also offline.
    func library() async -> [Game]
    /// Asks the store for the library again, in the background; `sync` says how it went. A store
    /// that keeps its own catalog on the Mac (Steam) has nothing to do here.
    func refresh() async
    /// Starts fetching the game; its progress shows in `Game.install` from the next `library()`.
    func install(_ game: Game, context: StoreContext) async throws
    /// Removes the game from the Mac (or the download that's under way).
    func uninstall(_ game: Game) async throws
    /// What the store sells under `term`, signed in or not. Nothing when it can't be reached – or,
    /// like Epic's, can't be searched from here (`StoreHits.epicSearch`).
    func search(_ term: String) async -> [StoreHit]
}

extension StoreProvider {
    func refresh() async {}
    func search(_ term: String) async -> [StoreHit] { [] }
}

/// A store the player signs in to in the store's own page (Epic Games, GOG): Settings › Stores and
/// the sync banner show each the same way.
@MainActor
protocol AccountStore: StoreProvider, ObservableObject {
    /// The sign-in page is open.
    var connecting: Bool { get }
    /// The account's name, as the store shows it.
    var accountName: String? { get }
}

/// How the update before a start went ("Update & Play"), for stores Nightforge updates itself.
enum StoreUpdate: Equatable {
    /// Up to date now, or there was nothing to fetch.
    case updated
    /// Nothing was fetched, so the version on the Mac starts – as the stores' launchers do offline.
    case skipped(Skip)
    /// It stopped once it had begun, or there's no room for it: the game may be half updated, and
    /// the next try carries on where this one stopped.
    case failed(String)
    /// The game is up to date, one of its add-ons stopped (its name, the reason): the game starts
    /// without it, and the next update tries again.
    case addOnFailed(String, String)

    enum Skip: Equatable {
        /// The store out of reach (offline, no answer).
        case offline
        /// Another download of the store's is running, which can't share.
        case busy
    }
}

/// Steam: Nightforge's own Windows Steam (hidden, in its Wine prefix), CrossOver bottles and Steam
/// for Mac. Its library is read from Steam's files on the Mac, so it's always at hand; downloads are
/// requests to that Steam. Starting a game goes through Steam too, which `LibraryModel` follows in
/// Steam's log (`LaunchWatcher`) – it's woven into Steam's sign-in and restarts there.
@MainActor
final class SteamStore: StoreProvider {
    let provider = Provider.steam
    private(set) var sync = StoreSync()
    /// Nightforge's own Steam is set up, or another Steam has games.
    private(set) var isConnected = false

    func search(_ term: String) async -> [StoreHit] {
        await StoreSearch.shared.search(term).map(StoreHit.init)
    }

    func library() async -> [Game] {
        let root = Prefs.bottlesRoot
        let builtIn = Engine.isSteamInstalled ? [Engine.bottle] : []
        let preferWindows = await ProfileStore.shared.preferWindows()
        let blocks = await ProfileStore.shared.antiCheatBlocks()
        let found = await Task.detached(priority: .userInitiated) {
            // Libraries on drives that are unplugged, in Nightforge's Steam and in Steam for Mac.
            let drives = (builtIn.isEmpty ? [:] : LibraryScanner.missingDrives(steamRoot: Engine.steamRoot, bottle: Engine.bottle))
                .merging(LibraryScanner.missingDrives(steamRoot: MacSteam.root, bottle: MacSteam.bottle)) { windows, _ in windows }
            return LibraryScanner.markMissingDrives(LibraryScanner.markAntiCheat(
                LibraryScanner.merge(LibraryScanner.scan(bottlesRoot: root, extraBottles: builtIn),
                                     mac: LibraryScanner.scanMac(), preferWindows: preferWindows),
                blocks: blocks), drives: drives)
        }.value
        isConnected = !builtIn.isEmpty || !found.isEmpty
        sync = StoreSync(state: .ok, lastSuccess: Date())
        return found
    }

    /// A Windows game: asks Nightforge's Steam for it, which takes it up after a restart – right
    /// away, or once nothing runs (the restart would end the game). Mac versions go through Steam
    /// for Mac, whose setup `LibraryModel` leads (`downloadMac`).
    func install(_ game: Game, context: StoreContext) async throws {
        guard let wine = await Engine.installedWine() else { return }
        if let drive = context.drive { return try await install(game, onDrive: drive, wine: wine, context: context) }
        try Engine.requestDownload(appID: game.appID, name: game.name, installDir: game.installDirName)
        context.requested()
        if context.busy {
            restartWhenIdle = true
        } else {
            try await Engine.restartSteamInBackground(wine)
        }
    }

    /// A download Steam only picks up after a restart, which waits while a game runs: restarting
    /// Steam then would end the game too.
    var restartWhenIdle = false

    /// A demo or free game the account has no licence for yet: Steam adds the free licence when
    /// asked to install it (steam://install), in its own install window. True once the player
    /// confirmed there and Steam wrote its manifest (up to 5 min) – from then on it downloads like
    /// any game.
    func addDemoLicense(_ game: Game) async throws -> Bool {
        if game.platform == .mac {
            MacSteam.ask("install/\(game.appID)")
        } else {
            guard let wine = await Engine.installedWine() else { return false }
            try await Engine.startSteamOffMain(wine, arguments: ["steam://install/\(game.appID)"])
            await SteamWindow.bringForward()  // in front of Nightforge, once it's there
        }
        // A store hit has no folder of its own yet, so the library by the Steam that adds it.
        let steamapps = game.platform == .mac ? MacSteam.steamapps : game.steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        let manifest = steamapps.appendingPathComponent("appmanifest_\(game.appID).acf")
        for _ in 0..<150 {
            try? await Task.sleep(for: .seconds(2))
            if FileManager.default.fileExists(atPath: manifest.path) { return true }
        }
        return false
    }

    func uninstall(_ game: Game) async throws {
        if game.platform == .mac {
            try await MacSteam.uninstall(appID: game.appID, installDir: game.installDir)
            return
        }
        guard let wine = await Engine.installedWine() else { return }
        try await Engine.uninstall(appID: game.appID, installDir: game.installDir, wine: wine)
    }
}
