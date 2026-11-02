import Foundation

/// The line under the first start's running step – what happens right now – and the one under a
/// finished step. Only what Nightforge can see: a download's bytes, Steam's own log, the files
/// Windows lays down. No guesses, no estimated times.
enum SetupDetail {
    /// A finished step: how long it took, or that it was already there (a setup carried on).
    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole < 1 { return L10n.t("was already there") }
        if whole < 60 { return L10n.t("in %ld s", whole) }
        return L10n.t("in %ld min %ld s", whole / 60, whole % 60)
    }

    /// The Mac's step, done: Rosetta is there, and how much room the disk has.
    static func mac(freeBytes: Int64) -> String {
        L10n.t("Rosetta is there · %@ free", Format.bytes(freeBytes))
    }

    /// "142 MB of 461 MB · 15 MB/s" – the speed once it's known.
    static func transfer(done: Int64, total: Int64, bytesPerSecond: Double?) -> String {
        let amount = L10n.t("%@ of %@", Format.bytes(max(done, 0)), Format.bytes(total))
        guard let rate = bytesPerSecond, rate > 0 else { return amount }
        return amount + " · " + Format.bytes(Int64(rate)) + "/s"
    }

    /// A component coming down, then being unpacked (its archive is complete, the checksum and
    /// unpacking report nothing).
    static func component(_ component: Component, fraction: Double, bytesPerSecond: Double?) -> String {
        guard fraction < 1 else { return L10n.t("Unpacking %@ …", name(of: component)) }
        let done = Int64(fraction * Double(component.size))
        return L10n.t("%@: %@", name(of: component), transfer(done: done, total: component.size, bytesPerSecond: bytesPerSecond))
    }

    /// A component's name for people, with its version from the list.
    static func name(of component: Component) -> String {
        // "1.10.3-20230507" → "1.10.3"; "11.18-dxmt0.80-13" → DXMT's "0.80".
        let version = component.version.split(separator: "-").first.map(String.init) ?? component.version
        switch component.id {
        case Engine.winecxEngineID: return L10n.t("Wine %@ (CrossOver)", component.version)
        case Engine.engineID: return "Wine \(component.version)"
        case Engine.graphicsID:
            let dxmt = component.version.split(separator: "-").first { $0.hasPrefix("dxmt") }?.dropFirst(4)
            return dxmt.map { "DXMT \($0)" } ?? L10n.t("Graphics layers")
        case Engine.d3dMetalID: return "D3DMetal \(component.version)"
        case Engine.gamepadID: return L10n.t("Controller support")
        case Engine.engineFixID: return L10n.t("Engine fixes (sound, stability)")
        case Engine.dxvkID: return "DXVK \(version)"
        case Engine.moltenVKID: return "MoltenVK \(component.version)"
        default: return "\(component.id) \(component.version)"
        }
    }

    /// Windows being laid down by wineboot: its system files, counted as they appear.
    static func windows(systemFiles: Int) -> String {
        systemFiles > 0 ? L10n.t("Creating Windows · %ld system files", systemFiles) : L10n.t("Creating Windows …")
    }

    /// The engine's own steps after its downloads (Engine.ensureEngine).
    static func engine(_ step: Engine.SetupStep, bytesPerSecond: Double? = nil) -> String {
        switch step {
        case .downloading(let component, let fraction): return self.component(component, fraction: fraction, bytesPerSecond: bytesPerSecond)
        case .graphics: return L10n.t("Setting up the graphics layers …")
        case .gameEnvironment: return L10n.t("Setting up the game environment …")
        }
    }

    /// Steam's update as Nightforge fetches it ahead (SteamPrefetch), when it's still coming down
    /// as Steam is about to start.
    static func steamUpdate(done: Int64, total: Int64, bytesPerSecond: Double?) -> String {
        L10n.t("Downloading Steam's update: %@", transfer(done: done, total: total, bytesPerSecond: bytesPerSecond))
    }

    /// Steam's own update, from its bootstrap log: which of its two packages (the 32-bit step first,
    /// then the 64-bit client), how far and how fast – the speed from the log's own stamps.
    static func steam(log: String, clientInstalled: Bool) -> String {
        var block: [Substring] = []
        for line in log.split(whereSeparator: \.isNewline) {
            if line.contains("Startup - updater built") { block = [] }
            block.append(line)
        }
        let package: Int? = block.last { $0.contains("steam_client_win") }.map { $0.contains("steam_client_win64") ? 2 : 1 }
        switch SteamBootstrap(log: log) {
        case .downloading:
            guard let progress = downloadProgress(block) else { return L10n.t("Steam looks for its update …") }
            let amount = transfer(done: progress.done, total: progress.total, bytesPerSecond: progress.rate)
            switch package {
            case 1: return L10n.t("Steam downloads update 1 of 2: %@", amount)
            case 2: return L10n.t("Steam downloads update 2 of 2, the 64-bit version: %@", amount)
            default: return L10n.t("Steam downloads its update: %@", amount)
            }
        case .installing:
            switch package {
            case 1: return L10n.t("Steam installs update 1 of 2 …")
            case 2: return L10n.t("Steam installs update 2 of 2, the 64-bit version …")
            default: return L10n.t("Steam installs its update …")
            }
        case .updated:
            return L10n.t("Update installed – Steam starts again …")
        case .idle:
            return clientInstalled ? L10n.t("Steam starts for the first time …") : L10n.t("Steam is starting …")
        }
    }

    /// Steam for Mac's step (MacSteamPrep), which runs alongside the Windows setup: its download and
    /// update – from its bootstrap log, like the Windows Steam's – then what became of it.
    static func macSteam(_ state: MacSteamPrep.State, log: String) -> String? {
        switch state {
        case .idle: return nil
        case .preparing(.installing): return L10n.t("Downloading Steam for Mac …")
        case .preparing(.updating):
            var block: [Substring] = []
            for line in log.split(whereSeparator: \.isNewline) {
                if line.contains("Startup - updater built") { block = [] }
                block.append(line)
            }
            guard let progress = downloadProgress(block) else { return L10n.t("Steam for Mac updates itself …") }
            return L10n.t("Steam for Mac updates itself: %@", transfer(done: progress.done, total: progress.total, bytesPerSecond: progress.rate))
        case .preparing(.waitingForSignIn), .ready(.waitingForSignIn): return L10n.t("Ready – you sign in right after Steam")
        case .preparing(.remembered), .ready(.remembered), .done(.alreadySignedIn): return L10n.t("Already signed in on this Mac")
        case .ready: return L10n.t("Ready")
        case .signingIn: return L10n.t("Its sign-in window is open")
        case .done(.signIn): return L10n.t("Signed in")
        case .done(.otherAccount): return L10n.t("Signed in with another account – left as it is")
        case .done(.notNeeded): return L10n.t("Not needed – none of your games has a Mac version")
        case .later: return L10n.t("Later – the first time you play a Mac version")
        case .failed(let message): return message
        }
    }

    /// The newest "(12,345 von 336,229 KB)" line – the word in the middle is Steam's language – and
    /// the speed from it and one at least 3 s older.
    private static func downloadProgress(_ block: [Substring]) -> (done: Int64, total: Int64, rate: Double?)? {
        let lines = block.compactMap { line -> (date: Date, done: Double, total: Double)? in
            guard line.contains(" KB)"), let date = stamp(line) else { return nil }
            let numbers = line.split(separator: "(").last?.split(separator: " ").compactMap {
                Double($0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ""))
            } ?? []
            guard numbers.count >= 2, numbers[1] > 0 else { return nil }
            return (date, numbers[0], numbers[1])
        }
        guard let last = lines.last else { return nil }
        var rate: Double?
        if let earlier = lines.last(where: { last.date.timeIntervalSince($0.date) >= 3 }), last.done > earlier.done {
            rate = (last.done - earlier.done) * 1024 / last.date.timeIntervalSince(earlier.date)
        }
        return (Int64(last.done * 1024), Int64(last.total * 1024), rate)
    }

    private static let stamps: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")  // only differences count
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return format
    }()

    private static func stamp(_ line: Substring) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return stamps.date(from: String(line[line.index(after: line.startIndex)..<close]))
    }
}
