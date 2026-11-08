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
    static let openSelector = NSSelectorFromString("openControllerHomeButtonSettingsForActivity:error:")
    /// GCControllerHomeButtonSettingsCustomizeSystemActionActivity.
    private static let customizeSystemAction = 1

    /// macOS has it, on this Mac.
    static var exists: Bool { NSClassFromString(className) != nil }

    private static func manager() -> NSObject? { (NSClassFromString(className) as? NSObject.Type)?.init() }

    static func current() -> State {
        guard let manager = manager(), manager.responds(to: readSelector) else { return .unavailable }
        typealias Read = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Int
        return state(systemAction: unsafeBitCast(manager.method(for: readSelector), to: Read.self)(manager, readSelector, nil))
    }

    @discardableResult
    static func openSettings() -> Bool {
        guard let manager = manager(), manager.responds(to: openSelector) else { return false }
        typealias Open = @convention(c) (AnyObject, Selector, Int, UnsafeMutableRawPointer?) -> Bool
        return unsafeBitCast(manager.method(for: openSelector), to: Open.self)(manager, openSelector, customizeSystemAction, nil)
    }
}
