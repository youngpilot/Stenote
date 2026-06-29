import AppKit
import InputMethodKit

// Notification names shared between Steneo main app and this IME process.
extension Notification.Name {
    static let steneoStartComposition  = Notification.Name("com.youngpilot.Steneo.startComposition")
    static let steneoUpdateComposition = Notification.Name("com.youngpilot.Steneo.updateComposition")
    static let steneoCommitComposition = Notification.Name("com.youngpilot.Steneo.commitComposition")
    static let steneoCancelComposition = Notification.Name("com.youngpilot.Steneo.cancelComposition")
}

final class NotificationBridge {
    static let shared = NotificationBridge()

    // The currently active IMKInputController (set by activateServer / deactivateServer).
    weak var activeController: SteneoInputController?

    private init() {}

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleStart(_:)),  name: .steneoStartComposition,  object: nil)
        dnc.addObserver(self, selector: #selector(handleUpdate(_:)), name: .steneoUpdateComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCommit(_:)), name: .steneoCommitComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCancel(_:)), name: .steneoCancelComposition, object: nil)
    }

    // MARK: - Handlers

    @objc private func handleStart(_ note: Notification) {
        // Nothing to do yet — composition begins implicitly on first update.
    }

    @objc private func handleUpdate(_ note: Notification) {
        guard let text = note.userInfo?["text"] as? String else { return }
        activeController?.updateComposition(text)
    }

    @objc private func handleCommit(_ note: Notification) {
        guard let text = note.userInfo?["text"] as? String else { return }
        activeController?.commitComposition(text)
    }

    @objc private func handleCancel(_ note: Notification) {
        activeController?.clearComposition()
    }
}
