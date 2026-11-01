import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()

            if let game = model.heroGame {
                Backdrop(game: game, stage: model.route == .home)
                    .id("\(game.id)\(model.route == .home)")
                    .transition(.opacity)
            }
            // The library's darkening; a swipe to or from the library fades it with the fingers.
            Theme.night.opacity(0.86).ignoresSafeArea()
                .modifier(SwipeLevel(route: .library, shown: model.showingLibrary, moves: false))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                TopBar()

                ZStack(alignment: .topLeading) {
                    // The grid stays behind a game's page opened from it, so going back finds it
                    // scrolled to where it was.
                    // A trackpad swipe moves them with the fingers (SwipeLevel); a swipe back from
                    // a game's page shows the grid through.
                    if keepsLibrary {
                        LibraryLevel()
                            .modifier(SwipeLevel(route: .library, shown: model.showingLibrary))
                            .allowsHitTesting(model.showingLibrary)
                            .accessibilityHidden(!model.showingLibrary)
                            .padReachable(model.showingLibrary)
                    }
                    switch model.route {
                    case .home:
                        HomeLevel()
                            .modifier(SwipeLevel(route: .home))
                            .transition(.opacity)
                    case .detail:
                        if let game = model.selected {
                            DetailLevel(game: game)
                                .modifier(SwipeLevel(route: model.route))
                                .transition(.opacity)
                        }
                    case .library:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HintBar()
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 22)
            }

            if model.showingDownloads {
                // A click beside the panel closes it, like a popover.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.showingDownloads = false }
                DownloadsPanel()
                    .padding(.top, 84)  // below the top bar (36 + 38), right under the downloads ring
                    .padding(.trailing, Theme.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }

            if let lightbox = model.lightbox {
                ScreenshotLightbox(lightbox: lightbox)
                    .transition(.opacity)
            }

            ToastHost()
        }
        .animation(.easeOut(duration: 0.2), value: model.lightbox)
        // A list a chip of the library's row opened, under that chip and over the grid.
        .overlayPreferenceValue(LibraryMenuAnchors.self) { anchors in
            if model.route == .library {
                LibraryMenuLayer(anchors: anchors)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.libraryMenu)
        .animation(.easeOut(duration: 0.18), value: model.showingDownloads)
        .animation(.easeOut(duration: 0.28), value: model.heroGame?.id)
        .animation(.easeOut(duration: 0.22), value: model.route)
        // A changed version moves the game to another Steam: scan again.
        .sheet(isPresented: $model.showingOptions, onDismiss: { model.reload(quiet: true) }) {
            if let game = model.selected {
                GameOptionsSheet(game: game, insight: model.insights[game.gameID]) { model.reportProblem(for: game) }
            }
        }
        .sheet(item: $model.pendingSpace) { request in
            if request.shortfall > 0 { SpaceSheet(request: request) } else { DestinationSheet(request: request) }
        }
        .sheet(item: $model.pendingMove) { game in
            MoveSheet(game: game, targets: model.moveTargets(for: game))
        }
        // Esc closes it like Cancel: the setup stops.
        .sheet(item: Binding(get: { model.macSetup }, set: { if $0 == nil { model.closeMacSetup() } })) { setup in
            MacSteamSetupView(
                setup: setup,
                useWindows: setup.game.switchable ? { model.useWindowsVersion(of: setup.game) } : nil,
                close: { model.closeMacSetup() }
            )
        }
        .sheet(item: DialogMessage.item($model.errorMessage)) { error in
            GlassQuestion(L10n.t("Something went wrong"), message: error.text, id: "error") {
                Button(L10n.t("OK")) { model.errorMessage = nil }
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("error.ok", cornerRadius: 21, preferred: true, activate: { model.errorMessage = nil })
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
        }
        .sheet(item: $model.sessionSummary) { summary in
            SessionSummarySheet(summary: summary)
        }
        .sheet(item: $model.failedLaunch) { failed in
            FailedLaunchSheet(failed: failed)
        }
        .sheet(item: $model.saveChoice, onDismiss: { model.answerSaveChoice(takeNewer: false) }) { choice in
            SaveChoiceSheet(choice: choice)
        }
        .sheet(item: $model.pendingDemoLicense) { game in
            DemoLicenseSheet(game: game)
        }
        .sheet(item: $model.pendingCloudGame) { game in
            GlassQuestion(L10n.t("Play %@ on GeForce Now?", game.name),
                          message: L10n.t("Its anti-cheat doesn't run on a Mac, so it runs on NVIDIA's servers and streams to your Mac – with the copy you own on Steam. The first time, sign in to GeForce Now with an NVIDIA account and link Steam there. Free play lasts an hour at a time, with ads and a queue; GeForce Now's paid plans lift that. GeForce Now forgets the game while you sign in: afterwards, press Play on GeForce Now here once more."),
                          id: "cloud") {
                Button(L10n.t("Cancel")) { model.pendingCloudGame = nil }
                    .buttonStyle(GlassTextButtonStyle())
                    .padFocus("cloud.cancel", cornerRadius: 21, activate: { model.pendingCloudGame = nil })
                Button(L10n.t("Continue to GeForce Now")) { model.confirmCloud() }
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .padFocus("cloud.continue", cornerRadius: 21, preferred: true, activate: { model.confirmCloud() })
            }
        }
        .sheet(item: $model.pendingUninstall) { game in
            GlassQuestion(game.isInstalled ? L10n.t("Uninstall %@?", game.name) : L10n.t("Cancel the download of %@?", game.name),
                          message: game.downloadRefused ? L10n.t("Nightforge takes the download request back from Steam. Nothing was downloaded.")
                              : !game.isInstalled
                              ? L10n.t("The part downloaded so far is deleted. You can start the download again any time.")
                              : game.uninstallMessage,
                          id: "uninstall") {
                // Return (and A) keeps the game; uninstalling takes a deliberate click or a pad move first.
                Button(L10n.t("Keep")) { model.pendingUninstall = nil }
                    .buttonStyle(GlassTextButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padFocus("uninstall.keep", cornerRadius: 21, preferred: true, activate: { model.pendingUninstall = nil })
                Button(game.isInstalled ? L10n.t("Uninstall") : L10n.t("Cancel Download")) { model.confirmUninstall() }
                    .buttonStyle(GlassTextButtonStyle(destructive: true))
                    .padFocus("uninstall.confirm", cornerRadius: 21, activate: { model.confirmUninstall() })
            }
        }
        .sheet(item: $model.pendingLeftoverRemoval) { game in
            GlassQuestion(L10n.t("Remove the Windows version of %@?", game.name),
                          message: L10n.t("Nightforge uses the Mac version of this game now. Removing the Windows version frees %@; you can switch back and download it again any time.",
                                          Format.bytes(game.windowsLeftover ?? 0)),
                          id: "leftover") {
                Button(L10n.t("Keep")) { model.pendingLeftoverRemoval = nil }
                    .buttonStyle(GlassTextButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padFocus("leftover.keep", cornerRadius: 21, preferred: true, activate: { model.pendingLeftoverRemoval = nil })
                Button(L10n.t("Remove")) { model.confirmLeftoverRemoval() }
                    .buttonStyle(GlassTextButtonStyle(destructive: true))
                    .padFocus("leftover.confirm", cornerRadius: 21, activate: { model.confirmLeftoverRemoval() })
            }
        }
        .onAppear {
            model.startInput()
            if model.games.isEmpty { model.reload() }
            model.startBackgroundSteam()
        }
    }

    private var keepsLibrary: Bool { model.route.level == .library }
}

// MARK: - The three levels

/// Level 1 – what you play: the selected game big on the stage, its words beside it, and the way to
/// the rest at the stage's end (design 2d).
private struct HomeLevel: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var padFocus = PadFocus.shared

    var body: some View {
        if model.showsFirstStart || model.allGames.isEmpty {
            // A page taller than the window (a short one, larger text) scrolls instead of pushing the
            // top bar out; its buttons are at its end, so the pad's highlight brings the end into view.
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 24)
                            if model.showsFirstStart {
                                SetupView(setup: model.setup, macSteam: model.macSteamPrep)
                                    .padding(.horizontal, Theme.gutter)
                            } else if !model.isScanning {
                                EmptyLibrary()
                                    .padding(.horizontal, Theme.gutter)
                            }
                            Spacer(minLength: 28)
                                .id("firstStart.end")
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: padFocus.focused) { _, id in
                        guard id != nil else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("firstStart.end", anchor: .bottom) }
                    }
                }
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HomeStage()
                        .padding(.leading, geo.size.width * 0.36)
                    Group {
                        if let game = model.heroGame {
                            GameDetail(game: game, compact: true, role: model.homeRole(place: model.homePlace))
                                .id(game.id)
                                .transition(.opacity)
                        } else {
                            AllGamesHero()
                                .transition(.opacity)
                        }
                    }
                    // Up to where the stage begins (its covers fade in from there): nothing in the column
                    // runs over a cover.
                    .frame(width: max(360, min(600, geo.size.width * 0.36 + 24 - Theme.gutter)), alignment: .leading)
                    .padding(.leading, Theme.gutter)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

