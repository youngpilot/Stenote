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

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            logger.warning("No default output device found")
            // Try media pause as fallback even without volume control
            pauseMediaIfPlaying()
            return
        }

        let currentVolume = getVolume(deviceID: deviceID)
        if currentVolume < 0.001 {
            // Already silent — just pause media
            savedVolume = 0
            pauseMediaIfPlaying()
            return
        }

        savedVolume = currentVolume

        // Fade down, then pause media once silent
        animateVolume(deviceID: deviceID, from: currentVolume, to: 0) { [weak self] in
            self?.pauseMediaIfPlaying()
        }
        logger.info("Fading out system audio from \(currentVolume)")
    }

    /// Resume media playback, then fade audio back up
    func resumeAndFadeIn() {
        fadeTimer?.invalidate()

        // Resume media first (while still silent)
        if didPauseMedia {
            mediaRemote.sendCommand(.play)
            didPauseMedia = false
            logger.info("Resumed media playback")
        }

        guard let targetVolume = savedVolume, targetVolume > 0.001 else {
            savedVolume = nil
            return
        }

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            savedVolume = nil
            return
        }

        animateVolume(deviceID: deviceID, from: 0, to: targetVolume)
        savedVolume = nil
        logger.info("Fading in system audio to \(targetVolume)")
    }

    private func pauseMediaIfPlaying() {
        mediaRemote.isPlaying { [weak self] playing in
            guard let self, playing else { return }
            self.mediaRemote.sendCommand(.pause)
            self.didPauseMedia = true
            logger.info("Paused media playback")
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
        case togglePlayPause = 2
    }

    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool

    private let isPlayingFn: IsPlayingFn?
    private let sendCommandFn: SendCommandFn?

    init() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        ) else {
            isPlayingFn = nil
            sendCommandFn = nil
            return
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            isPlayingFn = unsafeBitCast(ptr, to: IsPlayingFn.self)
        } else {
            isPlayingFn = nil
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommandFn = unsafeBitCast(ptr, to: SendCommandFn.self)
        } else {
            sendCommandFn = nil
        }
    }

    func isPlaying(completion: @MainActor @escaping (Bool) -> Void) {
        guard let fn = isPlayingFn else {
            Task { @MainActor in completion(false) }
            return
        }
        fn(DispatchQueue.main) { playing in
            Task { @MainActor in completion(playing) }
        }
    }

    @discardableResult
    func sendCommand(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }
}
