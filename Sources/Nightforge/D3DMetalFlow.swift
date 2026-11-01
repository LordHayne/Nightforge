import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The question about Apple's D3DMetal, which a DirectX 12 game (or Settings) asks once: Apple's
/// licence in plain words, then the way it comes – Nightforge's download, or Apple's own toolkit,
/// imported. See D3DMetalSupply for what the answer is and where D3DMetal comes from.
struct D3DMetalDialog: Identifiable {
    enum Step: Equatable {
        case choose
        /// Setting it up: coming down (0…1, nil before it is known), going into the engine.
        case settingUp(Double?)
        /// Apple's page is open and Nightforge watches the Downloads folder.
        case waitingForApple
        case importing(String)
        case failed(String)
    }

    let id = UUID()
    /// The game whose start waits for the answer (nil: asked from Settings).
    var game: Game?
    var step = Step.choose
    /// Apple's licence was accepted before: it isn't shown again.
    var licenseAccepted: Bool
    /// Nightforge's own download is on offer; false when the component list has no D3DMetal.
    var downloadable: Bool
}

/// What is going on behind the dialog.
struct D3DMetalRun {
    var task: Task<Void, Never>?
    var game: Game?
    /// The answer on file when the question was opened; what stands if it is cancelled.
    var choiceBefore: D3DMetalSupply.Choice?
    /// An answer was recorded that goes away again with a cancel.
    var choiceChanged = false
    var finished = false
}

extension LibraryModel {
    /// A game that can't draw without D3DMetal, which isn't in the engine: the question comes before
    /// anything of the start, and the start follows once it's answered. True when the start waits.
    func askAboutD3DMetalBeforeStart(_ game: Game) -> Bool {
        guard game.bottle.isBuiltIn, game.platform == .windows, d3dMetalDialog == nil, !Engine.d3dMetalReady,
              Engine.installedWineNow().map({ Engine.isGPTKCapable(wine: $0) }) == true else { return false }
        let picked = GameOptionsStore.load(game.gameID).graphics
        if let analysis = insights[game.gameID]?.analysis {
            guard D3DMetalSupply.needed(by: analysis, picked: picked) else { return false }
            askAboutD3DMetal(for: game)
            return true
        }
        // Not looked at yet: look, then decide.
        Task {
            let insight = await self.insight(of: game)
            if D3DMetalSupply.needed(by: insight?.analysis, picked: picked) {
                askAboutD3DMetal(for: game)
            } else {
                launch(game, d3dMetalChecked: true)
            }
        }
        return true
    }

    /// Opens the question – or, when it was answered before and D3DMetal only isn't in the engine
    /// (a new engine, a download that failed), goes straight to setting it up.
    func askAboutD3DMetal(for game: Game?) {
        guard d3dMetalDialog == nil, !Engine.d3dMetalReady else { return }
        let choice = D3DMetalSupply.choice()
        d3dMetalRun = D3DMetalRun(game: game, choiceBefore: choice)
        d3dMetalDialog = D3DMetalDialog(game: game, licenseAccepted: choice != nil,
                                        downloadable: D3DMetalSupply.canDownload(ComponentStore.localManifest()))
        Task {
            let manifest = try? await ComponentStore.shared.manifest()
            d3dMetalDialog?.downloadable = D3DMetalSupply.canDownload(manifest)
            let atHand = D3DMetalSupply.current(manifest: manifest, componentsRoot: ComponentStore.shared.root)
            if atHand != nil, d3dMetalDialog?.step == .choose { setUpD3DMetal() }
        }
    }

    /// "Download from Nightforge".
    func downloadD3DMetal() {
        guard d3dMetalDialog != nil else { return }
        var choice = D3DMetalSupply.choice() ?? D3DMetalSupply.Choice(source: .nightforge, version: nil, accepted: Date())
        choice.source = .nightforge
        choice.version = nil
        D3DMetalSupply.save(choice)
        d3dMetalRun.choiceChanged = true
        setUpD3DMetal()
    }

    /// Puts D3DMetal into the engine from the way chosen: the download, a copy kept, the import.
    private func setUpD3DMetal() {
        d3dMetalDialog?.step = .settingUp(nil)
        d3dMetalRun.task?.cancel()
        d3dMetalRun.task = Task {
            let built = await rebuildEngine { step in
                guard case .downloading(let component, let fraction) = step, component.id == Engine.d3dMetalID else { return }
                Task { @MainActor in self.d3dMetalDialog?.step = .settingUp(fraction) }
            }
            guard !Task.isCancelled else { return }
            finishD3DMetal(engineBuilt: built)
        }
    }

