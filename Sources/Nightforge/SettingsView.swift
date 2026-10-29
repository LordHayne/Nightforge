import AppKit
import GameController
import SwiftUI

/// Settings in tabs: where the games come from, how they run, the controller, and what
/// Nightforge is built on. The tabs are a row of buttons, so the pad reaches them too.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case stores, general, controller, storage, about

        var label: String {
            switch self {
            case .stores: return L10n.t("Stores")
            case .general: return L10n.t("General")
            case .controller: return L10n.t("Controller")
            case .storage: return L10n.t("Storage")
            case .about: return L10n.t("About")
            }
        }
    }

    @State private var tab: Tab
    @Environment(\.dismiss) private var dismiss

    init(tab: Tab = .general) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassDialogHeader(title: L10n.t("Settings"), id: "settings") { dismiss() }
                .padding(.horizontal, 28)
                .padding(.top, 28)
            Segmented(options: Tab.allCases.map { ($0, $0.label, nil) }, selection: tab, id: "settings.tab") { tab = $0 }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 2)
            Group {
                switch tab {
                case .stores: StoresSettings()
                case .general: GeneralSettings()
                case .controller: ControllerSettings()
                case .storage: StorageSettings()
                        .frame(height: 480)  // the list of games scrolls
                case .about: AboutSettings()
                        .frame(height: 480)  // the list of projects scrolls
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .toggleStyle(GlassSwitchStyle())
            .buttonStyle(GlassTextButtonStyle(small: true))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        // The design's dialog: thick glass over the dimmed library, not a window of its own.
        .glassDialogBackground()
    }
}

// MARK: - Stores

