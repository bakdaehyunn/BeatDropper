import BeatDropperCore
import Foundation
import Testing

struct PlannerEvidenceTests {
    @Test func plannerRequestIncludesSummaryAndPairContext() throws {
        let currentTrack = Track(id: "current", title: "Current", durationSec: 180, format: .wav, bpm: 124)
        let nextTrack = Track(id: "next", title: "Next", durationSec: 190, format: .wav, bpm: 126)
        let currentAnalysis = analysis(trackId: "current", durationSec: 180, bpm: 124, outroSec: 160)
        let nextAnalysis = analysis(trackId: "next", durationSec: 190, bpm: 126, outroSec: 172)

        let request = PlannerRequestBuilder.build(
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            elapsedSec: 130,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis,
            currentPreparation: TrackPreparation(
                bpmOverride: 123.8,
                hotCues: [TrackPreparationCue(id: "prep-out", kind: .outro, timeSec: 158, label: "Prep outro")]
            ),
            nextPreparation: TrackPreparation(
                hotCues: [TrackPreparationCue(id: "prep-drop", kind: .drop, timeSec: 32, label: "Drop")]
            ),
            settings: PlannerSettingsSnapshot(fadeDurationSec: 8, aiDjMode: .balanced)
        )

        #expect(request.analysisSummary?.current?.plannerReady == true)
        #expect(request.analysisSummary?.next?.cues.firstDownbeat != nil)
        #expect(request.analysisSummary?.current?.mixWindows.mixOut.contains { $0.kind == .outro } == true)
        #expect(request.analysisSummary?.next?.mixWindows.mixIn.contains { $0.kind == .firstDownbeat } == true)
        #expect(request.pairContext?.readiness == .ready)
        #expect(request.pairContext?.recommendedCandidateId != nil)
        #expect(request.preparation?.current?.bpmOverride == 123.8)
        #expect(request.preparation?.next?.hotCues.first?.kind == .drop)

        let encoded = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["analysisSummary"] != nil)
        #expect(object["pairContext"] != nil)
        #expect(object["preparation"] != nil)
    }

    @Test func pairContextFallsBackWhenAnalysisIsMissing() {
        let currentTrack = Track(id: "current", title: "Current", durationSec: 180, format: .wav)
        let nextTrack = Track(id: "next", title: "Next", durationSec: 190, format: .wav)

        let context = PlannerEvidenceBuilder.buildMixPairContext(
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: nil,
            nextAnalysis: nil
        )

        #expect(context.readiness == .analysisPending)
        #expect(context.candidates.allSatisfy { $0.source == .tailFallback })
    }

    @Test func mixPlanValidationClampsTimingAndNextOffset() throws {
        let candidate = MixPlan(
            transitionStartSec: 100,
            transitionEndSec: 130,
            nextTrackStartOffsetSec: 500,
            style: .smoothBlend,
            confidence: 1.4,
            reasoningSummary: "candidate",
            tempoSync: MixTempoSyncPlan(enabled: true, targetRate: 1.4),
            evidence: Array(repeating: "evidence", count: 12)
        )

        let result = MixPlanValidator.validateAndClamp(
            candidate,
            context: MixPlanValidationContext(
                currentPlaybackElapsedSec: 120,
                currentTrackDurationSec: 150,
                nextTrackDurationSec: 190,
                maxFadeDurationSec: 8
            )
        )

        let plan = try #require(result.plan)
        #expect(plan.transitionStartSec == 122)
        #expect(plan.transitionEndSec == 130)
        #expect(plan.nextTrackStartOffsetSec == 190)
        #expect(plan.confidence == 1)
        #expect(plan.tempoSync.targetRate == 1.15)
        #expect(plan.evidence.count == 8)
        #expect(plan.mixControls?.gain.outgoingTrimDb == 0)
        #expect(plan.mixControls?.clipProtection.mode == .monitorOnly)
    }

    @Test func mixPlanValidationClampsMixControls() throws {
        let candidate = MixPlan(
            transitionStartSec: 120,
            transitionEndSec: 128,
            nextTrackStartOffsetSec: 16,
            style: .energySwap,
            confidence: 0.8,
            reasoningSummary: "candidate",
            tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil),
            mixControls: MixControlPlan(
                gain: MixGainPlan(outgoingTrimDb: -50, incomingTrimDb: 20),
                eq: MixThreeBandEQPlan(
                    outgoingLowDb: -40,
                    outgoingMidDb: 12,
                    outgoingHighDb: 0.5,
                    incomingLowDb: 9,
                    incomingMidDb: -20,
                    incomingHighDb: 0
                ),
                filter: MixFilterPlan(
                    outgoingMode: .lowPass,
                    outgoingStartHz: 5,
                    outgoingEndHz: 40_000,
                    incomingMode: .disabled,
                    incomingStartHz: 200,
                    incomingEndHz: 500
                ),
                loudness: MixLoudnessPlan(targetIntegratedLufs: -40, maxPeakDb: 2),
                clipProtection: MixClipProtectionPlan(enabled: true, mode: .softLimit, ceilingDb: -20),
                qualityNotes: Array(repeating: "note", count: 8)
            )
        )

        let result = MixPlanValidator.validateAndClamp(
            candidate,
            context: MixPlanValidationContext(
                currentPlaybackElapsedSec: 100,
                currentTrackDurationSec: 150,
                nextTrackDurationSec: 190,
                maxFadeDurationSec: 8
            )
        )

        let controls = try #require(result.plan?.mixControls)
        #expect(controls.gain.outgoingTrimDb == -12)
        #expect(controls.gain.incomingTrimDb == 6)
        #expect(controls.eq.outgoingLowDb == -12)
        #expect(controls.eq.outgoingMidDb == 6)
        #expect(controls.eq.incomingLowDb == 6)
        #expect(controls.eq.incomingMidDb == -12)
        #expect(controls.filter.outgoingStartHz == 20)
        #expect(controls.filter.outgoingEndHz == 20_000)
        #expect(controls.filter.incomingStartHz == nil)
        #expect(controls.loudness.targetIntegratedLufs == -24)
        #expect(controls.loudness.maxPeakDb == -0.1)
        #expect(controls.clipProtection.mode == .softLimit)
        #expect(controls.clipProtection.ceilingDb == -6)
        #expect(controls.qualityNotes.count == 6)
    }

    @Test func mixPlanSchedulerStartsAtTransitionStartWithTolerance() {
        let plan = MixPlan(
            transitionStartSec: 120,
            transitionEndSec: 128,
            nextTrackStartOffsetSec: 16,
            style: .smoothBlend,
            confidence: 0.8,
            reasoningSummary: nil,
            tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil)
        )

        #expect(MixPlanScheduler.secondsUntilTransition(plan: plan, elapsedSec: 110) == 10)
        #expect(MixPlanScheduler.shouldStartTransition(plan: plan, elapsedSec: 119.7) == false)
        #expect(MixPlanScheduler.shouldStartTransition(plan: plan, elapsedSec: 119.85) == true)
        #expect(MixPlanScheduler.shouldStartTransition(plan: plan, elapsedSec: 121) == true)
    }

    private func analysis(trackId: String, durationSec: Double, bpm: Double, outroSec: Double) -> TrackAnalysis {
        let beat = 60 / bpm
        let beatGrid = stride(from: 0.0, through: durationSec, by: beat).prefix(320).map { $0 }
        let bars = beatGrid.enumerated()
            .filter { $0.offset % 4 == 0 }
            .map { index, value in
                BarMarker(index: index, startSec: value, beatIndex: index * 4)
            }
        let phrases = bars
            .filter { $0.index % 8 == 0 }
            .map {
                PhraseMarker(index: $0.index / 8, startSec: $0.startSec, bars: 8, confidence: 0.78)
            }

        return TrackAnalysis(
            trackId: trackId,
            generatedAt: "2026-05-25T00:00:00Z",
            source: .derived,
            bpm: bpm,
            bpmConfidence: 0.82,
            beatGridSec: Array(beatGrid),
            downbeatsSec: bars.map(\.startSec),
            barGrid: bars,
            phraseMarkers: phrases,
            introCueSec: 0,
            outroCueSec: outroSec,
            energyProfile: [0.2, 0.35, 0.5, 0.62, 0.58, 0.44],
            waveformPeaks: [WaveformPeak(timeSec: 0, peak: 0.8, rms: 0.4)],
            waveformDetail: [WaveformDetailPoint(timeSec: 0, peak: 0.8, rms: 0.4, min: -0.7, max: 0.8)],
            spectralBands: [SpectralBandPoint(timeSec: 0, low: 0.3, mid: 0.6, high: 0.2)],
            transientMarkers: [
                TransientMarker(index: 0, timeSec: 0, strength: 0.86),
                TransientMarker(index: 1, timeSec: beat, strength: 0.76)
            ],
            cueCandidates: [
                CueCandidate(id: "first-downbeat", type: .firstDownbeat, startSec: 0, endSec: 4, confidence: 0.8, label: "First downbeat"),
                CueCandidate(id: "outro", type: .outro, startSec: outroSec, endSec: durationSec, confidence: 0.74, label: "Outro mix-out")
            ],
            analysisConfidence: 0.84,
            analysisQuality: AnalysisQuality(
                waveformDetail: 0.45,
                spectralBands: 0.45,
                transientMarkers: 0.62,
                beatGrid: 0.72
            ),
            analysisWarnings: [.beatGridEstimated]
        )
    }
}
