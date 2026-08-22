import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct RenderedTransitionQualityTests {
    @Test func cleanTransitionPassesRenderedQualityEstimate() {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan(
                mixControls: MixControlPlan(
                    gain: MixGainPlan(outgoingTrimDb: 0, incomingTrimDb: -2),
                    clipProtection: .conservativeDefaults
                )
            ),
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: analysis(
                trackId: "current",
                waveform: [
                    (98, 0.48, 0.24),
                    (100, 0.5, 0.25),
                    (104, 0.5, 0.24)
                ],
                spectral: [
                    (100, 0.28, 0.36, 0.22),
                    (104, 0.24, 0.32, 0.2)
                ]
            ),
            nextAnalysis: analysis(
                trackId: "next",
                waveform: [
                    (0, 0.44, 0.22),
                    (4, 0.46, 0.23),
                    (6, 0.44, 0.22)
                ],
                spectral: [
                    (0, 0.16, 0.26, 0.18),
                    (4, 0.18, 0.28, 0.18)
                ]
            )
        )

        #expect(report.grade == .pass)
        #expect(report.shouldApply == true)
        #expect(report.issues.isEmpty)
        #expect(report.metrics.contains { $0.name == "estimated_peak" })
    }

    @Test func clippingRiskRejectsRenderedQualityEstimate() {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan(),
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: analysis(
                trackId: "current",
                waveform: [
                    (98, 0.6, 0.28),
                    (100, 0.95, 0.4),
                    (104, 0.95, 0.4)
                ],
                spectral: [(100, 0.4, 0.4, 0.3)]
            ),
            nextAnalysis: analysis(
                trackId: "next",
                waveform: [
                    (0, 0.95, 0.4),
                    (4, 0.95, 0.4),
                    (6, 0.6, 0.28)
                ],
                spectral: [(0, 0.4, 0.4, 0.3)]
            )
        )

        #expect(report.grade == .reject)
        #expect(report.shouldApply == false)
        #expect(report.issues.contains { $0.code == .clippingRisk && $0.severity == .critical })
    }

    @Test func peakAndRMSJumpsAreReportedWithoutChangingExecution() {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan(),
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: analysis(
                trackId: "current",
                waveform: [
                    (98, 0.16, 0.08),
                    (100, 0.55, 0.4),
                    (104, 0.55, 0.4)
                ],
                spectral: [(100, 0.2, 0.2, 0.2)]
            ),
            nextAnalysis: analysis(
                trackId: "next",
                waveform: [
                    (0, 0.55, 0.4),
                    (4, 0.55, 0.4),
                    (6, 0.16, 0.08)
                ],
                spectral: [(0, 0.2, 0.2, 0.2)]
            )
        )

        #expect(report.grade == .warn)
        #expect(report.shouldApply == true)
        #expect(report.issues.contains { $0.code == .peakJump })
        #expect(report.issues.contains { $0.code == .rmsJump })
    }

    @Test func spectralMaskingRiskIsReportedForDenseOverlappingBands() {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan(),
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: analysis(
                trackId: "current",
                waveform: [
                    (98, 0.32, 0.18),
                    (100, 0.36, 0.2),
                    (104, 0.36, 0.2)
                ],
                spectral: [
                    (100, 0.95, 0.9, 0.82),
                    (104, 0.95, 0.9, 0.82)
                ]
            ),
            nextAnalysis: analysis(
                trackId: "next",
                waveform: [
                    (0, 0.36, 0.2),
                    (4, 0.36, 0.2),
                    (6, 0.32, 0.18)
                ],
                spectral: [
                    (0, 0.92, 0.88, 0.8),
                    (4, 0.92, 0.88, 0.8)
                ]
            )
        )

        #expect(report.grade == .warn)
        #expect(report.shouldApply == true)
        #expect(report.issues.contains { $0.code == .spectralMaskingRisk })
    }

    @Test func missingAnalysisProducesWarningButNotRejection() {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan(),
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: nil,
            nextAnalysis: nil
        )

        #expect(report.grade == .warn)
        #expect(report.shouldApply == true)
        #expect(report.issues.contains { $0.code == .missingAnalysis })
    }

    private var currentTrack: Track {
        Track(id: "current", title: "Current", durationSec: 120, format: .wav, bpm: 124)
    }

    private var nextTrack: Track {
        Track(id: "next", title: "Next", durationSec: 120, format: .wav, bpm: 124)
    }

    private func plan(mixControls: MixControlPlan? = .conservativeDefaults) -> MixPlan {
        MixPlan(
            transitionStartSec: 100,
            transitionEndSec: 104,
            nextTrackStartOffsetSec: 0,
            style: .smoothBlend,
            confidence: 0.82,
            reasoningSummary: "test plan",
            tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil),
            mixControls: mixControls
        )
    }

    private func analysis(
        trackId: String,
        waveform: [(Double, Double, Double)],
        spectral: [(Double, Double, Double, Double)]
    ) -> TrackAnalysis {
        TrackAnalysis(
            trackId: trackId,
            generatedAt: "2026-06-15T00:00:00Z",
            source: .derived,
            bpm: 124,
            bpmConfidence: 0.86,
            beatGridSec: [0, 0.48, 0.96],
            downbeatsSec: [0],
            barGrid: [BarMarker(index: 0, startSec: 0, beatIndex: 0)],
            phraseMarkers: [PhraseMarker(index: 0, startSec: 0, bars: 8, confidence: 0.8)],
            introCueSec: 0,
            outroCueSec: 100,
            energyProfile: [0.4, 0.5, 0.45],
            waveformPeaks: waveform.map {
                WaveformPeak(timeSec: $0.0, peak: $0.1, rms: $0.2)
            },
            waveformDetail: waveform.map {
                WaveformDetailPoint(timeSec: $0.0, peak: $0.1, rms: $0.2, min: -$0.1, max: $0.1)
            },
            spectralBands: spectral.map {
                SpectralBandPoint(timeSec: $0.0, low: $0.1, mid: $0.2, high: $0.3)
            },
            transientMarkers: [TransientMarker(index: 0, timeSec: 0, strength: 0.8)],
            cueCandidates: [],
            analysisConfidence: 0.82,
            analysisQuality: AnalysisQuality(
                waveformDetail: 0.8,
                spectralBands: 0.8,
                transientMarkers: 0.8,
                beatGrid: 0.8
            ),
            analysisWarnings: [.beatGridEstimated]
        )
    }
}
