import CoreGraphics
import Foundation

/// One key of the pad keyboard: where it is, in key units from the board's top left.
struct PadKey: Equatable {
    enum Action: Equatable { case text(String), space, backspace, shift, page, done }

    let id: String
    let label: String
    let action: Action
    let frame: CGRect
}

enum PadKeyPage: Equatable { case letters, symbols }

/// QWERTZ in a plain grid, without the typewriter's stagger: each thumb reaches its keys by position,
/// and a straight column is the larger target. Five columns for the left thumb, six for the right.
struct PadKeyLayout: Equatable {
    static let columns: CGFloat = 11
    static let rows: CGFloat = 5
    /// Where the left thumb's half ends: after T, G and V.
    static let split: CGFloat = 5

    let keys: [PadKey]

    static func make(page: PadKeyPage, shifted: Bool) -> PadKeyLayout {
        let top: [String]
        switch page {
        case .letters:
            top = ["1234567890ß", "qwertzuiopü", "asdfghjklöä", "yxcvbnm-."]
        case .symbols:
            top = ["1234567890ß", "!\"§$%&/()=?", "@#€+*~':;_\\", "<>|[]{}^,."]
        }
        var keys: [PadKey] = []
        for (row, line) in top.enumerated() {
            // The fourth row holds Shift on its left and Backspace on its right, on the symbols page
            // a key in place of Shift (ten of them on that row).
            var column: CGFloat = 0
            if row == 3 && page == .letters {
                keys.append(special("shift", "⇧", .shift, x: 0, y: 3, width: 1))
                column = 1
            }
            for character in line {
                let plain = String(character)
                let text = shifted && page == .letters && plain != "ß" ? plain.uppercased() : plain
                keys.append(PadKey(id: plain, label: text, action: .text(text),
                                   frame: CGRect(x: column, y: CGFloat(row), width: 1, height: 1)))
                column += 1
            }
        }
        keys.append(special("backspace", "⌫", .backspace, x: 10, y: 3, width: 1))
        keys.append(special("page", page == .letters ? "?123" : "ABC", .page, x: 0, y: 4, width: 2))
        keys.append(special("space", " ", .space, x: 2, y: 4, width: 7))
        keys.append(special("done", "↵", .done, x: 9, y: 4, width: 2))
        return PadKeyLayout(keys: keys)
    }

    private static func special(_ id: String, _ label: String, _ action: PadKey.Action, x: CGFloat, y: CGFloat, width: CGFloat) -> PadKey {
        PadKey(id: id, label: label, action: action, frame: CGRect(x: x, y: y, width: width, height: 1))
    }

    /// The part of the board a thumb or stick stays in.
    static func region(_ side: PadKeyboard.Side) -> CGRect {
        side == .left ? CGRect(x: 0, y: 0, width: split, height: rows)
            : CGRect(x: split, y: 0, width: columns - split, height: rows)
    }

    func key(id: String?) -> PadKey? { id.flatMap { id in keys.first { $0.id == id } } }

    func key(at point: CGPoint) -> PadKey? { keys.first { $0.frame.contains(point) } }

    /// How far past its edge a key stays hit, in key units: a thumb resting on a border doesn't make
    /// the highlight and the haptics flutter between two keys.
    static let stickiness: CGFloat = 0.14

    /// The key under `point`; while it's near enough, still the one it was on.
    func hit(_ point: CGPoint, current: String?) -> PadKey? {
        if let key = key(id: current), key.frame.insetBy(dx: -Self.stickiness, dy: -Self.stickiness).contains(point) { return key }
        return key(at: point)
    }
}

/// The on-screen keyboard's input, without a view: each thumb has a pointer on its half of the board,
/// L2/R2 type at the start of their travel, L1 deletes, R1 is the space. A DualSense or DualShock
/// uses the touchpad's halves, any other controller a stick per half; the d-pad and A walk the whole
/// board as a fallback. Feed it a snapshot of the pad; `events` tell the view what to tick.
struct PadKeyboard {
    enum Side: Equatable, CaseIterable { case left, right }
    enum Shift: Equatable { case off, once, locked }

