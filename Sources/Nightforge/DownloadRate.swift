import Foundation

/// How fast a download goes and how long it still takes. Steam has no queue to ask, so this comes
/// from the progress Nightforge reads from the appmanifest every few seconds.
struct DownloadRate: Equatable {
    struct Sample: Equatable {
        let date: Date
        let bytes: Double
    }

    /// The last half minute: long enough to even out Steam's bursts, short enough to follow a change.
    static let window: TimeInterval = 30
    /// Shorter than this says nothing yet.
    static let minimumSpan: TimeInterval = 6

    private(set) var samples: [Sample] = []

    mutating func add(bytes: Double, at date: Date = Date()) {
        // A look with no newer measurement than the last (StagingSizes) adds nothing.
        if let last = samples.last, date <= last.date { return }
        // Less than before: the download started over (another depot, a verify).
        if let last = samples.last, bytes < last.bytes { samples.removeAll() }
        samples.append(Sample(date: date, bytes: bytes))
        samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
    }

    /// Bytes per second, nil until two looks far enough apart show progress.
    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= Self.minimumSpan, last.bytes > first.bytes else { return nil }
        return (last.bytes - first.bytes) / span
    }

    /// Seconds until `total` bytes are there at the current speed.
    func secondsLeft(total: Double) -> Double? {
        guard let rate = bytesPerSecond, let last = samples.last, total > last.bytes else { return nil }
        return (total - last.bytes) / rate
    }

    /// "12.4 MB/s · 25 min left" – nil while there's nothing to say.
    func label(total: Double) -> String? {
        guard let rate = bytesPerSecond else { return nil }
        let speed = Format.bytes(Int64(rate)) + "/s"
        guard let seconds = secondsLeft(total: total) else { return speed }
        return L10n.t("%@ · %@ left", speed, Self.duration(seconds))
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return L10n.t("under a minute") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        formatter.calendar = calendar
        // Whole minutes, rounded up: "1 min" rather than "0 min" for 59 s more.
        return formatter.string(from: (seconds / 60).rounded(.up) * 60) ?? ""
    }
}
