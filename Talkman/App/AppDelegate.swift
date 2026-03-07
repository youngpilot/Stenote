import AppKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Talkman launching...")
        requestMicrophonePermission()
        requestAccessibilityPermission()

        // Start model loading immediately on launch
        Task { @MainActor in
            logger.info("Starting model loading...")
            await RecordingManager.shared.setup()
            logger.info("Model loading complete")
        }
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                logger.info("Microphone access granted")
            } else {
                logger.error("Microphone access denied")
            }
        }
    }

    private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility trusted: \(trusted)")
    }
}
