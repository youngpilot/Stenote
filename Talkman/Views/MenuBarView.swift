import SwiftUI

struct MenuBarView: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var settings = SettingsStore.shared
    @State private var audioService = SystemAudioService.shared
    @State private var updater = UpdateService.shared
    @State private var copiedFeedback = false
    @State private var showSettings = false
    @State private var copiedHistoryId: UUID?
    @State private var savedHistoryId: UUID?
    @State private var hoveredHistoryId: UUID?
    @State private var expandedHistoryId: UUID?
    @State private var showResetConfirm = false
    @State private var historyPage = 0
    @State private var hoveringRecordings = false
    @State private var showClearConfirm = false

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
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        // Top bar: Shortcut hint + Settings + Quit
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HotkeyChoice.allCases.filter { settings.hotkeys.contains($0) }.map { $0.label }.joined(separator: " or "))
                    .font(.body)
                    .fontWeight(.medium)
                Text("Right-click the menubar icon")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut(",", modifiers: .command)
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.medium)
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(.bordered)
            .controlSize(.regular)
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
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
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
                    Text("Talkman needs this to type text into other apps.")
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
            // Waveform visualization
            WaveformView(samples: recordingManager.waveformSamples, isRecording: recordingManager.isRecording)

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
            }
        }

        // History
        if !recordingManager.historyService.entries.isEmpty {
            Divider()
            historySection
        }

        // Status bar at the bottom
        Divider()

        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.body)
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
                    Text("\(formatDuration(h.totalDuration)) · \(formatCharCount(h.totalCharacters)) chars")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
        }
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
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button {
                    showResetConfirm = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Reset to Defaults")
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
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Reset") {
                        SettingsStore.shared.resetToDefaults()
                        TextReplacementService.shared.removeAll()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showResetConfirm = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
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
        if s.vadSensitivity != .normal { items.append("Pause sensitivity: \(s.vadSensitivity.label) → Normal") }
        if s.autoStopTimeout != .thirty { items.append("Auto-stop: \(s.autoStopTimeout.label) → 30s") }
        if !s.silenceMediaWhileRecording { items.append("Silence media while recording: off → on") }
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
            let pageSize = 5
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
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(safePage == 0)

                Text("\(safePage + 1)/\(totalPages)")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Button {
                    historyPage = min(totalPages - 1, historyPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(safePage >= totalPages - 1)
            }

            Spacer()

            if showClearConfirm {
                Button("Confirm") {
                    recordingManager.historyService.clearHistory()
                    historyPage = 0
                    showClearConfirm = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)
            } else {
                Button("Clear") {
                    showClearConfirm = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showClearConfirm = false
                    }
                }
                .buttonStyle(.bordered)
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
        .background(hoveredHistoryId == entry.id ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 8))
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
        let filename = "Talkman_\(entry.formattedId)_\(formatDurationFilename(entry.duration)).txt"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var content = "Talkman Recording #\(entry.formattedId)\n"
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
            if settings.silenceMediaWhileRecording, !audioService.supportsVolumeControl, audioService.detectedMediaApp == nil {
                return "Ready — can't silence this audio device"
            }
            return "Ready"
        }
        return "Initializing..."
    }

    private var statusColor: Color {
        if recordingManager.isRecording { return .red }
        if recordingManager.isModelLoading { return .orange }
        if recordingManager.modelLoadError != nil { return .red }
        if recordingManager.isModelLoaded {
            if settings.silenceMediaWhileRecording, !audioService.supportsVolumeControl, audioService.detectedMediaApp == nil { return .orange }
            return .green
        }
        return .secondary
    }
}

// MARK: - Audio Level Indicator

private struct AudioLevelView: View {
    let level: Float
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(height: 6)
                    .opacity(level > threshold ? 1.0 : 0.15)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barColor(for index: Int) -> Color {
        let ratio = Float(index) / Float(barCount)
        if ratio > 0.8 { return .red }
        if ratio > 0.6 { return .orange }
        return .green
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var isExpanded: Bool = true
    var onToggle: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? DesignTokens.Spacing.s : 0) {
            if let title {
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
                .contentShape(Rectangle())
                .onTapGesture { onToggle?() }
            }
            if isExpanded {
                content()
            }
        }
        .padding(DesignTokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
                .buttonStyle(.bordered)
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
                            .buttonStyle(.link)
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
            }

            // Recording
            SettingsCard(title: "Recording", isExpanded: expandedSection == "Recording", onToggle: { toggleSection("Recording") }) {
                Toggle("Silence media while recording", isOn: Binding(
                    get: { settings.silenceMediaWhileRecording },
                    set: { settings.silenceMediaWhileRecording = $0 }
                ))
                .font(labelFont)

                if settings.silenceMediaWhileRecording {
                    Text("Mutes all audio to silence while you dictate, and pauses Spotify or Apple Music if they're playing. Everything resumes when you stop.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let app = audioService.detectedMediaApp {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(app) detected — it will pause and resume too.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    }

                    if !audioService.supportsVolumeControl {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(audioService.detectedMediaApp == nil
                                 ? "This audio device can't be muted by software, and no Spotify or Apple Music is running to pause."
                                 : "This audio device can't be muted by software, but the detected player will still be paused.")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    }
                }

                settingsRow("Pause sensitivity") {
                    Picker("", selection: Binding(
                        get: { settings.vadSensitivity },
                        set: { settings.vadSensitivity = $0 }
                    )) {
                        ForEach(VadSensitivity.allCases) { sensitivity in
                            Text(sensitivity.label).tag(sensitivity)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                settingsRow("Auto-stop silence") {
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
                    Text("Say \"period\", \"comma\", \"new line\" etc. to insert punctuation.")
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
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("May reduce accuracy. If transcription quality drops, turn this off.")
                            .foregroundStyle(.orange)
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
                    .disabled(newTo.isEmpty)
                    .buttonStyle(.plain)
                }
                .font(labelFont)
            }

            // Word list — outside SettingsCard so @Observable triggers correctly
            if expandedSection == "Word Corrections" {
                wordListSection
            }

            // Updates
            SettingsCard(title: "Updates", isExpanded: expandedSection == "Updates", onToggle: { toggleSection("Updates") }) {
                settingsRow("Check for updates") {
                    Picker("", selection: Binding(
                        get: { settings.updateCheckMode },
                        set: { newMode in
                            settings.updateCheckMode = newMode
                            if newMode == .daily { Task { await updater.autoCheckIfDue() } }
                        }
                    )) {
                        ForEach(UpdateCheckMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Text(settings.updateCheckMode == .daily
                     ? "Talkman checks GitHub once a day. One request, no account, nothing sent."
                     : "No automatic checks. Talkman makes no network calls unless you press Check Now.")
                    .font(labelFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        Task { await updater.checkNow() }
                    } label: {
                        Text(updater.isChecking ? "Checking…" : "Check Now")
                    }
                    .buttonStyle(.bordered)
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
                } else if updater.lastChecked != nil {
                    Text("You're on the latest version (v\(updater.currentVersion)).")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
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

    private func addWord() {
        guard !newTo.isEmpty else { return }
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

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle().inset(by: -4))
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
