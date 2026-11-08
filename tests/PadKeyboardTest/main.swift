// Checks the pad keyboard's input without a view (PadKeyLayout, PadKeyboard): tests/PadKeyboardTest/run.sh
import CoreGraphics
import Foundation

@main
struct PadKeyboardTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Input = PadKeyboard.Input
    typealias Finger = TouchpadPointer.Finger

    static func main() {
        layout()
        touch()
        typing()
        sticks()
        dpad()
        geometry()
        print(failures == 0 ? "✓ PadKeyboard" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The key under the pad position that lands in the middle of `id`, on its half.
    static func finger(on id: String, _ board: PadKeyboard) -> Finger {
        let key = board.layout.key(id: id)!
        let side: PadKeyboard.Side = key.frame.midX < PadKeyLayout.split ? .left : .right
        let region = PadKeyLayout.region(side)
        let u = (key.frame.midX - region.minX) / region.width, v = key.frame.midY / PadKeyLayout.rows
        let edge = PadKeyboard.edge
        let across = u * (1 - 2 * edge) + edge, down = v * (1 - 2 * edge) + edge
        return Finger(x: Float(side == .left ? across - 1 : across), y: Float(1 - 2 * down))
    }

    static func geometry() {
        let g = PadKeyboardGeometry.fitting(width: 1_100)
        let board = PadKeyLayout.make(page: .letters, shifted: false)
        check(g.size.width <= 1_100, "it fits the room it was given")
        check(g.keyHeight >= 40 && g.keyWidth >= 44, "the keys stay readable from the sofa")
        let huge = PadKeyboardGeometry.fitting(width: 4_000)
        check(huge.keyWidth == 104, "a wider board doesn't mean more thumb travel for nothing")
        for key in board.keys {
            let rect = g.rect(key)
            check(rect.minX >= 0 && rect.maxX <= g.size.width + 0.5, "\(key.id) stays on the board")
            for other in board.keys where other.id != key.id {
                check(!rect.intersects(g.rect(other)), "\(key.id) and \(other.id) don't overlap")
            }
        }
        let t = g.rect(board.key(id: "t")!), z = g.rect(board.key(id: "z")!)
        check(t.maxX < g.seamX && g.seamX < z.minX, "the seam runs between T and Z")
        check(z.minX - t.maxX == PadKeyboardGeometry.gap + PadKeyboardGeometry.splitGap, "the halves stand apart by the split")
        let space = g.rect(board.key(id: "space")!)
        check(space.minX < g.seamX && g.seamX < space.maxX, "the space bar lies under the seam, for the N")
        check(abs(t.width - z.width) < 0.5, "a key is the same width on both halves")
        let inside = g.point(CGPoint(x: 1.5, y: 1.5)), key = g.rect(board.key(id: "w")!)
        check(key.contains(inside), "a pointer in the middle of a key is drawn on that key")
    }

    static func layout() {
        for page in [PadKeyPage.letters, .symbols] {
            let board = PadKeyLayout.make(page: page, shifted: false)
            var x: CGFloat = 0.25
            while x < PadKeyLayout.columns {
                var y: CGFloat = 0.25
                while y < PadKeyLayout.rows {
                    let hits = board.keys.filter { $0.frame.contains(CGPoint(x: x, y: y)) }
                    check(hits.count == 1, "\(page): exactly one key at \(x),\(y), not \(hits.map(\.id))")
                    y += 0.5
                }
                x += 0.5
            }
            check(Set(board.keys.map(\.id)).count == board.keys.count, "\(page): no key twice")
        }
        let letters = PadKeyLayout.make(page: .letters, shifted: false)
        let row = letters.keys.filter { $0.frame.minY == 1 }.sorted { $0.frame.minX < $1.frame.minX }.map(\.label).joined()
        check(row == "qwertzuiopü", "QWERTZ, with the umlauts: \(row)")
        check(letters.key(at: CGPoint(x: 0.5, y: 2.5))?.id == "a" && letters.key(at: CGPoint(x: 10.5, y: 2.5))?.id == "ä", "the home row")
        check(letters.key(at: CGPoint(x: 1.5, y: 3.5))?.id == "y" && letters.key(at: CGPoint(x: 0.5, y: 3.5))?.id == "shift", "Y where a German board has it")

        let left = PadKeyLayout.region(.left), right = PadKeyLayout.region(.right)
        check(left.maxX == right.minX && right.maxX == PadKeyLayout.columns, "the halves meet and fill the board")
        check(letters.key(id: "t")!.frame.maxX <= left.maxX && letters.key(id: "z")!.frame.minX >= right.minX, "T is the left thumb's, Z the right's")
        check(letters.key(id: "space")!.frame.intersects(left) && letters.key(id: "space")!.frame.intersects(right), "both thumbs reach the space bar")

        let shifted = PadKeyLayout.make(page: .letters, shifted: true)
        check(shifted.key(id: "q")?.action == .text("Q") && shifted.key(id: "ß")?.action == .text("ß"), "capitals, and ß stays what it is")

        check(letters.hit(CGPoint(x: 1.05, y: 1.5), current: "q")?.id == "q", "just past a key's edge it's still that key")
        check(letters.hit(CGPoint(x: 1.2, y: 1.5), current: "q")?.id == "w", "further on, the next")
        check(letters.hit(CGPoint(x: 1.05, y: 1.5), current: nil)?.id == "w", "nothing before: what's there")
    }

    static func touch() {
        var board = PadKeyboard()
        check(board.pointers[.left]?.key == "f" && board.pointers[.right]?.key == "j", "the thumbs start on F and J")

        let g = finger(on: "g", board), u = finger(on: "u", board)
        check(board.feed(Input(primary: g)) == [.hover(.left, "g")], "a thumb landing on the left half moves the left pointer there, with a tick")
        check(board.feed(Input(primary: g, secondary: u, now: 0.01)) == [.hover(.right, "u")], "the other thumb has the other half")
        check(board.feed(Input(primary: g, secondary: u, now: 0.02)).isEmpty, "resting: no ticks")

        // Sliding over the middle: the thumb stays at its half's edge.
        var slide = PadKeyboard()
        _ = slide.feed(Input(primary: Finger(x: -0.2, y: 0.1)))
        _ = slide.feed(Input(primary: Finger(x: 0.9, y: 0.1), now: 0.01))
        check((slide.pointers[.left]?.position.x ?? 9) < PadKeyLayout.split, "a thumb stays on its half when it crosses the middle")
        check(slide.pointers[.right]?.key == "j", "and doesn't move the other pointer")

        // A second thumb on a half already taken waits for it.
        var both = PadKeyboard()
        _ = both.feed(Input(primary: Finger(x: -0.5, y: 0.1)))
        let before = both.pointers[.left]
        _ = both.feed(Input(primary: Finger(x: -0.5, y: 0.1), secondary: Finger(x: -0.2, y: -0.5), now: 0.01))
        check(both.pointers[.left] == before, "a second thumb on the same half takes nothing")

        // Corners are reachable although the thumb can't quite get to the pad's edge.
        var corner = PadKeyboard()
        _ = corner.feed(Input(primary: Finger(x: -0.95, y: 0.95)))
        check(corner.pointers[.left]?.key == "1", "top left: the first key")
        var far = PadKeyboard()
        _ = far.feed(Input(primary: Finger(x: 0.95, y: -0.95)))
        check(far.pointers[.right]?.key == "done", "bottom right: the last key")

        // Sensitivity: finer after the landing, still lands where the thumb is.
        var fine = PadKeyboard()
        fine.sensitivity = 0.5
        var exact = PadKeyboard()
        _ = fine.feed(Input(primary: Finger(x: -0.5, y: 0)))
        _ = exact.feed(Input(primary: Finger(x: -0.5, y: 0)))
        check(fine.pointers[.left]?.position == exact.pointers[.left]?.position, "the landing is the same at any sensitivity")
        _ = fine.feed(Input(primary: Finger(x: -0.3, y: 0), now: 0.01))
        _ = exact.feed(Input(primary: Finger(x: -0.3, y: 0), now: 0.01))
        let start = CGFloat(-0.5 + 1 - PadKeyboard.edge) / (1 - 2 * PadKeyboard.edge) * 5
        let fineWay = fine.pointers[.left]!.position.x - start, exactWay = exact.pointers[.left]!.position.x - start
        check(abs(fineWay * 2 - exactWay) < 0.01, "half the sensitivity, half the way")
    }

    static func typing() {
        var board = PadKeyboard()
        let g = finger(on: "g", board), u = finger(on: "u", board)
        var pad = Input(primary: g, secondary: u)
        _ = board.feed(pad)

        pad.r2 = 0.2; pad.now = 0.1
        check(board.feed(pad).isEmpty, "a trigger barely touched types nothing")
        pad.r2 = 0.3; pad.now = 0.11
        check(board.feed(pad) == [.typed(.right, "u")] && board.text == "u", "R2 types with the right pointer, early in its travel")
        pad.r2 = 1; pad.now = 0.2
        check(board.feed(pad).isEmpty && board.text == "u", "held: only once, however far it's pulled")
        pad.r2 = 0.2; pad.now = 0.3
        check(board.feed(pad).isEmpty, "not back far enough to go again")
        pad.r2 = 0.05; pad.now = 0.4
        _ = board.feed(pad)
        pad.r2 = 0.5; pad.now = 0.5
        _ = board.feed(pad)
        check(board.text == "uu", "let go and pulled again: the next letter, without a full release")
        pad.l2 = 0.4; pad.now = 0.6
        check(board.feed(pad) == [.typed(.left, "g")] && board.text == "uug", "L2 with the left pointer")

        pad = Input(now: 1)
        _ = board.feed(pad)
        pad.r1 = true; pad.now = 1.1
        check(board.feed(pad) == [.typed(nil, "space")] && board.text == "uug ", "R1 is the space")
        pad.now = 2
        check(board.feed(pad).isEmpty, "not repeated")
        pad.r1 = false; pad.l1 = true; pad.now = 2.1
        check(board.feed(pad) == [.typed(nil, "backspace")] && board.text == "uug", "L1 deletes")
        pad.now = 2.2
        check(board.feed(pad).isEmpty, "held a moment: not yet again")
        pad.now = 2.55
        _ = board.feed(pad)
        check(board.text == "uu", "held on: it repeats")
        pad.now = 2.63
        _ = board.feed(pad)
        pad.now = 2.71
        _ = board.feed(pad)
        pad.now = 2.8
        check(board.feed(pad).isEmpty && board.text.isEmpty, "until nothing is left, without a tick for nothing")

        // Shift: once, then held, then off; the keys show it.
        var shift = PadKeyboard()
        var s = Input(a: false)
        _ = shift.feed(s)
        s.l3 = true; s.now = 0.1
        _ = shift.feed(s)
        check(shift.shift == .once && shift.layout.key(id: "j")?.label == "J", "L3: the next letter big")
        s.l3 = false; s.a = true; s.now = 0.2
        _ = shift.feed(s)
        check(shift.text == "J" && shift.shift == .off && shift.layout.key(id: "j")?.label == "j", "A types with the last pointer; after one letter small again")

        // The page key, and pointers on the new page.
        var page = PadKeyboard()
        var p = Input(r3: true, now: 0.1)
        _ = page.feed(p)
        check(page.page == .symbols && page.pointers[.left]?.key == page.layout.key(at: page.pointers[.left]!.position)?.id, "R3: symbols, each pointer on what's now there")
        p.r3 = false; p.a = true; p.now = 0.2
        _ = page.feed(p)
        check(page.text == "'", "and it types from that page: the key at J's place")

        // Touchpad click, Done, B, ☰, the limit.
        var click = PadKeyboard()
        _ = click.feed(Input(primary: finger(on: "h", click)))
        _ = click.feed(Input(primary: finger(on: "h", click), touchClick: true, now: 0.1))
        check(click.text == "h", "pressing the touchpad types where the thumb is")

        var done = PadKeyboard()
        let doneFinger = finger(on: "done", done)
        _ = done.feed(Input(primary: doneFinger))
        check(done.feed(Input(primary: doneFinger, r2: 1, now: 0.1)) == [.submit], "the Done key submits")
        var buttons = PadKeyboard()
        check(buttons.feed(Input(menu: true, now: 0.1)) == [.submit], "☰ submits from anywhere")
        check(buttons.feed(Input(b: true, now: 0.2)) == [.close], "B closes")

        var long = PadKeyboard(text: String(repeating: "x", count: PadKeyboard.limit))
        check(long.feed(Input(r1: true, now: 0.1)).isEmpty && long.text.count == PadKeyboard.limit, "the limit: no more, and no tick")
        check(PadKeyboard(text: String(repeating: "x", count: 100)).text.count == PadKeyboard.limit, "a longer search taken over is cut to fit")
    }

    static func sticks() {
        var board = PadKeyboard()
        var pad = Input(leftStick: CGPoint(x: 0.1, y: 0.1), now: 0)
        _ = board.feed(pad)
        pad.now = 0.05
        check(board.feed(pad).isEmpty && board.pointers[.left]?.key == "f", "a resting stick moves nothing")

        var now: TimeInterval = 0.1
        var moved: [PadKeyboard.Event] = []
        pad = Input(leftStick: CGPoint(x: 1, y: 0), rightStick: CGPoint(x: -1, y: 0), now: now)
        _ = board.feed(Input(now: now - 0.016))
        for _ in 0..<120 {
            now += 0.016
            pad.now = now
            moved += board.feed(pad)
        }
        check(moved.contains(.hover(.left, "g")), "a stick walks its pointer key by key, with ticks")
        check((board.pointers[.left]?.position.x ?? 9) < PadKeyLayout.split, "the left stick stops at the middle")
        check((board.pointers[.right]?.position.x ?? 0) >= PadKeyLayout.split, "the right stick too, from its side")
        check(board.pointers[.left]?.key == "g" && board.pointers[.right]?.key == "h", "right against the middle: G and H")

        // Up on the stick is up on the board; a thumb on that half has it.
        var up = PadKeyboard()
        _ = up.feed(Input(now: 0))
        _ = up.feed(Input(leftStick: CGPoint(x: 0, y: 1), now: 0.1))
        check(up.pointers[.left]!.position.y < 2.5, "stick up, pointer up")
        var thumb = PadKeyboard()
        let g = finger(on: "g", thumb)
        _ = thumb.feed(Input(primary: g, now: 0))
        let held = thumb.pointers[.left]
        _ = thumb.feed(Input(primary: g, leftStick: CGPoint(x: -1, y: 0), now: 0.1))
        check(thumb.pointers[.left] == held, "a thumb on the touchpad wins over the stick")
    }

    static func dpad() {
        var board = PadKeyboard()
        var pad = Input(dpad: CGPoint(x: -1, y: 0), now: 0)
        check(board.feed(pad) == [.hover(.right, "h")], "the d-pad starts with the pointer used last: J to H")
        pad.now = 0.1
        check(board.feed(pad).isEmpty, "a moment held: no second step")
        pad.now = 0.4
        check(board.feed(pad) == [.hover(.left, "g")] && board.lastSide == .left, "held on: over the middle, the left pointer takes over")
        pad.now = 0.45
        check(board.feed(pad).isEmpty, "the repeat has its pace")
        pad.now = 0.52
        check(board.feed(pad) == [.hover(.left, "f")], "and goes on")

        pad = Input(now: 1)
        _ = board.feed(pad)
        pad.dpad = CGPoint(x: 0, y: 1); pad.now = 1.1
        check(board.feed(pad) == [.hover(.left, "r")], "up keeps the column")
        pad.dpad = .zero; pad.now = 1.2
        _ = board.feed(pad)
        pad.a = true; pad.now = 1.3
        _ = board.feed(pad)
        check(board.text == "r", "A types the key it's on")

        var bottom = PadKeyboard()
        var way = Input(dpad: CGPoint(x: 0, y: -1), now: 0)
        _ = bottom.feed(way)
        way.dpad = .zero; way.now = 0.1
        _ = bottom.feed(way)
        way.dpad = CGPoint(x: 0, y: -1); way.now = 0.2
        check(bottom.feed(way) == [.hover(.right, "space")], "down reaches the space bar")
        way.dpad = .zero; way.now = 0.3
        _ = bottom.feed(way)
        way.dpad = CGPoint(x: 0, y: -1); way.now = 0.4
        check(bottom.feed(way).isEmpty, "past the last row: nothing")
        way.dpad = .zero; way.now = 0.5
        _ = bottom.feed(way)
        way.dpad = CGPoint(x: 1, y: 0); way.now = 0.6
        check(bottom.feed(way) == [.hover(.right, "done")], "right of the space bar: Done")
    }
}
