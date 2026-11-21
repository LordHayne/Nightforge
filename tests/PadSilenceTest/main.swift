// Nightforge's side of the pad's silence against winebus's code (standin.c): begins, is answered, keeps
// going past one lease, ends; ends by itself when nothing renews it, as after a crash or a hang.
// tests/PadSilenceTest/run.sh
import Foundation

@main
struct PadSilenceTest {
    @MainActor static var failures = 0
    @MainActor static var said: [String] = []

    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Waits for the stand-in to say something new; nil after `seconds`.
    @MainActor static func next(within seconds: Double) async -> String? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !said.isEmpty { return said.removeFirst() }
            await wait(0.02)
        }
        return nil
    }

    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { print("usage"); exit(2) }
        let patch = (try? String(contentsOfFile: arguments[2], encoding: .utf8)) ?? ""
        check(patch.contains("\"\(PadSilence.defaultName)\""), "the patch listens on Nightforge's name")
        check(patch.contains("\"\(PadSilence.defaultName).answer\""), "… and answers on the name Nightforge reads")
        check(PadSilence.renewEvery * 2 < PadSilence.lease, "one late renewal doesn't end the silence")
        check(PadSilence.answered(10, since: 10) && PadSilence.answered(11, since: 10), "an answer to this silence counts")
        check(!PadSilence.answered(9, since: 10), "… one from an earlier silence doesn't")
        check(!PadSilence.answered(10, since: 0), "… nor any without a silence")

        // Names of the test's own: nothing here may reach a Wine session that's running.
        PadSilence.name = "io.github.lordhayne.nightforge.pad-silence-test-\(getpid())"
        let standIn = Process()
        let wrapper = arguments.count > 3 ? arguments[3].split(separator: " ").map(String.init) : []
        standIn.executableURL = URL(fileURLWithPath: wrapper.isEmpty ? arguments[1] : "/usr/bin/arch")
        standIn.arguments = (wrapper.isEmpty ? [] : Array(wrapper.dropFirst()) + [arguments[1]]) + [PadSilence.name, PadSilence.name + ".answer"]
        let output = Pipe()
        standIn.standardOutput = output
        var rest = ""
        output.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            DispatchQueue.main.async {
                rest += text
                while let line = rest.firstIndex(of: "\n") {
                    said.append(String(rest[..<line]))
                    rest = String(rest[rest.index(after: line)...])
                }
            }
        }
        try? standIn.run()

        let up = await next(within: 5) ?? ""
        check(up.hasPrefix("up "), "the stand-in starts")
        if let there = UInt64(up.dropFirst(3)) {
            let here = PadSilence.now()
            check(max(here, there) - min(here, there) < 2_000_000_000, "Nightforge and an x86_64 driver read the same clock")
        }
        await wait(0.1)

        check(!PadSilence.heard, "nothing asked: no answer")
        PadSilence.begin()
        check(await next(within: 2) == "begins", "begin: the driver falls silent")
        await wait(0.1)
        check(PadSilence.heard, "… and answers")

        // Longer than one lease: only the renewal keeps it going.
        check(await next(within: PadSilence.lease + 1.5) == nil, "renewed: it stays silent past one lease")
        PadSilence.end()
        check(await next(within: 2) == "ends", "end: the driver hears the pad again")
        check(!PadSilence.heard, "… and no answer counts any more")

        // As after a crash or a hang: a time limit is written and nobody moves it on.
        PadSilence.write(PadSilence.now() + 1_000_000_000)
        check(await next(within: 2) == "begins", "a limit one second off: silent")
        check(await next(within: 3) == "ends", "… and it ends by itself when nothing renews it")

        PadSilence.write(PadSilence.now() + 3_600_000_000_000)
        check(await next(within: 1) == nil, "a time absurdly far off changes nothing")
        PadSilence.write(0)
        await wait(0.1)
        said.removeAll()

        // No driver that answers: an engine without the patch, or no Wine running.
        standIn.terminate()
        standIn.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        PadSilence.name += "-none"
        PadSilence.begin()
        await wait(0.3)
        check(PadSilence.isOn && !PadSilence.heard, "no driver: no answer, so the game is stopped instead")
        PadSilence.end()
        check(!PadSilence.isOn, "… and it's over")

        if failures == 0 { print("✓ PadSilence: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}
