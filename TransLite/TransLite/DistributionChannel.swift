import Foundation
#if SETAPP
import Setapp
#endif

/// Which distribution this binary was built for, decided at compile time by
/// the SETAPP flag (set only on the TransLiteSetapp target). Distribution
/// differences should key off this file or live behind #if SETAPP in the
/// few places that genuinely diverge (backend, licensing UI, updates).
enum DistributionChannel: String {
    case direct
    case setapp

    static let current: DistributionChannel = {
        #if SETAPP
        return .setapp
        #else
        return .direct
        #endif
    }()
}

/// Setapp calculates vendor payouts from reported usage, and menu bar apps
/// have no regular window for the framework to observe — so every meaningful
/// interaction (opening the popover, translating via hotkey) must be reported
/// explicitly. No-op in the direct build.
enum SetappUsage {
    static func reportUserInteraction() {
        #if SETAPP
        SetappManager.shared.reportUsageEvent(.userInteraction)
        #endif
    }
}
