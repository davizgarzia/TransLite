import SwiftUI
import Sparkle

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
    static var shared: AppDelegate!

    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var viewModel: AppViewModel?

    // Sparkle updater controller
    var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        AnalyticsClient.track("app_opened")

        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the view model
        viewModel = AppViewModel()

        // Initialize the status bar controller
        if let viewModel = viewModel {
            statusBarController = StatusBarController(viewModel: viewModel)
            
            // Show popover on first launch (when onboarding is not complete)
            if viewModel.onboardingStep != .complete {
                // Delay slightly to ensure UI is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.statusBarController?.showPopover()
                }
            }
        }

        // Initialize the hotkey manager with double-tap support
        hotkeyManager = HotkeyManager(
            onSingleTap: { [weak self] in
                self?.viewModel?.translateClipboard()
            },
            onDoubleTap: { [weak self] in
                self?.viewModel?.improveText()
            }
        )

        // Register the global hotkey with saved key code
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let keyCode = savedKeyCode > 0 ? UInt32(savedKeyCode) : HotkeyManager.defaultKeyCode
        hotkeyManager?.registerHotkey(keyCode: keyCode)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterHotkey()
    }
}
