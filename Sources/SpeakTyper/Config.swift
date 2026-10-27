import FluidAudio
import Foundation

/// Tweak these to change the shortcut or the Parakeet model.
enum Config {
    /// Trigger: the Right Option key on its own (see TriggerKey.swift).
    /// Hold it to talk and release to type, or tap it once for hands-free and tap again to stop.
    static let hotKeyLabel = "Right ⌥"

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

    static var launchAtLogin: Bool {
        get { d.object(forKey: "launchAtLogin") as? Bool ?? true }
        set { d.set(newValue, forKey: "launchAtLogin") }
    }

    static var playSounds: Bool {
        get { d.object(forKey: "playSounds") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSounds") }
    }
}