    enum Event: Equatable {
        /// A pointer reached another key: a light tick in that hand.
        case hover(Side, String)
        /// A key went down: a firmer tick. `side` is nil for the shoulder buttons.
        case typed(Side?, String)
        case submit
        case close
    }

    /// One look at the pad.
    struct Input: Equatable {
        var primary = TouchpadPointer.Finger()
        var secondary = TouchpadPointer.Finger()
        var leftStick = CGPoint.zero
        var rightStick = CGPoint.zero
        var dpad = CGPoint.zero
        var l2: Float = 0
        var r2: Float = 0
        var l1 = false, r1 = false
        var l3 = false, r3 = false
        var a = false, b = false, menu = false
        var touchClick = false
        var now: TimeInterval = 0
    }

    struct Pointer: Equatable {
        var position: CGPoint
        var key: String?
    }

    /// The touchpad's outer edge is hard to reach with a thumb: this much of it counts as the board's edge.
    static let edge: CGFloat = 0.06
    static let stickDead: CGFloat = 0.18
    /// Keys per second with a stick at its end.
    static let stickSpeed: CGFloat = 9
    /// Trigger travel: a key goes down here, early in the pull, and the trigger has to come back past
    /// `triggerRelease` for the next one. Ticks of the same key need no full release.
    static let triggerPress: Float = 0.25
    static let triggerRelease: Float = 0.12
    static let limit = 64

    private(set) var text: String
    private(set) var shift = Shift.off
    private(set) var page = PadKeyPage.letters
    private(set) var layout = PadKeyLayout.make(page: .letters, shifted: false)
    private(set) var pointers: [Side: Pointer]
    /// The pointer A and the touchpad's click type with: the one that moved last.
    private(set) var lastSide = Side.right
    /// How far a sliding thumb moves the pointer after it landed: 1 follows the pad exactly, less is finer.
    var sensitivity: CGFloat = 1

    private struct Slot: Equatable {
        var side: Side
        var landing: CGPoint
        var board: CGPoint
    }

    private struct Latch {
        var down = false
        mutating func update(_ value: Float) -> Bool {
            if down {
                if value <= PadKeyboard.triggerRelease { down = false }
                return false
            }
            guard value >= PadKeyboard.triggerPress else { return false }
            down = true
            return true
        }
    }

    private struct Repeater {
        var next: TimeInterval?
        mutating func update(down: Bool, now: TimeInterval, first: TimeInterval, then: TimeInterval) -> Bool {
            guard down else {
                next = nil
                return false
            }
            guard let due = next else {
                next = now + first
                return true
            }
            guard now >= due else { return false }
            next = now + then
            return true
        }
    }

    private var slots: [Slot?] = [nil, nil]
    private var left = Latch(), right = Latch()
    private var deleteRepeat = Repeater()
    private var dpadRepeat = Repeater()
    private var dpadWay = CGPoint.zero
    private var last = Input()

    init(text: String = "") {
        self.text = String(text.prefix(Self.limit))
        // The thumbs start on F and J, where the fingers rest on a real keyboard.
        let start = PadKeyLayout.make(page: .letters, shifted: false)
        let f = start.key(id: "f")!, j = start.key(id: "j")!
        pointers = [.left: Pointer(position: CGPoint(x: f.frame.midX, y: f.frame.midY), key: f.id),
                    .right: Pointer(position: CGPoint(x: j.frame.midX, y: j.frame.midY), key: j.id)]
    }

    mutating func feed(_ input: Input) -> [Event] {
        var events: [Event] = []
        let elapsed = CGFloat(min(max(input.now - last.now, 0), 0.1))
        track(input.primary, slot: 0, &events)
        track(input.secondary, slot: 1, &events)
        steer(.left, input.leftStick, elapsed, &events)
        steer(.right, input.rightStick, elapsed, &events)
        walk(input, &events)

        if left.update(input.l2) { type(with: .left, &events) }
        if right.update(input.r2) { type(with: .right, &events) }
        if pressed(\.a, input) || pressed(\.touchClick, input) { type(with: lastSide, &events) }
        if deleteRepeat.update(down: input.l1, now: input.now, first: 0.4, then: 0.07) { perform(.backspace, id: "backspace", side: nil, &events) }
        if pressed(\.r1, input) { perform(.space, id: "space", side: nil, &events) }
        if pressed(\.l3, input) { perform(.shift, id: "shift", side: nil, &events) }
        if pressed(\.r3, input) { perform(.page, id: "page", side: nil, &events) }
        if pressed(\.menu, input) { events.append(.submit) }
        if pressed(\.b, input) { events.append(.close) }
        last = input
        return events
    }

