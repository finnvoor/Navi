# Navi

An agent that can navigate, click, read, and fill forms in Safari on macOS.

[Download the latest release](https://github.com/finnvoor/Navi/releases/latest/download/Navi.zip)

## Tools

- **read_page** — Read the current page text, metadata, and interactive elements.
- **click** — Click a visible interactive element by its ID.
- **type** — Type text into an editable element, optionally submitting.
- **scroll** — Scroll to a specific element and highlight it.
- **navigate** — Navigate the active tab to a URL.
- **wait** — Pause briefly so the page can settle after an action.

## Development

Requires Xcode and [mise](https://mise.jdx.dev).

To cut a macOS release locally, make sure your Sparkle signing key exists in your login Keychain, keep the `jj` working copy clean, then run `mise run release:macos <version>`. The task bumps the version, builds the `Navi macOS` scheme with Xcode automatic signing, notarizes the app, signs the update using the Sparkle keychain account `ed25519` by default, creates or updates the GitHub release asset, updates `appcast.xml`, commits the release change with Jujutsu, and leaves you on a fresh empty working-copy change. For notarization, it uses a stored `notarytool` profile named `release` if present; otherwise it falls back to interactive Apple ID notarization using `NOTARY_APPLE_ID` or a terminal prompt, and `notarytool` will ask for your app-specific password.
