import CoreGraphics
import Foundation

/// Steam's licence at a game's first start: what Nightforge can know beforehand, how it sees the player's
/// answer, and what happens after it. Nightforge never answers it and never writes any of this. Measured on
/// 9.11.2026 in the logs of both Steams:
/// - appinfo's `common/eulas` names the licences, each with an `id` and maybe a `version`. Saying yes
///   stores `"<id>" "<version>"` in userdata/<account>/config/localconfig.vdf, 0 without a version: 12 of 12
///   keys, and Steam's own code hands over (appID, id, version). So "0" is an answer too, and no key is none.
/// - That rule named exactly the 12 of 24 started games Steam asked about.
/// - The Windows Steam under Wine never goes on after the answer: no "continues with user response", in
///   7 of 7. Only a new -applaunch did (25 s to 12 min later, in the same Steam at 25 s and 43 s). Steam
///   for Mac goes on in the same second, 5 of 5.
enum SteamLicence {
    struct Entry: Equatable {
        var id: String
        /// 0 when appinfo gives none.
        var version: Int
        /// Only for those countries. Steam didn't ask a German account for Spacewar's US-only one.
        var countries: String?
    }

    /// Whether Steam will show a licence at this start, as far as can be told. Only ever a word on the
    /// loading screen: Steam decides in its client, and the frame comes when it asks, said or not.
    /// One limited to some countries isn't counted, the player's country being unknown here.
    /// `answeredInLog`: the log has a yes a moment before localconfig does (`answeredInConfig`).
    static func stillOpen(_ entries: [Entry], accepted: [String: Int], answeredInLog: Set<String>) -> Bool {
        entries.contains { entry in
            guard entry.countries == nil, inConfigLines(entry.id), !answeredInLog.contains(entry.id) else { return false }
            guard let answered = accepted[entry.id] else { return true }
            return answered < entry.version
        }
    }

    /// Whether a licence's answer can be found at all, only localconfig's lines with "eula" being looked at.
    /// One named otherwise (America's Army 3 Dedicated Server's "create_me", 1 of the 77 in appinfo on 9.11.) would count as open at
    /// every start, so it isn't announced: better no word than a wrong one each time.
    static func inConfigLines(_ text: some StringProtocol) -> Bool { text.range(of: "eula", options: .caseInsensitive) != nil }

    /// The licences answered in a localconfig.vdf: only its lines with "eula" are looked at.
    static func accepted(inLocalConfig text: String) -> [String: Int] {
        var accepted: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) where inConfigLines(line) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count == 5, let version = Int(parts[3]) else { continue }
            accepted[String(parts[1])] = version
        }
        return accepted
    }

    /// The offset between a SteamID64 and the account number userdata's folders go by.
    private static let steamIDBase: UInt64 = 76_561_197_960_265_728

    /// The folder in userdata of the account Steam remembers (`SteamLogin.rememberedAccount`, by its SteamID),
    /// or the only account there is. Nil when it can't be told, and then nothing is announced.
    static func accountFolder(remembered: String?, folders: [String]) -> String? {
        let accounts = folders.filter { (UInt64($0) ?? 0) != 0 }
        if let remembered, let id = UInt64(remembered), id > steamIDBase {
            let folder = String(id - steamIDBase)
            return accounts.contains(folder) ? folder : nil
        }
        return accounts.count == 1 ? accounts[0] : nil
    }

    /// What Steam's interface logs in webhelper_js.txt, "SteamUI: INFO: accepted eula <id>".
    enum LogLine: Equatable {
        case accepted(String)
        case complete(String)
    }

    static func logLine(_ line: Substring) -> LogLine? {
        func id(after marker: String) -> String? {
            guard let range = line.range(of: marker) else { return nil }
            let id = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
        if let id = id(after: "INFO: accepted eula ") { return .accepted(id) }
        if let id = id(after: "INFO: eulas complete ") { return .complete(id) }
        return nil
    }

    /// One of this game's licences: named in appinfo (`known`), or by the usual `<appID>_…`, `…_<appID>`.
    static func belongs(_ id: String, appID: Int, known: Set<String>) -> Bool {
        known.contains(id) || id.hasPrefix("\(appID)_") || id.hasSuffix("_\(appID)")
    }

    /// The player's yes, as Steam logs it: each licence accepted, then "eulas complete" for the last.
    /// A No logs nothing of the kind, nor does closing the window.
    struct Answer {
        let appID: Int
        var known: Set<String> = []
        private(set) var accepted: Set<String> = []
        private(set) var complete = false

        init(appID: Int) { self.appID = appID }

        mutating func read(_ line: Substring) {
            switch SteamLicence.logLine(line) {
            case .accepted(let id)? where belongs(id, appID: appID, known: known):
                accepted.insert(id)
            case .complete(let id)? where accepted.contains(id):
                complete = true
            default:
                break
            }
        }
    }

    /// Whether Steam has stored a yes: its record had the licence open when it asked and doesn't now. Its
    /// configstore_log says "Flushed store 'userlocal'" 0 to 1 s after a yes, 7 of 7 (9.11.). A No or a closed
    /// window stores nothing. Nil, unknown, is no yes: a licence for some countries isn't in `stillOpen`.
    static func answeredInConfig(openWhenAsked: Bool?, openNow: Bool?) -> Bool {
        openWhenAsked == true && openNow == false
    }

    enum AfterAnswer: Equatable { case nothing, wait, startAgain }

    /// How long Steam gets to go on by itself after the yes, with its answer stored. Steam for Mac takes
    /// less than a second, the Windows Steam never did (7 of 7).
    static let startAgainAfter = 5

    /// The new start goes out by now in any case, the answer seen in Steam's record or not: the quickest
    /// new start seen to work came 25 s after a yes.
    static let startAgainAtLatest = 25

    /// After the player's yes. The Windows Steam is sent the start once more, the one the player asked
    /// for: once per start, and only if Steam hasn't moved on by itself. Steam for Mac always does.
    /// It waits for `answerStored`, there being one shot: a start Steam takes before it knows the answer
    /// only shows the licence again (asked and unanswered, a new start was taken at once, 2 of 2).
    static func afterAnswer(windowsSteam: Bool, answeredAgo: Int?, steamWentOn: Bool, startedAgain: Bool,
                            answerStored: Bool) -> AfterAnswer {
        guard windowsSteam, let answeredAgo, !steamWentOn, !startedAgain else { return .nothing }
        return answeredAgo >= (answerStored ? startAgainAfter : startAgainAtLatest) ? .startAgain : .wait
    }

    /// How the player answers, for the bar on the curtain.
    enum Answering: Equatable { case mouse, touchpad, stick }
    enum Pad: Equatable { case none, touchpad, stick }

    /// With the mouse unless the pad's pointer can click in Steam's window: that needs the setting and
    /// macOS's Accessibility permission, without which a click never arrives.
    static func answering(pad: Pad, pointerOn: Bool, mayClick: Bool) -> Answering {
        guard pointerOn, mayClick else { return .mouse }
        switch pad {
        case .none: return .mouse
        case .touchpad: return .touchpad
        case .stick: return .stick
        }
    }

    /// Where the seam goes on the curtain (`curtain`, both in screen coordinates, y down), in the
    /// curtain's own. Nil for a window that isn't on it, or too small to be the question.
    static func seam(window: CGRect, curtain: CGRect) -> CGRect? {
        let shown = window.intersection(curtain)
        guard !shown.isNull, shown.width >= 200, shown.height >= 100 else { return nil }
        return window.offsetBy(dx: -curtain.minX, dy: -curtain.minY)
    }

    /// The window to frame: the frontmost of Steam's, as the licence stands over its main window.
    static func windowToFrame(frontToBack windows: [Int]) -> Int? { windows.first }
}

