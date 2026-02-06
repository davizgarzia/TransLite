import AppKit
import SwiftUI

/// Floating HUD window that shows translation status
final class TranslationHUD {
    static let shared = TranslationHUD()

    private var window: NSWindow?
    private var hostingView: NSHostingView<HUDContentView>?

    private init() {}

    /// Shows the HUD with the given message
    func show(message: String = "Translating...") {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow(message: message)
        }
    }

    /// Hides the HUD
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.window?.orderOut(nil)
                self?.window = nil
            }
        }
    }

    /// Updates the message while HUD is showing
    func update(message: String) {
        DispatchQueue.main.async { [weak self] in
            if let hostingView = self?.hostingView {
                hostingView.rootView = HUDContentView(message: message)
            }
        }
    }

    private func createAndShowWindow(message: String) {
        // Close existing window if any
        window?.orderOut(nil)

        // Create the SwiftUI content
        let contentView = HUDContentView(message: message)
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = NSRect(x: 0, y: 0, width: 180, height: 80)

        // Create the window
        let hudWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        hudWindow.contentView = hostingView
        hudWindow.isOpaque = false
        hudWindow.backgroundColor = .clear
        hudWindow.level = .floating
        hudWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        hudWindow.isMovableByWindowBackground = false
        hudWindow.hasShadow = true

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 90
            let y = screenFrame.midY - 40
            hudWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Show with fade in
        hudWindow.alphaValue = 0
        hudWindow.orderFront(nil)
        hudWindow.animator().alphaValue = 1

        self.window = hudWindow
    }
}

/// SwiftUI view for HUD content
struct HUDContentView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .colorInvert()
                .brightness(1)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
