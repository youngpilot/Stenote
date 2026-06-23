import ServiceManagement
import SwiftUI
import Observation

enum VadSensitivity: String, CaseIterable, Identifiable {
    case quick = "quick"
    case normal = "normal"
    case patient = "patient"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick (0.4s)"
        case .normal: "Normal (0.75s)"
        case .patient: "Patient (1.5s)"
        }
    }

    var minSilenceDuration: TimeInterval {
        switch self {
        case .quick: 0.4
        case .normal: 0.75
        case .patient: 1.5
        }
    }
}

enum AutoStopOption: Int, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case thirty = 30
    case sixty = 60
    case off = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .ten: "10s"
        case .twenty: "20s"
        case .thirty: "30s"
        case .sixty: "60s"
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

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    // Stored properties for @Observable tracking, synced to UserDefaults
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
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

    var vadSensitivity: VadSensitivity {
        didSet { UserDefaults.standard.set(vadSensitivity.rawValue, forKey: "vadSensitivity") }
    }

    var autoStopTimeout: AutoStopOption {
        didSet { UserDefaults.standard.set(autoStopTimeout.rawValue, forKey: "autoStopTimeout") }
    }

    /// When recording, mute all output to silence and pause Spotify / Apple
    /// Music if playing. On by default.
    var silenceMediaWhileRecording: Bool {
        didSet { UserDefaults.standard.set(silenceMediaWhileRecording, forKey: "silenceMediaWhileRecording") }
    }

    var enableVocabBoosting: Bool {
        didSet { UserDefaults.standard.set(enableVocabBoosting, forKey: "enableVocabBoosting") }
    }

    var insertionMode: InsertionMode {
        didSet { UserDefaults.standard.set(insertionMode.rawValue, forKey: "insertionMode") }
    }

    var enableVoiceCommands: Bool {
        didSet { UserDefaults.standard.set(enableVoiceCommands, forKey: "enableVoiceCommands") }
    }

    var updateCheckMode: UpdateCheckMode {
        didSet { UserDefaults.standard.set(updateCheckMode.rawValue, forKey: "updateCheckMode") }
    }

    var historyPreviewLines: Int {
        didSet { UserDefaults.standard.set(historyPreviewLines, forKey: "historyPreviewLines") }
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
        vadSensitivity = .normal
        autoStopTimeout = .thirty
        silenceMediaWhileRecording = true
        enableVocabBoosting = false
        insertionMode = .auto
        enableVoiceCommands = false
        updateCheckMode = .manual
        historyPreviewLines = 3
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
        self.vadSensitivity = VadSensitivity(rawValue: ud.string(forKey: "vadSensitivity") ?? "") ?? .normal
        self.autoStopTimeout = {
            if ud.object(forKey: "autoStopTimeout") == nil { return .thirty }
            return AutoStopOption(rawValue: ud.integer(forKey: "autoStopTimeout")) ?? .thirty
        }()
        // New key wins; else migrate the old picker (.none → off, otherwise on); else default on.
        if ud.object(forKey: "silenceMediaWhileRecording") != nil {
            self.silenceMediaWhileRecording = ud.bool(forKey: "silenceMediaWhileRecording")
        } else if let legacy = ud.string(forKey: "mediaPlaybackOption") {
            self.silenceMediaWhileRecording = (legacy != "none")
        } else {
            self.silenceMediaWhileRecording = true
        }
        self.enableVocabBoosting = ud.object(forKey: "enableVocabBoosting") == nil ? false : ud.bool(forKey: "enableVocabBoosting")
        self.insertionMode = InsertionMode(rawValue: ud.string(forKey: "insertionMode") ?? "") ?? .auto
        self.enableVoiceCommands = ud.bool(forKey: "enableVoiceCommands")
        self.updateCheckMode = UpdateCheckMode(rawValue: ud.string(forKey: "updateCheckMode") ?? "") ?? .manual
        self.historyPreviewLines = ud.object(forKey: "historyPreviewLines") == nil ? 3 : ud.integer(forKey: "historyPreviewLines")
        self.exportDirectory = ud.string(forKey: "exportDirectory") ?? SettingsStore.defaultDownloadsPath
    }

    static let defaultDownloadsPath: String = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
    }()
}
