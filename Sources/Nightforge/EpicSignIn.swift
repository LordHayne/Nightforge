import AppKit
import WebKit

/// Epic's own sign-in page (7.2), on the stage (SignInStage). Password, two-factor code and captcha
/// stay on Epic's page – Nightforge never reads them. It only waits for the page Epic ends with,
/// which shows a one-time code for legendary. Nothing of the visit is kept (no cookies, no cache).
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
    final class PageWatcher: SignInPageWatcher {
        override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url, url.host?.hasSuffix("epicgames.com") == true, url.path == "/id/api/redirect" else {
                return super.webView(webView, didFinish: navigation)
            }
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                guard let text = result as? String, let code = EpicSignIn.code(fromPage: text) else { return }
                MainActor.assumeIsolated { self?.found(code) }
            }
        }
    }
}
