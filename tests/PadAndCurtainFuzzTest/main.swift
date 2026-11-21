import CoreGraphics
import Foundation

var failures = 0
var shown = 0
func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !condition() {
        failures += 1
        shown += 1
        if shown <= 30 { print("✗ \(message())") }
    }
}

struct Random {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ limit: Int) -> Int { Int(next() % UInt64(max(limit, 1))) }
    mutating func coin(_ percent: Int = 50) -> Bool { below(100) < percent }
    mutating func unit() -> Float { Float(below(2001)) / 1000 - 1 }
}

// MARK: - The touchpad as a mouse

func touchpad(seed: UInt64) {
    var random = Random(seed)
    var pointer = TouchpadPointer()
    var now: TimeInterval = 0
    var held: TouchpadPointer.Button?
    var primary = TouchpadPointer.Finger(), secondary = TouchpadPointer.Finger()
    var clicked = false
    for step in 0..<4000 {
        now += [0.004, 0.008, 0.02, 0.2, 1][random.below(5)]
        if random.coin(30) { primary = random.coin(25) ? .init() : .init(x: random.unit(), y: random.unit()) }
        if random.coin(15) { secondary = random.coin(60) ? .init() : .init(x: random.unit(), y: random.unit()) }
        if random.coin(10) { clicked.toggle() }
        for action in pointer.feed(.init(primary: primary, secondary: secondary, clicked: clicked, now: now)) {
            switch action {
            case let .move(dx, dy), let .scroll(dx, dy):
                check(dx.isFinite && dy.isFinite && abs(dx) < 20_000 && abs(dy) < 20_000, "a sane movement (seed \(seed), step \(step)): \(dx) \(dy)")
            case let .press(button, clicks):
                check(held == nil, "a press with a button still down (seed \(seed), step \(step))")
                check((1...3).contains(clicks), "clicks \(clicks)")
                held = button
            case let .release(button):
                check(held == button, "the release of what was pressed (seed \(seed), step \(step))")
                held = nil
            }
        }
        if !clicked { check(held == nil, "no button down once the pad isn't pressed (seed \(seed), step \(step))") }
        if random.below(200) == 0 {
            let actions = pointer.reset()
            check(actions == (held.map { [.release($0)] } ?? []), "the reset lets go of what's held: \(actions)")
            held = nil
            clicked = false
            primary = .init()
            secondary = .init()
            check(pointer.isIdle, "and nothing's left of it")
            _ = pointer.feed(.init(now: now))
        }
    }
}

@MainActor final class Desk: PointerDesk {
    var hasAccess = false
    var location = CGPoint(x: 100, y: 100)
    var displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 1280, height: 720)]
    var now: TimeInterval = 0
    var own = false
    var postedDown = 0, ownDown = 0, explained = 0
    func isOwnWindow(at point: CGPoint) -> Bool { own }
    func postMove(to point: CGPoint, dragging: TouchpadPointer.Button?) { location = point }
    func warp(to point: CGPoint) { location = point }
    func postScroll(dx: CGFloat, dy: CGFloat) {}
    func postButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) { postedDown += down ? 1 : -1 }
    func ownButton(_ button: TouchpadPointer.Button, down: Bool, clicks: Int, at point: CGPoint) { ownDown += down ? 1 : -1 }
    func ownScroll(dx: CGFloat, dy: CGFloat, at point: CGPoint) {}
    func explainAccess() { explained += 1 }
}

@MainActor func driver(seed: UInt64) {
    var random = Random(seed)
    let desk = Desk()
    let driver = PointerDriver(desk: desk)
    var down = false
    for step in 0..<3000 {
        desk.now += 0.5
        // The permission and what's under the pointer can change while a button is down: its release has to go the same way.
        if random.coin(10) { desk.hasAccess.toggle() }
        if random.coin(10) { desk.own.toggle() }
        if random.coin(40) {
            driver.apply([.move(dx: CGFloat(random.unit()) * 900, dy: CGFloat(random.unit()) * 900)])
            check(desk.displays.contains { $0.contains(desk.location) }, "the pointer stays on a screen (seed \(seed), step \(step)): \(desk.location)")
        }
        if random.coin(20) {
            driver.apply(down ? [.release(.left)] : [.press(.left, clicks: 1)])
            down.toggle()
            check((0...1).contains(desk.postedDown) && (0...1).contains(desk.ownDown), "each press has one release, by its own way (seed \(seed), step \(step))")
            if !down { check(desk.postedDown == 0 && desk.ownDown == 0, "nothing stays down (seed \(seed), step \(step))") }
        }
    }
}

