import SwiftUI
import ServiceManagement
import Sparkle

/// Main SwiftUI view for the menubar popover
struct PopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingAPIKeyHelp = false
    @State private var onboardingProvider: APIProvider = .openai
    @State private var addingKeyFor: APIProvider? = nil
    @State private var showingApiKeySteps = false
    @State private var showingApiKeysSection = false
    @State private var showingShortcutConfig = false
    @State private var hotkeyLetter: String = "T"

    private let cardPadding: CGFloat = 8
    private let cardCornerRadius: CGFloat = 12
    private let contentSpacing: CGFloat = 8

    private var trialExpired: Bool {
        if case .expired = viewModel.trialStatus { return true }
        return false
    }

    private var isLicensed: Bool {
        if case .licensed = viewModel.trialStatus { return true }
        return false
    }

    private var trialDaysRemaining: Int {
        if case .active(let days) = viewModel.trialStatus { return days }
        return 0
    }

    private var trialProgress: Double {
        let total = 7.0
        let used = total - Double(trialDaysRemaining)
        return used / total
    }

    @State private var showingLicenseInput = false
    @State private var customEndpointURLInput: String = ""
    @State private var customEndpointKeyInput: String = ""
    @State private var customEndpointModelInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch viewModel.onboardingStep {
            case .welcome:
                onboardingWelcomeCard

            case .apiKey:
                onboardingApiKeyCard

            case .permissions:
                onboardingPermissionsCard

            case .complete:
                if let provider = addingKeyFor {
                    addApiKeyCard(for: provider)
                } else if showingShortcutConfig {
                    shortcutConfigCard
                } else {
                    if !isLicensed {
                        trialSection
                    }

                    VStack(spacing: contentSpacing) {
                        translationCard
                        settingsCard
                        keysCard
                    }
                    .opacity(trialExpired ? 0.5 : 1.0)
                    .disabled(trialExpired)
                }
            }

            if !viewModel.statusMessage.isEmpty {
                statusSection
            }

            footerSection
        }
        .padding(14)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            viewModel.refreshAccessibilityStatus()
            viewModel.refreshTrialStatus()
            hotkeyLetter = String(HotkeyManager.character(for: viewModel.hotkeyKeyCode) ?? "T")
            if viewModel.autoPasteEnabled && !viewModel.hasAccessibilityPermission {
                viewModel.startPermissionPolling()
            }
        }
        .onDisappear {
            viewModel.stopPermissionPolling()
        }
        .onChange(of: viewModel.autoPasteEnabled) { newValue in
            if newValue && !viewModel.hasAccessibilityPermission {
                viewModel.startPermissionPolling()
            } else if !newValue {
                viewModel.stopPermissionPolling()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image("TransLiteIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 15)

            Text("TransLite")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                showingShortcutConfig = true
            } label: {
                HStack(spacing: 3) {
                    Text(viewModel.hotkeyDisplayString)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)

                    if !viewModel.autoPasteEnabled {
                        Text("+")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("⌘V")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(3)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Trial Section

    private var trialSection: some View {
        VStack(spacing: 0) {
            // Trial status section
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if trialExpired {
                            Text("Trial Expired")
                                .font(.system(size: 11, weight: .semibold))
                        } else {
                            Text("\(trialDaysRemaining) days left in trial")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.openPurchasePage()
                    } label: {
                        UpgradeButton(text: trialExpired ? "Buy License" : "Upgrade", isExpired: trialExpired)
                    }
                    .buttonStyle(.plain)
                }

                // Progress bar (always visible)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(trialExpired ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(trialExpired ? Color.red : Color.accentColor)
                            .frame(width: geometry.size.width * (trialExpired ? 1.0 : trialProgress), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(10)
            .background(trialExpired ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))

            // License section
            VStack(spacing: 0) {
                // License row
                HStack {
                    Label("License", systemImage: "key.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    if showingLicenseInput && !viewModel.licenseKeyInput.isEmpty {
                        Button("Save") {
                            viewModel.activateLicense()
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isActivatingLicense)
                    } else {
                        Button(showingLicenseInput ? "Cancel" : "Enter") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingLicenseInput.toggle()
                                if !showingLicenseInput {
                                    viewModel.licenseKeyInput = ""
                                }
                            }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)

                // Expandable license input
                if showingLicenseInput {
                    TextField("License key", text: $viewModel.licenseKeyInput)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .background(trialExpired ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
        }
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Translation Card (Language + Tone + Auto-paste)

    private var translationCard: some View {
        VStack(spacing: 0) {
            // Language row
            HStack {
                Label("Translate to", systemImage: "character.bubble")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $viewModel.targetLanguage) {
                    ForEach(TargetLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 8)

            Divider().padding(.leading, cardPadding)

            // Tone row
            VStack(alignment: .leading, spacing: 6) {
                Label("Tone", systemImage: "text.quote")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                toneSelector
            }
            .padding(cardPadding)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Shortcut row
            Button {
                showingShortcutConfig = true
            } label: {
                HStack {
                    Label("Shortcut", systemImage: "command")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.hotkeyDisplayString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, cardPadding)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, cardPadding)

            // Auto-paste row
            HStack {
                Label("Auto-paste", systemImage: "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $viewModel.autoPasteEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7, anchor: .trailing)
            }
            .padding(.horizontal, cardPadding)
            .frame(height: 36)

            if viewModel.autoPasteEnabled && !viewModel.hasAccessibilityPermission {
                Divider().padding(.leading, cardPadding)

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                    Text("Accessibility required")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Grant") {
                        viewModel.openAccessibilitySettings()
                    }
                    .font(.system(size: 9, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Tone Selector

    private var toneSelector: some View {
        HStack(spacing: 4) {
            ForEach(TranslationTone.allCases, id: \.self) { tone in
                toneButton(for: tone)
            }
        }
    }

    private func toneButton(for tone: TranslationTone) -> some View {
        let isSelected = viewModel.translationTone == tone

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.translationTone = tone
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tone.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 16)
                Text(tone.displayName)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Keys Card (Provider selector + API Keys)

    private var keysCard: some View {
        VStack(spacing: 0) {
            // Provider row
            HStack {
                Label("Provider", systemImage: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: Binding(
                    get: { viewModel.apiProvider },
                    set: { newProvider in
                        let isConfigured: Bool
                        switch newProvider {
                        case .openai: isConfigured = viewModel.hasAPIKey
                        case .claude: isConfigured = viewModel.hasClaudeAPIKey
                        case .custom: isConfigured = viewModel.hasCustomEndpoint
                        }
                        if isConfigured {
                            viewModel.apiProvider = newProvider
                        } else {
                            addingKeyFor = newProvider
                        }
                    }
                )) {
                    ForEach(APIProvider.allCases, id: \.self) { provider in
                        HStack {
                            Text(provider.displayName)
                            if (provider == .openai && !viewModel.hasAPIKey) ||
                               (provider == .claude && !viewModel.hasClaudeAPIKey) ||
                               (provider == .custom && !viewModel.hasCustomEndpoint) {
                                Text("(No key)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .padding(.horizontal, cardPadding)
            .frame(height: 36)

            Divider().padding(.leading, cardPadding)

            // API Keys row (collapsible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingApiKeysSection.toggle()
                }
            } label: {
                HStack {
                    Label("API Keys", systemImage: "key")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: showingApiKeysSection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, cardPadding)
                .frame(height: 36)
            }
            .buttonStyle(.plain)

            if showingApiKeysSection {
                Divider().padding(.leading, cardPadding)

                // OpenAI API Key row
                HStack {
                    HStack(spacing: 4) {
                        Image("OpenAIIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                        Text("OpenAI Key")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    if viewModel.hasAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                    }

                    Spacer()

                    if viewModel.hasAPIKey {
                        Menu {
                            Button("Test API Key") { viewModel.testOpenAIKey() }
                            Divider()
                            Button("Remove", role: .destructive) { viewModel.deleteAPIKey() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 24)
                    } else {
                        Button("Add") {
                            addingKeyFor = .openai
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, cardPadding)
                .frame(height: 36)

                Divider().padding(.leading, cardPadding)

                // Claude API Key row
                HStack {
                    HStack(spacing: 4) {
                        Image("ClaudeIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                        Text("Claude Key")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    if viewModel.hasClaudeAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                    }

                    Spacer()

                    if viewModel.hasClaudeAPIKey {
                        Menu {
                            Button("Test API Key") { viewModel.testClaudeKey() }
                            Divider()
                            Button("Remove", role: .destructive) { viewModel.deleteClaudeAPIKey() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 24)
                    } else {
                        Button("Add") {
                            addingKeyFor = .claude
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, cardPadding)
                .frame(height: 36)

                Divider().padding(.leading, cardPadding)

                // Custom Endpoint row
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .frame(width: 11, height: 11)
                        Text("Custom")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    if viewModel.hasCustomEndpoint {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                    }

                    Spacer()

                    if viewModel.hasCustomEndpoint {
                        Menu {
                            Button("Test Endpoint") { viewModel.testCustomEndpoint() }
                            Divider()
                            Button("Remove", role: .destructive) { viewModel.deleteCustomEndpoint() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 24)
                    } else {
                        Button("Add") {
                            addingKeyFor = .custom
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, cardPadding)
                .frame(height: 36)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Add API Key Card (full page)

    private func addApiKeyCard(for provider: APIProvider) -> some View {
        VStack(spacing: 0) {
            // Header with provider icon + close button
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    if provider == .openai {
                        Image("OpenAIIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    } else if provider == .claude {
                        Image("ClaudeIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "server.rack")
                            .font(.system(size: 22))
                            .frame(width: 28, height: 28)
                    }

                    Text(provider == .custom ? "Custom Endpoint" : "Add your \(provider.displayName) Key")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                Button {
                    viewModel.apiKeyInput = ""
                    viewModel.claudeApiKeyInput = ""
                    showingApiKeySteps = false
                    addingKeyFor = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            Divider()

            // API key input + Save + Open link + pricing
            VStack(spacing: 8) {
                if provider == .openai {
                    SecureField("API key", text: $viewModel.apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 12, design: .monospaced))

                    Button {
                        viewModel.saveAPIKey()
                        if viewModel.hasAPIKey {
                            addingKeyFor = nil
                        }
                    } label: {
                        Text("Save API Key")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKeyInput.isEmpty)

                    Button {
                        if let url = URL(string: "https://platform.openai.com/api-keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open OpenAI")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)

                    Text("OpenAI charges only for usage. To use a custom endpoint (Ollama, LM Studio, etc.), configure it in the API Keys section after saving.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if provider == .claude {
                    SecureField("sk-ant-...", text: $viewModel.claudeApiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 12, design: .monospaced))

                    Button {
                        viewModel.saveClaudeAPIKey()
                        if viewModel.hasClaudeAPIKey {
                            addingKeyFor = nil
                        }
                    } label: {
                        Text("Save API Key")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.claudeApiKeyInput.isEmpty)

                    Button {
                        if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open Anthropic")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)

                    Text("Anthropic charges only for usage. This app uses claude-sonnet-4. With normal use, $5 = 5,000+ translations.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Custom endpoint
                    TextField("Base URL (e.g. http://localhost:11434/v1)", text: $customEndpointURLInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))
                        .onAppear { customEndpointURLInput = viewModel.openAIBaseURL }

                    SecureField("API key (optional)", text: $customEndpointKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))

                    TextField("Model (default: gpt-4o-mini)", text: $customEndpointModelInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))
                        .onAppear { customEndpointModelInput = viewModel.openAIModel }

                    Button {
                        viewModel.saveCustomEndpoint(
                            url: customEndpointURLInput,
                            apiKey: customEndpointKeyInput,
                            model: customEndpointModelInput
                        )
                        if viewModel.hasCustomEndpoint {
                            customEndpointURLInput = ""
                            customEndpointKeyInput = ""
                            customEndpointModelInput = ""
                            addingKeyFor = nil
                        }
                    } label: {
                        Text("Save Endpoint")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customEndpointURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("For Ollama, LM Studio, vLLM, and other OpenAI-compatible APIs. API key is optional for local servers.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(cardPadding + 4)

            if provider != .custom {
            Divider()

            // Collapsible "How to get an API key"
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingApiKeySteps.toggle()
                    }
                } label: {
                    HStack {
                        Text("How to get an API key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: showingApiKeySteps ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, cardPadding + 4)
                    .frame(height: 32)
                }
                .buttonStyle(.plain)

                if showingApiKeySteps {
                    VStack(alignment: .leading, spacing: 6) {
                        if provider == .openai {
                            apiKeyStep(number: 1, text: "Sign in at platform.openai.com")
                            apiKeyStep(number: 2, text: "Go to API Keys section")
                            apiKeyStep(number: 3, text: "Create new secret key")
                            apiKeyStep(number: 4, text: "Copy and paste above")
                        } else {
                            apiKeyStep(number: 1, text: "Sign in at console.anthropic.com")
                            apiKeyStep(number: 2, text: "Go to API Keys section")
                            apiKeyStep(number: 3, text: "Create new key")
                            apiKeyStep(number: 4, text: "Copy and paste above")
                        }
                    }
                    .padding(.leading, cardPadding + 4)
                    .padding(.trailing, cardPadding)
                    .padding(.bottom, cardPadding)
                }
            }
            } // end if provider != .custom
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Shortcut Configuration

    private var shortcutConfigCard: some View {
        VStack(spacing: 0) {
            // Header
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Configure Shortcut")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                Button {
                    showingShortcutConfig = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            Divider()

            // Content
            VStack(spacing: 16) {
                // Current shortcut display
                VStack(spacing: 8) {
                    Text("Current Shortcut")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(viewModel.hotkeyDisplayString)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }

                // Key selector
                VStack(spacing: 8) {
                    Text("Select a key (⌘⇧ is fixed)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    TextField("", text: $hotkeyLetter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .frame(width: 40, height: 40)
                        .multilineTextAlignment(.center)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .onChange(of: hotkeyLetter) { newValue in
                            let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                            if let char = filtered.last {
                                hotkeyLetter = String(char)
                                viewModel.updateHotkeyKey(char)
                            } else if newValue.isEmpty {
                                hotkeyLetter = String(HotkeyManager.character(for: viewModel.hotkeyKeyCode) ?? "T")
                            }
                        }
                }

                // Actions list
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Translate")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(viewModel.hotkeyDisplayString)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(3)
                    }
                    HStack {
                        Text("Improve text")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        let key = String(HotkeyManager.character(for: viewModel.hotkeyKeyCode) ?? "T")
                        Text("⌘⇧+\(key)+\(key)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(3)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)

                // Done button
                Button {
                    showingShortcutConfig = false
                } label: {
                    Text("Done")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(cardPadding + 4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
        .onAppear {
            hotkeyLetter = String(HotkeyManager.character(for: viewModel.hotkeyKeyCode) ?? "T")
        }
    }

    // MARK: - Onboarding: Welcome

    private var onboardingWelcomeCard: some View {
        VStack(spacing: 0) {
            // Welcome header with icon
            VStack(spacing: 12) {
                Image("HappyTransLite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                Text("Instant translation anywhere")
                    .font(.system(size: 14, weight: .semibold))

                Text("Select text anywhere on your Mac and translate it instantly. No tabs, no copy-paste loops — just a shortcut.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)

            Divider()

            // Features
            VStack(spacing: 10) {
                featureRow(icon: "bolt.fill", text: "Auto-paste with one shortcut")
                featureRow(icon: "desktopcomputer", text: "Works anywhere on your Mac")
                featureRow(icon: "paintbrush.fill", text: "Custom tone & any language")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, cardPadding + 4)

            Divider()

            // Continue button
            Button {
                viewModel.continueFromWelcome()
            } label: {
                Text("Get Started")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.borderedProminent)
            .padding(cardPadding + 4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            Spacer()
        }
    }

    // MARK: - Onboarding: API Key

    @State private var showingOnboardingApiKeySteps = false

    private var onboardingApiKeyCard: some View {
        VStack(spacing: 0) {
            // Header with provider icon
            VStack(spacing: 6) {
                if onboardingProvider == .openai {
                    Image("OpenAIIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else if onboardingProvider == .claude {
                    Image("ClaudeIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: 22))
                        .frame(width: 28, height: 28)
                }

                Text(onboardingProvider == .custom ? "Custom Endpoint" : "Add your \(onboardingProvider.displayName) Key")
                    .font(.system(size: 13, weight: .semibold))

                Text("Your API key, your data. We never store or read your content.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)

            Divider()

            // Provider selector
            HStack {
                Label("Provider", systemImage: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $onboardingProvider) {
                    ForEach(APIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .padding(.horizontal, cardPadding + 4)
            .frame(height: 36)

            Divider()

            // API key input + Save + Open link + pricing
            VStack(spacing: 8) {
                if onboardingProvider == .openai {
                    SecureField("sk-...", text: $viewModel.apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 12, design: .monospaced))

                    Button {
                        viewModel.saveAPIKey()
                    } label: {
                        Text("Save API Key")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKeyInput.isEmpty)

                    Button {
                        if let url = URL(string: "https://platform.openai.com/api-keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open OpenAI")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)

                    Text("OpenAI charges only for usage. This app uses gpt-4o-mini. With normal use, $5 = 15,000+ translations.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if onboardingProvider == .claude {
                    SecureField("sk-ant-...", text: $viewModel.claudeApiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 12, design: .monospaced))

                    Button {
                        viewModel.saveClaudeAPIKey()
                    } label: {
                        Text("Save API Key")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.claudeApiKeyInput.isEmpty)

                    Button {
                        if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open Anthropic")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)

                    Text("Anthropic charges only for usage. This app uses claude-sonnet-4. With normal use, $5 = 5,000+ translations.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Custom endpoint
                    TextField("Base URL (e.g. http://localhost:11434/v1)", text: $customEndpointURLInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))

                    SecureField("API key (optional)", text: $customEndpointKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))

                    TextField("Model (default: gpt-4o-mini)", text: $customEndpointModelInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .font(.system(size: 11, design: .monospaced))

                    Button {
                        viewModel.saveCustomEndpoint(
                            url: customEndpointURLInput,
                            apiKey: customEndpointKeyInput,
                            model: customEndpointModelInput
                        )
                        if viewModel.hasCustomEndpoint {
                            customEndpointURLInput = ""
                            customEndpointKeyInput = ""
                            customEndpointModelInput = ""
                        }
                    } label: {
                        Text("Save Endpoint")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customEndpointURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("For Ollama, LM Studio, vLLM, and other OpenAI-compatible APIs. API key is optional for local servers.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(cardPadding + 4)

            if onboardingProvider != .custom {
            Divider()

            // Collapsible "How to get an API key"
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingOnboardingApiKeySteps.toggle()
                    }
                } label: {
                    HStack {
                        Text("How to get an API key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: showingOnboardingApiKeySteps ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, cardPadding + 4)
                    .frame(height: 32)
                }
                .buttonStyle(.plain)

                if showingOnboardingApiKeySteps {
                    VStack(alignment: .leading, spacing: 6) {
                        if onboardingProvider == .openai {
                            apiKeyStep(number: 1, text: "Sign in at platform.openai.com")
                            apiKeyStep(number: 2, text: "Go to API Keys section")
                            apiKeyStep(number: 3, text: "Create new secret key")
                            apiKeyStep(number: 4, text: "Copy and paste above")
                        } else {
                            apiKeyStep(number: 1, text: "Sign in at console.anthropic.com")
                            apiKeyStep(number: 2, text: "Go to API Keys section")
                            apiKeyStep(number: 3, text: "Create new key")
                            apiKeyStep(number: 4, text: "Copy and paste above")
                        }
                    }
                    .padding(.leading, cardPadding + 4)
                    .padding(.trailing, cardPadding)
                    .padding(.bottom, cardPadding)
                }
            }
            } // end if onboardingProvider != .custom
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Onboarding: Permissions

    private var onboardingPermissionsCard: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                Text("Enable Auto-Paste")
                    .font(.system(size: 14, weight: .semibold))

                Text("For the best experience, allow TransLite to paste translated text automatically")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)

            Divider()

            // Shortcut preview
            VStack(spacing: 8) {
                Text("Your workflow will be:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        Text("Select text")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))

                    VStack(spacing: 4) {
                        Text(viewModel.hotkeyDisplayString)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Shortcut")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))

                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                        Text("Translated")
                            .font(.system(size: 9))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.vertical, 12)

            Divider()

            // Buttons
            VStack(spacing: 8) {
                Button {
                    viewModel.enableAutoPasteWithPermissions()
                } label: {
                    Text("Enable Auto-Paste")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.skipAutoPaste()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(cardPadding + 4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
    }

    private func apiKeyStep(number: Int, text: String) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.accentColor.opacity(0.8)))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.system(size: 9))
            Text(viewModel.statusMessage)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            FeedbackMenu()

            Spacer()

            #if DEBUG
            DebugMenu(viewModel: viewModel)
                .padding(.trailing, 8)
            #endif

            MoreOptionsMenu()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var statusIcon: String {
        if viewModel.statusMessage.contains("success") ||
           viewModel.statusMessage.contains("Translated") ||
           viewModel.statusMessage.contains("saved") ||
           viewModel.statusMessage.contains("working ✓") {
            return "checkmark.circle.fill"
        } else if viewModel.statusMessage.contains("error") ||
                  viewModel.statusMessage.contains("Failed") ||
                  viewModel.statusMessage.contains("Invalid") ||
                  viewModel.statusMessage.contains("empty") {
            return "exclamationmark.circle.fill"
        } else {
            return "info.circle.fill"
        }
    }

    private var statusColor: Color {
        if viewModel.statusMessage.contains("success") ||
           viewModel.statusMessage.contains("Translated") ||
           viewModel.statusMessage.contains("saved") ||
           viewModel.statusMessage.contains("working ✓") {
            return .green
        } else if viewModel.statusMessage.contains("error") ||
                  viewModel.statusMessage.contains("Failed") ||
                  viewModel.statusMessage.contains("Invalid") ||
                  viewModel.statusMessage.contains("empty") {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Footer Components

private struct FeedbackMenu: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: "https://tally.so/r/D4zL25") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                Text("Feedback")
                    .font(.system(size: 10))
            }
            .foregroundColor(isHovered ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct UpgradeButton: View {
    let text: String
    let isExpired: Bool
    @State private var isHovered = false

    private var baseColor: Color {
        isExpired ? .red : .accentColor
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(baseColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(baseColor.opacity(isHovered ? 0.2 : 0.1))
            .cornerRadius(6)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

#if DEBUG
private struct DebugMenu: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHovered = false

    private var trialInfo: String {
        let info = TrialManager.shared.debugInfo
        return "Start: \(info.startDate)\nLast: \(info.lastUsed)\nStatus: \(info.status)"
    }

    var body: some View {
        Menu {
            Section("Current State") {
                Text(trialInfo)
                    .font(.system(size: 10, design: .monospaced))
            }

            Divider()

            Section("Trial") {
                Button("Reset Trial (7 days)") {
                    TrialManager.shared.debugResetTrial()
                    viewModel.refreshTrialStatus()
                }
                Button("Expire Trial") {
                    TrialManager.shared.debugExpireTrial()
                    viewModel.refreshTrialStatus()
                }
                Button("Set 1 Day Left") {
                    TrialManager.shared.debugSetDaysLeft(1)
                    viewModel.refreshTrialStatus()
                }
                Button("Set 3 Days Left") {
                    TrialManager.shared.debugSetDaysLeft(3)
                    viewModel.refreshTrialStatus()
                }
            }

            Divider()

            Section("License") {
                Button("Add Fake License") {
                    Task {
                        _ = await TrialManager.shared.activateLicense("DEBUG-LICENSE-KEY")
                        viewModel.refreshTrialStatus()
                    }
                }
                Button("Remove License") {
                    TrialManager.shared.removeLicense()
                    viewModel.refreshTrialStatus()
                }
            }

            Divider()

            Section("Onboarding") {
                Button("Reset Everything") {
                    // Delete API keys first (it sets some flags)
                    viewModel.deleteAPIKey()
                    viewModel.deleteClaudeAPIKey()

                    // Now reset all onboarding flags
                    UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")

                    // Reset trial
                    TrialManager.shared.debugResetTrial()
                    viewModel.refreshTrialStatus()

                    // Force back to welcome screen
                    viewModel.onboardingStep = .welcome
                }
            }
        } label: {
            Image(systemName: "ladybug")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
#endif

private struct MoreOptionsMenu: View {
    @State private var isHovered = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Menu {
            Button {
                launchAtLogin.toggle()
                toggleLaunchAtLogin(launchAtLogin)
            } label: {
                HStack {
                    Text("Launch at Startup")
                    if launchAtLogin {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            Button("Follow on X") {
                if let url = URL(string: "https://x.com/davizgarzia") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Visit website") {
                if let url = URL(string: "https://translite.app") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Check for Updates...") {
                AppDelegate.shared?.updaterController?.checkForUpdates(nil)
            }

            Divider()

            Button("Quit TransLite") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            if enabled {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

#Preview {
    PopoverView(viewModel: AppViewModel())
}
