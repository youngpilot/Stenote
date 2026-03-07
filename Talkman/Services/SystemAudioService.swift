import CoreAudio
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "SystemAudio")

/// Mutes/unmutes system audio output during recording to prevent interference.
@MainActor
final class SystemAudioService {
    static let shared = SystemAudioService()

    /// Whether system audio was already muted before we muted it
    private var wasAlreadyMuted = false
    /// Whether we currently hold a mute
    private var didMute = false

    private init() {}

    func muteOutput() {
        let (deviceID, currentMute) = getDefaultOutputState()
        guard deviceID != kAudioObjectUnknown else {
            logger.warning("No default output device found")
            return
        }

        wasAlreadyMuted = currentMute
        if !currentMute {
            setMute(deviceID: deviceID, mute: true)
            logger.info("Muted system audio output")
        }
        didMute = true
    }

    func restoreOutput() {
        guard didMute else { return }
        didMute = false

        // Only unmute if we were the ones who muted it
        guard !wasAlreadyMuted else {
            logger.info("System audio was already muted before recording, leaving muted")
            return
        }

        let (deviceID, _) = getDefaultOutputState()
        guard deviceID != kAudioObjectUnknown else { return }

        setMute(deviceID: deviceID, mute: false)
        logger.info("Restored system audio output")
    }

    // MARK: - CoreAudio helpers

    private func getDefaultOutputState() -> (AudioDeviceID, Bool) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return (kAudioObjectUnknown, false) }

        // Read current mute state
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)

        return (deviceID, muted != 0)
    }

    private func setMute(deviceID: AudioDeviceID, mute: Bool) {
        var muteValue: UInt32 = mute ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &muteValue
        )
    }
}
