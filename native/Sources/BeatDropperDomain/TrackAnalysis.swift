import Foundation

public let trackAnalysisSchemaVersion = 7

public enum TrackAnalysisSource: String, Codable, Sendable {
    case metadata
    case derived
    case external
}

public enum CueCandidateType: String, Codable, Sendable {
    case intro
    case firstDownbeat = "first_downbeat"
    case outro
    case lowEnergyBreak = "low_energy_break"
    case highEnergyDrop = "high_energy_drop"
}

public enum CueCandidateOrigin: String, Codable, Sendable {
    case derived
    case heuristicPlaceholder = "heuristic_placeholder"
    case user
}

public enum AnalysisWarning: String, Codable, Sendable {
    case bpmUnavailable = "bpm_unavailable"
    case bpmLowConfidence = "bpm_low_confidence"
    case bpmMetadataMismatch = "bpm_metadata_mismatch"
    case beatGridEstimated = "beat_grid_estimated"
    case shortTrack = "short_track"
    case flatEnergy = "flat_energy"
    case analysisUpgradeAvailable = "analysis_upgrade_available"
    case keyUnavailable = "key_unavailable"
    case keyLowConfidence = "key_low_confidence"
    case loudnessLowConfidence = "loudness_low_confidence"
    case headroomLow = "headroom_low"
}

public enum MusicalKeyMode: String, Codable, Sendable {
    case major
    case minor
}

public struct MusicalKeyEstimate: Codable, Hashable, Sendable {
    public var tonic: String
    public var mode: MusicalKeyMode
    public var confidence: Double
    public var chromaEnergy: Double

    public init(tonic: String, mode: MusicalKeyMode, confidence: Double, chromaEnergy: Double) {
        self.tonic = tonic
        self.mode = mode
        self.confidence = confidence
        self.chromaEnergy = chromaEnergy
    }
}

public struct LoudnessAnalysis: Codable, Hashable, Sendable {
    public var integratedRMSDb: Double
    public var integratedLUFS: Double?
    public var peakDb: Double
    public var truePeakDb: Double?
    public var headroomDb: Double
    public var crestFactorDb: Double
    public var dynamicRangeDb: Double
    public var loudnessRangeLU: Double?
    public var measurement: String?
    public var confidence: Double

    public init(
        integratedRMSDb: Double,
        integratedLUFS: Double? = nil,
        peakDb: Double,
        truePeakDb: Double? = nil,
        headroomDb: Double,
        crestFactorDb: Double,
        dynamicRangeDb: Double,
        loudnessRangeLU: Double? = nil,
        measurement: String? = nil,
        confidence: Double
    ) {
        self.integratedRMSDb = integratedRMSDb
        self.integratedLUFS = integratedLUFS
        self.peakDb = peakDb
        self.truePeakDb = truePeakDb
        self.headroomDb = headroomDb
        self.crestFactorDb = crestFactorDb
        self.dynamicRangeDb = dynamicRangeDb
        self.loudnessRangeLU = loudnessRangeLU
        self.measurement = measurement
        self.confidence = confidence
    }
}

public struct StereoAnalysis: Codable, Hashable, Sendable {
    public var channelCount: Int
    public var leftPeakDb: Double?
    public var rightPeakDb: Double?
    public var leftRMSDb: Double?
    public var rightRMSDb: Double?
    public var stereoWidth: Double
    public var phaseCorrelation: Double
    public var midSideBalance: Double
    public var confidence: Double

    public init(
        channelCount: Int,
        leftPeakDb: Double? = nil,
        rightPeakDb: Double? = nil,
        leftRMSDb: Double? = nil,
        rightRMSDb: Double? = nil,
        stereoWidth: Double,
        phaseCorrelation: Double,
        midSideBalance: Double,
        confidence: Double
    ) {
        self.channelCount = channelCount
        self.leftPeakDb = leftPeakDb
        self.rightPeakDb = rightPeakDb
        self.leftRMSDb = leftRMSDb
        self.rightRMSDb = rightRMSDb
        self.stereoWidth = stereoWidth
        self.phaseCorrelation = phaseCorrelation
        self.midSideBalance = midSideBalance
        self.confidence = confidence
    }
}

