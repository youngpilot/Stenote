import SwiftUI

/// A boxed input-level meter: a scrolling strip of a few-pixel-wide bars, each
/// one honest mic-level time-slice. Reads the smoothed `inputLevel` directly
/// (so updates don't invalidate the whole popover) and keeps its own bar ring.
struct WaveformView: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var bars: [Float] = []

    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 2
    private let inset: CGFloat = 4          // keep bars clear of the rounded box
    private let maxHalf: CGFloat = 13       // half-height within the 32pt box
    private let capacity = 256              // bar-ring cap (well over what fits)

    var body: some View {
        Canvas { context, size in
            let pitch = barWidth + gap
            let count = max(1, Int((size.width - inset * 2) / pitch))
            let midY = size.height / 2
            let visible = Array(bars.suffix(count))
            let leftPad = count - visible.count   // fill from the right while warming up

            for (offset, level) in visible.enumerated() {
                let i = leftPad + offset
                let x = inset + CGFloat(i) * pitch
                let half = max(1, CGFloat(level) * maxHalf)   // ~1pt nub at silence
                let rect = CGRect(x: x, y: midY - half, width: barWidth, height: half * 2)
                let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                // Bars near the top (hot) flip to orange as a clipping cue.
                context.fill(bar, with: .color(level > 0.9 ? .orange : .green))
            }
        }
        .frame(height: 32)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .onChange(of: recordingManager.inputLevel) { _, level in
            bars.append(level)
            if bars.count > capacity { bars.removeFirst(bars.count - capacity) }
        }
        .onChange(of: recordingManager.isRecording) { _, recording in
            if !recording { bars.removeAll() }
        }
    }
}
