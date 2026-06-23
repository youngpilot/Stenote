import AppKit
import InputMethodKit

// Notification names shared between Stenote main app and this IME process.
extension Notification.Name {
    static let stenoteStartComposition  = Notification.Name("com.youngpilot.Stenote.startComposition")
    static let stenoteUpdateComposition = Notification.Name("com.youngpilot.Stenote.updateComposition")
    static let stenoteCommitComposition = Notification.Name("com.youngpilot.Stenote.commitComposition")
    static let stenoteCancelComposition = Notification.Name("com.youngpilot.Stenote.cancelComposition")
}

final class NotificationBridge {
    static let shared = NotificationBridge()

    // The currently active IMKInputController (set by activateServer / deactivateServer).
    weak var activeController: StenoteInputController?

    private init() {}

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleStart(_:)),  name: .stenoteStartComposition,  object: nil)
        dnc.addObserver(self, selector: #selector(handleUpdate(_:)), name: .stenoteUpdateComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCommit(_:)), name: .stenoteCommitComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCancel(_:)), name: .stenoteCancelComposition, object: nil)
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