/// Level 2 – every game, in the grid, with its filters; a search's hits show here.
private struct LibraryLevel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryToolbar()
            if model.games.isEmpty {
                VStack(alignment: .leading) {
                    Spacer()
                    if !model.searchText.isEmpty {
                        NoResults()
                    } else if model.filters.narrows {
                        NoFilterMatches()
                    } else if !model.isScanning {
                        EmptyLibrary()
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LibraryGrid()
                    .padding(.top, 4)
            }
        }
    }
}

private struct NoFilterMatches: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("No games match these filters"))
                .displayFont(30)
                .foregroundStyle(Theme.ink)
            Button(L10n.t("Clear filters")) { model.filters = model.filters.cleared }
                .buttonStyle(GlassTextButtonStyle())
                .padFocus("noResults.clearFilters", activate: { model.filters = model.filters.cleared })
        }
    }
}

/// Level 3 – one game's page: everything Nightforge knows about it, and the one button.
private struct DetailLevel: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var focus = PadFocus.shared
    /// The page went up past its first screen: the game bar shows under the top bar.
    @State private var barShown = false

    var body: some View {
        let info = model.info(for: game).flatMap { GameAboutSection.hasContent($0) ? $0 : nil }
        GeometryReader { geo in
            ScrollViewReader { scroll in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { place in
                            Color.clear.preference(key: PageOffset.self, value: place.frame(in: .named("page")).minY)
                        }
                        .frame(height: 0)
                        firstScreen
                            // With "About the game" below, its title and the screenshots' top peek in.
                            .frame(height: max(geo.size.height - (info == nil ? 0 : 70), 0), alignment: .topLeading)
                            // It fades as the page goes up, rather than being cut by the top bar.
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content.opacity(phase.value < 0 ? max(0, 1 + phase.value * 2.5) : 1)
                            }
                        if let info {
                            Button { withAnimation(.easeOut(duration: 0.35)) { scroll.scrollTo("about", anchor: .top) } } label: {
                                HStack(spacing: 8) {
                                    SectionTitle(L10n.t("About the game"))
                                    Image(systemName: "chevron.down")
                                        .font(size: 9, weight: .bold)
                                        .foregroundStyle(Theme.muted)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padFocus("detail.about", cornerRadius: 8) {
                                withAnimation(.easeOut(duration: 0.35)) { scroll.scrollTo("about", anchor: .top) }
                            }
                            .padding(.bottom, 18)
                            GameAboutSection(game: game, info: info, narrow: geo.size.width < 1100)
                                .id("about")
                                .padding(.bottom, 40)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .background(alignment: .top) {
                        if info != nil {
                            // Darkens the art behind as the section comes up: a gradient that scrolls with
                            // the page, no blur (UI power budget).
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Theme.night.opacity(0.92), location: 0.5),
                                                   .init(color: Theme.night.opacity(0.95), location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.top, geo.size.height * 0.5)
                                .padding(.bottom, -400)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .coordinateSpace(name: "page")
                .modifier(PageScrolled(threshold: geo.size.height * 0.4, scrolled: $barShown))
                .overlay(alignment: .top) {
                    if barShown {
                        GameBar(game: game)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    }
                }
                .modifier(SoftTopEdge())
                // The pad's highlight stays in sight as it moves down the page, clear of the game bar,
                // and the page follows it smoothly.
                .onChange(of: focus.focused) { _, id in PadFocus.shared.reveal(id, top: 96) }
            }
        }
        .id(game.id)
        .task(id: game.id) { await model.askInfo(for: game) }
    }

    private var firstScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackPill(to: model.route.level)
                .padding(.top, 18)
            Spacer(minLength: 24)
            HStack(alignment: .bottom, spacing: 32) {
                GameDetail(game: game, compact: false)
                // What's set for it and where that comes from (2.3), beside the title as in the design.
                if game.install != .inStore {
                    Spacer(minLength: 0)
                    ThisGameCard(game: game)
                }
            }
            // Ahead of the spacers: the logo gives way only when the window is really too short.
            .layoutPriority(1)
            Spacer(minLength: 20)
        }
    }
}

/// Where a game's page has scrolled to (its top in the scroll view, negative once it went up), for
/// macOS 14; from 15 on the scroll view says it itself.
private struct PageOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// `scrolled` turns true once the page went up more than `threshold` – only then, not on every step.
private struct PageScrolled: ViewModifier {
    let threshold: CGFloat
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > threshold } action: { _, past in
                set(past)
            }
        } else {
            content.onPreferenceChange(PageOffset.self) { y in set(-y > threshold) }
        }
    }

    private func set(_ past: Bool) {
        guard past != scrolled else { return }
        withAnimation(.easeOut(duration: 0.18)) { scrolled = past }
    }
}

/// Under the top bar once a game's page went up: the game and its button, on a solid edge the page
/// passes under – nothing is cut by the top bar.
private struct GameBar: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @State private var logo: NSImage?

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180, maxHeight: 34, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(game.name)
                        .displayFont(18)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(game.name)
            MetaLine(compatibility: model.compatibility(of: game), facts: nil, stores: game.providers.map(\.label), info: model.info(for: game))
                .fixedSize()
                .layoutPriority(-1)
            Spacer(minLength: 0)
            PlayButton.of(game, model: model, compact: true)
                .padFocus("detail.bar.play", cornerRadius: 22, activate: { model.primaryAction() })
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 64)
        .background {
            VStack(spacing: 0) {
                Theme.night.opacity(0.95)
                LinearGradient(colors: [Theme.night.opacity(0.95), Theme.night.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
            .padding(.bottom, -28)
            .allowsHitTesting(false)
        }
        .task(id: game.id) { logo = await ArtworkStore.shared.image(for: game, kind: .logo) }
    }
}

/// Content scrolling under the top bar fades out there: the system's soft edge from macOS 26, a
/// plain edge before.
private struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// "‹ Home" / "‹ Library": where Esc and B go from a game's page.
private struct BackPill: View {
    let to: Route.Level
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Button { model.back() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(size: 12, weight: .bold)
                Text(to == .home ? L10n.t("Home") : L10n.t("Library"))
                    .font(size: 13, weight: .semibold)
            }
            .foregroundStyle(Theme.ink.opacity(0.9))
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 34)
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
        .help(L10n.t("Back (Esc)"))
        .accessibilityLabel(to == .home ? L10n.t("Back to Home") : L10n.t("Back to the library"))
        .padFocus("detail.back", cornerRadius: 17, activate: { model.back() })
    }
}

/// Home with the rail's last tile selected: the way to every game.
private struct AllGamesHero: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("Library").uppercased())
                .font(size: 12, weight: .semibold)
                .kerning(1.8)
                .foregroundStyle(Theme.muted)
            Text(model.visibleCount == 1 ? L10n.t("Your game") : L10n.t("All %ld games", model.visibleCount))
                .displayFont(54)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Text(L10n.t("Everything in your library – installed or not – in one place."))
                .font(size: 15)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 320, maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.goLibrary() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(size: 15, weight: .bold)
                    Text(L10n.t("Open Library"))
                        .displayFont(17)
                }
                .foregroundStyle(Theme.night)
                .padding(.horizontal, 32)
                .frame(height: 52)
            }
            .buttonStyle(GlassButtonStyle(glass: .tinted(Theme.sodium, glows: true), shape: Capsule()))
            .help(L10n.t("Whole library (L)"))
            .padFocus("play", cornerRadius: 34, activate: { model.goLibrary() })
        }
        .frame(height: 340, alignment: .bottomLeading)
    }
}

// MARK: - Didn't start

