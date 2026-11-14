import Foundation

/// What a game test measures of a picture while the game plays on (`playSeconds`): the frame rates and
/// slowest frames its layer logged, the size it drew at, the limit it was held to – for the list of games
/// that run (docs/LAEUFT-LISTE.md, scripts/laeuft-liste.py). Only what something reports: DXMT and
/// Nightforge's Vulkan layer log frames; D3DMetal, Wine's own Direct3D, DXVK on MoltenVK under winecx and
/// Mac versions log none, and then the report says "not measured" instead of a number. No way reports the
/// slowest 1 % of frames: a period's line carries its one slowest frame.
extension GameTest {
    /// One period a layer logged:
    /// "[nightforge-dxmt] Game: 58.2 FPS over 10 s, frames 17.2 ms on average, slowest 76 ms".
    struct Period: Equatable {
        var fps: Double
        var seconds: Double
        /// The slowest single frame in it, in milliseconds; nil where the line doesn't say.
        var slowest: Double?
        /// The layer that logged it: "dxmt", "vulkan".
        var source: String
    }

    /// Every period the given programs logged (as FramePacing.periods reads them), with the slowest frame
    /// and the layer's name.
    static func periods(in log: String, programs: Set<String>) -> [Period] {
        let names = Set(programs.map(programName))
        var periods: [Period] = []
        for line in log.split(whereSeparator: \.isNewline) {
            guard let open = line.range(of: "[nightforge-"),
                  let close = line.range(of: "] ", range: open.upperBound..<line.endIndex),
                  let colon = line.range(of: ": ", range: close.upperBound..<line.endIndex),
                  names.contains(programName(String(line[close.upperBound..<colon.lowerBound])))
            else { continue }
            let fields = line[colon.upperBound...].split(separator: " ")
            guard fields.count >= 5, fields[1] == "FPS", fields[2] == "over",
                  let fps = Double(fields[0]), let seconds = Double(fields[3])
            else { continue }
            var slowest: Double?
            if let index = fields.firstIndex(of: "slowest"), fields.indices.contains(index + 1) { slowest = Double(fields[index + 1]) }
            periods.append(Period(fps: fps, seconds: seconds, slowest: slowest, source: String(line[open.upperBound..<close.lowerBound])))
        }
        return periods
    }

    private static func programName(_ program: String) -> String {
        let lower = program.lowercased()
        return lower.hasSuffix(".exe") ? String(lower.dropLast(4)) : lower
    }

    /// The frame rates with what the periods say beyond them: how long they cover, the slowest frame of all
    /// (a loading hitch counts), the slowest frame of a usual period (the median of the periods' slowest),
    /// and who logged them.
    static func measuredFrames(_ periods: [Period]) -> Frames? {
        let periods = periods.filter { $0.fps > 0 && $0.seconds > 0 }
        guard var frames = frames(periods.map { (fps: $0.fps, seconds: $0.seconds) }) else { return nil }
        frames.seconds = periods.map(\.seconds).reduce(0, +)
        let slowest = periods.compactMap(\.slowest).sorted()
        if !slowest.isEmpty {
            frames.slowestFrame = slowest[slowest.count - 1]
            frames.slowestTypical = slowest[(slowest.count - 1) / 2]
        }
        frames.source = Set(periods.map(\.source)).sorted().joined(separator: "+")
        return frames
    }

    /// The conditions and sizes a picture's numbers hold for.
    struct Measure: Codable, Equatable {
        /// The game's window when the curtain sank and the screen it stood on, in points ("1512×982") –
        /// not what was drawn: Retina and MetalFX lie between.
        var window: String?
        var screen: String?
        /// What Nightforge's Vulkan layer drew at, in pixels, and what MetalFX scaled that to.
        var swapchain: String?
        var upscaledTo: String?
        /// The display mode the game set, as DXMT logs it ("1512×982@120").
        var displayMode: String?
        /// The frame limit the start was held to (0: none), the screen's refresh rate, MetalFX on for it.
        var frameLimit: Int?
        var refreshRate: Int?
        var metalFX: Bool?
        /// Why a picture has no frame rates (`NoFrames`).
        var noFrames: String?
    }

