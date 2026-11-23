import Foundation

/// A test program never finds or reaches the player's real Wine session. Most test series run with the Mac's real home
/// (103 of 127 on 23.11.2026); there Nightforge's data folder is the real one, with Steam and its session in it, and a test
/// that called a step of Engine's without a stand-in for every part could have ended the session or started Steam.
/// None did, and this makes sure none can: in a program without a bundle of its own (every test) run with the account's
/// real home, Nightforge's own processes are none (`Engine.own`), no Wine program from the data folder starts
/// (`WineSandbox.process`), no session ends (`Engine.stopAll`), no quit script is handed over
/// (`Engine.scheduleSteamShutdown`), and the data folder's helper app isn't used (`DetachedProcess.helperApp`).
/// Nightforge itself has a bundle; a test with a home of its own (HOME in a temporary folder) has its own data folder:
/// for both nothing changes.
enum TestGuard {
    struct KeptOut: Error {}

    /// This is a test program run with the account's real home.
    static let realHome: Bool = isTestWithRealHome(bundleID: Bundle.main.bundleIdentifier, home: NSHomeDirectory(), account: accountHome())

    /// This is a test program, whatever its home: what belongs to the whole Mac – its volume, a picture of the screen – it
    /// never changes or takes (SystemVolume, GameScreenshot), not even with a home of its own.
    static let testProgram: Bool = Bundle.main.bundleIdentifier == nil

    nonisolated static func isTestWithRealHome(bundleID: String?, home: String, account: String) -> Bool {
        bundleID == nil && !account.isEmpty && canonical(home) == canonical(account)
    }

    /// `path` lies in Nightforge's real data folder, and this is such a test.
    static func keepsOut(_ path: String) -> Bool {
        realHome && lies(path, in: Engine.supportDir.path)
    }

    nonisolated static func lies(_ path: String, in folder: String) -> Bool {
        let path = canonical(path), folder = canonical(folder)
        return path == folder || path.hasPrefix(folder + "/")
    }

    private nonisolated static func canonical(_ path: String) -> String {
        var text = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The account's home as the system has it, whatever HOME says.
    nonisolated static func accountHome() -> String {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return "" }
        return String(cString: directory)
    }
}
