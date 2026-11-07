// Checks what each store shows in each state in both launcher menus (LauncherState), how a client's
// sign-in is read from its files, and that the sign-in has no field of Nightforge's own:
// tests/LauncherMenuTest/run.sh
import AppKit

@main
struct LauncherMenuTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Facts = LauncherState.Facts

    static func main() {
        TestDefaults.useWorkFolder()
        notSignedIn()
        signedIn()
        signingIn()
        signedOut()
        unreachable()
        battleNetWithoutClient()
        counting()
        padIDs()
        steamName()
        battleNetLog()
        battleNetFolder()
        noFieldOfOurOwn()
        print(failures == 0 ? "✓ LauncherMenu" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func notSignedIn() {
        for provider in Provider.allCases {
            let state = LauncherState(provider, facts: Facts())
            check(state.account == .notSignedIn, "\(provider): nothing known is not signed in")
            check(state.status == L10n.t("Not signed in"), "\(provider): the card says so")
            check(state.menuStatus == L10n.t("Not signed in"), "\(provider): the menu says so")
            check(state.action == .signIn && state.quickAction == .signIn, "\(provider): both menus open its sign-in")
            check(state.actionLabel == L10n.t("Sign In to %@", provider.label), "\(provider): the card's button names the store")
            check(state.shortLabel(.signIn) == L10n.t("Sign In"), "\(provider): the row's button is short")
            check(!state.isSignedIn, "\(provider): doesn't count in the pill")
            check(!state.detail.isEmpty, "\(provider): the card says what it brings")
        }
        let battleNet = LauncherState(.battlenet, facts: Facts()).detail
        check(battleNet == L10n.t("Shows what Battle.net for Mac has installed: WoW, Hearthstone and more. Overwatch runs through Steam."),
              "Battle.net says what's there and where Overwatch is")
        check(!battleNet.contains("Diablo"), "Battle.net promises no Windows game")
    }

    static func signedIn() {
        for provider in Provider.allCases {
            let state = LauncherState(provider, facts: Facts(connected: true, signedIn: true, name: "Lord", games: 12))
            check(state.account == .signedIn(name: "Lord"), "\(provider): signed in")
            check(state.status == L10n.t("Signed in – %@", "Lord"), "\(provider): the card names the account")
            check(state.detail == L10n.t("%ld games in your library", 12), "\(provider): and counts the games")
            check(state.menuStatus == L10n.t("Signed in – %@", L10n.t("%ld games", 12)), "\(provider): the menu counts them")
            check(state.action == .manage, "\(provider): the card manages it")
            check(state.quickAction == nil, "\(provider): the row has no button")
            check(state.isSignedIn, "\(provider): counts in the pill")
        }
        let noName = LauncherState(.battlenet, facts: Facts(connected: true, signedIn: true, games: 1))
        check(noName.status == L10n.t("Signed in"), "no name, no dash")
        check(noName.detail == L10n.t("1 game in your library"), "one game")
        check(noName.menuStatus == L10n.t("Signed in – %@", L10n.t("1 game")), "one game in the menu")
    }

    static func signingIn() {
        for provider in Provider.allCases {
            for facts in [Facts(signingIn: true), Facts(signingIn: true, connected: true, signedIn: true, games: 3)] {
                let state = LauncherState(provider, facts: facts)
                check(state.account == .signingIn, "\(provider): its sign-in comes first")
                check(state.status == L10n.t("Waiting for sign-in …"), "\(provider): the card waits")
                check(state.action == nil && state.quickAction == nil, "\(provider): nothing to press meanwhile")
            }
        }
    }

    static func signedOut() {
        var ended = StoreSync()
        ended.state = .signedOut
        for facts in [Facts(connected: true, signedIn: true, sync: ended, games: 4), Facts(connected: true, signedIn: false, games: 4)] {
            let state = LauncherState(.epic, facts: facts)
            check(state.account == .signedOut, "the store's end, or a lost sign-in")
            check(state.status == L10n.t("Signed out"), "the card says so")
            check(state.menuStatus == L10n.t("Signed out – %@", L10n.t("%ld games", 4)), "the games stay")
            check(state.action == .signInAgain && state.quickAction == .signInAgain, "both menus sign in again at once")
            check(state.actionLabel == L10n.t("Sign In Again"), "the card's button")
            check(!state.isSignedIn, "not in the pill")
        }
    }

    static func unreachable() {
        var failed = StoreSync()
        failed.state = .failed("No connection")
        let state = LauncherState(.gog, facts: Facts(connected: true, signedIn: true, sync: failed, games: 7))
        check(state.account == .unreachable(failed), "the last update failed")
        check(state.status == L10n.t("Not reachable"), "the card says so")
        check(state.detail == StoreSyncText.text(provider: .gog, sync: failed), "in the banner's words")
        check(state.menuStatus == L10n.t("Not reachable – %@", L10n.t("%ld games", 7)), "the games stay")
        check(state.action == .manage && state.quickAction == .retry, "the card manages, the row tries again")
        check(state.isSignedIn, "still signed in")
        var busy = StoreSync()
        busy.state = .syncing
        check(LauncherState(.gog, facts: Facts(connected: true, signedIn: true, name: "n", sync: busy)).account == .signedIn(name: "n"),
              "updating is signed in, nothing shows")
    }

    static func battleNetWithoutClient() {
        let state = LauncherState(.battlenet, facts: Facts(clientMissing: true))
        check(state.account == .noClient, "no client")
        check(state.status == L10n.t("Not installed"), "the card says so")
        check(state.menuStatus == L10n.t("Not installed"), "the menu says so")
        check(state.action == .getClient && state.quickAction == .getClient, "both lead to Blizzard's page")
        check(state.actionLabel == L10n.t("Get %@", "Battle.net"), "the card's button")
        check(BattleNetClient.downloadPage.host == "download.battle.net", "Blizzard's own page")
        check(LauncherState(.battlenet, facts: Facts(signingIn: true, clientMissing: true)).account == .signingIn, "a sign-in on its way wins")
    }

    static func counting() {
        let states = [LauncherState(.steam, account: .signedIn(name: nil), games: 1), LauncherState(.epic, account: .signedOut),
                      LauncherState(.gog, account: .unreachable(StoreSync())), LauncherState(.battlenet)]
        check(states.filter(\.isSignedIn).count == 2, "the pill counts what's signed in")
        check(Provider.allCases.map { LauncherState($0).id } == ["steam", "epic", "gog", "battlenet"], "both menus in the same order")
        check(Provider.allCases.map { LauncherState($0).letter } == ["S", "E", "G", "B"], "plain type, no logos")
    }

    static func padIDs() {
        let ids = Provider.allCases.flatMap { [LauncherState.cardID($0), LauncherState.rowID($0)] }
        check(Set(ids).count == 8, "a card and a row of each store, none the same")
        check(Route.launchers.parent == .home && Route.launchers.level == .home, "the cards belong to Home, back leads there")
        check(!Route.launchers.isDetail, "they're no game's page")
    }

    static func steamName() {
        let users = VDF.parse(#"""
        "users"
        {
            "76561198000000001"
            {
                "AccountName"    "login_name"
                "PersonaName"    "Lord Hayne"
                "MostRecent"     "1"
            }
            "76561198000000002"
            {
                "AccountName"    "other_login"
                "PersonaName"    "Other"
                "MostRecent"     "0"
            }
        }
        """#)?["users"]
        check(SteamLogin.personaName(users: users) == "Lord Hayne", "the name Steam shows, of the account it remembers")
        check(SteamLogin.personaName(users: nil) == nil, "no accounts, no name")
        let empty = VDF.parse(#""users" { "1" { "AccountName" "a" "PersonaName" "" "MostRecent" "1" } }"#)?["users"]
        check(SteamLogin.personaName(users: empty) == nil, "an empty name isn't one")
    }

    /// Client starts on a real Mac (6.11. and 7.11.), only the lines of these two kinds, in their order.
    /// What sits between them (mail address, country) never goes into a test.
    static func line(_ text: String) -> String { "D 2026-11-07 19:22:31.1 [x] {Main} \(text)\n" }
    static func page(_ state: String) -> String { line("UAuth: browser state changed: \(state)") }
    static func status(_ state: String) -> String { line("UAuth: status changed: \(state)") }
    static func account(_ state: String) -> String { line("[AccountManager] {Main} Account manager state has changed to: \(state)") }

    /// 6.11. 18:18: the sign-in page, closed without signing in.
    static let neverThrough = page("Login")
    /// 7.11. 19:22: signed in on the page. After "Done" it loads a new sign-in page behind it, and the
    /// last page state is "None"; "Incomplete" is the client shutting down.
    static let throughThePage = page("LoginCredential") + status("RequestingToken") + page("None") + status("ReceivedToken")
        + status("Ready") + page("Done") + page("None") + page("LoginCredential") + account("Loading") + account("Ready")
        + page("None") + account("Incomplete")
    /// 7.11. 19:25: the start after it, signed in from memory: no sign-in page at all.
    static let remembered = account("Loading") + account("Ready")
    /// 6.11. 20:24: "stay signed in" off, so the next start asks again.
    static let asksAgain = page("LoginCredential")
    /// Signed out in the client while it runs: its page asks after the account was there.
    static let signedOutWhileRunning = remembered + page("Login")

    static func battleNetLog() {
        check(BattleNetClient.signedIn(log: neverThrough) == false, "the page asked, no one signed in")
        check(BattleNetClient.signedIn(log: throughThePage) == true, "signed in on the page, whatever page states follow")
        check(BattleNetClient.signedIn(log: remembered) == true, "a remembered sign-in shows no page and counts")
        check(BattleNetClient.signedIn(log: asksAgain) == false, "the page asks again")
        check(BattleNetClient.signedIn(log: signedOutWhileRunning) == false, "the page asking after the account was there")
        check(BattleNetClient.signedIn(log: account("Loading")) == nil, "a start still loading says nothing")
        check(BattleNetClient.signedIn(log: line("[Main] {Main} Starting")) == nil, "the short log beside a start says nothing")
        check(BattleNetClient.signedIn(log: "") == nil, "an empty log says nothing")
    }

    static func battleNetFolder() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ text: String) {
            try? text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        check(!BattleNetClient.isSignedIn(logs: folder), "no logs: not signed in")
        check(!BattleNetClient.isSignedIn(logs: folder.appendingPathComponent("gone")), "no folder: not signed in")
        // Each start writes a short log and its real one, a few hundred ms apart.
        write("battle.net-20261106T202443.536327.log", line("[Main] {Main} Starting"))
        write("battle.net-20261106T202443.841847.log", asksAgain)
        write("libcef-20261106T202445.137163.log", account("Ready"))
        check(!BattleNetClient.isSignedIn(logs: folder), "the start that asked and nothing more")
        write("battle.net-20261107T192229.617391.log", line("[Main] {Main} Starting"))
        write("battle.net-20261107T192230.291231.log", throughThePage)
        check(BattleNetClient.isSignedIn(logs: folder), "signed in on the page (the live test of 7.11. 20:24)")
        write("battle.net-20261107T192521.941521.log", line("[Main] {Main} Starting"))
        write("battle.net-20261107T192522.248808.log", remembered)
        check(BattleNetClient.isSignedIn(logs: folder), "the restart after it, from memory")
        // A new start that hasn't got to its account yet: the one before still counts.
        write("battle.net-20261107T203000.100000.log", account("Loading"))
        check(BattleNetClient.isSignedIn(logs: folder), "a start still loading leaves the last word to the one before")
        write("battle.net-20261107T203100.100000.log", asksAgain)
        check(!BattleNetClient.isSignedIn(logs: folder), "the newest start that says so counts")
    }

    /// Nightforge never sees a password: the sign-in has no field of its own, wherever it opens.
    static func noFieldOfOurOwn() {
        let files = ["SignInStage", "LauncherViews", "Launchers", "EpicSignIn", "GOGSignIn"]
        for file in files {
            guard let text = try? String(contentsOfFile: "Sources/Nightforge/\(file).swift", encoding: .utf8) else {
                check(false, "\(file).swift can be read")
                continue
            }
            for field in ["SecureField", "TextField", "NSSecureTextField", "evaluateJavaScript(\"document.getElement", "keychain", "Keychain"] {
                check(!text.contains(field), "\(file) has no \(field)")
            }
        }
        let epic = (try? String(contentsOfFile: "Sources/Nightforge/EpicSignIn.swift", encoding: .utf8)) ?? ""
        check(epic.components(separatedBy: "evaluateJavaScript").count == 2, "Epic's page is read in one place")
        check(epic.contains("url.path == \"/id/api/redirect\""), "and only on its last page")
        check(EpicSignIn.signInURL.host == "www.epicgames.com" && GOGSignIn.signInURL.host == "auth.gog.com", "the stores' own pages")
    }
}
