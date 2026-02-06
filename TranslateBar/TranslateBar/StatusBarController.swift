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
    private var spinner: NSProgressIndicator?
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
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "TransLite")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Set target for menu items
        for item in contextMenu.items {
            item.target = self
        }

        // Monitor for clicks outside popover to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }

        // Observe translation state for spinner
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
    
    /// Shows the popover (can be called externally)
    func showPopover() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover window becomes key
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Spinner Animation

    private func startSpinner() {
        guard let button = statusItem.button else { return }
        
        // Hide the icon
        button.image = nil
        
        // Create and configure spinner
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        
        // Add spinner to button
        button.addSubview(spinner)
        
        // Center the spinner
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        
        spinner.startAnimation(nil)
        self.spinner = spinner
    }

    private func stopSpinner() {
        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil
        
        // Restore the icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "TransLite")
        }
    }
}
