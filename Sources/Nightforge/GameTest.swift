import Foundation

/// The game test ("Spieletest"): Nightforge plays through the installed games by itself, one after
/// the other and each the way Play starts it, and writes down what happened – the ways it took,
/// whether a picture came and how soon, the frame rates, and for a game without one the log's
/// errors or where it hung. A run after an engine change shows at once which games start and which
/// broke; until now that came out live, one game at a time ("should run, doesn't for us"). This is
/// what the run decides and writes; GameTestRun drives it. Only ever started by hand:
/// `defaults write io.github.lordhayne.nightforge gameTest -bool true`.
enum GameTest {
    /// Its switches, all in Nightforge's defaults.
    enum Keys {
        /// True: a run starts once Nightforge is ready and no game runs – once: it's removed then.
        static let start = "gameTest"
        /// Only these games, by key ("steam.570") or name, separated by commas.
        static let only = "gameTest.only"
        /// Seconds a game gets for its first picture once its process is there.
        static let pictureWait = "gameTest.pictureWait"
        /// Seconds a game with a picture keeps running, for its frame rates.
        static let playSeconds = "gameTest.playSeconds"
        /// True: the run ends after the game it's at.
        static let stop = "gameTest.stop"
        /// A test basket (`Basket`, compat-db's testkorb.json): its games first, by its score.
        static let basket = "gameTest.basket"
        /// The helper that presses "Play!" in Unity's start window is on (UnityDialog's own switch, on
        /// unless set to false, read at every start – `UnityDialog.enabled`): the run gives it time before
        /// it calls the window one that needs a click. Whether it runs for a game says UnityDialog.programs.
        static let unityDialogPlay = UnityDialog.switchKey
    }

    /// A run is under way: nothing gets installed for a start (LibraryModel.installRuntimes), and
    /// Nightforge doesn't quit after one (Prefs.afterLaunch). Set on the main actor only.
    nonisolated(unsafe) static var active = false

    struct Settings: Equatable {
        var pictureWait: TimeInterval = 120
        var playSeconds: TimeInterval = 60
        var only: [String] = []
        /// The test basket's file, "" for none.
        var basket = ""

        init(pictureWait: TimeInterval = 120, playSeconds: TimeInterval = 60, only: [String] = [], basket: String = "") {
            self.pictureWait = pictureWait
            self.playSeconds = playSeconds
            self.only = only
            self.basket = basket
        }

        /// From the switches, within sensible bounds: a picture gets 30 s to 15 min, a game runs 10 s to 10 min.
        init(_ defaults: UserDefaults) {
            let wait = defaults.integer(forKey: Keys.pictureWait)
            let play = defaults.integer(forKey: Keys.playSeconds)
            self.init(pictureWait: wait > 0 ? TimeInterval(min(max(wait, 30), 900)) : 120,
                      playSeconds: play > 0 ? TimeInterval(min(max(play, 10), 600)) : 60,
                      only: (defaults.string(forKey: Keys.only) ?? "").split(whereSeparator: { ",;\n".contains($0) })
                          .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                      basket: defaults.string(forKey: Keys.basket) ?? "")
        }
    }

    // MARK: - Which games, in which order

    /// Why a game isn't started, or why its start was called off: each would need the player, or a download.
    enum Skip: String, Codable, CaseIterable {
        case antiCheat, vrOnly, otherBottle, signIn, update, runtimes, d3dMetal, macSteamSetup, versionSwitch,
             steamAsks, macOSAsks, stopped, gone

        var german: String {
            switch self {
            case .antiCheat: return "Anti-Cheat sperrt es auf dem Mac"
            case .vrOnly: return "nur mit VR-Brille"
            case .otherBottle: return "liegt in einer CrossOver-Flasche"
            case .signIn: return "bräuchte eine Anmeldung"
            case .update: return "ein Update stünde an (würde laden)"
            case .runtimes: return "bräuchte erst Laufzeiten (würde laden)"
            case .d3dMetal: return "braucht D3DMetal, das nicht eingerichtet ist"
            case .macSteamSetup: return "Steam für Mac ist nicht eingerichtet"
            case .versionSwitch: return "erster Start der anderen Fassung (Spielstände würden übertragen)"
            case .steamAsks: return "Steam fragte etwas in seinem Fenster"
            case .macOSAsks: return "macOS fragt um Erlaubnis"
            case .stopped: return "Test vorher angehalten"
            case .gone: return "nicht mehr installiert"
            }
        }
    }

