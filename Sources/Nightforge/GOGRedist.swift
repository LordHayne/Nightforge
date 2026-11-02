import Foundation

/// GOG Galaxy's "Common Redistributables" for a Windows game, set up the way Heroic does it (7.3):
/// what a game needs, its gogdl manifest says (`dependencies`). gogdl fetches the installers from
/// GOG's dependencies repository into one folder for every game (GOG/Redist), and Nightforge runs
/// them quietly in its Windows environment – each once per environment, noted in the environment
/// itself, so a new one sets them up again and the next game with the same needs costs nothing.
/// A game installed by GOG's install script (`scriptInterpreter`) gets that run as Galaxy runs it,
/// once per build: it writes the registry entries and files the game looks for.
enum GOGRedist {
    /// The installers, shared by all games; gogdl keeps the repository's list in it.
    static var folder: URL { Engine.supportDir.appendingPathComponent("GOG/Redist", isDirectory: true) }
    static var repositoryFile: URL { folder.appendingPathComponent(".gogdl-redist-manifest") }
    /// What's set up in Nightforge's Windows environment, kept in it.
    static var recordFile: URL { Engine.prefix.appendingPathComponent("gog-redist.json") }
    static var log: URL { GOGDL.logsDir.appendingPathComponent("redist.log") }
    /// GOG's install script interpreter, fetched like an installer.
    static let interpreterID = "ISI"
    static var interpreter: URL { folder.appendingPathComponent("__redist/ISI/scriptinterpreter.exe") }

    /// Not run, each for a reason (docs/ROADMAP.md 7.3):
    /// - DirectX: DXSETUP (June 2010, 103 MB) brings d3dx9/10/11, d3dcompiler_43, XInput, XACT,
    ///   XAudio2, X3DAudio and XAPOFX – winecx has every one built in (i386 and x86_64), and native
    ///   copies in the one environment would replace them for every game.
    /// - .NET Framework 3.5 to 4.7.2: Microsoft's installers don't run under Wine; Wine Mono stands
    ///   in (`needsWineMono`).
    /// - ISI runs the install script, it isn't installed; Foxit is a PDF reader for manuals.
    static let dotNetFramework: Set<String> = ["dotNet35", "dotNet35C", "dotNet4", "dotNet4C", "dotNet45", "dotNet46", "dotNet47", "dotNet472"]
    static let skipped: Set<String> = Set(["DirectX", interpreterID, "Foxit"]).union(dotNetFramework)

    /// One entry of GOG's dependencies repository.
    struct Depot: Equatable {
        let id: String
        let name: String
        /// In `folder` ("__redist/MSVC2017/VC_redist.x86.exe"); empty: nothing to run (files a game
        /// uses itself, like DOSBox).
        let path: String
        let arguments: String
    }

    /// The repository as gogdl keeps it in `folder`, and which of it gogdl has fetched.
    struct Repository: Equatable {
        var depots: [String: Depot]
        var fetched: Set<String>

        static func from(json: Data) -> Repository? {
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let depots = object["depots"] as? [[String: Any]] else { return nil }
            var byID: [String: Depot] = [:]
            for depot in depots {
                guard let id = depot["dependencyId"] as? String else { continue }
                let executable = depot["executable"] as? [String: Any]
                byID[id] = Depot(id: id, name: depot["readableName"] as? String ?? id, path: executable?["path"] as? String ?? "",
                                 arguments: executable?["arguments"] as? String ?? "")
            }
            return Repository(depots: byID, fetched: Set(object["HGLInstalled"] as? [String] ?? []))
        }
    }

    /// What a game's gogdl manifest asks for.
    struct Needs: Equatable {
        var dependencies: [String]
        var scriptInterpreter = false
        /// The game and its add-ons, each with the installer GOG ran for it before install scripts
        /// (`temp_executable`, in the game's support folder; empty for most).
        var products: [(id: String, installer: String)] = []
        var build: String?

        static func == (a: Needs, b: Needs) -> Bool {
            a.dependencies == b.dependencies && a.scriptInterpreter == b.scriptInterpreter && a.build == b.build
                && a.products.map(\.id) == b.products.map(\.id) && a.products.map(\.installer) == b.products.map(\.installer)
        }

