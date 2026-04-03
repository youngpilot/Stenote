import AppKit
import InputMethodKit

// Notification names shared between Talkman main app and this IME process.
extension Notification.Name {
    static let talkmanStartComposition  = Notification.Name("com.youngpilot.Talkman.startComposition")
    static let talkmanUpdateComposition = Notification.Name("com.youngpilot.Talkman.updateComposition")
    static let talkmanCommitComposition = Notification.Name("com.youngpilot.Talkman.commitComposition")
    static let talkmanCancelComposition = Notification.Name("com.youngpilot.Talkman.cancelComposition")
}

final class NotificationBridge {
    static let shared = NotificationBridge()

    // The currently active IMKInputController (set by activateServer / deactivateServer).
    weak var activeController: TalkmanInputController?

    private init() {}

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleStart(_:)),  name: .talkmanStartComposition,  object: nil)
        dnc.addObserver(self, selector: #selector(handleUpdate(_:)), name: .talkmanUpdateComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCommit(_:)), name: .talkmanCommitComposition, object: nil)
        dnc.addObserver(self, selector: #selector(handleCancel(_:)), name: .talkmanCancelComposition, object: nil)
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
