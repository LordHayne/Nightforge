import SwiftUI

/// One "Good to know" card while Steam installs: each is something Nightforge really does.
struct SetupTip: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let text: (_ playstation: Bool) -> String

    static var all: [SetupTip] {
        [
            SetupTip(id: "mac-first", symbol: "laptopcomputer", title: L10n.t("Mac versions first")) { _ in
                L10n.t("When a game also comes for the Mac, Nightforge takes the Mac version – without any Windows translation.")
            },
            SetupTip(id: "sharp", symbol: "sparkles", title: L10n.t("Sharp and smooth by itself")) { _ in
                L10n.t("Most Windows games get MetalFX sharpness and an even frame rate – 60 FPS on a 120 Hz display.")
            },
            SetupTip(id: "geforce-now", symbol: "cloud", title: L10n.t("Anti-cheat? Then through GeForce Now")) { _ in
                L10n.t("Games whose anti-cheat needs Windows itself stream through GeForce Now – with your copy from Steam.")
            },
            SetupTip(id: "menu-button", symbol: "gamecontroller", title: L10n.t("The menu button switches the view")) { playstation in
                playstation ? L10n.t("Options goes between Home and the library, △ opens a game's options, ○ goes back.")
                    : L10n.t("Menu goes between Home and the library, Y opens a game's options, B goes back.")
            },
            SetupTip(id: "trackpad", symbol: "hand.draw", title: L10n.t("Swipe and pinch")) { _ in
                L10n.t("Two fingers sideways go back. In the library, two fingers apart or together make the covers bigger or smaller.")
            },
            SetupTip(id: "welcome-back", symbol: "clock", title: L10n.t("Welcome back")) { _ in
                L10n.t("After every game Nightforge shows how long you played – and asks how it ran. It remembers that for the next start.")
            },
            SetupTip(id: "awake", symbol: "moon.zzz", title: L10n.t("Downloads keep the Mac awake")) { _ in
                L10n.t("While games download, your Mac doesn't go to sleep. The display may still turn off.")
            },
            SetupTip(id: "big-screen", symbol: "tv", title: L10n.t("Off to the big screen")) { _ in
                L10n.t("Plug in a monitor or TV: Nightforge and your games move over to it by themselves.")
            },
            SetupTip(id: "charger", symbol: "bolt", title: L10n.t("Charger too weak?")) { _ in
                L10n.t("If your charger gives too few watts for games, you see it at the top of the window – before the battery runs low.")
            },
            SetupTip(id: "rollback", symbol: "arrow.uturn.backward", title: L10n.t("Nightforge catches crashes")) { _ in
                L10n.t("When a game crashes with the newest engine, Nightforge starts it with the one before by itself.")
            },
            SetupTip(id: "dock", symbol: "dock.rectangle", title: L10n.t("Your games in the Dock")) { _ in
                L10n.t("Right-click Nightforge in the Dock: your last five games are there to start right away.")
            },
        ]
    }
}

/// The tip cards, one every 7 seconds, held while the pointer is on them or while Steam's sign-in
/// window waits (`paused`). The timer only runs while the card is on screen.
struct SetupTipCarousel: View {
    let paused: Bool
    let playstation: Bool
    @State private var index = 0
    @State private var hovering = false
    @State private var shown: CGFloat = 0
    @Environment(\.reduceMotion) private var reduceMotion

    private static let seconds = 7.0
    private struct Wait: Hashable { let index: Int; let held: Bool }

    var body: some View {
        let tips = SetupTip.all
        let tip = tips[index % tips.count]
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: tip.symbol)
                .font(size: 24, weight: .semibold, scales: false)
                .foregroundStyle(Theme.sodium)
                .frame(width: 60, height: 60)
                .background(GlassBackground(glass: .regular, shape: RoundedRectangle(cornerRadius: 19, style: .continuous)))
                .id("art.\(tip.id)")
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.t("Good to know").uppercased())
                        .font(size: 11, weight: .semibold)
                        .kerning(1.8)
                    Spacer()
                    Text("\(index % tips.count + 1) / \(tips.count)")
                        .font(size: 11, weight: .semibold).monospacedDigit()
                        .opacity(0.7)
                }
                .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title)
                        .font(size: 16.5, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    Text(tip.text(playstation))
                        .font(size: 14)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 40, alignment: .topLeading)
                }
                .id(tip.id)
                .transition(.opacity)
                HStack(spacing: 6) {
                    ForEach(tips.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index % tips.count ? Theme.sodium : Color.white.opacity(0.2))
                            .frame(width: i == index % tips.count ? 20 : 6, height: 6)
                            .contentShape(Rectangle().inset(by: -4))
                            .onTapGesture { index = i }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: 580, alignment: .leading)
        .background(GlassBackground(glass: .regular, shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
        // When the next one comes: a hairline, drawn as a scale so it costs no layout.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.sodium.opacity(0.7))
                .frame(height: 2)
                .scaleEffect(x: shown, anchor: .leading)
                .padding(.horizontal, 22)
                .opacity(paused || hovering ? 0 : 1)
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: index)
        .accessibilityElement(children: .combine)
        .task(id: Wait(index: index, held: paused || hovering)) {
            shown = 0
            guard !paused, !hovering else { return }
            withAnimation(.linear(duration: Self.seconds)) { shown = 1 }
            try? await Task.sleep(for: .seconds(Self.seconds))
            guard !Task.isCancelled else { return }
            index = (index + 1) % tips.count
        }
    }
}

/// The right half of "Connecting Steam": the controller test, and under it the tips. While Steam's
/// sign-in window waits for the player it goes quiet – pale, held, the pad not read.
struct SetupSidePanel: View {
    let paused: Bool
    @StateObject private var tester = PadTester()

    var body: some View {
        VStack(spacing: 24) {
            ControllerTestView(tester: tester)
            SetupTipCarousel(paused: paused, playstation: tester.layout != .xbox)
        }
        .opacity(paused ? 0.22 : 1)
        .saturation(paused ? 0 : 1)
        .allowsHitTesting(!paused)
        .accessibilityHidden(paused)
        .overlay(alignment: .top) {
            if paused {
                HStack(spacing: 8) {
                    Circle().fill(Theme.sodium).frame(width: 6, height: 6)
                    Text(L10n.t("Paused while Steam waits for you to sign in"))
                        .font(size: 13, weight: .medium)
                        .foregroundStyle(Theme.muted)
                }
                .offset(y: -30)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.5), value: paused)
        .onAppear { if !paused { tester.start() } }
        .onDisappear { tester.stop() }
        .onChange(of: paused) { _, held in held ? tester.stop() : tester.start() }
    }
}