        /// gogdl's manifest is GOG's build manifest (v2: `dependencies`, `scriptInterpreter`,
        /// `products`; v1: depots with a `redist`).
        static func from(manifest json: Data) -> Needs? {
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
            if (object["version"] as? NSNumber)?.intValue == 1 {
                let depots = (object["product"] as? [String: Any])?["depots"] as? [[String: Any]] ?? []
                var dependencies: [String] = []
                for case let redist as String in depots.map({ $0["redist"] }) where !dependencies.contains(redist) {
                    dependencies.append(redist)
                }
                return Needs(dependencies: dependencies)
            }
            var dependencies: [String] = []
            for dependency in object["dependencies"] as? [String] ?? [] where !dependencies.contains(dependency) {
                dependencies.append(dependency)
            }
            let products = (object["products"] as? [[String: Any]] ?? []).compactMap { product -> (id: String, installer: String)? in
                guard let id = (product["productId"] as? String) ?? (product["productId"] as? NSNumber)?.stringValue else { return nil }
                return (id, product["temp_executable"] as? String ?? "")
            }
            return Needs(dependencies: dependencies, scriptInterpreter: object["scriptInterpreter"] as? Bool ?? false, products: products,
                         build: (object["buildId"] as? String) ?? (object["buildId"] as? NSNumber)?.stringValue)
        }
    }

    /// What's set up in the environment. A step that failed is tried again at a later start – not
    /// within ten minutes (a retry during the same start) and not after twice: each start would
    /// wait for it again.
    struct Record: Codable, Equatable {
        var installed: Set<String> = []
        /// Install scripts and installers run per product: the build they ran for.
        var products: [String: String] = [:]
        var failures: [String: Failure] = [:]

        struct Failure: Codable, Equatable {
            var count: Int
            var last: Date
        }

        func gaveUp(_ key: String, now: Date) -> Bool {
            guard let failure = failures[key] else { return false }
            return failure.count >= 2 || now.timeIntervalSince(failure.last) < 10 * 60
        }

        mutating func failed(_ key: String, now: Date) {
            failures[key] = Failure(count: (failures[key]?.count ?? 0) + 1, last: now)
        }

        mutating func succeeded(_ key: String) { failures[key] = nil }
    }

