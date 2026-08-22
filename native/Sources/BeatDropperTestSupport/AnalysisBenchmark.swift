import Foundation
import BeatDropperDomain

public enum AnalysisBenchmarkGrade: String, Codable, Sendable {
    case pass
    case warn
    case fail
}

public enum AnalysisBenchmarkFixtureKind: String, Codable, Sendable {
    case synthetic
    case snapshot
    case realAudio = "real_audio"
}

public struct AnalysisBenchmarkExpectation: Codable, Hashable, Sendable {
    public var bpm: Double?
    public var firstDownbeatSec: Double?
    public var downbeatSec: [Double]?
    public var outroCueSec: Double?
    public var barGridSec: [Double]?
    public var phraseBoundarySec: [Double]?
    public var plannerReady: Bool?
    public var musicalKey: AnalysisBenchmarkKeyExpectation?
    public var loudness: AnalysisBenchmarkLoudnessExpectation?
    public var stereo: AnalysisBenchmarkStereoExpectation?
    public var cueCandidates: [AnalysisBenchmarkCueExpectation]?
    public var mixReadiness: AnalysisBenchmarkMixReadinessExpectation?

    public init(
        bpm: Double? = nil,
        firstDownbeatSec: Double? = nil,
        downbeatSec: [Double]? = nil,
        outroCueSec: Double? = nil,
        barGridSec: [Double]? = nil,
        phraseBoundarySec: [Double]? = nil,
        plannerReady: Bool? = nil,
        musicalKey: AnalysisBenchmarkKeyExpectation? = nil,
        loudness: AnalysisBenchmarkLoudnessExpectation? = nil,
        stereo: AnalysisBenchmarkStereoExpectation? = nil,
        cueCandidates: [AnalysisBenchmarkCueExpectation]? = nil,
        mixReadiness: AnalysisBenchmarkMixReadinessExpectation? = nil
    ) {
        self.bpm = bpm
        self.firstDownbeatSec = firstDownbeatSec
        self.downbeatSec = downbeatSec
        self.outroCueSec = outroCueSec
        self.barGridSec = barGridSec
        self.phraseBoundarySec = phraseBoundarySec
        self.plannerReady = plannerReady
        self.musicalKey = musicalKey
        self.loudness = loudness
        self.stereo = stereo
        self.cueCandidates = cueCandidates
        self.mixReadiness = mixReadiness
    }
}

public struct AnalysisBenchmarkKeyExpectation: Codable, Hashable, Sendable {
    public var tonic: String?
    public var mode: MusicalKeyMode?
    public var minConfidence: Double?

    public init(tonic: String? = nil, mode: MusicalKeyMode? = nil, minConfidence: Double? = nil) {
        self.tonic = tonic
        self.mode = mode
        self.minConfidence = minConfidence
    }
}

public struct AnalysisBenchmarkLoudnessExpectation: Codable, Hashable, Sendable {
    public var integratedRMSDb: Double?
    public var integratedLUFS: Double?
    public var peakDb: Double?
    public var truePeakDb: Double?
    public var minHeadroomDb: Double?
    public var minConfidence: Double?

    public init(
        integratedRMSDb: Double? = nil,
        integratedLUFS: Double? = nil,
        peakDb: Double? = nil,
        truePeakDb: Double? = nil,
        minHeadroomDb: Double? = nil,
        minConfidence: Double? = nil
    ) {
        self.integratedRMSDb = integratedRMSDb
        self.integratedLUFS = integratedLUFS
        self.peakDb = peakDb
        self.truePeakDb = truePeakDb
        self.minHeadroomDb = minHeadroomDb
        self.minConfidence = minConfidence
    }
}

public struct AnalysisBenchmarkCueExpectation: Codable, Hashable, Sendable {
    public var type: CueCandidateType
    public var startSec: Double
    public var minConfidence: Double?
    public var origin: CueCandidateOrigin?

    public init(type: CueCandidateType, startSec: Double, minConfidence: Double? = nil, origin: CueCandidateOrigin? = nil) {
        self.type = type
        self.startSec = startSec
        self.minConfidence = minConfidence
        self.origin = origin
    }
}

public struct AnalysisBenchmarkMixReadinessExpectation: Codable, Hashable, Sendable {
    public var minAnalysisConfidence: Double?
    public var minHarmonicKeyQuality: Double?
    public var minLoudnessConfidence: Double?
    public var forbiddenWarnings: [AnalysisWarning]?

    public init(
        minAnalysisConfidence: Double? = nil,
        minHarmonicKeyQuality: Double? = nil,
        minLoudnessConfidence: Double? = nil,
        forbiddenWarnings: [AnalysisWarning]? = nil
    ) {
        self.minAnalysisConfidence = minAnalysisConfidence
        self.minHarmonicKeyQuality = minHarmonicKeyQuality
        self.minLoudnessConfidence = minLoudnessConfidence
        self.forbiddenWarnings = forbiddenWarnings
    }
}

public struct AnalysisBenchmarkStereoExpectation: Codable, Hashable, Sendable {
    public var channelCount: Int?
    public var minStereoWidth: Double?
    public var maxStereoWidth: Double?
    public var minPhaseCorrelation: Double?
    public var maxMidSideBalance: Double?
    public var minConfidence: Double?

    public init(
        channelCount: Int? = nil,
        minStereoWidth: Double? = nil,
        maxStereoWidth: Double? = nil,
        minPhaseCorrelation: Double? = nil,
        maxMidSideBalance: Double? = nil,
        minConfidence: Double? = nil
    ) {
        self.channelCount = channelCount
        self.minStereoWidth = minStereoWidth
        self.maxStereoWidth = maxStereoWidth
        self.minPhaseCorrelation = minPhaseCorrelation
        self.maxMidSideBalance = maxMidSideBalance
        self.minConfidence = minConfidence
    }
}

public struct AnalysisBenchmarkThresholds: Codable, Hashable, Sendable {
    public var bpmWarnError: Double
    public var bpmFailError: Double
    public var cueWarnDistanceSec: Double
    public var cueFailDistanceSec: Double
    public var downbeatWarnAverageDistanceSec: Double
    public var downbeatFailAverageDistanceSec: Double
    public var downbeatWarnMaxDistanceSec: Double
    public var downbeatFailMaxDistanceSec: Double
    public var barWarnAverageDriftSec: Double
    public var barFailAverageDriftSec: Double
    public var barWarnMaxDriftSec: Double
    public var barFailMaxDriftSec: Double
    public var phraseWarnAverageDistanceSec: Double
    public var phraseFailAverageDistanceSec: Double
    public var keyWarnConfidence: Double
    public var keyFailConfidence: Double
    public var loudnessWarnDeltaDb: Double
    public var loudnessFailDeltaDb: Double
    public var headroomWarnDb: Double
    public var headroomFailDb: Double
    public var cueWarnConfidence: Double
    public var cueFailConfidence: Double

