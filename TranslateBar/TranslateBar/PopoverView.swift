import SwiftUI

/// Main SwiftUI view for the menubar popover
struct PopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingAPIKeyHelp = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch viewModel.onboardingStep {
            case .apiKey:
                onboardingApiKeyCard

            case .permissions:
                onboardingPermissionsCard

            case .complete:
                if !isLicensed {
                    trialSection
                }

                VStack(spacing: contentSpacing) {
                    translationCard
                    keysCard
                }
                .opacity(trialExpired ? 0.5 : 1.0)
                .disabled(trialExpired)
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
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)

            Text("TransLite")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            HStack(spacing: 3) {
                Text("⌘C")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(3)
                Text("+")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("⌘⇧T")
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

    // MARK: - Keys Card (API Key only)

    private var keysCard: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image("OpenAIIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                    Text("API Key")
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
                    Button("Remove") {
                        viewModel.deleteAPIKey()
                    }
                    .font(.system(size: 9, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, cardPadding)
            .frame(height: 36)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
    }

    // MARK: - Onboarding: API Key

    private var onboardingApiKeyCard: some View {
        VStack(spacing: 0) {
            // Welcome header
            VStack(spacing: 4) {
                Text("Welcome to TransLite")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add your OpenAI API key to get started")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Divider()

            // API key input
            VStack(spacing: 8) {
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
            }
            .padding(cardPadding + 4)

            Divider()

            // Steps always visible
            VStack(alignment: .leading, spacing: 8) {
                Text("How to get an API key")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    apiKeyStep(number: 1, text: "Sign in at platform.openai.com")
                    apiKeyStep(number: 2, text: "Go to API Keys section")
                    apiKeyStep(number: 3, text: "Create new secret key")
                    apiKeyStep(number: 4, text: "Copy and paste above")
                }

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
            }
            .padding(cardPadding + 4)
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

                HStack(spacing: 6) {
                    shortcutBadge("⌘C")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    shortcutBadge("⌘⇧T")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text("Done ✨")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
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
        HStack(spacing: 12) {
            FeedbackMenu()

            Spacer()

            #if DEBUG
            DebugMenu(viewModel: viewModel)
            #endif

            QuitButton()
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var statusIcon: String {
        if viewModel.statusMessage.contains("success") ||
           viewModel.statusMessage.contains("Translated") ||
           viewModel.statusMessage.contains("saved") {
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
           viewModel.statusMessage.contains("saved") {
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
        Menu {
            Button {
                if let url = URL(string: "https://mail.google.com/mail/?view=cm&to=dvzgrz@gmail.com&su=TransLite%20Feedback") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Send an email", systemImage: "envelope")
            }

            Button {
                if let url = URL(string: "https://x.com/messages/compose?recipient_id=1164799217748942849") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Message on X", systemImage: "at")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                Text("Feedback")
                    .font(.system(size: 10))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(isHovered ? .primary : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                        await TrialManager.shared.activateLicense("DEBUG-LICENSE-KEY")
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
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")
                    TrialManager.shared.debugResetTrial()
                    viewModel.onboardingStep = .apiKey
                    viewModel.deleteAPIKey()
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

private struct QuitButton: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    PopoverView(viewModel: AppViewModel())
}
