import Foundation

/// Starts wrapper/pad-answer.c in the game's Wine session, one press at a time.
enum PadAnswerRun {
    static var program: URL? { Bundle.main.url(forResource: "pad-answer", withExtension: "exe") }
    static var available: Bool { program != nil }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: DetachedProcess?

    /// `done` with the helper's exit code.
    static func send(_ choice: PadAnswer.Choice, wine: URL, done: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard running?.isRunning != true, let program,
              let process = try? WineSandbox.process(wine, [Engine.windowsPath(of: program)] + PadAnswer.arguments(choice))
        else { return }
        process.environment = Engine.environment(wine: wine)
        // Not in the game's folder, where it would count as the game's own (GameProcesses.runsFrom).
        process.currentDirectoryURL = Engine.prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { done($0.terminationStatus) }
        guard (try? process.run()) != nil else { return }
        running = process
    }
}
