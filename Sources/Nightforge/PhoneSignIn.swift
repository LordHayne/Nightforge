import CryptoKit
import Darwin
import Foundation

/// Signing in to GOG from the sofa: the store's real page opens on the phone, and only the one-time
/// code at its end comes back, through a small page Nightforge shows on the local network while the
/// sign-in is open (PhoneSignInServer). The password stays between the phone and GOG. This file has
/// what can be decided without a socket; nothing here or in the server writes anything down.

/// Who gets what: one random token in the address, for a limited time, for one code.
struct PhoneSignInDoor {
    enum Reply: Equatable {
        case page, tryAgain, accepted(code: String)
        /// A wrong token, an old one and a closed door all look the same from outside.
        case closed
    }

    static let lifetime: TimeInterval = 600

    let token: String
    let deadline: Date
    private(set) var isOpen = true

    init(token: String = newToken(), lifetime: TimeInterval = Self.lifetime, now: Date = Date()) {
        self.token = token
        self.deadline = now.addingTimeInterval(lifetime)
    }

    /// 256 random bits, short enough for a QR code that's easy to scan from the sofa.
    static func newToken() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `code` finds the store's one-time code in what the player pasted.
    mutating func answer(method: String, path: String, form: String, now: Date = Date(),
                         code: (String) -> String?) -> Reply {
        if now >= deadline { isOpen = false }
        guard isOpen, Self.same(path, "/" + token) else { return .closed }
        switch method {
        case "GET":
            return .page
        case "POST":
            guard let pasted = Self.field("address", in: form), let found = code(pasted) else { return .tryAgain }
            isOpen = false
            return .accepted(code: found)
        default:
            return .closed
        }
    }

    mutating func close() { isOpen = false }

