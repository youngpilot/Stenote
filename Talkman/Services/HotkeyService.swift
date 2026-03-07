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
    private var currentHotkey: HotkeyChoice = .doubleRightCmd

    var onToggle: (() -> Void)?

    func start() {
        currentHotkey = SettingsStore.shared.hotkey
        SettingsStore.shared.onHotkeyChanged = { [weak self] newHotkey in
            self?.currentHotkey = newHotkey
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
        switch currentHotkey {
        case .doubleRightCmd:
            // Right Cmd keyCode is 54; check if Cmd flag is now set (key-down moment)
            guard event.keyCode == 54, event.modifierFlags.contains(.command) else { return }
            checkDoublePress()
        case .doubleFn:
            guard event.keyCode == 63, event.modifierFlags.contains(.function) else { return }
            checkDoublePress()
        default:
            break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch currentHotkey {
        case .f5:
            guard event.keyCode == 96 else { return }
            fireToggle()
        case .f6:
            guard event.keyCode == 97 else { return }
            fireToggle()
        case .controlShiftSpace:
            guard event.keyCode == 49,
                  event.modifierFlags.contains(.control),
                  event.modifierFlags.contains(.shift) else { return }
            fireToggle()
        default:
            break
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
