# Changelog

All notable changes to Steneo. Dates are release dates; versions follow the app's `MARKETING_VERSION`.

## 1.2.0

### Added
- **Remove filler words (opt-in)** — after dictation, Steneo can drop spoken fillers (um, uh, äh, ähm) right on your Mac. It's instant, rule-based, and never changes your actual wording — so it's safe in any language. Punctuation & capitalization already come from the speech model. Enable it in **Settings → Text Output**. (Smart formatting — paragraphs, bullet lists, "→ email / Slack", tone — is planned for a later version.)

### Changed
- **More reliable & accurate transcription** — your whole recording is now transcribed in one full-context pass the moment you stop, instead of in live windows. This fixes words lost at the very start of a recording and garbled short clips, and improves overall accuracy. The text appears (and is pasted) when you stop.
- **Renamed Stenote → Steneo.** Same app, same on-device engine — only the name. Your settings, history, and permissions carry over (the underlying identifier is unchanged).
- **Instant, honest recording feedback** — the start sound fires the instant you press, and the mic turns red only once it's actually capturing, so a red mic always means you're being recorded. The app no longer gets throttled when idle (App Nap), so the first press after a quiet spell is immediate too.
- **Menubar icon states** — a deep-red mic while recording, calm **blue** while transcribing an audio file, calm **green** when a file result is ready (clearing the next time you open the popover).

## 1.0.0

The 1.0 release — still 100% on-device and private, now with file transcription, encrypted history, a clearer level meter, and dictation stats.

### Added
- **Transcribe audio files** — drag a file onto the popover, pick one with the waveform button in the menubar header, or transcribe an audio file from the clipboard. Files run through the batch speech engine; the text is copied and saved to History.
- **Words-per-minute** — your dictation pace is tracked per recording and shown as an average (`~140 wpm avg`) in the footer stats. File imports and very short or implausibly slow/fast clips are excluded so the number stays honest.
- **Clearer level meter** — the recording waveform is now a boxed strip of bars that reads as an input-level meter: bars rise with your voice and turn orange when you're too loud.
- **Menubar feedback** — the mic icon gently pulses while recording, and a short status line confirms file transcriptions ("Saved to history · copied") or surfaces errors.

### Changed
- **Transcription history is now encrypted at rest** (AES-GCM, key held in the macOS Keychain). Existing plaintext history is migrated automatically on first launch. Recorded audio is still never written to disk.
- Reworked the audio level pipeline to feed the meter directly, dropping the old raw-sample buffer — less memory and less work while recording.

### Internal
- Added a unit-test target (27 tests) covering the streaming-window invariant (the guard behind the 0.8.6 fix), trailing-stutter removal, the AES-GCM primitive, and WPM eligibility.

## 0.8.7

Robustness pass on the recording pipeline:
- A **stop pressed during the brief start-up window** is now honored instead of ignored.
- The audio resampler is reset between recordings, so a new recording never inherits the previous session's filter state.
- The streaming window size is clamped at runtime (not just a debug assert), so it can never exceed the speech model's input limit regardless of future tuning — a permanent guard against the 0.8.6 class of bug.
- An empty final transcript no longer leaves a stale preview fragment behind.

## 0.8.6

### Fixed
- **Long recordings no longer lose the middle.** The streaming recognizer assembled each window as left-context + chunk + right-context = 15.5 s, which exceeds the speech model's fixed 15 s input. Every middle window overflowed and was silently discarded, so only the start and end of a long dictation survived. The window now fits the model with margin (and is clamped so it can never regress). Audio is also delivered to the recognizer through a single in-order pipeline (no out-of-order or overlapping buffers), and pre-roll buffering is bounded, so memory stays flat on arbitrarily long recordings.

## 0.8.5

### Fixed
- **Dropped characters in the output** (e.g. "Deutsch" → "Dutsch", "sauber" → "saubr"). After the switch to whole-text paste, a full sentence was typed key-by-key with no gap, overrunning the target app's event queue so it silently dropped letters. Sentences now insert atomically via the clipboard; the direct-typing path (short snippets / Direct Typing mode) is paced and runs off the main thread so it stays reliable without freezing the UI.

## 0.8.4

### Added
- **Instant start** — pressing the shortcut reacts immediately: amber mic icon + sound the moment it registers, while the (reused, pre-warmed) audio engine spins up. Audio captured during start-up is buffered and fed to the recognizer, so no words are lost.
- **Whole-text paste at stop** — the complete transcript is inserted once when you finish, instead of word-by-word during recording. No more chunk-boundary glitches; the popover still shows a live preview.
- **Individually toggleable voice commands** — turn New line / New paragraph / Period / Comma / Question mark / Exclamation / Colon / Semicolon on or off independently. Paragraph breaks are now the explicit "new paragraph" command (reliable with whole-text paste).
- **Emoji by voice** (opt-in) — say a word next to "emoji", e.g. "smile emoji" → 😊, "emoji fire" → 🔥. Curated, on-device, no model.
- **Microphone warning** in the menubar when access is denied, with a one-click Grant — instead of silently capturing nothing.
- **Recordings per page** and a longer silence range (default 1 min, plus 2 min / 5 min).

### Fixed
- **Crash** when typing characters above U+FFFF (emoji, some CJK) in direct-typing mode — now encoded as UTF-16.
- **Media pause** (Spotify/Apple Music) runs off the main thread, so the first recording isn't delayed by the Automation prompt; the prompt is also front-loaded in onboarding.
- **Recording no longer dies silently** on input-device changes; **clipboard fully preserved** (images/files/rich text) with restore gated on pasting completing.
- If Accessibility is off, the transcript is left on the clipboard (and always saved to history) instead of vanishing.
- "New York, New York" and similar real repetition is no longer trimmed as a stutter.

### Changed
- VoiceOver labels on icon-only controls; clearer Accessibility-grant guidance in onboarding.
- Removed the unreliable automatic pause-based paragraph break (use the "new paragraph" command).
- README documents local data-at-rest and build-from-source signing.

## 0.8.3

- Settings polish: app-wide hover feedback; hovering a category lifts the whole card; bigger, consistent expand/collapse hit area; blue underlined GitHub links.
- Word Corrections: accurate Model-Boosting guidance; boost-only words under 4 letters are caught with a tip.

## 0.8.2

- Fixed **Launch at Login** (the toggle did nothing due to a state-tracking bug).
- Onboarding polish: clear button hovers, a "click a text field first" step, no stray focus ring.

## 0.8.1

- Guided first-run setup (permissions, shortcut, preferences).
- Polished menubar UI.

## 0.8.0

- Renamed **Talkman → Stenote**.
