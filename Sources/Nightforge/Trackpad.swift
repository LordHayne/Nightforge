import AppKit
import SwiftUI

/// Two fingers sideways on the trackpad go back and forward between Nightforge's levels, like
/// Safari (InputRouter tracks them). The direction is the content's, as in Safari: content moving
/// right (the fingers to the right with natural scrolling) goes back.
enum TrackpadSwipe {
    enum Direction: Equatable { case back, forward }

    /// Sideways movement, summed since the fingers started, before a swipe takes over from
    /// scrolling (Safari waits about as long).
    static let distance: CGFloat = 15

    /// The way a scroll's movement points: nil while it's still or mostly up and down.
    static func direction(dx: CGFloat, dy: CGFloat) -> Direction? {
        guard abs(dx) > abs(dy) else { return nil }
        return dx > 0 ? .back : .forward
    }

    /// Whether a swipe that way may go anywhere now: back needs a level behind, forward a step
    /// just gone back; over Home's rail (`rail` given) only past the end it can't scroll to.
    static func allows(_ direction: Direction, canGoBack: Bool, canGoForward: Bool, rail: ScrollEdges?) -> Bool {
        guard direction == .back ? canGoBack : canGoForward else { return false }
        return rail?.lets(direction) ?? true
    }
}

/// Where a sideways scroller stands: a swipe only navigates the way it can't scroll any more,
/// so Home's rail scrolls first and back or forward take over at its end.
struct ScrollEdges: Equatable {
    var atStart: Bool
    var atEnd: Bool

    /// Neither end known (no geometry before macOS 15): the rail keeps every swipe.
    static let unknown = ScrollEdges(atStart: false, atEnd: false)

    init(atStart: Bool, atEnd: Bool) {
        self.atStart = atStart
        self.atEnd = atEnd
    }

    /// `offset`: how far it's scrolled; `content` and `visible`: the widths of what scrolls and
    /// of the window onto it. A point of slack for rounding.
    init(offset: CGFloat, content: CGFloat, visible: CGFloat, leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) {
        atStart = offset <= -leadingInset + 1
        atEnd = offset + visible >= content + trailingInset - 1
    }

    /// Content moving right (back) scrolls toward the start; left (forward) toward the end.
    func lets(_ direction: TrackpadSwipe.Direction) -> Bool {
        direction == .back ? atStart : atEnd
    }
}

/// Decides, event by event, whether a two-finger scroll is a swipe. It has to start sideways and
/// go on far enough sideways; up and down stays scrolling. Until it's decided the events wait
/// (InputRouter holds them back and hands them on when it turns out to be scrolling).
struct SwipeRecognizer {
    enum Phase { case began, changed, ended }

    enum Verdict: Equatable {
        /// Not a swipe: the events so far go on to whatever scrolls.
        case scroll
        /// Not decided yet.
        case wait
        case swipe(TrackpadSwipe.Direction)
    }

    private var deciding = false
    private var direction: TrackpadSwipe.Direction?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0

    /// `allows`: whether the window can go that way now; asked once, when the direction is clear.
    mutating func feed(_ phase: Phase, dx: CGFloat, dy: CGFloat, allows: (TrackpadSwipe.Direction) -> Bool) -> Verdict {
        switch phase {
        case .began:
            self = SwipeRecognizer()
            deciding = true
        case .changed:
            guard deciding else { return .scroll }
        case .ended:
            return settle(.scroll)  // lifted before it was clear: it was scrolling
        }
        self.dx += dx
        self.dy += dy
        if direction == nil {
            guard self.dx != 0 || self.dy != 0 else { return .wait }
            guard let way = TrackpadSwipe.direction(dx: self.dx, dy: self.dy), allows(way) else { return settle(.scroll) }
            direction = way
        }
        guard let direction else { return .wait }
        // Turned back the other way, or up and down after all: scrolling.
        if (self.dx > 0) != (direction == .back) || abs(self.dy) >= max(abs(self.dx), TrackpadSwipe.distance) {
            return settle(.scroll)
        }
        if abs(self.dx) >= TrackpadSwipe.distance { return settle(.swipe(direction)) }
        return .wait
    }

    private mutating func settle(_ verdict: Verdict) -> Verdict {
        deciding = false
        return verdict
    }
}

/// The library's cover size, chosen by pinching on the trackpad (fingers apart: bigger), in
/// steps and remembered.
enum CoverSize: Int, CaseIterable {
    case small, regular, large, huge

    static let defaultsKey = "coverSize"

    var width: CGFloat {
        switch self {
        case .small: return 116
        case .regular: return 154
        case .large: return 196
        case .huge: return 240
        }
    }

    /// What's stored; the usual size when nothing (or something unknown) is.
    init(stored: Int?) {
        self = stored.flatMap(CoverSize.init(rawValue:)) ?? .regular
    }

