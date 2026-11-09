import AppKit
import CoreGraphics
import SwiftUI

/// What can honestly be said about the Mac while downloads are listed: the word at the ring and the
/// sentence in the Downloads panel (board DownloadHinweise, A1). It follows what really holds the Mac awake.
enum DownloadStanding: Equatable {
    /// Nothing listed, or the hold couldn't be taken: no word, as any would be a guess.
    case silent
    case awake
    /// Awake, and closing the lid would still put it to sleep.
    case awakeLidOpen
    /// Nothing fetches: all paused, or waiting for room.
    case paused
    /// The store that would fetch has been gone for longer than a changeover takes.
    case storeStopped(String)

    /// `fetching` already has the grace of a store changing over (`KeepAwake.held`): until that has run out
    /// nothing here says the store is gone.
    nonisolated static func of(listed: Bool, fetching: Bool, holding: Bool,
                               downloads: [KeepAwake.Download], lidMatters: Bool) -> DownloadStanding {
        guard listed else { return .silent }
        if fetching { return holding ? (lidMatters ? .awakeLidOpen : .awake) : .silent }
        guard let stopped = downloads.first(where: { !$0.paused }) else { return .paused }
        return .storeStopped(stopped.provider.label)
    }

    /// Only a Mac with a lid (a battery tells, an iMac has none), with its own screen on. With another screen
    /// the Mac runs on with the lid shut, but only on the mains (Apple's closed-display mode).
    nonisolated static func lidMatters(hasBattery: Bool, builtInDisplay: Bool, externalDisplay: Bool, onBattery: Bool) -> Bool {
        hasBattery && builtInDisplay && (!externalDisplay || onBattery)
    }

    /// Which screens are connected. Online also counts a mirrored or sleeping one, which the list of screens
    /// to draw on doesn't. Can't be read: neither, so no word about the lid.
    static func onlineDisplays() -> (builtIn: Bool, external: Bool) {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return (false, false) }
        let online = ids.prefix(Int(count))
        return (online.contains { CGDisplayIsBuiltin($0) != 0 }, online.contains { CGDisplayIsBuiltin($0) == 0 })
    }

    /// The ring turns grey: nothing is being fetched.
    var mayDoze: Bool {
        switch self {
        case .paused, .storeStopped: return true
        case .silent, .awake, .awakeLidOpen: return false
        }
    }

    var ringWord: String? {
        switch self {
        case .silent: return nil
        case .awake: return L10n.t("Mac stays awake")
        case .awakeLidOpen: return L10n.t("Keep the lid open")
        case .paused: return L10n.t("Mac may sleep")
        case .storeStopped(let store): return L10n.t("%@ isn't running", store)
        }
    }

    /// The panel's last line: what stands out first, then the rest, then what the player has to do.
    struct Sentence: Equatable {
        let symbol: String
        var lead: String?
        var text: String
        var action: String?

        var whole: String { [lead, text, action].compactMap { $0 }.joined(separator: " ") }
    }

    var sentence: Sentence? {
        let awake = L10n.t("Your Mac stays awake while games download. The display can still turn off.")
        switch self {
        case .silent:
            return nil
        case .awake:
            return Sentence(symbol: "sun.max", text: awake)
        case .awakeLidOpen:
            return Sentence(symbol: "laptopcomputer", text: awake, action: L10n.t("Keep the lid open."))
        case .paused:
            return Sentence(symbol: "moon.zzz", text: L10n.t("Paused: your Mac may sleep."))
        case .storeStopped(let store):
            return Sentence(symbol: "moon.zzz", lead: L10n.t("%@ isn't running, so the download has stopped.", store),
                            text: L10n.t("Your Mac may sleep."))
        }
    }
}

/// The proof on coming back: what the downloads did while the screen was dark (board DownloadHinweise, C2).
/// Says nothing unless it can show it.
struct DownloadProof: Equatable {
    enum Kind: Equatable {
        case ranOn
        case severalRanOn
        case finished(String)
    }

    let kind: Kind
    /// Nil: the amount isn't known, the sentence goes without a number.
    let bytes: Int64?

    /// How far a download was at one moment.
    struct Mark: Equatable {
        var name: String
        var fraction: Double?
        var size: Int64
        var finished = false
    }

    /// A time the screen was dark, from its start.
    struct Stretch: Equatable {
        let began: Date
        let awakeAtStart: TimeInterval
        let before: [String: Mark]
    }

