import SwiftUI

/// The first start on Home: a welcome, the setup's checklist that fills itself in, the library
/// check, and how many of the games run here.
struct SetupView: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        Group {
            switch setup.stage {
            case .welcome:
                WelcomePage(setup: setup)
            case .checklist:
                ChecklistPage(setup: setup)
            case .checking(let check):
                CheckingPage(check: check, replay: setup.isReplay) { setup.close() }
            case .reveal(let reveal):
                RevealPage(reveal: reveal) { setup.close() }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 10)))
        .animation(.easeOut(duration: 0.3), value: setup.stage)
    }
}

private struct WelcomePage: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("Welcome to Nightforge"))
                    .font(Theme.display(48))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(SetupModel.welcomeText(replay: setup.isReplay))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                SetupButton(title: L10n.t("Let's Go"), symbol: "arrow.right", preferred: true) { setup.begin() }
                if setup.isReplay {
                    SkipButton { setup.close() }
                }
            }
        }
    }
}

private struct ChecklistPage: View {
    @ObservedObject var setup: SetupModel

    /// A narrow window keeps only the checklist.
    @State private var wide = true

    /// Beside the checklist, while Steam installs and updates itself: something to do – the
    /// controller test and the tips (SetupSidePanel).
    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            checklist
                .frame(maxWidth: .infinity, alignment: .leading)
            if wide {
                SetupSidePanel(paused: setup.phase == .waitingForSignIn)
                    .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1080 } action: { wide = $0 }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(L10n.t("Connecting Steam"))
                .font(Theme.display(40))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            StepList(setup: setup)

            if let note = SetupModel.signInNote(phase: setup.phase, steamStarting: setup.steamStarting) {
                QRNote(text: note)
                    .transition(.opacity)
            }

            actions
        }
        .animation(.easeOut(duration: 0.25), value: setup.phase)
        .animation(.easeOut(duration: 0.25), value: setup.steamStarting)
    }

    @ViewBuilder private var actions: some View {
        switch setup.phase {
        case .idle, .running, .done:
            EmptyView()

        case .needsRosetta:
            Note(L10n.t("Windows games need Rosetta from Apple. macOS asks for your password once to install it; by installing you accept Apple's Rosetta license."))
            SetupButton(title: L10n.t("Install Rosetta"), symbol: "arrow.down.circle", preferred: true) { setup.installRosetta() }

        case .waitingForSignIn:
            Button(L10n.t("Show Steam window again")) { setup.reopenSteam() }
                .buttonStyle(GlassTextButtonStyle())
                .padFocus("setup.showSteam", cornerRadius: 21, preferred: true, activate: { setup.reopenSteam() })

        case .failed(_, let message):
            Note(message, isError: true)
            SetupButton(title: L10n.t("Try again"), symbol: "arrow.clockwise", preferred: true) { setup.start() }
        }
    }
}

/// Steam's sign-in window and its QR code for the Steam app on the phone.
private struct QRNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 560, alignment: .leading)
        .background(GlassBackground(glass: .regular, shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .accessibilityElement(children: .combine)
    }
}

/// "Checking your library … N of M games", while Steam sends the library and each game is looked up.
private struct CheckingPage: View {
    let check: LibraryCheck
    let replay: Bool
    let skip: () -> Void

    var body: some View {
        let texts = SetupModel.checkingTexts(check, replay: replay)
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(L10n.t("Checking your library"))
            Text(texts.headline)
                .font(Theme.display(48).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            Group {
                if let fraction = check.fraction {
                    GlassProgressBar(value: fraction, height: 6)
                } else {
                    HStack(spacing: 10) {
                        GlassSpinner()
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 420)
            Text(texts.line)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            SkipButton(action: skip)
                .padding(.top, 8)
        }
    }
}

/// How many of the games run here, then "Let's Play". Epic Games is added in Settings › Stores.
private struct RevealPage: View {
    let reveal: LibraryReveal
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(L10n.t("Your library on this Mac"))
            Text(reveal.headline)
                .font(Theme.display(48))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if reveal.total > 0 {
                LibraryRevealView(reveal: reveal)
                    .frame(maxWidth: 760, alignment: .leading)
            } else {
                Text(L10n.t("Your Steam library has no games yet – the ones you get in Steam show up here by themselves."))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SetupButton(title: L10n.t("Let's Play"), symbol: "play.fill", preferred: true, action: play)
                .padding(.top, 6)
        }
    }
}

private struct SkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(L10n.t("Skip"), action: action)
            .buttonStyle(GlassTextButtonStyle())
            .padFocus("setup.skip", cornerRadius: 21, activate: action)
    }
}

private struct StepList: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SetupModel.Step.allCases) { step in
                let state = state(of: step)
                StepRow(
                    title: step.title,
                    state: state,
                    progress: setup.currentStep() == step ? setup.progress : nil,
                    detail: state == .done ? setup.summaries[step] : state == .active ? setup.detail : nil
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func state(of step: SetupModel.Step) -> StepRow.State {
        if setup.isFinished(step) { return .done }
        guard setup.currentStep() == step else { return .pending }
        switch setup.phase {
        case .failed: return .failed
        case .needsRosetta, .waitingForSignIn: return .waiting
        default: return .active
        }
    }
}

struct StepRow: View {
    enum State { case pending, active, waiting, done, failed }

    let title: String
    let state: State
    let progress: Double?
    /// What it's doing right now, or (done) how long it took – the first start's checklist.
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                switch state {
                case .pending:
                    Circle().strokeBorder(Theme.muted.opacity(0.5), lineWidth: 1.5)
                case .active:
                    GlassSpinner()
                case .waiting:
                    Image(systemName: "hand.point.right.fill").foregroundStyle(Theme.sodium)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sodium)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: state == .pending ? .regular : .semibold))
                    .foregroundStyle(state == .pending ? Theme.muted : Theme.ink)
                if let progress {
                    GlassProgressBar(value: progress)
                        .frame(width: 320)
                    if detail == nil {
                        Text("\(Int(progress * 100)) %")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: state == .done ? 12.5 : 13).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .contentTransition(.numericText())
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: detail)
        }
    }
}

struct Note: View {
    let text: String
    var isError = false

    init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(isError ? Theme.errorText : Theme.ink.opacity(0.85))
            .frame(maxWidth: 560, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SetupButton: View {
    let title: String
    let symbol: String
    /// In a dialog: where the pad's highlight starts.
    var preferred = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(Theme.display(17))
            }
            .foregroundStyle(Theme.night)
            .padding(.horizontal, 32)
            .frame(height: 52)
        }
        .buttonStyle(GlassButtonStyle(glass: .tinted(Theme.sodium, glows: true), shape: Capsule()))
        .keyboardShortcut(.defaultAction)
        .padFocus("setup.\(symbol)", cornerRadius: 26, preferred: preferred, activate: action)
    }
}