    /// What a start was held to, worked out as LibraryModel.launch does (GameTestRun.held).
    struct Held: Equatable {
        var frameLimit: Int
        var refreshRate: Int
        var metalFX: Bool
    }

    /// Why a picture has no frame rates: its way reports none (D3DMetal, Wine's own Direct3D, a Mac
    /// version), or one that does logged none (DXMT; DXVK, whose frames come from Nightforge's Vulkan
    /// layer – under winecx only where KosmicKrisp draws).
    enum NoFrames: String {
        case wayReportsNone, noneInLog

        var german: String {
            self == .wayReportsNone ? "der Weg meldet keine" : "keine im Log"
        }
    }

    static func noFrames(way: String?) -> NoFrames {
        let layer = way?.split(separator: " ").first.map(String.init) ?? ""
        return ["d3dmetal", "wined3d", "mac"].contains(layer) ? .wayReportsNone : .noneInLog
    }

    /// "1512x982" or "1512×982" as "1512×982"; nil for anything else.
    private static func size(_ text: Substring) -> String? {
        let parts = text.split(whereSeparator: { $0 == "x" || $0 == "×" })
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    /// The game's window and the screen when the curtain sank for it (LibraryModel.watchCurtain):
    /// "Curtain down for <game>: <app> in front, its window 1512×982 on 1512×982". The last one counts.
    static func pictureSize(of game: String, in log: String) -> (window: String?, screen: String)? {
        let marker = "Curtain down for \(game): "
        var found: (window: String?, screen: String)?
        for line in log.split(whereSeparator: \.isNewline) {
            guard let start = line.range(of: marker), let its = line.range(of: ", its window ", range: start.upperBound..<line.endIndex),
                  let on = line.range(of: " on ", range: its.upperBound..<line.endIndex), let screen = size(line[on.upperBound...])
            else { continue }
            found = (size(line[its.upperBound..<on.lowerBound]), screen)
        }
        return found
    }

    /// The Vulkan layer's last swapchain: "[nightforge-vulkan] swapchain 1280x720 format 44 colour space 0,
    /// MetalFX to 2560x1440".
    static func swapchain(in log: String) -> (size: String, upscaledTo: String?)? {
        var found: (size: String, upscaledTo: String?)?
        for line in log.split(whereSeparator: \.isNewline) {
            guard let start = line.range(of: "[nightforge-vulkan] swapchain "),
                  let first = line[start.upperBound...].split(separator: " ").first, let drawn = size(first)
            else { continue }
            let to = line.range(of: ", MetalFX to ").flatMap { size(line[$0.upperBound...]) }
            found = (drawn, to)
        }
        return found
    }

    /// The last display mode the game set under DXMT: "Setting display mode: 1512x982@120".
    static func displayMode(in log: String) -> String? {
        var found: String?
        for line in log.split(whereSeparator: \.isNewline) {
            guard let start = line.range(of: "Setting display mode: ") else { continue }
            let parts = line[start.upperBound...].split(separator: "@")
            guard let first = parts.first, let mode = size(first) else { continue }
            found = parts.count == 2 && Int(parts[1]) != nil ? "\(mode)@\(parts[1])" : mode
        }
        return found
    }

    /// What holds for a picture's numbers, from the start's stretch of the log and what it was held to.
    static func measure(of game: String, way: String?, in log: String, frames: Frames?, held: Held?) -> Measure {
        var measure = Measure()
        if let picture = pictureSize(of: game, in: log) {
            measure.window = picture.window
            measure.screen = picture.screen
        }
        if let drawn = swapchain(in: log) {
            measure.swapchain = drawn.size
            measure.upscaledTo = drawn.upscaledTo
        }
        if way?.hasPrefix("dxmt") == true { measure.displayMode = displayMode(in: log) }
        measure.frameLimit = held?.frameLimit
        measure.refreshRate = held?.refreshRate
        measure.metalFX = held?.metalFX
        if frames == nil { measure.noFrames = noFrames(way: way).rawValue }
        return measure
    }

    // MARK: - In the German summary

    /// The frame rates' cell: "58 / 41", or why there are none.
    static func framesText(_ entry: Entry) -> String {
        if let frames = entry.frames {
            return "\(Int(frames.average.rounded())) / \(Int(frames.low.rounded()))" + (entry.load?.low == false ? " (Last hoch)" : "")
        }
        guard entry.outcome == .picture else { return "–" }
        let way = entry.way ?? ""
        if way.hasPrefix("d3dmetal") { return "nicht gemessen (D3DMetal meldet keine)" }
        if way == "mac" { return "nicht gemessen (Mac-Fassung meldet keine)" }
        if way.hasPrefix("wined3d") { return "nicht gemessen (WineD3D meldet keine)" }
        return "nicht gemessen (keine im Log)"
    }

    /// "## Messwerte": one row per game with a picture – the limit, the size, the frames – and what the
    /// numbers stand for. Empty without a picture.
    static func measures(_ report: Report) -> [String] {
        let pictures = report.games.filter { $0.outcome == .picture }
        guard !pictures.isEmpty else { return [] }
        var lines = ["## Messwerte", "",
                     "Vom ersten Frame bis zum Ende des Spielfensters (\(Int(report.playSeconds)) s nach dem ersten Bild), mit den Einstellungen, "
                     + "die das Spiel mitbringt. Keine feste Szene: meist Intro, Menü oder die ersten Sekunden im Spiel. "
                     + "Das 1-%-Tief meldet kein Weg; „langsamster Frame“ ist der eine langsamste je Messperiode."]
        if report.onBattery == true || report.lowPower == true {
            let how = [report.onBattery == true ? "auf Akku" : nil, report.lowPower == true ? "im Stromsparmodus" : nil].compactMap { $0 }
            lines.append("Der Mac lief \(how.joined(separator: " und ")): Die Werte sind mit anderen Läufen nicht vergleichbar.")
        }
        lines += ["", "| Spiel | Weg | Frame-Limit | Größe | FPS Ø / tiefste Periode | Langsamster Frame |", "|---|---|---|---|---|---|"]
        for entry in pictures {
            let measure = entry.measure
            let limit = measure?.frameLimit.map { $0 > 0 ? "\($0) FPS" : "keins" } ?? "nicht gemessen"
            var frames = framesText(entry)
            if let seconds = entry.frames?.seconds { frames += " über \(Int(seconds)) s" }
            let cells = [entry.game.replacingOccurrences(of: "|", with: "\\|"), entry.way ?? "–", limit, sizeText(measure), frames, slowestText(entry.frames)]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")
        return lines
    }

    /// What it drew at where a layer says so, else the game's display mode, else its window.
    static func sizeText(_ measure: Measure?) -> String {
        if let drawn = measure?.swapchain {
            return "\(drawn) px" + (measure?.upscaledTo.map { ", MetalFX auf \($0)" } ?? "")
        }
        if let mode = measure?.displayMode { return "\(mode) (Modus des Spiels)" }
        if let window = measure?.window { return "Fenster \(window) Punkte" }
        return "nicht gemessen"
    }

    static func slowestText(_ frames: Frames?) -> String {
        guard let frames, let worst = frames.slowestFrame else { return "nicht gemessen" }
        let usual = frames.slowestTypical.map { "üblich \(Int($0.rounded())) ms, " } ?? ""
        return "\(usual)schlimmster \(Int(worst.rounded())) ms"
    }
}