    /// Shorter than this and nobody missed anything.
    static let shortestDark: TimeInterval = 120
    /// Less than this came down: not worth a sentence, and nothing that proves anything.
    static let leastBytes = 100_000_000.0
    /// The clock ran this much longer than the Mac was awake: it has slept.
    static let sleptAfter: TimeInterval = 30
    /// The first touch after the line came, and it's gone this much later.
    static let staysAfterTouch: TimeInterval = 4

    /// `awake…` is the system uptime, which stands still while the Mac sleeps and the clock doesn't: a real
    /// measure of whether it stayed awake, whichever order macOS sends its sleep notices in.
    nonisolated static func outcome(_ dark: Stretch, ended: Date, awakeAtEnd: TimeInterval, after: [String: Mark]) -> DownloadProof? {
        let wall = ended.timeIntervalSince(dark.began)
        guard wall >= shortestDark, wall - (awakeAtEnd - dark.awakeAtStart) < sleptAfter else { return nil }
        var fetched = 0.0
        var amountUnknown = false
        var moved: [Mark] = []
        // Sorted, so that which game is named doesn't depend on the dictionary's order.
        for id in after.keys.sorted() {
            guard let now = after[id], let was = dark.before[id], let reached = now.fraction else { continue }
            let from = was.fraction ?? 0  // "preparing": nothing fetched yet
            guard reached > from else { continue }
            moved.append(now)
            if now.size > 0 { fetched += (reached - from) * Double(now.size) } else { amountUnknown = true }
        }
        let bytes = fetched >= leastBytes ? Int64(fetched) : nil
        guard let first = moved.first, bytes != nil || amountUnknown else { return nil }
        if moved.count > 1 { return DownloadProof(kind: .severalRanOn, bytes: bytes) }
        return DownloadProof(kind: first.finished ? .finished(first.name) : .ranOn, bytes: bytes)
    }

    /// The downloads listed now, for the start of a dark stretch.
    nonisolated static func marks(of games: [Game]) -> [String: Mark] {
        var marks: [String: Mark] = [:]
        for game in games {
            guard case .downloading(let fraction) = game.install else { continue }
            marks[game.id] = Mark(name: game.name, fraction: fraction, size: game.sizeOnDisk)
        }
        return marks
    }

    /// The same downloads afterwards: on their way still, or installed now.
    nonisolated static func marks(after dark: Stretch, games: [Game]) -> [String: Mark] {
        var marks = Self.marks(of: games)
        for game in games where game.isInstalled {
            // The size that came down (`sizeOnDisk` means it only while a game downloads).
            guard let was = dark.before[game.id] else { continue }
            marks[game.id] = Mark(name: game.name, fraction: 1, size: was.size, finished: true)
        }
        return marks
    }

    enum Moment: Equatable {
        case show, wait, drop
    }

    /// A game on the way or on screen ends it for good: at a start every message is one too many. A locked Mac
    /// or Nightforge behind another app waits, or the line would be up with nobody there to see it.
    nonisolated static func moment(gameOn: Bool, curtain: Bool, overlay: Bool, firstStart: Bool, locked: Bool, inFront: Bool) -> Moment {
        if gameOn || curtain || overlay { return .drop }
        return locked || !inFront || firstStart ? .wait : .show
    }

    /// Someone touched something since the line came up. What brought the screen back was before that.
    nonisolated static func touched(idle: TimeInterval, shownFor: TimeInterval) -> Bool { idle < shownFor }

    var amount: String? { bytes.map(Format.bytes) }

    var message: String {
        switch (kind, amount) {
        case (.ranOn, let amount?): return L10n.t("The download kept going: %@ while the display was off.", amount)
        case (.ranOn, nil): return L10n.t("The download kept going while the display was off.")
        case (.severalRanOn, let amount?): return L10n.t("The downloads kept going: %@ while the display was off.", amount)
        case (.severalRanOn, nil): return L10n.t("The downloads kept going while the display was off.")
        case (.finished(let name), let amount?): return L10n.t("%@ finished: %@ while the display was off.", name, amount)
        case (.finished(let name), nil): return L10n.t("%@ finished while the display was off.", name)
        }
    }
}

/// Follows the screen going dark and coming back, and keeps the proof line until someone has seen it.
@MainActor
final class DarkWatch: ObservableObject {
    static let shared = DarkWatch()

    @Published private(set) var line: DownloadProof?
    private var stretch: DownloadProof.Stretch?
    private var waiting: DownloadProof?
    private var lineWatch: Task<Void, Never>?
    private weak var model: LibraryModel?

