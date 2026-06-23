<p align="center">
  <img src="assets/feature.png" alt="Talkman" width="640">
</p>

# Talkman

**The voice-to-text app macOS should have built in.**

_Free for private use · 100% on-device · no cloud, no API keys._

Talkman is a native menubar app that transcribes your voice in real time — directly into whatever app you're working in. No cloud. No API keys. No latency. Just speak and watch text appear instantly.

Built on [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), running entirely on-device via Apple Neural Engine through [FluidAudio SDK](https://github.com/AntAudioIntelligence/FluidAudio). Transcription runs at **~120x real-time on M4 Pro** — faster than you can speak.

## Why Talkman

**Apple's built-in Dictation is slow, unreliable, and English-centric.** It sends your audio to Apple's servers, adds noticeable latency, frequently drops words, and struggles with accents, technical terms, and non-English languages.

Talkman fixes all of that:

- **Instant** — transcription happens on your Neural Engine in milliseconds, not seconds. No network round-trip, no waiting.
- **Accurate** — Parakeet TDT v3 is a state-of-the-art 600M parameter model trained on 86,000+ hours of speech. It handles accents, technical jargon, and natural speech patterns that Apple Dictation mangles.
- **Private** — your voice never leaves your Mac. Zero data sent anywhere. Ever.
- **Truly multilingual** — automatic language detection across 25 European languages with the same model, the same accuracy, no switching required:

  English, German, French, Spanish, Italian, Portuguese, Dutch, Polish, Czech, Romanian, Hungarian, Swedish, Danish, Finnish, Greek, Bulgarian, Croatian, Slovak, Slovenian, Estonian, Latvian, Lithuanian, Russian, Ukrainian, Maltese

- **Reliable** — no "I didn't catch that", no phantom words, no random stops. VAD-based speech detection means it transcribes exactly when you speak and stops exactly when you don't.

## How Talkman compares

Most dictation tools make you trade something away: privacy for polish, or price for accuracy. Talkman's edge is refusing that trade. It is private, local, focused, and free at the same time.

| | Talkman | Apple Dictation (macOS Tahoe) | Wispr Flow | Whisper apps (superwhisper, MacWhisper) |
|---|---|---|---|---|
| **Compute** | 100% on-device (Neural Engine) | On-device | Cloud | On-device |
| **Privacy** | Audio never leaves your Mac | Stays on device | Audio uploaded to the cloud; "Privacy Mode" only limits retention | Stays on device |
| **Price** | Free, unlimited | Free | Free tier ~2,000 words/week; Pro $15/mo ($144/yr) | Freemium or paid (subscription or one-time) |
| **Languages** | 25 European, auto-detected with no manual switching, even German and English mixed in one sentence | Several, but you switch by hand (Globe key) | 100+ (cloud) | Many, but usually one model per language or a manual pick |
| **Accuracy model** | Parakeet TDT v3, a transducer that minimizes hallucination | Apple on-device model; silence cutoffs, no custom vocabulary, accuracy regressions across releases | Cloud models with strong auto-formatting | Whisper: accurate, but prone to hallucinate during silence |
| **Footprint** | 16 MB app, ~460 MB model on first run, then fully offline | Built into macOS | Tiny app, but needs internet for every dictation | Larger models (Whisper large is ~1.5 GB) |
| **Design** | Minimal menubar app, types into any app | System feature | Polished, with AI commands and formatting | File transcription plus power features |

What this means in practice:

- **Versus Apple Dictation:** both are private and on-device, but Apple makes you switch languages by hand, cuts off after pauses, has no custom vocabulary, and regresses between macOS releases. Talkman just listens, detects the language automatically (even when you mix German and English), and types.
- **Versus Wispr Flow:** Wispr is polished, but every word is processed in the cloud and the free tier runs out at about 2,000 words per week (roughly 15 minutes of talking). Talkman is unlimited and free, and your voice never leaves the machine.
- **Versus Whisper apps:** same on-device privacy, but Whisper models are larger and tend to invent text during silence. Parakeet TDT is smaller, faster, and far less hallucination-prone, which is exactly what you want when the text lands straight in your editor.

Talkman deliberately does less: no account, no subscription, no cloud, no feature bloat. Just fast, private, reliable dictation in any app.

## Remove the Keyboard Bottleneck

Most people type at 40-80 WPM. You speak at 150+ WPM. Talkman closes that gap — everything you'd normally type, you can now dictate at 2-3x the speed with zero accuracy loss.

**Best use cases:**

- **Writing emails and messages** — draft replies in seconds instead of minutes
- **Meeting notes and documentation** — speak your thoughts while they're fresh, get clean text instantly
- **AI prompting** — dictate complex prompts to ChatGPT, Claude, Cursor, or any LLM tool faster than you can type them. Describe what you want in natural speech — no more wrestling with keyboard input for multi-paragraph instructions
- **Coding comments and commit messages** — describe what your code does without breaking flow
- **Chat and Slack** — respond at the speed of conversation
- **Journaling and brainstorming** — capture ideas faster than you can think them through
- **Long-form writing** — articles, reports, specs — dictate the first draft, then edit
- **Accessibility** — for anyone with RSI, carpal tunnel, or motor impairments, voice input isn't a convenience — it's a necessity

Talkman works in **any text field, in any app** — your editor, browser, terminal, Notion, Slack, Mail, whatever has focus.

## Install

1. Download `Talkman-0.7.1.dmg` from the [latest release](https://github.com/youngpilot/Talkman/releases/latest)
2. Open the DMG and drag Talkman to Applications
3. Launch Talkman — grant Microphone and Accessibility permissions when prompted
4. The speech model downloads automatically on first launch (~460 MB, one-time — then fully offline). The optional word-boosting model adds ~100 MB only if you turn it on.

> If macOS says the app "cannot be opened because the developer cannot be verified," right-click the app → **Open** → **Open**. Released builds are notarized, so this only happens with copies you build yourself.

Requires **macOS 15.2+** and **Apple Silicon** (M1 or later).

## Usage

1. **Double-press Right ⌥** (or your configured hotkey) to start recording
2. Speak naturally — Talkman detects speech pauses and transcribes on-device
3. Text is pasted into whatever app was focused when you started
4. Press the hotkey again, or let auto-stop end the session after silence

You can also **right-click the menubar icon** to toggle recording, or **left-click** to open the settings panel.

The mic icon turns red while recording.

<p align="center">
  <img src="assets/screenshot-main.png" alt="Main menu" width="340">
  &nbsp;&nbsp;&nbsp;
  <img src="assets/screenshot-settings.png" alt="Settings" width="340">
</p>

## Features

- **Streaming transcription** — confirmed text is inserted incrementally as you speak, with maximum accuracy from continuous context.
- **25 languages, auto-detected** — speak in any supported language and Talkman recognizes it automatically. No language switching needed.
- **Menubar-only** — lives in your menu bar, no dock icon, no windows, out of your way
- **Global hotkey** — double-press Right ⌥ to toggle recording (configurable: Right ⌘, ⌥ + Space, Fn + Space, F5, Fn/🌐 — multiple shortcuts can be active simultaneously)
- **Right-click to record** — right-click the menubar icon to start/stop recording
- **Media playback control** — automatically pauses Spotify or Apple Music while recording and resumes after
- **Smart clipboard** — uses concealed pasteboard type so clipboard managers (Maccy, Paste, Alfred) ignore transcription pastes; restores your clipboard after each session
- **Word corrections** — teach Talkman your brand names with custom word replacements + vocabulary boosting
- **Paragraph breaks** — automatically inserts paragraph breaks after 2.5s+ pauses
- **Auto-stop** — configurable silence timeout (10s-60s or off)
- **Prefix/suffix text** — automatically prepend or append text to each transcription
- **Transcription history** — last 10 recordings, click to copy
- **Launch at Login** — via SMAppService
- **Update checks** — your choice: *Manual* (no network calls at all, the default) or *Daily* (one lightweight GitHub check per day). No account, no telemetry.

## Requirements

- macOS 15.2+
- Apple Silicon (M1 or later) — runs inference on Neural Engine
- Microphone permission
- Accessibility permission (for simulating Cmd+V paste into target apps)

## Tech Stack

- Swift 6 + SwiftUI
- FluidAudio SDK 0.13.0 (Parakeet TDT v3 CoreML, Silero VAD, CTC vocabulary boosting)
- Apple Neural Engine for inference
- AVAudioEngine for mic capture (16kHz mono)
- CGEvent for paste simulation
- NSEvent global monitors for hotkey detection

## Building from Source

Requires **Xcode 16+** (developed on Xcode 26.5) and an Apple Silicon Mac.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Talkman.xcodeproj -scheme Talkman -configuration Debug build
```

The first build resolves the FluidAudio Swift package automatically. To produce a signed build, set your own Apple Developer Team in Xcode (*Signing & Capabilities*) or override `DEVELOPMENT_TEAM`. Models are downloaded automatically on first launch (~460 MB, one-time).

## Experimental

The `TalkmanIM/` directory contains a work-in-progress system-wide **input method extension** (an alternative to clipboard-paste insertion). It is **not yet wired into the app** and is not required to build or run Talkman — treat it as experimental. Build it standalone with `scripts/build-ime.sh` (requires your own Apple Developer signing identity).

## Credits

- Menubar icon: [Solar](https://icon-sets.iconify.design/solar/) by 480 Design (CC BY 4.0)
- ASR model: [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (Apache 2.0)
- Audio SDK: [FluidAudio](https://github.com/AntAudioIntelligence/FluidAudio)

## License

**Talkman is free for private use.** It is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE) — you may use, modify, and share it for any noncommercial purpose (personal use, hobby projects, study, and noncommercial organizations). Commercial use is not permitted.

Copyright © 2026 Julian Schiemann.
