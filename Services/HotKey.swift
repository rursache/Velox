import AppKit
import Carbon

/// Global hotkey using Carbon
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32
    private let callback: () -> Void
    private(set) var registrationStatus: OSStatus = noErr

    static var lastRegistrationStatus: OSStatus = noErr
    static var lastRegistrationFailed: Bool { lastRegistrationStatus != noErr }

    private static let lock = NSLock()
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static var handlerRef: EventHandlerRef?

    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    init(keyCode: UInt32, modifiers: Modifiers, handler: @escaping () -> Void) {
        self.callback = handler
        HotKey.lock.lock()
        self.id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = handler
        HotKey.lock.unlock()

        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(Constants.HotKey.carbonSignature), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        registrationStatus = status
        HotKey.lastRegistrationStatus = status
        if status != noErr {
            NSLog("[Velox] RegisterEventHotKey failed: %d", status)
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        HotKey.lock.lock()
        HotKey.handlers[id] = nil
        HotKey.lock.unlock()
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr else { return noErr }
                HotKey.lock.lock()
                let cb = HotKey.handlers[hkID.id]
                HotKey.lock.unlock()
                if let cb {
                    DispatchQueue.main.async { cb() }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status == noErr {
            handlerInstalled = true
        } else {
            NSLog("[Velox] InstallEventHandler failed: %d", status)
        }
    }
}
