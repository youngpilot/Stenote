import AppKit
import CoreAudio
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "SystemAudio")

/// Fades system audio and pauses/resumes media playback during recording.
@Observable
@MainActor
final class SystemAudioService {
    static let shared = SystemAudioService()

    private(set) var supportsVolumeControl: Bool = true
    private(set) var detectedMediaApp: String?

    private var savedVolume: Float?
    private var savedMute: Bool?
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

    // MARK: - Media control (two independent capabilities)

    /// Make all output audio inaudible: fade the system volume to zero, then
    /// hard-mute the device (silent even where the volume scalar can't reach
    /// true zero). Undo with restoreOutput().
    func muteOutput() {
        fadeTimer?.invalidate()
        savedVolume = nil
        savedMute = nil

        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            logger.warning("No default output device found")
            return
        }

        savedMute = getMute(deviceID: deviceID)
        let currentVolume = getVolume(deviceID: deviceID)
        savedVolume = currentVolume

        if currentVolume > 0.001 {
            animateVolume(deviceID: deviceID, from: currentVolume, to: 0) { [weak self] in
                self?.setMute(deviceID: deviceID, muted: true)
            }
        } else {
            setMute(deviceID: deviceID, muted: true)
        }
        logger.info("Muted output (volume \(currentVolume) → muted)")
    }

    /// Undo muteOutput(): restore the prior mute state and fade volume back.
    /// No-op if we didn't mute, so it never unmutes a device the user muted.
    func restoreOutput() {
        guard savedVolume != nil else { return }
        fadeTimer?.invalidate()

        let deviceID = getDefaultOutputDevice()
        if deviceID != kAudioObjectUnknown {
            setMute(deviceID: deviceID, muted: savedMute ?? false)
            let targetVolume = savedVolume ?? 0
            if targetVolume > 0.001 {
                animateVolume(deviceID: deviceID, from: getVolume(deviceID: deviceID), to: targetVolume)
                logger.info("Restored output to \(targetVolume)")
            }
        }
        savedVolume = nil
        savedMute = nil
    }

    /// Pause the first running, currently-playing supported player
    /// (Spotify / Apple Music). Undo with resumeMediaApps().
    func pauseMediaApps() {
        pausedApp = nil
        for (name, scriptName, bundleId) in Self.supportedMediaApps {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) else { continue }
            guard isPlaying(scriptName: scriptName) else { continue }
            if runAppleScript("tell application \"\(scriptName)\" to pause", context: "pause \(name)") {
                pausedApp = scriptName
                logger.info("Paused \(name)")
            }
            break
        }
    }

    /// Resume the player paused by pauseMediaApps(). No-op if nothing was paused.
    func resumeMediaApps() {
        guard let app = pausedApp else { return }
        pausedApp = nil
        // Brief delay so resume lands after any unmute/fade settles.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            self.runAppleScript("tell application \"\(app)\" to play", context: "resume \(app)")
            logger.info("Resumed \(app)")
        }
    }

    // MARK: - AppleScript helpers

    private func isPlaying(scriptName: String) -> Bool {
        guard let script = NSAppleScript(source: "tell application \"\(scriptName)\" to player state as string") else { return false }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            logger.warning("AppleScript player-state \(scriptName) failed: \(String(describing: error))")
            return false
        }
        return descriptor.stringValue?.lowercased() == "playing"
    }

    @discardableResult
    private func runAppleScript(_ source: String, context: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.warning("AppleScript (\(context)) failed: \(String(describing: error))")
            return false
        }
        return true
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

    /// True if we can silence this output device by software — either via a
    /// volume scalar or a dedicated mute property.
    private func checkVolumeSupport() -> Bool {
        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return false }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                if AudioObjectHasProperty(deviceID, &address) { return true }
            }
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

    private nonisolated func setMute(deviceID: AudioDeviceID, muted: Bool) {
        var val: UInt32 = muted ? 1 : 0
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                AudioObjectSetPropertyData(
                    deviceID, &address, 0, nil,
                    UInt32(MemoryLayout<UInt32>.size), &val
                )
            }
        }
    }

    private func getMute(deviceID: AudioDeviceID) -> Bool? {
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                var muted: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr {
                    return muted != 0
                }
            }
        }
        return nil
    }
}

