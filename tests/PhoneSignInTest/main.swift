// The small page GOG's sign-in from the phone comes back through: the token, how long it lasts, one
// code and no more, that the server closes, and that nothing gets written down. The sockets stay on
// this Mac's loopback address: tests/PhoneSignInTest/run.sh
import CoreImage
import Foundation
import Network

@main @MainActor
struct PhoneSignInTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let loopback = PhoneNetworkAddress(ip: 0x7F00_0001, mask: 0xFF00_0000)
    static let goodAddress = "https://embed.gog.com/on_login_success?origin=client&code=abc-DEF_123"
    static let readCode: (String) -> String? = { URL(string: $0).flatMap(GOGSignIn.code(from:)) }

    static func main() {
        TestDefaults.useWorkFolder()
        token()
        door()
        expiry()
        form()
        requests()
        network()
        pages()
        words()
        writesNothing()
        qrCode()
        serverAnswers()
        serverClosesAfterTheCode()
        serverExpires()
        serverStops()
        stageEnd()
        print(failures == 0 ? "PhoneSignInTest: all good" : "PhoneSignInTest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Without sockets

    static func token() {
        let tokens = (0..<200).map { _ in PhoneSignInDoor.newToken() }
        check(Set(tokens).count == 200, "every door has its own token")
        check(tokens.allSatisfy { $0.count == 43 }, "256 bits")
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        check(tokens.allSatisfy { $0.unicodeScalars.allSatisfy(safe.contains) }, "that fit an address as they are")
    }

    static func door() {
        var door = PhoneSignInDoor(token: "secret")
        let path = "/secret"
        check(door.answer(method: "GET", path: path, form: "", code: readCode) == .page, "the right token gets the page")
        for wrong in ["/", "/secre", "/secretx", "/SECRET", "/secret/", "/secret?x=1", "/favicon.ico", ""] {
            check(door.answer(method: "GET", path: wrong, form: "", code: readCode) == .closed, "\(wrong) gets nothing")
        }
        check(door.answer(method: "DELETE", path: path, form: "", code: readCode) == .closed, "only reading and sending the form")

        check(door.answer(method: "POST", path: path, form: "address=nonsense", code: readCode) == .tryAgain, "what isn't an address asks again")
        check(door.answer(method: "POST", path: path, form: "other=1", code: readCode) == .tryAgain, "a form without the field too")
        for foreign in ["http://embed.gog.com/on_login_success?code=abc", "https://evil.example/on_login_success?code=abc",
                        "https://embed.gog.com/other?code=abc", "https://embed.gog.com/on_login_success"] {
            let sent = "address=" + foreign.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            check(door.answer(method: "POST", path: path, form: sent, code: readCode) == .tryAgain, "\(foreign) has no code for us")
        }
        check(door.isOpen, "and none of that closes the door")
        check(door.answer(method: "POST", path: "/wrong", form: "address=" + goodAddress, code: readCode) == .closed,
              "a good address with the wrong token gets nothing")
        check(door.isOpen, "and takes nothing from the right one")

        let sent = "address=" + goodAddress.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        check(door.answer(method: "POST", path: path, form: sent, code: readCode) == .accepted(code: "abc-DEF_123"), "the store's address hands over its code")
        check(!door.isOpen, "one code and the door is shut")
        check(door.answer(method: "POST", path: path, form: sent, code: readCode) == .closed, "the token doesn't work twice")
        check(door.answer(method: "GET", path: path, form: "", code: readCode) == .closed, "not even for the page")

        var closed = PhoneSignInDoor(token: "secret")
        closed.close()
        check(closed.answer(method: "GET", path: path, form: "", code: readCode) == .closed, "a closed door is closed")
    }

    static func expiry() {
        let start = Date(timeIntervalSince1970: 1000)
        var door = PhoneSignInDoor(token: "t", lifetime: 600, now: start)
        check(door.answer(method: "GET", path: "/t", form: "", now: start.addingTimeInterval(599), code: readCode) == .page, "still valid just before the end")
        check(door.answer(method: "GET", path: "/t", form: "", now: start.addingTimeInterval(600), code: readCode) == .closed, "over at the end")
        check(!door.isOpen, "and it stays over")
        check(door.answer(method: "GET", path: "/t", form: "", now: start.addingTimeInterval(1), code: readCode) == .closed, "a clock going back doesn't reopen it")
        check(PhoneSignInDoor.lifetime == 600, "ten minutes, as the stage says")
    }

    static func form() {
        check(PhoneSignInDoor.field("address", in: "a=1&address=https%3A%2F%2Fx.y%2Fz%3Fq%3D1&b=2") == "https://x.y/z?q=1", "percent-encoded, as browsers send it")
        check(PhoneSignInDoor.field("address", in: "address=+https%3A%2F%2Fx+") == "https://x", "spaces around a paste go")
        check(PhoneSignInDoor.field("address", in: "b=2") == nil, "no such field")
        check(PhoneSignInDoor.field("address", in: "address") == nil, "a field without a value")
    }

    static func requests() {
        let get = Data("GET /t HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        check(PhoneSignInRequest.read(get) == .ready(method: "GET", path: "/t", form: ""), "a plain request")
        check(PhoneSignInRequest.read(Data("GET /t HTTP/1.1\r\nHost".utf8)) == .incomplete, "half a head waits")
        let post = "POST /t HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
        check(PhoneSignInRequest.read(Data((post + "ab").utf8)) == .incomplete, "half a body waits")
        check(PhoneSignInRequest.read(Data((post + "abcde").utf8)) == .ready(method: "POST", path: "/t", form: "abcde"), "a whole form")
        check(PhoneSignInRequest.read(Data("nonsense\r\n\r\n".utf8)) == .invalid, "garbage")
        check(PhoneSignInRequest.read(Data("POST /t HTTP/1.1\r\nContent-Length: nope\r\n\r\n".utf8)) == .invalid, "a broken length")
        check(PhoneSignInRequest.read(Data("POST /t HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)) == .invalid, "a huge length isn't waited for")
        check(PhoneSignInRequest.read(Data(repeating: 65, count: PhoneSignInRequest.limit + 1)) == .invalid, "too much is refused")
    }

    static func network() {
        typealias C = PhoneNetworkAddress.Candidate
        let wifi = C(name: "en0", isActive: true, ip: 0xC0A8_0114, mask: 0xFFFF_FF00)
        check(PhoneNetworkAddress.pick([wifi])?.text == "192.168.1.20", "Wi-Fi with a private address")
        let unusable = [C(name: "lo0", isActive: true, ip: 0x7F00_0001, mask: 0xFF00_0000),
                        C(name: "utun3", isActive: true, ip: 0x0A08_0001, mask: 0xFFFF_FF00),
                        C(name: "bridge100", isActive: true, ip: 0xC0A8_4001, mask: 0xFFFF_FF00),
                        C(name: "en5", isActive: true, ip: 0xA9FE_0102, mask: 0xFFFF_0000),
                        C(name: "en6", isActive: true, ip: 0x0808_0808, mask: 0xFFFF_FF00),
                        C(name: "en7", isActive: false, ip: 0xC0A8_0202, mask: 0xFFFF_FF00)]
        check(PhoneNetworkAddress.pick(unusable) == nil, "no VPN, bridge, link-local, public or switched-off address")
        check(PhoneNetworkAddress.pick(unusable + [wifi])?.ip == wifi.ip, "the one that's left")
        check(PhoneNetworkAddress.isPrivate(0x0A00_0001) && PhoneNetworkAddress.isPrivate(0xAC1F_FFFF) && PhoneNetworkAddress.isPrivate(0xC0A8_0001), "the three private ranges")
        check(!PhoneNetworkAddress.isPrivate(0xAC20_0001) && !PhoneNetworkAddress.isPrivate(0xC0A9_0001), "and only those")
        let home = PhoneNetworkAddress(ip: 0xC0A8_0114, mask: 0xFFFF_FF00)
        check(home.reaches(0xC0A8_0163), "a phone on the same network")
        check(!home.reaches(0xC0A8_0263) && !home.reaches(0x0808_0808), "nobody else")
    }

    static func pages() {
        let pages = PhoneSignInPages.make(store: "GOG", storePage: GOGSignIn.signInURL, token: "the-token")
        let form = String(decoding: pages.form, as: UTF8.self)
        check(!form.lowercased().contains("type=\"password\""), "no password field, ever")
        check(!form.lowercased().contains("<script"), "no script")
        check(form.contains("action=\"/the-token\"") && form.contains("method=\"post\""), "the form comes back to its own address")
        check(form.contains("href=\"https://auth.gog.com/auth?") && form.contains("&amp;"), "the link goes to GOG's own page")
        check(form.contains("rel=\"noreferrer noopener\""), "and doesn't tell GOG the token")
        for header in ["Cache-Control: no-store", "Referrer-Policy: no-referrer", "Connection: close", "form-action 'self'"] {
            check(form.contains(header), "header: \(header)")
        }
        let done = String(decoding: pages.done, as: UTF8.self)
        check(!done.contains("the-token") && !done.contains("<form"), "the last page has no way back in")
        check(!String(decoding: pages.closed, as: UTF8.self).contains("the-token"), "a closed door says nothing")
        check(String(decoding: pages.retry, as: UTF8.self).hasPrefix("HTTP/1.1 422"), "a wrong paste is answered as one")
    }

    static func words() {
        check(SignInWords.window(.steam).contains("QR"), "Steam's stage names the QR code")
        check(SignInWords.window(.battlenet) != SignInWords.window(.steam), "Battle.net's says its own")
        check(SignInWords.saysKeyboard(.epic, controller: true), "Epic says so on the sofa")
        check(!SignInWords.saysKeyboard(.epic, controller: false), "not to someone at the desk")
        for provider in [Provider.steam, .gog, .battlenet] {
            check(!SignInWords.saysKeyboard(provider, controller: true), "\(provider): not Epic's sentence")
        }
        check(SignInWords.title(.epic, controller: false, onPhone: false) == L10n.t("Sign in once"), "Epic at the desk: as before")
        check(SignInWords.line(.epic, controller: false) == SignInWords.line(.epic), "word for word")
        check(SignInWords.title(.gog, controller: true, onPhone: true) == L10n.t("Sign in with your phone"), "GOG from the phone")
        check(SignInWords.phoneSteps(.gog).count == 3, "three steps, as on the board")
    }

    /// Nothing about the visitors or the code may end up in a file or a log.
    static func writesNothing() {
        for file in ["PhoneSignIn", "PhoneSignInServer", "PhoneSignInView"] {
            guard let text = try? String(contentsOfFile: "Sources/Nightforge/\(file).swift", encoding: .utf8) else {
                check(false, "\(file).swift can be read")
                continue
            }
            for word in ["GameLog", "print(", "NSLog", "os_log", "Logger(", ".write(to", "UserDefaults", "FileManager", "NSPasteboard"] {
                check(!text.contains(word), "\(file) has no \(word)")
            }
        }
    }

    static func qrCode() {
        let url = URL(string: "http://192.168.178.100:54321/" + PhoneSignInDoor.newToken())!
        guard let picture = PhoneSignInQR.picture(of: url) else { return check(false, "a QR code comes out") }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let reader = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let found = reader?.features(in: CIImage(cgImage: picture)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        check(found == [url.absoluteString], "the QR code reads as the address")
    }

    // MARK: - With sockets, on loopback only

    final class Run: @unchecked Sendable {
        let opened = DispatchSemaphore(value: 0)
        let ended = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var port_: UInt16 = 0
        private var endings_: [PhoneSignInServer.Ending] = []
        var server: PhoneSignInServer!
        var door: PhoneSignInDoor!

        var port: UInt16 { lock.withLock { port_ } }
        var endings: [PhoneSignInServer.Ending] { lock.withLock { endings_ } }
        func didOpen(_ port: UInt16) { lock.withLock { port_ = port }; opened.signal() }
        func didEnd(_ ending: PhoneSignInServer.Ending) { lock.withLock { endings_.append(ending) }; ended.signal() }
        var path: String { "/" + door.token }
    }

    static func start(lifetime: TimeInterval = 600) -> Run? {
        let run = Run()
        let door = PhoneSignInDoor(lifetime: lifetime)
        run.door = door
        let pages = PhoneSignInPages.make(store: "GOG", storePage: GOGSignIn.signInURL, token: door.token)
        run.server = PhoneSignInServer(address: loopback, door: door, pages: pages, readCode: readCode,
                                       deliver: DispatchQueue(label: "test"), opened: run.didOpen, ended: run.didEnd)
        run.server.start()
        guard run.opened.wait(timeout: .now() + 5) == .success, run.port != 0 else {
            check(false, "the server opens on loopback")
            return nil
        }
        return run
    }

    /// One request; what comes back, or nil when nobody's there.
    static func ask(_ port: UInt16, _ request: String) -> String? {
        final class Reply: @unchecked Sendable {
            var data = Data()
            var failed = false
            let done = DispatchSemaphore(value: 0)
        }
        let reply = Reply()
        let queue = DispatchQueue(label: "client")
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        @Sendable func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data { reply.data.append(data) }
                if isComplete || error != nil { reply.done.signal() } else { receive() }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in receive() })
            case .waiting, .failed:
                reply.failed = true
                reply.done.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        let answered = reply.done.wait(timeout: .now() + 5) == .success
        connection.cancel()
        return queue.sync { answered && !reply.failed && !reply.data.isEmpty ? String(decoding: reply.data, as: UTF8.self) : nil }
    }

    static func get(_ path: String) -> String { "GET \(path) HTTP/1.1\r\nHost: x\r\n\r\n" }

    static func post(_ path: String, _ address: String) -> String {
        let form = "address=" + address.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "POST \(path) HTTP/1.1\r\nHost: x\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: \(form.utf8.count)\r\n\r\n\(form)"
    }

    /// The listener goes a moment after it's told to.
    static func isGone(_ port: UInt16) -> Bool {
        for _ in 0..<20 {
            if ask(port, get("/")) == nil { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    static func serverAnswers() {
        guard let run = start() else { return }
        check(ask(run.port, get(run.path))?.hasPrefix("HTTP/1.1 200") == true, "the page, with the token")
        check(ask(run.port, get("/wrong"))?.hasPrefix("HTTP/1.1 404") == true, "nothing without it")
        check(ask(run.port, "nonsense\r\n\r\n") == nil, "garbage gets hung up on")
        check(ask(run.port, post(run.path, "nonsense"))?.hasPrefix("HTTP/1.1 422") == true, "a wrong paste asks again")
        check(run.endings.isEmpty, "none of that ends anything")
        run.server.stop()
    }

    static func serverClosesAfterTheCode() {
        guard let run = start() else { return }
        let port = run.port
        check(ask(port, post(run.path, goodAddress))?.hasPrefix("HTTP/1.1 200") == true, "the phone hears it worked")
        check(run.ended.wait(timeout: .now() + 3) == .success, "the code comes out")
        check(run.endings == [.code("abc-DEF_123")], "once, and only the code")
        check(isGone(port), "and the port is shut straight after")
        run.server.stop()
        check(run.endings.count == 1, "stopping afterwards ends nothing more")
    }

    static func serverExpires() {
        guard let run = start(lifetime: 0.4) else { return }
        let port = run.port
        check(ask(port, get(run.path))?.hasPrefix("HTTP/1.1 200") == true, "open at first")
        check(run.ended.wait(timeout: .now() + 3) == .success, "the time runs out by itself")
        check(run.endings == [.expired], "and says so")
        check(isGone(port), "the port is shut")
    }

    static func serverStops() {
        guard let run = start() else { return }
        let port = run.port
        // A browser that opened a connection and hasn't said anything yet.
        let idle = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let closed = DispatchSemaphore(value: 0)
        idle.start(queue: DispatchQueue(label: "idle"))
        idle.receive(minimumIncompleteLength: 1, maximumLength: 16) { _, _, isComplete, error in
            if isComplete || error != nil { closed.signal() }
        }
        Thread.sleep(forTimeInterval: 0.2)
        run.server.stop()
        check(closed.wait(timeout: .now() + 3) == .success, "stopping hangs up on whoever is still connected")
        check(isGone(port), "and shuts the port")
        check(run.endings.isEmpty, "the stage asked for it, so nothing is reported")
        idle.cancel()
    }

    /// The object the stage holds: the address it shows, and the end of it.
    static func stageEnd() {
        let phone = PhoneSignIn()
        phone.open(on: nil) { _ in }
        check(phone.state == .unavailable, "no network: says so")

        var codes: [String] = []
        phone.open(on: loopback) { codes.append($0) }
        func settle(_ test: () -> Bool) {
            let end = Date().addingTimeInterval(5)
            while !test(), Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        }
        var isOpen: Bool { if case .open = phone.state { return true } else { return false } }
        settle { isOpen }
        guard case .open(let first) = phone.state, let firstPort = first.port.map(UInt16.init) else { return check(false, "the stage gets an address") }
        check(first.absoluteString.hasPrefix("http://127.0.0.1:") && phone.picture != nil, "and a QR code for it")

        phone.open(on: loopback) { codes.append($0) }
        check(isGone(firstPort), "a new code shuts the old door")
        settle { isOpen }
        guard case .open(let second) = phone.state, let secondPort = second.port.map(UInt16.init) else { return check(false, "the new code opens") }
        check(first.path != second.path, "with a new token")

        phone.close()
        check(phone.state == .closed && phone.picture == nil, "the stage leaves: nothing left to show")
        check(isGone(secondPort), "and the door is shut")
        check(codes.isEmpty, "no code appeared on the way")

        phone.open(on: loopback, lifetime: 0.3) { codes.append($0) }
        settle { phone.state == .expired }
        check(phone.state == .expired && phone.picture == nil, "the time is up: the stage says so and drops the picture")

        phone.open(on: loopback) { codes.append($0) }
        settle { isOpen }
        guard case .open(let third) = phone.state, let thirdPort = third.port.map(UInt16.init) else { return check(false, "opens again after that") }
        DispatchQueue.global().async { _ = ask(thirdPort, post(third.path, goodAddress)) }
        settle { !codes.isEmpty }
        check(codes == ["abc-DEF_123"] && phone.state == .closed, "the code reaches the stage's end, and it's closed")
    }
}
