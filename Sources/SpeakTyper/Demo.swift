import AppKit
import SwiftUI

/// `SpeakTyper --demo` — plays the island through every state with a fake voice, no mic needed.
@MainActor
enum Demo {
    static var isRequested: Bool { CommandLine.arguments.contains("--demo") }

    static func run(_ island: IslandController) {
        let start = Date()
        let at = { (t: TimeInterval, f: @escaping @Sendable @MainActor () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated(f) }
        }

        at(0.5) { island.show(.listening) }
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                guard t < 6.5 else { timer.invalidate(); return }
                // Quiet for the first 1.5s (breathing), then a syllable-ish speech envelope.
                let speech = t < 2 ? 0 : abs(sin(t * 5.3)) * (0.65 + 0.35 * sin(t * 1.7))
                island.model.push(level: Float(speech))
            }
        }
        at(6.5) { island.show(.processing) }
        at(8.3) { island.show(.done(words: 12)) }
        at(9.6) { island.hide() }
        at(10.6) { island.flash("Didn't catch that", symbol: "waveform.slash") }
        at(13.2) { NSApp.terminate(nil) }
    }
}
