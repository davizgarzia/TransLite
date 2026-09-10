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

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain"
        case .claude: return "ClaudeIcon"
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
    @Published var statusMessage: String = ""
    @Published var isTranslating: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    // Trial & License
    @Published var trialStatus: TrialManager.TrialStatus = .expired
    @Published var licenseKeyInput: String = ""
    @Published var isActivatingLicense: Bool = false

    // Onboarding (free-first: no API key step — BYOK setup lives in
    // settings and only appears once the user has a license)
    enum OnboardingStep {
        case welcome
        case permissions
        case complete
    }
    @Published var onboardingStep: OnboardingStep = .welcome

    // MARK: - Backend Resolution

    /// How a translation/improvement request is fulfilled: with the user's
    /// own key (BYOK, direct to the provider) or through our proxy Worker
    /// on the free tier.
    enum TranslationBackend {
        case byok(provider: APIProvider, apiKey: String)
        case freeTier
    }

    /// Free tier applies when the user has no API key configured at all.
    /// If a key exists for another provider, we keep the explicit
    /// "no key for selected provider" error instead of silently proxying.
    var usesFreeTier: Bool {
        !hasAPIKey && !hasClaudeAPIKey
    }

    /// Whether the BYOK settings (provider picker, API keys) should be
    /// offered at all: requires a license or a still-active grandfathered
    /// trial. Free users never see key configuration.
    var canConfigureBYOK: Bool {
        if case .expired = trialStatus { return false }
        return true
    }

    // MARK: - Private Properties

    private let trialManager = TrialManager.shared
    private let keychain = KeychainHelper.shared
    private let clipboard = ClipboardManager.shared
    private let openAI = OpenAIClient.shared
    private let claude = ClaudeClient.shared
    private let proxy = ProxyClient.shared
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
        } else {
            // No key is a valid state: it means free tier
            self.hasAPIKey = keychain.hasAPIKey
            self.hasClaudeAPIKey = keychain.hasClaudeAPIKey
            self.onboardingStep = onboardingComplete ? .complete : .permissions
        }

        // Keep free-tier limits in sync with the server (fire and forget)
        Task {
            await ProxyClient.shared.refreshLimits()
        }
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
            statusMessage = ""
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
        } else {
            statusMessage = "Failed to save API key"
        }
    }

    // MARK: - Onboarding

    func continueFromWelcome() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        onboardingStep = .permissions
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

        // Switch to Claude if it was the active provider;
        // with no keys left the app falls back to the free tier
        if hasClaudeAPIKey, apiProvider == .openai {
            apiProvider = .claude
        }
    }

    func testOpenAIKey() {
        guard let key = keychain.getAPIKey() else { return }
        Task {
            statusMessage = "Testing OpenAI..."
            do {
                _ = try await openAI.translate(text: "Hi", apiKey: key, targetLanguage: "Spanish", tone: "Preserve the original tone")
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

        // Switch to OpenAI if it was the active provider;
        // with no keys left the app falls back to the free tier
        if hasAPIKey, apiProvider == .claude {
            apiProvider = .openai
        }
    }

    // MARK: - Translation

    /// Resolves how the next request should be fulfilled, setting
    /// statusMessage and returning nil when the action can't proceed.
    private func resolveBackend() -> TranslationBackend? {
        refreshTrialStatus()

        if usesFreeTier {
            return .freeTier
        }

        // BYOK requires a license (or a grandfathered trial still running)
        guard trialManager.canUseApp else {
            statusMessage = "License required to use your own API key"
            return nil
        }

        switch apiProvider {
        case .openai:
            guard hasAPIKey, let key = keychain.getAPIKey() else {
                statusMessage = "No OpenAI API key configured"
                return nil
            }
            return .byok(provider: .openai, apiKey: key)
        case .claude:
            guard hasClaudeAPIKey, let key = keychain.getClaudeAPIKey() else {
                statusMessage = "No Claude API key configured"
                return nil
            }
            return .byok(provider: .claude, apiKey: key)
        }
    }

    private static func analyticsProvider(for backend: TranslationBackend) -> String {
        switch backend {
        case .byok(let provider, _): return provider.rawValue
        case .freeTier: return "free_tier"
        }
    }

    /// Shows an error in the HUD long enough to be read before the caller
    /// hides it. Free-tier users may never open the popover, so the HUD is
    /// their only feedback channel.
    private func flashHUDError(_ message: String) async {
        hud.update(message: message)
        try? await Task.sleep(nanoseconds: 1_600_000_000)
    }

    func translateClipboard() {
        guard !isTranslating else {
            statusMessage = "Translation in progress..."
            return
        }

        guard let backend = resolveBackend() else { return }
        let providerLabel = Self.analyticsProvider(for: backend)

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
                    "provider": .string(providerLabel),
                    "reason": .string("no_selected_text")
                ])
                hud.hide()
                isTranslating = false
                return
            }

            // Free tier: reject over-limit text before spending a request
            if case .freeTier = backend, text.count > proxy.freeLimits.maxChars {
                statusMessage = "Text too long (max \(proxy.freeLimits.maxChars) characters)"
                AnalyticsClient.track("translation_failed", properties: [
                    "provider": .string(providerLabel),
                    "reason": .string("text_too_long")
                ])
                await flashHUDError(statusMessage)
                hud.hide()
                isTranslating = false
                return
            }

            // Free tier: only the allowed target languages (English)
            if case .freeTier = backend,
               let allowedTargets = proxy.freeLimits.allowedTargets,
               !allowedTargets.contains(targetLanguage.rawValue) {
                statusMessage = "Free plan translates to \(allowedTargets.joined(separator: ", ")) only"
                AnalyticsClient.track("translation_failed", properties: [
                    "provider": .string(providerLabel),
                    "reason": .string("language_not_allowed")
                ])
                await flashHUDError(statusMessage)
                hud.hide()
                isTranslating = false
                return
            }

            statusMessage = "Translating..."
            hud.update(message: "Translating...")
            let startedAt = Date()
            let baseProperties: [String: AnalyticsValue] = [
                "provider": .string(providerLabel),
                "target_language": .string(targetLanguage.rawValue),
                "tone": .string(translationTone.rawValue),
                "auto_paste": .boolean(autoPasteEnabled)
            ]
            AnalyticsClient.track("translation_started", properties: baseProperties)

            do {
                let translated: String
                switch backend {
                case .byok(.openai, let apiKey):
                    translated = try await openAI.translate(
                        text: text,
                        apiKey: apiKey,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone.promptInstruction
                    )
                case .byok(.claude, let apiKey):
                    translated = try await claude.translate(
                        text: text,
                        apiKey: apiKey,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone.promptInstruction
                    )
                case .freeTier:
                    translated = try await proxy.translate(
                        text: text,
                        targetLanguage: targetLanguage.rawValue,
                        tone: translationTone
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

                    if case .freeTier = backend, let remaining = proxy.quotaRemaining {
                        statusMessage += " · \(remaining) left today"
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
                if error is ProxyError {
                    await flashHUDError(statusMessage)
                }
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

        guard let backend = resolveBackend() else { return }
        let providerLabel = Self.analyticsProvider(for: backend)

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
                    "provider": .string(providerLabel),
                    "reason": .string("no_selected_text")
                ])
                hud.hide()
                isTranslating = false
                return
            }

            // Free tier: reject over-limit text before spending a request
            if case .freeTier = backend, text.count > proxy.freeLimits.maxChars {
                statusMessage = "Text too long (max \(proxy.freeLimits.maxChars) characters)"
                AnalyticsClient.track("improvement_failed", properties: [
                    "provider": .string(providerLabel),
                    "reason": .string("text_too_long")
                ])
                await flashHUDError(statusMessage)
                hud.hide()
                isTranslating = false
                return
            }

            statusMessage = "Improving..."
            hud.update(message: "Improving...")
            let startedAt = Date()
            let baseProperties: [String: AnalyticsValue] = [
                "provider": .string(providerLabel),
                "auto_paste": .boolean(autoPasteEnabled)
            ]
            AnalyticsClient.track("improvement_started", properties: baseProperties)

            do {
                let improved: String
                switch backend {
                case .byok(.openai, let apiKey):
                    improved = try await openAI.improve(
                        text: text,
                        apiKey: apiKey
                    )
                case .byok(.claude, let apiKey):
                    improved = try await claude.improve(
                        text: text,
                        apiKey: apiKey
                    )
                case .freeTier:
                    improved = try await proxy.improve(text: text)
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

                    if case .freeTier = backend, let remaining = proxy.quotaRemaining {
                        statusMessage += " · \(remaining) left today"
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
                if error is ProxyError {
                    await flashHUDError(statusMessage)
                }
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

        if let error = error as? ProxyError {
            switch error {
            case .invalidResponse: return "invalid_response"
            case .textTooLong: return "text_too_long"
            case .quotaExceeded: return "quota_exceeded"
            case .languageNotAllowed: return "language_not_allowed"
            case .busy: return "rate_limited"
            case .apiError: return "provider_error"
            case .serverError: return "server_error"
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
