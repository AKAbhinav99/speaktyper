import FluidAudio
import Foundation

/// Owns the Parakeet model (via FluidAudio, running on the Apple Neural Engine).
actor Transcriber {
    enum LoadEvent: Sendable {
        case progress(Double, String)
        case ready
        case failed(String)
    }

    private var loadTask: Task<AsrManager, Error>?
    private(set) var isReady = false

    static var modelsAreCached: Bool {
        AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: Config.modelVersion), version: Config.modelVersion)
    }

    /// Downloads (first run only), compiles and warms up the model.
    func load(onEvent: @escaping @Sendable (LoadEvent) -> Void) {
        guard loadTask == nil else { return }
        let smoother = ProgressSmoother()
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(
                version: Config.modelVersion,
                progressHandler: { p in
                    let label: String
                    switch p.phase {
                    case .listing: label = "Finding Parakeet…"
                    case .downloading: label = "Downloading Parakeet…"
                    case .compiling: label = "Optimizing for Neural Engine…"
                    }
                    onEvent(.progress(smoother.overall(p.fractionCompleted), label))
                })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)

            // Warm-up pass so the first real dictation is instant.
            var state = TdtDecoderState.make()
            _ = try? await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &state)
            return manager
        }
        loadTask = task

        Task {
            do {
                _ = try await task.value
                self.markReady()
                onEvent(.ready)
            } catch {
                self.resetAfterFailure()
                onEvent(.failed(error.localizedDescription))
            }
        }
    }

    private func markReady() { isReady = true }
    private func resetAfterFailure() { loadTask = nil }

    /// Transcribes 16 kHz mono samples. Waits for the model if it's still loading.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let loadTask else { throw TranscriberError.notLoaded }
        let manager = try await loadTask.value

        // Pad very short clips (and give the tail a little silence) so the last word isn't clipped.
        var audio = samples
        audio.append(contentsOf: [Float](repeating: 0, count: 4_000))
        if audio.count < 16_000 {
            audio.append(contentsOf: [Float](repeating: 0, count: 16_000 - audio.count))
        }

        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(audio, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriberError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Parakeet model isn't loaded" }
}

/// FluidAudio reports 0→100% separately for each Parakeet sub-model (preprocessor,
/// encoder, decoder, joint). Stitch those into one bar that only moves forward.
private final class ProgressSmoother: @unchecked Sendable {
    private let lock = NSLock()
    private var finishedParts = 0
    private var lastFraction = 0.0
    private var shown = 0.0
    private let expectedParts = 4.0

    func overall(_ fraction: Double) -> Double {
        lock.withLock {
            if fraction + 0.05 < lastFraction { finishedParts += 1 }
            lastFraction = fraction
            shown = max(shown, min(0.99, (Double(finishedParts) + fraction) / expectedParts))
            return shown
        }
    }
}
