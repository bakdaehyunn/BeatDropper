import BeatDropperCore
import Foundation
import Testing

struct AnalysisBenchmarkCorpusTests {
    @Test func realAudioCorpusSummarizesEveryGoalTwoConceptAndCalibration() throws {
        let fixture = richFixture()
        let report = AnalysisBenchmarkCorpusEvaluator.evaluate([fixture])

        #expect(report.realAudioFixtureCount == 1)
        #expect(report.splitCounts[.calibration] == 1)
        #expect(report.integrityIssues.isEmpty)
        for concept in AnalysisBenchmarkConcept.allCases {
            let summary = try #require(report.conceptSummaries.first { $0.concept == concept })
            #expect(summary.labeledCount > 0)
            #expect(summary.accuracy == 1)
            #expect(summary.errorP95 == 0)
            #expect(summary.calibration?.sampleCount ?? 0 > 0)
        }
    }

    @Test func repeatedDownbeatsParticipateInFixtureEvaluation() {
        let fixture = richFixture()
        let result = AnalysisBenchmarkEvaluator.evaluateFixture(fixture).result

        #expect(result.downbeats.checkedCount == 4)
        #expect(result.downbeats.averageDistanceSec == 0)
        #expect(result.downbeats.maxDistanceSec == 0)
        #expect(result.issues.contains { $0.code == "downbeat_grid_distance_high" } == false)
    }

    @Test func integrityRejectsUnreviewedOrIncompleteRealAudioFixture() {
        let fixture = AnalysisBenchmarkFixture(
            id: "invalid-real",
            title: "Invalid real fixture",
            kind: .realAudio,
            expected: AnalysisBenchmarkExpectation(bpm: 124),
            groundTruthLabels: AnalysisBenchmarkGroundTruthLabels(
                schemaVersion: 2,
                reviewedBy: "UNREVIEWED",
                reviewedAt: nil,
                expected: AnalysisBenchmarkExpectation(bpm: 124)
            ),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot(bpm: 124, bpmConfidence: 0.8)
        )

        let report = AnalysisBenchmarkCorpusEvaluator.evaluate([fixture])
        let codes = Set(report.integrityIssues.map(\.code))

        #expect(codes.contains("corpus_metadata_missing"))
    }

    @Test func candidateGateReportsCoverageButCannotBeEnforced() {
        let report = AnalysisBenchmarkCorpusEvaluator.evaluate([richFixture()])
        let concepts = Dictionary(uniqueKeysWithValues: AnalysisBenchmarkConcept.allCases.map {
            ($0.rawValue, AnalysisBenchmarkConceptGate(
                minimumLabeledCount: 1,
                minimumAccuracy: 1,
                maximumP95Error: 0,
                minimumCalibrationSamples: 1,
                maximumExpectedCalibrationError: 0.25,
                maximumBrierScore: 0.25
            ))
        })
        let configuration = AnalysisBenchmarkCorpusGateConfiguration(
            status: .candidate,
            minimumRealAudioFixtures: 1,
            minimumSplitCounts: ["calibration": 1],
            concepts: concepts
        )

        let gate = AnalysisBenchmarkCorpusGateEvaluator.evaluate(
            report: report,
            configuration: configuration
        )

        #expect(gate.status == .candidate)
        #expect(gate.enforceable == false)
        #expect(gate.meetsThresholds == true)
        #expect(gate.issues.isEmpty)
    }

    @Test func integrityRejectsDuplicateAssetsAcrossSplitsAndLegacyLabels() {
        let calibration = richFixture()
        var validation = richFixture()
        validation.id = "real-rich-002"
        validation.corpus?.split = .validation
        validation.groundTruthLabels?.schemaVersion = 1

        let report = AnalysisBenchmarkCorpusEvaluator.evaluate([calibration, validation])
        let codes = Set(report.integrityIssues.map(\.code))

        #expect(codes.contains("asset_id_duplicate"))
        #expect(codes.contains("labels_schema_unsupported"))
        #expect(report.splitCounts[.calibration] == 1)
        #expect(report.splitCounts[.validation] == 1)
    }

