import AppKit
import Foundation

/// A Blizzard Mac game started the way Blizzard's client starts it: Nightforge asks the running,
/// signed-in client, and the client does the rest (its sign-in, its checks, the game). The game's
/// files, its arguments and Blizzard's anti-cheat are none of Nightforge's business.
///
/// The way in is the client's own `--exec` option ("Execute a command" in its option list, 2.53.8), given
/// to a second start of its program, which hands the command to the one already running. A client that
/// has only just started lets it go by, as Playnite, Lutris and bnetlauncher all found, so it has to be
/// through its start first. Nothing of this is documented by Blizzard (docs/TODO.md, Battle.net).
///
/// The client's logs are read for fixed lines only: the ones around them can hold the account's
/// mail address and country, and no line of them is kept or passed on.
enum BattleNetStart {
    // MARK: What is asked

    /// What the client is told to do. WoW's Classic variants have no start code of their own; the
    /// client also has `launch_uid`, which goes by the product's name in its list.
    nonisolated static func command(code: String) -> String? {
        guard let title = BattleNetLibrary.titles[code], title.macVersion else { return nil }
        return title.startCode.map { "launch \($0)" } ?? "launch_uid \(code)"
    }

    /// One argument, the space included.
    nonisolated static func arguments(command: String) -> [String] { ["--exec=\(command)"] }

    /// The game's page in the client, for what the player has to do there.
    nonisolated static func gamePage(code: String) -> URL? {
        BattleNetLibrary.titles[code]?.startCode.flatMap { URL(string: "battlenet://\($0)") }
    }

    /// Why a start doesn't even begin.
    enum Blocker: Equatable {
        case noClient, updateFirst, notAMacGame
    }

    nonisolated static func blocker(code: String, pendingUpdate: Bool, clientThere: Bool) -> Blocker? {
        guard command(code: code) != nil else { return .notAMacGame }
        guard clientThere else { return .noClient }
        return pendingUpdate ? .updateFirst : nil
    }

    // MARK: The client's state

    enum ClientState: Equatable {
        case notRunning, starting, signInNeeded, ready
    }

    nonisolated static let controllerReady = "GameController initialization complete"
    nonisolated static let controllerDown = "Shutting down GameController"
    nonisolated private static let accountLine = "Account manager state has changed to"

    /// Where a client is by its own log. Signed in isn't enough yet: the games' side comes a few seconds
    /// after the account (2 s on 7.11.), and a command before it goes unheard.
    nonisolated static func state(running: Bool, log: String?) -> ClientState {
        guard running else { return .notRunning }
        guard let log else { return .starting }
        if let down = log.range(of: controllerDown, options: .backwards),
           log.range(of: controllerReady, options: .backwards).map({ $0.lowerBound < down.lowerBound }) ?? true {
            return .starting  // that run is ending; the next one writes its own log
        }
        switch BattleNetClient.signedIn(log: log) {
        case false?: return .signInNeeded
        case nil: return .starting
        case true?: return log.contains(controllerReady) ? .ready : .starting
        }
    }

