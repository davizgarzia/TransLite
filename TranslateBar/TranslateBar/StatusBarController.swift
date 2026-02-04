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
    private var animationTimer: Timer?
    private var animationFrame: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private let animationIcons = ["globe", "globe.americas.fill", "globe.europe.africa.fill", "globe.asia.australia.fill"]

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
        contextMenu.addItem(NSMenuItem(title: "Quit TranslateBar", action: #selector(quitApp), keyEquivalent: "q"))

        // Configure status item button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "TranslateBar")
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

        // Observe translation state for icon animation
        viewModel.$isTranslating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranslating in
                if isTranslating {
                    self?.startIconAnimation()
                } else {
                    self?.stopIconAnimation()
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
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Ensure popover window becomes key
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon Animation

    private func startIconAnimation() {
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.animationFrame = (self.animationFrame + 1) % self.animationIcons.count
                if let button = self.statusItem.button {
                    button.image = NSImage(systemSymbolName: self.animationIcons[self.animationFrame], accessibilityDescription: "Translating")
                }
            }
        }
    }

    private func stopIconAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "TranslateBar")
        }
    }
}
