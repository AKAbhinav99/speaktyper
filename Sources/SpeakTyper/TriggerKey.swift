import AppKit

/// Watches the Right Option key pressed on its own — a key almost nothing else uses.
/// Uses global event monitors, which rely on the Accessibility permission SpeakTyper
/// already needs for typing.
final class TriggerKey {
    /// Right Option is held down (true) or released (false).
    var onChange: ((_ isDown: Bool) -> Void)?
    /// Another key or modifier was pressed while it was held, so it was part of a shortcut.
    var onChord: (() -> Void)?

    /// Device-specific bit for the right-hand Option key (NX_DEVICERALTKEYMASK).
    private static let rightOptionMask: UInt = 0x40
    private static let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .shift, .function]

    private var monitors: [Any] = []
    private var isDown = false

    init() {
        let handleFlags: (NSEvent) -> Void = { [weak self] in self?.flagsChanged($0) }
        let handleKey: (NSEvent) -> Void = { [weak self] _ in self?.keyPressed() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handleFlags),
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handleKey),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { handleFlags($0); return $0 },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handleKey($0); return $0 },
        ].compactMap { $0 }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func flagsChanged(_ event: NSEvent) {
        let rightOption = event.modifierFlags.rawValue & Self.rightOptionMask != 0
        let others = !event.modifierFlags.intersection(Self.otherModifiers).isEmpty

        if isDown, others {
            onChord?()  // e.g. Right ⌥ + ⌘ — someone's shortcut, not dictation
        }
        guard rightOption != isDown else { return }
        // Pressed together with another modifier → not ours.
        if rightOption, others { return }
        isDown = rightOption
        onChange?(rightOption)
    }

    private func keyPressed() {
        if isDown { onChord?() }  // e.g. Right ⌥ + E to type an accent
    }
}
