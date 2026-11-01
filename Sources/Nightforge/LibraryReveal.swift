import SwiftUI

/// At the end of the first start (and its replay from Settings › About): how many of your games
/// run on this Mac, in one bar, with what each part means.
struct LibraryReveal: Identifiable, Equatable {
    var great = 0, tweaks = 0, untested = 0, no = 0
    /// Games that don't start on a Mac yet, and Nightforge is working on it (apart from `no`: anti-cheat that stays).
    var later = 0
    /// Of the games that don't run, the ones GeForce Now streams, and the VR-only ones.
    var cloud = 0
    var vr = 0
    /// Of all of them, the ones Nightforge plays as their Mac version (through Steam for Mac).
    var mac = 0
    let id = UUID()

    var total: Int { great + tweaks + untested + no + later }
    /// "Run here": rated great or with tweaks.
    var running: Int { great + tweaks }

    init(great: Int = 0, tweaks: Int = 0, untested: Int = 0, no: Int = 0, cloud: Int = 0, vr: Int = 0, mac: Int = 0, later: Int = 0) {
        (self.great, self.tweaks, self.untested, self.no, self.cloud, self.vr) = (great, tweaks, untested, no, cloud, vr)
        self.mac = mac
        self.later = later
    }

    /// The player's own games' levels (store hits and demos of games they don't own aren't theirs).
    init(_ rated: [(game: Game, level: Compatibility.Level)]) {
        for (game, level) in rated where game.inLibrary {
            if game.platform == .mac || game.macPending != nil { mac += 1 }
            switch level {
            case .great: great += 1
            case .tweaks: tweaks += 1
            case .untested: untested += 1
            case .notYet: later += 1
            case .no:
                no += 1
                if game.isVROnly { vr += 1 } else if game.playsInCloud { cloud += 1 }
            }
        }
    }

    static func == (a: LibraryReveal, b: LibraryReveal) -> Bool {
        (a.great, a.tweaks, a.untested, a.no, a.cloud, a.vr) == (b.great, b.tweaks, b.untested, b.no, b.cloud, b.vr)
            && a.mac == b.mac && a.later == b.later
    }

    /// The line about Mac versions under the bar: they play natively once Steam for Mac is signed
    /// in in the first start, or ("Later") the first time one is played.
    func macLine(later: Bool) -> String? {
        switch (mac, later) {
        case (0, _): return nil
        case (1, false): return L10n.t("1 of them plays as its Mac version – without any Windows translation.")
        case (_, false): return L10n.t("%ld of them play as their Mac version – without any Windows translation.", mac)
        case (1, true): return L10n.t("1 has a Mac version – Nightforge sets it up the first time you play it.")
        case (_, true): return L10n.t("%ld have a Mac version – Nightforge sets it up the first time you play one.", mac)
        }
    }

    var headline: String {
        switch total {
        case 0: return L10n.t("Steam is connected")
        case 1: return L10n.t("%ld of your 1 game runs here", running)
        default: return L10n.t("%ld of your %ld games run here", running, total)
        }
    }
}

/// The first start's look at the library, "Checking your library … N of M games". Steam sends the
/// account's games a moment after the sign-in – its licence list and app info land in its caches,
/// and a scan finds more while that goes on – so the check scans until two scans in a row find the
/// same games. Then every game is looked up once.
struct LibraryCheck: Equatable {
    /// The games found; nil while Steam is still sending them.
    var total: Int?
    var checked = 0

    /// Up to how long the check waits for Steam's library after the sign-in.
    static let patience: TimeInterval = 120
    /// Between two scans while it waits.
    static let interval = Duration.seconds(3)

    var fraction: Double? {
        total.map { $0 == 0 ? 1 : min(Double(checked) / Double($0), 1) }
    }

    /// Whether to scan once more: nothing found yet, or not as many as the scan before (Steam is
    /// still writing). The replay counts what's there; after `patience` the check goes on with
    /// what it has.
    static func waitsForSteam(previous: Int?, now: Int, waited: TimeInterval, replay: Bool) -> Bool {
        guard !replay, waited < patience else { return false }
        return now == 0 || previous != now
    }

    /// The pause after each game, so the count can be read: 90 ms a game, all of them within 2.5 s.
    static func pause(total: Int) -> Duration {
        total > 0 ? .milliseconds(min(90, 2500 / total)) : .zero
    }
}

