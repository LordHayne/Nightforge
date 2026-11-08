// Checks the switch for opening at login (LoginItem) against a stand-in for macOS, which never
// touches the real login items: tests/LoginItemTest/run.sh
import Foundation
import ServiceManagement

final class StandIn: LoginService {
    var status: SMAppService.Status = .notRegistered
    var fails = false
    var after: SMAppService.Status = .enabled
    struct Refused: Error {}

    func register() throws {
        if fails { throw Refused() }
        status = after
    }

    func unregister() throws {
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

        print(failures == 0 ? "✓ LoginItem" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
