# TranslateBar

A lightweight macOS menubar app that translates clipboard text to natural professional English using the OpenAI API.

## Features

- **Global Hotkey**: Press `Cmd+Shift+T` from anywhere to translate clipboard contents
- **Menubar App**: Lives in your menubar with no Dock icon
- **Secure Storage**: API key stored in macOS Keychain (not UserDefaults)
- **Auto-paste**: Optionally paste translated text directly into the focused app
- **Clean UI**: Simple popover interface for configuration and manual translation

## Project Structure

```
TranslateBar/
├── TranslateBar/
│   ├── TranslateBarApp.swift       # App entry point & AppDelegate
│   ├── StatusBarController.swift   # NSStatusBar & popover management
│   ├── PopoverView.swift           # SwiftUI interface
│   ├── AppViewModel.swift          # Main state management
│   ├── HotkeyManager.swift         # Global keyboard shortcut (Carbon)
│   ├── ClipboardManager.swift      # NSPasteboard read/write
│   ├── OpenAIClient.swift          # OpenAI API integration
│   ├── KeychainHelper.swift        # Secure API key storage
│   ├── AccessibilityHelper.swift   # CGEvent & permissions
│   ├── Info.plist                  # App configuration
│   └── TranslateBar.entitlements   # App entitlements
├── TranslateBar.xcodeproj/         # Xcode project (generated)
├── project.yml                     # XcodeGen specification
└── README.md
```

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- OpenAI API key

## Quick Start

### Option 1: Using the Pre-Generated Xcode Project

The project already includes a generated `TranslateBar.xcodeproj`:

```bash
cd TranslateBar
open TranslateBar.xcodeproj
```

Then in Xcode:
1. Press `Cmd+R` to build and run
2. The app will appear in your menubar with a globe icon

### Option 2: Regenerate Xcode Project (if needed)

If you need to regenerate the Xcode project:

```bash
# Install xcodegen if needed
brew install xcodegen

# Generate the project
cd TranslateBar
xcodegen generate

# Open in Xcode
open TranslateBar.xcodeproj
```

### Building from Command Line

```bash
cd TranslateBar
xcodebuild -project TranslateBar.xcodeproj \
  -scheme TranslateBar \
  -configuration Debug \
  build
```

The built app will be in:
`~/Library/Developer/Xcode/DerivedData/TranslateBar-*/Build/Products/Debug/TranslateBar.app`

## How to Use

### First-Time Setup

1. Click the globe icon (🌐) in the menubar
2. Enter your OpenAI API key (starts with `sk-`)
3. Click **Save API Key**
4. (Optional) Enable **Auto-paste after translation**
5. If auto-paste is enabled, grant Accessibility permission when prompted

### Translation Workflow

**Method 1: Global Hotkey**
1. Select text in any app
2. Copy it (`Cmd+C`)
3. Press `Cmd+Shift+T`
4. If auto-paste is off, paste manually (`Cmd+V`)
5. If auto-paste is on, text is automatically pasted

**Method 2: Manual Button**
1. Copy text to clipboard
2. Click the menubar icon
3. Click **Translate Clipboard Now**
4. Paste the result

### Testing the App

1. **Run the app** - Build and run in Xcode (`Cmd+R`)
2. **Enter API key** - Click the globe icon, enter your OpenAI API key
3. **Test clipboard** - Copy some text in any language
4. **Test hotkey** - Press `Cmd+Shift+T`
5. **Check result** - Paste (`Cmd+V`) to see translated text

### Accessibility Permission (for Auto-paste)

If you enable auto-paste, the app needs Accessibility permission to simulate `Cmd+V`:

1. Click **Request Permission** in the popover, or
2. Go to **System Settings → Privacy & Security → Accessibility**
3. Find TranslateBar and enable it
4. You may need to restart the app

## How It Works

| Component | Technology | Purpose |
|-----------|------------|---------|
| Clipboard | `NSPasteboard.general` | Read and write plain text |
| Translation | OpenAI API (`gpt-4o-mini`) | Translate text to English |
| Global Hotkey | Carbon Hot Key APIs | `Cmd+Shift+T` from anywhere |
| Auto-paste | `CGEvent` | Simulate `Cmd+V` keystroke |
| API Key Storage | Keychain Services | Secure credential storage |
| UI | SwiftUI + NSPopover | Menubar popover interface |

## Translation Prompt

The exact prompt sent to OpenAI:

```
Translate the following text to natural, concise, professional English.
Preserve meaning and tone.
Return only the translated text.

Text:
"""
{clipboard_text}
"""
```

## API Configuration

- **Model**: `gpt-4o-mini` (fast, cost-effective)
- **Temperature**: `0.3` (low for consistent translations)
- **Max tokens**: `2048`
- **Timeout**: `30 seconds`

## Troubleshooting

### Hotkey not working
- Make sure no other app has registered `Cmd+Shift+T`
- Try restarting the app
- Check Console.app for "Failed to register hotkey" errors

### Auto-paste not working
- Check Accessibility permission is granted
- Click "Request Permission" or manually add in System Settings
- Restart the app after granting permission

### API errors
- Verify your API key is correct (starts with `sk-`)
- Check you have API credits in your OpenAI account
- Look at the status message in the popover for specific errors

### App not appearing in menubar
- Check if the app is running (Activity Monitor)
- The icon is a small globe; it may be hidden by other menubar icons
- Try holding `Cmd` and dragging menubar icons to rearrange

### Build errors
- Ensure you have Xcode 15.0 or later
- Run `xcodegen generate` to regenerate the project
- Clean build folder: `Cmd+Shift+K` in Xcode

## Dependencies

**None** - This project uses only native macOS frameworks:
- `SwiftUI` - User interface
- `AppKit` - Status bar and clipboard
- `Carbon` - Global hotkey registration
- `Security` - Keychain access
- `ApplicationServices` - Accessibility APIs

## Key Implementation Details

### Global Hotkey (Carbon)
The app uses legacy Carbon APIs (`RegisterEventHotKey`) because this is the only reliable way to register system-wide hotkeys in macOS. The key code for 'T' is `17`, and the modifier mask combines `cmdKey | shiftKey`.

### Keychain Storage
API keys are stored using `SecItemAdd` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to ensure they're only accessible when the device is unlocked and never synced to other devices.

### No App Sandbox
The app runs without App Sandbox because `CGEvent` posting requires unrestricted access. This is necessary for the auto-paste feature to work.

### LSUIElement
The `Info.plist` includes `LSUIElement = true` which makes the app a "background" or "agent" app with no Dock icon.

## Security Notes

- API key is stored in macOS Keychain, not in plain text
- App Sandbox is disabled (required for CGEvent)
- The app only accesses clipboard when triggered
- No data is sent anywhere except OpenAI's API
- No analytics or telemetry

## Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| `TranslateBarApp.swift` | ~40 | App entry point, AppDelegate |
| `StatusBarController.swift` | ~50 | NSStatusBar, popover management |
| `PopoverView.swift` | ~180 | Main SwiftUI interface |
| `AppViewModel.swift` | ~110 | State management, translation logic |
| `HotkeyManager.swift` | ~90 | Carbon hotkey registration |
| `ClipboardManager.swift` | ~35 | NSPasteboard wrapper |
| `OpenAIClient.swift` | ~110 | OpenAI API client |
| `KeychainHelper.swift` | ~70 | Keychain Services wrapper |
| `AccessibilityHelper.swift` | ~60 | CGEvent, accessibility checks |

## License

MIT License - Use freely for personal or commercial purposes.
