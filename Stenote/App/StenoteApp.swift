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

    /// A non-template mic icon whose capsule (top) uses `top`; the stand adapts to
    /// the menu bar's light/dark appearance.
    private static func coloredMicIcon(top: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if let svg = makeSVGImage(topColor: top, bottomColor: isDark ? "white" : "black") {
                svg.draw(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Recording — a clean, deep-red mic head with the stand adapting to light/dark.
    /// Static (no animation, no level fill); shown the moment recording starts.
    static let micRecordingIcon: NSImage = coloredMicIcon(top: "#E04848")

    /// Transcribing an audio file — a warm yellow that matches the drag-over
    /// highlight, so "processing" reads the same whether you dropped or are waiting.
    static let micTranscribingIcon: NSImage = coloredMicIcon(top: "#E6A23C")

    /// A file transcription just finished and is waiting to be seen — a calm green.
    static let micDoneIcon: NSImage = coloredMicIcon(top: "#34C759")
}

/// The menubar status item reflects state: a deep-red mic while recording; warm
/// yellow while transcribing a file; green when a transcription is ready; otherwise
/// the default mic. The yellow transcribing state gently breathes (no mic signal to
/// drive it) to read as "processing". It's a status item, not a Liquid-Glass tap target.
private struct MenuBarLabel: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var dimmed = false

    /// The yellow "processing" states use the timed breathe (file transcription and
    /// the post-record LLM pass) — recording shows static red instead.
    private var isBreathing: Bool {
        (recordingManager.isTranscribingFile || recordingManager.isPostProcessing) && !recordingManager.isRecording
    }

    var body: some View {
        Image(nsImage: icon)
            .opacity(isBreathing && dimmed ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.6), value: dimmed)
            .task(id: isBreathing) {
                dimmed = false
                guard isBreathing else { return }
                while !Task.isCancelled && isBreathing {
                    dimmed.toggle()
                    try? await Task.sleep(for: .milliseconds(600))
                }
                dimmed = false
            }
    }

    private var icon: NSImage {
        // Red == actually recording (only once the mic is live), so a red mic
        // always means "your audio is being captured" — never a dead warm-up window.
        if recordingManager.isRecording { return StenoteApp.micRecordingIcon }
        if recordingManager.isTranscribingFile || recordingManager.isPostProcessing { return StenoteApp.micTranscribingIcon }
        if recordingManager.fileTranscriptionDone { return StenoteApp.micDoneIcon }
        return StenoteApp.micIdleIcon
    }
}
