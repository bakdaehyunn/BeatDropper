import Foundation

public enum AnalysisBenchmarkGrade: String, Codable, Sendable {
    case pass
    case warn
    case fail
}

public enum AnalysisBenchmarkFixtureKind: String, Codable, Sendable {
    case synthetic
    case snapshot
}

public struct AnalysisBenchmarkExpectation: Codable, Hashable, Sendable {
    public var bpm: Double?
    public var firstDownbeatSec: Double?
    public var outroCueSec: Double?
    public var barGridSec: [Double]?
    public var phraseBoundarySec: [Double]?
    public var plannerReady: Bool?

    public init(
        bpm: Double? = nil,
        firstDownbeatSec: Double? = nil,
        outroCueSec: Double? = nil,
        barGridSec: [Double]? = nil,
        phraseBoundarySec: [Double]? = nil,
        plannerReady: Bool? = nil
    ) {
        self.bpm = bpm
        self.firstDownbeatSec = firstDownbeatSec
        self.outroCueSec = outroCueSec
        self.barGridSec = barGridSec
        self.phraseBoundarySec = phraseBoundarySec
        self.plannerReady = plannerReady
    }
}

public struct AnalysisBenchmarkThresholds: Codable, Hashable, Sendable {
    public var bpmWarnError: Double
    public var bpmFailError: Double
    public var cueWarnDistanceSec: Double
    public var cueFailDistanceSec: Double
    public var barWarnAverageDriftSec: Double
    public var barFailAverageDriftSec: Double
    public var barWarnMaxDriftSec: Double
    public var barFailMaxDriftSec: Double
    public var phraseWarnAverageDistanceSec: Double
    public var phraseFailAverageDistanceSec: Double

    public init(
        bpmWarnError: Double = 1.5,
        bpmFailError: Double = 4,
        cueWarnDistanceSec: Double = 1,
        cueFailDistanceSec: Double = 4,
        barWarnAverageDriftSec: Double = 0.18,
        barFailAverageDriftSec: Double = 0.55,
        barWarnMaxDriftSec: Double = 0.45,
        barFailMaxDriftSec: Double = 1.25,
        phraseWarnAverageDistanceSec: Double = 2,
        phraseFailAverageDistanceSec: Double = 8
    ) {
        self.bpmWarnError = bpmWarnError
        self.bpmFailError = bpmFailError
        self.cueWarnDistanceSec = cueWarnDistanceSec
        self.cueFailDistanceSec = cueFailDistanceSec
        self.barWarnAverageDriftSec = barWarnAverageDriftSec
        self.barFailAverageDriftSec = barFailAverageDriftSec
        self.barWarnMaxDriftSec = barWarnMaxDriftSec
        self.barFailMaxDriftSec = barFailMaxDriftSec
        self.phraseWarnAverageDistanceSec = phraseWarnAverageDistanceSec
        self.phraseFailAverageDistanceSec = phraseFailAverageDistanceSec
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

public struct AnalysisBenchmarkResult: Codable, Hashable, Sendable {
    public var grade: AnalysisBenchmarkGrade
    public var score: Double
    public var issues: [AnalysisBenchmarkIssue]
    public var bpmError: Double?
    public var firstDownbeat: AnalysisBenchmarkDistanceMetric?
    public var outro: AnalysisBenchmarkDistanceMetric?
    public var barGrid: AnalysisBenchmarkSeriesMetric
    public var phraseBoundaries: AnalysisBenchmarkSeriesMetric
    public var plannerReadyMatch: Bool?

    public init(
        grade: AnalysisBenchmarkGrade,
        score: Double,
        issues: [AnalysisBenchmarkIssue],
        bpmError: Double?,
        firstDownbeat: AnalysisBenchmarkDistanceMetric?,
        outro: AnalysisBenchmarkDistanceMetric?,
        barGrid: AnalysisBenchmarkSeriesMetric,
        phraseBoundaries: AnalysisBenchmarkSeriesMetric,
        plannerReadyMatch: Bool?
    ) {
        self.grade = grade
        self.score = score
        self.issues = issues
        self.bpmError = bpmError
        self.firstDownbeat = firstDownbeat
        self.outro = outro
        self.barGrid = barGrid
        self.phraseBoundaries = phraseBoundaries
        self.plannerReadyMatch = plannerReadyMatch
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
    public var expected: AnalysisBenchmarkExpectation
    public var analysis: AnalysisBenchmarkTrackAnalysisSnapshot
    public var thresholds: AnalysisBenchmarkThresholds?

    public init(
        id: String,
        title: String,
        kind: AnalysisBenchmarkFixtureKind? = nil,
        tags: [String]? = nil,
        expectedGrade: AnalysisBenchmarkGrade? = nil,
        expected: AnalysisBenchmarkExpectation,
        analysis: AnalysisBenchmarkTrackAnalysisSnapshot,
        thresholds: AnalysisBenchmarkThresholds? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.tags = tags
        self.expectedGrade = expectedGrade
        self.expected = expected
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
        let result = evaluate(
            analysis: analysis,
            expected: fixture.expected,
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
        let summaries = [AnalysisBenchmarkFixtureKind.synthetic, .snapshot].compactMap { kind in
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

        let scoreParts = [
            bpmError.map { scoreDistance($0, warn: thresholds.bpmWarnError, fail: thresholds.bpmFailError) },
            firstDownbeat.map { scoreDistance($0.distanceSec, warn: thresholds.cueWarnDistanceSec, fail: thresholds.cueFailDistanceSec) },
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
            plannerReadyMatch.map { $0 ? 1 : 0.5 }
        ].compactMap { $0 }

        return AnalysisBenchmarkResult(
            grade: grade(from: issues),
            score: rounded(average(scoreParts) ?? 0),
            issues: issues,
            bpmError: bpmError,
            firstDownbeat: firstDownbeat,
            outro: outro,
            barGrid: barGrid,
            phraseBoundaries: phraseBoundaries,
            plannerReadyMatch: plannerReadyMatch
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
