import BeatDropperCore
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
                CueCandidate(id: "first", type: .firstDownbeat, startSec: firstDownbeat, endSec: firstDownbeat + 4, confidence: 0.8, label: "First"),
                outro.map { CueCandidate(id: "outro", type: .outro, startSec: $0, endSec: $0 + 8, confidence: 0.8, label: "Outro") }
            ].compactMap { $0 },
            analysisConfidence: ready ? 0.8 : 0.3,
            analysisQuality: AnalysisQuality(
                waveformDetail: ready ? 0.8 : 0,
                spectralBands: 0.8,
                transientMarkers: ready ? 0.8 : 0.2,
                beatGrid: ready ? 0.8 : 0.2
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
            analysisConfidence: analysis.analysisConfidence,
            analysisQuality: analysis.analysisQuality,
            analysisWarnings: analysis.analysisWarnings
        )
    }
}
