import Foundation
import ServiceManagement

/// Starts SpeakTyper when you log in (shows up in System Settings → General → Login Items).
enum LoginItem {
    /// Only the installed copy is registered — not a build folder that may move or be deleted.
    static var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Makes the system login item match the "Launch at Login" preference.
    static func sync() {
        guard isInstalled else { return }
        do {
            if Prefs.launchAtLogin, status != .enabled {
                try SMAppService.mainApp.register()
            } else if !Prefs.launchAtLogin, status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SpeakTyper: couldn't update login item — \(error.localizedDescription)")
        }
        NSLog("SpeakTyper: launch at login status = \(status.rawValue) (0 off, 1 on, 2 needs approval)")
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
