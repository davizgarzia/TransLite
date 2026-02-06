import AppKit
import ApplicationServices

/// Handles macOS Accessibility permissions and simulated key events
final class AccessibilityHelper {
    static let shared = AccessibilityHelper()

    private init() {}

    /// Raw AXIsProcessTrusted check (for debugging)
    var isAXTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Check if we can create CGEvents (for debugging)
    var canCreateCGEvent: Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let testEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        return testEvent != nil
    }

    /// Checks if the app has Accessibility permissions
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Requests Accessibility permissions by prompting the user
    /// This will show the system dialog if not already granted
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings to the Accessibility pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Simulates Cmd+C keystroke to copy selected text
    /// - Returns: True if successful, false if no permission or error
    @discardableResult
    func simulateCopy() -> Bool {
        guard hasAccessibilityPermission else {
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'C' is 8
        let keyCodeC: CGKeyCode = 8

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    /// Simulates Cmd+V keystroke to paste from clipboard
    /// - Returns: True if successful, false if no permission or error
    @discardableResult
    func simulatePaste() -> Bool {
        guard hasAccessibilityPermission else {
            return false
        }

        // Small delay to ensure clipboard is ready
        usleep(50000) // 50ms

        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyCodeV: CGKeyCode = 9

        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand

        // Create key up event with Command modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}
