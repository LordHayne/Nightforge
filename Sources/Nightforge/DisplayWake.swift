import CoreGraphics
import IOKit.pwr_mgt

/// A fresh press on the pad brings the picture back when the screen has gone to sleep and the Mac
/// is awake. macOS counts a DualSense as use by itself (pmset's log, 1.–7.11.); for other pads this
/// does it. Without any permission. It can't wake a Mac that's really asleep.
enum DisplayWake {
    static func wakes(freshPress: Bool, displayAsleep: Bool) -> Bool { freshPress && displayAsleep }

    private static var activity: IOPMAssertionID = 0

    static var displayAsleep: Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }

    static func declareUse() {
        IOPMAssertionDeclareUserActivity("Controller pressed" as CFString, kIOPMUserActiveLocal, &activity)
    }
}
