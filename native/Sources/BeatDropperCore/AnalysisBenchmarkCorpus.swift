import Foundation

public enum AnalysisBenchmarkCorpusSplit: String, Codable, CaseIterable, Sendable {
    case calibration
    case validation
    case regression
}

public enum AnalysisBenchmarkAudioRights: String, Codable, Sendable {
    case privateUserOwned = "private_user_owned"
    case redistributionCleared = "redistribution_cleared"
    case synthetic
}

public enum AnalysisBenchmarkTempoProfile: String, Codable, Sendable {
    case fixed
    case drifting
    case variable
    case ambiguous
}

public struct AnalysisBenchmarkReferenceTool: Codable, Hashable, Sendable {
    public var name: String
    public var version: String?
    public var settings: String?

    public init(name: String, version: String? = nil, settings: String? = nil) {
        self.name = name
        self.version = version
        self.settings = settings
    }
}

public struct AnalysisBenchmarkCorpusMetadata: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var split: AnalysisBenchmarkCorpusSplit
    public var anonymizedAssetId: String
    public var audioRights: AnalysisBenchmarkAudioRights
    public var audioDurationSec: Double
    public var sampleRate: Double?
    public var channelCount: Int?
    public var genreTags: [String]
    public var tempoProfile: AnalysisBenchmarkTempoProfile
    public var referenceTools: [AnalysisBenchmarkReferenceTool]

    public init(
        schemaVersion: Int = 2,
        split: AnalysisBenchmarkCorpusSplit,
        anonymizedAssetId: String,
        audioRights: AnalysisBenchmarkAudioRights,
        audioDurationSec: Double,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        genreTags: [String] = [],
        tempoProfile: AnalysisBenchmarkTempoProfile = .fixed,
        referenceTools: [AnalysisBenchmarkReferenceTool] = []
    ) {
        self.schemaVersion = schemaVersion
        self.split = split
        self.anonymizedAssetId = anonymizedAssetId
        self.audioRights = audioRights
        self.audioDurationSec = audioDurationSec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.genreTags = genreTags
        self.tempoProfile = tempoProfile
        self.referenceTools = referenceTools
    }
}

public enum AnalysisBenchmarkConcept: String, Codable, CaseIterable, Sendable {
    case bpm
    case beatgrid
    case downbeats
    case phrases
    case key
    case lufs
    case truePeak = "true_peak"
    case cues
}

public struct AnalysisBenchmarkCalibrationBin: Codable, Hashable, Sendable {
    public var lowerBound: Double
    public var upperBound: Double
    public var count: Int
    public var meanConfidence: Double
    public var accuracy: Double
}

public struct AnalysisBenchmarkCalibrationMetric: Codable, Hashable, Sendable {
    public var sampleCount: Int
    public var accuracy: Double
    public var meanConfidence: Double
    public var expectedCalibrationError: Double
    public var brierScore: Double
    public var bins: [AnalysisBenchmarkCalibrationBin]
}

public struct AnalysisBenchmarkConceptSummary: Codable, Hashable, Sendable {
    public var concept: AnalysisBenchmarkConcept
    public var labeledCount: Int
    public var correctCount: Int
    public var accuracy: Double
    public var errorP50: Double?
    public var errorP95: Double?
    public var calibration: AnalysisBenchmarkCalibrationMetric?
}

public struct AnalysisBenchmarkCorpusIntegrityIssue: Codable, Hashable, Sendable {
    public var fixtureId: String
    public var code: String
    public var message: String

    public init(fixtureId: String, code: String, message: String) {
        self.fixtureId = fixtureId
        self.code = code
        self.message = message
    }
}

public struct AnalysisBenchmarkCorpusReport: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var fixtureCount: Int
    public var realAudioFixtureCount: Int
    public var splitCounts: [AnalysisBenchmarkCorpusSplit: Int]
    public var conceptSummaries: [AnalysisBenchmarkConceptSummary]
    public var integrityIssues: [AnalysisBenchmarkCorpusIntegrityIssue]
}

