import AppKit
import WebKit

/// Epic's own sign-in page in a window of its own (7.2). Password, two-factor code and captcha stay
/// on Epic's page – Nightforge never reads them. It only waits for the page Epic ends with, which
/// shows a one-time code for legendary, and closes the window then. Nothing of the visit is kept
/// (no cookies, no cache).
@MainActor
enum EpicSignIn {
    /// Epic's sign-in, sending the player on to the page with the code (the launcher's client ID,
    /// as legendary uses it).
    nonisolated static let signInURL: URL = {
        let redirect = "https://www.epicgames.com/id/api/redirect?clientId=34a02cf8f4414e29b15921876da36f9a&responseType=code"
        var components = URLComponents(string: "https://www.epicgames.com/id/login")!
        components.queryItems = [URLQueryItem(name: "redirectUrl", value: redirect)]
        return components.url!
    }()

    private static var window: NSWindow?
    private static var delegate: PageWatcher?

    /// Opens the window; `done` gets the code, or nil when the player closed it.
    static func present(done: @escaping (String?) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: configuration)
        // Epic's page lays itself out for Safari.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        let watcher = PageWatcher { code in
            finish(code, done: done)
        }
        web.navigationDelegate = watcher
        web.uiDelegate = watcher
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.t("Sign in to Epic Games")
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

    /// The code from the page Epic ends with: `{"redirectUrl": …, "authorizationCode": "…", …}`.
    nonisolated static func code(fromPage text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let code = object["authorizationCode"] as? String,
              !code.isEmpty, code.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        return code
    }

    /// Watches where the page goes: only the last page, Epic's answer with the code, is read.
    private final class PageWatcher: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
        let found: (String) -> Void
        var closed: () -> Void = {}

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url, url.host?.hasSuffix("epicgames.com") == true, url.path == "/id/api/redirect" else { return }
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                guard let text = result as? String, let code = EpicSignIn.code(fromPage: text) else { return }
                MainActor.assumeIsolated { self?.found(code) }
            }
        }

        /// "Sign in with Google/Apple …" opens a new window: here it opens in this one.
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
