import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioInputDeviceManagerError: LocalizedError {
    case deviceLookupFailed
    case deviceSelectionFailed(OSStatus)
    case audioUnitUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceLookupFailed:
            return "Unable to load audio input devices."
        case .deviceSelectionFailed(let status):
            return "Unable to switch to the selected input device (OSStatus \(status))."
        case .audioUnitUnavailable:
            return "Unable to access the microphone input unit."
        }
    }
}

enum AudioInputDeviceManager {
    static func inputDevices() -> [RecordingInputDevice] {
        deviceIDs()
            .filter(hasInputChannels)
            .compactMap { deviceID in
                guard
                    let uid = deviceUID(for: deviceID),
                    let name = deviceName(for: deviceID)
                else { return nil }

                return RecordingInputDevice(id: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceUID(for: deviceID)
    }

    static func applyInputDevice(id preferredID: String?, to engine: AVAudioEngine) throws -> String? {
        guard let preferredID, let deviceID = deviceID(forUID: preferredID) else {
            return defaultInputDeviceID()
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioInputDeviceManagerError.audioUnitUnavailable
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioInputDeviceManagerError.deviceSelectionFailed(status)
        }

        return preferredID
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)

        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else { return [] }
        return deviceIDs
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        for deviceID in deviceIDs() where deviceUID(for: deviceID) == uid {
            return deviceID
        }
        return nil
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr else { return nil }
        return uid?.takeUnretainedValue() as String?
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else { return nil }
        return name?.takeUnretainedValue() as String?
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else { return false }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let list = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, list)
        guard dataStatus == noErr else { return false }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}
