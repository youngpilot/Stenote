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
    case doubleRightCmd = "doubleRightCmd"
    case f5 = "f5"
    case f6 = "f6"
    case doubleFn = "doubleFn"
    case controlShiftSpace = "controlShiftSpace"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .doubleRightCmd: "Double-press Right ⌘"
        case .f5: "F5"
        case .f6: "F6"
        case .doubleFn: "Double-press Fn/🌐"
        case .controlShiftSpace: "⌃⇧Space"
        }
    }

    var needsFunctionKeyHint: Bool {
        self == .f5 || self == .f6
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

    var hotkey: HotkeyChoice {
        didSet {
            UserDefaults.standard.set(hotkey.rawValue, forKey: "hotkey")
            onHotkeyChanged?(hotkey)
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

    var muteAudioDuringRecording: Bool {
        didSet { UserDefaults.standard.set(muteAudioDuringRecording, forKey: "muteAudioDuringRecording") }
    }

    var onHotkeyChanged: ((HotkeyChoice) -> Void)?

    func resetToDefaults() {
        enableITN = true
        hotkey = .doubleRightCmd
        politenessMode = false
        prefixText = ""
        suffixText = ""
        vadSensitivity = .normal
        autoStopTimeout = .thirty
        muteAudioDuringRecording = false
    }

    private init() {
        let ud = UserDefaults.standard
        self.enableITN = ud.object(forKey: "enableITN") == nil ? true : ud.bool(forKey: "enableITN")
        self.hotkey = HotkeyChoice(rawValue: ud.string(forKey: "hotkey") ?? "") ?? .doubleRightCmd
        self.politenessMode = ud.bool(forKey: "politenessMode")
        self.suffixText = ud.string(forKey: "suffixText") ?? ""
        self.prefixText = ud.string(forKey: "prefixText") ?? ""
        self.vadSensitivity = VadSensitivity(rawValue: ud.string(forKey: "vadSensitivity") ?? "") ?? .normal
        self.autoStopTimeout = {
            if ud.object(forKey: "autoStopTimeout") == nil { return .thirty }
            return AutoStopOption(rawValue: ud.integer(forKey: "autoStopTimeout")) ?? .thirty
        }()
        self.muteAudioDuringRecording = ud.bool(forKey: "muteAudioDuringRecording")
    }
}