/// Steam's own files, read only: whether a licence is open before the start, and the player's answer during it.
enum SteamLicenceFiles {
    /// How far back the log is searched for an answer localconfig doesn't have yet.
    private static let tailSize: UInt64 = 512 * 1024

    /// Whether Steam will ask at this start (`SteamLicence.stillOpen`). False whenever it can't be told.
    static func stillOpen(entries: [SteamLicence.Entry], steamRoot: URL) -> Bool {
        guard !entries.isEmpty, let config = localConfig(steamRoot: steamRoot),
              let data = try? Data(contentsOf: config)
        else { return false }
        return SteamLicence.stillOpen(entries, accepted: SteamLicence.accepted(inLocalConfig: String(decoding: data, as: UTF8.self)),
                                      answeredInLog: answeredInLog(steamRoot: steamRoot))
    }

    /// Whether one of these stands open in Steam's own record, read just now. Nil when it can't be told, as
    /// with one that can't be found there: the others answered wouldn't say it was.
    static func openInConfig(entries: [SteamLicence.Entry], steamRoot: URL) -> Bool? {
        guard !entries.isEmpty, entries.allSatisfy({ SteamLicence.inConfigLines($0.id) }),
              let config = localConfig(steamRoot: steamRoot), let data = try? Data(contentsOf: config)
        else { return nil }
        return SteamLicence.stillOpen(entries, accepted: SteamLicence.accepted(inLocalConfig: String(decoding: data, as: UTF8.self)),
                                      answeredInLog: [])
    }

    private static func localConfig(steamRoot: URL) -> URL? {
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: userdata.path)) ?? [])
        return SteamLicence.accountFolder(remembered: SteamLogin.rememberedAccount(steamRoot: steamRoot), folders: folders)
            .map { userdata.appendingPathComponent("\($0)/config/localconfig.vdf") }
    }

    private static func answeredInLog(steamRoot: URL) -> Set<String> {
        let log = steamRoot.appendingPathComponent("logs/webhelper_js.txt")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tailSize ? size - tailSize : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        var answered: Set<String> = []
        for line in tail.split(whereSeparator: \.isNewline) {
            if case .accepted(let id)? = SteamLicence.logLine(line) { answered.insert(id) }
        }
        return answered
    }
}

/// Follows Steam's interface log during a start, for the player's answer to its licence: only what's
/// written after the start began counts. Whole lines, as Steam writes Windows line ends (LaunchWatcher).
struct SteamLicenceLog {
    private let file: URL
    private var offset: UInt64
    private(set) var answer: SteamLicence.Answer

    init(steamRoot: URL, appID: Int) {
        file = steamRoot.appendingPathComponent("logs/webhelper_js.txt")
        offset = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
        answer = SteamLicence.Answer(appID: appID)
    }

    mutating func know(_ ids: Set<String>) { answer.known = ids }

    /// Steam asked once more after a yes: that yes doesn't answer it.
    mutating func askedAgain() {
        let known = answer.known
        answer = SteamLicence.Answer(appID: answer.appID)
        answer.known = known
    }

    /// True once the player has said yes to all of it.
    mutating func answered() -> Bool {
        guard !answer.complete, let handle = try? FileHandle(forReadingFrom: file) else { return answer.complete }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }  // Steam started a fresh log
        try? handle.seek(toOffset: offset)
        let read = (try? handle.readToEnd()) ?? Data()
        guard let lastLine = read.lastIndex(of: 0x0A) else { return false }
        let data = read[read.startIndex...lastLine]
        offset += UInt64(data.count)
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) { answer.read(line) }
        return answer.complete
    }
}