// MARK: - The pad keyboard

func keyboard(seed: UInt64) {
    var random = Random(seed)
    var board = PadKeyboard()
    var input = PadKeyboard.Input()
    var length = 0
    for step in 0..<6000 {
        input.now += [0.004, 0.016, 0.05, 0.5][random.below(4)]
        if random.coin(25) { input.primary = random.coin(30) ? .init() : .init(x: random.unit(), y: random.unit()) }
        if random.coin(25) { input.secondary = random.coin(50) ? .init() : .init(x: random.unit(), y: random.unit()) }
        if random.coin(10) { input.leftStick = CGPoint(x: CGFloat(random.unit()), y: CGFloat(random.unit())) }
        if random.coin(10) { input.rightStick = CGPoint(x: CGFloat(random.unit()), y: CGFloat(random.unit())) }
        if random.coin(8) { input.dpad = [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)][random.below(5)] }
        if random.coin(20) { input.l2 = (random.unit() + 1) / 2 }
        if random.coin(20) { input.r2 = (random.unit() + 1) / 2 }
        if random.coin(10) { input.l1.toggle() }
        if random.coin(8) { input.r1.toggle() }
        if random.coin(3) { input.l3.toggle() }
        if random.coin(3) { input.r3.toggle() }
        if random.coin(8) { input.a.toggle() }
        if random.coin(5) { input.touchClick.toggle() }
        if random.coin(2) { input.menu.toggle() }
        if random.coin(2) { input.b.toggle() }
        let before = board.text
        let events = board.feed(input)
        length = board.text.count
        check(length <= PadKeyboard.limit, "the limit holds (seed \(seed), step \(step)): \(length)")
        for side in PadKeyboard.Side.allCases {
            guard let pointer = board.pointers[side] else { check(false, "a pointer per half"); continue }
            check(PadKeyLayout.region(side).contains(pointer.position), "a pointer stays on its half (seed \(seed), step \(step)): \(pointer.position)")
            check(pointer.key != nil && board.layout.key(id: pointer.key) != nil, "and on a key of this page (seed \(seed), step \(step)): \(String(describing: pointer.key))")
        }
        if !events.contains(where: { if case .typed = $0 { return true }; return false }) {
            check(board.text == before, "no text changes without a key going down (seed \(seed), step \(step))")
        }
    }
}

func keyboardLayouts() {
    for page in [PadKeyPage.letters, .symbols] {
        for shifted in [false, true] {
            let layout = PadKeyLayout.make(page: page, shifted: shifted)
            check(Set(layout.keys.map(\.id)).count == layout.keys.count, "every key has its own id (\(page), shifted \(shifted))")
            for y in stride(from: CGFloat(0.05), to: PadKeyLayout.rows, by: 0.1) {
                for x in stride(from: CGFloat(0.05), to: PadKeyLayout.columns, by: 0.1) {
                    check(layout.key(at: CGPoint(x: x, y: y)) != nil, "no gap on the board (\(page)): \(x), \(y)")
                }
            }
            let overlapping = layout.keys.indices.flatMap { a in layout.keys.indices.filter { $0 > a }.map { (a, $0) } }
                .filter { layout.keys[$0.0].frame.intersects(layout.keys[$0.1].frame) }
            check(overlapping.isEmpty, "keys don't lie on each other (\(page)): \(overlapping.map { layout.keys[$0.0].id + "/" + layout.keys[$0.1].id })")
        }
    }
    // Typed to the end: the limit holds, and what doesn't fit isn't reported as typed.
    var full = PadKeyboard()
    var press = PadKeyboard.Input()
    var typed = 0
    for tick in 0..<200 {
        press.now += 0.05
        press.r1 = tick % 2 == 0
        for event in full.feed(press) { if case .typed = event { typed += 1 } }
    }
    check(full.text.count == PadKeyboard.limit, "the text stops at the limit: \(full.text.count)")
    check(typed == PadKeyboard.limit, "and no key past it says it went in: \(typed)")
    // A long text, as a saved search might be: never longer than the limit, and the last key doesn't half fit.
    check(PadKeyboard(text: String(repeating: "x", count: 500)).text.count == PadKeyboard.limit, "text from elsewhere is cut to the limit")
    check(PadKeyboard(text: String(repeating: "🇩🇪", count: 100)).text.count == PadKeyboard.limit, "by characters, not bytes")
}

