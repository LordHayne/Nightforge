// Checks PadFocus: entering, moving by position, adjusting, and staying in its own window:
// tests/PadFocusTest/run.sh
import AppKit
import SwiftUI

@main
struct PadFocusTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let focus = PadFocus.shared
        var pressed: [String] = []
        var value = 0
        var views: [NSView] = []

        // Window y grows upward: a top row (y 300) with two buttons, a picker in the middle,
        // and a bottom row (y 40) with play and options.
        func add(_ id: String, _ frame: NSRect, in window: NSWindow = window, enabled: Bool = true, adjust: ((Int) -> Void)? = nil) {
            let view = NSView(frame: frame)
            window.contentView!.addSubview(view)
            views.append(view)
            focus.register(id, .init(view: view, enabled: enabled, activate: { pressed.append(id) }, adjust: adjust))
        }
        add("top.left", NSRect(x: 40, y: 300, width: 80, height: 30))
        add("top.right", NSRect(x: 460, y: 300, width: 80, height: 30))
        add("picker", NSRect(x: 40, y: 170, width: 200, height: 30), adjust: { value += $0 })
        add("play", NSRect(x: 40, y: 40, width: 160, height: 50))
        add("options", NSRect(x: 230, y: 40, width: 50, height: 50))
        add("disabled", NSRect(x: 320, y: 40, width: 50, height: 50), enabled: false)
        add("elsewhere", NSRect(x: 40, y: 40, width: 50, height: 50), in: other)

        check(focus.move(dx: 0, dy: -1, in: window) && focus.focused == "play", "up from below enters at the bottom left: \(focus.focused ?? "nil")")
        focus.move(dx: 1, dy: 0, in: window)
        check(focus.focused == "options", "right moves along the row: \(focus.focused ?? "nil")")
        check(!focus.move(dx: 1, dy: 0, in: window) && focus.focused == "options", "disabled controls are skipped, nothing further right")
        focus.move(dx: 0, dy: -1, in: window)
        check(focus.focused == "picker", "up reaches the picker: \(focus.focused ?? "nil")")
        focus.move(dx: 1, dy: 0, in: window)
        focus.move(dx: 1, dy: 0, in: window)
        focus.move(dx: -1, dy: 0, in: window)
        check(value == 1 && focus.focused == "picker", "left/right on a picker change its value")
        focus.move(dx: 0, dy: -1, in: window)
        check(focus.focused == "top.left", "up goes to the nearest control above, not the far one: \(focus.focused ?? "nil")")
        focus.focusedItem(in: window)?.activate()
        check(pressed == ["top.left"], "A presses the highlighted control")
        check(focus.focusedItem(in: other) == nil, "focus in one window isn't focus in another")
        focus.clear()
        check(focus.move(dx: 0, dy: 1, in: window) && focus.focused == "top.left", "any other way enters at the top left")
        focus.unregister("top.left", view: views[0])
        check(focus.focused == nil, "a control that goes away takes the highlight with it")

        // A dialog: the highlight starts on its default answer (Keep), not on the × at the top.
        let dialog = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        add("dialog.close", NSRect(x: 400, y: 190, width: 32, height: 32), in: dialog)
        let keep = NSView(frame: NSRect(x: 220, y: 30, width: 90, height: 42))
        dialog.contentView!.addSubview(keep)
        views.append(keep)
        focus.register("dialog.keep", .init(view: keep, enabled: true, activate: {}, preferred: true))
        add("dialog.remove", NSRect(x: 320, y: 30, width: 110, height: 42), in: dialog)
        check(focus.move(dx: 0, dy: 1, in: dialog) && focus.focused == "dialog.keep", "a dialog starts on its default: \(focus.focused ?? "nil")")
        focus.move(dx: 1, dy: 0, in: dialog)
        check(focus.focused == "dialog.remove", "the other answer is one step away: \(focus.focused ?? "nil")")
        focus.clear()

        // The library grid: groups start their own rows, and a search's order isn't the grid's.
        // Games 0–2 installed, 3 in the store, 4–11 owned; four columns.
        func game(_ id: Int, _ install: InstallState) -> Game {
            var game = Game(appID: id, name: "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                            installDir: Engine.bottle.url, sizeOnDisk: 0)
            game.install = install
            return game
        }
        let games = (0..<3).map { game($0, .installed) } + [game(3, .inStore)] + (4..<12).map { game($0, .notInstalled) }
        let grid = GridLayout(games: games, columns: 4)
        check(grid.rows == [[0, 1, 2], [4, 5, 6, 7], [8, 9, 10, 11], [3]], "groups start new rows: \(grid.rows)")
        check(grid.index(from: 1, rows: 1) == 5, "↓ keeps the column into the next group")
        check(grid.index(from: 7, rows: -1) == 2, "↑ into a shorter row lands on its last card")
        check(grid.index(from: 0, rows: -1) == nil, "↑ from the first row leaves the grid")
        check(grid.index(from: 2, steps: 1) == 4, "→ goes on in the order on screen, past the store hit")
        check(grid.index(from: 11, steps: 1) == 3, "→ from the last owned game reaches the store hit")
        check(grid.index(from: 3, steps: 1) == 3, "→ stops at the end")

        scrolling()
        levels()

        print(failures == 0 ? "✓ PadFocus" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The pad on a long page (a game's): a page step down and up, never past either end, the
    /// highlighted control brought into view with room around it, and the right stick's speed.
    @MainActor
    static func scrolling() {
        for flipped in [true, false] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
            let document = flipped ? FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 2_000)) : NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 2_000))
            scroll.documentView = document
            window.contentView = scroll
            let page = PageScroll(scroll)!
            let name = flipped ? "flipped" : "not flipped"
            // How far down the page shows, 0 at the top.
            func down() -> CGFloat { flipped ? scroll.contentView.bounds.origin.y : 1_400 - scroll.contentView.bounds.origin.y }
            page.move(by: -10_000, animated: false)
            check(abs(down()) < 1 && page.canScroll && page.visibleHeight == 600, "\(name): at the top, more below")
            check(page.move(by: 270, animated: false) && abs(down() - 270) < 1, "\(name): down by 270: \(down())")
            check(PadFocus.shared.scroll(by: 130, in: window) && abs(down() - 400) < 1, "\(name): the stick scrolls the page: \(down())")
            page.move(by: 10_000, animated: false)
            check(abs(down() - 1_400) < 1, "\(name): never past the end: \(down())")
            check(!page.move(by: 50, animated: false) && !PadFocus.shared.page(down: true, in: window), "\(name): at the end, nothing more")
            page.move(by: -10_000, animated: false)
            check(!page.move(by: -50, animated: false), "\(name): at the top, nothing above")

            // A control 1 500 points down shows with 48 points below it; one at 100 with 96 above
            // (the game bar's room).
            let control = NSView(frame: flipped ? NSRect(x: 20, y: 1_500, width: 100, height: 40)
                                               : NSRect(x: 20, y: 2_000 - 1_540, width: 100, height: 40))
            document.addSubview(control)
            page.show(control.convert(control.bounds, to: scroll.contentView), top: 96, bottom: 48)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))  // smoothly, then there
            check(abs(down() - (1_540 + 48 - 600)) < 1, "\(name): the control below shows with room under it: \(down())")
            let high = NSView(frame: flipped ? NSRect(x: 20, y: 100, width: 100, height: 40) : NSRect(x: 20, y: 2_000 - 140, width: 100, height: 40))
            document.addSubview(high)
            page.show(high.convert(high.bounds, to: scroll.contentView), top: 96, bottom: 48)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            check(abs(down() - 4) < 1, "\(name): the one above shows with the game bar's room over it: \(down())")
            page.show(high.convert(high.bounds, to: scroll.contentView), top: 96, bottom: 48)
            check(abs(down() - 4) < 1, "\(name): already in sight: nothing moves")
        }
        check(InputRouter.stickSpeed(0.1) == 0 && InputRouter.stickSpeed(-0.1) == 0, "the stick's middle doesn't scroll")
        check(InputRouter.stickSpeed(1) == -1_600 && InputRouter.stickSpeed(-1) == 1_600, "pushed all the way: 1 600 points a second, up and down")
        check(abs(InputRouter.stickSpeed(-0.59)) < 400 && InputRouter.stickSpeed(-0.59) > 0, "half way: much slower, for reading")
    }
}

