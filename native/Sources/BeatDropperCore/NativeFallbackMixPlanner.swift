import Foundation

public enum NativeFallbackMixPlanner {
    public static func buildPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        failureReason: String?
    ) -> MixPlan? {
        let candidates = request.pairContext?.candidates ?? []
        let selectedCandidate = selectCandidate(
            candidates: candidates,
            recommendedCandidateId: request.pairContext?.recommendedCandidateId,
            elapsedSec: request.currentPlayback.elapsedSec,
            mode: request.settings.aiDjMode
        )

        guard let selectedCandidate else {
            return buildEmergencyTailPlan(
                request: request,
                validationContext: validationContext,
                failureReason: failureReason
            )
        }

        let maxFadeDurationSec = max(0.25, request.settings.fadeDurationSec)
        let transitionDurationSec = preferredTransitionDuration(
            candidate: selectedCandidate,
            mode: request.settings.aiDjMode,
            maxFadeDurationSec: maxFadeDurationSec
        )
        let transitionEndSec = futureMixOutTime(
            candidate: selectedCandidate,
            request: request,
            transitionDurationSec: transitionDurationSec
        )
        let transitionStartSec = max(
            request.currentPlayback.elapsedSec,
            transitionEndSec - transitionDurationSec
        )
        let plan = MixPlan(
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: selectedCandidate.nextMixInSec,
            style: selectedCandidate.style,
            confidence: fallbackConfidence(for: selectedCandidate),
            reasoningSummary: "Local fallback: \(selectedCandidate.reason)",
            tempoSync: MixTempoSyncPlan(
                enabled: selectedCandidate.tempoSyncRate != nil && (selectedCandidate.bpmDelta ?? 0) <= 10,
                targetRate: selectedCandidate.tempoSyncRate
            ),
            candidateId: selectedCandidate.id,
            currentBarIndex: selectedCandidate.currentBarIndex,
            nextBarIndex: selectedCandidate.nextBarIndex,
            phraseAlignment: selectedCandidate.phraseAlignment,
            energyStrategy: energyStrategy(for: selectedCandidate.energyDelta),
            evidence: fallbackEvidence(candidate: selectedCandidate, failureReason: failureReason),
            mixControls: fallbackMixControls(candidate: selectedCandidate)
        )

        return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
    }

    private static func selectCandidate(
        candidates: [MixCandidate],
        recommendedCandidateId: String?,
        elapsedSec: Double,
        mode: AIDJMode
    ) -> MixCandidate? {
        let leadSec = preferredLeadSec(mode)
        let viable = candidates
            .filter { $0.currentMixOutSec >= elapsedSec + leadSec }
            .sorted { candidateSort($0, $1, recommendedCandidateId: recommendedCandidateId) }
        if let first = viable.first {
            return first
        }

        return candidates.sorted {
            candidateSort($0, $1, recommendedCandidateId: recommendedCandidateId)
        }.first
    }

    private static func candidateSort(
        _ left: MixCandidate,
        _ right: MixCandidate,
        recommendedCandidateId: String?
    ) -> Bool {
        if sourceRank(left.source) != sourceRank(right.source) {
            return sourceRank(left.source) < sourceRank(right.source)
        }
        if evidenceRank(left.evidenceLevel) != evidenceRank(right.evidenceLevel) {
            return evidenceRank(left.evidenceLevel) < evidenceRank(right.evidenceLevel)
        }
        if left.id == recommendedCandidateId {
            return true
        }
        if right.id == recommendedCandidateId {
            return false
        }
        return left.score > right.score
    }

    private static func sourceRank(_ source: MixCandidateSource) -> Int {
        switch source {
        case .analysis:
            return 0
        case .cue:
            return 1
        case .tailFallback:
            return 2
        }
    }

    private static func evidenceRank(_ evidenceLevel: MixEvidenceLevel) -> Int {
        switch evidenceLevel {
        case .strong:
            return 0
        case .partial:
            return 1
        case .fallback:
            return 2
        }
    }

    private static func preferredLeadSec(_ mode: AIDJMode) -> Double {
        switch mode {
        case .safe:
            return 4
        case .balanced:
            return 2
        case .adventurous:
            return 0.5
        }
    }

    private static func preferredTransitionDuration(
        candidate: MixCandidate,
        mode: AIDJMode,
        maxFadeDurationSec: Double
    ) -> Double {
        switch candidate.style {
        case .hardCut:
            switch mode {
            case .safe:
                return min(maxFadeDurationSec, 3)
            case .balanced:
                return min(maxFadeDurationSec, 2)
            case .adventurous:
                return min(maxFadeDurationSec, 1.25)
            }
        case .energySwap:
            return min(maxFadeDurationSec, max(2.5, maxFadeDurationSec * 0.65))
        case .smoothBlend:
            return maxFadeDurationSec
        }
    }

    private static func futureMixOutTime(
        candidate: MixCandidate,
        request: PlannerRequest,
        transitionDurationSec: Double
    ) -> Double {
        let elapsedSec = request.currentPlayback.elapsedSec
        let currentDurationSec = max(0, request.currentTrack.durationSec)
        if candidate.currentMixOutSec > elapsedSec + 0.25 {
            return min(candidate.currentMixOutSec, currentDurationSec)
        }
        return min(
            currentDurationSec,
            max(elapsedSec + min(transitionDurationSec, 2), currentDurationSec - transitionDurationSec * 0.5)
        )
    }

    private static func buildEmergencyTailPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        failureReason: String?
    ) -> MixPlan? {
        let durationSec = max(0.25, min(request.settings.fadeDurationSec, 8))
        let currentDurationSec = max(0, request.currentTrack.durationSec)
        let transitionEndSec = min(
            currentDurationSec,
            max(request.currentPlayback.elapsedSec + min(durationSec, 2), currentDurationSec - durationSec * 0.5)
        )
        let transitionStartSec = max(request.currentPlayback.elapsedSec, transitionEndSec - durationSec)
        let plan = MixPlan(
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: 0,
            style: .smoothBlend,
            confidence: 0.18,
            reasoningSummary: "Local fallback: emergency tail mix",
            tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil),
            candidateId: "native-emergency-tail",
            currentBarIndex: nil,
            nextBarIndex: nil,
            phraseAlignment: .free,
            energyStrategy: .maintain,
            evidence: [
                "local fallback",
                "emergency tail mix",
                failureReason.map { "planner failure: \($0)" }
            ].compactMap { $0 },
            mixControls: .conservativeDefaults
        )
        return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
    }

    private static func fallbackConfidence(for candidate: MixCandidate) -> Double {
        let cap = candidate.source == .tailFallback ? 0.42 : 0.78
        let floor = candidate.source == .tailFallback ? 0.18 : 0.38
        return min(cap, max(floor, candidate.confidence * 0.92))
    }

    private static func energyStrategy(for energyDelta: Double?) -> EnergyStrategy {
        guard let energyDelta else {
            return .maintain
        }
        if energyDelta > 0.08 {
            return .lift
        }
        if energyDelta < -0.08 {
            return .drop
        }
        return .maintain
    }

    private static func fallbackEvidence(
        candidate: MixCandidate,
        failureReason: String?
    ) -> [String] {
        var evidence = [
            "local fallback",
            "source \(candidate.source.rawValue)",
            "evidence \(candidate.evidenceLevel.rawValue)",
            "phrase \(candidate.phraseAlignment.rawValue)"
        ]
        if let currentBarIndex = candidate.currentBarIndex,
           let nextBarIndex = candidate.nextBarIndex {
            evidence.append("bars \(currentBarIndex) -> \(nextBarIndex)")
        }
        if let bpmDelta = candidate.bpmDelta {
            evidence.append("BPM delta \(String(format: "%.2f", bpmDelta))")
        }
        if let energyDelta = candidate.energyDelta {
            evidence.append(energyDelta >= 0
                ? "energy lift \(String(format: "%.2f", energyDelta))"
                : "energy drop \(String(format: "%.2f", abs(energyDelta)))")
        }
        if let failureReason, !failureReason.isEmpty {
            evidence.append("planner failure: \(failureReason)")
        }
        evidence.append(candidate.reason)
        return Array(evidence.prefix(8))
    }

    private static func fallbackMixControls(candidate: MixCandidate) -> MixControlPlan {
        let incomingTrimDb: Double = switch candidate.style {
        case .hardCut:
            -1
        case .energySwap:
            -1.5
        case .smoothBlend:
            -2
        }
        let outgoingLowDb: Double = switch candidate.energyDelta ?? 0 {
        case let delta where delta > 0.08:
            -2
        default:
            0
        }
        return MixControlPlan(
            gain: MixGainPlan(outgoingTrimDb: 0, incomingTrimDb: incomingTrimDb),
            eq: MixThreeBandEQPlan(
                outgoingLowDb: outgoingLowDb,
                outgoingMidDb: 0,
                outgoingHighDb: 0,
                incomingLowDb: 0,
                incomingMidDb: 0,
                incomingHighDb: 0
            ),
            filter: .conservativeDefaults,
            loudness: .conservativeDefaults,
            clipProtection: .conservativeDefaults,
            qualityNotes: [
                "local fallback mix controls are planning metadata only",
                "native audio engine execution remains unchanged"
            ]
        )
    }
}
