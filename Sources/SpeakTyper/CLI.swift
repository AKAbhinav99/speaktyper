import AVFoundation
import Foundation

/// `SpeakTyper --transcribe <audio file> [--channels N]` — runs a file through the same
/// downmix → resample → Parakeet path the mic uses, prints the text, and exits.
/// `--channels 3` copies the audio into a 3-channel buffer like the MacBook's mic array.
enum CLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])

        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let transcriber = Transcriber()
                let start = Date()
                await transcriber.load { event in
                    if case .progress(let f, let label) = event {
                        FileHandle.standardError.write("\r\(label) \(Int(f * 100))%   ".data(using: .utf8)!)
                    }
                }

                // Feed the file in mic-sized chunks through the recorder's converter.
                let file = try AVAudioFile(forReading: url)
                let channels = args.firstIndex(of: "--channels").flatMap { Int(args[$0 + 1]) } ?? 1
                let micFormat = channels > 2
                    ? AVAudioFormat(
                        standardFormatWithSampleRate: file.processingFormat.sampleRate,
                        channelLayout: AVAudioChannelLayout(
                            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))!)
                    : AVAudioFormat(
                        standardFormatWithSampleRate: file.processingFormat.sampleRate,
                        channels: AVAudioChannelCount(channels))!
                let recorder = AudioRecorder()
                recorder.prepare(inputFormat: micFormat)
                while file.framePosition < file.length {
                    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024)!
                    try file.read(into: buf, frameCount: 1024)
                    let mic = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: buf.frameLength)!
                    mic.frameLength = buf.frameLength
                    for c in 0..<channels {
                        mic.floatChannelData![c].update(from: buf.floatChannelData![0], count: Int(buf.frameLength))
                    }
                    recorder.process(mic)
                }
                let samples = recorder.snapshot()

                let text = try await transcriber.transcribe(samples)
                let loaded = Date().timeIntervalSince(start)
                let t0 = Date()
                _ = try await transcriber.transcribe(samples)
                let warm = Date().timeIntervalSince(t0)
                FileHandle.standardError.write(
                    String(format: "\nmodel ready + first pass: %.1fs · warm pass: %.0f ms for %.1fs audio\n",
                           loaded, warm * 1000, Double(samples.count) / AudioRecorder.sampleRate).data(using: .utf8)!)
                print(text)
            } catch {
                FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
            done.signal()
        }
        done.wait()
        exit(0)
    }
}
