import AppKit
import SwiftUI

/// Controls the floating HUD window that appears during translation
@MainActor
final class TranslationHUDController: ObservableObject {
    @Published var state: TranslationHUDState = .translating
    
    private var window: NSWindow?
    
    /// Shows the HUD at the specified screen position
    func show(at position: CGPoint) {
        hide() // Hide any existing HUD
        
        let hostingController = NSHostingController(rootView: TranslationHUDView(state: state))
        hostingController.view.wantsLayer = true
        
        let panel = NSPanel(
            contentRect: NSRect(x: position.x, y: position.y, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentViewController = hostingController
        panel.isMovable = false
        panel.hasShadow = true
        
        // Calculate proper size
        let size = hostingController.view.fittingSize
        panel.setContentSize(size)
        
        // Adjust position to be above and centered relative to the cursor
        var frame = panel.frame
        frame.origin.x = position.x - (size.width / 2)
        frame.origin.y = position.y + 20 // Position above cursor
        
        // Ensure HUD stays within screen bounds
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            // Adjust horizontal position
            if frame.maxX > screenFrame.maxX {
                frame.origin.x = screenFrame.maxX - frame.width - 10
            } else if frame.minX < screenFrame.minX {
                frame.origin.x = screenFrame.minX + 10
            }
            
            // Adjust vertical position
            if frame.maxY > screenFrame.maxY {
                frame.origin.y = position.y - size.height - 20 // Show below if no space above
            } else if frame.minY < screenFrame.minY {
                frame.origin.y = screenFrame.minY + 10
            }
        }
        
        panel.setFrame(frame, display: true)
        
        self.window = panel
        
        // Animate in
        panel.alphaValue = 0
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }
    
    /// Updates the HUD state
    func update(state: TranslationHUDState) {
        self.state = state
        
        // Update the view
        if let window = window,
           let hostingController = window.contentViewController as? NSHostingController<TranslationHUDView> {
            hostingController.rootView = TranslationHUDView(state: state)
        }
    }
    
    /// Hides the HUD with animation
    func hide(after delay: TimeInterval = 0) {
        guard let window = window else { return }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                window.orderOut(nil)
                self?.window = nil
            })
        }
    }
}
