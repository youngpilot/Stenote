# Talkman

Native macOS menubar app for real-time voice-to-text transcription. Speak into your mic and text appears live in whatever app you were working in.

Powered by [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) running locally on Apple Neural Engine via [FluidAudio SDK](https://github.com/AntAudioIntelligence/FluidAudio) — no cloud, no API keys, no latency.

## Install

1. Download `Talkman-0.3.0.dmg` from the [latest release](https://github.com/youngpilot/Talkman/releases/latest)
2. Open the DMG and drag Talkman to Applications
3. Launch Talkman — grant Microphone and Accessibility permissions when prompted
4. The ASR model downloads automatically on first launch (~200MB)

Requires **macOS 15.2+** and **Apple Silicon** (M1 or later).

## Usage

1. **Double-press Right Cmd** (or your configured hotkey) to start recording
2. Speak naturally — Talkman detects speech pauses and transcribes on-device
3. Text is pasted live into whatever app was focused when you started
4. Press the hotkey again, or let auto-stop end the session after silence

You can also **right-click the menubar icon** to toggle recording, or **left-click** to open the settings panel.

The mic icon turns red while recording.

## Features

- **Real-time transcription** — text is inserted live as you speak, triggered by natural speech pauses (VAD-based)
- **25 languages** — Parakeet v3 supports English, German, French, Spanish, and 21 more European languages
- **Menubar-only** — lives in your menu bar, no dock icon, no windows
- **Global hotkey** — double-press Right Cmd to toggle recording (configurable: Fn, F5, F6, Ctrl+Shift+Space)
- **Right-click to record** — right-click the menubar icon to start/stop recording
- **Smart clipboard** — uses concealed pasteboard type so clipboard managers ignore transcription pastes; restores your clipboard after each session
- **Brand name corrections** — teach Talkman your brand names with custom word replacements + vocabulary boosting
- **Paragraph breaks** — automatically inserts paragraph breaks after 2.5s+ pauses
- **Auto-stop** — configurable silence timeout (10s-60s or off)
- **Prefix/suffix text** — automatically prepend or append text to each transcription
- **Transcription history** — last 10 recordings, click to copy
- **Launch at Login** — via SMAppService

## Requirements

- macOS 15.2+
- Apple Silicon (M1 or later) — runs inference on Neural Engine
- Microphone permission
- Accessibility permission (for simulating Cmd+V paste into target apps)

## Tech Stack

- Swift 6 + SwiftUI
- FluidAudio SDK 0.12.2 (Parakeet TDT v3 CoreML, Silero VAD, CTC vocabulary boosting)
- Apple Neural Engine for inference (~120x real-time on M4 Pro)
- AVAudioEngine for mic capture (16kHz mono)
- CGEvent for paste simulation
- NSEvent global monitors for hotkey detection

## Building from Source

```bash
xcodebuild -project Talkman.xcodeproj -scheme Talkman -configuration Debug build
```

Models are downloaded automatically on first launch (~200MB).

## Credits

- Menubar icon: [Solar](https://icon-sets.iconify.design/solar/) by 480 Design (CC BY 4.0)
- ASR model: [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) (Apache 2.0)
- Audio SDK: [FluidAudio](https://github.com/AntAudioIntelligence/FluidAudio)

## License

MIT