    /// One step bigger (+1) or smaller (-1), stopping at either end.
    func stepped(_ delta: Int) -> CoverSize {
        let all = Self.allCases
        return all[max(0, min(all.count - 1, rawValue + delta))]
    }

    @MainActor
    static var current: CoverSize {
        get { CoverSize(stored: UserDefaults.standard.object(forKey: defaultsKey) as? Int) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// A pinch's movement in steps: one each time the fingers moved apart (+1) or together (-1) far
/// enough since the last.
struct PinchSteps {
    static let threshold: CGFloat = 0.25
    private var sum: CGFloat = 0

    mutating func begin() { sum = 0 }

    mutating func add(_ magnification: CGFloat) -> Int {
        sum += magnification
        if sum >= Self.threshold { sum = 0; return 1 }
        if sum <= -Self.threshold { sum = 0; return -1 }
        return 0
    }
}

/// How far a swipe has moved the window's page, for the levels to follow the fingers. Also where
/// Home's rail stands, for InputRouter to leave it its own scrolling.
@MainActor
final class SwipeStage: ObservableObject {
    static let shared = SwipeStage()

    struct Slide: Equatable {
        let id: Int
        /// The level being left, and the one being gone to (nil: back stays on this level and
        /// only drops the search).
        let from: Route
        let to: Route?
        let direction: TrackpadSwipe.Direction
        /// 0 at rest, 1 with the page all the way out.
        var progress: CGFloat = 0
    }

    @Published private(set) var slide: Slide?
    private var nextID = 0

    /// Where Home's rail and the library's search field are in the main window (SwiftUI's global
    /// coordinates, from the top left), so a swipe knows what the pointer is over; and where the
    /// rail stands.
    var areas: [SwipeArea.Kind: CGRect] = [:]
    var railEdges = ScrollEdges(atStart: true, atEnd: true)

    /// Whether `point` (from the window's top left) is on that area.
    func pointer(_ point: CGPoint, isOn kind: SwipeArea.Kind) -> Bool {
        areas[kind]?.contains(point) ?? false
    }

    func begin(from: Route, to: Route?, direction: TrackpadSwipe.Direction) -> Int {
        nextID += 1
        slide = Slide(id: nextID, from: from, to: to, direction: direction)
        return nextID
    }

    func move(_ id: Int, to progress: CGFloat) {
        guard slide?.id == id else { return }
        slide?.progress = min(1, max(0, progress))
    }

    /// The page comes back in after a swipe that didn't leave the level.
    func slideBack(_ id: Int) {
        withAnimation(.easeOut(duration: 0.25)) { move(id, to: 0) }
    }

    func end(_ id: Int) {
        guard slide?.id == id else { return }
        slide = nil
    }
}

/// A level of the main window while a swipe moves it: the page being left follows the fingers
/// (with Reduce Motion it only fades), and the one being gone to shows through when it's already
/// there behind it (the library behind a game's page).
struct SwipeLevel: ViewModifier {
    let route: Route
    /// Whether the level is on screen without a swipe (the library stays hidden behind a game's page).
    var shown = true
    /// False for what only dims (the library's darkening): it fades instead of moving.
    var moves = true
    @ObservedObject private var stage = SwipeStage.shared
    @Environment(\.reduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let slide = stage.slide
        let progress = slide?.progress ?? 0
        let leaving = shown && slide?.from == route
        let opacity: Double = !shown ? (slide?.to == route ? progress : 0)
            : !leaving ? 1
            : (moves && !reduceMotion ? 1 - 0.4 * progress : 1 - progress)
        let shift: CGFloat = leaving && moves && !reduceMotion ? (slide?.direction == .back ? progress : -progress) : 0
        content
            .opacity(opacity)
            .visualEffect { effect, proxy in effect.offset(x: shift * proxy.size.width) }
    }
}

/// Marks where a swipe has to leave the scrolling to the view: Home's rail (only past its end)
/// and the library's search field (never). Read by position when the fingers start, so it holds
/// whether the pointer moved there or the view came to the pointer.
struct SwipeArea: ViewModifier {
    enum Kind { case rail, search }

    let kind: Kind

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                SwipeStage.shared.areas[kind] = frame
            }
            .onDisappear { SwipeStage.shared.areas[kind] = nil }
            .modifier(RailEdges(active: kind == .rail))
    }

    /// Where the rail stands (macOS 15 and later tell; before, the rail keeps every swipe).
    private struct RailEdges: ViewModifier {
        let active: Bool

        func body(content: Content) -> some View {
            if !active {
                content
            } else if #available(macOS 15, *) {
                content.onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                    ScrollEdges(offset: geometry.contentOffset.x, content: geometry.contentSize.width,
                                visible: geometry.containerSize.width,
                                leadingInset: geometry.contentInsets.leading, trailingInset: geometry.contentInsets.trailing)
                } action: { _, edges in
                    SwipeStage.shared.railEdges = edges
                }
            } else {
                content.onAppear { SwipeStage.shared.railEdges = .unknown }
            }
        }
    }
}
