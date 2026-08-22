import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Testing

struct AnalysisBenchmarkTests {
    @Test func cleanFixtureShapePassesBenchmark() {
        let fixture = Self.analysis(
            trackId: "clean",
            bpm: 124.1,
            bars: [0, 7.742, 15.484],
            phrases: [0],
            firstDownbeat: 0,
            outro: 96.2,
            ready: true
        )

        #expect(fixture.result.result.grade == AnalysisBenchmarkGrade.pass)
        #expect(fixture.result.result.bpmError == 0.1)
        #expect(fixture.result.result.plannerReadyMatch == true)
    }

    @Test func weakFixtureShapeFailsBenchmark() {
        let fixture = Self.analysis(
            trackId: "weak",
            bpm: 136,
            bars: [3.4, 10.2],
            phrases: [],
            firstDownbeat: 3.4,
            outro: 83,
            ready: false
        )

        #expect(fixture.result.result.grade == AnalysisBenchmarkGrade.fail)
        #expect(fixture.result.result.issues.contains { $0.code == "bpm_error_high" })
        #expect(fixture.result.result.issues.contains { $0.code == "phrase_missing" })
    }

    @Test func suiteSummarizesGrades() {
        let passFixture = AnalysisBenchmarkFixture(
            id: "pass",
            title: "Pass",
            kind: .synthetic,
            tags: [],
            expectedGrade: .pass,
            expected: Self.expectation(),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot.from(Self.analysis(
                trackId: "pass",
                bpm: 124,
                bars: [0, 7.742],
                phrases: [0],
                firstDownbeat: 0,
                outro: 96,
                ready: true
            ).resultAnalysis),
            thresholds: nil
        )
        let failFixture = AnalysisBenchmarkFixture(
            id: "fail",
            title: "Fail",
            kind: .synthetic,
            tags: [],
            expectedGrade: .fail,
            expected: Self.expectation(),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot.from(Self.analysis(
                trackId: "fail",
                bpm: 140,
                bars: [],
                phrases: [],
                firstDownbeat: 12,
                outro: nil,
                ready: false
            ).resultAnalysis),
            thresholds: nil
        )

        let suite = AnalysisBenchmarkEvaluator.evaluateSuite([passFixture, failFixture])

        #expect(suite.grade == AnalysisBenchmarkGrade.fail)
        #expect(suite.passed == 1)
        #expect(suite.failed == 1)
        #expect(suite.byKind.first?.total == 2)
    }

    @Test func schemaV7CalibrationChecksKeyLoudnessStereoCueAndReadiness() {
        let analysis = Self.analysis(
            trackId: "schema-v7",
            bpm: 124,
            bars: [0, 8, 16, 24],
            phrases: [0, 64],
            firstDownbeat: 0,
            outro: 96,
            ready: true
        ).resultAnalysis
        let fixture = AnalysisBenchmarkFixture(
            id: "schema-v7",
            title: "Schema v7 calibration",
            kind: .snapshot,
            tags: ["schema-v7", "key", "loudness", "stereo"],
            expectedGrade: .pass,
            expected: AnalysisBenchmarkExpectation(
                bpm: 124,
                firstDownbeatSec: 0,
                outroCueSec: 96,
                barGridSec: [0, 8, 16, 24],
                phraseBoundarySec: [0, 64],
                plannerReady: true,
                musicalKey: AnalysisBenchmarkKeyExpectation(tonic: "C", mode: .minor, minConfidence: 0.4),
                loudness: AnalysisBenchmarkLoudnessExpectation(
                    integratedRMSDb: -10.2,
                    integratedLUFS: -9.8,
                    peakDb: -0.7,
                    truePeakDb: -0.55,
                    minHeadroomDb: 0.5,
                    minConfidence: 0.7
                ),
                stereo: AnalysisBenchmarkStereoExpectation(
                    channelCount: 2,
                    minStereoWidth: 0.2,
                    maxStereoWidth: 0.8,
                    minPhaseCorrelation: 0.4,
                    maxMidSideBalance: 4,
                    minConfidence: 0.7
                ),
                cueCandidates: [
                    AnalysisBenchmarkCueExpectation(type: .firstDownbeat, startSec: 0, minConfidence: 0.7, origin: .derived),
                    AnalysisBenchmarkCueExpectation(type: .outro, startSec: 96, minConfidence: 0.7, origin: .derived)
                ],
                mixReadiness: AnalysisBenchmarkMixReadinessExpectation(
                    minAnalysisConfidence: 0.78,
                    minHarmonicKeyQuality: 0.4,
                    minLoudnessConfidence: 0.7,
                    forbiddenWarnings: [.keyUnavailable, .loudnessLowConfidence]
                )
            ),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot.from(analysis),
            thresholds: nil
        )

        let result = AnalysisBenchmarkEvaluator.evaluateFixture(fixture).result

        #expect(result.grade == .pass)
        #expect(result.musicalKey?.matched == true)
        #expect(result.loudness?.integratedRMSDeltaDb == 0)
        #expect(result.loudness?.integratedLUFSDelta == 0)
        #expect(result.loudness?.truePeakDeltaDb == 0)
        #expect(result.loudness?.measurement == "ebu_r128_k_weighted_gated_mono")
        #expect(result.stereo?.actualChannelCount == 2)
        #expect(result.stereo?.stereoWidth == 0.32)
        #expect(result.stereo?.phaseCorrelation == 0.72)
        #expect(result.cueCandidates.count == 2)
        #expect(result.mixReadiness?.forbiddenWarningsPresent == [])
    }

