# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

Use GitHub's private vulnerability reporting: open the repository's **Security** tab → **Report a vulnerability**. This opens a private advisory visible only to the maintainer.

When reporting, please include:

- A description of the issue and its impact
- Steps to reproduce (a proof of concept if possible)
- The Stenote version (Settings footer) and your macOS version

You can expect an initial response within a few days. Once a fix is available it will ship in a new notarized release, and you'll be credited in the advisory unless you prefer otherwise.

## Scope

Stenote runs fully on-device. It requests **Microphone** (to hear you) and **Accessibility** (to type into other apps and use the global shortcut), and uses Apple Events to pause Spotify/Apple Music. The only network request is the optional GitHub update check (off by default). Findings around these surfaces — permission misuse, clipboard handling, injected input, or unexpected network egress — are especially in scope.

## Supported versions

Only the latest release receives security fixes.
