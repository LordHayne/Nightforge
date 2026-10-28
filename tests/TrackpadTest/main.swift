// Checks the trackpad gestures without a trackpad: which way a swipe goes and when it takes over
// from scrolling, back and forward between the levels, Home rail's ends, the pinch's steps:
// tests/TrackpadTest/run.sh
import Foundation

@main
struct TrackpadTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// Feeds a whole gesture and returns each event's verdict.
    static func gesture(_ moves: [(CGFloat, CGFloat)], lift: Bool = false,
                        allows: @escaping (TrackpadSwipe.Direction) -> Bool = { _ in true }) -> [SwipeRecognizer.Verdict] {
        var recognizer = SwipeRecognizer()
        var verdicts = moves.enumerated().map { place, move in
            recognizer.feed(place == 0 ? .began : .changed, dx: move.0, dy: move.1, allows: allows)
        }
        if lift { verdicts.append(recognizer.feed(.ended, dx: 0, dy: 0, allows: allows)) }
        return verdicts
    }

    static func main() {
        // Which way: the content's direction, like Safari – moving right goes back.
        check(TrackpadSwipe.direction(dx: 5, dy: 1) == .back, "content moving right: back")
        check(TrackpadSwipe.direction(dx: -5, dy: -2) == .forward, "content moving left: forward")
        check(TrackpadSwipe.direction(dx: 1, dy: 5) == nil, "mostly up and down: no swipe")
        check(TrackpadSwipe.direction(dx: 3, dy: -3) == nil, "as much up as sideways: no swipe")
        check(TrackpadSwipe.direction(dx: 0, dy: 0) == nil, "no movement: no direction")

        // A swipe takes over once the fingers went far enough sideways; until then it waits.
        check(gesture([(2, 0), (10, 1), (5, 0)]) == [.wait, .wait, .swipe(.back)], "sideways 17 points: back")
        check(gesture([(0, 0), (-8, 0), (-8, 1)]) == [.wait, .wait, .swipe(.forward)], "a start without movement waits for the first")
        check(gesture([(0, -3), (0, -10)]) == [.scroll, .scroll], "up and down: scrolling from the start")
        check(gesture([(2, 1), (1, 8), (0, 8)]) == [.wait, .wait, .scroll], "sideways at first, then down: scrolling")
        check(gesture([(4, 0), (-6, 0), (-20, 0)]) == [.wait, .scroll, .scroll], "turned back the other way: scrolling, and it stays so")
        check(gesture([(4, 0), (3, 0)], lift: true) == [.wait, .wait, .scroll], "lifted before it was clear: the held events scroll")
        check(gesture([(30, 0), (5, 0)]) == [.swipe(.back), .scroll], "one big move: right away; the rest isn't asked again")
        check(gesture([(4, 0), (20, 0)], allows: { $0 == .forward }) == [.scroll, .scroll], "back not possible: it scrolls")
        var asked = 0
        _ = gesture([(2, 0), (2, 0), (2, 0), (20, 0)]) { _ in asked += 1; return true }
        check(asked == 1, "whether the window can go that way is asked once: \(asked)")

        // Home's rail scrolls first; back and forward only past the end it can't scroll to.
        let atStart = ScrollEdges(offset: 0, content: 1000, visible: 600)
        check(atStart.atStart && !atStart.atEnd, "at the start of a long rail")
        check(atStart.lets(.back) && !atStart.lets(.forward), "at the start: back may take over, forward scrolls the rail")
        let atEnd = ScrollEdges(offset: 400, content: 1000, visible: 600)
        check(!atEnd.atStart && atEnd.atEnd && atEnd.lets(.forward), "at the end: forward may take over")
        check(ScrollEdges(offset: 399.5, content: 1000, visible: 600).atEnd, "half a point short still counts as the end")
        let middle = ScrollEdges(offset: 200, content: 1000, visible: 600)
        check(!middle.lets(.back) && !middle.lets(.forward), "in the middle: both ways scroll the rail")
        let short = ScrollEdges(offset: 0, content: 500, visible: 600)
        check(short.atStart && short.atEnd, "a rail that fits: both ends at once")
        check(ScrollEdges(offset: -10, content: 1000, visible: 600, leadingInset: 10).atStart, "insets count")
        check(!ScrollEdges.unknown.lets(.back) && !ScrollEdges.unknown.lets(.forward), "ends unknown: the rail keeps every swipe")

        check(!TrackpadSwipe.allows(.back, canGoBack: false, canGoForward: true, rail: nil), "Home has nothing behind")
        check(!TrackpadSwipe.allows(.forward, canGoBack: true, canGoForward: false, rail: nil), "forward only after going back")
        check(TrackpadSwipe.allows(.back, canGoBack: true, canGoForward: false, rail: nil), "a game's page goes back")
        check(!TrackpadSwipe.allows(.forward, canGoBack: false, canGoForward: true, rail: middle), "over the rail mid-way: it scrolls")
        check(TrackpadSwipe.allows(.forward, canGoBack: false, canGoForward: true, rail: atEnd), "over the rail at its end: forward")
        check(!TrackpadSwipe.allows(.forward, canGoBack: false, canGoForward: true, rail: atStart), "over the rail at its start: forward scrolls it")

        // Back and forward between the levels, like Safari's history.
        check(Route.home.parent == nil, "nothing behind Home")
        check(Route.library.parent == .home, "the library goes back Home")
        check(Route.detail(gameID: "a", from: .home).parent == .home, "a page opened on Home goes back Home")
        check(Route.detail(gameID: "a", from: .library).parent == .library, "a page opened in the library goes back there")

        let page = Route.detail(gameID: "a", from: .library)
        var history = NavigationHistory()
        history.moved(from: .home, to: .library, by: .other)
        history.moved(from: .library, to: page, by: .other)
        check(history.next(from: page) == nil, "nothing ahead before going back")
        history.moved(from: page, to: .library, by: .back)
        check(history.next(from: .library) == page, "back from a game's page: forward opens it again")
        history.moved(from: .library, to: .home, by: .back)
        check(history.next(from: .home) == .library, "back twice: forward goes to the library first")
        history.moved(from: .home, to: .library, by: .forward)
        check(history.next(from: .library) == page, "… and then to the game's page")
        history.moved(from: .library, to: page, by: .forward)
        check(history.next(from: page) == nil && history.forward.isEmpty, "all retraced: nothing ahead")

        history.moved(from: page, to: .library, by: .back)
        history.moved(from: .library, to: .detail(gameID: "b", from: .library), by: .other)
        check(history.forward.isEmpty, "another game opened after going back: forward is forgotten")
        history.moved(from: .detail(gameID: "b", from: .library), to: .library, by: .back)
        check(history.next(from: .home) == nil, "forward only from where it was gone back to")
        history.forget()
        check(history.next(from: .library) == nil, "back that only dropped the search: nothing to retrace")
        history.moved(from: page, to: .library, by: .back)
        history.moved(from: .library, to: .home, by: .forward)
        check(history.forward.isEmpty, "a forward step somewhere else forgets it all")

        // Pinching: the covers in steps, the usual size until one is chosen.
        check(CoverSize(stored: nil) == .regular && CoverSize(stored: 9) == .regular, "nothing or something unknown stored: the usual size")
        check(CoverSize(stored: CoverSize.large.rawValue) == .large, "a stored size comes back")
        check(CoverSize.regular.width == 154, "the usual size is the one the grid always had")
        check(CoverSize.allCases.map(\.width) == CoverSize.allCases.map(\.width).sorted(), "bigger with every step")
        check(CoverSize.small.stepped(-1) == .small && CoverSize.huge.stepped(1) == .huge, "stops at either end")
        check(CoverSize.regular.stepped(1) == .large && CoverSize.regular.stepped(-1) == .small, "one step each way")
        var pinch = PinchSteps()
        check([0.1, 0.1, 0.1].map { pinch.add($0) } == [0, 0, 1], "apart far enough: one step bigger")
        check([-0.2, -0.1].map { pinch.add($0) } == [0, -1], "together: one step smaller")
        _ = pinch.add(0.2)
        pinch.begin()
        check(pinch.add(0.1) == 0, "a new pinch starts from nothing")

        print(failures == 0 ? "✓ Trackpad" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
