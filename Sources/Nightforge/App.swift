import AppKit
import SwiftUI
import UserNotifications

@main
struct NightforgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LibraryModel()
    /// Views read strings through L10n, so the window content is rebuilt when this changes.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    init() {
        LegacyMigration.run()  // before anything reads settings or the data folder
        GameIDMigration.run()  // settings kept per game: from Steam app IDs to store and ID
        // macOS's "Enter Full Screen" out of the View menu: Nightforge's own takes ⌃⌘F (FullScreen).
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
    }

    var body: some Scene {
        Window("Nightforge", id: "main") {
            LibraryView()
                .id(language)
                .environmentObject(model)
                .modifier(AccessibilityFromSettings())
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("Rescan Library")) { model.rescan() }
                    .keyboardShortcut("r")
            }
            // A dialog over the library, not a window of its own.
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t("Settings …")) { model.openSettings() }
                    .keyboardShortcut(",")
            }
            // Also with a sheet open, which AppKit's own Quit waits for (Quit).
            CommandGroup(replacing: .appTermination) {
                Button(L10n.t("Quit Nightforge")) { Quit.now(by: "the menu") }
                    .keyboardShortcut("q")
            }
            // Without a Space of its own: starting a game slides nothing (FullScreen).
            CommandGroup(after: .toolbar) {
                Button(L10n.t("Full Screen")) { FullScreen.toggle() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        GameDisplay.follow()
        GameOverlay.resumeLeftovers()
        MacIntegration.setUp(delegate: self)
        // Quit from the Dock, `osascript … quit`, logging out: in place of AppKit's own handler,
        // which answered "User canceled" (-128) while a sheet was open (Quit).
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(quitEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
    }

    /// The answer waits until Nightforge really quits (Quit.now): logging out or restarting goes on
    /// then, rather than hearing yes while Nightforge is still there.
    @MainActor @objc private func quitEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let manager = NSAppleEventManager.shared()
        guard let held = manager.suspendCurrentAppleEvent() else {
            if !Quit.now(by: "an Apple Event") {
                reply.setParam(NSAppleEventDescriptor(int32: Int32(userCanceledErr)), forKeyword: keyErrorNumber)
            }
            return
        }
        guard !Quit.now(by: "an Apple Event", beforeQuitting: { manager.resume(withSuspensionID: held) }) else { return }
        // Removing itself: the sender hears that nothing happens now, as from AppKit.
        manager.replyAppleEvent(forSuspensionID: held)
            .setParam(NSAppleEventDescriptor(int32: Int32(userCanceledErr)), forKeyword: keyErrorNumber)
        manager.resume(withSuspensionID: held)
    }

    /// Never a silent no: the one time it waits, Quit says why in wine.log.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Quit.answer(removing: CompleteRemoval.isRunning) == .wait else { return .terminateNow }
        GameLog.note("Quit waits: Nightforge is removing itself and quits when that's done")
        return .terminateCancel
    }

    /// Right-click on the Dock icon: the last games played, one click to play.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MacIntegration.dockMenu(target: self, action: #selector(playFromDock(_:)))
    }

    /// nightforge://play/<app ID> – from a game's app in ~/Applications, Spotlight or a shortcut.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { MacIntegration.open($0) }
    }

    @MainActor @objc private func playFromDock(_ item: NSMenuItem) {
        MacIntegration.open(id: item.representedObject as? String, play: true)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        MacIntegration.handle(response)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.scheduleSteamShutdown()
        GameDisplay.quitting()
        GameOverlay.close()  // a game paused under the overlay runs on
    }
}