// MARK: - Player numbers

func players(seed: UInt64) {
    var random = Random(seed)
    var slots = PlayerSlots<Int>()
    var connected: [(pad: Int, kind: String)] = []
    var nextPad = 0
    var numbers: [Int: Int] = [:]
    for step in 0..<3000 {
        if random.coin(55), connected.count < 7 {
            connected.insert((nextPad, ["DualSense", "Xbox", "Joy-Con"][random.below(3)]), at: random.below(connected.count + 1))
            nextPad += 1
        } else if !connected.isEmpty, random.coin(70) {
            connected.remove(at: random.below(connected.count))
        }
        let now = slots.update(connected: connected)
        let label = "(seed \(seed), step \(step))"
        check(Set(now.values).count == now.count, "no number twice \(label): \(now)")
        check(now.values.allSatisfy((1...4).contains), "only 1 to 4 \(label)")
        check(now.count == min(connected.count, 4), "as many numbers as there are seats and pads \(label): \(now.count) of \(connected.count)")
        for (pad, number) in numbers where connected.contains(where: { $0.pad == pad }) {
            check(now[pad] == number, "a pad that stays keeps its number \(label)")
        }
        numbers = now
    }
    check(PlayerLight.color(player: 0) == nil && PlayerLight.color(player: 5) == nil, "no light without a number")
}

func notices(seed: UInt64) {
    var random = Random(seed)
    var rules = ControllerNotices(started: 0)
    var now: TimeInterval = 10
    let objects = (0..<4).map { _ in NSObject() }
    var pads: [ControllerNotices.Pad] = []
    var there: Set<String> = []
    for step in 0..<3000 {
        now += [0.5, 3, 10][random.below(3)]
        if random.coin(20), pads.count < 4 {
            let object = objects[random.below(objects.count)]
            let id = ObjectIdentifier(object)
            if !pads.contains(where: { $0.id == id }) {
                pads.append(.init(id: id, name: "Pad \(random.below(2))", battery: random.coin(70) ? (random.unit() + 1) / 2 : nil, charging: random.coin(20)))
            }
        } else if !pads.isEmpty, random.coin(20) {
            pads.remove(at: random.below(pads.count))
        }
        if !pads.isEmpty, random.coin(30) { pads[random.below(pads.count)].battery = random.coin(80) ? (random.unit() + 1) / 2 : nil }
        for notice in rules.update(pads, now: now) {
            switch notice {
            case let .low(_, percent):
                check((0...15).contains(percent), "low means low (seed \(seed), step \(step)): \(percent)")
            case let .connected(_, battery):
                check(battery.map((0...100).contains) ?? true, "a battery between 0 and 100")
            case .lost: break
            }
        }
        there = Set(pads.map(\.name))
    }
    _ = there
}