    @Test func editableGroundTruthLabelsOverrideStaleFixtureExpectedValues() {
        let analysis = Self.analysis(
            trackId: "editable-labels",
            bpm: 124,
            bars: [0, 8, 16, 24],
            phrases: [0, 64],
            firstDownbeat: 0,
            outro: 96,
            ready: true
        ).resultAnalysis
        let fixture = AnalysisBenchmarkFixture(
            id: "editable-labels",
            title: "Editable labels",
            kind: .snapshot,
            tags: ["labels"],
            expectedGrade: .pass,
            expected: AnalysisBenchmarkExpectation(bpm: 130, firstDownbeatSec: 12),
            groundTruthLabels: AnalysisBenchmarkGroundTruthLabels(
                schemaVersion: 1,
                reviewedBy: "user",
                reviewedAt: "2026-07-02T00:00:00.000Z",
                expected: AnalysisBenchmarkExpectation(
                    bpm: 124,
                    firstDownbeatSec: 0,
                    loudness: AnalysisBenchmarkLoudnessExpectation(
                        integratedLUFS: -9.8,
                        truePeakDb: -0.55,
                        minConfidence: 0.7
                    )
                )
            ),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot.from(analysis),
            thresholds: nil
        )

        let result = AnalysisBenchmarkEvaluator.evaluateFixture(fixture).result

        #expect(result.grade == .pass)
        #expect(result.bpmError == 0)
        #expect(result.firstDownbeat?.distanceSec == 0)
        #expect(result.loudness?.integratedLUFSDelta == 0)
    }

    private static func expectation() -> AnalysisBenchmarkExpectation {
        AnalysisBenchmarkExpectation(
            bpm: 124,
            firstDownbeatSec: 0,
            outroCueSec: 96,
            barGridSec: [0, 7.742],
            phraseBoundarySec: [0],
            plannerReady: true
        )
    }

