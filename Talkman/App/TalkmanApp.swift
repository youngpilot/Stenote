import SwiftUI

@main
struct TalkmanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var recordingManager = RecordingManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(nsImage: recordingManager.isRecording ? Self.micRecordingIcon : Self.micIdleIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private static let solarMicBoldSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="{color}" d="M12 2a5.75 5.75 0 0 0-5.75 5.75v3a5.75 5.75 0 0 0 11.452.75H13a.75.75 0 0 1 0-1.5h4.75V8.5H13A.75.75 0 0 1 13 7h4.701A5.75 5.75 0 0 0 12 2"/><path fill="{color}" fill-rule="evenodd" d="M4 9a.75.75 0 0 1 .75.75v1a7.25 7.25 0 1 0 14.5 0v-1a.75.75 0 0 1 1.5 0v1a8.75 8.75 0 0 1-8 8.718v2.282a.75.75 0 0 1-1.5 0v-2.282a8.75 8.75 0 0 1-8-8.718v-1A.75.75 0 0 1 4 9" clip-rule="evenodd"/></svg>
    """

    static let micIdleIcon: NSImage = {
        let svg = solarMicBoldSVG.replacingOccurrences(of: "{color}", with: "black")
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone")!
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static let micRecordingIcon: NSImage = {
        let svg = solarMicBoldSVG.replacingOccurrences(of: "{color}", with: "#E04848")
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone")!
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }()
}
