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
        var (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: home, current: speakers, switched: .none)
        check(action == .switchTo(home[1]) && state == .moved(from: speakers, to: denon),
              "on the TV the sound goes from the MacBook's speakers to the receiver")
        (action, state) = GameAudio.decide(tv: "", devices: home, current: speakers, switched: .none)
        check(action == .switchTo(home[1]), "mirrored onto it, without a name: the only HDMI output")
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: home, current: denon, switched: .moved(from: speakers, to: denon))
        check(action == .none && state == .moved(from: speakers, to: denon), "switched already: nothing more")

        // Back.
        (action, state) = GameAudio.decide(tv: nil, devices: home, current: denon, switched: .moved(from: speakers, to: denon))
        check(action == .restore(uid: speakers) && state == .none, "off the TV: back to the speakers")
        (action, state) = GameAudio.decide(tv: nil, devices: home, current: speakers, switched: .none)
        check(action == .none && state == .none, "never switched: nothing to put back")
        let gone = (setups["speakers-only"] ?? [])
        (action, state) = GameAudio.decide(tv: nil, devices: gone, current: speakers, switched: .moved(from: speakers, to: denon))
        check(action == .none && state == .none, "TV unplugged: macOS has moved the sound already")
        (action, state) = GameAudio.decide(tv: nil, devices: home, current: denon,
                                           switched: .moved(from: "AppleUSBAudioEngine:gone", to: denon))
        check(action == .none && state == .none, "the speakers it came from are gone: left as it is")

        // The player's own choice stays.
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: home, current: speakers,
                                           switched: .moved(from: speakers, to: denon))
        check(action == .none && state == .declined, "switched back to the speakers on the TV: the player's choice")
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: home, current: speakers, switched: .declined)
        check(action == .none && state == .declined, "and it stays so while the TV is there")
        (action, state) = GameAudio.decide(tv: nil, devices: home, current: speakers, switched: .declined)
        check(action == .none && state == .none, "until the TV goes")
        (action, state) = GameAudio.decide(tv: nil, devices: home, current: "70-F9-4A-11-22-33:output",
                                           switched: .moved(from: speakers, to: denon))
        check(action == .none && state == .none, "AirPods picked meanwhile: leaving the TV leaves them")

        let jack = setups["headphones"] ?? []
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: jack, current: headphones, switched: .none)
        check(action == .none && state == .none, "headphones on the Mac stay")
        let others = setups["airpods-usb"] ?? []
        for current in ["70-F9-4A-11-22-33:output", "AppleUSBAudioEngine:Focusrite:Scarlett 2i2:1"] {
            (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: others, current: current, switched: .none)
            check(action == .none && state == .none, "\(current) stays")
        }
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: others, current: speakers, switched: .none)
        check(action == .switchTo(others[3]), "with AirPods and an interface around, still the receiver from the speakers")

        // A receiver switched off and on: the TV's output went and comes back.
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: gone, current: speakers, switched: .moved(from: speakers, to: denon))
        check(action == .none && state == .none, "receiver off: nothing to switch to, nothing declined")
        (action, state) = GameAudio.decide(tv: "DENON-AVR", devices: home, current: speakers, switched: state)
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
        (action, state) = GameAudio.decide(tv: "LG TV SSCR2", devices: two, current: speakers, switched: .none)
        check(action == .switchTo(two[1]), "the TV's output, not the monitor's")
        (action, state) = GameAudio.decide(tv: nil, devices: gone, current: speakers, switched: .none)
        check(action == .none && state == .none, "a MacBook alone: nothing happens")

        if failures == 0 { print("✓ GameAudio: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}
