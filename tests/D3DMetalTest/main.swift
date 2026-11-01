// Checks where Apple's D3DMetal comes from: the answer on file, a copy from before the question, the
// import from Apple's toolkit, the wait for the download: tests/D3DMetalTest/run.sh
import Foundation

@main
struct D3DMetalTest {
    static var failures = 0
    static let fm = FileManager.default

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Supply = D3DMetalSupply

    static func main() async {
        guard fm.homeDirectoryForCurrentUser.path.contains("/home") else {
            print("✗ runs only in its own home (tests/D3DMetalTest/run.sh)")
            exit(1)
        }
        let work = fm.temporaryDirectory.appendingPathComponent("d3dmetal-test-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        answer(work)
        current(work)
        folders(work)
        imports(work)
        diskImages(work)
        await downloads(work)
        games()
        build()
        versions(work)
        licence(work)
        engineFiles(work)
        unrealWarning(work)

        print(failures == 0 ? "✓ D3DMetal" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Fixtures

    static func write(_ text: String, to url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    /// Apple's toolkit as it lies on its disk image: redist/lib with the framework, libd3dshared.dylib and the
    /// Windows front ends, the notices beside redist/. Not signed by anyone – the checks take a stand-in.
    @discardableResult
    static func toolkit(at root: URL, version: String = "3.0", notices: Bool = true, marker: String = "a") -> URL {
        let lib = root.appendingPathComponent("redist/lib", isDirectory: true)
        write("dylib \(marker)", to: lib.appendingPathComponent("external/libd3dshared.dylib"))
        let info: NSDictionary = ["CFBundleShortVersionString": version]
        let plist = lib.appendingPathComponent("external/D3DMetal.framework/Versions/A/Resources/Info.plist")
        try? fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        info.write(to: plist, atomically: true)
        write("framework \(marker)", to: lib.appendingPathComponent("external/D3DMetal.framework/Versions/A/D3DMetal"))
        for dll in ["d3d12.dll", "d3d11.dll", "dxgi.dll"] {
            write("front end \(dll) \(marker)", to: lib.appendingPathComponent("wine/x86_64-windows/\(dll)"))
        }
        let unix = lib.appendingPathComponent("wine/x86_64-unix", isDirectory: true)
        try? fm.createDirectory(at: unix, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: unix.appendingPathComponent("d3d12.so").path,
                                   withDestinationPath: "../../external/libd3dshared.dylib")
        if notices {
            write("licence", to: root.appendingPathComponent("License.rtf"))
            write("thanks", to: root.appendingPathComponent("Acknowledgements.rtf"))
        }
        return lib
    }

    static func manifest(d3dmetal version: String?) -> ComponentManifest? {
        let entry = version.map { """
            {"id": "d3dmetal", "kind": "graphics", "version": "\($0)", "url": "https://example.test/d3dmetal/nightforge-d3dmetal-\($0).tar.gz",
             "sha256": "\(String(repeating: "ab", count: 32))", "size": 1000, "license": "Apple", "source": "https://example.test"}
            """ } ?? ""
        let engine = """
            {"id": "winecx", "kind": "engine", "version": "4.7.3", "url": "https://example.test/winecx/Libraries.tar.gz",
             "sha256": "\(String(repeating: "cd", count: 32))", "size": 1000, "license": "LGPL", "source": "https://example.test"}
            """
        let json = #"{"schemaVersion": 1, "generated": "2026-11-01", "components": [\#(engine)\#(entry.isEmpty ? "" : ", " + entry)]}"#
        return try? JSONDecoder().decode(ComponentManifest.self, from: Data(json.utf8))
    }

    static func fresh(_ work: URL, _ name: String) -> URL {
        let dir = work.appendingPathComponent(name, isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: The answer

    static func answer(_ work: URL) {
        let folder = fresh(work, "answer")
        check(Supply.choice(in: folder) == nil, "nothing on file, no answer")
        let choice = Supply.Choice(source: .apple, version: "3.0", accepted: Date(timeIntervalSince1970: 1_800_000_000))
        Supply.save(choice, in: folder)
        check(Supply.choice(in: folder) == choice, "the answer comes back as it was saved")
        Supply.forget(in: folder)
        check(Supply.choice(in: folder) == nil, "taken back")
        write("not json", to: folder.appendingPathComponent("choice.json"))
        check(Supply.choice(in: folder) == nil, "a damaged file is no answer")
    }

    // MARK: What the engine gets

    static func current(_ work: URL) {
        let components = fresh(work, "components")
        let folder = fresh(work, "current")
        let list = manifest(d3dmetal: "3.0")
        check(list?.component("d3dmetal")?.version == "3.0", "the test list holds D3DMetal 3.0")

        check(Supply.current(manifest: list, componentsRoot: components, folder: folder) == nil
              && Supply.choice(in: folder) == nil, "never asked, nothing from before: no D3DMetal, and nothing recorded")

        // A copy an earlier Nightforge downloaded (no question was asked): it stays in use, and counts as answered.
        let old = components.appendingPathComponent("d3dmetal/4.0b3", isDirectory: true)
        // The package keeps lib/ directly under its folder (scripts/package-d3dmetal.sh): external/ and wine/ in it.
        let packed = old.appendingPathComponent("nightforge-d3dmetal-4.0b3/lib", isDirectory: true)
        try? fm.createDirectory(at: packed.deletingLastPathComponent(), withIntermediateDirectories: true)
        let laidOut = fresh(work, "laid-out")
        toolkit(at: laidOut, version: "4.0b3")
        try? fm.moveItem(at: laidOut.appendingPathComponent("redist/lib"), to: packed)
        check(Supply.earlierInstall(in: components) == nil, "a download without its marker isn't one")
        write("hash", to: old.appendingPathComponent(".sha256"))
        check(Supply.earlierInstall(in: components) == "4.0b3", "a finished download from before is found")
        let kept = Supply.current(manifest: list, componentsRoot: components, folder: folder)
        check(kept?.version == "4.0b3" && kept?.origin == .kept(old), "it stays in use, not the list's newer one: \(String(describing: kept))")
        check(Supply.choice(in: folder)?.source == .nightforge && Supply.choice(in: folder)?.version == "4.0b3",
              "and it is on file as answered, at that version")
        check(Supply.current(manifest: nil, componentsRoot: components, folder: folder)?.origin == .kept(old), "without the list, too")

        // The copy is gone: the download the player agreed to is the list's.
        try? fm.removeItem(at: old)
        let again = Supply.current(manifest: list, componentsRoot: components, folder: folder)
        check(again?.version == "3.0" && again?.origin == .download(list!.component("d3dmetal")!), "a vanished copy: the list's D3DMetal")
        check(Supply.current(manifest: manifest(d3dmetal: nil), componentsRoot: components, folder: folder) == nil
              && Supply.current(manifest: nil, componentsRoot: components, folder: folder) == nil, "nothing on offer, nothing to give")
        check(Supply.canDownload(list) && !Supply.canDownload(manifest(d3dmetal: nil)) && !Supply.canDownload(nil),
              "Nightforge's download is on offer only while the list has one")

        // Nightforge's download, chosen.
        let chosen = fresh(work, "chosen")
        Supply.save(.init(source: .nightforge, version: nil, accepted: Date()), in: chosen)
        check(Supply.current(manifest: list, componentsRoot: fresh(work, "empty-components"), folder: chosen)?.version == "3.0",
              "chosen: the list's version")

        // Apple's, imported.
        let apple = fresh(work, "apple")
        Supply.save(.init(source: .apple, version: "3.0", accepted: Date()), in: apple)
        check(Supply.current(manifest: list, componentsRoot: components, folder: apple) == nil, "an import that isn't there gives nothing (the list's isn't taken instead)")
        toolkit(at: fresh(work, "apple-source"))
        _ = try? Supply.importToolkit(from: work.appendingPathComponent("apple-source"), into: apple, verify: { _ in true })
        let imported = Supply.current(manifest: list, componentsRoot: components, folder: apple)
        check(imported?.version == "apple-3.0", "imported: apple-3.0: \(String(describing: imported?.version))")
        if case .imported(let dir)? = imported?.origin {
            check(dir == Supply.importedFolder(in: apple).appendingPathComponent("3.0"), "from the import folder")
        } else {
            check(false, "origin is the import")
        }
        // The import wins over a later change of the list; the choice, not the list, says where from.
        check(Supply.current(manifest: manifest(d3dmetal: "9.9"), componentsRoot: components, folder: apple)?.version == "apple-3.0",
              "a new list doesn't move an import")
    }

    // MARK: Finding and copying

    static func folders(_ work: URL) {
        let root = fresh(work, "disk")
        let nested = root.appendingPathComponent("Evaluation environment for Windows games/inner", isDirectory: true)
        let lib = toolkit(at: nested)
        let found = Supply.findToolkit(in: root)
        check(found?.lib.resolvingSymlinksInPath() == lib.resolvingSymlinksInPath(), "the toolkit is found a few folders down")
        check(found?.notices.map(\.lastPathComponent).sorted() == ["Acknowledgements.rtf", "License.rtf"], "with the notices beside redist/")
        check(Supply.findToolkit(in: root, maxDepth: 1) == nil, "not past the depth it looks")
        try? fm.removeItem(at: lib.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))
        check(Supply.findToolkit(in: root) == nil, "without the Direct3D 12 front end it isn't the toolkit")
        check(Supply.findToolkit(in: fresh(work, "empty-disk")) == nil, "an empty folder isn't one")

        check(Supply.isPlainVersion("3.0") && Supply.isPlainVersion("4.0b3") && Supply.isPlainVersion("4.0-beta+3"), "versions as Apple writes them")
        check(!Supply.isPlainVersion("") && !Supply.isPlainVersion("../x") && !Supply.isPlainVersion("a/b") && !Supply.isPlainVersion(".hidden")
              && !Supply.isPlainVersion(String(repeating: "1", count: 40)), "nothing that could leave the folder it becomes")
    }

    static func imports(_ work: URL) {
        let source = fresh(work, "toolkit-source")
        toolkit(at: source)
        let home = fresh(work, "import-home")
        var checked: [String] = []
        let version = try? Supply.importToolkit(from: source, into: home, verify: { checked.append($0.path); return true })
        check(version == "3.0", "imported at the framework's version: \(String(describing: version))")
        let target = Supply.importedFolder(in: home).appendingPathComponent("3.0")
        let lib = target.appendingPathComponent("lib")
        func same(_ path: String) -> Bool {
            fm.contentsEqual(atPath: source.appendingPathComponent("redist/lib/\(path)").path, andPath: lib.appendingPathComponent(path).path)
        }
        check(same("external/libd3dshared.dylib") && same("external/D3DMetal.framework/Versions/A/D3DMetal")
              && same("wine/x86_64-windows/d3d12.dll"), "byte for byte what Apple's toolkit holds")
        check((try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("wine/x86_64-unix/d3d12.so").path))
              == "../../external/libd3dshared.dylib", "the unix half stays a link")
        check(fm.fileExists(atPath: target.appendingPathComponent("License.rtf").path)
              && fm.fileExists(atPath: target.appendingPathComponent("Acknowledgements.rtf").path), "Apple's notices go along")
        check(Engine.d3dMetalPayloadRoot(in: target) != nil, "the engine finds its payload in the copy")
        check(checked.count == 4 && checked.filter { $0.contains("toolkit-source") }.count == 2
              && checked.filter { $0.contains("/.staging-") && $0.contains("/lib/external/") }.count == 2,
              "the signature is checked at the source and again on the copy: \(checked)")
        check(((try? fm.contentsOfDirectory(atPath: Supply.importedFolder(in: home).path)) ?? []) == ["3.0"], "no staging left behind")

        // A newer copy of the same version replaces it.
        toolkit(at: source, marker: "b")
        _ = try? Supply.importToolkit(from: source, into: home, verify: { _ in true })
        check((try? String(contentsOf: lib.appendingPathComponent("external/libd3dshared.dylib"), encoding: .utf8)) == "dylib b",
              "importing again replaces it")

        // What isn't Apple's, or isn't a toolkit, leaves nothing behind.
        let strange = fresh(work, "strange-home")
        func refused(_ root: URL, _ verify: @escaping (URL) -> Bool, _ expected: Supply.Failure, _ message: String) {
            do {
                _ = try Supply.importToolkit(from: root, into: strange, verify: verify)
                check(false, message + " (imported)")
            } catch {
                check(error as? Supply.Failure == expected, message + ": \(error)")
            }
        }
        refused(source, { _ in false }, .notSignedByApple, "unsigned is refused")
        var calls = 0
        refused(source, { _ in calls += 1; return calls <= 2 }, .notSignedByApple, "a copy that fails the check is refused")
        refused(fresh(work, "nothing"), { _ in true }, .notAToolkit, "no toolkit in it")
        let noVersion = fresh(work, "no-version")
        toolkit(at: noVersion, version: "../x")
        refused(noVersion, { _ in true }, .notAToolkit, "a version that isn't a plain name")
        let unreadable = fresh(work, "unreadable-version")
        toolkit(at: unreadable)
        try? fm.removeItem(at: unreadable.appendingPathComponent("redist/lib/external/D3DMetal.framework/Versions/A/Resources/Info.plist"))
        refused(unreadable, { _ in true }, .notAToolkit, "a framework that doesn't say its version")
        check(((try? fm.contentsOfDirectory(atPath: Supply.importedFolder(in: strange).path)) ?? []).isEmpty,
              "nothing left from the refused ones")
        // The real check: these files carry no signature of Apple's.
        do {
            _ = try Supply.importToolkit(from: source, into: strange)
            check(false, "files nobody signed were imported")
        } catch {
            check(error as? Supply.Failure == .notSignedByApple, "the real signature check refuses unsigned files: \(error)")
        }
    }

    static func diskImages(_ work: URL) {
        func image(from folder: URL, _ name: String) -> URL? {
            let dmg = work.appendingPathComponent("\(name).dmg")
            try? fm.removeItem(at: dmg)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["create", "-quiet", "-srcfolder", folder.path, "-volname", name, "-format", "UDZO", "-ov", dmg.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            return process.terminationStatus == 0 ? dmg : nil
        }
        func mounted() -> Bool {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/sbin/mount")
            process.standardOutput = pipe
            try? process.run()
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return text.contains("nightforge-d3dmetal-")
        }

        // The toolkit on a disk image of its own (3.0's evaluation environment).
        let plain = fresh(work, "plain-image")
        toolkit(at: plain.appendingPathComponent("Evaluation environment for Windows games 3.0"), version: "3.0")
        guard let direct = image(from: plain, "plain") else {
            check(false, "hdiutil made no disk image to test with")
            return
        }
        let home = fresh(work, "image-home")
        var version: String?
        do { version = try Supply.importDiskImage(direct, into: home, verify: { _ in true }) } catch { check(false, "importing a disk image: \(error)") }
        check(version == "3.0" && Engine.d3dMetalPayloadRoot(in: Supply.importedFolder(in: home).appendingPathComponent("3.0")) != nil,
              "imported from a disk image: \(String(describing: version))")
        check(!mounted(), "and the image is closed again")

        // The toolkit's own image, with the evaluation environment's image inside (3.0, the 4.0 betas).
        let inner = fresh(work, "inner-image")
        toolkit(at: inner.appendingPathComponent("Game Porting Toolkit"), version: "4.0b3")
        guard let innerImage = image(from: inner, "Evaluation_environment_for_Windows_games_4.0b3") else {
            check(false, "no inner disk image")
            return
        }
        let outer = fresh(work, "outer-image")
        write("Read me", to: outer.appendingPathComponent("Read Me.txt"))
        try? fm.copyItem(at: innerImage, to: outer.appendingPathComponent("Evaluation_environment_for_Windows_games_4.0b3.dmg"))
        guard let nested = image(from: outer, "Game_Porting_Toolkit_4.0_beta_3") else {
            check(false, "no outer disk image")
            return
        }
        let nestedHome = fresh(work, "nested-home")
        var nestedVersion: String?
        do { nestedVersion = try Supply.importDiskImage(nested, into: nestedHome, verify: { _ in true }) } catch { check(false, "importing a nested image: \(error)") }
        check(nestedVersion == "4.0b3", "imported from the image inside the image: \(String(describing: nestedVersion))")
        check(!mounted(), "both are closed again")

        // Not the toolkit, and not an image at all.
        let other = fresh(work, "other-image")
        write("holiday photos", to: other.appendingPathComponent("photo.txt"))
        if let otherImage = image(from: other, "other") {
            do {
                _ = try Supply.importDiskImage(otherImage, into: fresh(work, "other-home"), verify: { _ in true })
                check(false, "another image was imported")
            } catch {
                check(error as? Supply.Failure == .notAToolkit, "an image without the toolkit: \(error)")
            }
        }
        let broken = work.appendingPathComponent("broken.dmg")
        write("this is not a disk image", to: broken)
        do {
            _ = try Supply.importDiskImage(broken, into: fresh(work, "broken-home"), verify: { _ in true })
            check(false, "a broken image was imported")
        } catch {
            check(error as? Supply.Failure == .cannotOpen, "a file that isn't an image: \(error)")
        }
        check(!mounted(), "nothing stays mounted")
    }

    // MARK: Waiting for the download

    static func downloads(_ work: URL) async {
        let folder = fresh(work, "downloads")
        let since = Date()
        let old = since.addingTimeInterval(-3600)
        func make(_ name: String, at date: Date) {
            let url = folder.appendingPathComponent(name)
            write("x", to: url)
            try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
        make("Evaluation_environment_for_Windows_games_2.0.dmg", at: old)
        make("holiday.dmg", at: since.addingTimeInterval(5))
        make("Game_Porting_Toolkit_4.0_beta_3.dmg.download", at: since.addingTimeInterval(5))
        make("Game_Porting_Toolkit_3.0.pdf", at: since.addingTimeInterval(5))
        check(Supply.newToolkitDownload(in: folder, since: since) == nil, "an old one, another image and an unfinished download aren't it")
        make("Game_Porting_Toolkit_3.0.dmg", at: since.addingTimeInterval(10))
        check(Supply.newToolkitDownload(in: folder, since: since)?.lastPathComponent == "Game_Porting_Toolkit_3.0.dmg", "the finished one is")
        make("Evaluation_environment_for_Windows_games_3.0.DMG", at: since.addingTimeInterval(20))
        check(Supply.newToolkitDownload(in: folder, since: since)?.lastPathComponent == "Evaluation_environment_for_Windows_games_3.0.DMG",
              "the newest of several, whatever the case of its ending")
        let lying = fresh(work, "lying-downloads")
        write("x", to: lying.appendingPathComponent("Game_Porting_Toolkit_3.0.dmg"))
        try? fm.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: lying.appendingPathComponent("Game_Porting_Toolkit_3.0.dmg").path)
        check(Supply.newToolkitDownload(in: lying, since: since) == nil
              && Supply.newToolkitDownload(in: lying, since: .distantPast)?.lastPathComponent == "Game_Porting_Toolkit_3.0.dmg",
              "one lying there already is found when the time doesn't matter")
        check(Supply.newToolkitDownload(in: fresh(work, "no-downloads"), since: since) == nil
              && Supply.newToolkitDownload(in: work.appendingPathComponent("missing"), since: since) == nil, "an empty or missing folder")

        let found = await Supply.waitForToolkit(in: folder, since: since, timeout: 5, poll: 0.05)
        check(found?.lastPathComponent == "Evaluation_environment_for_Windows_games_3.0.DMG", "it waits for the size to stand still, then returns it")
        let nothing = await Supply.waitForToolkit(in: fresh(work, "still-empty"), since: since, timeout: 0.3, poll: 0.05)
        check(nothing == nil, "the time runs out")
        let waiting = Task { await Supply.waitForToolkit(in: fresh(work, "never"), since: since, timeout: 60, poll: 0.05) }
        try? await Task.sleep(for: .milliseconds(150))
        let began = Date()
        waiting.cancel()
        let cancelled = await waiting.value
        check(cancelled == nil && Date().timeIntervalSince(began) < 2, "cancelling ends the wait at once")
    }

    // MARK: Which games ask

    static func games() {
        func analysis(_ apis: Set<GameAnalysis.API>) -> GameAnalysis {
            var analysis = GameAnalysis()
            analysis.apis = apis
            return analysis
        }
        check(Supply.needed(by: analysis([.d3d12]), picked: .automatic), "DirectX 12 and nothing else needs it")
        check(!Supply.needed(by: analysis([.d3d11, .d3d12]), picked: .automatic), "DirectX 11 as well: it runs without")
        check(!Supply.needed(by: analysis([.d3d11]), picked: .automatic) && !Supply.needed(by: analysis([.d3d9]), picked: .dxvk)
              && !Supply.needed(by: nil, picked: .automatic), "other games don't ask, nor one not yet looked at")
        check(Supply.needed(by: analysis([.d3d11]), picked: .d3dmetal) && Supply.needed(by: nil, picked: .d3dmetal), "the player's own pick does")
    }

    // MARK: Versions

    static func versions(_ work: URL) {
        check(Supply.isBeta("4.0b3") && Supply.isBeta("4.0 beta 3") && Supply.isBeta("3.0rc1") && Supply.isBeta("2.0a1"), "betas")
        check(!Supply.isBeta("3.0") && !Supply.isBeta("2.1") && !Supply.isBeta("4.0"), "finished versions")
        check(Supply.displayVersion("4.0b3") == "4.0 beta 3" && Supply.displayVersion("3.0") == "3.0" && Supply.displayVersion("2.0a1") == "2.0 alpha 1",
              "for people: \(Supply.displayVersion("4.0b3"))")
        check(Supply.finishedVersion == "3.0", "the finished one Nightforge's download is pinned to")

        // Taking it all away: the answer, the imports, the copies Nightforge downloaded.
        let components = fresh(work, "remove-components")
        let folder = fresh(work, "remove-folder")
        write("hash", to: components.appendingPathComponent("d3dmetal/3.0/.sha256"))
        write("x", to: components.appendingPathComponent("winecx/4.7.3/keep.txt"))
        write("x", to: Supply.importedFolder(in: folder).appendingPathComponent("3.0/lib/a"))
        Supply.save(.init(source: .apple, version: "3.0", accepted: Date()), in: folder)
        Supply.removeAll(componentsRoot: components, folder: folder)
        check(!fm.fileExists(atPath: components.appendingPathComponent("d3dmetal").path)
              && !fm.fileExists(atPath: Supply.importedFolder(in: folder).path) && Supply.choice(in: folder) == nil
              && fm.fileExists(atPath: components.appendingPathComponent("winecx/4.7.3/keep.txt").path),
              "removed: copies, imports, answer – and nothing else")
        check(Supply.current(manifest: manifest(d3dmetal: "3.0"), componentsRoot: components, folder: folder) == nil,
              "and nothing is adopted again")

        // An import that has taken over leaves the older ones no use.
        let imports = fresh(work, "prune")
        for version in ["3.0", "4.0b3", "4.0b2"] { write("x", to: Supply.importedFolder(in: imports).appendingPathComponent("\(version)/lib/a")) }
        Supply.pruneImports(keeping: "3.0", in: imports)
        check(((try? fm.contentsOfDirectory(atPath: Supply.importedFolder(in: imports).path)) ?? []) == ["3.0"], "only the one in use stays")
        Supply.pruneImports(keeping: nil, in: imports)
        check(((try? fm.contentsOfDirectory(atPath: Supply.importedFolder(in: imports).path)) ?? []).isEmpty, "none when another way is in use")
    }

    // MARK: The engine's files

    /// A stand-in engine: a wine binary, Wine's own Direct3D front ends, the stamp.
    static func engine(_ work: URL, _ name: String) -> (wine: URL, lib: URL) {
        let root = fresh(work, name)
        let wine = root.appendingPathComponent("Libraries/Wine/bin/wine")
        write("wine", to: wine)
        let lib = root.appendingPathComponent("Libraries/Wine/lib", isDirectory: true)
        for dll in ["d3d12.dll", "d3d11.dll", "dxgi.dll"] { write("wine's \(dll)", to: lib.appendingPathComponent("wine/x86_64-windows/\(dll)")) }
        write("wined3d", to: lib.appendingPathComponent("wine/x86_64-unix/wined3d.so"))
        return (wine, lib)
    }

    static func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    static func engineFiles(_ work: URL) {
        // Apple's files, as far as the signature check goes: a binary Apple signed stands in for the framework and the dylib.
        let payload = fresh(work, "payload")
        let external = payload.appendingPathComponent("lib/external", isDirectory: true)
        try? fm.createDirectory(at: external, withIntermediateDirectories: true)
        for name in ["libd3dshared.dylib", "D3DMetal.framework"] { try? fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: external.appendingPathComponent(name)) }
        for dll in ["d3d12.dll", "d3d11.dll", "nvngx-on-metalfx.dll"] { write("apple's \(dll)", to: payload.appendingPathComponent("lib/wine/x86_64-windows/\(dll)")) }
        let unix = payload.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        try? fm.createDirectory(at: unix, withIntermediateDirectories: true)
        for so in ["d3d12.so", "d3d11.so", "nvngx-on-metalfx.so"] {
            try? fm.createSymbolicLink(atPath: unix.appendingPathComponent(so).path, withDestinationPath: "../../external/libd3dshared.dylib")
        }
        check(Engine.isAppleSigned(external.appendingPathComponent("libd3dshared.dylib")), "(the stand-in passes the signature check)")

        let (wine, lib) = engine(work, "engine")
        let windows = lib.appendingPathComponent("wine/x86_64-windows")
        do { try Engine.installD3DMetal(payload, into: wine) } catch { check(false, "installing: \(error)") }
        check(text(windows.appendingPathComponent("d3d12.dll")) == "apple's d3d12.dll" && text(windows.appendingPathComponent("d3d11.dll")) == "apple's d3d11.dll"
              && text(windows.appendingPathComponent("dxgi.dll")) == "wine's dxgi.dll", "Apple's front ends are in, the others stay")
        check(text(windows.appendingPathComponent("d3d12.dll.wine")) == "wine's d3d12.dll" && !fm.fileExists(atPath: windows.appendingPathComponent("dxgi.dll.wine").path),
              "Wine's own kept where they were replaced")
        check(text(windows.appendingPathComponent("nvngx.dll")) == "apple's nvngx-on-metalfx.dll", "DLSS under NVIDIA's name")
        check((try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("wine/x86_64-unix/d3d12.so").path)) == "../../external/libd3dshared.dylib"
              && fm.fileExists(atPath: lib.appendingPathComponent("wine/x86_64-unix/wined3d.so").path), "the unix halves link to the dylib; Wine's stays")
        check(Engine.isD3DMetalDeployed(wine: wine), "deployed")
        check(!fm.fileExists(atPath: lib.appendingPathComponent(".d3dmetal-staging").path), "no staging left")

        // Another copy over it: Wine's own aren't lost, Apple's are replaced.
        write("apple's d3d12.dll, newer", to: payload.appendingPathComponent("lib/wine/x86_64-windows/d3d12.dll"))
        do { try Engine.installD3DMetal(payload, into: wine) } catch { check(false, "installing again: \(error)") }
        check(text(windows.appendingPathComponent("d3d12.dll")) == "apple's d3d12.dll, newer" && text(windows.appendingPathComponent("d3d12.dll.wine")) == "wine's d3d12.dll",
              "installed over: the newer one, Wine's own still the first")

        // What isn't Apple's changes nothing – not a file of what is there.
        let unsigned = fresh(work, "unsigned-payload")
        try? fm.copyItem(at: payload.appendingPathComponent("lib"), to: unsigned.appendingPathComponent("lib"))
        try? fm.removeItem(at: unsigned.appendingPathComponent("lib/external/D3DMetal.framework"))
        write("not Apple's", to: unsigned.appendingPathComponent("lib/external/D3DMetal.framework"))
        write("apple's d3d12.dll, from a stranger", to: unsigned.appendingPathComponent("lib/wine/x86_64-windows/d3d12.dll"))
        do {
            try Engine.installD3DMetal(unsigned, into: wine)
            check(false, "an unsigned framework was installed")
        } catch {
            check(text(windows.appendingPathComponent("d3d12.dll")) == "apple's d3d12.dll, newer" && Engine.isD3DMetalDeployed(wine: wine)
                  && !fm.fileExists(atPath: lib.appendingPathComponent(".d3dmetal-staging").path), "refused: the engine is as it was")
        }

        // The version it says, by its framework (a real one has the plist; the stand-in doesn't) and by the stamp.
        check(Engine.deployedD3DMetalVersion(wine: wine) == nil, "no version where the framework doesn't say")
        let versioned = engine(work, "versioned-engine")
        write("dylib", to: versioned.lib.appendingPathComponent("external/libd3dshared.dylib"))
        try? fm.createSymbolicLink(atPath: versioned.lib.appendingPathComponent("wine/x86_64-unix/d3d12.so").path, withDestinationPath: "../../external/libd3dshared.dylib")
        let plist = versioned.lib.appendingPathComponent("external/D3DMetal.framework/Versions/A/Resources/Info.plist")
        try? fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (["CFBundleShortVersionString": "4.0b3"] as NSDictionary).write(to: plist, atomically: true)
        check(Engine.deployedD3DMetalVersion(wine: versioned.wine) == "4.0b3", "the version the framework says")
        let stamp = versioned.lib.appendingPathComponent("wine/.nightforge-graphics")
        write("graphics 11.18 engine-match true moltenvk 1.4.2 d3dmetal apple-3.0 gamepad 4.7.3-7", to: stamp)
        check(Engine.deployedD3DMetalLabel(wine: versioned.wine) == "apple-3.0", "and the stamp's")
        write("graphics 11.18 d3dmetal - gamepad 4.7.3-7", to: stamp)
        check(Engine.deployedD3DMetalLabel(wine: versioned.wine) == nil, "none in the stamp: none")
        try? fm.removeItem(at: stamp)
        check(Engine.deployedD3DMetalLabel(wine: versioned.wine) == nil && Engine.deployedD3DMetalVersion(wine: engine(work, "bare").wine) == nil, "no stamp, no engine files: none")

        // Taking it out: Wine's own come back, Apple's go, and the stamp, so the next setup starts clean.
        write("graphics d3dmetal 3.0", to: lib.appendingPathComponent("wine/.nightforge-graphics"))
        Engine.removeD3DMetal(from: wine)
        check(text(windows.appendingPathComponent("d3d12.dll")) == "wine's d3d12.dll" && text(windows.appendingPathComponent("d3d11.dll")) == "wine's d3d11.dll"
              && text(windows.appendingPathComponent("dxgi.dll")) == "wine's dxgi.dll", "Wine's front ends are back")
        check(!fm.fileExists(atPath: windows.appendingPathComponent("nvngx.dll").path) && !fm.fileExists(atPath: windows.appendingPathComponent("nvngx-on-metalfx.dll").path),
              "what only Apple's had goes")
        let left = (try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent("wine/x86_64-unix").path)) ?? []
        check(left == ["wined3d.so"] && !fm.fileExists(atPath: lib.appendingPathComponent("external").path), "no link to it, no external/: \(left)")
        check(text(windows.appendingPathComponent("d3d12.dll.wine")) == "wine's d3d12.dll", "Wine's copies stay (the prefix's Direct3D 12 comes from them)")
        check(!fm.fileExists(atPath: lib.appendingPathComponent("wine/.nightforge-graphics").path) && !Engine.isD3DMetalDeployed(wine: wine), "stamp gone, not deployed")
    }

    // MARK: Apple's licence in the app

    static func licence(_ work: URL) {
        // The file in the repository (tests run from its root) is the one build.sh puts in the app.
        let shipped = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/Apple-GPTK-License.rtf")
        check(fm.fileExists(atPath: shipped.path), "Resources/Apple-GPTK-License.rtf is there")
        check(Supply.licenseDocument(at: shipped) == shipped, "it is the licence of Apple's toolkit 3.0, byte for byte (SHA-256 \(Supply.licenseSHA256.prefix(8))…)")
        let altered = work.appendingPathComponent("altered.rtf")
        try? (Data(contentsOf: shipped) + Data(" and Nightforge may do anything".utf8)).write(to: altered)
        check(Supply.licenseDocument(at: altered) == nil, "a file that differs isn't shown as Apple's licence")
        check(Supply.licenseDocument(at: work.appendingPathComponent("missing.rtf")) == nil && Supply.licenseDocument(at: nil) == nil, "none there, none shown")
        let script = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        check(script.contains("Resources/Apple-GPTK-License.rtf"), "build.sh puts it in the app")
    }

    // MARK: Unreal's driver warning

    static func unrealWarning(_ work: URL) {
        // The Black Myth: Wukong Benchmark Tool as it lies on disk (1.11.2026): its program beside the
        // folders, the game under b1/, Unreal's helpers under Engine/. Its Hardware.ini holds only a blank line.
        let game = fresh(work, "unreal-game")
        for exe in ["b1_benchmark.exe", "b1/Binaries/Win64/b1-Win64-Shipping.exe", "Engine/Binaries/Win64/EpicWebHelper.exe",
                    "Engine/Binaries/Win64/CrashReportClient.exe"] {
            write("MZ", to: game.appendingPathComponent(exe))
        }
        let hardware = game.appendingPathComponent("b1/Saved/Config/Windows/Hardware.ini")
        write("\r\n", to: hardware)
        check(Engine.unrealProjects(in: game).map(\.lastPathComponent) == ["b1"], "the project is found, not the helpers under Engine/: \(Engine.unrealProjects(in: game))")

        Engine.clearUnrealDriverDenyList(installDir: game)
        let cleared = text(hardware) ?? ""
        for section in ["[GPU_AMD]", "[GPU_AMD Windows]"] { check(cleared.contains(section), "section \(section) is there") }
        check(cleared.components(separatedBy: "!DriverDenyList=ClearArray").count == 3 && cleared.components(separatedBy: "!Blacklist=ClearArray").count == 3,
              "each clears the list under both names: \(cleared.debugDescription)")
        check(cleared.replacingOccurrences(of: "\r\n", with: "").contains("\n") == false, "no stray line breaks: \(cleared.debugDescription)")
        check(!fm.fileExists(atPath: game.appendingPathComponent("Engine/Saved").path)
              && !fm.fileExists(atPath: game.appendingPathComponent("Saved").path), "nothing written for Unreal's helpers or beside the program")

        let before = cleared
        Engine.clearUnrealDriverDenyList(installDir: game)
        check(text(hardware) == before, "doing it again changes nothing")

        // A game that has not run yet has no Saved/ folder: it's made, so the very first start is spared too.
        let fresh1 = fresh(work, "unreal-first-start")
        write("MZ", to: fresh1.appendingPathComponent("Game/Binaries/Win64/Game-Win64-Shipping.exe"))
        Engine.clearUnrealDriverDenyList(installDir: fresh1)
        check(text(fresh1.appendingPathComponent("Game/Saved/Config/Windows/Hardware.ini"))?.hasPrefix("[GPU_AMD]\n!Blacklist=ClearArray\n!DriverDenyList=ClearArray\n") == true,
              "a first start gets the file")
        check(!fm.fileExists(atPath: fresh1.appendingPathComponent("Game/Saved/Config/WindowsNoEditor").path), "Unreal 4's folder isn't made")

        // What the game or the player has in the file stays; the section it already has is added to, not repeated.
        let kept = fresh(work, "unreal-kept")
        write("MZ", to: kept.appendingPathComponent("Game/Binaries/Win64/Game-Win64-Shipping.exe"))
        let file = kept.appendingPathComponent("Game/Saved/Config/Windows/Hardware.ini")
        write("[Other]\nValue=1\n\n[GPU_AMD]\nSuggestedDriverVersion=\"22.2.2\"\n", to: file)
        Engine.clearUnrealDriverDenyList(installDir: kept)
        let merged = text(file) ?? ""
        check(merged.contains("[Other]\nValue=1\n") && merged.contains("SuggestedDriverVersion=\"22.2.2\"")
              && merged.components(separatedBy: "[GPU_AMD]").count == 2 && merged.contains("[GPU_AMD Windows]"), "the rest stays, one [GPU_AMD]: \(merged.debugDescription)")

        // Unreal 4 keeps its saved files in WindowsNoEditor once it has run.
        let old = fresh(work, "unreal-4")
        write("MZ", to: old.appendingPathComponent("Game/Binaries/Win64/Game-Win64-Shipping.exe"))
        write("", to: old.appendingPathComponent("Game/Saved/Config/WindowsNoEditor/Engine.ini"))
        Engine.clearUnrealDriverDenyList(installDir: old)
        check(text(old.appendingPathComponent("Game/Saved/Config/WindowsNoEditor/Hardware.ini"))?.contains("!Blacklist=ClearArray") == true
              && fm.fileExists(atPath: old.appendingPathComponent("Game/Saved/Config/Windows/Hardware.ini").path), "Unreal 4: its folder as well")

        // Games that aren't Unreal are left alone; so is a project's program that isn't the shipping one.
        let other = fresh(work, "not-unreal")
        write("MZ", to: other.appendingPathComponent("Game.exe"))
        write("MZ", to: other.appendingPathComponent("Game/Binaries/Win64/Launcher.exe"))
        write("MZ", to: other.appendingPathComponent("Unity/Game_Data/x.exe"))
        Engine.clearUnrealDriverDenyList(installDir: other)
        let leftovers = (fm.enumerator(atPath: other.path)?.allObjects as? [String] ?? []).filter { $0.contains("Hardware.ini") }
        check(Engine.unrealProjects(in: other).isEmpty && leftovers.isEmpty, "no Unreal, no file: \(leftovers)")

        // Two projects in one folder (a game and its benchmark), both done.
        let two = fresh(work, "two-projects")
        write("MZ", to: two.appendingPathComponent("A/Binaries/Win64/A-Win64-Shipping.exe"))
        write("MZ", to: two.appendingPathComponent("B/Binaries/Win64/B-Win64-Shipping.exe"))
        Engine.clearUnrealDriverDenyList(installDir: two)
        check(Engine.unrealProjects(in: two).map(\.lastPathComponent) == ["A", "B"]
              && ["A", "B"].allSatisfy { text(two.appendingPathComponent("\($0)/Saved/Config/Windows/Hardware.ini")) != nil }, "both projects")
    }

    // MARK: In the engine's list

    static func build() {
        guard let list = manifest(d3dmetal: "3.0"), let component = list.component("d3dmetal"), let engine = list.component("winecx") else {
            check(false, "no component to build with")
            return
        }
        let with = EngineBuild(engine: engine, graphics: [], d3dMetal: "apple-3.0", stamp: "s")
        check(with.version(of: "d3dmetal") == "apple-3.0" && with.graphics == ["d3dmetal@apple-3.0"],
              "a build holds the D3DMetal it carries, imported or not: \(with.graphics)")
        let without = EngineBuild(engine: engine, graphics: [], stamp: "s")
        check(without.version(of: "d3dmetal") == nil && without.graphics.isEmpty, "none: none")
        check(EngineBuild(engine: engine, graphics: [], d3dMetal: "4.0b3", stamp: "s") != EngineBuild(engine: engine, graphics: [], d3dMetal: "3.0", stamp: "s"),
              "another D3DMetal is another build")
    }
}
