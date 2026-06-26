import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var settings = SettingsStore.shared
    @State private var audioService = SystemAudioService.shared
    @State private var updater = UpdateService.shared
    @State private var footerHover = false
    @State private var topHover = false
    @State private var copiedFeedback = false
    @State private var copyCardHover = false
    @State private var updateBannerHover = false
    @State private var showSettings = false
    @State private var copiedHistoryId: UUID?
    @State private var savedHistoryId: UUID?
    @State private var hoveredHistoryId: UUID?
    @State private var expandedHistoryId: UUID?
    @State private var showResetConfirm = false
    @State private var historyPage = 0
    @State private var hoveringRecordings = false
    @State private var showClearConfirm = false
    @State private var fileDropTargeted = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            if showSettings {
                settingsSection
            } else {
                mainSection
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 320)
        .contentShape(Rectangle())
        .focusEffectDisabled()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: Self.isAudioFile) else { return false }
            recordingManager.transcribeFile(url)
            return true
        } isTargeted: { fileDropTargeted = $0 }
        .overlay {
            if fileDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        Label("Drop audio to transcribe", systemImage: "waveform")
                            .font(.body).fontWeight(.medium)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: fileDropTargeted)
    }

    /// Whether a dragged/picked URL is an audio file we can transcribe.
    static func isAudioFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .audio) ?? false
    }

    /// Open a file picker for an audio file and transcribe the chosen one.
    private func pickAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Transcribe"
        panel.message = "Choose an audio file to transcribe"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            recordingManager.transcribeFile(url)
        }
    }

    // MARK: - Main View

    @ViewBuilder
    private var mainSection: some View {
        // Update banner (only when a newer release is available)
        if updater.updateAvailable, let url = updater.releaseURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("Update available" + (updater.latestVersion.map { " — v\($0)" } ?? ""))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(updateBannerHover ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { updateBannerHover = $0 }
        }

        // Top bar: Shortcut hint (hover → Start/Stop button) + Settings + Quit
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(HotkeyChoice.allCases.filter { settings.hotkeys.contains($0) }.map { $0.label }.joined(separator: " or "))
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Right-click the menubar icon")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .opacity(topHover ? 0 : 1)

                Button {
                    recordingManager.toggle()
                } label: {
                    HStack(spacing: 6) {
                        if recordingManager.isRecording {
                            Image(systemName: "stop.fill")
                        } else {
                            Image(nsImage: StenoteApp.micIdleIcon)
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 15, height: 15)
                        }
                        Text(recordingManager.isRecording ? "Stop Recording" : "Start Recording")
                    }
                    .fontWeight(.medium)
                }
                .buttonStyle(PopoverButtonStyle(prominent: true))
                .disabled(!recordingManager.isModelLoaded)
                .opacity(topHover ? 1 : 0)
                .allowsHitTesting(topHover)
            }
            .onHover { topHover = $0 }

            Spacer()

            Button {
                pickAudioFile()
            } label: {
                if recordingManager.isTranscribingFile {
                    ProgressView().controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "waveform.badge.plus")
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(PopoverButtonStyle())
            .disabled(!recordingManager.isModelLoaded || recordingManager.isRecording
                      || recordingManager.isStarting || recordingManager.isTranscribingFile)
            .help("Transcribe an audio file (or drop one here)")
            .accessibilityLabel("Transcribe an audio file")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut(",", modifiers: .command)
            .buttonStyle(PopoverButtonStyle())
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.medium)
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(PopoverButtonStyle())
            .accessibilityLabel("Quit Stenote")
        }

        // Model loading progress
        if recordingManager.isModelLoading {
            ProgressView(recordingManager.modelLoadingStep.isEmpty
                ? "Loading model..."
                : recordingManager.modelLoadingStep)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Error with retry
        if let error = recordingManager.modelLoadError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model loading failed")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry") {
                    Task { await recordingManager.setup() }
                }
                .font(.body)
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
        }

        // File transcription progress
        if recordingManager.isTranscribingFile {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing \(recordingManager.fileTranscriptionName ?? "file")…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }

        // File transcription error
        if let fileError = recordingManager.fileTranscriptionError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(fileError)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
        }

        // Microphone permission warning
        if recordingManager.needsMicrophone {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone access needed")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Stenote can't hear you until you allow the microphone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                .font(.body)
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
        }

        // Accessibility permission warning
        if recordingManager.needsAccessibility {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission required")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Stenote needs this to type text into other apps.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .font(.body)
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
        }

        // Audio level + transcription preview while recording
        if recordingManager.isRecording {
            // Input-level meter
            WaveformView()
                .accessibilityHidden(true)

            if !recordingManager.currentText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recordingManager.currentText, forType: .string)
                    copiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedFeedback = false
                    }
                } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Text(copiedFeedback ? "Copied!" : recordingManager.currentText)
                            .font(.body)
                            .foregroundStyle(copiedFeedback ? .green : .secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !copiedFeedback {
                            Image(systemName: "doc.on.doc")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(DesignTokens.Spacing.s)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(copyCardHover ? 0.07 : 0)))
                .onHover { copyCardHover = $0 }
            }
        }

        // History
        if !recordingManager.historyService.entries.isEmpty {
            Divider()
            historySection
        }

        // Status bar. Hovering anywhere below the separator (incl. the existing
        // gap) reveals the version + GitHub link — no extra spacing added.
        VStack(spacing: DesignTokens.Spacing.m) {
            Divider()

            ZStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if recordingManager.isRecording, !recordingManager.detectedLanguage.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(recordingManager.detectedLanguage.uppercased())
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                if recordingManager.isRecording, recordingManager.avgTokenConfidence > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Int(recordingManager.avgTokenConfidence * 100))%")
                        .font(.body)
                        .foregroundStyle(recordingManager.minTokenConfidence < 0.5 ? .orange : .secondary)
                }
                Spacer()
                if !recordingManager.isRecording, !recordingManager.isModelLoading {
                    let h = recordingManager.historyService
                    if h.totalRecordings > 0 {
                        let avgWpm = h.averageWPM
                        Text("\(formatDuration(h.totalDuration)) · \(formatCharCount(h.totalCharacters)) chars"
                             + (avgWpm > 0 ? " · ~\(Int(avgWpm.rounded())) wpm avg" : ""))
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .opacity(footerHover ? 0 : 1)

            // Revealed on hover
            HStack {
                Button {
                    if let url = URL(string: "https://github.com/youngpilot/Stenote") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Info glyph sized + spaced exactly like the status dot above.
                        Image(systemName: "info.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 8, height: 8)
                        Text("Stenote on GitHub →")
                    }
                }
                .buttonStyle(LinkHoverButtonStyle())
                Spacer()
                Text("Stenote v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .foregroundStyle(.quaternary)
            }
            .font(.caption)
            .opacity(footerHover ? 1 : 0)
            .allowsHitTesting(footerHover)
            }
        }
        .contentShape(Rectangle())
        .onHover { footerHover = $0 }
    }

    // MARK: - Settings View

    @ViewBuilder
    private var settingsSection: some View {
        ZStack {
            Text("Settings")
                .font(.body)
                .fontWeight(.medium)

            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSettings = false
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.regular)

                Spacer()

                Button {
                    showResetConfirm = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.regular)
                .help("Reset to Defaults")
                .accessibilityLabel("Reset to defaults")
            }
        }

        if showResetConfirm {
            VStack(spacing: DesignTokens.Spacing.s) {
                Text("Reset to Defaults?")
                    .font(.body)
                    .fontWeight(.medium)
                Text(resetSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showResetConfirm = false
                        }
                    }
                    .buttonStyle(BorderedHoverButtonStyle())
                    Spacer()
                    Button("Reset") {
                        SettingsStore.shared.resetToDefaults()
                        TextReplacementService.shared.removeAll()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showResetConfirm = false
                        }
                    }
                    .buttonStyle(BorderedHoverButtonStyle(tint: .red))
                }
                .font(.body)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
        }

        Divider()

        InlineSettingsView()
    }

    private var resetSummary: String {
        var items: [String] = []
        let s = SettingsStore.shared
        let r = TextReplacementService.shared

        if s.hotkeys != [.doubleRightOption] { items.append("Shortcuts → Double-press Right ⌥ only") }
        if s.autoStopTimeout != .thirty { items.append("Stop after silence: \(s.autoStopTimeout.label) → 30s") }
        if !s.silenceMediaWhileRecording { items.append("Silence media while recording: off → on") }
        if !s.pauseMediaApps { items.append("Pause Spotify/Apple Music: off → on") }
        if !s.prefixText.isEmpty { items.append("Prefix: \"\(s.prefixText)\" → empty") }
        if !s.suffixText.isEmpty { items.append("Suffix: \"\(s.suffixText)\" → empty") }

        let wordCount = r.replacements.count + r.boostWords.count
        if wordCount > 0 { items.append("\(wordCount) word correction\(wordCount == 1 ? "" : "s") will be removed") }

        if items.isEmpty { return "All settings are already at defaults." }
        return "This will reset:\n\n" + items.joined(separator: "\n")
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let allEntries = recordingManager.historyService.entries
            let pageSize = settings.historyPageSize
            let totalPages = max(1, (allEntries.count + pageSize - 1) / pageSize)
            let safePage = min(historyPage, totalPages - 1)
            let pageEntries = Array(allEntries.dropFirst(safePage * pageSize).prefix(pageSize))

            VStack(spacing: DesignTokens.Spacing.xs) {
                historyHeader(totalPages: totalPages, safePage: safePage)

                ForEach(pageEntries) { entry in
                    historyRow(entry)
                }
            }
        }
        .onChange(of: recordingManager.historyService.entries.count) {
            historyPage = 0
        }
    }

    @ViewBuilder
    private func historyHeader(totalPages: Int, safePage: Int) -> some View {
        HStack {
            Text("Recordings")
                .font(.body)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            Spacer()

            if totalPages > 1 {
                Button {
                    historyPage = max(0, historyPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.regular)
                .disabled(safePage == 0)
                .accessibilityLabel("Previous recordings")

                Text("\(safePage + 1)/\(totalPages)")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Button {
                    historyPage = min(totalPages - 1, historyPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.regular)
                .disabled(safePage >= totalPages - 1)
                .accessibilityLabel("Next recordings")
            }

            Spacer()

            if showClearConfirm {
                Button("Confirm") {
                    recordingManager.historyService.clearHistory()
                    historyPage = 0
                    showClearConfirm = false
                }
                .buttonStyle(BorderedHoverButtonStyle(tint: .red))
                .controlSize(.regular)
            } else {
                Button("Clear") {
                    showClearConfirm = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showClearConfirm = false
                    }
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let rid = entry.recordingId {
                    Text("#\(rid)")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                if entry.recordingId != nil, entry.duration != nil {
                    Text("·").foregroundStyle(.quaternary)
                }
                if let duration = entry.duration {
                    Text(formatDuration(duration))
                        .fontWeight(.medium)
                }
                Text("·").foregroundStyle(.quaternary)
                Text(roughTimestamp(entry.timestamp))
                Text("·").foregroundStyle(.quaternary)
                Text("\(entry.text.count) chars")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Text(entry.text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(SettingsStore.shared.historyPreviewLines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.Spacing.s)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hoveredHistoryId == entry.id ? 0.12 : 0))
            }
        )
        .overlay {
            let isActive = copiedHistoryId == entry.id || savedHistoryId == entry.id
            RoundedRectangle(cornerRadius: 8)
                .fill(.green.opacity(isActive ? 0.15 : 0))
                .overlay {
                    Text(savedHistoryId == entry.id ? "Saved" : "Copied")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                        .opacity(isActive ? 1 : 0)
                }
                .animation(.easeIn(duration: 0.1), value: isActive)
                .animation(.easeOut(duration: 0.6).delay(0.8), value: !isActive)
                .allowsHitTesting(false)
        }
        .onHover { hovering in hoveredHistoryId = hovering ? entry.id : nil }
        .contentShape(Rectangle())
        .onTapGesture { copyEntry(entry) }
        .help("Click to copy")
        .contextMenu {
            Button {
                copyEntry(entry)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                saveEntryAsTxt(entry)
            } label: {
                Label("Save as .txt", systemImage: "square.and.arrow.down")
            }
            Divider()
            Button(role: .destructive) {
                recordingManager.historyService.deleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func saveEntryAsTxt(_ entry: HistoryEntry) {
        let dir = SettingsStore.shared.exportDirectory
        let filename = "Stenote_\(entry.formattedId)_\(formatDurationFilename(entry.duration)).txt"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var content = "Stenote Recording #\(entry.formattedId)\n"
        content += "Date: \(dateFormatter.string(from: entry.timestamp))\n"
        if let duration = entry.duration {
            content += "Duration: \(formatDuration(duration))\n"
        }
        content += "Characters: \(entry.text.count)\n"
        content += "\n---\n\n"
        content += entry.text

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            savedHistoryId = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if savedHistoryId == entry.id {
                    savedHistoryId = nil
                }
            }
        } catch {
            // Silently fail
        }
    }

    private func formatDurationFilename(_ duration: TimeInterval?) -> String {
        guard let duration else { return "0s" }
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m\(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h\(String(format: "%02d", (seconds % 3600) / 60))m"
    }

    private func copyEntry(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedHistoryId = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedHistoryId == entry.id {
                copiedHistoryId = nil
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))m"
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", seconds % 60))h"
    }

    private func formatCharCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        return String(format: "%.1fk", Double(count) / 1000)
    }

    private func durationColor(_ duration: TimeInterval) -> Color {
        if duration < 10 { return .blue }
        if duration < 30 { return .green }
        if duration < 60 { return .orange }
        return .purple
    }

    private func roughTimestamp(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 5 { return "\(minutes)m ago" }
        if minutes < 10 { return "5m ago" }
        if minutes < 20 { return "15m ago" }
        if minutes < 40 { return "30m ago" }
        if minutes < 60 { return "45m ago" }
        let hours = minutes / 60
        if hours == 1 { return "1 hour ago" }
        if hours < 5 {
            let halfHours = (minutes + 15) / 30
            let h = halfHours / 2
            if halfHours % 2 == 1 { return "\(h).5 hours ago" }
            return "\(h) hours ago"
        }
        if hours < 24 { return "\(hours) hours ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    private var statusText: String {
        if recordingManager.isRecording { return "Recording..." }
        if recordingManager.isModelLoading {
            let step = recordingManager.modelLoadingStep
            return step.isEmpty ? "Loading model..." : step
        }
        if recordingManager.modelLoadError != nil { return "Model error" }
        if recordingManager.isModelLoaded {
            if settings.silenceMediaWhileRecording, !audioService.supportsVolumeControl {
                return "Stenote is Ready — can't mute this audio device"
            }
            return "Stenote is Ready"
        }
        return "Initializing..."
    }

    private var statusColor: Color {
        if recordingManager.isRecording { return .red }
        if recordingManager.isModelLoading { return .orange }
        if recordingManager.modelLoadError != nil { return .red }
        if recordingManager.isModelLoaded {
            if settings.silenceMediaWhileRecording, !audioService.supportsVolumeControl { return .orange }
            return .green
        }
        return .secondary
    }
}

// MARK: - Button style

/// Borderless button with a clearly visible hover and press highlight.
private struct PopoverButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 14 : 9)
            .padding(.vertical, prominent ? 8 : 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.13 : 0.06)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Bordered button with a clearly visible hover/press highlight. Looks like the
/// native `.bordered` at rest but reacts on hover. Tint-, controlSize- and
/// enabled-aware, so it drops in wherever `.buttonStyle(.bordered)` was used.
private struct BorderedHoverButtonStyle: ButtonStyle {
    var tint: Color? = nil
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let base = tint ?? .primary
        let compact = controlSize == .small || controlSize == .mini
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(base.opacity(pressed ? 0.28 : (hovering ? 0.18 : 0.10)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(base.opacity(hovering ? 0.32 : 0.16), lineWidth: 0.75)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Link-style button (accent text) that underlines on hover.
private struct LinkHoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .underline(hovering)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Borderless icon button (e.g. +) with a soft rounded hover fill.
private struct IconHoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.13 : 0)))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var isExpanded: Bool = true
    var onToggle: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @State private var blockHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                // The header is the toggle target. Its own padding makes the hit
                // area fill the whole container when collapsed, and keeps that exact
                // header-band size when expanded — a consistent, easy-to-hit target.
                HStack {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    Spacer()
                    if onToggle != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(DesignTokens.Spacing.s)
                .contentShape(Rectangle())
                .onTapGesture { onToggle?() }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.bottom, DesignTokens.Spacing.s)
                .padding(.top, title == nil ? DesignTokens.Spacing.s : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Hovering anywhere over a collapsible category lifts the whole block.
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(blockHover && onToggle != nil ? 0.06 : 0))
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { blockHover = $0 }
        .animation(.easeOut(duration: 0.12), value: blockHover)
    }
}

