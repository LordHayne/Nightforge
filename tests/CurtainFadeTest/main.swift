// The curtain's fades (GameBackdrop.fade) go on after their time and set their end value, whether or not AppKit's
// animation ends: with the display asleep it never did, and the curtain stood as an orphan from 11:35 to 12:08 on
// 23.11.2026, the way back starting over every 19 s. A window of the test's own, off the screen: tests/CurtainFadeTest/run.sh
import AppKit

@main
struct CurtainFadeTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor
    static func main() async {
        TestDefaults.useWorkFolder()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 200, height: 120), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.alphaValue = 1

        let started = Date()
        let done = await GameBackdrop.fade(window, to: 0, over: 0.2)
        let took = Date().timeIntervalSince(started)
        check(done, "the fade went through")
        check(window.alphaValue == 0, "its end value is set, also where the animation didn't run (\(window.alphaValue))")
        check(took >= 0.2 && took < 1.5, "it waits its time, not for the animation's end (\(took) s)")

        // Called off meanwhile (another raise or hide has the window): nothing set, and it says so.
        window.alphaValue = 1
        let task = Task { @MainActor in await GameBackdrop.fade(window, to: 0, over: 0.5) }
        task.cancel()
        check(await task.value == false, "called off: false, so the caller doesn't hide the window")

        // W2: raised again while a fade to 0 still runs – the fade gives way, the curtain stays seen.
        window.alphaValue = 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: nil)
        GameBackdrop.settle(window, at: 1)
        try? await Task.sleep(for: .seconds(0.5))
        check(window.alphaValue == 1, "a fade under way gives way to the value set after it (\(window.alphaValue))")
        let source = (try? String(contentsOfFile: "Sources/Nightforge/GameBackdrop.swift", encoding: .utf8)) ?? ""
        let straight = source.components(separatedBy: "\n").filter { $0.contains("window.alphaValue = ") && !$0.contains("settle") }
        check(straight.count == 1, "the curtain's alpha is set straight only inside settle: \(straight)")

        print(failures == 0 ? "✓ CurtainFade" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
