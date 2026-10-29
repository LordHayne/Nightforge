import AppKit
import WebKit

/// GOG's own sign-in page in a window of its own (7.3), as GOG Galaxy shows it. Password, two-factor
/// code and captcha stay on GOG's page – Nightforge never reads them. It only waits for the address
/// GOG sends the player on to, which carries a one-time code for gogdl, and closes the window then.
/// Nothing of the visit is kept (no cookies, no cache).
@MainActor
enum GOGSignIn {
    /// GOG's sign-in for GOG Galaxy's client ID (the one gogdl swaps the code with).
    nonisolated static let signInURL: URL = {
        var components = URLComponents(string: "https://auth.gog.com/auth")!
        components.queryItems = [URLQueryItem(name: "client_id", value: "46899977096215655"),
                                 URLQueryItem(name: "redirect_uri", value: "https://embed.gog.com/on_login_success?origin=client"),
                                 URLQueryItem(name: "response_type", value: "code"),
                                 URLQueryItem(name: "layout", value: "galaxy")]
        return components.url!
    }()

    private static var window: NSWindow?
    private static var delegate: PageWatcher?

    /// Opens the window; `done` gets the code, or nil when the player closed it.
    static func present(done: @escaping (String?) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: configuration)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        let watcher = PageWatcher { code in
            finish(code, done: done)
        }
        web.navigationDelegate = watcher
        web.uiDelegate = watcher
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.t("Sign in to GOG")
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()
        watcher.closed = { finish(nil, done: done) }
        window.delegate = watcher
        self.window = window
        self.delegate = watcher
        web.load(URLRequest(url: signInURL))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func bringToFront() {
        window?.makeKeyAndOrderFront(nil)
    }

    private static func finish(_ code: String?, done: (String?) -> Void) {
        guard let window else { return }
        self.window = nil
        delegate = nil
        window.delegate = nil
        window.close()
        done(code)
    }

    /// The code from the address GOG ends with: https://embed.gog.com/on_login_success?origin=client&code=…
    nonisolated static func code(from url: URL) -> String? {
        guard url.scheme == "https", url.host == "embed.gog.com", url.path == "/on_login_success",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 2048,
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") })
        else { return nil }
        return code
    }

    /// Watches where the page goes: only the address GOG sends the player on to is read, and that
    /// page isn't loaded.
    private final class PageWatcher: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
        let found: (String) -> Void
        var closed: () -> Void = {}

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, let code = GOGSignIn.code(from: url) {
                decisionHandler(.cancel)
                found(code)
                return
            }
            decisionHandler(.allow)
        }

        /// "Sign in with Google …" opens a new window: here it opens in this one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated { closed() }
        }
    }
}
