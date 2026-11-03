import Foundation

/// A short-lived program, run to its end – with a limit. `Process.waitUntilExit()` has been seen
/// hanging for good (legendary, 1 call in ~400, once for 10 minutes; docs/ROADMAP.md, 28.10.2026), and
/// a Wine command waits for as long as Wine's session does. Whoever waits for a program here can't
/// be held up longer than `timeout`: it is asked to end then, and killed if it doesn't (`grace`).
///
/// For programs that are to outlive Nightforge, and for the long ones (downloads, Steam, games),
/// there are `DetachedProcess` and `Process` with their own waiting.
enum Subprocess {
    struct Outcome: Sendable {
        /// False when the program couldn't be started at all.
        var launched = true
        /// The exit code (or signal) – -1 when the program was ended for taking too long, or when
        /// its end was seen but not its status.
        var status: Int32 = -1
        var output = Data()
        /// It was still running after `timeout`, and was ended.
        var timedOut = false

        var succeeded: Bool { launched && !timedOut && status == 0 }
        var text: String { String(decoding: output, as: UTF8.self) }
    }

    /// Runs `executable` with `arguments` and returns when it has ended, or `timeout` seconds
    /// (plus at most `grace` + 2) have gone by. `capture`: what it writes to stdout comes back in
    /// `output`; otherwise it, and stderr, go nowhere. Its stdin is empty. `environment`: nil is
    /// Nightforge's own.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = [], environment: [String: String]? = nil,
                    capture: Bool = false, timeout: TimeInterval, grace: TimeInterval = 2) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = capture ? Pipe() : nil
        process.standardOutput = pipe ?? FileHandle.nullDevice

        let end = End()
        let collected = Collected()
        if let pipe {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collected.eof()
                } else {
                    collected.append(data)
                }
            }
        }
        process.terminationHandler = { finished in end.finish(finished.terminationStatus) }

        var outcome = Outcome()
        do {
            try process.run()
        } catch {
            pipe?.fileHandleForReading.readabilityHandler = nil
            outcome.launched = false
            return outcome
        }
        // A second pair of eyes, independent of Foundation's: if its termination handler never
        // comes, the end of the process is still noticed (the status is then not known).
        let watch = DispatchSource.makeProcessSource(identifier: process.processIdentifier, eventMask: .exit,
                                                     queue: .global(qos: .utility))
        watch.setEventHandler {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { end.finish(-1) }
        }
        watch.resume()
        defer { watch.cancel() }

        if end.wait(timeout) {
            outcome.status = end.status
        } else {
            outcome.timedOut = true
            if process.isRunning { process.terminate() }
            if !end.wait(grace) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = end.wait(2)
            }
        }
        if let pipe {
            // The program is gone; what it wrote is in already, unless something it started holds
            // the pipe open (a Wine session starts its server from a command).
            _ = collected.waitForEnd(0.5)
            pipe.fileHandleForReading.readabilityHandler = nil
            outcome.output = collected.data
        }
        return outcome
    }

    /// The program's end, told by whichever of the two watchers comes first.
    private final class End: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var done = false
        private var code: Int32 = -1

        var status: Int32 { lock.withLock { code } }

        func finish(_ status: Int32) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            code = status
            semaphore.signal()
        }

        /// True when it has ended.
        func wait(_ seconds: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + max(seconds, 0)) == .success
        }
    }

    /// What the program wrote, and whether its pipe has been read to the end.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private let ended = DispatchSemaphore(value: 0)
        private var bytes = Data()

        var data: Data { lock.withLock { bytes } }

        func append(_ more: Data) { lock.withLock { bytes.append(more) } }

        func eof() { ended.signal() }

        func waitForEnd(_ seconds: TimeInterval) -> Bool {
            ended.wait(timeout: .now() + seconds) == .success
        }
    }
}

/// Whichever of two parties comes first gets to answer.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

