import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestMicrophonePermission()
        requestAccessibilityPermission()
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("Microphone access denied")
            }
        }
    }

    private func requestAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt is not concurrency-safe, use the raw string value
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
