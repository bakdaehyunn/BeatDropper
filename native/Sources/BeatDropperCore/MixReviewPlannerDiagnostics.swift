import Foundation

public enum MixReviewPlannerDiagnosticVerdict: String, Hashable, Sendable {
    case aiStronger = "ai_stronger"
    case fallbackStronger = "fallback_stronger"
    case mixed = "mixed"
    case equivalent = "equivalent"
    case incompleteEvidence = "incomplete_evidence"
    case missingFallback = "missing_fallback"
}

public enum MixReviewPlannerWeaknessKind: String, Hashable, Sendable {
    case timingWorse = "timing_worse"
    case candidateMismatch = "candidate_mismatch"
    case confidenceWorse = "confidence_worse"
    case qualityWorse = "quality_worse"
    case metricWorse = "metric_worse"
    case missingMetric = "missing_metric"
    case missingFallback = "missing_fallback"
}

public struct MixReviewPlannerDiagnosticFinding: Hashable, Sendable {
    public var kind: MixReviewPlannerWeaknessKind
    public var field: String
    public var summary: String
    public var aiValue: String
    public var fallbackValue: String
    public var delta: String

    public init(
        kind: MixReviewPlannerWeaknessKind,
        field: String,
        summary: String,
        aiValue: String,
        fallbackValue: String,
        delta: String
    ) {
        self.kind = kind
        self.field = field
        self.summary = summary
        self.aiValue = aiValue
        self.fallbackValue = fallbackValue
        self.delta = delta
    }
}

public struct MixReviewPlannerDiagnosticSummary: Hashable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String
    public var verdict: MixReviewPlannerDiagnosticVerdict
    public var findings: [MixReviewPlannerDiagnosticFinding]

    public var weaknessCount: Int {
        findings.filter(\.kind.isPlannerWeakness).count
    }

    public init(
        currentTrackId: String,
        nextTrackId: String,
        verdict: MixReviewPlannerDiagnosticVerdict,
        findings: [MixReviewPlannerDiagnosticFinding]
    ) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
        self.verdict = verdict
        self.findings = findings
    }
}

public enum MixReviewPlannerDiagnostics {
    private static let timingToleranceSec = 1.0
    private static let confidenceTolerance = 0.05
    private static let scoreTolerance = 0.03
    private static let metricNames = ["estimated_peak", "peak_jump", "rms_jump", "spectral_masking"]

    public static func diagnose(event: MixReviewExportEvent) -> MixReviewPlannerDiagnosticSummary {
        diagnose(
            currentTrackId: event.currentTrackId,
            nextTrackId: event.nextTrackId,
            aiPlan: event.aiPlan,
            fallbackPlan: event.fallbackPlan
        )
    }

    public static func diagnose(detail: MixReviewArtifactPairDetail) -> MixReviewPlannerDiagnosticSummary {
        diagnose(
            currentTrackId: detail.currentTrackId,
            nextTrackId: detail.nextTrackId,
            aiPlan: detail.aiPlan,
            fallbackPlan: detail.fallbackPlan
        )
    }

    public static func diagnose(
        currentTrackId: String,
        nextTrackId: String,
        aiPlan: MixReviewExportPlan,
        fallbackPlan: MixReviewExportPlan?
    ) -> MixReviewPlannerDiagnosticSummary {
        guard let fallbackPlan else {
            let finding = MixReviewPlannerDiagnosticFinding(
                kind: .missingFallback,
                field: "Fallback",
                summary: "No local fallback plan is available, so AI planner quality cannot be compared against the baseline.",
                aiValue: sourceLabel(aiPlan),
                fallbackValue: "--",
                delta: "--"
            )
            return MixReviewPlannerDiagnosticSummary(
                currentTrackId: currentTrackId,
                nextTrackId: nextTrackId,
                verdict: .missingFallback,
                findings: [finding]
            )
        }

        let qualityDelta = aiPlan.renderedQuality.score - fallbackPlan.renderedQuality.score
        let fallbackQualityStronger = qualityDelta < -scoreTolerance
        var findings: [MixReviewPlannerDiagnosticFinding] = []

        if fallbackQualityStronger {
            findings.append(MixReviewPlannerDiagnosticFinding(
                kind: .qualityWorse,
                field: "Quality",
                summary: "AI rendered quality scores below local fallback.",
                aiValue: qualityLabel(aiPlan.renderedQuality),
                fallbackValue: qualityLabel(fallbackPlan.renderedQuality),
                delta: pointDelta(qualityDelta)
            ))
        }

        if fallbackQualityStronger && timingDiffers(aiPlan, fallbackPlan) {
            findings.append(MixReviewPlannerDiagnosticFinding(
                kind: .timingWorse,
                field: "Timing",
                summary: "AI timing differs from a stronger fallback plan.",
                aiValue: timingLabel(aiPlan),
                fallbackValue: timingLabel(fallbackPlan),
                delta: timingDeltaLabel(aiPlan, fallbackPlan)
            ))
        }

        if fallbackQualityStronger && aiPlan.candidateId != fallbackPlan.candidateId {
            findings.append(MixReviewPlannerDiagnosticFinding(
                kind: .candidateMismatch,
                field: "Candidate",
                summary: "AI chose a different candidate while fallback rendered stronger.",
                aiValue: aiPlan.candidateId ?? "--",
                fallbackValue: fallbackPlan.candidateId ?? "--",
                delta: "diff"
            ))
        }

        let confidenceDelta = aiPlan.confidence - fallbackPlan.confidence
        if confidenceDelta < -confidenceTolerance {
            findings.append(MixReviewPlannerDiagnosticFinding(
                kind: .confidenceWorse,
                field: "Confidence",
                summary: "AI confidence is materially lower than fallback confidence.",
                aiValue: percent(aiPlan.confidence),
                fallbackValue: percent(fallbackPlan.confidence),
                delta: pointDelta(confidenceDelta)
            ))
        }

        findings += metricFindings(aiPlan: aiPlan, fallbackPlan: fallbackPlan)

        return MixReviewPlannerDiagnosticSummary(
            currentTrackId: currentTrackId,
            nextTrackId: nextTrackId,
            verdict: verdict(aiPlan: aiPlan, fallbackPlan: fallbackPlan, findings: findings),
            findings: findings
        )
    }

