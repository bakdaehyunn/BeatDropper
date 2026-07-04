import BeatDropperCore
import Foundation
import Testing

struct NativeFallbackMixPlannerTests {
    @Test func buildsFallbackPlanFromPairContextCandidate() throws {
        let current = Track(id: "current", title: "Current", durationSec: 180, format: .wav, bpm: 124)
        let next = Track(id: "next", title: "Next", durationSec: 190, format: .wav, bpm: 126)
        let request = PlannerRequestBuilder.build(
            currentTrack: current,
            nextTrack: next,
            elapsedSec: 80,
            currentAnalysis: analysis(trackId: "current", durationSec: 180, bpm: 124, outroSec: 152),
            nextAnalysis: analysis(trackId: "next", durationSec: 190, bpm: 126, outroSec: 170),
            settings: PlannerSettingsSnapshot(fadeDurationSec: 8, aiDjMode: .balanced)
        )

        let plan = try #require(NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext(request),
            failureReason: "planner_timeout"
        ))

        #expect(plan.transitionEndSec > plan.transitionStartSec)
        #expect(plan.transitionStartSec >= 80)
        #expect(plan.transitionEndSec - plan.transitionStartSec <= 8)
        #expect(plan.nextTrackStartOffsetSec >= 0)
        #expect(plan.candidateId == request.pairContext?.recommendedCandidateId)
        #expect(plan.evidence.contains("local fallback"))
        #expect(plan.evidence.contains { $0.contains("planner_timeout") })
        #expect(plan.confidence >= 0.38)
        #expect(plan.mixControls?.clipProtection.mode == .monitorOnly)
        #expect(plan.mixControls?.qualityNotes.contains { $0.contains("planning metadata") } == true)
    }

    @Test func usesTailFallbackWhenAnalysisIsMissing() throws {
        let current = Track(id: "current", title: "Current", durationSec: 180, format: .wav)
        let next = Track(id: "next", title: "Next", durationSec: 190, format: .wav)
        let request = PlannerRequestBuilder.build(
            currentTrack: current,
            nextTrack: next,
            elapsedSec: 120,
            currentAnalysis: nil,
            nextAnalysis: nil,
            settings: PlannerSettingsSnapshot(fadeDurationSec: 10, aiDjMode: .safe)
        )

        let plan = try #require(NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext(request),
            failureReason: "planner_returned_no_plan"
        ))

        #expect(plan.candidateId?.contains("tail_fallback") == true)
        #expect(plan.transitionStartSec >= 120)
        #expect(plan.transitionEndSec - plan.transitionStartSec <= 10)
        #expect(plan.phraseAlignment == .free)
        #expect(plan.confidence <= 0.42)
        #expect(plan.evidence.contains { $0.contains("planner_returned_no_plan") })
        #expect(plan.mixControls?.gain.incomingTrimDb == -2)
    }

    @Test func staleTailRecommendationDoesNotOverrideAnalysisCandidate() throws {
        let current = Track(id: "current", title: "Current", durationSec: 210, format: .wav, bpm: 124)
        let next = Track(id: "next", title: "Next", durationSec: 200, format: .wav, bpm: 126)
        let analysisCandidate = candidate(
            id: "analysis-phrase",
            current: current,
            next: next,
            source: .analysis,
            evidenceLevel: .strong,
            currentMixOutSec: 188,
            nextMixInSec: 16,
            currentBarIndex: 88,
            nextBarIndex: 8,
            phraseAlignment: .aligned,
            bpmDelta: 2,
            tempoSyncRate: 124 / 126,
            energyDelta: 0.14,
            style: .smoothBlend,
            score: 0.72,
            confidence: 0.72,
            reason: "analysis phrase boundary"
        )
        let tailCandidate = candidate(
            id: "tail-fallback-stale",
            current: current,
            next: next,
            source: .tailFallback,
            evidenceLevel: .fallback,
            currentMixOutSec: 194,
            nextMixInSec: 0,
            currentBarIndex: nil,
            nextBarIndex: nil,
            phraseAlignment: .free,
            bpmDelta: 2,
            tempoSyncRate: 124 / 126,
            energyDelta: 0,
            style: .hardCut,
            score: 0.99,
            confidence: 0.99,
            reason: "stale recommended tail fallback"
        )
        let request = request(
            current: current,
            next: next,
            elapsedSec: 176,
            candidates: [tailCandidate, analysisCandidate],
            recommendedCandidateId: tailCandidate.id,
            readiness: .ready
        )

        let plan = try #require(NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext(request),
            failureReason: "planner_timeout"
        ))

        #expect(plan.candidateId == analysisCandidate.id)
        #expect(plan.phraseAlignment == .aligned)
        #expect(plan.nextTrackStartOffsetSec == 16)
        #expect(plan.evidence.contains { $0.contains("source analysis") })
        #expect(plan.evidence.contains { $0.contains("phrase aligned") })
    }

    @Test func buildsEmergencyPlanWhenPairContextHasNoCandidates() throws {
        let request = PlannerRequest(
            currentTrack: PlannerTrackSnapshot(id: "current", title: "Current", durationSec: 60, bpm: nil),
            nextTrack: PlannerTrackSnapshot(id: "next", title: "Next", durationSec: 80, bpm: nil),
            currentPlayback: PlannerPlaybackSnapshot(elapsedSec: 45, remainingSec: 15),
            analysis: PlannerAnalysisPair(current: nil, next: nil),
            analysisSummary: nil,
            pairContext: MixPairContext(
                currentTrackId: "current",
                nextTrackId: "next",
                candidates: [],
                recommendedCandidateId: nil,
                readiness: .fallbackOnly
            ),
            settings: PlannerSettingsSnapshot(fadeDurationSec: 8, aiDjMode: .balanced)
        )

        let plan = try #require(NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext(request),
            failureReason: "script_missing"
        ))

        #expect(plan.candidateId == "native-emergency-tail")
        #expect(plan.transitionStartSec >= 45)
        #expect(plan.nextTrackStartOffsetSec == 0)
        #expect(plan.evidence.contains("emergency tail mix"))
        #expect(plan.mixControls?.gain.outgoingTrimDb == 0)
        #expect(plan.mixControls?.clipProtection.enabled == true)
    }

    private func request(
        current: Track,
        next: Track,
        elapsedSec: Double,
        candidates: [MixCandidate],
        recommendedCandidateId: String?,
        readiness: MixPairReadiness
    ) -> PlannerRequest {
        PlannerRequest(
            currentTrack: PlannerTrackSnapshot(track: current),
            nextTrack: PlannerTrackSnapshot(track: next),
            currentPlayback: PlannerPlaybackSnapshot(
                elapsedSec: elapsedSec,
                remainingSec: max(0, current.durationSec - elapsedSec)
            ),
            analysis: PlannerAnalysisPair(current: nil, next: nil),
            analysisSummary: nil,
            pairContext: MixPairContext(
                currentTrackId: current.id,
                nextTrackId: next.id,
                candidates: candidates,
                recommendedCandidateId: recommendedCandidateId,
                readiness: readiness
            ),
            settings: PlannerSettingsSnapshot(fadeDurationSec: 8, aiDjMode: .balanced)
        )
    }

    private func candidate(
        id: String,
        current: Track,
        next: Track,
        source: MixCandidateSource,
        evidenceLevel: MixEvidenceLevel,
        currentMixOutSec: Double,
        nextMixInSec: Double,
        currentBarIndex: Int?,
        nextBarIndex: Int?,
        phraseAlignment: PhraseAlignment,
        bpmDelta: Double?,
        tempoSyncRate: Double?,
        energyDelta: Double?,
        style: MixStyle,
        score: Double,
        confidence: Double,
        reason: String
    ) -> MixCandidate {
        MixCandidate(
            id: id,
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: source,
            evidenceLevel: evidenceLevel,
            requiresAnalysisUpgrade: source == .tailFallback,
            currentMixOutSec: currentMixOutSec,
            nextMixInSec: nextMixInSec,
            currentBarIndex: currentBarIndex,
            nextBarIndex: nextBarIndex,
            phraseAlignment: phraseAlignment,
            bpmDelta: bpmDelta,
            tempoSyncRate: tempoSyncRate,
            energyDelta: energyDelta,
            style: style,
            score: score,
            confidence: confidence,
            reason: reason
        )
    }

    private func validationContext(_ request: PlannerRequest) -> MixPlanValidationContext {
        MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: request.currentTrack.durationSec,
            nextTrackDurationSec: request.nextTrack.durationSec,
            maxFadeDurationSec: request.settings.fadeDurationSec
        )
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
                CueCandidate(id: "first-downbeat", type: .firstDownbeat, startSec: 0, endSec: 4, confidence: 0.8, label: "First downbeat", origin: .derived),
                CueCandidate(id: "outro", type: .outro, startSec: outroSec, endSec: durationSec, confidence: 0.74, label: "Outro mix-out", origin: .derived)
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
