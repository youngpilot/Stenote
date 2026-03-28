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

enum MediaPlaybackOption: String, CaseIterable, Identifiable {
    case none = "none"
    case stopMedia = "stopMedia"
    case muteOnly = "muteOnly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Don't interrupt"
        case .stopMedia: "Pause & Resume"
        case .muteOnly: "Mute Only"
        }
    }
}

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case accurate = "accurate"
    case live = "live"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: "Live"
        case .accurate: "Accurate"
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

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    // Stored properties for @Observable tracking, synced to UserDefaults
    var enableITN: Bool {
        didSet { UserDefaults.standard.set(enableITN, forKey: "enableITN") }
    }

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

    var mediaPlaybackOption: MediaPlaybackOption {
        didSet { UserDefaults.standard.set(mediaPlaybackOption.rawValue, forKey: "mediaPlaybackOption") }
    }

    var enableVocabBoosting: Bool {
        didSet { UserDefaults.standard.set(enableVocabBoosting, forKey: "enableVocabBoosting") }
    }

    var transcriptionMode: TranscriptionMode {
        didSet { UserDefaults.standard.set(transcriptionMode.rawValue, forKey: "transcriptionMode") }
    }

    var insertionMode: InsertionMode {
        didSet { UserDefaults.standard.set(insertionMode.rawValue, forKey: "insertionMode") }
    }

    var enableVoiceCommands: Bool {
        didSet { UserDefaults.standard.set(enableVoiceCommands, forKey: "enableVoiceCommands") }
    }

    var historyPreviewLines: Int {
        didSet { UserDefaults.standard.set(historyPreviewLines, forKey: "historyPreviewLines") }
    }

    var exportDirectory: String {
        didSet { UserDefaults.standard.set(exportDirectory, forKey: "exportDirectory") }
    }

    var onHotkeyChanged: ((Set<HotkeyChoice>) -> Void)?

    func resetToDefaults() {
        enableITN = true
        hotkeys = [.doubleRightOption]
        politenessMode = false
        prefixText = ""
        suffixText = ""
        vadSensitivity = .normal
        autoStopTimeout = .thirty
        mediaPlaybackOption = .none
        enableVocabBoosting = false
        transcriptionMode = .accurate
        insertionMode = .auto
        enableVoiceCommands = false
        historyPreviewLines = 3
        exportDirectory = SettingsStore.defaultDownloadsPath
    }

    private init() {
        let ud = UserDefaults.standard
        self.enableITN = ud.object(forKey: "enableITN") == nil ? true : ud.bool(forKey: "enableITN")
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
        self.mediaPlaybackOption = MediaPlaybackOption(rawValue: ud.string(forKey: "mediaPlaybackOption") ?? "") ?? .none
        self.enableVocabBoosting = ud.object(forKey: "enableVocabBoosting") == nil ? false : ud.bool(forKey: "enableVocabBoosting")
        self.transcriptionMode = TranscriptionMode(rawValue: ud.string(forKey: "transcriptionMode") ?? "") ?? .accurate
        self.insertionMode = InsertionMode(rawValue: ud.string(forKey: "insertionMode") ?? "") ?? .auto
        self.enableVoiceCommands = ud.bool(forKey: "enableVoiceCommands")
        self.historyPreviewLines = ud.object(forKey: "historyPreviewLines") == nil ? 3 : ud.integer(forKey: "historyPreviewLines")
        self.exportDirectory = ud.string(forKey: "exportDirectory") ?? SettingsStore.defaultDownloadsPath
    }

    static let defaultDownloadsPath: String = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
    }()
}
