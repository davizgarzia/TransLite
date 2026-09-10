import AppKit
import SwiftUI

/// Observable state driving the HUD content and its animations
final class HUDModel: ObservableObject {
    @Published var message: String = ""
    @Published var visible: Bool = false
    @Published var tip: String?
}

/// Floating HUD window that shows translation status
final class TranslationHUD {
    static let shared = TranslationHUD()

    private var window: NSWindow?
    private var hostingView: NSHostingView<HUDContentView>?
    private let model = HUDModel()
    private var tipTimer: Timer?

    /// One-line usage tips shown under the HUD while the user waits
    private static let tips = [
        "Double-press the shortcut to improve",
        "Auto-paste replaces text in place",
        "Switch tones from the menu bar",
        "The result is in your clipboard",
        "Change the language in the menu bar",
        "The shortcut is customizable"
    ]

    private init() {}

    /// Shows the HUD with the given message
    func show(message: String = "Translating...") {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow(message: message)
        }
    }

    /// Hides the HUD with a quick fade/scale-out
    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tipTimer?.invalidate()
            self.tipTimer = nil
            withAnimation(.easeIn(duration: 0.15)) {
                self.model.visible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.window?.orderOut(nil)
                self.window = nil
                self.hostingView = nil
            }
        }
    }

    /// Updates the message while HUD is showing, cross-fading the text and
    /// animating the window to the new content size
    func update(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.message = message
            self.resizeWindowToFit()
        }
    }

    /// Gives SwiftUI a runloop pass to lay out new content, then animates
    /// the window frame to fit it, keeping it centered
    private func resizeWindowToFit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, let hostingView = self.hostingView else { return }
            let newSize = hostingView.fittingSize
            var frame = window.frame
            frame.origin.x = frame.midX - newSize.width / 2
            frame.origin.y = frame.midY - newSize.height / 2
            frame.size = newSize
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }
    }

    /// Picks a random tip and keeps rotating it while the HUD is visible
    private func startTips() {
        model.tip = Self.tips.randomElement()
        tipTimer?.invalidate()
        tipTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let others = Self.tips.filter { $0 != self.model.tip }
            self.model.tip = others.randomElement()
            self.resizeWindowToFit()
        }
    }

    private func createAndShowWindow(message: String) {
        // Close existing window if any
        window?.orderOut(nil)

        model.message = message
        model.visible = false
        startTips()

        // Create the SwiftUI content
        let contentView = HUDContentView(model: model)
        hostingView = NSHostingView(rootView: contentView)

        // Let the view size itself to fit content
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 200, height: 80)
        hostingView?.frame = NSRect(origin: .zero, size: fittingSize)

        // Create the window
        let hudWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
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
        hudWindow.hasShadow = false

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.midY - fittingSize.height / 2
            hudWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        hudWindow.orderFront(nil)
        self.window = hudWindow

        // Animate the content in (fade + scale) once mounted
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self?.model.visible = true
            }
        }
    }
}

/// SwiftUI view for HUD content
struct HUDContentView: View {
    @ObservedObject var model: HUDModel
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            // Status row
            HStack(spacing: 12) {
                Image("TransLiteIcon")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 13)
                    .foregroundColor(.white.opacity(0.7))
                    .opacity(isPulsing ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear {
                        isPulsing = true
                    }

                Text(model.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)

            // Rotating usage tip, centered, sharing the card's width
            if let tip = model.tip {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)

                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                    Text(tip)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: true, vertical: false)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.25), value: tip)
            }
        }
        .fixedSize()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .scaleEffect(model.visible ? 1 : 0.9)
        .opacity(model.visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: model.message)
        .environment(\.colorScheme, .dark)
    }
}
