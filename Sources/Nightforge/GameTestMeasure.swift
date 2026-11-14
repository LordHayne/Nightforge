import Foundation

/// What a game test measures of a picture while the game plays on (`playSeconds`): the frame rates and
/// slowest frames its layer logged, the size it drew at, the limit it was held to – for the list of games
/// that run (docs/LAEUFT-LISTE.md, scripts/laeuft-liste.py). Only what something reports: Apple's Metal
/// HUD logs every frame of whatever presents through a Metal layer, and a game test's starts have it on
/// (Engine.setFrameLog); DXMT and Nightforge's Vulkan layer log periods of their own. Wine's own Direct3D
/// draws with OpenGL, which the HUD doesn't see: it says its frame rate itself where Wine's fps channel is on
/// (`wineRates`, `wineFrames`), and neither its slowest frames nor the slowest percent. A Mac version isn't started with
/// the HUD's logging: there the report says "not measured" instead of a number. Only the HUD gives the slowest
/// 1 % of frames: a layer's period carries its one slowest frame.
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
        /// The limit was lower than Nightforge's own for this screen because of the power: "battery" (the
        /// battery's 30 FPS) or "lowPower" (Low Power Mode). Such a number isn't one for a public list.
        var throttled: String?
        /// Why a picture has no frame rates (`NoFrames`).
        var noFrames: String?
    }

    /// What a start was held to, as LibraryModel.launch says it in the log (`limitNote`).
    struct Held: Equatable {
        var frameLimit: Int
        var refreshRate: Int
        var metalFX: Bool
        var throttled: String?
    }

    /// What a start is held to, for the log – a line per start, so that a frame rate under a limit ("holds
    /// 60 FPS") is told from a free one by what the start had, not by working it out afterwards:
    /// "Frame limit of <game>: 60 FPS at 120 Hz, MetalFX off" ·
    /// "Frame limit of <game>: none at 120 Hz, MetalFX on, throttled by battery".
    static func limitNote(game: String, _ held: Held) -> String {
        "Frame limit of \(game): \(held.frameLimit > 0 ? "\(held.frameLimit) FPS" : "none") at \(held.refreshRate) Hz, "
            + "MetalFX \(held.metalFX ? "on" : "off")" + (held.throttled.map { ", throttled by \($0)" } ?? "")
    }

    /// The game's last `limitNote` in a stretch of the log; nil where there's none or it doesn't read.
    static func held(of game: String, in log: String) -> Held? {
        let marker = "Frame limit of \(game): "
        var found: Held?
        for line in log.split(whereSeparator: \.isNewline) {
            guard let start = line.range(of: marker) else { continue }
            let parts = line[start.upperBound...].components(separatedBy: ", ")
            let words = parts[0].split(separator: " ")
            guard parts.count >= 2, parts[1] == "MetalFX on" || parts[1] == "MetalFX off",
                  let at = words.firstIndex(of: "at"), words.indices.contains(at + 1), let rate = Int(words[at + 1]), rate > 0,
                  let limit = words[0] == "none" ? 0 : Int(words[0]), limit >= 0
            else { continue }
            let throttled = parts.dropFirst(2).first { $0.hasPrefix("throttled by ") }.map { String($0.dropFirst("throttled by ".count)) }
            found = Held(frameLimit: limit, refreshRate: rate, metalFX: parts[1] == "MetalFX on", throttled: throttled)
        }
        return found
    }

    /// Why a picture has no frame rates: its way reports none, or one that does logged none. Which ways
    /// report hangs on the HUD's frame log (`frameLog`, Engine.setFrameLog): with it, all that present through
    /// Metal – D3DMetal and DXVK on MoltenVK too – and not Wine's own Direct3D (OpenGL) or a Mac version;
    /// without it, DXMT and DXVK only (DXVK's frames come from Nightforge's Vulkan layer, under winecx only
    /// where KosmicKrisp draws). Wine's own Direct3D reports with Wine's fps channel on (`wineFps`).
    enum NoFrames: String {
        case wayReportsNone, noneInLog

        var german: String {
            self == .wayReportsNone ? "der Weg meldet keine" : "keine im Log"
        }
    }

    static func noFrames(way: String?, frameLog: Bool = false, wineFps: Bool = false) -> NoFrames {
        let layer = way?.split(separator: " ").first.map(String.init) ?? ""
        var silent: Set<String> = ["mac"]
        if !frameLog { silent.insert("d3dmetal") }
        if !wineFps { silent.insert("wined3d") }
        return silent.contains(layer) ? .wayReportsNone : .noneInLog
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
    static func measure(of game: String, way: String?, in log: String, frames: Frames?, held: Held?, frameLog: Bool = false,
                        wineFps: Bool = false) -> Measure {
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
        measure.throttled = held?.throttled
        if frames == nil { measure.noFrames = noFrames(way: way, frameLog: frameLog, wineFps: wineFps).rawValue }
        return measure
    }

    // MARK: - Wine's fps channel

    /// What Wine's own Direct3D says of its frame rate with the debug channel `fps` on (WINEDEBUG=+fps): every
    /// time a swapchain presents and more than 1.5 s have passed since its last line,
    /// "0124:trace:fps:wined3d_cs_exec_present 00000000012A3B40 @ approx 59.94fps" – the frames since then over
    /// the time since then (Wine 11.17, dlls/wined3d/cs.c: `1000.0 * swapchain->frames / (time -
    /// swapchain->prev_time)`, by GetTickCount). Before the thread stands the process with +pid ("0810:0124:…")
    /// and before that the same clock with +timestamp ("253517.239:0810:0124:…", dlls/ntdll/unix/debug.c). The
    /// process is Wine's own number, not the one macOS gives: whose it is, the loads of +loaddll say
    /// ("…:trace:loaddll:build_module Loaded L"C:\\…\\Game.exe" at …").
    struct WineRate: Equatable {
        var fps: Double
        /// The seconds it covers: the time since the swapchain's line before it where the lines carry a time,
        /// else the 1.5 s the channel waits at least.
        var seconds: Double
    }

    static let wineRateWindow = 1.5

    /// The game's rates in a stretch of the log: those of its own processes – by the program a process loaded
    /// (`programs`, the game's executables) – and of them the swapchain with the most lines. A process known to
    /// be another program's (Steam's windows) never counts. Where no load says whose a process is (no +pid, no
    /// +loaddll), it's the process and swapchain with the most lines. A process is a pid from one program's load
    /// to the next: Wine hands a pid out again (CloserLook.read). A swapchain's first line is left out: its
    /// count begins at Wine's start, not at a line before it. Whatever function Wine names in the line, it's
    /// read by its channel and its text.
    static func wineRates(in log: String, programs: Set<String>) -> [WineRate] {
        let names = Set(programs.map(programName))
        var instance: [Substring: Int] = [:], instances = 0
        var ownerKnown: [Int: Bool] = [:]  // the process's program is one of the game's
        struct Chain { var rates: [WineRate] = []; var lastTime: Double?; var lines = 0 }
        var chains: [String: Chain] = [:], order: [String] = [], processOf: [String: Int?] = [:]
        for raw in log.split(whereSeparator: \.isNewline) {
            guard let line = CloserLook.Line(raw) else { continue }
            if line.channel == "loaddll" {
                guard let pid = line.pid, line.text.hasPrefix("Loaded "), let open = line.text.firstIndex(of: "\""),
                      let close = line.text[line.text.index(after: open)...].firstIndex(of: "\"")
                else { continue }
                let path = line.text[line.text.index(after: open)..<close].lowercased()
                guard path.hasSuffix(".exe") else { continue }
                let program = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path
                instances += 1
                instance[pid] = instances
                ownerKnown[instances] = names.contains(programName(program))
                continue
            }
            guard line.channel == "fps", let at = line.text.range(of: " @ approx "), line.text.hasSuffix("fps"),
                  let fps = Double(line.text[at.upperBound...].dropLast(3)), fps >= 0
            else { continue }
            let process = line.pid.flatMap { instance[$0] }
            // One swapchain of one process: its pointer, and the process as far as the line says it.
            let key = "\(process.map(String.init) ?? line.pid.map(String.init) ?? "-") \(line.text[..<at.lowerBound])"
            if chains[key] == nil {
                order.append(key)
                processOf[key] = process
            }
            var chain = chains[key] ?? Chain()
            let time = wineTime(raw)
            if chain.lines > 0, fps > 0 {
                let seconds = time.flatMap { now in chain.lastTime.map { now - $0 } }.flatMap { $0 > 0 ? $0 : nil } ?? wineRateWindow
                chain.rates.append(WineRate(fps: fps, seconds: seconds))
            }
            chain.lines += 1
            chain.lastTime = time ?? chain.lastTime
            chains[key] = chain
        }
        func owned(_ key: String) -> Bool? { (processOf[key] ?? nil).flatMap { ownerKnown[$0] } }
        let own = order.filter { owned($0) == true }
        let pool = own.isEmpty ? order.filter { owned($0) == nil } : own
        // The most lines; the earlier one where two have as many.
        var best: String?
        for key in pool where (chains[key]?.rates.count ?? 0) > (best.flatMap { chains[$0]?.rates.count } ?? 0) { best = key }
        return best.flatMap { chains[$0]?.rates } ?? []
    }

    /// The seconds a line begins with under +timestamp ("253517.239:0810:…", "%3u.%03u:"), nil without.
    private static func wineTime(_ line: Substring) -> Double? {
        let line = line.drop { $0 == " " }
        guard let colon = line.firstIndex(of: ":"), line[..<colon].contains("."),
              line[..<colon].allSatisfy({ $0.isNumber || $0 == "." })
        else { return nil }
        return Double(line[..<colon])
    }

    /// Wine's rates in the report's shape: the average over all of them by the time each covers, and the
    /// lowest stretch of ten seconds as the layers' periods and the HUD's frames give it (a last stretch
    /// shorter than that is left out). No slowest frame and no slowest percent: the channel says a rate, not
    /// its frames.
    static func wineFrames(_ rates: [WineRate]) -> Frames? {
        let rates = rates.filter { $0.fps > 0 && $0.seconds > 0 }
        guard !rates.isEmpty else { return nil }
        var stretches: [(fps: Double, seconds: Double)] = []
        var count = 0.0, time = 0.0
        for rate in rates {
            count += rate.fps * rate.seconds
            time += rate.seconds
            if time >= 10 {
                stretches.append((count / time, time))
                (count, time) = (0, 0)
            }
        }
        if stretches.isEmpty { stretches.append((count / time, time)) }
        guard var frames = frames(stretches) else { return nil }
        let seconds = rates.map(\.seconds).reduce(0, +)
        frames.average = (rates.map { $0.fps * $0.seconds }.reduce(0, +) / seconds * 10).rounded() / 10
        frames.seconds = (seconds * 10).rounded() / 10
        frames.source = "wine-fps"
        return frames
    }

    // MARK: - Apple's Metal HUD

    /// The frames Apple's Metal Performance HUD logged while its logging was on (MTL_HUD_ENABLED=1 with
    /// MTL_HUD_LOG_ENABLED=1, or ⌘F8 in the game's menu) – once a second
    /// "metal-HUD: <first frame>,<graphics memory>,<process memory>,<present interval>,<GPU time>,…", a pair
    /// per frame (Apple, "Monitoring your Metal app's graphics performance"; the unit isn't named there, the
    /// log shows milliseconds: 16.67 at 60 FPS). Wine's process writes it to wine.log:
    /// "… wine[18259:1984832] metal-HUD: 48,335.58,3079.71,139.45,4.70,16.67,4.58" (Overwatch on DXMT, 7.11.2026).
    /// It's the one count that doesn't hang on the layer: whatever draws through Metal can have it.
    struct HUDSample: Equatable {
        /// Each frame's present interval and GPU time in milliseconds, in the log's order.
        var intervals: [Double]
        var gpuTimes: [Double]
    }

    /// The frames of the process that logged the most (the game; a launcher's window logs a few) – among
    /// `processes`, the game's own as the process list had them, where any of those logged: Steam's windows
    /// present through Metal too.
    static func hudSample(in log: String, processes: Set<Int32> = []) -> HUDSample? {
        var byProcess: [String: HUDSample] = [:]
        for line in log.split(whereSeparator: \.isNewline) {
            guard let marker = line.range(of: "metal-HUD: ") else { continue }
            let values = line[marker.upperBound...].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count >= 5, values.count % 2 == 1, !values.contains(nil) else { continue }
            // "wine[18259:1984832] ": the process's number, "" where the line has none.
            let before = line[..<marker.lowerBound]
            let process = before.range(of: "[", options: .backwards).map { before[$0.upperBound...].prefix { $0.isNumber } }.map(String.init) ?? ""
            var sample = byProcess[process] ?? HUDSample(intervals: [], gpuTimes: [])
            for index in stride(from: 3, to: values.count - 1, by: 2) {
                sample.intervals.append(values[index] ?? 0)
                sample.gpuTimes.append(values[index + 1] ?? 0)
            }
            byProcess[process] = sample
        }
        let own = byProcess.filter { Int32($0.key).map(processes.contains) == true }
        return (own.isEmpty ? byProcess : own).max { ($0.value.intervals.count, $1.key) < ($1.value.intervals.count, $0.key) }?.value
    }

    /// The HUD's frames in the report's shape: the average over all of them, the lowest stretch of ten
    /// seconds and its slowest frames (as the layers' periods are; a last stretch shorter than that is left
    /// out), and what only single frames give: the slowest percent and the GPU's time.
    static func measuredFrames(_ hud: HUDSample) -> Frames? {
        let intervals = hud.intervals.filter { $0 > 0 }
        let total = intervals.reduce(0, +)
        guard intervals.count >= 2, total > 0 else { return nil }
        func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        var rates: [Double] = [], slowest: [Double] = []
        var count = 0.0, time = 0.0, worst = 0.0
        for interval in intervals {
            count += 1
            time += interval
            worst = max(worst, interval)
            if time >= 10_000 {
                rates.append(count * 1000 / time)
                slowest.append(worst)
                (count, time, worst) = (0, 0, 0)
            }
        }
        if rates.isEmpty {
            rates.append(count * 1000 / time)
            slowest.append(worst)
        }
        let sorted = intervals.sorted()
        slowest.sort()
        var frames = Frames(average: tenth(Double(intervals.count) * 1000 / total), low: tenth(rates.min() ?? 0), periods: rates.count)
        frames.seconds = (total / 1000).rounded()
        frames.slowestFrame = tenth(sorted[sorted.count - 1])
        frames.slowestTypical = tenth(slowest[(slowest.count - 1) / 2])
        frames.onePercentLow = tenth(1000 / sorted[max(0, Int((Double(sorted.count) * 0.99).rounded(.up)) - 1)])
        let gpu = hud.gpuTimes.filter { $0 > 0 }.sorted()
        if !gpu.isEmpty { frames.gpuTime = tenth(gpu[(gpu.count - 1) / 2]) }
        frames.source = "metal-hud"
        return frames
    }

    // MARK: - Done with a game?

    /// What a run saw of the two things a game needs before it's done with ("fertig, darf weg",
    /// docs/LAEUFT-LISTE.md): a clean start and a frame rate that counts. "ok", or what is missing.
    struct Check: Codable, Equatable {
        /// ok · neededPlayer · noPicture · severalWays · endedByItself · tooShort
        var start: String
        /// ok · noPicture · wayReportsNone · noneInLog · throttled · loadHigh
        var fps: String

        var done: Bool { start == "ok" && fps == "ok" }
    }

    /// A clean start: a picture on the first and only way, not ended by itself, and working by LaunchHealth's
    /// own measure – frames counted, or `drawingWindow` (180 s) with the picture, which a run shorter than
    /// that can't have seen. A frame rate that counts: measured, on mains and out of Low Power Mode, with the
    /// Mac not busy. Nil for a game that wasn't started.
    static func check(_ entry: Entry, playSeconds: TimeInterval, onBattery: Bool, lowPower: Bool) -> Check? {
        guard entry.outcome != .skipped else { return nil }
        let picture = entry.outcome == .picture
        let start: String
        if entry.outcome == .needsPlayer {
            start = "neededPlayer"
        } else if !picture {
            start = "noPicture"
        } else if entry.ways.count > 1 {
            start = "severalWays"
        } else if entry.issues.contains("crashed") {
            start = "endedByItself"
        } else if entry.frames == nil, playSeconds < LaunchHealth.drawingWindow {
            start = "tooShort"
        } else {
            start = "ok"
        }
        let fps: String
        if !picture {
            fps = "noPicture"
        } else if entry.frames == nil {
            fps = entry.measure?.noFrames ?? noFrames(way: entry.way).rawValue
        } else if onBattery || lowPower || entry.measure?.throttled != nil {
            fps = "throttled"
        } else if entry.load?.low == false {
            fps = "loadHigh"
        } else {
            fps = "ok"
        }
        return Check(start: start, fps: fps)
    }

    static let checkWords: [String: String] = [
        "ok": "ja", "neededPlayer": "brauchte den Spieler", "noPicture": "kein Bild", "severalWays": "brauchte mehrere Wege",
        "endedByItself": "endete von selbst", "tooShort": "Bild, aber unter 180 s beobachtet und keine Frames gezählt",
        "wayReportsNone": "der Weg meldet keine", "noneInLog": "keine im Log", "throttled": "auf Akku oder gedrosselt gemessen",
        "loadHigh": "Last war hoch",
    ]

    /// The skips a run can't mend by itself or by waiting: someone has to look at the game by hand.
    static let byHand: Set<Skip> = [.antiCheat, .vrOnly, .otherBottle, .versionSwitch, .battleNet]

    /// "## Abhakliste": every installed game with its size and whether this run saw both – so a run over
    /// all of them ends with what is done and what is missing. Nothing is ever uninstalled from here.
    static func checklist(_ report: Report) -> [String] {
        guard !report.games.isEmpty else { return [] }
        func size(_ bytes: Int64?) -> String {
            bytes.map { String(format: "%.1f GB", Double($0) / 1_000_000_000).replacingOccurrences(of: ".", with: ",") } ?? "–"
        }
        var lines = ["## Abhakliste", "",
                     "Je geladenem Spiel, ob dieser Lauf einen sauberen Start (Bild auf dem ersten Weg, nicht von selbst beendet, "
                     + "Frames gezählt oder 180 s mit Bild) und einen FPS-Wert gesehen hat. Deinstalliert wird hier nie etwas.", "",
                     "| Spiel | Fassung | Größe | Start | FPS | Fazit |", "|---|---|---|---|---|---|"]
        var done: Int64 = 0, doneCount = 0
        for entry in report.games {
            var cells = [entry.game.replacingOccurrences(of: "|", with: "\\|"), entry.platform == "mac" ? "Mac" : "Windows", size(entry.sizeBytes)]
            if let check = entry.check {
                let start = checkWords[check.start] ?? check.start, fps = checkWords[check.fps] ?? check.fps
                cells += [start, fps, check.done ? "fertig" : "fehlt: " + [check.start == "ok" ? nil : "Start", check.fps == "ok" ? nil : "FPS"]
                    .compactMap { $0 }.joined(separator: ", ")]
                if check.done {
                    done += entry.sizeBytes ?? 0
                    doneCount += 1
                }
            } else {
                let why = entry.skip?.german ?? "nicht gestartet"
                cells += ["–", "–", entry.skip.map(byHand.contains) == true ? "von Hand zu prüfen: \(why)" : "nicht gestartet: \(why)"]
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines += ["", "Fertig in diesem Lauf: \(doneCount) von \(report.games.count) Spielen, zusammen \(size(done)).", ""]
        return lines
    }

    // MARK: - In the German summary

    /// The frame rates' cell: "58 / 41", or why there are none.
    static func framesText(_ entry: Entry) -> String {
        if let frames = entry.frames {
            return "\(Int(frames.average.rounded())) / \(Int(frames.low.rounded()))" + (entry.load?.low == false ? " (Last hoch)" : "")
        }
        guard entry.outcome == .picture else { return "–" }
        // With the HUD's frame log on, a way that presents through Metal had its chance (`noFrames`).
        if entry.measure?.noFrames == NoFrames.noneInLog.rawValue { return "nicht gemessen (keine im Log)" }
        let way = entry.way ?? ""
        if way.hasPrefix("d3dmetal") { return "nicht gemessen (D3DMetal meldet keine)" }
        if way == "mac" { return "nicht gemessen (Mac-Fassung meldet keine)" }
        if way.hasPrefix("wined3d") { return "nicht gemessen (WineD3D meldet keine ohne Wines fps-Kanal)" }
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
                     + "Das 1-%-Tief gibt es nur aus Apples Metal-HUD-Protokoll (jeder Frame einzeln); "
                     + "„langsamster Frame“ ist der eine langsamste je zehn Sekunden. WineD3D meldet über Wines fps-Kanal "
                     + "nur seine Bildrate (alle 1,5 s): Ø und tiefste zehn Sekunden, weder 1-%-Tief noch langsamsten Frame."]
        if report.onBattery == true || report.lowPower == true {
            let how = [report.onBattery == true ? "auf Akku" : nil, report.lowPower == true ? "im Stromsparmodus" : nil].compactMap { $0 }
            lines.append("Der Mac lief \(how.joined(separator: " und ")): Die Werte sind mit anderen Läufen nicht vergleichbar.")
        }
        lines += ["", "| Spiel | Weg | Frame-Limit | Größe | FPS Ø / tiefste Periode | 1-%-Tief | Langsamster Frame |", "|---|---|---|---|---|---|---|"]
        for entry in pictures {
            let measure = entry.measure
            let limit = measure?.frameLimit.map { $0 > 0 ? "\($0) FPS" : "keins" } ?? "nicht gemessen"
            var frames = framesText(entry)
            if let seconds = entry.frames?.seconds { frames += " über \(Int(seconds)) s" }
            let onePercent = entry.frames?.onePercentLow.map { "\(Int($0.rounded())) FPS" } ?? "–"
            let cells = [entry.game.replacingOccurrences(of: "|", with: "\\|"), entry.way ?? "–", limit, sizeText(measure), frames, onePercent,
                         slowestText(entry.frames)]
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
