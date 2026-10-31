import IOKit.ps
import SwiftUI

/// Plugged in or on battery, and how full the battery is (IOKit's power sources).
struct PowerSource: Equatable {
    var onBattery = false
    /// 0…1; nil without a battery (desktop Macs).
    var level: Double?
    /// What the plugged-in power adapter offers; nil on battery or when macOS doesn't say.
    var adapterWatts: Int?

    /// The frame limit "Save battery when unplugged" sets.
    static let batteryFrameLimit = 30

    static func current() -> PowerSource { reading().source }

    /// The power source plus the battery's current in mA (below 0: it drains, also while plugged in).
    /// The current changes with every reading, so it stays out of `PowerSource`.
    static func reading() -> (source: PowerSource, batteryCurrent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (PowerSource(), nil) }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var source = PowerSource(onBattery: providing == kIOPSBatteryPowerValue)
        var current: Int?
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            source.level = Double(capacity) / Double(maximum)
            current = description[kIOPSCurrentKey] as? Int
        }
        if !source.onBattery,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 {
            source.adapterWatts = watts
        }
        return (source, current)
    }

    static func symbol(_ level: Double) -> String {
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// The limit a start uses: on battery with the setting on, at most 30 FPS (0 = no limit).
    static func cappedLimit(_ limit: Int, onBattery: Bool, saveBattery: Bool) -> Int {
        guard onBattery, saveBattery else { return limit }
        return limit > 0 ? min(limit, batteryFrameLimit) : batteryFrameLimit
    }
}

/// Plugged in, but the charger can't keep up (roadmap 3.5). With a too weak adapter macOS still
/// says "charging" while the battery drains during a game – the fun ends without anyone seeing why.
/// Weak: under 30 W, or the battery drains over several readings in a row. At the charge limit
/// (80 %) no current flows at all; that is fine.
struct ChargerCheck {
    enum Warning: Equatable {
        case weak(watts: Int)
        case draining
    }

    static let minimumWatts = 30
    /// Below this the battery drains; around 0 it just rests at the charge limit.
    static let drainingMilliamps = -100
    /// Readings in a row before the warning comes, and before it goes again (no flicker).
    static let readingsInARow = 3

    private var draining = 0
    private var steady = 0
    private var isDraining = false

    mutating func add(_ source: PowerSource, batteryCurrent: Int?) -> Warning? {
        guard !source.onBattery, source.level != nil else {
            self = ChargerCheck()
            return nil
        }
        if let current = batteryCurrent, current <= Self.drainingMilliamps {
            draining += 1
            steady = 0
        } else {
            steady += 1
            draining = 0
        }
        if draining >= Self.readingsInARow { isDraining = true }
        if steady >= Self.readingsInARow { isDraining = false }
        if let watts = source.adapterWatts, watts < Self.minimumWatts { return .weak(watts: watts) }
        return isDraining ? .draining : nil
    }
}

/// In the top bar while plugged in with a too weak charger: an amber bolt with the watts.
struct ChargerPill: View {
    let warning: ChargerCheck.Warning
    let power: PowerSource

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill").foregroundStyle(Theme.warning)
            Text(label)
        }
        .font(size: 13, weight: .semibold).monospacedDigit()
        .foregroundStyle(Theme.ink.opacity(0.9))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(GlassBackground(glass: .regular, shape: Capsule()))
        .help(Self.note(warning))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.note(warning))
    }

    private var label: String {
        if let watts = power.adapterWatts { return "\(watts) W" }
        if let level = power.level { return "\(Int((level * 100).rounded())) %" }
        return ""
    }

    /// The line on Home and the game page, also the pill's tooltip.
    static func note(_ warning: ChargerCheck.Warning) -> String {
        switch warning {
        case .weak(let watts):
            return L10n.t("The charger gives only %@ W – too little for games: the battery drains while you play. A stronger one helps.", String(watts))
        case .draining:
            return L10n.t("The battery drains although the Mac is plugged in – the charger is too weak for games.")
        }
    }
}