extension PadFocusTest {
    /// SwiftUI: a level kept out of sight (the library behind a game's page, at opacity 0) is off the
    /// map, though AppKit still sees its views; an open panel keeps the highlight to itself.
    @MainActor
    static func levels() {
        struct Page: View {
            var body: some View {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading) {
                        Spacer().frame(height: 120)
                        Button("Store") {}.padFocus("behind.chip", activate: {})
                        Spacer()
                    }
                    .opacity(0)
                    .padReachable(false)
                    VStack(alignment: .leading) {
                        HStack(alignment: .top) {
                            Button("Back") {}.padFocus("page.back", activate: {})
                            Spacer()
                            // Like the downloads panel, at the top right.
                            VStack {
                                Button("Close") {}.padFocus("panel.close", activate: {})
                                Button("Cancel") {}.padFocus("panel.cancel", activate: {})
                            }
                            .padZone(.panel)
                        }
                        Spacer()
                        Button("Play") {}.padFocus("page.play", preferred: true, activate: {})
                    }
                    .padding(20)
                }
                .frame(width: 600, height: 400)
            }
        }
        // Off screen: laid out like a real window, never seen.
        let window = NSWindow(contentRect: NSRect(x: -6_000, y: -6_000, width: 600, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Page())
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let focus = PadFocus.shared
        focus.clear()
        check(focus.move(dx: 0, dy: -1, in: window) && focus.focused == "page.play", "the page starts on Play: \(focus.focused ?? "nil")")
        focus.move(dx: 0, dy: -1, in: window)
        check(focus.focused == "page.back", "up from Play skips what's out of sight behind the page: \(focus.focused ?? "nil")")
        check(focus.move(dx: 0, dy: 1, in: window, within: .panel) && focus.focusedZone(in: window) == .panel,
              "a step in an open panel enters it: \(focus.focused ?? "nil")")
        focus.move(dx: 0, dy: 1, in: window, within: .panel)
        check(focus.focused == "panel.cancel" && !focus.move(dx: -1, dy: 0, in: window, within: .panel),
              "the panel keeps the highlight: nothing beside it counts")
        focus.clear()
        window.orderOut(nil)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