/// Work that may take as long as it wants, asked for in `seconds` at most. nil when the time ran
/// out first: the work is then cancelled (it ends at its next suspension point – a blocking call
/// in it isn't interrupted) and no longer waited for.
func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = Once()
        let task = Task {
            let value = await work()
            if once.take() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.take() {
                task.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

/// The list of every process, from `ps` – which has been seen not answering at all, for good, whatever
/// was done to it (2.11.2026, after a Wine process was stopped in the middle of a debugger: `ps -ax`
/// hung, and could not be ended, in every program that asked; Nightforge's own window hung in it).
/// So: a limit on the wait, and once `ps` has missed it, no new one for a minute (each would only be one
/// more that never ends, and one more wait for whoever asks – often the main thread). In that minute
/// whoever may do with an old list gets the last good one (up to ten minutes old), the others nil.
enum ProcessList {
    /// What `ps -axo <columns>` would say, handed in: a test with its own processes (tests/Shared/FakeProcesses.swift)
    /// or none at all. While it is set no process is started – a `ps` that hangs on the Mac doesn't stop a series.
    nonisolated(unsafe) static var source: ((String) -> String?)?

    /// Tests of ProcessList itself point it at a stand-in program.
    nonisolated(unsafe) static var program = "/bin/ps"
    nonisolated(unsafe) static var timeout: TimeInterval = 4
    nonisolated(unsafe) static var pause: TimeInterval = 60

    private static let lock = NSLock()
    nonisolated(unsafe) private static var downUntil = Date.distantPast
    nonisolated(unsafe) private static var lastGood: [String: (text: String, date: Date)] = [:]

    /// `ps -axo <columns>`: the answer, or why there is none. `allowOld`: during a pause the last good answer
    /// (not ten minutes old) in its place, marked as old. The answer "nothing" is `.fresh("")`, never
    /// `.unavailable`: whoever concludes from an empty list ("the game has ended", "Steam isn't running") has
    /// to ask which of the two it is.
    static func listing(_ columns: String, allowOld: Bool = false) -> ProcessListing<String> {
        if let source { return source(columns).map { .fresh($0) } ?? .unavailable }
        let down = lock.withLock { Date() < downUntil }
        if !down {
            let result = Subprocess.run(program, ["-axo", columns], capture: true, timeout: timeout, grace: 0.5)
            if result.launched, !result.timedOut {
                lock.withLock { lastGood[columns] = (result.text, Date()) }
                return .fresh(result.text)
            }
            if result.timedOut { lock.withLock { downUntil = Date().addingTimeInterval(pause) } }
        }
        guard allowOld, let old = lock.withLock({ lastGood[columns] }), Date().timeIntervalSince(old.date) < 600 else {
            return .unavailable
        }
        return .old(old.text)
    }

    /// `listing` as text, nil when there is none (`stale`: an old one will do).
    static func ps(_ columns: String, stale: Bool = false) -> String? {
        listing(columns, allowOld: stale).value
    }

    /// For the test: a new start.
    static func reset() {
        lock.withLock {
            downUntil = .distantPast
            lastGood = [:]
        }
    }
}

/// What a process list says and how far it can be trusted: asked just now, the last good one while `ps` doesn't
/// answer, or nothing. A list that is `.fresh` and empty means "no process"; `.unavailable` means "not known".
enum ProcessListing<Value> {
    case fresh(Value)
    case old(Value)
    case unavailable

    /// The list, fresh or old.
    var value: Value? {
        switch self {
        case .fresh(let value), .old(let value): return value
        case .unavailable: return nil
        }
    }

    /// Only a list asked for just now says a process is gone.
    var freshValue: Value? {
        if case .fresh(let value) = self { return value }
        return nil
    }

    func map<T>(_ transform: (Value) -> T) -> ProcessListing<T> {
        switch self {
        case .fresh(let value): return .fresh(transform(value))
        case .old(let value): return .old(transform(value))
        case .unavailable: return .unavailable
        }
    }
}

/// A value several threads read and write, under a lock.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