    /// Looks at every character, so the time an answer takes says nothing about the token.
    private static func same(_ one: String, _ other: String) -> Bool {
        let a = Array(one.utf8), b = Array(other.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// A field of a form as browsers send it.
    static func field(_ name: String, in form: String) -> String? {
        for pair in form.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == name else { continue }
            return parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

/// The little HTTP a browser sends here. Anything longer than a form is refused.
enum PhoneSignInRequest: Equatable {
    case incomplete, invalid
    case ready(method: String, path: String, form: String)

    static let limit = 16 * 1024

    static func read(_ data: Data) -> Self {
        guard data.count <= limit else { return .invalid }
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let request = lines[0].split(separator: " ")
        guard request.count == 3, request[2].hasPrefix("HTTP/1.") else { return .invalid }
        var length = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            guard let value = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)),
                  value >= 0, value <= limit else { return .invalid }
            length = value
        }
        let body = data[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .ready(method: String(request[0]), path: String(request[1]),
                      form: String(decoding: body.prefix(length), as: UTF8.self))
    }
}

/// This Mac's address on the local network, and who counts as being on it.
struct PhoneNetworkAddress: Equatable {
    /// In the order they're written: 192.168.1.20 is 0xC0A80114.
    let ip: UInt32
    let mask: UInt32

    struct Candidate {
        let name: String
        let isActive: Bool
        let ip: UInt32
        let mask: UInt32
    }

    var text: String {
        [24, 16, 8, 0].map { String((ip >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    func reaches(_ peer: UInt32) -> Bool { peer & mask == ip & mask }

    /// The ranges meant for home and office networks.
    static func isPrivate(_ ip: UInt32) -> Bool {
        ip >> 24 == 10 || ip >> 20 == 0xAC1 || ip >> 16 == 0xC0A8
    }

    /// Wi-Fi or a cable (`en…`) with a private address. No VPN, no bridge, no direct cable link.
    static func pick(_ all: [Candidate]) -> Self? {
        all.filter { $0.isActive && $0.name.hasPrefix("en") && isPrivate($0.ip) && $0.mask != 0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .first.map { Self(ip: $0.ip, mask: $0.mask) }
    }

    static func current() -> Self? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var all: [Candidate] = []
        var entry = list
        while let item = entry?.pointee {
            defer { entry = item.ifa_next }
            guard let address = item.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = item.ifa_netmask else { continue }
            let read = { (socket: UnsafeMutablePointer<sockaddr>) in
                socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            let flags = Int32(item.ifa_flags)
            all.append(Candidate(name: String(cString: item.ifa_name), isActive: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                                 ip: read(address), mask: read(netmask)))
        }
        return pick(all)
    }
}

/// The pages the phone sees, written once when the door opens: nothing a visitor sends comes back in them.
struct PhoneSignInPages {
    let form: Data
    let retry: Data
    let done: Data
    let closed: Data

    @MainActor
    static func make(store: String, storePage: URL, token: String) -> Self {
        let form = page(store: store, storePage: storePage, token: token, mistake: nil)
        let retry = page(store: store, storePage: storePage, token: token,
                         mistake: L10n.t("That wasn't %@'s address. Copy the whole address of the page %@ ended on.", store, store))
        let done = shell("<h1>\(escape(L10n.t("All done")))</h1><p>\(escape(L10n.t("Nightforge carries on from here, you can put your phone down.")))</p>")
        return Self(form: response("200 OK", form), retry: response("422 Unprocessable Content", retry),
                    done: response("200 OK", done), closed: response("404 Not Found", shell("<h1>Nightforge</h1>")))
    }

    @MainActor
    private static func page(store: String, storePage: URL, token: String, mistake: String?) -> String {
        let warning = mistake.map { "<p class=\"mistake\">\(escape($0))</p>" } ?? ""
        return shell("""
        <h1>\(escape(L10n.t("Connect %@", store)))</h1>
        <section><h2>1 · \(escape(L10n.t("Sign in at %@", store)))</h2>
        <a class="go" href="\(escape(storePage.absoluteString))" target="_blank" rel="noreferrer noopener">\(escape(L10n.t("Open %@", store)))</a>
        <p>\(escape(L10n.t("You give your password only on %@'s page. Nightforge never sees it.", store)))</p></section>
        <form method="post" action="/\(escape(token))"><h2>2 · \(escape(L10n.t("Paste the address")))</h2>
        <p>\(escape(L10n.t("When %@ is through, copy the whole address from the address bar, come back to this tab and paste it here.", store)))</p>
        \(warning)<input name="address" type="url" inputmode="url" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" required>
        <button>\(escape(L10n.t("Done")))</button></form>
        """)
    }

    private static func shell(_ content: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\
        <title>Nightforge</title><style>\
        :root{color-scheme:dark}body{margin:0;background:#0f141c;color:#f3f1ec;font:17px/1.4 -apple-system,system-ui,sans-serif}\
        main{max-width:420px;margin:0 auto;padding:28px 20px}.mark{font-size:12px;letter-spacing:4px;color:#9aa3af;margin:0 0 18px}\
        h1{font-size:26px;margin:0 0 22px}h2{font-size:18px;margin:0 0 10px}section,form{margin:0 0 30px}p{color:#9aa3af;margin:10px 0}\
        .go,button{display:block;box-sizing:border-box;width:100%;padding:14px;border:0;border-radius:11px;background:#ffb347;color:#0f141c;\
        font:600 17px -apple-system,system-ui,sans-serif;text-align:center;text-decoration:none}\
        input{display:block;box-sizing:border-box;width:100%;padding:13px;margin:12px 0;border:1px solid #5a626e;border-radius:9px;\
        background:#141a24;color:#f3f1ec;font-size:16px}.mistake{color:#ffb4a8}\
        </style></head><body><main><p class="mark">NIGHTFORGE</p>\(content)</main></body></html>
        """
    }

    private static func response(_ status: String, _ html: String) -> Data {
        let body = Data(html.utf8)
        let head = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'",
            "Connection: close",
        ].joined(separator: "\r\n")
        return Data((head + "\r\n\r\n").utf8) + body
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
