import Foundation

/// The PS or Xbox button held opens Nightforge. New in macOS 27: the player assigns it in System
/// Settings, an app may only look at the choice and open the right page. Reached at run time: the
/// build's SDK (26.5, build.sh) doesn't have the class yet. Only with a controller connected,
/// macOS says, and never from a test: the page would open.
enum HomeButtonSetup {
    enum State: Equatable { case unavailable, opensNightforge, somethingElse }

    /// GCControllerHomeButtonSettingSystemAction's values.
    static func state(systemAction: Int) -> State {
        switch systemAction {
        case 1: return .opensNightforge
        case -1: return .unavailable
        default: return .somethingElse
        }
    }

    static let className = "GCControllerHomeButtonSettingsManager"
    static let readSelector = NSSelectorFromString("readControllerHomeButtonSystemActionWithError:")
    static let readInAppSelector = NSSelectorFromString("readControllerHomeButtonInAppActionWithError:")
    static let openSelector = NSSelectorFromString("openControllerHomeButtonSettingsForActivity:error:")

    /// Which page of System Settings (GCControllerHomeButtonSettingsCustomizationActivity).
    enum Page: Int {
        /// The button held: which app it opens.
        case longPress = 1
        /// The button pressed with this app in front: whether the app may have it.
        case shortPress = 2
    }

    /// GCControllerHomeButtonSettingInAppAction: 1 is "the app decides"; the button switched off
    /// (NSIntegerMax) reaches the app as well. 0 keeps macOS's own handling, -1 can't be read.
    static func appMayHave(inAppAction: Int) -> Bool { inAppAction == 1 || inAppAction == Int.max }

    /// A short press belongs to Nightforge only while it's in front, no game runs and the player
    /// wants it. Asking for the button is what makes macOS ask ("… möchte das Systemverhalten
    /// überschreiben", Allow/Don't Allow, from gamecontrollerd, and it stays until answered, also
    /// over a game: 8.11.). So never before it's allowed or the player asked for it in Settings.
    static func takesButton(exists: Bool, active: Bool, overlay: Bool, gameOn: Bool, allowed: Bool, asked: Bool) -> Bool {
        exists && active && !overlay && !gameOn && (allowed || asked)
    }

    /// Held longer it's the system's long press.
    static func isShortPress(held: TimeInterval) -> Bool { held < 0.5 }

    /// macOS has it, on this Mac.
    static var exists: Bool { NSClassFromString(className) != nil }

    private static func manager() -> NSObject? { (NSClassFromString(className) as? NSObject.Type)?.init() }

    static func current() -> State {
        guard let manager = manager(), manager.responds(to: readSelector) else { return .unavailable }
        typealias Read = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Int
        return state(systemAction: unsafeBitCast(manager.method(for: readSelector), to: Read.self)(manager, readSelector, nil))
    }

    /// Whether System Settings lets the app have the short press.
    static func appMayHaveButton() -> Bool {
        guard let manager = manager(), manager.responds(to: readInAppSelector) else { return false }
        typealias Read = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Int
        return appMayHave(inAppAction: unsafeBitCast(manager.method(for: readInAppSelector), to: Read.self)(manager, readInAppSelector, nil))
    }

    @discardableResult
    static func openSettings(_ page: Page = .longPress) -> Bool {
        guard let manager = manager(), manager.responds(to: openSelector) else { return false }
        typealias Open = @convention(c) (AnyObject, Selector, Int, UnsafeMutableRawPointer?) -> Bool
        return unsafeBitCast(manager.method(for: openSelector), to: Open.self)(manager, openSelector, page.rawValue, nil)
    }
}
