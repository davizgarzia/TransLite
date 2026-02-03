import SwiftUI
import Combine

/// Main view model managing app state and translation logic
@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var apiKeyInput: String = ""
    @Published var hasAPIKey: Bool = false
    @Published var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled")
        }
    }
    @Published var statusMessage: String = ""
    @Published var isTranslating: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    // MARK: - Private Properties

    private let keychain = KeychainHelper.shared
    private let clipboard = ClipboardManager.shared
    private let openAI = OpenAIClient.shared
    private let accessibility = AccessibilityHelper.shared

    // MARK: - Initialization

    init() {
        // Load preferences
        self.autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")

        // Check if API key exists
        self.hasAPIKey = keychain.hasAPIKey

        // Check accessibility permission
        self.hasAccessibilityPermission = accessibility.hasAccessibilityPermission
    }

    // MARK: - API Key Management

    func saveAPIKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            statusMessage = "API key cannot be empty"
            return
        }

        guard trimmedKey.hasPrefix("sk-") else {
            statusMessage = "Invalid API key format"
            return
        }

        if keychain.saveAPIKey(trimmedKey) {
            hasAPIKey = true
            apiKeyInput = ""
            statusMessage = "API key saved securely"
        } else {
            statusMessage = "Failed to save API key"
        }
    }

    func deleteAPIKey() {
        keychain.deleteAPIKey()
        hasAPIKey = false
        statusMessage = "API key removed"
    }

    // MARK: - Translation

    func translateClipboard() {
        guard !isTranslating else {
            statusMessage = "Translation in progress..."
            return
        }

        guard hasAPIKey, let apiKey = keychain.getAPIKey() else {
            statusMessage = "No API key configured"
            return
        }

        guard let text = clipboard.readText() else {
            statusMessage = "Clipboard empty or non-text"
            return
        }

        isTranslating = true
        statusMessage = "Translating..."

        Task {
            do {
                let translated = try await openAI.translate(text: text, apiKey: apiKey)

                // Write to clipboard
                if clipboard.writeText(translated) {
                    statusMessage = "Translated successfully"

                    // Auto-paste if enabled and has permission
                    if autoPasteEnabled {
                        // Refresh permission status
                        hasAccessibilityPermission = accessibility.hasAccessibilityPermission

                        if hasAccessibilityPermission {
                            // Small delay to ensure clipboard is set
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            if accessibility.simulatePaste() {
                                statusMessage = "Translated & pasted"
                            } else {
                                statusMessage = "Translated (paste failed)"
                            }
                        } else {
                            statusMessage = "Translated (no paste permission)"
                        }
                    }
                } else {
                    statusMessage = "Failed to write clipboard"
                }

            } catch {
                statusMessage = error.localizedDescription
            }

            isTranslating = false
        }
    }

    // MARK: - Accessibility

    func refreshAccessibilityStatus() {
        hasAccessibilityPermission = accessibility.hasAccessibilityPermission
    }

    func requestAccessibilityPermission() {
        accessibility.requestAccessibilityPermission()
        // Refresh after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAccessibilityStatus()
        }
    }

    func openAccessibilitySettings() {
        accessibility.openAccessibilitySettings()
    }
}
