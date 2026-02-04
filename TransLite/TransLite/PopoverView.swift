import SwiftUI

/// Main SwiftUI view for the menubar popover
struct PopoverView: View {
    @ObservedObject var viewModel: AppViewModel

    private let cardPadding: CGFloat = 8
    private let cardCornerRadius: CGFloat = 12
    private let contentSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: contentSpacing) {
                settingsCard
                apiKeyCard
                autoPasteCard
            }

            if !viewModel.statusMessage.isEmpty {
                statusSection
            }
        }
        .padding(14)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            viewModel.refreshAccessibilityStatus()
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
            Image(systemName: "globe")
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
            }
        }
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Language row
            HStack {
                Label("Language", systemImage: "globe")
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
                Spacer()

                if viewModel.hasAPIKey {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("Configured")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Button {
                            viewModel.deleteAPIKey()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
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
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(cardCornerRadius)
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

#Preview {
    PopoverView(viewModel: AppViewModel())
}
