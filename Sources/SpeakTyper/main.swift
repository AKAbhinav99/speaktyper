import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dictation = DictationController()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SpeakTyper")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if Demo.isRequested {
            Demo.run(dictation.island)
            return
        }

        dictation.onStatusChange = { [weak self] in self?.refreshIcon() }
        dictation.start()

        // Ask for Accessibility up front (needed to type into other apps).
        if !TextTyper.isTrusted { TextTyper.requestAccess() }
    }

    private func refreshIcon() {
        let symbol: String
        switch dictation.state {
        case .idle: symbol = "waveform"
        case .listening: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SpeakTyper")
    }

    // Rebuild the menu each time it opens so status is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: dictation.modelStatus, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if dictation.modelStatus.contains("retry") {
            menu.addItem(item("Retry Loading Model", #selector(retryModel)))
        }

        let toggleTitle = dictation.state == .listening ? "Stop & Type" : "Start Dictation"
        let toggle = item("\(toggleTitle)    \(Config.hotKeyLabel)", #selector(toggleDictation))
        menu.addItem(toggle)
        menu.addItem(.separator())

        let space = item("Add Space After Text", #selector(toggleTrailingSpace))
        space.state = Prefs.addTrailingSpace ? .on : .off
        menu.addItem(space)

        let sounds = item("Play Sounds", #selector(toggleSounds))
        sounds.state = Prefs.playSounds ? .on : .off
        menu.addItem(sounds)

        if !TextTyper.isTrusted {
            menu.addItem(.separator())
            menu.addItem(item("⚠︎ Allow Accessibility (needed to type)…", #selector(openAccessibility)))
        }

        menu.addItem(.separator())
        let tip = NSMenuItem(title: "Hold \(Config.hotKeyLabel) to talk · tap for hands-free · Esc cancels", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SpeakTyper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleDictation() { dictation.toggleFromMenu() }
    @objc private func retryModel() { dictation.retryModelLoad() }
    @objc private func toggleTrailingSpace() { Prefs.addTrailingSpace.toggle() }
    @objc private func toggleSounds() { Prefs.playSounds.toggle() }
    @objc private func openAccessibility() {
        TextTyper.requestAccess()
        TextTyper.openAccessibilitySettings()
    }
}

CLI.runIfRequested()

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
