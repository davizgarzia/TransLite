import AppKit
import ApplicationServices

/// Represents selected text and its screen position
struct SelectedTextInfo {
    let text: String
    let position: CGPoint
}

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

    /// Gets the currently selected text and its screen position
    /// - Returns: SelectedTextInfo if text is selected, nil otherwise
    func getSelectedText() -> SelectedTextInfo? {
        guard hasAccessibilityPermission else {
            return nil
        }

        // Get the focused application
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        
        let appResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        
        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        // Get the focused element in that application
        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard elementResult == .success, let element = focusedElement else {
            return nil
        }

        // Try to get selected text
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        
        guard textResult == .success,
              let text = selectedText as? String,
              !text.isEmpty else {
            return nil
        }

        // Try to get the position of the selected text
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        
        var position = CGPoint.zero
        
        if rangeResult == .success,
           let range = selectedRange,
           CFGetTypeID(range) == AXValueGetTypeID() {
            var cfRange = CFRange()
            AXValueGetValue(range as! AXValue, .cfRange, &cfRange)
            
            // Try to get bounds for the selected text range
            var boundsValue: AnyObject?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                element as! AXUIElement,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range as! AXValue,
                &boundsValue
            )
            
            if boundsResult == .success,
               let bounds = boundsValue,
               CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
                position = CGPoint(x: rect.midX, y: rect.minY)
            }
        }
        
        // Fallback: use cursor position if we couldn't get text position
        if position == .zero {
            position = NSEvent.mouseLocation
        }

        return SelectedTextInfo(text: text, position: position)
    }

    /// Simulates backspace/delete key presses to delete characters
    /// - Parameter count: Number of characters to delete
    func simulateDelete(count: Int) {
        guard hasAccessibilityPermission, count > 0 else {
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeDelete: CGKeyCode = 51 // Backspace key

        for _ in 0..<count {
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeDelete, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeDelete, keyDown: false) {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                usleep(8000) // 8ms between deletions for visual effect
            }
        }
    }

    /// Types text character by character with a typing effect
    /// - Parameters:
    ///   - text: Text to type
    ///   - delayPerChar: Microseconds delay between characters (default 15ms)
    ///   - progressCallback: Called with progress (0.0 to 1.0) after each character
    func simulateTyping(
        text: String,
        delayPerChar: UInt32 = 15000,
        progressCallback: ((Double) -> Void)? = nil
    ) {
        guard hasAccessibilityPermission, !text.isEmpty else {
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let characters = Array(text)
        let totalChars = Double(characters.count)

        for (index, char) in characters.enumerated() {
            let string = String(char)
            
            // Create a key event for typing the character
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                
                // Set the Unicode string for the character
                let unicodeString = string.utf16
                keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: Array(unicodeString))
                keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: Array(unicodeString))
                
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                
                // Report progress
                let progress = Double(index + 1) / totalChars
                progressCallback?(progress)
                
                usleep(delayPerChar)
            }
        }
    }
}