    func begin(with model: LibraryModel) {
        self.model = model
        let workspace = NSWorkspace.shared.notificationCenter
        _ = workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wentDark() }
        }
        _ = workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameBack() }
        }
        _ = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.offer(unlocked: true) }
        }
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.offer() }
        }
    }

    private func wentDark() {
        guard stretch == nil, let model else { return }
        let before = DownloadProof.marks(of: model.allGames)
        guard !before.isEmpty else { return }
        stretch = DownloadProof.Stretch(began: Date(), awakeAtStart: ProcessInfo.processInfo.systemUptime, before: before)
    }

    private func cameBack() {
        guard let dark = stretch else { return }
        stretch = nil
        let ended = Date()
        let awakeAtEnd = ProcessInfo.processInfo.systemUptime
        Task { [weak self] in
            // A fresh look: what the last one saw can be old, and a download done meanwhile needs a whole scan.
            await self?.model?.scanInLine()
            guard let self, let model = self.model else { return }
            let after = DownloadProof.marks(after: dark, games: model.allGames)
            let proof = DownloadProof.outcome(dark, ended: ended, awakeAtEnd: awakeAtEnd, after: after)
            GameLog.note("Screen back after \(Int(ended.timeIntervalSince(dark.began))) s: \(proof == nil ? "no download proof" : "download proof ready")")
            guard let proof else { return }
            self.waiting = proof
            self.offer()
        }
    }

    private func moment(unlocked: Bool = false) -> DownloadProof.Moment {
        guard let model else { return .drop }
        return DownloadProof.moment(gameOn: model.gameOnScreen, curtain: GameBackdrop.isRaised, overlay: GameOverlay.isOpen,
                                    firstStart: model.showsFirstStart, locked: !unlocked && Self.screenLocked, inFront: NSApp.isActive)
    }

    private static var screenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    private func offer(unlocked: Bool = false) {
        guard let proof = waiting else { return }
        switch moment(unlocked: unlocked) {
        case .wait: return
        case .drop: waiting = nil
        case .show:
            waiting = nil
            show(proof)
        }
    }

    /// The regular look of the main loop: a proof still waiting goes when a game comes, not to appear after it.
    func look() {
        if waiting != nil, moment(unlocked: true) == .drop { waiting = nil }
    }

    private func show(_ proof: DownloadProof) {
        line = proof
        if let window = NSApp.mainWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: proof.message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        lineWatch?.cancel()
        let shown = ProcessInfo.processInfo.systemUptime
        lineWatch = Task { [weak self] in
            var touchedAt: TimeInterval?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if self.moment(unlocked: true) == .drop { self.line = nil; return }  // the lock doesn't matter for that
                if touchedAt == nil {
                    // Only looks at when something was last touched: the line can't take a key from anyone.
                    let idle = InputRouter.secondsSinceUse
                    if DownloadProof.touched(idle: idle, shownFor: now - shown) { touchedAt = now - idle }
                }
                if let touchedAt, now - touchedAt >= DownloadProof.staysAfterTouch { self.line = nil; return }
            }
        }
    }
}

/// The proof, where the Downloads panel opens: stays until someone touches something. No button and no
/// place for the highlight, so nothing to reach or to press away, and it's not there at a game's start.
struct DarkProofLine: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var watch = DarkWatch.shared
    @ObservedObject private var tv = TVLayout.shared
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let proof = watch.line, !model.gameOnScreen, !model.showingDownloads {
                line(proof)
                    .padding(.top, Theme.margins.top + 48)  // below the top bar, under the ring
                    .padding(.trailing, Theme.gutter)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: watch.line)
    }

    private func line(_ proof: DownloadProof) -> some View {
        // As wide as the sentence; only in a window too narrow for that (a long game name) it wraps.
        ViewThatFits(in: .horizontal) {
            box(proof, oneLine: true)
            box(proof, oneLine: false)
        }
    }

    private func box(_ proof: DownloadProof, oneLine: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "sun.max")
                .foregroundStyle(Theme.sodium)
            Text(Self.styled(proof.message, amount: proof.amount))
                .lineLimit(oneLine ? 1 : 3)
                .fixedSize(horizontal: oneLine, vertical: true)
                .frame(maxWidth: oneLine ? nil : .infinity, alignment: .leading)
        }
        // On a TV it has to be read from the sofa: the size of the TV board's text.
        .font(size: tv.isOn ? 24 : 14, weight: .semibold, scales: !tv.isOn)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: oneLine ? nil : (tv.isOn ? 900 : 460))
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .environment(\.colorScheme, .dark)
    }

    private static func styled(_ message: String, amount: String?) -> AttributedString {
        var text = AttributedString(message)
        if let amount, let range = text.range(of: amount) {
            text[range].foregroundColor = Theme.sodium
        }
        return text
    }
}