/// A game that ended right after starting with every way Nightforge knows: what was tried, and
/// what's left to do – "Most compatible", start over, choose by hand, or report it.
struct FailedLaunchSheet: View {
    let failed: FailedLaunch
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        GlassDialog(L10n.t("%@ didn't start", failed.game.name), id: "failed") {
            // The ways out scroll in a short window; the report line stays under them.
            DialogScroll {
                VStack(alignment: .leading, spacing: 8) {
                    DialogWarning(L10n.t("It ended right after starting, with every way Nightforge knows to start it."))
                    if !failed.tried.isEmpty {
                        Text(L10n.t("Tried: %@", failed.tried.joined(separator: " · ")))
                            .font(size: 12.5)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 26)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    // A on a controller is Return: the first way out, not a browser.
                    if offersCompatible {
                        Button(action: mostCompatible) {
                            Label(L10n.t("Try “Most compatible”"), systemImage: "shield.lefthalf.filled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassTextButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .padFocus("failed.compatible", cornerRadius: 21, preferred: true, activate: mostCompatible)
                        Text(L10n.t("Starts it the slower, safest way – no MetalFX, 60 FPS, the safest graphics first – and keeps that for this game. Change it any time in its options."))
                            .font(size: 12.5)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }
                    Button(action: startOver) {
                        Label(L10n.t("Try Again From the First Way"), systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassTextButtonStyle(prominent: !offersCompatible))
                    .keyboardShortcut(offersCompatible ? nil : .defaultAction)
                    .padFocus("failed.again", cornerRadius: 21, preferred: !offersCompatible, activate: startOver)
                    Text(L10n.t("Helps when something got in the way the first time – Steam updating, a window asking something."))
                        .font(size: 12.5)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if hasLayers {
                        Button(action: chooseByHand) {
                            Label(L10n.t("Choose Graphics by Hand …"), systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassTextButtonStyle())
                        .padFocus("failed.options", cornerRadius: 21, activate: chooseByHand)
                        .padding(.top, 4)
                    }
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.t("Still no luck? A problem report opens on GitHub, filled in with what Nightforge tried – nothing is sent until you submit it there."))
                    .font(size: 12.5)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(L10n.t("Report problem"), action: report)
                    .buttonStyle(GlassTextButtonStyle(small: true))
                    .fixedSize()
                    .padFocus("failed.report", cornerRadius: 15, activate: report)
            }
        }
    }

    /// Vulkan, OpenGL and DirectX 12 have one way each: nothing to pick by hand.
    private var hasLayers: Bool {
        guard failed.game.bottle.isBuiltIn, failed.game.platform == .windows else { return false }
        guard let analysis = model.insights[failed.game.gameID]?.analysis else { return true }
        return analysis.usesD3D11 || analysis.usesD3D9 || analysis.apis.isEmpty
    }

    /// Nightforge's own Windows games, not yet on "Most compatible" (1.2, 2.3).
    private var offersCompatible: Bool {
        failed.game.bottle.isBuiltIn && failed.game.platform == .windows
            && GameOptionsStore.load(failed.game.gameID).preset != .compatible
    }

    private func mostCompatible() { model.startMostCompatible(failed) }
    private func startOver() { model.startOver(failed) }
    private func chooseByHand() { model.chooseGraphicsByHand(failed) }
    private func report() { model.reportProblem(for: failed.game, tried: failed.tried) }
}

// MARK: - Saves of both versions

/// A game switching between its Windows and Mac version where both have saves and the one played
/// before has newer ones: go on with those (this version's are backed up) or keep this version's.
struct SaveChoiceSheet: View {
    let choice: LibraryModel.SaveChoice
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        // × and Esc keep this version's own save, like the second answer.
        GlassDialog(L10n.t("Which save do you want to play on?"), id: "saves", width: 480, spacing: 18) {
            DialogWarning(L10n.t("%@ has saves from both its Windows and its Mac version, and they're different.", choice.game.name))
            VStack(spacing: 10) {
                // Return and A take the newer one – nothing is lost either way.
                option(title: version(choice.from), date: choice.newer.theirs, newer: true) { model.answerSaveChoice(takeNewer: true) }
                    .keyboardShortcut(.defaultAction)
                    .padFocus("saves.newer", cornerRadius: 16, preferred: true, activate: { model.answerSaveChoice(takeNewer: true) })
                option(title: version(choice.from == .mac ? .windows : .mac), date: choice.newer.ours, newer: false) {
                    model.answerSaveChoice(takeNewer: false)
                }
                .padFocus("saves.keep", cornerRadius: 16, activate: { model.answerSaveChoice(takeNewer: false) })
            }
            Text(L10n.t("Taking the newer one keeps this version's save as a backup in Nightforge's Backups folder."))
                .font(size: 12.5)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func version(_ platform: Platform) -> String {
        platform == .mac ? L10n.t("Mac version") : L10n.t("Windows version")
    }

    private func option(title: String, date: Date, newer: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: newer ? "clock.arrow.circlepath" : "clock")
                    .font(size: 18, weight: .semibold, scales: false)
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(size: 14, weight: .semibold).foregroundStyle(Theme.ink)
                        if newer {
                            Text(L10n.t("Newer"))
                                .font(size: 11, weight: .semibold)
                                .foregroundStyle(Theme.sodium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.sodium.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(Self.when(date)).font(size: 12.5).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GlassButtonStyle(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }

    /// "Today at 14:02", "Yesterday at 21:10", "12 Oct 2026 at 9:30".
    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

// MARK: - Not enough space

/// A download that wouldn't fit: how much is missing, and long unplayed games to make room with.
struct SpaceSheet: View {
    let request: SpaceRequest
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String>

    init(request: SpaceRequest) {
        self.request = request
        _picked = State(initialValue: SpaceCheck.preselect(request.candidates, shortfall: request.shortfall))
    }

    private var freed: Int64 { request.candidates.filter { picked.contains($0.id) }.reduce(0) { $0 + $1.sizeOnDisk } }
    private var enough: Bool { freed >= request.shortfall }

    var body: some View {
        GlassDialog(L10n.t("%@ needs up to %@", request.game.name, Format.bytes(request.needed)), id: "space", width: 540) {
            // The games to make room with scroll in a short window; the buttons stay under them.
            DialogScroll {
                DialogWarning(L10n.t("Your Mac has %@ free – %@ short. Nothing is downloaded until there's room, so nothing stops halfway.",
                                     Format.bytes(request.free), Format.bytes(request.shortfall)),
                              symbol: "externaldrive.badge.exclamationmark")
                if request.candidates.isEmpty {
                    Text(L10n.t("No game here has gone unplayed for a month. Remove games or other files you don't need, then try again."))
                        .font(size: 13)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(request.candidates.allSatisfy { $0.provider == .steam }
                             ? L10n.t("Make room – these haven't been played for a while. They stay in your Steam library, and saves in the Steam Cloud are kept.")
                             : L10n.t("Make room – these haven't been played for a while. They stay in your store's library, and saves in its cloud are kept."))
                            .font(size: 13, weight: .medium)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            ForEach(Array(request.candidates.enumerated()), id: \.element.id) { place, game in
                                let on = Binding(get: { picked.contains(game.id) },
                                                 set: { if $0 { picked.insert(game.id) } else { picked.remove(game.id) } })
                                if place > 0 { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                                Toggle(isOn: on) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(game.name)
                                                .font(size: 13.5, weight: .semibold)
                                                .lineLimit(1)
                                            Text(game.lastPlayed.map { L10n.t("Last played %@", Format.relative($0)) } ?? L10n.t("Never played"))
                                                .font(size: 12)
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Text(Format.bytes(game.sizeOnDisk))
                                            .font(size: 13)
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.ink.opacity(0.8))
                                    }
                                }
                                .toggleStyle(GlassCheckboxStyle())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .padFocus("space.\(game.id)", toggle: on)
                            }
                        }
                        .glassWell()
                    }
                }
                DriveInstallChoices(request: request)
            }
            HStack(spacing: 8) {
                if !request.candidates.isEmpty {
                    Text(enough ? L10n.t("Frees %@ – enough", Format.bytes(freed)) : L10n.t("Frees %@ of %@", Format.bytes(freed), Format.bytes(request.shortfall)))
                        .font(size: 12.5).monospacedDigit()
                        .foregroundStyle(enough ? Theme.runsGreat : Theme.muted)
                }
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .buttonStyle(GlassTextButtonStyle())
                    .fixedSize()
                    .padFocus("space.cancel", cornerRadius: 21, activate: { dismiss() })
                if !request.candidates.isEmpty {
                    Button(L10n.t("Uninstall %ld & Download", picked.count)) { model.freeUpAndDownload(picked) }
                        .buttonStyle(GlassTextButtonStyle(prominent: true))
                        .fixedSize()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!enough)
                        .padFocus("space.confirm", enabled: enough, cornerRadius: 21, activate: { model.freeUpAndDownload(picked) })
                }
            }
            .padding(.top, 2)
        }
    }
}

/// A dialog's warning line: the sign, then what happened.
private struct DialogWarning: View {
    let text: String
    var symbol = "exclamationmark.triangle"

    init(_ text: String, symbol: String = "exclamationmark.triangle") {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(size: 14, weight: .semibold, scales: false)
                .foregroundStyle(Theme.warning)
                .frame(width: 16)
            Text(text)
                .font(size: 14)
                .lineSpacing(3)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backdrop

private struct Backdrop: View {
    let game: Game
    /// Home's stage: the key art blurred (made once, ArtworkStore.stageBackdrop) with the cover's
    /// light; a game's page shows it sharp.
    var stage = false
    @State private var hero: NSImage?
    @State private var cover: NSImage?
    @State private var light: StageBackdrop?
    /// The blurred art settles from a little closer in, once per game – then nothing moves.
    @State private var settled = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        if stage { stageBody } else { pageBody }
    }

    private var stageBody: some View {
        GeometryReader { geo in
            ZStack {
                if let light {
                    Image(nsImage: light.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(settled || reduceMotion ? 1 : 1.06)
                        .opacity(0.72)
                        .clipped()
                    // The cover's colour, weaker for a bright cover so the words beside it stay readable.
                    RadialGradient(colors: [Color(nsColor: light.glow).opacity(light.brightness > 0.55 ? 0.16 : 0.3), .clear],
                                   center: UnitPoint(x: 0.64, y: 0.42), startRadius: 0, endRadius: geo.size.width * 0.5)
                }
                LinearGradient(
                    stops: [
                        .init(color: Theme.night.opacity(0.86), location: 0),
                        .init(color: Theme.night.opacity(light.map { $0.brightness > 0.55 ? 0.62 : 0.5 } ?? 0.5), location: 0.34),
                        .init(color: Theme.night.opacity(0.1), location: 0.6),
                        .init(color: Theme.night.opacity(0.35), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: Theme.night.opacity(0.5), location: 0),
                        .init(color: Theme.night.opacity(0.05), location: 0.3),
                        .init(color: Theme.night.opacity(0.35), location: 0.7),
                        .init(color: Theme.night.opacity(0.92), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .task(id: game.id) {
            light = await ArtworkStore.shared.stageBackdrop(for: game)
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 14)) { settled = true }
        }
    }

    private var pageBody: some View {
        GeometryReader { geo in
            ZStack {
                if let hero {
                    Image(nsImage: hero)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let cover {
                    // No hero art: use the cover as a soft light source instead.
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 70)
                        .opacity(0.55)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: Theme.night.opacity(0.10), location: 0),
                        .init(color: Theme.night.opacity(0.50), location: 0.45),
                        .init(color: Theme.night.opacity(0.94), location: 0.78),
                        .init(color: Theme.night, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [Theme.night.opacity(0.85), Theme.night.opacity(0)],
                    startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5)
                )
            }
        }
        .ignoresSafeArea()
        .task(id: game.id) {
            hero = await ArtworkStore.shared.image(for: game, kind: .hero)
            if hero == nil {
                cover = await ArtworkStore.shared.image(for: game, kind: .cover)
            }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                NightforgeMark()
                    .frame(height: 17)
                Text("Nightforge")
                    .displayFont(15)
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            if !model.allGames.isEmpty {
                SectionSwitch()
                    .fixedSize()
                    .padding(.leading, 10)
            }

            Spacer()

            if model.isScanning {
                HStack(spacing: 8) {
                    GlassSpinner(size: 14)
                    Text(L10n.t("Scanning …"))
                        .font(size: 13)
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            if let update = model.availableUpdate {
                Button {
                    model.installUpdate()
                } label: {
                    HStack(spacing: 7) {
                        if model.updating {
                            GlassSpinner(size: 14, tint: Theme.night)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(model.updating ? L10n.t("Updating …") : L10n.t("Update to %@", update.version))
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .font(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.night)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                }
                .buttonStyle(GlassButtonStyle(glass: .tinted(Theme.sodium), shape: Capsule(), fadesWhenDisabled: false))
                .disabled(model.updating)
                .padFocus("top.update", enabled: !model.updating, cornerRadius: 17, activate: { model.installUpdate() })
                .help(L10n.t("Installs the new version and restarts Nightforge. Your games and settings stay."))
            }


            if model.power.onBattery, let level = model.power.level {
                Label("\(Int((level * 100).rounded())) %", systemImage: PowerSource.symbol(level))
                    .font(size: 13, weight: .semibold).monospacedDigit()
                    .foregroundStyle(level < 0.2 ? Theme.sodium : Theme.ink.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(GlassBackground(glass: .regular, shape: Capsule()))
                    .help(Prefs.saveBattery ? L10n.t("On battery – games are capped at 30 FPS to last longer")
                          : L10n.t("On battery – “Save battery when unplugged” in Settings caps games at 30 FPS"))
            } else if let warning = model.chargerWarning {
                ChargerPill(warning: warning, power: model.power)
            }
            // Downloads, rescan and settings share one piece of glass.
            HStack(spacing: 2) {
                if !model.downloads.isEmpty || model.move != nil {
                    DownloadsButton()
                    GlassDivider()
                }
                Button { model.rescan() } label: {
                    Image(systemName: "arrow.clockwise").font(size: 13, weight: .semibold, scales: false)
                }
                .buttonStyle(GlassGroupButtonStyle())
                .help(L10n.t("Rescan library (⌘R)"))
                .accessibilityLabel(L10n.t("Rescan library"))
                .padFocus("top.rescan", cornerRadius: 15, activate: { model.rescan() })
                GlassDivider()
                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape").font(size: 14, weight: .semibold, scales: false)
                }
                .buttonStyle(GlassGroupButtonStyle())
                .help(L10n.t("Settings (⌘,)"))
                .accessibilityLabel(L10n.t("Settings"))
                .padFocus("top.settings", cornerRadius: 15, activate: { model.openSettings() })
            }
            .padding(.horizontal, 4)
            .frame(height: 38)
            .background(GlassBackground(glass: .regular, shape: Capsule()))

            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute().locale(L10n.locale))  // the app's language, not the Mac's
                    .font(size: 14, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(GlassBackground(glass: .regular, shape: Capsule()))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 36)
    }

}

/// "Home | Library 104": the two levels, the one you're on filled in.
private struct SectionSwitch: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 8) {
            // With a controller: L1 is always Home, R1 always the library (InputRouter.section).
            if model.controllerConnected { chip(model.padSymbols.shoulders[0]) }
            HStack(spacing: 0) {
                segment(.home, L10n.t("Home"), count: nil) { model.goHome() }
                segment(.library, L10n.t("Library"), count: model.visibleCount) { model.goLibrary() }
            }
            .padding(4)
            .frame(height: 38)
            .background(GlassBackground(glass: .regular, shape: Capsule()))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.t("Sections"))
            if model.controllerConnected { chip(model.padSymbols.shoulders[1]) }
        }
    }

    /// A shoulder button's name on a keycap, like the hint bar's keys.
    private func chip(_ name: String) -> some View {
        Text(name)
            .font(size: 11, weight: .semibold)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(GlassBackground(glass: .regular, shape: Capsule()))
            .accessibilityHidden(true)
    }

    private func segment(_ level: Route.Level, _ title: String, count: Int?, action: @escaping () -> Void) -> some View {
        let on = model.route.level == level
        return Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                }
            }
            .font(size: 13, weight: .semibold)
            .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.8))
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background(on ? Theme.ink : .clear, in: Capsule())
            .shadow(color: .black.opacity(on ? 0.3 : 0), radius: 4, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(level == .home ? L10n.t("Home – what you play (L)") : L10n.t("Whole library (L)"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus("top.\(level == .home ? "home" : "library")", cornerRadius: 15, activate: action)
    }
}

private struct NoResults: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("No games match “%@”", model.searchText))
                .displayFont(30)
                .foregroundStyle(Theme.ink)
            Button(L10n.t("Clear search")) { model.searchText = "" }
                .buttonStyle(GlassTextButtonStyle())
                .padFocus("noResults.clear", activate: { model.searchText = "" })
        }
    }
}

// MARK: - Selected game

/// The selected game big: on Home what you need to press Play (`compact`), on its page everything.
private struct GameDetail: View {
    let game: Game
    var compact = false
    /// On Home's stage: what the game is there (StarterPicks, HomeRail.stage).
    var role: LibraryModel.HomeRole?
    @EnvironmentObject private var model: LibraryModel
    @State private var logo: NSImage?
    /// The Metacritic score the store gave when Steam's catalog on the Mac had none.
    @State private var askedScore: Int?