    private func pressed(_ button: KeyPath<Input, Bool>, _ input: Input) -> Bool {
        input[keyPath: button] && !last[keyPath: button]
    }

    // MARK: Pointers

    /// A finger belongs to the half it landed on until it lifts: sliding over the middle it stays at
    /// its half's edge. A second finger on a half already taken waits.
    private mutating func track(_ finger: TouchpadPointer.Finger, slot: Int, _ events: inout [Event]) {
        guard finger.isDown else {
            slots[slot] = nil
            return
        }
        guard let held = slots[slot] else {
            let side: Side = finger.x < 0 ? .left : .right
            guard slots[1 - slot]?.side != side else { return }
            let point = Self.boardPoint(finger, side: side)
            slots[slot] = Slot(side: side, landing: point, board: point)
            place(side, at: point, &events)
            return
        }
        let now = Self.boardPoint(finger, side: held.side)
        place(held.side, at: CGPoint(x: held.board.x + (now.x - held.landing.x) * sensitivity,
                                     y: held.board.y + (now.y - held.landing.y) * sensitivity), &events)
    }

    /// Where the finger is on its half of the board. Not limited to it: `place` does that.
    private static func boardPoint(_ finger: TouchpadPointer.Finger, side: Side) -> CGPoint {
        let region = PadKeyLayout.region(side)
        let across = side == .left ? CGFloat(finger.x) + 1 : CGFloat(finger.x)
        let down = (1 - CGFloat(finger.y)) / 2
        let u = (across - edge) / (1 - 2 * edge), v = (down - edge) / (1 - 2 * edge)
        return CGPoint(x: region.minX + u * region.width, y: region.minY + v * region.height)
    }

    /// A stick moves its pointer as fast as it's pushed. While a thumb is on that half, the thumb has it.
    private mutating func steer(_ side: Side, _ stick: CGPoint, _ elapsed: CGFloat, _ events: inout [Event]) {
        guard !slots.contains(where: { $0?.side == side }), elapsed > 0, let from = pointers[side]?.position else { return }
        let push = hypot(stick.x, stick.y)
        guard push > Self.stickDead else { return }
        let amount = min(1, (push - Self.stickDead) / (1 - Self.stickDead))
        let travel = amount * amount * Self.stickSpeed * elapsed / push
        place(side, at: CGPoint(x: from.x + stick.x * travel, y: from.y - stick.y * travel), &events)
    }

    /// One key at a time, over the whole board: the way across the middle hands over to the other pointer.
    private mutating func walk(_ input: Input, _ events: inout [Event]) {
        let way = input.dpad
        if way != dpadWay {
            dpadWay = way
            dpadRepeat = Repeater()
        }
        guard dpadRepeat.update(down: way != .zero, now: input.now, first: 0.38, then: 0.11) else { return }
        step(dx: way.x > 0 ? 1 : (way.x < 0 ? -1 : 0), dy: way.y > 0 ? -1 : (way.y < 0 ? 1 : 0), &events)
    }

    private mutating func step(dx: Int, dy: Int, _ events: inout [Event]) {
        guard let pointer = pointers[lastSide], let current = layout.key(id: pointer.key) else { return }
        // Left or right goes next to this key; up or down keeps the column, also across the long space bar.
        let target = dx != 0
            ? CGPoint(x: dx > 0 ? current.frame.maxX + 0.5 : current.frame.minX - 0.5, y: current.frame.midY)
            : CGPoint(x: pointer.position.x, y: dy > 0 ? current.frame.maxY + 0.5 : current.frame.minY - 0.5)
        guard let next = layout.key(at: target) else { return }
        let reaches = PadKeyLayout.region(lastSide).intersects(next.frame)
        let side: Side = reaches ? lastSide : (lastSide == .left ? .right : .left)
        let x = dx != 0 ? next.frame.midX : pointer.position.x
        pointers[side]?.key = nil  // no hanging on to the key it came from
        place(side, at: CGPoint(x: x, y: next.frame.midY), &events)
    }

