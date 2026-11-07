import AppKit
import SwiftUI
import WebKit

/// Signing in to a store, on the curtain: the Nightforge mark and a few words on the left, the
/// store's real sign-in on the right. Epic's and GOG's page sits in the stage itself; Steam and
/// Battle.net sign in in their own window, which lies over the curtain. Nightforge has no field of
/// its own here: password and two-factor code stay with the store.
struct SignInStage: View {
    let provider: Provider
    @EnvironmentObject private var model: LibraryModel

    private static let slotWidth: CGFloat = 440
    private static let slotHeight: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            let room = geo.size.width - 2 * Theme.gutter - Self.slotWidth
            let gap = min(96, max(32, room - 340))
            VStack(spacing: 0) {
                HStack(spacing: gap) {
                    words.frame(width: min(500, room - gap))
                    slot
                        .frame(width: Self.slotWidth, height: min(Self.slotHeight, geo.size.height - 120))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .padding(.top, 36)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 22)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(background(geo.size))
        }
        .ignoresSafeArea()
    }

    /// The canvas's `radial-gradient(circle at 34% 48%, slate, night 62%)`, to the farthest corner.
    private func background(_ size: CGSize) -> some View {
        let center = CGPoint(x: size.width * 0.34, y: size.height * 0.48)
        let corner = hypot(max(center.x, size.width - center.x), max(center.y, size.height - center.y))
        return RadialGradient(colors: [Theme.slate, Theme.night], center: UnitPoint(x: 0.34, y: 0.48),
                              startRadius: 0, endRadius: corner * 0.62)
    }

    private var words: some View {
        VStack(spacing: 24) {
            StageMark()
            VStack(spacing: 10) {
                // Still centred: the space after the last letter is made up for on the left.
                Text(verbatim: "NIGHTFORGE")
                    .kerning(8)
                    .padding(.leading, 8)
                    .fontWidth(.expanded)
                    .font(size: 22, weight: .light)
                    .foregroundStyle(Color(nsColor: BrandArt.wordmark))
                Text(verbatim: provider.label.uppercased(with: L10n.locale))
                    .kerning(4)
                    .padding(.leading, 4)
                    .fontWidth(.expanded)
                    .font(size: 13)
                    .foregroundStyle(Color(nsColor: BrandArt.tagline))
            }
            Text(L10n.t("Sign in once"))
                .displayFont(30)
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text(SignInWords.line(provider))
                .font(size: 15)
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var slot: some View {
        switch provider {
        case .epic, .gog:
            StoreSignInSlot(provider: provider) { model.signInPageDone(provider, code: $0) }
        case .steam, .battlenet:
            ClientWindowSlot(provider: provider)
        }
    }

    /// One way out, with the mouse too: its keycap or pad button says how.
    private var footer: some View {
        HStack(spacing: 22) {
            Button { model.cancelSignIn() } label: {
                Hint(model.controllerConnected ? .pad(model.padSymbols.back) : .key("esc"),
                     text: model.launcherMenuOpen || model.showsLauncherCards
                        ? L10n.t("Cancel, back to the launcher menu") : L10n.t("Cancel"))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if provider.signsInInItsOwnWindow {
                Hint(model.controllerConnected ? .pad(model.padSymbols.confirm) : .key("↵"), text: L10n.t("Show Window Again"))
            }
            Spacer()
        }
    }
}

extension Provider {
    /// Steam and Battle.net sign in in a client of their own, Epic and GOG on a page in the stage.
    var signsInInItsOwnWindow: Bool { self == .steam || self == .battlenet }
}

/// The words on the stage, by what comes after the sign-in.
enum SignInWords {
    static func line(_ provider: Provider) -> String {
        switch provider {
        case .steam: return L10n.t("Your password only goes to %@. After that, %@ runs invisibly in the background.", "Valve", provider.label)
        case .battlenet: return L10n.t("Your password only goes to %@. After that, %@ runs invisibly in the background.", "Blizzard", provider.label)
        case .epic, .gog: return L10n.t("Your password only goes to %@. After that, Nightforge downloads and starts your games itself.", provider.label)
        }
    }

    /// Who's window it is: "Blizzard's window is open".
    static func windowOwner(_ provider: Provider) -> String { provider == .battlenet ? "Blizzard" : provider.label }
}

/// The N in brushed metal, drawn once (BrandArt). A still picture: nothing here redraws.
private struct StageMark: View {
    @Environment(\.displayScale) private var scale
    private static let height: CGFloat = 170

    var body: some View {
        let unit = Self.height / BrandArt.glyphSize.height
        let reach = BrandArt.reach * unit
        let size = CGSize(width: BrandArt.glyphSize.width * unit + 2 * reach, height: Self.height + 2 * reach)
        let picture = GameBackdrop.picture("signInMark", size: size, scale: scale) {
            BrandArt.drawMark($0, origin: CGPoint(x: reach, y: reach), scale: unit, seam: true, glow: unit / 0.78 * scale)
        }
        Group {
            if let picture { Image(decorative: picture, scale: scale) }
        }
        .frame(width: Self.height, height: Self.height)
        .accessibilityLabel("Nightforge")
    }
}

/// The store's page in its slot, once it has something to show.
private struct StoreSignInSlot: View {
    let provider: Provider
    let done: (String?) -> Void
    @State private var phase = StoreSignInPage.Phase.loading

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.night.opacity(0.7))
            switch phase {
            case .loading:
                GlassSpinner(size: 22)
            case .failed:
                Text(L10n.t("%@'s sign-in page doesn't answer. Check your internet connection.", provider.label))
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.errorText)
                    .multilineTextAlignment(.center)
                    .padding(32)
            case .shown:
                EmptyView()
            }
            StoreSignInPage(provider: provider, phase: $phase, done: done)
                .opacity(phase == .shown ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(L10n.t("Sign in to %@", provider.label))
    }
}

