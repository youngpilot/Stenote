import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let isRecording: Bool

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let binCount = max(1, Int(size.width))

            guard !samples.isEmpty, isRecording else {
                var linePath = Path()
                linePath.move(to: CGPoint(x: 0, y: midY))
                linePath.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(linePath, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                return
            }

            let rmsValues = downsample(binCount: binCount)
            let smoothed = smooth(rmsValues, windowSize: 3)

            var topPath = Path()
            var bottomPath = Path()
            topPath.move(to: CGPoint(x: 0, y: midY))
            bottomPath.move(to: CGPoint(x: 0, y: midY))

            for (i, rms) in smoothed.enumerated() {
                let x = CGFloat(i)
                let amplitude = CGFloat(min(rms * 7.0, 1.0)) * midY
                topPath.addLine(to: CGPoint(x: x, y: midY - amplitude))
                bottomPath.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }

            topPath.addLine(to: CGPoint(x: size.width, y: midY))
            bottomPath.addLine(to: CGPoint(x: size.width, y: midY))

            let fillColor = Color.green
            let topGradient = Gradient(stops: [
                .init(color: fillColor.opacity(0.2), location: 0),
                .init(color: fillColor.opacity(0.7), location: 1),
            ])
            let bottomGradient = Gradient(stops: [
                .init(color: fillColor.opacity(0.7), location: 0),
                .init(color: fillColor.opacity(0.2), location: 1),
            ])

            context.fill(topPath, with: .linearGradient(
                topGradient,
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: midY)
            ))
            context.fill(bottomPath, with: .linearGradient(
                bottomGradient,
                startPoint: CGPoint(x: size.width / 2, y: midY),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))
        }
        .frame(height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.3), value: isRecording)
    }

    private func downsample(binCount: Int) -> [Float] {
        let samplesPerBin = max(1, samples.count / binCount)
        var bins: [Float] = []
        bins.reserveCapacity(binCount)

        for i in 0..<binCount {
            let start = i * samples.count / binCount
            let end = min(start + samplesPerBin, samples.count)
            guard start < end else {
                bins.append(0)
                continue
            }
            var sumSquares: Float = 0
            for j in start..<end {
                sumSquares += samples[j] * samples[j]
            }
            bins.append(sqrtf(sumSquares / Float(end - start)))
        }
        return bins
    }

    private func smooth(_ values: [Float], windowSize: Int) -> [Float] {
        guard values.count > windowSize else { return values }
        let half = windowSize / 2
        var result: [Float] = []
        result.reserveCapacity(values.count)

        for i in 0..<values.count {
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            var sum: Float = 0
            for j in lo...hi {
                sum += values[j]
            }
            result.append(sum / Float(hi - lo + 1))
        }
        return result
    }
}
