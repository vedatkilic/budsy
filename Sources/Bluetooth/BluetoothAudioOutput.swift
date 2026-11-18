import CoreAudio
import Foundation

enum BluetoothAudioOutput {
    static func connectedNames() -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devicesProperty = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesProperty, 0, nil, &size) == noErr else {
            return []
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let result = devices.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let buffer = bytes.baseAddress else { return kAudioHardwareBadPropertySizeError }
            return AudioObjectGetPropertyData(system, &devicesProperty, 0, nil, &size, buffer)
        }
        guard result == noErr else { return [] }

        return Set(devices.compactMap { device in
            guard let transport = number(kAudioDevicePropertyTransportType, on: device),
                  transport == kAudioDeviceTransportTypeBluetooth ||
                    transport == kAudioDeviceTransportTypeBluetoothLE,
                  number(kAudioDevicePropertyDeviceIsAlive, on: device) == 1
            else { return nil }

            var streams = property(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }

            var nameProperty = property(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout.size(ofValue: name))
            guard AudioObjectGetPropertyData(device, &nameProperty, 0, nil, &nameSize, &name) == noErr
            else { return nil }
            return name.map { $0.takeRetainedValue() as String }
        })
    }

    private static func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func number(_ selector: AudioObjectPropertySelector, on device: AudioDeviceID) -> UInt32? {
        var address = property(selector)
        var result: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: result))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &result) == noErr else {
            return nil
        }
        return result
    }
}
