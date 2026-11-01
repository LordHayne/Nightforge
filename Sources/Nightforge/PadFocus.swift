import AppKit
import QuartzCore
import SwiftUI

/// Controller focus for everything besides the game list: buttons, switches and pickers in every
/// window (game options, settings, setup, the top bar) mark themselves with `.padFocus`, and the
/// pad moves a highlight between them by where they sit on screen – so a control added later
/// works with the pad without any wiring. The highlight only shows once the pad moved it.
@MainActor
final class PadFocus: ObservableObject {
    static let shared = PadFocus()

    struct Item {
        weak var view: NSView?
        var enabled: Bool
        var activate: () -> Void
        /// Left/right on a switch or picker change its value instead of moving on.
        var adjust: ((Int) -> Void)?
        /// Where the highlight starts in its window: a dialog's default answer, like Return.
        var preferred = false
    }

    @Published private(set) var focused: String?
    private var items: [String: Item] = [:]

    func register(_ id: String, _ item: Item) { items[id] = item }

    /// Only when `view` still holds the id: a control rebuilt under the same id keeps its place.
    func unregister(_ id: String, view: NSView) {
        guard items[id]?.view === view || items[id]?.view == nil else { return }
        items[id] = nil
        if focused == id { focused = nil }
    }

    /// The usable controls in `window`, with their frames in window coordinates (y up).
    private func entries(in window: NSWindow) -> [(id: String, item: Item, frame: CGRect)] {
        items.compactMap { id, item in
            guard item.enabled, let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  view.visibleRect.width > 0 else { return nil }
            return (id, item, view.convert(view.bounds, to: nil))
        }
    }

    func hasItems(in window: NSWindow) -> Bool { !entries(in: window).isEmpty }

    /// The focused control when it's in `window`.
    func focusedItem(in window: NSWindow) -> Item? {
        guard let focused else { return nil }
        return entries(in: window).first { $0.id == focused }?.item
    }

    func clear() { focused = nil }

    /// Puts the highlight on a control, as when a list closes and it goes back to its chip.
    func focus(_ id: String) { focused = id }

    /// Brings the highlighted control into view where a scroll view hides it, with room around it
    /// (`top` more where a bar covers the top, like a game page's) – smoothly, as the trackpad
    /// would, not with a jump.
    func reveal(_ id: String?, top: CGFloat = 48, bottom: CGFloat = 48) {
        guard let id, let view = items[id]?.view else { return }
        guard let scroll = PageScroll(view.enclosingScrollView) else {
            view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -48))
            return
        }
        scroll.show(view.convert(view.bounds, to: scroll.clip), top: top, bottom: bottom)
    }

    /// Down (or up) a page past its first or last control, `fraction` of what shows at a time, or
    /// false at its end. The pad on a game's page reaches what has no control of its own (the
    /// description, the cards under the screenshots).
    @discardableResult
    func page(down: Bool, in window: NSWindow, fraction: CGFloat = 0.45) -> Bool {
        guard let scroll = pageScroll(in: window) else { return false }
        return scroll.move(by: (down ? 1 : -1) * scroll.visibleHeight * fraction, animated: true)
    }

    /// Scrolls `points` down (negative: up) at once – the right stick, frame by frame.
    @discardableResult
    func scroll(by points: CGFloat, in window: NSWindow) -> Bool {
        pageScroll(in: window)?.move(by: points, animated: false) ?? false
    }

    /// What the pad scrolls in `window`: the scroll view around the highlighted control, else the
    /// biggest one that has more than it shows (a game's page, the library's grid, Settings).
    private func pageScroll(in window: NSWindow) -> PageScroll? {
        if let focused, let view = items[focused]?.view, view.window === window, let scroll = PageScroll(view.enclosingScrollView), scroll.canScroll {
            return scroll
        }
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        return found.compactMap(PageScroll.init).filter(\.canScroll)
            .max { $0.clip.bounds.width * $0.clip.bounds.height < $1.clip.bounds.width * $1.clip.bounds.height }
    }

    /// Moves the highlight one step (dx: -1 left, 1 right; dy: -1 up, 1 down). With nothing
    /// focused yet, it starts on the preferred control (a dialog's default answer); else up enters
    /// from the bottom (the main window's action row, above the games) and any other direction
    /// from the top. Returns false when there's nothing that way.
    @discardableResult
    func move(dx: Int, dy: Int, in window: NSWindow) -> Bool {
        let all = entries(in: window)
        guard !all.isEmpty else { return false }
        guard let current = all.first(where: { $0.id == focused }) else {
            if let preferred = all.first(where: { $0.item.preferred }) {
                focused = preferred.id
                return true
            }
            let sorted = all.sorted { a, b in
                abs(a.frame.midY - b.frame.midY) > 8 ? a.frame.midY > b.frame.midY : a.frame.minX < b.frame.minX
            }
            // Bottom row when coming up from below: its leftmost control (the play button).
            let start = dy < 0 ? sorted.filter { abs($0.frame.midY - sorted.last!.frame.midY) < 8 }.min { $0.frame.minX < $1.frame.minX }
                               : sorted.first
            focused = start?.id
            return start != nil
        }
        if dx != 0, let adjust = current.item.adjust {
            adjust(dx)
            return true
        }
        // Nearest control in that direction; straying sideways costs more than distance.
        let from = current.frame
        let best = all.filter { $0.id != current.id }.compactMap { other -> (String, CGFloat)? in
            let along: CGFloat, across: CGFloat
            if dx != 0 {
                along = (other.frame.midX - from.midX) * CGFloat(dx)
                across = abs(other.frame.midY - from.midY)
            } else {
                along = (from.midY - other.frame.midY) * CGFloat(dy)  // window y grows upward
                across = abs(other.frame.midX - from.midX)
            }
            // Sideways stays in the row (within 45°); up and down may reach across to the next one.
            guard along > 4, dx == 0 || across < along else { return nil }
            return (other.id, along + across * 2)
        }.min { $0.1 < $1.1 }
        guard let best else { return false }
        focused = best.0
        return true
    }
}

