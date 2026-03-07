import AppKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Talkman launching...")
        requestMicrophonePermission()
        requestAccessibilityPermission()
        installRightClickMonitor()

        // Start model loading immediately on launch
        Task { @MainActor in
            logger.info("Starting model loading...")
            await RecordingManager.shared.setup()
            logger.info("Model loading complete")
        }
    }

    private func installRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Status bar button clicks come through NSStatusBarWindow
            if let windowClass = event.window?.className, windowClass.contains("StatusBar") {
                Task { @MainActor in
                    RecordingManager.shared.toggle()
                }
                return nil
            }
            return event
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
