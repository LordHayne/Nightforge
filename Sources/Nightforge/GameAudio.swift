import CoreAudio
import Foundation

/// The TV's sound with the TV's picture. macOS remembers the output per device and leaves it on
/// the MacBook's speakers when a TV or an AV receiver comes in over HDMI. So while a TV shows
/// Nightforge (GameDisplay), the default output goes to that screen's HDMI or DisplayPort device –
/// only away from the Mac's own speakers, never from headphones, AirPods or an interface the
/// player chose – and back when Nightforge leaves the TV, if it switched and nobody changed it
/// since. Wine's games take the output when they start (winecoreaudio doesn't listen for a new
/// default while it plays), and the switch comes with the TV, before any game.
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

    /// What to do with the output. `tv`: the TV showing Nightforge, by its screen's name ("" when
    /// only a mirror shows it, nil without one). `current`: the default output's ID.
    static func decide(tv: String?, devices: [Device], current: String?, switched: Switched) -> (Action, Switched) {
        guard let tv else {
            // Off the TV: back to the speakers, if the sound is still where Nightforge put it.
            if case .moved(let from, let to) = switched, current == to, devices.contains(where: { $0.uid == from }) {
                return (.restore(uid: from), .none)
            }
            return (.none, .none)
        }
        switch switched {
        case .declined:
            return (.none, .declined)
        case .moved(_, let to) where current == to:
            return (.none, switched)
        case .moved(_, let to) where devices.contains(where: { $0.uid == to }):
            return (.none, .declined)  // the TV's output is there, the player chose another
        case .none, .moved:
            // Not yet, or the TV's output went (receiver off) and macOS moved the sound back.
            guard let now = devices.first(where: { $0.uid == current }), now.speakers,
                  let target = output(for: tv, in: devices)
            else { return (.none, .none) }
            return (.switchTo(target), .moved(from: now.uid, to: target.uid))
        }
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

    /// Where the output should be with `tv` showing Nightforge (GameDisplay). Also when outputs
    /// come and go: a TV's HDMI sound shows up a moment after its picture.
    static func follow(tv: String?) {
        self.tv = tv
        if !listening {
            listening = true
            var address = propertyAddress(kAudioHardwarePropertyDevices)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated { apply() }
            }
        }
        apply()
    }

    private static func apply() {
        let outputs = outputDevices()
        let current = deviceUID(defaultOutput())
        let (action, switched) = decide(tv: tv, devices: outputs.map(\.device), current: current, switched: stored)
        switch action {
        case .none:
            break
        case .switchTo(let device):
            guard let id = outputs.first(where: { $0.device.uid == device.uid })?.id, setDefaultOutput(id) else { return }
            Toasts.shared.show(L10n.t("Sound now comes from %@", device.name))
        case .restore(let uid):
            guard let id = outputs.first(where: { $0.device.uid == uid })?.id, setDefaultOutput(id) else { return }
        }
        stored = switched
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
