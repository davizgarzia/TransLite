import Carbon
import AppKit

/// Manages global keyboard shortcuts using Carbon Hot Key APIs
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    // Unique identifier for our hotkey
    private let hotkeyID = EventHotKeyID(signature: OSType(0x5442_4152), id: 1) // "TBAR"

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    deinit {
        unregisterHotkey()
    }

    /// Registers the global hotkey (Cmd+Shift+T)
    func registerHotkey() {
        // Key code for 'T' is 17
        let keyCode: UInt32 = 17
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var hotKeyID = hotkeyID

        // Register the hotkey
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr else {
            print("Failed to register hotkey: \(status)")
            return
        }

        // Install event handler
        installEventHandler()
    }

    /// Unregisters the global hotkey
    func unregisterHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // We need to capture self in a way that Carbon callbacks can use
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                // Check if this is our hotkey
                if hotKeyID.signature == manager.hotkeyID.signature && hotKeyID.id == manager.hotkeyID.id {
                    DispatchQueue.main.async {
                        manager.callback()
                    }
                    return noErr
                }

                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }
}
