import AppKit
import Observation

@Observable
@MainActor
final class OutputService {
    private var sourceApp: NSRunningApplication?
    private var originalPasteboardContents: [NSPasteboardItem]?

    func rememberSourceApp() {
        sourceApp = NSWorkspace.shared.frontmostApplication
    }

    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // Save current clipboard
        savePasteboard()

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Activate source app and paste
        sourceApp?.activate()

        // Small delay to let app activate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste()

            // Restore clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.restorePasteboard()
            }
        }
    }

    private func simulatePaste() {
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func savePasteboard() {
        // Simple save — just remember we modified it
        originalPasteboardContents = NSPasteboard.general.pasteboardItems?.compactMap { item in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
    }

    private func restorePasteboard() {
        guard let items = originalPasteboardContents else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
        originalPasteboardContents = nil
    }
}
