import AppKit

/// Handles clipboard read/write operations using NSPasteboard
final class ClipboardManager {
    static let shared = ClipboardManager()

    private let pasteboard = NSPasteboard.general

    private init() {}

    /// Reads plain text from the clipboard
    /// - Returns: The clipboard text, or nil if empty or non-text
    func readText() -> String? {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Writes plain text to the clipboard
    /// - Parameter text: The text to write
    /// - Returns: True if successful
    @discardableResult
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Checks if the clipboard contains text
    var hasText: Bool {
        readText() != nil
    }
}
