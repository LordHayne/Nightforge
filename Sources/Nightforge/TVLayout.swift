import AppKit
import SwiftUI

/// Whether Nightforge's window is on a TV (TVRules), kept up to date as it moves or a screen comes
/// and goes. The margins are read as constants all over the views, so the root view is rebuilt when
/// they change, as it is for the language.
@MainActor
final class TVLayout: ObservableObject {
    static let shared = TVLayout()
    @Published private(set) var isOn = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    private func update() {
        guard let screen = NSApp.windows.first(where: { $0.title == "Nightforge" })?.screen ?? NSScreen.main else { return }
        let onTV = GameDisplay.isTV(screen)
        let margins = TVRules.margins(onTV: onTV, screen: screen.frame.size)
        Theme.focusRing = TVRules.ringWidth(onTV: onTV)
        guard onTV != isOn || margins != Theme.margins else { return }
        GameLog.note("TV layout \(onTV ? "on" : "off") on \(screen.localizedName)")
        Theme.margins = margins
        isOn = onTV
    }
}
