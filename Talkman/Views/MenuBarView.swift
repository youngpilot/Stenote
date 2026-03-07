import SwiftUI

struct MenuBarView: View {
    @State private var recordingManager = RecordingManager.shared
    @State private var settings = SettingsStore.shared
    @State private var copiedFeedback = false
    @State private var showSettings = false
    @State private var copiedHistoryId: UUID?
    @State private var hoveredHistoryId: UUID?
    @State private var showResetConfirm = false

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
        .focusEffectDisabled()
    }

    // MARK: - Main View

    @ViewBuilder
    private var mainSection: some View {
        // Top bar: Record + Settings + Quit
        HStack(spacing: 8) {
            Button {
                recordingManager.toggle()
            } label: {
                HStack(spacing: 5) {
                    let icon = recordingManager.isRecording
                        ? TalkmanApp.micRecordingIcon
                        : TalkmanApp.micIdleIcon
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                    Text(recordingManager.isRecording ? "Stop" : "Record")
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .controlSize(.large)
            .disabled(!recordingManager.isModelLoaded)

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
                        .font(DesignTokens.Font.caption)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry") {
                    Task { await recordingManager.setup() }
                }
                .font(.caption2)
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }

        // Accessibility permission warning
        if recordingManager.needsAccessibility {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission required")
                        .font(DesignTokens.Font.caption)
                        .fontWeight(.medium)
                    Text("Talkman needs this to type text into other apps.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .font(.caption2)
                .controlSize(.small)
            }
            .padding(DesignTokens.Spacing.s)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }

        // Current transcription preview — only while recording
        if recordingManager.isRecording, !recordingManager.currentText.isEmpty {
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
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(copiedFeedback ? .green : .secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !copiedFeedback {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(DesignTokens.Spacing.s)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }

        // History
        if !recordingManager.historyService.entries.isEmpty {
            Divider()

            HStack {
                Text("Last 10 recordings")
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                Spacer()
                Button("Clear") {
                    recordingManager.historyService.clearHistory()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            let entries = recordingManager.historyService.entries.prefix(10)

            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(entries)) { entry in
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
                                .font(DesignTokens.Font.caption)
                                .foregroundStyle(copiedHistoryId == entry.id ? .green : .primary)
                                .lineLimit(3)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 4) {
                                Text(entry.timestamp, format: .relative(presentation: .named))
                                Text("·")
                                Text("\(entry.text.count) chars")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(DesignTokens.Spacing.s)
                    .background(Color.primary.opacity(hoveredHistoryId == entry.id ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 6))
                    .onHover { hovering in hoveredHistoryId = hovering ? entry.id : nil }
                }
            }
        }

        // Status bar at the bottom
        Divider()

        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(DesignTokens.Font.caption)
                .foregroundStyle(.secondary)
            if recordingManager.isRecording, !recordingManager.detectedLanguage.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(recordingManager.detectedLanguage.uppercased())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Settings View

    @ViewBuilder
    private var settingsSection: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings = false
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .font(DesignTokens.Font.caption)
            .controlSize(.small)

            Spacer()

            Text("Settings")
                .font(DesignTokens.Font.body)
                .fontWeight(.medium)

            Spacer()

            Button {
                showResetConfirm = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .font(DesignTokens.Font.caption)
            .controlSize(.small)
            .help("Restore Defaults")
        }
        .alert("Restore Defaults?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                SettingsStore.shared.resetToDefaults()
                TextReplacementService.shared.removeAll()
            }
        } message: {
            Text(resetSummary)
        }

        Divider()

        InlineSettingsView()
    }

    private var resetSummary: String {
        var items: [String] = []
        let s = SettingsStore.shared
        let r = TextReplacementService.shared

        if s.hotkey != .doubleRightCmd { items.append("Shortcut: \(s.hotkey.label) → Double-press Right ⌘") }
        if !s.enableITN { items.append("Inverse Text Normalization: off → on") }
        if s.vadSensitivity != .normal { items.append("Pause sensitivity: \(s.vadSensitivity.label) → Normal") }
        if s.autoStopTimeout != .thirty { items.append("Auto-stop: \(s.autoStopTimeout.label) → 30s") }
        if s.muteAudioDuringRecording { items.append("Mute audio: on → off") }
        if s.politenessMode { items.append("Politeness mode: on → off") }
        if !s.prefixText.isEmpty { items.append("Prefix: \"\(s.prefixText)\" → empty") }
        if !s.suffixText.isEmpty { items.append("Suffix: \"\(s.suffixText)\" → empty") }

        let wordCount = r.replacements.count + r.boostWords.count
        if wordCount > 0 { items.append("\(wordCount) brand name\(wordCount == 1 ? "" : "s") will be removed") }

        if items.isEmpty { return "All settings are already at defaults." }
        return "This will reset:\n\n" + items.joined(separator: "\n")
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if recordingManager.isRecording { return .red }
        if recordingManager.isModelLoading { return .orange }
        if recordingManager.modelLoadError != nil { return .red }
        if recordingManager.isModelLoaded { return .green }
        return .secondary
    }

    private var statusText: String {
        if recordingManager.isRecording { return "Recording..." }
        if recordingManager.isModelLoading {
            let step = recordingManager.modelLoadingStep
            return step.isEmpty ? "Loading model..." : step
        }
        if recordingManager.modelLoadError != nil { return "Model error" }
        if recordingManager.isModelLoaded { return "Ready" }
        return "Initializing..."
    }
}

// MARK: - Inline Settings

private struct InlineSettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var replacementService = TextReplacementService.shared
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var showFnKeyHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            // General
            Text("General")
                .font(DesignTokens.Font.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            Toggle("Inverse Text Normalization", isOn: Binding(
                get: { settings.enableITN },
                set: { settings.enableITN = $0 }
            ))
            .font(DesignTokens.Font.caption)

            Toggle("Launch at Login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }
            ))
            .font(DesignTokens.Font.caption)

            Toggle("Mute Audio While Recording", isOn: Binding(
                get: { settings.muteAudioDuringRecording },
                set: { settings.muteAudioDuringRecording = $0 }
            ))
            .font(DesignTokens.Font.caption)
            .help("Mute system audio output during recording to prevent interference, restores when done")

            Divider()

            // Text Options
            Text("Text Options")
                .font(DesignTokens.Font.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            Toggle("Politeness Mode", isOn: Binding(
                get: { settings.politenessMode },
                set: { settings.politenessMode = $0 }
            ))
            .font(DesignTokens.Font.caption)
            .help("Append \"Thank you!\" at the end of each transcription")

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("Prefix:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                TextField("", text: Binding(
                    get: { settings.prefixText },
                    set: { settings.prefixText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("Suffix:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                TextField("", text: Binding(
                    get: { settings.suffixText },
                    set: { settings.suffixText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
            }

            Divider()

            // Pause Sensitivity
            HStack {
                Text("Pause sensitivity:")
                    .font(DesignTokens.Font.caption)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.vadSensitivity },
                    set: { settings.vadSensitivity = $0 }
                )) {
                    ForEach(VadSensitivity.allCases) { sensitivity in
                        Text(sensitivity.label).tag(sensitivity)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .font(DesignTokens.Font.caption)
            }

            // Auto-Stop Timeout
            HStack {
                Text("Auto-stop after silence:")
                    .font(DesignTokens.Font.caption)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.autoStopTimeout },
                    set: { settings.autoStopTimeout = $0 }
                )) {
                    ForEach(AutoStopOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
                .font(DesignTokens.Font.caption)
            }

            Divider()

            // Shortcut
            HStack {
                Text("Shortcut:")
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.hotkey },
                    set: { newValue in
                        settings.hotkey = newValue
                        showFnKeyHint = newValue.needsFunctionKeyHint
                    }
                )) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .font(DesignTokens.Font.caption)
            }

            if showFnKeyHint || settings.hotkey.needsFunctionKeyHint {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Enable standard function keys", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("To press \(settings.hotkey.label) without holding Fn:\nSystem Settings → Keyboard → \"Use F1, F2, etc. as standard function keys\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Open Keyboard Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                }
                .padding(8)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Brand Names
            Text("Brand Names")
                .font(DesignTokens.Font.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            HStack(spacing: 4) {
                TextField("Wrong (optional)", text: $newFrom)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Font.caption)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                TextField("Correct", text: $newTo)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Font.caption)
                Button {
                    guard !newTo.isEmpty else { return }
                    if newFrom.isEmpty {
                        replacementService.addBoostWord(newTo)
                    } else {
                        replacementService.addReplacement(from: newFrom, to: newTo)
                    }
                    newFrom = ""
                    newTo = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newTo.isEmpty)
                .buttonStyle(.plain)
            }

            let hasEntries = !replacementService.replacements.isEmpty || !replacementService.boostWords.isEmpty
            if hasEntries {
                ScrollView {
                    VStack(spacing: 2) {
                        // Boost-only words
                        ForEach(replacementService.boostWords, id: \.self) { word in
                            HStack(spacing: 4) {
                                Text(word)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    replacementService.removeBoostWord(word)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(DesignTokens.Font.caption)
                        }

                        // Replacement pairs
                        ForEach(
                            replacementService.replacements.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { from, to in
                            HStack(spacing: 4) {
                                Text(from)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption2)
                                Text(to)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    replacementService.removeReplacement(from: from)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(DesignTokens.Font.caption)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

        }
    }
}
