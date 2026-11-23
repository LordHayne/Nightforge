import CoreAudio
import Foundation

/// The Mac's volume for the big overlay (docs/ENTWURF-OVERLAY-FUNKTIONEN.md, „Lautstärke“): the default output's volume
/// and mute through Core Audio, without a permission. Not every output has one in software: HDMI to a TV or an AV
/// receiver often has none, and then the overlay leaves the tile out (`tile`) instead of showing a slider that does
/// nothing. The probe of 23.11.2026 (docs/probes/overlay-lautstaerke) found the MacBook's speakers with a main-element
/// volume and mute, both settable, and no per-channel volume; other devices only have channels 1 and 2, so both ways count.
/// Not hooked into the overlay yet: that comes with its variant.
enum SystemVolume {
    /// Core Audio's part, as small as the rule needs: so the tests run on a stand-in and never touch the real volume.
    struct Hardware {
        /// The default output device; nil when there is none.
        var defaultOutput: () -> AudioObjectID?
        /// Whether the property exists on the device's output scope, at `element`, and whether it can be set.
        var has: (AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyElement) -> (exists: Bool, settable: Bool)
        var readFloat: (AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyElement) -> Float32?
        var writeFloat: (AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyElement, Float32) -> Bool
        var readUInt: (AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyElement) -> UInt32?
        var writeUInt: (AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyElement, UInt32) -> Bool
    }

    /// Where an output keeps its volume: on the main element, or on its first two channels (left, right).
    enum Control: Equatable {
        case main
        case channels([AudioObjectPropertyElement])
        /// No volume in software (often HDMI): the TV's or the receiver's remote has it.
        case none

        var elements: [AudioObjectPropertyElement] {
            switch self {
            case .main: return [kAudioObjectPropertyElementMain]
            case .channels(let channels): return channels
            case .none: return []
            }
        }
    }

    /// What the overlay's tile shows.
    struct State: Equatable {
        /// 0…1.
        var volume: Float
        var muted: Bool
        /// Mute can be switched (else the tile mutes by volume 0 and back).
        var canMute: Bool
    }

    enum Tile: Equatable {
        /// No volume in software on this output: no tile.
        case hidden
        case shown(State)
    }

    static let stereo: [AudioObjectPropertyElement] = [1, 2]

    /// Where `device` keeps a volume that can be set.
    static func control(of device: AudioObjectID, _ hardware: Hardware) -> Control {
        if hardware.has(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain) == (true, true) { return .main }
        let channels = stereo.filter { hardware.has(device, kAudioDevicePropertyVolumeScalar, $0) == (true, true) }
        return channels.isEmpty ? .none : .channels(channels)
    }

    static func canMute(_ device: AudioObjectID, _ hardware: Hardware) -> Bool {
        hardware.has(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain) == (true, true)
    }

    /// The tile for the default output now.
    static func tile(_ hardware: Hardware = .live) -> Tile {
        guard let device = hardware.defaultOutput() else { return .hidden }
        let control = control(of: device, hardware)
        guard control != .none else { return .hidden }
        let levels = control.elements.compactMap { hardware.readFloat(device, kAudioDevicePropertyVolumeScalar, $0) }
        guard !levels.isEmpty else { return .hidden }
        let mutable = canMute(device, hardware)
        let muted = mutable ? (hardware.readUInt(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain) ?? 0) != 0 : false
        return .shown(State(volume: clamp(levels.reduce(0, +) / Float(levels.count)), muted: muted, canMute: mutable))
    }

    /// Sets the default output's volume (0…1, on every element that has it). Unmutes, as the Mac's own keys do. False when
    /// this output has no volume in software or Core Audio said no.
    @discardableResult
    static func set(_ volume: Float, _ hardware: Hardware = .live) -> Bool {
        guard let device = hardware.defaultOutput() else { return false }
        let elements = control(of: device, hardware).elements
        guard !elements.isEmpty else { return false }
        let wrote = elements.map { hardware.writeFloat(device, kAudioDevicePropertyVolumeScalar, $0, clamp(volume)) }
        if canMute(device, hardware), volume > 0 { _ = hardware.writeUInt(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain, 0) }
        return wrote.allSatisfy { $0 }
    }

    /// Mutes or unmutes the default output. False where it has no mute switch.
    @discardableResult
    static func mute(_ on: Bool, _ hardware: Hardware = .live) -> Bool {
        guard let device = hardware.defaultOutput(), canMute(device, hardware) else { return false }
        return hardware.writeUInt(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain, on ? 1 : 0)
    }

    /// One press on the pad (left/right on the tile): a sixteenth, as the Mac's volume keys go. From between two steps
    /// (set elsewhere, or a mean of two channels) it goes to the next step that way, never past one.
    static func step(_ volume: Float, up: Bool) -> Float {
        let sixteenths = clamp(volume) * 16
        let near = sixteenths.rounded()
        // Within a hair of a step counts as on it: Core Audio gives back 0.5625 as 0.56249994.
        let from = abs(sixteenths - near) < 0.01 ? near : sixteenths
        return clamp((up ? (from + 1).rounded(.down) : (from - 1).rounded(.up)) / 16)
    }

    static func clamp(_ value: Float) -> Float { min(1, max(0, value.isNaN ? 0 : value)) }
}

extension SystemVolume.Hardware {
    private static func address(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// The Mac's own. In a test program (no bundle) it writes nothing: the real volume isn't a test's to change.
    static let live = SystemVolume.Hardware(
        defaultOutput: {
            var device = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var where_ = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyElementMain, scope: kAudioObjectPropertyScopeGlobal)
            let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &device)
            return status == noErr && device != kAudioObjectUnknown ? device : nil
        },
        has: { device, selector, element in
            var where_ = address(selector, element)
            guard AudioObjectHasProperty(device, &where_) else { return (false, false) }
            var settable: DarwinBoolean = false
            return (true, AudioObjectIsPropertySettable(device, &where_, &settable) == noErr && settable.boolValue)
        },
        readFloat: { device, selector, element in
            var where_ = address(selector, element)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr ? value : nil
        },
        writeFloat: { device, selector, element, value in
            guard !TestGuard.testProgram else { return false }
            var where_ = address(selector, element)
            var value = value
            return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        },
        readUInt: { device, selector, element in
            var where_ = address(selector, element)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr ? value : nil
        },
        writeUInt: { device, selector, element, value in
            guard !TestGuard.testProgram else { return false }
            var where_ = address(selector, element)
            var value = value
            return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        })
}