    /// "Download from Apple and Import": Apple's page opens, and the toolkit is imported from the
    /// Downloads folder as soon as it is there.
    func importD3DMetalFromApple() {
        guard d3dMetalDialog != nil else { return }
        d3dMetalDialog?.step = .waitingForApple
        NSWorkspace.shared.open(D3DMetalSupply.appleDownloadURL)
        // A download that finished a moment ago counts; an old one in the folder doesn't.
        let since = Date().addingTimeInterval(-120)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        d3dMetalRun.task?.cancel()
        d3dMetalRun.task = Task {
            guard let file = await D3DMetalSupply.waitForToolkit(in: downloads, since: since) else {
                if !Task.isCancelled {
                    d3dMetalDialog?.step = .failed(L10n.t("Nothing arrived in your Downloads folder within half an hour. Try again once the download is done, or choose the file yourself."))
                }
                return
            }
            await importD3DMetal(from: file)
        }
    }

    /// "Choose File …": the toolkit's disk image, or the folder it opens to.
    func chooseD3DMetalFile() {
        let panel = NSOpenPanel()
        panel.message = L10n.t("Choose the Game Porting Toolkit you downloaded from Apple (the .dmg file, or the folder it opens to).")
        panel.allowedContentTypes = [.diskImage, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url, d3dMetalDialog != nil else { return }
        d3dMetalRun.task?.cancel()
        d3dMetalRun.task = Task { await importD3DMetal(from: url) }
    }

    private func importD3DMetal(from file: URL) async {
        d3dMetalDialog?.step = .importing(file.lastPathComponent)
        do {
            let version = try await Engine.offMain { () throws -> String in
                var isFolder: ObjCBool = false
                FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder)
                return isFolder.boolValue ? try D3DMetalSupply.importToolkit(from: file) : try D3DMetalSupply.importDiskImage(file)
            }
            guard !Task.isCancelled else { return }
            D3DMetalSupply.save(D3DMetalSupply.Choice(source: .apple, version: version,
                                                      accepted: D3DMetalSupply.choice()?.accepted ?? Date()))
            // Imported and kept; the engine takes it now or at the next start.
            d3dMetalRun.choiceChanged = false
            setUpD3DMetal()
        } catch {
            guard !Task.isCancelled else { return }
            d3dMetalDialog?.step = .failed(error.localizedDescription)
        }
    }

    private func finishD3DMetal(engineBuilt: Bool) {
        if Engine.d3dMetalReady {
            let game = d3dMetalRun.game
            d3dMetalRun = D3DMetalRun(finished: true)
            d3dMetalDialog = nil
            Toasts.shared.show(L10n.t("DirectX 12 is ready"))
            if let game { launch(allGames.first { $0.id == game.id } ?? game, d3dMetalChecked: true) }
            return
        }
        // A game runs: the engine's files wait until it ends (ensureEngine).
        if !running.isEmpty {
            d3dMetalDialog?.step = .failed(L10n.t("D3DMetal is ready and goes into the engine once no game is running. Close the game, then press Play again."))
        } else if engineBuilt {
            d3dMetalDialog?.step = .failed(L10n.t("D3DMetal didn't go into the engine. A problem report from the game's page helps."))
        } else {
            d3dMetalDialog?.step = .failed(L10n.t("D3DMetal couldn't be set up. Check your internet connection and try again."))
        }
    }

    /// The sheet is gone. A question left unanswered takes back what it recorded, and says why the
    /// game doesn't start.
    func d3dMetalDismissed() {
        let run = d3dMetalRun
        d3dMetalRun = D3DMetalRun()
        run.task?.cancel()
        guard !run.finished else { return }
        if run.choiceChanged {
            if let before = run.choiceBefore { D3DMetalSupply.save(before) } else { D3DMetalSupply.forget() }
        }
        if let game = run.game {
            Toasts.shared.show(L10n.t("%@ needs DirectX 12, which runs through Apple's D3DMetal. Without it the game doesn't start – set it up in Settings.", game.name))
        }
    }

    /// Settings › General's line about DirectX 12.
    var d3dMetalStatus: String {
        guard Engine.d3dMetalReady else { return L10n.t("Not set up") }
        switch D3DMetalSupply.choice()?.source {
        case .apple?: return L10n.t("Set up, imported from Apple")
        case .nightforge?: return L10n.t("Set up, from Nightforge")
        case nil: return L10n.t("Set up")
        }
    }
}

// MARK: - The sheet

struct D3DMetalSheet: View {
    let opened: D3DMetalDialog
    @EnvironmentObject private var model: LibraryModel

