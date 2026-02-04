import SwiftUI

/// Visual states for the translation HUD
enum TranslationHUDState {
    case translating
    case typing(progress: Double)
    case success
    case error(String)
}

/// Floating HUD that appears near selected text during translation
struct TranslationHUDView: View {
    let state: TranslationHUDState
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            iconView
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if case .translating = state {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(height: 4)
                } else if case .typing(let progress) = state {
                    ProgressView(value: progress)
                        .frame(height: 4)
                        .tint(.accentColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .translating:
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
                .onAppear { isAnimating = true }
        case .typing:
            Image(systemName: "text.cursor")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.red)
        }
    }
    
    private var titleText: String {
        switch state {
        case .translating:
            return "Traduciendo..."
        case .typing:
            return "Escribiendo..."
        case .success:
            return "¡Traducido!"
        case .error(let message):
            return message
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TranslationHUDView(state: .translating)
        TranslationHUDView(state: .typing(progress: 0.6))
        TranslationHUDView(state: .success)
        TranslationHUDView(state: .error("Error"))
    }
    .padding()
    .frame(width: 300, height: 300)
}