    static func openBatterySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 24) {
            VStack(alignment: .leading, spacing: 10) {
            // On a new line rather than cut short when Home's column is too narrow for all of it.
            FlowRow(spacing: 12, lineSpacing: 8, centered: true) {
                if let role, let kicker = StageKicker(role: role, game: game) {
                    kicker
                }
                MetaLine(compatibility: model.compatibility(of: game), facts: facts, stores: game.providers.map(\.label), info: info)
                    .fixedSize()
                if model.isHidden(game) {
                    Label(L10n.t("Hidden"), systemImage: "eye.slash")
                        .font(size: 12, weight: .semibold)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }

            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480, maxHeight: compact ? 150 : 170, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                } else {
                    Text(game.name)
                        .displayFont(54)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: 760, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                }
            }
            // The logo gives way first when the window is short (a game's page in a small window with
            // its buttons on two lines, larger text): the page has to fit, or it grows past the window
            // and the top bar jumps between Home and the library.
            .frame(minHeight: 80, maxHeight: compact ? 150 : 170, alignment: .bottomLeading)
            .accessibilityLabel(game.name)

            // Why it's a good start, in one sentence – only for a game nobody has played here yet.
            if let starter {
                Text(StarterPicks.reason(starter))
                    .font(size: 15)
                    .foregroundStyle(Theme.ink.opacity(0.82))
                    .frame(minWidth: 320, maxWidth: 600, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }

            // Each stat whole, on a second line when Home's column is full – never cut short.
            FlowRow(spacing: 34, lineSpacing: 14) {
                if game.install != .inStore && !(starter != nil && game.lastPlayed == nil) {
                    Stat(label: L10n.t("Last played"), value: game.lastPlayed.map(Format.relative) ?? L10n.t("Never"))
                }
                if let minutes = game.playtimeMinutes, minutes > 0 {
                    Stat(label: L10n.t("Play time"), value: Format.playtime(minutes))
                }
                switch game.install {
                case .inStore:
                    Stat(label: L10n.t("Price"), value: game.storePrice ?? "–")
                    if let score = game.metascore {
                        Stat(label: "Metascore", value: "\(score)")
                    }
                case .installed:
                    Stat(label: L10n.t("Size"), value: Format.bytes(game.sizeOnDisk))
                case .notInstalled where game.onUnpluggedDrive:
                    // Installed there, only not plugged in: where it is and what it takes – not a download.
                    Stat(label: L10n.t("On %@", game.missingDrive ?? ""),
                         value: game.sizeOnDisk > 0 ? Format.bytes(game.sizeOnDisk) : "–")
                case .notInstalled where game.playsInCloud:
                    Stat(label: L10n.t("Plays on"), value: "GeForce Now")
                case .notInstalled:
                    if let download = game.downloadSize {
                        Stat(label: L10n.t("Download"), value: Format.bytes(download))
                        Stat(label: L10n.t("On your Mac"), value: Format.bytes(game.sizeOnDisk))
                    } else {
                        Stat(label: L10n.t("Download"), value: game.sizeOnDisk > 0
                             ? L10n.t("up to %@", Format.bytes(game.sizeOnDisk)) : "–")
                    }
                case .downloading:
                    Stat(label: L10n.t("Download"), value: Format.bytes(game.sizeOnDisk))
                }
                if (!compact || starter != nil) && game.install != .inStore, let score = metascore {
                    Stat(label: "Metascore", value: "\(score)")
                }
                if game.switchable {
                    Stat(label: L10n.t("Version"), value: game.platform == .mac ? "Mac" : "Windows")
                } else if let starter {
                    Stat(label: L10n.t("Version"), value: starter.mac ? "Mac" : "Windows")
                }
                if game.install != .inStore || game.controller != .none {
                    // Epic and GOG games without the same game on Steam: nobody says.
                    Stat(label: L10n.t("Controller"), value: game.knownController?.label ?? "–")
                }
                if !game.bottle.isBuiltIn && game.platform == .windows {  // only means something with several CrossOver bottles
                    Stat(label: L10n.t("Bottle"), value: game.bottle.name)
                }
            }

            if !compact {
                CompatibilityNote(compatibility: model.compatibility(of: game))
            }
            if !compact, !game.addOns.isEmpty {
                Label(AddOns.line(game.addOns), systemImage: "puzzlepiece.extension")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if game.isVROnly {
                Label(L10n.t("Needs a VR headset – this game can't be played on a Mac."), systemImage: "visionpro")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
            }
            if let block = game.antiCheatBlock {
                AntiCheatNote(block: block)
            }
            if game.demoOf != nil {
                DemoNote(game: game)
            }
            if game.downloadRefused {
                RefusedDownloadNote()
            }
            if !compact, let insight = model.insights[game.gameID] {
                GameInsightNotes(game: game, insight: insight)
            }
            // Not while it's being started: "Runs with …" only once it did.
            if !compact, model.launchingID != game.id, let held = model.heldEngine(of: game) {
                HeldEngineNote(game: game, held: held)
            }
            if model.power.onBattery && Prefs.saveBattery && game.isInstalled && !model.isRunning(game) {
                Label(L10n.t("On battery: games are capped at 30 FPS to last longer."), systemImage: "battery.50percent")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
            }
            if let warning = model.chargerWarning, game.install != .inStore {
                Label(ChargerPill.note(warning), systemImage: "bolt.fill")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.warning)
            }
            if model.lowPowerMode && game.install != .inStore {
                HStack(spacing: 10) {
                    Label(L10n.t("Low Power Mode is on – games run much slower with it."), systemImage: "battery.25percent")
                        .font(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.sodium)
                    Button(L10n.t("Battery Settings"), action: Self.openBatterySettings)
                        .buttonStyle(GlassTextButtonStyle(small: true))
                        .padFocus("detail.battery", activate: Self.openBatterySettings)
                }
            }
            if !compact {
                VersionNotes(game: game)
            }
            if let needed = game.downloadNeedsSpace {
                Label(L10n.t("Not enough space: Steam needs %@ to download this game, your Mac has %@ free. Make some room, then continue.",
                             Format.bytes(needed), Format.bytes(LibraryModel.freeSpace(at: game.installDir.deletingLastPathComponent()))),
                      systemImage: "externaldrive.badge.exclamationmark")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !compact && game.providers.count > 1 && game.install != .inStore {
                StoreChoiceRow(game: game)
            }

            // The round buttons go to a new line rather than squeezing Play's words (a narrow window,
            // larger text, German).
            FlowRow(spacing: 14, lineSpacing: 14, centered: true) {
                // On its page the pad starts here, not on the lowest row (the screenshots further down).
                PlayButton.of(game, model: model)
                    .padFocus("play", cornerRadius: 34, preferred: !compact, activate: { model.primaryAction() })
                if compact {
                    RoundIconButton(symbol: "info", help: L10n.t("Details (I)")) {
                        model.openDetail()
                    }
                }
                if game.install != .inStore {
                    RoundIconButton(symbol: "slider.horizontal.3", help: L10n.t("Options for this game (O)")) {
                        model.showingOptions = true
                    }
                }
                if !compact && game.hasFolder {
                    RoundIconButton(symbol: "folder", help: L10n.t("Show game folder in Finder")) {
                        model.revealSelected()
                    }
                }
                if !compact && model.canUninstall(game) {
                    RoundIconButton(
                        symbol: game.isInstalled ? "trash" : "xmark",
                        help: game.isInstalled ? L10n.t("Uninstall (⌘⌫)") : L10n.t("Cancel Download")
                    ) {
                        model.requestUninstall(game)
                    }
                }
                if !compact && game.install != .inStore {
                    let hidden = model.isHidden(game)
                    RoundIconButton(symbol: hidden ? "eye" : "eye.slash",
                                    help: hidden ? L10n.t("Show in library again (H)") : L10n.t("Hide from library (H)"),
                                    focusID: "detail.hide") {
                        model.toggleHidden(game)
                    }
                }
                if !compact && game.isInstalled {
                    let added = model.shortcutsChanged >= 0 && GameShortcut.exists(for: game)
                    RoundIconButton(symbol: added ? "app.badge.checkmark" : "app.badge",
                                    help: added ? L10n.t("In Applications – show it") : L10n.t("Add to Applications – Spotlight and Launchpad find it"),
                                    focusID: "detail.shortcut") {
                        if added {
                            NSWorkspace.shared.activateFileViewerSelecting([GameShortcut.appURL(for: game)])
                        } else {
                            model.addShortcut(for: game)
                        }
                    }
                }
                if !compact && (model.canPin(game) || model.isPinned(game)) {
                    let pinned = model.isPinned(game)
                    RoundIconButton(symbol: pinned ? "pin.fill" : "pin",
                                    help: pinned ? L10n.t("Unpin from Home (P)") : L10n.t("Pin to Home – stays on the rail (P)"),
                                    focusID: "detail.pin") {
                        model.togglePinned(game)
                    }
                }
            }
            if let starter, game.install == .notInstalled, model.launchingID != game.id {
                Text(starter.mac && game.platform != .mac
                     ? L10n.t("Comes as its Mac version – the first time, Nightforge sets up Steam for Mac for it, once, in a few minutes.")
                     : L10n.t("Downloads in the background – you can browse on, and your Mac stays awake."))
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.launchingID == game.id, let hint = model.launchHint {
                Text(hint)
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: game.id) {
            logo = await ArtworkStore.shared.image(for: game, kind: .logo)
        }
        .task(id: game.id) {
            guard !compact, let steam, game.install != .inStore, facts?.metascore == nil else { return }
            askedScore = await Metascores.score(for: steam.appID)
        }
    }

    /// Its Steam entry – also when it starts through another store – for what only Steam knows.
    private var steam: Game? { game.entries.first { $0.provider == .steam } }

    /// What StarterPicks knows of it, on Home's stage among "To start with".
    private var starter: StarterFacts? {
        guard compact, let role, role != .played, role != .next else { return nil }
        return model.starterFacts(game)
    }

    /// Genre, year and score from Steam's catalog on the Mac (store hits aren't in it; games only other stores have neither).
    private var facts: StoreFacts? {
        steam.flatMap { SteamCatalog.storeFacts(appID: $0.appID, steamRoot: $0.steamRoot) }
    }

    /// What its store or the same game on Steam says about it (GameInfoStore).
    private var info: GameInfo? { model.info(for: game) }

    /// Steam's catalog first; else what the store said, now or before (offline).
    private var metascore: Int? {
        facts?.metascore ?? askedScore ?? steam.flatMap { Metascores.cached($0.appID) }
    }
}

extension PlayButton {
    /// The button for `game` as its page shows it – `compact` in the game bar that stays at the top of
    /// its scrolled page.
    @MainActor static func of(_ game: Game, model: LibraryModel, compact: Bool = false) -> PlayButton {
        PlayButton(install: game.install, isLaunching: model.launchingID == game.id || model.sizingID == game.id,
                   isUninstalling: model.uninstallingID == game.id,
                   isRunning: model.isRunning(game),
                   needsConfirmation: model.launchNeedsConfirmation,
                   status: model.sizingID == game.id ? L10n.t("Checking the size …") : model.launchPhase?.title,
                   unavailable: unavailable(game, model: model), cloud: game.playsInCloud,
                   noSpace: game.downloadNeedsSpace != nil,
                   demo: game.demoOf != nil,
                   update: game.pendingUpdate,
                   compact: compact) {
            model.primaryAction()
        }
    }

    /// Nothing a Mac can run (VR only, anti-cheat): the button says why instead.
    @MainActor private static func unavailable(_ game: Game, model: LibraryModel) -> Unavailable? {
        guard game.install == .notInstalled || game.install == .installed, !model.isRunning(game) else { return nil }
        if let drive = game.missingDrive, game.install == .notInstalled {
            return .init(title: L10n.t("Connect %@ to Play", drive), symbol: "externaldrive.badge.xmark")
        }
        if game.isVROnly && game.install == .notInstalled { return .init(title: L10n.t("VR only"), symbol: "visionpro") }
        if game.antiCheatBlock != nil && !game.playsInCloud {
            return .init(title: L10n.t("Doesn't run on a Mac"), symbol: "shield.slash")
        }
        return nil
    }
}

/// Before the meta line on Home's stage: "Recommended to start" in sodium for the first pick, and
/// on glass "Continue playing · 1.2 hrs" or "Up next" once a game was played.
private struct StageKicker: View {
    let text: String
    let prominent: Bool

    init?(role: LibraryModel.HomeRole, game: Game) {
        switch role {
        case .recommended:
            text = L10n.t("Recommended to start")
            prominent = true
        case .played:
            text = game.playtimeMinutes.map { $0 > 0 ? L10n.t("Continue playing · %@", Format.playtime($0)) : L10n.t("Continue playing") }
                ?? L10n.t("Continue playing")
            prominent = false
        case .upNext:
            text = L10n.t("Up next")
            prominent = false
        case .starter, .next:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if prominent { Image(systemName: "sparkle").font(size: 10, weight: .bold) }
            Text(text).font(size: 11.5, weight: .bold)
        }
        .foregroundStyle(prominent ? Theme.night : Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(prominent ? AnyShapeStyle(Theme.sodium) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
        .shadow(color: prominent ? Theme.sodium.opacity(0.4) : .clear, radius: 8)
        .fixedSize()
    }
}

/// A game the player owns in several stores (one card for all): the store it starts, downloads and
/// uninstalls through, and – while another of its stores downloads it – how far that is.
private struct StoreChoiceRow: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(L10n.t("Start through"))
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                // In the stores' own order, so the choice doesn't move the segments.
                Segmented(options: Provider.allCases.filter(game.providers.contains).map { ($0, $0.label, nil) },
                          selection: game.provider, id: "detail.store") { model.chooseStore($0, for: game) }
            }
            Label(L10n.t("Saves stay with each store."), systemImage: "externaldrive.badge.icloud")
                .font(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
            if game.shown.id != game.id, case .downloading(let fraction) = game.shown.install {
                Label(fraction.map { L10n.t("Downloading from %@ … %ld %%", game.shown.provider.label, Int($0 * 100)) }
                      ?? L10n.t("Preparing the download from %@ …", game.shown.provider.label),
                      systemImage: "arrow.down.circle")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

/// On a game's page, what its badge above the title means for this game, and where it was tested.
private struct CompatibilityNote: View {
    let compatibility: Compatibility

    var body: some View {
        let tested = compatibility.testedOn.isEmpty ? nil : L10n.t("Tested on %@", compatibility.testedOn.joined(separator: ", "))
        let parts = [compatibility.note, tested].compactMap { $0 }
        if !parts.isEmpty {
            Label(parts.joined(separator: " · "), systemImage: compatibility.level.symbol)
                .font(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
                .lineLimit(3)
                .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The newest engine crashed this game, so it runs with the previous one – and the way to give the
/// newest another try now rather than after the next update (EngineRollback).
private struct HeldEngineNote: View {
    let game: Game
    let held: HeldBuild
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(L10n.t("Runs with the previous engine from %@ – the newest one crashed it. Nightforge tries the new one again after the next update.",
                         EngineRollback.day(held.setUp)),
                  systemImage: "arrow.uturn.backward")
                .font(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.t("Try the Newest Now")) { model.tryNewestEngine(game) }
                .buttonStyle(GlassTextButtonStyle(small: true))
                .padFocus("detail.newestEngine", activate: { model.tryNewestEngine(game) })
        }
    }
}

/// Why a game with anti-cheat can't be played on a Mac, and where it can be streamed instead.
private struct AntiCheatNote: View {
    let block: AntiCheatBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t("This game's anti-cheat (%@) stops it on a Mac: it needs Windows itself, and getting around it would get your account banned.",
                         block.antiCheat.joined(separator: ", ")),
                  systemImage: "shield.slash")
            if block.geforceNow != nil {
                Label(L10n.t("Nightforge plays it on GeForce Now, NVIDIA's cloud gaming, with your Steam copy (own NVIDIA account; free sessions last an hour)."),
                      systemImage: "cloud")
            }
        }
        .font(size: 13, weight: .medium)
        .foregroundStyle(Theme.muted)
        .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(size: 12, weight: .medium)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(size: 16, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .fixedSize()  // its own width: FlowRow moves it to the next line instead of squeezing it
    }
}

/// The one big button: Download → Downloading … % → Play.
private struct PlayButton: View {
    let install: InstallState
    let isLaunching: Bool
    var isUninstalling = false
    var isRunning = false
    var needsConfirmation = false
    /// What the launch is busy with, when it's more than waiting for Steam.
    var status: String?
    /// Nothing a Mac can run (VR only, anti-cheat): what the button says instead.
    var unavailable: Unavailable?
    /// Streams from GeForce Now instead (anti-cheat games it carries).
    var cloud = false
    /// Steam stopped the download for lack of disk space: the button carries on with it.
    var noSpace = false
    /// A demo, for a game the player doesn't own.
    var demo = false
    /// An update Steam downloads first: its size, 0 when not known yet.
    var update: Int64?
    /// Smaller, for the game bar.
    var compact = false
    let action: () -> Void

    private var busy: Bool {
        if isLaunching || unavailable != nil || isUninstalling { return true }
        if case .downloading = install, !noSpace { return true }
        return false
    }

    private var title: String {
        if isLaunching, let status { return status }
        if isLaunching { return needsConfirmation ? L10n.t("Confirm in the Steam window") : L10n.t("Launching …") }
        if isUninstalling { return L10n.t("Uninstalling …") }
        if isRunning { return L10n.t("Running – switch to game") }
        if let unavailable { return unavailable.title }
        if cloud { return L10n.t("Play on GeForce Now") }
        if noSpace { return L10n.t("Continue Download") }
        switch install {
        case .installed where update != nil:
            return update! > 0 ? L10n.t("Update & Play · %@", Format.bytes(update!)) : L10n.t("Update & Play")
        case .installed: return demo ? L10n.t("Play Demo") : L10n.t("Play")
        case .notInstalled: return demo ? L10n.t("Download Demo") : L10n.t("Download")
        case .downloading(let fraction?): return L10n.t("Downloading … %ld %%", Int(fraction * 100))
        case .downloading(nil): return L10n.t("Preparing download …")
        case .inStore: return L10n.t("View in Steam Store")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isRunning && !busy {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                } else if let unavailable {
                    Image(systemName: unavailable.symbol)
                        .font(size: 15, weight: .bold)
                } else if cloud {
                    Image(systemName: "cloud.fill")
                        .font(size: 15, weight: .bold)
                } else if noSpace {
                    Image(systemName: "arrow.clockwise")
                        .font(size: 15, weight: .bold)
                } else if busy {
                    ProgressView()
                        .controlSize(.small)
                        .environment(\.colorScheme, .light)
                } else if install == .installed && update != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(size: 15, weight: .bold)
                } else {
                    Image(systemName: install == .notInstalled ? "arrow.down" : install == .inStore ? "cart" : "play.fill")
                        .font(size: 15, weight: .bold)
                }
                Text(title)
                    .displayFont(compact ? 14 : 17)
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.night)
            .padding(.horizontal, compact ? 20 : 32)
            .frame(height: compact ? 40 : 52)
            .animation(.easeOut(duration: 0.4), value: install)
        }
        .buttonStyle(GlassButtonStyle(glass: .tinted(Theme.sodium, glows: true), shape: Capsule(), dimmed: busy,
                                      progress: progress, fadesWhenDisabled: false))
        .disabled(busy && !(isLaunching && needsConfirmation))  // then it brings Steam's window up
    }

    /// How far a download is, filled into the button.
    private var progress: Double? {
        if case .downloading(let fraction?) = install, !noSpace { return fraction }
        return nil
    }

    struct Unavailable {
        let title: String
        let symbol: String
    }
}

struct RoundIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 52
    /// For a button whose symbol changes (hide/show): keeps the pad's highlight on it.
    var focusID: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(size: size * 0.32, weight: .semibold, scales: false)
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
        }
        .buttonStyle(GlassButtonStyle(shape: Circle()))
        .help(help)
        // Spoken without the shortcut in brackets ("Rescan library", not "arrow.clockwise").
        .accessibilityLabel(help.replacingOccurrences(of: #" \(.*\)$"#, with: "", options: .regularExpression))
        .padFocus(focusID ?? "round.\(symbol)", cornerRadius: size / 2, activate: action)
    }
}

/// Right-click on a cover: the same actions as the big view, without selecting first.
struct GameContextMenu: ViewModifier {
    let game: Game
    let index: Int
    @EnvironmentObject private var model: LibraryModel

    func body(content: Content) -> some View {
        content.contextMenu {
            switch game.install {
            case _ where game.playsInCloud:
                Button(L10n.t("Play on GeForce Now")) { select(); model.primaryAction() }
            case .installed where game.antiCheatBlock == nil || model.isRunning(game):
                Button(model.isRunning(game) ? L10n.t("Switch to Game") : game.demoOf != nil ? L10n.t("Play Demo") : L10n.t("Play")) {
                    select(); model.primaryAction()
                }
            case .notInstalled where !game.isVROnly && game.antiCheatBlock == nil:
                Button(game.demoOf != nil ? L10n.t("Download Demo") : L10n.t("Download")) { select(); model.primaryAction() }
            case .inStore:
                Button(L10n.t("View in Steam Store")) { model.openStorePage(game) }
            default:
                EmptyView()
            }
            if game.hasFolder {
                Button(L10n.t("Show game folder in Finder")) { select(); model.revealSelected() }
            }
            // Onto a drive plugged in, or back to the Mac (DriveMoves).
            if model.canMove(game) {
                Button(L10n.t("Move to …")) { model.requestMove(game) }
            }
            if model.canUninstall(game) {
                Divider()
                Button(game.isInstalled ? L10n.t("Uninstall …") : L10n.t("Cancel Download"), role: .destructive) {
                    model.requestUninstall(game)
                }
            }
        }
    }

    private func select() {
        model.select(index)
    }
}

struct CoverCard: View {
    let game: Game
    let isSelected: Bool
    var isRunning = false
    var isPinned = false
    /// The library's covers change size with a pinch (CoverSize); the rail's stay as they are.
    var width = CoverSize.regular.width
    @State private var cover: NSImage?
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)
                Text(game.name)
                    .font(size: 15, weight: .bold).fontWidth(.expanded)
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
        }
        .frame(width: width, height: width * 1.5)
        .saturation(shown.install == .notInstalled || shown.install == .inStore ? 0.15 : 1)
        .overlay(alignment: .bottom) { installBadge }
        .overlay(alignment: .topTrailing) {
            // Side by side: a game from several stores can use its Mac version from Steam.
            HStack(spacing: -7) {
                // Another store than Steam: which one (Steam is where most games come from); a game from
                // several stores names them all.
                if game.providers != [.steam] {
                    Text(game.providers.map(\.short).joined(separator: " + "))
                        .displayFont(9.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)  // small covers (a pinch) with two stores
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.night.opacity(0.78), in: Capsule())
                        .padding(7)
                        .help(L10n.t("From %@", Self.stores(game)))
                }
                // The version in use; in the store, that Steam has one.
                if game.platform == .mac || (game.install == .inStore && game.macNative) {
                    Text("MAC")
                        .displayFont(9.5)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.night.opacity(0.78), in: Capsule())
                        .padding(7)
                        .help(game.platform == .mac ? L10n.t("Uses the Mac version") : L10n.t("Steam also has a Mac version"))
                }
            }
        }
        .overlay(alignment: .topTrailing) { DemoTag(game: game) }
        .overlay(alignment: .bottomLeading) {
            // From the couch: which games play with a controller, at a glance.
            // Full support in the accent colour, so it reads across the room; partial in outline.
            if game.controller != .none {
                Image(systemName: game.controller == .full ? "gamecontroller.fill" : "gamecontroller")
                    .font(size: 15, weight: .bold, scales: false)
                    .foregroundStyle(game.controller == .full ? Theme.sodium : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.night.opacity(0.82), in: Capsule())
                    .padding(7)
                    .help(game.controller.help)
            }
        }
        .overlay(alignment: .topLeading) {
            if isPinned && !isRunning {
                Image(systemName: "pin.fill")
                    .font(size: 11, weight: .bold, scales: false)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Theme.night.opacity(0.78), in: Capsule())
                    .padding(7)
                    .help(L10n.t("Pinned to Home"))
            }
            if isRunning {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text(L10n.t("Running")).font(size: 11, weight: .bold)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.night.opacity(0.75), in: Capsule())
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.sodium, lineWidth: isSelected ? 3 : 0)
        )
        .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1)
        .opacity(isSelected ? 1 : 0.6)
        .shadow(color: .black.opacity(isSelected ? 0.55 : 0.25), radius: isSelected ? 22 : 8, y: isSelected ? 12 : 4)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        .help(game.name)
        // VoiceOver reads a cover as one button: the game and what its badges show.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: game.id) {
            cover = await ArtworkStore.shared.image(for: game, kind: .cover)
        }
    }

    /// A game from several stores shows what one of them is doing (a download), else the one it starts through.
    private var shown: Game { game.shown }

    /// "Steam and Epic Games".
    static func stores(_ game: Game) -> String {
        let labels = game.providers.map(\.label)
        return labels.count < 2 ? labels.joined() : L10n.t("%@ and %@", labels.dropLast().joined(separator: ", "), labels.last!)
    }

    private var spokenDescription: String {
        var parts = [game.name]
        switch shown.install {
        case .installed: parts.append(game.pendingUpdate != nil ? L10n.t("Installed, update waiting") : L10n.t("Installed"))
        case .downloading: parts.append(L10n.t("Downloading"))
        case .notInstalled where shown.onUnpluggedDrive: parts.append(L10n.t("Connect %@ to Play", shown.missingDrive ?? ""))
        case .notInstalled: parts.append(game.demoOf != nil ? L10n.t("Free demo") : L10n.t("In your library"))
        case .inStore: parts.append(L10n.t("In the Steam Store"))
        }
        if game.platform == .mac { parts.append(L10n.t("Uses the Mac version")) }
        if game.providers != [.steam] { parts.append(L10n.t("From %@", Self.stores(game))) }
        if isPinned { parts.append(L10n.t("Pinned to Home")) }
        if game.controller != .none { parts.append(game.controller.help) }
        if isRunning { parts.append(L10n.t("Running")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var installBadge: some View {
        switch shown.install {
        case .installed where game.pendingUpdate != nil:
            HStack {
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(size: 20, weight: .semibold, scales: false)
                    .foregroundStyle(Theme.ink, Theme.night.opacity(0.7))
                    .padding(8)
                    .help(game.provider != .steam ? L10n.t("An update is waiting – it comes from %@ before the game starts", game.provider.label)
                          : L10n.t("An update is waiting – Steam downloads it before the game starts"))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .installed:
            EmptyView()
        case .notInstalled where shown.onUnpluggedDrive:
            // Not a download: it's on a drive that's unplugged.
            HStack {
                Spacer()
                Image(systemName: "externaldrive.badge.xmark")
                    .font(size: 14, weight: .bold, scales: false)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Theme.night.opacity(0.82), in: Capsule())
                    .padding(7)
                    .help(L10n.t("Connect %@ to Play", shown.missingDrive ?? ""))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .notInstalled, .inStore:
            HStack {
                Spacer()
                if let block = game.antiCheatBlock {
                    // Instead of the download sign: this one won't run here, or only in the cloud.
                    Image(systemName: block.geforceNow != nil ? "cloud" : "shield.slash")
                        .font(size: 14, weight: .bold, scales: false)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Theme.night.opacity(0.82), in: Capsule())
                        .padding(7)
                        .help(block.geforceNow != nil ? L10n.t("Plays on GeForce Now – its anti-cheat doesn't run on a Mac")
                              : L10n.t("Anti-cheat stops this game on a Mac"))
                } else {
                    Image(systemName: game.install == .inStore ? "cart.circle.fill" : "arrow.down.circle.fill")
                        .font(size: 20, weight: .semibold, scales: false)
                        .foregroundStyle(Theme.ink, Theme.night.opacity(0.7))
                        .padding(8)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .downloading(let fraction):
            VStack(spacing: 0) {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.night.opacity(0.75))
                        Rectangle().fill(Theme.sodium).frame(width: geo.size.width * (fraction ?? 0))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Hints & empty state

private struct HintBar: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var focus = PadFocus.shared
    @ObservedObject private var toasts = Toasts.shared

    var body: some View {
        HStack(spacing: 22) {
            // During the first start's checklist the controller test shows the battery itself.
            if model.controllerConnected, let status = model.controllerStatus,
               !(model.showsFirstStart && model.setup.stage == .checklist) {
                Label(status.label, systemImage: status.symbol)
                    .font(size: 12, weight: .medium).monospacedDigit()
                    .foregroundStyle(status.isLow ? Theme.sodium : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(GlassBackground(glass: .regular, shape: Capsule()))
                    .help(L10n.t("Controller battery"))
            }
            Spacer()
            let pad = model.padSymbols
            if let action = toasts.current?.action, focus.focused != Toasts.padID {
                Hint(model.controllerConnected ? .pad(pad.stick) : .key("⌘↩"), text: action.label)
            }
            let controller = model.controllerConnected
            if controller && focus.focused != nil {
                Hint(.pad(pad.confirm), text: L10n.t("Select"))
                Hint(.pad(pad.stick), text: L10n.t("Move"))
                Hint(.pad(pad.back), text: L10n.t("Back"))
            } else {
                switch model.route {
                case .home where model.showsFirstStart:
                    // The first start's page: what Return and Esc do there.
                    if let action = SetupModel.confirmAction(stage: model.setup.stage, phase: model.setup.phase) {
                        Hint(controller ? .pad(pad.confirm) : .key("↵"), text: action.label)
                    }
                    if let action = SetupModel.backAction(stage: model.setup.stage, replay: model.setup.isReplay) {
                        Hint(controller ? .pad(pad.back) : .key("esc"), text: action.label)
                    }
                case .home:
                    if model.heroGame != nil {
                        Hint(controller ? .pad(pad.confirm) : .key("↵"), text: L10n.t("Play"))
                        Hint(controller ? .pad(pad.library) : .key("I"), text: L10n.t("Details"))
                    } else {
                        Hint(controller ? .pad(pad.confirm) : .key("↵"), text: L10n.t("Open"))
                    }
                    Hint(controller ? .pad("line.3.horizontal.circle.fill") : .key("L"), text: L10n.t("Library"))
                    Hint(controller ? .pad(pad.stick) : .key("← →"), text: L10n.t("Select"))
                case .library:
                    Hint(controller ? .pad(pad.confirm) : .key("↵"), text: L10n.t("Open"))
                    Hint(controller ? .pad(pad.stick) : .key("← ↑ →"),
                         text: L10n.t("Select"))
                    if !controller {
                        Hint(.key("⌘F"), text: L10n.t("Search"))
                    }
                    Hint(controller ? .pad(pad.back) : .key("esc"),
                         text: !model.searchText.isEmpty ? L10n.t("Clear search") : model.showingHidden ? L10n.t("All games") : L10n.t("Home"))
                case .detail(_, let from):
                    if let game = model.selected, game.install != .inStore {
                        // What Return does here: the big button's word, short.
                        Hint(controller ? .pad(pad.confirm) : .key("↵"),
                             text: game.install == .notInstalled && !game.playsInCloud ? L10n.t("Download") : L10n.t("Play"))
                        Hint(controller ? .pad(pad.options) : .key("O"), text: L10n.t("Options"))
                        if !controller {
                            Hint(.key("H"), text: model.isHidden(game) ? L10n.t("Show") : L10n.t("Hide"))
                        }
                    }
                    Hint(controller ? .pad(pad.back) : .key("esc"), text: from == .home ? L10n.t("Home") : L10n.t("Library"))
                }
            }
        }
        .opacity(model.games.isEmpty && !model.showsFirstStart ? 0 : 1)
    }
}

private struct Hint: View {
    /// A key on a glass keycap, or the controller's own button.
    enum Glyph {
        case key(String)
        case pad(String)
    }

    let glyph: Glyph
    let text: String

    init(_ glyph: Glyph, text: String) {
        self.glyph = glyph
        self.text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            switch glyph {
            case .key(let key):
                Text(key)
                    .font(size: 11, weight: .semibold)
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .padding(.horizontal, key.count > 1 ? 7 : 0)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(GlassBackground(glass: .regular, shape: Capsule()))
            case .pad(let symbol):
                Image(systemName: symbol).font(size: 17, weight: .semibold)
            }
            Text(text).font(size: 13, weight: .medium)
        }
        .foregroundStyle(Theme.muted)
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if Engine.isSteamInstalled {
            connected
        } else {
            bottles
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("Steam is connected"))
                .displayFont(36)
                .foregroundStyle(Theme.ink)
            Text(L10n.t("Install a game in Steam – it shows up here as soon as it's on your Mac."))
                .font(size: 15)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(L10n.t("Open Steam")) { model.openSteam() }
                    .padFocus("empty.openSteam", activate: { model.openSteam() })
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                Button(L10n.t("Rescan")) { model.rescan() }
                    .padFocus("empty.rescan", activate: { model.rescan() })
                    .buttonStyle(GlassTextButtonStyle())
            }
        }
    }

    private var bottles: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("No games here yet"))
                .displayFont(36)
                .foregroundStyle(Theme.ink)
            Text(L10n.t("Nightforge shows the Steam games installed in your CrossOver bottles. Install Steam in a bottle, download a game there, then rescan your library."))
                .font(size: 15)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("Scanned: %@", Prefs.bottlesRoot.path))
                .font(size: 12)
                .foregroundStyle(Theme.muted.opacity(0.8))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button(L10n.t("Rescan")) { model.rescan() }
                    .padFocus("empty.rescan", activate: { model.rescan() })
                    .buttonStyle(GlassTextButtonStyle(prominent: true))
                Button(L10n.t("Choose Another Folder …")) { model.chooseBottlesFolder() }
                    .padFocus("empty.chooseFolder", activate: { model.chooseBottlesFolder() })
                    .buttonStyle(GlassTextButtonStyle())
            }
        }
    }
}

