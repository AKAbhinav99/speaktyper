import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

/// The state machine: idle → listening → transcribing → (typing) → idle.
@MainActor
final class DictationController {
    enum State { case idle, listening, transcribing }

    private(set) var state = State.idle
    private(set) var modelStatus = "Loading Parakeet…"
    var onStatusChange: (() -> Void)?

    let island = IslandController()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()

    private var hotKey: HotKey?
    private var escapeKey: HotKey?
    private var hotKeyIsDown = false
    private var pressStartedAt: Date?
    private var session = 0
    private var showLoadingInIsland = false
    private var smoothedLevel: Float = 0
    private var lastLevelPush = Date.distantPast

    init() {
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.receive(level: level) }
        }
    }

    func start() {
        hotKey = HotKey(keyCode: Config.hotKeyCode, modifiers: Config.hotKeyModifiers) { [weak self] pressed in
            MainActor.assumeIsolated { self?.hotKeyChanged(pressed: pressed) }
        }
        loadModel()

        if hotKey?.isRegistered == false {
            island.flash("\(Config.hotKeyLabel) is taken by another app", symbol: "keyboard", for: 3)
        }
    }

    // MARK: - Model

    private func loadModel() {
        // Only show the download in the island on first run (it can take a minute).
        showLoadingInIsland = !Transcriber.modelsAreCached
        if showLoadingInIsland {
            island.show(.loading(progress: 0, label: "Downloading Parakeet…"))
        }
        Task {
            await transcriber.load { [weak self] event in
                Task { @MainActor in self?.handleLoadEvent(event) }
            }
        }
    }

    private func handleLoadEvent(_ event: Transcriber.LoadEvent) {
        switch event {
        case .progress(let fraction, let label):
            modelStatus = "\(label) \(Int(fraction * 100))%"
            if showLoadingInIsland, state == .idle {
                island.show(.loading(progress: fraction, label: label))
            }
        case .ready:
            modelStatus = "\(Config.modelLabel) · Ready"
            if showLoadingInIsland, state == .idle {
                island.flash("Ready — hold \(Config.hotKeyLabel) and talk", symbol: "sparkles", for: 2.5)
            }
            showLoadingInIsland = false
        case .failed(let message):
            modelStatus = "Model failed to load — click to retry"
            if state == .idle {
                island.flash("Couldn't load Parakeet: \(message)", symbol: "exclamationmark.triangle", for: 4)
            }
        }
        onStatusChange?()
    }

    func retryModelLoad() {
        loadModel()
    }

    // MARK: - Hotkey

    private func hotKeyChanged(pressed: Bool) {
        if pressed {
            guard !hotKeyIsDown else { return }  // ignore key-repeat
            hotKeyIsDown = true
            switch state {
            case .idle:
                pressStartedAt = Date()
                beginListening()
            case .listening:
                pressStartedAt = nil
                finishListening()
            case .transcribing:
                break
            }
        } else {
            hotKeyIsDown = false
            if state == .listening, let started = pressStartedAt {
                // Held → push-to-talk, release stops. A quick tap keeps listening until tapped again.
                if Date().timeIntervalSince(started) > Config.pushToTalkThreshold {
                    finishListening()
                }
            }
            pressStartedAt = nil
        }
    }

    func toggleFromMenu() {
        switch state {
        case .idle: beginListening()
        case .listening: finishListening()
        case .transcribing: break
        }
    }

    // MARK: - Session

    private func beginListening() {
        guard state == .idle else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            pressStartedAt = nil
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted { self.beginListening() } else { self.showMicDenied() }
                }
            }
            return
        default:
            showMicDenied()
            return
        }

        do {
            try recorder.start()
        } catch {
            island.flash("Mic error: \(error.localizedDescription)", symbol: "mic.slash", for: 3)
            return
        }

        session += 1
        state = .listening
        smoothedLevel = 0
        island.model.resetLevels()
        island.show(.listening)
        play("Tink")
        onStatusChange?()

        escapeKey = HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.cancelListening() }
        }
    }

    private func receive(level: Float) {
        guard state == .listening else { return }
        // Fast attack, slower release — feels like a real meter.
        smoothedLevel = level > smoothedLevel
            ? smoothedLevel * 0.3 + level * 0.7
            : smoothedLevel * 0.75 + level * 0.25
        let now = Date()
        if now.timeIntervalSince(lastLevelPush) >= 0.04 {
            lastLevelPush = now
            island.model.push(level: smoothedLevel)
        }
    }

    private func finishListening() {
        guard state == .listening else { return }
        escapeKey = nil
        let (samples, peak) = recorder.stop()
        state = .transcribing
        island.show(.processing)
        onStatusChange?()

        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        let thisSession = session
        Task {
            defer {
                if self.session == thisSession {
                    self.state = .idle
                    self.onStatusChange?()
                }
            }

            // Nothing (or only silence) recorded.
            guard seconds > 0.25, peak > 0.06 else {
                NSLog("SpeakTyper: skipped — %.2fs audio, peak %.3f", seconds, peak)
                island.flash("Didn't catch that", symbol: "waveform.slash")
                return
            }

            let text: String
            do {
                text = try await transcriber.transcribe(samples)
            } catch {
                NSLog("SpeakTyper: transcription error — \(error)")
                island.flash("Transcription failed", symbol: "exclamationmark.triangle", for: 3)
                return
            }
            NSLog("SpeakTyper: %.2fs audio, peak %.3f → %d chars", seconds, peak, text.count)
            guard !text.isEmpty else {
                island.flash("Didn't catch that", symbol: "waveform.slash")
                return
            }

            let output = Prefs.addTrailingSpace ? text + " " : text
            guard TextTyper.isTrusted else {
                TextTyper.copyToClipboard(output)
                TextTyper.requestAccess()
                island.flash("Copied — allow Accessibility so I can type for you", symbol: "doc.on.clipboard", for: 3.5)
                return
            }

            island.show(.done(words: text.split(whereSeparator: \.isWhitespace).count))
            await TextTyper.type(output)
            island.hide(after: 0.55)
        }
    }

    private func cancelListening() {
        guard state == .listening else { return }
        escapeKey = nil
        _ = recorder.stop()
        session += 1
        state = .idle
        island.hide()
        onStatusChange?()
    }

    // MARK: - Helpers

    private func showMicDenied() {
        island.flash("Microphone access is off — enable it in System Settings", symbol: "mic.slash", for: 3.5)
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func play(_ name: String) {
        guard Prefs.playSounds, let sound = NSSound(named: name) else { return }
        sound.volume = 0.25
        sound.play()
    }
}