func pointerRules() {
    // Every combination of what decides whether the pad is the Mac's pointer.
    for bits in 0..<128 {
        func on(_ n: Int) -> Bool { bits >> n & 1 == 1 }
        let (setting, keyboard, inFront, overlay, curtain, playing, frontGame) = (on(0), on(1), on(2), on(3), on(4), on(5), on(6))
        for asks in [false, true] {
            let works = PadPointerRules.works(setting: setting, keyboardOpen: keyboard, inFront: inFront, overlay: overlay, curtain: curtain,
                                              gamePlaying: playing, frontIsGame: frontGame, macOSAsks: asks)
            if !setting || keyboard { check(!works, "off, or the keyboard has the touchpad") }
            if setting, !keyboard, inFront || overlay || curtain { check(works, "Nightforge's own surfaces") }
            if setting, !keyboard, asks { check(works, "macOS's question comes first") }
            if setting, !keyboard, !inFront, !overlay, !curtain, !asks, playing || frontGame {
                check(!works, "a game has the touchpad: a moved pointer would turn its camera")
            }
            for hasTouchpad in [false, true] {
                let stick = PadPointerRules.stickIsPointer(works: works, hasTouchpad: hasTouchpad, inFront: inFront, overlay: overlay, curtain: curtain)
                if hasTouchpad || !works || overlay { check(!stick, "the stick only stands in, and not in the overlay") }
                if inFront && !curtain { check(!stick, "in Nightforge the stick scrolls") }
            }
        }
    }
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 20, width: 50, height: 50)]
    var random = Random(5)
    for _ in 0..<4000 {
        let point = CGPoint(x: CGFloat(random.below(1000)) - 400, y: CGFloat(random.below(1000)) - 400)
        let clamped = PadPointerRules.clamped(point, to: screens)
        check(screens.contains { $0.contains(clamped) }, "clamped onto a screen: \(point) → \(clamped)")
        if screens.contains(where: { $0.contains(point) }) { check(clamped == point, "a point on a screen stays") }
    }
    check(PadPointerRules.clamped(CGPoint(x: 5, y: 5), to: []) == CGPoint(x: 5, y: 5), "no screens known")
    check(PadPointerRules.stickVelocity(x: 0, y: 0) == .zero && PadPointerRules.stickVelocity(x: 0.1, y: 0.1) == .zero, "the stick's dead middle")
    check(PadPointerRules.stickVelocity(x: 1, y: 0).dx > 0 && PadPointerRules.stickVelocity(x: 0, y: 1).dy < 0, "right is right, up is up on the screen")
    check(PadPointerRules.screenScale(width: 0) == 0.75 && PadPointerRules.screenScale(width: 100_000) == 2, "within reason")
}

// MARK: - The way out of a curtain

func curtainEscape() {
    var states = 0
    typealias Reason = CurtainEscape.Reason
    for bits in 0..<128 {
        func on(_ n: Int) -> Bool { bits >> n & 1 == 1 }
        for waited in [0.0, 29.9, 30, 89.9, 90, 500] {
            for still in [nil, 0.0, 179.9, 180, 900] as [Double?] {
                for asked in [nil, 0.0, 119.9, 120] as [Double?] {
                    let look = CurtainEscape.Look(gameRuns: on(0), startGoesOn: on(1), questionUp: on(2), waited: waited, updating: on(3),
                                                  ownUpdate: on(4), ownSaves: on(5), updateStillFor: still, askedAgo: asked)
                    states += 1
                    let reason = CurtainEscape.reason(look)
                    let label = "\(look)"
                    if look.gameRuns || !look.startGoesOn || look.questionUp { check(reason == nil, "no way out over a game, after a start, under macOS's question: \(label)") }
                    if look.ownUpdate, !look.gameRuns, look.startGoesOn, !look.questionUp { check(reason == .ownUpdate, "Nightforge's own update can stop at once: \(label)") }
                    if reason == .storeQuiet || reason == .updating || reason == .updateStuck { check(waited >= CurtainEscape.openAfter, "a store gets its time first: \(label)") }
                    if reason == .updateStuck { check((still ?? 0) >= CurtainEscape.updateStuckAfter, "stuck only if it hasn't moved: \(label)") }
                    if CurtainEscape.asks(look) {
                        check(reason != nil && reason?.atOnce == false, "the question only for a store's start: \(label)")
                        check((asked ?? .infinity) >= CurtainEscape.askAgainAfter, "and not again right after: \(label)")
                        check(reason != .updating, "an update that moves doesn't ask: \(label)")
                    }
                    if let reason {
                        for pad in [nil, PadSymbols()] as [PadSymbols?] {
                            let tip = CurtainEscape.tip(reason, pad: pad)
                            check(!tip.text.isEmpty, "the curtain says how out: \(reason)")
                            check(pad == nil ? tip.symbols.isEmpty : !tip.symbols.isEmpty, "Esc without a pad, the pad's button with one")
                        }
                        let words = CurtainEscape.words(reason, game: "%@ odd", store: "Steam")
                        check(!words.title.isEmpty && !words.text.isEmpty, "the question has words: \(reason)")
                    }
                }
            }
        }
    }
    check(states == 128 * 6 * 5 * 4, "every state seen: \(states)")
    check(!LibraryModel.exitRaisesCurtain(curtainUp: true, sawPicture: true, judged: false, othersRunning: false), "a curtain that's up isn't raised again")
    check(!LibraryModel.exitRaisesCurtain(curtainUp: false, sawPicture: false, judged: false, othersRunning: false), "before the first picture the start tells")
    check(!LibraryModel.exitRaisesCurtain(curtainUp: false, sawPicture: true, judged: false, othersRunning: true), "another game still runs")
    check(LibraryModel.exitRaisesCurtain(curtainUp: false, sawPicture: true, judged: false, othersRunning: false), "the game went, the curtain comes")
    check(!LibraryModel.startWentWrong(message: "Word", hint: "Word", failed: false), "a word in a start that goes on keeps the curtain")
    check(LibraryModel.startWentWrong(message: "Other", hint: "Word", failed: false), "any other message is the start's end")
    check(LibraryModel.startWentWrong(message: nil, hint: nil, failed: true), "as is a failed start")
    check(!LibraryModel.startWentWrong(message: nil, hint: "Word", failed: false), "no message, nothing wrong")
}

