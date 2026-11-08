// Every state a launcher can be in (every combination of LauncherState.Facts), against what the two menus may
// show: a press always has an answer, the small menu never promises more than the card, the words are there in
// both languages, and Battle.net never links itself against the player's wish:
// tests/LauncherStatesMatrixTest/run.sh
import Foundation

@main
struct LauncherStatesMatrixTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()
        var combinations = 0
        for language in ["english", "german"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.storageKey)
            for provider in Provider.allCases {
                for bits in 0..<(1 << 5) {
                    for games in [0, 1, 7] {
                        for failed in [false, true] {
                            var facts = LauncherState.Facts(signingIn: bits & 1 != 0, connected: bits & 2 != 0, signedIn: bits & 4 != 0,
                                                            clientMissing: bits & 8 != 0, name: bits & 16 != 0 ? "Jörg" : nil, games: games)
                            if failed { facts.sync = failedSync() }
                            combinations += 1
                            rules(LauncherState(provider, facts: facts), facts: facts, language: language)
                        }
                    }
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        linking()
        ids()
        print(failures == 0 ? "✓ Launcher states (\(combinations) states)" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func failedSync() -> StoreSync {
        var sync = StoreSync()
        sync.state = .failed(L10n.t("Not reachable"))
        return sync
    }

    static func rules(_ state: LauncherState, facts: LauncherState.Facts, language: String) {
        let name = "\(state.provider) \(state.account) \(language)"
        for (label, text) in [("status", state.status), ("menuStatus", state.menuStatus), ("actionLabel", state.actionLabel)] {
            check(!text.isEmpty && !text.contains("%"), "\(label) of \(name): “\(text)”")
        }
        if case .signingIn = state.account {
            check(state.action == nil && state.quickAction == nil, "being signed in has no button: \(name)")
            check(!state.isSignedIn, "and doesn't count yet: \(name)")
        } else {
            check(state.action != nil, "every other state has its button: \(name)")
        }
        if state.isSignedIn { check(facts.connected && facts.signedIn && !facts.clientMissing, "signed in means just that: \(name)") }
        if let quick = state.quickAction {
            check(!state.shortLabel(quick).isEmpty && !state.shortLabel(quick).contains("%"), "its short button: \(name)")
        }
        if facts.signingIn {
            if case .signingIn = state.account {} else { check(false, "a sign-in under way goes first: \(name)") }
        }
        if case .signedIn = state.account { check(state.action == .manage && state.quickAction == nil, "signed in: Manage, nothing in the small menu: \(name)") }
        if case .noClient = state.account { check(state.action == .getClient, "no client: Get it: \(name)") }
    }

    static func linking() {
        check(BattleNetStore.links(linked: true, unlinked: false, clientSignedIn: false), "linked stays linked")
        check(BattleNetStore.links(linked: false, unlinked: false, clientSignedIn: true), "signed in on this Mac: comes by itself")
        check(!BattleNetStore.links(linked: false, unlinked: true, clientSignedIn: true), "the player disconnected: never by itself again")
        check(!BattleNetStore.links(linked: false, unlinked: false, clientSignedIn: false), "nothing to go on: not linked")
    }

    static func ids() {
        let cards = Set(Provider.allCases.map(LauncherState.cardID))
        let rows = Set(Provider.allCases.map(LauncherState.rowID))
        check(cards.count == Provider.allCases.count && rows.count == Provider.allCases.count && cards.isDisjoint(with: rows), "a pad name per card and row")
        for provider in Provider.allCases {
            check(LauncherState(provider).letter.count == 1, "\(provider): one letter")
        }
    }
}