    private mutating func place(_ side: Side, at point: CGPoint, _ events: inout [Event]) {
        guard var pointer = pointers[side] else { return }
        let region = PadKeyLayout.region(side)
        let limited = CGPoint(x: min(max(point.x, region.minX), region.maxX - 0.001),
                              y: min(max(point.y, region.minY), region.maxY - 0.001))
        let key = layout.hit(limited, current: pointer.key)?.id
        pointer.position = limited
        if let key, key != pointer.key { events.append(.hover(side, key)) }
        pointer.key = key
        pointers[side] = pointer
        lastSide = side
    }

    // MARK: Typing

    private mutating func type(with side: Side, _ events: inout [Event]) {
        guard let key = layout.key(id: pointers[side]?.key) else { return }
        perform(key.action, id: key.id, side: side, &events)
    }

    private mutating func perform(_ action: PadKey.Action, id: String, side: Side?, _ events: inout [Event]) {
        switch action {
        case let .text(characters):
            guard insert(characters) else { return }
            if shift == .once {
                shift = .off
                rebuild()
            }
        case .space:
            guard insert(" ") else { return }
        case .backspace:
            guard !text.isEmpty else { return }
            text.removeLast()
        case .shift:
            shift = shift == .off ? .once : (shift == .once ? .locked : .off)
            rebuild()
        case .page:
            page = page == .letters ? .symbols : .letters
            rebuild()
        case .done:
            events.append(.submit)
            return
        }
        events.append(.typed(side, id))
    }

    private mutating func insert(_ characters: String) -> Bool {
        guard text.count + characters.count <= Self.limit else { return false }
        text += characters
        return true
    }

    /// Other labels or another page; each pointer stays where it is and takes the key now under it.
    private mutating func rebuild() {
        layout = PadKeyLayout.make(page: page, shifted: shift != .off)
        for side in Side.allCases {
            guard let position = pointers[side]?.position else { continue }
            pointers[side]?.key = layout.key(at: position)?.id
        }
    }
}

/// Where the keys are on screen, for a board `width` points wide. A key is never drawn smaller than
/// it's readable from the sofa; the split gives each thumb its half and the light seam its place.
struct PadKeyboardGeometry: Equatable {
    let keyWidth: CGFloat
    let keyHeight: CGFloat
    static let gap: CGFloat = 6
    static let splitGap: CGFloat = 18

    /// The keys that fit `width`, up to the size where a wider board only adds thumb travel.
    static func fitting(width: CGFloat) -> PadKeyboardGeometry {
        let room = (width - (PadKeyLayout.columns - 1) * gap - splitGap) / PadKeyLayout.columns
        let keyWidth = max(44, min(104, room.rounded(.down)))
        return PadKeyboardGeometry(keyWidth: keyWidth, keyHeight: max(40, min(68, (keyWidth * 0.72).rounded())))
    }

    private func x(_ column: CGFloat) -> CGFloat {
        column * (keyWidth + Self.gap) + (column >= PadKeyLayout.split ? Self.splitGap : 0)
    }

    var size: CGSize {
        CGSize(width: PadKeyLayout.columns * keyWidth + (PadKeyLayout.columns - 1) * Self.gap + Self.splitGap,
               height: PadKeyLayout.rows * keyHeight + (PadKeyLayout.rows - 1) * Self.gap)
    }

    /// The middle of the gap between the halves.
    var seamX: CGFloat { x(PadKeyLayout.split) - (Self.gap + Self.splitGap) / 2 }

    func rect(_ key: PadKey) -> CGRect {
        let minX = x(key.frame.minX), maxX = x(key.frame.maxX) - Self.gap
        // A key's right edge at the split doesn't reach over the gap, one across it does.
        let right = key.frame.maxX == PadKeyLayout.split ? maxX - Self.splitGap : maxX
        return CGRect(x: minX, y: key.frame.minY * (keyHeight + Self.gap), width: right - minX, height: keyHeight)
    }

    func point(_ place: CGPoint) -> CGPoint {
        CGPoint(x: x(place.x), y: place.y * (keyHeight + Self.gap))
    }
}
