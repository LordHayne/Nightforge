import SwiftUI

/// The keyboard's state for its view. Two parts: the keys change when a thumb reaches another one,
/// the thumbs' places with every movement, so only the two points redraw at that pace.
@MainActor
final class PadKeyboardSession: ObservableObject {
    /// The two glow points, in key units.
    @MainActor
    final class Thumbs: ObservableObject {
        @Published var left = CGPoint.zero
        @Published var right = CGPoint.zero
    }

    @Published private(set) var layout: PadKeyLayout
    @Published private(set) var shift = PadKeyboard.Shift.off
    @Published private(set) var hovered: Set<String> = []
    /// How often each key went down: a new count lights it once more.
    @Published private(set) var presses: [String: Int] = [:]
    let thumbs = Thumbs()
    private(set) var board: PadKeyboard

    init(text: String) {
        board = PadKeyboard(text: text)
        layout = board.layout
        show()
    }

    /// A key clicked with the mouse. Done closes.
    func tap(_ id: String) -> [PadKeyboard.Event] {
        let events = board.tap(id)
        for case let .typed(_, key) in events { presses[key, default: 0] += 1 }
        show()
        return events
    }

    /// One look at the pad. What happened is handed back, for the motors and to close.
    func feed(_ input: PadKeyboard.Input) -> [PadKeyboard.Event] {
        let events = board.feed(input)
        for case let .typed(_, id) in events { presses[id, default: 0] += 1 }
        show()
        return events
    }

    private func show() {
        if layout != board.layout { layout = board.layout }
        if shift != board.shift { shift = board.shift }
        let keys = Set(board.pointers.values.compactMap(\.key))
        if hovered != keys { hovered = keys }
        if let left = board.pointers[.left]?.position, thumbs.left != left { thumbs.left = left }
        if let right = board.pointers[.right]?.position, thumbs.right != right { thumbs.right = right }
    }
}

/// The keyboard over the bottom of the library: a thumb per half with the blue seam between them,
/// which ends in the N on the space bar. The hits stay in view above it.
struct PadKeyboardPanel: View {
    @ObservedObject var session: PadKeyboardSession
    /// Whose names the buttons go by.
    let layout: PadLayout
    /// Where the search bar stands above it; the hits end there.
    var onBarFrame: (CGRect) -> Void = { _ in }
    /// Done, clicked with the mouse.
    var onDone: () -> Void = {}
    private let padding = PadKeyboardGeometry.panelPadding

    var body: some View {
        GeometryReader { geo in
            let inner = min(geo.size.width - 2 * Theme.gutter, 1_180) - 2 * padding
            let geometry = PadKeyboardGeometry.fitting(width: inner, windowHeight: geo.size.height)
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    LightSeam(geometry: geometry)
                    ForEach(session.layout.keys, id: \.id) { key in
                        let rect = geometry.rect(key)
                        KeyCap(label: key.label, height: geometry.keyHeight, hovered: session.hovered.contains(key.id),
                               armed: key.action == .shift && session.shift != .off, presses: session.presses[key.id] ?? 0)
                            .frame(width: rect.width, height: rect.height)
                            .contentShape(Rectangle())
                            .onTapGesture { if session.tap(key.id).contains(.submit) { onDone() } }
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    if let space = session.layout.key(id: "space") {
                        let rect = geometry.rect(space)
                        NightforgeMark()
                            .frame(height: rect.height * 0.6)
                            .offset(x: geometry.seamX - rect.height * 0.6 * 332 / 440 / 2, y: rect.minY + rect.height * 0.2)
                            .allowsHitTesting(false)
                    }
                    ThumbPoints(thumbs: session.thumbs, geometry: geometry)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                legend
            }
            .padding(padding)
            .background(Theme.slate.opacity(0.97), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink.opacity(0.1)) }
            .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, Theme.margins.bottom)
            .onAppear { onBarFrame(geometry.searchBarFrame(window: geo.size, bottomMargin: Theme.margins.bottom)) }
            .onChange(of: geo.size) { _, size in onBarFrame(geometry.searchBarFrame(window: size, bottomMargin: Theme.margins.bottom)) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Keyboard"))
    }

    private var legend: some View {
        HStack(spacing: 22) {
            Text(L10n.t("%@ %@ type", PadPart.l2.name(layout), PadPart.r2.name(layout)))
            Text(L10n.t("%@ delete", PadPart.l1.name(layout)))
            Text(L10n.t("%@ space", PadPart.r1.name(layout)))
            Text(L10n.t("%@ to the games", PadPart.start.name(layout)))
            Text(L10n.t("%@ back", PadPart.b.name(layout)))
        }
        .font(size: 13, weight: .medium)
        .foregroundStyle(Theme.muted)
    }
}