public struct WaveformPeak: Codable, Hashable, Sendable {
    public var timeSec: Double
    public var peak: Double
    public var rms: Double

    public init(timeSec: Double, peak: Double, rms: Double) {
        self.timeSec = timeSec
        self.peak = peak
        self.rms = rms
    }
}

public struct WaveformDetailPoint: Codable, Hashable, Sendable {
    public var timeSec: Double
    public var peak: Double
    public var rms: Double
    public var min: Double
    public var max: Double

    public init(timeSec: Double, peak: Double, rms: Double, min: Double, max: Double) {
        self.timeSec = timeSec
        self.peak = peak
        self.rms = rms
        self.min = min
        self.max = max
    }
}

public struct SpectralBandPoint: Codable, Hashable, Sendable {
    public var timeSec: Double
    public var low: Double
    public var mid: Double
    public var high: Double

    public init(timeSec: Double, low: Double, mid: Double, high: Double) {
        self.timeSec = timeSec
        self.low = low
        self.mid = mid
        self.high = high
    }
}

public struct TransientMarker: Codable, Hashable, Sendable {
    public var index: Int
    public var timeSec: Double
    public var strength: Double

    public init(index: Int, timeSec: Double, strength: Double) {
        self.index = index
        self.timeSec = timeSec
        self.strength = strength
    }
}

public struct AnalysisQuality: Codable, Hashable, Sendable {
    public var waveformDetail: Double
    public var spectralBands: Double
    public var transientMarkers: Double
    public var beatGrid: Double
    public var harmonicKey: Double

    public init(
        waveformDetail: Double,
        spectralBands: Double,
        transientMarkers: Double,
        beatGrid: Double,
        harmonicKey: Double = 0
    ) {
        self.waveformDetail = waveformDetail
        self.spectralBands = spectralBands
        self.transientMarkers = transientMarkers
        self.beatGrid = beatGrid
        self.harmonicKey = harmonicKey
    }

    private enum CodingKeys: String, CodingKey {
        case waveformDetail
        case spectralBands
        case transientMarkers
        case beatGrid
        case harmonicKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.waveformDetail = try container.decode(Double.self, forKey: .waveformDetail)
        self.spectralBands = try container.decode(Double.self, forKey: .spectralBands)
        self.transientMarkers = try container.decode(Double.self, forKey: .transientMarkers)
        self.beatGrid = try container.decode(Double.self, forKey: .beatGrid)
        self.harmonicKey = try container.decodeIfPresent(Double.self, forKey: .harmonicKey) ?? 0
    }
}

public struct TrackFileRevision: Codable, Hashable, Sendable {
    public var sizeBytes: Double
    public var mtimeMs: Double

    public init(sizeBytes: Double, mtimeMs: Double) {
        self.sizeBytes = sizeBytes
        self.mtimeMs = mtimeMs
    }
}

public struct BarMarker: Codable, Hashable, Sendable {
    public var index: Int
    public var startSec: Double
    public var beatIndex: Int

    public init(index: Int, startSec: Double, beatIndex: Int) {
        self.index = index
        self.startSec = startSec
        self.beatIndex = beatIndex
    }
}

public struct PhraseMarker: Codable, Hashable, Sendable {
    public var index: Int
    public var startSec: Double
    public var bars: Int
    public var confidence: Double

    public init(index: Int, startSec: Double, bars: Int, confidence: Double) {
        self.index = index
        self.startSec = startSec
        self.bars = bars
        self.confidence = confidence
    }
}

public struct CueCandidate: Codable, Hashable, Sendable {
    public var id: String
    public var type: CueCandidateType
    public var startSec: Double
    public var endSec: Double
    public var confidence: Double
    public var label: String
    public var origin: CueCandidateOrigin

