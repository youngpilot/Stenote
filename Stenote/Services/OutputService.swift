import AppKit
import ApplicationServices
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "Output")

enum InsertionMode: String, CaseIterable, Identifiable {
    case auto
    case clipboard
    case direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .clipboard: "Clipboard"
        case .direct: "Direct Typing"
        }
    }
}

@Observable
@MainActor
final class OutputService {
    private var sourceApp: NSRunningApplication?
    private var pendingText: String = ""

    /// Once we've pasted at least once, the target is locked for this recording session
    private var targetLocked = false
    /// Whether we're in an active recording session
    private var isSessionActive = false
    /// Guard against overlapping paste operations
    private var isPasting = false
    /// Saved clipboard contents to restore after paste
    private var savedPasteboardItems: [NSPasteboardItem]?

    /// The last non-Stenote app that was frontmost
    private var previousApp: NSRunningApplication?
    private var activationObserver: Any?

    private var ownBundleID: String? { Bundle.main.bundleIdentifier }

    func startTrackingAppActivations() {
        let bundleID = ownBundleID
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != bundleID {
            previousApp = front
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != bundleID {
                MainActor.assumeIsolated {
                    self?.previousApp = app
                    if let self, self.isSessionActive, !self.targetLocked {
                        self.sourceApp = app
                        if !self.pendingText.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.flushPendingText()
                            }
                        }
                    }
                }
            }
        }
    }

    func rememberSourceApp() {
        isSessionActive = true
        targetLocked = false

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier == ownBundleID {
            sourceApp = previousApp
        } else {
            sourceApp = frontmost
        }
    }

    func endSession() {
        isSessionActive = false
        targetLocked = false
        sourceApp = nil
        logger.info("Session ended — restoring clipboard in 750ms")
        // Delay restore so the last Cmd+V has time to be read by the target app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.restorePasteboard()
        }
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }

        guard let sourceApp else {
            logger.warning("insertText but no sourceApp — buffering \(text.count) chars")
            pendingText += text
            return
        }

        targetLocked = true
        pendingText += text
        logger.info("insertText: \(text.prefix(60))… (pending: \(self.pendingText.count) chars)")

        guard !isPasting else { return }

        doPaste(to: sourceApp)
    }

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Saved clipboard string to restore after session
    private var savedClipboardString: String?
    private var savedClipboardChangeCount: Int = 0

    private func doPaste(to app: NSRunningApplication) {
        guard !pendingText.isEmpty else {
            isPasting = false
            return
        }

        isPasting = true
        let textToSend = pendingText
        pendingText = ""

        let mode = SettingsStore.shared.insertionMode
        let useDirectTyping: Bool
        switch mode {
        case .direct:
            useDirectTyping = true
        case .auto:
            useDirectTyping = textToSend.count <= 80
        case .clipboard:
            useDirectTyping = false
        }

        if useDirectTyping {
            logger.info("Direct typing: \(textToSend.count) chars")

            // Only activate if not already frontmost
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            if !isFrontmost {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.typeTextDirectly(textToSend)
                    self?.scheduleDrain(to: app)
                }
            } else {
                typeTextDirectly(textToSend)
                scheduleDrain(to: app)
            }
            return
        }

        let pasteboard = NSPasteboard.general

        // Save clipboard once per session (just the string — fast)
        if savedPasteboardItems == nil {
            savedClipboardString = pasteboard.string(forType: .string)
            savedClipboardChangeCount = pasteboard.changeCount
            savedPasteboardItems = [] // Mark as saved
        }

        // Write text with concealed flag so clipboard managers ignore it
        pasteboard.clearContents()
        pasteboard.setString(textToSend, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)

        // Only activate if not already frontmost
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if !isFrontmost {
            app.activate()
            // Need a short delay for app activation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.simulatePaste()
                self?.scheduleDrain(to: app)
            }
        } else {
            // Already frontmost — paste immediately, no delay
            simulatePaste()
            scheduleDrain(to: app)
        }
    }

    private func scheduleDrain(to app: NSRunningApplication) {
        // Check for more pending text after a minimal delay for the paste to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            if !self.pendingText.isEmpty {
                self.doPaste(to: app)
            } else {
                self.isPasting = false
            }
        }
    }

    /// Restore the clipboard to what it was before we used it
    private func restorePasteboard() {
        guard savedPasteboardItems != nil else { return }
        if let saved = savedClipboardString {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
        savedPasteboardItems = nil
        savedClipboardString = nil
    }

    var hasPendingOutput: Bool {
        isPasting || !pendingText.isEmpty
    }

    func flushPendingText() {
        guard !pendingText.isEmpty, let sourceApp, !isPasting else { return }
        doPaste(to: sourceApp)
    }

    private func typeTextDirectly(_ text: String) {
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var char = UniChar(scalar.value)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

// Free function to avoid Swift 6 Sendable issues with kAXTrustedCheckOptionPrompt
private nonisolated func promptAccessibility() {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    let options = [key: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
