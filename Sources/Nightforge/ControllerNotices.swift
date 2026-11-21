import Foundation

/// What a controller coming, going or running low is worth saying, once. Only the rules: InputRouter
/// shows them (GameHint, over a game too, without taking anything from it).
struct ControllerNotices {
    struct Pad: Equatable {
        var id: ObjectIdentifier
        var name: String
        /// 0…1; nil when the controller doesn't say.
        var battery: Float?
        var charging = false
    }

    enum Notice: Equatable {
        case connected(String, battery: Int?)
        case lost(String)
        case low(String, percent: Int)
    }

    /// At 15 % it says so, once a charge.
    static let lowAt: Float = 0.15
    /// Higher again, or on the cable, it may say so again another time.
    static let rearmAt: Float = 0.2
    /// What comes while Nightforge starts is no news: macOS finds the pads a moment after launch.
    static let quietStart: TimeInterval = 6
    /// Bluetooth dropping out for a moment: back within this long, it's no news either.
    static let flicker: TimeInterval = 4

    private let started: TimeInterval
    private var known: [ObjectIdentifier: String] = [:]
    private var warned: Set<ObjectIdentifier> = []
    private var lostAt: [String: TimeInterval] = [:]

    init(started: TimeInterval) { self.started = started }

    mutating func update(_ pads: [Pad], now: TimeInterval) -> [Notice] {
        var notices: [Notice] = []
        let quiet = now - started < Self.quietStart
        let ids = Set(pads.map(\.id))
        for (id, name) in known where !ids.contains(id) {
            known[id] = nil
            warned.remove(id)
            lostAt[name] = now
            if !quiet { notices.append(.lost(name)) }
        }
        for pad in pads {
            if known[pad.id] == nil {
                known[pad.id] = pad.name
                let returning = lostAt[pad.name].map { now - $0 < Self.flicker } ?? false
                if !quiet && !returning {
                    notices.append(.connected(pad.name, battery: pad.battery.map { Int(($0 * 100).rounded()) }))
                }
            }
            guard let battery = pad.battery else { continue }
            if pad.charging || battery >= Self.rearmAt {
                warned.remove(pad.id)
            } else if battery <= Self.lowAt, !warned.contains(pad.id) {
                warned.insert(pad.id)
                notices.append(.low(pad.name, percent: Int((battery * 100).rounded())))
            }
        }
        return notices
    }
}
