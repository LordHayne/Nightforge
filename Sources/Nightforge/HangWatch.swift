import AppKit
import CoreAudio
import Darwin

/// Stage 1 of noticing a hung game (docs/ENTWURF-HAENGER.md): only behind the hidden test switch `gameTest.hangWatch`
/// (GameTest.watchesHangs), every look of the running-games loop takes a sample of each running game from outside
/// (HangRule.Sample) and writes one line to wine.log when HangRule calls it hung, and one when it moves again. No surface,
/// nothing loaded into or asked of the game's process – the same for games with an anti-cheat.
@MainActor
final class HangWatch {
    private struct Watched {
        var samples: [HangRule.Sample] = []
        var verdict: HangRule.Verdict = .unknown
        /// When it was first seen running: its start, for a game Nightforge didn't start itself.
        var firstSeen = Date()
        /// The process the samples are of: a new one (the game started again, a launcher handed over) starts afresh,
        /// as its counters start at nought.
        var pid: pid_t = 0
    }

    private var watched: [String: Watched] = [:]
    /// Enough looks for the longest limit and some (a look every ~3 s).
    private let kept = 60

    /// `games`: the running games by ID with their process, name, start (nil: when first seen) and whether it's their
    /// first start here.
    func look(_ games: [String: (pid: pid_t, name: String, started: Date?, firstStart: Bool)]) async {
        watched = watched.filter { games[$0.key] != nil }
        guard !games.isEmpty else { return }
        let paused = GameOverlay.mayHoldGame
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = games.mapValues(\.pid)
        let taken = await Task.detached(priority: .utility) { () -> [String: HangRule.Sample] in
            let now = Date().timeIntervalSince1970
            let shown = Self.shownWindowOwners()
            return pids.compactMapValues { pid in
                guard let usage = Self.usage(pid) else { return nil }
                return HangRule.Sample(at: now, cpu: usage.cpu, read: usage.read, sound: Self.playsSound(pid),
                                       shown: shown.contains(pid), front: front == pid, paused: paused)
            }
        }.value
        for (id, sample) in taken {
            guard let game = games[id] else { continue }
            var entry = watched[id] ?? Watched()
            if entry.pid != game.pid { entry = Watched(pid: game.pid) }
            entry.samples.append(sample)
            if entry.samples.count > kept { entry.samples.removeFirst(entry.samples.count - kept) }
            let started = (game.started ?? entry.firstSeen).timeIntervalSince1970
            let verdict = HangRule.judge(entry.samples, started: started, firstStart: game.firstStart)
            if let line = Self.line(game.name, change: HangRule.change(from: entry.verdict, to: verdict), samples: entry.samples) {
                GameLog.note(line)
            }
            entry.verdict = HangRule.remembered(old: entry.verdict, new: verdict)
            watched[id] = entry
        }
    }

    /// The line for wine.log, by name and numbers only. Nil when nothing changed worth one.
    nonisolated static func line(_ name: String, change: HangRule.Change?, samples: [HangRule.Sample]) -> String? {
        guard let change, let last = samples.last else { return nil }
        switch change {
        case .hangs(let since):
            let first = samples.first { $0.at >= since } ?? last
            let seconds = max(1, last.at - first.at)
            let cpu = max(0, last.cpu - first.cpu) / seconds * 100
            let read = Double(last.read >= first.read ? last.read - first.read : 0) / seconds / 1024
            let sound = last.sound.map { $0 ? "yes" : "no" } ?? "unknown"
            return "Hang watch: \(name) quiet in front for \(Int(last.at - since)) s (CPU "
                + String(format: "%.1f", cpu) + " %, reads " + String(format: "%.0f", read)
                + " KB/s, sound \(sound)): would offer Quit Game"
        case .movesAgain(let since):
            return "Hang watch: \(name) moves again after \(Int(last.at - since)) s"
        }
    }

    /// CPU time (user and system, seconds) and bytes read of `pid`, from the kernel's accounting; nil when it can't be read.
    nonisolated static func usage(_ pid: pid_t) -> (cpu: TimeInterval, read: UInt64)? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        let seconds = ticks * Double(base.numer) / Double(base.denom) / 1e9
        return (seconds, info.ri_diskio_bytesread)
    }

    /// Whether `pid` plays sound now (Core Audio's process objects, macOS 14); nil when Core Audio doesn't know it.
    nonisolated static func playsSound(_ pid: pid_t) -> Bool? {
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var asked = pid
        let found = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                               UInt32(MemoryLayout<pid_t>.size), &asked, &size, &process)
        guard found == noErr, process != kAudioObjectUnknown else { return nil }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioProcessPropertyIsRunningOutput
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr else { return nil }
        return running != 0
    }

    /// The processes with a window of at least 200 × 200 on the screen: a normal one, or one on the shielding level, where
    /// a game that captured the display draws (Overwatch's at L2147483628, docs/TODO.md).
    nonisolated static func shownWindowOwners() -> Set<pid_t> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return shownOwners(windows)
    }

    nonisolated static func shownOwners(_ windows: [[String: Any]]) -> Set<pid_t> {
        Set(windows.compactMap { window -> pid_t? in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 || layer == Int(CGShieldingWindowLevel()),
                  let owner = (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 200, height >= 200 else { return nil }
            return owner
        })
    }
}
