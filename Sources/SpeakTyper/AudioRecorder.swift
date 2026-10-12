import Accelerate
import AVFoundation

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone found" }
}

/// Captures the default mic and converts it on the fly to 16 kHz mono Float32 — what Parakeet expects.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with a 0…1 loudness value, ~45×/sec.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var monoFormat: AVAudioFormat?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var peak: Float = 0

    func start() throws {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            peak = 0
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }
        prepare(inputFormat: inputFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns everything recorded plus the loudest level seen.
    func stop() -> (samples: [Float], peak: Float) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { (samples, peak) }
    }

    func prepare(inputFormat: AVAudioFormat) {
        let mono = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)!
        monoFormat = mono
        converter = AVAudioConverter(from: mono, to: targetFormat)
    }

    func snapshot() -> [Float] {
        lock.withLock { samples }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let mono = downmix(buffer) else { return }
        let ratio = targetFormat.sampleRate / mono.format.sampleRate
        let capacity = AVAudioFrameCount(Double(mono.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return mono
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }

        let count = Int(out.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(count))
        // Map roughly -55 dB…-10 dB onto 0…1 so normal speech fills the meter.
        let db = 20 * log10(max(rms, 1e-7))
        let level = min(max((db + 55) / 45, 0), 1)

        lock.withLock {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            peak = max(peak, level)
        }
        onLevel?(level)
    }

    /// Averages all input channels into one. Needed because built-in Mac mics are often
    /// multi-channel arrays (the MacBook Air's is 3-channel), and AVAudioConverter silently
    /// outputs pure zeros when asked to go from 3 channels to mono.
    private func downmix(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let monoFormat, let src = buffer.floatChannelData, buffer.frameLength > 0,
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength)
        else { return nil }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let interleaved = buffer.format.isInterleaved
        mono.frameLength = buffer.frameLength
        let dst = mono.floatChannelData![0]

        if channels == 1 {
            dst.update(from: src[0], count: frames)
            return mono
        }
        vDSP_vclr(dst, 1, vDSP_Length(frames))
        for c in 0..<channels {
            vDSP_vadd(dst, 1, interleaved ? src[0] + c : src[c], interleaved ? channels : 1, dst, 1, vDSP_Length(frames))
        }
        var scale = 1 / Float(channels)
        vDSP_vsmul(dst, 1, &scale, dst, 1, vDSP_Length(frames))
        return mono
    }
}
