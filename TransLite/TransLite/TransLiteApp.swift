import SwiftUI

@main
struct TransLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - we're a menubar-only app
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the view model
        viewModel = AppViewModel()

        // Initialize the status bar controller
        if let viewModel = viewModel {
            statusBarController = StatusBarController(viewModel: viewModel)
            
            // Show popover on first launch (when user is on welcome screen)
            if viewModel.onboardingStep == .welcome {
                // Delay slightly to ensure UI is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.statusBarController?.showPopover()
                }
            }
        }

        // Initialize the hotkey manager
        hotkeyManager = HotkeyManager { [weak self] in
            self?.viewModel?.translateClipboard()
        }

        // Register the global hotkey (Cmd+Shift+T)
        hotkeyManager?.registerHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterHotkey()
    }
}