    /// What decides whether a game can start unattended, as GameTestRun finds it before the run.
    struct Facts: Equatable {
        var platform = Platform.windows
        var store = Provider.steam
        /// Its anti-cheat stops it – not a profile's "not yet", which Play Anyway starts.
        var antiCheat = false
        var vrOnly = false
        var builtInBottle = true
        /// Steam for Mac is installed and has been signed in.
        var macSteamReady = true
        /// Its store has a sign-in to start it with (Nightforge's Steam, Epic).
        var signedIn = true
        var pendingUpdate = false
        /// The first start of its other version, which carries the saves over (SaveTransfer).
        var versionSwitch = false
        /// Winetricks verbs or GOG's redistributables a start would fetch first.
        var missingRuntimes: [String] = []
        /// It needs D3DMetal, and starting it would ask to set that up.
        var needsD3DMetal = false
    }

    static func skip(_ facts: Facts) -> Skip? {
        if facts.antiCheat { return .antiCheat }
        if facts.vrOnly { return .vrOnly }
        if facts.platform == .windows, !facts.builtInBottle { return .otherBottle }
        if facts.platform == .mac, facts.store == .steam, !facts.macSteamReady { return .macSteamSetup }
        if !facts.signedIn { return .signIn }
        if facts.pendingUpdate { return .update }
        if facts.versionSwitch { return .versionSwitch }
        if !facts.missingRuntimes.isEmpty { return .runtimes }
        if facts.needsD3DMetal { return .d3dMetal }
        return nil
    }

    struct Candidate: Equatable {
        var key: String
        var name: String
        var store: Provider
        var storeID: String
        var platform: Platform
        /// The profile says it doesn't start on a Mac yet; Play Anyway starts it all the same.
        var notYet = false
        var skip: Skip?
        /// What the skip is about: the runtimes it lacks.
        var skipNote: String?
        /// From the test basket: it's in there, the way it expects first, the popular games it stands for.
        var inBasket = false
        var hint: String?
        var standsFor: [String]?
    }

    /// Which games matter most to test (compat-db, scripts/test-basket.py): by `score`, with the way
    /// LaunchHealth is expected to take first (`hint`) and the popular games of the same engine and
    /// graphics each one stands for. It only orders the installed games – never a reason to download.
    struct Basket: Decodable, Equatable {
        struct Item: Decodable, Equatable {
            var key: String
            var score: Double?
            var hint: String?
            var standsFor: [String]?
        }

        static let format = 1

        var formatVersion: Int
        var generated: String?
        var games: [Item]

        static func load(_ path: String) -> Basket? {
            guard !path.isEmpty, let data = FileManager.default.contents(atPath: (path as NSString).expandingTildeInPath),
                  let basket = try? JSONDecoder().decode(Basket.self, from: data), basket.formatVersion == format
            else { return nil }
            return basket
        }
    }

    /// The games in the order they're played: the Windows versions first – Steam's, then Epic's and
    /// GOG's, all in the one Wine session – then the Mac versions, GOG's and last Steam's: Steam for
    /// Mac signs the Windows Steam out, so it changes over once. Within each the test basket's games
    /// first, highest score first – a run cut short has tested what matters most – then by name.
    /// With `only`, just those games, by key or name.
    static func plan(_ candidates: [Candidate], only: [String] = [], basket: Basket? = nil) -> [Candidate] {
        let wanted = Set(only.map { $0.lowercased() })
        let items = (basket?.games ?? []).enumerated().sorted { ($0.element.score ?? 0, -$0.offset) > ($1.element.score ?? 0, -$1.offset) }
        var place: [String: (index: Int, item: Basket.Item)] = [:]
        for (index, entry) in items.enumerated() where place[entry.element.key.lowercased()] == nil {
            place[entry.element.key.lowercased()] = (index, entry.element)
        }
        return candidates
            .filter { wanted.isEmpty || wanted.contains($0.key.lowercased()) || wanted.contains($0.name.lowercased()) }
            .map { candidate in
                var candidate = candidate
                if let item = place[candidate.key.lowercased()]?.item {
                    candidate.inBasket = true
                    candidate.hint = item.hint
                    candidate.standsFor = item.standsFor?.isEmpty == false ? item.standsFor : nil
                }
                return candidate
            }
            .sorted {
                (rank($0), place[$0.key.lowercased()]?.index ?? Int.max, $0.name.lowercased(), $0.key)
                    < (rank($1), place[$1.key.lowercased()]?.index ?? Int.max, $1.name.lowercased(), $1.key)
            }
    }