public enum AnalysisBenchmarkGateStatus: String, Codable, Sendable {
    case candidate
    case approved
}

public struct AnalysisBenchmarkConceptGate: Codable, Hashable, Sendable {
    public var minimumLabeledCount: Int
    public var minimumAccuracy: Double?
    public var maximumP95Error: Double?
    public var minimumCalibrationSamples: Int?
    public var maximumExpectedCalibrationError: Double?
    public var maximumBrierScore: Double?

    public init(
        minimumLabeledCount: Int,
        minimumAccuracy: Double? = nil,
        maximumP95Error: Double? = nil,
        minimumCalibrationSamples: Int? = nil,
        maximumExpectedCalibrationError: Double? = nil,
        maximumBrierScore: Double? = nil
    ) {
        self.minimumLabeledCount = minimumLabeledCount
        self.minimumAccuracy = minimumAccuracy
        self.maximumP95Error = maximumP95Error
        self.minimumCalibrationSamples = minimumCalibrationSamples
        self.maximumExpectedCalibrationError = maximumExpectedCalibrationError
        self.maximumBrierScore = maximumBrierScore
    }
}

public struct AnalysisBenchmarkCorpusGateConfiguration: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var status: AnalysisBenchmarkGateStatus
    public var approvedBy: String?
    public var approvedAt: String?
    public var minimumRealAudioFixtures: Int
    public var minimumSplitCounts: [String: Int]
    public var concepts: [String: AnalysisBenchmarkConceptGate]

    public init(
        schemaVersion: Int = 1,
        status: AnalysisBenchmarkGateStatus,
        approvedBy: String? = nil,
        approvedAt: String? = nil,
        minimumRealAudioFixtures: Int,
        minimumSplitCounts: [String: Int],
        concepts: [String: AnalysisBenchmarkConceptGate]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.minimumRealAudioFixtures = minimumRealAudioFixtures
        self.minimumSplitCounts = minimumSplitCounts
        self.concepts = concepts
    }
}

public struct AnalysisBenchmarkCorpusGateIssue: Codable, Hashable, Sendable {
    public var code: String
    public var message: String
}

public struct AnalysisBenchmarkCorpusGateResult: Codable, Hashable, Sendable {
    public var status: AnalysisBenchmarkGateStatus
    public var enforceable: Bool
    public var meetsThresholds: Bool
    public var issues: [AnalysisBenchmarkCorpusGateIssue]
}

public enum AnalysisBenchmarkCorpusEvaluator {
    private struct Observation {
        var error: Double
        var confidence: Double?
        var correct: Bool
    }

    public static func evaluate(_ fixtures: [AnalysisBenchmarkFixture]) -> AnalysisBenchmarkCorpusReport {
        var observations: [AnalysisBenchmarkConcept: [Observation]] = [:]
        var integrityIssues: [AnalysisBenchmarkCorpusIntegrityIssue] = []
        var splitCounts: [AnalysisBenchmarkCorpusSplit: Int] = [:]
        var assetOwners: [String: (fixtureId: String, split: AnalysisBenchmarkCorpusSplit)] = [:]
        let realAudioFixtures = fixtures.filter { $0.kind == .realAudio }

        for fixture in realAudioFixtures {
            validateIntegrity(fixture, issues: &integrityIssues)
            if let corpus = fixture.corpus {
                let assetId = corpus.anonymizedAssetId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !assetId.isEmpty, let owner = assetOwners[assetId] {
                    let detail = owner.split == corpus.split
                        ? "Duplicate anonymized asset id also used by fixture \(owner.fixtureId)."
                        : "Anonymized asset id is assigned to both \(owner.split.rawValue) and \(corpus.split.rawValue) splits."
                    integrityIssues.append(.init(fixtureId: fixture.id, code: "asset_id_duplicate", message: detail))
                } else if !assetId.isEmpty {
                    assetOwners[assetId] = (fixture.id, corpus.split)
                }
                let split = corpus.split
                splitCounts[split, default: 0] += 1
            }
            collectObservations(fixture, into: &observations)
        }

        let summaries = AnalysisBenchmarkConcept.allCases.map { concept in
            summarize(concept: concept, observations: observations[concept] ?? [])
        }
        return AnalysisBenchmarkCorpusReport(
            schemaVersion: 1,
            fixtureCount: fixtures.count,
            realAudioFixtureCount: realAudioFixtures.count,
            splitCounts: splitCounts,
            conceptSummaries: summaries,
            integrityIssues: integrityIssues
        )
    }

