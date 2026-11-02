// Checks what Nightforge reads from profiles/agw.json (AppleGamingWiki), the links on a game's page,
// the shared report and the "How did it run?" answers: tests/MacSourcesTest/run.sh
import AppKit
import CryptoKit
import Foundation

@main
struct MacSourcesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A made-up file in agw.json's shape: an entry with every field, a GOG-only one, odd ones.
    static let sample = #"""
    {
     "formatVersion": 1,
     "license": "CC BY-NC-SA 3.0",
     "aliases": {"steam": {"871": "870"}, "gog": {"555": "870"}},
     "games": {
      "870": {"page": "Some Game: Deluxe", "codeweavers": "Some Game", "paths": {
        "native": {"rating": "perfect"},
        "crossover": {"rating": "perfect", "note": "Fine.", "versions": ["CrossOver 23.5"], "graphics": ["d3dmetal", "glide"],
                      "directX": ["12"], "chips": ["M1 Pro"], "date": "2023-10-13"},
        "wine": {"rating": "menu"},
        "parallels": {"rating": "perfect"},
        "rosetta": {"rating": "excellent"}},
       "hint": {"graphics": "d3dmetal", "directX": "12", "from": ["crossover"], "source": "agw"}},
      "gog.777": {"page": "Only on GOG", "ids": "name", "paths": {"crossover": {"rating": "unplayable"}}},
      "900": {"page": "Future", "paths": {"crossover": {"rating": "playable"}}, "hint": {"graphics": "metal4"}},
      "901": {"paths": {"crossover": {"rating": "perfect"}}},
      "902": "nonsense"
     }
    }
    """#

    static func main() async throws {
        // MARK: Reading the file
        guard let index = AGWIndex.decode(Data(sample.utf8)) else {
            print("✗ the sample didn't decode")
            exit(1)
        }
        check(Set(index.games.keys) == ["870", "gog.777", "900"], "odd entries cost only themselves: \(index.games.keys.sorted())")
        let entry = index.games["870"]
        check(entry?.reports.count == 3, "native, CrossOver, Wine; Parallels and an unknown rating are left out")
        check(entry?.reports[.crossover]?.graphics == [.d3dmetal], "a layer this Nightforge doesn't know is skipped")
        check(entry?.hint == SourceHint(graphics: .d3dmetal, directX: "12", source: "agw"), "the hint, with its source")
        check(index.games["900"]?.hint == nil, "a hint with an unknown layer is none")
        check(entry?.reports[.crossover]?.basis == "CrossOver 23.5 · D3DMetal · DirectX 12 · M1 Pro · 2023",
              "what the reports name, in one line: \(entry?.reports[.crossover]?.basis ?? "-")")
        check(entry?.ways.map(\.way) == [.native, .crossover, .wine], "the ways in the table's order")
        check(entry?.wineSummary == "CrossOver: \(AGWEntry.Rating.perfect.label), \(AGWEntry.Way.wine.label): \(AGWEntry.Rating.menu.label)",
              "the Windows ways for the badge: \(entry?.wineSummary ?? "-")")
        check(AGWIndex.decode(Data(#"{"formatVersion": 2, "games": {}}"#.utf8)) == nil, "a newer format isn't read")
        check(AGWIndex.decode(Data("not json".utf8)) == nil, "nor something else")

        // MARK: Finding a game
        check(index.entry(steamAppID: 870, gogID: nil)?.page == "Some Game: Deluxe", "by Steam app ID")
        check(index.entry(steamAppID: 871, gogID: nil)?.page == "Some Game: Deluxe", "by another Steam app ID of the page")
        check(index.entry(steamAppID: nil, gogID: "555")?.page == "Some Game: Deluxe", "by a GOG product ID the page names")
        check(index.entry(steamAppID: nil, gogID: "777")?.page == "Only on GOG", "a game only on GOG")
        check(index.entry(steamAppID: 1, gogID: "777")?.page == "Only on GOG", "an unknown Steam app ID falls back to GOG")
        check(index.entry(steamAppID: 1, gogID: nil) == nil, "an unknown game")
        let bottle = Engine.bottle
        var gogGame = Game(gameID: GameID(provider: .gog, id: "555"), name: "Some Game", bottle: bottle, steamRoot: bottle.url,
                           steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
        check(index.entry(for: gogGame)?.page == "Some Game: Deluxe", "a GOG game in the library")
        var epicGame = Game(gameID: GameID(provider: .epic, id: "Calluna"), name: "Some Game", bottle: bottle, steamRoot: bottle.url,
                            steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
        check(index.entry(for: epicGame) == nil, "an Epic game without a Steam twin")
        epicGame.steamTwin = 870
        check(index.entry(for: epicGame)?.page == "Some Game: Deluxe", "…found by the same game on Steam")
        gogGame.steamTwin = 1

        // MARK: The copy at hand
        let folder = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("agw-store", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cached = folder.appendingPathComponent("agw.json")
        // Like the other online lists it counts only with the maintainer's signature beside it; here a
        // key of the test's own signs (SignatureTest has the signatures themselves).
        let signer = Curve25519.Signing.PrivateKey()
        let keys = [signer.publicKey.rawRepresentation.base64EncodedString()]
        func signature(of data: Data, by key: Curve25519.Signing.PrivateKey) throws -> Data {
            Data(try key.signature(for: data).base64EncodedString().utf8)
        }
        let answer = Data(sample.utf8)
        let signed = try signature(of: answer, by: signer)
        check(await AGWStore(remoteURL: nil, cachedURL: cached, keys: keys).current().isEmpty, "nothing before the first download – no copy in the app")
        try answer.write(to: cached)
        check(await AGWStore(remoteURL: nil, cachedURL: cached, keys: keys).current().isEmpty, "a copy without its signature doesn't count")
        try signature(of: answer, by: Curve25519.Signing.PrivateKey()).write(to: Signature.file(for: cached))
        check(await AGWStore(remoteURL: nil, cachedURL: cached, keys: keys).current().isEmpty, "nor one a stranger signed")
        try signed.write(to: Signature.file(for: cached))
        let store = AGWStore(remoteURL: nil, cachedURL: cached, keys: keys)
        await store.refresh()
        check(await store.current().games.count == 3, "the last copy fetched, with its signature")

        /// The online copy: the list, and its signature beside it (nil: there's none, 404).
        func online(_ data: Data, signature: Data?, after delay: Duration = .zero) -> Signature.Load {
            { request in
                if delay > .zero { try await Task.sleep(for: delay) }
                let url = request.url!
                let body = url.pathExtension == "sig" ? signature : data
                return (body ?? Data(), HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!)
            }
        }

        // The first run: a start waits for the download once, briefly – never for a slow network each time.
        let remote = URL(string: "https://example.invalid/agw.json")!
        let slow = AGWStore(remoteURL: remote, cachedURL: folder.appendingPathComponent("slow.json"), keys: keys,
                            load: online(answer, signature: signed, after: .seconds(1.5)))
        var began = Date()
        await slow.beforeFirstStart(waitingAtMost: 0.3)
        let firstWait = Date().timeIntervalSince(began)
        let notYet = await slow.current().isEmpty
        check(firstWait < 1 && notYet, "a slow download holds the first start up only briefly (\(firstWait) s), it starts without")
        began = Date()
        await slow.beforeFirstStart(waitingAtMost: 0.3)
        check(Date().timeIntervalSince(began) < 0.1, "only once per run: the next start doesn't wait at all")
        await slow.refresh()
        let arrived = await slow.current().games.count
        check(arrived == 3, "the list arrives in the background for the next start")
        let offline = AGWStore(remoteURL: remote, cachedURL: folder.appendingPathComponent("offline.json"), keys: keys) { _ in
            throw URLError(.notConnectedToInternet)
        }
        began = Date()
        await offline.beforeFirstStart(waitingAtMost: 4)
        check(Date().timeIntervalSince(began) < 1, "offline: no wait beyond the failed request")
        let quickCopy = folder.appendingPathComponent("quick.json")
        let quick = AGWStore(remoteURL: remote, cachedURL: quickCopy, keys: keys, load: online(answer, signature: signed))
        await quick.beforeFirstStart(waitingAtMost: 4)
        let quickCount = await quick.current().games.count
        check(quickCount == 3, "a quick download is there for the first start already")
        check(!SignedLists.refused.contains(SignedLists.agw), "a signed list isn't noted as turned away")
        check(await AGWStore(remoteURL: nil, cachedURL: quickCopy, keys: keys).current().games.count == 3,
              "kept with its signature: the next run has it at hand")

        // Online without a signature that holds: turned away, and the copy at hand stays.
        for (name, signature) in [("unsigned", nil), ("stranger", try signature(of: answer, by: Curve25519.Signing.PrivateKey())),
                                  ("changed", try signature(of: Data(sample.replacingOccurrences(of: "Deluxe", with: "Gold").utf8), by: signer))] {
            let copy = folder.appendingPathComponent(name + ".json")
            let turnedAway = AGWStore(remoteURL: remote, cachedURL: copy, keys: keys, load: online(answer, signature: signature))
            await turnedAway.refresh()
            let count = await turnedAway.current().games.count
            check(count == 0 && !FileManager.default.fileExists(atPath: copy.path), "\(name) online: not taken, not kept")
            check(SignedLists.refused.contains(SignedLists.agw), "\(name) online: noted for Settings › About")
        }
        let kept = AGWStore(remoteURL: remote, cachedURL: quickCopy, keys: keys, load: online(answer, signature: nil))
        await kept.refresh()
        check(await kept.current().games.count == 3, "a list turned away online leaves the last signed copy")
        await AGWStore(remoteURL: remote, cachedURL: quickCopy, keys: keys, load: online(answer, signature: signed)).refresh()
        check(!SignedLists.refused.contains(SignedLists.agw), "a signed one later takes the note back")

        // MARK: Links
        check(MacSources.wikiPage("Some Game: Deluxe")?.absoluteString == "https://www.applegamingwiki.com/wiki/Some_Game:_Deluxe",
              "the wiki page by its title: \(MacSources.wikiPage("Some Game: Deluxe")?.absoluteString ?? "-")")
        check(MacSources.wikiPage("100% Orange Juice?")?.absoluteString == "https://www.applegamingwiki.com/wiki/100%25_Orange_Juice%3F",
              "a title with % and ? stays one page")
        check(MacSources.codeWeavers(name: "Some Game", entry: entry)?.absoluteString == "https://www.codeweavers.com/compatibility/crossover/Some%20Game",
              "CodeWeavers' page the wiki names")
        check(MacSources.codeWeavers(name: "A & B", entry: nil)?.absoluteString.hasPrefix("https://www.codeweavers.com/compatibility?name=A%20%26%20B") == true,
              "else CodeWeavers' search")
        check(MacSources.macGamingDB(steamAppID: 870)?.absoluteString == "https://macgamingdb.app/games/870", "MacGamingDB by Steam app ID")
        check(MacSources.macGamingDB(steamAppID: nil)?.absoluteString == "https://macgamingdb.app/", "…else its front page")
        check(MacSources.wikiSearch("Some Game")?.absoluteString == "https://www.applegamingwiki.com/w/index.php?search=Some%20Game", "the wiki's search")

        // MARK: "How did it run?"
        let well = GameRating.choice(good: true, issues: [.sound], way: "dxmt -dx11")
        check(well.good && well.issues.isEmpty && well.didntStart == nil && well.way == "dxmt -dx11", "Ran well: no chips, the way kept")
        let problems = GameRating.choice(good: false, issues: [.sound, .crashed], way: "d3dmetal")
        check(!problems.good && problems.issues == [.crashed, .sound] && problems.didntStart == nil, "With problems: the chips in their order")
        let noStart = GameRating.choice(good: true, issues: [.sound], didntStart: true, way: "dxvk")
        check(!noStart.good && noStart.issues.isEmpty && noStart.didntStart == true && noStart.way == "dxvk", "Didn't start: not good, no chips")
        let old = try JSONDecoder().decode(GameRating.self, from: Data(#"{"good": false, "issues": ["stutters"], "date": 0}"#.utf8))
        check(old.didntStart == nil && old.way == nil && old.issues == [.stutters], "an answer saved by 0.3.0 still reads")
        check(Compatibility.rate(Compatibility.Facts(ownRating: noStart)).level == .no, "Didn't start: the player's own word")
        check(Compatibility.rate(Compatibility.Facts(antiCheatBlock: AntiCheatBlock(antiCheat: [], geforceNow: nil, notYet: "x"), ownRating: well)).level == .notYet,
              "a reason Nightforge knows still beats it")

        // MARK: Others' word in the rating
        var reported = Compatibility.Facts()
        reported.reported = entry
        let said = Compatibility.rate(reported)
        check(said.level == .untested && said.note == L10n.t("According to AppleGamingWiki: %@.", entry?.wineSummary ?? ""),
              "still not tested, but what the wiki says is said")
        var badly = Compatibility.Facts()
        badly.reported = index.games["gog.777"]
        let warned = Compatibility.rate(badly)
        check(warned.level == .untested && warned.note == L10n.t("According to AppleGamingWiki it runs badly through CrossOver and Wine (%@) – it may not run here either.",
                                                                 "CrossOver: " + AGWEntry.Rating.unplayable.label),
              "a bad word is said as a warning before the download, never a block: \(warned.note ?? "-")")
        reported.ownRating = well
        check(Compatibility.rate(reported).level == .great, "the player's own word beats the wiki's")
        reported.ownRating = nil
        reported.platform = .mac
        check(Compatibility.rate(reported).note == nil, "a Mac version needs no word on Wine")

        // MARK: The shared report
        var game = Game(appID: 870, name: "Some Game", bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "",
                        installDir: bottle.url, sizeOnDisk: 0)
        game.platform = .windows
        let winecx = Component(id: "winecx", kind: .engine, version: "4.7.3", url: URL(string: "https://example.invalid/w.tar.xz")!,
                               sha256: "", size: 0, license: "LGPL-2.1-or-later", source: URL(string: "https://example.invalid")!)
        let build = EngineBuild(engine: winecx, graphics: [], d3dMetal: "4.0b3", stamp: "x")
        let fields = Dictionary(uniqueKeysWithValues: CompatReport.fields(game: game, rating: problems, preset: .automatic, engine: build,
                                                                           chip: "Apple M5", macOS: "27.0", nightforge: "0.3.1",
                                                                           home: "/Users/jane", user: "jane").map { ($0.id, $0.value) })
        check(fields["game"] == "Some Game" && fields["store"] == "steam" && fields["store-id"] == "870", "which game")
        check(fields["result"] == "problems" && fields["way"] == "d3dmetal" && fields["issues"] == "crashed, sound", "how it ran, and how")
        check(fields["setup"] == "Nightforge 0.3.1 · preset automatic · winecx@4.7.3, d3dmetal@4.0b3", "what ran it: \(fields["setup"] ?? "-")")
        check(fields["mac"] == "Apple M5 · macOS 27.0", "the Mac")
        check(CompatReport.result(noStart) == "no-start" && CompatReport.result(well) == "good", "the form's fixed words")
        let named = Game(appID: 870, name: "Mod in /Users/jane/Games for jane@example.com", bottle: bottle, steamRoot: bottle.url,
                         steamExeWindowsPath: "", installDir: bottle.url, sizeOnDisk: 0)
        let scrubbed = CompatReport.url(game: named, rating: well, preset: nil, engine: nil, chip: "Apple M5", macOS: "27.0",
                                        nightforge: "0.3.1", home: "/Users/jane", user: "jane")?.absoluteString ?? ""
        check(!scrubbed.contains("jane") && scrubbed.contains("template=compat-report.yml"), "no home folder or e-mail in the link: \(scrubbed)")
        var mac = game
        mac.platform = .mac
        check(CompatReport.fields(game: mac, rating: GameRating(good: true), preset: nil, engine: nil, chip: "M", macOS: "27",
                                  nightforge: "1").first { $0.id == "way" }?.value == "mac", "a Mac version's way")
        let form = try String(contentsOf: URL(fileURLWithPath: ".github/ISSUE_TEMPLATE/compat-report.yml"), encoding: .utf8)
        for (id, _) in fields { check(form.contains("id: \(id)\n"), "the form has the field \(id)") }

        // MARK: The file in the repository
        if let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), let real = AGWIndex.decode(data) {
            check(real.games.count > 1000, "profiles/agw.json has \(real.games.count) games")
            let control = real.entry(steamAppID: 870780, gogID: nil)
            check(control?.reports[.crossover]?.graphics == [.d3dmetal] && control?.reports[.crossover]?.directX == ["12"],
                  "Control: the wiki's CrossOver report runs it as DirectX 12 on D3DMetal")
            check(control?.hint == nil, "…and no hint, since profiles/mac.json has Control's own layer (mac.json wins)")
            check(real.games.values.allSatisfy { !$0.reports.isEmpty }, "every entry says something")
        } else {
            check(false, "profiles/agw.json reads")
        }

        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("✓ Mac sources")
    }
}
