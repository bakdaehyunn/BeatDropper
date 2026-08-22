import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Testing

struct MixPlanAcceptanceGateTests {
    @Test func acceptsAIWhenDiagnosticsAreEquivalent() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "aligned", score: 0.82),
            fallbackPlan: plan(source: "local-fallback", candidateId: "aligned", score: 0.82)
        )

        #expect(decision.selectedRole == .aiPlanner)
        #expect(decision.rejectedRole == .localFallback)
        #expect(decision.reason == .aiAcceptedEquivalent)
        #expect(decision.diagnostics.verdict == .equivalent)
    }

    @Test func acceptsAIWhenDiagnosticsAreStronger() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "aligned", score: 0.89),
            fallbackPlan: plan(source: "local-fallback", candidateId: "aligned", score: 0.72)
        )

        #expect(decision.selectedRole == .aiPlanner)
        #expect(decision.reason == .aiAcceptedStronger)
        #expect(decision.diagnostics.verdict == .aiStronger)
    }

    @Test func acceptsAIForMixedNonCriticalMetricWeakness() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(
                source: "cli",
                candidateId: "aligned",
                score: 0.75,
                metrics: completeMetrics(score: 0.75, spectralScore: 0.42)
            ),
            fallbackPlan: plan(
                source: "local-fallback",
                candidateId: "aligned",
                score: 0.75,
                metrics: completeMetrics(score: 0.75, spectralScore: 0.85)
            )
        )

        #expect(decision.selectedRole == .aiPlanner)
        #expect(decision.reason == .aiAcceptedMixedNonCritical)
        #expect(decision.diagnostics.verdict == .mixed)
        #expect(decision.diagnostics.findings.contains { $0.kind == .metricWorse })
    }

    @Test func acceptsFallbackWhenAIQualityIsWorse() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "aligned", score: 0.55, grade: .warn),
            fallbackPlan: plan(source: "local-fallback", candidateId: "aligned", score: 0.76, grade: .pass)
        )

        #expect(decision.selectedRole == .localFallback)
        #expect(decision.reason == .fallbackAcceptedStronger)
        #expect(decision.diagnostics.verdict == .fallbackStronger)
        #expect(decision.diagnostics.findings.contains { $0.kind == .qualityWorse })
    }

    @Test func acceptsFallbackForCandidateMismatchWhenFallbackIsStronger() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "tail", score: 0.52, grade: .warn),
            fallbackPlan: plan(source: "local-fallback", candidateId: "analysis", score: 0.81, grade: .pass)
        )

        #expect(decision.selectedRole == .localFallback)
        #expect(decision.diagnostics.verdict == .fallbackStronger)
        #expect(decision.diagnostics.findings.contains { $0.kind == .candidateMismatch })
    }

    @Test func acceptsFallbackWhenAIQualityRejectsAndFallbackIsUsable() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "ai", score: 0.78, grade: .reject, shouldApply: false),
            fallbackPlan: plan(source: "local-fallback", candidateId: "fallback", score: 0.62, grade: .warn, shouldApply: true)
        )

        #expect(decision.selectedRole == .localFallback)
        #expect(decision.reason == .fallbackAcceptedAIQualityReject)
    }

    @Test func missingMetricsDoNotForceFallbackByThemselves() {
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: "current",
            nextTrackId: "next",
            aiPlan: plan(source: "cli", candidateId: "aligned", score: 0.72, metrics: []),
            fallbackPlan: plan(source: "local-fallback", candidateId: "aligned", score: 0.72)
        )

        #expect(decision.selectedRole == .aiPlanner)
        #expect(decision.reason == .aiAcceptedIncompleteEvidence)
        #expect(decision.diagnostics.verdict == .incompleteEvidence)
        #expect(decision.diagnostics.findings.allSatisfy { $0.kind == .missingMetric })
    }

    private func plan(
        source: String,
        candidateId: String,
        score: Double,
        grade: RenderedTransitionQualityGrade = .pass,
        shouldApply: Bool? = nil,
        metrics: [RenderedTransitionQualityMetric]? = nil
    ) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: source,
            transitionStartSec: 100,
            transitionEndSec: 108,
            nextTrackStartOffsetSec: 16,
            style: .smoothBlend,
            confidence: 0.82,
            candidateId: candidateId,
            renderedQuality: quality(
                score: score,
                grade: grade,
                shouldApply: shouldApply ?? (grade != .reject),
                metrics: metrics
            )
        )
    }

    private func quality(
        score: Double,
        grade: RenderedTransitionQualityGrade,
        shouldApply: Bool,
        metrics: [RenderedTransitionQualityMetric]?
    ) -> RenderedTransitionQualityReport {
        RenderedTransitionQualityReport(
            score: score,
            grade: grade,
            shouldApply: shouldApply,
            issues: grade == .reject
                ? [RenderedTransitionQualityIssue(code: .clippingRisk, severity: .critical, message: "reject fixture")]
                : [],
            metrics: metrics ?? completeMetrics(score: score),
            summary: "\(grade.rawValue) \(Int((score * 100).rounded()))%"
        )
    }

    private func completeMetrics(score: Double, spectralScore: Double? = nil) -> [RenderedTransitionQualityMetric] {
        [
            metric("estimated_peak", score: score),
            metric("peak_jump", score: score),
            metric("rms_jump", score: score),
            metric("spectral_masking", score: spectralScore ?? score)
        ]
    }

    private func metric(_ name: String, score: Double) -> RenderedTransitionQualityMetric {
        RenderedTransitionQualityMetric(name: name, value: score, score: score, summary: "\(name) \(score)")
    }
}
