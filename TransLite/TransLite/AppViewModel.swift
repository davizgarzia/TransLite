import SwiftUI
import Combine

// MARK: - Language Model

enum TargetLanguage: String, CaseIterable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case italian = "Italian"
    case portuguese = "Portuguese"
    case dutch = "Dutch"
    case polish = "Polish"
    case turkish = "Turkish"
    case russian = "Russian"
    case arabic = "Arabic"
    case hindi = "Hindi"
    case chinese = "Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case vietnamese = "Vietnamese"
    case thai = "Thai"
    case indonesian = "Indonesian"

    var displayName: String { rawValue }
}

enum TranslationTone: String, CaseIterable {
    case original = "original"
    case formal = "formal"
    case casual = "casual"
    case concise = "concise"

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .concise: return "Concise"
        }
    }

    var icon: String {
        switch self {
        case .original: return "text.alignleft"
        case .formal: return "briefcase.fill"
        case .casual: return "bubble.left.fill"
        case .concise: return "scissors"
        }
    }

    var promptInstruction: String {
        switch self {
        case .original: return "Preserve the original tone"
        case .formal: return "Use a formal, professional tone"
        case .casual: return "Use a casual, relaxed tone"
        case .concise: return "Be direct and brief, remove unnecessary words"
        }
    }
}

enum APIProvider: String, CaseIterable {
    case openai = "openai"
    case claude = "claude"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain"
        case .claude: return "ClaudeIcon"
        case .custom: return "server.rack"
        }
    }
}