    private static func analysis(
        trackId: String,
        bpm: Double,
        bars: [Double],
        phrases: [Double],
        firstDownbeat: Double,
        outro: Double?,
        ready: Bool
    ) -> (result: AnalysisBenchmarkFixtureResult, resultAnalysis: TrackAnalysis) {
        let trackAnalysis = TrackAnalysis(
            trackId: trackId,
            generatedAt: "test",
            source: .derived,
            bpm: bpm,
            bpmConfidence: ready ? 0.8 : 0.3,
            beatGridSec: [0, 1.936, 3.871],
            downbeatsSec: [firstDownbeat],
            barGrid: bars.enumerated().map { BarMarker(index: $0.offset, startSec: $0.element, beatIndex: $0.offset * 4) },
            phraseMarkers: phrases.enumerated().map { PhraseMarker(index: $0.offset, startSec: $0.element, bars: 8, confidence: 0.8) },
            introCueSec: 0,
            outroCueSec: outro,
            energyProfile: ready ? [0.8, 0.7, 0.5] : [0.4],
            waveformPeaks: [WaveformPeak(timeSec: 0, peak: 0.8, rms: 0.4)],
            waveformDetail: ready ? [WaveformDetailPoint(timeSec: 0, peak: 0.8, rms: 0.4, min: -0.7, max: 0.8)] : [],
            spectralBands: [SpectralBandPoint(timeSec: 0, low: 0.5, mid: 0.4, high: 0.3)],
            transientMarkers: [TransientMarker(index: 0, timeSec: firstDownbeat, strength: 0.8)],
            cueCandidates: [
                CueCandidate(id: "first", type: .firstDownbeat, startSec: firstDownbeat, endSec: firstDownbeat + 4, confidence: 0.8, label: "First", origin: .derived),
                outro.map { CueCandidate(id: "outro", type: .outro, startSec: $0, endSec: $0 + 8, confidence: 0.8, label: "Outro", origin: .derived) }
            ].compactMap { $0 },
            musicalKey: MusicalKeyEstimate(tonic: "C", mode: .minor, confidence: 0.45, chromaEnergy: 128),
            loudness: LoudnessAnalysis(
                integratedRMSDb: -10.2,
                integratedLUFS: -9.8,
                peakDb: -0.7,
                truePeakDb: -0.55,
                headroomDb: 0.7,
                crestFactorDb: 9.5,
                dynamicRangeDb: 12.8,
                loudnessRangeLU: 4.1,
                measurement: "ebu_r128_k_weighted_gated_mono",
                confidence: 0.82
            ),
            stereo: StereoAnalysis(
                channelCount: 2,
                leftPeakDb: -0.7,
                rightPeakDb: -1.1,
                leftRMSDb: -10.1,
                rightRMSDb: -10.6,
                stereoWidth: 0.32,
                phaseCorrelation: 0.72,
                midSideBalance: 2.15,
                confidence: 0.86
            ),
            analysisConfidence: ready ? 0.8 : 0.3,
            analysisQuality: AnalysisQuality(
                waveformDetail: ready ? 0.8 : 0,
                spectralBands: 0.8,
                transientMarkers: ready ? 0.8 : 0.2,
                beatGrid: ready ? 0.8 : 0.2,
                harmonicKey: ready ? 0.45 : 0.2
            ),
            analysisWarnings: ready ? [] : [.bpmLowConfidence]
        )
        let fixture = AnalysisBenchmarkFixture(
            id: trackId,
            title: trackId,
            kind: .synthetic,
            tags: [],
            expectedGrade: nil,
            expected: Self.expectation(),
            analysis: AnalysisBenchmarkTrackAnalysisSnapshot.from(trackAnalysis),
            thresholds: nil
        )
        return (AnalysisBenchmarkEvaluator.evaluateFixture(fixture), trackAnalysis)
    }
}

private extension AnalysisBenchmarkTrackAnalysisSnapshot {
    static func from(_ analysis: TrackAnalysis) -> AnalysisBenchmarkTrackAnalysisSnapshot {
        AnalysisBenchmarkTrackAnalysisSnapshot(
            trackId: analysis.trackId,
            source: analysis.source,
            bpm: analysis.bpm,
            bpmConfidence: analysis.bpmConfidence,
            beatGridSec: analysis.beatGridSec,
            downbeatsSec: analysis.downbeatsSec,
            barGrid: analysis.barGrid,
            phraseMarkers: analysis.phraseMarkers,
            introCueSec: analysis.introCueSec,
            outroCueSec: analysis.outroCueSec,
            energyProfile: analysis.energyProfile,
            waveformPeaks: analysis.waveformPeaks,
            waveformDetail: analysis.waveformDetail,
            spectralBands: analysis.spectralBands,
            transientMarkers: analysis.transientMarkers,
            cueCandidates: analysis.cueCandidates,
            musicalKey: analysis.musicalKey,
            loudness: analysis.loudness,
            stereo: analysis.stereo,
            analysisConfidence: analysis.analysisConfidence,
            analysisQuality: analysis.analysisQuality,
            analysisWarnings: analysis.analysisWarnings
        )
    }
}
