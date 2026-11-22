// Steam's licence at a game's first start, without Steam: what's known beforehand, the player's answer
// and the one new start after it: tests/SteamLicenceTest/run.sh
import CoreGraphics
import Foundation

@main
struct SteamLicenceTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A question that turns out to be the licence after it stood on the curtain: the curtain's watch says what it is
    /// at every round, and the curtain takes it only while a question stands and when it's news.
    static func late() {
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        let backdrop = (try? String(contentsOfFile: "Sources/Nightforge/GameBackdrop.swift", encoding: .utf8)) ?? ""
        check(model.contains("GameBackdrop.sayQuestion(questionLook)"), "the curtain's watch looks at every round")
        check(backdrop.contains("guard state.steamAsks, state.question != look else { return }"), "nothing on the curtain: nothing to say; said already: once")
    }

    /// The bar goes by the pad in the player's hand.
    static func inHand() {
        check(SteamLicence.pad(inHandHasTouchpad: true) == .touchpad, "a DualSense in hand: the touchpad")
        check(SteamLicence.pad(inHandHasTouchpad: false) == .stick, "an Xbox pad in hand, a DualSense beside it: the stick")
        check(SteamLicence.pad(inHandHasTouchpad: nil) == .none, "no pad: the mouse")
        let model = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
        check(model.contains("GCController.current?.extendedGamepad") && model.contains("SteamLicence.pad(inHandHasTouchpad:")
              && !model.contains("pads.contains { Touchpad($0) != nil }"), "the model asks for the pad last used, not for any")
    }

    static func main() {
        inHand()
        late()
        beforehand()
        localConfig()
        account()
        answer()
        afterAnswer()
        bar()
        seam()
        print(failures == 0 ? "✓ Steam's licence" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    typealias Entry = SteamLicence.Entry

    static func beforehand() {
        let twoGames = Entry(id: "1426210_eula_1", version: 0)
        func open(_ entries: [Entry], _ accepted: [String: Int] = [:], log: Set<String> = []) -> Bool {
            SteamLicence.stillOpen(entries, accepted: accepted, answeredInLog: log)
        }
        check(!open([]), "a game without one has none open")
        check(open([twoGames]), "no key: not answered")
        check(!open([twoGames], ["1426210_eula_1": 0]), "\"0\" is the answer to a licence without a version")
        check(open([Entry(id: "a_eula", version: 4)], ["a_eula": 3]), "an older answer doesn't answer a newer version")
        check(!open([Entry(id: "a_eula", version: 4)], ["a_eula": 4]), "the version answered")
        check(!open([Entry(id: "108600_eula_1", version: 11)], ["108600_eula_1": 12]), "a later answer holds as well")
        check(!open([Entry(id: "480_eula_1", version: 0, countries: "US")]), "one for some countries isn't announced")
        check(open([Entry(id: "480_eula_1", version: 0, countries: "US"), Entry(id: "480_eula_0", version: 0)]), "the other one still is")
        check(!open([twoGames], log: ["1426210_eula_1"]), "answered in this session: localconfig only has it later")
        check(!open([Entry(id: "", version: 0)]), "an entry without a name is nothing to announce")
        let unnamed = Entry(id: "create_me", version: 0)
        check(!open([unnamed]), "named without \"eula\": its answer can't be found, so no word at every start")
        check(open([unnamed, twoGames]), "the other one still says it")
        check(!open([unnamed, Entry(id: "a_eula", version: 1)], ["a_eula": 1]), "the other answered: nothing left to say")
        check(open([Entry(id: "480_EULA", version: 0)]), "the word in any case, as localconfig is read")
    }

    static func localConfig() {
        let text = """
        "UserLocalConfigStore"\r
        {\r
        \t\t"480_eula_0"\t\t"0"\r
        \t\t"203160_eula"\t\t"4"\r
        \t\t"eula_48240"\t\t"2"\r
        \t\t"OtherSetting"\t\t"7"\r
        \t\t"note_eula"\t\t"not a number"\r
        }\r
        """
        let accepted = SteamLicence.accepted(inLocalConfig: text)
        check(accepted == ["480_eula_0": 0, "203160_eula": 4, "eula_48240": 2], "only the licences, with any form of id: \(accepted)")
        check(SteamLicence.accepted(inLocalConfig: "").isEmpty, "an empty file")
    }

    static func account() {
        let remembered = "76561197972611406"
        let folder = "12345678"
        func account(_ id: String?, _ folders: [String]) -> String? { SteamLicence.accountFolder(remembered: id, folders: folders) }
        check(account(remembered, ["0", folder]) == folder, "the account Steam remembers, not the folder 0")
        check(account(remembered, ["39734273", folder]) == folder, "of two")
        check(account(remembered, ["39734273"]) == nil, "its folder isn't there: nothing to tell")
        check(account(nil, ["0", folder]) == folder, "none remembered: the only account there is")
        check(account(nil, ["39734273", folder]) == nil, "two and none remembered: nothing to tell")
        check(account("abc", []) == nil, "nonsense")
    }

    static func answer() {
        let app = 1_426_210
        func read(_ lines: [String], known: Set<String> = []) -> Bool {
            var answer = SteamLicence.Answer(appID: app)
            answer.known = known
            for line in lines { answer.read(line[...]) }
            return answer.complete
        }
        let accepted = "[2026-11-09 06:31:05] SteamUI: INFO: accepted eula 1426210_eula_1"
        let complete = "[2026-11-09 06:31:05] SteamUI: INFO: eulas complete 1426210_eula_1"
        check(read([accepted, complete]), "a yes")
        check(!read([complete]), "complete without a yes isn't one")
        check(!read([accepted]), "with a second licence still to come")
        check(!read(["[…] SteamUI: INFO: prompt for eula 1426210_eula_1"]), "being asked isn't answering: a No or a closed window logs nothing")
        check(!read(["SteamUI: INFO: accepted eula 578080_eula_1", "SteamUI: INFO: eulas complete 578080_eula_1"]), "another game's")
        check(!read(["SteamUI: INFO: accepted eula 11426210_eula_1", "SteamUI: INFO: eulas complete 11426210_eula_1"]), "a longer app ID isn't this one")
        check(read(["SteamUI: INFO: accepted eula 231430_eula_0", "SteamUI: INFO: eulas complete 231430_eula_0"], known: ["231430_eula_0"]), "the ID of another app, as appinfo names it")
        check(read(["INFO: accepted eula eula_1426210", "INFO: eulas complete eula_1426210"]), "the old form")
        check(read(["INFO: accepted eula create_me", "INFO: eulas complete create_me"], known: ["create_me"]), "Steam's log still tells that one's yes")
        check(!read(["SteamBrowser: INFO: said accepted eulaz 1426210_eula_1"]), "other lines")
        check(SteamLicence.logLine("INFO: accepted eula ") == nil, "a line without an id")
    }

    static func afterAnswer() {
        typealias Step = SteamLicence.AfterAnswer
        let after = SteamLicence.startAgainAfter
        let latest = SteamLicence.startAgainAtLatest
        func step(windows: Bool = true, ago: Int?, on: Bool = false, again: Bool = false, stored: Bool = true) -> Step {
            SteamLicence.afterAnswer(windowsSteam: windows, answeredAgo: ago, steamWentOn: on, startedAgain: again, answerStored: stored)
        }
        check(step(ago: nil) == .nothing, "no yes, no new start: a No or B never gets here")
        check(step(ago: 0) == .wait && step(ago: after - 1) == .wait, "Steam gets a moment")
        check(step(ago: after) == .startAgain, "then the start once more")
        check(step(ago: after + 60) == .startAgain, "at the next look, however late")
        check(step(ago: after, again: true) == .nothing, "once per start")
        check(step(ago: after, on: true) == .nothing, "not when Steam went on by itself")
        check(step(windows: false, ago: after) == .nothing, "Steam for Mac goes on by itself")
        check(step(ago: after, stored: false) == .wait && step(ago: latest - 1, stored: false) == .wait,
              "not while Steam's record hasn't got the answer: it would only show the licence again")
        check(step(ago: latest, stored: false) == .startAgain, "by the quickest start seen to work it goes out anyway")
        check(step(ago: latest, again: true, stored: false) == .nothing, "and still once")
        check(latest <= 25, "no later than a new start is known to work")

        func yes(_ then: Bool?, _ now: Bool?) -> Bool { SteamLicence.answeredInConfig(openWhenAsked: then, openNow: now) }
        check(yes(true, false), "open when asked, not any more: stored")
        check(!yes(true, true), "still open: a No, a closed window, or not written yet")
        check(!yes(false, false), "not open when asked: this record can't tell, as for one limited to some countries")
        check(!yes(nil, false) && !yes(true, nil) && !yes(nil, nil), "a record that can't be read says nothing")
    }

    static func bar() {
        func how(_ pad: SteamLicence.Pad, on: Bool = true, click: Bool = true) -> SteamLicence.Answering {
            SteamLicence.answering(pad: pad, pointerOn: on, mayClick: click)
        }
        check(how(.none) == .mouse, "no controller")
        check(how(.touchpad) == .touchpad && how(.stick) == .stick, "the pad there is")
        check(how(.touchpad, click: false) == .mouse, "without Accessibility a click never arrives")
        check(how(.stick, on: false) == .mouse, "the pointer switched off")
    }

    static func seam() {
        let curtain = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let window = CGRect(x: 406, y: 191, width: 700, height: 600)
        check(SteamLicence.seam(window: window, curtain: curtain) == window, "on the main screen")
        let other = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        check(SteamLicence.seam(window: CGRect(x: -1500, y: 200, width: 700, height: 500), curtain: other)
                == CGRect(x: 420, y: 300, width: 700, height: 500), "on another screen, in the curtain's coordinates")
        check(SteamLicence.seam(window: window, curtain: other) == nil, "not on this screen")
        check(SteamLicence.seam(window: CGRect(x: 10, y: 10, width: 50, height: 50), curtain: curtain) == nil, "too small to be the question")
        check(SteamLicence.windowToFrame(frontToBack: [7, 3]) == 7, "the frontmost: the licence over the main window")
        check(SteamLicence.windowToFrame(frontToBack: []) == nil, "none yet")
    }
}