    private static func validateIntegrity(
        _ fixture: AnalysisBenchmarkFixture,
        issues: inout [AnalysisBenchmarkCorpusIntegrityIssue]
    ) {
        guard let corpus = fixture.corpus else {
            issues.append(.init(fixtureId: fixture.id, code: "corpus_metadata_missing", message: "Real-audio fixture has no corpus metadata."))
            return
        }
        if corpus.schemaVersion != 2 {
            issues.append(.init(fixtureId: fixture.id, code: "corpus_schema_unsupported", message: "Corpus schemaVersion must be 2."))
        }
        if corpus.anonymizedAssetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(fixtureId: fixture.id, code: "asset_id_missing", message: "An anonymized asset id is required."))
        }
        if !corpus.audioDurationSec.isFinite || corpus.audioDurationSec <= 0 {
            issues.append(.init(fixtureId: fixture.id, code: "audio_duration_invalid", message: "Audio duration must be positive and finite."))
        }
        if corpus.audioRights == .synthetic {
            issues.append(.init(fixtureId: fixture.id, code: "real_audio_rights_invalid", message: "A real-audio fixture cannot declare synthetic rights."))
        }
        if corpus.referenceTools.isEmpty {
            issues.append(.init(fixtureId: fixture.id, code: "reference_tools_missing", message: "At least one independent reference tool is required."))
        }
        guard let labels = fixture.groundTruthLabels else {
            issues.append(.init(fixtureId: fixture.id, code: "ground_truth_missing", message: "Reviewed ground-truth labels are required."))
            return
        }
        if labels.schemaVersion != 2 {
            issues.append(.init(fixtureId: fixture.id, code: "labels_schema_unsupported", message: "Ground-truth schemaVersion must be 2."))
        }
        let reviewer = labels.reviewedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
        if reviewer?.isEmpty != false || reviewer == "UNREVIEWED" || reviewer == "SIMULATED_REVIEW" {
            issues.append(.init(fixtureId: fixture.id, code: "reviewer_missing", message: "A pseudonymous reviewer id is required."))
        }
        if labels.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.init(fixtureId: fixture.id, code: "review_date_missing", message: "A review timestamp is required."))
        }
        if labeledConcepts(labels.expected).isEmpty {
            issues.append(.init(fixtureId: fixture.id, code: "labels_empty", message: "At least one DSP concept must be labeled."))
        }
    }

    private static func collectObservations(
        _ fixture: AnalysisBenchmarkFixture,
        into observations: inout [AnalysisBenchmarkConcept: [Observation]]
    ) {
        guard let expected = fixture.groundTruthLabels?.expected else {
            return
        }
        let analysis = fixture.analysis.toTrackAnalysis(trackId: fixture.id)
        let thresholds = fixture.thresholds ?? AnalysisBenchmarkThresholds()

        if let bpm = expected.bpm {
            let error = analysis.bpm.map { abs($0 - bpm) } ?? .infinity
            observations[.bpm, default: []].append(.init(
                error: error,
                confidence: analysis.bpm.map { _ in analysis.bpmConfidence },
                correct: error <= thresholds.bpmWarnError
            ))
        }
        if let expectedBars = expected.barGridSec, !expectedBars.isEmpty {
            let error = seriesAverageDistance(actual: analysis.barGrid.map(\.startSec), expected: expectedBars)
            observations[.beatgrid, default: []].append(.init(
                error: error,
                confidence: analysis.analysisQuality.beatGrid,
                correct: error <= thresholds.barWarnAverageDriftSec
            ))
        }
        if let expectedDownbeats = expected.downbeatSec, !expectedDownbeats.isEmpty {
            let error = seriesAverageDistance(actual: analysis.downbeatsSec, expected: expectedDownbeats)
            let confidence = analysis.cueCandidates.first(where: { $0.type == .firstDownbeat })?.confidence
                ?? analysis.analysisQuality.beatGrid
            observations[.downbeats, default: []].append(.init(
                error: error,
                confidence: confidence,
                correct: error <= thresholds.downbeatWarnAverageDistanceSec
            ))
        } else if let firstDownbeat = expected.firstDownbeatSec {
            let error = nearestDistance(actual: analysis.downbeatsSec, expected: firstDownbeat)
            let confidence = analysis.cueCandidates.first(where: { $0.type == .firstDownbeat })?.confidence
                ?? analysis.analysisQuality.beatGrid
            observations[.downbeats, default: []].append(.init(
                error: error,
                confidence: confidence,
                correct: error <= thresholds.cueWarnDistanceSec
            ))
        }
        if let expectedPhrases = expected.phraseBoundarySec, !expectedPhrases.isEmpty {
            let error = seriesAverageDistance(actual: analysis.phraseMarkers.map(\.startSec), expected: expectedPhrases)
            let confidence = average(analysis.phraseMarkers.map(\.confidence))
            observations[.phrases, default: []].append(.init(
                error: error,
                confidence: confidence,
                correct: error <= thresholds.phraseWarnAverageDistanceSec
            ))
        }
        if let key = expected.musicalKey {
            let tonicMatches = key.tonic == nil || key.tonic == analysis.musicalKey?.tonic
            let modeMatches = key.mode == nil || key.mode == analysis.musicalKey?.mode
            let correct = tonicMatches && modeMatches && analysis.musicalKey != nil
            observations[.key, default: []].append(.init(
                error: correct ? 0 : 1,
                confidence: analysis.musicalKey?.confidence,
                correct: correct
            ))
        }
        if let expectedLUFS = expected.loudness?.integratedLUFS {
            let error = analysis.loudness?.integratedLUFS.map { abs($0 - expectedLUFS) } ?? .infinity
            observations[.lufs, default: []].append(.init(
                error: error,
                confidence: analysis.loudness?.confidence,
                correct: error <= thresholds.loudnessWarnDeltaDb
            ))
        }
        if let expectedTruePeak = expected.loudness?.truePeakDb {
            let error = analysis.loudness?.truePeakDb.map { abs($0 - expectedTruePeak) } ?? .infinity
            observations[.truePeak, default: []].append(.init(
                error: error,
                confidence: analysis.loudness?.confidence,
                correct: error <= thresholds.loudnessWarnDeltaDb
            ))
        }
        for cue in expected.cueCandidates ?? [] {
            let nearest = analysis.cueCandidates
                .filter { $0.type == cue.type }
                .map { candidate in (candidate, abs(candidate.startSec - cue.startSec)) }
                .min { $0.1 < $1.1 }
            let error = nearest?.1 ?? .infinity
            observations[.cues, default: []].append(.init(
                error: error,
                confidence: nearest?.0.confidence,
                correct: error <= thresholds.cueWarnDistanceSec
            ))
        }
    }

    private static func labeledConcepts(_ expected: AnalysisBenchmarkExpectation) -> Set<AnalysisBenchmarkConcept> {
        var concepts = Set<AnalysisBenchmarkConcept>()
        if expected.bpm != nil { concepts.insert(.bpm) }
        if expected.barGridSec?.isEmpty == false { concepts.insert(.beatgrid) }
        if expected.downbeatSec?.isEmpty == false || expected.firstDownbeatSec != nil { concepts.insert(.downbeats) }
        if expected.phraseBoundarySec?.isEmpty == false { concepts.insert(.phrases) }
        if expected.musicalKey != nil { concepts.insert(.key) }
        if expected.loudness?.integratedLUFS != nil { concepts.insert(.lufs) }
        if expected.loudness?.truePeakDb != nil { concepts.insert(.truePeak) }
        if expected.cueCandidates?.isEmpty == false { concepts.insert(.cues) }
        return concepts
    }

    private static func summarize(
        concept: AnalysisBenchmarkConcept,
        observations: [Observation]
    ) -> AnalysisBenchmarkConceptSummary {
        let finiteErrors = observations.map(\.error).filter(\.isFinite).sorted()
        let correctCount = observations.filter(\.correct).count
        return AnalysisBenchmarkConceptSummary(
            concept: concept,
            labeledCount: observations.count,
            correctCount: correctCount,
            accuracy: rounded(observations.isEmpty ? 0 : Double(correctCount) / Double(observations.count)),
            errorP50: percentile(finiteErrors, 0.5).map(rounded),
            errorP95: percentile(finiteErrors, 0.95).map(rounded),
            calibration: calibration(observations)
        )
    }

    private static func calibration(_ observations: [Observation]) -> AnalysisBenchmarkCalibrationMetric? {
        let samples = observations.compactMap { observation -> (Double, Bool)? in
            guard let confidence = observation.confidence, confidence.isFinite else { return nil }
            return (min(1, max(0, confidence)), observation.correct)
        }
        guard !samples.isEmpty else { return nil }
        let binCount = 5
        var bins: [AnalysisBenchmarkCalibrationBin] = []
        var weightedGap = 0.0
        for index in 0..<binCount {
            let lower = Double(index) / Double(binCount)
            let upper = Double(index + 1) / Double(binCount)
            let binSamples = samples.filter { sample in
                index == binCount - 1 ? sample.0 >= lower && sample.0 <= upper : sample.0 >= lower && sample.0 < upper
            }
            guard !binSamples.isEmpty else { continue }
            let confidence = average(binSamples.map(\.0)) ?? 0
            let accuracy = Double(binSamples.filter(\.1).count) / Double(binSamples.count)
            weightedGap += abs(confidence - accuracy) * Double(binSamples.count) / Double(samples.count)
            bins.append(AnalysisBenchmarkCalibrationBin(
                lowerBound: rounded(lower),
                upperBound: rounded(upper),
                count: binSamples.count,
                meanConfidence: rounded(confidence),
                accuracy: rounded(accuracy)
            ))
        }
        let accuracy = Double(samples.filter(\.1).count) / Double(samples.count)
        let meanConfidence = average(samples.map(\.0)) ?? 0
        let brier = average(samples.map { confidence, correct in
            pow(confidence - (correct ? 1 : 0), 2)
        }) ?? 0
        return AnalysisBenchmarkCalibrationMetric(
            sampleCount: samples.count,
            accuracy: rounded(accuracy),
            meanConfidence: rounded(meanConfidence),
            expectedCalibrationError: rounded(weightedGap),
            brierScore: rounded(brier),
            bins: bins
        )
    }

    private static func nearestDistance(actual: [Double], expected: Double) -> Double {
        actual.filter(\.isFinite).map { abs($0 - expected) }.min() ?? .infinity
    }

    private static func seriesAverageDistance(actual: [Double], expected: [Double]) -> Double {
        let distances = expected.filter(\.isFinite).map { nearestDistance(actual: actual, expected: $0) }
        guard !distances.isEmpty, distances.allSatisfy(\.isFinite) else { return .infinity }
        return average(distances) ?? .infinity
    }

    private static func percentile(_ sorted: [Double], _ quantile: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int((Double(sorted.count - 1) * quantile).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}

public enum AnalysisBenchmarkCorpusGateEvaluator {
    public static func evaluate(
        report: AnalysisBenchmarkCorpusReport,
        configuration: AnalysisBenchmarkCorpusGateConfiguration
    ) -> AnalysisBenchmarkCorpusGateResult {
        var issues: [AnalysisBenchmarkCorpusGateIssue] = []
        if configuration.status == .approved {
            if configuration.approvedBy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(code: "gate_approver_missing", message: "Approved gates require approvedBy provenance."))
            }
            if configuration.approvedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(code: "gate_approval_date_missing", message: "Approved gates require approvedAt provenance."))
            }
        }
        if !report.integrityIssues.isEmpty {
            issues.append(.init(code: "corpus_integrity_failed", message: "Corpus has \(report.integrityIssues.count) integrity issue(s)."))
        }
        if report.realAudioFixtureCount < configuration.minimumRealAudioFixtures {
            issues.append(.init(
                code: "real_audio_coverage_low",
                message: "Real-audio fixtures \(report.realAudioFixtureCount) are below required \(configuration.minimumRealAudioFixtures)."
            ))
        }
        for (splitName, minimum) in configuration.minimumSplitCounts.sorted(by: { $0.key < $1.key }) {
            guard let split = AnalysisBenchmarkCorpusSplit(rawValue: splitName) else {
                issues.append(.init(code: "gate_split_unknown", message: "Gate uses unknown split \(splitName)."))
                continue
            }
            let actual = report.splitCounts[split] ?? 0
            if actual < minimum {
                issues.append(.init(code: "split_coverage_low", message: "Split \(split.rawValue) has \(actual), requires \(minimum)."))
            }
        }
        for (conceptName, gate) in configuration.concepts.sorted(by: { $0.key < $1.key }) {
            guard let concept = AnalysisBenchmarkConcept(rawValue: conceptName) else {
                issues.append(.init(code: "gate_concept_unknown", message: "Gate uses unknown concept \(conceptName)."))
                continue
            }
            guard let summary = report.conceptSummaries.first(where: { $0.concept == concept }) else {
                issues.append(.init(code: "concept_missing", message: "Concept \(concept.rawValue) has no summary."))
                continue
            }
            if summary.labeledCount < gate.minimumLabeledCount {
                issues.append(.init(code: "concept_coverage_low", message: "Concept \(concept.rawValue) has \(summary.labeledCount), requires \(gate.minimumLabeledCount)."))
            }
            if let minimumAccuracy = gate.minimumAccuracy, summary.accuracy < minimumAccuracy {
                issues.append(.init(code: "concept_accuracy_low", message: "Concept \(concept.rawValue) accuracy \(summary.accuracy) is below \(minimumAccuracy)."))
            }
            if let maximumP95 = gate.maximumP95Error,
               (summary.errorP95 ?? .infinity) > maximumP95 {
                issues.append(.init(code: "concept_p95_high", message: "Concept \(concept.rawValue) p95 \(summary.errorP95 ?? .infinity) exceeds \(maximumP95)."))
            }
            if let minimumSamples = gate.minimumCalibrationSamples,
               (summary.calibration?.sampleCount ?? 0) < minimumSamples {
                issues.append(.init(code: "calibration_coverage_low", message: "Concept \(concept.rawValue) calibration has \(summary.calibration?.sampleCount ?? 0), requires \(minimumSamples)."))
            }
            if let maximumECE = gate.maximumExpectedCalibrationError,
               (summary.calibration?.expectedCalibrationError ?? .infinity) > maximumECE {
                issues.append(.init(code: "calibration_ece_high", message: "Concept \(concept.rawValue) ECE exceeds \(maximumECE)."))
            }
            if let maximumBrier = gate.maximumBrierScore,
               (summary.calibration?.brierScore ?? .infinity) > maximumBrier {
                issues.append(.init(code: "calibration_brier_high", message: "Concept \(concept.rawValue) Brier score exceeds \(maximumBrier)."))
            }
        }
        return AnalysisBenchmarkCorpusGateResult(
            status: configuration.status,
            enforceable: configuration.status == .approved,
            meetsThresholds: issues.isEmpty,
            issues: issues
        )
    }
}