    static func rank(_ candidate: Candidate) -> Int {
        switch (candidate.platform, candidate.store) {
        case (.windows, .steam): return 0
        case (.windows, .epic): return 1
        case (.windows, .gog): return 2
        case (.mac, .gog), (.mac, .epic): return 3
        case (.mac, .steam): return 4
        }
    }

    /// A start that came to a sign-in: the store's other games of that version would only come to it again.
    static func blocked(_ candidate: Candidate, after entries: [Entry]) -> Bool {
        entries.contains {
            $0.skip == .signIn && $0.outcome == .needsPlayer && $0.store == candidate.store.rawValue
                && $0.platform == candidate.platform.rawValue
        }
    }

    // MARK: - What a start came to

    enum Outcome: String, Codable {
        /// The curtain sank for it: its window in front, in picture size.
        case picture
        /// It ran, and ended without a picture and without signs of a crash.
        case noWindow
        /// It ended without a picture, with a crash in the log.
        case crash
        /// Still running without a picture after `pictureWait`: sampled, then ended.
        case hang
        /// Unity's start window ("<Game> Configuration" with "Play!"; The Forest's 464×438, 3.11.)
        /// stood before any picture: it waits for a click there. Ended without a sample.
        case startWindow
        /// Still running without a picture, but with a window of its own smaller than a picture
        /// standing all along – a start window or a question (GameProcesses.question): it waits for a
        /// click, it doesn't hang (Black Myth: Wukong's driver warning, 2.11.).
        case dialog
        /// No process of it showed up.
        case noStart
        /// Called off: it came to something only the player can do (a sign-in, Steam's question).
        case needsPlayer
        /// No process list the whole while (ps didn't answer, 3.11.): nothing is known about the start –
        /// neither that it ran nor that it didn't.
        case unknown
        case skipped
    }

    /// One look while waiting for a game's picture. `waited`: since its process last appeared –
    /// each way the ladder tries gets the full wait; `idle`: how long nothing of it has run with no
    /// start under way (the ladder decides on the next way within that); `total`: since Play.
    enum Look: Equatable { case wait, picture, ended, hang, tooLong }

    /// Long enough for the ladder: its first seconds' watch counts a game gone after 10 s, then
    /// Steam has to see it gone before the next way starts.
    static let endGrace: TimeInterval = 25
    /// Steam's own wait for a start ends after 15 minutes (LibraryModel.start); then something hangs.
    static let longestStart: TimeInterval = 20 * 60

    static func look(picture: Bool, running: Bool, waited: TimeInterval, idle: TimeInterval, total: TimeInterval,
                     settings: Settings) -> Look {
        if picture { return .picture }
        if running, waited >= settings.pictureWait { return .hang }
        if !running, idle >= endGrace { return .ended }
        return total >= longestStart ? .tooLong : .wait
    }

    /// How long Steam's question may stand before the run calls the start off. Some go on by
    /// themselves within seconds – ShowInterstitials once Steam's hidden window has been shown: Left
    /// 4 Dead 2 on 2.11. after 5 s, while the run had called it off at 3 s and went on to the next
    /// game with it still starting. Everything else that needs the player calls it off at once.
    static let steamAskPatience: TimeInterval = 30

    static func callsOff(_ need: Skip, after waiting: TimeInterval) -> Bool {
        need == .steamAsks ? waiting >= steamAskPatience : true
    }

    /// A question of macOS's over the start that nobody has answered, from the curtain's lines
    /// (LibraryModel.watchCurtain): "Curtain under a question of macOS's for <game>: <app> in front",
    /// not "… macOS's question is answered" since. Only the player can answer it – access to a
    /// removable volume (Tomb Raider's Mac version on the stick, 3.11.: UserNotificationCenter),
    /// Accessibility, a password. `gaveUp`: the curtain stopped waiting for it ("Curtain stops waiting
    /// for macOS's question for <game>"), three minutes unanswered. After that the curtain says nothing
    /// more about it, not even when it goes – so that line is the run's verdict (it calls the start off
    /// then), and a later hang is never taken for the question.
    struct MacOSQuestion: Equatable {
        var asker: String
        var gaveUp = false
    }