// MARK: - Inline Settings

private struct InlineSettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var replacementService = TextReplacementService.shared
    @State private var audioService = SystemAudioService.shared
    @State private var recordingManager = RecordingManager.shared
    @State private var updater = UpdateService.shared
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var showFnKeyHint = false
    @State private var showShortcutPicker = false
    @State private var expandedSection: String? = "General"

    private let labelFont = Font.body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            // General
            SettingsCard(title: "General", isExpanded: expandedSection == "General", onToggle: { toggleSection("General") }) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                .font(labelFont)
                .onAppear { settings.refreshLaunchAtLoginStatus() }

                Button {
                    showShortcutPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("Shortcut: " + HotkeyChoice.allCases
                            .filter { settings.hotkeys.contains($0) }
                            .map { $0.label }
                            .joined(separator: " or "))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(labelFont)
                }
                .buttonStyle(BorderedHoverButtonStyle())
                .popover(isPresented: $showShortcutPicker, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(HotkeyChoice.allCases) { choice in
                            Toggle(choice.label, isOn: Binding(
                                get: { settings.hotkeys.contains(choice) },
                                set: { enabled in
                                    var updated = settings.hotkeys
                                    if enabled {
                                        updated.insert(choice)
                                    } else if updated.count > 1 {
                                        updated.remove(choice)
                                    }
                                    settings.hotkeys = updated
                                    showFnKeyHint = updated.contains(.f5)
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                        if showFnKeyHint || settings.hotkeys.contains(.f5) {
                            Divider()
                            Label("Enable standard function keys", systemImage: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("System Settings → Keyboard →\n\"Use F1, F2, etc. as standard function keys\"")
                                .foregroundStyle(.secondary)
                            Button("Open Keyboard Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                            }
                            .buttonStyle(LinkHoverButtonStyle())
                        }
                    }
                    .font(labelFont)
                    .padding(12)
                    .frame(minWidth: 220)
                }

                settingsRow("History preview") {
                    Picker("", selection: Binding(
                        get: { settings.historyPreviewLines },
                        set: { settings.historyPreviewLines = $0 }
                    )) {
                        ForEach(1...9, id: \.self) { n in
                            Text("\(n) lines").tag(n)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                settingsRow("Recordings per page") {
                    Picker("", selection: Binding(
                        get: { settings.historyPageSize },
                        set: { settings.historyPageSize = $0 }
                    )) {
                        ForEach([1, 3, 5, 7, 10], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                settingsRow("History length") {
                    Picker("", selection: Binding(
                        get: { settings.historyLength },
                        set: { newValue in
                            settings.historyLength = newValue
                            HistoryService.shared.enforceLimit()
                        }
                    )) {
                        ForEach(HistoryLength.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                HStack {
                    Text("Export folder")
                        .font(labelFont)
                    Spacer()
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: settings.exportDirectory)
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.exportDirectory = url.path
                        }
                    } label: {
                        Text(URL(fileURLWithPath: settings.exportDirectory).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Divider().opacity(0.5)

                settingsRow("Check for updates") {
                    Picker("", selection: Binding(
                        get: { settings.updateCheckMode },
                        set: { newMode in
                            settings.updateCheckMode = newMode
                            if newMode == .daily { updater.maybeAutoCheck() }
                        }
                    )) {
                        ForEach(UpdateCheckMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Text(settings.updateCheckMode == .daily
                     ? "Stenote checks GitHub once a day. One request, no account, nothing sent."
                     : "No automatic checks. Stenote makes no network calls unless you press Check Now.")
                    .font(labelFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        Task { await updater.checkNow() }
                    } label: {
                        Text(updater.isChecking ? "Checking…" : "Check Now")
                    }
                    .buttonStyle(BorderedHoverButtonStyle())
                    .controlSize(.small)
                    .disabled(updater.isChecking)
                    Spacer()
                }

                if updater.updateAvailable, let v = updater.latestVersion, let url = updater.releaseURL {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update available: v\(v)")
                            Link("Download from GitHub", destination: url)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(labelFont)
                } else if updater.lastCheckFailed {
                    Text("Couldn't reach GitHub. Check your connection and try Check Now again.")
                        .font(labelFont)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if updater.lastSuccess != nil {
                    Text("You're on the latest version (v\(updater.currentVersion)).")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.5)

                Button("Show welcome screen again") {
                    OnboardingPresenter.shared.show()
                }
                .buttonStyle(LinkHoverButtonStyle())
                .font(labelFont)
            }

            // Recording
            SettingsCard(title: "Recording", isExpanded: expandedSection == "Recording", onToggle: { toggleSection("Recording") }) {
                Toggle("Mute Media Playback while recording", isOn: Binding(
                    get: { settings.silenceMediaWhileRecording },
                    set: { settings.silenceMediaWhileRecording = $0 }
                ))
                .font(labelFont)

                if settings.silenceMediaWhileRecording, !audioService.supportsVolumeControl {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This audio device can't be muted by software.")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(labelFont)
                }

                Toggle("Pause Spotify & Apple Music", isOn: Binding(
                    get: { settings.pauseMediaApps },
                    set: { settings.pauseMediaApps = $0 }
                ))
                .font(labelFont)

                if settings.pauseMediaApps {
                    if let app = audioService.detectedMediaApp {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(app) detected — it pauses while you record and resumes after.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    } else {
                        Text("Pauses Spotify or Apple Music if either is playing. macOS asks for Automation permission the first time.")
                            .font(labelFont)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsRow("Stop after silence") {
                    Picker("", selection: Binding(
                        get: { settings.autoStopTimeout },
                        set: { settings.autoStopTimeout = $0 }
                    )) {
                        ForEach(AutoStopOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // Text Output
            SettingsCard(title: "Text Output", isExpanded: expandedSection == "Text Output", onToggle: { toggleSection("Text Output") }) {
                settingsRow("Insertion") {
                    Picker("", selection: Binding(
                        get: { settings.insertionMode },
                        set: { settings.insertionMode = $0 }
                    )) {
                        ForEach(InsertionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.insertionMode == .direct {
                    Text("Types characters directly. Works everywhere but slower for long texts.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if settings.insertionMode == .clipboard {
                    Text("Uses clipboard paste. Fastest, but briefly replaces clipboard.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Direct typing for short text, clipboard for longer text.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Voice Commands", isOn: Binding(
                    get: { settings.enableVoiceCommands },
                    set: { settings.enableVoiceCommands = $0 }
                ))
                .font(labelFont)

                if settings.enableVoiceCommands {
                    Text("Say the phrase to insert it (e.g. \"new paragraph\", \"period\"). Toggle the ones you want:")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(VoiceCommandID.allCases) { cmd in
                            Toggle(cmd.label, isOn: Binding(
                                get: { settings.enabledVoiceCommandIDs.contains(cmd.id) },
                                set: { on in
                                    var ids = settings.enabledVoiceCommandIDs
                                    if on { ids.insert(cmd.id) } else { ids.remove(cmd.id) }
                                    settings.enabledVoiceCommandIDs = ids
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(labelFont)
                        }
                    }
                    .padding(.leading, 8)
                }

                Toggle("Emoji by Voice", isOn: Binding(
                    get: { settings.enableEmojiCommands },
                    set: { settings.enableEmojiCommands = $0 }
                ))
                .font(labelFont)

                if settings.enableEmojiCommands {
                    Text("Say a word next to \"emoji\" — e.g. \"smile emoji\" → 😊, \"emoji fire\" → 🔥. Curated, on-device.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsRow("Prefix") {
                    TextField("", text: Binding(
                        get: { settings.prefixText },
                        set: { settings.prefixText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                settingsRow("Suffix") {
                    TextField("", text: Binding(
                        get: { settings.suffixText },
                        set: { settings.suffixText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Word Corrections
            SettingsCard(title: "Word Corrections", isExpanded: expandedSection == "Word Corrections", onToggle: { toggleSection("Word Corrections") }) {
                Text("Wrong → Right corrections always work. Boost-only words (no \"Wrong\") need Model Boosting enabled.")
                    .font(labelFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Model Boosting", isOn: Binding(
                    get: { settings.enableVocabBoosting },
                    set: { newValue in
                        settings.enableVocabBoosting = newValue
                        if newValue { recordingManager.prepareVocabularyBoosting() }
                    }
                ))
                .font(labelFont)

                if settings.enableVocabBoosting {
                    if recordingManager.isVocabModelLoading {
                        HStack(alignment: .top, spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Downloading boosting model (~98 MB, one-time)…")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    } else if recordingManager.vocabModelLoadFailed {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("Couldn't download the boosting model. It needs internet once — it will retry on your next recording.")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Works best for single, distinctive words (4+ letters). It only swaps a word when it's acoustically confident, so it rarely affects other text.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(labelFont)
                }

                HStack(spacing: 4) {
                    TextField("Wrong (optional)", text: $newFrom)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    TextField("Correct", text: $newTo)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button { addWord() } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTo.isEmpty || tooShortBoostWord)
                    .buttonStyle(IconHoverButtonStyle())
                }
                .font(labelFont)

                if tooShortBoostWord {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Boost-only words need 4+ letters — shorter ones are ignored by the model. Add a “Wrong” word to make it an exact replacement instead.")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(labelFont)
                }
            }

            // Word list — outside SettingsCard so @Observable triggers correctly
            if expandedSection == "Word Corrections" {
                wordListSection
            }

            HStack {
                Button {
                    if let url = URL(string: "https://github.com/youngpilot/Stenote") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Stenote on GitHub →")
                }
                .buttonStyle(LinkHoverButtonStyle())
                Spacer()
                Text("Stenote v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .foregroundStyle(.quaternary)
            }
            .font(.caption)
        }
    }

    private func toggleSection(_ section: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            expandedSection = expandedSection == section ? nil : section
        }
    }

    // MARK: - Reusable row

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(labelFont)
            Spacer()
            content()
                .font(labelFont)
        }
    }

    // MARK: - Word list

    @ViewBuilder
    private var wordListSection: some View {
        if !replacementService.boostWords.isEmpty || !replacementService.replacements.isEmpty {
            WordPillsView(
                boostWords: replacementService.boostWords.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                replacements: replacementService.replacements.sorted(by: { $0.key < $1.key }),
                onRemoveBoost: { replacementService.removeBoostWord($0) },
                onRemoveReplacement: { replacementService.removeReplacement(from: $0) }
            )
        }
    }

    /// A boost-only entry (no "Wrong") under 4 letters: FluidAudio's rescorer
    /// skips terms this short, so adding it would do nothing.
    private var tooShortBoostWord: Bool {
        newFrom.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...3).contains(newTo.trimmingCharacters(in: .whitespaces).count)
    }

    private func addWord() {
        guard !newTo.isEmpty, !tooShortBoostWord else { return }
        if newFrom.isEmpty {
            replacementService.addBoostWord(newTo)
        } else {
            replacementService.addReplacement(from: newFrom, to: newTo)
        }
        newFrom = ""
        newTo = ""
    }
}

// MARK: - Word Pills

private struct WordPillsView: View {
    let boostWords: [String]
    let replacements: [(key: String, value: String)]
    let onRemoveBoost: (String) -> Void
    let onRemoveReplacement: (String) -> Void

    var body: some View {
        let allPills: [(id: String, label: String)] = {
            let b = boostWords.map { (id: "b:\($0)", label: $0) }
            let r = replacements.map { (id: "r:\($0.key)", label: "\($0.key) → \($0.value)") }
            return (b + r).sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        }()

        WrappingHStack(spacing: 5) {
            ForEach(allPills, id: \.id) { pill in
                WordPill(label: pill.label) {
                    if pill.id.hasPrefix("b:") {
                        onRemoveBoost(String(pill.id.dropFirst(2)))
                    } else {
                        onRemoveReplacement(String(pill.id.dropFirst(2)))
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
    }
}

private struct WordPill: View {
    let label: String
    let onRemove: () -> Void
    @State private var xHover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(xHover ? .primary : .secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(xHover ? 0.28 : 0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle().inset(by: -4))
            .onHover { xHover = $0 }
            .accessibilityLabel("Remove word")
        }
        .font(.body)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

// MARK: - Wrapping HStack Layout

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CGFloat) -> CGSize {
        cache = proposal.width ?? 300
        let rows = computeRows(maxWidth: cache, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            height += row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            if i > 0 { height += spacing }
        }
        return CGSize(width: cache, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CGFloat) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    func makeCache(subviews: Subviews) -> CGFloat { 300 }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
