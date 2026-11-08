import Foundation
import notify

/// Asks our Wine pad driver to keep the controllers from a Windows game while the overlay is up
/// (engine/patches/winebus-winecx-pad-silence.patch). The player's rule, 8.11.: the game gets no
/// controller input then. It works on a time limit: Nightforge writes when the silence ends and keeps
/// moving that on. Renewed on the main actor on purpose – if Nightforge hangs or crashes, nothing
/// renews it and the player has the pad back within `lease` seconds.
@MainActor
enum PadSilence {
    nonisolated static let defaultName = "io.github.lordhayne.nightforge.pad-silence"
    /// What the driver is asked for at a time, and how often that is moved on: more than twice the
    /// interval, so one late round doesn't end it.
    nonisolated static let lease: TimeInterval = 5
    nonisolated static let renewEvery: TimeInterval = 2

    /// Another name for the tests: nothing of theirs may reach a Wine session that's running.
    static var name = defaultName
    private static var answerName: String { name + ".answer" }

    private static var token: Int32 = -1
    private static var answerToken: Int32 = -1
    private static var tokenName = ""
    private static var renewing: Task<Void, Never>?
    /// The first time limit of this silence: an answer at or after it answers this one.
    private static var first: UInt64 = 0

    static var isOn: Bool { renewing != nil }

    /// The driver has answered this silence (engine with the patch, and Wine running).
    static var heard: Bool {
        guard isOn, ready() else { return false }
        var answer: UInt64 = 0
        guard notify_get_state(answerToken, &answer) == NOTIFY_STATUS_OK else { return false }
        return answered(answer, since: first)
    }

    static func begin() {
        guard !isOn, ready() else { return }
        first = deadline(now: now())
        write(first)
        renewing = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(renewEvery))
                guard !Task.isCancelled else { return }
                write(deadline(now: now()))
            }
        }
    }

    static func end() {
        guard isOn else { return }
        renewing?.cancel()
        renewing = nil
        first = 0
        write(0)
    }

    /// The time limit, as the driver reads it. Internal for the tests.
    static func write(_ until: UInt64) {
        guard ready() else { return }
        notify_set_state(token, until)
        notify_post(name)
    }

    nonisolated static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    nonisolated static func deadline(now: UInt64) -> UInt64 { now + UInt64(lease * 1_000_000_000) }

    nonisolated static func answered(_ answer: UInt64, since first: UInt64) -> Bool { first != 0 && answer >= first }

    private static func ready() -> Bool {
        if token >= 0, tokenName == name { return true }
        var request: Int32 = -1
        var answer: Int32 = -1
        guard notify_register_check(name, &request) == NOTIFY_STATUS_OK,
              notify_register_check(answerName, &answer) == NOTIFY_STATUS_OK
        else { return false }
        token = request
        answerToken = answer
        tokenName = name
        return true
    }
}
