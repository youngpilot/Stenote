# Talkman

Native macOS menubar app for real-time voice-to-text transcription. Speak into your mic and text appears live in whatever app you were working in.

Powered by [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) running locally on Apple Neural Engine via [FluidAudio SDK](https://github.com/AntAudioIntelligence/FluidAudio) — no cloud, no API keys, no latency.

## Features

- **Real-time transcription** — text is inserted live as you speak, triggered by natural speech pauses (VAD-based)
- **25 languages** — Parakeet v3 supports English, German, French, Spanish, and 21 more European languages
- **Menubar-only** — lives in your menu bar, no dock icon, no windows
- **Global hotkey** — double-press Right Cmd to toggle recording (configurable: Fn, F5, F6, Ctrl+Shift+Space)
- **Smart clipboard** — uses concealed pasteboard type so clipboard managers ignore transcription pastes; restores your clipboard after each session
- **Brand name corrections** — teach Talkman your brand names with custom word replacements + vocabulary boosting
- **Paragraph breaks** — automatically inserts paragraph breaks after 2.5s+ pauses
- **Auto-stop** — configurable silence timeout (10s–60s or off)
- **Prefix/suffix text** — automatically prepend or append text to each transcription
- **Transcription history** — last 10 recordings, click to copy
- **Launch at Login** — via SMAppService

## Requirements

- macOS 15.2+
- Apple Silicon (M1 or later) — runs inference on Neural Engine
- Microphone permission
- Accessibility permission (for simulating Cmd+V paste into target apps)

## How It Works

1. Click the mic icon or press the hotkey to start recording
2. Speak naturally — Talkman detects speech pauses via Silero VAD
3. Each speech segment is transcribed on-device and pasted into the focused text field
4. Press the hotkey again or let auto-stop end the session

The mic icon turns red while recording.

## Tech Stack

- Swift 6 + SwiftUI
- FluidAudio SDK 0.12.2 (Parakeet TDT v3 CoreML, Silero VAD, CTC vocabulary boosting)
- Apple Neural Engine for inference (~120x real-time on M4 Pro)
- AVAudioEngine for mic capture (16kHz mono)
- CGEvent for paste simulation
- NSEvent global monitors for hotkey detection

## Building

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
