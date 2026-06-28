import AppKit
import Carbon
import Observation

@Observable
@MainActor
final class HotkeyService {
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var lastDoublePressTime: Date?
    private let doublePressInterval: TimeInterval = 0.4
    private var currentHotkeys: Set<HotkeyChoice> = [.doubleRightOption]

    var onToggle: (() -> Void)?

    func start() {
        currentHotkeys = SettingsStore.shared.hotkeys
        SettingsStore.shared.onHotkeyChanged = { [weak self] newHotkeys in
            self?.currentHotkeys = newHotkeys
        }
        installMonitors()
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func installMonitors() {
        // Monitor flagsChanged globally (works without accessibility for modifier keys)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(event)
            }
        }

        // Monitor keyDown globally (needs accessibility for some key combos)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleKeyDown(event)
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
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

    private func handleKeyDown(_ event: NSEvent) {
        if currentHotkeys.contains(.f5), event.keyCode == 96 {
            fireToggle(); return
        }
        if currentHotkeys.contains(.optionSpace),
           event.keyCode == 49,
           event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control) {
            fireToggle(); return
        }
        if currentHotkeys.contains(.fnSpace),
           event.keyCode == 49,
           event.modifierFlags.contains(.function),
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.control) {
            fireToggle(); return
        }
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

    private func fireToggle() {
        onToggle?()
    }
}
