import AppKit
import ApplicationServices

/// Types text into whatever app currently has keyboard focus by posting synthetic key events.
enum TextTyper {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt if we aren't trusted yet.
    @discardableResult
    static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func type(_ text: String) async {
        await waitForModifiersReleased()

        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            // Clear modifiers so a still-held ⌥ doesn't turn letters into symbols.
            down.flags = []
            up.flags = []
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 2_500_000)
        }
    }

    /// Fallback when Accessibility isn't granted: put the text on the clipboard.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// In push-to-talk you may still be holding ⌥ when transcription finishes.
    private static func waitForModifiersReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline,
              !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
