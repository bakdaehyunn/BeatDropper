import Foundation

public let trackAnalysisSchemaVersion = 5

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

public enum AnalysisWarning: String, Codable, Sendable {
    case bpmUnavailable = "bpm_unavailable"
    case bpmLowConfidence = "bpm_low_confidence"
    case bpmMetadataMismatch = "bpm_metadata_mismatch"
    case beatGridEstimated = "beat_grid_estimated"
    case shortTrack = "short_track"
    case flatEnergy = "flat_energy"
    case analysisUpgradeAvailable = "analysis_upgrade_available"
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

    public init(
        waveformDetail: Double,
        spectralBands: Double,
        transientMarkers: Double,
        beatGrid: Double
    ) {
        self.waveformDetail = waveformDetail
        self.spectralBands = spectralBands
        self.transientMarkers = transientMarkers
        self.beatGrid = beatGrid
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

    public init(
        id: String,
        type: CueCandidateType,
        startSec: Double,
        endSec: Double,
        confidence: Double,
        label: String
    ) {
        self.id = id
        self.type = type
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
        self.label = label
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
        self.analysisConfidence = analysisConfidence
        self.analysisQuality = analysisQuality
        self.analysisWarnings = analysisWarnings
    }
}
