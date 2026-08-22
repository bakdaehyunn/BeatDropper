import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct MixReviewExportTests {
    @Test func markdownIncludesAIAndFallbackDiffNotes() {
        let document = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:00:00Z",
            events: [
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:01:00Z",
                    currentTrackId: "current",
                    currentTrackTitle: "Current Track",
                    nextTrackId: "next",
                    nextTrackTitle: "Next Track",
                    aiPlan: plan(
                        source: "AI planner",
                        transitionStartSec: 100,
                        transitionEndSec: 108,
                        nextTrackStartOffsetSec: 16,
                        style: .smoothBlend,
                        confidence: 0.82,
                        candidateId: "ai-cue",
                        quality: quality(score: 0.86, grade: .pass, peakSummary: "max -4.0 dB")
                    ),
                    fallbackPlan: plan(
                        source: "Local fallback",
                        reason: "shadow_fallback_comparison",
                        transitionStartSec: 104,
                        transitionEndSec: 112,
                        nextTrackStartOffsetSec: 0,
                        style: .hardCut,
                        confidence: 0.44,
                        candidateId: "tail",
                        quality: quality(
                            score: 0.64,
                            grade: .warn,
                            peakSummary: "max -1.0 dB",
                            issues: [
                                RenderedTransitionQualityIssue(
                                    code: .peakJump,
                                    severity: .warning,
                                    message: "Estimated peak jump is 5.0 dB."
                                )
                            ]
                        )
                    )
                )
            ]
        )

        let markdown = MixReviewExportRenderer.markdown(document: document)

        #expect(markdown.contains("# BeatDropper Mix Review Notes"))
        #expect(markdown.contains("Current Track (current) -> Next Track (next)"))
        #expect(markdown.contains("| Field | AI planner | Local fallback | Delta |"))
        #expect(markdown.contains("| Candidate | ai-cue | tail | diff |"))
        #expect(markdown.contains("| Next In | 0:16 | 0:00 | +0:16 |"))
        #expect(markdown.contains("| Quality | PASS 86% | WARN 64% | +22 |"))
        #expect(markdown.contains("| Estimated Peak | max -4.0 dB | max -1.0 dB |"))
        #expect(markdown.contains("warning: peak_jump - Estimated peak jump is 5.0 dB."))
    }

    @Test func markdownHandlesEmptyReviewHistory() {
        let markdown = MixReviewExportRenderer.markdown(
            document: MixReviewExportDocument(generatedAt: "2026-06-17T00:00:00Z", events: [])
        )

        #expect(markdown.contains("No recent mix review events."))
    }

    @Test func jsonRoundTripsAIAndFallbackDiffNotes() throws {
        let document = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:00:00Z",
            events: [
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:01:00Z",
                    currentTrackId: "current",
                    currentTrackTitle: "Current Track",
                    nextTrackId: "next",
                    nextTrackTitle: "Next Track",
                    aiPlan: plan(
                        source: "AI planner",
                        transitionStartSec: 100,
                        transitionEndSec: 108,
                        nextTrackStartOffsetSec: 16,
                        style: .smoothBlend,
                        confidence: 0.82,
                        candidateId: "ai-cue",
                        quality: quality(score: 0.86, grade: .pass, peakSummary: "max -4.0 dB")
                    ),
                    fallbackPlan: plan(
                        source: "Local fallback",
                        reason: "shadow_fallback_comparison",
                        transitionStartSec: 104,
                        transitionEndSec: 112,
                        nextTrackStartOffsetSec: 0,
                        style: .hardCut,
                        confidence: 0.44,
                        candidateId: "tail",
                        quality: quality(score: 0.64, grade: .warn, peakSummary: "max -1.0 dB")
                    )
                )
            ]
        )

        let json = try MixReviewExportRenderer.json(document: document)
        let decoded = try JSONDecoder().decode(MixReviewExportDocument.self, from: Data(json.utf8))

        #expect(json.contains("\"schemaVersion\" : 1"))
        #expect(decoded == document)
        #expect(decoded.events.first?.aiPlan.candidateId == "ai-cue")
        #expect(decoded.events.first?.fallbackPlan?.reason == "shadow_fallback_comparison")
        #expect(decoded.events.first?.fallbackPlan?.style == .hardCut)
    }

    private func plan(
        source: String,
        reason: String? = nil,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        candidateId: String,
        quality: RenderedTransitionQualityReport
    ) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: source,
            reason: reason,
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: nextTrackStartOffsetSec,
            style: style,
            confidence: confidence,
            candidateId: candidateId,
            renderedQuality: quality
        )
    }

    private func quality(
        score: Double,
        grade: RenderedTransitionQualityGrade,
        peakSummary: String,
        issues: [RenderedTransitionQualityIssue] = []
    ) -> RenderedTransitionQualityReport {
        RenderedTransitionQualityReport(
            score: score,
            grade: grade,
            shouldApply: grade != .reject,
            issues: issues,
            metrics: [
                RenderedTransitionQualityMetric(name: "estimated_peak", value: 0.4, score: score, summary: peakSummary),
                RenderedTransitionQualityMetric(name: "peak_jump", value: 2, score: 0.8, summary: "jump 2.0 dB"),
                RenderedTransitionQualityMetric(name: "rms_jump", value: 1, score: 0.9, summary: "jump 1.0 dB"),
                RenderedTransitionQualityMetric(name: "spectral_masking", value: 0.3, score: 0.7, summary: "risk 30%")
            ],
            summary: peakSummary
        )
    }
}
