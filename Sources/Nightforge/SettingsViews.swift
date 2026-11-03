import AppKit
import SwiftUI

struct GameOptionsSheet: View {
    let game: Game
    /// What Nightforge knows about the game: which layers fit it and which way "Automatic" takes.
    let insight: GameInsight?
    let report: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: GameOptions
    /// Known fixes for the game, so "Automatic" shows what it will really do.
    @State private var profile: GameProfile?
    /// The expert options are open – from the start when they're what counts (Custom).
    @State private var expertOpen: Bool
    /// How tall the options are: they scroll only when the window leaves less room.
    @State private var contentHeight: CGFloat = 0
    @ObservedObject private var padFocus = PadFocus.shared
    /// The program the store starts (Steam's launch option, its one without anti-cheat when there is
    /// one; Epic's, GOG's), and the game's programs beside it.
    private let storeProgram: URL?
    private let programs: [String]

    init(game: Game, insight: GameInsight?, report: @escaping () -> Void) {
        self.game = game
        self.insight = insight
        self.report = report
        let stored = GameOptionsStore.load(game.gameID)
        _options = State(initialValue: stored)
        _expertOpen = State(initialValue: stored.preset == .custom)
        Hardware.refresh()  // so "Automatic (…)" shows what a start now would do
        storeProgram = Self.storeProgram(of: game)
        programs = storeProgram.map { GameAnalysis.programs(near: $0, in: game.installDir) } ?? []
    }

    /// The program a game's store starts, inside its folder.
    private static func storeProgram(of game: Game) -> URL? {
        guard game.bottle.isBuiltIn, game.isInstalled else { return nil }
        let relative: String?
        switch game.provider {
        case .epic: relative = EpicStore.executable(of: game.gameID.id)
        case .gog: relative = GOGStore.executable(of: game.gameID.id, in: game.installDir)
        case .steam: relative = SteamProgram.storeProgram(SteamCatalog.launchEntries(appID: game.appID, steamRoot: game.steamRoot))
        }
        return relative.map { game.installDir.appendingPathComponent($0.replacingOccurrences(of: "\\", with: "/")) }
    }

    var body: some View {
        GlassDialog(game.name, id: "options", width: 520, spacing: 20) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        profileLine
                        if game.switchable { versionChoice }
                        if game.bottle.isBuiltIn { presets }
                        if !game.bottle.isBuiltIn && game.platform == .windows {
                            Toggle(isOn: $options.metalHUD) {
                                switchLabel(L10n.t("Performance HUD in game"),
                                            L10n.t("Shows frames per second, frame times and GPU load in the top left corner of the game."))
                            }
                            .toggleStyle(GlassSwitchStyle())
                            .padFocus("options.hud", toggle: $options.metalHUD)
                            .id("options.hud")
                        }
                        if game.bottle.isBuiltIn { expertSection }
                        // A few programs side by side (Control's DirectX 11 and 12); more is a folder of tools.
                        if (2...4).contains(programs.count) { programChoice }
                        launchOptions
                    }
                    // Room for the pad's highlight, which reaches a little past each control.
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, maxScrollHeight))
                .padding(.horizontal, -8)
                .onChange(of: padFocus.focused) { _, id in
                    // The pad's highlight stays in view, so what's further down comes up as it moves on.
                    guard let id, let section = Self.sections.first(where: { id.hasPrefix($0) }) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(section, anchor: .center) }
                }
                .onChange(of: expertOpen) { _, open in
                    guard open else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("options.expert", anchor: .top) }
                }
            }

            HStack(spacing: 8) {
                if game.bottle.isBuiltIn {
                    Button(L10n.t("Report problem …"), action: reportProblem)
                        .buttonStyle(GlassTextButtonStyle())
                        .help(L10n.t("Opens a problem report on GitHub, filled in with the game and its settings. GitHub gets that as the page opens; it's public only once you submit it. The error lines from the last start go on your clipboard, to paste if you want."))
                        .padFocus("options.report", cornerRadius: 21, activate: reportProblem)
                }
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .buttonStyle(GlassTextButtonStyle())
                    .padFocus("options.cancel", cornerRadius: 21, activate: { dismiss() })
                Button(L10n.t("Save"), action: save)
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("options.save", cornerRadius: 21, activate: save)
            }
            .padding(.top, 2)
        }
        .task {
            if game.bottle.isBuiltIn || game.switchable { profile = await ProfileStore.shared.profile(for: game.gameID) }
        }
    }

    /// The parts that scroll into view with the pad, by the start of their controls' ids.
    private static let sections = ["options.reset", "options.version", "options.preset", "options.hud", "options.expert",
                                   "options.graphics", "options.frameLimit", "options.upscaling", "options.hdr", "options.program",
                                   "options.args"]
}

