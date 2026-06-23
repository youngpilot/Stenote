import AppKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var rightClickMonitor: Any?
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Stenote launching...")
        requestMicrophonePermission()
        requestAccessibilityPermission()
        installRightClickMonitor()
        configureMenuBarPanel()

        // Start model loading immediately on launch
        Task { @MainActor in
            logger.info("Starting model loading...")
            await RecordingManager.shared.setup()
            logger.info("Model loading complete")
        }
    }

    /// Configure the MenuBarExtra NSPanel to block mouse events from passing through
    private func configureMenuBarPanel() {
        // The panel may not exist yet at launch, so observe window creation
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? NSPanel,
                  panel.className.contains("StatusBarWindow") || panel.level == .popUpMenu || panel.level == .floating
            else { return }
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isMovableByWindowBackground = false
            self?.windowObserver = nil
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
