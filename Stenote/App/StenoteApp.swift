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

    // --- Recording: a steady macOS-orange mic with a deep-red level rising inside
    // the mic head — a tiny live waveform. The orange base never fluctuates; only
    // the red level (and its gentle wavy top) tracks your voice. ---
    private static let recordingOrange = "#FF9500"   // macOS systemOrange

    /// Just the mic-head (capsule) shape — used to clip the red level to the head.
    private static let capsuleOnlySVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="#000000" d="M12 2a5.75 5.75 0 0 0-5.75 5.75v3a5.75 5.75 0 0 0 11.452.75H13a.75.75 0 0 1 0-1.5h4.75V8.5H13A.75.75 0 0 1 13 7h4.701A5.75 5.75 0 0 0 12 2"/></svg>
    """

    private static let orangeMicImage: NSImage =
        makeSVGImage(topColor: recordingOrange, bottomColor: recordingOrange) ?? micIdleIcon

    private static let capsuleMaskImage: NSImage = {
        guard let data = capsuleOnlySVG.data(using: .utf8), let img = NSImage(data: data) else { return NSImage() }
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    @MainActor private static var recordingIconCache: [Int: NSImage] = [:]

    /// Recording icon: steady orange mic, deep-red level filling the mic head from
    /// below as you get louder, with a gentle wavy top so it reads as a tiny live
    /// waveform. Quantized into level buckets and cached for efficiency.
    @MainActor static func recordingIcon(level: Float) -> NSImage {
        let steps = 24
        let clamped = min(max(level, 0), 1)
        let bucket = Int((clamped * Float(steps - 1)).rounded())
        if let cached = recordingIconCache[bucket] { return cached }

        let size = NSSize(width: 18, height: 18)
        let bounds = NSRect(origin: .zero, size: size)

        // Fill height inside the mic head (points, origin bottom-left), kept within
        // the capsule's vertical band so there's always a little red at the bottom
        // and it never overflows the head.
        let frac = 0.15 + Double(bucket) / Double(steps - 1) * 0.80   // 15%..95%
        let fillTop = 8.0 + CGFloat(frac) * 7.5                       // ~8.0 .. 15.5
        let phase = Double(bucket) * 0.7                             // subtle flow as level moves

        // 1) Deep-red wavy fill across the full width.
        let redWave = NSImage(size: size)
        redWave.lockFocus()
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 0, y: 0))
        var x: CGFloat = 0
        while x <= 18 {
            let y = fillTop + 0.9 * CGFloat(sin(Double(x) / 18.0 * 4 * .pi + phase))  // ~2 humps
            wave.line(to: NSPoint(x: x, y: y))
            x += 1
        }
        wave.line(to: NSPoint(x: 18, y: 0))
        wave.close()
        NSColor(srgbRed: 0.784, green: 0.118, blue: 0.118, alpha: 1).setFill()       // deep red
        wave.fill()
        redWave.unlockFocus()

        // 2) Keep the red only inside the mic head.
        let redInHead = NSImage(size: size)
        redInHead.lockFocus()
        capsuleMaskImage.draw(in: bounds)
        redWave.draw(in: bounds, from: .zero, operation: .sourceIn, fraction: 1)
        redInHead.unlockFocus()

        // 3) Steady orange mic + the red level on top.
        let icon = NSImage(size: size)
        icon.lockFocus()
        orangeMicImage.draw(in: bounds)
        redInHead.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        icon.unlockFocus()
        icon.isTemplate = false

        recordingIconCache[bucket] = icon
        return icon
    }

    /// Transcribing an audio file — a calm blue.
    static let micTranscribingIcon: NSImage = coloredMicIcon(top: "#3B82F6")

    /// A file transcription just finished and is waiting to be seen — a calm green.
    static let micDoneIcon: NSImage = coloredMicIcon(top: "#34C759")
}

/// The menubar status item reflects state: a steady orange mic while recording,
/// with a deep-red level rising inside the head as you speak (a tiny live
/// waveform); blue while transcribing a file; green when a transcription is ready;
/// otherwise the default mic. The blue transcribing state gently breathes (no mic
/// signal to drive it). It's a status item, not a Liquid-Glass tap target.
private struct MenuBarLabel: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var dimmed = false

    /// Only the file-transcription (blue) state uses the timed breathe — recording
    /// shows the live red level instead.
    private var isBreathing: Bool {
        recordingManager.isTranscribingFile && !recordingManager.isRecording
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
        // No separate "starting" state — go straight to the recording visualization.
        if recordingManager.isRecording || recordingManager.isStarting {
            return StenoteApp.recordingIcon(level: recordingManager.inputLevel)
        }
        if recordingManager.isTranscribingFile { return StenoteApp.micTranscribingIcon }
        if recordingManager.fileTranscriptionDone { return StenoteApp.micDoneIcon }
        return StenoteApp.micIdleIcon
    }
}
