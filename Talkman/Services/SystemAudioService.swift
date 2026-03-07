import CoreAudio
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "SystemAudio")

/// Fades system audio output down during recording and back up when done.
@MainActor
final class SystemAudioService {
    static let shared = SystemAudioService()

    private var savedVolume: Float?
    private var fadeTimer: Timer?
    private let fadeDuration: TimeInterval = 0.3
    private let fadeSteps = 10

    private init() {}

    func fadeOut() {
        fadeTimer?.invalidate()

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            logger.warning("No default output device found")
            return
        }

        let currentVolume = getVolume(deviceID: deviceID)
        guard currentVolume > 0.001 else {
            // Already silent, nothing to fade
            savedVolume = 0
            return
        }

        savedVolume = currentVolume
        animateVolume(deviceID: deviceID, from: currentVolume, to: 0)
        logger.info("Fading out system audio from \(currentVolume)")
    }

    func fadeIn() {
        fadeTimer?.invalidate()

        guard let targetVolume = savedVolume, targetVolume > 0.001 else {
            savedVolume = nil
            return
        }

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        animateVolume(deviceID: deviceID, from: 0, to: targetVolume)
        savedVolume = nil
        logger.info("Fading in system audio to \(targetVolume)")
    }

    private func animateVolume(deviceID: AudioDeviceID, from: Float, to: Float) {
        let stepInterval = fadeDuration / Double(fadeSteps)
        let stepSize = (to - from) / Float(fadeSteps)
        var step = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            step += 1
            if step >= (self?.fadeSteps ?? 0) {
                timer.invalidate()
                self?.setVolume(deviceID: deviceID, volume: to)
            } else {
                let volume = from + stepSize * Float(step)
                self?.setVolume(deviceID: deviceID, volume: volume)
            }
        }
    }

    // MARK: - CoreAudio helpers

    private func getDefaultOutputDevice() -> AudioDeviceID {
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
        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func getVolume(deviceID: AudioDeviceID) -> Float {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return volume
    }

    private nonisolated func setVolume(deviceID: AudioDeviceID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &vol
        )
    }
}
