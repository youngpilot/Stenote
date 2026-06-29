import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Presenter

/// Shows the one-time onboarding in its own window (the app is menubar-only).
/// Re-openable from Settings. Marks onboarding complete when the window closes.
@MainActor
final class OnboardingPresenter: NSObject, NSWindowDelegate {
    static let shared = OnboardingPresenter()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in self?.window?.close() })
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 460, height: 580))
        win.center()
        win.delegate = self
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsStore.shared.hasCompletedOnboarding = true
        // A test recording could still be live if the user closed mid-try — stop it.
        if RecordingManager.shared.isRecording || RecordingManager.shared.isStarting {
            RecordingManager.shared.toggle()
        }
        window = nil
    }
}

// MARK: - View

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var step = 0
    @State private var settings = SettingsStore.shared
    @State private var recordingManager = RecordingManager.shared
    @State private var micGranted = false
    @State private var axGranted = false
    @State private var requestedMediaAuth = false
    @State private var warmedEncryption = false

    // 0–4 = core flow (5 screens); 5–7 = optional "expert options".
    private let coreLast = 4
    private let expertLast = 7

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: tryItStep
                case 3: controlStep
                case 4: readyStep
                case 5: expertTextStep
                case 6: expertMoreStep
                default: expertPrefsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(28)

            Divider()
            navBar
        }
        .frame(width: 460, height: 580)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    // MARK: Navigation

    private var navBar: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(OnboardingSubtleButtonStyle())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step <= coreLast {
                HStack(spacing: 6) {
                    ForEach(0...coreLast, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                Text("Expert options · \(step - coreLast)/\(expertLast - coreLast)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(primaryLabel) {
                switch step {
                case coreLast, expertLast: onFinish()
                default: withAnimation { step += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .focusEffectDisabled()
    }

    private var primaryLabel: String {
        switch step {
        case coreLast: return "Start using Steneo"
        case expertLast: return "Done"
        default: return "Continue"
        }
    }

    // MARK: 1 · Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: SteneoApp.micIdleIcon)
                .resizable().renderingMode(.template)
                .frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            Text("Welcome to Steneo")
                .font(.largeTitle).fontWeight(.semibold)
            Text("Type with your voice in any app. Press a shortcut, speak, and your words land at the cursor — everything runs on your Mac. No cloud, no account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            modelStatus
            Spacer()
        }
    }

    @ViewBuilder private var modelStatus: some View {
        if recordingManager.isModelLoaded {
            Label("Speech model ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        } else if recordingManager.modelLoadError != nil {
            Label("Model download failed — check your connection", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(recordingManager.modelLoadingStep.isEmpty ? "Downloading speech model…" : recordingManager.modelLoadingStep)
                    .foregroundStyle(.secondary).font(.callout)
            }
        }
    }

    // MARK: 2 · Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Permissions", "Steneo needs two permissions to work. Granting them here means no nagging later.")
            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                desc: "To hear what you say. Audio is transcribed on-device and never leaves your Mac.",
                granted: micGranted,
                action: requestMic
            )
            permissionRow(
                icon: "accessibility",
                title: "Accessibility",
                desc: "To type text into other apps and use the global shortcut. After you click Allow, enable Steneo in the list that opens.",
                granted: axGranted,
                action: requestAX
            )
            Label("Spotify & Apple Music control is requested once, automatically, the first time it's needed.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label("History is encrypted on this Mac; the key stays in your Keychain. If macOS asks, choose Allow.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .onAppear {
            if !warmedEncryption {
                warmedEncryption = true
                EncryptionService.shared.warm()
            }
        }
    }

    // MARK: 3 · Try it + mic colours

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Try it", "Press Record and say a sentence. It stays in this window — nothing is pasted or saved.")
            colorLegend
            Divider().opacity(0.5)
            testControl
            if let t = recordingManager.testTranscript {
                Text(t)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }
    }

    private var colorLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the menubar mic tells you:").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                legendDot(Color(hex: "#FF9500"), "Starting")
                legendDot(Color(hex: "#E04848"), "Recording")
                legendDot(Color(hex: "#E6A23C"), "Working")
                legendDot(Color(hex: "#34C759"), "Done")
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var testControl: some View {
        if !recordingManager.isModelLoaded {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Speech model still downloading — try again in a moment.").foregroundStyle(.secondary)
            }.font(.callout)
        } else {
            HStack(spacing: 12) {
                Button {
                    if recordingManager.isRecording || recordingManager.isStarting {
                        recordingManager.toggle()
                    } else {
                        recordingManager.startTestRecording()
                    }
                } label: {
                    Label(testActive ? "Stop" : "Record a test",
                          systemImage: testActive ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(OnboardingSubtleButtonStyle(bordered: true))
                Text(testStatus).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var testActive: Bool { recordingManager.isRecording || recordingManager.isStarting }

    private var testStatus: String {
        if recordingManager.isStarting { return "Starting…" }
        if recordingManager.isRecording { return "Recording — pause to finish." }
        if recordingManager.testTranscript != nil { return "Nice. That's exactly how it works." }
        return "First time? macOS will ask for microphone access."
    }

    // MARK: 4 · How to record

    private var controlStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader("How to record", "Pick a shortcut — you can choose more than one.")
            ForEach(HotkeyChoice.allCases) { choice in
                Toggle(isOn: Binding(
                    get: { settings.hotkeys.contains(choice) },
                    set: { on in
                        var updated = settings.hotkeys
                        if on { updated.insert(choice) } else if updated.count > 1 { updated.remove(choice) }
                        settings.hotkeys = updated
                    }
                )) { Text(choice.label) }
                .toggleStyle(.checkbox)
            }
            if settings.hotkeys.contains(.f5) {
                Label("For F5: enable “Use F1, F2 as standard function keys” in System Settings → Keyboard.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.5)
            Text("You can start & stop three ways:").font(.callout).foregroundStyle(.secondary)
            controlMethod("command", "Your shortcut", "The key(s) you picked above.")
            controlMethod("cursorarrow.rays", "Right-click the menubar mic", "Starts or stops instantly.")
            controlMethod("cursorarrow.click.2", "Left-click the mic, then hover", "Press the Record button in the panel header.")
            Spacer()
        }
    }

    // MARK: 5 · Ready

    private var readyStep: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.green)
            Text("You're all set").font(.largeTitle).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 9) {
                howToRow("1.", "Click where you want the text.")
                howToRow("2.", "\(shortcutSummary), or right-click the menubar mic, to start.")
                howToRow("3.", "Speak. Pause, or trigger again, to finish.")
                howToRow("4.", "Your text lands right at the cursor.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Toggle("Start Steneo at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }))
            .toggleStyle(.checkbox)
            Button("Show expert options →") { withAnimation { step = coreLast + 1 } }
                .buttonStyle(OnboardingSubtleButtonStyle())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .onAppear {
            // Front-load the Spotify/Apple Music Automation prompt for everyone who
            // reaches Ready (only does anything if pausing is on and a player runs).
            if !requestedMediaAuth, settings.pauseMediaApps {
                requestedMediaAuth = true
                SystemAudioService.shared.requestMediaAutomationPermission()
            }
        }
    }

    // MARK: 6–8 · Expert options (optional)

    private var expertTextStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Smarter text", "On-device and off by default — flip these on in Settings → Text Output.")
            featureRow("wand.and.stars", "Cleanup", "Rules instantly drops fillers (um, äh) and never changes your wording; AI does a smarter pass.")
            featureRow("text.alignleft", "Format", "Turn raw dictation into Paragraphs or a Bullet list.")
            Label("AI cleanup & formatting run via Apple Intelligence (formatting needs macOS 26).", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var expertMoreStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("More ways to use it", "Discover these whenever you like.")
            featureRow("hand.tap", "Push-to-talk", "Prefer holding? Settings → General → Activation → Hold: hold to record, release to stop.")
            featureRow("waveform", "Transcribe a file", "Drag an audio file onto the panel — it's transcribed on-device too.")
            featureRow("clock.arrow.circlepath", "History", "Your past transcriptions, encrypted on this Mac and searchable in the panel.")
            Spacer()
        }
    }

    private var expertPrefsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader("Preferences", "Sensible defaults — change any of these here or later in Settings.")
            Toggle("Mute media playback while recording", isOn: Binding(
                get: { settings.silenceMediaWhileRecording },
                set: { settings.silenceMediaWhileRecording = $0 }))
            Toggle("Pause Spotify & Apple Music while recording", isOn: Binding(
                get: { settings.pauseMediaApps },
                set: { settings.pauseMediaApps = $0 }))
            HStack {
                Text("Check for updates")
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.updateCheckMode },
                    set: { settings.updateCheckMode = $0 })) {
                    ForEach(UpdateCheckMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Text(settings.updateCheckMode == .daily
                 ? "Checks GitHub once a day. One request, no account, nothing sent."
                 : "No automatic network calls — only when you press Check Now.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: Pieces

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2).fontWeight(.semibold)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func permissionRow(icon: String, title: String, desc: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2).frame(width: 28).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(.green).font(.title2)
            } else {
                Button("Allow", action: action).buttonStyle(OnboardingSubtleButtonStyle(bordered: true))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func controlMethod(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 26).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func howToRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(num).fontWeight(.semibold).foregroundStyle(.tint).frame(width: 18, alignment: .leading)
            Text(text)
            Spacer(minLength: 0)
        }
    }

    private var shortcutSummary: String {
        let labels = HotkeyChoice.allCases.filter { settings.hotkeys.contains($0) }.map { $0.label }
        return labels.first ?? "Press your shortcut"
    }

    // MARK: Permissions

    private func refresh() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
        settings.refreshLaunchAtLoginStatus()
    }

    private func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { refresh() }
        }
    }

    private func requestAX() {
        // String-literal key (kAXTrustedCheckOptionPrompt isn't concurrency-safe in Swift 6).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

// MARK: - Button styles (clear, consistent hover on every onboarding button)

/// Primary call-to-action: accent-filled, brightens on hover, dims on press.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor))
            .brightness(configuration.isPressed ? -0.08 : (hovering ? 0.10 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Secondary/tertiary: a subtle fill that clearly brightens on hover.
/// `bordered` gives a resting fill (standalone actions like “Allow”); otherwise
/// it's transparent at rest (inline nav like “Back”). Foreground is inherited.
private struct OnboardingSubtleButtonStyle: ButtonStyle {
    var bordered = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let rest = bordered ? 0.07 : 0.0
        return configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : (hovering ? 0.13 : rest)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
