import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct PlaybackDSPTests {
    private let sampleRate = 48_000.0

    @Test func resolverCombinesLoudnessTrimAndPeakSafety() {
        let plan = makePlan(
            controls: MixControlPlan(
                gain: MixGainPlan(incomingTrimDb: 1),
                loudness: MixLoudnessPlan(targetIntegratedLufs: -14, maxPeakDb: -1)
            )
        )
        let settings = PlaybackDSPResolver.deckSettings(
            plan: plan,
            role: .incoming,
            analysis: makeAnalysis(integratedLUFS: -18, truePeakDb: -3)
        )

        // Requested gain is +5 dB, but the measured true peak permits only +2 dB.
        #expect(settings.gainDb == 2)
    }

    @Test func resolverIgnoresUntrustedLoudnessAndSanitizesTempo() {
        let plan = makePlan(
            tempoRate: 1.4,
            controls: MixControlPlan(
                gain: MixGainPlan(outgoingTrimDb: -2, incomingTrimDb: 1),
                loudness: MixLoudnessPlan(targetIntegratedLufs: -14, maxPeakDb: nil)
            )
        )
        let analysis = makeAnalysis(integratedLUFS: -24, truePeakDb: -5, confidence: 0.2)

        let outgoing = PlaybackDSPResolver.deckSettings(plan: plan, role: .outgoing, analysis: analysis)
        let incoming = PlaybackDSPResolver.deckSettings(plan: plan, role: .incoming, analysis: analysis)

        #expect(outgoing.gainDb == -2)
        #expect(outgoing.playbackRate == 1)
        #expect(incoming.gainDb == 1)
        #expect(incoming.playbackRate == 1.15)
    }

    @Test func logarithmicFilterSweepIsMonotonic() {
        let settings = PlaybackDeckDSPSettings(
            gainDb: 0,
            lowEQDb: 0,
            midEQDb: 0,
            highEQDb: 0,
            filterMode: .highPass,
            filterStartHz: 40,
            filterEndHz: 10_000,
            playbackRate: 1
        )

        let start = settings.filterFrequency(at: 0) ?? 0
        let midpoint = settings.filterFrequency(at: 0.5) ?? 0
        let end = settings.filterFrequency(at: 1) ?? 0

        #expect(start == 40)
        #expect(midpoint > start)
        #expect(midpoint < end)
        #expect(abs(midpoint - sqrt(start * end)) < 0.001)
        #expect(abs(end - 10_000) < 0.001)
    }

    @Test func deckControlRampHasStableEndpointsAndMidpoint() {
        let target = PlaybackDeckDSPSettings(
            gainDb: -6,
            lowEQDb: 4,
            midEQDb: -2,
            highEQDb: 6,
            filterMode: .highPass,
            filterStartHz: 40,
            filterEndHz: 8_000,
            playbackRate: 1.1
        )

        let start = PlaybackDeckDSPSettings.neutral.interpolated(toward: target, progress: 0)
        let midpoint = PlaybackDeckDSPSettings.neutral.interpolated(toward: target, progress: 0.5)
        let end = PlaybackDeckDSPSettings.neutral.interpolated(toward: target, progress: 1)

        #expect(start.gainDb == 0)
        #expect(start.playbackRate == 1)
        #expect(midpoint.gainDb == -3)
        #expect(midpoint.lowEQDb == 2)
        #expect(midpoint.playbackRate == 1.05)
        #expect(end == target)
    }

    @Test func neutralReferenceRenderPreservesPCM() {
        let input = sine(frequency: 997, amplitude: 0.35, frameCount: 24_000)
        let output = PlaybackDSPReferenceRenderer.renderDeck(
            samples: input,
            sampleRate: sampleRate,
            settings: .neutral,
            filterProgress: 0
        )

        #expect(maximumDelta(input, output) < 0.000_001)
    }

    @Test func gainAndThreeBandEQChangeExpectedSignals() {
        let low = sine(frequency: 80, amplitude: 0.2, frameCount: 48_000)
        let mid = sine(frequency: 1_000, amplitude: 0.2, frameCount: 48_000)
        let high = sine(frequency: 10_000, amplitude: 0.2, frameCount: 48_000)
        let settings = PlaybackDeckDSPSettings(
            gainDb: 3,
            lowEQDb: 6,
            midEQDb: -6,
            highEQDb: 6,
            filterMode: .disabled,
            filterStartHz: nil,
            filterEndHz: nil,
            playbackRate: 1
        )

        let lowDelta = levelDeltaDb(input: low, settings: settings)
        let midDelta = levelDeltaDb(input: mid, settings: settings)
        let highDelta = levelDeltaDb(input: high, settings: settings)

        #expect(lowDelta > 7)
        #expect(midDelta < 0)
        #expect(highDelta > 7)
    }

    @Test func highPassAndLowPassRejectOppositeSides() {
        let low = sine(frequency: 80, amplitude: 0.3, frameCount: 48_000)
        let high = sine(frequency: 8_000, amplitude: 0.3, frameCount: 48_000)
        let highPass = PlaybackDeckDSPSettings(
            gainDb: 0,
            lowEQDb: 0,
            midEQDb: 0,
            highEQDb: 0,
            filterMode: .highPass,
            filterStartHz: 1_000,
            filterEndHz: 1_000,
            playbackRate: 1
        )
        let lowPass = PlaybackDeckDSPSettings(
            gainDb: 0,
            lowEQDb: 0,
            midEQDb: 0,
            highEQDb: 0,
            filterMode: .lowPass,
            filterStartHz: 1_000,
            filterEndHz: 1_000,
            playbackRate: 1
        )

        #expect(levelDeltaDb(input: low, settings: highPass) < -30)
        #expect(levelDeltaDb(input: high, settings: highPass) > -1)
        #expect(levelDeltaDb(input: low, settings: lowPass) > -1)
        #expect(levelDeltaDb(input: high, settings: lowPass) < -30)
    }

    @Test func softLimiterBoundsRenderedPCMAtCeiling() {
        let loud = Array(repeating: Float(1), count: 8_192)
        let rendered = PlaybackDSPReferenceRenderer.mix(
            outgoing: loud,
            incoming: loud,
            progress: 0.5,
            master: PlaybackMasterDSPSettings(softLimitEnabled: true, ceilingDb: -1)
        )
        let peak = rendered.map { abs(Double($0)) }.max() ?? 0
        let ceiling = PlaybackDSPResolver.linearGain(db: -1)

        #expect(peak <= ceiling + 0.000_001)
        #expect(peak > 0.8)
    }

    private func makePlan(
        tempoRate: Double? = nil,
        controls: MixControlPlan
    ) -> MixPlan {
        MixPlan(
            transitionStartSec: 10,
            transitionEndSec: 18,
            nextTrackStartOffsetSec: 0,
            style: .smoothBlend,
            confidence: 0.8,
            reasoningSummary: nil,
            tempoSync: MixTempoSyncPlan(enabled: tempoRate != nil, targetRate: tempoRate),
            mixControls: controls
        )
    }

    private func makeAnalysis(
        integratedLUFS: Double,
        truePeakDb: Double,
        confidence: Double = 0.9
    ) -> TrackAnalysis {
        TrackAnalysis(
            trackId: "test",
            generatedAt: "2026-08-10T00:00:00Z",
            source: .derived,
            bpm: 124,
            bpmConfidence: 0.9,
            beatGridSec: [],
            downbeatsSec: [],
            barGrid: [],
            phraseMarkers: [],
            introCueSec: 0,
            outroCueSec: 100,
            energyProfile: [],
            waveformPeaks: [],
            waveformDetail: [],
            spectralBands: [],
            transientMarkers: [],
            cueCandidates: [],
            loudness: LoudnessAnalysis(
                integratedRMSDb: integratedLUFS,
                integratedLUFS: integratedLUFS,
                peakDb: truePeakDb,
                truePeakDb: truePeakDb,
                headroomDb: -truePeakDb,
                crestFactorDb: 8,
                dynamicRangeDb: 5,
                confidence: confidence
            ),
            analysisConfidence: confidence,
            analysisQuality: AnalysisQuality(
                waveformDetail: 1,
                spectralBands: 1,
                transientMarkers: 1,
                beatGrid: 1
            ),
            analysisWarnings: []
        )
    }

    private func sine(frequency: Double, amplitude: Double, frameCount: Int) -> [Float] {
        (0..<frameCount).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / sampleRate) * amplitude)
        }
    }

    private func levelDeltaDb(input: [Float], settings: PlaybackDeckDSPSettings) -> Double {
        let output = PlaybackDSPReferenceRenderer.renderDeck(
            samples: input,
            sampleRate: sampleRate,
            settings: settings,
            filterProgress: 1
        )
        let skip = min(2_048, input.count / 4)
        return db(rms(Array(output.dropFirst(skip)))) - db(rms(Array(input.dropFirst(skip))))
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
    }

    private func db(_ value: Double) -> Double {
        20 * log10(max(0.000_001, value))
    }

    private func maximumDelta(_ lhs: [Float], _ rhs: [Float]) -> Double {
        zip(lhs, rhs).map { abs(Double($0) - Double($1)) }.max() ?? 0
    }
}
