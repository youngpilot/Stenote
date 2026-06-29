import AppKit
import Carbon
import Observation

/// How the recording hotkey activates: tap to toggle, or hold (push-to-talk).
enum ActivationMode: String, CaseIterable, Identifiable {
    case toggle   // press to start, press again to stop (double-press for modifier keys)
    case hold     // push-to-talk: hold to record, release to stop
    var id: String { rawValue }
    var label: String { self == .toggle ? "Toggle" : "Hold" }
}

@Observable
@MainActor
final class HotkeyService {
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var lastDoublePressTime: Date?
    private let doublePressInterval: TimeInterval = 0.4
    private var currentHotkeys: Set<HotkeyChoice> = [.doubleRightOption]
    /// In Hold mode, the hotkey currently held down (pairs press→release).
    private var heldHotkey: HotkeyChoice?

    var onToggle: (() -> Void)?    // Toggle mode
    var onPress: (() -> Void)?     // Hold mode: hotkey pressed → start
    var onRelease: (() -> Void)?   // Hold mode: hotkey released → stop

    func start() {
        currentHotkeys = SettingsStore.shared.hotkeys
        SettingsStore.shared.onHotkeyChanged = { [weak self] newHotkeys in
            self?.currentHotkeys = newHotkeys
        }
        installMonitors()
    }

    func stop() {
        for m in [flagsMonitor, keyDownMonitor, keyUpMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(m)
        }
        flagsMonitor = nil; keyDownMonitor = nil; keyUpMonitor = nil
    }

    private var mode: ActivationMode { SettingsStore.shared.activationMode }

    private func installMonitors() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlagsChanged(event) }
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyDown(event) }
        }
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyUp(event) }
        }
    }

    // MARK: - Modifier keys (Right ⌥ / Right ⌘ / Fn)

    private func handleFlagsChanged(_ event: NSEvent) {
        if mode == .hold { handleHoldFlags(event); return }
        // Toggle mode: double-press of a modifier hotkey.
        if currentHotkeys.contains(.doubleRightOption), event.keyCode == 61, event.modifierFlags.contains(.option) {
            checkDoublePress(); return
        }
        if currentHotkeys.contains(.doubleRightCmd), event.keyCode == 54, event.modifierFlags.contains(.command) {
            checkDoublePress(); return
        }
        if currentHotkeys.contains(.doubleFn), event.keyCode == 63, event.modifierFlags.contains(.function) {
            checkDoublePress(); return
        }
    }

    /// Hold mode: a modifier's keyCode event carries the resulting flag state —
    /// flag present = pressed (start), absent = released (stop).
    private func handleHoldFlags(_ event: NSEvent) {
        if currentHotkeys.contains(.doubleRightOption), event.keyCode == 61 {
            event.modifierFlags.contains(.option) ? holdPress(.doubleRightOption) : holdRelease(.doubleRightOption)
            return
        }
        if currentHotkeys.contains(.doubleRightCmd), event.keyCode == 54 {
            event.modifierFlags.contains(.command) ? holdPress(.doubleRightCmd) : holdRelease(.doubleRightCmd)
            return
        }
        if currentHotkeys.contains(.doubleFn), event.keyCode == 63 {
            event.modifierFlags.contains(.function) ? holdPress(.doubleFn) : holdRelease(.doubleFn)
            return
        }
    }

    // MARK: - Regular keys (F5, ⌥Space, Fn Space)

    private func handleKeyDown(_ event: NSEvent) {
        if mode == .hold {
            if matchesF5(event) { holdPress(.f5) }
            else if matchesOptionSpace(event) { holdPress(.optionSpace) }
            else if matchesFnSpace(event) { holdPress(.fnSpace) }
            return
        }
        if matchesF5(event) || matchesOptionSpace(event) || matchesFnSpace(event) { fireToggle() }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard mode == .hold else { return }
        if event.keyCode == 96 { holdRelease(.f5); return }   // F5 up
        if event.keyCode == 49 {                              // Space up → end any space-combo hold
            holdRelease(.optionSpace)
            holdRelease(.fnSpace)
        }
    }

    private func matchesF5(_ e: NSEvent) -> Bool {
        currentHotkeys.contains(.f5) && e.keyCode == 96
    }
    private func matchesOptionSpace(_ e: NSEvent) -> Bool {
        currentHotkeys.contains(.optionSpace) && e.keyCode == 49 &&
            e.modifierFlags.contains(.option) &&
            !e.modifierFlags.contains(.command) && !e.modifierFlags.contains(.control)
    }
    private func matchesFnSpace(_ e: NSEvent) -> Bool {
        currentHotkeys.contains(.fnSpace) && e.keyCode == 49 &&
            e.modifierFlags.contains(.function) &&
            !e.modifierFlags.contains(.command) && !e.modifierFlags.contains(.option) &&
            !e.modifierFlags.contains(.control)
    }

    // MARK: - Helpers

    private func checkDoublePress() {
        let now = Date()
        if let last = lastDoublePressTime, now.timeIntervalSince(last) < doublePressInterval {
            lastDoublePressTime = nil
            fireToggle()
        } else {
            lastDoublePressTime = now
        }
    }

    private func fireToggle() { onToggle?() }

    /// Hold-mode press: start once, tracking which key is held.
    private func holdPress(_ choice: HotkeyChoice) {
        guard heldHotkey == nil else { return }
        heldHotkey = choice
        onPress?()
    }

    /// Hold-mode release: stop only when the key that started the hold is released.
    private func holdRelease(_ choice: HotkeyChoice) {
        guard heldHotkey == choice else { return }
        heldHotkey = nil
        onRelease?()
    }
}
