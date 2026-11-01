// Checks where GameAudio sends the sound when a TV shows Nightforge and when it goes back, with
// output devices as fixtures – the Mac's own audio settings are never touched:
// tests/GameAudioTest/run.sh
import Foundation

@main
struct GameAudioTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Device = GameAudio.Device

    struct Fixture: Decodable {
        var uid: String
        var name: String
        var transport: String
        var speakers: Bool?
    }

    static func load() -> [String: [Device]] {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        json["about"] = nil
        var setups: [String: [Device]] = [:]
        for (name, list) in json {
            guard let listData = try? JSONSerialization.data(withJSONObject: list),
                  let devices = try? JSONDecoder().decode([Fixture].self, from: listData)
            else { continue }
            setups[name] = devices.map { fixture in
                let transports: [String: Device.Transport] = ["builtIn": .builtIn, "hdmi": .hdmi, "displayPort": .displayPort,
                                                              "bluetooth": .bluetooth, "usb": .usb, "airPlay": .airPlay]
                return Device(uid: fixture.uid, name: fixture.name, transport: transports[fixture.transport] ?? .other,
                              speakers: fixture.speakers ?? false)
            }
        }
        return setups
    }

    static func main() {
        let setups = load()
        check(setups.count == 5, "the five setups from devices.json (\(setups.count))")
        let speakers = "BuiltInSpeakerDevice"
        let headphones = "BuiltInHeadphoneOutputDevice"
        let denon = "AppleGFXHDAEngineOutputDP:10001:0:{AC10-D0A0-00000001}"
        let lg = "AppleGFXHDAEngineOutputDP:10001:0:{1E6D-C0A2-00000001}"

        // The live test: TV behind a DENON receiver, sound still on the MacBook.
        let home = setups["macbook-denon"] ?? []
        func decide(_ moment: GameAudio.Moment, tv: String? = "DENON-AVR", _ devices: [Device], current: String?,
                    _ switched: GameAudio.Switched) -> (GameAudio.Action, GameAudio.Switched) {
            GameAudio.decide(moment, tv: tv, devices: devices, current: current, switched: switched)
        }
        var (action, state) = decide(.plugged, home, current: speakers, .none)
        check(action == .switchTo(home[1]) && state == .moved(from: speakers, to: denon),
              "the TV plugged in: the sound goes from the MacBook's speakers to the receiver")
        (action, state) = decide(.gameStarts, home, current: speakers, .none)
        check(action == .switchTo(home[1]), "a game starting on the TV with the speakers still on: switched (Wine takes it now)")
        (action, state) = decide(.plugged, tv: "", home, current: speakers, .none)
        check(action == .switchTo(home[1]), "mirrored onto it, without a name: the only HDMI output")
        (action, state) = decide(.look, home, current: speakers, .none)
        check(action == .none && state == .none, "just a look (Nightforge in front, its window between Spaces): nothing switches")
        (action, state) = decide(.gameStarts, home, current: denon, .moved(from: speakers, to: denon))
        check(action == .none && state == .moved(from: speakers, to: denon), "switched already: nothing more")

        // The live test on 1.11.: the player puts the speakers back to compare – it stays so.
        (action, state) = decide(.look, home, current: speakers, .moved(from: speakers, to: denon))
        check(action == .none && state == .declined, "the player chose the speakers: noted, nothing switched")
        for moment in [GameAudio.Moment.look, .gameStarts, .look] {
            (action, state) = decide(moment, home, current: speakers, state)
            check(action == .none && state == .declined, "and it stays so (\(moment)) – Nightforge in front again, a game starting")
        }
        (action, state) = decide(.left, tv: nil, home, current: speakers, .declined)
        check(action == .none && state == .declined, "the window off the TV for a moment: the choice still stands")
        (action, state) = decide(.plugged, home, current: speakers, .declined)
        check(action == .switchTo(home[1]) && state == .moved(from: speakers, to: denon), "until the TV is plugged in again")

        // Back.
        (action, state) = decide(.left, tv: nil, home, current: denon, .moved(from: speakers, to: denon))
        check(action == .restore(uid: speakers) && state == .none, "off the TV: back to the speakers")
        (action, state) = decide(.left, tv: nil, home, current: speakers, .none)
        check(action == .none && state == .none, "never switched: nothing to put back")
        let gone = (setups["speakers-only"] ?? [])
        (action, state) = decide(.left, tv: nil, gone, current: speakers, .moved(from: speakers, to: denon))
        check(action == .none && state == .none, "TV unplugged: macOS has moved the sound already")
        (action, state) = decide(.left, tv: nil, home, current: denon, .moved(from: "AppleUSBAudioEngine:gone", to: denon))
        check(action == .none && state == .none, "the speakers it came from are gone: left as it is")
        (action, state) = decide(.left, tv: nil, home, current: "70-F9-4A-11-22-33:output", .moved(from: speakers, to: denon))
        check(action == .none && state == .declined, "AirPods picked meanwhile: leaving the TV leaves them")

        let jack = setups["headphones"] ?? []
        (action, state) = decide(.plugged, jack, current: headphones, .none)
        check(action == .none && state == .none, "headphones on the Mac stay")
        let others = setups["airpods-usb"] ?? []
        for current in ["70-F9-4A-11-22-33:output", "AppleUSBAudioEngine:Focusrite:Scarlett 2i2:1"] {
            (action, state) = decide(.gameStarts, others, current: current, .none)
            check(action == .none && state == .none, "\(current) stays")
        }
        (action, state) = decide(.plugged, others, current: speakers, .none)
        check(action == .switchTo(others[3]), "with AirPods and an interface around, still the receiver from the speakers")

        // A receiver switched off and on: its output went and comes back (a new HDMI output counts as plugged in).
        (action, state) = decide(.look, gone, current: speakers, .moved(from: speakers, to: denon))
        check(action == .none && state == .none, "receiver off: nothing to switch to, nothing declined")
        (action, state) = decide(.plugged, home, current: speakers, state)
        check(action == .switchTo(home[1]), "receiver on again: back to it")

        // Which output is the TV's.
        let two = setups["tv-and-monitor"] ?? []
        check(GameAudio.output(for: "LG TV SSCR2", in: two)?.uid == lg, "of a TV and a monitor, the one named like the TV")
        let sony = two + [Device(uid: "sony", name: "SONY TV", transport: .hdmi)]
        check(GameAudio.output(for: "SONY TV  *00", in: sony)?.uid == "sony", "a screen named \"SONY TV  *00\", its output \"SONY TV\"")
        check(GameAudio.output(for: "lg tv sscr2", in: two)?.uid == lg, "names compared without case")
        check(GameAudio.output(for: "SAMSUNG", in: two) == nil, "no output named like it: none rather than a guess")
        check(GameAudio.output(for: "", in: two) == nil, "a mirror without a name and two outputs: none")
        check(GameAudio.output(for: "SAMSUNG", in: home)?.uid == denon, "a single HDMI output is the TV's, whatever its name")
        check(GameAudio.output(for: "DENON-AVR", in: gone) == nil, "no HDMI output, no switch")
        (action, state) = decide(.plugged, tv: "LG TV SSCR2", two, current: speakers, .none)
        check(action == .switchTo(two[1]), "the TV's output, not the monitor's")
        (action, state) = decide(.gameStarts, tv: nil, gone, current: speakers, .none)
        check(action == .none && state == .none, "a MacBook alone: nothing happens")

        if failures == 0 { print("✓ GameAudio: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}
