import SwiftUI

@main
struct TalkmanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "mic.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