    static func loadRecord() -> Record {
        (try? Data(contentsOf: recordFile)).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } ?? Record()
    }

    static func save(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: recordFile, options: .atomic)
    }

    // MARK: - What's to do

    /// The dependencies still to install, in the manifest's order.
    static func wanted(_ needs: Needs, record: Record, now: Date = Date()) -> [String] {
        needs.dependencies.filter { !skipped.contains($0) && !record.installed.contains($0) && !record.gaveUp($0, now: now) }
    }

    /// The products whose install script (or installer) hasn't run for this build.
    static func productsDue(_ needs: Needs, install: GOGInstall, record: Record, now: Date = Date()) -> [String] {
        let build = needs.build ?? install.build
        return needs.products.filter { product in
            (product.id == install.id || install.dlcs.contains(product.id)) && (needs.scriptInterpreter || !product.installer.isEmpty)
                && record.products[product.id] != build && !record.gaveUp("product:" + product.id, now: now)
        }.map(\.id)
    }

    static func needsWineMono(_ needs: Needs) -> Bool { needs.dependencies.contains(where: dotNetFramework.contains) }

    /// What to have gogdl fetch: what's wanted and what it fetched before – it removes whatever
    /// isn't named.
    static func idsToFetch(wanted: [String], script: Bool, repository: Repository?) -> [String] {
        Array((repository?.fetched ?? []).union(wanted).union(script ? [interpreterID] : [])).sorted()
    }

    /// An installer's command line under Wine, without a window: an .msi through msiexec, fully
    /// quiet; "/passive" (a progress window) becomes "/quiet".
    static func command(for depot: Depot, in folder: URL) -> [String] {
        let file = folder.appendingPathComponent(depot.path)
        let arguments = split(depot.arguments)
        if file.pathExtension.lowercased() == "msi" {
            let quietless = arguments.filter { !["/passive", "/qb", "/qn", "/quiet"].contains($0.lowercased()) }
            return ["msiexec", "/i", Engine.windowsPath(of: file)] + quietless + ["/qn"]
        }
        return [Engine.windowsPath(of: file)] + arguments.map { $0.lowercased() == "/passive" ? "/quiet" : $0 }
    }

    /// GOG's install script for a product (or the installer it came with), started the way Galaxy
    /// and Heroic start it.
    static func productCommand(_ product: (id: String, installer: String), needs: Needs, install: GOGInstall,
                               versionName: String?) -> [String] {
        let code = install.language.isEmpty ? "en-US" : install.language
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: String(code.prefix { $0 != "-" })) ?? "English"
        let program = needs.scriptInterpreter
            ? interpreter
            : GOGDL.supportDir(for: install.id).appendingPathComponent(product.id).appendingPathComponent(product.installer)
        let named = needs.scriptInterpreter ? language : language.lowercased()
        return [Engine.windowsPath(of: program), "/VERYSILENT", "/DIR=" + Engine.windowsPath(of: install.path),
                "/Language=" + named, "/LANG=" + named, "/ProductId=" + product.id, "/galaxyclient",
                "/buildId=" + (needs.build ?? install.build), "/versionName=" + (versionName ?? ""), "/lang-code=" + code,
                "/supportDir=" + Engine.windowsPath(of: GOGDL.supportDir(for: install.id)),
                "/nodesktopshorctut", "/nodesktopshortcut"]  // sic: GOG's scripts know the typo
    }

    /// GOG's argument strings, split like a shell would (Heroic uses shlex): quotes group and go.
    static func split(_ arguments: String) -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var started = false
        for character in arguments {
            if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started || !word.isEmpty { words.append(word) }
                word = ""
                started = false
            } else {
                word.append(character)
            }
        }
        if started || !word.isEmpty { words.append(word) }
        return words
    }

    /// Done: 0, 3010 and 1641 (done, a restart wanted), 1638 (a newer one is there). Wine hands on
    /// the low byte of a Windows exit code.
    static func succeeded(_ status: Int32) -> Bool {
        [0, 3010, 1641, 1638].contains { $0 & 0xFF == status & 0xFF }
    }

    // MARK: - Setting up

    /// Whether `install` still needs something, read from its manifest and the record: cheap, so
    /// every start can ask.
    static func hasWork(_ install: GOGInstall) -> Bool {
        guard install.platform == .windows, let json = try? Data(contentsOf: GOGDL.manifest(for: install.id)),
              let needs = Needs.from(manifest: json) else { return false }
        let record = loadRecord()
        return !wanted(needs, record: record).isEmpty || !productsDue(needs, install: install, record: record).isEmpty
            || (needsWineMono(needs) && !Engine.wineMonoInstalled)
    }

    /// One game's setup at a time: two would fetch and install the same parts at once.
    @MainActor private static var busy = false

    /// Fetches what `install` needs and sets it up; `progress` gets each part's name as it goes
    /// (nil while they come from GOG). Returns the parts that failed and whether they're tried
    /// again at a later start.
    @MainActor
    static func setUp(_ install: GOGInstall, versionName: String?, wine: URL,
                      progress: (String?) -> Void) async -> (failed: [String], retried: Bool) {
        while busy { try? await Task.sleep(for: .milliseconds(300)) }
        busy = true
        defer { busy = false }
        guard let json = try? Data(contentsOf: GOGDL.manifest(for: install.id)), let needs = Needs.from(manifest: json) else { return ([], false) }
        var record = loadRecord()
        let wanted = wanted(needs, record: record)
        let due = productsDue(needs, install: install, record: record)
        var failed: [String] = []
        var keys: [String] = []

        // From GOG, unless every installer is here already.
        var repository = (try? Data(contentsOf: repositoryFile)).flatMap(Repository.from)
        let missing = wanted.contains { id in
            guard let depot = repository?.depots[id] else { return true }
            return depot.path.hasPrefix("__redist") && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(depot.path).path)
        } || (needs.scriptInterpreter && !due.isEmpty && !FileManager.default.fileExists(atPath: interpreter.path))
        if missing {
            progress(nil)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ids = idsToFetch(wanted: wanted, script: needs.scriptInterpreter && !due.isEmpty, repository: repository)
            let result = try? await GOGDL.run(["redist", "--ids", ids.joined(separator: ","), "--path", folder.path], timeout: 1800)
            // Only gogdl's errors: its other lines may carry download links.
            let errors = (result?.log ?? "").split(whereSeparator: \.isNewline).filter { $0.contains("ERROR") || $0.contains("CRITICAL") }
            note("gogdl redist --ids \(ids.joined(separator: ",")) ended with \(result.map { String($0.status) } ?? "no start")"
                 + errors.map { "\n  " + $0 }.joined())
            repository = (try? Data(contentsOf: repositoryFile)).flatMap(Repository.from)
        }

        for id in wanted {
            guard let depot = repository?.depots[id] else {
                // Not in GOG's repository (or GOG couldn't be asked): tried again next time.
                record.failed(id, now: Date())
                failed.append(id)
                keys.append(id)
                continue
            }
            let installer = folder.appendingPathComponent(depot.path)
            guard !depot.path.isEmpty, depot.path.hasPrefix("__redist") else {
                // Files the game uses itself (gogdl puts them in its folder): nothing to run.
                record.installed.insert(id)
                continue
            }
            progress(depot.name)
            let status = FileManager.default.fileExists(atPath: installer.path)
                ? await runWindows(command(for: depot, in: folder), wine: wine, directory: folder, timeout: 600) : nil
            if let status, succeeded(status) {
                record.installed.insert(id)
                record.succeeded(id)
            } else {
                record.failed(id, now: Date())
                failed.append(depot.name)
                keys.append(id)
            }
            save(record)
        }
        if needsWineMono(needs) && !Engine.wineMonoInstalled {
            progress(".NET (Wine Mono)")
            await Engine.installWineMono(wine)
        }
        for id in due {
            guard let product = needs.products.first(where: { $0.id == id }) else { continue }
            progress(nil)
            let command = productCommand(product, needs: needs, install: install, versionName: versionName)
            let program = needs.scriptInterpreter
                ? interpreter : GOGDL.supportDir(for: install.id).appendingPathComponent(product.id).appendingPathComponent(product.installer)
            let status = FileManager.default.fileExists(atPath: program.path)
                ? await runWindows(command, wine: wine, directory: install.path, timeout: 600) : nil
            if let status, succeeded(status) {
                record.products[id] = needs.build ?? install.build
                record.succeeded("product:" + id)
            } else {
                record.failed("product:" + id, now: Date())
                failed.append(L10n.t("GOG's install script"))
                keys.append("product:" + id)
            }
            save(record)
        }
        save(record)
        return (failed, keys.contains { (record.failures[$0]?.count ?? 0) < 2 })
    }

    /// Runs a Windows program in Nightforge's environment and waits for it – for it alone, not for
    /// Wine as a whole: Steam may be running in there. nil when it didn't start or took longer
    /// than `timeout` (then it's stopped).
    nonisolated static func runWindows(_ arguments: [String], wine: URL, directory: URL, timeout: TimeInterval) async -> Int32? {
        note("wine " + arguments.joined(separator: " "))
        try? FileManager.default.createDirectory(at: GOGDL.logsDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let output = try? FileHandle(forWritingTo: log)
        defer { try? output?.close() }
        let process = DetachedProcess()
        process.executableURL = wine
        process.arguments = arguments
        process.environment = Engine.environment(wine: wine)
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        guard (try? process.run()) != nil else { return nil }
        let start = Date()
        while process.isRunning {
            if Date().timeIntervalSince(start) > timeout {
                process.terminate()
                note("stopped after \(Int(timeout)) s")
                return nil
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        note("ended with \(process.terminationStatus)")
        return process.terminationStatus
    }

    /// A line in GOG/Logs/redist.log (kept under 4 MB).
    nonisolated static func note(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: GOGDL.logsDir, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: log.path))?[.size] as? UInt64, size > 4_000_000 { try? fm.removeItem(at: log) }
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: log) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(Data("\(ISO8601DateFormatter().string(from: Date())) \(text)\n".utf8))
    }
}
