import CoreAudio
import Foundation

/// The TV's sound with the TV's picture. macOS remembers the output per device and leaves it on
/// the MacBook's speakers when a TV or an AV receiver comes in over HDMI. So while a TV shows
/// Nightforge (GameDisplay), the default output goes to that screen's HDMI or DisplayPort device –
/// only away from the Mac's own speakers, never from headphones, AirPods or an interface the
/// player chose – and back when Nightforge leaves the TV, if it switched and nobody changed it
/// since. Wine's games take the output when they start (winecoreaudio doesn't listen for a new
/// default while it plays), and the switch comes with the TV, before any game. Any output the
/// player picks meanwhile stays, also across Nightforge's restarts, until the next TV comes.
@MainActor
enum GameAudio {
    struct Device: Equatable {
        enum Transport: Equatable { case builtIn, hdmi, displayPort, bluetooth, usb, airPlay, other }

        var uid: String
        var name: String
        var transport: Transport
        /// The Mac's own speakers (not its headphone jack).
        var speakers = false
    }

    /// What Nightforge did with the output, kept across starts.
    enum Switched: Equatable {
        case none
        /// Switched from the speakers (`from`) to the TV (`to`), by their unique IDs.
        case moved(from: String, to: String)
        /// The player picked another output while on the TV: left alone until the TV goes.
        case declined
    }

    enum Action: Equatable {
        case none
        case switchTo(Device)
        case restore(uid: String)
    }

    /// Why the output is looked at. It's switched at two moments only – a TV comes, a game starts
    /// on it (Wine takes the output when it opens it) – never because Nightforge comes to the front
    /// or its window moves between Spaces: the player's own choice stays until the next TV.
    enum Moment: Equatable {
        /// A TV or receiver came: its picture, or its HDMI sound a moment later – not one back
        /// after a moment away (`plugged(_:before:gone:at:)`).
        case plugged
        case gameStarts
        /// Nightforge's window went to a screen that's no TV, or the TV went.
        case left
        /// The default output changed, not by Nightforge: the player picked one in the menu bar,
        /// or macOS moved the sound as the TV came or went.
        case chosen
        /// Anything else: nothing switches, the player's choice is noted.
        case look
    }

    /// What to do with the output. `tv`: the TV showing Nightforge, by its screen's name ("" when
    /// only a mirror shows it, nil without one). `current`: the default output's ID.
    static func decide(_ moment: Moment, tv: String?, devices: [Device], current: String?, switched: Switched) -> (Action, Switched) {
        var state = switched
        // A new TV: what the player chose for the last one is over.
        if moment == .plugged, state == .declined { state = .none }
        // The sound left where Nightforge put it: the player chose another output – or the receiver
        // went off and macOS moved the sound back.
        if case .moved(_, let to) = state, current != to {
            state = devices.contains { $0.uid == to } ? .declined : .none
        }
        switch moment {
        case .plugged, .gameStarts:
            guard state == .none, let tv, let now = devices.first(where: { $0.uid == current }), now.speakers,
                  let target = output(for: tv, in: devices)
            else { return (.none, state) }
            return (.switchTo(target), .moved(from: now.uid, to: target.uid))
        case .left:
            // Off the TV: back to the speakers, if the sound is still where Nightforge put it.
            if case .moved(let from, let to) = state, current == to, devices.contains(where: { $0.uid == from }) {
                return (.restore(uid: from), .none)
            }
            return (.none, state == .declined ? .declined : .none)
        case .chosen:
            // The sound is still where Nightforge put it; otherwise what was picked stays while a
            // TV is there – also a game starting with the speakers on the 1.11. leaves them.
            if case .moved(_, let to) = state, current == to { return (.none, state) }
            let screens = devices.contains { $0.transport == .hdmi || $0.transport == .displayPort }
            return (.none, screens ? .declined : .none)
        case .look:
            return (.none, state)
        }
    }

    /// How long an output (or a screen) may be away and still count as the same when it's back: an
    /// HDMI device goes for a moment when the TV or receiver changes its picture's mode.
    nonisolated static let backWithin: TimeInterval = 30

    /// Whether `now` brings an output or screen (by ID) that's new – not one back after under
    /// `backWithin`. `gone`: when each went, kept up to date.
    nonisolated static func plugged(_ now: Set<String>, before: Set<String>, gone: inout [String: Date], at time: Date) -> Bool {
        for id in before.subtracting(now) { gone[id] = time }
        let new = now.subtracting(before).contains { id in gone[id].map { time.timeIntervalSince($0) > backWithin } ?? true }
        for id in now { gone[id] = nil }
        return new
    }

    /// The overlay's line while a game runs whose output isn't the default any more: Wine keeps
    /// the device it opened (`gameOutput`) until the game starts again. Nil when nothing changed.
    nonisolated static func inGameHint(gameOutput: String?, current: String?, devices: [Device]) -> String? {
        guard let gameOutput, let current, gameOutput != current,
              let name = devices.first(where: { $0.uid == gameOutput })?.name, !name.isEmpty
        else { return nil }
        return name
    }

    /// The TV's own output: the only HDMI or DisplayPort device, or of several the one named like
    /// the screen. None when that leaves a choice.
    static func output(for tv: String, in devices: [Device]) -> Device? {
        let screens = devices.filter { $0.transport == .hdmi || $0.transport == .displayPort }
        if screens.count == 1 { return screens[0] }
        let screen = tv.lowercased()
        guard !screen.isEmpty else { return nil }
        let named = screens.filter { device in
            let name = device.name.lowercased()
            return !name.isEmpty && (name.contains(screen) || screen.contains(name))
        }
        return named.count == 1 ? named[0] : nil
    }