// MARK: - Parts

private extension GameOptionsSheet {
    /// Where the game's fixes come from, and the way back to them once something is changed.
    @ViewBuilder var profileLine: some View {
        let origin = ProfileOrigin(profile)
        if origin != nil || options != GameOptions() {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let origin {
                        Label(origin.text, systemImage: origin.symbol)
                            .font(size: 13.5, weight: .medium)
                            .help(origin.note ?? origin.text)
                    }
                    if options != GameOptions() {
                        Text(L10n.t("Your own settings."))
                            .font(size: 12.5)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                if options != GameOptions() {
                    Button(origin == nil ? L10n.t("Back to Automatic") : L10n.t("Back to the Profile")) { options = GameOptions() }
                        .buttonStyle(GlassTextButtonStyle(small: true))
                        .fixedSize()
                        .padFocus("options.reset", cornerRadius: 15, activate: { options = GameOptions() })
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassWell()
            .id("options.reset")
        }
    }

    var versionChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(L10n.t("Version"))
            Segmented(options: [(GameVersion.automatic, automaticLabel(automaticVersion == .mac ? "Mac" : "Windows"), nil),
                                (.mac, "Mac", nil), (.windows, "Windows", nil)],
                      selection: options.version, id: "options.version") { options.version = $0 }
            caption(game.platform == .mac
                    ? L10n.t("Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation; its graphics settings are in the game itself. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs.")
                    : L10n.t("Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs."))
        }
        .id("options.version")
    }

    /// The four presets as cards, two by two; none is lit while the expert options say otherwise.
    var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            title(L10n.t("Graphics"))
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    presetCard(.automatic)
                    presetCard(.balanced)
                }
                GridRow {
                    presetCard(.fastest)
                    presetCard(.compatible)
                }
            }
            if options.preset == .custom {
                Label(GraphicsPreset.custom.help, systemImage: "slider.horizontal.3")
                    .font(size: 12.5, weight: .medium)
                    .foregroundStyle(Theme.ink.opacity(0.85))
            }
        }
        .id("options.preset")
    }

    func presetCard(_ preset: GraphicsPreset) -> some View {
        let on = options.preset == preset
        return Button { options.choose(preset) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(preset.label)
                        .font(size: 13.5, weight: .semibold)
                    if preset == .automatic {
                        Text(L10n.t("recommended"))
                            .font(size: 11, weight: .semibold)
                            .foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                    }
                }
                Text(preset.help)
                    .font(size: 12)
                    .lineSpacing(1)
                    .foregroundStyle(on ? Theme.night.opacity(0.75) : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(on ? Theme.night : Theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(PresetCardStyle(on: on))
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus("options.preset.\(preset.rawValue)", cornerRadius: 16, preferred: on, activate: { options.choose(preset) })
    }

    /// The single switches the presets stand for, folded away: changing one makes it "Custom".
    var expertSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: toggleExpert) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(size: 11, weight: .bold)
                        .rotationEffect(.degrees(expertOpen ? 90 : 0))
                    Text(L10n.t("Expert options"))
                        .font(size: 14, weight: .medium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.ink.opacity(0.9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expertOpen ? L10n.t("Expanded") : L10n.t("Collapsed"))
            .padFocus("options.expert", cornerRadius: 8, activate: toggleExpert)
            .id("options.expert")

            if expertOpen {
                expertOptions
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder var expertOptions: some View {
        let shown = expert
        VStack(alignment: .leading, spacing: 8) {
            title(L10n.t("Graphics layer"))
            if !layers.isEmpty {
                Segmented(options: layers.map { ($0, $0 == .automatic ? automaticLabel(automaticWay.shortLabel) : $0.shortLabel, nil) },
                          selection: shown.graphics, id: "options.graphics") { layer in change { $0.graphics = layer } }
            }
            caption(graphicsCaption)
        }
        .id("options.graphics")

        VStack(alignment: .leading, spacing: 8) {
            title(L10n.t("Frame limit"))
            Segmented(options: [(Int?.none, automaticLabel(automaticLimit.fpsLabel), nil)]
                        + GameOptions.frameLimits.map { (Int?.some($0), $0 == 0 ? L10n.t("Off") : "\($0)", nil) },
                      selection: shown.frameLimit, id: "options.frameLimit") { limit in change { $0.frameLimit = limit } }
        }
        .id("options.frameLimit")

        VStack(alignment: .leading, spacing: 8) {
            // WineD3D draws through OpenGL, which MetalFX can't reach: nothing to choose there.
            if canChooseUpscaling {
                title(L10n.t("MetalFX upscaling"))
                Segmented(options: [(Choice.automatic, automaticLabel(GameOptions().effectiveUpscaling(profile: profile) ? L10n.t("On") : L10n.t("Off")), nil),
                                    (.on, L10n.t("On"), nil), (.off, L10n.t("Off"), nil)],
                          selection: shown.upscaling, id: "options.upscaling") { choice in change { $0.upscaling = choice } }
            }
            caption(L10n.t("Automatic follows “Sharp & smooth” in Settings. The frame limit keeps frames even; MetalFX upscales the picture to full Retina sharpness (not with WineD3D) – set a lower resolution in the game for more FPS."))
        }
        .id("options.upscaling")

        // Not part of any preset: it doesn't make them "Custom".
        Toggle(isOn: $options.hdr) {
            switchLabel("HDR", L10n.t("For games that draw through Vulkan, on the XDR display. Off by default: under Wine HDR mostly looks washed out."))
        }
        .toggleStyle(GlassSwitchStyle())
        .disabled(!canUseHDR)
        .padFocus("options.hdr", enabled: canUseHDR, toggle: $options.hdr)
        .id("options.hdr")
    }

    /// Which of the game's programs starts it (GameProgram): Automatic, or one picked by hand.
    var programChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(L10n.t("Program"))
            Segmented(options: [("", L10n.t("Automatic"), nil)]
                        + programs.map { ($0, (($0 as NSString).lastPathComponent as NSString).deletingPathExtension, nil) },
                      selection: options.program, id: "options.program") { program in options.program = program }
            caption(L10n.t("Which of the game's programs starts. Automatic: %@.", automaticProgram))
        }
        .id("options.program")
    }

    /// The program "Automatic" starts with the layer the game draws with.
    var automaticProgram: String {
        guard let storeProgram else { return "" }
        return GameProgram.resolve(store: storeProgram, installDir: game.installDir, layer: drawsWith, chosen: "",
                                   profile: profile?.executable).lastPathComponent
    }

    var launchOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(L10n.t("Launch Options"))
            GlassTextField(prompt: L10n.t("e.g. -dx11 -skipintro"), text: $options.extraArgs, id: "options.args", monospaced: true)
            caption(L10n.t("Passed straight to the game at launch."))
        }
        .id("options.args")
    }
}

