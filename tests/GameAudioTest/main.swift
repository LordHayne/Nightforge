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

        // The live test at 12:00 on 1.11.: Nightforge hadn't switched (the TV came before it started),
        // the player picked the speakers in the menu bar, and the game's start put the receiver back.
        (action, state) = decide(.chosen, home, current: speakers, .none)
        check(action == .none && state == .declined, "the speakers picked in the menu bar with a TV there: noted at once")
        (action, state) = decide(.gameStarts, home, current: speakers, state)
        check(action == .none && state == .declined, "a game starting afterwards leaves them")
        (action, state) = decide(.chosen, home, current: denon, .moved(from: speakers, to: denon))
        check(action == .none && state == .moved(from: speakers, to: denon), "Nightforge's own switch coming back isn't a choice")
        (action, state) = decide(.chosen, home, current: denon, .none)
        check(action == .none && state == .declined, "the receiver picked by hand: left alone, nothing to put back")
        (action, state) = decide(.left, tv: nil, home, current: denon, state)
        check(action == .none && state == .declined, "and nothing put back when Nightforge leaves the TV")
        let alone = setups["speakers-only"] ?? []
        (action, state) = decide(.chosen, tv: nil, alone, current: speakers, .declined)
        check(action == .none && state == .none, "TV unplugged, macOS back on the speakers: no choice left to keep")

        // Only a TV that's new counts as plugged in, not one back after a moment (its HDMI handshake).
        var away: [String: Date] = [:]
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        check(GameAudio.plugged([denon], before: [], gone: &away, at: t0), "an output never seen: plugged in")
        check(!GameAudio.plugged([], before: [denon], gone: &away, at: t0.addingTimeInterval(60)), "gone: nothing plugged in")
        check(!GameAudio.plugged([denon], before: [], gone: &away, at: t0.addingTimeInterval(65)), "back after 5 s: the same TV")
        check(away.isEmpty, "and its time away forgotten")
        _ = GameAudio.plugged([], before: [denon], gone: &away, at: t0.addingTimeInterval(100))
        check(GameAudio.plugged([denon], before: [], gone: &away, at: t0.addingTimeInterval(140)), "back after 40 s: plugged in again")
        check(!GameAudio.plugged([denon], before: [denon], gone: &away, at: t0.addingTimeInterval(150)), "still there: nothing new")
        check(GameAudio.plugged([denon, lg], before: [denon], gone: &away, at: t0.addingTimeInterval(160)), "a second TV next to it")

        // Per TV (the user's idea on 1.11.): what the player chose for it stays, whatever comes.
        check(GameAudio.remembered(.chosen, tv: "DENON-AVR", devices: home, current: speakers, switched: .moved(from: speakers, to: denon)) == false,
              "the speakers picked with the receiver there: this TV's sound off it")
        check(GameAudio.remembered(.chosen, tv: "DENON-AVR", devices: home, current: denon, switched: .declined) == true,
              "the receiver picked again later: kept too")
        check(GameAudio.remembered(.chosen, tv: "DENON-AVR", devices: home, current: denon, switched: .moved(from: speakers, to: denon)) == nil,
              "Nightforge's own switch says nothing")
        check(GameAudio.remembered(.look, tv: "DENON-AVR", devices: home, current: speakers, switched: .none) == nil, "a look says nothing")
        check(GameAudio.remembered(.chosen, tv: nil, devices: home, current: speakers, switched: .none) == nil, "no TV showing Nightforge: nothing kept")
        check(GameAudio.remembered(.chosen, tv: "DENON-AVR", devices: alone, current: speakers, switched: .none) == nil,
              "its output gone (unplugged): nothing kept")
        for moment in [GameAudio.Moment.plugged, .gameStarts] {
            (action, state) = GameAudio.decide(moment, tv: "DENON-AVR", devices: home, current: speakers, switched: .none, wantsTV: false)
            check(action == .none && state == .none, "a known TV the player hears through the speakers: \(moment) leaves them")
            (action, state) = GameAudio.decide(moment, tv: "DENON-AVR", devices: home, current: speakers, switched: .none, wantsTV: true)
            check(action == .switchTo(home[1]), "one whose sound they want: \(moment) puts it there")
        }
        (action, state) = GameAudio.decide(.plugged, tv: "DENON-AVR", devices: home, current: speakers, switched: .none, wantsTV: nil)
        check(action == .switchTo(home[1]), "a TV never seen: its sound, as before")
        // Kept in their own suite here, never in Nightforge's settings (HOME doesn't move UserDefaults).
        let suite = "nightforge.game-audio-test.\(getpid())"
        if let defaults = UserDefaults(suiteName: suite) {
            let key = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
            check(TVSettings.soundOnTV(key, in: defaults) == nil, "a TV not seen before: nothing kept")
            TVSettings.setSoundOnTV(false, for: key, in: defaults)
            TVSettings.setSoundOnTV(true, for: "LG TV SSCR2", in: defaults)
            check(TVSettings.soundOnTV(key, in: defaults) == false, "the speakers for it, kept")
            check(TVSettings.soundOnTV("LG TV SSCR2", in: defaults) == true, "another TV keeps its own")
            TVSettings.setSoundOnTV(true, for: key, in: defaults)
            check(TVSettings.soundOnTV(key, in: defaults) == true, "changed back: kept so")
            check(TVSettings.fullScreen(key, in: defaults) == nil, "full screen on it: nothing kept yet")
            TVSettings.setFullScreen(true, for: key, in: defaults)
            check(TVSettings.fullScreen(key, in: defaults) == true && TVSettings.soundOnTV(key, in: defaults) == true,
                  "full screen kept beside its sound")
            defaults.removePersistentDomain(forName: suite)
        } else {
            check(false, "a defaults suite of its own")
        }

        // The overlay's line: Wine keeps the device the game opened.
        check(GameAudio.inGameHint(gameOutput: denon, current: speakers, devices: home) == "DENON-AVR",
              "the speakers picked during a game: it plays on the receiver until its next start")
        check(GameAudio.inGameHint(gameOutput: denon, current: denon, devices: home) == nil, "nothing changed: no line")
        check(GameAudio.inGameHint(gameOutput: nil, current: speakers, devices: home) == nil, "no game: no line")
        check(GameAudio.inGameHint(gameOutput: denon, current: speakers, devices: alone) == nil, "its device gone: no line")

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