    @Test func approvedGateRequiresApprovalProvenance() {
        let report = AnalysisBenchmarkCorpusEvaluator.evaluate([richFixture()])
        let configuration = AnalysisBenchmarkCorpusGateConfiguration(
            status: .approved,
            minimumRealAudioFixtures: 1,
            minimumSplitCounts: ["calibration": 1],
            concepts: [:]
        )

        let missing = AnalysisBenchmarkCorpusGateEvaluator.evaluate(report: report, configuration: configuration)
        #expect(missing.enforceable == true)
        #expect(missing.meetsThresholds == false)
        #expect(missing.issues.contains { $0.code == "gate_approver_missing" })
        #expect(missing.issues.contains { $0.code == "gate_approval_date_missing" })

        var approved = configuration
        approved.approvedBy = "user-goal-approval"
        approved.approvedAt = "2026-08-15T00:00:00+09:00"
        let valid = AnalysisBenchmarkCorpusGateEvaluator.evaluate(report: report, configuration: approved)
        #expect(valid.meetsThresholds == true)
        #expect(valid.issues.isEmpty)
    }

    private func richFixture() -> AnalysisBenchmarkFixture {
        let expected = AnalysisBenchmarkExpectation(
            bpm: 120,
            firstDownbeatSec: 0,
            downbeatSec: [0, 8, 16, 24],
            outroCueSec: 96,
            barGridSec: [0, 8, 16, 24],
            phraseBoundarySec: [0, 64],
            plannerReady: true,
            musicalKey: AnalysisBenchmarkKeyExpectation(tonic: "C", mode: .minor, minConfidence: 0.7),
            loudness: AnalysisBenchmarkLoudnessExpectation(
                integratedLUFS: -12,
                truePeakDb: -1,
                minConfidence: 0.7
            ),
            cueCandidates: [
                AnalysisBenchmarkCueExpectation(type: .firstDownbeat, startSec: 0, minConfidence: 0.7, origin: .derived),
                AnalysisBenchmarkCueExpectation(type: .outro, startSec: 96, minConfidence: 0.7, origin: .derived)
            ]
        )
        return AnalysisBenchmarkFixture(
            id: "real-rich-001",
            title: "Anonymized real fixture",
            kind: .realAudio,
            tags: ["house", "fixed-tempo"],
            expectedGrade: .pass,
            corpus: AnalysisBenchmarkCorpusMetadata(
                split: .calibration,
                anonymizedAssetId: "asset-001",
                audioRights: .privateUserOwned,
                audioDurationSec: 120,
                sampleRate: 48_000,
                channelCount: 2,
                genreTags: ["house"],
                tempoProfile: .fixed,
                referenceTools: [AnalysisBenchmarkReferenceTool(name: "reference", version: "1")]
            ),
            expected: expected,
            groundTruthLabels: AnalysisBenchmarkGroundTruthLabels(
                schemaVersion: 2,
                reviewedBy: "reviewer-01",
                reviewedAt: "2026-08-10T00:00:00Z",
                notes: "Independently reviewed",
                expected: expected
            ),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot(
                trackId: "real-rich-001",
                source: .derived,
                bpm: 120,
                bpmConfidence: 0.9,
                beatGridSec: stride(from: 0.0, through: 24.0, by: 0.5).map { $0 },
                downbeatsSec: [0, 8, 16, 24],
                barGrid: [0.0, 8, 16, 24].enumerated().map {
                    BarMarker(index: $0.offset, startSec: $0.element, beatIndex: $0.offset * 4)
                },
                phraseMarkers: [
                    PhraseMarker(index: 0, startSec: 0, bars: 8, confidence: 0.9),
                    PhraseMarker(index: 1, startSec: 64, bars: 8, confidence: 0.9)
                ],
                introCueSec: 0,
                outroCueSec: 96,
                energyProfile: [0.7, 0.8],
                waveformDetail: [WaveformDetailPoint(timeSec: 0, peak: 0.8, rms: 0.4, min: -0.8, max: 0.8)],
                cueCandidates: [
                    CueCandidate(id: "downbeat", type: .firstDownbeat, startSec: 0, endSec: 4, confidence: 0.9, label: "Downbeat", origin: .derived),
                    CueCandidate(id: "outro", type: .outro, startSec: 96, endSec: 104, confidence: 0.9, label: "Outro", origin: .derived)
                ],
                musicalKey: MusicalKeyEstimate(tonic: "C", mode: .minor, confidence: 0.9, chromaEnergy: 100),
                loudness: LoudnessAnalysis(
                    integratedRMSDb: -12.5,
                    integratedLUFS: -12,
                    peakDb: -1.2,
                    truePeakDb: -1,
                    headroomDb: 1,
                    crestFactorDb: 8,
                    dynamicRangeDb: 6,
                    confidence: 0.9
                ),
                analysisConfidence: 0.9,
                analysisQuality: AnalysisQuality(
                    waveformDetail: 0.9,
                    spectralBands: 0.9,
                    transientMarkers: 0.9,
                    beatGrid: 0.9,
                    harmonicKey: 0.9
                ),
                analysisWarnings: []
            )
        )
    }
}