    /// As it is now: the sheet's item doesn't follow the steps by itself.
    private var dialog: D3DMetalDialog { model.d3dMetalDialog ?? opened }

    private var title: String {
        switch dialog.step {
        case .choose: return L10n.t("Set Up DirectX 12")
        case .settingUp, .importing: return L10n.t("Setting Up DirectX 12")
        case .waitingForApple: return L10n.t("Download from Apple")
        case .failed: return L10n.t("DirectX 12 isn't set up")
        }
    }

    var body: some View {
        GlassDialog(title, id: "d3dmetal", width: 520) {
            switch dialog.step {
            case .choose: choose
            case .settingUp(let fraction): progress(fraction.map { L10n.t("Downloading D3DMetal … %ld %%", Int($0 * 100)) }
                                                    ?? L10n.t("Setting up D3DMetal …"), fraction: fraction)
            case .waitingForApple: waiting
            case .importing(let name): progress(L10n.t("Importing %@ …", name), fraction: nil)
            case .failed(let message): failed(message)
            }
        }
    }

    // MARK: Steps

    @ViewBuilder private var choose: some View {
        Text(dialog.game.map { L10n.t("%@ draws with DirectX 12, which a Mac runs through Apple's D3DMetal.", $0.name) }
             ?? L10n.t("DirectX 12 games run on a Mac through Apple's D3DMetal."))
            .modifier(BodyText())
        if !dialog.licenseAccepted {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(L10n.t("D3DMetal is Apple's software, from the Game Porting Toolkit. Apple's licence lets you use it only for developing, testing or evaluating video games, on Apple hardware, and lets Nightforge pass it on only because Nightforge is free and non-commercial. By going on you accept Apple's licence. Nightforge asks this once."))
                        .modifier(BodyText())
                } icon: {
                    Image(systemName: "doc.text").foregroundStyle(Theme.muted)
                }
                button(L10n.t("Read Apple's Licence"), id: "licence", small: true) { NSWorkspace.shared.open(D3DMetalSupply.licenseTextURL) }
            }
        }
        if !dialog.downloadable {
            Text(L10n.t("Nightforge's own download of D3DMetal isn't available at the moment."))
                .modifier(BodyText(muted: true))
        }
        HStack(spacing: 8) {
            Spacer()
            button(L10n.t("Cancel"), id: "cancel") { model.d3dMetalDialog = nil }
            button(L10n.t("Download from Apple and Import"), id: "apple", prominent: !dialog.downloadable) { model.importD3DMetalFromApple() }
            if dialog.downloadable {
                button(L10n.t("Download from Nightforge"), id: "nightforge", prominent: true) { model.downloadD3DMetal() }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var waiting: some View {
        Text(L10n.t("Apple's download page is open in your browser. Sign in with your Apple Account and download the Game Porting Toolkit – the .dmg file. Nightforge notices it in your Downloads folder and imports it by itself."))
            .modifier(BodyText())
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(L10n.t("Waiting for the download …")).modifier(BodyText(muted: true))
        }
        HStack(spacing: 8) {
            Spacer()
            button(L10n.t("Cancel"), id: "cancel", preferred: true) { model.d3dMetalDialog = nil }
            button(L10n.t("Choose File …"), id: "file") { model.chooseD3DMetalFile() }
            button(L10n.t("Open Apple's Page Again"), id: "again") { NSWorkspace.shared.open(D3DMetalSupply.appleDownloadURL) }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func progress(_ text: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).modifier(BodyText(muted: true)).monospacedDigit()
        }
        HStack(spacing: 8) {
            Spacer()
            button(L10n.t("Cancel"), id: "cancel", preferred: true) { model.d3dMetalDialog = nil }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func failed(_ message: String) -> some View {
        Label {
            Text(message).modifier(BodyText())
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
        }
        HStack(spacing: 8) {
            Spacer()
            button(L10n.t("Close"), id: "cancel") { model.d3dMetalDialog = nil }
            button(L10n.t("Try Again"), id: "back", prominent: true) { model.d3dMetalDialog?.step = .choose }
        }
        .padding(.top, 4)
    }

    private func button(_ label: String, id: String, prominent: Bool = false, preferred: Bool = false, small: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(GlassTextButtonStyle(prominent: prominent, small: small))
            .fixedSize()
            .padFocus("d3dmetal.\(id)", cornerRadius: small ? 18 : 21, preferred: prominent || preferred, activate: action)
    }
}

private struct BodyText: ViewModifier {
    var muted = false

    func body(content: Content) -> some View {
        content
            .font(size: 14)
            .lineSpacing(3)
            .foregroundStyle(muted ? Theme.muted : Theme.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
}
