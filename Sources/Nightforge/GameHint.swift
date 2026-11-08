import AppKit
import SwiftUI

/// A short note over a running game that takes nothing from it: never the keys, no clicks, gone after
/// six seconds (the controller that came late, 8.11.). The game keeps the front all along.
@MainActor
enum GameHint {
    private static var panel: NSPanel?
    private static var hide: DispatchWorkItem?
    static let seconds: Double = 6

    static func show(title: String, detail: String, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let panel = self.panel ?? make()
        self.panel = panel
        let host = NSHostingView(rootView: HintView(title: title, detail: detail).modifier(AccessibilityFromSettings()))
        host.sizingOptions = []
        panel.contentView = host
        let size = NSSize(width: 480, height: 86)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 28,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        hide?.cancel()
        let work = DispatchWorkItem { panel.orderOut(nil) }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private static func make() -> NSPanel {
        let panel = HintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Over the game's full screen, like the overlay, but it lets every click through.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        return panel
    }
}

/// Never key, never main: the game keeps its keys (a key panel made Unity games minimise, 7.11.).
private final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HintView: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(size: 18, weight: .semibold)
                .foregroundStyle(Theme.sodium)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(size: 14, weight: .bold)
                Text(detail).font(size: 12).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.night.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
