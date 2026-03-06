import SwiftUI
import Observation

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    var autoLanguageDetect: Bool {
        get { UserDefaults.standard.bool(forKey: "autoLanguageDetect") }
        set { UserDefaults.standard.set(newValue, forKey: "autoLanguageDetect") }
    }

    var enableITN: Bool {
        get {
            if UserDefaults.standard.object(forKey: "enableITN") == nil { return true }
            return UserDefaults.standard.bool(forKey: "enableITN")
        }
        set { UserDefaults.standard.set(newValue, forKey: "enableITN") }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }

    private init() {}
}