// MARK: - What it means

private extension GameOptionsSheet {
    func title(_ text: String) -> some View {
        Text(text).font(size: 14, weight: .medium)
    }

    /// What an option means, under it.
    func caption(_ text: String) -> some View {
        Text(text)
            .font(size: 12.5)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A switch's name with what it does, like the switches in Settings.
    func switchLabel(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(size: 14, weight: .medium)
            Text(help)
                .font(size: 12.5)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func toggleExpert() {
        withAnimation(.easeOut(duration: 0.2)) { expertOpen.toggle() }
    }

    func reportProblem() {
        report()
        dismiss()
    }

    func save() {
        // Picking a layer or version by hand overrides what self-healing learned.
        if options.graphics != .automatic { LaunchHealth.reset(game.gameID) }
        if options.version != GameOptionsStore.load(game.gameID).version { MacHealth.reset(game.appID) }
        GameOptionsStore.save(options, for: game.gameID)
        dismiss()
    }

    /// The expert options as the preset sets them – what they show, and where "Custom" starts from.
    var expert: GameOptions {
        var shown = options.resolved(refreshRate: refreshRate, profile: profile)
        // "Most compatible" turned "Custom" keeps the layer it draws with, rather than Automatic's.
        if options.preset == .compatible, choosableLayers.contains(way(for: .compatible).graphics) {
            shown.graphics = way(for: .compatible).graphics
        }
        return shown
    }

    /// One expert option changed: from now on the expert options count, unless all are automatic again.
    func change(_ edit: (inout GameOptions) -> Void) {
        var next = expert
        edit(&next)
        next.preset = next.graphics == .automatic && next.frameLimit == nil && next.upscaling == .automatic ? .automatic : .custom
        options = next
    }

    var refreshRate: Int { GameDisplay.screen?.maximumFramesPerSecond ?? 60 }

    /// Leaves room for the title, the buttons and the sheet's edges in the main window.
    var maxScrollHeight: CGFloat { max(260, DialogRoom.height - 190) }

    /// What the next start uses for "Automatic", including what Nightforge learned (FramePacing).
    var automaticLimit: Int {
        var automatic = expert
        automatic.frameLimit = nil
        return FramePacing.automaticLimit(game: game.gameID, options: automatic, profile: profile, refreshRate: refreshRate).limit
    }

    func automaticLabel(_ value: String) -> String { L10n.t("Automatic (%@)", value) }

    /// The version "Automatic" would play (VersionChoice), from what the entry knows about both.
    var automaticVersion: Platform {
        let facts = VersionChoice.Facts(
            macNative: true, mac64: game.mac64, windows: game.windowsBuild,
            macInstalled: game.platform == .mac && game.isInstalled,
            windowsInstalled: game.platform == .windows ? game.isInstalled : game.windowsLeftover != nil)
        return VersionChoice.decide(facts, choice: .automatic, preferWindows: profile?.preferWindows == true,
                                    macFailed: MacHealth.failed(game.appID)).0
    }

    /// The layers that fit what the game draws with; none for Vulkan, OpenGL and DirectX 12.
    /// DirectX 11 can take D3DMetal too, once it's set up.
    var choosableLayers: [GraphicsLayer] {
        if let analysis = insight?.analysis, !analysis.usesD3D11, !analysis.apis.isEmpty {
            return analysis.usesD3D9 ? [.automatic, .dxvk, .wined3d] : []
        }
        return Engine.d3dMetalReady ? [.automatic, .dxmt, .dxvk, .d3dmetal] : [.automatic, .dxmt, .dxvk]
    }

    /// The choosable layers, plus one picked before that no longer fits (D3DMetal, say).
    var layers: [GraphicsLayer] {
        var list = choosableLayers
        let picked = expert.graphics
        if !list.isEmpty, !list.contains(picked) { list.append(picked) }
        return list
    }

    /// The way a preset's list takes right now (LaunchHealth).
    func way(for preset: GraphicsPreset) -> LaunchAttempt {
        let attempts = LaunchHealth.ladder(insight?.attempts ?? [], preset: preset, profile: profile, hint: insight?.hint)
        guard !attempts.isEmpty else { return LaunchAttempt(graphics: Engine.defaultGraphics) }
        return attempts[LaunchHealth.current(game.gameID, attempts).index]
    }

    /// The way "Automatic" takes in the graphics layer row: in "Most compatible"'s order there.
    var automaticWay: LaunchAttempt { way(for: options.preset) }

    var drawsWith: GraphicsLayer { expert.graphics == .automatic ? automaticWay.graphics : expert.graphics }

    var canChooseUpscaling: Bool { drawsWith.upscales && !layers.isEmpty }

    var canUseHDR: Bool { !(drawsWith == .dxmt && insight?.analysis.apis.contains(.vulkan) != true) }

    var graphicsCaption: String {
        guard let analysis = insight?.analysis, !analysis.apis.isEmpty else {
            return L10n.t("How DirectX 10/11 reaches the Mac's graphics. DXMT translates straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games.")
        }
        if analysis.usesD3D11 {
            return L10n.t("This game uses %@. DXMT translates DirectX 10/11 straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games. Automatic switches by itself if a game doesn't start.", analysis.summary)
                + (!choosableLayers.contains(.d3dmetal) ? ""
                   : " " + (analysis.apis.contains(.d3d12) ? L10n.t("D3DMetal draws its DirectX 12 version.") : L10n.t("D3DMetal, Apple's own, runs it too.")))
        }
        if analysis.usesD3D9 {
            return L10n.t("This game uses %@. DXVK is usually faster; WineD3D runs some older games DXVK can't. Automatic switches by itself if a game doesn't start.", analysis.summary)
        }
        return L10n.t("This game uses %@ and draws without a DirectX layer, so there's nothing to choose here.", analysis.summary)
    }
}

/// A preset's card: ink while it's the one chosen, a dark well that lightens under the pointer otherwise.
private struct PresetCardStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        PresetCard(label: configuration.label, on: on, pressed: configuration.isPressed)
    }

    private struct PresetCard<Label: View>: View {
        let label: Label
        let on: Bool
        let pressed: Bool
        @State private var hovering = false
        @Environment(\.reduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            label
                .background(on ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.white.opacity(hovering ? 0.1 : 0)), in: shape)
                .background(on ? .clear : .black.opacity(0.2), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(on ? 0 : 0.1)))
                .shadow(color: .black.opacity(on ? 0.3 : 0), radius: 6, y: 3)
                .contentShape(shape)
                .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.15), value: on)
        }
    }
}

private extension Int {
    var fpsLabel: String { self == 0 ? L10n.t("Off") : "\(self) FPS" }
}
