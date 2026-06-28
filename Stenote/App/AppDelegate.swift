import AppKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var rightClickMonitor: Any?
    private var windowObserver: Any?
    private var popoverKeyObserver: Any?
    private var appNapActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest the app is only a test host — skip the heavy bootstrap
        // (model download, mic/accessibility prompts, global hotkey monitor).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        logger.info("Stenote launching...")

        // Opt out of App Nap so the global hotkey, the red mic icon, and the start
        // sound fire INSTANTLY. A windowless menubar agent (LSUIElement) is a prime
        // App Nap target: when idle, macOS throttles its run loop / coalesces timers
        // and events, adding up to ~1s to the first shortcut press after a quiet
        // spell. Held for the app's lifetime; we still allow the Mac to sleep.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Instant global-hotkey response")
        installRightClickMonitor()
        configureMenuBarPanel()
        observePopoverOpen()

        Task { @MainActor in
            // First launch: show onboarding (it handles the permission prompts).
            // Otherwise re-validate permissions (no prompt if already decided).
            if SettingsStore.shared.hasCompletedOnboarding {
                requestMicrophonePermission()
                requestAccessibilityPermission()
            } else {
                OnboardingPresenter.shared.show()
            }

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

    /// Clear the green "transcription ready" menubar badge whenever the popover
    /// opens (the user has come to look). Persistent — fires on every open.
    private func observePopoverOpen() {
        popoverKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let win = notification.object as? NSWindow,
                  win.className.contains("StatusBar") || win.level == .popUpMenu || win.level == .floating
            else { return }
            Task { @MainActor in RecordingManager.shared.markWindowOpened() }
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
