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
    /// Saved clipboard contents to restore after paste (full items, all types)
    private var savedPasteboardItems: [NSPasteboardItem]?
    /// When set, skip restoring the clipboard at end of session (e.g. paste was
    /// blocked, so we intentionally leave the transcript on the clipboard).
    var suppressClipboardRestore = false

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
        suppressClipboardRestore = false

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
        // Restore once pasting is actually idle (instead of a fixed timer that can
        // race a slow paste and clobber the target with the old clipboard).
        scheduleRestoreWhenIdle(attempt: 0)
    }

    private func scheduleRestoreWhenIdle(attempt: Int) {
        guard !suppressClipboardRestore else { return }
        if !hasPendingOutput || attempt >= 20 {
            // Give the last ⌘V a moment to be read by the target, then restore.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.suppressClipboardRestore else { return }
                self.restorePasteboard()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.scheduleRestoreWhenIdle(attempt: attempt + 1)
            }
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
            // Only genuinely short snippets type directly; anything longer goes
            // through the atomic, drop-proof clipboard paste below. (Whole-text
            // paste-at-stop means "short" must be small — an 80-char sentence
            // typed key-by-key dropped characters.)
            useDirectTyping = textToSend.count <= 30
        case .clipboard:
            useDirectTyping = false
        }

        if useDirectTyping {
            logger.info("Direct typing: \(textToSend.count) chars")

            // Typing runs on the background typingQueue (it sleeps between
            // characters); only activate the app first if it isn't frontmost,
            // then drain back on the main actor once typing completes.
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            if !isFrontmost {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    OutputService.typingQueue.async { [weak self] in
                        self?.typeTextDirectly(textToSend)
                        DispatchQueue.main.async { self?.scheduleDrain(to: app) }
                    }
                }
            } else {
                OutputService.typingQueue.async { [weak self] in
                    self?.typeTextDirectly(textToSend)
                    DispatchQueue.main.async { self?.scheduleDrain(to: app) }
                }
            }
            return
        }

        let pasteboard = NSPasteboard.general

        // Snapshot the FULL clipboard once per session (every item + type) so we
        // restore images/files/RTF too — not just plain text. Copy eagerly; the
        // originals are invalidated by clearContents().
        if savedPasteboardItems == nil {
            savedPasteboardItems = (pasteboard.pasteboardItems ?? []).compactMap { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy.types.isEmpty ? nil : copy
            }
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

    /// Restore the clipboard to exactly what it was before we used it.
    private func restorePasteboard() {
        guard let items = savedPasteboardItems else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
        savedPasteboardItems = nil
    }

    var hasPendingOutput: Bool {
        isPasting || !pendingText.isEmpty
    }

    func flushPendingText() {
        guard !pendingText.isEmpty, let sourceApp, !isPasting else { return }
        doPaste(to: sourceApp)
    }

    /// Serial queue for synthetic keystrokes, so the small inter-character gap
    /// below never blocks the main thread.
    private static let typingQueue = DispatchQueue(label: "com.youngpilot.Stenote.typing", qos: .userInitiated)

    /// Types `text` as Unicode keystrokes. Runs OFF the main thread on
    /// `typingQueue` with a short gap between characters: posting a whole
    /// sentence back-to-back overruns the target app's event queue and it
    /// silently drops characters ("Deutsch" → "Dutsch"). The gap lets each
    /// keystroke land. Longer whole-text inserts go through the clipboard
    /// instead (see `doPaste`), so this only handles short text + Direct mode.
    private nonisolated func typeTextDirectly(_ text: String) {
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        // Per grapheme, encoded as UTF-16 — so characters above U+FFFF (emoji,
        // some CJK) go out as a surrogate pair instead of trapping `UniChar`.
        for character in text {
            var utf16 = Array(character.utf16)
            guard !utf16.isEmpty else { continue }
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.005)
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
