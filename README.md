# TransLite

A lightweight macOS menubar app for instant text translation.

**[Download](https://translite.app)** · **[Website](https://translite.app)**

## Features

- Global hotkey (`Cmd+Shift+T`) to translate from anywhere
- Auto-paste translated text directly
- Multiple languages and tones
- Lives in your menubar, no Dock icon

## Requirements

- macOS 13.0+
- OpenAI API key

## Development

Build and open a local Debug version:

```bash
./scripts/dev.sh
```

Run the same command after each change. Xcode builds incrementally, closes the
previous development instance and opens the new one. Use `--clean` only when an
incremental build behaves unexpectedly:

```bash
./scripts/dev.sh --clean
```

To compile without opening the app, use `./scripts/dev.sh --build-only`.

There is no hot reload; running the script is the short edit-build-launch loop.

## Publishing a release

The release script requires a clean `main` branch, XcodeGen, `create-dmg`, an
authenticated GitHub CLI, a Developer ID Application certificate, the Sparkle
private key and a `notarytool` Keychain profile named `TransLite`.

```bash
brew install xcodegen create-dmg
gh auth login
```

Publish a new version by incrementing both the semantic version and build
number:

```bash
./scripts/publish-release.sh 1.1.4 15 \
  --note "First change" \
  --note "Second change"
```

The script builds, signs and notarizes the DMG, updates `appcast.xml`, commits
and tags the release, uploads it to GitHub and publishes the updated appcast.
Run `./scripts/publish-release.sh --help` for configuration overrides.

## License

Proprietary - All rights reserved.
