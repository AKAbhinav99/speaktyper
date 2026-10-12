import Carbon.HIToolbox
import FluidAudio
import Foundation

/// Tweak these to change the shortcut or the Parakeet model.
enum Config {
    /// Global shortcut: ⌥ Space.
    /// Tap it to start, tap again to stop — or hold it down and release to stop (push-to-talk).
    static let hotKeyCode = UInt32(kVK_Space)
    static let hotKeyModifiers = UInt32(optionKey)
    static let hotKeyLabel = "⌥Space"

    /// Holding the shortcut longer than this turns the session into push-to-talk.
    static let pushToTalkThreshold: TimeInterval = 0.35

    /// `.v2` = Parakeet TDT 0.6B v2 (English, best recall).
    /// `.v3` / `.ultra` = multilingual (25 European languages).
    static let modelVersion: AsrModelVersion = .v2
    static let modelLabel = "Parakeet TDT 0.6B v2"
}

enum Prefs {
    private static let d = UserDefaults.standard

    static var addTrailingSpace: Bool {
        get { d.object(forKey: "addTrailingSpace") as? Bool ?? true }
        set { d.set(newValue, forKey: "addTrailingSpace") }
    }

    static var playSounds: Bool {
        get { d.object(forKey: "playSounds") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSounds") }
    }
}
