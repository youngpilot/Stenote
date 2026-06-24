# Changelog

All notable changes to Stenote. Dates are release dates; versions follow the app's `MARKETING_VERSION`.

## 0.8.4

### Added
- **Emoji by voice** (opt-in) — say a word next to "emoji" to insert one, e.g. "smile emoji" → 😊, "emoji fire" → 🔥. Curated, on-device, no model.
- **Microphone warning** in the menubar when access is denied, with a one-click Grant — instead of silently capturing nothing.

### Fixed
- **Crash** when typing characters above U+FFFF (emoji, some CJK) in direct-typing mode — now encoded as UTF-16.
- **Voice commands** ("period", "comma", "new line") now take effect immediately and apply to streamed text, not only after a relaunch / on the final word.
- **Recording no longer dies silently** when the input device changes mid-recording (AirPods unplugged, dock change) — the audio tap rebuilds.
- **Clipboard is fully preserved** across a recording — images, files, and rich text are restored, not just plain text; restore waits for pasting to finish instead of racing a fixed timer.
- If Accessibility is off, the transcript is left on the clipboard (and always saved to history) instead of vanishing.
- "New York, New York" and similar real repetition is no longer trimmed as a stutter.

### Changed
- VoiceOver labels on icon-only controls; clearer Accessibility-grant guidance in onboarding.
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
