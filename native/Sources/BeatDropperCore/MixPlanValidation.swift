import Foundation

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
                evidence: Array(candidate.evidence.prefix(8))
            ),
            nil
        )
    }
}

private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
}
