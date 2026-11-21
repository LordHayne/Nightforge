import Foundation
import os

/// Windows games need Rosetta, because Wine is x86_64. Apple keeps it for everything through macOS 27;
/// after that only for some older games, and doesn't say which (docs/ENTWURF-ARM64.md). So past macOS 27
/// a Mac without it isn't one to offer the install on: Nightforge says so plainly, and says nothing about
/// what comes later.
enum RosettaSupport {
    static let lastMajorWithRosetta = 27

    /// Past macOS 27 and x86_64 code doesn't run. Up to macOS 27 `translates` isn't even asked: a Rosetta
    /// missing there is one Apple still installs (SetupModel's `.needsRosetta`).
    static func isGone(macOSMajor: Int, translates: () -> Bool) -> Bool {
        macOSMajor > lastMajorWithRosetta && !translates()
    }

    static var isGoneHere: Bool {
        isGone(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) { Engine.isRosettaInstalled }
    }

    static var notice: String {
        L10n.t("Windows games can't run on this version of macOS: Rosetta, which they need, isn't available here.")
    }

    // MARK: - Before x86_64 code runs

    /// What a Mac has for x86_64 code (Wine, wineserver, Windows Steam, nightforge-sandbox, a Mac version made for
    /// Intel): Rosetta there, missing where Apple still installs it, or gone past macOS 27.
    enum State: Equatable { case ready, missing, gone }

    static func state(macOSMajor: Int, installed: () -> Bool) -> State {
        if installed() { return .ready }
        return macOSMajor > lastMajorWithRosetta ? .gone : .missing
    }

    /// Rosetta seen this session: then it isn't asked again, until a "Bad CPU type" says otherwise (`forget`).
    private static let seen = OSAllocatedUnfairLock(initialState: false)

    /// Once per session while it's there; at each ask while it's missing, so an install counts at once. A fresh
    /// Mac has none: the user's MacBook Pro on 21.11.2026 signed in through the launcher cards, never reached the
    /// first start's Rosetta step, and Windows Steam failed with "Bad CPU type in executable".
    static func stateHere(probe: () -> Bool = { Engine.isRosettaInstalled }, defaults: UserDefaults = .standard) -> State {
        if testsMissing(defaults: defaults) {
            return state(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, installed: { false })
        }
        if seen.withLock({ $0 }) { return .ready }
        let state = state(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, installed: probe)
        if state == .ready { seen.withLock { $0 = true } }
        return state
    }

    /// x86_64 code just failed for want of Rosetta: the next ask looks again.
    static func forget() { seen.withLock { $0 = false } }

    // MARK: - Error 86

    /// Error 86 (EBADARCH, "Bad CPU type in executable"): x86_64 code and no Rosetta to run it. macOS says it in
    /// the Mac's language ("Ungültiger CPU-Typ im startfähigen Programm"), once wrapped in another error too.
    static func isBadCPUType(_ error: Error) -> Bool {
        if error is Missing { return true }
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EBADARCH) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isBadCPUType) ?? false
    }

    /// What Process.run's error 86 becomes: the player reads that Rosetta is missing, never the system's words.
    struct Missing: LocalizedError {
        var errorDescription: String? { RosettaSupport.missingText(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }
    }

    static func missingText(macOSMajor: Int) -> String {
        macOSMajor > lastMajorWithRosetta ? notice : L10n.t("Rosetta from Apple is missing on this Mac. Windows games need it.")
    }

    /// An error for the player: error 86 as Rosetta missing, any other as it says itself.
    static func playerText(_ error: Error) -> String {
        isBadCPUType(error) ? (Missing().errorDescription ?? "") : error.localizedDescription
    }

    /// `process.run()`, its error 86 thrown as `Missing`, and Rosetta asked again next time.
    static func run(_ process: Process) throws {
        try starting(process.executableURL) { try process.run() }
    }

    /// The same through Nightforge Helper, which reports the program's spawn error ("error 86") as a POSIXError.
    static func run(_ process: DetachedProcess) throws {
        try starting(process.executableURL) { try process.run() }
    }

    private static func starting(_ program: URL?, _ start: () throws -> Void) throws {
        do {
            try start()
        } catch where isBadCPUType(error) {
            forget()
            GameLog.note("\(program?.lastPathComponent ?? "?") couldn't start: Bad CPU type – Rosetta is missing")
            throw Missing()
        }
    }

    // MARK: - The hidden test switch

    /// "Install Rosetta" pressed this session: the test switch says "missing" no longer.
    private static let installAsked = OSAllocatedUnfairLock(initialState: false)

    static func noteInstallAsked() { installAsked.withLock { $0 = true } }

    /// Nightforge's own test switch (`defaults write io.github.lordhayne.nightforge gameTest.missingRosetta -bool true`):
    /// the probe says Rosetta is missing until "Install Rosetta" is pressed in this session, so a Mac with Rosetta shows
    /// what a new one without it does – the first start's step, the question before a Windows game, and the start after
    /// it. The install runs as ever: on a Mac with Rosetta macOS asks for the password and is done at once. No entry in
    /// the interface; `defaults delete io.github.lordhayne.nightforge gameTest.missingRosetta` ends it. A build made with
    /// NIGHTFORGE_RELEASE has no such switch (as WindowsRoots.testsQuestion): neither its key – 23 bytes, text in an
    /// optimized build, which the release workflow looks for – nor anything that reads it.
    #if NIGHTFORGE_RELEASE
    static func testsMissing(defaults: UserDefaults = .standard) -> Bool { false }
    #else
    static let testMissingRosettaKey = "gameTest.missingRosetta"
    static func testsMissing(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: testMissingRosettaKey) && !installAsked.withLock { $0 }
    }
    #endif

    // MARK: - The install

    /// macOS's own password prompt for a system install; Rosetta itself comes from Apple. The player accepts its
    /// licence with the button that leads here ("by installing you accept Apple's Rosetta license"). True when done.
    static func install() async -> Bool {
        noteInstallAsked()
        let script = #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#
        let ok = await Task.detached { () -> Bool in
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            return error == nil
        }.value
        forget()
        GameLog.note("Rosetta: the install \(ok ? "is done" : "didn't happen (cancelled or failed)")")
        return ok
    }
}