/// Where a client's own window lies. Nightforge can't move another app's window, so this says what's
/// going on and brings it forward when it went behind.
private struct ClientWindowSlot: View {
    let provider: Provider
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.t("%@'s window is open", SignInWords.windowOwner(provider)))
                .displayFont(19)
                .foregroundStyle(Theme.ink)
            Text(L10n.t("Sign in there, with two-factor too. Nightforge only lays it on the curtain."))
                .font(size: 13, weight: .medium)
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 300)
            Button(L10n.t("Show Window Again")) { model.showSignInWindow(provider) }
                .buttonStyle(GlassTextButtonStyle(small: true))
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.night.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
    }
}

/// The page of a store that signs in on the web (EpicSignIn, GOGSignIn), in the stage. Nothing of
/// the visit is kept (no cookies, no cache), and only the store's last address or answer is read.
struct StoreSignInPage: NSViewRepresentable {
    enum Phase { case loading, shown, failed }

    let provider: Provider
    @Binding var phase: Phase
    /// The store's one-time code. Called once.
    let done: (String) -> Void

    init(provider: Provider, phase: Binding<Phase>, done: @escaping (String?) -> Void) {
        self.provider = provider
        self._phase = phase
        self.done = { done($0) }
    }

    func makeCoordinator() -> SignInPageWatcher {
        provider == .gog ? GOGSignIn.PageWatcher() : EpicSignIn.PageWatcher()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 560), configuration: configuration)
        // The stores' pages lay themselves out for Safari.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        update(context.coordinator)
        web.load(URLRequest(url: provider == .gog ? GOGSignIn.signInURL : EpicSignIn.signInURL))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        update(context.coordinator)
    }

    private func update(_ watcher: SignInPageWatcher) {
        let phase = $phase
        watcher.found = done
        watcher.changed = { phase.wrappedValue = $0 }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: SignInPageWatcher) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }
}

/// What every store's page needs from its watcher: when it shows, when it fails, and sign-ins that
/// open a window of their own ("Sign in with Google …"), which open in the same place.
class SignInPageWatcher: NSObject, WKNavigationDelegate, WKUIDelegate {
    var found: (String) -> Void = { _ in }
    var changed: (StoreSignInPage.Phase) -> Void = { _ in }

    /// The code in an address the store sends the player on to: that page isn't loaded.
    func code(from url: URL) -> String? { nil }

    // Here and not in a store's subclass: only a method of the class that conforms reaches WebKit.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let code = code(from: url) {
            decisionHandler(.cancel)
            found(code)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        changed(.shown)
        // The keys go to the page, without a click first.
        webView.window?.makeFirstResponder(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let error = error as NSError
        // A page that's called off is no failure: the address with the code stops there on purpose.
        guard error.domain == NSURLErrorDomain, error.code != NSURLErrorCancelled else { return }
        changed(.failed)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}
