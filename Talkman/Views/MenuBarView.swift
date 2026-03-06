import SwiftUI

struct MenuBarView: View {
    @State private var recordingManager = RecordingManager.shared

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            // Status
            HStack {
                Circle()
                    .fill(recordingManager.isRecording ? Color.red : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(recordingManager.isRecording ? "Recording..." : "Ready")
                    .font(DesignTokens.Font.body)
                Spacer()
            }

            // Current transcription preview
            if !recordingManager.currentText.isEmpty {
                Text(recordingManager.currentText)
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Toggle button
            Button {
                recordingManager.toggle()
            } label: {
                Label(
                    recordingManager.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: recordingManager.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("r", modifiers: .command)
            .controlSize(.large)

            Divider()

            HStack {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .font(DesignTokens.Font.caption)
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 280)
    }
}