    public init(
        bpmWarnError: Double = 1.5,
        bpmFailError: Double = 4,
        cueWarnDistanceSec: Double = 1,
        cueFailDistanceSec: Double = 4,
        downbeatWarnAverageDistanceSec: Double = 0.08,
        downbeatFailAverageDistanceSec: Double = 0.25,
        downbeatWarnMaxDistanceSec: Double = 0.15,
        downbeatFailMaxDistanceSec: Double = 0.5,
        barWarnAverageDriftSec: Double = 0.18,
        barFailAverageDriftSec: Double = 0.55,
        barWarnMaxDriftSec: Double = 0.45,
        barFailMaxDriftSec: Double = 1.25,
        phraseWarnAverageDistanceSec: Double = 2,
        phraseFailAverageDistanceSec: Double = 8,
        keyWarnConfidence: Double = 0.35,
        keyFailConfidence: Double = 0.24,
        loudnessWarnDeltaDb: Double = 1.5,
        loudnessFailDeltaDb: Double = 3,
        headroomWarnDb: Double = 1,
        headroomFailDb: Double = 0.2,
        cueWarnConfidence: Double = 0.55,
        cueFailConfidence: Double = 0.35
    ) {
        self.bpmWarnError = bpmWarnError
        self.bpmFailError = bpmFailError
        self.cueWarnDistanceSec = cueWarnDistanceSec
        self.cueFailDistanceSec = cueFailDistanceSec
        self.downbeatWarnAverageDistanceSec = downbeatWarnAverageDistanceSec
        self.downbeatFailAverageDistanceSec = downbeatFailAverageDistanceSec
        self.downbeatWarnMaxDistanceSec = downbeatWarnMaxDistanceSec
        self.downbeatFailMaxDistanceSec = downbeatFailMaxDistanceSec
        self.barWarnAverageDriftSec = barWarnAverageDriftSec
        self.barFailAverageDriftSec = barFailAverageDriftSec
        self.barWarnMaxDriftSec = barWarnMaxDriftSec
        self.barFailMaxDriftSec = barFailMaxDriftSec
        self.phraseWarnAverageDistanceSec = phraseWarnAverageDistanceSec
        self.phraseFailAverageDistanceSec = phraseFailAverageDistanceSec
        self.keyWarnConfidence = keyWarnConfidence
        self.keyFailConfidence = keyFailConfidence
        self.loudnessWarnDeltaDb = loudnessWarnDeltaDb
        self.loudnessFailDeltaDb = loudnessFailDeltaDb
        self.headroomWarnDb = headroomWarnDb
        self.headroomFailDb = headroomFailDb
        self.cueWarnConfidence = cueWarnConfidence
        self.cueFailConfidence = cueFailConfidence
    }
}

public struct AnalysisBenchmarkIssue: Codable, Hashable, Sendable {
    public var code: String
    public var grade: AnalysisBenchmarkGrade
    public var message: String

    public init(code: String, grade: AnalysisBenchmarkGrade, message: String) {
        self.code = code
        self.grade = grade
        self.message = message
    }
}

public struct AnalysisBenchmarkDistanceMetric: Codable, Hashable, Sendable {
    public var expectedSec: Double
    public var actualSec: Double?
    public var distanceSec: Double?

    public init(expectedSec: Double, actualSec: Double?, distanceSec: Double?) {
        self.expectedSec = expectedSec
        self.actualSec = actualSec
        self.distanceSec = distanceSec
    }
}

public struct AnalysisBenchmarkSeriesMetric: Codable, Hashable, Sendable {
    public var checkedCount: Int
    public var averageDistanceSec: Double?
    public var maxDistanceSec: Double?

    public init(checkedCount: Int, averageDistanceSec: Double?, maxDistanceSec: Double?) {
        self.checkedCount = checkedCount
        self.averageDistanceSec = averageDistanceSec
        self.maxDistanceSec = maxDistanceSec
    }
}

public struct AnalysisBenchmarkKeyMetric: Codable, Hashable, Sendable {
    public var expectedTonic: String?
    public var expectedMode: MusicalKeyMode?
    public var actualTonic: String?
    public var actualMode: MusicalKeyMode?
    public var confidence: Double?
    public var matched: Bool?
}

public struct AnalysisBenchmarkLoudnessMetric: Codable, Hashable, Sendable {
    public var expectedIntegratedRMSDb: Double?
    public var actualIntegratedRMSDb: Double?
    public var integratedRMSDeltaDb: Double?
    public var expectedIntegratedLUFS: Double?
    public var actualIntegratedLUFS: Double?
    public var integratedLUFSDelta: Double?
    public var expectedPeakDb: Double?
    public var actualPeakDb: Double?
    public var peakDeltaDb: Double?
    public var expectedTruePeakDb: Double?
    public var actualTruePeakDb: Double?
    public var truePeakDeltaDb: Double?
    public var headroomDb: Double?
    public var loudnessRangeLU: Double?
    public var measurement: String?
    public var confidence: Double?
}

public struct AnalysisBenchmarkGroundTruthLabels: Codable, Hashable, Sendable {
    public var schemaVersion: Int?
    public var reviewedBy: String?
    public var reviewedAt: String?
    public var notes: String?
    public var expected: AnalysisBenchmarkExpectation

    public init(
        schemaVersion: Int? = nil,
        reviewedBy: String? = nil,
        reviewedAt: String? = nil,
        notes: String? = nil,
        expected: AnalysisBenchmarkExpectation
    ) {
        self.schemaVersion = schemaVersion
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.notes = notes
        self.expected = expected
    }
}

public struct AnalysisBenchmarkCueMetric: Codable, Hashable, Sendable {
    public var type: CueCandidateType
    public var expectedSec: Double
    public var actualSec: Double?
    public var distanceSec: Double?
    public var confidence: Double?
    public var origin: CueCandidateOrigin?
}

public struct AnalysisBenchmarkMixReadinessMetric: Codable, Hashable, Sendable {
    public var analysisConfidence: Double
    public var harmonicKeyQuality: Double
    public var loudnessConfidence: Double?
    public var forbiddenWarningsPresent: [AnalysisWarning]
}

public struct AnalysisBenchmarkStereoMetric: Codable, Hashable, Sendable {
    public var expectedChannelCount: Int?
    public var actualChannelCount: Int?
    public var stereoWidth: Double?
    public var phaseCorrelation: Double?
    public var midSideBalance: Double?
    public var confidence: Double?
}

public struct AnalysisBenchmarkResult: Codable, Hashable, Sendable {
    public var grade: AnalysisBenchmarkGrade
    public var score: Double
    public var issues: [AnalysisBenchmarkIssue]
    public var bpmError: Double?
    public var firstDownbeat: AnalysisBenchmarkDistanceMetric?
    public var downbeats: AnalysisBenchmarkSeriesMetric
    public var outro: AnalysisBenchmarkDistanceMetric?
    public var barGrid: AnalysisBenchmarkSeriesMetric
    public var phraseBoundaries: AnalysisBenchmarkSeriesMetric
    public var plannerReadyMatch: Bool?
    public var musicalKey: AnalysisBenchmarkKeyMetric?
    public var loudness: AnalysisBenchmarkLoudnessMetric?
    public var stereo: AnalysisBenchmarkStereoMetric?
    public var cueCandidates: [AnalysisBenchmarkCueMetric]
    public var mixReadiness: AnalysisBenchmarkMixReadinessMetric?

