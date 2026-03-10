import AppKit
import CoreAudio
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "SystemAudio")

/// Fades system audio and pauses/resumes media playback during recording.
@Observable
@MainActor
final class SystemAudioService {
    static let shared = SystemAudioService()

    private(set) var supportsVolumeControl: Bool = true
    private(set) var detectedMediaApp: String?

    private var savedVolume: Float?
    private var fadeTimer: Timer?
    private var pausedApp: String?
    private let fadeDuration: TimeInterval = 0.3
    private let fadeSteps = 10

    private static let supportedMediaApps: [(name: String, scriptName: String, bundleId: String)] = [
        ("Spotify", "Spotify", "com.spotify.client"),
        ("Apple Music", "Music", "com.apple.Music"),
    ]

    private init() {
        DispatchQueue.main.async { [self] in
            self.supportsVolumeControl = self.checkVolumeSupport()
            self.installDeviceChangeListener()
            self.refreshDetectedMediaApp()
            self.installWorkspaceObservers()
        }
    }

    // MARK: - Media app detection

    private func refreshDetectedMediaApp() {
        detectedMediaApp = Self.supportedMediaApps.first { entry in
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == entry.bundleId }
        }?.name
    }

    private func installWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.refreshDetectedMediaApp()
            }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: handler)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: handler)
    }

    // MARK: - Media control via AppleScript

    /// Fade audio down and optionally pause media playback
    func fadeOutAndPause(stopMedia: Bool) {
        fadeTimer?.invalidate()
        pausedApp = nil

        if stopMedia {
            for (name, scriptName, bundleId) in Self.supportedMediaApps {
                guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) else { continue }
                guard let stateScript = NSAppleScript(source: "tell application \"\(scriptName)\" to player state as string") else { continue }
                var error: NSDictionary?
                let descriptor = stateScript.executeAndReturnError(&error)
                if let result = descriptor.stringValue, result == "playing" {
                    NSAppleScript(source: "tell application \"\(scriptName)\" to pause")?.executeAndReturnError(nil)
                    pausedApp = scriptName
                    logger.info("Paused \(name) via AppleScript")
                    break
                }
            }
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

        if targetVolume > 0.001, deviceID != kAudioObjectUnknown {
            animateVolume(deviceID: deviceID, from: 0, to: targetVolume)
            logger.info("Fading in system audio to \(targetVolume)")
        }
        savedVolume = nil

        if let app = pausedApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let playScript = NSAppleScript(source: "tell application \"\(app)\" to play")
                playScript?.executeAndReturnError(nil)
                logger.info("Resumed \(app) via AppleScript")
            }
            pausedApp = nil
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

    // MARK: - Device change listener

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.supportsVolumeControl = self?.checkVolumeSupport() ?? true
            }
        }
    }

    private func checkVolumeSupport() -> Bool {
        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return false }
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) { return true }
        }
        return false
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

    /// Find which element has volume control (master=0, or per-channel=1)
    private func volumeElement(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address) { return kAudioObjectPropertyElementMain }
        address.mElement = 1
        if AudioObjectHasProperty(deviceID, &address) { return 1 }
        return kAudioObjectPropertyElementMain
    }

    private func getVolume(deviceID: AudioDeviceID) -> Float {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: volumeElement(for: deviceID)
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return volume
    }

    private nonisolated func setVolume(deviceID: AudioDeviceID, volume: Float) {
        var vol = volume
        // Set on all possible elements (master + channels 1 & 2)
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            AudioObjectSetPropertyData(
                deviceID, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &vol
            )
        }
    }
}

