import CoreHaptics
import GameController

/// The pad's motors (PadHapticRules says when). An engine per controller, which switches itself off
/// when idle: single moments, nothing that keeps running. Whether a pad has any is its own business.
@MainActor
final class PadHaptics {
    private var engines: [ObjectIdentifier: CHHapticEngine] = [:]
    /// The hold's taps, to call off when the buttons are let go early.
    private var holding: CHHapticPatternPlayer?

    func play(_ moment: PadHapticRules.Moment, on controller: GCController?) {
        guard let engine = engine(for: controller), let player = player(for: moment, on: engine) else { return }
        if moment == .overlayHold { holding = player }
        engine.start { error in
            if error == nil { try? player.start(atTime: CHHapticTimeImmediate) }
        }
    }

    func stopHold() {
        try? holding?.stop(atTime: CHHapticTimeImmediate)
        holding = nil
    }

    /// A controller left: its engine goes with it.
    func forgetGone() {
        let here = Set(GCController.controllers().map(ObjectIdentifier.init))
        engines = engines.filter { here.contains($0.key) }
    }

    private func engine(for controller: GCController?) -> CHHapticEngine? {
        guard let controller = controller ?? GCController.current else { return nil }
        let id = ObjectIdentifier(controller)
        if let engine = engines[id] { return engine }
        guard let engine = controller.haptics?.createEngine(withLocality: .default) else { return nil }
        engine.isAutoShutdownEnabled = true
        engine.playsHapticsOnly = true
        engines[id] = engine
        return engine
    }

    private func player(for moment: PadHapticRules.Moment, on engine: CHHapticEngine) -> CHHapticPatternPlayer? {
        let events = PadHapticRules.taps(moment).map { tap in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                                       CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness)],
                          relativeTime: tap.time)
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return nil }
        return try? engine.makePlayer(with: pattern)
    }
}
