import CoreImage
import Foundation
import Network

/// The small page on the local network (PhoneSignIn.swift), only while a sign-in has it open: bound
/// to this Mac's address on the network, answers only that network, and closes when the code is
/// there, the time is up or the stage goes away. Requests aren't written down anywhere.
final class PhoneSignInServer: @unchecked Sendable {
    enum Ending: Equatable {
        case code(String), expired, failed
    }

    /// What a browser gets to finish one request.
    private static let patience: TimeInterval = 20
    private static let mostConnections = 8

    private let address: PhoneNetworkAddress
    private let pages: PhoneSignInPages
    private let readCode: (String) -> String?
    private let deliver: DispatchQueue
    private let opened: (UInt16) -> Void
    private let ended: (Ending) -> Void
    private let queue = DispatchQueue(label: "Nightforge.PhoneSignIn")

    // Only on `queue`.
    private var door: PhoneSignInDoor
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var expiry: DispatchWorkItem?
    private var finished = false

    init(address: PhoneNetworkAddress, door: PhoneSignInDoor, pages: PhoneSignInPages,
         readCode: @escaping (String) -> String?, deliver: DispatchQueue = .main,
         opened: @escaping (UInt16) -> Void, ended: @escaping (Ending) -> Void) {
        self.address = address
        self.door = door
        self.pages = pages
        self.readCode = readCode
        self.deliver = deliver
        self.opened = opened
        self.ended = ended
    }

    func start() {
        queue.async { [self] in
            guard !finished else { return }
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            guard let host = IPv4Address(address.text), door.isOpen else { return finish(.failed) }
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(host), port: .any)
            guard let listener = try? NWListener(using: parameters) else { return finish(.failed) }
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                self.listenerChanged(state, listener)
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)

            let expiry = DispatchWorkItem { [weak self] in self?.finish(.expired) }
            self.expiry = expiry
            queue.asyncAfter(deadline: .now() + max(0, door.deadline.timeIntervalSinceNow), execute: expiry)
        }
    }

    /// The stage went away. When this returns nobody gets in any more.
    func stop() {
        queue.sync { finish(nil) }
    }

    private func listenerChanged(_ state: NWListener.State, _ listener: NWListener) {
        guard !finished, listener === self.listener else { return }
        switch state {
        case .ready:
            if let port = listener.port?.rawValue { deliver.async { [opened] in opened(port) } }
        case .failed:
            finish(.failed)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard door.isOpen, connections.count < Self.mostConnections, isOnThisNetwork(connection.endpoint) else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections[id] = nil
            default: break
            }
        }
        connection.start(queue: queue)
        read(connection, Data())
        queue.asyncAfter(deadline: .now() + Self.patience) { [weak connection] in connection?.cancel() }
    }

    private func isOnThisNetwork(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint, case .ipv4(let peer) = host, peer.rawValue.count == 4 else { return false }
        return address.reaches(peer.rawValue.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: PhoneSignInRequest.limit) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let all = received + (data ?? Data())
            switch PhoneSignInRequest.read(all) {
            case .ready(let method, let path, let form):
                self.answer(connection, method, path, form)
            case .incomplete where !isComplete && error == nil:
                self.read(connection, all)
            case .incomplete, .invalid:
                connection.cancel()
            }
        }
    }

    private func answer(_ connection: NWConnection, _ method: String, _ path: String, _ form: String) {
        switch door.answer(method: method, path: path, form: form, code: readCode) {
        case .page: send(pages.form, to: connection)
        case .tryAgain: send(pages.retry, to: connection)
        case .closed: send(pages.closed, to: connection)
        case .accepted(let code):
            // Closed before the phone hears back: from here on the page is only saying goodbye.
            finish(.code(code), sparing: connection)
            send(pages.done, to: connection)
        }
    }

    private func send(_ page: Data, to connection: NWConnection) {
        connection.send(content: page, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ ending: Ending?, sparing kept: NWConnection? = nil) {
        guard !finished else { return }
        finished = true
        door.close()
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values where connection !== kept { connection.cancel() }
        if let ending { deliver.async { [ended] in ended(ending) } }
    }
}

/// The stage's end of it: opens the door for one sign-in and says what the QR code should show.
@MainActor
final class PhoneSignIn: ObservableObject {
    enum State: Equatable {
        case closed, opening
        case open(URL)
        case expired
        /// No local network, or the port wouldn't open.
        case unavailable
    }

    @Published private(set) var state = State.closed
    @Published private(set) var picture: CGImage?
    private var server: PhoneSignInServer?

    func open(on network: PhoneNetworkAddress? = PhoneNetworkAddress.current(), lifetime: TimeInterval = PhoneSignInDoor.lifetime,
              done: @escaping (String) -> Void) {
        close()
        guard let address = network else {
            state = .unavailable
            return
        }
        let door = PhoneSignInDoor(lifetime: lifetime)
        let pages = PhoneSignInPages.make(store: Provider.gog.label, storePage: GOGSignIn.signInURL, token: door.token)
        var made: PhoneSignInServer?
        let server = PhoneSignInServer(
            address: address, door: door, pages: pages,
            readCode: { URL(string: $0).flatMap(GOGSignIn.code(from:)) },
            opened: { [weak self] port in
                MainActor.assumeIsolated {
                    guard let self, let server = self.server, server === made,
                          let url = URL(string: "http://\(address.text):\(port)/\(door.token)") else { return }
                    self.picture = PhoneSignInQR.picture(of: url)
                    self.state = .open(url)
                }
            },
            ended: { [weak self] ending in
                MainActor.assumeIsolated {
                    guard let self, let server = self.server, server === made else { return }
                    self.server = nil
                    self.picture = nil
                    switch ending {
                    case .code(let code):
                        self.state = .closed
                        done(code)
                    case .expired: self.state = .expired
                    case .failed: self.state = .unavailable
                    }
                }
            })
        made = server
        self.server = server
        state = .opening
        server.start()
    }

    func close() {
        server?.stop()
        server = nil
        picture = nil
        state = .closed
    }
}

/// The QR code as a still picture, drawn once per sign-in.
enum PhoneSignInQR {
    static func picture(of url: URL) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(image, from: image.extent)
    }
}
