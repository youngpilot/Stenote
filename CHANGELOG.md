# Changelog

All notable changes to Stenote. Dates are release dates; versions follow the app's `MARKETING_VERSION`.

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
