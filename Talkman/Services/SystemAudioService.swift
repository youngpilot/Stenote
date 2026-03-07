import CoreAudio
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "SystemAudio")

/// Fades system audio and pauses/resumes media playback during recording.
@MainActor
final class SystemAudioService {
    static let shared = SystemAudioService()

    private var savedVolume: Float?
    private var fadeTimer: Timer?
    private var didPauseMedia = false
    private let fadeDuration: TimeInterval = 0.3
    private let fadeSteps = 10

    // MediaRemote function pointers (loaded dynamically)
    private let mediaRemote = MediaRemoteBridge()

    private init() {}

    /// Fade audio down, then pause media playback
    func fadeOutAndPause() {
        fadeTimer?.invalidate()
        didPauseMedia = false

        // Pause media immediately (if nothing is playing, this is a no-op)
        let wasPaused = mediaRemote.sendCommand(.pause)
        if wasPaused {
            didPauseMedia = true
            logger.info("Paused media playback")
        }

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            logger.warning("No default output device found")
            return
        }

        let currentVolume = getVolume(deviceID: deviceID)
        if currentVolume < 0.001 {
            savedVolume = 0
            return
        }

        savedVolume = currentVolume
        animateVolume(deviceID: deviceID, from: currentVolume, to: 0)
        logger.info("Fading out system audio from \(currentVolume)")
    }

    /// Resume media playback and fade audio back up
    func resumeAndFadeIn() {
        fadeTimer?.invalidate()

        let deviceID = getDefaultOutputDevice()
        let targetVolume = savedVolume ?? 0

        // Restore volume first (so resume isn't silent)
        if targetVolume > 0.001, deviceID != kAudioObjectUnknown {
            animateVolume(deviceID: deviceID, from: 0, to: targetVolume)
            logger.info("Fading in system audio to \(targetVolume)")
        }
        savedVolume = nil

        // Resume media after a short delay so volume has started fading in
        if didPauseMedia {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.mediaRemote.sendCommand(.play)
                logger.info("Resumed media playback")
            }
            didPauseMedia = false
        }
    }

    // MARK: - Volume animation

    private func animateVolume(
        deviceID: AudioDeviceID, from: Float, to: Float,
        completion: (() -> Void)? = nil
    ) {
        let stepInterval = fadeDuration / Double(fadeSteps)
        let stepSize = (to - from) / Float(fadeSteps)
        var step = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            step += 1
            guard let self else { timer.invalidate(); return }
            if step >= self.fadeSteps {
                timer.invalidate()
                self.setVolume(deviceID: deviceID, volume: to)
                completion?()
            } else {
                self.setVolume(deviceID: deviceID, volume: from + stepSize * Float(step))
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

// MARK: - MediaRemote bridge (private framework, loaded dynamically)

private final class MediaRemoteBridge: @unchecked Sendable {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
    }

    private typealias SendCommandFn = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
    private let sendCommandFn: SendCommandFn?

    init() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        ) else {
            sendCommandFn = nil
            return
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommandFn = unsafeBitCast(ptr, to: SendCommandFn.self)
        } else {
            sendCommandFn = nil
        }
    }

    @discardableResult
    func sendCommand(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }
}
