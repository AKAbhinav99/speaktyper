import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut via Carbon's RegisterEventHotKey.
/// Doesn't need Accessibility permission, and swallows the keystroke so it never
/// reaches the focused app.
final class HotKey {
    typealias Handler = (_ isPressed: Bool) -> Void

    nonisolated(unsafe) private static var handlers: [UInt32: Handler] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var eventHandlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
        Self.installEventHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x5350_5459) /* 'SPTY' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        isRegistered = status == noErr
        if !isRegistered {
            NSLog("SpeakTyper: failed to register hotkey (\(status)) — is another app using it?")
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr, let handler = HotKey.handlers[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            handler(GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, types.count, &types, nil, nil)
    }
}
