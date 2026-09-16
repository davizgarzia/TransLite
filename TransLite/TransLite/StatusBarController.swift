import AppKit
import SwiftUI
import Combine

/// Manages the menubar status item and popover
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: Any?
    private var contextMenu: NSMenu
    private var pulseAnimation: CABasicAnimation?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: AppViewModel) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(viewModel: viewModel))

        // Create context menu for right-click
        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Quit TransLite", action: #selector(quitApp), keyEquivalent: "q"))

        // Configure status item button
        if let button = statusItem.button {
            if let image = NSImage(named: "TransLiteIcon") {
                image.size = NSSize(width: 20, height: 16)
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Set target for menu items
        for item in contextMenu.items {
            item.target = self
        }

        // Monitor for clicks outside popover to close it. Skipped while the
        // popover is pinned (.applicationDefined) during onboarding, so the
        // welcome card survives the post-install clicking around (closing the
        // DMG, Gatekeeper dialogs, ...)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown, popover.behavior == .transient {
                popover.performClose(nil)
            }
        }

        // Pin the popover open until onboarding is done, then restore the
        // normal click-outside-to-dismiss behavior
        viewModel.$onboardingStep
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step in
                self?.popover.behavior = step == .complete ? .transient : .applicationDefined
            }
            .store(in: &cancellables)

        // Observe translation state for pulse animation
        viewModel.$isTranslating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranslating in
                if isTranslating {
                    self?.startSpinner()
                } else {
                    self?.stopSpinner()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show context menu
            if let button = statusItem.button {
                contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            }
        } else {
            // Left-click: toggle popover
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }
    
    /// Shows the popover (can be called externally). Pass `activating: true`
    /// to bring the app to the front first — used on first launch so the
    /// welcome popover doesn't appear unfocused behind Finder.
    func showPopover(activating: Bool = false) {
        if activating {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover window becomes key
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Pulse Animation

    private func startSpinner() {
        guard let button = statusItem.button else { return }

        // Ensure layer-backed view
        button.wantsLayer = true

        // Create pulse animation
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        button.layer?.add(pulse, forKey: "pulseAnimation")
        pulseAnimation = pulse
    }

    private func stopSpinner() {
        guard let button = statusItem.button else { return }

        // Remove animation
        button.layer?.removeAnimation(forKey: "pulseAnimation")
        pulseAnimation = nil
    }
}