private struct StoresSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.bottlesRoot) private var bottlesRoot = ""
    @AppStorage(Prefs.Keys.runnerPath) private var runnerPath = ""
    /// Folded away unless something is filled in: most players never need it.
    @State private var showsOwnWine = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button(L10n.t("Open Steam")) { model.openSteam() }
                        .disabled(!Engine.isSteamInstalled)
                        .padFocus("settings.openSteam", enabled: Engine.isSteamInstalled, activate: { model.openSteam() })
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steam")
                        Text(steamStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                AccountStoreRow(store: model.epic, connect: model.connectEpic, disconnect: model.disconnectEpic)
                AccountStoreRow(store: model.gog, connect: model.connectGOG, disconnect: model.disconnectGOG)
            } footer: {
                Text(L10n.t("Games from every connected store show up together. Nightforge downloads and starts Epic and GOG games itself – no Epic launcher, no GOG Galaxy. You sign in in the store's own window; Nightforge never sees your login."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only for players who bring their own Wine setup; Nightforge needs none of it.
            Section {
                Button { showsOwnWine.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("CrossOver, Whisky and your own Wine"))
                            Text(L10n.t("Only needed to also show games from your own bottles."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsOwnWine ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsOwnWine ? L10n.t("On") : L10n.t("Off"))
                .padFocus("settings.ownWine", activate: { showsOwnWine.toggle() })
                if showsOwnWine {
                LabeledContent(L10n.t("Bottles Folder")) {
                    HStack {
                        TextField("", text: $bottlesRoot, prompt: Text(LibraryScanner.defaultBottlesRoot().path))
                            .labelsHidden()
                        Button(L10n.t("Choose …")) { model.chooseBottlesFolder() }
                            .padFocus("settings.chooseBottles", activate: { model.chooseBottlesFolder() })
                    }
                }
                LabeledContent("Wine") {
                    TextField("", text: $runnerPath, prompt: Text(Launcher.detectRunner()))
                        .labelsHidden()
                }
                Text(L10n.t("Nightforge brings everything it needs. Fill this in only to also show games from CrossOver or Whisky bottles: leave Wine empty for CrossOver, or enter the path to the wine binary of Whisky or your own Wine."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Rescan Library")) { model.reload() }
                    .padFocus("settings.rescan", activate: { model.reload() })
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsOwnWine)
        .onAppear { showsOwnWine = !bottlesRoot.isEmpty || !runnerPath.isEmpty }
    }

    private var steamStatus: String {
        guard Engine.isSteamInstalled else { return L10n.t("Not set up yet – Nightforge does it at the first start.") }
        let count = model.visibleCount(of: .steam)
        let games = count == 1 ? L10n.t("1 game") : L10n.t("%ld games", count)
        return Engine.steamSignedIn ? L10n.t("Signed in · %@", games) : L10n.t("Not signed in · %@", games)
    }
}

/// A store the player signs in to (Epic Games, GOG): connect in the store's own sign-in window,
/// then how its library stands – with a way out when the store couldn't be reached (the games from
/// last time still play).
private struct AccountStoreRow<Store: AccountStore>: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject var store: Store
    let connect: () -> Void
    let disconnect: () -> Void

    private var label: String { store.provider.label }
    private var key: String { store.provider.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent {
                HStack(spacing: 8) {
                    if store.isConnected && store.sync.state == .signedOut {
                        Button(store.connecting ? L10n.t("Waiting for sign-in …") : L10n.t("Sign In Again"), action: connect)
                            .buttonStyle(GlassTextButtonStyle(prominent: !store.connecting, small: true))
                            .padFocus("settings.\(key).signIn", activate: connect)
                    } else if store.isConnected && store.sync.failed {
                        Button { model.refreshStores(force: true) } label: {
                            Label(L10n.t("Try Again"), systemImage: "arrow.clockwise")
                        }
                        .padFocus("settings.\(key).retry", activate: { model.refreshStores(force: true) })
                    }
                    if store.isConnected {
                        Button(L10n.t("Disconnect"), action: disconnect)
                            .padFocus("settings.\(key).disconnect", activate: disconnect)
                    } else {
                        Button(store.connecting ? L10n.t("Waiting for sign-in …") : L10n.t("Connect"), action: connect)
                            .buttonStyle(GlassTextButtonStyle(prominent: !store.connecting, small: true))
                            .padFocus("settings.\(key).connect", activate: connect)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                    status
                        .font(.caption)
                }
            }
            if store.connecting {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.badge.key")
                        .foregroundStyle(Theme.sodium)
                    Text(L10n.t("%@'s sign-in page is open in a window. Once you're signed in, your games appear here by themselves.", label))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder private var status: some View {
        if !store.isConnected {
            Text(store.connecting ? L10n.t("Sign in in %@'s window", label) : L10n.t("Not connected"))
                .foregroundStyle(.secondary)
        } else {
            switch store.sync.state {
            case .syncing:
                Text(L10n.t("Updating …")).foregroundStyle(.secondary)
            case .failed(let reason):
                Text(store.sync.lastSuccess.map { L10n.t("%@ · last update %@", reason, Format.relative($0)) } ?? reason)
                    .foregroundStyle(Theme.sodium)
            case .signedOut:
                Text(L10n.t("%@ signed you out – your games stay here", label))
                    .foregroundStyle(Theme.sodium)
            case .ok:
                let count = model.visibleCount(of: store.provider)
                let games = count == 1 ? L10n.t("1 game") : L10n.t("%ld games", count)
                HStack(spacing: 6) {
                    Circle().fill(Theme.runsGreat).frame(width: 7, height: 7)
                    Text(store.sync.lastSuccess.map { L10n.t("%@ · up to date %@", games, Format.relative($0)) } ?? games)
                }
                .foregroundStyle(.secondary)
                .help(store.accountName.map { L10n.t("Signed in as %@", $0) } ?? "")
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.afterLaunch) private var afterLaunch = AfterLaunch.hide.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.Keys.performanceHUD) private var performanceHUD = false
    @AppStorage(Prefs.Keys.gameMode) private var gameMode = true
    @AppStorage(Prefs.Keys.sharpAndSmooth) private var sharpAndSmooth = true
    @AppStorage(Prefs.Keys.notifyDownloads) private var notifyDownloads = true
    @AppStorage(Prefs.Keys.saveBattery) private var saveBattery = false
    @AppStorage(Prefs.Keys.reduceMotion) private var reduceMotionSetting = ""
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .padFocus("settings.language", selection: $language, values: AppLanguage.allCases.map(\.rawValue))
                Toggle(isOn: $sharpAndSmooth) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Sharp & smooth"))
                        Text(L10n.t("Every game gets Apple's MetalFX upscaling to full Retina sharpness and an even frame rate that fits your display (60 FPS on a 120 Hz screen). Change it per game in its options."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padFocus("settings.sharp", toggle: $sharpAndSmooth)
                Toggle(isOn: $gameMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Game Mode"))
                        Text(L10n.t("Gives games priority on the CPU and graphics and halves Bluetooth latency for controllers and headphones. Turn it off if a game's sound crackles."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: gameMode) { _, _ in model.applySteamSettings() }
                .padFocus("settings.gameMode", toggle: $gameMode)
                Toggle(isOn: $saveBattery) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Save battery when unplugged"))
                        Text(L10n.t("On battery, games are capped at 30 FPS so the battery lasts longer. Plugged in, everything runs at full speed. Takes effect at the next game start."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padFocus("settings.saveBattery", toggle: $saveBattery)
                Toggle(isOn: $performanceHUD) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Performance HUD in games"))
                        Text(L10n.t("Shows frames per second and frame times while you play. Takes effect at the next game start."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: performanceHUD) { _, _ in model.applySteamSettings() }
                .padFocus("settings.hud", toggle: $performanceHUD)
                Toggle(isOn: $notifyDownloads) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Notify me when downloads finish"))
                        Text(L10n.t("A macOS notification with a Play button while Nightforge is in the background. Your last five games are in the Dock menu, too."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padFocus("settings.notify", toggle: $notifyDownloads)
                Picker(L10n.t("After Launch"), selection: $afterLaunch) {
                    ForEach(AfterLaunch.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .padFocus("settings.afterLaunch", selection: $afterLaunch, values: AfterLaunch.allCases.map(\.rawValue))
            }

            Section {
                Toggle(isOn: reduceMotion) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Reduce motion"))
                        Text(L10n.t("No zoom on covers, no sliding – plain cross-fades. Follows “Reduce motion” in macOS until you change it here."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padFocus("settings.reduceMotion", toggle: reduceMotion)
            } header: {
                SectionTitle(L10n.t("Accessibility"))
            }
        }
    }

    /// Shows what applies now; set back to what macOS says, it follows macOS again.
    private var reduceMotion: Binding<Bool> {
        Binding(
            get: { Prefs.reduceMotion(system: systemReduceMotion, stored: reduceMotionSetting) },
            set: { reduceMotionSetting = $0 == systemReduceMotion ? "" : ($0 ? "on" : "off") }
        )
    }
}

// MARK: - Controller

private struct ControllerSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.padGlyphs) private var padGlyphs = PadSymbols.Style.automatic.rawValue
    /// Bumped when a controller comes or goes, or its battery may have changed.
    @State private var refresh = 0
    @State private var pairing = false

    private static let bluetoothSettings = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    var body: some View {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        VStack(alignment: .leading, spacing: 14) {
            // The connected controllers in one box, like the design's.
            VStack(spacing: 0) {
                if pads.isEmpty {
                    Text(L10n.t("No controller connected."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(pads.enumerated()), id: \.offset) { index, pad in
                    if index > 0 { Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.horizontal, 14) }
                    padRow(pad)
                }
            }
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .id(refresh)

            Button(L10n.t("Pair a Controller …"), action: pair)
                .padFocus("settings.pair", cornerRadius: 15, activate: pair)
            if pairing {
                Text(L10n.t("PlayStation: hold PS and Create until the light flashes. Xbox: hold the pair button on top until the logo flashes. Nintendo: hold the sync button. Then choose it in the Bluetooth settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionTitle(L10n.t("Button labels"))
                .padding(.top, 6)
            Segmented(options: PadSymbols.Style.allCases.map { ($0.rawValue, $0.label, nil) }, selection: padGlyphs,
                      id: "settings.padGlyphs") { padGlyphs = $0 }
                .onChange(of: padGlyphs) { _, _ in model.refreshPadSymbols() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in refresh += 1; pairing = false }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in refresh += 1 }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }

    /// One controller: its name, that it works everywhere, and its battery.
    private func padRow(_ pad: GCController) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.sodium)
            VStack(alignment: .leading, spacing: 3) {
                Text(pad.vendorName ?? pad.productCategory)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(L10n.t("Connected · works in every game and in Nightforge"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = pad.battery, battery.batteryState != .unknown {
                Label("\(Int((battery.batteryLevel * 100).rounded())) %",
                      systemImage: battery.batteryState == .charging ? "battery.100.bolt" : Self.batterySymbol(battery.batteryLevel))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(battery.batteryLevel < 0.2 && battery.batteryState != .charging ? Theme.sodium : .secondary)
                    .help(L10n.t("Controller battery"))
            }
        }
        .padding(14)
    }

    /// Pairing happens in macOS: open its Bluetooth settings and say what to press on the controller.
    private func pair() {
        pairing = true
        NSWorkspace.shared.open(Self.bluetoothSettings)
    }

    private static func batterySymbol(_ level: Float) -> String {
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @EnvironmentObject private var model: LibraryModel
    /// Nightforge's own folder without the games in it (engine, Windows environment, Steam, caches);
    /// nil while it's being measured.
    @State private var ownSize: Int64?
    /// The shader caches' size; nil while measured or cleared.
    @State private var shaderSize: Int64?
    @State private var clearingShaders = false
    /// "Remove Nightforge completely": what it would take, once measured; then the question.
    @State private var removal: RemovalPlan?
    @State private var measuringRemoval = false
    @State private var removing = false
    @State private var removalError: String?

    private struct RemovalPlan: Identifiable {
        let id = UUID()
        /// The games in Nightforge's folder (Windows games, GOG's Mac versions) and their stores.
        let games: Int
        let gamesSize: Int64
        let stores: Set<Provider>
        let ownSize: Int64
        let savesSize: Int64
    }

    private struct Disk {
        let name: String
        let total: Int64
        let free: Int64
    }

    private var disk: Disk? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? SpaceCheck.existingFolder(for: Engine.supportDir).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return Disk(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total),
                    free: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Installed and downloading games, biggest first.
    private var games: [Game] {
        model.allGames.filter { $0.install != .notInstalled && $0.install != .inStore }.sorted { $0.sizeOnDisk > $1.sizeOnDisk }
    }

    var body: some View {
        let games = self.games
        let gamesSize = games.reduce(Int64(0)) { $0 + $1.sizeOnDisk }
        Form {
            if let disk {
                Section {
                    let own = ownSize ?? 0
                    let other = max(0, disk.total - disk.free - gamesSize - own)
                    StorageBar(parts: [(gamesSize, Theme.sodium), (own, Theme.storageNightforge), (other, .white.opacity(0.25))],
                               total: disk.total)
                    HStack(spacing: 16) {
                        legend(L10n.t("Games"), gamesSize, Theme.sodium)
                        if let ownSize {
                            legend("Nightforge", ownSize, Theme.storageNightforge)
                        } else {
                            HStack(spacing: 6) { GlassSpinner(size: 12); Text(L10n.t("Measuring Nightforge …")) }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        legend(L10n.t("Other"), other, .white.opacity(0.25))
                        Spacer()
                        Text(L10n.t("%@ free", Format.bytes(disk.free)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.t("“Nightforge” is the game engine, the Windows environment and Steam itself – everything besides the games."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionTitle(disk.name)
                }
            }

            Section {
                if games.isEmpty {
                    Text(L10n.t("No games on this Mac yet.")).foregroundStyle(.secondary)
                }
                ForEach(games) { game in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(Format.bytes(game.sizeOnDisk)).monospacedDigit().foregroundStyle(.secondary)
                            Button { reveal(game) } label: { Image(systemName: "folder") }
                                .help(L10n.t("Show game folder in Finder"))
                                .accessibilityLabel(L10n.t("Show game folder in Finder"))
                                .padFocus("storage.reveal.\(game.id)", activate: { reveal(game) })
                            if model.canUninstall(game) {
                                Button(game.isInstalled ? L10n.t("Uninstall …") : L10n.t("Cancel Download")) { uninstall(game) }
                                    .padFocus("storage.uninstall.\(game.id)", activate: { uninstall(game) })
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).lineLimit(1)
                            Text(game.lastPlayed.map { L10n.t("Last played %@", Format.relative($0)) } ?? L10n.t("Never played"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SectionTitle(L10n.t("Games on this Mac"))
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if let shaderSize {
                            Text(Format.bytes(shaderSize)).monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            GlassSpinner()
                        }
                        Button(L10n.t("Clear"), action: clearShaders)
                            .disabled(!canClearShaders)
                            .padFocus("storage.clearShaders", enabled: canClearShaders, activate: clearShaders)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Shader caches"))
                        Text(gameBusy ? L10n.t("Quit the game first – it's using them.")
                                      : L10n.t("Rebuilt by itself – the next start of each game takes a moment longer."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                SectionTitle(L10n.t("Caches"))
            }

            Section {
                HStack {
                    Button(L10n.t("Remove Nightforge Completely …"), action: planRemoval)
                        .disabled(gameBusy || measuringRemoval || removing)
                        .padFocus("storage.removeAll", enabled: !gameBusy && !measuringRemoval && !removing, activate: planRemoval)
                    if measuringRemoval || removing {
                        GlassSpinner()
                        Text(removing ? L10n.t("Removing …") : L10n.t("Measuring …")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.t("Deletes the game engine, the Windows environment with its games, the caches and the settings. Saves that are only on this Mac are copied to Documents first."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $removal) { plan in
            GlassQuestion(L10n.t("Remove Nightforge completely?"), message: removalMessage(plan), id: "removeAll") {
                // Return keeps everything; removing takes a deliberate click or a pad move first.
                Button(L10n.t("Cancel")) { removal = nil }
                    .buttonStyle(GlassTextButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padFocus("removeAll.cancel", cornerRadius: 21, preferred: true, activate: { removal = nil })
                Button(L10n.t("Remove Everything"), action: removeEverything)
                    .buttonStyle(GlassTextButtonStyle(destructive: true))
                    .padFocus("removeAll.confirm", cornerRadius: 21, activate: removeEverything)
            }
        }
        .sheet(item: DialogMessage.item($removalError)) { error in
            GlassQuestion(L10n.t("Nothing was removed"), message: error.text, id: "removeAllFailed") {
                Button(L10n.t("OK")) { removalError = nil }
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("removeAllFailed.ok", cornerRadius: 21, preferred: true, activate: { removalError = nil })
            }
        }
        .task { await measureShaders() }
        .task(id: model.allGames.count) {
            let builtIn = model.allGames.filter { $0.inNightforgeFolder && $0.install != .notInstalled && $0.install != .inStore }
                .reduce(Int64(0)) { $0 + $1.sizeOnDisk }
            let folder = Engine.supportDir
            let total = await Task.detached(priority: .utility) { LibraryScanner.folderSize(folder) }.value
            ownSize = max(0, total - builtIn)
        }
    }

    /// A game running or starting has its shaders open.
    private var gameBusy: Bool { !model.running.isEmpty || model.launchingID != nil }

    private var canClearShaders: Bool { !gameBusy && !clearingShaders && (shaderSize ?? 0) > 0 }

    nonisolated private static var shaderFolders: [URL] {
        ShaderCaches.folders(steamapps: LibraryScanner.libraryFolders(steamRoot: Engine.steamRoot, bottle: Engine.bottle))
    }

    private func measureShaders() async {
        shaderSize = await Task.detached(priority: .utility) { ShaderCaches.size(Self.shaderFolders) }.value
    }

    private func clearShaders() {
        guard canClearShaders else { return }
        clearingShaders = true
        shaderSize = nil
        Task {
            _ = await Task.detached(priority: .userInitiated) { ShaderCaches.clear(Self.shaderFolders) }.value
            clearingShaders = false
            await measureShaders()
        }
    }

    private func planRemoval() {
        guard !gameBusy else { return }
        measuringRemoval = true
        let games = model.allGames.filter { $0.inNightforgeFolder && $0.install != .notInstalled && $0.install != .inStore }
        let gamesSize = games.reduce(Int64(0)) { $0 + $1.sizeOnDisk }
        Task {
            let (own, saves) = await Task.detached(priority: .userInitiated) {
                let total = CompleteRemoval.targets().reduce(Int64(0)) { $0 + LibraryScanner.folderSize($1) }
                let saves = CompleteRemoval.saveSources().reduce(Int64(0)) { $0 + LibraryScanner.folderSize($1.source) }
                return (total, saves)
            }.value
            measuringRemoval = false
            removal = RemovalPlan(games: games.count, gamesSize: gamesSize, stores: Set(games.map(\.provider)),
                                  ownSize: max(0, own - gamesSize), savesSize: saves)
        }
    }

    private func removalMessage(_ plan: RemovalPlan) -> String {
        var parts: [String] = []
        if let games = CompleteRemoval.gamesNote(count: plan.games, size: plan.gamesSize, stores: plan.stores) { parts.append(games) }
        parts.append(L10n.t("The game engine, the Windows environment, caches and settings: %@.", Format.bytes(plan.ownSize)))
        if plan.savesSize > 0 {
            parts.append(L10n.t("Saves that are only on this Mac (%@) are copied to Documents › Nightforge Saves first.", Format.bytes(plan.savesSize)))
        }
        parts.append(L10n.t("Steam for Mac with its Mac games and your saves in your stores' clouds stay. Then Nightforge moves itself to the Bin and quits."))
        return parts.joined(separator: "\n\n")
    }

    private func removeEverything() {
        removal = nil
        removing = true
        Task {
            do {
                try await CompleteRemoval.run()
            } catch {
                removing = false
                removalError = L10n.t("The saves couldn't be copied to Documents (%@), so everything is still there.", error.localizedDescription)
            }
        }
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Format.bytes(bytes))").monospacedDigit()
        }
        .font(.caption)
    }

    private func reveal(_ game: Game) {
        let folder = FileManager.default.fileExists(atPath: game.installDir.path) ? game.installDir : game.installDir.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Asks in the main window, like the game's own Uninstall button.
    private func uninstall(_ game: Game) {
        model.closeSettings { model.requestUninstall(game) }
    }
}

/// How a disk is used: one bar, parts left to right, the rest free.
private struct StorageBar: View {
    let parts: [(bytes: Int64, color: Color)]
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.color)
                        .frame(width: max(0, geo.size.width * CGFloat(part.bytes) / CGFloat(max(total, 1))))
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @EnvironmentObject private var model: LibraryModel

    private struct Credit: Identifiable {
        let name: String
        let version: String?
        let role: String
        let license: String
        var id: String { name }
    }

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("No account. No telemetry. No background service."))
                            .fontWeight(.semibold)
                        Text(L10n.t("Nothing leaves your Mac unless you send it – a problem report opens on GitHub, filled in, and goes nowhere until you submit it."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "lock.fill")
                }
            } header: {
                SectionTitle(L10n.t("Nightforge %@", Updater.currentVersion))
            }

            Section {
                Text(L10n.t("Nightforge is free software under the GPL-3.0. It stands on these projects – thank you to everyone behind them. Their licence files ship inside the app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(credits) { credit in
                    LabeledContent {
                        Text(credit.license)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 220, alignment: .trailing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(credit.name)
                                if let version = credit.version {
                                    Text(version).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            Text(credit.role).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(L10n.t("Show Licence Files"), action: showLicences)
                    .padFocus("settings.licences", activate: showLicences)
                Button(L10n.t("Show the First Start Again"), action: showReveal)
                    .padFocus("settings.reveal", activate: showReveal)
            } header: {
                SectionTitle(L10n.t("Built on"))
            }
        }
    }

    /// From the component list at hand (the last one fetched, else the app's own) – no network.
    private var credits: [Credit] {
        let components = ComponentStore.localManifest()?.components ?? []
        return components.map { Credit(name: Self.name(of: $0), version: $0.version, role: Self.role(of: $0), license: $0.license) }
            + [Credit(name: "umu-protonfixes", version: nil, role: L10n.t("Fixes for single games"), license: "BSD-2-Clause"),
               Credit(name: "AreWeAntiCheatYet", version: nil, role: L10n.t("Which games' anti-cheat runs where"), license: "MIT")]
    }

    private static func name(of component: Component) -> String {
        switch component.id {
        case "wine": return "Wine"
        case "winecx": return "Wine (CrossOver)"
        case "d3dmetal": return "D3DMetal"
        case "dxmt": return "DXMT"
        case "dxvk-macos": return "DXVK"
        case "moltenvk": return "MoltenVK"
        case "winetricks": return "winetricks"
        case "cabextract": return "cabextract"
        case "gamepad": return L10n.t("Wine with controller support")
        case "graphics": return L10n.t("Wine with DXMT")
        default: return component.id
        }
    }

    private static func role(of component: Component) -> String {
        switch component.id {
        case "wine", "winecx", "gamepad", "graphics": return L10n.t("Runs Windows games on the Mac")
        case "d3dmetal": return L10n.t("DirectX 12 on Metal (Apple)")
        case "dxmt": return L10n.t("DirectX 10 and 11 on Metal")
        case "dxvk-macos": return L10n.t("DirectX 9 to 11 on Vulkan")
        case "moltenvk": return L10n.t("Vulkan on Metal")
        case "winetricks": return L10n.t("Installs what games need from Windows")
        case "cabextract": return L10n.t("Unpacks Windows installers")
        default:
            switch component.kind {
            case .engine: return L10n.t("Runs Windows games on the Mac")
            case .graphics: return L10n.t("Graphics")
            case .tool: return L10n.t("Tool")
            }
        }
    }

    /// The first start once more, in the main window: the welcome, the library check, the reveal.
    private func showReveal() {
        model.closeSettings { model.showFirstStartAgain() }
    }

    private func showLicences() {
        let files = ["LICENSE", "LICENSE-umu-protonfixes", "LICENSE-areweanticheatyet"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
        if files.isEmpty {
            NSWorkspace.shared.open(URL(string: "https://github.com/LordHayne/Nightforge")!)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }
}
