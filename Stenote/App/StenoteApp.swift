import SwiftUI

@main
struct StenoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private static let solarMicSVGTemplate = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="{topColor}" d="M12 2a5.75 5.75 0 0 0-5.75 5.75v3a5.75 5.75 0 0 0 11.452.75H13a.75.75 0 0 1 0-1.5h4.75V8.5H13A.75.75 0 0 1 13 7h4.701A5.75 5.75 0 0 0 12 2"/><path fill="{bottomColor}" fill-rule="evenodd" d="M4 9a.75.75 0 0 1 .75.75v1a7.25 7.25 0 1 0 14.5 0v-1a.75.75 0 0 1 1.5 0v1a8.75 8.75 0 0 1-8 8.718v2.282a.75.75 0 0 1-1.5 0v-2.282a8.75 8.75 0 0 1-8-8.718v-1A.75.75 0 0 1 4 9" clip-rule="evenodd"/></svg>
    """

    private static func makeSVGImage(topColor: String, bottomColor: String) -> NSImage? {
        let svg = solarMicSVGTemplate
            .replacingOccurrences(of: "{topColor}", with: topColor)
            .replacingOccurrences(of: "{bottomColor}", with: bottomColor)
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    static let micIdleIcon: NSImage = {
        guard let image = makeSVGImage(topColor: "black", bottomColor: "black") else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone")!
        }
        image.isTemplate = true
        return image
    }()

    static let micRecordingIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let standColor = isDark ? "white" : "black"
            if let svgImage = makeSVGImage(topColor: "#E04848", bottomColor: standColor) {
                svgImage.draw(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }()

    /// Shown for the brief moment between pressing the shortcut and the audio
    /// engine being live — amber "got it, starting".
    static let micStartingIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let standColor = isDark ? "white" : "black"
            if let svgImage = makeSVGImage(topColor: "#E0A21E", bottomColor: standColor) {
                svgImage.draw(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }()
}

/// The menubar status item. While recording, the red mic gently breathes
/// (opacity) so "it's listening" reads at a glance — a menubar app's only
/// always-visible surface. The pulse loop only runs while recording (no idle
/// timer), and it's a status item, not a Liquid-Glass tap target.
private struct MenuBarLabel: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var dimmed = false

    var body: some View {
        Image(nsImage: icon)
            .opacity(recordingManager.isRecording && dimmed ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.6), value: dimmed)
            .task(id: recordingManager.isRecording) {
                dimmed = false
                guard recordingManager.isRecording else { return }
                while !Task.isCancelled && recordingManager.isRecording {
                    dimmed.toggle()
                    try? await Task.sleep(for: .milliseconds(600))
                }
                dimmed = false
            }
    }

    private var icon: NSImage {
        recordingManager.isStarting
            ? StenoteApp.micStartingIcon
            : (recordingManager.isRecording ? StenoteApp.micRecordingIcon : StenoteApp.micIdleIcon)
    }
}
