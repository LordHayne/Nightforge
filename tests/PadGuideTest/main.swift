// Checks the players' tips (SetupTip, PadGuideRow, LaunchTip) for PlayStation and Xbox, without
// UserDefaults: tests/PadGuideTest/run.sh
import AppKit

@main
struct PadGuideTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func shows(_ name: String) -> Bool {
        name == PadSymbols.optionsCapsule
            || (NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil && !PadSymbols.isBare(name))
    }

    static func main() {
        let ps = PadSymbols(style: .playstation)
        let xbox = PadSymbols(style: .xbox)
        check(ps.layout == .playstation && xbox.layout == .xbox && PadSymbols().layout == .xbox, "the styles' layouts")

        // Setup tips: the buttons as they are now, in the controller's names.
        let tips = Dictionary(uniqueKeysWithValues: SetupTip.all.map { ($0.id, $0) })
        check(tips.count == SetupTip.all.count, "every tip has its own id")
        if let menu = tips["menu-button"] {
            let p = menu.text(true), x = menu.text(false)
            check(p.contains("△") && p.contains("L1") && p.contains("○") && !p.contains("LB"), "PlayStation: △ search, L1/R1, ○ back: \(p)")
            check(x.contains("Y") && x.contains("LB") && x.contains("B ") && !x.contains("△"), "Xbox: Y search, LB/RB, B back: \(x)")
        } else {
            check(false, "the controller tip is there")
        }
        if let overlay = tips["overlay"] {
            check(overlay.text(true).contains("L3 + R3"), "PlayStation: the overlay's tip says L3 + R3")
            check(overlay.text(false).contains("LS + RS"), "Xbox: the overlay's tip says LS + RS")
        } else {
            check(false, "the overlay's tip is there")
        }

        // Every button: each row with a symbol that shows its mark, or a printed name.
        for (pad, name) in [(ps, "PlayStation"), (xbox, "Xbox")] {
            let rows = PadGuideRow.all(pad)
            check(Set(rows.map(\.id)).count == rows.count, "\(name): one row per button")
            for row in rows {
                switch row.glyph {
                case .symbols(let names, _): check(!names.isEmpty && names.allSatisfy(shows), "\(name) \(row.id): \(names) show a mark")
                case .label(let text): check(!text.isEmpty, "\(name) \(row.id): a name")
                }
                check(!row.meaning.isEmpty, "\(name) \(row.id): what it does")
            }
        }
        let psRows = PadGuideRow.all(ps).map(\.id), xboxRows = PadGuideRow.all(xbox).map(\.id)
        check(psRows.contains("touch") && !xboxRows.contains("touch"), "the touchpad only on a PlayStation pad")
        check(xboxRows.first == "a" && xboxRows.contains("start") && xboxRows.contains("l3r3"), "A first, ☰ and both sticks listed")
        check(PadGuideRow.all(ps).first { $0.id == "start" }?.glyph == .symbols([PadSymbols.optionsCapsule]),
              "PlayStation's ☰ is the Options capsule")
        let bare = PadGuideRow.all(xbox, present: [.a, .b, .x, .y, .start, .l1, .r1, .l2, .r2, .up, .down, .left, .right, .ls, .rs])
        check(!bare.contains { ["l3r3", "select", "home", "touch"].contains($0.id) }, "a pad without stick buttons, View or Home: no rows for them")

        // The loading screen's tip: the first three starts with a controller, then never again.
        check(LaunchTip.pick(shown: 0, pad: ps)?.text.contains("L3 + R3") == true, "PlayStation: L3 + R3")
        check(LaunchTip.pick(shown: 2, pad: xbox)?.text.contains("LS + RS") == true, "Xbox: LS + RS, on the third start too")
        check(LaunchTip.pick(shown: 0, pad: ps)?.symbols == ps.overlayChord, "it draws the overlay's buttons")
        check(LaunchTip.pick(shown: LaunchTip.starts, pad: ps) == nil, "after three starts: no more")
        check(LaunchTip.pick(shown: 0, pad: nil) == nil, "no controller: no tip")

        print(failures == 0 ? "✓ PadGuide" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
