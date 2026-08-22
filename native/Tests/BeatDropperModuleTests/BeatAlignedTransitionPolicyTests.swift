import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct BeatAlignedTransitionPolicyTests {
    @Test func fourEightAndSixteenBarDurationMathUsesFourFourGrid() throws {
        #expect(try #require(BeatAlignedTransitionPolicy.durationSec(barCount: 4, synchronizedBPM: 120)) == 8)
        #expect(try #require(BeatAlignedTransitionPolicy.durationSec(barCount: 8, synchronizedBPM: 120)) == 16)
        #expect(try #require(BeatAlignedTransitionPolicy.durationSec(barCount: 16, synchronizedBPM: 120)) == 32)
        #expect(BeatAlignedTransitionPolicy.durationSec(barCount: 8, synchronizedBPM: 0) == nil)
    }

    @Test func smoothBlendUsesEightAlignedBarsAndSynchronizesTempo() throws {
        let request = request(currentBPM: 120, nextBPM: 124, mode: .balanced)
        let plan = try #require(apply(style: .smoothBlend, request: request))

        #expect(plan.transitionBarCount == 8)
        #expect(plan.transitionTimingSource == .beatGrid)
        #expect(abs((plan.transitionEndSec - plan.transitionStartSec) - 16) < 0.001)
        #expect(plan.currentBarIndex.map { $0.isMultiple(of: 8) } == true)
        #expect(plan.currentBarIndex.map { $0 % 8 } == plan.nextBarIndex.map { $0 % 8 })
        #expect(plan.phraseAlignment == .aligned)
        #expect(plan.tempoSync.enabled)
        #expect(abs(try #require(plan.tempoSync.targetRate) - (120.0 / 124.0)) < 0.001)
        #expect(abs(try #require(plan.synchronizedBPM) - 120) < 0.001)
    }

    @Test func energySwapUsesFourBars() throws {
        let request = request(currentBPM: 128, nextBPM: 130, mode: .balanced)
        let plan = try #require(apply(style: .energySwap, request: request))

        #expect(plan.style == .energySwap)
        #expect(plan.transitionBarCount == 4)
        #expect(plan.currentBarIndex.map { $0.isMultiple(of: 4) } == true)
        #expect(abs((plan.transitionEndSec - plan.transitionStartSec) - 7.5) < 0.001)
        #expect(plan.transitionTimingSource == .beatGrid)
    }

    @Test func safeHighConfidenceAlignedBlendCanUseSixteenBars() throws {
        let request = request(currentBPM: 120, nextBPM: 120, mode: .safe, quality: 0.9)
        let plan = try #require(apply(style: .smoothBlend, request: request, phraseAlignment: .aligned))

        #expect(plan.style == .smoothBlend)
        #expect(plan.transitionBarCount == 16)
        #expect(plan.currentBarIndex.map { $0.isMultiple(of: 8) } == true)
        #expect(abs((plan.transitionEndSec - plan.transitionStartSec) - 32) < 0.001)
    }

    @Test func extremeTempoDifferenceDowngradesToOneBarHardCut() throws {
        let request = request(currentBPM: 120, nextBPM: 170, mode: .balanced)
        let plan = try #require(apply(style: .smoothBlend, request: request))

        #expect(plan.style == .hardCut)
        #expect(plan.transitionBarCount == 1)
        #expect(abs((plan.transitionEndSec - plan.transitionStartSec) - 2) < 0.001)
        #expect(!plan.tempoSync.enabled)
        #expect(plan.tempoSync.targetRate == nil)
        #expect(plan.evidence.contains { $0.contains("tempo sync unsuitable") })
    }

    @Test func moderateUnsynchronizedTempoDifferenceUsesFourBarEnergySwap() throws {
        let request = request(currentBPM: 120, nextBPM: 150, mode: .balanced)
        let plan = try #require(apply(style: .smoothBlend, request: request))

        #expect(plan.style == .energySwap)
        #expect(plan.transitionBarCount == 4)
        #expect(!plan.tempoSync.enabled)
    }

    @Test func lowGridConfidenceUsesConfiguredSecondsFallbackOnly() throws {
        let request = request(currentBPM: 120, nextBPM: 124, mode: .balanced, quality: 0.3, fadeDuration: 9)
        let plan = try #require(apply(style: .smoothBlend, request: request))

        #expect(plan.transitionBarCount == nil)
        #expect(plan.transitionTimingSource == .secondsFallback)
        #expect(plan.synchronizedBPM == nil)
        #expect(abs((plan.transitionEndSec - plan.transitionStartSec) - 9) < 0.001)
        #expect(!plan.tempoSync.enabled)
    }

    @Test func manualNextStartsOnFirstAvailableBarInsteadOfDistantOutro() throws {
        let request = request(currentBPM: 120, nextBPM: 124, mode: .balanced, elapsed: 31)
        let plan = try #require(apply(style: .smoothBlend, request: request, intent: .manualNext))

        #expect(plan.transitionStartSec == 32)
        #expect(plan.transitionEndSec == 48)
        #expect(plan.transitionBarCount == 8)
        #expect(plan.currentBarIndex.map { $0.isMultiple(of: 8) } == true)
        #expect(plan.phraseAlignment == .aligned)
        #expect(plan.evidence.contains { $0.contains("manual Next") })
    }

    @Test func optionalTimingFieldsRemainBackwardCompatibleWithPlannerJSON() throws {
        let json = """
        {
          "transitionStartSec": 32,
          "transitionEndSec": 40,
          "nextTrackStartOffsetSec": 0,
          "style": "smooth_blend",
          "confidence": 0.7,
          "reasoningSummary": "legacy planner response",
          "tempoSync": { "enabled": false, "targetRate": null },
          "evidence": []
        }
        """
        let plan = try JSONDecoder().decode(MixPlan.self, from: Data(json.utf8))

        #expect(plan.transitionBarCount == nil)
        #expect(plan.transitionTimingSource == nil)
        #expect(plan.synchronizedBPM == nil)
    }

    private func apply(
        style: MixStyle,
        request: PlannerRequest,
        phraseAlignment: PhraseAlignment = .aligned,
        intent: TransitionPlanningIntent = .scheduled
    ) -> MixPlan? {
        BeatAlignedTransitionPolicy.apply(
            to: MixPlan(
                transitionStartSec: 168,
                transitionEndSec: 184,
                nextTrackStartOffsetSec: 16,
                style: style,
                confidence: 0.8,
                reasoningSummary: "test plan",
                tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil),
                currentBarIndex: 92,
                nextBarIndex: 8,
                phraseAlignment: phraseAlignment,
                evidence: ["test evidence"]
            ),
            request: request,
            validationContext: validationContext(request),
            intent: intent
        )
    }

    private func request(
        currentBPM: Double,
        nextBPM: Double,
        mode: AIDJMode,
        quality: Double = 0.82,
        fadeDuration: Double = 8,
        elapsed: Double = 80
    ) -> PlannerRequest {
        let current = Track(id: "current", title: "Current", durationSec: 240, format: .wav, bpm: currentBPM)
        let next = Track(id: "next", title: "Next", durationSec: 240, format: .wav, bpm: nextBPM)
        return PlannerRequestBuilder.build(
            currentTrack: current,
            nextTrack: next,
            elapsedSec: elapsed,
            currentAnalysis: analysis(trackId: current.id, bpm: currentBPM, quality: quality),
            nextAnalysis: analysis(trackId: next.id, bpm: nextBPM, quality: quality),
            settings: PlannerSettingsSnapshot(fadeDurationSec: fadeDuration, aiDjMode: mode)
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

    private func analysis(trackId: String, bpm: Double, quality: Double) -> TrackAnalysis {
        let beatSec = 60 / bpm
        let barSec = beatSec * 4
        let bars = stride(from: 0.0, through: 240.0, by: barSec).enumerated().map {
            BarMarker(index: $0.offset, startSec: $0.element, beatIndex: $0.offset * 4)
        }
        let beats = stride(from: 0.0, through: 240.0, by: beatSec).map { $0 }
        return TrackAnalysis(
            trackId: trackId,
            generatedAt: "2026-08-16T00:00:00Z",
            source: .derived,
            bpm: bpm,
            bpmConfidence: quality,
            beatGridSec: beats,
            downbeatsSec: bars.map(\.startSec),
            barGrid: bars,
            phraseMarkers: bars.filter { $0.index.isMultiple(of: 8) }.map {
                PhraseMarker(index: $0.index / 8, startSec: $0.startSec, bars: 8, confidence: quality)
            },
            introCueSec: 0,
            outroCueSec: 216,
            energyProfile: [0.3, 0.5, 0.7, 0.45],
            waveformPeaks: [],
            waveformDetail: [],
            spectralBands: [],
            transientMarkers: [],
            cueCandidates: [],
            analysisConfidence: quality,
            analysisQuality: AnalysisQuality(
                waveformDetail: quality,
                spectralBands: quality,
                transientMarkers: quality,
                beatGrid: quality
            ),
            analysisWarnings: []
        )
    }
}