    public init(
        grade: AnalysisBenchmarkGrade,
        score: Double,
        issues: [AnalysisBenchmarkIssue],
        bpmError: Double?,
        firstDownbeat: AnalysisBenchmarkDistanceMetric?,
        downbeats: AnalysisBenchmarkSeriesMetric = AnalysisBenchmarkSeriesMetric(checkedCount: 0, averageDistanceSec: nil, maxDistanceSec: nil),
        outro: AnalysisBenchmarkDistanceMetric?,
        barGrid: AnalysisBenchmarkSeriesMetric,
        phraseBoundaries: AnalysisBenchmarkSeriesMetric,
        plannerReadyMatch: Bool?,
        musicalKey: AnalysisBenchmarkKeyMetric? = nil,
        loudness: AnalysisBenchmarkLoudnessMetric? = nil,
        stereo: AnalysisBenchmarkStereoMetric? = nil,
        cueCandidates: [AnalysisBenchmarkCueMetric] = [],
        mixReadiness: AnalysisBenchmarkMixReadinessMetric? = nil
    ) {
        self.grade = grade
        self.score = score
        self.issues = issues
        self.bpmError = bpmError
        self.firstDownbeat = firstDownbeat
        self.downbeats = downbeats
        self.outro = outro
        self.barGrid = barGrid
        self.phraseBoundaries = phraseBoundaries
        self.plannerReadyMatch = plannerReadyMatch
        self.musicalKey = musicalKey
        self.loudness = loudness
        self.stereo = stereo
        self.cueCandidates = cueCandidates
        self.mixReadiness = mixReadiness
    }
}

public struct AnalysisBenchmarkFixtureResult: Codable, Hashable, Sendable {
    public var fixtureId: String
    public var title: String
    public var trackId: String
    public var kind: AnalysisBenchmarkFixtureKind
    public var tags: [String]
    public var expectedGrade: AnalysisBenchmarkGrade?
    public var result: AnalysisBenchmarkResult

    public init(
        fixtureId: String,
        title: String,
        trackId: String,
        kind: AnalysisBenchmarkFixtureKind,
        tags: [String],
        expectedGrade: AnalysisBenchmarkGrade?,
        result: AnalysisBenchmarkResult
    ) {
        self.fixtureId = fixtureId
        self.title = title
        self.trackId = trackId
        self.kind = kind
        self.tags = tags
        self.expectedGrade = expectedGrade
        self.result = result
    }
}

public struct AnalysisBenchmarkKindSummary: Codable, Hashable, Sendable {
    public var kind: AnalysisBenchmarkFixtureKind
    public var grade: AnalysisBenchmarkGrade
    public var score: Double
    public var total: Int
    public var passed: Int
    public var warned: Int
    public var failed: Int
}

public struct AnalysisBenchmarkSuiteResult: Codable, Hashable, Sendable {
    public var grade: AnalysisBenchmarkGrade
    public var score: Double
    public var passed: Int
    public var warned: Int
    public var failed: Int
    public var byKind: [AnalysisBenchmarkKindSummary]
    public var results: [AnalysisBenchmarkFixtureResult]
}

public struct AnalysisBenchmarkFixture: Decodable, Sendable {
    public var id: String
    public var title: String
    public var kind: AnalysisBenchmarkFixtureKind?
    public var tags: [String]?
    public var expectedGrade: AnalysisBenchmarkGrade?
    public var corpus: AnalysisBenchmarkCorpusMetadata?
    public var expected: AnalysisBenchmarkExpectation
    public var groundTruthLabels: AnalysisBenchmarkGroundTruthLabels?
    public var analysis: AnalysisBenchmarkTrackAnalysisSnapshot
    public var thresholds: AnalysisBenchmarkThresholds?

    public init(
        id: String,
        title: String,
        kind: AnalysisBenchmarkFixtureKind? = nil,
        tags: [String]? = nil,
        expectedGrade: AnalysisBenchmarkGrade? = nil,
        corpus: AnalysisBenchmarkCorpusMetadata? = nil,
        expected: AnalysisBenchmarkExpectation,
        groundTruthLabels: AnalysisBenchmarkGroundTruthLabels? = nil,
        analysis: AnalysisBenchmarkTrackAnalysisSnapshot,
        thresholds: AnalysisBenchmarkThresholds? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.tags = tags
        self.expectedGrade = expectedGrade
        self.corpus = corpus
        self.expected = expected
        self.groundTruthLabels = groundTruthLabels
        self.analysis = analysis
        self.thresholds = thresholds
    }
}

public struct AnalysisBenchmarkTrackAnalysisSnapshot: Decodable, Sendable {
    public var trackId: String?
    public var source: TrackAnalysisSource?
    public var bpm: Double?
    public var bpmConfidence: Double?
    public var beatGridSec: [Double]?
    public var downbeatsSec: [Double]?
    public var barGrid: [BarMarker]?
    public var phraseMarkers: [PhraseMarker]?
    public var introCueSec: Double?
    public var outroCueSec: Double?
    public var energyProfile: [Double]?
    public var waveformPeaks: [WaveformPeak]?
    public var waveformDetail: [WaveformDetailPoint]?
    public var spectralBands: [SpectralBandPoint]?
    public var transientMarkers: [TransientMarker]?
    public var cueCandidates: [CueCandidate]?
    public var musicalKey: MusicalKeyEstimate?
    public var loudness: LoudnessAnalysis?
    public var stereo: StereoAnalysis?
    public var analysisConfidence: Double?
    public var analysisQuality: AnalysisQuality?
    public var analysisWarnings: [AnalysisWarning]?

    public init(
        trackId: String? = nil,
        source: TrackAnalysisSource? = nil,
        bpm: Double? = nil,
        bpmConfidence: Double? = nil,
        beatGridSec: [Double]? = nil,
        downbeatsSec: [Double]? = nil,
        barGrid: [BarMarker]? = nil,
        phraseMarkers: [PhraseMarker]? = nil,
        introCueSec: Double? = nil,
        outroCueSec: Double? = nil,
        energyProfile: [Double]? = nil,
        waveformPeaks: [WaveformPeak]? = nil,
        waveformDetail: [WaveformDetailPoint]? = nil,
        spectralBands: [SpectralBandPoint]? = nil,
        transientMarkers: [TransientMarker]? = nil,
        cueCandidates: [CueCandidate]? = nil,
        musicalKey: MusicalKeyEstimate? = nil,
        loudness: LoudnessAnalysis? = nil,
        stereo: StereoAnalysis? = nil,
        analysisConfidence: Double? = nil,
        analysisQuality: AnalysisQuality? = nil,
        analysisWarnings: [AnalysisWarning]? = nil
    ) {
        self.trackId = trackId
        self.source = source
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

    public func toTrackAnalysis(trackId fallbackTrackId: String) -> TrackAnalysis {
        TrackAnalysis(
            trackId: trackId?.isEmpty == false ? trackId! : fallbackTrackId,
            generatedAt: "benchmark-fixture",
            source: source ?? .derived,
            bpm: bpm,
            bpmConfidence: bpmConfidence ?? 0,
            beatGridSec: beatGridSec ?? [],
            downbeatsSec: downbeatsSec ?? [],
            barGrid: barGrid ?? [],
            phraseMarkers: phraseMarkers ?? [],
            introCueSec: introCueSec,
            outroCueSec: outroCueSec,
            energyProfile: energyProfile ?? [],
            waveformPeaks: waveformPeaks ?? [],
            waveformDetail: waveformDetail ?? [],
            spectralBands: spectralBands ?? [],
            transientMarkers: transientMarkers ?? [],
            cueCandidates: cueCandidates ?? [],
            musicalKey: musicalKey,
            loudness: loudness,
            stereo: stereo,
            analysisConfidence: analysisConfidence ?? 0,
            analysisQuality: analysisQuality ?? AnalysisQuality(
                waveformDetail: 0,
                spectralBands: 0,
                transientMarkers: 0,
                beatGrid: 0
            ),
            analysisWarnings: analysisWarnings ?? []
        )
    }
}

public enum AnalysisBenchmarkEvaluator {
    public static func evaluateFixture(_ fixture: AnalysisBenchmarkFixture) -> AnalysisBenchmarkFixtureResult {
        let analysis = fixture.analysis.toTrackAnalysis(trackId: fixture.id)
        let expected = fixture.groundTruthLabels?.expected ?? fixture.expected
        let result = evaluate(
            analysis: analysis,
            expected: expected,
            thresholds: fixture.thresholds ?? AnalysisBenchmarkThresholds()
        )
        return AnalysisBenchmarkFixtureResult(
            fixtureId: fixture.id,
            title: fixture.title,
            trackId: analysis.trackId,
            kind: fixture.kind ?? .synthetic,
            tags: fixture.tags?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? [],
            expectedGrade: fixture.expectedGrade,
            result: result
        )
    }