    static func macOSQuestion(_ game: String, in log: String) -> MacOSQuestion? {
        let asks = "Curtain under a question of macOS's for \(game): "
        let answered = "Curtain up again for \(game): macOS's question is answered"
        let gaveUp = "Curtain stops waiting for macOS's question for \(game) "
        var question: MacOSQuestion?
        for line in log.split(separator: "\n") {
            if let range = line.range(of: asks) {
                let rest = line[range.upperBound...]
                question = MacOSQuestion(asker: String(rest.hasSuffix(" in front") ? rest.dropLast(" in front".count) : rest))
            } else if line.contains(answered) {
                question = nil
            } else if line.contains(gaveUp) {
                question?.gaveUp = true
            }
        }
        return question
    }

    /// The program asking, while a question stands (`macOSQuestion`).
    static func macOSAsking(_ game: String, in log: String) -> String? {
        macOSQuestion(game, in: log)?.asker
    }

    /// How the report names an app that had the front: Nightforge, Steam, Wine's programs and macOS's own
    /// (its askers, the Finder) by name, any other as "eine andere App" – a password manager or a
    /// messenger has no place in a report that may go public.
    static func frontName(_ name: String?, path: String?, bundleID: String?) -> String {
        guard let name, !name.isEmpty else { return "keine App" }
        if bundleID?.hasPrefix("io.github.lordhayne") == true { return "Nightforge" }
        let lower = path?.lowercased() ?? ""
        // Under Wine the program is Wine's loader; Steam's window there says so by its name.
        if lower.contains("steam") || name.lowercased().contains("steam") { return "Steam" }
        if lower.contains("wine") { return "ein Windows-Programm" }
        if lower.hasPrefix("/system/") { return name }
        return "eine andere App"
    }

    /// The names macOS asks through (GameProcesses.macOSAskers on the curtain's side) and what else
    /// may stand in a look of the curtain's by name.
    static let knownFront = ["Nightforge", "Nightforge Game", "Steam", "steamwebhelper", "nobody", "UserNotificationCenter",
                             "AuthorizationPromptService", "universalAccessAuthWarn", "CoreLocationAgent", "CoreServicesUIAgent",
                             "SecurityAgent", "coreautha", "Finder"]

    /// A look of the curtain's for the report: who had the front only when it's the game, Nightforge,
    /// Steam or macOS's own ("in front Claude (1276, not the game's)" → "in front eine andere App …").
    static func reportLook(_ look: String, game: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"in front (.+?) \(([0-9-]+), (the game's|not the game's)\)"#) else { return look }
        let range = NSRange(look.startIndex..., in: look)
        guard let match = regex.firstMatch(in: look, range: range), let nameRange = Range(match.range(at: 1), in: look),
              let ownerRange = Range(match.range(at: 3), in: look)
        else { return look }
        let name = String(look[nameRange])
        if look[ownerRange] == "the game's" || name == game || knownFront.contains(name) { return look }
        return look.replacingCharacters(in: nameRange, with: "eine andere App")
    }

    /// An app in front that has nothing to do with the start – not Nightforge, the game, Wine or
    /// Steam. Unattended, the curtain then never hands the front to the game, which only Nightforge
    /// in front can do: on 2.11. the Claude app had it, and Black Myth: Wukong counted as hanging.
    static func foreignFront(path: String?, bundleID: String?, gameFolder: String?) -> Bool {
        if bundleID?.hasPrefix("io.github.lordhayne") == true { return false }
        guard let path = path?.lowercased(), !path.isEmpty else { return false }
        if path.contains("wine") || path.contains("steam") { return false }
        if let gameFolder, !gameFolder.isEmpty, path.hasPrefix(gameFolder.lowercased()) { return false }
        return true
    }

    /// Whether a Unity game's start window has stood long enough to be one: a window of its own
    /// smaller than a picture (GameProcesses.question) for `startWindowGrace` seconds before any
    /// picture. Unity draws its splash in the game's own window, so a small one is its "<Game>
    /// Configuration" with "Play!". Only for Unity: elsewhere a small window may be a splash that
    /// goes by itself (Unreal's), and waits the whole `pictureWait` (then `dialog`).
    static func startWindowStands(unity: Bool, picture: Bool, standing: TimeInterval?, helper: Bool) -> Bool {
        unity && !picture && (standing ?? 0) >= startWindowGrace(helper: helper)
    }

    /// With the helper on, long enough for it to press "Play!" first: it presses 0.5–1 s after the
    /// window comes, and once more 3 s later.
    static func startWindowGrace(helper: Bool) -> TimeInterval { helper ? 30 : 10 }

