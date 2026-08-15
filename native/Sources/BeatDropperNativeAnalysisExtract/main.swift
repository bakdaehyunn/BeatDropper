import AVFoundation
import BeatDropperCore
import Foundation

@main
struct BeatDropperNativeAnalysisExtract {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            throw ExtractError.message("Usage: BeatDropperNativeAnalysisExtract <audio-file> <output-json>")
        }
        let inputURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let buffer = try readPCMBuffer(from: inputURL)
        let trackId = "private-\(stableHash(inputURL.path))"
        let track = Track(
            id: trackId,
            title: "Private calibration source",
            durationSec: buffer.durationSec,
            format: inputURL.pathExtension.lowercased() == "mp3" ? .mp3 : .wav
        )
        let analysis = NativeDSPAnalyzer().analyze(track: track, buffer: buffer)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(analysis).write(to: outputURL, options: .atomic)
        print("Wrote anonymized analysis to \(outputURL.path)")
    }

    private static func readPCMBuffer(from url: URL) throws -> PCMAnalysisBuffer {
        let file = try AVAudioFile(forReading: url)
        let frameCount = min(file.length, AVAudioFramePosition(UInt32.max))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw ExtractError.message("Could not create a PCM buffer for analysis.")
        }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        guard frameLength > 0, channelCount > 0, sampleRate > 0, let channelData = buffer.floatChannelData else {
            throw ExtractError.message("The audio file has no readable floating-point PCM samples.")
        }
        var channels = Array(repeating: Array(repeating: Float(0), count: frameLength), count: channelCount)
        var mono = Array(repeating: Float(0), count: frameLength)
        for frame in 0..<frameLength {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                channels[channel][frame] = sample
                sum += sample
            }
            mono[frame] = sum / Float(channelCount)
        }
        return PCMAnalysisBuffer(
            samples: mono,
            channelSamples: channels,
            sampleRate: sampleRate,
            durationSec: Double(frameLength) / sampleRate
        )
    }

    private static func stableHash(_ value: String) -> String {
        value.utf8.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, byte in
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }.description
    }
}

enum ExtractError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
