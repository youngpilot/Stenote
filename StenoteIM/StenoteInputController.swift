import AppKit
import InputMethodKit

// @objc name must match InputMethodServerControllerClass in Info.plist exactly.
@objc(StenoteInputController)
final class StenoteInputController: IMKInputController {

    private var currentComposition = ""

    // Called by IMKit when a text field gains focus with this input source active.
    // Store the client reference so NotificationBridge can call insertText on it.
    override func activateServer(_ sender: Any!) {
        NotificationBridge.shared.activeController = self
    }

    override func deactivateServer(_ sender: Any!) {
        if NotificationBridge.shared.activeController === self {
            NotificationBridge.shared.activeController = nil
        }
    }

    // We don't handle key events — text is driven entirely by DNDC notifications.
    // Returning false passes all keystrokes through to the application.
    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        return false
    }

    // IMKit queries these during composition.
    override func composedString(_ sender: Any!) -> Any! {
        return currentComposition
    }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        return NSAttributedString(string: currentComposition)
    }

    // MARK: - IPC entry points (called by NotificationBridge)

    func updateComposition(_ text: String) {
        currentComposition = text
        client()?.setMarkedText(
            NSAttributedString(string: text),
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    func commitComposition(_ text: String) {
        currentComposition = ""
        client()?.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    func clearComposition() {
        currentComposition = ""
        client()?.setMarkedText(
            NSAttributedString(string: ""),
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}
