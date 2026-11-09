// Steam's licence from Steam's own files in a made-up Steam folder: what's open before a start, and the player's yes
// as the log grows, in any pieces. SteamLicenceTest has the rules: tests/SteamLicenceFilesTest/run.sh
import Foundation

@main
struct SteamLicenceFilesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let fm = FileManager.default
    static let worlds = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("worlds", isDirectory: true)
    static var made = 0

    typealias Entry = SteamLicence.Entry

    static func world() -> URL {
        made += 1
        let root = worlds.appendingPathComponent("\(made)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func put(_ data: Data, _ path: String, in root: URL) {
        let file = root.appendingPathComponent(path)
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }

    static func put(_ text: String, _ path: String, in root: URL) { put(Data(text.utf8), path, in: root) }

    static func append(_ data: Data, _ path: String, in root: URL) {
        let file = root.appendingPathComponent(path)
        guard let handle = try? FileHandle(forWritingTo: file) else { return put(data, path, in: root) }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    }

    static let first = (id: "76561197972611406", folder: "12345678")
    static let second = (id: "76561198000000001", folder: "39734273")
    static let licence = "1426210_eula_1"
    static let entries = [Entry(id: licence, version: 0)]

    static func users(_ list: [(id: String, recent: Bool)], key: String = "MostRecent") -> String {
        var text = "\"users\"\n{\n"
        for user in list { text += "\t\"\(user.id)\"\n\t{\n\t\t\"AccountName\"\t\t\"a\"\n\t\t\"\(key)\"\t\t\"\(user.recent ? 1 : 0)\"\n\t}\n" }
        return text + "}\n"
    }

    static func config(_ pairs: [String: Int] = [:]) -> String {
        var text = "\"UserLocalConfigStore\"\r\n{\r\n"
        for (id, version) in pairs { text += "\t\t\"\(id)\"\t\t\"\(version)\"\r\n" }
        return text + "}\r\n"
    }

    static func accepted(_ id: String) -> String { "[2026-11-09 06:31:05] SteamUI: INFO: accepted eula \(id)\r\n" }
    static func complete(_ id: String) -> String { "[2026-11-09 06:31:05] SteamUI: INFO: eulas complete \(id)\r\n" }
    static let logPath = "logs/webhelper_js.txt"

    static func open(_ root: URL, _ list: [Entry] = entries) -> Bool { SteamLicenceFiles.stillOpen(entries: list, steamRoot: root) }

    // MARK: Before the start

    static func beforehand() {
        let one = world()
        put(users([(first.id, true)]), "config/loginusers.vdf", in: one)
        put(config(), "userdata/\(first.folder)/config/localconfig.vdf", in: one)
        check(open(one), "the account's config has no answer: open")
        check(!open(one, []), "a game without a licence")

        let answered = world()
        put(users([(first.id, true)]), "config/loginusers.vdf", in: answered)
        put(config([licence: 0]), "userdata/\(first.folder)/config/localconfig.vdf", in: answered)
        check(!open(answered), "answered in localconfig")
        check(open(answered, [Entry(id: licence, version: 2)]), "a newer version than was answered")

        let empty = world()
        check(!open(empty), "no Steam folder to speak of: nothing is said")

        let noConfig = world()
        put(users([(first.id, true)]), "config/loginusers.vdf", in: noConfig)
        try? fm.createDirectory(at: noConfig.appendingPathComponent("userdata/\(first.folder)"), withIntermediateDirectories: true)
        check(!open(noConfig), "the account has no localconfig yet: can't be told, nothing is said")

        let two = world()
        put(users([(first.id, false), (second.id, true)]), "config/loginusers.vdf", in: two)
        put(config([licence: 0]), "userdata/\(first.folder)/config/localconfig.vdf", in: two)
        put(config(), "userdata/\(second.folder)/config/localconfig.vdf", in: two)
        check(open(two), "the account signed in last counts, not the other's answer")

        let lower = world()
        put(users([(second.id, true)], key: "mostrecent"), "config/loginusers.vdf", in: lower)
        put(config([licence: 0]), "userdata/\(second.folder)/config/localconfig.vdf", in: lower)
        put(config(), "userdata/\(first.folder)/config/localconfig.vdf", in: lower)
        check(!open(lower), "as an older Steam spells the key")

        let wrongFolder = world()
        put(users([(first.id, true)]), "config/loginusers.vdf", in: wrongFolder)
        put(config(), "userdata/\(second.folder)/config/localconfig.vdf", in: wrongFolder)
        check(!open(wrongFolder), "the marked account has no folder here: another's config says nothing")

        let damagedUsers = world()
        put("\"users\"\n{\n\t\"", "config/loginusers.vdf", in: damagedUsers)
        put(config([licence: 0]), "userdata/\(first.folder)/config/localconfig.vdf", in: damagedUsers)
        check(!open(damagedUsers), "loginusers cut off: the only account there is")

        let garbage = world()
        put(users([(first.id, true)]), "config/loginusers.vdf", in: garbage)
        put(Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 37) }), "userdata/\(first.folder)/config/localconfig.vdf", in: garbage)
        check(open(garbage), "a localconfig that's noise answers nothing, and breaks nothing")
    }

    static func inTheLog() {
        func root(log: Data) -> URL {
            let root = world()
            put(users([(first.id, true)]), "config/loginusers.vdf", in: root)
            put(config(), "userdata/\(first.folder)/config/localconfig.vdf", in: root)
            put(log, logPath, in: root)
            return root
        }
        check(!open(root(log: Data(accepted(licence).utf8))), "said yes just now: localconfig only has it when Steam quits")
        check(open(root(log: Data(complete(licence).utf8))), "only an accepted line is an answer")
        check(open(root(log: Data(accepted("578080_eula_1").utf8))), "another game's yes")

        let filler = Data(String(repeating: "x", count: 99).utf8) + Data("\n".utf8)
        let farAway = Data(accepted(licence).utf8) + Data((0..<6_000).flatMap { _ in filler })
        check(open(root(log: farAway)), "further back than is searched: as if never said, the word is only a word")
        let near = Data((0..<6_000).flatMap { _ in filler }) + Data(accepted(licence).utf8)
        check(!open(root(log: near)), "at the end of a long log")

        let umlauts = Data(String(repeating: "äöü€", count: 90_000).utf8) + Data("\n".utf8) + Data(accepted(licence).utf8)
        check(!open(root(log: umlauts)), "the search starting in the middle of a character costs nothing")
    }

    // MARK: During the start

    static func answerAsItGrows() {
        let app = 1_426_210

        let old = world()
        put(accepted(licence) + complete(licence), logPath, in: old)
        var fromBefore = SteamLicenceLog(steamRoot: old, appID: app)
        check(!fromBefore.answered(), "a yes from before this start isn't this start's")

        let halves = world()
        put("", logPath, in: halves)
        var half = SteamLicenceLog(steamRoot: halves, appID: app)
        append(Data(accepted(licence).utf8), logPath, in: halves)
        append(Data("[…] SteamUI: INFO: eulas compl".utf8), logPath, in: halves)
        check(!half.answered(), "half a line isn't read")
        append(Data("ete \(licence)".utf8), logPath, in: halves)
        check(!half.answered(), "nor is a line without its end")
        append(Data("\r\n".utf8), logPath, in: halves)
        check(half.answered(), "whole, it is")

        let apart = world()
        put("", logPath, in: apart)
        var pieces = SteamLicenceLog(steamRoot: apart, appID: app)
        append(Data(accepted(licence).utf8), logPath, in: apart)
        check(!pieces.answered(), "accepted, with more to come")
        append(Data("SteamBrowser: unrelated\r\n".utf8), logPath, in: apart)
        check(!pieces.answered(), "something else meanwhile")
        append(Data(complete(licence).utf8), logPath, in: apart)
        check(pieces.answered(), "complete, at a later look")

        let fresh = world()
        put(String(repeating: "old line\r\n", count: 500), logPath, in: fresh)
        var restarted = SteamLicenceLog(steamRoot: fresh, appID: app)
        put(accepted(licence) + complete(licence), logPath, in: fresh)
        check(restarted.answered(), "Steam began a fresh, shorter log")

        let late = world()
        var notYet = SteamLicenceLog(steamRoot: late, appID: app)
        check(!notYet.answered(), "no log at all yet")
        put(accepted(licence) + complete(licence), logPath, in: late)
        check(notYet.answered(), "a log that comes after the start counts from its first line")

        let gone = world()
        put("", logPath, in: gone)
        var keeps = SteamLicenceLog(steamRoot: gone, appID: app)
        put(accepted(licence) + complete(licence), logPath, in: gone)
        check(keeps.answered(), "a yes")
        try? fm.removeItem(at: gone.appendingPathComponent(logPath))
        check(keeps.answered(), "and it stays one when the log goes")

        let again = world()
        put("", logPath, in: again)
        var twice = SteamLicenceLog(steamRoot: again, appID: 231_430)
        twice.know(["231430x"])
        append(Data((accepted("231430x") + complete("231430x")).utf8), logPath, in: again)
        check(twice.answered(), "a licence appinfo names")
        twice.askedAgain()
        check(!twice.answered(), "Steam asks once more: that yes doesn't answer it")
        append(Data((accepted("231430x") + complete("231430x")).utf8), logPath, in: again)
        check(twice.answered(), "the names it knows are still known for the next yes")

        let others = world()
        put("", logPath, in: others)
        var mine = SteamLicenceLog(steamRoot: others, appID: app)
        append(Data((accepted("578080_eula_1") + complete("578080_eula_1") + accepted(licence)).utf8), logPath, in: others)
        check(!mine.answered(), "another game's whole yes beside this game's half")
    }

    /// However the bytes come in, a growing log ends up saying the same.
    static func anyPieces() {
        var random = SystemRandomNumberGenerator()
        let app = 1_426_210
        let line = [accepted(licence), complete(licence), accepted("578080_eula_1"), complete("578080_eula_1"),
                    "SteamBrowser: ä€😀 nothing\r\n", "\r\n", "INFO: accepted eula \r\n", "\n"]
        for _ in 0..<400 {
            let text = (0..<Int.random(in: 0...14, using: &random)).map { _ in line.randomElement(using: &random)! }.joined()
            let bytes = Data(text.utf8)
            var whole = SteamLicence.Answer(appID: app)
            for piece in text.split(whereSeparator: \.isNewline) { whole.read(piece) }

            let root = world()
            put("", logPath, in: root)
            var log = SteamLicenceLog(steamRoot: root, appID: app)
            var at = 0
            var said = false
            while at < bytes.count {
                let size = min(Int.random(in: 1...40, using: &random), bytes.count - at)
                append(bytes.subdata(in: at..<(at + size)), logPath, in: root)
                at += size
                if Bool.random(using: &random) { said = log.answered() || said }
            }
            said = log.answered() || said
            check(said == whole.complete, "the same yes in any pieces: \(said) for \(text.debugDescription)")
            try? fm.removeItem(at: root)
            if failures > 0 { return }
        }
    }

    // MARK: The same for the question: what the console log says, in any pieces

    static func watcherAnyPieces() {
        var random = SystemRandomNumberGenerator()
        let app = 1_426_210
        let steps = ["GameAction [AppID \(app), ActionID 3] : LaunchApp changed task to ShowEula with \"\"\r\n",
                     "GameAction [AppID \(app), ActionID 3] : LaunchApp waiting for user response to ShowEula \"\"\r\n",
                     "GameAction [AppID \(app), ActionID 4] : LaunchApp changed task to CreatingProcess with \"\"\r\n",
                     "GameAction [AppID \(app), ActionID 3] : LaunchApp continues with user response \"ShowEula\"\r\n",
                     "GameAction [AppID 578080, ActionID 9] : LaunchApp changed task to ShowEula with \"\"\r\n",
                     "unrelated ä€😀\r\n"]
        let path = "logs/console_log.txt"
        for _ in 0..<300 {
            let chosen = (0..<Int.random(in: 1...10, using: &random)).map { _ in steps.randomElement(using: &random)! }
            let text = chosen.joined()
            let bytes = Data(text.utf8)

            let oneGo = world()
            put("", path, in: oneGo)
            var once = LaunchWatcher(steamRoot: oneGo, appID: app)
            put(bytes, path, in: oneGo)
            _ = once.poll()

            let root = world()
            put("", path, in: root)
            var watcher = LaunchWatcher(steamRoot: root, appID: app)
            var at = 0
            while at < bytes.count {
                let size = min(Int.random(in: 1...60, using: &random), bytes.count - at)
                append(bytes.subdata(in: at..<(at + size)), path, in: root)
                at += size
                if Bool.random(using: &random) { _ = watcher.poll() }
            }
            _ = watcher.poll()
            check(once.licenceAsked == watcher.licenceAsked, "asked, in any pieces: \(text.debugDescription)")
            check(once.wentOnAfterLicence == watcher.wentOnAfterLicence, "went on, in any pieces: \(text.debugDescription)")
            check(once.licenceContinued == watcher.licenceContinued, "continued, in any pieces: \(text.debugDescription)")
            check(!watcher.wentOnAfterLicence || watcher.licenceAsked, "nothing goes on from a licence nobody asked: \(text.debugDescription)")
            let otherGame = chosen.allSatisfy { $0.contains("578080") || $0.contains("unrelated") }
            check(!otherGame || !watcher.licenceAsked, "another game's licence isn't this one's: \(text.debugDescription)")
            try? fm.removeItem(at: oneGo)
            try? fm.removeItem(at: root)
            if failures > 0 { return }
        }
    }

    // MARK: Rules under random input

    static func randomText(_ random: inout SystemRandomNumberGenerator) -> String {
        let parts = ["\"", "\t", "\n", "\r\n", "eula", "EULA", "_", "0", "7", "99999999999999999999", "-1", "ä", "😀", " ", "{", "}", "1426210", "\\"]
        return (0..<Int.random(in: 0...30, using: &random)).map { _ in parts.randomElement(using: &random)! }.joined()
    }

    static func rules() {
        var random = SystemRandomNumberGenerator()
        let pool = ["a_eula", "b_eula", "c_eula", ""]
        for _ in 0..<20_000 {
            // Whatever localconfig holds: only what's in the shape of an answer comes out, and nothing breaks.
            let text = randomText(&random)
            let answers = SteamLicence.accepted(inLocalConfig: text)
            for key in answers.keys { check(text.lowercased().contains("eula"), "an answer from a text without one: \(text.debugDescription) \(key)") }

            let entries = (0..<Int.random(in: 0...4, using: &random)).map { _ in
                Entry(id: pool.randomElement(using: &random)!, version: Int.random(in: 0...3, using: &random), countries: Bool.random(using: &random) ? nil : "US")
            }
            var given: [String: Int] = [:]
            for id in pool where Bool.random(using: &random) { given[id] = Int.random(in: 0...3, using: &random) }
            var log = Set<String>()
            for id in pool where Int.random(in: 0...3, using: &random) == 0 { log.insert(id) }
            let open = SteamLicence.stillOpen(entries, accepted: given, answeredInLog: log)

            // More answers never open anything; everything answered at its version closes it.
            var more = given
            for id in pool where Bool.random(using: &random) { more[id] = 99 }
            check(!SteamLicence.stillOpen(entries, accepted: more, answeredInLog: log) || open, "an answer more can't open a licence")
            check(!SteamLicence.stillOpen(entries, accepted: given, answeredInLog: log.union(pool)), "everything answered in the log")
            var all: [String: Int] = [:]
            for entry in entries { all[entry.id] = max(all[entry.id] ?? 0, entry.version) }
            check(!SteamLicence.stillOpen(entries, accepted: all, answeredInLog: []), "everything answered at its version")

            // The account's folder is one that's there, or none.
            let ids = (0..<Int.random(in: 0...3, using: &random)).map { _ -> (id: String, mostRecent: Bool) in
                let id = ["76561197972611406", "76561197960265728", "0", "abc", "99999999999999999999", "18446744073709551615", ""].randomElement(using: &random)!
                return (id, Bool.random(using: &random))
            }
            let folders = ["0", "12345678", "39734273", "x", "99999999999999999999"].filter { _ in Bool.random(using: &random) }
            if let folder = SteamLicence.accountFolder(users: ids, folders: folders) {
                check(folders.contains(folder) && folder != "0" && UInt64(folder) != nil, "a folder that isn't an account's: \(folder) of \(folders)")
            }

            // A yes needs its own licence accepted first.
            var answer = SteamLicence.Answer(appID: 480)
            for _ in 0..<Int.random(in: 0...6, using: &random) {
                let id = ["480_eula_0", "480_eula_1", "4800_eula_0", "x", randomText(&random)].randomElement(using: &random)!
                let line = (Bool.random(using: &random) ? "INFO: accepted eula " : "INFO: eulas complete ") + id
                answer.read(line[...])
            }
            check(!answer.complete || !answer.accepted.isEmpty, "complete with nothing accepted")
            check(answer.accepted.allSatisfy { SteamLicence.belongs($0, appID: 480, known: []) }, "accepted what isn't this game's: \(answer.accepted)")
            _ = SteamLicence.logLine(randomText(&random)[...])

            // Nothing but a real yes starts anything again, once.
            let windows = Bool.random(using: &random), ago = Bool.random(using: &random) ? nil : Int.random(in: -3...600, using: &random)
            let on = Bool.random(using: &random), again = Bool.random(using: &random)
            let step = SteamLicence.afterAnswer(windowsSteam: windows, answeredAgo: ago, steamWentOn: on, startedAgain: again)
            if step == .startAgain { check(windows && (ago ?? -1) >= SteamLicence.startAgainAfter && !on && !again, "a new start without its reasons") }
            if !windows || ago == nil || on || again { check(step == .nothing, "nothing to do, and it does something") }
            if failures > 0 { return }
        }
    }

    static func main() {
        beforehand()
        inTheLog()
        answerAsItGrows()
        anyPieces()
        watcherAnyPieces()
        rules()
        print(failures == 0 ? "✓ Steam's licence from its files" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
