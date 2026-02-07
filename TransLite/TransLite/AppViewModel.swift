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
    case chinese = "Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case arabic = "Arabic"
    case russian = "Russian"

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
        } else if onboardingComplete {
            // Only access keychain if onboarding is complete
            self.hasAPIKey = keychain.hasAPIKey
            self.onboardingStep = hasAPIKey ? .complete : .apiKey
        } else {
            // Onboarding in progress - check keychain to determine step
            self.hasAPIKey = keychain.hasAPIKey
            if !hasAPIKey {
                self.onboardingStep = .apiKey
            } else {
                self.onboardingStep = .permissions
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

        guard trimmedKey.hasPrefix("sk-") else {
            statusMessage = "Invalid API key format"
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
        statusMessage = "API key removed"

        // Reset onboarding
        UserDefaults.standard.set(false, forKey: "onboardingComplete")
        onboardingStep = .apiKey
    }

    // MARK: - Translation

    func translateClipboard() {
        guard !isTranslating else {
            statusMessage = "Translation in progress..."
            return
        }

        // Check trial/license status
        guard trialManager.canUseApp else {
            statusMessage = "Trial expired - please activate license"
            return
        }

        guard hasAPIKey, let apiKey = keychain.getAPIKey() else {
            statusMessage = "No API key configured"
            return
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
                hud.hide()
                isTranslating = false
                return
            }

            statusMessage = "Translating..."
            hud.update(message: "Translating...")

            do {
                let translated = try await openAI.translate(
                    text: text,
                    apiKey: apiKey,
                    targetLanguage: targetLanguage.rawValue,
                    tone: translationTone.promptInstruction
                )

                // Write to clipboard
                if clipboard.writeText(translated) {
                    statusMessage = "Translated successfully"

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

            hud.hide()
            isTranslating = false
        }
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
        if let url = URL(string: "https://translite.lemonsqueezy.com/checkout/buy/e4acbf88-40ff-47a9-a07c-e82dda0a4015") {
            NSWorkspace.shared.open(url)
        }
    }
}