    public init(
        id: String,
        type: CueCandidateType,
        startSec: Double,
        endSec: Double,
        confidence: Double,
        label: String,
        origin: CueCandidateOrigin = .heuristicPlaceholder
    ) {
        self.id = id
        self.type = type
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
        self.label = label
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case startSec
        case endSec
        case confidence
        case label
        case origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.type = try container.decode(CueCandidateType.self, forKey: .type)
        self.startSec = try container.decode(Double.self, forKey: .startSec)
        self.endSec = try container.decode(Double.self, forKey: .endSec)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.label = try container.decode(String.self, forKey: .label)
        self.origin = try container.decodeIfPresent(CueCandidateOrigin.self, forKey: .origin) ?? .heuristicPlaceholder
    }
}

public struct TrackAnalysis: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var trackId: String
    public var generatedAt: String
    public var source: TrackAnalysisSource
    public var fileRevision: TrackFileRevision?
    public var bpm: Double?
    public var bpmConfidence: Double
    public var beatGridSec: [Double]
    public var downbeatsSec: [Double]
    public var barGrid: [BarMarker]
    public var phraseMarkers: [PhraseMarker]
    public var introCueSec: Double?
    public var outroCueSec: Double?
    public var energyProfile: [Double]
    public var waveformPeaks: [WaveformPeak]
    public var waveformDetail: [WaveformDetailPoint]
    public var spectralBands: [SpectralBandPoint]
    public var transientMarkers: [TransientMarker]
    public var cueCandidates: [CueCandidate]
    public var musicalKey: MusicalKeyEstimate?
    public var loudness: LoudnessAnalysis?
    public var stereo: StereoAnalysis?
    public var analysisConfidence: Double
    public var analysisQuality: AnalysisQuality
    public var analysisWarnings: [AnalysisWarning]

    public init(
        schemaVersion: Int = trackAnalysisSchemaVersion,
        trackId: String,
        generatedAt: String,
        source: TrackAnalysisSource,
        fileRevision: TrackFileRevision? = nil,
        bpm: Double?,
        bpmConfidence: Double,
        beatGridSec: [Double],
        downbeatsSec: [Double],
        barGrid: [BarMarker],
        phraseMarkers: [PhraseMarker],
        introCueSec: Double?,
        outroCueSec: Double?,
        energyProfile: [Double],
        waveformPeaks: [WaveformPeak],
        waveformDetail: [WaveformDetailPoint],
        spectralBands: [SpectralBandPoint],
        transientMarkers: [TransientMarker],
        cueCandidates: [CueCandidate],
        musicalKey: MusicalKeyEstimate? = nil,
        loudness: LoudnessAnalysis? = nil,
        stereo: StereoAnalysis? = nil,
        analysisConfidence: Double,
        analysisQuality: AnalysisQuality,
        analysisWarnings: [AnalysisWarning]
    ) {
        self.schemaVersion = schemaVersion
        self.trackId = trackId
        self.generatedAt = generatedAt
        self.source = source
        self.fileRevision = fileRevision
        self.bpm = bpm
        self.bpmConfidence = bpmConfidence
        self.beatGridSec = beatGridSec
        self.downbeatsSec = downbeatsSec
        self.barGrid = barGrid
        self.phraseMarkers = phraseMarkers
        self.introCueSec = introCueSec
        self.outroCueSec = outroCueSec
        self.energyProfile = energyProfile
        self.waveformPeaks = waveformPeaks
        self.waveformDetail = waveformDetail
        self.spectralBands = spectralBands
        self.transientMarkers = transientMarkers
        self.cueCandidates = cueCandidates
        self.musicalKey = musicalKey
        self.loudness = loudness
        self.stereo = stereo
        self.analysisConfidence = analysisConfidence
        self.analysisQuality = analysisQuality
        self.analysisWarnings = analysisWarnings
    }
}