/// Main view model managing app state and translation logic
@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var apiKeyInput: String = ""
    @Published var claudeApiKeyInput: String = ""
    @Published var hasAPIKey: Bool = false
    @Published var hasClaudeAPIKey: Bool = false
    @Published var apiProvider: APIProvider {
        didSet {
            UserDefaults.standard.set(apiProvider.rawValue, forKey: "apiProvider")
        }
    }
    @Published var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled")
        }
    }
    @Published var targetLanguage: TargetLanguage {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: "targetLanguage")
        }
    }
    @Published var translationTone: TranslationTone {
        didSet {
            UserDefaults.standard.set(translationTone.rawValue, forKey: "translationTone")
        }
    }
    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
            AppDelegate.shared?.hotkeyManager?.updateHotkey(keyCode: hotkeyKeyCode)
        }
    }
    @Published var openAIBaseURL: String = "" {
        didSet {
            UserDefaults.standard.set(openAIBaseURL, forKey: "openAIBaseURL")
        }
    }
    @Published var openAIModel: String = "" {
        didSet {
            UserDefaults.standard.set(openAIModel, forKey: "openAIModel")
        }
    }
    @Published var statusMessage: String = ""
    @Published var isTranslating: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    // Trial & License
    @Published var trialStatus: TrialManager.TrialStatus = .expired
    @Published var licenseKeyInput: String = ""
    @Published var isActivatingLicense: Bool = false

    // Onboarding
    enum OnboardingStep {
        case welcome
        case apiKey
        case permissions
        case complete
    }
    @Published var onboardingStep: OnboardingStep = .welcome

    // MARK: - Private Properties

    private let trialManager = TrialManager.shared
    private let keychain = KeychainHelper.shared
    private let clipboard = ClipboardManager.shared
    private let openAI = OpenAIClient.shared
    private let claude = ClaudeClient.shared
    private let accessibility = AccessibilityHelper.shared
    private let hud = TranslationHUD.shared
    private var permissionPollingTimer: Timer?

    // MARK: - Initialization

    init() {
        // Load preferences - auto-paste enabled by default
        if UserDefaults.standard.object(forKey: "autoPasteEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "autoPasteEnabled")
        }
        self.autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")

        // Load target language
        if let savedLanguage = UserDefaults.standard.string(forKey: "targetLanguage"),
           let language = TargetLanguage(rawValue: savedLanguage) {
            self.targetLanguage = language
        } else {
            self.targetLanguage = .english
        }

        // Load translation tone
        if let savedTone = UserDefaults.standard.string(forKey: "translationTone"),
           let tone = TranslationTone(rawValue: savedTone) {
            self.translationTone = tone
        } else {
            self.translationTone = .original
        }

        // Load API provider
        if let savedProvider = UserDefaults.standard.string(forKey: "apiProvider"),
           let provider = APIProvider(rawValue: savedProvider) {
            self.apiProvider = provider
        } else {
            self.apiProvider = .openai
        }

        // Load OpenAI endpoint settings
        self.openAIBaseURL = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? ""
        self.openAIModel = UserDefaults.standard.string(forKey: "openAIModel") ?? ""

        // Load hotkey key code
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        self.hotkeyKeyCode = savedKeyCode > 0 ? UInt32(savedKeyCode) : HotkeyManager.defaultKeyCode

        // Check accessibility permission
        self.hasAccessibilityPermission = accessibility.hasAccessibilityPermission

        // Record usage and get trial status
        trialManager.recordUsage()
        self.trialStatus = trialManager.status

        // Set onboarding step - determine WITHOUT accessing Keychain yet
        // to avoid triggering the Keychain permission dialog before UI is ready
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")

        if !hasSeenWelcome {
            self.onboardingStep = .welcome
            self.hasAPIKey = false // Don't check keychain yet
            self.hasClaudeAPIKey = false
        } else if onboardingComplete {
            // Only access keychain if onboarding is complete
            self.hasAPIKey = keychain.hasAPIKey
            self.hasClaudeAPIKey = keychain.hasClaudeAPIKey
            let hasAnyKey = hasAPIKey || hasClaudeAPIKey
            self.onboardingStep = hasAnyKey ? .complete : .apiKey
        } else {
            // Onboarding in progress - check keychain to determine step
            self.hasAPIKey = keychain.hasAPIKey
            self.hasClaudeAPIKey = keychain.hasClaudeAPIKey
            let hasAnyKey = hasAPIKey || hasClaudeAPIKey
            if !hasAnyKey {
                self.onboardingStep = .apiKey
            } else {
                self.onboardingStep = .permissions
            }
        }
    }

    // MARK: - Custom Endpoint Helpers

    var effectiveOpenAIBaseURL: String {
        let trimmed = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? OpenAIClient.defaultBaseURL : trimmed
    }

    var effectiveOpenAIModel: String {
        let trimmed = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? OpenAIClient.defaultModel : trimmed
    }

    var hasCustomEndpoint: Bool {
        !openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveCustomEndpoint(url: String, apiKey: String, model: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            statusMessage = "Base URL cannot be empty"
            return
        }
        openAIBaseURL = trimmedURL
        openAIModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            keychain.saveCustomAPIKey(trimmedKey)
        } else {
            keychain.deleteCustomAPIKey()
        }
        apiProvider = .custom
        statusMessage = ""
        if onboardingStep == .apiKey {
            onboardingStep = .permissions
        }
    }

    func deleteCustomEndpoint() {
        openAIBaseURL = ""
        openAIModel = ""
        keychain.deleteCustomAPIKey()
        statusMessage = "Custom endpoint removed"
        if apiProvider == .custom {
            if hasAPIKey {
                apiProvider = .openai
            } else if hasClaudeAPIKey {
                apiProvider = .claude
            } else {
                UserDefaults.standard.set(false, forKey: "onboardingComplete")
                onboardingStep = .apiKey
            }
        }
    }

    func testCustomEndpoint() {
        guard hasCustomEndpoint else { return }
        let key = keychain.getCustomAPIKey() ?? ""
        Task {
            statusMessage = "Testing custom endpoint..."
            do {
                _ = try await openAI.translate(text: "Hi", apiKey: key, targetLanguage: "Spanish", tone: "Preserve the original tone", baseURL: effectiveOpenAIBaseURL, model: effectiveOpenAIModel)
                statusMessage = "Custom endpoint working ✓"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    // MARK: - API Key Management

    func saveAPIKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            statusMessage = "API key cannot be empty"
            return
        }


        if keychain.saveAPIKey(trimmedKey) {
            hasAPIKey = true
            apiKeyInput = ""
            statusMessage = ""

            // Go to permissions step
            onboardingStep = .permissions
        } else {
            statusMessage = "Failed to save API key"
        }
    }

    func saveClaudeAPIKey() {
        let trimmedKey = claudeApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            statusMessage = "API key cannot be empty"
            return
        }

        guard trimmedKey.hasPrefix("sk-ant-") else {
            statusMessage = "Invalid Claude API key format"
            return
        }

        if keychain.saveClaudeAPIKey(trimmedKey) {
            hasClaudeAPIKey = true
            claudeApiKeyInput = ""
            statusMessage = ""

            // Go to permissions step if this is the first key
            if onboardingStep == .apiKey {
                onboardingStep = .permissions
            }
        } else {
            statusMessage = "Failed to save API key"
        }
    }

    // MARK: - Onboarding

    func continueFromWelcome() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        onboardingStep = .apiKey
    }

    func enableAutoPasteWithPermissions() {
        autoPasteEnabled = true
        accessibility.requestAccessibilityPermission()
        startPermissionPolling()

        // Complete onboarding after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.completeOnboarding()
        }
    }

    func skipAutoPaste() {
        autoPasteEnabled = false
        completeOnboarding()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        onboardingStep = .complete
    }

    func deleteAPIKey() {
        keychain.deleteAPIKey()
        hasAPIKey = false
        statusMessage = "OpenAI API key removed"

        if hasClaudeAPIKey {
            // Switch to Claude if it was the active provider
            if apiProvider == .openai {
                apiProvider = .claude
            }
        } else {
            // No keys left - reset onboarding
            UserDefaults.standard.set(false, forKey: "onboardingComplete")
            onboardingStep = .apiKey
        }
    }

    func testOpenAIKey() {
        guard let key = keychain.getAPIKey() else { return }
        Task {
            statusMessage = "Testing OpenAI..."
            do {
                _ = try await openAI.translate(text: "Hi", apiKey: key, targetLanguage: "Spanish", tone: "Preserve the original tone", baseURL: effectiveOpenAIBaseURL, model: effectiveOpenAIModel)
                statusMessage = "OpenAI key working ✓"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func testClaudeKey() {
        guard let key = keychain.getClaudeAPIKey() else { return }
        Task {
            statusMessage = "Testing Claude..."
            do {
                _ = try await claude.translate(text: "Hi", apiKey: key, targetLanguage: "Spanish", tone: "Preserve the original tone")
                statusMessage = "Claude key working ✓"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func deleteClaudeAPIKey() {
        keychain.deleteClaudeAPIKey()
        hasClaudeAPIKey = false
        statusMessage = "Claude API key removed"

        if hasAPIKey {
            // Switch to OpenAI if it was the active provider
            if apiProvider == .claude {
                apiProvider = .openai
            }
        } else {
            // No keys left - reset onboarding
            UserDefaults.standard.set(false, forKey: "onboardingComplete")
            onboardingStep = .apiKey
        }
    }

    // MARK: - Translation

    func translateClipboard() {
        guard !isTranslating else {
            statusMessage = "Translation in progress..."
            return
        }

        // Check trial/license status and sync UI
        refreshTrialStatus()
        guard trialManager.canUseApp else {
            statusMessage = "Trial expired - please activate license"
            return
        }

        // Get API key based on selected provider
        let selectedProvider = apiProvider
        let apiKey: String
        switch selectedProvider {
        case .openai:
            guard hasAPIKey, let key = keychain.getAPIKey() else {
                statusMessage = "No OpenAI API key configured"
                return
            }
            apiKey = key
        case .claude:
            guard hasClaudeAPIKey, let key = keychain.getClaudeAPIKey() else {
                statusMessage = "No Claude API key configured"
                return
            }
            apiKey = key
        case .custom:
            guard hasCustomEndpoint else {
                statusMessage = "No custom endpoint configured"
                return
            }
            apiKey = keychain.getCustomAPIKey() ?? ""
        }

        isTranslating = true
        hud.show(message: "Copying...")

        // Auto-copy selected text if we have accessibility permission
        if accessibility.hasAccessibilityPermission {
            accessibility.simulateCopy()
        }

        Task {
            // Delay to allow clipboard to update after copy
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

            guard let text = clipboard.readText() else {
                statusMessage = "No text selected"
                AnalyticsClient.track("translation_failed", properties: [
                    "provider": .string(selectedProvider.rawValue),
                    "reason": .string("no_selected_text")
                ])
                hud.hide()
                isTranslating = false
                return
            }

            statusMessage = "Translating..."
            hud.update(message: "Translating...")
            let startedAt = Date()
            let baseProperties: [String: AnalyticsValue] = [
                "provider": .string(selectedProvider.rawValue),
                "target_language": .string(targetLanguage.rawValue),
                "tone": .string(translationTone.rawValue),
                "auto_paste": .boolean(autoPasteEnabled)
            ]
            AnalyticsClient.track("translation_started", properties: baseProperties)

            do {
                let translated: String
                switch selectedProvider {
                case .openai:
                    translated = try await openAI.translate(
                        text: text,
                        apiKey: apiKey,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone.promptInstruction,
                        baseURL: effectiveOpenAIBaseURL,
                        model: effectiveOpenAIModel
                    )
                case .claude:
                    translated = try await claude.translate(
                        text: text,
                        apiKey: apiKey,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone.promptInstruction
                    )
                case .custom:
                    translated = try await openAI.translate(
                        text: text,
                        apiKey: apiKey,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone.promptInstruction,
                        baseURL: effectiveOpenAIBaseURL,
                        model: effectiveOpenAIModel
                    )
                }

                // Write to clipboard
                if clipboard.writeText(translated) {
                    statusMessage = "Translated successfully"
                    var delivery = "clipboard"

                    // Auto-paste if enabled and has permission
                    if autoPasteEnabled {
                        // Refresh permission status
                        hasAccessibilityPermission = accessibility.hasAccessibilityPermission

                        if hasAccessibilityPermission {
                            hud.update(message: "Pasting...")
                            // Small delay to ensure clipboard is set
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            if accessibility.simulatePaste() {
                                statusMessage = "Translated & pasted"
                                delivery = "auto_paste"
                            } else {
                                statusMessage = "Translated (paste failed)"
                                delivery = "paste_failed"
                            }
                        } else {
                            statusMessage = "Translated (no paste permission)"
                            delivery = "no_accessibility_permission"
                        }
                    }

                    var completedProperties = baseProperties
                    completedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                    completedProperties["delivery"] = .string(delivery)
                    AnalyticsClient.track("translation_completed", properties: completedProperties)
                } else {
                    statusMessage = "Failed to write clipboard"
                    var failedProperties = baseProperties
                    failedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                    failedProperties["reason"] = .string("clipboard_write_failed")
                    AnalyticsClient.track("translation_failed", properties: failedProperties)
                }

            } catch {
                statusMessage = error.localizedDescription
                var failedProperties = baseProperties
                failedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                failedProperties["reason"] = .string(Self.analyticsErrorCategory(error))
                AnalyticsClient.track("translation_failed", properties: failedProperties)
            }

            hud.hide()
            isTranslating = false
        }
    }

    func improveText() {
        guard !isTranslating else {
            statusMessage = "Operation in progress..."
            return
        }

        // Check trial/license status and sync UI
        refreshTrialStatus()
        guard trialManager.canUseApp else {
            statusMessage = "Trial expired - please activate license"
            return
        }

        // Get API key based on selected provider
        let selectedProvider = apiProvider
        let apiKey: String
        switch selectedProvider {
        case .openai:
            guard hasAPIKey, let key = keychain.getAPIKey() else {
                statusMessage = "No OpenAI API key configured"
                return
            }
            apiKey = key
        case .claude:
            guard hasClaudeAPIKey, let key = keychain.getClaudeAPIKey() else {
                statusMessage = "No Claude API key configured"
                return
            }
            apiKey = key
        case .custom:
            guard hasCustomEndpoint else {
                statusMessage = "No custom endpoint configured"
                return
            }
            apiKey = keychain.getCustomAPIKey() ?? ""
        }

        isTranslating = true
        hud.show(message: "Copying...")

        // Auto-copy selected text if we have accessibility permission
        if accessibility.hasAccessibilityPermission {
            accessibility.simulateCopy()
        }

        Task {
            // Delay to allow clipboard to update after copy
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

            guard let text = clipboard.readText() else {
                statusMessage = "No text selected"
                AnalyticsClient.track("improvement_failed", properties: [
                    "provider": .string(selectedProvider.rawValue),
                    "reason": .string("no_selected_text")
                ])
                hud.hide()
                isTranslating = false
                return
            }

            statusMessage = "Improving..."
            hud.update(message: "Improving...")
            let startedAt = Date()
            let baseProperties: [String: AnalyticsValue] = [
                "provider": .string(selectedProvider.rawValue),
                "auto_paste": .boolean(autoPasteEnabled)
            ]
            AnalyticsClient.track("improvement_started", properties: baseProperties)

            do {
                let improved: String
                switch selectedProvider {
                case .openai:
                    improved = try await openAI.improve(
                        text: text,
                        apiKey: apiKey,
                        baseURL: effectiveOpenAIBaseURL,
                        model: effectiveOpenAIModel
                    )
                case .claude:
                    improved = try await claude.improve(
                        text: text,
                        apiKey: apiKey
                    )
                case .custom:
                    improved = try await openAI.improve(
                        text: text,
                        apiKey: apiKey,
                        baseURL: effectiveOpenAIBaseURL,
                        model: effectiveOpenAIModel
                    )
                }

                // Write to clipboard
                if clipboard.writeText(improved) {
                    statusMessage = "Improved successfully"
                    var delivery = "clipboard"

                    // Auto-paste if enabled and has permission
                    if autoPasteEnabled {
                        // Refresh permission status
                        hasAccessibilityPermission = accessibility.hasAccessibilityPermission

                        if hasAccessibilityPermission {
                            hud.update(message: "Pasting...")
                            // Small delay to ensure clipboard is set
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            if accessibility.simulatePaste() {
                                statusMessage = "Improved & pasted"
                                delivery = "auto_paste"
                            } else {
                                statusMessage = "Improved (paste failed)"
                                delivery = "paste_failed"
                            }
                        } else {
                            statusMessage = "Improved (no paste permission)"
                            delivery = "no_accessibility_permission"
                        }
                    }

                    var completedProperties = baseProperties
                    completedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                    completedProperties["delivery"] = .string(delivery)
                    AnalyticsClient.track("improvement_completed", properties: completedProperties)
                } else {
                    statusMessage = "Failed to write clipboard"
                    var failedProperties = baseProperties
                    failedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                    failedProperties["reason"] = .string("clipboard_write_failed")
                    AnalyticsClient.track("improvement_failed", properties: failedProperties)
                }

            } catch {
                statusMessage = error.localizedDescription
                var failedProperties = baseProperties
                failedProperties["duration_ms"] = .integer(Self.durationMilliseconds(since: startedAt))
                failedProperties["reason"] = .string(Self.analyticsErrorCategory(error))
                AnalyticsClient.track("improvement_failed", properties: failedProperties)
            }

            hud.hide()
            isTranslating = false
        }
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    private static func analyticsErrorCategory(_ error: Error) -> String {
        if error is URLError {
            return "network_error"
        }

        if let error = error as? OpenAIError {
            switch error {
            case .invalidResponse: return "invalid_response"
            case .emptyResponse: return "empty_response"
            case .invalidAPIKey: return "invalid_api_key"
            case .rateLimited: return "rate_limited"
            case .serverError: return "server_error"
            case .apiError: return "provider_error"
            case .unknownError: return "http_error"
            }
        }

        if let error = error as? ClaudeError {
            switch error {
            case .invalidResponse: return "invalid_response"
            case .emptyResponse: return "empty_response"
            case .invalidAPIKey: return "invalid_api_key"
            case .rateLimited: return "rate_limited"
            case .serverError: return "server_error"
            case .apiError: return "provider_error"
            case .unknownError: return "http_error"
            }
        }

        return "unknown_error"
    }

    // MARK: - Accessibility

    func refreshAccessibilityStatus() {
        let newStatus = accessibility.hasAccessibilityPermission
        hasAccessibilityPermission = newStatus

        // If we now have permission, stop polling
        if newStatus {
            stopPermissionPolling()
        }
    }

    /// Starts polling for permission changes every second
    /// Call this when the popover appears and permissions are needed
    func startPermissionPolling() {
        // Don't start if already have permission or already polling
        guard !hasAccessibilityPermission, permissionPollingTimer == nil else { return }

        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
    }

    /// Stops the permission polling timer
    func stopPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }

    func requestAccessibilityPermission() {
        accessibility.requestAccessibilityPermission()
        // Start polling after requesting
        startPermissionPolling()
    }

    func openAccessibilitySettings() {
        accessibility.openAccessibilitySettings()
        // Start polling after opening settings
        startPermissionPolling()
    }

    // MARK: - Hotkey

    var hotkeyDisplayString: String {
        let char = HotkeyManager.character(for: hotkeyKeyCode) ?? "T"
        return "⌘⇧\(char)"
    }

    func updateHotkeyKey(_ character: Character) {
        guard let keyCode = HotkeyManager.keyCode(for: character) else { return }
        hotkeyKeyCode = keyCode
    }

    // MARK: - Trial & License

    func refreshTrialStatus() {
        trialStatus = trialManager.status
    }

    func activateLicense() {
        let trimmedKey = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            statusMessage = "Please enter a license key"
            return
        }

        isActivatingLicense = true
        statusMessage = "Activating license..."

        Task {
            let success = await trialManager.activateLicense(trimmedKey)

            if success {
                trialStatus = trialManager.status
                licenseKeyInput = ""
                statusMessage = "License activated!"
            } else {
                statusMessage = "Invalid license key"
            }

            isActivatingLicense = false
        }
    }

    func openPurchasePage() {
        if let url = URL(string: "https://translite.lemonsqueezy.com/checkout/buy/02a955f2-5f2b-4bb0-a70d-21b3acb3ef2f") {
            NSWorkspace.shared.open(url)
        }
    }
}