    /// The log of the client that runs now: written to since it started. Every start also leaves a
    /// short one of its loader, and each command sent leaves one more, so the newest isn't the one.
    nonisolated static func clientLog(in folder: URL, since started: Date?) -> (file: URL, text: String)? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names.filter({ $0.hasPrefix("battle.net-") && $0.hasSuffix(".log") }).sorted().reversed().prefix(8) {
            let file = folder.appendingPathComponent(name)
            if let started,
               let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               written < started { continue }
            guard let data = try? Data(contentsOf: file) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if text.contains(accountLine) || text.contains(BattleNetClient.pageAsks) { return (file, text) }
        }
        return nil
    }

    // MARK: Following a start

    enum Event: Equatable {
        /// The client took the command and goes through its launch.
        case launching
        /// It says it can't.
        case refused
        /// Its launch was called off (a question answered with No, a closed dialog).
        case calledOff
        /// It is shutting down.
        case clientEnds
    }

    nonisolated private static let launchingLines = ["Game launch options: programId=", "Game is now running with game launch behavior"]
    nonisolated private static let refusedLines = [
        "Attempted to launch a game that is not installed.", "Could not launch ", "Failed to launch executable",
        "Pending game launch expired before Agent", "Blizzard code signature check failed", "Error threshold reached launching",
    ]
    nonisolated private static let calledOffLine = "Game launch sequence canceled"

    /// What the lines written since the last look say. At its end the client calls every launch off:
    /// that's the end, not a launch being called off.
    nonisolated static func events(in text: String) -> [Event] {
        guard !text.isEmpty else { return [] }
        if text.contains(controllerDown) { return [.clientEnds] }
        var found: [Event] = []
        if launchingLines.contains(where: text.contains) { found.append(.launching) }
        if refusedLines.contains(where: text.contains) { found.append(.refused) }
        if text.contains(calledOffLine) { found.append(.calledOff) }
        return found
    }

    /// The log from where it ended when the command went out.
    struct LogFollower {
        let file: URL
        private var offset: UInt64

        init(file: URL) {
            self.file = file
            offset = (try? FileHandle(forReadingFrom: file).seekToEnd()) ?? 0
        }

        /// What was added since the last call; only whole lines, a line being written waits.
        mutating func newText() -> String {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
            defer { try? handle.close() }
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(), !data.isEmpty,
                  let lastLine = data.lastIndex(of: 0x0A)
            else { return "" }
            let whole = data[data.startIndex...lastLine]
            offset += UInt64(whole.count)
            return String(decoding: whole, as: UTF8.self)
        }
    }

    /// What a start does from second to second, until the game's process is there (which ends this).
    struct Watch: Equatable {
        enum Failure: Equatable { case refused, calledOff, clientEnded, noAnswer }
        enum Step: Equatable { case wait, sendAgain, playerAsked, failed(Failure) }

        /// A command that isn't taken is sent again this often, this many times.
        static let resendEvery = 12
        static let resends = 2
        /// Nothing to show for it this long: the client may be asking something behind the curtain
        /// (a consent, the operating system, which game account), which only its window shows.
        static let askAfter = 30
        /// The client took the command and is starting the game: that can take a while, and its
        /// window coming forward in the middle of a normal start would only be in the way.
        static let askAfterTaken = 120
        /// From then on the player has this long.
        static let answerFor = 300

        private(set) var seconds = 0
        private(set) var taken = false
        private(set) var sent = 0
        private(set) var askedAt: Int?

        /// One second on, with what the log said in it.
        mutating func step(_ events: [Event]) -> Step {
            seconds += 1
            if events.contains(.clientEnds) { return .failed(.clientEnded) }
            if events.contains(.refused) { return .failed(.refused) }
            if events.contains(.calledOff) { return .failed(.calledOff) }
            if events.contains(.launching) { taken = true }
            if let askedAt {
                return seconds - askedAt >= Self.answerFor ? .failed(.noAnswer) : .wait
            }
            if seconds >= (taken ? Self.askAfterTaken : Self.askAfter) {
                askedAt = seconds
                return .playerAsked
            }
            if !taken, sent < Self.resends, seconds % Self.resendEvery == 0 {
                sent += 1
                return .sendAgain
            }
            return .wait
        }
    }
}

extension BattleNetClient {
    nonisolated static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    /// The client running now, and its log: when it's ready and which file a start follows.
    nonisolated static func lookAtClient() -> (state: BattleNetStart.ClientState, log: URL?) {
        let apps = running
        guard !apps.isEmpty else { return (.notRunning, nil) }
        let found = BattleNetStart.clientLog(in: logs, since: apps.compactMap(\.launchDate).min())
        return (BattleNetStart.state(running: true, log: found?.text), found?.file)
    }

    /// Up and out of sight: the window only comes when it needs the player (`show`).
    @MainActor
    static func startHidden() {
        guard let app else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// Passes a command to the running client. Its second start only hands it over and ends, so
    /// nothing waits for it; apart from Nightforge, like everything that may outlive it (DetachedProcess).
    nonisolated static func send(_ command: String) throws {
        guard let app, let program = Bundle(url: app)?.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let process = DetachedProcess()
        process.executableURL = program
        process.arguments = BattleNetStart.arguments(command: command)
        try process.run()
    }

    /// The client in front, on the game's page where there's a way to say so.
    @MainActor
    static func showGame(code: String) {
        if let page = BattleNetStart.gamePage(code: code), NSWorkspace.shared.open(page) { return }
        show()
    }
}