// MARK: - What the 0.3.3 start reads along the way

func startNumbers() {
    let digits = String(repeating: "9", count: 400)
    let speed = Legendary.progress(inLog: "+ Download \(digits) MiB/s").speed
    check(speed != nil, "a speed past any number is read: \(String(describing: speed))")
    check(DownloadRate.label(speed: speed, secondsLeft: 60) != nil, "and shown on the curtain, no crash")
    check(DownloadRate.label(speed: .infinity, secondsLeft: nil) != nil && DownloadRate.label(speed: .nan, secondsLeft: nil) == nil, "inf and nan")
    check(DownloadRate.label(speed: 0, secondsLeft: 5) == nil && DownloadRate.label(speed: nil, secondsLeft: 5) == nil, "nothing known, nothing said")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: folder) }
    try? Data("before\n".utf8).write(to: folder)
    var follower = BattleNetStart.LogFollower(file: folder)
    check(follower.newText().isEmpty, "what was there before the command doesn't count")
    let handle = try? FileHandle(forWritingTo: folder)
    _ = try? handle?.seekToEnd()
    try? handle?.write(contentsOf: Data("Game launch options: programId=x\nhalf a li".utf8))
    let first = follower.newText()
    check(first == "Game launch options: programId=x\n", "only whole lines: \(first)")
    try? handle?.write(contentsOf: Data("ne\n".utf8))
    check(follower.newText() == "half a line\n", "the rest of it comes with its end")
    try? handle?.close()
    check(follower.newText().isEmpty, "and nothing twice")
    // The order: the log is followed from before the command goes out.
    let source = (try? String(contentsOfFile: "Sources/Nightforge/LibraryModel.swift", encoding: .utf8)) ?? ""
    if let start = source.range(of: "func launchBattleNetMac"), let made = source.range(of: "BattleNetStart.LogFollower(file: log)", range: start.upperBound..<source.endIndex),
       let sent = source.range(of: "BattleNetClient.send(command)", range: start.upperBound..<source.endIndex) {
        check(made.lowerBound < sent.lowerBound, "Battle.net's log is followed from before the command")
    } else {
        check(false, "the start through Battle.net follows its log")
    }
}

// MARK: - Steam only when it's needed