    private static func metricFindings(
        aiPlan: MixReviewExportPlan,
        fallbackPlan: MixReviewExportPlan
    ) -> [MixReviewPlannerDiagnosticFinding] {
        metricNames.flatMap { metricName -> [MixReviewPlannerDiagnosticFinding] in
            let aiMetric = metric(aiPlan.renderedQuality, metricName)
            let fallbackMetric = metric(fallbackPlan.renderedQuality, metricName)
            guard let aiMetric, let fallbackMetric else {
                return [MixReviewPlannerDiagnosticFinding(
                    kind: .missingMetric,
                    field: metricName,
                    summary: "Rendered metric is missing from \(aiMetric == nil ? "AI" : "fallback") quality evidence.",
                    aiValue: aiMetric?.summary ?? "--",
                    fallbackValue: fallbackMetric?.summary ?? "--",
                    delta: "--"
                )]
            }

            let delta = aiMetric.score - fallbackMetric.score
            guard delta < -scoreTolerance else {
                return []
            }
            return [MixReviewPlannerDiagnosticFinding(
                kind: .metricWorse,
                field: metricName,
                summary: "AI rendered metric scores below fallback.",
                aiValue: aiMetric.summary,
                fallbackValue: fallbackMetric.summary,
                delta: pointDelta(delta)
            )]
        }
    }

    private static func verdict(
        aiPlan: MixReviewExportPlan,
        fallbackPlan: MixReviewExportPlan,
        findings: [MixReviewPlannerDiagnosticFinding]
    ) -> MixReviewPlannerDiagnosticVerdict {
        let weaknessCount = findings.filter(\.kind.isPlannerWeakness).count
        let hasEvidenceGap = findings.contains { $0.kind == .missingMetric }
        let qualityDelta = aiPlan.renderedQuality.score - fallbackPlan.renderedQuality.score
        if weaknessCount > 0 && qualityDelta < -scoreTolerance {
            return .fallbackStronger
        }
        if weaknessCount > 0 {
            return .mixed
        }
        if hasEvidenceGap {
            return .incompleteEvidence
        }
        if qualityDelta > scoreTolerance {
            return .aiStronger
        }
        return .equivalent
    }

    private static func timingDiffers(_ aiPlan: MixReviewExportPlan, _ fallbackPlan: MixReviewExportPlan) -> Bool {
        abs(aiPlan.transitionStartSec - fallbackPlan.transitionStartSec) > timingToleranceSec ||
            abs(aiPlan.transitionEndSec - fallbackPlan.transitionEndSec) > timingToleranceSec ||
            abs(aiPlan.nextTrackStartOffsetSec - fallbackPlan.nextTrackStartOffsetSec) > timingToleranceSec
    }

    private static func timingLabel(_ plan: MixReviewExportPlan) -> String {
        "\(formatDuration(plan.transitionStartSec)) -> \(formatDuration(plan.transitionEndSec)), next in \(formatDuration(plan.nextTrackStartOffsetSec))"
    }

    private static func timingDeltaLabel(_ aiPlan: MixReviewExportPlan, _ fallbackPlan: MixReviewExportPlan) -> String {
        [
            labeledDurationDelta("start", aiPlan.transitionStartSec - fallbackPlan.transitionStartSec),
            labeledDurationDelta("end", aiPlan.transitionEndSec - fallbackPlan.transitionEndSec),
            labeledDurationDelta("next", aiPlan.nextTrackStartOffsetSec - fallbackPlan.nextTrackStartOffsetSec)
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func labeledDurationDelta(_ label: String, _ seconds: Double) -> String? {
        guard abs(seconds) > timingToleranceSec else {
            return nil
        }
        let sign = seconds >= 0 ? "+" : "-"
        return "\(label) \(sign)\(formatDuration(abs(seconds)))"
    }

    private static func metric(_ report: RenderedTransitionQualityReport, _ name: String) -> RenderedTransitionQualityMetric? {
        report.metrics.first { $0.name == name }
    }

    private static func sourceLabel(_ plan: MixReviewExportPlan) -> String {
        if let reason = plan.reason, !reason.isEmpty {
            return "\(plan.source) (\(reason))"
        }
        return plan.source
    }

    private static func qualityLabel(_ report: RenderedTransitionQualityReport) -> String {
        "\(report.grade.rawValue) \(percent(report.score))"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func pointDelta(_ value: Double) -> String {
        if abs(value) < 0.005 {
            return "same"
        }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }
}

private extension MixReviewPlannerWeaknessKind {
    var isPlannerWeakness: Bool {
        switch self {
        case .timingWorse, .candidateMismatch, .confidenceWorse, .qualityWorse, .metricWorse:
            return true
        case .missingMetric, .missingFallback:
            return false
        }
    }
}
