// Offline smoke test for ComponentStore: no network, only file:// components in a temp folder.
// Run with tests/ComponentsSmokeTest/run.sh

import CryptoKit
import Foundation

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        exit(1)
    }
}

let fm = FileManager.default
let work = fm.temporaryDirectory.appendingPathComponent("nightforge-smoke-\(UUID().uuidString)", isDirectory: true)
let payload = work.appendingPathComponent("payload", isDirectory: true)
try fm.createDirectory(at: payload.appendingPathComponent("bin"), withIntermediateDirectories: true)
try "hello".write(to: payload.appendingPathComponent("bin/wine"), atomically: true, encoding: .utf8)
defer { try? fm.removeItem(at: work) }

let archive = work.appendingPathComponent("engine-1.0.tar.gz")
let tar = Process()
tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
tar.arguments = ["-czf", archive.path, "-C", payload.path, "."]
try tar.run()
tar.waitUntilExit()

let script = work.appendingPathComponent("winetricks")
try "#!/bin/sh\necho ok\n".write(to: script, atomically: true, encoding: .utf8)

func component(_ id: String, _ kind: Component.Kind, _ file: URL, sha: String? = nil) throws -> Component {
    let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
    return Component(id: id, kind: kind, version: "1.0", url: file,
                     sha256: try sha ?? ComponentStore.sha256(of: file), size: size,
                     license: "LGPL-2.1-or-later", source: URL(string: "https://example.invalid")!)
}

let store = ComponentStore(root: work.appendingPathComponent("store"), remoteManifestURL: nil,
                           bundledManifestURL: URL(fileURLWithPath: "components/manifest.json"))

// The real manifest decodes and lists the engine.
let manifest = try await store.manifest()
check(manifest.component("wine") != nil, "bundled manifest decodes (\(manifest.components.count) components)")

// Archive: downloaded, verified, unpacked.
let engine = try component("engine", .engine, archive)
let reported = ProgressBox()
let dir = try await store.install(engine) { reported.value = $0 }
check(fm.fileExists(atPath: dir.appendingPathComponent("bin/wine").path), "archive unpacked to \(dir.lastPathComponent)/bin/wine")
check(reported.value == 1, "progress reaches 100 %")
check(await store.installedPath(for: engine) == dir, "installed version is recognised")

// Second install is a no-op.
let again = try await store.install(engine)
check(again == dir, "reinstall returns the existing folder")

// Single file (winetricks): copied and made executable.
let tool = try component("winetricks", .tool, script)
let toolDir = try await store.install(tool)
let mode = (try fm.attributesOfItem(atPath: toolDir.appendingPathComponent("winetricks").path)[.posixPermissions] as? Int) ?? 0
check(mode & 0o111 != 0, "single-file tool is executable")

// Wrong checksum is refused and leaves nothing behind.
let broken = try component("broken", .engine, archive, sha: String(repeating: "0", count: 64))
do {
    _ = try await store.install(broken)
    check(false, "checksum mismatch is refused")
} catch ComponentError.checksumMismatch {
    check(await store.installedPath(for: broken) == nil, "checksum mismatch is refused and not installed")
}

// A list with entries this version can't use keeps the rest: unknown kind, a version that would
// leave the components folder, plain HTTP, a missing field.
func entry(_ id: String, kind: String = "tool", version: String = "1.0", url: String = "https://example.com/a.tar.gz") -> String {
    #"{"id":"\#(id)","kind":"\#(kind)","version":"\#(version)","url":"\#(url)","sha256":"00","size":1,"license":"MIT","source":"https://example.com"}"#
}
let entries = [
    entry("good"), entry("future", kind: "plugin"), entry("escape", version: "../../Documents"),
    entry("plain", url: "http://example.com/a.tar.gz"), entry("hidden", url: "https://example.com/.."),
    #"{"id":"incomplete"}"#,
]
let mixed = #"{"schemaVersion":1,"generated":"now","components":["# + entries.joined(separator: ",") + "]}"
let lenient = try JSONDecoder().decode(ComponentManifest.self, from: Data(mixed.utf8))
check(lenient.components.map(\.id) == ["good"], "only the usable entry is kept (\(lenient.components.map(\.id)))")
// A list that names processors: no field and x86_64 and universal are what this Nightforge takes.
func archEntry(_ id: String, _ arch: String) -> String {
    String(entry(id).dropLast()) + #","arch":"\#(arch)"}"#
}
let archList = #"{"schemaVersion":1,"generated":"now","components":["#
    + [entry("plain"), archEntry("intel", "x86_64"), archEntry("both", "universal"), archEntry("wine-arm64", "arm64"), archEntry("odd", "riscv")].joined(separator: ",") + "]}"
let byArch = try JSONDecoder().decode(ComponentManifest.self, from: Data(archList.utf8))
check(byArch.components.map(\.id) == ["plain", "intel", "both"], "only what runs under Rosetta is kept (\(byArch.components.map(\.id)))")
check(byArch.component("plain")?.arch == nil, "no field stays no field")

let bundled = try JSONDecoder().decode(ComponentManifest.self, from: Data(contentsOf: URL(fileURLWithPath: "components/manifest.json")))
let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "components/manifest.json"))) as? [String: Any]
check(bundled.components.count == (raw?["components"] as? [Any])?.count, "every component of the shipped list is kept")

