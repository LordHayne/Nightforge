// Checks when A and B answer a game's question (PadAnswer). It never starts the helper: tests/PadAnswerTest/run.sh
import Foundation

@main
struct PadAnswerTest {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("✗ " + message)
            }
        }
        check(PadAnswer.takes(asking: true, helperThere: true, overlay: false), "a question stands: A and B answer it")
        check(!PadAnswer.takes(asking: false, helperThere: true, overlay: false), "no question: they're the game's")
        check(!PadAnswer.takes(asking: true, helperThere: false, overlay: false), "a build without the helper leaves it to the touchpad")
        check(!PadAnswer.takes(asking: true, helperThere: true, overlay: true), "the overlay has them first")
        check(PadAnswer.arguments(.ok) == ["ok"] && PadAnswer.arguments(.cancel) == ["cancel"], "what the helper takes")
        check(!PadAnswer.needsPointer(exit: 0), "pressed: done")
        check(PadAnswer.needsPointer(exit: 1) && PadAnswer.needsPointer(exit: 2), "no such dialog, or it didn't take the press: the pointer")
        print(failures == 0 ? "✓ PadAnswer" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