    // MARK: - CoreAudio

    private static var tv: String?
    private static var listening = false
    /// The HDMI and DisplayPort outputs seen last: a new one is a TV's sound arriving.
    private static var screenOutputs: Set<String> = []
    private static var screenOutputsGone: [String: Date] = [:]
    /// The output Nightforge just set: its own change coming back isn't the player's choice.
    private static var ownChange: String?
    /// The output a running game opened (`.gameStarts`), for the overlay's line.
    private static var gameOutput: String?

    /// Where the output should be with `tv` showing Nightforge (GameDisplay). Also when outputs
    /// come and go: a TV's HDMI sound shows up a moment after its picture, and counts as it coming.
    static func follow(_ moment: Moment, tv: String?) {
        self.tv = tv
        if !listening {
            listening = true
            screenOutputs = Set(outputDevices().map(\.device).filter { $0.transport == .hdmi || $0.transport == .displayPort }.map(\.uid))
            var address = propertyAddress(kAudioHardwarePropertyDevices)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated {
                    let now = Set(outputDevices().map(\.device).filter { $0.transport == .hdmi || $0.transport == .displayPort }.map(\.uid))
                    let arrived = plugged(now, before: screenOutputs, gone: &screenOutputsGone, at: Date())
                    screenOutputs = now
                    apply(arrived ? .plugged : .look)
                }
            }
            // The player's pick in the menu bar is seen when it's made, not at the next game.
            var chosen = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &chosen, .main) { _, _ in
                MainActor.assumeIsolated {
                    let current = deviceUID(defaultOutput())
                    if let own = ownChange {
                        ownChange = nil
                        if current == own { return }
                    }
                    apply(.chosen)
                }
            }
        }
        apply(moment)
    }

    /// The game ended: the overlay has nothing to say any more.
    static func gameEnded() { gameOutput = nil }

    /// The overlay's line (`inGameHint`): the device the running game still plays to.
    static var gameStillOn: String? {
        inGameHint(gameOutput: gameOutput, current: deviceUID(defaultOutput()), devices: outputDevices().map(\.device))
    }

    private static func apply(_ moment: Moment) {
        let outputs = outputDevices()
        let current = deviceUID(defaultOutput())
        let (action, switched) = decide(moment, tv: tv, devices: outputs.map(\.device), current: current, switched: stored)
        switch action {
        case .none:
            break
        case .switchTo(let device):
            guard let id = outputs.first(where: { $0.device.uid == device.uid })?.id, set(id, device.uid) else { return }
            Toasts.shared.show(L10n.t("Sound now comes from %@", device.name))
        case .restore(let uid):
            guard let id = outputs.first(where: { $0.device.uid == uid })?.id, set(id, uid) else { return }
        }
        stored = switched
        if moment == .gameStarts { gameOutput = deviceUID(defaultOutput()) }
    }

    private static func set(_ id: AudioObjectID, _ uid: String) -> Bool {
        ownChange = uid
        guard setDefaultOutput(id) else {
            ownChange = nil
            return false
        }
        return true
    }

    private static var stored: Switched {
        get {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "soundDeclined") { return .declined }
            guard let from = defaults.string(forKey: "soundMovedFrom"), let to = defaults.string(forKey: "soundMovedTo")
            else { return .none }
            return .moved(from: from, to: to)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue == .declined, forKey: "soundDeclined")
            if case .moved(let from, let to) = newValue {
                defaults.set(from, forKey: "soundMovedFrom")
                defaults.set(to, forKey: "soundMovedTo")
            } else {
                defaults.removeObject(forKey: "soundMovedFrom")
                defaults.removeObject(forKey: "soundMovedTo")
            }
        }
    }

    private static func propertyAddress(_ selector: AudioObjectPropertySelector,
                                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, empty: T) -> T? {
        var address = propertyAddress(selector, scope)
        var result = empty
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr ? result : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr, let result else { return nil }
        return result.takeRetainedValue() as String
    }

    private static func defaultOutput() -> AudioObjectID {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, empty: AudioObjectID(0)) ?? 0
    }

    private static func deviceUID(_ device: AudioObjectID) -> String? {
        device == 0 ? nil : string(device, kAudioDevicePropertyDeviceUID)
    }

    /// The devices that play sound.
    static func outputDevices() -> [(id: AudioObjectID, device: Device)] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devices = propertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devices, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devices, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = propertyAddress(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            let transport: Device.Transport
            switch value(id, kAudioDevicePropertyTransportType, empty: UInt32(0)) ?? 0 {
            case kAudioDeviceTransportTypeBuiltIn: transport = .builtIn
            case kAudioDeviceTransportTypeHDMI: transport = .hdmi
            case kAudioDeviceTransportTypeDisplayPort: transport = .displayPort
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: transport = .bluetooth
            case kAudioDeviceTransportTypeUSB: transport = .usb
            case kAudioDeviceTransportTypeAirPlay: transport = .airPlay
            default: transport = .other
            }
            // The built-in output's source says speakers ('ispk') or headphones ('hdpn'); on
            // Apple silicon they are devices of their own, "BuiltInSpeakerDevice" the speakers.
            let source = value(id, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput, empty: UInt32(0))
            let speakers = transport == .builtIn && (source == 0x6973_706B || uid.localizedCaseInsensitiveContains("speaker"))
            return (id, Device(uid: uid, name: string(id, kAudioObjectPropertyName) ?? "", transport: transport, speakers: speakers))
        }
    }

    /// Makes `device` the default output, for every app that plays to the default.
    private static func setDefaultOutput(_ device: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }
}
