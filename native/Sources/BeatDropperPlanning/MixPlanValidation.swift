import Foundation
import BeatDropperDomain

public struct MixPlanValidationContext: Sendable {
    public var currentPlaybackElapsedSec: Double
    public var currentTrackDurationSec: Double
    public var nextTrackDurationSec: Double
    public var maxFadeDurationSec: Double

    public init(
        currentPlaybackElapsedSec: Double,
        currentTrackDurationSec: Double,
        nextTrackDurationSec: Double,
        maxFadeDurationSec: Double
    ) {
        self.currentPlaybackElapsedSec = currentPlaybackElapsedSec
        self.currentTrackDurationSec = currentTrackDurationSec
        self.nextTrackDurationSec = nextTrackDurationSec
        self.maxFadeDurationSec = maxFadeDurationSec
    }
}

public enum MixPlanValidator {
    public static func validateAndClamp(
        _ candidate: MixPlan,
        context: MixPlanValidationContext
    ) -> (plan: MixPlan?, reason: String?) {
        let currentTrackDurationSec = max(0, context.currentTrackDurationSec)
        let nextTrackDurationSec = max(0, context.nextTrackDurationSec)
        let maxFadeDurationSec = max(0.25, context.maxFadeDurationSec)
        let elapsedSec = clamped(
            context.currentPlaybackElapsedSec,
            min: 0,
            max: currentTrackDurationSec
        )

        var transitionStartSec = clamped(
            candidate.transitionStartSec,
            min: elapsedSec,
            max: currentTrackDurationSec
        )
        let transitionEndSec = clamped(
            candidate.transitionEndSec,
            min: transitionStartSec,
            max: currentTrackDurationSec
        )

        if transitionEndSec - transitionStartSec > maxFadeDurationSec {
            transitionStartSec = max(elapsedSec, transitionEndSec - maxFadeDurationSec)
        }

        if transitionEndSec - transitionStartSec < 0.05 {
            return (nil, "mix_plan_window_too_small")
        }

        let nextTrackStartOffsetSec = clamped(
            candidate.nextTrackStartOffsetSec,
            min: 0,
            max: nextTrackDurationSec
        )
        let targetRate = candidate.tempoSync.targetRate.map {
            clamped($0, min: 0.85, max: 1.15)
        }

        return (
            MixPlan(
                transitionStartSec: transitionStartSec,
                transitionEndSec: transitionEndSec,
                nextTrackStartOffsetSec: nextTrackStartOffsetSec,
                style: candidate.style,
                confidence: clamped(candidate.confidence, min: 0, max: 1),
                reasoningSummary: candidate.reasoningSummary,
                tempoSync: MixTempoSyncPlan(
                    enabled: candidate.tempoSync.enabled && targetRate != nil,
                    targetRate: targetRate
                ),
                candidateId: candidate.candidateId,
                currentBarIndex: candidate.currentBarIndex.map { max(0, $0) },
                nextBarIndex: candidate.nextBarIndex.map { max(0, $0) },
                phraseAlignment: candidate.phraseAlignment,
                energyStrategy: candidate.energyStrategy,
                evidence: Array(candidate.evidence.prefix(8)),
                mixControls: clampedMixControls(candidate.mixControls),
                transitionBarCount: candidate.transitionBarCount.map { clampedInt($0, min: 0, max: 16) },
                transitionTimingSource: candidate.transitionTimingSource,
                synchronizedBPM: candidate.synchronizedBPM.map { clamped($0, min: 40, max: 240) }
            ),
            nil
        )
    }

    private static func clampedMixControls(_ candidate: MixControlPlan?) -> MixControlPlan {
        let controls = candidate ?? .conservativeDefaults
        return MixControlPlan(
            gain: MixGainPlan(
                outgoingTrimDb: controls.gain.outgoingTrimDb.map(clampedGainDb) ?? 0,
                incomingTrimDb: controls.gain.incomingTrimDb.map(clampedGainDb) ?? 0
            ),
            eq: MixThreeBandEQPlan(
                outgoingLowDb: controls.eq.outgoingLowDb.map(clampedEQDb) ?? 0,
                outgoingMidDb: controls.eq.outgoingMidDb.map(clampedEQDb) ?? 0,
                outgoingHighDb: controls.eq.outgoingHighDb.map(clampedEQDb) ?? 0,
                incomingLowDb: controls.eq.incomingLowDb.map(clampedEQDb) ?? 0,
                incomingMidDb: controls.eq.incomingMidDb.map(clampedEQDb) ?? 0,
                incomingHighDb: controls.eq.incomingHighDb.map(clampedEQDb) ?? 0
            ),
            filter: clampedFilterPlan(controls.filter),
            loudness: MixLoudnessPlan(
                targetIntegratedLufs: controls.loudness.targetIntegratedLufs.map {
                    clamped($0, min: -24, max: -6)
                },
                maxPeakDb: controls.loudness.maxPeakDb.map {
                    clamped($0, min: -6, max: -0.1)
                } ?? -1
            ),
            clipProtection: MixClipProtectionPlan(
                enabled: controls.clipProtection.enabled,
                mode: controls.clipProtection.mode,
                ceilingDb: controls.clipProtection.ceilingDb.map {
                    clamped($0, min: -6, max: -0.1)
                } ?? -1
            ),
            qualityNotes: Array(controls.qualityNotes.filter { !$0.isEmpty }.prefix(6))
        )
    }

    private static func clampedFilterPlan(_ filter: MixFilterPlan) -> MixFilterPlan {
        let outgoingStartHz = clampedFrequency(filter.outgoingStartHz, mode: filter.outgoingMode)
        let outgoingEndHz = clampedFrequency(filter.outgoingEndHz, mode: filter.outgoingMode)
        let incomingStartHz = clampedFrequency(filter.incomingStartHz, mode: filter.incomingMode)
        let incomingEndHz = clampedFrequency(filter.incomingEndHz, mode: filter.incomingMode)
        return MixFilterPlan(
            outgoingMode: filter.outgoingMode,
            outgoingStartHz: outgoingStartHz,
            outgoingEndHz: outgoingEndHz,
            incomingMode: filter.incomingMode,
            incomingStartHz: incomingStartHz,
            incomingEndHz: incomingEndHz
        )
    }

    private static func clampedFrequency(_ value: Double?, mode: MixFilterMode) -> Double? {
        guard mode != .disabled else {
            return nil
        }
        return value.map { clamped($0, min: 20, max: 20_000) }
    }

    private static func clampedGainDb(_ value: Double) -> Double {
        clamped(value, min: -12, max: 6)
    }

    private static func clampedEQDb(_ value: Double) -> Double {
        clamped(value, min: -12, max: 6)
    }
}

private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
}

private func clampedInt(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
    Swift.min(maxValue, Swift.max(minValue, value))
}
