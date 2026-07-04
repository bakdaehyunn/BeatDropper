import AVFoundation
import BeatDropperCore
import Foundation

enum NativeTrackAnalyzer {
    static func analyze(importedTrack: ImportedTrack) throws -> TrackAnalysis {
        let pcmBuffer = try readPCMBuffer(from: importedTrack.url)
        return NativeDSPAnalyzer().analyze(
            track: importedTrack.track,
            buffer: pcmBuffer,
            fileRevision: try currentFileRevision(for: importedTrack.url)
        )
    }

    static func currentFileRevision(for url: URL) throws -> TrackFileRevision {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let sizeBytes = Double(values.fileSize ?? 0)
        let mtimeMs = (values.contentModificationDate ?? Date(timeIntervalSince1970: 0))
            .timeIntervalSince1970 * 1_000
        return TrackFileRevision(sizeBytes: sizeBytes, mtimeMs: mtimeMs)
    }

    private static func readPCMBuffer(from url: URL) throws -> PCMAnalysisBuffer {
        let file = try AVAudioFile(forReading: url)
        let frameCount = min(file.length, AVAudioFramePosition(UInt32.max))
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        else {
            throw NativeTrackAnalyzerError.couldNotCreatePCMBuffer
        }

        try file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        guard frameLength > 0, channelCount > 0, sampleRate > 0 else {
            throw NativeTrackAnalyzerError.emptyAudioBuffer
        }
        guard let channelData = buffer.floatChannelData else {
            throw NativeTrackAnalyzerError.unsupportedPCMFormat
        }

        var channelSamples = Array(
            repeating: Array(repeating: Float(0), count: frameLength),
            count: channelCount
        )
        var samples = Array(repeating: Float(0), count: frameLength)
        for frameIndex in 0..<frameLength {
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                let sample = channelData[channelIndex][frameIndex]
                channelSamples[channelIndex][frameIndex] = sample
                sum += sample
            }
            samples[frameIndex] = sum / Float(channelCount)
        }

        return PCMAnalysisBuffer(
            samples: samples,
            channelSamples: channelSamples,
            sampleRate: sampleRate,
            durationSec: Double(frameLength) / sampleRate
        )
    }

}

enum NativeTrackAnalyzerError: LocalizedError {
    case couldNotCreatePCMBuffer
    case emptyAudioBuffer
    case unsupportedPCMFormat

    var errorDescription: String? {
        switch self {
        case .couldNotCreatePCMBuffer:
            return "Could not create a PCM buffer for analysis."
        case .emptyAudioBuffer:
            return "The selected audio file has no readable samples."
        case .unsupportedPCMFormat:
            return "The selected audio file could not be decoded as floating-point PCM."
        }
    }
}