// After the Mac woke (WakeCatchUp): the online list is asked once more, a newer one waits until what it names is
// here, and only then is it the one in use. `manifest()` alone kept the list of the day Nightforge was opened.
let signingKey = Curve25519.Signing.PrivateKey()
let trusted = [signingKey.publicKey.rawRepresentation.base64EncodedString()]
let onlineList = work.appendingPathComponent("online-manifest.json")
// Stamps around today: a kept stamp more than two days ahead of the clock counts as none (SignedLists.isOlder).
func stamp(daysAgo: Double) -> String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-daysAgo * 86_400)) }
@discardableResult
func publish(daysAgo: Double, engine version: String, signed: Bool = true) throws -> Data {
    let data = Data((#"{"schemaVersion":1,"generated":"\#(stamp(daysAgo: daysAgo))","components":["# + entry("engine", kind: "engine", version: version) + "]}").utf8)
    try data.write(to: onlineList)
    try? fm.removeItem(at: Signature.file(for: onlineList))
    if signed { try Data(try signingKey.signature(for: data).base64EncodedString().utf8).write(to: Signature.file(for: onlineList)) }
    return data
}
func engineVersion(_ manifest: ComponentManifest?) -> String? { manifest?.component("engine")?.version }

try publish(daysAgo: 20, engine: "1.0")
let wokenRoot = work.appendingPathComponent("woken")
let woken = ComponentStore(root: wokenRoot, remoteManifestURL: onlineList, bundledManifestURL: nil, keys: trusted)
check(engineVersion(try await woken.manifest()) == "1.0", "the online list of the day Nightforge was opened is in use")
let nothingNew = await woken.askAgain()
check(nothingNew == nil, "asked again with nothing new online: nothing waits")
let newerBytes = try publish(daysAgo: 1, engine: "2.0")
check(engineVersion(try await woken.manifest()) == "1.0", "manifest() keeps its answer for the whole run")
let newerList = await woken.askAgain()
check(engineVersion(newerList) == "2.0", "asked again after the wake: the newer list is found")
check(engineVersion(try await woken.manifest()) == "1.0", "and isn't in use yet: a start meanwhile goes on with the list it had")

// What it names is fetched to wait: at hand, but not beside the installed engines.
let archive2 = work.appendingPathComponent("engine-2.0.tar.gz")
try fm.copyItem(at: archive, to: archive2)
let engine2 = Component(id: "engine", kind: .engine, version: "2.0", url: archive2, sha256: try ComponentStore.sha256(of: archive2),
                        size: 1, license: "LGPL-2.1-or-later", source: URL(string: "https://example.invalid")!)
let overtaken = Component(id: "old-tool", kind: .tool, version: "0.9", url: script, sha256: try ComponentStore.sha256(of: script),
                          size: 1, license: "MIT", source: URL(string: "https://example.invalid")!)
try await woken.fetchAhead(engine2)
try await woken.fetchAhead(overtaken)
let atHand = await woken.isAtHand(engine2), inPlace = await woken.installedPath(for: engine2)
check(atHand && inPlace == nil, "fetched ahead: at hand, not installed")
check(!fm.fileExists(atPath: wokenRoot.appendingPathComponent("engine").path),
      "no engine folder for whoever looks for the newest one (Engine.installedWineNow)")
let visible = ((try? fm.contentsOfDirectory(atPath: wokenRoot.path)) ?? []).filter { !$0.hasPrefix(".") && $0 != "manifest.json" && $0 != "manifest.json.sig" }
check(visible.isEmpty, "nothing the clean-up of unused components would see (\(visible))")

await woken.adoptWaiting()
check(engineVersion(try await woken.manifest()) == "2.0", "taken on: the newer list is the one in use")
check(Signature.signedContents(of: wokenRoot.appendingPathComponent("manifest.json"), keys: trusted) == newerBytes,
      "and kept with its signature for the next run")
let overtakenLeft = await woken.isAtHand(overtaken)
check(!overtakenLeft, "what waited for a list that never came into use is gone")
try fm.removeItem(at: archive2)  // no second download: there's nothing left to download from
let placed = try await woken.install(engine2)
check(placed.path.hasSuffix("woken/engine/2.0") && fm.fileExists(atPath: placed.appendingPathComponent("bin/wine").path),
      "install takes what was fetched ahead into its place")
let stillWaiting = await woken.hasWaitingList, askedOnceMore = await woken.askAgain()
check(!stillWaiting && askedOnceMore == nil, "nothing waits any more")

// An earlier signed list put back, and one without a signature: both turned away, as at Nightforge's start.
try publish(daysAgo: 10, engine: "0.5")
let putBack = await woken.askAgain()
check(putBack == nil && SignedLists.older.contains(SignedLists.components), "an older list online is turned away")
try publish(daysAgo: 0, engine: "9.0", signed: false)
let unsigned = await woken.askAgain()
check(unsigned == nil && SignedLists.refused.contains(SignedLists.components), "an unsigned one too")
// No answer (offline) leaves a list that already waits waiting.
try publish(daysAgo: 0, engine: "3.0")
let third = await woken.askAgain()
try fm.removeItem(at: onlineList)
let offline = await woken.askAgain()
check(engineVersion(third) == "3.0" && engineVersion(offline) == "3.0", "offline at the next look: the list that waits stays")

print("All component checks passed.")

final class ProgressBox: @unchecked Sendable {
    var value = 0.0
}