extension View {
    /// Makes a control reachable with the pad. `activate` is what A does on it; `adjust`, for
    /// switches and pickers, what left/right do. `shape` is the highlight's corner radius;
    /// `preferred` marks a dialog's default answer, where the highlight starts.
    func padFocus(_ id: String, enabled: Bool = true, cornerRadius: CGFloat = 10, preferred: Bool = false,
                  activate: @escaping () -> Void, adjust: ((Int) -> Void)? = nil) -> some View {
        modifier(PadFocusModifier(id: id, enabled: enabled, cornerRadius: cornerRadius, preferred: preferred,
                                  activate: activate, adjust: adjust))
    }

    /// A switch: A and left/right flip it.
    func padFocus(_ id: String, enabled: Bool = true, toggle: Binding<Bool>) -> some View {
        padFocus(id, enabled: enabled, activate: { toggle.wrappedValue.toggle() },
                 adjust: { _ in toggle.wrappedValue.toggle() })
    }

    /// A picker: left/right step through `values`, A steps forward and wraps around.
    func padFocus<Value: Equatable>(_ id: String, enabled: Bool = true, selection: Binding<Value>, values: [Value]) -> some View {
        func step(_ delta: Int, wrap: Bool) {
            guard !values.isEmpty else { return }
            let index = values.firstIndex(of: selection.wrappedValue) ?? 0
            let next = wrap ? (index + delta + values.count) % values.count : min(max(index + delta, 0), values.count - 1)
            selection.wrappedValue = values[next]
        }
        return padFocus(id, enabled: enabled, activate: { step(1, wrap: true) }, adjust: { step($0, wrap: false) })
    }
}

private struct PadFocusModifier: ViewModifier {
    let id: String
    let enabled: Bool
    let cornerRadius: CGFloat
    let preferred: Bool
    let activate: () -> Void
    let adjust: ((Int) -> Void)?
    @ObservedObject private var focus = PadFocus.shared

    func body(content: Content) -> some View {
        content
            .background(PadAnchor(id: id, enabled: enabled, preferred: preferred, activate: activate, adjust: adjust))
            .overlay {
                if focus.focused == id {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.sodium, lineWidth: 3)
                        .padding(-5)
                        .shadow(color: Theme.sodium.opacity(0.5), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: focus.focused == id)
    }
}

/// Puts the control on the map: its NSView tells PadFocus the window and where it sits, and every
/// SwiftUI update hands over fresh actions (they capture the view's current state).
private struct PadAnchor: NSViewRepresentable {
    let id: String
    let enabled: Bool
    let preferred: Bool
    let activate: () -> Void
    let adjust: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(id)
        PadFocus.shared.register(id, .init(view: view, enabled: enabled, activate: activate, adjust: adjust, preferred: preferred))
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        MainActor.assumeIsolated {
            if let id = view.identifier?.rawValue { PadFocus.shared.unregister(id, view: view) }
        }
    }
}

/// A vertical scroll view as the pad moves it: in "down" and "up", whichever way its content is
/// flipped, never past either end.
@MainActor
struct PageScroll {
    let scroll: NSScrollView
    let clip: NSClipView
    let document: NSView

    init?(_ scroll: NSScrollView?) {
        guard let scroll, let document = scroll.documentView else { return nil }
        self.scroll = scroll
        self.clip = scroll.contentView
        self.document = document
    }

    var visibleHeight: CGFloat { clip.bounds.height }
    private var range: CGFloat { max(0, document.frame.height - clip.bounds.height) }
    var canScroll: Bool { range > 1 }

    /// How far down it is, 0 at the top.
    private var down: CGFloat {
        clip.isFlipped ? clip.bounds.origin.y : range - clip.bounds.origin.y
    }

    private func origin(down: CGFloat) -> NSPoint {
        let clamped = min(max(down, 0), range)
        return NSPoint(x: clip.bounds.origin.x, y: clip.isFlipped ? clamped : range - clamped)
    }

    /// False when it's at that end already.
    @discardableResult
    func move(by points: CGFloat, animated: Bool) -> Bool {
        let target = min(max(down + points, 0), range)
        guard abs(target - down) > 0.5 else { return false }
        set(origin(down: target), animated: animated)
        return true
    }

    /// Scrolls just enough that `rect` (in the clip view's coordinates) shows, with room above and below.
    func show(_ rect: NSRect, top: CGFloat, bottom: CGFloat) {
        let height = clip.bounds.height
        // Distance from the content's top to the rect's top and bottom edge.
        let rectTop = clip.isFlipped ? rect.minY : document.frame.height - rect.maxY
        let rectBottom = rectTop + rect.height
        var target = down
        if rectTop - top < down {
            target = rectTop - top
        } else if rectBottom + bottom > down + height {
            target = min(rectBottom + bottom - height, rectTop - top)
        }
        guard abs(target - down) > 0.5 else { return }
        set(origin(down: target), animated: true)
    }

    private func set(_ origin: NSPoint, animated: Bool) {
        let still = Prefs.reduceMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                       stored: UserDefaults.standard.string(forKey: Prefs.Keys.reduceMotion) ?? "")
        if animated && !still {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(origin)
            } completionHandler: { [scroll, clip] in
                MainActor.assumeIsolated { scroll.reflectScrolledClipView(clip) }
            }
        } else {
            clip.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(clip)
        }
    }
}
