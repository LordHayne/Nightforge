// The big overlay's services (docs/ENTWURF-OVERLAY-FUNKTIONEN.md): the Mac's volume and a picture of the game's window.
// Everything runs on stand-ins: the real volume is never changed, no real picture is taken, and nothing stays on disk.
import AppKit
import CoreAudio

@main
struct OverlayServicesTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A Core Audio device as the rule sees it: which properties it has, which can be set, and their values.
    final class FakeAudio {
        struct Key: Hashable { let selector: AudioObjectPropertySelector; let element: AudioObjectPropertyElement }
        var device: AudioObjectID? = 42
        var settable: Set<Key> = []
        var readOnly: Set<Key> = []
        var floats: [Key: Float32] = [:]
        var uints: [Key: UInt32] = [:]
        var writes: [String] = []

        static func volume(_ element: AudioObjectPropertyElement) -> Key { Key(selector: kAudioDevicePropertyVolumeScalar, element: element) }
        static let mute = Key(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)

        var hardware: SystemVolume.Hardware {
            SystemVolume.Hardware(
                defaultOutput: { self.device },
                has: { _, selector, element in
                    let key = Key(selector: selector, element: element)
                    return (self.settable.contains(key) || self.readOnly.contains(key), self.settable.contains(key))
                },
                readFloat: { _, selector, element in self.floats[Key(selector: selector, element: element)] },
                writeFloat: { _, selector, element, value in
                    let key = Key(selector: selector, element: element)
                    guard self.settable.contains(key) else { return false }
                    self.floats[key] = value
                    self.writes.append("volume \(element) \(value)")
                    return true
                },
                readUInt: { _, selector, element in self.uints[Key(selector: selector, element: element)] },
                writeUInt: { _, selector, element, value in
                    let key = Key(selector: selector, element: element)
                    guard self.settable.contains(key) else { return false }
                    self.uints[key] = value
                    self.writes.append("mute \(value)")
                    return true
                })
        }
    }

    static func volume() {
        let main = kAudioObjectPropertyElementMain
        // The MacBook's speakers as the probe found them: main-element volume and mute, both settable.
        let speakers = FakeAudio()
        speakers.settable = [FakeAudio.volume(main), FakeAudio.mute]
        speakers.floats[FakeAudio.volume(main)] = 0.5
        speakers.uints[FakeAudio.mute] = 0
        check(SystemVolume.tile(speakers.hardware) == .shown(.init(volume: 0.5, muted: false, canMute: true)), "speakers: a tile with their volume")
        check(SystemVolume.set(0.75, speakers.hardware) && speakers.floats[FakeAudio.volume(main)] == 0.75, "set: on the main element")
        check(SystemVolume.mute(true, speakers.hardware) && SystemVolume.tile(speakers.hardware) == .shown(.init(volume: 0.75, muted: true, canMute: true)),
              "muted: the tile says so")
        check(SystemVolume.set(0.5, speakers.hardware) && speakers.uints[FakeAudio.mute] == 0, "a new volume unmutes, as the Mac's keys do")
        speakers.writes = []
        check(SystemVolume.set(0, speakers.hardware) && !speakers.writes.contains("mute 0"), "volume 0 doesn't unmute")
        check(SystemVolume.set(1.7, speakers.hardware) && speakers.floats[FakeAudio.volume(main)] == 1, "kept within 0…1")

        // A device with its volume per channel only, no mute.
        let channels = FakeAudio()
        channels.settable = [FakeAudio.volume(1), FakeAudio.volume(2)]
        channels.floats = [FakeAudio.volume(1): 0.25, FakeAudio.volume(2): 0.75]
        check(SystemVolume.control(of: 42, channels.hardware) == .channels([1, 2]), "left and right count where main has none")
        check(SystemVolume.tile(channels.hardware) == .shown(.init(volume: 0.5, muted: false, canMute: false)), "the tile: their mean, no mute switch")
        check(SystemVolume.set(0.6, channels.hardware) && channels.floats[FakeAudio.volume(1)] == 0.6 && channels.floats[FakeAudio.volume(2)] == 0.6,
              "set: both channels")
        check(!SystemVolume.mute(true, channels.hardware), "no mute switch: mute says no")

        // HDMI to a TV or a receiver: no volume in software, or one that can only be read.
        let hdmi = FakeAudio()
        hdmi.readOnly = [FakeAudio.volume(main)]
        hdmi.floats[FakeAudio.volume(main)] = 1
        check(SystemVolume.tile(hdmi.hardware) == .hidden, "a volume that can't be set: no tile")
        check(!SystemVolume.set(0.5, hdmi.hardware) && hdmi.writes.isEmpty, "and nothing written")
        let none = FakeAudio()
        check(SystemVolume.tile(none.hardware) == .hidden && SystemVolume.control(of: 42, none.hardware) == .none, "no volume at all: no tile")
        none.device = nil
        check(SystemVolume.tile(none.hardware) == .hidden && !SystemVolume.set(0.5, none.hardware), "no output: no tile")
        let unread = FakeAudio()
        unread.settable = [FakeAudio.volume(main)]
        check(SystemVolume.tile(unread.hardware) == .hidden, "a volume Core Audio won't read: no tile")

        // The pad's steps: sixteenths, as the volume keys.
        check(SystemVolume.step(0.5, up: true) == 0.5625 && SystemVolume.step(0.5, up: false) == 0.4375, "one sixteenth a press")
        check(SystemVolume.step(1, up: true) == 1 && SystemVolume.step(0, up: false) == 0, "not past the ends")
        check(SystemVolume.step(0.51, up: true) == 0.5625 && SystemVolume.step(0.55, up: true) == 0.5625, "from between two steps: to the next one up")
        check(SystemVolume.step(0.45, up: false) == 0.4375 && SystemVolume.step(0.55, up: false) == 0.5, "and the next one down")
        check(SystemVolume.step(0.56249994, up: true) == 0.625 && SystemVolume.step(0.56249994, up: false) == 0.5, "a hair off a step is on it")
        check(SystemVolume.clamp(.nan) == 0, "nonsense is silence")

        // The real one never writes in a test program.
        check(TestGuard.testProgram, "this is a test program")
        if let device = SystemVolume.Hardware.live.defaultOutput() {
            check(!SystemVolume.Hardware.live.writeFloat(device, kAudioDevicePropertyVolumeScalar, main, 0)
                  && !SystemVolume.Hardware.live.writeUInt(device, kAudioDevicePropertyMute, main, 1),
                  "the Mac's volume: a test program writes nothing")
        }
    }

    static func window(_ pid: pid_t, number: Int, width: Double = 1512, height: Double = 982, level: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowNumber as String: NSNumber(value: number),
         kCGWindowLayer as String: NSNumber(value: level), kCGWindowAlpha as String: NSNumber(value: alpha),
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": width, "Height": height] as [String: Any]]
    }

    @MainActor
    static func screenshot() async {
        // Which window: the game's own, of a game's size, the frontmost; not a splash, not another app's, not the shield.
        let shield = window(7, number: 1, level: Int(CGShieldingWindowLevel()))
        let splash = window(7, number: 2, width: 400, height: 300)
        let other = window(9, number: 3)
        let game = window(7, number: 4)
        let behind = window(7, number: 5)
        check(GameScreenshot.window(in: [shield, splash, other, game, behind], pids: [7]) == 4, "the game's frontmost picture window")
        check(GameScreenshot.window(in: [splash, other, window(7, number: 6, alpha: 0)], pids: [7]) == nil, "none of a game's size: none")
        check(GameScreenshot.window(in: [game], pids: []) == nil, "no game: none")

        // Where: macOS' own setting where that folder is there, else the Desktop.
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let there: (URL) -> Bool = { $0.path == "/Users/someone/Pictures/Shots" || $0.path == "/Volumes/Photos" }
        check(GameScreenshot.folder(location: nil, home: home, exists: there).path == "/Users/someone/Desktop", "not set: the Desktop")
        check(GameScreenshot.folder(location: "~/Pictures/Shots", home: home, exists: there).path == "/Users/someone/Pictures/Shots", "~ is the home")
        check(GameScreenshot.folder(location: "/Volumes/Photos", home: home, exists: there).path == "/Volumes/Photos", "a folder elsewhere")
        check(GameScreenshot.folder(location: "/Volumes/Gone", home: home, exists: there).path == "/Users/someone/Desktop", "a folder that isn't there: the Desktop")
        check(GameScreenshot.folder(location: "relative/x", home: home, exists: { _ in true }).path == "/Users/someone/Desktop", "no absolute path: the Desktop")

        // The name.
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 11, 23, 13, 55, 1)
        let date = Calendar.current.date(from: parts)!
        check(GameScreenshot.fileName(game: "Black Myth: Wukong", at: date, taken: { _ in false }) == "Black Myth- Wukong 2026-11-23 13.55.01.png",
              "game, date, time; no colon")
        check(GameScreenshot.fileName(game: "AC/DC Racer", at: date, taken: { $0 == "AC-DC Racer 2026-11-23 13.55.01.png" })
              == "AC-DC Racer 2026-11-23 13.55.01 2.png", "a second in the same second: „ 2“")
        check(GameScreenshot.fileName(game: "  ", at: date, taken: { _ in false }).hasPrefix("Nightforge 2026"), "no name: Nightforge's")
        check(!GameScreenshot.fileName(game: "..hidden", at: date, taken: { _ in false }).hasPrefix("."), "never a hidden file")

        // The whole way, on stand-ins: permission first, then the window, the picture, the file.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("overlay-shot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try? FileManager.default.createDirectory(at: work.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        let picture = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        var captured: [Int] = []
        var system = GameScreenshot.System(
            permitted: { true }, windows: { [other, game] }, capture: { captured.append($0); return picture }, location: { nil },
            home: work, exists: { FileManager.default.fileExists(atPath: $0.path) },
            write: { GameScreenshot.writePNG($0, to: $1) }, now: { date })
        let saved = await GameScreenshot.take(game: "Some Game", pids: [7], system)
        let file = work.appendingPathComponent("Desktop/Some Game 2026-11-23 13.55.01.png")
        check(saved == .saved(file) && captured == [4] && FileManager.default.fileExists(atPath: file.path), "taken and saved: \(saved)")
        let second = await GameScreenshot.take(game: "Some Game", pids: [7], system)
        check(second == .saved(work.appendingPathComponent("Desktop/Some Game 2026-11-23 13.55.01 2.png")), "the next one beside it")

        captured = []
        system.permitted = { false }
        check(await GameScreenshot.take(game: "Some Game", pids: [7], system) == .needsPermission && captured.isEmpty,
              "no Screen Recording: „needs permission“, and no picture tried")
        system.permitted = { true }
        system.windows = { [other] }
        check(await GameScreenshot.take(game: "Some Game", pids: [7], system) == .noWindow && captured.isEmpty, "no window of the game's")
        system.windows = { [game] }
        system.capture = { _ in nil }
        check(await GameScreenshot.take(game: "Some Game", pids: [7], system) == .failed, "no picture: failed")
        system.capture = { _ in picture }
        system.write = { _, _ in false }
        check(await GameScreenshot.take(game: "Some Game", pids: [7], system) == .failed, "not written: failed")

        // The real one: in a test program it takes no picture and writes nothing.
        check(await GameScreenshot.System.live.capture(1) == nil, "a test program takes no picture")
        check(!GameScreenshot.System.live.write(picture, work.appendingPathComponent("live.png"))
              && !FileManager.default.fileExists(atPath: work.appendingPathComponent("live.png").path), "and writes none")

        // Nightforge never asks for Screen Recording itself, and only this service talks to ScreenCaptureKit.
        let sources = (try? FileManager.default.contentsOfDirectory(atPath: "Sources/Nightforge")) ?? []
        check(!sources.isEmpty, "the sources are there to look at")
        for name in sources where name.hasSuffix(".swift") {
            let text = (try? String(contentsOfFile: "Sources/Nightforge/" + name, encoding: .utf8)) ?? ""
            check(!text.contains("CGRequestScreenCaptureAccess"), "\(name): never asks for Screen Recording")
            if name != "GameScreenshot.swift" { check(!text.contains("SCScreenshotManager"), "\(name): no picture outside the service") }
        }
    }

    @MainActor
    static func main() async {
        TestDefaults.useWorkFolder()
        volume()
        await screenshot()
        print(failures == 0 ? "✓ OverlayServices" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
