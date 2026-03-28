import SwiftUI

struct MenuBarView: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var settings = SettingsStore.shared
    @State private var audioService = SystemAudioService.shared
    @State private var copiedFeedback = false
    @State private var showSettings = false
    @State private var copiedHistoryId: UUID?
    @State private var hoveredHistoryId: UUID?
    @State private var showResetConfirm = false
    @State private var historyPage = 0

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
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(",", modifiers: .command)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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

            HStack {
                Text("Recordings")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                Spacer()
                Button("Clear") {
                    recordingManager.historyService.clearHistory()
                    historyPage = 0
                }
                .font(.body)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                let allEntries = recordingManager.historyService.entries
                let pageSize = 5
                let totalPages = max(1, (allEntries.count + pageSize - 1) / pageSize)
                let safePage = min(historyPage, totalPages - 1)
                let pageEntries = Array(allEntries.dropFirst(safePage * pageSize).prefix(pageSize))

                VStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(pageEntries) { entry in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            copiedHistoryId = entry.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedHistoryId == entry.id {
                                    copiedHistoryId = nil
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(copiedHistoryId == entry.id ? "Copied!" : entry.text)
                                    .font(.body)
                                    .foregroundStyle(copiedHistoryId == entry.id ? .green : .primary)
                                    .lineLimit(3)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 4) {
                                    if let duration = entry.duration {
                                        Text(formatDuration(duration))
                                            .fontWeight(.medium)
                                            .foregroundStyle(durationColor(duration))
                                    }
                                    Text(entry.timestamp, format: .relative(presentation: .named))
                                    Text("·")
                                    Text("\(entry.text.count) chars")
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(DesignTokens.Spacing.s)
                        .background(hoveredHistoryId == entry.id ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 8))
                        .onHover { hovering in hoveredHistoryId = hovering ? entry.id : nil }
                    }

                    // Pagination
                    if totalPages > 1 {
                        HStack {
                            Button {
                                historyPage = max(0, historyPage - 1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .disabled(safePage == 0)

                            Spacer()

                            Text("\(safePage + 1) / \(totalPages)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Spacer()

                            Button {
                                historyPage = min(totalPages - 1, historyPage + 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .disabled(safePage >= totalPages - 1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.s)
                    }
                }
            }
            .onChange(of: recordingManager.historyService.entries.count) {
                historyPage = 0
            }
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
            Spacer()
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
                .font(.body)

                Spacer()

                Button {
                    showResetConfirm = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
        if !s.enableITN { items.append("Number formatting: off → on") }
        if s.vadSensitivity != .normal { items.append("Pause sensitivity: \(s.vadSensitivity.label) → Normal") }
        if s.autoStopTimeout != .thirty { items.append("Auto-stop: \(s.autoStopTimeout.label) → 30s") }
        if s.mediaPlaybackOption != .none { items.append("Playback: \(s.mediaPlaybackOption.label) → Don't interrupt") }
        if !s.prefixText.isEmpty { items.append("Prefix: \"\(s.prefixText)\" → empty") }
        if !s.suffixText.isEmpty { items.append("Suffix: \"\(s.suffixText)\" → empty") }

        let wordCount = r.replacements.count + r.boostWords.count
        if wordCount > 0 { items.append("\(wordCount) word correction\(wordCount == 1 ? "" : "s") will be removed") }

        if items.isEmpty { return "All settings are already at defaults." }
        return "This will reset:\n\n" + items.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "0:\(String(format: "%02d", seconds))"
        }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func durationColor(_ duration: TimeInterval) -> Color {
        if duration < 10 { return .blue }
        if duration < 30 { return .green }
        if duration < 60 { return .orange }
        return .purple
    }

    private var statusText: String {
        if recordingManager.isRecording { return "Recording..." }
        if recordingManager.isModelLoading {
            let step = recordingManager.modelLoadingStep
            return step.isEmpty ? "Loading model..." : step
        }
        if recordingManager.modelLoadError != nil { return "Model error" }
        if recordingManager.isModelLoaded {
            if settings.mediaPlaybackOption == .muteOnly {
                if !audioService.supportsVolumeControl {
                    return "Ready — Mute may not work with this audio device"
                }
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
            if settings.mediaPlaybackOption == .muteOnly {
                if !audioService.supportsVolumeControl { return .orange }
            }
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            if let title {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
            }
            content()
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
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var showFnKeyHint = false
    @State private var showShortcutPicker = false

    private let labelFont = Font.body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            // General
            SettingsCard {
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
            }

            // Recording
            SettingsCard(title: "Recording") {
                settingsRow("Mode") {
                    Picker("", selection: Binding(
                        get: { settings.transcriptionMode },
                        set: { settings.transcriptionMode = $0 }
                    )) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.transcriptionMode == .live {
                    Label("Accuracy is reduced.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(labelFont)
                    Text("Text appears as you speak, phrase by phrase.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Text appears as confirmed. Max accuracy.")
                        .font(labelFont)
                        .foregroundStyle(.tertiary)
                }

                settingsRow("Media Playback") {
                    Picker("", selection: Binding(
                        get: { settings.mediaPlaybackOption },
                        set: { settings.mediaPlaybackOption = $0 }
                    )) {
                        ForEach(MediaPlaybackOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.mediaPlaybackOption == .stopMedia {
                    if let app = audioService.detectedMediaApp {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(app) detected — will pause and resume during recording.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    } else {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Works with Spotify and Apple Music. No supported app running.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(labelFont)
                    }
                }

                if settings.mediaPlaybackOption == .muteOnly, !audioService.supportsVolumeControl {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Your audio device doesn't support software volume control. Use \"Pause & Resume\" instead.")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(labelFont)
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
            SettingsCard(title: "Text Output") {
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

                Toggle("Number Formatting (ITN)", isOn: Binding(
                    get: { settings.enableITN },
                    set: { settings.enableITN = $0 }
                ))
                .font(labelFont)

                Text("Converts spoken numbers to digits: \"twenty three\" → \"23\", \"january fifth\" → \"January 5th\"")
                    .font(labelFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
            SettingsCard(title: "Word Corrections") {
                Text("Wrong → Right corrections always work. Boost-only words (no \"Wrong\") need Model Boosting enabled.")
                    .font(labelFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Model Boosting", isOn: Binding(
                    get: { settings.enableVocabBoosting },
                    set: { settings.enableVocabBoosting = $0 }
                ))
                .font(labelFont)

                if settings.enableVocabBoosting {
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
            wordListSection
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