    public static func evaluateSuite(_ fixtures: [AnalysisBenchmarkFixture]) -> AnalysisBenchmarkSuiteResult {
        let results = fixtures.map(evaluateFixture)
        let passed = results.filter { $0.result.grade == .pass }.count
        let warned = results.filter { $0.result.grade == .warn }.count
        let failed = results.filter { $0.result.grade == .fail }.count
        let score = rounded(average(results.map(\.result.score)) ?? 0)
        let summaries = [AnalysisBenchmarkFixtureKind.synthetic, .snapshot, .realAudio].compactMap { kind in
            summarize(kind: kind, results: results)
        }
        return AnalysisBenchmarkSuiteResult(
            grade: failed > 0 ? .fail : warned > 0 ? .warn : .pass,
            score: score,
            passed: passed,
            warned: warned,
            failed: failed,
            byKind: summaries,
            results: results
        )
    }

    public static func evaluate(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkExpectation,
        thresholds: AnalysisBenchmarkThresholds = AnalysisBenchmarkThresholds()
    ) -> AnalysisBenchmarkResult {
        var issues: [AnalysisBenchmarkIssue] = []

        let bpmError = expected.bpm.flatMap { expectedBPM in
            analysis.bpm.map { rounded(abs($0 - expectedBPM)) }
        }
        if expected.bpm != nil && analysis.bpm == nil {
            issues.append(AnalysisBenchmarkIssue(code: "bpm_missing", grade: .fail, message: "BPM is missing."))
        } else if let bpmError, bpmError > thresholds.bpmFailError {
            issues.append(AnalysisBenchmarkIssue(code: "bpm_error_high", grade: .fail, message: "BPM error is \(format(bpmError))."))
        } else if let bpmError, bpmError > thresholds.bpmWarnError {
            issues.append(AnalysisBenchmarkIssue(code: "bpm_error_high", grade: .warn, message: "BPM error is \(format(bpmError))."))
        }

        let firstDownbeat = expected.firstDownbeatSec.map { expectedSec in
            distanceMetric(
                actualValues: collectCueTimes(analysis: analysis, type: .firstDownbeat, fallbackSec: nil) +
                    analysis.downbeatsSec.filter(\.isFinite),
                expectedSec: expectedSec
            )
        }
        if let firstDownbeat {
            evaluateDistanceIssue(
                metric: firstDownbeat,
                missingCode: "first_downbeat_missing",
                farCode: "first_downbeat_far",
                label: "First downbeat",
                warnDistanceSec: thresholds.cueWarnDistanceSec,
                failDistanceSec: thresholds.cueFailDistanceSec,
                issues: &issues
            )
        }

        let expectedDownbeats = expected.downbeatSec?.filter(\.isFinite) ?? []
        let downbeats = evaluateSeriesDistances(
            actualValues: analysis.downbeatsSec,
            expectedValues: expectedDownbeats
        )
        if !expectedDownbeats.isEmpty && analysis.downbeatsSec.isEmpty {
            issues.append(AnalysisBenchmarkIssue(code: "downbeats_missing", grade: .fail, message: "Downbeat grid is missing."))
        } else if let averageDistance = downbeats.averageDistanceSec,
                  averageDistance > thresholds.downbeatFailAverageDistanceSec ||
                    (downbeats.maxDistanceSec ?? 0) > thresholds.downbeatFailMaxDistanceSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "downbeat_grid_distance_high",
                grade: .fail,
                message: "Downbeat distance avg \(format(averageDistance))s, max \(format(downbeats.maxDistanceSec ?? 0))s."
            ))
        } else if let averageDistance = downbeats.averageDistanceSec,
                  averageDistance > thresholds.downbeatWarnAverageDistanceSec ||
                    (downbeats.maxDistanceSec ?? 0) > thresholds.downbeatWarnMaxDistanceSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "downbeat_grid_distance_high",
                grade: .warn,
                message: "Downbeat distance avg \(format(averageDistance))s, max \(format(downbeats.maxDistanceSec ?? 0))s."
            ))
        }

        let outro = expected.outroCueSec.map { expectedSec in
            distanceMetric(
                actualValues: collectCueTimes(analysis: analysis, type: .outro, fallbackSec: analysis.outroCueSec),
                expectedSec: expectedSec
            )
        }
        if let outro {
            evaluateDistanceIssue(
                metric: outro,
                missingCode: "outro_missing",
                farCode: "outro_far",
                label: "Outro cue",
                warnDistanceSec: thresholds.cueWarnDistanceSec,
                failDistanceSec: thresholds.cueFailDistanceSec,
                issues: &issues
            )
        }

        let expectedBars = expected.barGridSec?.filter(\.isFinite) ?? []
        let barGrid = evaluateSeriesDistances(
            actualValues: analysis.barGrid.map(\.startSec),
            expectedValues: expectedBars
        )
        if !expectedBars.isEmpty && analysis.barGrid.isEmpty {
            issues.append(AnalysisBenchmarkIssue(code: "bar_grid_missing", grade: .fail, message: "Bar grid is missing."))
        } else if let averageDrift = barGrid.averageDistanceSec,
                  averageDrift > thresholds.barFailAverageDriftSec ||
                    (barGrid.maxDistanceSec ?? 0) > thresholds.barFailMaxDriftSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "bar_grid_drift_high",
                grade: .fail,
                message: "Bar grid drift avg \(format(averageDrift))s, max \(format(barGrid.maxDistanceSec ?? 0))s."
            ))
        } else if let averageDrift = barGrid.averageDistanceSec,
                  averageDrift > thresholds.barWarnAverageDriftSec ||
                    (barGrid.maxDistanceSec ?? 0) > thresholds.barWarnMaxDriftSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "bar_grid_drift_high",
                grade: .warn,
                message: "Bar grid drift avg \(format(averageDrift))s, max \(format(barGrid.maxDistanceSec ?? 0))s."
            ))
        }

        let expectedPhrases = expected.phraseBoundarySec?.filter(\.isFinite) ?? []
        let phraseBoundaries = evaluateSeriesDistances(
            actualValues: analysis.phraseMarkers.map(\.startSec),
            expectedValues: expectedPhrases
        )
        if !expectedPhrases.isEmpty && analysis.phraseMarkers.isEmpty {
            issues.append(AnalysisBenchmarkIssue(code: "phrase_missing", grade: .fail, message: "Phrase boundaries are missing."))
        } else if let averageDistance = phraseBoundaries.averageDistanceSec,
                  averageDistance > thresholds.phraseFailAverageDistanceSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "phrase_boundary_far",
                grade: .fail,
                message: "Phrase boundary distance avg \(format(averageDistance))s."
            ))
        } else if let averageDistance = phraseBoundaries.averageDistanceSec,
                  averageDistance > thresholds.phraseWarnAverageDistanceSec {
            issues.append(AnalysisBenchmarkIssue(
                code: "phrase_boundary_far",
                grade: .warn,
                message: "Phrase boundary distance avg \(format(averageDistance))s."
            ))
        }

        let plannerReadyActual = hasPlannerReadyTrackAnalysis(analysis)
        let plannerReadyMatch = expected.plannerReady.map { $0 == plannerReadyActual }
        if plannerReadyMatch == false {
            issues.append(AnalysisBenchmarkIssue(
                code: "planner_ready_mismatch",
                grade: .warn,
                message: "Planner-ready expected \(expected.plannerReady == true), got \(plannerReadyActual)."
            ))
        }

        let musicalKey = expected.musicalKey.map {
            evaluateMusicalKey(analysis: analysis, expected: $0, thresholds: thresholds, issues: &issues)
        }
        let loudness = expected.loudness.map {
            evaluateLoudness(analysis: analysis, expected: $0, thresholds: thresholds, issues: &issues)
        }
        let stereo = expected.stereo.map {
            evaluateStereo(analysis: analysis, expected: $0, issues: &issues)
        }
        let cueCandidates = (expected.cueCandidates ?? []).map {
            evaluateCueCandidate(analysis: analysis, expected: $0, thresholds: thresholds, issues: &issues)
        }
        let mixReadiness = expected.mixReadiness.map {
            evaluateMixReadiness(analysis: analysis, expected: $0, issues: &issues)
        }

        let scoreParts = [
            bpmError.map { scoreDistance($0, warn: thresholds.bpmWarnError, fail: thresholds.bpmFailError) },
            firstDownbeat.map { scoreDistance($0.distanceSec, warn: thresholds.cueWarnDistanceSec, fail: thresholds.cueFailDistanceSec) },
            expectedDownbeats.isEmpty ? nil : scoreDistance(
                downbeats.averageDistanceSec,
                warn: thresholds.downbeatWarnAverageDistanceSec,
                fail: thresholds.downbeatFailAverageDistanceSec
            ),
            outro.map { scoreDistance($0.distanceSec, warn: thresholds.cueWarnDistanceSec, fail: thresholds.cueFailDistanceSec) },
            expectedBars.isEmpty ? nil : scoreDistance(
                barGrid.averageDistanceSec,
                warn: thresholds.barWarnAverageDriftSec,
                fail: thresholds.barFailAverageDriftSec
            ),
            expectedPhrases.isEmpty ? nil : scoreDistance(
                phraseBoundaries.averageDistanceSec,
                warn: thresholds.phraseWarnAverageDistanceSec,
                fail: thresholds.phraseFailAverageDistanceSec
            ),
            plannerReadyMatch.map { $0 ? 1 : 0.5 },
            musicalKey.map { keyScore($0, expected: expected.musicalKey, thresholds: thresholds) },
            loudness.map { loudnessScore($0, expected: expected.loudness, thresholds: thresholds) },
            stereo.map { stereoScore($0, expected: expected.stereo) },
            cueCandidates.isEmpty ? nil : average(cueCandidates.map {
                scoreDistance($0.distanceSec, warn: thresholds.cueWarnDistanceSec, fail: thresholds.cueFailDistanceSec)
            }),
            mixReadiness.map { mixReadinessScore($0, expected: expected.mixReadiness) }
        ].compactMap { $0 }

        return AnalysisBenchmarkResult(
            grade: grade(from: issues),
            score: rounded(average(scoreParts) ?? 0),
            issues: issues,
            bpmError: bpmError,
            firstDownbeat: firstDownbeat,
            downbeats: downbeats,
            outro: outro,
            barGrid: barGrid,
            phraseBoundaries: phraseBoundaries,
            plannerReadyMatch: plannerReadyMatch,
            musicalKey: musicalKey,
            loudness: loudness,
            stereo: stereo,
            cueCandidates: cueCandidates,
            mixReadiness: mixReadiness
        )
    }

    private static func summarize(
        kind: AnalysisBenchmarkFixtureKind,
        results: [AnalysisBenchmarkFixtureResult]
    ) -> AnalysisBenchmarkKindSummary? {
        let kindResults = results.filter { $0.kind == kind }
        guard !kindResults.isEmpty else {
            return nil
        }
        let passed = kindResults.filter { $0.result.grade == .pass }.count
        let warned = kindResults.filter { $0.result.grade == .warn }.count
        let failed = kindResults.filter { $0.result.grade == .fail }.count
        return AnalysisBenchmarkKindSummary(
            kind: kind,
            grade: failed > 0 ? .fail : warned > 0 ? .warn : .pass,
            score: rounded(average(kindResults.map(\.result.score)) ?? 0),
            total: kindResults.count,
            passed: passed,
            warned: warned,
            failed: failed
        )
    }

    private static func evaluateMusicalKey(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkKeyExpectation,
        thresholds: AnalysisBenchmarkThresholds,
        issues: inout [AnalysisBenchmarkIssue]
    ) -> AnalysisBenchmarkKeyMetric {
        let key = analysis.musicalKey
        let confidence = key?.confidence
        let tonicMatches = expected.tonic == nil || key?.tonic == expected.tonic
        let modeMatches = expected.mode == nil || key?.mode == expected.mode
        let matched = key == nil ? Optional<Bool>.none : tonicMatches && modeMatches

        if key == nil {
            issues.append(AnalysisBenchmarkIssue(code: "key_missing", grade: .fail, message: "Musical key evidence is missing."))
        } else if matched == false {
            issues.append(AnalysisBenchmarkIssue(
                code: "key_mismatch",
                grade: (confidence ?? 0) >= thresholds.keyWarnConfidence ? .fail : .warn,
                message: "Musical key expected \(expected.tonic ?? "--") \(expected.mode?.rawValue ?? "--"), got \(key?.tonic ?? "--") \(key?.mode.rawValue ?? "--")."
            ))
        }

        if let minConfidence = expected.minConfidence,
           (confidence ?? 0) < minConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "key_confidence_low",
                grade: (confidence ?? 0) < thresholds.keyFailConfidence ? .fail : .warn,
                message: "Musical key confidence \(format(confidence ?? 0)) is below expected \(format(minConfidence))."
            ))
        }

        return AnalysisBenchmarkKeyMetric(
            expectedTonic: expected.tonic,
            expectedMode: expected.mode,
            actualTonic: key?.tonic,
            actualMode: key?.mode,
            confidence: confidence.map { rounded($0) },
            matched: matched
        )
    }

    private static func evaluateLoudness(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkLoudnessExpectation,
        thresholds: AnalysisBenchmarkThresholds,
        issues: inout [AnalysisBenchmarkIssue]
    ) -> AnalysisBenchmarkLoudnessMetric {
        guard let loudness = analysis.loudness else {
            issues.append(AnalysisBenchmarkIssue(code: "loudness_missing", grade: .fail, message: "Loudness evidence is missing."))
            return AnalysisBenchmarkLoudnessMetric(
                expectedIntegratedRMSDb: expected.integratedRMSDb,
                actualIntegratedRMSDb: nil,
                integratedRMSDeltaDb: nil,
                expectedIntegratedLUFS: expected.integratedLUFS,
                actualIntegratedLUFS: nil,
                integratedLUFSDelta: nil,
                expectedPeakDb: expected.peakDb,
                actualPeakDb: nil,
                peakDeltaDb: nil,
                expectedTruePeakDb: expected.truePeakDb,
                actualTruePeakDb: nil,
                truePeakDeltaDb: nil,
                headroomDb: nil,
                loudnessRangeLU: nil,
                measurement: nil,
                confidence: nil
            )
        }

        let rmsDelta = expected.integratedRMSDb.map { rounded(abs(loudness.integratedRMSDb - $0), digits: 2) }
        evaluateDbDeltaIssue(
            delta: rmsDelta,
            code: "loudness_rms_delta_high",
            label: "Integrated RMS",
            thresholds: thresholds,
            issues: &issues
        )

        let lufsDelta = expected.integratedLUFS.flatMap { expectedLUFS in
            loudness.integratedLUFS.map { rounded(abs($0 - expectedLUFS), digits: 2) }
        }
        if expected.integratedLUFS != nil && loudness.integratedLUFS == nil {
            issues.append(AnalysisBenchmarkIssue(
                code: "loudness_lufs_missing",
                grade: .fail,
                message: "Integrated LUFS evidence is missing."
            ))
        }
        evaluateDbDeltaIssue(
            delta: lufsDelta,
            code: "loudness_lufs_delta_high",
            label: "Integrated LUFS",
            thresholds: thresholds,
            issues: &issues
        )

        let peakDelta = expected.peakDb.map { rounded(abs(loudness.peakDb - $0), digits: 2) }
        evaluateDbDeltaIssue(
            delta: peakDelta,
            code: "loudness_peak_delta_high",
            label: "Peak",
            thresholds: thresholds,
            issues: &issues
        )

        let truePeakDelta = expected.truePeakDb.flatMap { expectedPeak in
            loudness.truePeakDb.map { rounded(abs($0 - expectedPeak), digits: 2) }
        }
        if expected.truePeakDb != nil && loudness.truePeakDb == nil {
            issues.append(AnalysisBenchmarkIssue(
                code: "loudness_true_peak_missing",
                grade: .fail,
                message: "True-peak evidence is missing."
            ))
        }
        evaluateDbDeltaIssue(
            delta: truePeakDelta,
            code: "loudness_true_peak_delta_high",
            label: "True peak",
            thresholds: thresholds,
            issues: &issues
        )

        if let minHeadroom = expected.minHeadroomDb,
           loudness.headroomDb < minHeadroom {
            issues.append(AnalysisBenchmarkIssue(
                code: "headroom_low",
                grade: loudness.headroomDb < thresholds.headroomFailDb ? .fail : .warn,
                message: "Headroom \(format(loudness.headroomDb)) dB is below expected \(format(minHeadroom)) dB."
            ))
        }

        if let minConfidence = expected.minConfidence,
           loudness.confidence < minConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "loudness_confidence_low",
                grade: loudness.confidence < 0.45 ? .fail : .warn,
                message: "Loudness confidence \(format(loudness.confidence)) is below expected \(format(minConfidence))."
            ))
        }

        return AnalysisBenchmarkLoudnessMetric(
            expectedIntegratedRMSDb: expected.integratedRMSDb,
            actualIntegratedRMSDb: rounded(loudness.integratedRMSDb, digits: 2),
            integratedRMSDeltaDb: rmsDelta,
            expectedIntegratedLUFS: expected.integratedLUFS,
            actualIntegratedLUFS: loudness.integratedLUFS.map { rounded($0, digits: 2) },
            integratedLUFSDelta: lufsDelta,
            expectedPeakDb: expected.peakDb,
            actualPeakDb: rounded(loudness.peakDb, digits: 2),
            peakDeltaDb: peakDelta,
            expectedTruePeakDb: expected.truePeakDb,
            actualTruePeakDb: loudness.truePeakDb.map { rounded($0, digits: 2) },
            truePeakDeltaDb: truePeakDelta,
            headroomDb: rounded(loudness.headroomDb, digits: 2),
            loudnessRangeLU: loudness.loudnessRangeLU.map { rounded($0, digits: 2) },
            measurement: loudness.measurement,
            confidence: rounded(loudness.confidence)
        )
    }

    private static func evaluateCueCandidate(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkCueExpectation,
        thresholds: AnalysisBenchmarkThresholds,
        issues: inout [AnalysisBenchmarkIssue]
    ) -> AnalysisBenchmarkCueMetric {
        let candidates = analysis.cueCandidates.filter { $0.type == expected.type }
        let nearest = candidates
            .map { cue in (cue: cue, distance: abs(cue.startSec - expected.startSec)) }
            .min { $0.distance < $1.distance }
        if nearest == nil {
            issues.append(AnalysisBenchmarkIssue(code: "cue_missing", grade: .fail, message: "Cue \(expected.type.rawValue) is missing."))
        } else if let distance = nearest?.distance {
            if distance > thresholds.cueFailDistanceSec {
                issues.append(AnalysisBenchmarkIssue(code: "cue_far", grade: .fail, message: "Cue \(expected.type.rawValue) is \(format(distance))s from expected."))
            } else if distance > thresholds.cueWarnDistanceSec {
                issues.append(AnalysisBenchmarkIssue(code: "cue_far", grade: .warn, message: "Cue \(expected.type.rawValue) is \(format(distance))s from expected."))
            }
        }

        if let minConfidence = expected.minConfidence,
           (nearest?.cue.confidence ?? 0) < minConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "cue_confidence_low",
                grade: (nearest?.cue.confidence ?? 0) < thresholds.cueFailConfidence ? .fail : .warn,
                message: "Cue \(expected.type.rawValue) confidence \(format(nearest?.cue.confidence ?? 0)) is below expected \(format(minConfidence))."
            ))
        }

        if let origin = expected.origin,
           nearest?.cue.origin != origin {
            issues.append(AnalysisBenchmarkIssue(
                code: "cue_origin_mismatch",
                grade: .warn,
                message: "Cue \(expected.type.rawValue) origin expected \(origin.rawValue), got \(nearest?.cue.origin.rawValue ?? "--")."
            ))
        }

        return AnalysisBenchmarkCueMetric(
            type: expected.type,
            expectedSec: expected.startSec,
            actualSec: nearest.map { rounded($0.cue.startSec) },
            distanceSec: nearest.map { rounded($0.distance) },
            confidence: nearest.map { rounded($0.cue.confidence) },
            origin: nearest?.cue.origin
        )
    }

    private static func evaluateStereo(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkStereoExpectation,
        issues: inout [AnalysisBenchmarkIssue]
    ) -> AnalysisBenchmarkStereoMetric {
        guard let stereo = analysis.stereo else {
            issues.append(AnalysisBenchmarkIssue(code: "stereo_missing", grade: .fail, message: "Stereo evidence is missing."))
            return AnalysisBenchmarkStereoMetric(
                expectedChannelCount: expected.channelCount,
                actualChannelCount: nil,
                stereoWidth: nil,
                phaseCorrelation: nil,
                midSideBalance: nil,
                confidence: nil
            )
        }

        if let channelCount = expected.channelCount,
           stereo.channelCount != channelCount {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_channel_count_mismatch",
                grade: .fail,
                message: "Channel count expected \(channelCount), got \(stereo.channelCount)."
            ))
        }
        if let minStereoWidth = expected.minStereoWidth,
           stereo.stereoWidth < minStereoWidth {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_width_low",
                grade: .warn,
                message: "Stereo width \(format(stereo.stereoWidth)) is below expected \(format(minStereoWidth))."
            ))
        }
        if let maxStereoWidth = expected.maxStereoWidth,
           stereo.stereoWidth > maxStereoWidth {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_width_high",
                grade: .warn,
                message: "Stereo width \(format(stereo.stereoWidth)) is above expected \(format(maxStereoWidth))."
            ))
        }
        if let minPhaseCorrelation = expected.minPhaseCorrelation,
           stereo.phaseCorrelation < minPhaseCorrelation {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_phase_correlation_low",
                grade: stereo.phaseCorrelation < 0 ? .fail : .warn,
                message: "Phase correlation \(format(stereo.phaseCorrelation)) is below expected \(format(minPhaseCorrelation))."
            ))
        }
        if let maxMidSideBalance = expected.maxMidSideBalance,
           stereo.midSideBalance > maxMidSideBalance {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_mid_side_balance_high",
                grade: .warn,
                message: "Mid/side balance \(format(stereo.midSideBalance)) is above expected \(format(maxMidSideBalance))."
            ))
        }
        if let minConfidence = expected.minConfidence,
           stereo.confidence < minConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "stereo_confidence_low",
                grade: .warn,
                message: "Stereo confidence \(format(stereo.confidence)) is below expected \(format(minConfidence))."
            ))
        }

        return AnalysisBenchmarkStereoMetric(
            expectedChannelCount: expected.channelCount,
            actualChannelCount: stereo.channelCount,
            stereoWidth: rounded(stereo.stereoWidth),
            phaseCorrelation: rounded(stereo.phaseCorrelation),
            midSideBalance: rounded(stereo.midSideBalance),
            confidence: rounded(stereo.confidence)
        )
    }

    private static func evaluateMixReadiness(
        analysis: TrackAnalysis,
        expected: AnalysisBenchmarkMixReadinessExpectation,
        issues: inout [AnalysisBenchmarkIssue]
    ) -> AnalysisBenchmarkMixReadinessMetric {
        if let minAnalysisConfidence = expected.minAnalysisConfidence,
           analysis.analysisConfidence < minAnalysisConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "analysis_confidence_low",
                grade: .warn,
                message: "Analysis confidence \(format(analysis.analysisConfidence)) is below expected \(format(minAnalysisConfidence))."
            ))
        }
        if let minHarmonicKeyQuality = expected.minHarmonicKeyQuality,
           analysis.analysisQuality.harmonicKey < minHarmonicKeyQuality {
            issues.append(AnalysisBenchmarkIssue(
                code: "harmonic_key_quality_low",
                grade: .warn,
                message: "Harmonic key quality \(format(analysis.analysisQuality.harmonicKey)) is below expected \(format(minHarmonicKeyQuality))."
            ))
        }
        if let minLoudnessConfidence = expected.minLoudnessConfidence,
           (analysis.loudness?.confidence ?? 0) < minLoudnessConfidence {
            issues.append(AnalysisBenchmarkIssue(
                code: "loudness_confidence_low",
                grade: .warn,
                message: "Loudness confidence \(format(analysis.loudness?.confidence ?? 0)) is below expected \(format(minLoudnessConfidence))."
            ))
        }
        let forbiddenWarnings = expected.forbiddenWarnings ?? []
        let presentWarnings = forbiddenWarnings.filter { analysis.analysisWarnings.contains($0) }
        for warning in presentWarnings {
            issues.append(AnalysisBenchmarkIssue(
                code: "forbidden_warning_present",
                grade: .warn,
                message: "Forbidden analysis warning is present: \(warning.rawValue)."
            ))
        }
        return AnalysisBenchmarkMixReadinessMetric(
            analysisConfidence: rounded(analysis.analysisConfidence),
            harmonicKeyQuality: rounded(analysis.analysisQuality.harmonicKey),
            loudnessConfidence: analysis.loudness.map { rounded($0.confidence) },
            forbiddenWarningsPresent: presentWarnings
        )
    }

    private static func hasPlannerReadyTrackAnalysis(_ analysis: TrackAnalysis) -> Bool {
        !analysis.waveformDetail.isEmpty &&
            !analysis.energyProfile.isEmpty &&
            !analysis.barGrid.isEmpty &&
            analysis.analysisQuality.waveformDetail >= 0.2 &&
            analysis.analysisQuality.beatGrid >= 0.35 &&
            analysis.bpmConfidence >= 0.45 &&
            !analysis.analysisWarnings.contains(.analysisUpgradeAvailable) &&
            !analysis.analysisWarnings.contains(.bpmLowConfidence)
    }

    private static func collectCueTimes(
        analysis: TrackAnalysis,
        type: CueCandidateType,
        fallbackSec: Double?
    ) -> [Double] {
        analysis.cueCandidates
            .filter { $0.type == type }
            .map(\.startSec)
            .filter(\.isFinite) +
            (fallbackSec?.isFinite == true ? [fallbackSec!] : [])
    }

    private static func distanceMetric(
        actualValues: [Double],
        expectedSec: Double
    ) -> AnalysisBenchmarkDistanceMetric {
        guard let nearest = nearestValue(actualValues, expected: expectedSec) else {
            return AnalysisBenchmarkDistanceMetric(expectedSec: expectedSec, actualSec: nil, distanceSec: nil)
        }
        return AnalysisBenchmarkDistanceMetric(
            expectedSec: expectedSec,
            actualSec: rounded(nearest.value),
            distanceSec: rounded(nearest.distance)
        )
    }

    private static func evaluateSeriesDistances(
        actualValues: [Double],
        expectedValues: [Double]
    ) -> AnalysisBenchmarkSeriesMetric {
        let distances = expectedValues.compactMap { expected in
            nearestValue(actualValues, expected: expected)?.distance
        }
        return AnalysisBenchmarkSeriesMetric(
            checkedCount: expectedValues.count,
            averageDistanceSec: average(distances).map { rounded($0) },
            maxDistanceSec: distances.max().map { rounded($0) }
        )
    }

    private static func evaluateDistanceIssue(
        metric: AnalysisBenchmarkDistanceMetric,
        missingCode: String,
        farCode: String,
        label: String,
        warnDistanceSec: Double,
        failDistanceSec: Double,
        issues: inout [AnalysisBenchmarkIssue]
    ) {
        guard let distanceSec = metric.distanceSec else {
            issues.append(AnalysisBenchmarkIssue(code: missingCode, grade: .fail, message: "\(label) is missing."))
            return
        }
        if distanceSec > failDistanceSec {
            issues.append(AnalysisBenchmarkIssue(code: farCode, grade: .fail, message: "\(label) is \(format(distanceSec))s from expected."))
        } else if distanceSec > warnDistanceSec {
            issues.append(AnalysisBenchmarkIssue(code: farCode, grade: .warn, message: "\(label) is \(format(distanceSec))s from expected."))
        }
    }

    private static func evaluateDbDeltaIssue(
        delta: Double?,
        code: String,
        label: String,
        thresholds: AnalysisBenchmarkThresholds,
        issues: inout [AnalysisBenchmarkIssue]
    ) {
        guard let delta else {
            return
        }
        if delta > thresholds.loudnessFailDeltaDb {
            issues.append(AnalysisBenchmarkIssue(code: code, grade: .fail, message: "\(label) delta is \(format(delta)) dB."))
        } else if delta > thresholds.loudnessWarnDeltaDb {
            issues.append(AnalysisBenchmarkIssue(code: code, grade: .warn, message: "\(label) delta is \(format(delta)) dB."))
        }
    }

    private static func nearestValue(
        _ values: [Double],
        expected: Double
    ) -> (value: Double, distance: Double)? {
        values
            .filter(\.isFinite)
            .map { (value: $0, distance: abs($0 - expected)) }
            .min { $0.distance < $1.distance }
    }

    private static func scoreDistance(_ value: Double?, warn: Double, fail: Double) -> Double {
        guard let value else {
            return 0
        }
        if value <= warn {
            return 1
        }
        if value >= fail {
            return 0
        }
        return min(1, max(0, 1 - (value - warn) / (fail - warn)))
    }

    private static func keyScore(
        _ metric: AnalysisBenchmarkKeyMetric,
        expected: AnalysisBenchmarkKeyExpectation?,
        thresholds: AnalysisBenchmarkThresholds
    ) -> Double {
        guard metric.actualTonic != nil else {
            return 0
        }
        let matchScore = metric.matched == false ? 0.0 : 1.0
        let confidenceScore = scoreLowerBound(
            metric.confidence,
            warn: expected?.minConfidence ?? thresholds.keyWarnConfidence,
            fail: thresholds.keyFailConfidence
        )
        return (matchScore * 0.68) + (confidenceScore * 0.32)
    }

    private static func loudnessScore(
        _ metric: AnalysisBenchmarkLoudnessMetric,
        expected: AnalysisBenchmarkLoudnessExpectation?,
        thresholds: AnalysisBenchmarkThresholds
    ) -> Double {
        var parts: [Double] = []
        if expected?.integratedRMSDb != nil {
            parts.append(scoreDistance(metric.integratedRMSDeltaDb, warn: thresholds.loudnessWarnDeltaDb, fail: thresholds.loudnessFailDeltaDb))
        }
        if expected?.integratedLUFS != nil {
            parts.append(scoreDistance(metric.integratedLUFSDelta, warn: thresholds.loudnessWarnDeltaDb, fail: thresholds.loudnessFailDeltaDb))
        }
        if expected?.peakDb != nil {
            parts.append(scoreDistance(metric.peakDeltaDb, warn: thresholds.loudnessWarnDeltaDb, fail: thresholds.loudnessFailDeltaDb))
        }
        if expected?.truePeakDb != nil {
            parts.append(scoreDistance(metric.truePeakDeltaDb, warn: thresholds.loudnessWarnDeltaDb, fail: thresholds.loudnessFailDeltaDb))
        }
        if expected?.minHeadroomDb != nil {
            parts.append(scoreLowerBound(metric.headroomDb, warn: thresholds.headroomWarnDb, fail: thresholds.headroomFailDb))
        }
        if expected?.minConfidence != nil {
            parts.append(scoreLowerBound(metric.confidence, warn: expected?.minConfidence ?? 0.68, fail: 0.45))
        }
        return average(parts) ?? (metric.actualIntegratedRMSDb == nil && metric.actualIntegratedLUFS == nil ? 0 : 1)
    }

    private static func stereoScore(
        _ metric: AnalysisBenchmarkStereoMetric,
        expected: AnalysisBenchmarkStereoExpectation?
    ) -> Double {
        guard metric.actualChannelCount != nil else {
            return 0
        }
        var parts: [Double] = []
        if let channelCount = expected?.channelCount {
            parts.append(metric.actualChannelCount == channelCount ? 1 : 0)
        }
        if let minStereoWidth = expected?.minStereoWidth {
            parts.append((metric.stereoWidth ?? 0) >= minStereoWidth ? 1 : 0.5)
        }
        if let maxStereoWidth = expected?.maxStereoWidth {
            parts.append((metric.stereoWidth ?? 1) <= maxStereoWidth ? 1 : 0.5)
        }
        if let minPhaseCorrelation = expected?.minPhaseCorrelation {
            parts.append((metric.phaseCorrelation ?? -1) >= minPhaseCorrelation ? 1 : 0.5)
        }
        if let maxMidSideBalance = expected?.maxMidSideBalance {
            parts.append((metric.midSideBalance ?? 99) <= maxMidSideBalance ? 1 : 0.5)
        }
        if let minConfidence = expected?.minConfidence {
            parts.append((metric.confidence ?? 0) >= minConfidence ? 1 : 0.5)
        }
        return average(parts) ?? 1
    }

    private static func mixReadinessScore(
        _ metric: AnalysisBenchmarkMixReadinessMetric,
        expected: AnalysisBenchmarkMixReadinessExpectation?
    ) -> Double {
        var parts: [Double] = []
        if let minAnalysisConfidence = expected?.minAnalysisConfidence {
            parts.append(metric.analysisConfidence >= minAnalysisConfidence ? 1 : 0.5)
        }
        if let minHarmonicKeyQuality = expected?.minHarmonicKeyQuality {
            parts.append(metric.harmonicKeyQuality >= minHarmonicKeyQuality ? 1 : 0.5)
        }
        if let minLoudnessConfidence = expected?.minLoudnessConfidence {
            parts.append((metric.loudnessConfidence ?? 0) >= minLoudnessConfidence ? 1 : 0.5)
        }
        if expected?.forbiddenWarnings?.isEmpty == false {
            parts.append(metric.forbiddenWarningsPresent.isEmpty ? 1 : 0.5)
        }
        return average(parts) ?? 1
    }

    private static func scoreLowerBound(_ value: Double?, warn: Double, fail: Double) -> Double {
        guard let value else {
            return 0
        }
        if value >= warn {
            return 1
        }
        if value <= fail {
            return 0
        }
        return min(1, max(0, (value - fail) / (warn - fail)))
    }

    private static func grade(from issues: [AnalysisBenchmarkIssue]) -> AnalysisBenchmarkGrade {
        if issues.contains(where: { $0.grade == .fail }) {
            return .fail
        }
        if issues.contains(where: { $0.grade == .warn }) {
            return .warn
        }
        return .pass
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func rounded(_ value: Double, digits: Int = 3) -> Double {
        let multiplier = pow(10, Double(digits))
        return (value * multiplier).rounded() / multiplier
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
