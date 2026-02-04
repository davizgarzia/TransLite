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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if case .expired = viewModel.trialStatus {
                licenseCard
            }

            VStack(spacing: contentSpacing) {
                settingsCard
                apiKeyCard
                autoPasteCard
            }
            .opacity(trialExpired ? 0.5 : 1.0)
            .disabled(trialExpired)

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

            trialBadge

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
            }
        }
    }

    @ViewBuilder
    private var trialBadge: some View {
        switch viewModel.trialStatus {
        case .licensed:
            Text("Pro")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green)
                .cornerRadius(4)
        case .active(let days):
            Text("\(days)d left")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        case .expired:
            Text("Expired")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red)
                .cornerRadius(4)
        }
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Language row
            HStack {
                Label("Language", systemImage: "character.bubble")
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

    // MARK: - API Key Card

    private var apiKeyCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("API Key", systemImage: "key.fill")
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

            if !viewModel.hasAPIKey {
                Divider().padding(.leading, cardPadding)

                VStack(spacing: 6) {
                    SecureField("sk-...", text: $viewModel.apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                        .font(.system(size: 11, design: .monospaced))

                    Button {
                        viewModel.saveAPIKey()
                    } label: {
                        Text("Save Key")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKeyInput.isEmpty)
                }
                .padding(cardPadding)

                Divider().padding(.leading, cardPadding)

                // Footer help section
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                    Text("OpenAI API Key required")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(showingAPIKeyHelp ? "Hide" : "Help") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAPIKeyHelp.toggle()
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, 8)

                // Expandable help steps
                if showingAPIKeyHelp {
                    Divider().padding(.leading, cardPadding)

                    VStack(alignment: .leading, spacing: 6) {
                        apiKeyStep(number: 1, text: "Sign in at platform.openai.com")
                        apiKeyStep(number: 2, text: "Go to API Keys section")
                        apiKeyStep(number: 3, text: "Create new secret key")
                        apiKeyStep(number: 4, text: "Copy and paste above")

                        Button {
                            if let url = URL(string: "https://platform.openai.com/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open OpenAI")
                            }
                            .font(.system(size: 9, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(cardPadding)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
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

    // MARK: - Auto-paste Card

    private var autoPasteCard: some View {
        VStack(spacing: 0) {
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

    // MARK: - License Card

    private var licenseCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trial Expired")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Activate a license to continue")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(cardPadding)

            Divider().padding(.leading, cardPadding)

            // License key input
            VStack(spacing: 8) {
                TextField("Enter license key", text: $viewModel.licenseKeyInput)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                    .font(.system(size: 11, design: .monospaced))

                HStack(spacing: 8) {
                    Button {
                        viewModel.activateLicense()
                    } label: {
                        Text("Activate")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.licenseKeyInput.isEmpty || viewModel.isActivatingLicense)

                    Button {
                        viewModel.openPurchasePage()
                    } label: {
                        Text("Buy License")
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(cardPadding)
        }
        .background(Color.orange.opacity(0.1))
        .cornerRadius(cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
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
