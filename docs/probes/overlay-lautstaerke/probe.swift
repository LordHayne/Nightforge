// Reads only: is the default output's volume settable without a permission, and do Core Audio's process objects have a volume?
import CoreAudio
import Foundation
var device = AudioObjectID(kAudioObjectUnknown)
var size = UInt32(MemoryLayout<AudioObjectID>.size)
var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
for (name, element) in [("main", kAudioObjectPropertyElementMain), ("channel 1", 1)] as [(String, UInt32)] {
    var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    var settable: DarwinBoolean = false
    let has = AudioObjectHasProperty(device, &volume)
    let status = has ? AudioObjectIsPropertySettable(device, &volume, &settable) : -1
    print("output volume (\(name)): exists \(has), settable \(settable.boolValue) (status \(status))")
}
var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
print("mute exists: \(AudioObjectHasProperty(device, &mute))")
// A process object of this program: is there anything like a volume on it?
var me = getpid(), process = AudioObjectID(kAudioObjectUnknown)
size = UInt32(MemoryLayout<AudioObjectID>.size)
address.mSelector = kAudioHardwarePropertyTranslatePIDToProcessObject
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &me, &size, &process)
var volumeOnProcess = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
print("process object: \(process != kAudioObjectUnknown), volume on it: \(process != kAudioObjectUnknown && AudioObjectHasProperty(process, &volumeOnProcess))")
