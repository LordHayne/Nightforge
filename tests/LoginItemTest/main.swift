// Checks the switch for opening at login (LoginItem) against a stand-in for macOS, which never
// touches the real login items: tests/LoginItemTest/run.sh
import Foundation
import ServiceManagement

final class StandIn: LoginService {
    var status: SMAppService.Status = .notRegistered
    var fails = false
    var after: SMAppService.Status = .enabled
    var unregistered = 0
    struct Refused: Error {}

    func register() throws {
        if fails { throw Refused() }
        status = after
    }

    func unregister() throws {
        unregistered += 1
        if fails { throw Refused() }
        status = .notRegistered
    }
}

@main
struct LoginItemTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        check(LoginItem.state(of: .notRegistered) == .off, "not registered: off")
        check(LoginItem.state(of: .notFound) == .off, "macOS can't find it: off")
        check(LoginItem.state(of: .enabled) == .on, "enabled: on")
        check(LoginItem.state(of: .requiresApproval) == .needsApproval, "switched off in macOS's settings: says so")

        let service = StandIn()
        check(LoginItem.set(true, service: service) == .on && service.status == .enabled, "turning it on registers")
        check(LoginItem.set(false, service: service) == .off && service.status == .notRegistered, "turning it off unregisters")

        service.after = .requiresApproval
        check(LoginItem.set(true, service: service) == .needsApproval, "macOS wants it confirmed first")

        let refused = StandIn()
        refused.fails = true
        var said = ""
        check(LoginItem.set(true, service: refused, note: { said = $0 }) == .off, "a refusal leaves it off")
        check(said.contains("turn it on"), "and says why")

        // "Remove Nightforge completely": against the stand-in only.
        for status in [SMAppService.Status.enabled, .requiresApproval] {
            let registered = StandIn()
            registered.status = status
            LoginItem.forget(service: registered)
            check(registered.unregistered == 1 && registered.status == .notRegistered, "the removal takes it out of macOS's login items: \(status)")
        }
        for status in [SMAppService.Status.notRegistered, .notFound] {
            let absent = StandIn()
            absent.status = status
            LoginItem.forget(service: absent)
            check(absent.unregistered == 0, "nothing registered: macOS isn't asked: \(status)")
        }
        let stubborn = StandIn()
        stubborn.status = .enabled
        stubborn.fails = true
        LoginItem.forget(service: stubborn)
        check(stubborn.unregistered == 1, "a refusal stops nothing")

        print(failures == 0 ? "✓ LoginItem" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
