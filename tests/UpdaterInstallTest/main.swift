import CryptoKit
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        print("✗ \(message)")
    }
}

/// A made-up internet: an answer per address, nothing else.
final class Server: URLProtocol {
    enum Answer { case ok(Data), status(Int), failure }
    nonisolated(unsafe) static var answers: [String: Answer] = [:]
    nonisolated(unsafe) static var asked: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.asked.append(url.absoluteString)
        switch Self.answers[url.absoluteString] ?? .failure {
        case .ok(let data):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .status(let code):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
    override func stopLoading() {}
}

let fm = FileManager.default
let workshop = fm.temporaryDirectory.appendingPathComponent("workshop-\(UUID().uuidString)", isDirectory: true)
let key = Curve25519.Signing.PrivateKey()
let stranger = Curve25519.Signing.PrivateKey()
let keys = [key.publicKey.rawRepresentation.base64EncodedString()]
func sign(_ data: Data, _ with: Curve25519.Signing.PrivateKey = key) -> Data { Data(((try? with.signature(for: data))?.base64EncodedString() ?? "").utf8) }

@discardableResult func tool(_ path: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

/// A release's zip, holding what's asked for.
func zip(version: String, bundle: String = "test.nightforge.updater", minimumMac: String? = nil, codesigned: Bool = true, name: String = "Nightforge.app") -> Data {
    let folder = workshop.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let app = folder.appendingPathComponent(name, isDirectory: true)
    try? fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try? fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/Nightforge"))
    var info: [String: Any] = ["CFBundleIdentifier": bundle, "CFBundleExecutable": "Nightforge", "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
    if let minimumMac { info["LSMinimumSystemVersion"] = minimumMac }
    (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
    if codesigned { tool("/usr/bin/codesign", ["-f", "-s", "-", "--deep", app.path]) }
    else { tool("/usr/bin/codesign", ["--remove-signature", app.appendingPathComponent("Contents/MacOS/Nightforge").path]) }
    let out = folder.appendingPathComponent("out.zip")
    tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, out.path])
    return (try? Data(contentsOf: out)) ?? Data()
}

let zipURL = "https://example.test/Nightforge-9.9.9.zip"
let update = AppUpdate(version: "9.9.9", archive: URL(string: zipURL)!, signature: URL(string: zipURL + ".sig")!, page: URL(string: "https://example.test/page")!)

/// One try at installing: what it was turned away with.
func tryInstall(_ zipAnswer: Server.Answer, signature: Server.Answer) async -> Error? {
    Server.answers = [zipURL: zipAnswer, zipURL + ".sig": signature]
    do {
        try await Updater.install(update, keys: keys)
        return nil
    } catch {
        return error
    }
}

/// The temporary folder is the Mac's own here too (TMPDIR isn't always followed): only what wasn't there before counts.
let thereBefore = workFolders()
func workFolders() -> Set<String> {
    Set(((try? fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)) ?? []).filter { $0.hasPrefix("nightforge-update-") })
}
func leftovers() -> [String] { Array(workFolders().subtracting(thereBefore)) }

/// The swap's own folder goes before quitting (the `defer` wouldn't get to it), and after the swap: read from the source.
func cleansUpBeforeQuitting() {
    let source = (try? String(contentsOfFile: "Sources/Nightforge/Updater.swift", encoding: .utf8)) ?? ""
    guard let remove = source.range(of: "try? fm.removeItem(at: work)\n        await MainActor.run { _ = Quit.now") else {
        return check(false, "the work folder goes right before the quit")
    }
    check(source.range(of: "fm.replaceItemAt(app, withItemAt: fresh)")!.upperBound < remove.lowerBound, "after the swap, which needs what's in it")
}

func appUntouched() -> Bool {
    Bundle(url: Bundle.main.bundleURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.3.2"
        && fm.fileExists(atPath: Bundle.main.executablePath ?? "")
}

func turnedAway(_ error: Error?, _ what: String, _ matches: (Updater.Failure) -> Bool) {
    guard let failure = error as? Updater.Failure else {
        return check(false, "\(what): \(String(describing: error))")
    }
    check(matches(failure), "\(what): \(failure)")
    check(failure.errorDescription?.isEmpty == false, "\(what) says why")
    check(leftovers().isEmpty, "\(what): nothing left in the temporary folder: \(leftovers())")
    check(appUntouched(), "\(what): the app stays as it was")
}

func release(tag: String, sig: Bool = true) -> Data {
    let name = "Nightforge-\(tag.dropFirst()).zip"
    var assets: [[String: Any]] = [["browser_download_url": "https://example.test/\(name)"]]
    if sig { assets.append(["browser_download_url": "https://example.test/\(name).sig"]) }
    return (try? JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": "https://example.test/page", "assets": assets])) ?? Data()
}

let latest = "https://api.github.com/repos/LordHayne/Nightforge/releases/latest"

func checkRelease() async {
    check(Updater.currentVersion == "0.3.2", "the app's version is read from its bundle: \(Updater.currentVersion)")

    Server.answers = [latest: .ok(release(tag: "v0.4.0"))]
    var found = await Updater.check()
    check(found?.version == "0.4.0" && found?.signature.absoluteString.hasSuffix(".zip.sig") == true, "a newer release is offered: \(String(describing: found))")

    Server.answers = [latest: .ok(release(tag: "v0.3.2"))]
    found = await Updater.check()
    check(found == nil, "the same version isn't")
    Server.answers = [latest: .ok(release(tag: "v0.3.1"))]
    found = await Updater.check()
    check(found == nil, "an older one isn't")
    Server.answers = [latest: .ok(release(tag: "v0.4.0", sig: false))]
    found = await Updater.check()
    check(found == nil, "one without its signature isn't")
    Server.answers = [latest: .status(403)]
    found = await Updater.check()
    check(found == nil, "GitHub turning it away (its limit) is no update")
    Server.answers = [latest: .ok(Data("<html>".utf8))]
    found = await Updater.check()
    check(found == nil, "an answer that isn't JSON")
    Server.answers = [:]
    found = await Updater.check()
    check(found == nil, "offline")

    // A test release, for this Mac alone.
    Server.answers = [latest: .ok(release(tag: "v0.4.0")), "https://api.github.com/repos/LordHayne/Nightforge/releases/tags/v0.4.1-rc.2": .ok(release(tag: "v0.4.1-rc.2"))]
    UserDefaults.standard.set("v0.4.1-rc.2", forKey: Updater.testReleaseKey)
    found = await Updater.check()
    check(found?.version == "0.4.1-rc.2", "the test release this Mac is set to: \(String(describing: found))")
    UserDefaults.standard.set("../../evil", forKey: Updater.testReleaseKey)
    Server.asked = []
    found = await Updater.check()
    check(Server.asked == [latest] && found?.version == "0.4.0", "a tag that could be a path isn't followed: \(Server.asked)")
    UserDefaults.standard.removeObject(forKey: Updater.testReleaseKey)
}

func checkDownloads() async {
    let good = zip(version: "9.9.9", minimumMac: "99.0")
    let goodSig = Server.Answer.ok(sign(good))

    turnedAway(await tryInstall(.ok(good), signature: .status(404)), "no signature file") { if case .download = $0 { return true }; return false }
    turnedAway(await tryInstall(.status(500), signature: goodSig), "the zip doesn't come") { if case .download = $0 { return true }; return false }
    turnedAway(await tryInstall(.failure, signature: goodSig), "offline halfway") { if case .download = $0 { return true }; return false }
    turnedAway(await tryInstall(.ok(good), signature: .failure), "the signature doesn't come") { if case .download = $0 { return true }; return false }

    // The signature.
    turnedAway(await tryInstall(.ok(good), signature: .ok(sign(good, stranger))), "someone else's signature") { if case .signature = $0 { return true }; return false }
    turnedAway(await tryInstall(.ok(good + Data([0])), signature: goodSig), "a changed zip") { if case .signature = $0 { return true }; return false }
    turnedAway(await tryInstall(.ok(good), signature: .ok(Data("not base64 at all".utf8))), "rubbish for a signature") { if case .signature = $0 { return true }; return false }
    turnedAway(await tryInstall(.ok(good), signature: .ok(Data())), "an empty signature") { if case .signature = $0 { return true }; return false }

    // Signed, and still not what it should be.
    let notZip = Data("this isn't a zip".utf8)
    turnedAway(await tryInstall(.ok(notZip), signature: .ok(sign(notZip))), "signed, but no zip") { if case .unpack = $0 { return true }; return false }
    let empty = zip(version: "9.9.9", name: "Something.app")
    turnedAway(await tryInstall(.ok(empty), signature: .ok(sign(empty))), "no Nightforge.app in it") { if case .unpack = $0 { return true }; return false }
    let other = zip(version: "9.9.9", bundle: "com.example.other")
    turnedAway(await tryInstall(.ok(other), signature: .ok(sign(other))), "another program in it") { if case .unpack = $0 { return true }; return false }
    let older = zip(version: "0.1.0")
    turnedAway(await tryInstall(.ok(older), signature: .ok(sign(older))), "an old signed release under a new tag") {
        if case .otherVersion(let found, let named) = $0 { return found == "0.1.0" && named == "9.9.9" }
        return false
    }
    let unsigned = zip(version: "9.9.9", codesigned: false)
    turnedAway(await tryInstall(.ok(unsigned), signature: .ok(sign(unsigned))), "arrived damaged (no code signature)") { if case .signature = $0 { return true }; return false }
    turnedAway(await tryInstall(.ok(good), signature: goodSig), "needs a newer macOS") {
        if case .needsNewerMac(let required) = $0 { return required == "99.0" }
        return false
    }
}

@main struct Main {
    static func main() async {
        let mode = CommandLine.arguments.dropFirst().first ?? "normal"
        TestDefaults.useWorkFolder()
        _ = thereBefore  // before anything is tried
        URLProtocol.registerClass(Server.self)
        try? fm.createDirectory(at: workshop, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workshop) }
        switch mode {
        case "locked":
            Server.asked = []
            turnedAway(await tryInstall(.failure, signature: .failure), "a folder it can't write to") { if case .notWritable = $0 { return true }; return false }
            check(Server.asked.isEmpty, "nothing is downloaded for that: \(Server.asked)")
        case "translocated":
            Server.asked = []
            turnedAway(await tryInstall(.failure, signature: .failure), "started from its download") { if case .protectedPlace = $0 { return true }; return false }
            check(Server.asked.isEmpty, "nothing is downloaded for that: \(Server.asked)")
        default:
            await checkRelease()
            await checkDownloads()
            cleansUpBeforeQuitting()
        }
        print(failures == 0 ? "✓ Update turned away where it should be (\(mode))" : "✗ \(failures) failures (\(mode))")
        exit(failures == 0 ? 0 : 1)
    }
}
