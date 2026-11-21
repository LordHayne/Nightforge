import ServiceManagement

/// What LoginItem needs from macOS; a stand-in in the tests.
protocol LoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginService {}

/// Nightforge opening when the player logs in, the first step of "switch on and play". A switch in
/// Settings › General, off until the player sets it: it keeps Nightforge in memory all day.
enum LoginItem {
    enum State: Equatable {
        case off, on
        /// Registered, but macOS's Login Items settings still have it switched off.
        case needsApproval
    }

    static func state(of status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Nightforge is being removed: nothing stays behind that opens it at login. Only one that's registered:
    /// macOS answers the others with an error, and there's nobody left to tell.
    static func forget(service: LoginService) {
        guard state(of: service.status) != .off else { return }
        try? service.unregister()
    }

    /// The state after trying. A failure leaves things as they were and says why through `note`.
    @discardableResult
    static func set(_ on: Bool, service: LoginService, note: (String) -> Void = { _ in }) -> State {
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            note("Start at login: couldn't turn it \(on ? "on" : "off"): \(error.localizedDescription)")
        }
        return state(of: service.status)
    }
}