/// The search while the keyboard is open: the field from the library's header, grown and right
/// above the keys, so the eyes needn't go up and back. One element, moved from the field's place
/// to the middle and back; nothing here runs once it has arrived.
struct PadSearchBar: View {
    /// The window's own coordinates, which the field and the bar are measured in.
    static let space = "nightforge.window"

    let text: String
    /// The field's place in the header.
    let from: CGRect
    let to: CGRect
    let raised: Bool
    var close: () -> Void = {}

    var body: some View {
        let rect = raised ? to : from
        let scale = raised || to.height == 0 ? 1 : from.height / to.height
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.slate.opacity(0.97))
            Capsule().strokeBorder(Theme.sodium.opacity(0.8), lineWidth: 1.5)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(size: 20, weight: .semibold, scales: false)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 2) {
                    if text.isEmpty {
                        Rectangle().fill(Theme.sodium).frame(width: 2, height: 26)
                        Text(L10n.t("Search"))
                            .font(size: 24, weight: .semibold, scales: false)
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text(text)
                            .font(size: 24, weight: .semibold, scales: false)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Rectangle().fill(Theme.sodium).frame(width: 2, height: 26)
                    }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(size: 12, weight: .bold, scales: false)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(Theme.ink.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(raised ? 1 : 0)
                .accessibilityLabel(L10n.t("Close"))
            }
            .padding(.horizontal, 22)
            .frame(width: to.width, height: to.height, alignment: .leading)
            .scaleEffect(scale, anchor: .leading)
            .frame(width: rect.width, height: rect.height, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(raised)
    }
}

/// The seam from the N, between the halves, down to the space bar.
private struct LightSeam: View {
    let geometry: PadKeyboardGeometry

    var body: some View {
        Rectangle()
            .fill(LinearGradient(stops: [.init(color: NightforgeMark.seamColor.opacity(0), location: 0),
                                         .init(color: NightforgeMark.seamColor, location: 0.14),
                                         .init(color: Color(red: 0.43, green: 0.65, blue: 1), location: 0.55),
                                         .init(color: NightforgeMark.seamColor, location: 0.92)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 2, height: geometry.point(CGPoint(x: 0, y: PadKeyLayout.rows - 1)).y + 8)
            .shadow(color: NightforgeMark.seamColor.opacity(0.85), radius: 4)
            .offset(x: geometry.seamX - 1, y: -8)
            .allowsHitTesting(false)
    }
}

private struct KeyCap: View {
    let label: String
    let height: CGFloat
    let hovered: Bool
    let armed: Bool
    let presses: Int
    /// 1 as the key goes down, then it dies away: the only thing here that animates, on this one key.
    @State private var glow: Double = 0
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
        let size = height * 0.4
        ZStack {
            shape.fill(hovered
                       ? AnyShapeStyle(LinearGradient(colors: [Theme.sodium.opacity(0.08), Theme.sodium.opacity(0.26)], startPoint: .top, endPoint: .bottom))
                       : AnyShapeStyle(Theme.ink.opacity(0.08)))
            if hovered {
                VStack { Spacer(minLength: 0); Rectangle().fill(Theme.sodium).frame(height: 2) }
                    .clipShape(shape)
            }
            Text(label)
                .font(size: size, weight: .bold, scales: false)
                .foregroundStyle(hovered || armed ? Theme.sodium : Theme.ink)
            if glow > 0 {
                ZStack {
                    shape.fill(Theme.sodium)
                    Text(label)
                        .font(size: size, weight: .bold, scales: false)
                        .foregroundStyle(Theme.night)
                }
                .shadow(color: Theme.sodium.opacity(0.7), radius: 9)
                .opacity(glow)
            }
        }
        .onChange(of: presses) { _, _ in
            glow = 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { glow = 0 }
            }
        }
    }
}

/// The two thumbs, as points of glowing light.
private struct ThumbPoints: View {
    @ObservedObject var thumbs: PadKeyboardSession.Thumbs
    let geometry: PadKeyboardGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            point(thumbs.left)
            point(thumbs.right)
        }
        .allowsHitTesting(false)
    }

    private func point(_ place: CGPoint) -> some View {
        let at = geometry.point(place), size = geometry.keyHeight * 0.5
        return ZStack {
            Circle().fill(RadialGradient(stops: [.init(color: Theme.sodium.opacity(0.95), location: 0.1),
                                                 .init(color: Theme.sodium.opacity(0.45), location: 0.5),
                                                 .init(color: Theme.sodium.opacity(0), location: 1)],
                                         center: .center, startRadius: 0, endRadius: size / 2))
            Circle().fill(Color.white).frame(width: size * 0.26, height: size * 0.26)
                .overlay(Circle().stroke(Theme.night.opacity(0.4), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .offset(x: at.x - size / 2, y: at.y - size / 2)
    }
}
