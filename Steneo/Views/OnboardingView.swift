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

    private let lastStep = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: shortcutStep
                case 3: preferencesStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(28)

            Divider()

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .buttonStyle(OnboardingSubtleButtonStyle())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button(step == lastStep ? "Done" : "Continue") {
                    if step == lastStep { onFinish() } else { withAnimation { step += 1 } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // Nav chrome shouldn't draw a focus ring: on steps with no other
            // focusable content (welcome, ready), the prominent button would
            // otherwise auto-focus and show a ring on top of its accent fill.
            .focusEffectDisabled()
        }
        .frame(width: 460, height: 580)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    // MARK: Steps

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

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Permissions", "Steneo needs two permissions to work.")
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
            Label("Spotify & Apple Music control is requested later, only the first time you record with pausing on.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Your transcription history is encrypted on this Mac. The key is kept in your Keychain and never leaves the device — if macOS asks, choose Allow.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .onAppear {
            // Create the history-encryption key now, during setup, so any one-time
            // Keychain prompt happens here (explained above) — not later mid-use.
            if !warmedEncryption {
                warmedEncryption = true
                EncryptionService.shared.warm()
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Your shortcut", "Pick the key you press to start and stop recording. You can choose more than one.")
            ForEach(HotkeyChoice.allCases) { choice in
                Toggle(isOn: Binding(
                    get: { settings.hotkeys.contains(choice) },
                    set: { on in
                        var updated = settings.hotkeys
                        if on { updated.insert(choice) } else if updated.count > 1 { updated.remove(choice) }
                        settings.hotkeys = updated
                    }
                )) {
                    Text(choice.label)
                }
                .toggleStyle(.checkbox)
            }
            if settings.hotkeys.contains(.f5) {
                Label("For F5: enable “Use F1, F2, etc. as standard function keys” in System Settings → Keyboard.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Preferences", "Sensible defaults — change any of these later in Settings.")
            Toggle("Mute media playback while recording", isOn: Binding(
                get: { settings.silenceMediaWhileRecording },
                set: { settings.silenceMediaWhileRecording = $0 }))
            Toggle("Pause Spotify & Apple Music while recording", isOn: Binding(
                get: { settings.pauseMediaApps },
                set: { settings.pauseMediaApps = $0 }))
            Toggle("Start Steneo at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }))
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
        .onAppear {
            // Front-load the Spotify/Apple Music Automation prompt during setup,
            // so the first recording reacts instantly. Only does anything if
            // pausing is on and a player is actually running.
            if !requestedMediaAuth, settings.pauseMediaApps {
                requestedMediaAuth = true
                SystemAudioService.shared.requestMediaAutomationPermission()
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("You're all set")
                .font(.largeTitle).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 10) {
                howToRow("1.", "Click into the text field where you want the text to appear.")
                howToRow("2.", "\(shortcutSummary) to start recording.")
                howToRow("3.", "Speak. Pause, or press again, to finish.")
                howToRow("4.", "Your text lands right at the cursor.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Text("Tip: right-click the menubar icon to start/stop, left-click for settings.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
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

    private func howToRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(num).fontWeight(.semibold).foregroundStyle(.tint).frame(width: 18, alignment: .leading)
            Text(text)
            Spacer(minLength: 0)
        }
    }

    private var shortcutSummary: String {
        let labels = HotkeyChoice.allCases.filter { settings.hotkeys.contains($0) }.map { $0.label }
        return labels.first ?? "your shortcut"
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
