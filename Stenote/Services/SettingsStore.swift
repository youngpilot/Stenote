import ServiceManagement
import SwiftUI
import Observation
import os

private let launchLoginLogger = Logger(subsystem: "com.youngpilot.Stenote", category: "LaunchAtLogin")

enum AutoStopOption: Int, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case thirty = 30
    case sixty = 60
    case twoMin = 120
    case fiveMin = 300
    case off = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .ten: "10s"
        case .twenty: "20s"
        case .thirty: "30s"
        case .sixty: "1 min"
        case .twoMin: "2 min"
        case .fiveMin: "5 min"
        case .off: "Off"
        }
    }
}


enum HotkeyChoice: String, CaseIterable, Identifiable {
    case doubleRightOption = "doubleRightOption"
    case doubleRightCmd = "doubleRightCmd"
    case optionSpace = "optionSpace"
    case fnSpace = "fnSpace"
    case f5 = "f5"
    case doubleFn = "doubleFn"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .doubleRightOption: "Double-press Right ⌥"
        case .doubleRightCmd: "Double-press Right ⌘"
        case .optionSpace: "⌥ + Space"
        case .fnSpace: "Fn + Space"
        case .f5: "F5"
        case .doubleFn: "Double-press Fn/🌐"
        }
    }

    var needsFunctionKeyHint: Bool {
        self == .f5
    }
}

enum UpdateCheckMode: String, CaseIterable, Identifiable {
    case manual = "manual"   // no automatic outbound calls
    case daily = "daily"     // one background check per 24h

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .daily: "Daily"
        }
    }
}

