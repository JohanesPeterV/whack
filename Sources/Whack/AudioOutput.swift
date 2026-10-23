import CoreAudio
import Foundation

/// Reports system output silence. Digital devices without software volume are
/// left alone; a missing volume property does not imply silence.
enum AudioOutput {
    static func issue() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return "No sound output is available. Connect speakers or headphones." }

        func read(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> UInt32? {
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &property) else { return nil }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        if let muted = read(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain), muted != 0 {
            return "Your Mac is muted. Unmute it to hear tap reactions."
        }
        let volumes: [Float32]
        if let master = read(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            volumes = [Float32(bitPattern: master)]
        } else {
            volumes = [1, 2].compactMap { read(kAudioDevicePropertyVolumeScalar, element: $0).map { Float32(bitPattern: $0) } }
        }
        if !volumes.isEmpty, volumes.allSatisfy({ $0 <= 0.001 }) {
            return "Your Mac’s output volume is at zero. Turn it up to hear reactions."
        }
        return nil
    }
}
