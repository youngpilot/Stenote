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
                        .buttonStyle(.plain)
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
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 580)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: StenoteApp.micIdleIcon)
                .resizable().renderingMode(.template)
                .frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            Text("Welcome to Stenote")
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
            stepHeader("Permissions", "Stenote needs two permissions to work.")
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
                desc: "To type the text into other apps and to use the global shortcut.",
                granted: axGranted,
                action: requestAX
            )
            Label("Spotify & Apple Music control is requested later, only the first time you record with pausing on.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
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
            Toggle("Start Stenote at login", isOn: Binding(
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
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("You're all set")
                .font(.largeTitle).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 10) {
                howToRow("1.", "Press \(shortcutSummary) in any app.")
                howToRow("2.", "Speak. Pause, or press again, to finish.")
                howToRow("3.", "Your text appears right at the cursor.")
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
                Button("Allow", action: action).buttonStyle(.bordered)
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