    /// The helper pressed "Play!" in the start's stretch of wine.log: `Unity's window "…": pressed Play!`.
    static func helperPressedPlay(in log: String) -> Bool {
        log.split(separator: "\n").contains { $0.contains("Unity's window") && $0.contains("pressed Play!") }
    }

    /// What the run saw of a start.
    struct Seen: Equatable {
        var process = false
        var picture = false
        var stillRunning = false
        var crashSigns = false
        var needs: Skip?
        /// A window of its own smaller than a picture stood when the wait ran out.
        var smallWindow = false
        /// Unity's start window stood (`startWindowStands`).
        var startWindow = false
        /// `blindLooks` looks in a row without a process list.
        var unknown = false
    }

    /// Looks in a row without a process list (one a second) before the run gives up on a start.
    static let blindLooks = 120

    enum BlindLook: Equatable { case picture, wait, unknown }

    /// A look without a process list: the curtain's picture is known all the same (it sank for the
    /// game), so it counts as one; else the run waits, `blindLooks` at most, then nothing is known.
    static func blindLook(picture: Bool, looks: Int) -> BlindLook {
        if picture { return .picture }
        return looks >= blindLooks ? .unknown : .wait
    }

    /// How long the run waits for a process list before it ends a game or starts the next one. Past
    /// that it goes on without (the game not ended, its end unknown), and while ps stays down
    /// (`gaveUpBefore`) it doesn't wait again: a ps down for good still lets the run finish.
    static let processListPatience: TimeInterval = 15 * 60

    static func waitsForProcessList(waited: TimeInterval, gaveUpBefore: Bool) -> Bool {
        !gaveUpBefore && waited < processListPatience
    }

    static func outcome(_ seen: Seen) -> Outcome {
        if seen.picture { return .picture }
        if seen.needs != nil { return .needsPlayer }
        if seen.unknown { return .unknown }
        if seen.startWindow { return .startWindow }
        if seen.stillRunning { return seen.smallWindow ? .dialog : .hang }
        if seen.crashSigns { return .crash }
        return seen.process ? .noWindow : .noStart
    }

    /// Below this a picture counts as a low frame rate (GameRating's lowFrameRate).
    static let lowFrameRate: Double = 25

    /// GameRating.Issue's words: it ended by itself while it was played, its frames stayed low.
    static func issues(endedWhilePlaying: Bool, frames: Frames?) -> [String] {
        var issues: [String] = []
        if endedWhilePlaying { issues.append("crashed") }
        if let frames, frames.average < lowFrameRate { issues.append("lowFrameRate") }
        return issues
    }

    /// compat-report.yml's words (CompatReport.result), so a count of reports takes an entry as it
    /// is: good, problems, no-start. Nil: not tried, says nothing about the game.
    static func result(_ outcome: Outcome, issues: [String]) -> String? {
        switch outcome {
        case .picture: return issues.isEmpty ? "good" : "problems"
        case .noWindow, .crash, .hang, .noStart: return "no-start"
        // Waiting for a click says nothing yet about how it runs.
        case .startWindow, .dialog, .needsPlayer, .unknown, .skipped: return nil
        }
    }

    struct Frames: Codable, Equatable {
        /// Over all periods, by their length.
        var average: Double
        /// The lowest period.
        var low: Double
        var periods: Int
    }

    /// The frame rates the game logged (FramePacing.periods): DXMT does, every 10 s from its first
    /// frame. D3DMetal, WineD3D, DXVK on winecx and Mac versions log none.
    static func frames(_ periods: [(fps: Double, seconds: Double)]) -> Frames? {
        let periods = periods.filter { $0.fps > 0 && $0.seconds > 0 }
        guard !periods.isEmpty else { return nil }
        let seconds = periods.map(\.seconds).reduce(0, +)
        let average = periods.map { $0.fps * $0.seconds }.reduce(0, +) / seconds
        return Frames(average: (average * 10).rounded() / 10, low: ((periods.map(\.fps).min() ?? 0) * 10).rounded() / 10,
                      periods: periods.count)
    }

    // MARK: - The ways in the log

    /// The line LibraryModel.launch writes before each start of a Windows game.
    static func startNote(game: String, way: String, engine: String?) -> String {
        "Start of \(game): \(way)" + (engine.map { " on \($0)" } ?? "")
    }