extension LibraryModel {
    /// The first start's last step, after the sign-in (and the replay's): Steam's library, every
    /// game looked up – the newest list of what runs, and what the files of the ones on the Mac
    /// say – then how many of them run here.
    func checkLibrary() {
        guard setup.isActive else {
            reload()
            return
        }
        let replay = setup.isReplay
        setup.checkTask?.cancel()
        setup.checkTask = Task {
            if !replay { await ProfileStore.shared.refresh() }
            let start = Date()
            var previous: Int?
            var games = await ownGamesAfterScan()
            while LibraryCheck.waitsForSteam(previous: previous, now: games.count,
                                             waited: Date().timeIntervalSince(start), replay: replay) {
                try? await Task.sleep(for: LibraryCheck.interval)
                guard !Task.isCancelled else { return }
                previous = games.count
                games = await ownGamesAfterScan()
            }

            var check = LibraryCheck(total: games.count)
            setup.checking(check)
            let pause = LibraryCheck.pause(total: games.count)
            for game in games {
                guard !Task.isCancelled else { return }
                _ = await insight(of: game)
                check.checked += 1
                setup.checking(check)
                try? await Task.sleep(for: pause)
            }
            try? await Task.sleep(for: .milliseconds(500))  // the full count, for a moment
            guard !Task.isCancelled else { return }
            let reveal = LibraryReveal(games.map { ($0, compatibility(of: $0).level) })
            // Steam for Mac got ready alongside the setup: now that the games are known, the second
            // code – for the Mac versions – or not (MacSteamPrep). Not in the replay.
            if !replay, macSteamPrep.state != .idle {
                await macSteamPrep.finish(windowsAccount: SteamLogin.rememberedAccount(steamRoot: Engine.steamRoot),
                                          macVersions: reveal.mac)
                guard !Task.isCancelled else { return }
                comeForward()  // Steam for Mac's window had the front for its sign-in
            }
            setup.reveal(reveal)
        }
    }

    private func ownGamesAfterScan() async -> [Game] {
        let before = lastScan
        reload(quiet: true)
        while lastScan == before, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return cards.filter(\.inLibrary)  // a game from two stores is one game (DuplicateGames)
    }
}

/// The bar in the compatibility colours and a line for each part: what it means.
struct LibraryRevealView: View {
    let reveal: LibraryReveal

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.level) { part in
                        Rectangle().fill(part.level.color)
                            .frame(width: max(0, geo.size.width * CGFloat(part.count) / CGFloat(max(reveal.total, 1)) - 2))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            Grid(alignment: .topLeading, horizontalSpacing: 36, verticalSpacing: 16) {
                GridRow {
                    row(.great, reveal.great, L10n.t("Tested by Nightforge, a Mac version, or it started fine here."))
                    row(.tweaks, reveal.tweaks, L10n.t("Nightforge applies what they need by itself, at every start."))
                }
                GridRow {
                    row(.untested, reveal.untested, L10n.t("Nobody has tried them on a Mac with Nightforge yet – most still run. The first start tells, and Nightforge remembers what works."))
                    row(.no, reveal.no, notRunning)
                }
                if reveal.later > 0 {
                    GridRow {
                        row(.notYet, reveal.later, L10n.t("Nightforge doesn't start them yet and is working on it. Some play on GeForce Now meanwhile."))
                    }
                }
            }
        }
    }

    /// Why: anti-cheat (some on GeForce Now instead) and VR headsets.
    private var notRunning: String {
        var reasons: [String] = []
        if reveal.no > reveal.vr {
            reasons.append(reveal.cloud > 0
                ? L10n.t("Their anti-cheat needs Windows itself – %ld of them play on GeForce Now instead.", reveal.cloud)
                : L10n.t("Their anti-cheat needs Windows itself."))
        }
        if reveal.vr > 0 {
            reasons.append(reveal.vr == 1 ? L10n.t("1 needs a VR headset.") : L10n.t("%ld need a VR headset.", reveal.vr))
        }
        return reasons.isEmpty ? L10n.t("Their anti-cheat needs Windows itself.") : reasons.joined(separator: " ")
    }

    private var parts: [(level: Compatibility.Level, count: Int)] {
        [(.great, reveal.great), (.tweaks, reveal.tweaks), (.untested, reveal.untested), (.no, reveal.no), (.notYet, reveal.later)]
            .filter { $0.count > 0 }
    }

    private func row(_ level: Compatibility.Level, _ count: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count) · \(level.label)").font(size: 15, weight: .semibold).monospacedDigit()
                Text(text)
                    .font(size: 13)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .opacity(count > 0 ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }
}
