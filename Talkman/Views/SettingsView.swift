import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Transcription") {
                Toggle("Auto-detect language", isOn: Binding(
                    get: { settings.autoLanguageDetect },
                    set: { settings.autoLanguageDetect = $0 }
                ))
                Toggle("Inverse Text Normalization", isOn: Binding(
                    get: { settings.enableITN },
                    set: { settings.enableITN = $0 }
                ))
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("Shortcut") {
                Text("Double-press Right Command to toggle recording")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
