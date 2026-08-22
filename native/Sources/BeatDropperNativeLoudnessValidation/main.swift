import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Foundation

@main
struct BeatDropperNativeLoudnessValidation {
    static func main() throws {
        let options = try Options.parse(CommandLine.arguments.dropFirst())
        if options.help {
            print(Options.usage)
            return
        }
        guard let folderPath = options.folderPath else {
            throw ValidationError.message("--folder is required.")
        }
        guard let writeJSONPath = options.writeJSONPath else {
            throw ValidationError.message("--write-json is required.")
        }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL
        let records = analyzeFolder(folderURL)
        let report = NativeLoudnessValidationReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: records.contains { $0.loudness != nil } ? "PASS" : "FAIL",
            records: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let writeURL = URL(fileURLWithPath: writeJSONPath).standardizedFileURL
        try FileManager.default.createDirectory(
            at: writeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: writeURL, options: [.atomic])
    }

    private static func analyzeFolder(_ folderURL: URL) -> [NativeLoudnessValidationRecord] {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { ["mp3", "wav"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                analyzeFile(url)
            }
    }

    private static func analyzeFile(_ url: URL) -> NativeLoudnessValidationRecord {
        do {
            let buffer = try readPCMBuffer(from: url)
            guard let format = AudioFormat(rawValue: url.pathExtension.lowercased()) else {
                throw ValidationError.message("Unsupported audio format.")
            }
            let trackId = url.deletingPathExtension().lastPathComponent
            let analysis = NativeDSPAnalyzer().analyze(
                track: Track(
                    id: trackId,
                    title: trackId,
                    durationSec: buffer.durationSec,
                    format: format
                ),
                buffer: buffer,
                generatedAt: "native-loudness-validation"
            )

            return NativeLoudnessValidationRecord(
                anonymizedName: url.lastPathComponent,
                trackId: trackId,
                durationSec: rounded(buffer.durationSec),
                loudness: analysis.loudness.map {
                    NativeLoudnessValidationLoudness(
                        integratedLUFS: $0.integratedLUFS.map(rounded),
                        truePeakDb: $0.truePeakDb.map(rounded),
                        integratedRMSDb: rounded($0.integratedRMSDb),
                        peakDb: rounded($0.peakDb),
                        loudnessRangeLU: $0.loudnessRangeLU.map(rounded),
                        measurement: $0.measurement,
                        confidence: rounded($0.confidence)
                    )
                },
                stereo: analysis.stereo.map {
                    NativeLoudnessValidationStereo(
                        channelCount: $0.channelCount,
                        stereoWidth: rounded($0.stereoWidth),
                        phaseCorrelation: rounded($0.phaseCorrelation),
                        midSideBalance: rounded($0.midSideBalance),
                        confidence: rounded($0.confidence)
                    )
                },
                warnings: analysis.analysisWarnings.map(\.rawValue),
                error: nil
            )
        } catch {
            return NativeLoudnessValidationRecord(
                anonymizedName: url.lastPathComponent,
                trackId: url.deletingPathExtension().lastPathComponent,
                durationSec: nil,
                loudness: nil,
                stereo: nil,
                warnings: [],
                error: error.localizedDescription
            )
        }
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
            throw ValidationError.message("Could not create a PCM buffer for analysis.")
        }

        try file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        guard frameLength > 0, channelCount > 0, sampleRate > 0 else {
            throw ValidationError.message("The audio file has no readable samples.")
        }
        guard let channelData = buffer.floatChannelData else {
            throw ValidationError.message("The audio file could not be decoded as floating-point PCM.")
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

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}
struct NativeLoudnessValidationReport: Codable {
    var schemaVersion: Int
    var generatedAt: String
    var status: String
    var records: [NativeLoudnessValidationRecord]
}

struct NativeLoudnessValidationRecord: Codable {
    var anonymizedName: String
    var trackId: String
    var durationSec: Double?
    var loudness: NativeLoudnessValidationLoudness?
    var stereo: NativeLoudnessValidationStereo?
    var warnings: [String]
    var error: String?
}

struct NativeLoudnessValidationLoudness: Codable {
    var integratedLUFS: Double?
    var truePeakDb: Double?
    var integratedRMSDb: Double
    var peakDb: Double
    var loudnessRangeLU: Double?
    var measurement: String?
    var confidence: Double
}

struct NativeLoudnessValidationStereo: Codable {
    var channelCount: Int
    var stereoWidth: Double
    var phaseCorrelation: Double
    var midSideBalance: Double
    var confidence: Double
}

struct Options {
    var folderPath: String?
    var writeJSONPath: String?
    var help: Bool = false

    static let usage = """
    Usage: swift run --package-path native BeatDropperNativeLoudnessValidation --folder <anonymized-folder> --write-json <path>

    Analyzes staged local .mp3/.wav files and writes per-file BeatDropper loudness evidence.
    Input files should already be anonymized by the caller.
    """

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        var options = Options()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let arg = arguments[index]
            func readValue(_ name: String) throws -> String {
                let next = arguments.index(after: index)
                guard next < arguments.endIndex else {
                    throw ValidationError.message("\(name) requires a value.")
                }
                index = next
                return arguments[index]
            }

            switch arg {
            case "--help", "-h":
                options.help = true
            case "--folder":
                options.folderPath = try readValue("--folder")
            case "--write-json":
                options.writeJSONPath = try readValue("--write-json")
            default:
                if arg.hasPrefix("--folder=") {
                    options.folderPath = String(arg.dropFirst("--folder=".count))
                } else if arg.hasPrefix("--write-json=") {
                    options.writeJSONPath = String(arg.dropFirst("--write-json=".count))
                } else {
                    throw ValidationError.message("Unknown option: \(arg)")
                }
            }
            index = arguments.index(after: index)
        }
        return options
    }
}

enum ValidationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}
