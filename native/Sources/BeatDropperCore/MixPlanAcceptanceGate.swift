import Foundation

public enum MixPlanAcceptanceSelectedRole: String, Codable, Hashable, Sendable {
    case aiPlanner = "ai_planner"
    case localFallback = "local_fallback"
}

public enum MixPlanAcceptanceReason: String, Codable, Hashable, Sendable {
    case aiAcceptedEquivalent = "ai_accepted_equivalent"
    case aiAcceptedStronger = "ai_accepted_stronger"
    case aiAcceptedIncompleteEvidence = "ai_accepted_incomplete_evidence"
    case aiAcceptedMixedNonCritical = "ai_accepted_mixed_non_critical"
    case aiAcceptedMissingFallback = "ai_accepted_missing_fallback"
    case fallbackAcceptedStronger = "fallback_accepted_stronger"
    case fallbackAcceptedAIQualityReject = "fallback_accepted_ai_quality_reject"
    case fallbackAcceptedMaterialEvidence = "fallback_accepted_material_evidence"
}

public struct MixPlanAcceptanceDecision: Hashable, Sendable {
    public var selectedRole: MixPlanAcceptanceSelectedRole
    public var rejectedRole: MixPlanAcceptanceSelectedRole?
    public var reason: MixPlanAcceptanceReason
    public var diagnostics: MixReviewPlannerDiagnosticSummary

    public init(
        selectedRole: MixPlanAcceptanceSelectedRole,
        rejectedRole: MixPlanAcceptanceSelectedRole?,
        reason: MixPlanAcceptanceReason,
        diagnostics: MixReviewPlannerDiagnosticSummary
    ) {
        self.selectedRole = selectedRole
        self.rejectedRole = rejectedRole
        self.reason = reason
        self.diagnostics = diagnostics
    }
}

public enum MixPlanAcceptanceGate {
    public static func decide(
        currentTrackId: String,
        nextTrackId: String,
        aiPlan: MixReviewExportPlan,
        fallbackPlan: MixReviewExportPlan?
    ) -> MixPlanAcceptanceDecision {
        let diagnostics = MixReviewPlannerDiagnostics.diagnose(
            currentTrackId: currentTrackId,
            nextTrackId: nextTrackId,
            aiPlan: aiPlan,
            fallbackPlan: fallbackPlan
        )

        guard let fallbackPlan else {
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: nil,
                reason: .aiAcceptedMissingFallback,
                diagnostics: diagnostics
            )
        }

        if aiPlan.renderedQuality.grade == .reject,
           fallbackPlan.renderedQuality.shouldApply {
            return decision(
                selectedRole: .localFallback,
                rejectedRole: .aiPlanner,
                reason: .fallbackAcceptedAIQualityReject,
                diagnostics: diagnostics
            )
        }

        switch diagnostics.verdict {
        case .fallbackStronger:
            return decision(
                selectedRole: .localFallback,
                rejectedRole: .aiPlanner,
                reason: .fallbackAcceptedStronger,
                diagnostics: diagnostics
            )
        case .mixed where hasMaterialPlanningWeakness(diagnostics):
            return decision(
                selectedRole: .localFallback,
                rejectedRole: .aiPlanner,
                reason: .fallbackAcceptedMaterialEvidence,
                diagnostics: diagnostics
            )
        case .aiStronger:
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: .localFallback,
                reason: .aiAcceptedStronger,
                diagnostics: diagnostics
            )
        case .incompleteEvidence:
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: .localFallback,
                reason: .aiAcceptedIncompleteEvidence,
                diagnostics: diagnostics
            )
        case .mixed:
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: .localFallback,
                reason: .aiAcceptedMixedNonCritical,
                diagnostics: diagnostics
            )
        case .missingFallback:
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: nil,
                reason: .aiAcceptedMissingFallback,
                diagnostics: diagnostics
            )
        case .equivalent:
            return decision(
                selectedRole: .aiPlanner,
                rejectedRole: .localFallback,
                reason: .aiAcceptedEquivalent,
                diagnostics: diagnostics
            )
        }
    }

    private static func hasMaterialPlanningWeakness(_ diagnostics: MixReviewPlannerDiagnosticSummary) -> Bool {
        diagnostics.findings.contains { finding in
            switch finding.kind {
            case .qualityWorse, .candidateMismatch, .timingWorse:
                return true
            case .confidenceWorse, .metricWorse, .missingMetric, .missingFallback:
                return false
            }
        }
    }

    private static func decision(
        selectedRole: MixPlanAcceptanceSelectedRole,
        rejectedRole: MixPlanAcceptanceSelectedRole?,
        reason: MixPlanAcceptanceReason,
        diagnostics: MixReviewPlannerDiagnosticSummary
    ) -> MixPlanAcceptanceDecision {
        MixPlanAcceptanceDecision(
            selectedRole: selectedRole,
            rejectedRole: rejectedRole,
            reason: reason,
            diagnostics: diagnostics
        )
    }
}