extension ControllerSupport {
    var label: String {
        switch self {
        case .full: return L10n.t("Full")
        case .partial: return L10n.t("Partial")
        case .none: return L10n.t("Mouse & keyboard")
        }
    }

    var help: String {
        switch self {
        case .full: return L10n.t("Full controller support – playable from the couch")
        case .partial: return L10n.t("Partial controller support – some menus need a mouse or keyboard")
        case .none: return L10n.t("Made for mouse and keyboard")
        }
    }
}

/// Which version of the game Nightforge runs, and why – when Steam has both.
private struct VersionNotes: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = game.macPending {
                note(L10n.t("There's a Mac version of this game that runs without any Windows translation. Nightforge switches to it as soon as it's on your Mac – until then you play the Windows version."),
                     systemImage: "apple.logo")
                HStack(spacing: 10) {
                    if case .downloading(let fraction) = pending {
                        if let fraction {
                            GlassProgressBar(value: fraction)
                                .frame(width: 200)
                        } else {
                            GlassSpinner()
                        }
                        Text(fraction.map { L10n.t("Loading the Mac version … %ld %%", Int($0 * 100)) }
                             ?? L10n.t("Preparing the Mac version …"))
                            .font(size: 12, weight: .medium).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                        Button(L10n.t("Cancel")) { model.cancelMacVersion(of: game) }
                            .buttonStyle(GlassTextButtonStyle(small: true))
                            .padFocus("detail.cancelMac", enabled: model.uninstallingID == nil,
                                      activate: { model.cancelMacVersion(of: game) })
                    } else {
                        Button(game.macSize > 0 ? L10n.t("Load Mac Version (%@)", Format.bytes(game.macSize)) : L10n.t("Load Mac Version")) {
                            model.loadMacVersion(of: game)
                        }
                        .buttonStyle(GlassTextButtonStyle(small: true))
                        .padFocus("detail.loadMac", enabled: model.uninstallingID == nil,
                                  activate: { model.loadMacVersion(of: game) })
                    }
                }
                .padding(.leading, 26)
                .disabled(model.uninstallingID != nil)
            } else if let text {
                note(text, systemImage: game.platform == .mac ? "apple.logo" : "laptopcomputer")
            }
            if let leftover = game.windowsLeftover {
                HStack(spacing: 10) {
                    Label(L10n.t("The Windows version is still installed and takes %@.", Format.bytes(leftover)),
                          systemImage: "externaldrive")
                        .font(size: 13, weight: .medium)
                        .foregroundStyle(Theme.muted)
                    Button(L10n.t("Remove …")) { model.requestLeftoverRemoval(game) }
                        .buttonStyle(GlassTextButtonStyle(small: true))
                        .disabled(model.uninstallingID != nil || model.launchingID != nil)
                        .padFocus("detail.removeLeftover", enabled: model.uninstallingID == nil && model.launchingID == nil,
                                  activate: { model.requestLeftoverRemoval(game) })
                }
            }
        }
    }

    private var text: String? {
        if game.install == .inStore {
            return game.macNative ? L10n.t("Steam also has a Mac version of this game. Nightforge uses it once you own the game, if it runs on current Macs.") : nil
        }
        guard let reason = game.versionReason else { return nil }
        if game.platform == .mac {
            return game.macAppleSilicon
                ? L10n.t("Nightforge uses the Mac version of this game, made for Apple silicon – no Windows translation needed.")
                : L10n.t("Nightforge uses the Mac version of this game – no Windows translation needed. It's made for Intel Macs, so Rosetta runs it.")
        }
        switch reason {
        case .windowsBetter:
            return L10n.t("Steam also has a Mac version, but the Windows version runs better, so Nightforge uses that.")
        case .macTooOld:
            return L10n.t("Steam's Mac version of this game is too old for current Macs, so Nightforge uses the Windows version.")
        case .macFailed:
            return L10n.t("The Mac version didn't start, so Nightforge uses the Windows version. You can switch back in the game's options.")
        case .only, .chosen, .macRuns, .macInstalled:
            return nil
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(size: 13, weight: .medium)
            .foregroundStyle(Theme.muted)
            .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What Nightforge found out about a game that the player should know before pressing Play.
private struct GameInsightNotes: View {
    let game: Game
    let insight: GameInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if GameOptionsStore.load(game.gameID).graphics == .automatic,
               let healed = LaunchHealth.note(game.gameID, insight.attempts) {
                note(healed, systemImage: "wand.and.stars")
            }
            if insight.analysis.onlyD3D12, !insight.attempts.contains(where: { $0.graphics == .d3dmetal }) {
                note(L10n.t("This game uses DirectX 12 only, which runs on a Mac in part at best."), systemImage: "exclamationmark.triangle")
            }
            if let launcher = insight.analysis.launcher {
                note(L10n.t("Starts through another launcher: %@. Under Wine its window can stay empty or fail to sign in; if the game doesn't come up, a problem report helps.", launcher),
                     systemImage: "arrow.triangle.branch")
            } else if insight.analysis.usesWebView2 {
                note(L10n.t("Draws some windows (sign-in, news) with Microsoft WebView2, which can stay empty on a Mac."),
                     systemImage: "rectangle.dashed")
            }
            if !insight.analysis.antiCheat.isEmpty && game.antiCheatBlock == nil {
                note(L10n.t("Uses %@: online play with it doesn't work on a Mac, single player usually does.",
                            insight.analysis.antiCheat.joined(separator: ", ")),
                     systemImage: "shield.lefthalf.filled")
            }
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(size: 13, weight: .medium)
            .foregroundStyle(Theme.muted)
            .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