enum HistoryLength: Int, CaseIterable, Identifiable {
    case none = 0
    case ten = 10
    case twenty = 20
    case fifty = 50
    case hundred = 100
    case unlimited = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .unlimited: "Unlimited"
        default: "\(rawValue)"
        }
    }

    /// Max entries to keep; nil = unlimited.
    var cap: Int? {
        switch self {
        case .none: 0
        case .unlimited: nil
        default: rawValue
        }
    }
}

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    // Stored properties for @Observable tracking, synced to UserDefaults

    /// Stored mirror of the login-item state. This MUST be a stored property:
    /// `@Observable` only tracks stored properties, so the previous computed
    /// `{ SMAppService.mainApp.status == .enabled }` was invisible to SwiftUI —
    /// toggling it never re-rendered the bound Toggle, so it looked dead even
    /// though registration had succeeded. We update this optimistically and
    /// reconcile with the real status (reverting + logging on failure).
    private(set) var launchAtLoginEnabled: Bool = (SMAppService.mainApp.status == .enabled)

    var launchAtLogin: Bool {
        get { launchAtLoginEnabled }
        set { setLaunchAtLogin(newValue) }
    }

    /// Re-reads the authoritative status (e.g. the user may have toggled the app
    /// off in System Settings › General › Login Items while we weren't running).
    func refreshLaunchAtLoginStatus() {
        let actual = (SMAppService.mainApp.status == .enabled)
        if actual != launchAtLoginEnabled { launchAtLoginEnabled = actual }
    }

    /// Registers/unregisters the main app as a login item, surfacing the real
    /// failure reason instead of swallowing it with `try?`. `SMAppService.mainApp`
    /// requires a Developer ID-signed app in a stable location (e.g. /Applications);
    /// a translocated or unsigned build throws `Operation not permitted`.
    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let before = service.status
        launchAtLoginEnabled = enabled  // optimistic — UI reflects the click immediately
        do {
            if enabled {
                if before != .enabled { try service.register() }
            } else {
                if before == .enabled { try service.unregister() }
            }
            if enabled && service.status == .requiresApproval {
                // macOS parked it pending user approval — send them to the toggle.
                launchLoginLogger.notice("Launch at login requires approval in System Settings › General › Login Items")
                SMAppService.openSystemSettingsLoginItems()
            }
            launchLoginLogger.info(
                "Launch at login \(enabled ? "enabled" : "disabled", privacy: .public); status \(before.rawValue) -> \(service.status.rawValue)")
        } catch {
            launchAtLoginEnabled = (service.status == .enabled)  // revert to reality
            launchLoginLogger.error(
                "Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed (status \(before.rawValue)): \(error.localizedDescription, privacy: .public)")
        }
    }

    var hotkeys: Set<HotkeyChoice> {
        didSet {
            UserDefaults.standard.set(Array(hotkeys.map { $0.rawValue }), forKey: "hotkeys")
            onHotkeyChanged?(hotkeys)
        }
    }

    var politenessMode: Bool {
        didSet {
            UserDefaults.standard.set(politenessMode, forKey: "politenessMode")
            if politenessMode && suffixText.isEmpty {
                suffixText = "Thank you!"
            } else if !politenessMode && suffixText == "Thank you!" {
                suffixText = ""
            }
        }
    }

    var suffixText: String {
        didSet { UserDefaults.standard.set(suffixText, forKey: "suffixText") }
    }

    var prefixText: String {
        didSet { UserDefaults.standard.set(prefixText, forKey: "prefixText") }
    }

    var autoStopTimeout: AutoStopOption {
        didSet { UserDefaults.standard.set(autoStopTimeout.rawValue, forKey: "autoStopTimeout") }
    }

    /// When recording, mute all system output to silence. On by default.
    var silenceMediaWhileRecording: Bool {
        didSet { UserDefaults.standard.set(silenceMediaWhileRecording, forKey: "silenceMediaWhileRecording") }
    }

    /// When recording, pause Spotify / Apple Music if playing (and resume
    /// after). Independent of muting. On by default.
    var pauseMediaApps: Bool {
        didSet { UserDefaults.standard.set(pauseMediaApps, forKey: "pauseMediaApps") }
    }

    var enableVocabBoosting: Bool {
        didSet { UserDefaults.standard.set(enableVocabBoosting, forKey: "enableVocabBoosting") }
    }

    /// How dictated text is cleaned up after recording: Off / Rules (deterministic
    /// filler removal) / AI (on-device Foundation Models). Default Off. Text never
    /// leaves the Mac in any mode.
    var cleanupMode: CleanupMode {
        didSet { UserDefaults.standard.set(cleanupMode.rawValue, forKey: "cleanupMode") }
    }

    var insertionMode: InsertionMode {
        didSet { UserDefaults.standard.set(insertionMode.rawValue, forKey: "insertionMode") }
    }

    var enableVoiceCommands: Bool {
        didSet { UserDefaults.standard.set(enableVoiceCommands, forKey: "enableVoiceCommands") }
    }

    /// Which individual voice commands are active (when `enableVoiceCommands` is on).
    var enabledVoiceCommandIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledVoiceCommandIDs), forKey: "enabledVoiceCommandIDs") }
    }

    /// "<word> emoji" / "emoji <word>" → a fitting emoji (curated, on-device).
    var enableEmojiCommands: Bool {
        didSet { UserDefaults.standard.set(enableEmojiCommands, forKey: "enableEmojiCommands") }
    }

    var updateCheckMode: UpdateCheckMode {
        didSet { UserDefaults.standard.set(updateCheckMode.rawValue, forKey: "updateCheckMode") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var historyPreviewLines: Int {
        didSet { UserDefaults.standard.set(historyPreviewLines, forKey: "historyPreviewLines") }
    }

    /// How many recordings show per page in the menubar history (1…10).
    var historyPageSize: Int {
        didSet { UserDefaults.standard.set(historyPageSize, forKey: "historyPageSize") }
    }

    var historyLength: HistoryLength {
        didSet { UserDefaults.standard.set(historyLength.rawValue, forKey: "historyLength") }
    }

    var exportDirectory: String {
        didSet { UserDefaults.standard.set(exportDirectory, forKey: "exportDirectory") }
    }

    var onHotkeyChanged: ((Set<HotkeyChoice>) -> Void)?

    func resetToDefaults() {
        hotkeys = [.doubleRightOption]
        politenessMode = false
        prefixText = ""
        suffixText = ""
        autoStopTimeout = .sixty
        silenceMediaWhileRecording = true
        pauseMediaApps = true
        enableVocabBoosting = false
        cleanupMode = .off
        insertionMode = .auto
        enableVoiceCommands = false
        enabledVoiceCommandIDs = Set(VoiceCommandID.allCases.map(\.rawValue))
        enableEmojiCommands = false
        updateCheckMode = .manual
        historyPreviewLines = 3
        historyPageSize = 5
        historyLength = .twenty
        exportDirectory = SettingsStore.defaultDownloadsPath
    }

    private init() {
        let ud = UserDefaults.standard
        // Migrate from old single "hotkey" key if needed
        if let rawValues = ud.stringArray(forKey: "hotkeys") {
            let parsed = Set(rawValues.compactMap { HotkeyChoice(rawValue: $0) })
            self.hotkeys = parsed.isEmpty ? [.doubleRightOption] : parsed
        } else if let legacy = ud.string(forKey: "hotkey").flatMap({ HotkeyChoice(rawValue: $0) }) {
            self.hotkeys = [legacy]
        } else {
            self.hotkeys = [.doubleRightOption]
        }
        self.politenessMode = ud.bool(forKey: "politenessMode")
        self.suffixText = ud.string(forKey: "suffixText") ?? ""
        self.prefixText = ud.string(forKey: "prefixText") ?? ""
        self.autoStopTimeout = {
            if ud.object(forKey: "autoStopTimeout") == nil { return .sixty }
            return AutoStopOption(rawValue: ud.integer(forKey: "autoStopTimeout")) ?? .sixty
        }()
        // New key wins; else migrate the old picker (.none → off, otherwise on); else default on.
        if ud.object(forKey: "silenceMediaWhileRecording") != nil {
            self.silenceMediaWhileRecording = ud.bool(forKey: "silenceMediaWhileRecording")
        } else if let legacy = ud.string(forKey: "mediaPlaybackOption") {
            self.silenceMediaWhileRecording = (legacy != "none")
        } else {
            self.silenceMediaWhileRecording = true
        }
        self.pauseMediaApps = ud.object(forKey: "pauseMediaApps") == nil ? true : ud.bool(forKey: "pauseMediaApps")
        self.enableVocabBoosting = ud.object(forKey: "enableVocabBoosting") == nil ? false : ud.bool(forKey: "enableVocabBoosting")
        // Migrate the old boolean toggle: on → Rules (the safe default), off → Off.
        if let raw = ud.string(forKey: "cleanupMode"), let mode = CleanupMode(rawValue: raw) {
            self.cleanupMode = mode
        } else {
            self.cleanupMode = ud.bool(forKey: "cleanupText") ? .rules : .off
        }
        self.insertionMode = InsertionMode(rawValue: ud.string(forKey: "insertionMode") ?? "") ?? .auto
        self.enableVoiceCommands = ud.bool(forKey: "enableVoiceCommands")
        self.enabledVoiceCommandIDs = (ud.array(forKey: "enabledVoiceCommandIDs") as? [String]).map(Set.init)
            ?? Set(VoiceCommandID.allCases.map(\.rawValue))
        self.enableEmojiCommands = ud.bool(forKey: "enableEmojiCommands")
        self.updateCheckMode = UpdateCheckMode(rawValue: ud.string(forKey: "updateCheckMode") ?? "") ?? .manual
        self.hasCompletedOnboarding = ud.bool(forKey: "hasCompletedOnboarding")
        self.historyPreviewLines = ud.object(forKey: "historyPreviewLines") == nil ? 3 : ud.integer(forKey: "historyPreviewLines")
        self.historyPageSize = ud.object(forKey: "historyPageSize") == nil ? 5 : ud.integer(forKey: "historyPageSize")
        self.historyLength = ud.object(forKey: "historyLength") == nil ? .twenty : (HistoryLength(rawValue: ud.integer(forKey: "historyLength")) ?? .twenty)
        self.exportDirectory = ud.string(forKey: "exportDirectory") ?? SettingsStore.defaultDownloadsPath
    }

    static let defaultDownloadsPath: String = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
    }()
}
