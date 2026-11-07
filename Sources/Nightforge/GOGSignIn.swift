import AppKit
import WebKit

/// GOG's own sign-in page (7.3), as GOG Galaxy shows it, on the stage (SignInStage). Password,
/// two-factor code and captcha stay on GOG's page – Nightforge never reads them. It only waits for
/// the address GOG sends the player on to, which carries a one-time code for gogdl. Nothing of the
/// visit is kept (no cookies, no cache).
@MainActor
enum GOGSignIn {
    /// GOG Galaxy's client ID: the one gogdl swaps the code with and keeps its tokens under.
    nonisolated static let clientID = "46899977096215655"

    /// GOG's sign-in for that client ID.
    nonisolated static let signInURL: URL = {
        var components = URLComponents(string: "https://auth.gog.com/auth")!
        components.queryItems = [URLQueryItem(name: "client_id", value: clientID),
                                 URLQueryItem(name: "redirect_uri", value: "https://embed.gog.com/on_login_success?origin=client"),
                                 URLQueryItem(name: "response_type", value: "code"),
                                 URLQueryItem(name: "layout", value: "galaxy")]
        return components.url!
    }()

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
    final class PageWatcher: SignInPageWatcher {
        override func code(from url: URL) -> String? { GOGSignIn.code(from: url) }
    }
}