func steamOnDemand(seed: UInt64) {
    var random = Random(seed)
    var steam = SteamOnDemand()
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var facts = SteamOnDemand.Facts(onBattery: true, inFront: false, steamRunning: true, signInKept: true)
    var quietFor: TimeInterval = 0
    for step in 0..<6000 {
        let moved = TimeInterval([3, 10, 60, 600, 1200][random.below(5)])
        now = now.addingTimeInterval(moved)
        var next = facts
        if random.coin(6) { next.onBattery.toggle() }
        if random.coin(6) { next.inFront.toggle() }
        if random.coin(4) { next.gameBusy.toggle() }
        if random.coin(3) { next.downloading.toggle() }
        if random.coin(3) { next.gameRanRecently.toggle() }
        if random.coin(2) { next.clientUpdating.toggle() }
        if random.coin(2) { next.otherWork.toggle() }
        if random.coin(1) { next.signInKept.toggle() }
        if random.coin(4) { next.steamRunning.toggle() }
        if random.coin(4) { next.macBusy.toggle() }
        facts = next
        let wasAsleep = steam.asleep
        let unneeded = SteamOnDemand.unneeded(facts)
        quietFor = unneeded && !wasAsleep ? quietFor + moved : 0
        let result = steam.step(facts, now: now)
        let label = "(seed \(seed), step \(step)) \(facts)"
        switch result {
        case .sleep:
            check(unneeded, "Steam is only stopped when nothing needs it \(label)")
            check(!facts.inFront && facts.onBattery, "never with the player here or on the cable \(label)")
            check(!wasAsleep && steam.asleep, "and is marked \(label)")
            quietFor = 0
            facts.steamRunning = false
        case .wake:
            check(wasAsleep && !steam.asleep, "only what slept wakes \(label)")
            check(facts.inFront || !facts.onBattery, "and only for the player or the cable \(label)")
            check(!facts.macBusy, "and not under a Mac version \(label)")
            facts.steamRunning = true
        case .keep:
            break
        }
        if random.below(40) == 0 {
            let had = steam.asleep
            check(steam.wakeNow() == had && !steam.asleep, "Play wakes what slept, once \(label)")
            check(steam.wakeNow() == false, "and only once \(label)")
            if had { facts.steamRunning = true }
        }
    }
}

/// A Mac version started while Steam slept (the Dock's menu, a link): Steam stays down for it, and comes back after it.
func steamAfterMacGame() {
    var steam = SteamOnDemand()
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var facts = SteamOnDemand.Facts(onBattery: true, inFront: false, steamRunning: true, signInKept: true)
    _ = steam.step(facts, now: now)
    now = now.addingTimeInterval(SteamOnDemand.awayFor + 1)
    check(steam.step(facts, now: now) == .sleep && steam.asleep, "it sleeps")
    facts.steamRunning = false
    facts.inFront = true
    facts.macBusy = true
    now = now.addingTimeInterval(5)
    check(steam.step(facts, now: now) == .keep && steam.asleep, "the player's here, but a Mac version needs Steam for Mac: it sleeps on")
    facts.macBusy = false
    now = now.addingTimeInterval(5)
    check(steam.step(facts, now: now) == .wake && !steam.asleep, "and wakes once that's over")
    let source = (try? String(contentsOfFile: "Sources/Nightforge/SteamOnDemand.swift", encoding: .utf8)) ?? ""
    check(source.contains("steamOnDemand.stayAsleep()") && source.contains("if macGameBusy || (macDownload && !forStart) { return .stay }"), "coming to the front under a Mac version doesn't use up the wake")
}

@main struct Main {
    static func main() async {
        TestDefaults.useWorkFolder()
        await MainActor.run {
            for seed in UInt64(1)...12 {
                touchpad(seed: seed)
                driver(seed: seed)
                keyboard(seed: seed)
                players(seed: seed)
                notices(seed: seed)
                steamOnDemand(seed: seed)
            }
            keyboardLayouts()
            pointerRules()
            curtainEscape()
            startNumbers()
            steamAfterMacGame()
        }
        print(failures == 0 ? "✓ Pad, keyboard, player numbers, the curtain's way out and Steam only when needed" : "✗ \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
