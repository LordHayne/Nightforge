import Foundation
import IOKit.pwr_mgt

/// Whether Nightforge keeps the Mac from going to sleep, a choice in Settings › General that the
/// player makes: by default it never does, and it's never for good. At most for the chosen time
/// after the last input, plugged in only, and the screen may go dark meanwhile. That's what lets a
/// pad find the Mac awake after a pause, without Nightforge costing power when nobody's there.
enum IdleAwake {
    /// The choices, in minutes. 0 is the default: Nightforge leaves the Mac's sleep alone.
    static let choices = [0, 15, 30, 60, 120]

    static func holds(minutes: Int, onBattery: Bool, idle: TimeInterval) -> Bool {
        minutes > 0 && !onBattery && idle < TimeInterval(minutes) * 60
    }

    /// A stored number that isn't one of the choices counts as the default.
    static func minutes(stored: Int) -> Int { choices.contains(stored) ? stored : 0 }

    private static var assertion: IOPMAssertionID = 0
    private static var holding = false

    /// Called every few seconds; takes or lets go of the hold when the answer changes.
    static func apply(_ hold: Bool, reason: String) {
        guard hold != holding else { return }
        if hold {
            holding = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                  IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &assertion) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            holding = false
        }
    }
}
