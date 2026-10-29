import AppKit
import GameController
import SwiftUI

/// Reads the connected controller for the first start's test. It only looks: InputRouter keeps
/// its handlers, so the pad still works the page. A 30-per-second look, only while the test is on
/// screen and a controller is there; the reading changes only when the pad does.
@MainActor
final class PadTester: ObservableObject {
    struct Press: Equatable {
        let part: PadPart
        let count: Int
    }

    /// nil: no controller.
    @Published private(set) var layout: PadLayout?
    @Published private(set) var name = ""
    @Published private(set) var battery: Float?
    @Published private(set) var reading = PadReading()
    /// What was tried since this controller came, and the last new press.
    @Published private(set) var tried: Set<PadPart> = []
    @Published private(set) var last: Press?
    private(set) var parts: Set<PadPart> = []

    private var controller: GCController?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var down: Set<PadPart> = []

    func start() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach() }
            })
        }
        attach()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func attach() {
        let current = GCController.current.flatMap { $0.extendedGamepad != nil ? $0 : nil }
            ?? GCController.controllers().first { $0.extendedGamepad != nil }
        if current !== controller {
            controller = current
            tried = []
            last = nil
            down = []
            reading = PadReading()
        }
        guard let current, let pad = current.extendedGamepad else {
            layout = nil
            timer?.invalidate()
            timer = nil
            return
        }
        layout = PadLayout(pad)
        name = ControllerStatus.shortName(current.vendorName ?? current.productCategory)
        parts = PadPart.present(on: pad)
        battery = current.battery.flatMap { $0.batteryState == .unknown ? nil : $0.batteryLevel }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func look() {
        guard let pad = controller?.extendedGamepad else { return }
        let now = PadReading(pad)
        guard now != reading else { return }
        reading = now
        let pressed = now.pressedParts.intersection(parts)
        let fresh = pressed.subtracting(down)
        down = pressed
        if let part = PadPart.allCases.last(where: fresh.contains) {
            tried.formUnion(fresh)
            last = Press(part: part, count: (last?.count ?? 0) + 1)
        }
    }
}

/// The first start's controller test: "Connect your controller" with a calm outline, or the
/// controller in glass whose buttons, sticks and triggers light up, the shoulder buttons as chips
/// above it, and under it what the button does in Nightforge.
struct ControllerTestView: View {
    @ObservedObject var tester: PadTester

    var body: some View {
        VStack(spacing: 0) {
            heading
            ZStack(alignment: .top) {
                PadDrawing(layout: tester.layout, reading: tester.reading)
                GeometryReader { geo in
                    ShoulderChips(layout: tester.layout, reading: tester.reading)
                        .padding(.horizontal, geo.size.width * 0.07)
                        .offset(y: geo.size.height * 60 / PadDrawing.size.height - 34)
                }
            }
            .aspectRatio(PadDrawing.size.width / PadDrawing.size.height, contentMode: .fit)
            .frame(maxWidth: 470)
            .padding(.top, 14)

            Group {
                if let layout = tester.layout, let last = tester.last {
                    MeaningPill(part: last.part, layout: layout)
                        .id(last.count)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else if tester.layout != nil {
                    Text(L10n.t("Press a button – here it says what it does in Nightforge."))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 46)
            .animation(.easeOut(duration: 0.25), value: tester.last)

            if tester.layout != nil { counter }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var heading: some View {
        if tester.layout != nil {
            VStack(spacing: 6) {
                Text(L10n.t("Controller detected: %@", tester.name))
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("Press a few buttons – they light up."))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 8) {
                Text(L10n.t("Connect your controller"))
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("By Bluetooth or USB cable – Nightforge recognises PlayStation and Xbox controllers by itself."))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Pair a Controller …"), action: Self.pair)
                    .buttonStyle(GlassTextButtonStyle(small: true))
                    .padFocus("setup.pair", cornerRadius: 15, activate: Self.pair)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var counter: some View {
        let total = tester.parts.count
        let done = total > 0 && tester.tried.count >= total
        return HStack(spacing: 6) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                Text(L10n.t("Everything works"))
            } else {
                Text(L10n.t("%ld of %ld tried", tester.tried.count, total))
            }
            if let battery = tester.battery {
                Text("·").foregroundStyle(Color.white.opacity(0.2))
                Text(L10n.t("Battery %ld %%", Int((battery * 100).rounded()))).foregroundStyle(Theme.muted.opacity(0.85))
            }
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .foregroundStyle(done ? Theme.runsGreat : Theme.muted.opacity(0.85))
        .padding(.top, 4)
    }

    private static func pair() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}

/// L1 L2 · R1 R2 just above the controller, like the key chips in the hint bar: lit while pressed,
/// the triggers filling with how far they're pulled.
private struct ShoulderChips: View {
    let layout: PadLayout?
    let reading: PadReading

    var body: some View {
        HStack(spacing: 6) {
            chip(.l1)
            chip(.l2)
            Spacer(minLength: 0)
            chip(.r1)
            chip(.r2)
        }
        .opacity(layout == nil ? 0.5 : 1)
    }

    private func chip(_ part: PadPart) -> some View {
        let value = layout == nil ? 0 : CGFloat(reading.value(part))
        let trigger = part == .l2 || part == .r2
        let lit = value > (trigger ? 0.6 : 0.5)
        return Text(part.name(layout ?? .playstation))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(lit ? Theme.night : Theme.ink.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(minWidth: 34, minHeight: 24)
            .background {
                if lit {
                    Capsule().fill(Theme.sodium).shadow(color: Theme.sodium.opacity(0.7), radius: 8)
                } else {
                    ZStack(alignment: .leading) {
                        GlassBackground(glass: .regular, shape: Capsule())
                        if trigger && value > 0.02 {
                            GeometryReader { geo in
                                Rectangle().fill(Theme.sodium.opacity(0.7)).frame(width: geo.size.width * value)
                            }
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .fixedSize()
    }
}

/// "✕  In Nightforge: Selects – on Home it starts the game".
private struct MeaningPill: View {
    let part: PadPart
    let layout: PadLayout

    var body: some View {
        HStack(spacing: 12) {
            if let symbol = part.symbol(layout) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.night, Theme.sodium)
            } else {
                Text(part.name(layout))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Theme.night)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Theme.sodium, in: Capsule())
            }
            (Text(L10n.t("In Nightforge:") + " ").foregroundColor(Theme.muted) + Text(part.meaning).foregroundColor(Theme.ink))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(height: 42)
        .background(GlassBackground(glass: .regular, shape: Capsule()))
        .accessibilityElement(children: .combine)
    }
}