    /// The starts of `game` in a stretch of wine.log (`startNote`), each with the log up to the next one.
    static func starts(of game: String, in log: String) -> [(way: String, engine: String?, log: String)] {
        let marker = "[nightforge] " + startNote(game: game, way: "", engine: nil)
        var starts: [(way: String, engine: String?, log: String)] = []
        var lines: [Substring] = []
        func close() {
            if !starts.isEmpty { starts[starts.count - 1].log = lines.joined(separator: "\n") }
            lines = []
        }
        for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let range = line.range(of: marker) else {
                if !starts.isEmpty { lines.append(line) }
                continue
            }
            close()
            let rest = line[range.upperBound...]
            if let on = rest.range(of: " on ", options: .backwards) {
                starts.append((String(rest[..<on.lowerBound]), String(rest[on.upperBound...]), ""))
            } else {
                starts.append((String(rest), nil, ""))
            }
        }
        close()
        return starts
    }

    struct Way: Codable, Equatable {
        /// A `LaunchAttempt.id` ("dxmt -dx11"), or "mac".
        var way: String
        var engine: String?
        /// How it ended: the earlier ways without a picture, the last as the game's start did.
        var outcome: Outcome
    }

    static func ways(of game: String, in log: String, last: Outcome) -> [Way] {
        let starts = starts(of: game, in: log)
        return starts.enumerated().map { index, start in
            Way(way: start.way, engine: start.engine,
                outcome: index == starts.count - 1 ? last : GameLog.crashed(in: start.log) ? .crash : .noWindow)
        }
    }

    /// Where a hanging game waits: the heaviest frames of `sample`'s "Sort by top of stack" list
    /// (semaphore_wait_trap, kevent, read …), its counts kept.
    static func topOfStack(in sample: String, limit: Int = 8) -> [String] {
        guard let start = sample.range(of: "Sort by top of stack") else { return [] }
        var frames: [String] = []
        for line in sample[start.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let frame = line.trimmingCharacters(in: .whitespaces)
            if frame.isEmpty || frame.hasSuffix(":") {
                if frames.isEmpty { continue }
                break
            }
            frames.append(frame.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression))
            if frames.count == limit { break }
        }
        return frames
    }

    /// What the curtain saw last of the game (LibraryModel.watchCurtain): its processes, its windows,
    /// who had the front – why no picture counted.
    static func lastLook(of game: String, in log: String) -> String? {
        let marker = "Curtain look at \(game): "
        return log.split(separator: "\n").last { $0.contains(marker) }
            .flatMap { line in line.range(of: marker).map { String(line[$0.upperBound...]) } }
    }

    // MARK: - The Mac's load

    /// How busy the Mac is when the run, or a game, starts: with other work going on (a build, 24
    /// compilers at once), the frame rates are not the game's.
    struct Load: Codable, Equatable {
        /// The one-minute load average.
        var average: Double
        var cores: Int
        /// Under half the cores busy (`lowLoadShare`).
        var low: Bool

        init(average: Double, cores: Int) {
            self.average = (average * 10).rounded() / 10
            self.cores = cores
            low = self.average < Double(max(cores, 1)) * GameTest.lowLoadShare
        }

        static var now: Load? {
            var averages = [Double](repeating: 0, count: 3)
            guard getloadavg(&averages, 3) >= 1 else { return nil }
            return Load(average: averages[0], cores: ProcessInfo.processInfo.activeProcessorCount)
        }
    }

    static let lowLoadShare = 0.5
    /// How long a run waits at its start for a busy Mac to calm down.
    static let loadPatience: TimeInterval = 5 * 60

    // MARK: - Calm between games

    /// The CPU Steam and the Wine session use together, from `ps -axo pcpu=,command=`: both Steams
    /// and their helpers, wineserver and Wine's own programs.
    static func sessionCPU(_ ps: String) -> Double {
        ps.split(separator: "\n").reduce(0) { sum, line in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, let cpu = Double(fields[0].replacingOccurrences(of: ",", with: ".")) else { return sum }
            let command = fields[1].lowercased()
            return command.contains("wine") || command.contains("steam") ? sum + cpu : sum
        }
    }

    /// Calm: the last `count` looks all under `limit` percent – the save written, Steam idle again.
    static func calm(_ looks: [Double], limit: Double = 30, count: Int = 3) -> Bool {
        looks.count >= count && looks.suffix(count).allSatisfy { $0 < limit }
    }
}
