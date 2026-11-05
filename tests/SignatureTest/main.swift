// Checks the Ed25519 signatures Nightforge asks for before it installs an update or takes an online
// list: a good one, the spare key's, a stranger's, a changed file, a missing or broken signature; the
// release the updater picks from GitHub's answer (and what 0.3.0's updater picks from a signed
// release); and the component and profile lists, fetched from file:// "online" copies into a home of
// the test's own: tests/SignatureTest/run.sh
import CryptoKit
import Foundation

@main
struct SignatureTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let mainKey = Curve25519.Signing.PrivateKey()
    static let spareKey = Curve25519.Signing.PrivateKey()
    static let strangerKey = Curve25519.Signing.PrivateKey()
    static let keys = [mainKey, spareKey].map { $0.publicKey.rawRepresentation.base64EncodedString() }

    static func sign(_ data: Data, _ key: Curve25519.Signing.PrivateKey = mainKey) -> Data {
        Data(((try? key.signature(for: data))?.base64EncodedString() ?? "").utf8 + [0x0a])
    }

    static let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("nightforge-signature-test-\(UUID().uuidString)", isDirectory: true)

    static func main() async {
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        signatures()
        files()
        await fetching()
        updates()
        await components()
        await profiles()
        try? FileManager.default.removeItem(at: work)
        print(failures == 0 ? "✓ Signature" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func signatures() {
        let data = Data("{\"schemaVersion\": 1}".utf8)
        check(Signature.isValid(sign(data), of: data, keys: keys), "signed with the main key: it holds")
        check(Signature.signer(of: data, signature: sign(data), keys: keys) == keys[0], "and says it's the main key")
        check(Signature.signer(of: data, signature: sign(data, spareKey), keys: keys) == keys[1], "the spare key's holds as well")
        check(!Signature.isValid(sign(data, strangerKey), of: data, keys: keys), "a stranger's key doesn't")
        check(!Signature.isValid(sign(data), of: Data("{\"schemaVersion\": 2}".utf8), keys: keys), "a file changed after signing doesn't")
        check(!Signature.isValid(Data(), of: data, keys: keys), "no signature at all doesn't")
        check(!Signature.isValid(Data("not base64 !".utf8), of: data, keys: keys)
              && !Signature.isValid(Data(String(String(decoding: sign(data), as: UTF8.self).dropLast(5)).utf8), of: data, keys: keys),
              "nor a broken or cut-off one")
        check(!Signature.isValid(sign(data), of: data, keys: []) && !Signature.isValid(sign(data), of: data, keys: ["", "AAAA"]),
              "with no keys (before make-signing-keys.sh) nothing counts")
        let crlf = Data(String(decoding: sign(data), as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)
        check(Signature.isValid(crlf, of: data, keys: keys), "a line end from Windows doesn't matter")
        // After a key change a file carries two signatures: one that holds is enough.
        let two = sign(data, strangerKey) + sign(data, spareKey)
        check(Signature.signer(of: data, signature: two, keys: keys) == keys[1], "two lines: the spare's holds, the stranger's is passed over")
        check(!Signature.isValid(sign(data, strangerKey) + sign(Data("old".utf8)), of: data, keys: keys), "two lines, neither holds: no")
        check(!SigningKeys.trusted.contains(""), "an empty key in SigningKeys.swift isn't trusted")
    }

    static func files() {
        let file = work.appendingPathComponent("manifest.json")
        let data = Data("{\"a\": 1}".utf8)
        try? data.write(to: file)
        check(Signature.file(for: file).lastPathComponent == "manifest.json.sig", "the signature lies beside the file")
        check(Signature.file(for: URL(string: "https://raw.githubusercontent.com/LordHayne/Nightforge/main/profiles/profiles.json")!).absoluteString
              == "https://raw.githubusercontent.com/LordHayne/Nightforge/main/profiles/profiles.json.sig", "online too")
        check(Signature.signedContents(of: file, keys: keys) == nil, "a file without its signature isn't read")
        try? sign(data).write(to: Signature.file(for: file))
        check(Signature.signedContents(of: file, keys: keys) == data, "with it, it is")
        try? Data("{\"a\": 2}".utf8).write(to: file)
        check(Signature.signedContents(of: file, keys: keys) == nil, "changed on disk, it isn't")
    }

    static func fetching() async {
        let online = work.appendingPathComponent("online", isDirectory: true)
        try? FileManager.default.createDirectory(at: online, withIntermediateDirectories: true)
        let list = online.appendingPathComponent("list.json")
        let data = Data("{\"b\": 1}".utf8)
        try? data.write(to: list)
        if case .refused = await Signature.fetch(list, keys: keys) {} else { check(false, "a list without its .sig is turned away") }
        try? sign(data, strangerKey).write(to: Signature.file(for: list))
        if case .refused = await Signature.fetch(list, keys: keys) {} else { check(false, "one with a stranger's signature too") }
        try? sign(data).write(to: Signature.file(for: list))
        if case .signed(let got, let signature) = await Signature.fetch(list, keys: keys) {
            check(got == data && Signature.isValid(signature, of: got, keys: keys), "a signed one comes with its signature")
        } else {
            check(false, "a signed list is taken")
        }
        if case .unavailable = await Signature.fetch(online.appendingPathComponent("gone.json"), keys: keys) {} else {
            check(false, "nothing at the address: unavailable, not refused")
        }
    }

    /// GitHub's answer for a release, its assets in the order GitHub lists them (by name).
    static func release(_ tag: String, signed: Bool) -> Data {
        let version = tag.dropFirst()
        let base = "https://github.com/LordHayne/Nightforge/releases/download/\(tag)/Nightforge-\(version)"
        let names = [".dmg", ".zip"] + (signed ? [".zip.sig"] : [])
        let assets = names.map { #"{"name": "Nightforge-\#(version)\#($0)", "browser_download_url": "\#(base)\#($0)"}"# }
        return Data(#"{"tag_name": "\#(tag)", "html_url": "https://github.com/LordHayne/Nightforge/releases/tag/\#(tag)", "assets": [\#(assets.joined(separator: ","))]}"#.utf8)
    }

    static func updates() {
        let update = Updater.release(from: release("v0.3.2", signed: true), newerThan: "0.3.1")
        check(update?.version == "0.3.2" && update?.archive.lastPathComponent == "Nightforge-0.3.2.zip"
              && update?.signature.lastPathComponent == "Nightforge-0.3.2.zip.sig", "a signed release: the zip and its signature")
        check(Updater.release(from: release("v0.3.2", signed: false), newerThan: "0.3.1") == nil, "an unsigned one isn't offered")
        check(Updater.release(from: release("v0.3.1", signed: true), newerThan: "0.3.1") == nil
              && Updater.release(from: release("v0.3.0", signed: false), newerThan: "0.3.1-rc.1") == nil, "nor one that isn't newer")
        check(Updater.release(from: release("v0.3.1-rc.2", signed: true), newerThan: "0.3.1-rc.1")?.version == "0.3.1-rc.2",
              "the next test release is")
        check(Updater.release(from: Data("{}".utf8), newerThan: "0.3.1") == nil, "nor an answer that isn't a release")
        // 0.3.0 (no keys yet) takes the first asset ending in .zip: still the app, with the .sig in
        // the list, whichever order GitHub gives them in.
        func picked030(_ answer: Data) -> String? {
            let json = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any]
            return (json?["assets"] as? [[String: Any]])?.compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".zip") && $0.contains("Nightforge-") }
        }
        let signed = release("v0.3.1", signed: true)
        check(picked030(signed)?.hasSuffix("/Nightforge-0.3.1.zip") == true, "0.3.0's updater picks the zip of a signed release")
        let reversed = Data(String(decoding: signed, as: UTF8.self).replacingOccurrences(of: ".zip\"", with: ".zip.tmp\"")
            .replacingOccurrences(of: ".zip.sig\"", with: ".zip\"").replacingOccurrences(of: ".zip.tmp\"", with: ".zip.sig\"").utf8)
        check(picked030(reversed)?.hasSuffix(".zip") == true, "and never the .sig")

        check(Updater.releaseURL(testRelease: nil).absoluteString.hasSuffix("/releases/latest"), "normally the newest release")
        check(Updater.releaseURL(testRelease: "v0.3.1-rc.2").absoluteString.hasSuffix("/releases/tags/v0.3.1-rc.2"), "a test release when one is set")
        check(Updater.releaseURL(testRelease: "../../evil?x=1").absoluteString.hasSuffix("/releases/latest")
              && Updater.releaseURL(testRelease: "").absoluteString.hasSuffix("/releases/latest"), "an odd name: the newest release again")

        check(Updater.isNewer("0.3.1-rc.2", than: "0.3.1-rc.1") && Updater.isNewer("0.3.1-rc.10", than: "0.3.1-rc.9"),
              "a later test release is newer")
        check(Updater.isNewer("0.3.1", than: "0.3.1-rc.2") && !Updater.isNewer("0.3.1-rc.2", than: "0.3.1"), "the release comes after its tests")
        check(Updater.isNewer("0.3.1-rc.1", than: "0.3.0") && Updater.isNewer("0.3.1", than: "0.3.0") && !Updater.isNewer("0.3.0", than: "0.3.1"),
              "0.3.1 is newer than 0.3.0")
        check(!Updater.isNewer("0.3.1-rc.1", than: "0.3.1-rc.1") && !Updater.isNewer("0.3.1", than: "0.3.1") && !Updater.isNewer("", than: "0.3.0"),
              "the same version isn't newer, nor an empty one")

        let zip = work.appendingPathComponent("Nightforge-0.3.2.zip")
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        try? bytes.write(to: zip)
        check(Updater.isSigned(zip, signature: sign(bytes), keys: keys), "the downloaded zip with its signature")
        check(Updater.isSigned(zip, signature: sign(bytes, spareKey), keys: keys), "with the spare's")
        check(!Updater.isSigned(zip, signature: sign(bytes, strangerKey), keys: keys), "not with a stranger's")
        var changed = bytes
        changed[100] ^= 1
        try? changed.write(to: zip)
        check(!Updater.isSigned(zip, signature: sign(bytes), keys: keys), "not when one bit changed on the way")
        check(!Updater.isSigned(work.appendingPathComponent("missing.zip"), signature: sign(bytes), keys: keys), "not without a download")
        check(Updater.Failure.notNewer.errorDescription?.isEmpty == false, "an older release passed off as new has its message")
        // The app in the zip has to be exactly its release's version (review C).
        func outcome(_ found: String, named: String) -> String {
            do { try Updater.check(found, named: named, current: "0.3.1"); return "installs" }
            catch Updater.Failure.otherVersion { return "other version" }
            catch Updater.Failure.notNewer { return "not newer" }
            catch { return "\(error)" }
        }
        check(outcome("0.3.2", named: "0.3.2") == "installs", "the version its release names, newer: installs")
        check(outcome("0.3.1", named: "9.9.9") == "other version", "an old signed zip under a new tag doesn't")
        check(outcome("0.3.2", named: "9.9.9") == "other version", "nor a newer one under another tag")
        check(outcome("0.3.1", named: "0.3.1") == "not newer", "the same version again doesn't either")
        check(Updater.Failure.otherVersion(found: "0.3.1", named: "9.9.9").errorDescription?.contains("9.9.9") == true,
              "its message names both")
    }

    static func components() async {
        let online = work.appendingPathComponent("components-online", isDirectory: true)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Components", isDirectory: true)
        try? FileManager.default.createDirectory(at: online, withIntermediateDirectories: true)
        let bundled = URL(fileURLWithPath: "components/manifest.json")
        let remote = online.appendingPathComponent("manifest.json")
        func publish(_ generated: String, signedBy key: Curve25519.Signing.PrivateKey?) {
            var text = (try? String(contentsOf: bundled, encoding: .utf8)) ?? ""
            text = text.replacingOccurrences(of: #""generated": "[^"]*""#, with: #""generated": "\#(generated)""#, options: .regularExpression)
            try? Data(text.utf8).write(to: remote)
            try? FileManager.default.removeItem(at: Signature.file(for: remote))
            if let key { try? sign(Data(text.utf8), key).write(to: Signature.file(for: remote)) }
        }
        func store() -> ComponentStore { ComponentStore(root: root, remoteManifestURL: remote, bundledManifestURL: bundled, keys: keys) }

        publish("2026-11-02T04:17:00Z", signedBy: mainKey)
        let first = store()
        check((try? await first.manifest())?.generated == "2026-11-02T04:17:00Z", "a signed online list is taken")
        check(await first.manifestIsSigned, "a signed list: unused components may go")
        check(Signature.signedContents(of: root.appendingPathComponent("manifest.json"), keys: keys) != nil, "and kept with its signature")
        check(!SignedLists.refused.contains(SignedLists.components), "nothing to tell")
        check(ComponentStore.localManifest(keys: keys)?.generated == "2026-11-02T04:17:00Z", "Settings › About sees the kept one")

        publish("2026-11-03T04:17:00Z", signedBy: strangerKey)
        check((try? await store().manifest())?.generated == "2026-11-02T04:17:00Z", "a wrongly signed one: the last signed list still counts")
        check(SignedLists.refused.contains(SignedLists.components), "and Settings › About says so, calmly")
        publish("2026-11-03T04:17:00Z", signedBy: nil)
        let kept = store()
        check((try? await kept.manifest())?.generated == "2026-11-02T04:17:00Z", "an unsigned one too")
        check(await kept.manifestIsSigned, "the kept copy is signed as well")

        try? Data("x".utf8).write(to: Signature.file(for: root.appendingPathComponent("manifest.json")))
        let own = try? JSONDecoder().decode(ComponentManifest.self, from: Data(contentsOf: bundled))
        let fallback = store()
        check((try? await fallback.manifest())?.generated == own?.generated, "the kept list's signature broken: the app's own list")
        check(await !fallback.manifestIsSigned, "only the app's own list: nothing installed is taken away (review M9)")
        check(ComponentStore.localManifest(keys: keys)?.generated != "2026-11-02T04:17:00Z", "Settings › About passes it over too")

        publish("2026-11-04T04:17:00Z", signedBy: spareKey)
        check((try? await store().manifest())?.generated == "2026-11-04T04:17:00Z", "the spare key's signature counts")
        check(!SignedLists.refused.contains(SignedLists.components), "and the note goes away")

        // An earlier signed list put back (review M1): the kept, newer one counts.
        publish("2026-11-02T04:17:00Z", signedBy: mainKey)
        check((try? await store().manifest())?.generated == "2026-11-04T04:17:00Z", "an older signed list isn't taken")
        check(SignedLists.older.contains(SignedLists.components), "Settings › About says so")
        let keptStamp = Signature.signedContents(of: root.appendingPathComponent("manifest.json"), keys: keys)
            .flatMap { try? JSONDecoder().decode(ComponentManifest.self, from: $0) }?.generated
        check(keptStamp == "2026-11-04T04:17:00Z", "the kept copy stays the newer one")
        publish("2026-11-04T04:17:00Z", signedBy: mainKey)
        check((try? await store().manifest())?.generated == "2026-11-04T04:17:00Z" && !SignedLists.older.contains(SignedLists.components),
              "the same list signed again counts, and the note goes")
        // The app's own list newer than the kept one (an app update): its own counts (review N6).
        let ownData = try? Data(contentsOf: bundled)
        let behindText = (String(data: ownData ?? Data(), encoding: .utf8) ?? "")
            .replacingOccurrences(of: #""generated": "[^"]*""#, with: #""generated": "2026-01-01T00:00:00Z""#, options: .regularExpression)
        let keptURL = root.appendingPathComponent("manifest.json")
        try? Data(behindText.utf8).write(to: keptURL)
        try? sign(Data(behindText.utf8), mainKey).write(to: Signature.file(for: keptURL))
        let offline = ComponentStore(root: root, remoteManifestURL: nil, bundledManifestURL: bundled, keys: keys)
        check((try? await offline.manifest())?.generated == own?.generated, "a kept list older than the app's own: the app's own counts")
        check(await !offline.manifestIsSigned, "and with it nothing installed is taken away")
        check(ComponentStore.newerFirst(kept: Data(behindText.utf8), own: ownData).first?.1 == false
              && ComponentStore.newerFirst(kept: ownData, own: Data(behindText.utf8)).first?.1 == true,
              "Settings › About takes the newer of the two as well")
        publish("2026-02-01T00:00:00Z", signedBy: mainKey)
        let behindOnline = store()
        check((try? await behindOnline.manifest())?.generated == own?.generated && !SignedLists.older.contains(SignedLists.components),
              "an online list newer than the kept one but older than the app's own: the app's own, and nothing to tell")
        check(Signature.signedContents(of: keptURL, keys: keys).map { String(decoding: $0, as: UTF8.self).contains("2026-01-01") } == true,
              "the kept copy isn't overwritten with it")

        check(SignedLists.isOlder(Data(#"{"generated": "2026-11-04"}"#.utf8), than: Data(#"{"generated": "2026-11-04T04:17:00Z"}"#.utf8))
              && SignedLists.isOlder(Data("{}".utf8), than: Data(#"{"generated": "2026-11-04"}"#.utf8))
              && !SignedLists.isOlder(Data("{}".utf8), than: Data("{}".utf8)),
              "a date alone is older than a time that day; no stamp is older than one; without a kept stamp nothing is")

        // A kept stamp from the future (a wrong clock, a typo) mustn't lock the channel (review N5).
        let now = Date(), iso = ISO8601DateFormatter()
        func stamped(_ stamp: String) -> Data { Data(#"{"generated": "\#(stamp)"}"#.utf8) }
        let today = stamped(iso.string(from: now))
        check(!SignedLists.isOlder(today, than: stamped(iso.string(from: now.addingTimeInterval(10 * 86_400))), now: now),
              "a kept stamp ten days ahead counts as none")
        check(SignedLists.isOlder(today, than: stamped(iso.string(from: now.addingTimeInterval(86_400))), now: now),
              "one a day ahead still counts")
        check(!SignedLists.isOlder(stamped("2026-11-03"), than: stamped("2999-01-01"), now: now), "a date alone far ahead too")

        // Compared as dates, not as text (review F).
        let then = iso.date(from: "2026-11-04T12:00:00Z")!
        check(SignedLists.isOlder(stamped("2026-11-04T06:00:00+02:00"), than: stamped("2026-11-04T05:00:00Z"), now: then),
              "06:00 at +02:00 is 04:00 UTC: older than 05:00 UTC")
        check(!SignedLists.isOlder(stamped("2026-11-04T05:00:00.5Z"), than: stamped("2026-11-04T05:00:00Z"), now: then),
              "half a second later isn't older")
        check(!SignedLists.isOlder(stamped("2026-11-04"), than: stamped("2026-11-04T00:00:00Z"), now: then),
              "a day alone is its midnight in UTC")
        check(SignedLists.isOlder(stamped("2026-11-03T23:59:59Z"), than: stamped("2026-11-04"), now: then),
              "and a second before it is older")

        // sign-lists.sh asks these, through the signing tool, so it never signs what the app turns away.
        check(SignedLists.isNewer(stamped("2026-11-04T20:00:00-02:00"), than: stamped("2026-11-04T20:26:15Z"), now: then),
              "20:00 at -02:00 is 22:00 UTC: newer than 20:26 UTC, though its text sorts before")
        check(!SignedLists.isNewer(stamped("2026-11-05T00:30:00+05:00"), than: stamped("2026-11-04T20:26:15Z"), now: then),
              "00:30 on the 5th at +05:00 is 19:30 UTC on the 4th: not newer, though its text sorts after")
        check(!SignedLists.isNewer(stamped("2026-11-04T20:26:15Z"), than: stamped("2026-11-04T20:26:15Z"), now: then),
              "the same stamp isn't newer: a changed list needs a new one")
        check(SignedLists.isNewer(stamped("2026-11-04T05:00:00Z"), than: stamped("2999-01-01"), now: then)
              && SignedLists.isNewer(stamped("2026-11-04T05:00:00Z"), than: Data("{}".utf8), now: then),
              "over a stamp the app counts as none (far ahead, or none at all) any stamp is newer")
        check(SignedLists.isAhead(stamped("2026-11-05T13:00:00Z"), now: then) == true
              && SignedLists.isAhead(stamped("2026-11-05T11:00:00Z"), now: then) == false
              && SignedLists.isAhead(stamped("2026-11-05T01:00:00-12:00"), now: then) == true
              && SignedLists.isAhead(stamped("someday"), now: then) == nil,
              "more than a day ahead, as dates (01:00 at -12:00 is 13:00 UTC); a stamp that isn't a date")
    }

    static func profiles() async {
        let online = work.appendingPathComponent("profiles-online", isDirectory: true)
        try? FileManager.default.createDirectory(at: online, withIntermediateDirectories: true)
        let remote = online.appendingPathComponent("profiles.json")
        func publish(_ name: String, signedBy key: Curve25519.Signing.PrivateKey?, generated: String = "2026-11-02T04:37:00Z") {
            let data = Data(#"{"formatVersion": 1, "generated": "\#(generated)", "games": {"50130": {"name": "\#(name)"}}}"#.utf8)
            try? data.write(to: remote)
            try? FileManager.default.removeItem(at: Signature.file(for: remote))
            if let key { try? sign(data, key).write(to: Signature.file(for: remote)) }
        }
        func name() async -> String? { await ProfileStore(bundledURL: nil, remoteURL: remote, keys: keys).profile(for: 50130)?.name }

        publish("signed", signedBy: mainKey)
        check(await name() == "signed", "a signed online profile list is taken")
        let cached = Engine.supportDir.appendingPathComponent("profiles.json")
        check(Signature.signedContents(of: cached, keys: keys) != nil, "and kept with its signature")
        publish("forged", signedBy: strangerKey)
        check(await name() == "signed", "a wrongly signed one: the kept list still counts")
        check(SignedLists.refused.contains(SignedLists.profiles), "noted for Settings › About")
        publish("unsigned", signedBy: nil)
        check(await name() == "signed", "an unsigned one too")
        check(Signature.signedContents(of: cached, keys: keys).map { String(decoding: $0, as: UTF8.self).contains("signed") } == true,
              "the kept copy wasn't overwritten")
        publish("spare", signedBy: spareKey)
        check(await name() == "spare" && !SignedLists.refused.contains(SignedLists.profiles), "the spare key's counts, and the note goes")
        publish("old", signedBy: mainKey, generated: "2026-11-01T04:37:00Z")
        check(await name() == "spare", "an earlier signed list put back isn't taken (review M1)")
        check(SignedLists.older.contains(SignedLists.profiles), "noted for Settings › About")
        publish("newer", signedBy: mainKey, generated: "2026-11-03T04:37:00Z")
        check(await name() == "newer" && !SignedLists.older.contains(SignedLists.profiles), "a newer one is taken, and the note goes")
        publish("ahead", signedBy: mainKey, generated: "2999-01-01T00:00:00Z")
        check(await name() == "ahead", "a list from the future is taken once")
        publish("right", signedBy: mainKey, generated: "2026-11-04T04:37:00Z")
        check(await name() == "right" && !SignedLists.older.contains(SignedLists.profiles),
              "but doesn't lock the channel: the next right list counts again (review N5)")

        // The app's own list from the future mustn't turn away every right online list either (review B).
        let ownAhead = online.appendingPathComponent("own-ahead.json")
        try? Data(#"{"formatVersion": 1, "generated": "2999-01-01T00:00:00Z", "games": {"50130": {"name": "own"}}}"#.utf8).write(to: ownAhead)
        publish("online", signedBy: mainKey, generated: "2026-11-05T04:37:00Z")
        check(await ProfileStore(bundledURL: ownAhead, remoteURL: remote, keys: keys).profile(for: 50130)?.name == "online",
              "an own list from the future doesn't win over a right online one")
    }
}
