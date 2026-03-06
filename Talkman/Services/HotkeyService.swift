import AppKit
import Carbon
import Observation

@Observable
@MainActor
final class HotkeyService {
    private var eventTap: CFMachPort?
    private var lastRightCmdPress: Date?
    private let doublePressInterval: TimeInterval = 0.4

    var onToggle: (() -> Void)?

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            service.handleFlagsChanged(event)
            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("Failed to create event tap — check Accessibility permissions")
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Right Command key code is 54
        let isRightCmd = keyCode == 54

        guard isRightCmd else { return }

        // Detect key-down (flag added)
        if flags.contains(.maskCommand) {
            let now = Date()
            if let last = lastRightCmdPress, now.timeIntervalSince(last) < doublePressInterval {
                lastRightCmdPress = nil
                Task { @MainActor in
                    self.onToggle?()
                }
            } else {
                lastRightCmdPress = now
            }
        }
    }
}
